// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./events.sol";

// NOTE: @dev I have delibrately not added functions to update collateral class or debt class or liquidation threshold etc. as of now

/// @title FluidMoneyMarketAdminModuleImplementation
/// @notice Admin module for Money Market configuration and management
/// @dev Called via delegatecall from main FluidMoneyMarket contract. Only accessible by governance or authorized addresses.
///      Manages oracle, tokens, emodes, position caps, isolated caps, and protocol upgrades.
contract FluidMoneyMarketAdminModuleImplementation is CommonImport {
    address internal immutable THIS_ADDRESS;

    /// @notice Initializes the Admin Module with Liquidity and DexV2 addresses
    /// @param liquidityAddress_ The FluidLiquidity contract address
    /// @param dexV2Address_ The FluidDexV2 contract address
    constructor(address liquidityAddress_, address dexV2Address_) {
        THIS_ADDRESS = address(this);
        LIQUIDITY = IFluidLiquidity(liquidityAddress_);
        DEX_V2 = IFluidDexV2(dexV2Address_);
    }

    /// @dev Ensures function is called via delegatecall, not directly
    modifier _onlyDelegateCall() {
        if (address(this) == THIS_ADDRESS) {
            revert FluidMoneyMarketError(ErrorTypes.AdminModule__Unauthorized);
        }
        _;
    }

    /// @dev Ensures caller is the governance address
    modifier _onlyGovernance() {
        if (_getGovernanceAddr() != msg.sender) {
            revert FluidMoneyMarketError(ErrorTypes.AdminModule__Unauthorized);
        }
        _;
    }

    /// @notice Updates the auth status for an address
    /// @param auth_ The address to update the auth status for
    /// @param isAuth_ The new auth status
    /// @dev Only callable by authorized addresses
    function updateAuth(address auth_, bool isAuth_) external _onlyDelegateCall _onlyGovernance {
        _isAuth[auth_] = isAuth_ ? 1 : 0;
        emit LogUpdateAuth(auth_, isAuth_);
    }

    /// @dev Internal function to upgrade implementation with UUPS safety checks
    function _authorizeAndUpgrade(address newImplementation_, bytes memory data_) private {
        // Verify new implementation is a contract
        uint256 size_;
        assembly {
            size_ := extcodesize(newImplementation_)
        }
        if (size_ == 0) {
            revert FluidMoneyMarketError(ErrorTypes.AdminModule__UpgradeFailed);
        }

        // UUPS safety check: verify new implementation supports proxiableUUID
        try IERC1822Proxiable(newImplementation_).proxiableUUID() returns (bytes32 slot) {
            if (slot != IMPLEMENTATION_SLOT) {
                revert FluidMoneyMarketError(ErrorTypes.AdminModule__UpgradeFailed);
            }
        } catch {
            revert FluidMoneyMarketError(ErrorTypes.AdminModule__UpgradeFailed);
        }

        // Store new implementation address in EIP-1967 slot
        assembly {
            sstore(IMPLEMENTATION_SLOT, newImplementation_)
        }
        emit LogUpgraded(newImplementation_);

        // Call initialization function if data provided
        if (data_.length > 0) {
            (bool success_, bytes memory returndata_) = newImplementation_.delegatecall(data_);
            if (!success_) {
                if (returndata_.length > 0) {
                    assembly {
                        revert(add(returndata_, 32), mload(returndata_))
                    }
                } else {
                    revert FluidMoneyMarketError(ErrorTypes.AdminModule__UpgradeFailed);
                }
            }
        }
    }

    /// @notice Upgrades the proxy to a new implementation
    /// @param newImplementation_ Address of the new implementation contract
    function upgradeTo(address newImplementation_) external _onlyDelegateCall _onlyGovernance {
        _authorizeAndUpgrade(newImplementation_, "");
    }

    /// @notice Upgrades the proxy to a new implementation and calls a function on it
    /// @param newImplementation_ Address of the new implementation contract
    /// @param data_ Data to pass to the new implementation via delegatecall
    function upgradeToAndCall(address newImplementation_, bytes calldata data_) external payable _onlyDelegateCall _onlyGovernance {
        _authorizeAndUpgrade(newImplementation_, data_);
    }

    /// @notice Updates the oracle address
    /// @param newOracle_ The new oracle address
    /// @dev Only callable by authorized addresses
    function updateOracle(address newOracle_) external _onlyDelegateCall {
        // Validate that the new oracle address is not zero
        if (newOracle_ == address(0)) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        
        // Get the current oracle address (first 160 bits of _moneyMarketVariables)
        address oldOracle_ = address(uint160((_moneyMarketVariables >> MSL.BITS_MONEY_MARKET_VARIABLES_ORACLE_ADDRESS) & X160));
        
        // Update the oracle address in _moneyMarketVariables
        // Clear the first 160 bits and set the new oracle address
        _moneyMarketVariables = (_moneyMarketVariables & ~(X160 << MSL.BITS_MONEY_MARKET_VARIABLES_ORACLE_ADDRESS)) | 
            (uint256(uint160(newOracle_)) << MSL.BITS_MONEY_MARKET_VARIABLES_ORACLE_ADDRESS);
        
        // Emit event
        emit OracleUpdated(oldOracle_, newOracle_);
    }

    /// @notice Updates the max positions per NFT
    /// @param newMaxPositions_ The new max positions per NFT
    /// @dev Only callable by authorized addresses. Max value is 1023 (10 bits)
    function updateMaxPositionsPerNFT(uint256 newMaxPositions_) external _onlyDelegateCall {
        // Validate that the new max positions is within the 10-bit limit
        if (newMaxPositions_ > X10) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        
        // Get the current max positions per NFT (bits 160-169 of _moneyMarketVariables)
        uint256 oldMaxPositions_ = (_moneyMarketVariables >> MSL.BITS_MONEY_MARKET_VARIABLES_MAX_POSITIONS_PER_NFT) & X10;
        
        // Update the max positions per NFT in _moneyMarketVariables
        _moneyMarketVariables = (_moneyMarketVariables & ~(X10 << MSL.BITS_MONEY_MARKET_VARIABLES_MAX_POSITIONS_PER_NFT)) | 
            (newMaxPositions_ << MSL.BITS_MONEY_MARKET_VARIABLES_MAX_POSITIONS_PER_NFT);
        
        // Emit event
        emit MaxPositionsPerNFTUpdated(oldMaxPositions_, newMaxPositions_);
    }

    /// @notice Updates the min normalized collateral value
    /// @param newMinNormalizedCollateralValue_ The new min normalized collateral value in 18 decimals
    /// @dev Only callable by authorized addresses. Value should be in 18 decimals
    function updateMinNormalizedCollateralValue(uint256 newMinNormalizedCollateralValue_) external _onlyDelegateCall {
        // If you want zero then actually pass zero
        if (newMinNormalizedCollateralValue_ != 0 && newMinNormalizedCollateralValue_ < EIGHTEEN_DECIMALS) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        newMinNormalizedCollateralValue_ = newMinNormalizedCollateralValue_ / EIGHTEEN_DECIMALS;
        if (newMinNormalizedCollateralValue_ > X12) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);

        // Get the current min normalized collateral value
        uint256 oldMinNormalizedCollateralValue_ = (_moneyMarketVariables >> MSL.BITS_MONEY_MARKET_VARIABLES_MIN_NORMALIZED_COLLATERAL_VALUE) & X12;
        
        // Update the min normalized collateral value in _moneyMarketVariables
        _moneyMarketVariables = (_moneyMarketVariables & ~(X12 << MSL.BITS_MONEY_MARKET_VARIABLES_MIN_NORMALIZED_COLLATERAL_VALUE)) | 
            (newMinNormalizedCollateralValue_ << MSL.BITS_MONEY_MARKET_VARIABLES_MIN_NORMALIZED_COLLATERAL_VALUE);
        
        // Emit event
        emit MinNormalizedCollateralValueUpdated(oldMinNormalizedCollateralValue_ * EIGHTEEN_DECIMALS, newMinNormalizedCollateralValue_ * EIGHTEEN_DECIMALS);
    }

    /// @notice Updates the HF (Health Factor) limit for liquidation
    /// @param newHfLimit_ The new HF limit in big number format (10|8)
    /// @dev Only callable by authorized addresses.
    function updateHfLimitForLiquidation(uint256 newHfLimit_) external _onlyDelegateCall {
        // Get the current HF limit for liquidation (bits 170-187 of _moneyMarketVariables)
        uint256 oldHfLimit_ = (_moneyMarketVariables >> MSL.BITS_MONEY_MARKET_VARIABLES_HF_LIMIT_FOR_LIQUIDATION) & X18;
        oldHfLimit_ = BM.fromBigNumber(oldHfLimit_, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);
        
        // Update the HF limit for liquidation in _moneyMarketVariables
        _moneyMarketVariables = (_moneyMarketVariables & ~(X18 << MSL.BITS_MONEY_MARKET_VARIABLES_HF_LIMIT_FOR_LIQUIDATION)) | 
            (BM.toBigNumber(newHfLimit_, SMALL_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_UP) << MSL.BITS_MONEY_MARKET_VARIABLES_HF_LIMIT_FOR_LIQUIDATION);
        
        // Emit event
        emit HfLimitForLiquidationUpdated(oldHfLimit_, newHfLimit_);
    }

    /// @notice Lists a new token with its configuration, assigns token index to that token
    /// @param token_ The token address to list
    /// @param collateralClass_ The collateral class (0 = not enabled, 1 = permissioned, 2 = permissionless, 3 = isolated)
    /// @param debtClass_ The debt class (0 = not enabled, 1 = permissioned, 2 = permissionless)
    /// @param collateralFactor_ The collateral factor (e.g., 800 = 0.8 = 80%)
    /// @param liquidationThreshold_ The liquidation threshold (e.g., 900 = 0.9 = 90%)
    /// @param liquidationPenalty_ The liquidation penalty (e.g., 100 = 0.1 = 10%)
    /// @dev Only callable by authorized addresses
    /// @dev Token indices start from 1 (index 0 means token is not listed)
    function listToken(
        address token_,
        uint256 collateralClass_,
        uint256 debtClass_,
        uint256 collateralFactor_,
        uint256 liquidationThreshold_,
        uint256 liquidationPenalty_
    ) external _onlyDelegateCall {
        // Check if token is already listed (index 0 means not listed)
        if (_tokenIndex[token_] != 0) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);

        uint256 tokenDecimals_;
        if (token_ == NATIVE_TOKEN) tokenDecimals_ = NATIVE_TOKEN_DECIMALS;
        else tokenDecimals_ = IERC20WithDecimals(token_).decimals();
        
        // Validate parameters
        if (
            token_ == address(0) ||
            tokenDecimals_ < MIN_TOKEN_DECIMALS || tokenDecimals_ > MAX_TOKEN_DECIMALS ||
            collateralClass_ > 3 ||
            debtClass_ > 2 ||
            collateralFactor_ > THREE_DECIMALS ||
            liquidationThreshold_ > THREE_DECIMALS ||
            liquidationPenalty_ > THREE_DECIMALS ||
            collateralFactor_ >= liquidationThreshold_ || // not allowing == aswell
            ((liquidationThreshold_ * (THREE_DECIMALS + liquidationPenalty_)) / THREE_DECIMALS) > 990 // LP applied at LT should not exceed 99%
        ) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        
        // Get the total number of tokens and assign next index (starting from 1)
        uint256 totalTokens_ = (_moneyMarketVariables >> MSL.BITS_MONEY_MARKET_VARIABLES_TOTAL_TOKENS) & X12;
        uint256 tokenIndex_ = totalTokens_ + 1;
        
        // Validate token index doesn't exceed 12-bit limit
        if (tokenIndex_ >= X12) revert FluidMoneyMarketError(ErrorTypes.AdminModule__CapExceeded);
        
        // Update total tokens count in money market variables
        _moneyMarketVariables = (_moneyMarketVariables & ~(X12 << MSL.BITS_MONEY_MARKET_VARIABLES_TOTAL_TOKENS)) | 
            (tokenIndex_ << MSL.BITS_MONEY_MARKET_VARIABLES_TOTAL_TOKENS);
        
        // Update the token index mapping
        _tokenIndex[token_] = tokenIndex_;
        
        // Store the token configs
        _tokenConfigs[NO_EMODE][tokenIndex_] = 
            (uint256(uint160(token_)) << MSL.BITS_TOKEN_CONFIGS_TOKEN_ADDRESS) |
            (tokenDecimals_ << MSL.BITS_TOKEN_CONFIGS_TOKEN_DECIMALS) |
            (collateralClass_ << MSL.BITS_TOKEN_CONFIGS_COLLATERAL_CLASS) |
            (debtClass_ << MSL.BITS_TOKEN_CONFIGS_DEBT_CLASS) |
            (collateralFactor_ << MSL.BITS_TOKEN_CONFIGS_COLLATERAL_FACTOR) |
            (liquidationThreshold_ << MSL.BITS_TOKEN_CONFIGS_LIQUIDATION_THRESHOLD) |
            (liquidationPenalty_ << MSL.BITS_TOKEN_CONFIGS_LIQUIDATION_PENALTY);
        
        // Emit event
        emit TokenListed(
            token_,
            tokenIndex_,
            tokenDecimals_,
            collateralClass_,
            debtClass_,
            collateralFactor_,
            liquidationThreshold_,
            liquidationPenalty_
        );
    }

    /// @notice Lists a new emode with custom token configurations
    /// @param tokenConfigsList_ Array of token configurations for this emode
    /// @param debtTokens_ Array of token addresses that are allowed as debt in this emode
    /// @dev Only callable by authorized addresses
    /// @dev Emodes are assigned sequentially starting from 1 (0 is reserved for NO_EMODE)
    /// @dev For tokens in tokenConfigsList_, their configs will be different from NO_EMODE configs
    /// @dev For tokens in debtTokens_, they are explicitly allowed as debt for this emode
    function listEmode(
        TokenConfig[] calldata tokenConfigsList_,
        address[] calldata debtTokens_
    ) external _onlyDelegateCall {
        // Get the total number of emodes from money market variables
        uint256 totalEmodes_ = (_moneyMarketVariables >> MSL.BITS_MONEY_MARKET_VARIABLES_TOTAL_EMODES) & X12;

        if (totalEmodes_ == X12) revert FluidMoneyMarketError(ErrorTypes.AdminModule__CapExceeded);
        
        // Assign the next emode (emodes start from 1, 0 is NO_EMODE)
        uint256 emode_ = totalEmodes_ + 1;
        
        // Process token configs list
        for (uint256 i_ = 0; i_ < tokenConfigsList_.length; i_++) {      
            // Validate token is already listed
            uint256 tokenIndex_ = _tokenIndex[tokenConfigsList_[i_].token];
            if (tokenIndex_ == 0) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);

            uint256 tokenDecimals_;
            if (tokenConfigsList_[i_].token == NATIVE_TOKEN) tokenDecimals_ = NATIVE_TOKEN_DECIMALS;
            else tokenDecimals_ = IERC20WithDecimals(tokenConfigsList_[i_].token).decimals();
            
            // Validate parameters
            if (
                tokenDecimals_ < MIN_TOKEN_DECIMALS || tokenDecimals_ > MAX_TOKEN_DECIMALS ||
                tokenConfigsList_[i_].collateralClass > 3 ||
                tokenConfigsList_[i_].debtClass > 2 ||
                tokenConfigsList_[i_].collateralFactor > THREE_DECIMALS ||
                tokenConfigsList_[i_].liquidationThreshold > THREE_DECIMALS ||
                tokenConfigsList_[i_].liquidationPenalty > THREE_DECIMALS ||
                tokenConfigsList_[i_].collateralFactor >= tokenConfigsList_[i_].liquidationThreshold || // not allowing == aswell
                ((tokenConfigsList_[i_].liquidationThreshold * (THREE_DECIMALS + tokenConfigsList_[i_].liquidationPenalty)) / THREE_DECIMALS) > 990 // LP applied at LT should not exceed 99%
            ) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
            
            // Store the token configs for this emode
            _tokenConfigs[emode_][tokenIndex_] = 
                (uint256(uint160(tokenConfigsList_[i_].token)) << MSL.BITS_TOKEN_CONFIGS_TOKEN_ADDRESS) |
                (tokenDecimals_ << MSL.BITS_TOKEN_CONFIGS_TOKEN_DECIMALS) |
                (tokenConfigsList_[i_].collateralClass << MSL.BITS_TOKEN_CONFIGS_COLLATERAL_CLASS) |
                (tokenConfigsList_[i_].debtClass << MSL.BITS_TOKEN_CONFIGS_DEBT_CLASS) |
                (tokenConfigsList_[i_].collateralFactor << MSL.BITS_TOKEN_CONFIGS_COLLATERAL_FACTOR) |
                (tokenConfigsList_[i_].liquidationThreshold << MSL.BITS_TOKEN_CONFIGS_LIQUIDATION_THRESHOLD) |
                (tokenConfigsList_[i_].liquidationPenalty << MSL.BITS_TOKEN_CONFIGS_LIQUIDATION_PENALTY);
            
            if (_tokenConfigs[emode_][tokenIndex_] == _tokenConfigs[NO_EMODE][tokenIndex_]) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
            
            // Set bit in emode map indicating that token configs change for this emode
            // Bit position: ((tokenIndex - 1) * 2) for config change flag
            uint256 parent_ = (tokenIndex_ - 1) / 128;
            uint256 bitPosition_ = ((tokenIndex_ - 1) % 128) * 2;
            
            _emodeMap[emode_][parent_] = _emodeMap[emode_][parent_] | (X1 << bitPosition_);
        }
        
        // Process debt tokens list
        // By default, all bits are 0, which means debt is not allowed
        // We need to set bit = 1 for tokens that ARE allowed as debt in this emode
        // Bit position: ((tokenIndex - 1) * 2 + 1) for debt allowed flag
        // Bit = 0 means debt is NOT allowed (default state)
        // Bit = 1 means debt is allowed
        for (uint256 i_ = 0; i_ < debtTokens_.length; i_++) {
            uint256 tokenIndex_ = _tokenIndex[debtTokens_[i_]];
            if (tokenIndex_ == 0) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
            
            // Set bit to 1 to indicate this token is allowed as debt
            uint256 parent_ = (tokenIndex_ - 1) / 128;
            uint256 bitPosition_ = (((tokenIndex_ - 1) % 128) * 2) + 1;
            
            _emodeMap[emode_][parent_] = _emodeMap[emode_][parent_] | (X1 << bitPosition_);
        }
        
        // Update total emodes count in money market variables
        _moneyMarketVariables = (_moneyMarketVariables & ~(X12 << MSL.BITS_MONEY_MARKET_VARIABLES_TOTAL_EMODES)) | 
            (emode_ << MSL.BITS_MONEY_MARKET_VARIABLES_TOTAL_EMODES);
        
        // Emit event for emode listing
        emit EmodeListed(emode_, tokenConfigsList_, debtTokens_);
    }

    // NOTE: Commenting out the below 2 functions as they can change the liquidation health factor of exisiting positions and hence need to be used carefully

    // /// @notice Adds a custom token configuration to an existing emode
    // /// @param emode_ The emode to add the token config to
    // /// @param config_ The token configuration to add
    // /// @dev Only callable by authorized addresses
    // /// @dev This will store the custom config and set the bit in the emode map
    // function addTokenConfigToEmode(uint256 emode_, TokenConfig calldata config_) external _onlyDelegateCall {
    //     // Validate emode exists
    //     if (emode_ == NO_EMODE) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
    //     uint256 totalEmodes_ = (_moneyMarketVariables >> MSL.BITS_MONEY_MARKET_VARIABLES_TOTAL_EMODES) & X12;
    //     if (emode_ > totalEmodes_) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        
    //     // Validate token is already listed
    //     uint256 tokenIndex_ = _tokenIndex[config_.token];
    //     if (tokenIndex_ == 0) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        
    //     // Check if token config is already set for this emode
    //     // Bit position: ((tokenIndex - 1) * 2) for config change flag
    //     uint256 parent_ = (tokenIndex_ - 1) / 128;
    //     uint256 bitPosition_ = ((tokenIndex_ - 1) % 128) * 2;
    //     if ((_emodeMap[emode_][parent_] >> bitPosition_) & X1 == 1) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);

    //     uint256 tokenDecimals_;
    //     if (config_.token == NATIVE_TOKEN) tokenDecimals_ = NATIVE_TOKEN_DECIMALS;
    //     else tokenDecimals_ = IERC20WithDecimals(config_.token).decimals();
        
    //     // Validate parameters
    //     if (
    //         tokenDecimals_ < MIN_TOKEN_DECIMALS || tokenDecimals_ > MAX_TOKEN_DECIMALS ||
    //         config_.collateralClass > 3 ||
    //         config_.debtClass > 2 ||
    //         config_.collateralFactor > THREE_DECIMALS ||
    //         config_.liquidationThreshold > THREE_DECIMALS ||
    //         config_.liquidationPenalty > THREE_DECIMALS ||
    //         config_.collateralFactor >= config_.liquidationThreshold || // not allowing == aswell
    //         ((config_.liquidationThreshold * (THREE_DECIMALS + config_.liquidationPenalty)) / THREE_DECIMALS) > 990 // LP applied at LT should not exceed 99%
    //     ) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        
    //     // Store the token configs for this emode
    //     _tokenConfigs[emode_][tokenIndex_] = 
    //         (uint256(uint160(config_.token)) << MSL.BITS_TOKEN_CONFIGS_TOKEN_ADDRESS) |
    //         (tokenDecimals_ << MSL.BITS_TOKEN_CONFIGS_TOKEN_DECIMALS) |
    //         (config_.collateralClass << MSL.BITS_TOKEN_CONFIGS_COLLATERAL_CLASS) |
    //         (config_.debtClass << MSL.BITS_TOKEN_CONFIGS_DEBT_CLASS) |
    //         (config_.collateralFactor << MSL.BITS_TOKEN_CONFIGS_COLLATERAL_FACTOR) |
    //         (config_.liquidationThreshold << MSL.BITS_TOKEN_CONFIGS_LIQUIDATION_THRESHOLD) |
    //         (config_.liquidationPenalty << MSL.BITS_TOKEN_CONFIGS_LIQUIDATION_PENALTY);

    //     if (_tokenConfigs[emode_][tokenIndex_] == _tokenConfigs[NO_EMODE][tokenIndex_]) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        
    //     // Set bit in emode map indicating that token configs change for this emode
    //     _emodeMap[emode_][parent_] = _emodeMap[emode_][parent_] | (X1 << bitPosition_);
        
    //     // Emit event
    //     emit TokenConfigAddedToEmode(
    //         emode_,
    //         config_.token,
    //         tokenIndex_,
    //         config_.collateralClass,
    //         config_.debtClass,
    //         config_.collateralFactor,
    //         config_.liquidationThreshold,
    //         config_.liquidationPenalty
    //     );
    // }

    // /// @notice Removes a token configuration from an emode, reverting to NO_EMODE config
    // /// @param emode_ The emode to remove the token config from
    // /// @param token_ The token address to remove
    // /// @dev Only callable by authorized addresses
    // /// @dev This will delete the custom config and unset the bit in the emode map
    // function removeTokenConfigFromEmode(uint256 emode_, address token_) external _onlyDelegateCall {
    //     // Validate emode exists
    //     if (emode_ == NO_EMODE) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
    //     uint256 totalEmodes_ = (_moneyMarketVariables >> MSL.BITS_MONEY_MARKET_VARIABLES_TOTAL_EMODES) & X12;
    //     if (emode_ > totalEmodes_) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        
    //     // Get token index
    //     uint256 tokenIndex_ = _tokenIndex[token_];
    //     if (tokenIndex_ == 0) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        
    //     // Check if token config is set for this emode
    //     // Bit position: ((tokenIndex - 1) * 2) for config change flag
    //     uint256 parent_ = (tokenIndex_ - 1) / 128;
    //     uint256 bitPosition_ = ((tokenIndex_ - 1) % 128) * 2;
    //     if ((_emodeMap[emode_][parent_] >> bitPosition_) & X1 == 0) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        
    //     // Delete the token config for this emode
    //     delete _tokenConfigs[emode_][tokenIndex_];
        
    //     // Clear the bit by using AND with inverted mask
    //     _emodeMap[emode_][parent_] = _emodeMap[emode_][parent_] & ~(X1 << bitPosition_);
        
    //     // Emit event
    //     emit TokenConfigRemovedFromEmode(emode_, token_, tokenIndex_);
    // }

    /// @notice Adds a token to the list of allowed debt tokens in an emode
    /// @param emode_ The emode to add the debt token to
    /// @param token_ The token address to allow as debt
    /// @dev Only callable by authorized addresses
    /// @dev This will set the debt allowed bit in the emode map
    function addDebtToEmode(uint256 emode_, address token_) external _onlyDelegateCall {
        // Validate emode exists
        if (emode_ == NO_EMODE) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        uint256 totalEmodes_ = (_moneyMarketVariables >> MSL.BITS_MONEY_MARKET_VARIABLES_TOTAL_EMODES) & X12;
        if (emode_ > totalEmodes_) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        
        // Get token index
        uint256 tokenIndex_ = _tokenIndex[token_];
        if (tokenIndex_ == 0) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        
        // Check if debt is already allowed for this token in this emode
        // Bit position: ((tokenIndex - 1) * 2 + 1) for debt allowed flag
        uint256 parent_ = (tokenIndex_ - 1) / 128;
        uint256 bitPosition_ = (((tokenIndex_ - 1) % 128) * 2) + 1;
        if ((_emodeMap[emode_][parent_] >> bitPosition_) & X1 == 1) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        
        // Set the bit (bit = 1 means debt allowed)
        _emodeMap[emode_][parent_] = _emodeMap[emode_][parent_] | (X1 << bitPosition_);
        
        // Emit event
        emit DebtAddedToEmode(emode_, token_, tokenIndex_);
    }

    /// @notice Removes a debt token from an emode, making it not allowed as debt
    /// @param emode_ The emode to remove the debt token from
    /// @param token_ The token address to remove from allowed debt
    /// @dev Only callable by authorized addresses
    /// @dev This will unset the debt allowed bit in the emode map
    function removeDebtFromEmode(uint256 emode_, address token_) external _onlyDelegateCall {
        // Validate emode exists
        if (emode_ == NO_EMODE) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        uint256 totalEmodes_ = (_moneyMarketVariables >> MSL.BITS_MONEY_MARKET_VARIABLES_TOTAL_EMODES) & X12;
        if (emode_ > totalEmodes_) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        
        // Get token index
        uint256 tokenIndex_ = _tokenIndex[token_];
        if (tokenIndex_ == 0) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        
        // Check if debt is allowed for this token in this emode
        // Bit position: ((tokenIndex - 1) * 2 + 1) for debt allowed flag
        uint256 parent_ = (tokenIndex_ - 1) / 128;
        uint256 bitPosition_ = (((tokenIndex_ - 1) % 128) * 2) + 1;
        if ((_emodeMap[emode_][parent_] >> bitPosition_) & X1 == 0) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        
        // Clear the bit by using AND with inverted mask (bit = 0 means debt not allowed)
        _emodeMap[emode_][parent_] = _emodeMap[emode_][parent_] & ~(X1 << bitPosition_);
        
        // Emit event
        emit DebtRemovedFromEmode(emode_, token_, tokenIndex_);
    }

    /// @notice Updates the collateral factor for a token in a specific emode or NO_EMODE
    /// @param emode_ The emode to update (0 for NO_EMODE)
    /// @param token_ The token address
    /// @param newCollateralFactor_ The new collateral factor
    /// @dev Only callable by authorized addresses
    /// @dev For non-zero emode, the token config change bit must be set for this emode
    /// @dev Collateral factor must be < liquidation threshold
    function updateCollateralFactor(uint256 emode_, address token_, uint256 newCollateralFactor_) external _onlyDelegateCall {
        // Validate token is listed
        uint256 tokenIndex_ = _tokenIndex[token_];
        if (tokenIndex_ == 0) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        
        // If emode is not NO_EMODE, validate emode exists and token config change bit is set
        if (emode_ != NO_EMODE) {
            uint256 totalEmodes_ = (_moneyMarketVariables >> MSL.BITS_MONEY_MARKET_VARIABLES_TOTAL_EMODES) & X12;
            if (emode_ > totalEmodes_) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
            
            // Check if token config change bit is set for this emode
            uint256 parent_ = (tokenIndex_ - 1) / 128;
            uint256 bitPosition_ = ((tokenIndex_ - 1) % 128) * 2;
            if ((_emodeMap[emode_][parent_] >> bitPosition_) & X1 == 0) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        }
        
        // Validate new collateral factor
        if (newCollateralFactor_ > THREE_DECIMALS) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        
        // Get current token config
        uint256 tokenConfig_ = _tokenConfigs[emode_][tokenIndex_];
        
        // Get liquidation threshold to validate collateral factor
        uint256 liquidationThreshold_ = (tokenConfig_ >> MSL.BITS_TOKEN_CONFIGS_LIQUIDATION_THRESHOLD) & X10;
        if (newCollateralFactor_ >= liquidationThreshold_) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams); // not allowing == aswell
        
        // Get old collateral factor for event
        uint256 oldCollateralFactor_ = (tokenConfig_ >> MSL.BITS_TOKEN_CONFIGS_COLLATERAL_FACTOR) & X10;
        
        // Update the collateral factor
        _tokenConfigs[emode_][tokenIndex_] = (tokenConfig_ & ~(X10 << MSL.BITS_TOKEN_CONFIGS_COLLATERAL_FACTOR)) |
            (newCollateralFactor_ << MSL.BITS_TOKEN_CONFIGS_COLLATERAL_FACTOR);
        
        // If emode is not NO_EMODE, check if the updated config is now identical to NO_EMODE config
        if (emode_ != NO_EMODE) {
            if (_tokenConfigs[emode_][tokenIndex_] == _tokenConfigs[NO_EMODE][tokenIndex_]) {
                // Reverting here so the human gets notified about this and can use removeTokenConfigFromEmode() if needs to remove a token  
                revert FluidMoneyMarketError(ErrorTypes.AdminModule__EmodeConfigIdenticalToNoEmode);
            }
        }
        
        // Emit event
        emit CollateralFactorUpdated(emode_, token_, tokenIndex_, oldCollateralFactor_, newCollateralFactor_);
    }

    /// @notice Updates the liquidation penalty for a token in a specific emode or NO_EMODE
    /// @param emode_ The emode to update (0 for NO_EMODE)
    /// @param token_ The token address
    /// @param newLiquidationPenalty_ The new liquidation penalty
    /// @dev Only callable by authorized addresses
    /// @dev For non-zero emode, the token config change bit must be set for this emode
    function updateLiquidationPenalty(uint256 emode_, address token_, uint256 newLiquidationPenalty_) external _onlyDelegateCall {
        // Validate token is listed
        uint256 tokenIndex_ = _tokenIndex[token_];
        if (tokenIndex_ == 0) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        
        // If emode is not NO_EMODE, validate emode exists and token config change bit is set
        if (emode_ != NO_EMODE) {
            uint256 totalEmodes_ = (_moneyMarketVariables >> MSL.BITS_MONEY_MARKET_VARIABLES_TOTAL_EMODES) & X12;
            if (emode_ > totalEmodes_) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
            
            // Check if token config change bit is set for this emode
            uint256 parent_ = (tokenIndex_ - 1) / 128;
            uint256 bitPosition_ = ((tokenIndex_ - 1) % 128) * 2;
            if ((_emodeMap[emode_][parent_] >> bitPosition_) & X1 == 0) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        }
        
        // Validate new liquidation penalty
        if (newLiquidationPenalty_ > THREE_DECIMALS) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        
        // Get current token config
        uint256 tokenConfig_ = _tokenConfigs[emode_][tokenIndex_];
        
        // Get liquidation threshold to validate LP * LT constraint
        uint256 liquidationThreshold_ = (tokenConfig_ >> MSL.BITS_TOKEN_CONFIGS_LIQUIDATION_THRESHOLD) & X10;
        // LP applied at LT should not exceed 99%
        if (((liquidationThreshold_ * (THREE_DECIMALS + newLiquidationPenalty_)) / THREE_DECIMALS) > 990) 
            revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        
        // Get old liquidation penalty for event
        uint256 oldLiquidationPenalty_ = (tokenConfig_ >> MSL.BITS_TOKEN_CONFIGS_LIQUIDATION_PENALTY) & X10;
        
        // Update the liquidation penalty
        _tokenConfigs[emode_][tokenIndex_] = (tokenConfig_ & ~(X10 << MSL.BITS_TOKEN_CONFIGS_LIQUIDATION_PENALTY)) |
            (newLiquidationPenalty_ << MSL.BITS_TOKEN_CONFIGS_LIQUIDATION_PENALTY);
        
        // If emode is not NO_EMODE, check if the updated config is now identical to NO_EMODE config
        if (emode_ != NO_EMODE) {
            if (_tokenConfigs[emode_][tokenIndex_] == _tokenConfigs[NO_EMODE][tokenIndex_]) {
                // Reverting here so the human gets notified about this and can use removeTokenConfigFromEmode() if needs to remove a token  
                revert FluidMoneyMarketError(ErrorTypes.AdminModule__EmodeConfigIdenticalToNoEmode);
            }
        }
        
        // Emit event
        emit LiquidationPenaltyUpdated(emode_, token_, tokenIndex_, oldLiquidationPenalty_, newLiquidationPenalty_);
    }

    /// @notice Updates the supply cap for a token (position type 1)
    /// @param token_ The token address
    /// @param maxSupplyCap_ The new maximum supply cap (token amount)
    /// @dev Only callable by authorized addresses
    function updateTokenSupplyCap(address token_, uint256 maxSupplyCap_) external _onlyDelegateCall {
        // Validate token is listed
        uint256 tokenIndex_ = _tokenIndex[token_];
        if (tokenIndex_ == 0) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        
        // Calculate position id
        bytes32 positionId_ = keccak256(abi.encode(NORMAL_SUPPLY_POSITION_TYPE, tokenIndex_));
        
        // Get current position cap configs
        uint256 positionCapConfigs_ = _positionCapConfigs[positionId_];
        
        // Get old max supply cap for event
        uint256 oldMaxSupplyCapRaw_ = (positionCapConfigs_ >> MSL.BITS_POSITION_CAP_CONFIGS_TYPE_1_AND_2_MAX_TOTAL_TOKEN_RAW_AMOUNT) & X18;
        oldMaxSupplyCapRaw_ = BM.fromBigNumber(oldMaxSupplyCapRaw_, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);
        
        // Convert token amount to raw adjusted amount using exchange price
        uint256 maxSupplyCapRaw_;
        {
            (uint256 supplyExchangePrice_, ) = _getExchangePrices(token_);
            maxSupplyCapRaw_ = (maxSupplyCap_ * LC.EXCHANGE_PRICES_PRECISION) / supplyExchangePrice_;
        }
        
        // Convert to big number format and update the max supply cap
        _positionCapConfigs[positionId_] = (positionCapConfigs_ & ~(X18 << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_1_AND_2_MAX_TOTAL_TOKEN_RAW_AMOUNT)) |
            (BM.toBigNumber(maxSupplyCapRaw_, SMALL_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_DOWN) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_1_AND_2_MAX_TOTAL_TOKEN_RAW_AMOUNT);
        
        // Emit event
        emit TokenSupplyCapUpdated(token_, tokenIndex_, oldMaxSupplyCapRaw_, maxSupplyCapRaw_);
    }

    /// @notice Updates the debt cap for a token (position type 2)
    /// @param token_ The token address
    /// @param maxDebtCap_ The new maximum debt cap (token amount)
    /// @dev Only callable by authorized addresses
    function updateTokenDebtCap(address token_, uint256 maxDebtCap_) external _onlyDelegateCall {
        // Validate token is listed
        uint256 tokenIndex_ = _tokenIndex[token_];
        if (tokenIndex_ == 0) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        
        // Calculate position id
        bytes32 positionId_ = keccak256(abi.encode(NORMAL_BORROW_POSITION_TYPE, tokenIndex_));
        
        // Get current position cap configs
        uint256 positionCapConfigs_ = _positionCapConfigs[positionId_];
        
        // Get old max debt cap for event
        uint256 oldMaxDebtCapRaw_ = (positionCapConfigs_ >> MSL.BITS_POSITION_CAP_CONFIGS_TYPE_1_AND_2_MAX_TOTAL_TOKEN_RAW_AMOUNT) & X18;
        oldMaxDebtCapRaw_ = BM.fromBigNumber(oldMaxDebtCapRaw_, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);
        
        // Convert token amount to raw adjusted amount using exchange price
        uint256 maxDebtCapRaw_;
        {
            (, uint256 borrowExchangePrice_) = _getExchangePrices(token_);
            maxDebtCapRaw_ = (maxDebtCap_ * LC.EXCHANGE_PRICES_PRECISION) / borrowExchangePrice_;
        }
        
        // Convert to big number format and update the max debt cap
        _positionCapConfigs[positionId_] = (positionCapConfigs_ & ~(X18 << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_1_AND_2_MAX_TOTAL_TOKEN_RAW_AMOUNT)) |
            (BM.toBigNumber(maxDebtCapRaw_, SMALL_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_DOWN) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_1_AND_2_MAX_TOTAL_TOKEN_RAW_AMOUNT);
        
        // Emit event
        emit TokenDebtCapUpdated(token_, tokenIndex_, oldMaxDebtCapRaw_, maxDebtCapRaw_);
    }

    /// @notice Updates the position cap for D3 (smart collateral) positions
    /// @param dexKey_ The dex key identifying the pool
    /// @param minTick_ The minimum tick for allowed positions
    /// @param maxTick_ The maximum tick for allowed positions
    /// @param maxAmount0Cap_ The maximum token0 amount cap
    /// @param maxAmount1Cap_ The maximum token1 amount cap
    /// @dev Only callable by authorized addresses
    function updateD3PositionCap(
        DexKey calldata dexKey_,
        int24 minTick_,
        int24 maxTick_,
        uint256 maxAmount0Cap_,
        uint256 maxAmount1Cap_
    ) external _onlyDelegateCall {
        // Validate parameters
        if (minTick_ >= maxTick_ ||
            minTick_ < MIN_TICK || 
            maxTick_ > MAX_TICK
        ) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        
        // Calculate position id
        bytes32 positionId_ = keccak256(abi.encode(D3_POSITION_TYPE, dexKey_));
        
        UpdatePositionCapVars memory v_;
        
        // Get current position cap configs
        v_.positionCapConfigs = _positionCapConfigs[positionId_];
        
        // If this is a new dex key, add it to the permissioned list
        if (v_.positionCapConfigs == 0) {
            _d3PermissionedDexesList.push(dexKey_);
        }

        // Get current max raw adjusted amounts to preserve them
        v_.currentMaxRawAdjustedAmount0 = (v_.positionCapConfigs >> MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_CURRENT_MAX_RAW_ADJUSTED_AMOUNT_0) & X64;
        v_.currentMaxRawAdjustedAmount1 = (v_.positionCapConfigs >> MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_CURRENT_MAX_RAW_ADJUSTED_AMOUNT_1) & X64;
        
        // Convert token amounts to raw adjusted amounts using exchange prices
        (v_.exchangePrice0, ) = _getExchangePrices(dexKey_.token0);
        (v_.exchangePrice1, ) = _getExchangePrices(dexKey_.token1);
        
        // Get token indices
        v_.token0Index = _tokenIndex[dexKey_.token0];
        v_.token1Index = _tokenIndex[dexKey_.token1];
        
        // Get decimals from token configs
        v_.token0Decimals = (_tokenConfigs[NO_EMODE][v_.token0Index] >> MSL.BITS_TOKEN_CONFIGS_TOKEN_DECIMALS) & X5;
        v_.token1Decimals = (_tokenConfigs[NO_EMODE][v_.token1Index] >> MSL.BITS_TOKEN_CONFIGS_TOKEN_DECIMALS) & X5;
        
        // Calculate precisions
        (v_.token0NumeratorPrecision, v_.token0DenominatorPrecision) = _calculateNumeratorAndDenominatorPrecisions(v_.token0Decimals);
        (v_.token1NumeratorPrecision, v_.token1DenominatorPrecision) = _calculateNumeratorAndDenominatorPrecisions(v_.token1Decimals);
        
        // Convert to raw adjusted amounts
        v_.maxRawAdjustedAmount0Cap = (maxAmount0Cap_ * v_.token0NumeratorPrecision * LC.EXCHANGE_PRICES_PRECISION) / (v_.token0DenominatorPrecision * v_.exchangePrice0);
        v_.maxRawAdjustedAmount1Cap = (maxAmount1Cap_ * v_.token1NumeratorPrecision * LC.EXCHANGE_PRICES_PRECISION) / (v_.token1DenominatorPrecision * v_.exchangePrice1);
        
        // Update the position cap configs
        _positionCapConfigs[positionId_] = 
            ((minTick_ < 0 ? uint256(0) : uint256(1)) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_MIN_TICK_SIGN) |
            ((minTick_ < 0 ? uint256(uint24(-minTick_)) : uint256(uint24(minTick_))) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_ABSOLUTE_MIN_TICK) |
            ((maxTick_ < 0 ? uint256(0) : uint256(1)) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_MAX_TICK_SIGN) |
            ((maxTick_ < 0 ? uint256(uint24(-maxTick_)) : uint256(uint24(maxTick_))) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_ABSOLUTE_MAX_TICK) |
            (BM.toBigNumber(v_.maxRawAdjustedAmount0Cap, SMALL_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_DOWN) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_MAX_RAW_ADJUSTED_AMOUNT_0_CAP) |
            (v_.currentMaxRawAdjustedAmount0 << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_CURRENT_MAX_RAW_ADJUSTED_AMOUNT_0) |
            (BM.toBigNumber(v_.maxRawAdjustedAmount1Cap, SMALL_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_DOWN) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_MAX_RAW_ADJUSTED_AMOUNT_1_CAP) |
            (v_.currentMaxRawAdjustedAmount1 << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_CURRENT_MAX_RAW_ADJUSTED_AMOUNT_1);
        
        // Emit event
        emit D3PositionCapUpdated(dexKey_, minTick_, maxTick_, v_.maxRawAdjustedAmount0Cap, v_.maxRawAdjustedAmount1Cap);
    }

    /// @notice Updates the position cap for D4 (smart debt) positions
    /// @param dexKey_ The dex key identifying the pool
    /// @param minTick_ The minimum tick for allowed positions
    /// @param maxTick_ The maximum tick for allowed positions
    /// @param maxAmount0Cap_ The maximum token0 amount cap
    /// @param maxAmount1Cap_ The maximum token1 amount cap
    /// @dev Only callable by authorized addresses
    function updateD4PositionCap(
        DexKey calldata dexKey_,
        int24 minTick_,
        int24 maxTick_,
        uint256 maxAmount0Cap_,
        uint256 maxAmount1Cap_
    ) external _onlyDelegateCall {
        if (minTick_ >= maxTick_ ||
            minTick_ < MIN_TICK || 
            maxTick_ > MAX_TICK
        ) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        
        // Calculate position id
        bytes32 positionId_ = keccak256(abi.encode(D4_POSITION_TYPE, dexKey_));
        
        UpdatePositionCapVars memory v_;
        
        // Get current position cap configs
        v_.positionCapConfigs = _positionCapConfigs[positionId_];
        
        // If this is a new dex key, add it to the permissioned list
        if (v_.positionCapConfigs == 0) {
            _d4PermissionedDexesList.push(dexKey_);
        }

        // Get current max raw adjusted amounts to preserve them
        v_.currentMaxRawAdjustedAmount0 = (v_.positionCapConfigs >> MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_CURRENT_MAX_RAW_ADJUSTED_AMOUNT_0) & X64;
        v_.currentMaxRawAdjustedAmount1 = (v_.positionCapConfigs >> MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_CURRENT_MAX_RAW_ADJUSTED_AMOUNT_1) & X64;
        
        // Convert token amounts to raw adjusted amounts using exchange prices (use borrow exchange price for D4 debt)
        (, v_.exchangePrice0) = _getExchangePrices(dexKey_.token0);
        (, v_.exchangePrice1) = _getExchangePrices(dexKey_.token1);
        
        // Get token indices
        v_.token0Index = _tokenIndex[dexKey_.token0];
        v_.token1Index = _tokenIndex[dexKey_.token1];
        
        // Get decimals from token configs
        v_.token0Decimals = (_tokenConfigs[NO_EMODE][v_.token0Index] >> MSL.BITS_TOKEN_CONFIGS_TOKEN_DECIMALS) & X5;
        v_.token1Decimals = (_tokenConfigs[NO_EMODE][v_.token1Index] >> MSL.BITS_TOKEN_CONFIGS_TOKEN_DECIMALS) & X5;
        
        // Calculate precisions
        (v_.token0NumeratorPrecision, v_.token0DenominatorPrecision) = _calculateNumeratorAndDenominatorPrecisions(v_.token0Decimals);
        (v_.token1NumeratorPrecision, v_.token1DenominatorPrecision) = _calculateNumeratorAndDenominatorPrecisions(v_.token1Decimals);
        
        // Convert to raw adjusted amounts
        v_.maxRawAdjustedAmount0Cap = (maxAmount0Cap_ * v_.token0NumeratorPrecision * LC.EXCHANGE_PRICES_PRECISION) / (v_.token0DenominatorPrecision * v_.exchangePrice0);
        v_.maxRawAdjustedAmount1Cap = (maxAmount1Cap_ * v_.token1NumeratorPrecision * LC.EXCHANGE_PRICES_PRECISION) / (v_.token1DenominatorPrecision * v_.exchangePrice1);
        
        // Update the position cap configs
        _positionCapConfigs[positionId_] =  
            ((minTick_ < 0 ? uint256(0) : uint256(1)) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_MIN_TICK_SIGN) |
            ((minTick_ < 0 ? uint256(uint24(-minTick_)) : uint256(uint24(minTick_))) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_ABSOLUTE_MIN_TICK) |
            ((maxTick_ < 0 ? uint256(0) : uint256(1)) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_MAX_TICK_SIGN) |
            ((maxTick_ < 0 ? uint256(uint24(-maxTick_)) : uint256(uint24(maxTick_))) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_ABSOLUTE_MAX_TICK) |
            (BM.toBigNumber(v_.maxRawAdjustedAmount0Cap, SMALL_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_DOWN) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_MAX_RAW_ADJUSTED_AMOUNT_0_CAP) |
            (v_.currentMaxRawAdjustedAmount0 << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_CURRENT_MAX_RAW_ADJUSTED_AMOUNT_0) |
            (BM.toBigNumber(v_.maxRawAdjustedAmount1Cap, SMALL_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_DOWN) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_MAX_RAW_ADJUSTED_AMOUNT_1_CAP) |
            (v_.currentMaxRawAdjustedAmount1 << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_CURRENT_MAX_RAW_ADJUSTED_AMOUNT_1);
        
        // Emit event
        emit D4PositionCapUpdated(dexKey_, minTick_, maxTick_, v_.maxRawAdjustedAmount0Cap, v_.maxRawAdjustedAmount1Cap);
    }

    /// @notice Updates the default permissionless dex cap for D3 positions for a specific token pair
    /// @param token0_ The first token address (must be < token1_)
    /// @param token1_ The second token address (must be > token0_)
    /// @param minTick_ The minimum tick for allowed positions
    /// @param maxTick_ The maximum tick for allowed positions
    /// @param maxAmount0Cap_ The maximum token0 amount cap
    /// @param maxAmount1Cap_ The maximum token1 amount cap
    /// @dev Only callable by authorized addresses
    function updateD3DefaultPermissionlessDexCap(
        address token0_,
        address token1_,
        int24 minTick_,
        int24 maxTick_,
        uint256 maxAmount0Cap_,
        uint256 maxAmount1Cap_
    ) external _onlyDelegateCall {
        // Validate token ordering: token0 must be less than token1
        if (token0_ >= token1_) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        
        // Validate tick parameters
        if (minTick_ >= maxTick_ ||
            minTick_ < MIN_TICK || 
            maxTick_ > MAX_TICK
        ) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        
        UpdatePositionCapVars memory v_;
        
        // Convert token amounts to raw adjusted amounts using supply exchange prices
        (v_.exchangePrice0, ) = _getExchangePrices(token0_);
        (v_.exchangePrice1, ) = _getExchangePrices(token1_);
        
        // Get token indices
        v_.token0Index = _tokenIndex[token0_];
        v_.token1Index = _tokenIndex[token1_];
        
        // Get decimals from token configs
        v_.token0Decimals = (_tokenConfigs[NO_EMODE][v_.token0Index] >> MSL.BITS_TOKEN_CONFIGS_TOKEN_DECIMALS) & X5;
        v_.token1Decimals = (_tokenConfigs[NO_EMODE][v_.token1Index] >> MSL.BITS_TOKEN_CONFIGS_TOKEN_DECIMALS) & X5;
        
        // Calculate precisions
        (v_.token0NumeratorPrecision, v_.token0DenominatorPrecision) = _calculateNumeratorAndDenominatorPrecisions(v_.token0Decimals);
        (v_.token1NumeratorPrecision, v_.token1DenominatorPrecision) = _calculateNumeratorAndDenominatorPrecisions(v_.token1Decimals);
        
        // Convert to raw adjusted amounts
        v_.maxRawAdjustedAmount0Cap = (maxAmount0Cap_ * v_.token0NumeratorPrecision * LC.EXCHANGE_PRICES_PRECISION) / (v_.token0DenominatorPrecision * v_.exchangePrice0);
        v_.maxRawAdjustedAmount1Cap = (maxAmount1Cap_ * v_.token1NumeratorPrecision * LC.EXCHANGE_PRICES_PRECISION) / (v_.token1DenominatorPrecision * v_.exchangePrice1);
        
        // Update the default permissionless dex cap configs for D3
        // Note: Current max raw adjusted amounts are left at 0 since this is a default config template
        _defaultPermissionlessDexCapConfigs[D3_DEX_TYPE][token0_][token1_] = 
            ((minTick_ < 0 ? uint256(0) : uint256(1)) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_MIN_TICK_SIGN) |
            ((minTick_ < 0 ? uint256(uint24(-minTick_)) : uint256(uint24(minTick_))) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_ABSOLUTE_MIN_TICK) |
            ((maxTick_ < 0 ? uint256(0) : uint256(1)) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_MAX_TICK_SIGN) |
            ((maxTick_ < 0 ? uint256(uint24(-maxTick_)) : uint256(uint24(maxTick_))) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_ABSOLUTE_MAX_TICK) |
            (BM.toBigNumber(v_.maxRawAdjustedAmount0Cap, SMALL_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_DOWN) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_MAX_RAW_ADJUSTED_AMOUNT_0_CAP) |
            (BM.toBigNumber(v_.maxRawAdjustedAmount1Cap, SMALL_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_DOWN) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_MAX_RAW_ADJUSTED_AMOUNT_1_CAP);
        
        // Emit event
        emit D3DefaultPermissionlessDexCapUpdated(token0_, token1_, minTick_, maxTick_, v_.maxRawAdjustedAmount0Cap, v_.maxRawAdjustedAmount1Cap);
    }

    /// @notice Updates the default permissionless dex cap for D4 positions for a specific token pair
    /// @param token0_ The first token address (must be < token1_)
    /// @param token1_ The second token address (must be > token0_)
    /// @param minTick_ The minimum tick for allowed positions
    /// @param maxTick_ The maximum tick for allowed positions
    /// @param maxAmount0Cap_ The maximum token0 amount cap
    /// @param maxAmount1Cap_ The maximum token1 amount cap
    /// @dev Only callable by authorized addresses
    function updateD4DefaultPermissionlessDexCap(
        address token0_,
        address token1_,
        int24 minTick_,
        int24 maxTick_,
        uint256 maxAmount0Cap_,
        uint256 maxAmount1Cap_
    ) external _onlyDelegateCall {
        // Validate token ordering: token0 must be less than token1
        if (token0_ >= token1_) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        
        // Validate tick parameters
        if (minTick_ >= maxTick_ ||
            minTick_ < MIN_TICK || 
            maxTick_ > MAX_TICK
        ) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        
        UpdatePositionCapVars memory v_;
        
        // Convert token amounts to raw adjusted amounts using borrow exchange prices
        (, v_.exchangePrice0) = _getExchangePrices(token0_);
        (, v_.exchangePrice1) = _getExchangePrices(token1_);
        
        // Get token indices
        v_.token0Index = _tokenIndex[token0_];
        v_.token1Index = _tokenIndex[token1_];
        
        // Get decimals from token configs
        v_.token0Decimals = (_tokenConfigs[NO_EMODE][v_.token0Index] >> MSL.BITS_TOKEN_CONFIGS_TOKEN_DECIMALS) & X5;
        v_.token1Decimals = (_tokenConfigs[NO_EMODE][v_.token1Index] >> MSL.BITS_TOKEN_CONFIGS_TOKEN_DECIMALS) & X5;
        
        // Calculate precisions
        (v_.token0NumeratorPrecision, v_.token0DenominatorPrecision) = _calculateNumeratorAndDenominatorPrecisions(v_.token0Decimals);
        (v_.token1NumeratorPrecision, v_.token1DenominatorPrecision) = _calculateNumeratorAndDenominatorPrecisions(v_.token1Decimals);
        
        // Convert to raw adjusted amounts
        v_.maxRawAdjustedAmount0Cap = (maxAmount0Cap_ * v_.token0NumeratorPrecision * LC.EXCHANGE_PRICES_PRECISION) / (v_.token0DenominatorPrecision * v_.exchangePrice0);
        v_.maxRawAdjustedAmount1Cap = (maxAmount1Cap_ * v_.token1NumeratorPrecision * LC.EXCHANGE_PRICES_PRECISION) / (v_.token1DenominatorPrecision * v_.exchangePrice1);
    
        // Update the default permissionless dex cap configs for D4
        // Note: Current max raw adjusted amounts are left at 0 since this is a default config template
        _defaultPermissionlessDexCapConfigs[D4_DEX_TYPE][token0_][token1_] = 
            ((minTick_ < 0 ? uint256(0) : uint256(1)) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_MIN_TICK_SIGN) |
            ((minTick_ < 0 ? uint256(uint24(-minTick_)) : uint256(uint24(minTick_))) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_ABSOLUTE_MIN_TICK) |
            ((maxTick_ < 0 ? uint256(0) : uint256(1)) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_MAX_TICK_SIGN) |
            ((maxTick_ < 0 ? uint256(uint24(-maxTick_)) : uint256(uint24(maxTick_))) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_ABSOLUTE_MAX_TICK) |
            (BM.toBigNumber(v_.maxRawAdjustedAmount0Cap, SMALL_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_DOWN) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_MAX_RAW_ADJUSTED_AMOUNT_0_CAP) |
            (BM.toBigNumber(v_.maxRawAdjustedAmount1Cap, SMALL_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_DOWN) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_MAX_RAW_ADJUSTED_AMOUNT_1_CAP);
        
        // Emit event
        emit D4DefaultPermissionlessDexCapUpdated(token0_, token1_, minTick_, maxTick_, v_.maxRawAdjustedAmount0Cap, v_.maxRawAdjustedAmount1Cap);
    }

    /// @notice Updates the global default permissionless dex cap for D3 positions
    /// @param minTick_ The minimum tick for allowed positions
    /// @param maxTick_ The maximum tick for allowed positions
    /// @param maxRawAdjustedAmount0Cap_ The maximum raw adjusted token0 amount cap
    /// @param maxRawAdjustedAmount1Cap_ The maximum raw adjusted token1 amount cap
    /// @dev Only callable by authorized addresses
    /// @dev Raw adjusted amounts should be provided directly (no conversion is done)
    function updateD3GlobalDefaultPermissionlessDexCap(
        int24 minTick_,
        int24 maxTick_,
        uint256 maxRawAdjustedAmount0Cap_,
        uint256 maxRawAdjustedAmount1Cap_
    ) external _onlyDelegateCall {
        // Validate tick parameters
        if (minTick_ >= maxTick_ ||
            minTick_ < MIN_TICK || 
            maxTick_ > MAX_TICK
        ) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        
        // Build new global default permissionless dex cap configs
        // Note: Current max raw adjusted amounts are left at 0 since this is a default config template
        uint256 newGlobalDefaultConfigs_ = 
            ((minTick_ < 0 ? uint256(0) : uint256(1)) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_MIN_TICK_SIGN) |
            ((minTick_ < 0 ? uint256(uint24(-minTick_)) : uint256(uint24(minTick_))) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_ABSOLUTE_MIN_TICK) |
            ((maxTick_ < 0 ? uint256(0) : uint256(1)) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_MAX_TICK_SIGN) |
            ((maxTick_ < 0 ? uint256(uint24(-maxTick_)) : uint256(uint24(maxTick_))) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_ABSOLUTE_MAX_TICK) |
            (BM.toBigNumber(maxRawAdjustedAmount0Cap_, SMALL_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_DOWN) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_MAX_RAW_ADJUSTED_AMOUNT_0_CAP) |
            (BM.toBigNumber(maxRawAdjustedAmount1Cap_, SMALL_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_DOWN) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_MAX_RAW_ADJUSTED_AMOUNT_1_CAP);
        
        // Update the global default permissionless dex cap configs for D3
        _globalDefaultPermissionlessDexCapConfigs[D3_DEX_TYPE] = newGlobalDefaultConfigs_;
        
        // Emit event
        emit D3GlobalDefaultPermissionlessDexCapUpdated(minTick_, maxTick_, maxRawAdjustedAmount0Cap_, maxRawAdjustedAmount1Cap_);
    }

    /// @notice Updates the global default permissionless dex cap for D4 positions
    /// @param minTick_ The minimum tick for allowed positions
    /// @param maxTick_ The maximum tick for allowed positions
    /// @param maxRawAdjustedAmount0Cap_ The maximum raw adjusted token0 amount cap
    /// @param maxRawAdjustedAmount1Cap_ The maximum raw adjusted token1 amount cap
    /// @dev Only callable by authorized addresses
    /// @dev Raw adjusted amounts should be provided directly (no conversion is done)
    function updateD4GlobalDefaultPermissionlessDexCap(
        int24 minTick_,
        int24 maxTick_,
        uint256 maxRawAdjustedAmount0Cap_,
        uint256 maxRawAdjustedAmount1Cap_
    ) external _onlyDelegateCall {
        // Validate tick parameters
        if (minTick_ >= maxTick_ ||
            minTick_ < MIN_TICK || 
            maxTick_ > MAX_TICK
        ) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        
        // Build new global default permissionless dex cap configs
        // Note: Current max raw adjusted amounts are left at 0 since this is a default config template
        uint256 newGlobalDefaultConfigs_ = 
            ((minTick_ < 0 ? uint256(0) : uint256(1)) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_MIN_TICK_SIGN) |
            ((minTick_ < 0 ? uint256(uint24(-minTick_)) : uint256(uint24(minTick_))) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_ABSOLUTE_MIN_TICK) |
            ((maxTick_ < 0 ? uint256(0) : uint256(1)) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_MAX_TICK_SIGN) |
            ((maxTick_ < 0 ? uint256(uint24(-maxTick_)) : uint256(uint24(maxTick_))) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_ABSOLUTE_MAX_TICK) |
            (BM.toBigNumber(maxRawAdjustedAmount0Cap_, SMALL_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_DOWN) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_MAX_RAW_ADJUSTED_AMOUNT_0_CAP) |
            (BM.toBigNumber(maxRawAdjustedAmount1Cap_, SMALL_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_DOWN) << MSL.BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_MAX_RAW_ADJUSTED_AMOUNT_1_CAP);
        
        // Update the global default permissionless dex cap configs for D4
        _globalDefaultPermissionlessDexCapConfigs[D4_DEX_TYPE] = newGlobalDefaultConfigs_;
        
        // Emit event
        emit D4GlobalDefaultPermissionlessDexCapUpdated(minTick_, maxTick_, maxRawAdjustedAmount0Cap_, maxRawAdjustedAmount1Cap_);
    }

    /// @notice Updates the isolated cap for a specific isolated collateral and debt token pair
    /// @param isolatedToken_ The isolated collateral token address
    /// @param debtToken_ The debt token address
    /// @param newMaxDebtCapRaw_ The new maximum debt cap (raw token amount)
    /// @dev Only callable by authorized addresses
    function updateIsolatedCap(
        address isolatedToken_,
        address debtToken_,
        uint256 newMaxDebtCapRaw_
    ) external _onlyDelegateCall {
        // Validate isolated token is listed
        uint256 isolatedTokenIndex_ = _tokenIndex[isolatedToken_];
        if (isolatedTokenIndex_ == 0) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);

        // NOTE: Not checking here if the token is isolated or not as the token might be isolated in one emode and not the other
        
        // Validate debt token is listed
        uint256 debtTokenIndex_ = _tokenIndex[debtToken_];
        if (debtTokenIndex_ == 0) revert FluidMoneyMarketError(ErrorTypes.AdminModule__InvalidParams);
        
        // Get current isolated cap configs
        uint256 isolatedCapConfigs_ = _isolatedCapConfigs[isolatedTokenIndex_][debtTokenIndex_];
        
        // If this is a new isolated cap (cap config was 0), add debt token to the whitelist
        if (isolatedCapConfigs_ == 0) {
            _isolatedTokenToWhitelistedDebtTokens[isolatedToken_].push(debtToken_);
        }
        
        // Get current total token raw borrow to preserve it
        uint256 currentTotalTokenRawBorrow_ = (isolatedCapConfigs_ >> MSL.BITS_ISOLATED_CAP_CONFIGS_TOTAL_TOKEN_RAW_BORROW) & X64;
        
        // Build new isolated cap configs
        // Max debt cap is stored in big number format (10|8)
        // Current total borrow is preserved as-is
        uint256 newIsolatedCapConfigs_ = 
            (BM.toBigNumber(newMaxDebtCapRaw_, SMALL_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_DOWN) << MSL.BITS_ISOLATED_CAP_CONFIGS_MAX_TOTAL_TOKEN_RAW_BORROW) |
            (currentTotalTokenRawBorrow_ << MSL.BITS_ISOLATED_CAP_CONFIGS_TOTAL_TOKEN_RAW_BORROW);
        
        // Update the isolated cap configs
        _isolatedCapConfigs[isolatedTokenIndex_][debtTokenIndex_] = newIsolatedCapConfigs_;
        
        // Emit event
        emit IsolatedCapUpdated(isolatedToken_, isolatedTokenIndex_, debtToken_, debtTokenIndex_, newMaxDebtCapRaw_);
    }
}