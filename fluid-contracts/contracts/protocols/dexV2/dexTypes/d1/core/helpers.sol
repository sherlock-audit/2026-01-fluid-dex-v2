// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import "../other/commonImport.sol";
// import { ErrorTypes } from "../../../errorTypes.sol"; // TODO: Update all reverts

import { SafeTransfer } from "../../../../../libraries/safeTransfer.sol";
import { LiquiditySlotsLink } from "../../../../../libraries/liquiditySlotsLink.sol";
import { LiquidityCalcs } from "../../../../../libraries/liquidityCalcs.sol";
import { DexSlotsLink } from "../../../../../libraries/dexSlotsLink.sol";
import { DexCalcs } from "../../../../../libraries/dexCalcs.sol";

abstract contract Helpers is CommonImportD1Other {
    using BigMathMinified for uint256;

    function _setTotalSupplyRaw(bytes32 dexId_, uint256 token0TotalSupplyRaw_, uint256 token1TotalSupplyRaw_) internal {
        // TODO
    }

    function _getTotalSupplyRaw(bytes32 dexId_) internal view returns (uint256 token0TotalSupplyRaw_, uint256 token1TotalSupplyRaw_) {
        // TODO
    }

    function _calculateVars(address token0_, address token1_, uint256 dexVariables2_, bytes32 dexId_) internal view returns (CalculatedVars memory calculatedVars_) {
        uint256 token0Decimals_ = (dexVariables2_ >> 228) & X5;
        uint256 token1Decimals_ = (dexVariables2_ >> 233) & X5;

        (calculatedVars_.token0NumeratorPrecision, calculatedVars_.token0DenominatorPrecision) = calculateNumeratorAndDenominatorPrecisions(token0Decimals_);
        (calculatedVars_.token1NumeratorPrecision, calculatedVars_.token1DenominatorPrecision) = calculateNumeratorAndDenominatorPrecisions(token1Decimals_);

        // Exchange price will remain same as Liquidity Layer
        (calculatedVars_.token0SupplyExchangePrice, ) = LiquidityCalcs.calcExchangePrices(
            LIQUIDITY.readFromStorage(LiquiditySlotsLink.calculateMappingStorageSlot(LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT, token0_))
        );

        (calculatedVars_.token1SupplyExchangePrice, ) = LiquidityCalcs.calcExchangePrices(
            LIQUIDITY.readFromStorage(LiquiditySlotsLink.calculateMappingStorageSlot(LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT, token1_))
        );

        (calculatedVars_.token0TotalSupplyRaw, calculatedVars_.token1TotalSupplyRaw) = _getTotalSupplyRaw(dexId_);
        uint256 token0TotalSupply_ = (calculatedVars_.token0TotalSupplyRaw * calculatedVars_.token0SupplyExchangePrice) / LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
        uint256 token1TotalSupply_ = (calculatedVars_.token1TotalSupplyRaw * calculatedVars_.token1SupplyExchangePrice) / LiquidityCalcs.EXCHANGE_PRICES_PRECISION;

        calculatedVars_.token0TotalSupplyAdjusted = (token0TotalSupply_ * calculatedVars_.token0NumeratorPrecision) / calculatedVars_.token0DenominatorPrecision;
        calculatedVars_.token1TotalSupplyAdjusted = (token1TotalSupply_ * calculatedVars_.token1NumeratorPrecision) / calculatedVars_.token1DenominatorPrecision;
    }

    /// @dev getting reserves outside range.
    /// @param gp_ is geometric mean pricing of upper percent & lower percent
    /// @param pa_ price of upper range or lower range
    /// @param rx_ real reserves of token0 or token1
    /// @param ry_ whatever is rx_ the other will be ry_
    function _calculateReservesOutsideRange(uint256 gp_, uint256 pa_, uint256 rx_, uint256 ry_) internal pure returns (uint256 xa_, uint256 yb_) {
        // equations we have:
        // 1. x*y = k
        // 2. xa*ya = k
        // 3. xb*yb = k
        // 4. Pa = ya / xa = upperRange_ (known)
        // 5. Pb = yb / xb = lowerRange_ (known)
        // 6. x - xa = rx = real reserve of x (known)
        // 7. y - yb = ry = real reserve of y (known)
        // With solving we get:
        // ((Pa*Pb)^(1/2) - Pa)*xa^2 + (rx * (Pa*Pb)^(1/2) + ry)*xa + rx*ry = 0
        // yb = yb = xa * (Pa * Pb)^(1/2)

        // xa = (GP⋅rx + ry + (-rx⋅ry⋅4⋅(GP - Pa) + (GP⋅rx + ry)^2)^0.5) / (2Pa - 2GP)
        // multiply entire equation by 1e27 to remove the price decimals precision of 1e27
        // xa = (GP⋅rx + ry⋅1e27 + (rx⋅ry⋅4⋅(Pa - GP)⋅1e27 + (GP⋅rx + ry⋅1e27)^2)^0.5) / 2*(Pa - GP)
        // dividing the equation with 2*(Pa - GP). Pa is always > GP so answer will be positive.
        // xa = (((GP⋅rx + ry⋅1e27) / 2*(Pa - GP)) + (((rx⋅ry⋅4⋅(Pa - GP)⋅1e27) / 4*(Pa - GP)^2) + ((GP⋅rx + ry⋅1e27) / 2*(Pa - GP))^2)^0.5)
        // xa = (((GP⋅rx + ry⋅1e27) / 2*(Pa - GP)) + (((rx⋅ry⋅1e27) / (Pa - GP)) + ((GP⋅rx + ry⋅1e27) / 2*(Pa - GP))^2)^0.5)

        // dividing in 3 parts for simplification:
        // part1 = (Pa - GP)
        // part2 = (GP⋅rx + ry⋅1e27) / (2*part1)
        // part3 = rx⋅ry
        // note: part1 will almost always be < 1e28 but in case it goes above 1e27 then it's extremely unlikely it'll go above > 1e29
        uint256 p1_ = pa_ - gp_;
        uint256 p2_ = ((gp_ * rx_) + (ry_ * 1e27)) / (2 * p1_);
        uint256 p3_ = rx_ * ry_;
        // to avoid overflowing
        p3_ = (p3_ < 1e50) ? ((p3_ * 1e27) / p1_) : (p3_ / p1_) * 1e27;

        // xa = part2 + (part3 + (part2 * part2))^(1/2)
        // yb = xa_ * gp_
        xa_ = p2_ + FixedPointMathLib.sqrt((p3_ + (p2_ * p2_)));
        yb_ = (xa_ * gp_) / 1e27;
    }

    /// @notice Calculates the real and imaginary reserves for collateral tokens
    /// @dev This function retrieves the supply of both tokens from the liquidity layer,
    ///      adjusts them based on exchange prices, and calculates imaginary reserves
    ///      based on the geometric mean and price range
    /// @param geometricMean_ The geometric mean of the token prices
    /// @param upperRange_ The upper price range
    /// @param lowerRange_ The lower price range
    /// @param token0Supply_ The supply of token0
    /// @param token1Supply_ The supply of token1
    /// @return c_ A struct containing the calculated real and imaginary reserves for both tokens:
    ///         - token0RealReserves: The real reserves of token0
    ///         - token1RealReserves: The real reserves of token1
    ///         - token0ImaginaryReserves: The imaginary reserves of token0
    ///         - token1ImaginaryReserves: The imaginary reserves of token1
    function _getCollateralReserves(
        uint256 geometricMean_,
        uint256 upperRange_,
        uint256 lowerRange_,
        uint256 token0Supply_,
        uint256 token1Supply_
    ) internal pure returns (CollateralReserves memory c_) {
        if (geometricMean_ < 1e27) {
            (c_.token0ImaginaryReserves, c_.token1ImaginaryReserves) = _calculateReservesOutsideRange(geometricMean_, upperRange_, token0Supply_, token1Supply_);
        } else {
            // inversing, something like `xy = k` so for calculation we are making everything related to x into y & y into x
            // 1 / geometricMean for new geometricMean
            // 1 / lowerRange will become upper range
            // 1 / upperRange will become lower range
            (c_.token1ImaginaryReserves, c_.token0ImaginaryReserves) = _calculateReservesOutsideRange(
                (1e54 / geometricMean_),
                (1e54 / lowerRange_),
                token1Supply_,
                token0Supply_
            );
        }

        c_.token0RealReserves = token0Supply_;
        c_.token1RealReserves = token1Supply_;
        unchecked {
            c_.token0ImaginaryReserves += token0Supply_;
            c_.token1ImaginaryReserves += token1Supply_;
        }
    }

    function _updateSupplyShares(uint256 newTotalShares_, bytes32 dexId_) internal {
        uint256 totalSupplyShares_ = _totalSupplyShares[DEX_TYPE][dexId_];

        // new total shares are greater than old total shares && new total shares are greater than max supply shares
        if ((newTotalShares_ > (totalSupplyShares_ & X128)) && newTotalShares_ > (totalSupplyShares_ >> 128)) {
            revert(); // FluidDexError(ErrorTypes.DexT1__SupplySharesOverflow);
        }

        // keeping max supply shares intact
        _totalSupplyShares[DEX_TYPE][dexId_] = ((totalSupplyShares_ >> 128) << 128) | newTotalShares_;
    }

    /// @param c_ tokenA amount to swap and deposit
    /// @param d_ tokenB imaginary reserves
    /// @param e_ tokenA imaginary reserves
    /// @param f_ tokenA real reserves
    /// @param i_ tokenB real reserves
    function _getSwapAndDeposit(uint256 c_, uint256 d_, uint256 e_, uint256 f_, uint256 i_) internal pure returns (uint256 shares_) {
        // swap and deposit in equal proportion

        // tokenAx = c
        // imaginaryTokenBReserves = d
        // imaginaryTokenAReserves = e
        // tokenAReserves = f
        // tokenBReserves = i

        // Quadratic equations, A, B & C are:
        // A = i
        // B = (ie - ic + dc + fd)
        // C = -iec

        // final equation:
        // token to swap = (−(c⋅d−c⋅i+d⋅f+e⋅i) + (4⋅c⋅e⋅i^2 + (c⋅d−c⋅i+d⋅f+e⋅i)^2)^0.5) / 2⋅i
        // B = (c⋅d−c⋅i+d⋅f+e⋅i)
        // token to swap = (−B + (4⋅c⋅e⋅i^2 + (B)^2)^0.5) / 2⋅i
        // simplifying above equation by dividing the entire equation by i:
        // token to swap = (−B/i + (4⋅c⋅e + (B/i)^2)^0.5) / 2
        // note: d > i always, so dividing won't be an issue

        // temp_ => B/i
        uint256 temp_ = (c_ * d_ + d_ * f_ + e_ * i_ - c_ * i_) / i_;
        uint256 temp2_ = 4 * c_ * e_;
        uint256 amtToSwap_ = (FixedPointMathLib.sqrt((temp2_ + (temp_ * temp_))) - temp_) / 2;

        // Ensure the amount to swap is within reasonable bounds:
        // - Not greater than 99.9999% of the input amount (c_)
        // - Not less than 0.0001% of the input amount (c_)
        // This prevents extreme scenarios and maybe potential precision issues
        if ((amtToSwap_ > ((c_ * (SIX_DECIMALS - 1)) / SIX_DECIMALS)) || (amtToSwap_ < (c_ / SIX_DECIMALS))) revert(); // FluidDexError(ErrorTypes.DexT1__SwapAndDepositTooLowOrTooHigh);

        // temp_ => amt0ToDeposit
        temp_ = c_ - amtToSwap_;
        // (imaginaryTokenBReserves * amtToSwap_) / (imaginaryTokenAReserves + amtToSwap_)
        // temp2_ => amt1ToDeposit_
        temp2_ = (d_ * amtToSwap_) / (e_ + amtToSwap_);

        // temp_ => shares1
        temp_ = (temp_ * 1e18) / (f_ + amtToSwap_);
        // temp2_ => shares1
        temp2_ = (temp2_ * 1e18) / (i_ - temp2_);
        // temp_ & temp2 should be same. Although, due to some possible precision loss taking the lower one
        shares_ = temp_ > temp2_ ? temp2_ : temp_;
    }

    /// @notice Updates collateral reserves based on minting or burning of shares
    /// @param newShares_ The number of new shares being minted or burned
    /// @param totalOldShares_ The total number of shares before the operation
    /// @param c_ The current collateral reserves
    /// @param mintOrBurn_ True if minting shares, false if burning shares
    /// @return c2_ The updated collateral reserves after the operation
    function _getUpdatedColReserves(
        uint256 newShares_,
        uint256 totalOldShares_,
        CollateralReserves memory c_,
        bool mintOrBurn_ // true if mint, false if burn
    ) internal pure returns (CollateralReserves memory c2_) {
        if (mintOrBurn_) {
            // If minting, increase reserves proportionally to new shares
            c2_.token0RealReserves = c_.token0RealReserves + (c_.token0RealReserves * newShares_) / totalOldShares_;
            c2_.token1RealReserves = c_.token1RealReserves + (c_.token1RealReserves * newShares_) / totalOldShares_;
            c2_.token0ImaginaryReserves = c_.token0ImaginaryReserves + (c_.token0ImaginaryReserves * newShares_) / totalOldShares_;
            c2_.token1ImaginaryReserves = c_.token1ImaginaryReserves + (c_.token1ImaginaryReserves * newShares_) / totalOldShares_;
        } else {
            // If burning, decrease reserves proportionally to burned shares
            c2_.token0RealReserves = c_.token0RealReserves - ((c_.token0RealReserves * newShares_) / totalOldShares_);
            c2_.token1RealReserves = c_.token1RealReserves - ((c_.token1RealReserves * newShares_) / totalOldShares_);
            c2_.token0ImaginaryReserves = c_.token0ImaginaryReserves - ((c_.token0ImaginaryReserves * newShares_) / totalOldShares_);
            c2_.token1ImaginaryReserves = c_.token1ImaginaryReserves - ((c_.token1ImaginaryReserves * newShares_) / totalOldShares_);
        }
        return c2_;
    }

    /// @param c_ tokenA current real reserves (aka reserves before withdraw & swap)
    /// @param d_ tokenB current real reserves (aka reserves before withdraw & swap)
    /// @param e_ tokenA: final imaginary reserves - real reserves (aka reserves outside range after withdraw & swap)
    /// @param f_ tokenB: final imaginary reserves - real reserves (aka reserves outside range after withdraw & swap)
    /// @param g_ tokenA perfect amount to withdraw
    function _getWithdrawAndSwap(uint256 c_, uint256 d_, uint256 e_, uint256 f_, uint256 g_) internal pure returns (uint256 shares_) {
        // Equations we have:
        // 1. tokenAxa / tokenBxb = tokenAReserves / tokenBReserves (Withdraw in equal proportion)
        // 2. newTokenAReserves = tokenAReserves - tokenAxa
        // 3. newTokenBReserves = tokenBReserves - tokenBxb
        // 4 (known). finalTokenAReserves = tokenAReserves - tokenAx
        // 5 (known). finalTokenBReserves = tokenBReserves

        // Note: Xnew * Ynew = k = Xfinal * Yfinal (Xfinal & Yfinal is final imaginary reserve of token A & B).
        // Now as we know finalTokenAReserves & finalTokenAReserves, hence we can also calculate
        // imaginaryReserveMinusRealReservesA = finalImaginaryAReserves - finalTokenAReserves
        // imaginaryReserveMinusRealReservesB = finalImaginaryBReserves - finalTokenBReserves
        // Swaps only happen on real reserves hence before and after swap imaginaryReserveMinusRealReservesA &
        // imaginaryReserveMinusRealReservesB should have exactly the same value.

        // 6. newImaginaryTokenAReserves = imaginaryReserveMinusRealReservesA + newTokenAReserves
        // newImaginaryTokenAReserves = imaginaryReserveMinusRealReservesA + tokenAReserves - tokenAxa
        // 7. newImaginaryTokenBReserves = imaginaryReserveMinusRealReservesB + newTokenBReserves
        // newImaginaryTokenBReserves = imaginaryReserveMinusRealReservesB + tokenBReserves - tokenBxb
        // 8. tokenAxb = (newImaginaryTokenAReserves * tokenBxb) / (newImaginaryTokenBReserves + tokenBxb)
        // 9. tokenAxa + tokenAxb = tokenAx

        // simplifying knowns in 1 letter to make things clear:
        // c = tokenAReserves
        // d = tokenBReserves
        // e = imaginaryReserveMinusRealReservesA
        // f = imaginaryReserveMinusRealReservesB
        // g = tokenAx

        // A, B, C of quadratic are:
        // A = d
        // B = -(de + 2cd + cf)
        // C = cfg + cdg

        // tokenAxa = ((d⋅e + 2⋅c⋅d + c⋅f) - ((d⋅e + 2⋅c⋅d + c⋅f)^2 - 4⋅d⋅(c⋅f⋅g + c⋅d⋅g))^0.5) / 2d
        // dividing 2d first to avoid overflowing
        // B = (d⋅e + 2⋅c⋅d + c⋅f) / 2d
        // (B - ((B)^2 - (4⋅d⋅(c⋅f⋅g + c⋅d⋅g) / 4⋅d^2))^0.5)
        // (B - ((B)^2 - ((c⋅f⋅g + c⋅d⋅g) / d))^0.5)

        // temp_ = B/2A
        uint256 temp_ = (d_ * e_ + 2 * c_ * d_ + c_ * f_) / (2 * d_);
        // temp2_ = 4AC / 4A^2 = C / A
        // to avoid overflowing in any case multiplying with g_ later
        uint256 temp2_ = (((c_ * f_) / d_) + c_) * g_;

        // tokenAxa = (-B - (B^2 - 4AC)^0.5) / 2A
        uint256 tokenAxa_ = temp_ - FixedPointMathLib.sqrt((temp_ * temp_) - temp2_);

        // Ensure the amount to withdraw is within reasonable bounds:
        // - Not greater than 99.9999% of the input amount (g_)
        // - Not less than 0.0001% of the input amount (g_)
        // This prevents extreme scenarios and maybe potential precision issues
        if (tokenAxa_ > ((g_ * (SIX_DECIMALS - 1)) / SIX_DECIMALS) || tokenAxa_ < (g_ / SIX_DECIMALS)) revert(); // FluidDexError(ErrorTypes.DexT1__WithdrawAndSwapTooLowOrTooHigh);

        shares_ = (tokenAxa_ * 1e18) / c_;
    }

    function _updatingUserSupplyDataOnStorage(uint256 userSupplyData_, uint256 userSupply_, uint256 newWithdrawalLimit_, bytes32 dexId_) internal {
        // calculate withdrawal limit to store as previous withdrawal limit in storage
        newWithdrawalLimit_ = DexCalcs.calcWithdrawalLimitAfterOperate(userSupplyData_, userSupply_, newWithdrawalLimit_);

        userSupply_ = userSupply_.toBigNumber(DEFAULT_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, BigMathMinified.ROUND_DOWN);

        newWithdrawalLimit_ = newWithdrawalLimit_.toBigNumber(DEFAULT_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, BigMathMinified.ROUND_DOWN);

        if (((userSupplyData_ >> DexSlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64) == userSupply_) {
            // make sure that shares amount is not so small that it wouldn't affect storage update. if a difference
            // is present then rounding will be in the right direction to avoid any potential manipulation.
            revert(); // FluidDexError(ErrorTypes.DexT1__SharesAmountInsufficient);
        }

        // Updating on storage, copied exactly the same from Liquidity Layer
        _userSupplyData[DEX_TYPE][dexId_][msg.sender] =
            // mask to update bits 1-161 (supply amount, withdrawal limit, timestamp)
            (userSupplyData_ & 0xfffffffffffffffffffffffc0000000000000000000000000000000000000001) |
            (userSupply_ << DexSlotsLink.BITS_USER_SUPPLY_AMOUNT) | // converted to BigNumber can not overflow
            (newWithdrawalLimit_ << DexSlotsLink.BITS_USER_SUPPLY_PREVIOUS_WITHDRAWAL_LIMIT) | // converted to BigNumber can not overflow
            (block.timestamp << DexSlotsLink.BITS_USER_SUPPLY_LAST_UPDATE_TIMESTAMP);
    }
}
