// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./erc721.sol";

abstract contract CallbackHandlers is ERC721 {
    /// @notice Callback from Liquidity layer to transfer tokens from user during supply/payback operations
    /// @dev Only callable by the LIQUIDITY contract. Validates the action identifier before transferring.
    /// @param token_ The token address to transfer
    /// @param amount_ The amount of tokens to transfer
    /// @param data_ Encoded (moneyMarketIdentifier, actionIdentifier) for validation
    function liquidityCallback(address token_, uint amount_, bytes calldata data_) external {
        if (msg.sender != address(LIQUIDITY)) revert FluidMoneyMarketError(ErrorTypes.Base__Unauthorized);
        if (_msgSender == address(0)) revert FluidMoneyMarketError(ErrorTypes.Base__ValidationFailed);

        (
            bytes32 moneyMarketIdentifier_,
            bytes32 actionIdentifier_
        ) = abi.decode(data_, (bytes32, bytes32));

        if (moneyMarketIdentifier_ != MONEY_MARKET_IDENTIFIER) revert FluidMoneyMarketError(ErrorTypes.Base__ValidationFailed);
        if (!(
            actionIdentifier_ == CREATE_NORMAL_SUPPLY_POSITION_ACTION_IDENTIFIER || 
            actionIdentifier_ == CREATE_NORMAL_BORROW_POSITION_ACTION_IDENTIFIER || 
            actionIdentifier_ == NORMAL_SUPPLY_ACTION_IDENTIFIER || 
            actionIdentifier_ == NORMAL_BORROW_ACTION_IDENTIFIER || 
            actionIdentifier_ == NORMAL_WITHDRAW_ACTION_IDENTIFIER ||
            actionIdentifier_ == NORMAL_PAYBACK_ACTION_IDENTIFIER ||
            actionIdentifier_ == LIQUIDATE_NORMAL_PAYBACK_ACTION_IDENTIFIER ||
            actionIdentifier_ == LIQUIDATE_NORMAL_WITHDRAW_ACTION_IDENTIFIER)
        ) revert FluidMoneyMarketError(ErrorTypes.Base__ValidationFailed);

        SafeTransfer.safeTransferFrom(token_, _msgSender, address(LIQUIDITY), amount_);
    }

    /// @notice Callback from DexV2 to transfer tokens from user during DEX operations
    /// @dev Only callable by the DEX_V2 contract. Only allows transfers to LIQUIDITY or DEX_V2.
    /// @param token_ The token address to transfer
    /// @param to_ The destination address (must be LIQUIDITY or DEX_V2)
    /// @param amount_ The amount of tokens to transfer
    function dexCallback(address token_, address to_, uint256 amount_) external {
        if (msg.sender != address(DEX_V2)) revert FluidMoneyMarketError(ErrorTypes.Base__Unauthorized);
        if (_msgSender == address(0)) revert FluidMoneyMarketError(ErrorTypes.Base__ValidationFailed);
        if (!(
            to_ == address(LIQUIDITY) ||
            to_ == address(DEX_V2))
        ) revert FluidMoneyMarketError(ErrorTypes.Base__ValidationFailed);

        SafeTransfer.safeTransferFrom(token_, _msgSender, to_, amount_);
    }

    /// @notice Callback from DexV2 for D3/D4 position operations (deposit/withdraw/borrow/payback)
    /// @dev Delegates execution to the CALLBACK_MODULE_IMPLEMENTATION via delegatecall
    /// @param data_ Encoded callback data containing DexKey and StartOperationParams
    /// @return returnData_ The result from the callback module execution
    function startOperationCallback(bytes calldata data_) external returns (bytes memory returnData_) {
        return abi.decode(_spell(CALLBACK_MODULE_IMPLEMENTATION, msg.data), (bytes));
    }
}

