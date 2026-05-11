// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./variables.sol";

import { LiquiditySlotsLink as LSL } from "../../../../../libraries/liquiditySlotsLink.sol";

abstract contract Helpers is Variables {
    modifier _onlyDelegateCall() {
        if (address(this) == THIS_CONTRACT) revert FluidDexV2D3D4Error(ErrorTypes.Helpers__OnlyDelegateCallAllowed);
        _;
    }

    function _calculateVars(address token0_, address token1_, uint256 dexVariables2_) internal view returns (CalculatedVars memory calculatedVars_) {
        // temp_ => token 0 decimals
        uint256 temp_ = (dexVariables2_ >> DSL.BITS_DEX_V2_VARIABLES2_TOKEN_0_DECIMALS) & X4;
        if (temp_ == 15) temp_ = 18;

        (calculatedVars_.token0NumeratorPrecision, calculatedVars_.token0DenominatorPrecision) = 
            _calculateNumeratorAndDenominatorPrecisions(temp_);

        // temp_ => token 1 decimals
        temp_ = (dexVariables2_ >> DSL.BITS_DEX_V2_VARIABLES2_TOKEN_1_DECIMALS) & X4;
        if (temp_ == 15) temp_ = 18;

        (calculatedVars_.token1NumeratorPrecision, calculatedVars_.token1DenominatorPrecision) = 
            _calculateNumeratorAndDenominatorPrecisions(temp_);

        (, calculatedVars_.token0BorrowExchangePrice) = LC.calcExchangePrices(LIQUIDITY.readFromStorage(
            LSL.calculateMappingStorageSlot(LSL.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT, token0_)));
        if (calculatedVars_.token0BorrowExchangePrice == 0) revert FluidDexV2D3D4Error(ErrorTypes.Helpers__InvalidExchangePrice);

        (, calculatedVars_.token1BorrowExchangePrice) = LC.calcExchangePrices(LIQUIDITY.readFromStorage(
            LSL.calculateMappingStorageSlot(LSL.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT, token1_)));
        if (calculatedVars_.token1BorrowExchangePrice == 0) revert FluidDexV2D3D4Error(ErrorTypes.Helpers__InvalidExchangePrice);
    }

    function _verifyReserveAndDebtLimits(uint256 reserve_, uint256 debt_) internal pure {
        if (reserve_ == 0) {
            _verifyAdjustedAmountLimits(debt_);
            return;
        }

        if (debt_ == 0) {
            _verifyAdjustedAmountLimits(reserve_);
            return;
        }

        _verifyAdjustedAmountLimits(reserve_);
        _verifyAdjustedAmountLimits(debt_);

        unchecked {
            if (debt_ > (reserve_ * TWO_DECIMALS) || reserve_ > (debt_ * TWO_DECIMALS)) revert FluidDexV2D3D4Error(ErrorTypes.Helpers__ReserveDebtRatioExceeded);
        }
    }

    /// @notice Calculates the real and imaginary debt reserves for both tokens
    /// @dev This function uses a quadratic equation to determine the debt reserves
    ///      based on the geometric mean price and the current debt amounts
    /// @param gp_ The geometric mean price of upper range & lower range X96
    /// @param pa_ The price of upper range X96
    /// @param pb_ The price of lower range X96
    /// @param dx_ The debt amount of token0
    /// @param dy_ The debt amount of token1
    /// @return rx_ The real debt reserve of token0
    /// @return ry_ The real debt reserve of token1
    function _calculateReservesFromDebtAmounts(uint256 gp_, uint256 pa_, uint256 pb_, uint256 dx_, uint256 dy_) internal pure returns (uint256 rx_, uint256 ry_) {
        if (dx_ == 0) {
            // ry_ = 0;
            rx_ = FM.mulDiv(dy_, Q96, gp_);
        } else if (dy_ == 0) {
            // rx_ = 0;
            ry_ = FM.mulDiv(dx_, gp_, Q96);
        } else {
            /// @dev FINDING ry_
            // Assigning letter to knowns:
            // c = debtA
            // d = debtB
            // e = upperPrice
            // f = lowerPrice
            // g = upperPrice^1/2
            // h = lowerPrice^1/2

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

            // after finding the solution & simplifying:
            // x = ((c⋅g⋅(f^1/2) − d) / 2 + ((c⋅d⋅f) + ((c⋅g⋅(f^1/2) − d) / 2)^2))^(1/2))

            // dividing in 3 parts for simplification:
            // part1 = (c⋅g⋅(f^1/2) − d) / 2
            // part2 = (c⋅d⋅f)
            // x = (part1 + (part2 + part1^2)^(1/2))
            // NOTE: part1 will almost always be < 1e27 but in case it goes above 1e27 then it's extremely unlikely it'll go above > 1e28

            // part1 = ((debtA * geometricMean) - debtB) / 2
            // part2 = debtA * debtB * lowerPrice

            // converting decimals properly as price is in X96 decimals
            // part1 = ((debtA * geometricMeanX96) - (debtB * Q96)) / (2 * Q96)
            // part2 = (debtA * debtB * lowerPriceX96) / Q96
            // final x equals:
            // x = (part1 + (part2 + part1^2)^(1/2))
            int256 p1_ = (int256(dx_ * gp_) - int256(dy_ * Q96)) / int256(2 * Q96);
            uint256 p2_ = dx_ * dy_;
            p2_ = FM.mulDiv(p2_, pb_, Q96);
            ry_ = uint256(p1_ + int256(FPM.sqrt((p2_ + uint256(p1_ * p1_)))));

            /// @dev FINDING rx_
            // Because of mathematical symmetry, we convert the above formula to find rx_ by replacing:
            // dx_ <-> dy_
            // gp_ <-> Q192 / gp_
            // pb_ <-> Q192 / pa_
            p1_ = (int256(dy_ * Q96) - int256(dx_ * gp_)) / (2 * int256(gp_));
            p2_ = dy_ * dx_;
            p2_ = FM.mulDiv(p2_, Q96, pa_);
            rx_ = uint256(p1_ + int256(FPM.sqrt((p2_ + uint256(p1_ * p1_)))));
        }
    }

    function _getReservesFromDebtAmounts(
        uint256 geometricMeanPrice_,
        uint256 upperRangePrice_,
        uint256 lowerRangePrice_,
        uint256 token0Debt_,
        uint256 token1Debt_
    ) internal pure returns (uint256 token0Reserves_, uint256 token1Reserves_) {
        if (geometricMeanPrice_ < Q96) {
            (token0Reserves_, token1Reserves_) = _calculateReservesFromDebtAmounts(geometricMeanPrice_, upperRangePrice_, lowerRangePrice_, token0Debt_, token1Debt_);
        } else {
            // inversing, something like `xy = k` so for calculation we are making everything related to x into y & y into x
            // 1 / geometricMean for new geometricMean
            // 1 / lowerRange will become upper range
            // 1 / upperRange will become lower range
            (token1Reserves_, token0Reserves_) = 
                _calculateReservesFromDebtAmounts(Q192 / geometricMeanPrice_, Q192 / lowerRangePrice_, Q192 / upperRangePrice_, token1Debt_, token0Debt_);
        }
    }

    /// @notice Calculates the real and imaginary debt reserves for both tokens
    /// @dev This function uses a quadratic equation to determine the debt reserves
    ///      based on the geometric mean price and the current debt amounts
    /// @param gp_ The geometric mean price of upper range & lower range X96
    /// @param pa_ The price of upper range X96
    /// @param pb_ The price of lower range X96
    /// @param rx_ The real debt reserve of token0
    /// @param ry_ The real debt reserve of token1
    /// @return dx_ The debt amount of token0
    /// @return dy_ The debt amount of token1
    function _calculateDebtAmountsFromReserves(uint256 gp_, uint256 pa_, uint256 pb_, uint256 rx_, uint256 ry_) internal pure returns (uint256 dx_, uint256 dy_) {
        if (rx_ == 0) {
            // dy_ = 0;
            dx_ = FM.mulDiv(ry_, Q96, gp_);
        } else if (ry_ == 0) {
            // dx_ = 0;
            dy_ = FM.mulDiv(rx_, gp_, Q96);
        } else {
            /// @dev FINDING dx_
            // Assigning letter to knowns:
            // w = realDebtReserveA
            // x = realDebtReserveB
            // e = upperPrice
            // f = lowerPrice
            // g = upperPrice^1/2
            // h = lowerPrice^1/2

            // Assigning letter to unknowns:
            // c = debtA
            // d = debtB
            // y = imaginaryDebtReserveA
            // z = imaginaryDebtReserveB
            // k = k

            // below quadratic will give answer of debtA
            // A, B, C of quadratic equation:
            // A = -gf
            // B = hx − gwf
            // C = gwx

            // after finding the solution & simplifying: (note: gm is geometricMean, means (g*h))
            // c = ((x - gm.w) / 2.gm) + (((x - gm.w) / 2.gm)^2 + (w.x/f))^(1/2)

            // dividing in 3 parts for simplification:
            // part1 = (x - gm.w) / 2.gm
            // part2 = w.x/f
            // c = (part1 + (part2 + part1^2)^(1/2))
            // NOTE: part1 will almost always be < 1e27 but in case it goes above 1e27 then it's extremely unlikely it'll go above > 1e28

            // part1 = (realDebtReserveB - (realDebtReserveA * geometricMean)) / 2 * geometricMean
            // part2 = realDebtReserveA * realDebtReserveB / lowerPrice

            // converting decimals properly as price is in X96 decimals
            // part1 = ((realDebtReserveB * (1<<96)) - (realDebtReserveA * geometricMean)) / 2 * geometricMean
            // part2 = realDebtReserveA * realDebtReserveB * (1<<96) / lowerPrice
            // final c equals:
            // c = (part1 + (part2 + part1^2)^(1/2))
            int256 p1_ = (int256(ry_ * Q96) - int256(rx_ * gp_)) / (2 * int256(gp_));
            uint256 p2_ = rx_ * ry_;
            p2_ = FM.mulDiv(p2_, Q96, pb_);
            dx_ = uint256(p1_ + int256(FPM.sqrt((p2_ + uint256(p1_ * p1_)))));

            /// @dev FINDING z:
            // Because of mathematical symmetry, we convert the above formula to find dy_ by replacing:
            // rx_ <-> ry_
            // gp_ <-> Q192 / gp_
            // pb_ <-> Q192 / pa_
            p1_ = (int256(rx_ * gp_) - int256(ry_ * Q96)) / (2 * int256(Q96));
            p2_ = ry_ * rx_;
            p2_ = FM.mulDiv(p2_, pa_, Q96);
            dy_ = uint256(p1_ + int256(FPM.sqrt((p2_ + uint256(p1_ * p1_)))));
        }
    }

    function _getDebtAmountsFromReserves(
        uint256 geometricMeanPrice_,
        uint256 upperRangePrice_,
        uint256 lowerRangePrice_,
        uint256 token0Reserves_,
        uint256 token1Reserves_
    ) internal pure returns (uint256 token0Debt_, uint256 token1Debt_) {
        if (geometricMeanPrice_ < Q96) {
            (token0Debt_, token1Debt_) = _calculateDebtAmountsFromReserves(geometricMeanPrice_, upperRangePrice_, lowerRangePrice_, token0Reserves_, token1Reserves_);
        } else {
            // inversing, something like `xy = k` so for calculation we are making everything related to x into y & y into x
            // 1 / geometricMean for new geometricMean
            // 1 / lowerRange will become upper range
            // 1 / upperRange will become lower range
            (token1Debt_, token0Debt_) = 
                _calculateDebtAmountsFromReserves(Q192 / geometricMeanPrice_, Q192 / lowerRangePrice_, Q192 / upperRangePrice_,token1Reserves_, token0Reserves_);
        }
    }
}
