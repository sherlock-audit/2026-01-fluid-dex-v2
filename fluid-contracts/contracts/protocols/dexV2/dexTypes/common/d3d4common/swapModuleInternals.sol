// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./userModuleInternals.sol";

abstract contract CommonSwapModuleInternals is CommonUserModuleInternals {
    /// @dev Swap tokens with perfect amount in
    function _swapIn(SwapInInternalParams memory params_) internal returns (uint256 amountOutRaw_, uint256 protocolFeeAccruedRaw_, uint256 lpFeeAccruedRaw_) {
        // NOTE: Non zero active liquidity check is not needed because even if there is no liquidity at the current tick current price doesn't have liquidity, doesn't mean that there is no liquidity somewhere else
        // if (activeLiquidity_ == 0) revert InsufficientLiquidity();

        // This is checked before calling this internal function
        // if (params_.amountInRaw == 0) revert ZeroAmountIn();

        SwapInInternalVariables memory v_;
        DynamicFeeVariables memory d_;

        v_.dexVariablesStart = params_.dexVariables;

        uint256 sqrtPriceX96_ = (params_.dexVariables >> DSL.BITS_DEX_V2_VARIABLES_CURRENT_SQRT_PRICE) & X72;
        unchecked {
            // sqrtPriceX96 is always rounded down when it is stored
            // Which means that if its a 1 to 0 swap (increasing price swap), the swapper might get a slightly better price
            // Hence we add 1 to round it up while fetching so protocol always remains on the winning side
            uint256 coefficient_ = (sqrtPriceX96_ >> DEFAULT_EXPONENT_SIZE);
            uint256 exponent_ = (sqrtPriceX96_ & DEFAULT_EXPONENT_MASK);
            if (exponent_ > 0 && !params_.swap0To1) coefficient_ += 1;
            sqrtPriceX96_ = coefficient_ << exponent_;
        }
        v_.sqrtPriceStartX96 = sqrtPriceX96_;

        uint256 activeLiquidity_ = (params_.dexVariables2 >> DSL.BITS_DEX_V2_VARIABLES2_ACTIVE_LIQUIDITY) & X102;
        v_.activeLiquidityStart = activeLiquidity_;

        int256 currentTick_;
        unchecked {
            currentTick_ = int256((params_.dexVariables >> DSL.BITS_DEX_V2_VARIABLES_ABSOLUTE_CURRENT_TICK) & X19);
            if ((params_.dexVariables >> DSL.BITS_DEX_V2_VARIABLES_CURRENT_TICK_SIGN) & X1 == 0) currentTick_ = -int256(currentTick_);
        }

        v_.protocolFee = params_.swap0To1 ? 
            (params_.dexVariables2 >> DSL.BITS_DEX_V2_VARIABLES2_PROTOCOL_FEE_0_TO_1) & X12 : 
            (params_.dexVariables2 >> DSL.BITS_DEX_V2_VARIABLES2_PROTOCOL_FEE_1_TO_0) & X12;

        v_.protocolCutFee = (params_.dexVariables2 >> DSL.BITS_DEX_V2_VARIABLES2_PROTOCOL_CUT_FEE) & X6;

        {
            uint256 temp_;

            temp_ = (params_.dexVariables >> DSL.BITS_DEX_V2_VARIABLES_FEE_GROWTH_GLOBAL_0_X102) & X82;
            v_.feeGrowthGlobal0X102 = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);
            
            temp_= (params_.dexVariables >> DSL.BITS_DEX_V2_VARIABLES_FEE_GROWTH_GLOBAL_1_X102) & X82;
            v_.feeGrowthGlobal1X102 = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);
        }

        v_.feeVersion = (params_.dexVariables2 >> DSL.BITS_DEX_V2_VARIABLES2_FEE_VERSION) & X4;

        // If fee version is 1, we always sync the dynamic fee variables because even if constant fee is used, the dynamic fee variables need to be updated
        if (v_.feeVersion == 1) {
            (d_, params_.dexVariables2) = _calculateDynamicFeeVariables(sqrtPriceX96_, params_.swap0To1, params_.dexVariables2);
        }
        
        {  
            uint256 fetchedDynamicFee_;
            bool overrideDynamicFee_;

            // If fetchDynamicFeeFlag is ON, we always fetch the dynamic fee unless the controller is the swapper
            // This is called after syncing the dynamic fee variables so it gets synced fee variables
            if (((params_.dexVariables2 >> DSL.BITS_DEX_V2_VARIABLES2_FETCH_DYNAMIC_FEE_FLAG) & X1 == 1) && params_.dexKey.controller != msg.sender) {
                // Use low-level call with gas limit to prevent controller from blocking swaps
                // Gas limit of 200K is sufficient for any reasonable fee calculation
                (bool success_, bytes memory returnData_) = params_.dexKey.controller.call{gas: 200000}(
                    abi.encodeWithSelector(IController.fetchDynamicFeeForSwapIn.selector, params_)
                );
                // Only use the result if call succeeded and returned exactly 64 bytes (uint256 + bool)
                if (success_ && returnData_.length == 64) {
                    (fetchedDynamicFee_, overrideDynamicFee_) = abi.decode(returnData_, (uint256, bool));
                    if (fetchedDynamicFee_ > X16) {
                        overrideDynamicFee_ = false;
                    }
                }
                // On failure or wrong return data size, use default values (fetchedDynamicFee_ = 0, overrideDynamicFee_ = false)
            }

            if (overrideDynamicFee_) {
                v_.isConstantLpFee = true;
                v_.constantLpFee = fetchedDynamicFee_;
            } else if (v_.feeVersion == 0) {
                v_.isConstantLpFee = true;
                v_.constantLpFee = (params_.dexVariables2 >> DSL.BITS_DEX_V2_VARIABLES2_LP_FEE) & X16;
            } else if (v_.feeVersion == 1 && d_.priceImpactToFeeDivisionFactor == 0) {
                v_.isConstantLpFee = true;
                v_.constantLpFee = d_.minFee;
            }
        }

        uint256 amountInRemainingRaw_ = params_.amountInRaw;

        while (amountInRemainingRaw_ > 0) {
            v_.sqrtPriceStepStartX96 = sqrtPriceX96_;

            // Find next initialized tick using bitmap
            (v_.nextTick, v_.initialized) = _nextInitializedTickWithinOneWord(
                params_.dexType,
                params_.dexId,
                int24(currentTick_),
                params_.dexKey.tickSpacing,
                params_.swap0To1
            );

            if (v_.nextTick < MIN_TICK || v_.nextTick > MAX_TICK) {
                revert FluidDexV2D3D4Error(ErrorTypes.SwapModule__NextTickOutOfBounds);
            }

            // Calculate price limit for this step
            uint256 sqrtPriceNextX96_ = TM.getSqrtRatioAtTick(int24(v_.nextTick));

            // 1. If its swap 0 to 1, that means price is decreasing, but if next price is greater than current price, that means because of our rounding of sqrt price this anomaly occured, hence we need to correct it
            // 2. If its swap 1 to 0, that means price is increasing, but if next price is less than current price, that means because of our rounding of sqrt price this anomaly occured, hence we need to correct it
            if ((params_.swap0To1 && sqrtPriceNextX96_ > sqrtPriceX96_) || (!params_.swap0To1 && sqrtPriceNextX96_ < sqrtPriceX96_))  {
                // Verify deviation is not greater than 0.01%
                uint256 diff_ = params_.swap0To1 ? sqrtPriceNextX96_ - sqrtPriceX96_ : sqrtPriceX96_ - sqrtPriceNextX96_;
                if (diff_ * FOUR_DECIMALS > sqrtPriceX96_) {
                    revert FluidDexV2D3D4Error(ErrorTypes.SwapModule__SqrtPriceDeviationTooHigh);
                }
                sqrtPriceX96_ = sqrtPriceNextX96_;
            }

            {
                uint256 stepLpFeeRaw_;
                {
                    // Calculate swap step
                    uint256 stepAmountInRaw_;
                    uint256 stepAmountOutRaw_;
                    uint256 stepProtocolFeeRaw_;
                    
                    if (v_.isConstantLpFee) {
                        (sqrtPriceX96_, stepAmountInRaw_, stepAmountOutRaw_) = _computeSwapStepForSwapInWithoutFee(
                            sqrtPriceX96_,
                            sqrtPriceNextX96_,
                            activeLiquidity_,
                            amountInRemainingRaw_
                        );

                        unchecked {
                            // added this check for safety because we are using unchecked, this should ideally never happen though
                            if (stepAmountOutRaw_ > X86) {
                                revert FluidDexV2D3D4Error(ErrorTypes.SwapModule__StepAmountOutOverflow);
                            }
                            if (stepAmountOutRaw_ > 0 && v_.protocolFee > 0) {
                                stepProtocolFeeRaw_ = (((stepAmountOutRaw_ * v_.protocolFee) + 1) / SIX_DECIMALS) + 1;
                            }
                            stepAmountOutRaw_ = stepAmountOutRaw_ > stepProtocolFeeRaw_ ? stepAmountOutRaw_ - stepProtocolFeeRaw_ : 0;

                            if (stepAmountOutRaw_ > 0 && v_.constantLpFee > 0) {
                                stepLpFeeRaw_ = (((stepAmountOutRaw_ * v_.constantLpFee) + 1) / SIX_DECIMALS) + 1;
                            }
                            stepAmountOutRaw_ = stepAmountOutRaw_ > stepLpFeeRaw_ ? stepAmountOutRaw_ - stepLpFeeRaw_ : 0;
                        }
                    } else {
                        (sqrtPriceX96_, stepAmountInRaw_, stepAmountOutRaw_, stepProtocolFeeRaw_, stepLpFeeRaw_) = _computeSwapStepForSwapInWithDynamicFee(
                            ComputeSwapStepForSwapInWithDynamicFeeParams({
                                // doesnt matter what we pass as swap0To1 here because we anyway generate it later because passing the actual here causes stack too deep error
                                // and we need to pass something because this variable has to be in this struct otherwise there is stack too deep in the function we are calling
                                swap0To1: IS_0_TO_1_SWAP,
                                sqrtPriceCurrentX96: sqrtPriceX96_,
                                sqrtPriceTargetX96: sqrtPriceNextX96_,
                                liquidity: activeLiquidity_,
                                amountInRemaining: amountInRemainingRaw_,
                                protocolFee: v_.protocolFee,
                                dynamicFeeVariables: d_
                            })
                        );
                    }

                    unchecked {
                        // Taking protocol cut from lp fee and adding it to protocol fee
                        uint256 stepProtocolCutFeeRaw_;
                        if (stepLpFeeRaw_ > 0 && v_.protocolCutFee > 0) {
                            stepProtocolCutFeeRaw_ = (((stepLpFeeRaw_ * v_.protocolCutFee) + 1) / TWO_DECIMALS) + 1;
                        }

                        if (stepProtocolCutFeeRaw_ > 0) {
                            if (stepLpFeeRaw_ > stepProtocolCutFeeRaw_) {
                                stepProtocolFeeRaw_ += stepProtocolCutFeeRaw_;
                                stepLpFeeRaw_ -= stepProtocolCutFeeRaw_;
                            } else {
                                stepProtocolFeeRaw_ += stepLpFeeRaw_;
                                stepLpFeeRaw_ = 0;
                            }
                        }

                        // Update running totals
                        amountInRemainingRaw_ -= stepAmountInRaw_;
                        amountOutRaw_ += stepAmountOutRaw_;

                        // account for fees
                        protocolFeeAccruedRaw_ += stepProtocolFeeRaw_;
                        lpFeeAccruedRaw_ += stepLpFeeRaw_;
                    }
                }

                // Update global fee tracker
                if (activeLiquidity_ > 0) {
                    /// @dev Fee is cut from tokenOut in swap in
                    unchecked {
                        if (params_.swap0To1) v_.feeGrowthGlobal1X102 += (((stepLpFeeRaw_ * params_.token1ExchangePrice) 
                            / LC.EXCHANGE_PRICES_PRECISION) << 102) / activeLiquidity_;
                        else v_.feeGrowthGlobal0X102 += (((stepLpFeeRaw_ * params_.token0ExchangePrice) 
                            / LC.EXCHANGE_PRICES_PRECISION) << 102) / activeLiquidity_;
                    }
                }
            }
            

            // If we've reached the next price target
            if (sqrtPriceX96_ == sqrtPriceNextX96_) {
                if (v_.initialized) {
                    TickData memory tickData_ = _tickData[params_.dexType][params_.dexId][v_.nextTick];

                    {
                        // NOTE: Converting to big number and then converting back to normal number so that the precision lost later when storing big number in dex variables doesnt cause any issues
                        uint256 feeGrowthGlobal0X102_ = BM.toBigNumber(v_.feeGrowthGlobal0X102, BIG_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_DOWN);
                        uint256 feeGrowthGlobal1X102_ = BM.toBigNumber(v_.feeGrowthGlobal1X102, BIG_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_DOWN);

                        feeGrowthGlobal0X102_ = (feeGrowthGlobal0X102_ >> DEFAULT_EXPONENT_SIZE) << (feeGrowthGlobal0X102_ & DEFAULT_EXPONENT_MASK);
                        feeGrowthGlobal1X102_ = (feeGrowthGlobal1X102_ >> DEFAULT_EXPONENT_SIZE) << (feeGrowthGlobal1X102_ & DEFAULT_EXPONENT_MASK);

                        // Calculate new fee growth outside values
                        tickData_.feeGrowthOutside0X102 = feeGrowthGlobal0X102_ - tickData_.feeGrowthOutside0X102;
                        tickData_.feeGrowthOutside1X102 = feeGrowthGlobal1X102_ - tickData_.feeGrowthOutside1X102;
                    }

                    // Update Active Liquidity
                    unchecked {
                        // This can't go negative, but keeping the check in place for safety
                        int256 newActiveLiquidity_ = int256(activeLiquidity_) + (params_.swap0To1 ? -tickData_.liquidityNet : tickData_.liquidityNet);
                        // This will ideally never go negative, but adding the check for extra security
                        if (newActiveLiquidity_ < 0) {
                            revert FluidDexV2D3D4Error(ErrorTypes.SwapModule__ActiveLiquidityUnderflow);
                        }
                        activeLiquidity_ = uint256(newActiveLiquidity_);
                    }

                    // If active liquidity was zero when we started, then the sqrtPriceStartX96 will be recorded when liquidity becomes non zero for the first time
                    // Added this so pool price can move from no liquidity regions without any price change constraints until liquidity is found
                    if (v_.activeLiquidityStart == 0 && !v_.sqrtPriceStartX96Changed && activeLiquidity_ > 0) {
                        v_.sqrtPriceStartX96 = sqrtPriceX96_;
                        v_.sqrtPriceStartX96Changed = true;
                    }

                    _tickData[params_.dexType][params_.dexId][v_.nextTick] = tickData_;
                }

                // The tick got crossed, update current tick accordingly
                unchecked {
                    currentTick_ = params_.swap0To1 ? v_.nextTick - 1 : v_.nextTick;
                }
            } else if (sqrtPriceX96_ != v_.sqrtPriceStepStartX96) {
                // If price did change but didn't reach target, recalculate tick
                // this also means that amountInRemainingRaw_ has become zero, hence there will be no more loop iterations
                currentTick_ = TM.getTickAtSqrtRatio(uint160(sqrtPriceX96_));
            }
        }

        _verifySqrtPriceX96ChangeLimits(v_.sqrtPriceStartX96, sqrtPriceX96_);

        if (v_.feeVersion == 1) {
            unchecked {
                uint256 priceEndX96_ = FM.mulDiv(sqrtPriceX96_, sqrtPriceX96_, Q96);

                bool isPositivePriceDiff_ = priceEndX96_ > d_.zeroPriceImpactPriceX96;
                uint256 priceDiffX96_ = isPositivePriceDiff_ ? priceEndX96_ - d_.zeroPriceImpactPriceX96
                    : d_.zeroPriceImpactPriceX96 - priceEndX96_;
                uint256 finalAbsolutePriceImpact_ = (priceDiffX96_ * SIX_DECIMALS) / d_.zeroPriceImpactPriceX96;
                if (finalAbsolutePriceImpact_ >= SIX_DECIMALS) {
                    revert FluidDexV2D3D4Error(ErrorTypes.SwapModule__PriceImpactTooHigh);
                }

                int256 finalNetPriceImpact_ = isPositivePriceDiff_ ? int256(finalAbsolutePriceImpact_) : -int256(finalAbsolutePriceImpact_);
            
                params_.dexVariables2 = _updateDynamicFeeVariables(params_.dexVariables2, finalNetPriceImpact_);
            }
        }

        if (params_.dexVariables2 >> DSL.BITS_DEX_V2_VARIABLES2_POOL_ACCOUNTING_FLAG & X1 == 0) {
            uint256 tokenReserves_ = _tokenReserves[params_.dexType][params_.dexId];
            uint256 token0Reserves_ = (tokenReserves_ >> DSL.BITS_DEX_V2_TOKEN_RESERVES_TOKEN_0_RESERVES) & X128;
            uint256 token1Reserves_ = (tokenReserves_ >> DSL.BITS_DEX_V2_TOKEN_RESERVES_TOKEN_1_RESERVES) & X128;
            if (params_.swap0To1) {
                token0Reserves_ += params_.amountInRaw;
                token1Reserves_ -= amountOutRaw_;

                if (token0Reserves_ > X128) {
                    revert FluidDexV2D3D4Error(ErrorTypes.SwapModule__TokenReservesOverflow);
                }
            } else {
                token0Reserves_ -= amountOutRaw_;
                token1Reserves_ += params_.amountInRaw;

                if (token1Reserves_ > X128) {
                    revert FluidDexV2D3D4Error(ErrorTypes.SwapModule__TokenReservesOverflow);
                }
            }

            _tokenReserves[params_.dexType][params_.dexId] = (token0Reserves_ << DSL.BITS_DEX_V2_TOKEN_RESERVES_TOKEN_0_RESERVES) | 
                (token1Reserves_ << DSL.BITS_DEX_V2_TOKEN_RESERVES_TOKEN_1_RESERVES);
        }

        unchecked {
            // Dex variables will always have to be updated because the price will always change
            params_.dexVariables = (uint256(currentTick_ < 0 ? 0 : 1) << DSL.BITS_DEX_V2_VARIABLES_CURRENT_TICK_SIGN) |
                (uint256(currentTick_ < 0 ? -currentTick_ : currentTick_) << DSL.BITS_DEX_V2_VARIABLES_ABSOLUTE_CURRENT_TICK) |
                (BM.toBigNumber(sqrtPriceX96_, SMALL_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_DOWN) << DSL.BITS_DEX_V2_VARIABLES_CURRENT_SQRT_PRICE) |
                (BM.toBigNumber(v_.feeGrowthGlobal0X102, BIG_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_DOWN) << DSL.BITS_DEX_V2_VARIABLES_FEE_GROWTH_GLOBAL_0_X102) |
                (BM.toBigNumber(v_.feeGrowthGlobal1X102, BIG_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_DOWN) << DSL.BITS_DEX_V2_VARIABLES_FEE_GROWTH_GLOBAL_1_X102);
        }

        if (v_.dexVariablesStart == params_.dexVariables) {
            revert FluidDexV2D3D4Error(ErrorTypes.SwapModule__NoStateChange);
        }
        _dexVariables[params_.dexType][params_.dexId] = params_.dexVariables;

        // Update dex variables 2 if needed
        if (activeLiquidity_ != v_.activeLiquidityStart || v_.feeVersion == 1) {
            // params_.dexVariables2 was already updated above by _calculateDynamicFeeVariables and _updateDynamicFeeVariables functions
            _dexVariables2[params_.dexType][params_.dexId] = (params_.dexVariables2 & ~(X102 << DSL.BITS_DEX_V2_VARIABLES2_ACTIVE_LIQUIDITY)) | 
                (activeLiquidity_ << DSL.BITS_DEX_V2_VARIABLES2_ACTIVE_LIQUIDITY);
        }
    }

    /// @dev Swap tokens with perfect amount out
    function _swapOut(SwapOutInternalParams memory params_) internal returns (uint256 amountInRaw_, uint256 protocolFeeAccruedRaw_, uint256 lpFeeAccruedRaw_) {
        // NOTE: Non zero active liquidity check is not needed because even if there is no liquidity at the current tick current price doesn't have liquidity, doesn't mean that there is no liquidity somewhere else
        // if (activeLiquidity_ == 0) revert InsufficientLiquidity();

        // This is checked before calling this internal function
        // if (params_.amountOutRaw == 0) revert ZeroAmountOut();

        SwapOutInternalVariables memory v_;
        DynamicFeeVariables memory d_;

        v_.dexVariablesStart = params_.dexVariables;

        uint256 sqrtPriceX96_ = (params_.dexVariables >> DSL.BITS_DEX_V2_VARIABLES_CURRENT_SQRT_PRICE) & X72;
        unchecked {
            // sqrtPriceX96 is always rounded down when it is stored
            // Which means that if its a 1 to 0 swap (increasing price swap), the swapper might get a slightly better price
            // Hence we add 1 to round it up while fetching so protocol always remains on the winning side
            uint256 coefficient_ = (sqrtPriceX96_ >> DEFAULT_EXPONENT_SIZE);
            uint256 exponent_ = (sqrtPriceX96_ & DEFAULT_EXPONENT_MASK);
            if (exponent_ > 0 && !params_.swap0To1) coefficient_ += 1;
            sqrtPriceX96_ = coefficient_ << exponent_;
        }
        v_.sqrtPriceStartX96 = sqrtPriceX96_;

        uint256 activeLiquidity_ = (params_.dexVariables2 >> DSL.BITS_DEX_V2_VARIABLES2_ACTIVE_LIQUIDITY) & X102;
        v_.activeLiquidityStart = activeLiquidity_;

        int256 currentTick_;
        unchecked {
            currentTick_ = int256((params_.dexVariables >> DSL.BITS_DEX_V2_VARIABLES_ABSOLUTE_CURRENT_TICK) & X19);
            if ((params_.dexVariables >> DSL.BITS_DEX_V2_VARIABLES_CURRENT_TICK_SIGN) & X1 == 0) currentTick_ = -int256(currentTick_);
        } 

        v_.protocolFee = params_.swap0To1 ? 
            (params_.dexVariables2 >> DSL.BITS_DEX_V2_VARIABLES2_PROTOCOL_FEE_0_TO_1) & X12 : 
            (params_.dexVariables2 >> DSL.BITS_DEX_V2_VARIABLES2_PROTOCOL_FEE_1_TO_0) & X12;

        v_.protocolCutFee = (params_.dexVariables2 >> DSL.BITS_DEX_V2_VARIABLES2_PROTOCOL_CUT_FEE) & X6;

        {
            uint256 temp_;

            temp_ = (params_.dexVariables >> DSL.BITS_DEX_V2_VARIABLES_FEE_GROWTH_GLOBAL_0_X102) & X82;
            v_.feeGrowthGlobal0X102 = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);
            
            temp_ = (params_.dexVariables >> DSL.BITS_DEX_V2_VARIABLES_FEE_GROWTH_GLOBAL_1_X102) & X82;
            v_.feeGrowthGlobal1X102 = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);
        }

        v_.feeVersion = (params_.dexVariables2 >> DSL.BITS_DEX_V2_VARIABLES2_FEE_VERSION) & X4;

        // If fee version is 1 (inbuilt dynamic fee), we always sync the dynamic fee variables because even if constant fee is used, the dynamic fee variables need to be updated
        if (v_.feeVersion == 1) {
            (d_, params_.dexVariables2) = _calculateDynamicFeeVariables(sqrtPriceX96_, params_.swap0To1, params_.dexVariables2);
        }
        
        {
            uint256 fetchedDynamicFee_;
            bool overrideDynamicFee_;

            // If fetchDynamicFeeFlag is ON, we always fetch the dynamic fee unless the controller is the swapper
            // This is called after syncing the dynamic fee variables
            if (((params_.dexVariables2 >> DSL.BITS_DEX_V2_VARIABLES2_FETCH_DYNAMIC_FEE_FLAG) & X1 == 1) && params_.dexKey.controller != msg.sender) {
                // Use low-level call with gas limit to prevent controller from blocking swaps
                // Gas limit of 200K is sufficient for any reasonable fee calculation
                (bool success_, bytes memory returnData_) = params_.dexKey.controller.call{gas: 200000}(
                    abi.encodeWithSelector(IController.fetchDynamicFeeForSwapOut.selector, params_)
                );
                // Only use the result if call succeeded and returned exactly 64 bytes (uint256 + bool)
                if (success_ && returnData_.length == 64) {
                    (fetchedDynamicFee_, overrideDynamicFee_) = abi.decode(returnData_, (uint256, bool));
                    if (fetchedDynamicFee_ > X16) {
                        overrideDynamicFee_ = false;
                    }
                }
                // On failure or wrong return data size, use default values (fetchedDynamicFee_ = 0, overrideDynamicFee_ = false)
            }

            if (overrideDynamicFee_) {
                v_.isConstantLpFee = true;
                v_.constantLpFee = fetchedDynamicFee_;
            } else if (v_.feeVersion == 0) {
                v_.isConstantLpFee = true;
                v_.constantLpFee = (params_.dexVariables2 >> DSL.BITS_DEX_V2_VARIABLES2_LP_FEE) & X16;
            } else if (v_.feeVersion == 1 && d_.priceImpactToFeeDivisionFactor == 0) {
                v_.isConstantLpFee = true;
                v_.constantLpFee = d_.minFee;
            }
        }

        uint256 amountOutRemainingRaw_ = params_.amountOutRaw;

        while (amountOutRemainingRaw_ > 0) {
            v_.sqrtPriceStepStartX96 = sqrtPriceX96_;

            // Find next initialized tick using bitmap
            (v_.nextTick, v_.initialized) = _nextInitializedTickWithinOneWord(
                params_.dexType,
                params_.dexId,
                int24(currentTick_),
                params_.dexKey.tickSpacing,
                params_.swap0To1
            );

            if (v_.nextTick < MIN_TICK || v_.nextTick > MAX_TICK) {
                revert FluidDexV2D3D4Error(ErrorTypes.SwapModule__NextTickOutOfBounds);
            }

            // Calculate price limit for this step
            v_.sqrtPriceNextX96 = TM.getSqrtRatioAtTick(int24(v_.nextTick));

            // 1. If its swap 0 to 1, that means price is decreasing, but if next price is greater than current price, that means because of our rounding of sqrt price this anomaly occured, hence we need to correct it
            // 2. If its swap 1 to 0, that means price is increasing, but if next price is less than current price, that means because of our rounding of sqrt price this anomaly occured, hence we need to correct it
            if ((params_.swap0To1 && v_.sqrtPriceNextX96 > sqrtPriceX96_) || (!params_.swap0To1 && v_.sqrtPriceNextX96 < sqrtPriceX96_))  {
                // Verify deviation is not greater than 0.01%
                uint256 diff_ = params_.swap0To1 ? v_.sqrtPriceNextX96 - sqrtPriceX96_ : sqrtPriceX96_ - v_.sqrtPriceNextX96;
                if (diff_ * FOUR_DECIMALS > sqrtPriceX96_) {
                    revert FluidDexV2D3D4Error(ErrorTypes.SwapModule__SqrtPriceDeviationTooHigh);
                }
                sqrtPriceX96_ = v_.sqrtPriceNextX96;
            }

            {
                uint256 stepLpFeeRaw_;
                {
                    uint256 stepAmountInRaw_;
                    uint256 stepAmountOutRaw_;
                    uint256 stepProtocolFeeRaw_;
                    

                    if (v_.isConstantLpFee) {
                        (sqrtPriceX96_, stepAmountInRaw_, stepAmountOutRaw_) = _computeSwapStepForSwapOutWithoutFee(
                            sqrtPriceX96_,
                            v_.sqrtPriceNextX96,
                            activeLiquidity_,
                            amountOutRemainingRaw_
                        );

                        unchecked {
                            // added this check for safety because we are using unchecked, this should ideally never happen though
                            if (stepAmountInRaw_ > X86) {
                                revert FluidDexV2D3D4Error(ErrorTypes.SwapModule__StepAmountInOverflow);
                            }
                            uint256 amountInWithFee_ = stepAmountInRaw_;
                            if (v_.constantLpFee > 0) {
                                amountInWithFee_ = (((stepAmountInRaw_ * SIX_DECIMALS) + 1) / (SIX_DECIMALS - v_.constantLpFee)) + 1;
                            }
                            stepLpFeeRaw_ = amountInWithFee_ - stepAmountInRaw_;

                            if (v_.protocolFee > 0) {
                                amountInWithFee_ = (((amountInWithFee_ * SIX_DECIMALS) + 1) / (SIX_DECIMALS - v_.protocolFee)) + 1;
                            }
                            stepProtocolFeeRaw_ = amountInWithFee_ - stepAmountInRaw_ - stepLpFeeRaw_;

                            stepAmountInRaw_ = amountInWithFee_;
                        }
                    } else {
                        (sqrtPriceX96_, stepAmountInRaw_, stepAmountOutRaw_, stepProtocolFeeRaw_, stepLpFeeRaw_) = _computeSwapStepForSwapOutWithDynamicFee(
                            ComputeSwapStepForSwapOutWithDynamicFeeParams({
                                // doesnt matter what we pass as swap0To1 here because we anyway generate it later because passing the actual here causes stack too deep error
                                // and we need to pass something because this variable has to be in this struct otherwise there is stack too deep in the function we are calling
                                swap0To1: IS_0_TO_1_SWAP,
                                sqrtPriceCurrentX96: sqrtPriceX96_,
                                sqrtPriceTargetX96: v_.sqrtPriceNextX96,
                                liquidity: activeLiquidity_,
                                amountOutRemaining: amountOutRemainingRaw_,
                                protocolFee: v_.protocolFee,
                                dynamicFeeVariables: d_
                            })
                        );
                    }

                    unchecked {
                        // Taking protocol cut from lp fee and adding it to protocol fee
                        uint256 stepProtocolCutFeeRaw_;
                        if (stepLpFeeRaw_ > 0 && v_.protocolCutFee > 0) {
                            stepProtocolCutFeeRaw_ = (((stepLpFeeRaw_ * v_.protocolCutFee) + 1) / TWO_DECIMALS) + 1;
                        }

                        if (stepProtocolCutFeeRaw_ > 0) {
                            if (stepLpFeeRaw_ > stepProtocolCutFeeRaw_) {
                                stepProtocolFeeRaw_ += stepProtocolCutFeeRaw_;
                                stepLpFeeRaw_ -= stepProtocolCutFeeRaw_;
                            } else {
                                stepProtocolFeeRaw_ += stepLpFeeRaw_;
                                stepLpFeeRaw_ = 0;
                            }
                        }

                        // Update running totals
                        amountInRaw_ += stepAmountInRaw_;
                        amountOutRemainingRaw_ -= stepAmountOutRaw_;

                        // account for fees
                        protocolFeeAccruedRaw_ += stepProtocolFeeRaw_;
                        lpFeeAccruedRaw_ += stepLpFeeRaw_;
                    }
                }

                // Update global fee tracker
                if (activeLiquidity_ > 0) {
                    /// @dev Fee is cut from tokenIn in swap out
                    unchecked {
                        if (params_.swap0To1) v_.feeGrowthGlobal0X102 += (((stepLpFeeRaw_ * params_.token0ExchangePrice) 
                            / LC.EXCHANGE_PRICES_PRECISION) << 102) / activeLiquidity_;
                        else v_.feeGrowthGlobal1X102 += (((stepLpFeeRaw_ * params_.token1ExchangePrice) 
                            / LC.EXCHANGE_PRICES_PRECISION) << 102) / activeLiquidity_;
                    }
                }
            }

            // If we've reached the next price target
            if (sqrtPriceX96_ == v_.sqrtPriceNextX96) {
                if (v_.initialized) {
                    TickData memory tickData_ = _tickData[params_.dexType][params_.dexId][v_.nextTick];

                    {
                        // NOTE: Converting to big number and then converting back to normal number so that the precision lost later when storing big number in dex variables doesnt cause any issues
                        uint256 feeGrowthGlobal0X102_ = BM.toBigNumber(v_.feeGrowthGlobal0X102, BIG_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_DOWN);
                        uint256 feeGrowthGlobal1X102_ = BM.toBigNumber(v_.feeGrowthGlobal1X102, BIG_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_DOWN);

                        feeGrowthGlobal0X102_ = (feeGrowthGlobal0X102_ >> DEFAULT_EXPONENT_SIZE) << (feeGrowthGlobal0X102_ & DEFAULT_EXPONENT_MASK);
                        feeGrowthGlobal1X102_ = (feeGrowthGlobal1X102_ >> DEFAULT_EXPONENT_SIZE) << (feeGrowthGlobal1X102_ & DEFAULT_EXPONENT_MASK);

                        // Calculate new fee growth outside values
                        tickData_.feeGrowthOutside0X102 = feeGrowthGlobal0X102_ - tickData_.feeGrowthOutside0X102;
                        tickData_.feeGrowthOutside1X102 = feeGrowthGlobal1X102_ - tickData_.feeGrowthOutside1X102;
                    }

                    // Update Active Liquidity
                    unchecked {
                        int256 newActiveLiquidity_ = int256(activeLiquidity_) + (params_.swap0To1 ? -tickData_.liquidityNet : tickData_.liquidityNet);
                        // This will ideally never go negative, but adding the check for extra security
                        if (newActiveLiquidity_ < 0) {
                            revert FluidDexV2D3D4Error(ErrorTypes.SwapModule__ActiveLiquidityUnderflow);
                        }
                        activeLiquidity_ = uint256(newActiveLiquidity_);
                    }

                    // If active liquidity was zero when we started, then the sqrtPriceStartX96 will be recorded when liquidity becomes non zero for the first time
                    // Added this so pool price can move from no liquidity regions without any price change constraints until liquidity is found
                    if (v_.activeLiquidityStart == 0 && !v_.sqrtPriceStartX96Changed && activeLiquidity_ > 0) {
                        v_.sqrtPriceStartX96 = sqrtPriceX96_;
                        v_.sqrtPriceStartX96Changed = true;
                    }

                    _tickData[params_.dexType][params_.dexId][v_.nextTick] = tickData_;
                }

                // The tick got crossed, update current tick accordingly
                unchecked {
                    currentTick_ = params_.swap0To1 ? v_.nextTick - 1 : v_.nextTick;
                }
            } else if (sqrtPriceX96_ != v_.sqrtPriceStepStartX96) {
                // If price did change but didn't reach target, recalculate tick
                // this also means that amountInRemainingRaw_ has become zero, hence there will be no more loop iterations
                currentTick_ = TM.getTickAtSqrtRatio(uint160(sqrtPriceX96_));
            }
        }

        _verifySqrtPriceX96ChangeLimits(v_.sqrtPriceStartX96, sqrtPriceX96_);

        if (v_.feeVersion == 1) {
            unchecked {
                uint256 priceEndX96_ = FM.mulDiv(sqrtPriceX96_, sqrtPriceX96_, Q96);

                bool isPositivePriceDiff_ = priceEndX96_ > d_.zeroPriceImpactPriceX96;
                uint256 priceDiffX96_ = isPositivePriceDiff_ ? priceEndX96_ - d_.zeroPriceImpactPriceX96
                    : d_.zeroPriceImpactPriceX96 - priceEndX96_;
                uint256 finalAbsolutePriceImpact_ = (priceDiffX96_ * SIX_DECIMALS) / d_.zeroPriceImpactPriceX96;
                if (finalAbsolutePriceImpact_ >= SIX_DECIMALS) {
                    revert FluidDexV2D3D4Error(ErrorTypes.SwapModule__PriceImpactTooHigh);
                }

                int256 finalNetPriceImpact_ = isPositivePriceDiff_ ? int256(finalAbsolutePriceImpact_) : -int256(finalAbsolutePriceImpact_);
                params_.dexVariables2 = _updateDynamicFeeVariables(params_.dexVariables2, finalNetPriceImpact_);

            }
        }

        if (params_.dexVariables2 >> DSL.BITS_DEX_V2_VARIABLES2_POOL_ACCOUNTING_FLAG & X1 == 0) {
            uint256 tokenReserves_ = _tokenReserves[params_.dexType][params_.dexId];
            uint256 token0Reserves_ = (tokenReserves_ >> DSL.BITS_DEX_V2_TOKEN_RESERVES_TOKEN_0_RESERVES) & X128;
            uint256 token1Reserves_ = (tokenReserves_ >> DSL.BITS_DEX_V2_TOKEN_RESERVES_TOKEN_1_RESERVES) & X128;
            if (params_.swap0To1) {
                token0Reserves_ += amountInRaw_;
                token1Reserves_ -= params_.amountOutRaw;

                if (token0Reserves_ > X128) {
                    revert FluidDexV2D3D4Error(ErrorTypes.SwapModule__TokenReservesOverflow);
                }
            } else {
                token0Reserves_ -= params_.amountOutRaw;
                token1Reserves_ += amountInRaw_;

                if (token1Reserves_ > X128) {
                    revert FluidDexV2D3D4Error(ErrorTypes.SwapModule__TokenReservesOverflow);
                }
            }

            _tokenReserves[params_.dexType][params_.dexId] = (token0Reserves_ << DSL.BITS_DEX_V2_TOKEN_RESERVES_TOKEN_0_RESERVES) | 
                (token1Reserves_ << DSL.BITS_DEX_V2_TOKEN_RESERVES_TOKEN_1_RESERVES);
        }

        unchecked {
            // Dex variables will always have to be updated because the price will always change
            params_.dexVariables = (uint256(currentTick_ < 0 ? 0 : 1) << DSL.BITS_DEX_V2_VARIABLES_CURRENT_TICK_SIGN) |
                (uint256(currentTick_ < 0 ? -currentTick_ : currentTick_) << DSL.BITS_DEX_V2_VARIABLES_ABSOLUTE_CURRENT_TICK) |
                (BM.toBigNumber(sqrtPriceX96_, SMALL_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_DOWN) << DSL.BITS_DEX_V2_VARIABLES_CURRENT_SQRT_PRICE) |
                (BM.toBigNumber(v_.feeGrowthGlobal0X102, BIG_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_DOWN) << DSL.BITS_DEX_V2_VARIABLES_FEE_GROWTH_GLOBAL_0_X102) |
                (BM.toBigNumber(v_.feeGrowthGlobal1X102, BIG_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, ROUND_DOWN) << DSL.BITS_DEX_V2_VARIABLES_FEE_GROWTH_GLOBAL_1_X102);
        }

        if (v_.dexVariablesStart == params_.dexVariables) {
            revert FluidDexV2D3D4Error(ErrorTypes.SwapModule__NoStateChange);
        }
        _dexVariables[params_.dexType][params_.dexId] = params_.dexVariables;

        // Update dex variables 2 if needed
        if (activeLiquidity_ != v_.activeLiquidityStart || v_.feeVersion == 1) {
            // params_.dexVariables2 was already updated above by _calculateDynamicFeeVariables and _updateDynamicFeeVariables functions
            _dexVariables2[params_.dexType][params_.dexId] = (params_.dexVariables2 & ~(X102 << DSL.BITS_DEX_V2_VARIABLES2_ACTIVE_LIQUIDITY)) | 
                (activeLiquidity_ << DSL.BITS_DEX_V2_VARIABLES2_ACTIVE_LIQUIDITY);
        }
    }
}