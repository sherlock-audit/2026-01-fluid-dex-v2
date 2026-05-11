// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./variables.sol";
import { BigMathMinified as BM } from "../../../../../libraries/bigMathMinified.sol";
import { FixedPointMathLib as FPM } from "solmate/src/utils/FixedPointMathLib.sol";
import { DexV2D3D4CommonSlotsLink as DSL } from "../../../../../libraries/dexV2D3D4CommonSlotsLink.sol";
import { FullMath as FM } from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import { SqrtPriceMath as SPM } from "@uniswap/v3-core/contracts/libraries/SqrtPriceMath.sol";

abstract contract CommonHelpers is CommonVariables {
    modifier _onlyController(address controller_) {
        if (msg.sender != controller_) {
            revert FluidDexV2D3D4Error(ErrorTypes.Helpers__Unauthorized);
        }
        _;
    }

    function _getValidDex(DexKey memory dexKey_, uint256 dexType_) internal view returns (bytes32 dexId_) {
        dexId_ = keccak256(abi.encode(dexKey_));
        if (_dexVariables[dexType_][dexId_] == 0) {
            revert FluidDexV2D3D4Error(ErrorTypes.Helpers__DexNotInitialized);
        }
    }

    function _getDexVariables(uint256 dexType_, bytes32 dexId_) internal view returns (DexVariables memory dexVariables_) {
        uint256 dexVariablesPacked_ = _dexVariables[dexType_][dexId_];

        // temp_ => absolute current tick
        uint256 temp_ = (dexVariablesPacked_ >> DSL.BITS_DEX_V2_VARIABLES_ABSOLUTE_CURRENT_TICK) & X19;
        unchecked {
            if ((dexVariablesPacked_ >> DSL.BITS_DEX_V2_VARIABLES_CURRENT_TICK_SIGN) & X1 == 0) dexVariables_.currentTick = -int256(temp_);
            else dexVariables_.currentTick = int256(temp_);
        }

        // temp_ => current sqrt price
        temp_ = (dexVariablesPacked_ >> DSL.BITS_DEX_V2_VARIABLES_CURRENT_SQRT_PRICE) & X72;
        dexVariables_.sqrtPriceX96 = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);

        // temp_ => fee growth global 0
        temp_ = (dexVariablesPacked_ >> DSL.BITS_DEX_V2_VARIABLES_FEE_GROWTH_GLOBAL_0_X102) & X82;
        dexVariables_.feeGrowthGlobal0X102 = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);

        // temp_ => fee growth global 1
        temp_ = (dexVariablesPacked_ >> DSL.BITS_DEX_V2_VARIABLES_FEE_GROWTH_GLOBAL_1_X102) & X82;
        dexVariables_.feeGrowthGlobal1X102 = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);
    }

    function _setTickBitmap(DexKey memory dexKey_, uint256 dexType_, bytes32 dexId_, int256 tick_, bool initialize_) internal {
        int256 compressed_ = tick_ / int256(int24(dexKey_.tickSpacing));
        if (initialize_) _tickBitmap[dexType_][dexId_][compressed_ >> 8] |= (1 << (uint256(compressed_) % 256));
        else _tickBitmap[dexType_][dexId_][compressed_ >> 8] &= ~(1 << (uint256(compressed_) % 256));
    }

    function _tenPow(uint256 power_) internal pure returns (uint256) {
        // keeping the most used powers at the top for better gas optimization
        if (power_ == 3) {
            return 1_000; // used for 6 or 12 decimals (USDC, USDT)
        }
        if (power_ == 9) {
            return 1_000_000_000; // used for 18 decimals (ETH, and many more)
        }
        if (power_ == 1) {
            return 10; // used for 1 decimals (WBTC and more)
        }

        if (power_ == 0) {
            return 1;
        }
        if (power_ == 2) {
            return 100;
        }
        if (power_ == 4) {
            return 10_000;
        }
        if (power_ == 5) {
            return 100_000;
        }
        if (power_ == 6) {
            return 1_000_000;
        }
        if (power_ == 7) {
            return 10_000_000;
        }
        if (power_ == 8) {
            return 100_000_000;
        }

        // We will only need powers from 0 to 9 as token decimals can only be 6 to 18
        revert FluidDexV2D3D4Error(ErrorTypes.Helpers__InvalidPower);
    }

    function _calculateNumeratorAndDenominatorPrecisions(uint256 decimals_) internal pure returns (uint256 numerator_, uint256 denominator_) {
        unchecked {
            if (decimals_ > TOKENS_DECIMALS_PRECISION) {
                numerator_ = 1;
                denominator_ = _tenPow(decimals_ - TOKENS_DECIMALS_PRECISION);
            } else {
                numerator_ = _tenPow(TOKENS_DECIMALS_PRECISION - decimals_);
                denominator_ = 1;
            }
        }
    }

    function _verifyAmountLimits(uint256 amount_) internal pure {
        if (amount_ < FOUR_DECIMALS || amount_ > X128) {
            revert FluidDexV2D3D4Error(ErrorTypes.Helpers__AmountOutOfLimits);
        }
    }

    function _verifyAdjustedAmountLimits(uint256 adjustedAmount_) internal pure {
        if (adjustedAmount_ < FOUR_DECIMALS || adjustedAmount_ > X86) {
            revert FluidDexV2D3D4Error(ErrorTypes.Helpers__AdjustedAmountOutOfLimits);
        }
    }

    function _verifySqrtPriceX96ChangeLimits(uint256 sqrtPriceStartX96_, uint256 sqrtPriceEndX96_) internal pure {
        uint256 percentageChange_;
        unchecked {
            percentageChange_ = ((sqrtPriceEndX96_ > sqrtPriceStartX96_ ? sqrtPriceEndX96_ - sqrtPriceStartX96_ 
                : sqrtPriceStartX96_ - sqrtPriceEndX96_) * TEN_DECIMALS) / sqrtPriceStartX96_;
        }

        if (percentageChange_ > MAX_SQRT_PRICE_CHANGE_PERCENTAGE || percentageChange_ < MIN_SQRT_PRICE_CHANGE_PERCENTAGE) {
            revert FluidDexV2D3D4Error(ErrorTypes.Helpers__SqrtPriceChangeOutOfBounds);
        }
    }

    function _verifyLiquidityLimits(uint256 liquidity_) internal pure {
        if (liquidity_ < FOUR_DECIMALS || liquidity_ > X86) {
            revert FluidDexV2D3D4Error(ErrorTypes.Helpers__LiquidityOutOfLimits);
        }
    }

    function _verifyLiquidityChangeLimits(uint256 liquidity_, uint256 liquidityChange_) internal pure {
        unchecked {
            if (liquidityChange_ < (liquidity_ / NINE_DECIMALS) || (liquidity_ != 0 && liquidityChange_ > (liquidity_ * NINE_DECIMALS))) {
                revert FluidDexV2D3D4Error(ErrorTypes.Helpers__LiquidityChangeInvalid);
            }
        }
    }

    /// @notice Derives max liquidity per tick from given tick spacing
    /// @dev Executed when adding liquidity
    /// @param tickSpacing_ The amount of required tick separation, realized in multiples of `tickSpacing_`
    ///     e.g., a tickSpacing of 3 requires ticks to be initialized every 3rd tick i.e., ..., -6, -3, 0, 3, 6, ...
    /// @return The max liquidity per tick
    function _getMaxLiquidityPerTick(uint24 tickSpacing_) internal pure returns (uint256) {
        uint24 numTicks;
        unchecked {
            int24 minTick = MIN_TICK / int24(tickSpacing_);
            if (MIN_TICK % int24(tickSpacing_) != 0) minTick--;

            int24 maxTick = MAX_TICK / int24(tickSpacing_);
            numTicks = uint24(int24(maxTick - minTick) + 1);
        }

        return MAX_LIQUIDITY / numTicks;
    }

    function _calculateDynamicFeeVariables(
        uint256 sqrtPriceX96_,
        bool swap0To1_,
        uint256 dexVariables2_
    ) internal view returns (DynamicFeeVariables memory, uint256) {
        DynamicFeeVariables memory d_;

        // Sync dynamic fee variables
        uint256 newLastUpdateTimestamp_ = block.timestamp & X15;
        uint256 lastUpdateTimestamp_ = (dexVariables2_ >> DSL.BITS_DEX_V2_VARIABLES2_LAST_UPDATE_TIMESTAMP) & X15;

        uint256 timeElapsed_;
        unchecked {
            if (newLastUpdateTimestamp_ < lastUpdateTimestamp_) {
                // More time than than this might have passed, but we assume the minimum
                timeElapsed_ = X15 + 1 + newLastUpdateTimestamp_ - lastUpdateTimestamp_;
            } else {
                // More time than than this might have passed, but we assume the minimum
                timeElapsed_ = newLastUpdateTimestamp_ - lastUpdateTimestamp_;
            }
        }

        uint256 decayTimeRemaining_ = (dexVariables2_ >> DSL.BITS_DEX_V2_VARIABLES2_DECAY_TIME_REMAINING) & X12;
        int256 netPriceImpact_;

        if (timeElapsed_ < decayTimeRemaining_) {
            netPriceImpact_ = int256((dexVariables2_ >> DSL.BITS_DEX_V2_VARIABLES2_ABSOLUTE_NET_PRICE_IMPACT) & X20);
            unchecked {
                if ((dexVariables2_ >> DSL.BITS_DEX_V2_VARIABLES2_NET_PRICE_IMPACT_SIGN) & X1 == 0) netPriceImpact_ = -netPriceImpact_;
                netPriceImpact_ = (netPriceImpact_ * int256(decayTimeRemaining_ - timeElapsed_)) / int256(decayTimeRemaining_);
                decayTimeRemaining_ -= timeElapsed_;

                dexVariables2_ = (dexVariables2_ & ~(X58 << DSL.BITS_DEX_V2_VARIABLES2_NET_PRICE_IMPACT_SIGN)) |
                    (netPriceImpact_ < 0 ? uint256(0) : uint256(1) << DSL.BITS_DEX_V2_VARIABLES2_NET_PRICE_IMPACT_SIGN) |
                    (uint256(netPriceImpact_ < 0 ? -netPriceImpact_ : netPriceImpact_) << DSL.BITS_DEX_V2_VARIABLES2_ABSOLUTE_NET_PRICE_IMPACT) |
                    (newLastUpdateTimestamp_ << DSL.BITS_DEX_V2_VARIABLES2_LAST_UPDATE_TIMESTAMP) |
                    (decayTimeRemaining_ << DSL.BITS_DEX_V2_VARIABLES2_DECAY_TIME_REMAINING);
            }
        } else {
            // netPriceImpact_ = 0; // already zero
            // decayTimeRemaining_ = 0; // not needed below this

            // NOTE: The absolute price impact will become zero and price impact sign will be zero which means (-0) which is same as (0)
            dexVariables2_ = (dexVariables2_ & ~(X58 << DSL.BITS_DEX_V2_VARIABLES2_NET_PRICE_IMPACT_SIGN)) |
                (newLastUpdateTimestamp_ << DSL.BITS_DEX_V2_VARIABLES2_LAST_UPDATE_TIMESTAMP);
        }

        d_.minFee = (dexVariables2_ >> DSL.BITS_DEX_V2_VARIABLES2_MIN_FEE) & X16;
        d_.maxFee = (dexVariables2_ >> DSL.BITS_DEX_V2_VARIABLES2_MAX_FEE) & X16;
        d_.priceImpactToFeeDivisionFactor = (dexVariables2_ >> DSL.BITS_DEX_V2_VARIABLES2_PRICE_IMPACT_TO_FEE_DIVISION_FACTOR) & X8;

        unchecked {
            // Calculate the zero price impact price
            d_.zeroPriceImpactPriceX96 = (FM.mulDiv(sqrtPriceX96_, sqrtPriceX96_, Q96) * SIX_DECIMALS) / uint256((int256(SIX_DECIMALS) + netPriceImpact_));

            // Calculate the min fee kink price impact
            int256 minFeeKinkPriceImpact_ = int256(d_.minFee * d_.priceImpactToFeeDivisionFactor);
            if (minFeeKinkPriceImpact_ > int256(SIX_DECIMALS)) minFeeKinkPriceImpact_ = int256(SIX_DECIMALS);
            if (swap0To1_) minFeeKinkPriceImpact_ = -minFeeKinkPriceImpact_; // If swap0To1_ is true, it means the price is decreasing, hence the kinks for it will be less than the zero price impact price

            // Calculate the max fee kink price impact
            int256 maxFeeKinkPriceImpact_ = int256(d_.maxFee * d_.priceImpactToFeeDivisionFactor);
            if (maxFeeKinkPriceImpact_ > int256(SIX_DECIMALS)) maxFeeKinkPriceImpact_ = int256(SIX_DECIMALS);
            if (swap0To1_) maxFeeKinkPriceImpact_ = -maxFeeKinkPriceImpact_; // If swap0To1_ is true, it means the price is decreasing, hence the kinks for it will be less than the zero price impact price

            // Calculate the min fee kink price
            d_.minFeeKinkPriceX96 = (d_.zeroPriceImpactPriceX96 * uint256((int256(SIX_DECIMALS) + minFeeKinkPriceImpact_))) / SIX_DECIMALS;
            if (d_.minFeeKinkPriceX96 < MIN_PRICE_X96) {
                d_.minFeeKinkPriceX96 = MIN_PRICE_X96;
            } else if (d_.minFeeKinkPriceX96 > MAX_PRICE_X96) {
                d_.minFeeKinkPriceX96 = MAX_PRICE_X96;
            }

            if (d_.minFeeKinkPriceX96 < X160) {
                d_.minFeeKinkSqrtPriceX96 = FPM.sqrt(d_.minFeeKinkPriceX96 << 96);
            } else {
                d_.minFeeKinkSqrtPriceX96 = FPM.sqrt(d_.minFeeKinkPriceX96 << 84) << 6; // Because we know that minFeeKinkPriceX96 cannot exceed X172
            }

            // Calculate the max fee kink price
            d_.maxFeeKinkPriceX96 = (d_.zeroPriceImpactPriceX96 * uint256((int256(SIX_DECIMALS) + maxFeeKinkPriceImpact_))) / SIX_DECIMALS;
            if (d_.maxFeeKinkPriceX96 < MIN_PRICE_X96) {
                d_.maxFeeKinkPriceX96 = MIN_PRICE_X96;
            } else if (d_.maxFeeKinkPriceX96 > MAX_PRICE_X96) {
                d_.maxFeeKinkPriceX96 = MAX_PRICE_X96;
            }

            if (d_.maxFeeKinkPriceX96 < X160) {
                d_.maxFeeKinkSqrtPriceX96 = FPM.sqrt(d_.maxFeeKinkPriceX96 << 96);
            } else {
                d_.maxFeeKinkSqrtPriceX96 = FPM.sqrt(d_.maxFeeKinkPriceX96 << 84) << 6; // Because we know that maxFeeKinkPriceX96 cannot exceed X172
            }
        }

        return (d_, dexVariables2_);
    }

    function _updateDynamicFeeVariables(uint256 dexVariables2_, int256 finalNetPriceImpact_) internal pure returns (uint256) {
        uint256 decayTimeRemaining_ = (dexVariables2_ >> DSL.BITS_DEX_V2_VARIABLES2_DECAY_TIME_REMAINING) & X12;
        int256 netPriceImpact_ = int256((dexVariables2_ >> DSL.BITS_DEX_V2_VARIABLES2_ABSOLUTE_NET_PRICE_IMPACT) & X20);
        unchecked {
            if ((dexVariables2_ >> DSL.BITS_DEX_V2_VARIABLES2_NET_PRICE_IMPACT_SIGN) & X1 == 0) netPriceImpact_ = -netPriceImpact_;
        }

        uint256 maxDecayTime_ = (dexVariables2_ >> DSL.BITS_DEX_V2_VARIABLES2_MAX_DECAY_TIME) & X12;

        if (finalNetPriceImpact_ == 0) {
            // If final net price impact is 0, we set decay time to 0
            decayTimeRemaining_ = 0;
        } else if (netPriceImpact_ == 0) {
            // If initial net price impact was 0, we reset decay time to max (start the decay process)
            decayTimeRemaining_ = maxDecayTime_;
        } else if ((finalNetPriceImpact_ > 0 && netPriceImpact_ < 0) || (finalNetPriceImpact_ < 0 && netPriceImpact_ > 0)) {
            // If the sign of initial & final net price impact is different, we reset decay time to max
            decayTimeRemaining_ = maxDecayTime_;
        } else {
            // If none of the above, update decay time remaining in the ratio of change of net price impact, make sure it doesn't cross the max decay time
            uint256 newDecayTime_;
            unchecked {
                newDecayTime_ = uint256((int256(decayTimeRemaining_) * finalNetPriceImpact_) / netPriceImpact_);
            }

            decayTimeRemaining_ = newDecayTime_ > maxDecayTime_ ? maxDecayTime_ : newDecayTime_;
        }

        dexVariables2_ = (dexVariables2_ & ~(X12 << DSL.BITS_DEX_V2_VARIABLES2_DECAY_TIME_REMAINING)) |
            (decayTimeRemaining_ << DSL.BITS_DEX_V2_VARIABLES2_DECAY_TIME_REMAINING);

        unchecked {
            dexVariables2_ = (dexVariables2_ & ~(X21 << DSL.BITS_DEX_V2_VARIABLES2_NET_PRICE_IMPACT_SIGN)) |
                (uint256(finalNetPriceImpact_ < 0 ? 0 : 1) << DSL.BITS_DEX_V2_VARIABLES2_NET_PRICE_IMPACT_SIGN) |
                (uint256(finalNetPriceImpact_ < 0 ? -finalNetPriceImpact_ : finalNetPriceImpact_) << DSL.BITS_DEX_V2_VARIABLES2_ABSOLUTE_NET_PRICE_IMPACT);
        }
        return dexVariables2_;

    }

    function _calculateStepTargetSqrtPriceX96(bool swap0To1_, uint256 sqrtPriceKinkX96_, uint256 sqrtPriceTargetX96_) internal pure returns (uint256) {
        if (swap0To1_) return sqrtPriceKinkX96_ < sqrtPriceTargetX96_ ? sqrtPriceTargetX96_ : sqrtPriceKinkX96_;
        else return sqrtPriceKinkX96_ > sqrtPriceTargetX96_ ? sqrtPriceTargetX96_ : sqrtPriceKinkX96_;
    }

    function _calculateStepDynamicFee(
        bool swap0To1_, 
        uint256 priceStartX96_, 
        uint256 priceEndX96_, 
        uint256 zeroPriceImpactPriceX96_, 
        uint256 priceImpactToFeeDivisionFactor_
    ) internal pure returns (uint256 stepDynamicFee_) {
        uint256 stepMeanPriceImpact_;
        unchecked {
            uint256 priceMeanX96_ = (priceStartX96_ + priceEndX96_) / 2;

            // We can say for sure that zeroPriceImpactPriceX96_ > priceMeanX96_ for swap0To1_ = true and zeroPriceImpactPriceX96_ < priceMeanX96_ for swap0To1_ = false
            // This is because this function is only called for these cases (when the price is between min fee kink and max fee kink for that swap direction)
            stepMeanPriceImpact_ = 
                ((swap0To1_? zeroPriceImpactPriceX96_ - priceMeanX96_: priceMeanX96_ - zeroPriceImpactPriceX96_) * SIX_DECIMALS) / zeroPriceImpactPriceX96_;
        }
        
        // NOTE: priceImpactToFeeDivisionFactor_ cannot be zero because we have checked it before
        if (stepMeanPriceImpact_ > 0) {
            stepDynamicFee_ = ((stepMeanPriceImpact_ + 1) / priceImpactToFeeDivisionFactor_) + 1;
        }
    }

    function _computeSwapStepForSwapInWithoutFee(
        uint256 sqrtPriceCurrentX96_,
        uint256 sqrtPriceTargetX96_,
        uint256 liquidity_,
        uint256 amountInRemaining_
    ) internal pure returns (uint256 sqrtPriceNextX96_, uint256 amountIn_, uint256 amountOut_) {
        bool swap0To1_ = sqrtPriceCurrentX96_ > sqrtPriceTargetX96_; // we could have passed this aswell but this way we can save gas as we save stack too deep in the other function
        uint256 amountInAvailable_ = swap0To1_
            ? SPM.getAmount0Delta(uint160(sqrtPriceCurrentX96_), uint160(sqrtPriceTargetX96_), uint128(liquidity_), ROUND_UP)
            : SPM.getAmount1Delta(uint160(sqrtPriceCurrentX96_), uint160(sqrtPriceTargetX96_), uint128(liquidity_), ROUND_UP);
        // NOTE: We could have used < instead of >= here and interchanged the code blocks, but that actually increases gas, best optimization is to use >= here because if is the most used case
        if (amountInRemaining_ >= amountInAvailable_) {
            // target is reached
            sqrtPriceNextX96_ = sqrtPriceTargetX96_;
            amountIn_ = amountInAvailable_;
        } else {
            // target is not reached, hence we calculate the next sqrt price
            sqrtPriceNextX96_ = SPM.getNextSqrtPriceFromInput(uint160(sqrtPriceCurrentX96_), uint128(liquidity_), amountInRemaining_, swap0To1_);
            amountIn_ = amountInRemaining_;
        }
        amountOut_ = swap0To1_
            ? SPM.getAmount1Delta(uint160(sqrtPriceCurrentX96_), uint160(sqrtPriceNextX96_), uint128(liquidity_), ROUND_DOWN)
            : SPM.getAmount0Delta(uint160(sqrtPriceCurrentX96_), uint160(sqrtPriceNextX96_), uint128(liquidity_), ROUND_DOWN);
    }

    function _computeSwapStepForSwapInWithDynamicFee(ComputeSwapStepForSwapInWithDynamicFeeParams memory params_) internal pure 
        returns (uint256 sqrtPriceNextX96_, uint256 amountIn_, uint256 amountOut_, uint256 protocolFeeAmount_, uint256 lpFeeAmount_) {

        params_.swap0To1 = params_.sqrtPriceCurrentX96 > params_.sqrtPriceTargetX96; // we could have passed this aswell but this way we can save gas as we save stack too deep in the other function

        // next price will start from current price & move towards target price
        sqrtPriceNextX96_ = params_.sqrtPriceCurrentX96;
        uint256 priceNextX96_ = FM.mulDiv(sqrtPriceNextX96_, sqrtPriceNextX96_, Q96);
        
        // If params_.swap0To1 is true, price is decreasing, hence we process swaps at min fee until current price is greater than minFeeKinkPriceX96
        // If params_.swap0To1 is false, price is increasing, hence we process swaps at min fee until current price is less than minFeeKinkPriceX96
        if (params_.swap0To1
                ? priceNextX96_ > params_.dynamicFeeVariables.minFeeKinkPriceX96
                : priceNextX96_ < params_.dynamicFeeVariables.minFeeKinkPriceX96) {

            (sqrtPriceNextX96_, amountIn_, amountOut_) = _computeSwapStepForSwapInWithoutFee(
                sqrtPriceNextX96_,
                _calculateStepTargetSqrtPriceX96(params_.swap0To1, params_.dynamicFeeVariables.minFeeKinkSqrtPriceX96, params_.sqrtPriceTargetX96),
                params_.liquidity,
                params_.amountInRemaining
            );
            unchecked {
                params_.amountInRemaining -= amountIn_;

                // added this check for safety because we are using unchecked, this should ideally never happen though
                if (amountOut_ > X86) revert FluidDexV2D3D4Error(ErrorTypes.Helpers__AmountOutOverflow);
                if (amountOut_ > 0 && params_.protocolFee > 0) {
                    protocolFeeAmount_ = (((amountOut_ * params_.protocolFee) + 1) / SIX_DECIMALS) + 1;
                }
                amountOut_ = amountOut_ > protocolFeeAmount_ ? amountOut_ - protocolFeeAmount_ : 0;

                if (amountOut_ > 0 && params_.dynamicFeeVariables.minFee > 0) {
                    lpFeeAmount_ = (((amountOut_ * params_.dynamicFeeVariables.minFee) + 1) / SIX_DECIMALS) + 1;
                }
                amountOut_ = amountOut_ > lpFeeAmount_ ? amountOut_ - lpFeeAmount_ : 0;
            }

            // If we did not reach the target price, means amountInRemaining became zero, hence the swap is over
            if (sqrtPriceNextX96_ == params_.sqrtPriceTargetX96 || params_.amountInRemaining == 0) 
                return (sqrtPriceNextX96_, amountIn_, amountOut_, protocolFeeAmount_, lpFeeAmount_);

            // If we reached the target price, we set the next price to the min fee kink price
            priceNextX96_ = params_.dynamicFeeVariables.minFeeKinkPriceX96;
        }

        // If params_.swap0To1 is true, price is decreasing, hence we process swaps at dynamic fee until current price is greater than maxFeeKinkPriceX96
        // If params_.swap0To1 is false, price is increasing, hence we process swaps at dynamic fee until current price is less than maxFeeKinkPriceX96
        if (params_.swap0To1 
            ? priceNextX96_ > params_.dynamicFeeVariables.maxFeeKinkPriceX96
            : priceNextX96_ < params_.dynamicFeeVariables.maxFeeKinkPriceX96) {

            uint256 stepAmountIn_;
            uint256 stepAmountOut_;
            (sqrtPriceNextX96_, stepAmountIn_, stepAmountOut_) = _computeSwapStepForSwapInWithoutFee(
                sqrtPriceNextX96_,
                _calculateStepTargetSqrtPriceX96(params_.swap0To1, params_.dynamicFeeVariables.maxFeeKinkSqrtPriceX96, params_.sqrtPriceTargetX96),
                params_.liquidity,
                params_.amountInRemaining
            );
            unchecked {
                params_.amountInRemaining -= stepAmountIn_;

                uint256 stepDynamicFee_ = _calculateStepDynamicFee(
                    params_.swap0To1, 
                    priceNextX96_, // start price because priceNextX96 hasn't been updated yet
                    FM.mulDiv(sqrtPriceNextX96_, sqrtPriceNextX96_, Q96), // end price because sqrtPriceNextX96_ has been updated
                    params_.dynamicFeeVariables.zeroPriceImpactPriceX96, 
                    params_.dynamicFeeVariables.priceImpactToFeeDivisionFactor
                );

                // added this check for safety because we are using unchecked, this should ideally never happen though
                if (stepAmountOut_ > X86) revert FluidDexV2D3D4Error(ErrorTypes.Helpers__AmountOutOverflow);
                uint256 stepProtocolFeeAmount_;
                if (stepAmountOut_ > 0 && params_.protocolFee > 0) {
                    stepProtocolFeeAmount_ = (((stepAmountOut_ * params_.protocolFee) + 1) / SIX_DECIMALS) + 1;
                }
                stepAmountOut_ = stepAmountOut_ > stepProtocolFeeAmount_ ? stepAmountOut_ - stepProtocolFeeAmount_ : 0;

                uint256 stepLpFeeAmount_;
                if (stepAmountOut_ > 0 && stepDynamicFee_ > 0) {
                    stepLpFeeAmount_ = (((stepAmountOut_ * stepDynamicFee_) + 1) / SIX_DECIMALS) + 1;
                }
                stepAmountOut_ = stepAmountOut_ > stepLpFeeAmount_ ? stepAmountOut_ - stepLpFeeAmount_ : 0;

                amountOut_ += stepAmountOut_;
                amountIn_ += stepAmountIn_;
                protocolFeeAmount_ += stepProtocolFeeAmount_;
                lpFeeAmount_ += stepLpFeeAmount_;
            }

            // If we reached the target price, or amountInRemaining became zero, the swap is over
            if (sqrtPriceNextX96_ == params_.sqrtPriceTargetX96 || params_.amountInRemaining == 0) 
                return (sqrtPriceNextX96_, amountIn_, amountOut_, protocolFeeAmount_, lpFeeAmount_);

            // If we reached the target price, we set the next price to the max fee kink price
            // priceNextX96_ = params_.dynamicFeeVariables.maxFeeKinkPriceX96; // This was not needed here as priceNextX96_ is not used further
        }

        // NOTE: Defined stepAmountIn_, stepAmountOut_, stepProtocolFeeAmount_ & stepLpFeeAmount_ twice because it solved stack too deep error

        // We process the rest of the swap at max fee
        uint256 stepAmountIn_;
        uint256 stepAmountOut_;
        (sqrtPriceNextX96_, stepAmountIn_, stepAmountOut_) = _computeSwapStepForSwapInWithoutFee(
            sqrtPriceNextX96_,
            params_.sqrtPriceTargetX96,
            params_.liquidity,
            params_.amountInRemaining
        );
        // params_.amountInRemaining -= stepAmountIn_; // This was not needed here as params_.amountInRemaining is not used further

        unchecked {
            // added this check for safety because we are using unchecked, this should ideally never happen though
            if (stepAmountOut_ > X86) revert FluidDexV2D3D4Error(ErrorTypes.Helpers__AmountOutOverflow);
            uint256 stepProtocolFeeAmount_;
            if (stepAmountOut_ > 0 && params_.protocolFee > 0) {
                stepProtocolFeeAmount_ = (((stepAmountOut_ * params_.protocolFee) + 1) / SIX_DECIMALS) + 1;
            }
            stepAmountOut_ = stepAmountOut_ > stepProtocolFeeAmount_ ? stepAmountOut_ - stepProtocolFeeAmount_ : 0;

            uint256 stepLpFeeAmount_;
            if (stepAmountOut_ > 0 && params_.dynamicFeeVariables.maxFee > 0) {
                stepLpFeeAmount_ = (((stepAmountOut_ * params_.dynamicFeeVariables.maxFee) + 1) / SIX_DECIMALS) + 1;
            }
            stepAmountOut_ = stepAmountOut_ > stepLpFeeAmount_ ? stepAmountOut_ - stepLpFeeAmount_ : 0;

            amountOut_ += stepAmountOut_;
            amountIn_ += stepAmountIn_;
            protocolFeeAmount_ += stepProtocolFeeAmount_;
            lpFeeAmount_ += stepLpFeeAmount_;
        }
    }

    function _computeSwapStepForSwapOutWithoutFee(
        uint256 sqrtPriceCurrentX96_,
        uint256 sqrtPriceTargetX96_,
        uint256 liquidity_,
        uint256 amountOutRemaining_
    ) internal pure returns (uint256 sqrtPriceNextX96_, uint256 amountIn_, uint256 amountOut_) {
        bool swap0To1_ = sqrtPriceCurrentX96_ > sqrtPriceTargetX96_; // we could have passed this aswell but this way we can save gas as we save stack too deep in the other function
        uint256 amountOutAvailable_ = swap0To1_
            ? SPM.getAmount1Delta(uint160(sqrtPriceCurrentX96_), uint160(sqrtPriceTargetX96_), uint128(liquidity_), ROUND_DOWN)
            : SPM.getAmount0Delta(uint160(sqrtPriceCurrentX96_), uint160(sqrtPriceTargetX96_), uint128(liquidity_), ROUND_DOWN);
        // NOTE: We could have used < instead of >= here and interchanged the code blocks, but that actually increases gas, best optimization is to use >= here because if is the most used case
        if (amountOutRemaining_ >= amountOutAvailable_) {
            // target is reached
            sqrtPriceNextX96_ = sqrtPriceTargetX96_;
            amountOut_ = amountOutAvailable_;
        } else {
            // target is not reached, hence we calculate the next sqrt price
            sqrtPriceNextX96_ = SPM.getNextSqrtPriceFromOutput(uint160(sqrtPriceCurrentX96_), uint128(liquidity_), amountOutRemaining_, swap0To1_);
            amountOut_ = amountOutRemaining_;
        }
        amountIn_ = swap0To1_
            ? SPM.getAmount0Delta(uint160(sqrtPriceCurrentX96_), uint160(sqrtPriceNextX96_), uint128(liquidity_), ROUND_UP)
            : SPM.getAmount1Delta(uint160(sqrtPriceCurrentX96_), uint160(sqrtPriceNextX96_), uint128(liquidity_), ROUND_UP);
    }

    function _computeSwapStepForSwapOutWithDynamicFee(ComputeSwapStepForSwapOutWithDynamicFeeParams memory params_) internal pure 
        returns (uint256 sqrtPriceNextX96_, uint256 amountIn_, uint256 amountOut_, uint256 protocolFeeAmount_, uint256 lpFeeAmount_) {

        params_.swap0To1 = params_.sqrtPriceCurrentX96 > params_.sqrtPriceTargetX96; // we could have passed this aswell but this way we can save gas as we save stack too deep in the other function

        // next price will start from current price & move towards target price
        sqrtPriceNextX96_ = params_.sqrtPriceCurrentX96;
        uint256 priceNextX96_ = FM.mulDiv(sqrtPriceNextX96_, sqrtPriceNextX96_, Q96);

        // If params_.swap0To1 is true, price is decreasing, hence we process swaps at min fee until current price is greater than minFeeKinkPriceX96
        // If params_.swap0To1 is false, price is increasing, hence we process swaps at min fee until current price is less than minFeeKinkPriceX96
        if (params_.swap0To1 
            ? priceNextX96_ > params_.dynamicFeeVariables.minFeeKinkPriceX96
            : priceNextX96_ < params_.dynamicFeeVariables.minFeeKinkPriceX96) {

            (sqrtPriceNextX96_, amountIn_, amountOut_) = _computeSwapStepForSwapOutWithoutFee(
                sqrtPriceNextX96_,
                _calculateStepTargetSqrtPriceX96(params_.swap0To1, params_.dynamicFeeVariables.minFeeKinkSqrtPriceX96, params_.sqrtPriceTargetX96),
                params_.liquidity,
                params_.amountOutRemaining
            );
            unchecked {
                params_.amountOutRemaining -= amountOut_;

                // added this check for safety because we are using unchecked, this should ideally never happen though
                if (amountIn_ > X86) revert FluidDexV2D3D4Error(ErrorTypes.Helpers__AmountInOverflow);
                uint256 amountInWithFee_ = amountIn_;
                if (params_.dynamicFeeVariables.minFee > 0) {
                    amountInWithFee_ = (((amountIn_ * SIX_DECIMALS) + 1) / (SIX_DECIMALS - params_.dynamicFeeVariables.minFee)) + 1;
                }
                lpFeeAmount_ = amountInWithFee_ - amountIn_;

                if (params_.protocolFee > 0) {
                    amountInWithFee_ = (((amountInWithFee_ * SIX_DECIMALS) + 1) / (SIX_DECIMALS - params_.protocolFee)) + 1;
                }
                protocolFeeAmount_ = amountInWithFee_ - amountIn_ - lpFeeAmount_;

                amountIn_ = amountInWithFee_;
            }

            // If we did not reach the target price, means amountInRemaining became zero, hence the swap is over
            if (sqrtPriceNextX96_ == params_.sqrtPriceTargetX96 || params_.amountOutRemaining == 0) 
                return (sqrtPriceNextX96_, amountIn_, amountOut_, protocolFeeAmount_, lpFeeAmount_);

            // If we reached the target price, we set the next price to the min fee kink price
            priceNextX96_ = params_.dynamicFeeVariables.minFeeKinkPriceX96;
        }

        // If params_.swap0To1 is true, price is decreasing, hence we process swaps at dynamic fee until current price is greater than maxFeeKinkPriceX96
        // If params_.swap0To1 is false, price is increasing, hence we process swaps at dynamic fee until current price is less than maxFeeKinkPriceX96
        if (params_.swap0To1 
            ? priceNextX96_ > params_.dynamicFeeVariables.maxFeeKinkPriceX96
            : priceNextX96_ < params_.dynamicFeeVariables.maxFeeKinkPriceX96) {

            uint256 stepAmountIn_;
            uint256 stepAmountOut_;
            (sqrtPriceNextX96_, stepAmountIn_, stepAmountOut_) = _computeSwapStepForSwapOutWithoutFee(
                sqrtPriceNextX96_,
                _calculateStepTargetSqrtPriceX96(params_.swap0To1, params_.dynamicFeeVariables.maxFeeKinkSqrtPriceX96, params_.sqrtPriceTargetX96),
                params_.liquidity,
                params_.amountOutRemaining
            );
            unchecked {
                params_.amountOutRemaining -= stepAmountOut_;

                uint256 stepDynamicFee_ = _calculateStepDynamicFee(
                    params_.swap0To1, 
                    priceNextX96_, // start price because priceNextX96 hasn't been updated yet
                    FM.mulDiv(sqrtPriceNextX96_, sqrtPriceNextX96_, Q96), // end price because sqrtPriceNextX96_ has been updated
                    params_.dynamicFeeVariables.zeroPriceImpactPriceX96, 
                    params_.dynamicFeeVariables.priceImpactToFeeDivisionFactor
                );

                // added this check for safety because we are using unchecked, this should ideally never happen though
                if (stepAmountIn_ > X86) revert FluidDexV2D3D4Error(ErrorTypes.Helpers__AmountInOverflow);
                uint256 stepAmountInWithFee_ = stepAmountIn_;
                if (stepDynamicFee_ > 0) {
                    stepAmountInWithFee_ = (((stepAmountIn_ * SIX_DECIMALS) + 1) / (SIX_DECIMALS - stepDynamicFee_)) + 1;
                }
                uint256 stepLpFeeAmount_ = stepAmountInWithFee_ - stepAmountIn_;

                if (params_.protocolFee > 0) {
                    stepAmountInWithFee_ = (((stepAmountInWithFee_ * SIX_DECIMALS) + 1) / (SIX_DECIMALS - params_.protocolFee)) + 1;
                }
                uint256 stepProtocolFeeAmount_ = stepAmountInWithFee_ - stepAmountIn_ - stepLpFeeAmount_;

                amountIn_ += stepAmountInWithFee_;
                amountOut_ += stepAmountOut_;
                lpFeeAmount_ += stepLpFeeAmount_;
                protocolFeeAmount_ += stepProtocolFeeAmount_;
            }

            // If we reached the target price, or amountOutRemaining became zero, the swap is over
            if (sqrtPriceNextX96_ == params_.sqrtPriceTargetX96 || params_.amountOutRemaining == 0) 
                return (sqrtPriceNextX96_, amountIn_, amountOut_, protocolFeeAmount_, lpFeeAmount_);

            // If we reached the target price, we set the next price to the max fee kink price
            // priceNextX96_ = params_.dynamicFeeVariables.maxFeeKinkPriceX96; // This was not needed here as priceNextX96_ is not used further
        }

        // NOTE: Defined stepAmountIn_, stepAmountOut_, stepProtocolFeeAmount_ & stepLpFeeAmount_ twice because it solved stack too deep error

        // We process the rest of the swap at max fee
        uint256 stepAmountIn_;
        uint256 stepAmountOut_;
        (sqrtPriceNextX96_, stepAmountIn_, stepAmountOut_) = _computeSwapStepForSwapOutWithoutFee(
            sqrtPriceNextX96_,
            params_.sqrtPriceTargetX96,
            params_.liquidity,
            params_.amountOutRemaining
        );
        // params_.amountOutRemaining -= stepAmountOut_; // This was not needed here as params_.amountOutRemaining is not used further

        unchecked {
            // added this check for safety because we are using unchecked, this should ideally never happen though
            if (stepAmountIn_ > X86) revert FluidDexV2D3D4Error(ErrorTypes.Helpers__AmountInOverflow);
            uint256 stepAmountInWithFee_ = stepAmountIn_;
            if (params_.dynamicFeeVariables.maxFee > 0) {
                stepAmountInWithFee_ = (((stepAmountIn_ * SIX_DECIMALS) + 1) / (SIX_DECIMALS - params_.dynamicFeeVariables.maxFee)) + 1;
            }
            uint256 stepLpFeeAmount_ = stepAmountInWithFee_ - stepAmountIn_;
            
            if (params_.protocolFee > 0) {
                stepAmountInWithFee_ = (((stepAmountInWithFee_ * SIX_DECIMALS) + 1) / (SIX_DECIMALS - params_.protocolFee)) + 1;
            }
            uint256 stepProtocolFeeAmount_ = stepAmountInWithFee_ - stepAmountIn_ - stepLpFeeAmount_;

            amountIn_ += stepAmountInWithFee_;
            amountOut_ += stepAmountOut_;
            lpFeeAmount_ += stepLpFeeAmount_;
            protocolFeeAmount_ += stepProtocolFeeAmount_;
        }
    }

    /// @notice Finds the next initialized tick based on swap direction
    /// @param dexType_ The type of the DEX
    /// @param dexId_ The ID of the DEX
    /// @param tick_ The starting tick
    /// @param tickSpacing_ The spacing between usable ticks
    /// @param swap0To1_ The direction of the swap (true for token0 to token1, false for token1 to token0)
    /// @return nextTick The next initialized or uninitialized tick up to 256 ticks away from the current tick
    /// @return initialized Whether the next tick is initialized
    function _nextInitializedTickWithinOneWord(
        uint256 dexType_,
        bytes32 dexId_,
        int24 tick_,
        uint24 tickSpacing_,
        bool swap0To1_
    ) internal view returns (int24 nextTick, bool initialized) {
        unchecked {
            // Compress the tick to align with tick spacing
            int24 compressed = tick_ / int24(tickSpacing_);
            if (tick_ < 0 && tick_ % int24(tickSpacing_) != 0) compressed--;

            if (swap0To1_) {
                // Calculate bit position
                uint8 bitPos = uint8(uint24(compressed) % 256);

                // all the 1s at or to the right of the current bitPos
                uint256 masked = (_tickBitmap[dexType_][dexId_][int16(compressed >> 8)]) & (type(uint256).max >> (uint256(type(uint8).max) - bitPos));

                // if there are no initialized ticks to the right of or at the current tick, return rightmost in the word
                initialized = masked != 0;
                // overflow/underflow is possible, but prevented externally by limiting both tickSpacing and tick
                nextTick = initialized
                    ? (compressed - int24(uint24(bitPos - (BM.mostSignificantBit(masked) - 1)))) * int24(tickSpacing_) // -1 because our library indexing is from 1-256 not 0-255
                    : (compressed - int24(uint24(bitPos))) * int24(tickSpacing_);
            } else {
                // start from the word of the next tick, since the current tick state doesn't matter
                compressed++;

                // Calculate bit position
                uint8 bitPos = uint8(uint24(compressed) % 256);

                // all the 1s at or to the left of the bitPos
                uint256 masked = (_tickBitmap[dexType_][dexId_][int16(compressed >> 8)]) & (~((uint256(1) << bitPos) - 1));

                // if there are no initialized ticks to the left of the current tick, return leftmost in the word
                initialized = masked != 0;
                // overflow/underflow is possible, but prevented externally by limiting both tickSpacing and tick
                nextTick = initialized
                    ? (compressed + int24(uint24((BM.leastSignificantBit(masked) - 1) - bitPos))) * int24(tickSpacing_) // -1 because our library indexing is from 1-256 not 0-255
                    : (compressed + int24(uint24(type(uint8).max - bitPos))) * int24(tickSpacing_);
            }
        }
    }

    function _validateLPFee(uint24 lpFee_) internal pure returns (uint24) {
        // If lpFee is DYNAMIC_FEE_FLAG (i.e. type(uint24).max), then it is a dynamic fee pool and we return 0 (initial lp fee for dynamic fee pools is zero)
        if (lpFee_ == DYNAMIC_FEE_FLAG) {
            return 0;
        }
        if (lpFee_ > X16) revert FluidDexV2D3D4Error(ErrorTypes.Helpers__LpFeeInvalid);
        return lpFee_;
    }
}
