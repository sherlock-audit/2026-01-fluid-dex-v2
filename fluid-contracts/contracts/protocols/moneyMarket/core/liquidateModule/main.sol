// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./helpers.sol";

/// @title FluidMoneyMarketLiquidateModule
/// @notice Implementation module for Money Market liquidation functionality
/// @dev Called via delegatecall from the main FluidMoneyMarket contract.
///      Handles liquidation of unhealthy positions (HF < 1.0) by allowing liquidators to
///      pay back debt and seize collateral with a liquidation penalty.
contract FluidMoneyMarketLiquidateModule is Helpers {

    address internal immutable THIS_ADDRESS;

    /// @dev Ensures function is called via delegatecall, not directly
    modifier _onlyDelegateCall() {
        if (address(this) == THIS_ADDRESS) revert FluidMoneyMarketError(ErrorTypes.LiquidateModule__Unauthorized);
        _;
    }

    /// @notice Initializes the Liquidate Module with Liquidity and DexV2 addresses
    /// @param liquidity_ The FluidLiquidity contract address
    /// @param dexV2_ The FluidDexV2 contract address
    constructor(address liquidity_, address dexV2_) {
        THIS_ADDRESS = address(this);
        LIQUIDITY = IFluidLiquidity(liquidity_);
        DEX_V2 = IFluidDexV2(dexV2_);
    }

    /// @notice Liquidates an unhealthy position by paying back debt and seizing collateral
    /// @dev Position must have HF < 1.0 to be liquidatable. After liquidation, position must remain below HF limit.
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
    ) _onlyDelegateCall external payable returns (bytes memory, bytes memory withdrawData_) {
        if (params_.to == address(0)) params_.to = msg.sender;

        LiquidateVariables memory v_;
        v_.moneyMarketVariables = _moneyMarketVariables;
        v_.oracle = IOracle(address(uint160(v_.moneyMarketVariables))); // The first 160 bits of the token configs are the token address

        {
            HfInfo memory hfInfo_ = _getHfInfo(params_.nftId, IS_LIQUIDATE);
            if (hfInfo_.hf >= EIGHTEEN_DECIMALS) revert FluidMoneyMarketError(ErrorTypes.LiquidateModule__NotLiquidatable);

            if (hfInfo_.collateralValue < hfInfo_.debtValue) {
                v_.maxLiquidationPenalty = 0;
            } else {
                v_.maxLiquidationPenalty = ((hfInfo_.collateralValue - hfInfo_.debtValue) * THREE_DECIMALS) / hfInfo_.debtValue;
                if (v_.maxLiquidationPenalty > 0) v_.maxLiquidationPenalty -= 1; // Explicitly rounding down max LP by 0.1%
            }
        }

        v_.nftConfig = _nftConfigs[params_.nftId];
        v_.emode = v_.nftConfig >> MSL.BITS_NFT_CONFIGS_EMODE & X12;
        v_.numberOfPositions = v_.nftConfig >> MSL.BITS_NFT_CONFIGS_NUMBER_OF_POSITIONS & X10;

        if (
            params_.paybackPositionIndex == 0 || 
            params_.paybackPositionIndex > v_.numberOfPositions || 
            params_.withdrawPositionIndex == 0 || 
            params_.withdrawPositionIndex > v_.numberOfPositions
        ) revert FluidMoneyMarketError(ErrorTypes.LiquidateModule__InvalidParams);

        v_.paybackPositionData = _positionData[params_.nftId][params_.paybackPositionIndex];

        v_.paybackPositionType = (v_.paybackPositionData >> MSL.BITS_POSITION_DATA_POSITION_TYPE) & X5;

        if (v_.paybackPositionType == NORMAL_BORROW_POSITION_TYPE) {
            uint256 paybackAmount_ = abi.decode(params_.paybackData, (uint256));

            uint256 tokenIndex_ = (v_.paybackPositionData >> MSL.BITS_POSITION_DATA_POSITION_TYPE_1_AND_2_TOKEN_INDEX) & X12;
            uint256 tokenConfigs_ = _getTokenConfigs(v_.emode, tokenIndex_);
            address token_ = address(uint160(tokenConfigs_));

            uint256 tokenRawBorrow_;
            uint256 paybackAmountRaw_;
            {
                (, uint256 borrowExchangePrice_) = _getExchangePrices(token_);

                tokenRawBorrow_ = (v_.paybackPositionData >> MSL.BITS_POSITION_DATA_POSITION_TYPE_1_AND_2_TOKEN_RAW_AMOUNT) & X64;
                tokenRawBorrow_ = BM.fromBigNumber(tokenRawBorrow_, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);

                // Check if liquidator wants to pay back all
                if (paybackAmount_ == type(uint256).max) {
                    paybackAmountRaw_ = tokenRawBorrow_;
                    // Calculate the actual payback amount for liquidity layer
                    paybackAmount_ = (((tokenRawBorrow_ * borrowExchangePrice_) + 1) / LC.EXCHANGE_PRICES_PRECISION) + 1; // rounded up so protocol is on the winning side
                } else {
                    // rounded down so protocol is on the winning side
                    paybackAmountRaw_ = ((paybackAmount_ * LC.EXCHANGE_PRICES_PRECISION) - 1) / borrowExchangePrice_;
                    if (paybackAmountRaw_ > 0) paybackAmountRaw_ -= 1;
                }

                _verifyAmountLimits(paybackAmount_);
            }

            {
                // Update ethAmount if native token
                uint256 ethAmount_;
                if (token_ == NATIVE_TOKEN) {
                    ethAmount_ = paybackAmount_;
                    _msgValue -= ethAmount_; // will revert if it goes negative
                }

                {
                    uint256 tokenPrice_ = _getPrice(
                        v_.oracle,
                        token_,
                        tokenConfigs_ >> MSL.BITS_TOKEN_CONFIGS_TOKEN_DECIMALS & X5,
                        v_.emode,
                        IS_LIQUIDATE,
                        IS_DEBT
                    );

                    // rounded down so protocol is on the winning side
                    v_.paybackValue = ((paybackAmount_ * tokenPrice_) - 1) / EIGHTEEN_DECIMALS;
                    if (v_.paybackValue > 0) {
                        v_.paybackValue -= 1;
                    }
                }

                LIQUIDITY.operate{value: ethAmount_}(
                    token_, 
                    0, 
                    -int256(paybackAmount_), 
                    address(0), 
                    address(0), 
                    abi.encode(MONEY_MARKET_IDENTIFIER, LIQUIDATE_NORMAL_PAYBACK_ACTION_IDENTIFIER)
                );
            }

            v_.positionDeleted = _updateStorageForPayback(
                params_.nftId,
                v_.nftConfig,
                params_.paybackPositionIndex, 
                v_.paybackPositionData,
                tokenIndex_,
                tokenRawBorrow_,
                paybackAmountRaw_
            );

            params_.paybackData = abi.encode(paybackAmount_);
        } else if (v_.paybackPositionType == D4_POSITION_TYPE) {
            (
                uint256 paybackAmount0_,
                uint256 paybackAmount1_,
                uint256 paybackAmount0Min_,
                uint256 paybackAmount1Min_
            ) = abi.decode(params_.paybackData, (uint256, uint256, uint256, uint256));

            // Make sure that this is not a fee collection operation
            if (paybackAmount0_ == 0 && paybackAmount1_ == 0) revert FluidMoneyMarketError(ErrorTypes.LiquidateModule__InvalidParams);

            DexKey memory dexKey_;
            StartOperationParams memory s_ =  StartOperationParams({
                isOperate: IS_LIQUIDATE,
                positionType: v_.paybackPositionType,
                nftId: params_.nftId,
                nftConfig: v_.nftConfig,
                token0Index: (v_.paybackPositionData >> MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_TOKEN_0_INDEX) & X12,
                token1Index: (v_.paybackPositionData >> MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_TOKEN_1_INDEX) & X12,
                positionIndex: params_.paybackPositionIndex,
                tickLower: 0,
                tickUpper: 0,
                positionSalt: keccak256(abi.encode(params_.nftId)),
                emode: v_.emode,
                permissionlessTokens: false, // passing permissionless tokens as false because it doesn't matter because its a payback operation
                actionData: abi.encode(-int256(paybackAmount0_), -int256(paybackAmount1_), paybackAmount0Min_, paybackAmount1Min_, address(0))
            });

            (dexKey_, s_.tickLower, s_.tickUpper) = _decodeD3D4PositionData(
                v_.paybackPositionData, 
                _getTokenConfigs(v_.emode, s_.token0Index), 
                _getTokenConfigs(v_.emode, s_.token1Index)
            );

            (v_.positionDeleted, paybackAmount0_, paybackAmount1_) = abi.decode(
                DEX_V2.startOperation(abi.encode(dexKey_, s_)), 
                (bool, uint256, uint256)
            );

            params_.paybackData = abi.encode(paybackAmount0_, paybackAmount1_);

            uint256 token0Price_ = _getPrice(
                v_.oracle,
                dexKey_.token0,
                _getTokenConfigs(v_.emode, s_.token0Index) >> MSL.BITS_TOKEN_CONFIGS_TOKEN_DECIMALS & X5,
                v_.emode,
                IS_LIQUIDATE,
                IS_DEBT
            );
            uint256 token1Price_ = _getPrice(
                v_.oracle,
                dexKey_.token1,
                _getTokenConfigs(v_.emode, s_.token1Index) >> MSL.BITS_TOKEN_CONFIGS_TOKEN_DECIMALS & X5,
                v_.emode,
                IS_LIQUIDATE,
                IS_DEBT
            );

            {
                // rounded down so protocol is on the winning side
                uint256 paybackValue0_;
                if (paybackAmount0_ > 0) {
                    paybackValue0_ = ((paybackAmount0_ * token0Price_) - 1) / EIGHTEEN_DECIMALS;
                    if (paybackValue0_ > 0) paybackValue0_ -= 1;
                }
                uint256 paybackValue1_;
                if (paybackAmount1_ > 0) {
                    paybackValue1_ = ((paybackAmount1_ * token1Price_) - 1) / EIGHTEEN_DECIMALS;
                    if (paybackValue1_ > 0) paybackValue1_ -= 1;
                }

                v_.paybackValue = paybackValue0_ + paybackValue1_;
            }
        } else {
            revert FluidMoneyMarketError(ErrorTypes.LiquidateModule__InvalidParams);
        }
        
        // NOTE: Payback of less than $0.01 i.e. 1 cent is not allowed
        if (v_.paybackValue < 1e16) revert FluidMoneyMarketError(ErrorTypes.LiquidateModule__InvalidParams);

        if (v_.positionDeleted && params_.withdrawPositionIndex == v_.numberOfPositions) {
            // This means that the withdraw position was the last position, and when the payback position got deleted, its position index got changed
            params_.withdrawPositionIndex = params_.paybackPositionIndex;
        }

        v_.withdrawPositionData = _positionData[params_.nftId][params_.withdrawPositionIndex];
        v_.withdrawPositionType = (v_.withdrawPositionData >> MSL.BITS_POSITION_DATA_POSITION_TYPE) & X5;
        v_.withdrawValue = v_.paybackValue;

        if (v_.withdrawPositionType == NORMAL_SUPPLY_POSITION_TYPE) {
            LiquidateNormalWithdrawVariables memory vl_;
            vl_.tokenIndex = (v_.withdrawPositionData >> MSL.BITS_POSITION_DATA_POSITION_TYPE_1_AND_2_TOKEN_INDEX) & X12;

            {
                uint256 supplyExchangePrice_;
                {
                    uint256 tokenConfigs_ = _getTokenConfigs(v_.emode, vl_.tokenIndex);
                    vl_.token = address(uint160(tokenConfigs_));

                    (supplyExchangePrice_, ) = _getExchangePrices(vl_.token);

                    vl_.tokenPrice = _getPrice(
                        v_.oracle, 
                        vl_.token, 
                        tokenConfigs_ >> MSL.BITS_TOKEN_CONFIGS_TOKEN_DECIMALS & X5,
                        v_.emode,
                        IS_LIQUIDATE,
                        IS_COLLATERAL
                    );

                    // Scaling up the withdraw value by the liquidation penalty
                    {
                        uint256 liquidationPenalty_ = (tokenConfigs_ >> MSL.BITS_TOKEN_CONFIGS_LIQUIDATION_PENALTY) & X10;
                        if (liquidationPenalty_ > v_.maxLiquidationPenalty) liquidationPenalty_ = v_.maxLiquidationPenalty;

                        // rounded down so protocol is on the winning side
                        v_.withdrawValue = ((v_.withdrawValue * (THREE_DECIMALS + liquidationPenalty_)) - 1) / THREE_DECIMALS;
                        if (v_.withdrawValue > 0) v_.withdrawValue -= 1;
                    }
                }

                vl_.rawSupplyAmount = (v_.withdrawPositionData >> MSL.BITS_POSITION_DATA_POSITION_TYPE_1_AND_2_TOKEN_RAW_AMOUNT) & X64;
                vl_.rawSupplyAmount = BM.fromBigNumber(vl_.rawSupplyAmount, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);

                {
                    uint256 supplyValue_ = (((vl_.rawSupplyAmount * supplyExchangePrice_) + 1) / LC.EXCHANGE_PRICES_PRECISION) + 1; // rounded up so protocol is on the winning side
                    supplyValue_ = (((supplyValue_ * vl_.tokenPrice) + 1) / EIGHTEEN_DECIMALS) + 1; // rounded up so protocol is on the winning side

                    if (supplyValue_ < v_.withdrawValue) {
                        // If the collateral is not sufficient to cover the debt, then revert
                        revert FluidMoneyMarketError(ErrorTypes.LiquidateModule__InvalidParams);
                    } else {
                        // rounded down so protocol is on the winning side
                        vl_.withdrawAmount = ((v_.withdrawValue * EIGHTEEN_DECIMALS) - 1) / vl_.tokenPrice;
                        if (vl_.withdrawAmount > 0) vl_.withdrawAmount -= 1;
                        vl_.withdrawAmountRaw = (((vl_.withdrawAmount * LC.EXCHANGE_PRICES_PRECISION) + 1) / supplyExchangePrice_) + 1; // rounded up so protocol is on the winning side
                        if (vl_.withdrawAmountRaw > vl_.rawSupplyAmount) vl_.withdrawAmountRaw = vl_.rawSupplyAmount; // added this check for safety
                    }
                }
            }

            _updateStorageForWithdraw(
                params_.nftId, 
                _nftConfigs[params_.nftId], // using directly from storage because payback might have changed it 
                params_.withdrawPositionIndex, 
                v_.withdrawPositionData, 
                vl_.tokenIndex, 
                vl_.rawSupplyAmount, 
                vl_.withdrawAmountRaw
            );

            // Give the withdraw to the user
            LIQUIDITY.operate(vl_.token, -int256(vl_.withdrawAmount), 0, params_.to, address(0), abi.encode(MONEY_MARKET_IDENTIFIER, LIQUIDATE_NORMAL_WITHDRAW_ACTION_IDENTIFIER));

            withdrawData_ = abi.encode(vl_.withdrawAmount);
        } else if (v_.withdrawPositionType == D3_POSITION_TYPE) {
            DexKey memory dexKey_;
            StartOperationParams memory s_ = StartOperationParams({
                isOperate: IS_LIQUIDATE,
                positionType: D3_POSITION_TYPE,
                nftId: params_.nftId,
                nftConfig: _nftConfigs[params_.nftId], // using directly from storage because payback might have changed it
                token0Index: (v_.withdrawPositionData >> MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_TOKEN_0_INDEX) & X12,
                token1Index: (v_.withdrawPositionData >> MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_TOKEN_1_INDEX) & X12,
                positionIndex: params_.withdrawPositionIndex,
                tickLower: 0,
                tickUpper: 0,
                positionSalt: keccak256(abi.encode(params_.nftId)),
                emode: v_.emode,
                permissionlessTokens: false, // passing permissionless tokens as false because it doesn't matter because its a withdraw operation
                actionData: "" // will be set when needed
            });

            LiquidateD3WithdrawVariables memory vl_;

            {
                uint256 token0Configs_ = _getTokenConfigs(v_.emode, s_.token0Index);
                uint256 token1Configs_ = _getTokenConfigs(v_.emode, s_.token1Index);

                (dexKey_, s_.tickLower, s_.tickUpper) = _decodeD3D4PositionData(v_.withdrawPositionData, token0Configs_, token1Configs_);

                vl_.token0Decimals = (token0Configs_ >> MSL.BITS_TOKEN_CONFIGS_TOKEN_DECIMALS) & X5;
                vl_.token1Decimals = (token1Configs_ >> MSL.BITS_TOKEN_CONFIGS_TOKEN_DECIMALS) & X5;

                vl_.token0LiquidationPenalty = (token0Configs_ >> MSL.BITS_TOKEN_CONFIGS_LIQUIDATION_PENALTY) & X10;
                if (vl_.token0LiquidationPenalty > v_.maxLiquidationPenalty) vl_.token0LiquidationPenalty = v_.maxLiquidationPenalty;

                vl_.token1LiquidationPenalty = (token1Configs_ >> MSL.BITS_TOKEN_CONFIGS_LIQUIDATION_PENALTY) & X10;
                if (vl_.token1LiquidationPenalty > v_.maxLiquidationPenalty) vl_.token1LiquidationPenalty = v_.maxLiquidationPenalty;
            }

            {
                uint256 positionFeeStored_ = _positionFeeStored[params_.nftId][keccak256(abi.encode(D3_POSITION_TYPE, dexKey_))][
                    keccak256(abi.encode(address(this), s_.tickLower, s_.tickUpper, s_.positionSalt))];

                vl_.feeAmountToken0 = (positionFeeStored_ >> MSL.BITS_POSITION_FEE_STORED_FEE_STORED_TOKEN_0) & X128;
                vl_.feeAmountToken1 = (positionFeeStored_ >> MSL.BITS_POSITION_FEE_STORED_FEE_STORED_TOKEN_1) & X128;
            }

            {
                (uint256 token0SupplyExchangePrice_, ) = _getExchangePrices(dexKey_.token0);
                (uint256 token1SupplyExchangePrice_, ) = _getExchangePrices(dexKey_.token1);

                uint256 feeAccruedToken0_;
                uint256 feeAccruedToken1_;

                (
                    vl_.token0SupplyAmount, 
                    vl_.token1SupplyAmount, 
                    feeAccruedToken0_, 
                    feeAccruedToken1_
                ) = _getD3SupplyAmounts(
                    _getDexId(dexKey_), 
                    GetD3D4AmountsParams({
                        tickLower: s_.tickLower,
                        tickUpper: s_.tickUpper,
                        positionSalt: s_.positionSalt,
                        token0Decimals: vl_.token0Decimals,
                        token1Decimals: vl_.token1Decimals,
                        token0ExchangePrice: token0SupplyExchangePrice_,
                        token1ExchangePrice: token1SupplyExchangePrice_,
                        sqrtPriceX96: AT_POOL_PRICE
                    })
                );

                vl_.feeAmountToken0 += feeAccruedToken0_;
                vl_.feeAmountToken1 += feeAccruedToken1_;
            }

            vl_.token0Price = _getPrice(
                v_.oracle, 
                dexKey_.token0, 
                vl_.token0Decimals,
                v_.emode,
                IS_LIQUIDATE,
                IS_COLLATERAL
            );
            vl_.token1Price = _getPrice(
                v_.oracle, 
                dexKey_.token1, 
                vl_.token1Decimals,
                v_.emode,
                IS_LIQUIDATE,
                IS_COLLATERAL
            );

            if (!(vl_.token0SupplyAmount == 0 && vl_.token1SupplyAmount == 0)) {
                uint256 supplyValue_;
                uint256 averageLiquidationPenalty_;

                {
                    uint256 supplyValue0_ = (((vl_.token0SupplyAmount * vl_.token0Price) + 1) / EIGHTEEN_DECIMALS) + 1; // rounded up so protocol is on the winning side
                    uint256 supplyValue1_ = (((vl_.token1SupplyAmount * vl_.token1Price) + 1) / EIGHTEEN_DECIMALS) + 1; // rounded up so protocol is on the winning side

                    supplyValue_ = supplyValue0_ + supplyValue1_;
                    averageLiquidationPenalty_ = (
                        (vl_.token0LiquidationPenalty * supplyValue0_) + 
                        (vl_.token1LiquidationPenalty * supplyValue1_)
                    ) / supplyValue_;
                }

                // Scaling up the withdraw value by the average liquidation penalty
                // rounded down so protocol is on the winning side
                v_.withdrawValue = ((v_.withdrawValue * (THREE_DECIMALS + averageLiquidationPenalty_)) - 1) / THREE_DECIMALS;
                if (v_.withdrawValue > 0) v_.withdrawValue -= 1;

                if (supplyValue_ < v_.withdrawValue) {
                    // if one of the amounts is very small that it rounds to 0, then adding 1 here makes sure that the withdraw is actually happening
                    if (vl_.token0SupplyAmount == 0) vl_.token0SupplyAmount = 1;
                    if (vl_.token1SupplyAmount == 0) vl_.token1SupplyAmount = 1;

                    s_.actionData = abi.encode(-int256(vl_.token0SupplyAmount), -int256(vl_.token1SupplyAmount), 0, 0, params_.to);

                    v_.withdrawValue -= supplyValue_;

                    // This withdraw value was scaled up, hence now the remaining portion needs to be scaled down
                    // rounded down so protocol is on the winning side
                    v_.withdrawValue = ((v_.withdrawValue * THREE_DECIMALS) - 1) / (THREE_DECIMALS + averageLiquidationPenalty_);
                    if (v_.withdrawValue > 0) v_.withdrawValue -= 1;
                } else {
                    if (vl_.token0SupplyAmount == 0) {
                        // if one of the amounts is very small that it rounds to 0, then adding 1 here makes sure that the withdraw is actually happening
                        vl_.token0SupplyAmount = 1;
                    } else {
                        // rounded down so protocol is on the winning side
                        vl_.token0SupplyAmount = ((vl_.token0SupplyAmount * v_.withdrawValue) - 1) / supplyValue_;

                        // ensure at least 1 for withdraw
                        if (vl_.token0SupplyAmount > 1) {
                            vl_.token0SupplyAmount -= 1;
                        } else {
                            vl_.token0SupplyAmount = 1;
                        }
                    }

                    if (vl_.token1SupplyAmount == 0) {
                        // if one of the amounts is very small that it rounds to 0, then adding 1 here makes sure that the withdraw is actually happening
                        vl_.token1SupplyAmount = 1;
                    } else {
                        // rounded down so protocol is on the winning side
                        vl_.token1SupplyAmount = ((vl_.token1SupplyAmount * v_.withdrawValue) - 1) / supplyValue_;

                        // ensure at least 1 for withdraw
                        if (vl_.token1SupplyAmount > 1) {
                            vl_.token1SupplyAmount -= 1;
                        } else {
                            vl_.token1SupplyAmount = 1;
                        }
                    }
                    
                    s_.actionData = abi.encode(-int256(vl_.token0SupplyAmount), -int256(vl_.token1SupplyAmount), 0, 0, params_.to);

                    // The entire withdraw value was consumed
                    v_.withdrawValue = 0;
                }

                (, vl_.withdrawAmount0, vl_.withdrawAmount1) = abi.decode(
                    DEX_V2.startOperation(abi.encode(dexKey_, s_)),
                    (bool, uint256, uint256)
                );
            }

            // NOTE: We will process further withdrawal using fee stored only if the withdraw value is greater than $0.01 i.e. 1 cent
            if (v_.withdrawValue > 1e16) {
                if (!(vl_.feeAmountToken0 == 0 && vl_.feeAmountToken1 == 0)) {
                    (vl_.feeAmountToken0, vl_.feeAmountToken1) = _useFeeStoredForLiquidation(
                        vl_.feeAmountToken0,
                        vl_.feeAmountToken1,
                        v_.withdrawValue,
                        vl_.token0Price,
                        vl_.token1Price,
                        vl_.token0LiquidationPenalty,
                        vl_.token1LiquidationPenalty
                    );

                    s_.actionData = abi.encode(0, 0, vl_.feeAmountToken0, vl_.feeAmountToken1, params_.to);
                    DEX_V2.startOperation(abi.encode(dexKey_, s_));

                    vl_.withdrawAmount0 += vl_.feeAmountToken0;
                    vl_.withdrawAmount1 += vl_.feeAmountToken1;
                } else {
                    // Reverting here because withdrawValue_ was non zero, but there is no fee stored to fill it
                    revert FluidMoneyMarketError(ErrorTypes.LiquidateModule__InvalidParams);
                }
            }

            withdrawData_ = abi.encode(vl_.withdrawAmount0, vl_.withdrawAmount1);
        } else if (v_.withdrawPositionType == D4_POSITION_TYPE) {
            DexKey memory dexKey_;
            StartOperationParams memory s_ = StartOperationParams({
                isOperate: IS_LIQUIDATE,
                positionType: D4_POSITION_TYPE,
                nftId: params_.nftId,
                nftConfig: _nftConfigs[params_.nftId], // using directly from storage because payback might have changed it
                token0Index: (v_.withdrawPositionData >> MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_TOKEN_0_INDEX) & X12,
                token1Index: (v_.withdrawPositionData >> MSL.BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_TOKEN_1_INDEX) & X12,
                positionIndex: params_.withdrawPositionIndex,
                tickLower: 0,
                tickUpper: 0,
                positionSalt: keccak256(abi.encode(params_.nftId)),
                emode: v_.emode,
                permissionlessTokens: false, // passing permissionless tokens as false because it doesn't matter because its a fee collection operation
                actionData: "" // will be set when needed
            });

            LiquidateD4WithdrawVariables memory vl_;

            {
                uint256 token0Configs_ = _getTokenConfigs(v_.emode, s_.token0Index);
                uint256 token1Configs_ = _getTokenConfigs(v_.emode, s_.token1Index);

                (dexKey_, s_.tickLower, s_.tickUpper) = _decodeD3D4PositionData(v_.withdrawPositionData, token0Configs_, token1Configs_);

                vl_.token0Decimals = (token0Configs_ >> MSL.BITS_TOKEN_CONFIGS_TOKEN_DECIMALS) & X5;
                vl_.token1Decimals = (token1Configs_ >> MSL.BITS_TOKEN_CONFIGS_TOKEN_DECIMALS) & X5;
                vl_.token0LiquidationPenalty = (token0Configs_ >> MSL.BITS_TOKEN_CONFIGS_LIQUIDATION_PENALTY) & X10;
                if (vl_.token0LiquidationPenalty > v_.maxLiquidationPenalty) vl_.token0LiquidationPenalty = v_.maxLiquidationPenalty;

                vl_.token1LiquidationPenalty = (token1Configs_ >> MSL.BITS_TOKEN_CONFIGS_LIQUIDATION_PENALTY) & X10;
                if (vl_.token1LiquidationPenalty > v_.maxLiquidationPenalty) vl_.token1LiquidationPenalty = v_.maxLiquidationPenalty;
            }

            uint256 feeAmountToken0_;
            uint256 feeAmountToken1_;
            {

                uint256 positionFeeStored_ = _positionFeeStored[params_.nftId][keccak256(abi.encode(D4_POSITION_TYPE, dexKey_))][
                    keccak256(abi.encode(address(this), s_.tickLower, s_.tickUpper, s_.positionSalt))];

                feeAmountToken0_ = (positionFeeStored_ >> MSL.BITS_POSITION_FEE_STORED_FEE_STORED_TOKEN_0) & X128;
                feeAmountToken1_ = (positionFeeStored_ >> MSL.BITS_POSITION_FEE_STORED_FEE_STORED_TOKEN_1) & X128;
            }

            {
                (, uint256 token0BorrowExchangePrice_) = _getExchangePrices(dexKey_.token0);
                (, uint256 token1BorrowExchangePrice_) = _getExchangePrices(dexKey_.token1);

                uint256 feeAccruedToken0_;
                uint256 feeAccruedToken1_;

                (
                    , 
                    , 
                    feeAccruedToken0_, 
                    feeAccruedToken1_
                ) = _getD4DebtAmounts(
                    _getDexId(dexKey_), 
                    GetD3D4AmountsParams({
                        tickLower: s_.tickLower,
                        tickUpper: s_.tickUpper,
                        positionSalt: s_.positionSalt,
                        token0Decimals: vl_.token0Decimals,
                        token1Decimals: vl_.token1Decimals,
                        token0ExchangePrice: token0BorrowExchangePrice_,
                        token1ExchangePrice: token1BorrowExchangePrice_,
                        sqrtPriceX96: AT_POOL_PRICE
                    })
                );

                feeAmountToken0_ += feeAccruedToken0_;
                feeAmountToken1_ += feeAccruedToken1_;
            }

            if (!(feeAmountToken0_ == 0 && feeAmountToken1_ == 0)) {
                {
                    uint256 token0Price_ = _getPrice(
                        v_.oracle, 
                        dexKey_.token0, 
                        vl_.token0Decimals,
                        v_.emode,
                        IS_LIQUIDATE,
                        IS_COLLATERAL
                    );
                    uint256 token1Price_ = _getPrice(
                        v_.oracle, 
                        dexKey_.token1, 
                        vl_.token1Decimals,
                        v_.emode,
                        IS_LIQUIDATE,
                        IS_COLLATERAL
                    );
                    (feeAmountToken0_, feeAmountToken1_) = _useFeeStoredForLiquidation(
                        feeAmountToken0_,
                        feeAmountToken1_,
                        v_.withdrawValue,
                        token0Price_,
                        token1Price_,
                        vl_.token0LiquidationPenalty,
                        vl_.token1LiquidationPenalty
                    );
                }

                s_.actionData = abi.encode(0, 0, feeAmountToken0_, feeAmountToken1_, params_.to);
                DEX_V2.startOperation(abi.encode(dexKey_, s_));

                withdrawData_ = abi.encode(feeAmountToken0_, feeAmountToken1_);
            } else {
                // Reverting here because withdrawValue_ was non zero, but there is no fee stored to fill it
                revert FluidMoneyMarketError(ErrorTypes.LiquidateModule__InvalidParams);
            }
        } else {
            revert FluidMoneyMarketError(ErrorTypes.LiquidateModule__InvalidParams);
        }

        {
            uint256 hfLimit_ = (v_.moneyMarketVariables >> MSL.BITS_MONEY_MARKET_VARIABLES_HF_LIMIT_FOR_LIQUIDATION) & X18;
            hfLimit_ = BM.fromBigNumber(hfLimit_, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);

            if (_getHfInfo(params_.nftId, IS_LIQUIDATE).hf > hfLimit_) revert FluidMoneyMarketError(ErrorTypes.LiquidateModule__HfLimitExceeded);
        }

        if (params_.estimate) {
            revert FluidLiquidateEstimate(params_.paybackData, withdrawData_);
        }

        return (params_.paybackData, withdrawData_);
    }
}