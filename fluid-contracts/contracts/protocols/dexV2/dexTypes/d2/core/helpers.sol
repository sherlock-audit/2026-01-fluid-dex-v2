// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import "../other/commonImport.sol";
// import { ErrorTypes } from "../../../errorTypes.sol"; // TODO: Update all reverts

import { SafeTransfer } from "../../../../../libraries/safeTransfer.sol";
import { LiquiditySlotsLink } from "../../../../../libraries/liquiditySlotsLink.sol";
import { LiquidityCalcs } from "../../../../../libraries/liquidityCalcs.sol";
import { DexSlotsLink } from "../../../../../libraries/dexSlotsLink.sol";
import { DexCalcs } from "../../../../../libraries/dexCalcs.sol";

abstract contract Helpers is CommonImportD2Other {
    using BigMathMinified for uint256;

    function _setTotalBorrowRaw(bytes32 dexId_, uint256 token0TotalBorrowRaw_, uint256 token1TotalBorrowRaw_) internal {
        // TODO
    }

    function _getTotalBorrowRaw(bytes32 dexId_) internal view returns (uint256 token0TotalBorrowRaw_, uint256 token1TotalBorrowRaw_) {
        // TODO
    }

    function _calculateVars(address token0_, address token1_, uint256 dexVariables2_, bytes32 dexId_) internal view returns (CalculatedVars memory calculatedVars_) {
        uint256 token0Decimals_ = (dexVariables2_ >> 228) & X5;
        uint256 token1Decimals_ = (dexVariables2_ >> 233) & X5;

        (calculatedVars_.token0NumeratorPrecision, calculatedVars_.token0DenominatorPrecision) = calculateNumeratorAndDenominatorPrecisions(token0Decimals_);
        (calculatedVars_.token1NumeratorPrecision, calculatedVars_.token1DenominatorPrecision) = calculateNumeratorAndDenominatorPrecisions(token1Decimals_);

        // Exchange price will remain same as Liquidity Layer
        (, calculatedVars_.token0BorrowExchangePrice) = LiquidityCalcs.calcExchangePrices(
            LIQUIDITY.readFromStorage(LiquiditySlotsLink.calculateMappingStorageSlot(LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT, token0_))
        );

        (, calculatedVars_.token1BorrowExchangePrice) = LiquidityCalcs.calcExchangePrices(
            LIQUIDITY.readFromStorage(LiquiditySlotsLink.calculateMappingStorageSlot(LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT, token1_))
        );

        (calculatedVars_.token0TotalBorrowRaw, calculatedVars_.token1TotalBorrowRaw) = _getTotalBorrowRaw(dexId_);
        uint256 token0TotalBorrow_ = (calculatedVars_.token0TotalBorrowRaw * calculatedVars_.token0BorrowExchangePrice) / LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
        uint256 token1TotalBorrow_ = (calculatedVars_.token1TotalBorrowRaw * calculatedVars_.token1BorrowExchangePrice) / LiquidityCalcs.EXCHANGE_PRICES_PRECISION;

        calculatedVars_.token0TotalBorrowAdjusted = (token0TotalBorrow_ * calculatedVars_.token0NumeratorPrecision) / calculatedVars_.token0DenominatorPrecision;
        calculatedVars_.token1TotalBorrowAdjusted = (token1TotalBorrow_ * calculatedVars_.token1NumeratorPrecision) / calculatedVars_.token1DenominatorPrecision;
    }

    /// @notice Calculates the real and imaginary debt reserves for both tokens
    /// @dev This function uses a quadratic equation to determine the debt reserves
    ///      based on the geometric mean price and the current debt amounts
    /// @param gp_ The geometric mean price of upper range & lower range
    /// @param pb_ The price of lower range
    /// @param dx_ The debt amount of one token
    /// @param dy_ The debt amount of the other token
    /// @return rx_ The real debt reserve of the first token
    /// @return ry_ The real debt reserve of the second token
    /// @return irx_ The imaginary debt reserve of the first token
    /// @return iry_ The imaginary debt reserve of the second token
    function _calculateDebtReserves(
        uint256 gp_,
        uint256 pb_,
        uint256 dx_,
        uint256 dy_
    ) internal pure returns (uint256 rx_, uint256 ry_, uint256 irx_, uint256 iry_) {
        // Assigning letter to knowns:
        // c = debtA
        // d = debtB
        // e = upperPrice
        // f = lowerPrice
        // g = upperPrice^1/2
        // h = lowerPrice^1/2

        // c = 1
        // d = 2000
        // e = 2222.222222
        // f = 1800
        // g = 2222.222222^1/2
        // h = 1800^1/2

        // Assigning letter to unknowns:
        // w = realDebtReserveA
        // x = realDebtReserveB
        // y = imaginaryDebtReserveA
        // z = imaginaryDebtReserveB
        // k = k

        // below quadratic will give answer of realDebtReserveB
        // A, B, C of quadratic equation:
        // A = h
        // B = dh - cfg
        // C = -cfdh

        // A = lowerPrice^1/2
        // B = debtB⋅lowerPrice^1/2 - debtA⋅lowerPrice⋅upperPrice^1/2
        // C = -(debtA⋅lowerPrice⋅debtB⋅lowerPrice^1/2)

        // x = (cfg − dh + (4cdf(h^2)+(cfg−dh)^2))^(1/2)) / 2h
        // simplifying dividing by h, note h = f^1/2
        // x = ((c⋅g⋅(f^1/2) − d) / 2 + ((4⋅c⋅d⋅f⋅f) / (4h^2) + ((c⋅f⋅g) / 2h − (d⋅h) / 2h)^2))^(1/2))
        // x = ((c⋅g⋅(f^1/2) − d) / 2 + ((c⋅d⋅f) + ((c⋅g⋅(f^1/2) − d) / 2)^2))^(1/2))

        // dividing in 3 parts for simplification:
        // part1 = (c⋅g⋅(f^1/2) − d) / 2
        // part2 = (c⋅d⋅f)
        // x = (part1 + (part2 + part1^2)^(1/2))
        // note: part1 will almost always be < 1e27 but in case it goes above 1e27 then it's extremely unlikely it'll go above > 1e28

        // part1 = ((debtA * upperPrice^1/2 * lowerPrice^1/2) - debtB) / 2
        // note: upperPrice^1/2 * lowerPrice^1/2 = geometric mean
        // part1 = ((debtA * geometricMean) - debtB) / 2
        // part2 = debtA * debtB * lowerPrice

        // converting decimals properly as price is in 1e27 decimals
        // part1 = ((debtA * geometricMean) - (debtB * 1e27)) / (2 * 1e27)
        // part2 = (debtA * debtB * lowerPrice) / 1e27
        // final x equals:
        // x = (part1 + (part2 + part1^2)^(1/2))
        int p1_ = (int(dx_ * gp_) - int(dy_ * 1e27)) / (2 * 1e27);
        uint256 p2_ = (dx_ * dy_);
        p2_ = p2_ < 1e50 ? (p2_ * pb_) / 1e27 : (p2_ / 1e27) * pb_;
        ry_ = uint256(p1_ + int(FixedPointMathLib.sqrt((p2_ + uint256(p1_ * p1_)))));

        // finding z:
        // x^2 - zx + cfz = 0
        // z*(x - cf) = x^2
        // z = x^2 / (x - cf)
        // z = x^2 / (x - debtA * lowerPrice)
        // converting decimals properly as price is in 1e27 decimals
        // z = (x^2 * 1e27) / ((x * 1e27) - (debtA * lowerPrice))

        iry_ = ((ry_ * 1e27) - (dx_ * pb_));
        if (iry_ < SIX_DECIMALS) {
            // almost impossible situation to ever get here
            revert(); // FluidDexError(ErrorTypes.DexT1__DebtReservesTooLow);
        }
        if (ry_ < 1e25) {
            iry_ = (ry_ * ry_ * 1e27) / iry_;
        } else {
            // note: it can never result in negative as final result will always be in positive
            iry_ = (ry_ * ry_) / (iry_ / 1e27);
        }

        // finding y
        // x = z * c / (y + c)
        // y + c = z * c / x
        // y = (z * c / x) - c
        // y = (z * debtA / x) - debtA
        irx_ = ((iry_ * dx_) / ry_) - dx_;

        // finding w
        // w = y * d / (z + d)
        // w = (y * debtB) / (z + debtB)
        rx_ = (irx_ * dy_) / (iry_ + dy_);
    }

    /// @notice Calculates the debt reserves for both tokens
    /// @param geometricMean_ The geometric mean of the upper and lower price ranges
    /// @param upperRange_ The upper price range
    /// @param lowerRange_ The lower price range
    /// @param token0Debt_ The debt amount of token0
    /// @param token1Debt_ The debt amount of token1
    /// @return d_ The calculated debt reserves for both tokens, containing:
    ///         - token0Debt: The debt amount of token0
    ///         - token1Debt: The debt amount of token1
    ///         - token0RealReserves: The real reserves of token0 derived from token1 debt
    ///         - token1RealReserves: The real reserves of token1 derived from token0 debt
    ///         - token0ImaginaryReserves: The imaginary debt reserves of token0
    ///         - token1ImaginaryReserves: The imaginary debt reserves of token1
    function _getDebtReserves(
        uint256 geometricMean_,
        uint256 upperRange_,
        uint256 lowerRange_,
        uint256 token0Debt_,
        uint256 token1Debt_
    ) internal pure returns (DebtReserves memory d_) {
        d_.token0Debt = token0Debt_;
        d_.token1Debt = token1Debt_;

        // TODO: Can use full math here and remove the if else
        if (geometricMean_ < 1e27) {
            (d_.token0RealReserves, d_.token1RealReserves, d_.token0ImaginaryReserves, d_.token1ImaginaryReserves) = _calculateDebtReserves(
                geometricMean_,
                lowerRange_,
                token0Debt_,
                token1Debt_
            );
        } else {
            // inversing, something like `xy = k` so for calculation we are making everything related to x into y & y into x
            // 1 / geometricMean for new geometricMean
            // 1 / lowerRange will become upper range
            // 1 / upperRange will become lower range
            (d_.token1RealReserves, d_.token0RealReserves, d_.token1ImaginaryReserves, d_.token0ImaginaryReserves) = _calculateDebtReserves(
                (1e54 / geometricMean_),
                (1e54 / upperRange_),
                token1Debt_,
                token0Debt_
            );
        }
    }

    function _updateBorrowShares(uint256 newTotalShares_, bytes32 dexId_) internal {
        uint256 totalBorrowShares_ = _totalBorrowShares[DEX_TYPE][dexId_];

        // new total shares are greater than old total shares && new total shares are greater than max borrow shares
        if ((newTotalShares_ > (totalBorrowShares_ & X128)) && newTotalShares_ > (totalBorrowShares_ >> 128)) {
            revert(); // FluidDexError(ErrorTypes.DexT1__BorrowSharesOverflow);
        }

        // keeping max borrow shares intact
        _totalBorrowShares[DEX_TYPE][dexId_] = ((totalBorrowShares_ >> 128) << 128) | newTotalShares_;
    }

    /// @param c_ tokenA current debt before swap (aka debt before borrow & swap)
    /// @param d_ tokenB current debt before swap (aka debt before borrow & swap)
    /// @param e_ tokenA final imaginary reserves (reserves after borrow & swap)
    /// @param f_ tokenB final imaginary reserves (reserves after borrow & swap)
    /// @param g_ tokenA perfect amount to borrow
    function _getBorrowAndSwap(uint256 c_, uint256 d_, uint256 e_, uint256 f_, uint256 g_) internal pure returns (uint256 shares_) {
        // 1. tokenAxa / tokenADebt = tokenBxb / tokenBDebt (borrowing in equal proportion)
        // 2. newImaginaryTokenAReserves = tokenAFinalImaginaryReserves + tokenAxb
        // 3. newImaginaryTokenBReserves = tokenBFinalImaginaryReserves - tokenBxb
        // // Note: I assumed reserve of tokenA and debt of token A while solving which is fine.
        // // But in other places I use debtA to find reserveB
        // 4. tokenAxb = (newImaginaryTokenAReserves * tokenBxb) / (newImaginaryTokenBReserves + tokenBxb)
        // 5. tokenAxa + tokenAxb = tokenAx

        // Inserting 2 & 3 into 4:
        // 6. tokenAxb = ((tokenAFinalImaginaryReserves + tokenAxb) * tokenBxb) / ((tokenBFinalImaginaryReserves - tokenBxb) + tokenBxb)
        // 6. tokenAxb = ((tokenAFinalImaginaryReserves + tokenAxb) * tokenBxb) / (tokenBFinalImaginaryReserves)

        // Making 1 in terms of tokenBxb:
        // 1. tokenBxb = tokenAxa * tokenBDebt / tokenADebt

        // Inserting 5 into 6:
        // 7. (tokenAx - tokenAxa) = ((tokenAFinalImaginaryReserves + (tokenAx - tokenAxa)) * tokenBxb) / (tokenBFinalImaginaryReserves)

        // Inserting 1 into 7:
        // 8. (tokenAx - tokenAxa) * tokenBFinalImaginaryReserves = ((tokenAFinalImaginaryReserves + (tokenAx - tokenAxa)) * (tokenAxa * tokenBDebt / tokenADebt))

        // Replacing knowns with:
        // c = tokenADebt
        // d = tokenBDebt
        // e = tokenAFinalImaginaryReserves
        // f = tokenBFinalImaginaryReserves
        // g = tokenAx

        // 8. (g - tokenAxa) * f * c = ((e + (g - tokenAxa)) * (tokenAxa * d))
        // 8. cfg - cf*tokenAxa = de*tokenAxa + dg*tokenAxa - d*tokenAxa^2
        // 8. d*tokenAxa^2 - cf*tokenAxa - de*tokenAxa - dg*tokenAxa + cfg = 0
        // 8. d*tokenAxa^2 - (cf + de + dg)*tokenAxa + cfg = 0

        // A, B, C of quadratic are:
        // A = d
        // B = -(cf + de + dg)
        // C = cfg

        // temp_ = B/2A
        uint256 temp_ = (c_ * f_ + d_ * e_ + d_ * g_) / (2 * d_);

        // temp2_ = 4AC / 4A^2 = C / A
        // to avoid overflowing in any case multiplying with g_ later
        uint256 temp2_ = (c_ * f_ * g_) / d_;

        // tokenAxa = (-B - (B^2 - 4AC)^0.5) / 2A
        uint256 tokenAxa_ = temp_ - FixedPointMathLib.sqrt((temp_ * temp_) - temp2_);

        // Ensure the amount to borrow is within reasonable bounds:
        // - Not greater than 99.9999% of the input amount (g_)
        // - Not less than 0.0001% of the input amount (g_)
        // This prevents extreme scenarios and maybe potential precision issues
        if (tokenAxa_ > ((g_ * (SIX_DECIMALS - 1)) / SIX_DECIMALS) || tokenAxa_ < (g_ / SIX_DECIMALS)) revert(); // FluidDexError(ErrorTypes.DexT1__BorrowAndSwapTooLowOrTooHigh);

        // rounding up borrow shares to mint for user
        shares_ = ((tokenAxa_ + 1) * 1e18) / c_;
    }

    /// @notice Updates debt and reserves based on minting or burning shares
    /// @param shares_ The number of shares to mint or burn
    /// @param totalShares_ The total number of shares before the operation
    /// @param d_ The current debt and reserves
    /// @param mintOrBurn_ True if minting, false if burning
    /// @return d2_ The updated debt and reserves
    /// @dev This function calculates the new debt and reserves when minting or burning shares.
    /// @dev It updates the following for both tokens:
    /// @dev - Debt
    /// @dev - Real Reserves
    /// @dev - Imaginary Reserves
    /// @dev The calculation is done proportionally based on the ratio of shares to total shares.
    /// @dev For minting, it adds the proportional amount.
    /// @dev For burning, it subtracts the proportional amount.
    function _getUpdateDebtReserves(
        uint256 shares_,
        uint256 totalShares_,
        DebtReserves memory d_,
        bool mintOrBurn_ // true if mint, false if burn
    ) internal pure returns (DebtReserves memory d2_) {
        if (mintOrBurn_) {
            d2_.token0Debt = d_.token0Debt + (d_.token0Debt * shares_) / totalShares_;
            d2_.token1Debt = d_.token1Debt + (d_.token1Debt * shares_) / totalShares_;
            d2_.token0RealReserves = d_.token0RealReserves + (d_.token0RealReserves * shares_) / totalShares_;
            d2_.token1RealReserves = d_.token1RealReserves + (d_.token1RealReserves * shares_) / totalShares_;
            d2_.token0ImaginaryReserves = d_.token0ImaginaryReserves + (d_.token0ImaginaryReserves * shares_) / totalShares_;
            d2_.token1ImaginaryReserves = d_.token1ImaginaryReserves + (d_.token1ImaginaryReserves * shares_) / totalShares_;
        } else {
            d2_.token0Debt = d_.token0Debt - (d_.token0Debt * shares_) / totalShares_;
            d2_.token1Debt = d_.token1Debt - (d_.token1Debt * shares_) / totalShares_;
            d2_.token0RealReserves = d_.token0RealReserves - (d_.token0RealReserves * shares_) / totalShares_;
            d2_.token1RealReserves = d_.token1RealReserves - (d_.token1RealReserves * shares_) / totalShares_;
            d2_.token0ImaginaryReserves = d_.token0ImaginaryReserves - (d_.token0ImaginaryReserves * shares_) / totalShares_;
            d2_.token1ImaginaryReserves = d_.token1ImaginaryReserves - (d_.token1ImaginaryReserves * shares_) / totalShares_;
        }

        return d2_;
    }

    /// @param a_ tokenA new imaginary reserves (imaginary reserves after perfect payback but not swap yet)
    /// @param b_ tokenB new imaginary reserves (imaginary reserves after perfect payback but not swap yet)
    /// @param c_ tokenA current debt
    /// @param d_ tokenB current debt & final debt (tokenB current & final debt remains same)
    /// @param i_ tokenA new reserves (reserves after perfect payback but not swap yet)
    /// @param j_ tokenB new reserves (reserves after perfect payback but not swap yet)
    function _getSwapAndPaybackOneTokenPerfectShares(
        uint256 a_,
        uint256 b_,
        uint256 c_,
        uint256 d_,
        uint256 i_,
        uint256 j_
    ) internal pure returns (uint256 tokenAmt_) {
        // l_ => tokenA reserves outside range
        uint256 l_ = a_ - i_;
        // m_ => tokenB reserves outside range
        uint256 m_ = b_ - j_;
        // w_ => new K or final K will be same, xy = k
        uint256 w_ = a_ * b_;
        // z_ => final reserveB full, when entire debt is in tokenA
        uint256 z_ = w_ / l_;
        // y_ => final reserveA full, when entire debt is in tokenB
        uint256 y_ = w_ / m_;
        // v_ = final reserveB
        uint256 v_ = z_ - m_ - d_;
        // x_ = final tokenA debt
        uint256 x_ = (v_ * y_) / (m_ + v_);

        // amountA to payback, this amount will get swapped into tokenB to payback in perfect proportion
        tokenAmt_ = c_ - x_;

        // Ensure the amount to swap and payback is within reasonable bounds:
        // - Not greater than 99.9999% of the current debt (c_)
        // This prevents extreme scenarios where almost all debt is getting paid after swap,
        // which could maybe lead to precision issues & edge cases
        if ((tokenAmt_ > (c_ * (SIX_DECIMALS - 1)) / SIX_DECIMALS)) revert(); // FluidDexError(ErrorTypes.DexT1__SwapAndPaybackTooLowOrTooHigh);
    }

    /// @param c_ tokenA debt before swap & payback
    /// @param d_ tokenB debt before swap & payback
    /// @param e_ tokenA imaginary reserves before swap & payback
    /// @param f_ tokenB imaginary reserves before swap & payback
    /// @param g_ tokenA perfect amount to payback
    function _getSwapAndPayback(uint256 c_, uint256 d_, uint256 e_, uint256 f_, uint256 g_) internal pure returns (uint256 shares_) {
        // 1. tokenAxa / newTokenADebt = tokenBxb / newTokenBDebt (borrowing in equal proportion)
        // 2. newTokenADebt = tokenADebt - tokenAxb
        // 3. newTokenBDebt = tokenBDebt + tokenBxb
        // 4. imaginaryTokenAReserves = Calculated above from debtA
        // 5. imaginaryTokenBReserves = Calculated above from debtA
        // // Note: I assumed reserveA and debtA for same tokenA
        // // But in other places I used debtA to find reserveB
        // 6. tokenBxb = (imaginaryTokenBReserves * tokenAxb) / (imaginaryTokenAReserves + tokenAxb)
        // 7. tokenAxa + tokenAxb = tokenAx

        // Unknowns in the above equations are:
        // tokenAxa, tokenAxb, tokenBxb

        // simplifying knowns in 1 letter to make things clear:
        // c = tokenADebt
        // d = tokenBDebt
        // e = imaginaryTokenAReserves
        // f = imaginaryTokenBReserves
        // g = tokenAx

        // Restructuring 1:
        // 1. newTokenBDebt = (tokenBxb * newTokenADebt) / tokenAxa

        // Inserting 1 in 3:
        // 8. (tokenBxb * newTokenADebt) / tokenAxa = tokenBDebt + tokenBxb

        // Refactoring 8 w.r.t tokenBxb:
        // 8. (tokenBxb * newTokenADebt) - tokenAxa * tokenBxb = tokenBDebt * tokenAxa
        // 8. tokenBxb * (newTokenADebt - tokenAxa) = tokenBDebt * tokenAxa
        // 8. tokenBxb = (tokenBDebt * tokenAxa) / (newTokenADebt - tokenAxa)

        // Inserting 2 in 8:
        // 9. tokenBxb = (tokenBDebt * tokenAxa) / (tokenADebt - tokenAxb - tokenAxa)
        // 9. tokenBxb = (tokenBDebt * tokenAxa) / (tokenADebt - tokenAx)

        // Inserting 9 in 6:
        // 10. (tokenBDebt * tokenAxa) / (tokenADebt - tokenAx) = (imaginaryTokenBReserves * tokenAxb) / (imaginaryTokenAReserves + tokenAxb)
        // 10. (tokenBDebt * (tokenAx - tokenAxb)) / (tokenADebt - tokenAx) = (imaginaryTokenBReserves * tokenAxb) / (imaginaryTokenAReserves + tokenAxb)

        // Replacing with single digits:
        // 10. (d * (g - tokenAxb)) / (c - g) = (f * tokenAxb) / (e + tokenAxb)
        // 10. d * (g - tokenAxb) * (e + tokenAxb) = (f * tokenAxb) * (c - g)
        // 10. deg + dg*tokenAxb - de*tokenAxb - d*tokenAxb^2 = cf*tokenAxb - fg*tokenAxb
        // 10. d*tokenAxb^2 + cf*tokenAxb - fg*tokenAxb + de*tokenAxb - dg*tokenAxb - deg = 0
        // 10. d*tokenAxb^2 + (cf - fg + de - dg)*tokenAxb - deg = 0

        // A = d
        // B = (cf + de - fg - dg)
        // C = -deg

        // Solving Quadratic will give the value for tokenAxb, now that "tokenAxb" is known we can also know:
        // tokenAxa & tokenBxb

        // temp_ => B/A
        uint256 temp_ = (c_ * f_ + d_ * e_ - f_ * g_ - d_ * g_) / d_;

        // temp2_ = -AC / A^2
        uint256 temp2_ = 4 * e_ * g_;

        uint256 amtToSwap_ = (FixedPointMathLib.sqrt((temp2_ + (temp_ * temp_))) - temp_) / 2;

        // Ensure the amount to swap is within reasonable bounds:
        // - Not greater than 99.9999% of the input amount (g_)
        // - Not less than 0.0001% of the input amount (g_)
        // This prevents extreme scenarios and maybe potential precision issues
        if ((amtToSwap_ > (g_ * (SIX_DECIMALS - 1)) / SIX_DECIMALS) || (amtToSwap_ < (g_ / SIX_DECIMALS))) revert(); // FluidDexError(ErrorTypes.DexT1__SwapAndPaybackTooLowOrTooHigh);

        // temp_ => amt0ToPayback
        temp_ = g_ - amtToSwap_;
        // (imaginaryTokenBReserves * amtToSwap_) / (imaginaryTokenAReserves + amtToSwap_)
        // temp2_ => amt1ToPayback
        temp2_ = (f_ * amtToSwap_) / (e_ + amtToSwap_);

        // temp_ => shares0
        temp_ = (temp_ * 1e18) / (c_ - amtToSwap_);
        // temp_ => shares1
        temp2_ = (temp2_ * 1e18) / (d_ + temp2_);
        // temp_ & temp2 should be same. Although, due to some possible precision loss taking the lower one
        shares_ = temp_ > temp2_ ? temp2_ : temp_;
    }

    function _updatingUserBorrowDataOnStorage(uint256 userBorrowData_, uint256 userBorrow_, uint256 newBorrowLimit_, bytes32 dexId_) internal {
        // calculate borrow limit to store as previous borrow limit in storage
        newBorrowLimit_ = DexCalcs.calcBorrowLimitAfterOperate(userBorrowData_, userBorrow_, newBorrowLimit_);

        // Converting user's borrowings into bignumber
        userBorrow_ = userBorrow_.toBigNumber(DEFAULT_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, BigMathMinified.ROUND_UP);

        // Converting borrow limit into bignumber
        newBorrowLimit_ = newBorrowLimit_.toBigNumber(DEFAULT_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, BigMathMinified.ROUND_DOWN);

        if (((userBorrowData_ >> DexSlotsLink.BITS_USER_BORROW_AMOUNT) & X64) == userBorrow_) {
            // make sure that shares amount is not so small that it wouldn't affect storage update. if a difference
            // is present then rounding will be in the right direction to avoid any potential manipulation.
            revert(); // FluidDexError(ErrorTypes.DexT1__SharesAmountInsufficient);
        }

        // Updating on storage, copied exactly the same from Liquidity Layer
        _userBorrowData[DEX_TYPE][dexId_][msg.sender] =
            // mask to update bits 1-161 (borrow amount, borrow limit, timestamp)
            (userBorrowData_ & 0xfffffffffffffffffffffffc0000000000000000000000000000000000000001) |
            (userBorrow_ << DexSlotsLink.BITS_USER_BORROW_AMOUNT) | // converted to BigNumber can not overflow
            (newBorrowLimit_ << DexSlotsLink.BITS_USER_BORROW_PREVIOUS_BORROW_LIMIT) | // converted to BigNumber can not overflow
            (block.timestamp << DexSlotsLink.BITS_USER_BORROW_LAST_UPDATE_TIMESTAMP);
    }
}
