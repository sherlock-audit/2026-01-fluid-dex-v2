// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;
import "./variables.sol";
import { FixedPointMathLib } from "solmate/src/utils/FixedPointMathLib.sol";
import { AddressCalcs } from "../../../../../libraries/addressCalcs.sol";
import { BigMathMinified } from "../../../../../libraries/bigMathMinified.sol";

abstract contract CommonHelpers is CommonVariables {
    using BigMathMinified for uint256;

    function calculateNumeratorAndDenominatorPrecisions(uint256 decimals_) internal pure returns (uint256 numerator_, uint256 denominator_) {
        if (decimals_ > TOKENS_DECIMALS_PRECISION) {
            numerator_ = 1;
            denominator_ = 10 ** (decimals_ - TOKENS_DECIMALS_PRECISION);
        } else {
            numerator_ = 10 ** (TOKENS_DECIMALS_PRECISION - decimals_);
            denominator_ = 1;
        }
    }

    /// @dev Given an input amount of asset and pair reserves, returns the maximum output amount of the other asset
    /// @param amountIn_ The amount of input asset.
    /// @param iReserveIn_ Imaginary token reserve with input amount.
    /// @param iReserveOut_ Imaginary token reserve of output amount.
    function _getAmountOut(uint256 amountIn_, uint256 iReserveIn_, uint256 iReserveOut_) internal pure returns (uint256 amountOut_) {
        unchecked {
            // Both numerator and denominator are scaled to 1e6 to factor in fee scaling.
            uint256 numerator_ = amountIn_ * iReserveOut_;
            uint256 denominator_ = iReserveIn_ + amountIn_;

            // Using the swap formula: (AmountIn * iReserveY) / (iReserveX + AmountIn)
            amountOut_ = numerator_ / denominator_;
        }
    }

    /// @dev Given an output amount of asset and pair reserves, returns the input amount of the other asset
    /// @param amountOut_ Desired output amount of the asset.
    /// @param iReserveIn_ Imaginary token reserve of input amount.
    /// @param iReserveOut_ Imaginary token reserve of output amount.
    function _getAmountIn(uint256 amountOut_, uint256 iReserveIn_, uint256 iReserveOut_) internal pure returns (uint256 amountIn_) {
        // Both numerator and denominator are scaled to 1e6 to factor in fee scaling.
        uint256 numerator_ = amountOut_ * iReserveIn_;
        uint256 denominator_ = iReserveOut_ - amountOut_;

        // Using the swap formula: (AmountOut * iReserveX) / (iReserveY - AmountOut)
        amountIn_ = numerator_ / denominator_;
    }

    function _verifySwapAndNonPerfectActions(uint256 amountAdjusted_, uint256 amount_) internal pure {
        // after shifting amount should not become 0
        // limiting to six decimals which means in case of USDC, USDT it's 1 wei, for WBTC 100 wei, for ETH 1000 gwei
        if (amountAdjusted_ < SIX_DECIMALS || amountAdjusted_ > X96 || amount_ < TWO_DECIMALS || amount_ > X128) revert(); // FluidDexError(ErrorTypes.DexT1__LimitingAmountsSwapAndNonPerfectActions);
    }

    /// @dev if token0 reserves are too low w.r.t token1 then revert, this is to avoid edge case scenario and making sure that precision on calculations should be high enough
    function _verifyToken0Reserves(uint256 token0Reserves_, uint256 token1Reserves_, uint256 centerPrice_, uint256 minLiquidity_) internal pure {
        if (((token0Reserves_) < ((token1Reserves_ * 1e27) / (centerPrice_ * minLiquidity_)))) {
            revert(); // FluidDexError(ErrorTypes.DexT1__TokenReservesTooLow);
        }
    }

    /// @dev if token1 reserves are too low w.r.t token0 then revert, this is to avoid edge case scenario and making sure that precision on calculations should be high enough
    function _verifyToken1Reserves(uint256 token0Reserves_, uint256 token1Reserves_, uint256 centerPrice_, uint256 minLiquidity_) internal pure {
        if (((token1Reserves_) < ((token0Reserves_ * centerPrice_) / (1e27 * minLiquidity_)))) {
            revert(); //FluidDexError(ErrorTypes.DexT1__TokenReservesTooLow);
        }
    }

    /// @dev This function calculates the new value of a parameter after a shifting process.
    /// @param current_ The current value is the final value where the shift ends
    /// @param old_ The old value from where shifting started.
    /// @param timePassed_ The time passed since shifting started.
    /// @param shiftDuration_ The total duration of the shift when old_ reaches current_
    /// @return The new value of the parameter after the shift.
    function _calcShiftingDone(uint256 current_, uint256 old_, uint256 timePassed_, uint256 shiftDuration_) internal pure returns (uint256) {
        if (current_ > old_) {
            uint256 diff_ = current_ - old_;
            current_ = old_ + ((diff_ * timePassed_) / shiftDuration_);
        } else {
            uint256 diff_ = old_ - current_;
            current_ = old_ - ((diff_ * timePassed_) / shiftDuration_);
        }
        return current_;
    }

    /// @dev Calculates the new upper and lower range values during an active range shift
    /// @param upperRange_ The target upper range value
    /// @param lowerRange_ The target lower range value
    /// @param dexVariables2_ needed in case shift is ended and we need to update dexVariables2
    /// @return The updated upper range, lower range, and dexVariables2
    /// @notice This function handles the gradual shifting of range values over time
    /// @notice If the shift is complete, it updates the state and clears the shift data
    function _calcRangeShifting(
        uint256 upperRange_,
        uint256 lowerRange_,
        uint256 dexVariables2_,
        uint256 dexType_,
        bytes32 dexId_
    ) internal returns (uint256, uint256, uint256) {
        uint256 rangeShift_ = _rangeAndThresholdShift[dexType_][dexId_] & X128;
        uint256 oldUpperRange_ = rangeShift_ & X20;
        uint256 oldLowerRange_ = (rangeShift_ >> 20) & X20;
        uint256 shiftDuration_ = (rangeShift_ >> 40) & X20;
        uint256 startTimeStamp_ = ((rangeShift_ >> 60) & X33);
        if ((startTimeStamp_ + shiftDuration_) < block.timestamp) {
            // shifting fully done
            _rangeAndThresholdShift[dexType_][dexId_] &= ~X128;
            // making active shift as 0 because shift is over
            // fetching from storage and storing in storage, aside from admin module dexVariables2 only updates from this function and _calcThresholdShifting.
            dexVariables2_ = _dexVariables2[dexType_][dexId_] & ~uint256(1 << 26);
            _dexVariables2[dexType_][dexId_] = dexVariables2_;
            return (upperRange_, lowerRange_, dexVariables2_);
        }
        uint256 timePassed_ = block.timestamp - startTimeStamp_;
        return (
            _calcShiftingDone(upperRange_, oldUpperRange_, timePassed_, shiftDuration_),
            _calcShiftingDone(lowerRange_, oldLowerRange_, timePassed_, shiftDuration_),
            dexVariables2_
        );
    }

    /// @dev Calculates the new upper and lower threshold values during an active threshold shift
    /// @param upperThreshold_ The target upper threshold value
    /// @param lowerThreshold_ The target lower threshold value
    /// @param thresholdTime_ The time passed since shifting started
    /// @return The updated upper threshold, lower threshold, and threshold time
    /// @notice This function handles the gradual shifting of threshold values over time
    /// @notice If the shift is complete, it updates the state and clears the shift data
    function _calcThresholdShifting(
        uint256 upperThreshold_,
        uint256 lowerThreshold_,
        uint256 thresholdTime_,
        uint256 dexType_,
        bytes32 dexId_
    ) internal returns (uint256, uint256, uint256) {
        uint256 thresholdShift_ = _rangeAndThresholdShift[dexType_][dexId_] >> 128;
        uint256 oldUpperThreshold_ = thresholdShift_ & X20;
        uint256 oldLowerThreshold_ = (thresholdShift_ >> 20) & X20;
        uint256 shiftDuration_ = (thresholdShift_ >> 40) & X20;
        uint256 startTimeStamp_ = ((thresholdShift_ >> 60) & X33);
        uint256 oldThresholdTime_ = (thresholdShift_ >> 93) & X24;
        if ((startTimeStamp_ + shiftDuration_) < block.timestamp) {
            // shifting fully done
            _rangeAndThresholdShift[dexType_][dexId_] &= ~(X128 << 128);
            // making active shift as 0 because shift is over
            // fetching from storage and storing in storage, aside from admin module dexVariables2 only updates from this function and _calcRangeShifting.
            _dexVariables2[dexType_][dexId_] = _dexVariables2[dexType_][dexId_] & ~uint256(1 << 67);
            return (upperThreshold_, lowerThreshold_, thresholdTime_);
        }
        uint256 timePassed_ = block.timestamp - startTimeStamp_;
        return (
            _calcShiftingDone(upperThreshold_, oldUpperThreshold_, timePassed_, shiftDuration_),
            _calcShiftingDone(lowerThreshold_, oldLowerThreshold_, timePassed_, shiftDuration_),
            _calcShiftingDone(thresholdTime_, oldThresholdTime_, timePassed_, shiftDuration_)
        );
    }

    /// @dev Calculates the new center price during an active price shift
    /// @param dexVariables_ The current state of dex variables
    /// @param dexVariables2_ Additional dex variables
    /// @return newCenterPrice_ The updated center price
    /// @notice This function gradually shifts the center price towards a new target price over time
    /// @notice It uses an external price source (via ICenterPrice) to determine the target price
    /// @notice The shift continues until the current price reaches the target, or the shift duration ends
    /// @notice Once the shift is complete, it updates the state and clears the shift data
    /// @notice The shift rate is dynamic and depends on:
    /// @notice - Time remaining in the shift duration
    /// @notice - The new center price (fetched externally, which may change)
    /// @notice - The current (old) center price
    /// @notice This results in a fuzzy shifting mechanism where the rate can change as these parameters evolve
    /// @notice The externally fetched new center price is expected to not differ significantly from the last externally fetched center price
    function _calcCenterPrice(
        DexKey memory dexKey_,
        uint256 dexVariables_,
        uint256 dexVariables2_,
        uint256 dexType_,
        bytes32 dexId_
    ) internal returns (uint256 newCenterPrice_) {
        uint256 oldCenterPrice_ = (dexVariables_ >> 81) & X40;
        oldCenterPrice_ = (oldCenterPrice_ >> DEFAULT_EXPONENT_SIZE) << (oldCenterPrice_ & DEFAULT_EXPONENT_MASK);
        uint256 centerPriceShift_ = _centerPriceShift[dexType_][dexId_];
        uint256 startTimeStamp_ = centerPriceShift_ & X33;
        uint256 percent_ = (centerPriceShift_ >> 33) & X20;
        uint256 time_ = (centerPriceShift_ >> 53) & X20;

        uint256 fromTimeStamp_ = (dexVariables_ >> 121) & X33;
        fromTimeStamp_ = fromTimeStamp_ > startTimeStamp_ ? fromTimeStamp_ : startTimeStamp_;

        newCenterPrice_ = ICenterPrice(AddressCalcs.addressCalc(DEPLOYER_CONTRACT, ((dexVariables2_ >> 112) & X30))).centerPrice(
            dexKey_.token0,
            dexKey_.token1,
            bytes("0x")
        );
        uint256 priceShift_ = (oldCenterPrice_ * percent_ * (block.timestamp - fromTimeStamp_)) / (time_ * SIX_DECIMALS);

        if (newCenterPrice_ > oldCenterPrice_) {
            // shift on positive side
            oldCenterPrice_ += priceShift_;
            if (newCenterPrice_ > oldCenterPrice_) {
                newCenterPrice_ = oldCenterPrice_;
            } else {
                // shifting fully done
                delete _centerPriceShift[dexType_][dexId_];
                // making active shift as 0 because shift is over
                // fetching from storage and storing in storage, aside from admin module dexVariables2 only updates these shift function.
                _dexVariables2[dexType_][dexId_] = _dexVariables2[dexType_][dexId_] & ~uint256(1 << 248);
            }
        } else {
            unchecked {
                oldCenterPrice_ = oldCenterPrice_ > priceShift_ ? oldCenterPrice_ - priceShift_ : 0;
                // In case of oldCenterPrice_ ending up 0, which could happen when a lot of time has passed (pool has no swaps for many days or weeks)
                // then below we get into the else logic which will fully conclude shifting and return newCenterPrice_
                // as it was fetched from the external center price source.
                // not ideal that this would ever happen unless the pool is not in use and all/most users have left leaving not enough liquidity to trade on
            }
            if (newCenterPrice_ < oldCenterPrice_) {
                newCenterPrice_ = oldCenterPrice_;
            } else {
                // shifting fully done
                delete _centerPriceShift[dexType_][dexId_];
                // making active shift as 0 because shift is over
                // fetching from storage and storing in storage, aside from admin module dexVariables2 only updates these shift function.
                _dexVariables2[dexType_][dexId_] = _dexVariables2[dexType_][dexId_] & ~uint256(1 << 248);
            }
        }
    }

    /// @notice Calculates and returns the current prices and exchange prices for the pool
    /// @param dexVariables_ The first set of DEX variables containing various pool parameters
    /// @param dexVariables2_ The second set of DEX variables containing additional pool parameters
    /// @return prices_ A struct containing the calculated prices
    /// @dev This function performs the following operations:
    ///      1. Determines the center price (either from storage, external source, or calculated)
    ///      2. Retrieves the last stored price from dexVariables_
    ///      3. Calculates the upper and lower range prices based on the center price and range percentages
    ///      4. Checks if rebalancing is needed based on threshold settings
    ///      5. Adjusts prices if necessary based on the time elapsed and threshold conditions
    ///      6. Update the dexVariables2_ if changes were made
    function _getPrices(
        DexKey memory dexKey_,
        uint256 dexVariables_,
        uint256 dexVariables2_,
        uint256 dexType_,
        bytes32 dexId_
    ) internal returns (Prices memory prices_) {
        uint256 centerPrice_;

        if (((dexVariables2_ >> 248) & 1) == 0) {
            // centerPrice_ => center price hook
            centerPrice_ = (dexVariables2_ >> 112) & X30;
            if (centerPrice_ == 0) {
                centerPrice_ = (dexVariables_ >> 81) & X40;
                centerPrice_ = (centerPrice_ >> DEFAULT_EXPONENT_SIZE) << (centerPrice_ & DEFAULT_EXPONENT_MASK);
            } else {
                // center price should be fetched from external source. For exmaple, in case of wstETH <> ETH pool,
                // we would want the center price to be pegged to wstETH exchange rate into ETH
                centerPrice_ = ICenterPrice(AddressCalcs.addressCalc(DEPLOYER_CONTRACT, centerPrice_)).centerPrice(dexKey_.token0, dexKey_.token1, bytes("0x"));
            }
        } else {
            // an active centerPrice_ shift is going on
            centerPrice_ = _calcCenterPrice(dexKey_, dexVariables_, dexVariables2_, dexType_, dexId_);
        }

        uint256 lastStoredPrice_ = (dexVariables_ >> 41) & X40;
        lastStoredPrice_ = (lastStoredPrice_ >> DEFAULT_EXPONENT_SIZE) << (lastStoredPrice_ & DEFAULT_EXPONENT_MASK);

        uint256 upperRange_ = ((dexVariables2_ >> 27) & X20);
        uint256 lowerRange_ = ((dexVariables2_ >> 47) & X20);
        if (((dexVariables2_ >> 26) & 1) == 1) {
            // an active range shift is going on
            (upperRange_, lowerRange_, dexVariables2_) = _calcRangeShifting(upperRange_, lowerRange_, dexVariables2_, dexType_, dexId_);
        }

        unchecked {
            // adding into unchecked because upperRange_ & lowerRange_ can only be > 0 & < SIX_DECIMALS
            // 1% = 1e4, 100% = 1e6
            upperRange_ = (centerPrice_ * SIX_DECIMALS) / (SIX_DECIMALS - upperRange_);
            // 1% = 1e4, 100% = 1e6
            lowerRange_ = (centerPrice_ * (SIX_DECIMALS - lowerRange_)) / SIX_DECIMALS;
        }

        bool changed_;
        {
            // goal will be to keep threshold percents 0 if center price is fetched from external source
            // checking if threshold are set non 0 then only rebalancing is on
            if (((dexVariables2_ >> 68) & X20) > 0) {
                uint256 upperThreshold_ = (dexVariables2_ >> 68) & X10;
                uint256 lowerThreshold_ = (dexVariables2_ >> 78) & X10;
                uint256 shiftingTime_ = (dexVariables2_ >> 88) & X24;
                if (((dexVariables2_ >> 67) & 1) == 1) {
                    // if active shift is going on for threshold then calculate threshold real time
                    (upperThreshold_, lowerThreshold_, shiftingTime_) = _calcThresholdShifting(upperThreshold_, lowerThreshold_, shiftingTime_, dexType_, dexId_);
                }

                unchecked {
                    if (lastStoredPrice_ > (centerPrice_ + ((upperRange_ - centerPrice_) * (THREE_DECIMALS - upperThreshold_)) / THREE_DECIMALS)) {
                        uint256 timeElapsed_ = block.timestamp - ((dexVariables_ >> 121) & X33);
                        // price shifting towards upper range
                        if (timeElapsed_ < shiftingTime_) {
                            centerPrice_ = centerPrice_ + ((upperRange_ - centerPrice_) * timeElapsed_) / shiftingTime_;
                        } else {
                            // 100% price shifted
                            centerPrice_ = upperRange_;
                        }
                        changed_ = true;
                    } else if (lastStoredPrice_ < (centerPrice_ - ((centerPrice_ - lowerRange_) * (THREE_DECIMALS - lowerThreshold_)) / THREE_DECIMALS)) {
                        uint256 timeElapsed_ = block.timestamp - ((dexVariables_ >> 121) & X33);
                        // price shifting towards lower range
                        if (timeElapsed_ < shiftingTime_) {
                            centerPrice_ = centerPrice_ - ((centerPrice_ - lowerRange_) * timeElapsed_) / shiftingTime_;
                        } else {
                            // 100% price shifted
                            centerPrice_ = lowerRange_;
                        }
                        changed_ = true;
                    }
                }
            }
        }

        // temp_ => max center price
        uint256 temp_ = (dexVariables2_ >> 172) & X28;
        temp_ = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);
        if (centerPrice_ > temp_) {
            // if center price is greater than max center price
            centerPrice_ = temp_;
            changed_ = true;
        } else {
            // check if center price is less than min center price
            // temp_ => min center price
            temp_ = (dexVariables2_ >> 200) & X28;
            temp_ = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);
            if (centerPrice_ < temp_) {
                centerPrice_ = temp_;
                changed_ = true;
            }
        }

        // if centerPrice_ is changed then calculating upper and lower range again
        if (changed_) {
            upperRange_ = ((dexVariables2_ >> 27) & X20);
            lowerRange_ = ((dexVariables2_ >> 47) & X20);
            if (((dexVariables2_ >> 26) & 1) == 1) {
                (upperRange_, lowerRange_, dexVariables2_) = _calcRangeShifting(upperRange_, lowerRange_, dexVariables2_, dexType_, dexId_);
            }

            unchecked {
                // adding into unchecked because upperRange_ & lowerRange_ can only be > 0 & < SIX_DECIMALS
                // 1% = 1e4, 100% = 1e6
                upperRange_ = (centerPrice_ * SIX_DECIMALS) / (SIX_DECIMALS - upperRange_);
                // 1% = 1e4, 100% = 1e6
                lowerRange_ = (centerPrice_ * (SIX_DECIMALS - lowerRange_)) / SIX_DECIMALS;
            }
        }

        prices_.lastStoredPrice = lastStoredPrice_;
        prices_.centerPrice = centerPrice_;
        prices_.upperRange = upperRange_;
        prices_.lowerRange = lowerRange_;

        unchecked {
            if (upperRange_ < 1e38) {
                // 1e38 * 1e38 = 1e76 which is less than max uint256 limit
                prices_.geometricMean = FixedPointMathLib.sqrt(upperRange_ * lowerRange_);
            } else {
                // upperRange_ price is pretty large hence lowerRange_ will also be pretty large
                prices_.geometricMean = FixedPointMathLib.sqrt((upperRange_ / 1e18) * (lowerRange_ / 1e18)) * 1e18;
            }
        }
    }

    function _priceDiffCheck(uint256 oldPrice_, uint256 newPrice_) internal pure returns (int priceDiff_) {
        // check newPrice_ & oldPrice_ difference should not be more than 5%
        // old price w.r.t new price
        priceDiff_ = int(ORACLE_PRECISION) - int((oldPrice_ * ORACLE_PRECISION) / newPrice_);

        unchecked {
            if ((priceDiff_ > int(ORACLE_LIMIT)) || (priceDiff_ < -int(ORACLE_LIMIT))) {
                // if oracle price difference is more than 5% then revert
                // in 1 swap price should only change by <= 5%
                // if a total fall by let's say 8% then in current block price can only fall by 5% and
                // in next block it'll fall the remaining 3%
                revert(); //FluidDexError(ErrorTypes.DexT1__OracleUpdateHugeSwapDiff);
            }
        }
    }

    function _updateDexVariables(uint256 newPrice_, uint256 centerPrice_, uint256 dexVariables_) internal view returns (uint256) {
        // time difference between last & current swap
        uint256 timeDiff_ = block.timestamp - ((dexVariables_ >> 121) & X33);
        uint256 temp_;

        if (timeDiff_ == 0) {
            // doesn't matter if oracle is on or off when timediff = 0 code for both is same

            // temp_ => oldCenterPrice
            temp_ = (dexVariables_ >> 81) & X40;
            temp_ = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);

            // Ensure that the center price is within the acceptable range of the old center price if it's not the first swap in the same block
            unchecked {
                if ((centerPrice_ < (((EIGHT_DECIMALS - 1) * temp_) / EIGHT_DECIMALS)) || (centerPrice_ > (((EIGHT_DECIMALS + 1) * temp_) / EIGHT_DECIMALS))) {
                    revert(); // TODO: add error
                }
            }

            // olderPrice_ => temp_
            temp_ = (dexVariables_ >> 1) & X40;
            temp_ = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);

            _priceDiffCheck(temp_, newPrice_);

            // 2nd swap in same block no need to update anything around oracle, only need to update last swap price in dexVariables
            return ((dexVariables_ & 0xfffffffffffffffffffffffffffffffffffffffffffe0000000001ffffffffff) |
                (newPrice_.toBigNumber(32, 8, BigMathMinified.ROUND_DOWN) << 41));
        }

        temp_ = ((dexVariables_ >> 41) & X40);
        temp_ = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);

        _priceDiffCheck(temp_, newPrice_);

        return ((dexVariables_ & 0xfffffffffffffffffffffffffc00000000000000000000000000000000000001) |
            (((dexVariables_ >> 41) & X40) << 1) |
            (newPrice_.toBigNumber(32, 8, BigMathMinified.ROUND_DOWN) << 41) |
            (centerPrice_.toBigNumber(32, 8, BigMathMinified.ROUND_DOWN) << 81) |
            (block.timestamp << 121));
    }

    function _hookVerify(DexKey calldata dexKey_, uint256 hookAddress_, uint256 mode_, bool swap0To1_, uint256 price_) internal {
        try IHook(AddressCalcs.addressCalc(DEPLOYER_CONTRACT, hookAddress_)).dexPrice(mode_, swap0To1_, dexKey_.token0, dexKey_.token1, price_) returns (
            bool isOk_
        ) {
            if (!isOk_) revert(); // FluidDexError(ErrorTypes.DexT1__HookReturnedFalse);
        } catch (bytes memory /*lowLevelData*/) {
            // skip checking hook nothing
        }
    }

    function _verifyMint(uint256 amt_, uint256 totalAmt_) internal pure {
        // not minting too less shares or too more
        // If totalAmt_ is worth $1 then user can at max mint $1B of new amt_ at once.
        // If totalAmt_ is worth $1B then user have to mint min of $1 of amt_.
        if (amt_ < (totalAmt_ / NINE_DECIMALS) || amt_ > (totalAmt_ * NINE_DECIMALS)) {
            revert(); // FluidDexError(ErrorTypes.DexT1__MintAmtOverflow);
        }
    }

    function _verifyRedeem(uint256 amt_, uint256 totalAmt_) internal pure {
        // If burning of amt_ is > 99.99% of totalAmt_ or if amt_ is less than totalAmt_ / 1e9 then revert.
        if (amt_ > ((totalAmt_ * 9999) / FOUR_DECIMALS) || (amt_ < (totalAmt_ / NINE_DECIMALS))) {
            revert(); // FluidDexError(ErrorTypes.DexT1__BurnAmtOverflow);
        }
    }
}