/// @title FluidMoneyMarket
/// @notice Main entry point for Fluid Money Market protocol operations
/// @dev Manages NFT-based positions with support for normal supply/borrow and D3/D4 (smart collateral/debt) positions.
///      Uses delegatecall to route operations to specialized modules (Operate, Liquidate, Admin, Callback).
contract FluidMoneyMarket is CallbackHandlers {
    /// @notice Initializes the Money Market with Liquidity and DexV2 contract addresses
    /// @param liquidity_ The FluidLiquidity contract address for token operations
    /// @param dexV2_ The FluidDexV2 contract address for D3/D4 position operations
    constructor(
        address liquidity_, 
        address dexV2_
    ) {
        LIQUIDITY = IFluidLiquidity(liquidity_);
        DEX_V2 = IFluidDexV2(dexV2_);
    }

    /// @notice Changes the emode for a given NFT position
    /// @param nftId_ The NFT ID to change emode for
    /// @param newEmode_ The new emode to set
    /// @dev Validates that all positions are allowed in the new emode and checks health factor after change
    function changeEmode(uint256 nftId_, uint256 newEmode_) external payable _handleMsgDetails {
        uint256 nftConfig_ = _nftConfigs[nftId_];
        
        // Check that the caller is the owner of the NFT
        if (address(uint160(nftConfig_)) != msg.sender) revert FluidMoneyMarketError(ErrorTypes.Base__Unauthorized);
        
        // Get current emode
        uint256 currentEmode_ = (nftConfig_ >> MSL.BITS_NFT_CONFIGS_EMODE) & X12;
        
        // If the new emode is the same as current, nothing to do
        if (newEmode_ == currentEmode_) revert FluidMoneyMarketError(ErrorTypes.Base__InvalidParams);
        
        // Validate that the new emode is valid (must be less than total emodes)
        uint256 totalEmodes_ = (_moneyMarketVariables >> MSL.BITS_MONEY_MARKET_VARIABLES_TOTAL_EMODES) & X12;
        if (newEmode_ > totalEmodes_) revert FluidMoneyMarketError(ErrorTypes.Base__InvalidParams);
        
        uint256 numberOfPositions_ = (nftConfig_ >> MSL.BITS_NFT_CONFIGS_NUMBER_OF_POSITIONS) & X10;
        
        // Iterate through all positions and check:
        // 1) If collateral side positions, then check that collateral class should not change in new and old emode
        // 2) If debt side position, then check that debt class should not change in new and old emode and validate if the token is allowed as debt in the new emode
        for (uint256 i_ = 1; i_ <= numberOfPositions_; i_++) {
            uint256 positionData_ = _positionData[nftId_][i_];
            uint256 positionType_ = (positionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE) & X5;

            if (positionType_ == NORMAL_SUPPLY_POSITION_TYPE) {
                uint256 tokenIndex_ = (positionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE_1_AND_2_TOKEN_INDEX) & X12;
                if (
                    ((_getTokenConfigs(currentEmode_, tokenIndex_) >> MSL.BITS_TOKEN_CONFIGS_COLLATERAL_CLASS) & X3) != 
                    ((_getTokenConfigs(newEmode_, tokenIndex_) >> MSL.BITS_TOKEN_CONFIGS_COLLATERAL_CLASS) & X3)
                ) {
                    revert FluidMoneyMarketError(ErrorTypes.Base__InvalidParams);
                }
            } else if (positionType_ == NORMAL_BORROW_POSITION_TYPE) {
                // For normal borrow positions, validate the debt token is allowed in the new emode
                uint256 tokenIndex_ = (positionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE_1_AND_2_TOKEN_INDEX) & X12;
                if (
                    ((_getTokenConfigs(currentEmode_, tokenIndex_) >> MSL.BITS_TOKEN_CONFIGS_DEBT_CLASS) & X3) != 
                    ((_getTokenConfigs(newEmode_, tokenIndex_) >> MSL.BITS_TOKEN_CONFIGS_DEBT_CLASS) & X3)
                ) {
                    revert FluidMoneyMarketError(ErrorTypes.Base__InvalidParams);
                }

                _validateDebtForEmode(newEmode_, tokenIndex_);
            } else if (positionType_ == D3_POSITION_TYPE) {
                uint256 token0Index_ = (positionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_TOKEN_0_INDEX) & X12;
                if (
                    ((_getTokenConfigs(currentEmode_, token0Index_) >> MSL.BITS_TOKEN_CONFIGS_COLLATERAL_CLASS) & X3) != 
                    ((_getTokenConfigs(newEmode_, token0Index_) >> MSL.BITS_TOKEN_CONFIGS_COLLATERAL_CLASS) & X3)
                ) {
                    revert FluidMoneyMarketError(ErrorTypes.Base__InvalidParams);
                }

                uint256 token1Index_ = (positionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_TOKEN_1_INDEX) & X12;
                if (
                    ((_getTokenConfigs(currentEmode_, token1Index_) >> MSL.BITS_TOKEN_CONFIGS_COLLATERAL_CLASS) & X3) != 
                    ((_getTokenConfigs(newEmode_, token1Index_) >> MSL.BITS_TOKEN_CONFIGS_COLLATERAL_CLASS) & X3)
                ) {
                    revert FluidMoneyMarketError(ErrorTypes.Base__InvalidParams);
                }
            } else if (positionType_ == D4_POSITION_TYPE) {
                // NOTE: Checking both debt class and collateral class because D4 positions are used as both debt and collateral (fees)
                
                uint256 token0Index_ = (positionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_TOKEN_0_INDEX) & X12;
                if (
                    (
                        ((_getTokenConfigs(currentEmode_, token0Index_) >> MSL.BITS_TOKEN_CONFIGS_DEBT_CLASS) & X3) != 
                        ((_getTokenConfigs(newEmode_, token0Index_) >> MSL.BITS_TOKEN_CONFIGS_DEBT_CLASS) & X3)
                    ) ||
                    (
                        ((_getTokenConfigs(currentEmode_, token0Index_) >> MSL.BITS_TOKEN_CONFIGS_COLLATERAL_CLASS) & X3) != 
                        ((_getTokenConfigs(newEmode_, token0Index_) >> MSL.BITS_TOKEN_CONFIGS_COLLATERAL_CLASS) & X3)
                    )
                ) {
                    revert FluidMoneyMarketError(ErrorTypes.Base__InvalidParams);
                }
                _validateDebtForEmode(newEmode_, token0Index_);

                uint256 token1Index_ = (positionData_ >> MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_TOKEN_1_INDEX) & X12;
                if (
                    (
                        ((_getTokenConfigs(currentEmode_, token1Index_) >> MSL.BITS_TOKEN_CONFIGS_DEBT_CLASS) & X3) != 
                        ((_getTokenConfigs(newEmode_, token1Index_) >> MSL.BITS_TOKEN_CONFIGS_DEBT_CLASS) & X3)
                    ) ||
                    (
                        ((_getTokenConfigs(currentEmode_, token1Index_) >> MSL.BITS_TOKEN_CONFIGS_COLLATERAL_CLASS) & X3) != 
                        ((_getTokenConfigs(newEmode_, token1Index_) >> MSL.BITS_TOKEN_CONFIGS_COLLATERAL_CLASS) & X3)
                    )
                ) {
                    revert FluidMoneyMarketError(ErrorTypes.Base__InvalidParams);
                }
                _validateDebtForEmode(newEmode_, token1Index_);
            } else {
                revert FluidMoneyMarketError(ErrorTypes.Base__InvalidParams);
            }
        }
        
        // Update the emode in the NFT config
        _nftConfigs[nftId_] = (nftConfig_ & ~(X12 << MSL.BITS_NFT_CONFIGS_EMODE)) | (newEmode_ << MSL.BITS_NFT_CONFIGS_EMODE);
        
        // Check health factor with the new emode
        _checkHf(nftId_, IS_OPERATE);
        
        // Emit event
        emit EmodeChanged(nftId_, currentEmode_, newEmode_);
    }

    /// @notice Mints a new Money Market NFT for the current user
    /// @dev Only callable by the contract itself (via operate module delegatecall). 
    ///      The NFT represents a user's position in the money market.
    /// @return nftId_ The ID of the newly minted NFT
    function mint() external returns (uint256 nftId_) {
        // The operate module will do an external call to mint NFTs
        // Hence we check that the caller is the contract itself
        if (msg.sender != address(this)) revert FluidMoneyMarketError(ErrorTypes.Base__Unauthorized);
        if (_msgSender == address(0)) revert FluidMoneyMarketError(ErrorTypes.Base__ValidationFailed);
        
        return _mint(_msgSender, NO_NFT_DATA);
    }

    /// @notice Performs operations on a position including supply, borrow, withdraw, and payback actions
    /// @dev Can handle both creating new positions and modifying existing ones.
    ///      Supports multiple position types: Normal Supply, Normal Borrow, D3 (smart collateral), and D4 (smart debt).
    ///      The function validates health factor after operations that could affect position safety.
    /// @param nftId_ The NFT ID representing the position to operate on. Use type(uint256).max to create a new NFT.
    /// @param positionIndex_ The index of the position within the NFT to modify. Use type(uint256).max to create a new position.
    /// @param actionData_ Encoded action data specifying the operation type and parameters (supply/borrow/withdraw/payback amounts, tokens, etc.)
    /// @return Returns a tuple of (nftId, positionIndex) - the NFT ID and position index after the operation
    function operate(
        uint256 nftId_, 
        uint256 positionIndex_, 
        bytes calldata actionData_
    ) _handleMsgDetails external payable returns (uint256, uint256) {
        return abi.decode(_spell(OPERATE_MODULE_IMPLEMENTATION, msg.data), (uint256, uint256));
    }

    /// @notice Liquidates an unhealthy position by paying back debt and seizing collateral
    /// @dev The position must have a health factor < 1.0 to be liquidatable, and after liquidation must remain below the HF limit
    /// @param params_ LiquidateParams struct containing:
    ///        - nftId: The NFT ID of the position to liquidate
    ///        - paybackPositionIndex: The index of the debt position to pay back
    ///        - withdrawPositionIndex: The index of the collateral position to seize
    ///        - to: The address to receive the seized collateral (defaults to msg.sender if zero)
    ///        - estimate: If true, reverts with FluidLiquidateEstimate error containing paybackData and withdrawData for simulation
    ///        - paybackData: Encoded payback data specific to position type:
    ///            - For NORMAL_BORROW: abi.encode(uint256 paybackAmount)
    ///            - For D4: abi.encode(uint256 token0PaybackAmount, uint256 token1PaybackAmount, uint256 token0PaybackAmountMin, uint256 token1PaybackAmountMin)
    /// @return paybackData_ Encoded payback amounts paid by the liquidator:
    ///        - For NORMAL_BORROW: abi.encode(uint256 paybackAmount)
    ///        - For D4: abi.encode(uint256 token0PaybackAmount, uint256 token1PaybackAmount)
    /// @return withdrawData_ Encoded withdraw amounts sent to the liquidator:
    ///        - For NORMAL_SUPPLY: abi.encode(uint256 withdrawAmount)
    ///        - For D3/D4: abi.encode(uint256 token0Amount, uint256 token1Amount)
    function liquidate(
        LiquidateParams memory params_
    ) _handleMsgDetails external payable returns (bytes memory paybackData_, bytes memory withdrawData_) {
        return abi.decode(_spell(LIQUIDATE_MODULE_IMPLEMENTATION, msg.data), (bytes, bytes));
    }

    /// @notice Gets the health factor and related financial metrics for a money market position
    /// @dev This function calculates the position's health by comparing collateral value to debt
    /// @param nftId_ The NFT ID representing the money market position
    /// @param isOperate_ Whether this call is part of an operation (affects state updates like interest accrual)
    /// @return hfInfo_ The health factor and related financial metrics for the position
    function getHfInfo(
        uint256 nftId_, 
        bool isOperate_
    ) external returns (HfInfo memory hfInfo_) {
        return _getHfInfo(nftId_, isOperate_);
    }

    /// @notice Fallback function that routes admin calls to the AdminModule
    /// @dev Only authorized addresses (governance or auths) can call admin functions
    fallback() external {
        if (_isAuth[msg.sender] == 1 || _getGovernanceAddr() == msg.sender) {
            _spell(ADMIN_MODULE_IMPLEMENTATION, msg.data);
        } else {
            revert FluidMoneyMarketError(ErrorTypes.Base__Unauthorized);
        }
    }

    /// @dev Returns the proxiableUUID for UUPS compatibility
    /// @return The EIP-1967 implementation slot
    function proxiableUUID() external pure returns (bytes32) {
        return IMPLEMENTATION_SLOT;
    }

    /// @notice Reads a uint256 value from a specific storage slot
    /// @param slot_ The storage slot to read from
    /// @return result_ The value stored at the specified slot
    function readFromStorage(bytes32 slot_) public view returns (uint256 result_) {
        assembly {
            result_ := sload(slot_) // read value from the storage slot
        }
    }

    /// @notice Reads a uint256 value from a specific transient storage slot
    /// @param slot_ The transient storage slot to read from
    /// @return result_ The value stored at the specified transient slot
    function readFromTransientStorage(bytes32 slot_) public view returns (uint256 result_) {
        assembly {
            result_ := tload(slot_) // read value from the transient storage slot
        }
    }
}
