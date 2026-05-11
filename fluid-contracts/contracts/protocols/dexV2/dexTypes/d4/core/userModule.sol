// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "../other/commonImport.sol";
import { PendingTransfers as PT } from "../../../../../libraries/pendingTransfers.sol";

/// @title FluidDexV2D4UserModule
/// @notice User module for D4 (smart debt) DEX positions
/// @dev Handles borrows, paybacks, and pool initialization for concentrated liquidity debt positions
contract FluidDexV2D4UserModule is CommonImportD4Other {
    uint256 internal constant DEX_TYPE_WITH_VERSION = 40_000;

    /// @notice Initializes the D4 User Module
    /// @param liquidityAddress_ The FluidLiquidity contract address
    constructor(address liquidityAddress_) {
        THIS_CONTRACT = address(this);
        LIQUIDITY = IFluidLiquidity(liquidityAddress_);
    }

    /// @dev Ensures caller is whitelisted for D4 operations
    modifier _onlyWhitelistedUsers() {
        if (_whitelistedUsers[DEX_TYPE_WITH_VERSION / DEX_TYPE_DIVISOR][msg.sender] == 0) {
            revert FluidDexV2D3D4Error(ErrorTypes.UserModule__UserNotWhitelisted);
        }
        _;
    }

    /// @notice Borrows tokens by creating a concentrated liquidity debt position
    /// @param params_ BorrowParams containing dexKey, tick range, positionSalt, amounts, and minimums
    /// @return amount0 borrowed, amount1 borrowed, fee0 accrued, fee1 accrued, liquidity increase
    function borrow(BorrowParams calldata params_) external _onlyDelegateCall _onlyWhitelistedUsers 
        returns (uint256, uint256, uint256, uint256, uint256) {
        unchecked {
            BorrowVariables memory v_;

            bytes32 dexId_ = keccak256(abi.encode(params_.dexKey));
            PL.lock(dexId_);

            uint256 dexType_ = DEX_TYPE_WITH_VERSION / DEX_TYPE_DIVISOR;

            CalculatedVars memory c_;
            {
                DexVariables memory dexVariables_ = _getDexVariables(dexType_, dexId_);
                uint256 dexVariables2_ = _dexVariables2[dexType_][dexId_];

                if (dexVariables_.sqrtPriceX96 == 0) {
                    revert FluidDexV2D3D4Error(ErrorTypes.UserModule__DexNotInitialized);
                }

                if (params_.amount0 > 0) _verifyAmountLimits(params_.amount0);
                if (params_.amount1 > 0) _verifyAmountLimits(params_.amount1);

                c_ = _calculateVars(params_.dexKey.token0, params_.dexKey.token1, dexVariables2_);

                // Convert normal amounts to raw adjusted amounts
                // NOTE: This calculation is inside unchecked but it wont overflow because params_.amount0 is limited to X128
                v_.token0DebtAmountRawAdjusted = (params_.amount0 * LC.EXCHANGE_PRICES_PRECISION * c_.token0NumeratorPrecision) / (c_.token0BorrowExchangePrice * c_.token0DenominatorPrecision);
                // NOTE: This calculation is inside unchecked but it wont overflow because params_.amount1 is limited to X128
                v_.token1DebtAmountRawAdjusted = (params_.amount1 * LC.EXCHANGE_PRICES_PRECISION * c_.token1NumeratorPrecision) / (c_.token1BorrowExchangePrice * c_.token1DenominatorPrecision);

                if (
                    (v_.token0DebtAmountRawAdjusted == 0 && params_.amount0 > 0) ||
                    (v_.token1DebtAmountRawAdjusted == 0 && params_.amount1 > 0) ||
                    (v_.token0DebtAmountRawAdjusted == 0 && v_.token1DebtAmountRawAdjusted == 0)
                ) {
                    revert FluidDexV2D3D4Error(ErrorTypes.UserModule__AmountRoundsToZero);
                }

                v_.sqrtPriceLowerX96 = TM.getSqrtRatioAtTick(params_.tickLower);
                v_.sqrtPriceUpperX96 = TM.getSqrtRatioAtTick(params_.tickUpper);

                v_.geometricMeanPriceX96 = FM.mulDiv(v_.sqrtPriceLowerX96, v_.sqrtPriceUpperX96, Q96);
                v_.priceLowerX96 = FM.mulDiv(v_.sqrtPriceLowerX96, v_.sqrtPriceLowerX96, Q96);
                v_.priceUpperX96 = FM.mulDiv(v_.sqrtPriceUpperX96, v_.sqrtPriceUpperX96, Q96);

                (v_.token0ReserveAmountRawAdjusted, v_.token1ReserveAmountRawAdjusted) = _getReservesFromDebtAmounts(
                    v_.geometricMeanPriceX96,
                    v_.priceUpperX96,
                    v_.priceLowerX96,
                    v_.token0DebtAmountRawAdjusted,
                    v_.token1DebtAmountRawAdjusted
                );

                _verifyReserveAndDebtLimits(v_.token0ReserveAmountRawAdjusted, v_.token0DebtAmountRawAdjusted);
                _verifyReserveAndDebtLimits(v_.token1ReserveAmountRawAdjusted, v_.token1DebtAmountRawAdjusted);

                // no matter the user is adding/removing liquidity, the fee is being collected
                (
                    v_.token0ReserveAmountRawAdjusted,
                    v_.token1ReserveAmountRawAdjusted,
                    v_.feeAccruedToken0Adjusted,
                    v_.feeAccruedToken1Adjusted,
                    v_.liquidityIncreaseRaw
                ) = _addLiquidity(AddLiquidityInternalParams({
                    dexKey: params_.dexKey,
                    dexVariables: dexVariables_,
                    dexVariables2: dexVariables2_,
                    tickLower: params_.tickLower,
                    tickUpper: params_.tickUpper,
                    sqrtPriceLowerX96: v_.sqrtPriceLowerX96,
                    sqrtPriceUpperX96: v_.sqrtPriceUpperX96,
                    positionSalt: params_.positionSalt,
                    amount0DesiredRaw: v_.token0ReserveAmountRawAdjusted,
                    amount1DesiredRaw: v_.token1ReserveAmountRawAdjusted,
                    dexType: dexType_,
                    dexId: dexId_,
                    isSmartCollateral: IS_SMART_DEBT
                }));
            }

            (v_.token0DebtAmountRawAdjusted, v_.token1DebtAmountRawAdjusted) = _getDebtAmountsFromReserves(
                v_.geometricMeanPriceX96,
                v_.priceUpperX96,
                v_.priceLowerX96,
                v_.token0ReserveAmountRawAdjusted,
                v_.token1ReserveAmountRawAdjusted
            );

            _verifyReserveAndDebtLimits(v_.token0ReserveAmountRawAdjusted, v_.token0DebtAmountRawAdjusted);
            _verifyReserveAndDebtLimits(v_.token1ReserveAmountRawAdjusted, v_.token1DebtAmountRawAdjusted);

            // Convert raw adjusted amounts to normal amounts
            // Also explicitly rounding down to be 100% sure that the protocol is on the winning side (user gets less when borrowing)
            // NOTE: This calculation is inside unchecked but it wont overflow because v_.token0DebtAmountRawAdjusted is limited to X86
            v_.amount0 = (v_.token0DebtAmountRawAdjusted * c_.token0DenominatorPrecision * c_.token0BorrowExchangePrice * ROUNDING_FACTOR_MINUS_ONE) / 
                (c_.token0NumeratorPrecision * LC.EXCHANGE_PRICES_PRECISION * ROUNDING_FACTOR);
            if (v_.amount0 > 0) {
                v_.amount0 -= 1; // Just subtracting 1 so protocol remains on the winning side
                _verifyAmountLimits(v_.amount0);
            }

            // NOTE: This calculation is inside unchecked but it wont overflow because v_.token1DebtAmountRawAdjusted is limited to X86
            v_.amount1 = (v_.token1DebtAmountRawAdjusted * c_.token1DenominatorPrecision * c_.token1BorrowExchangePrice * ROUNDING_FACTOR_MINUS_ONE) / 
                (c_.token1NumeratorPrecision * LC.EXCHANGE_PRICES_PRECISION * ROUNDING_FACTOR);
            if (v_.amount1 > 0) {
                v_.amount1 -= 1; // Just subtracting 1 so protocol remains on the winning side
                _verifyAmountLimits(v_.amount1);
            }

            // Convert adjusted fee amounts to normal fee amounts
            // Also explicitly rounding down to be 100% sure that the protocol is on the winning side
            v_.feeAccruedToken0 = (v_.feeAccruedToken0Adjusted * c_.token0DenominatorPrecision * ROUNDING_FACTOR_MINUS_ONE) / (c_.token0NumeratorPrecision * ROUNDING_FACTOR);
            if (v_.feeAccruedToken0 > 0) v_.feeAccruedToken0 -= 1; // Just subtracting 1 so protocol remains on the winning side

            v_.feeAccruedToken1 = (v_.feeAccruedToken1Adjusted * c_.token1DenominatorPrecision * ROUNDING_FACTOR_MINUS_ONE) / (c_.token1NumeratorPrecision * ROUNDING_FACTOR);
            if (v_.feeAccruedToken1 > 0) v_.feeAccruedToken1 -= 1; // Just subtracting 1 so protocol remains on the winning side

            // Verify amounts are not less than minimums
            if (v_.amount0 < params_.amount0Min || v_.amount1 < params_.amount1Min) {
                revert FluidDexV2D3D4Error(ErrorTypes.UserModule__AmountsLessThanMinimum);
            }

            // Update Pending Transfers for token 0
            PT.addPendingBorrow(msg.sender, params_.dexKey.token0, int256(v_.amount0)); // When user adds liquidity, he/she is borrowing tokens from the protocol, hence a positive pending borrow 
            PT.addPendingSupply(msg.sender, params_.dexKey.token0, -int256(v_.feeAccruedToken0)); // when fee was accrued during swap we made it +ve supply, hence now we make it -ve.

            // Update Pending Transfers for token 1
            PT.addPendingBorrow(msg.sender, params_.dexKey.token1, int256(v_.amount1)); // When user adds liquidity, he/she is borrowing tokens from the protocol, hence a positive pending borrow 
            PT.addPendingSupply(msg.sender, params_.dexKey.token1, -int256(v_.feeAccruedToken1)); // when fee was accrued during swap we made it +ve supply, hence now we make it -ve.

            emit LogBorrow(
                dexType_, 
                dexId_,
                msg.sender, 
                params_.tickLower, 
                params_.tickUpper, 
                params_.positionSalt, 
                v_.amount0, 
                v_.amount1,
                v_.feeAccruedToken0, 
                v_.feeAccruedToken1, 
                v_.liquidityIncreaseRaw
            );

            PL.unlock(dexId_);

            return (v_.amount0, v_.amount1, v_.feeAccruedToken0, v_.feeAccruedToken1, v_.liquidityIncreaseRaw);
        }
    }

    /// @notice Pays back borrowed tokens to reduce a concentrated liquidity debt position
    /// @param params_ PaybackParams containing dexKey, tick range, positionSalt, amounts, and minimums
    /// @return amount0 paid back, amount1 paid back, fee0 accrued, fee1 accrued, liquidity decrease
    function payback(PaybackParams calldata params_) external _onlyDelegateCall _onlyWhitelistedUsers 
        returns (uint256, uint256, uint256, uint256, uint256) {
        // NOTE: No overall unchecked in payback because we are not doing amount limit checks
        PaybackVariables memory v_;

        bytes32 dexId_ = keccak256(abi.encode(params_.dexKey));
        PL.lock(dexId_);

        uint256 dexType_ = DEX_TYPE_WITH_VERSION / DEX_TYPE_DIVISOR;

        CalculatedVars memory c_;
        {
            DexVariables memory dexVariables_ = _getDexVariables(dexType_, dexId_);
            uint256 dexVariables2_ = _dexVariables2[dexType_][dexId_];

            if (dexVariables_.sqrtPriceX96 == 0) revert FluidDexV2D3D4Error(ErrorTypes.UserModule__DexNotInitialized);

            // NOTE: no checks in payback so liquidations dont get stuck
            // if (params_.amount0 > 0) _verifyAmountLimits(params_.amount0);
            // if (params_.amount1 > 0) _verifyAmountLimits(params_.amount1);

            c_ = _calculateVars(params_.dexKey.token0, params_.dexKey.token1, dexVariables2_);

            // Convert amounts to raw adjusted amounts using exchange prices
            v_.token0DebtAmountRawAdjusted = (params_.amount0 * LC.EXCHANGE_PRICES_PRECISION * c_.token0NumeratorPrecision) / (c_.token0BorrowExchangePrice * c_.token0DenominatorPrecision);
            v_.token1DebtAmountRawAdjusted = (params_.amount1 * LC.EXCHANGE_PRICES_PRECISION * c_.token1NumeratorPrecision) / (c_.token1BorrowExchangePrice * c_.token1DenominatorPrecision);

            // NOTE: no checks in payback so liquidations dont get stuck
            // if (
            //     (v_.token0DebtAmountRawAdjusted == 0 && params_.amount0 > 0) ||
            //     (v_.token1DebtAmountRawAdjusted == 0 && params_.amount1 > 0)
            // ) {
            //     revert FluidDexV2D3D4Error(ErrorTypes.UserModule__AmountRoundsToZero);
            // }

            v_.sqrtPriceLowerX96 = TM.getSqrtRatioAtTick(params_.tickLower);
            v_.sqrtPriceUpperX96 = TM.getSqrtRatioAtTick(params_.tickUpper);

            v_.geometricMeanPriceX96 = FM.mulDiv(v_.sqrtPriceLowerX96, v_.sqrtPriceUpperX96, Q96);
            v_.priceLowerX96 = FM.mulDiv(v_.sqrtPriceLowerX96, v_.sqrtPriceLowerX96, Q96);
            v_.priceUpperX96 = FM.mulDiv(v_.sqrtPriceUpperX96, v_.sqrtPriceUpperX96, Q96);

            (v_.token0ReserveAmountRawAdjusted, v_.token1ReserveAmountRawAdjusted) = _getReservesFromDebtAmounts(
                v_.geometricMeanPriceX96,
                v_.priceUpperX96,
                v_.priceLowerX96,
                v_.token0DebtAmountRawAdjusted,
                v_.token1DebtAmountRawAdjusted
            );

            // NOTE: no checks in payback so liquidations dont get stuck
            // _verifyReserveAndDebtLimits(v_.token0ReserveAmountRawAdjusted, v_.token0DebtAmountRawAdjusted);
            // _verifyReserveAndDebtLimits(v_.token1ReserveAmountRawAdjusted, v_.token1DebtAmountRawAdjusted);

            // no matter the user is adding/removing liquidity, the fee is being collected
            (
                v_.token0ReserveAmountRawAdjusted,
                v_.token1ReserveAmountRawAdjusted,
                v_.feeAccruedToken0Adjusted,
                v_.feeAccruedToken1Adjusted,
                v_.liquidityDecreaseRaw
            ) = _removeLiquidity(RemoveLiquidityInternalParams({
                dexKey: params_.dexKey,
                dexVariables: dexVariables_,
                dexVariables2: dexVariables2_,
                tickLower: params_.tickLower,
                tickUpper: params_.tickUpper,
                sqrtPriceLowerX96: v_.sqrtPriceLowerX96,
                sqrtPriceUpperX96: v_.sqrtPriceUpperX96,
                positionSalt: params_.positionSalt,
                amount0DesiredRaw: v_.token0ReserveAmountRawAdjusted,
                amount1DesiredRaw: v_.token1ReserveAmountRawAdjusted,
                dexType: dexType_,
                dexId: dexId_
            }));
        }

        (v_.token0DebtAmountRawAdjusted, v_.token1DebtAmountRawAdjusted) = _getDebtAmountsFromReserves(
            v_.geometricMeanPriceX96,
            v_.priceUpperX96,
            v_.priceLowerX96,
            v_.token0ReserveAmountRawAdjusted,
            v_.token1ReserveAmountRawAdjusted
        );

        // NOTE: no checks in payback so liquidations dont get stuck
        // _verifyReserveAndDebtLimits(v_.token0ReserveAmountRawAdjusted, v_.token0DebtAmountRawAdjusted);
        // _verifyReserveAndDebtLimits(v_.token1ReserveAmountRawAdjusted, v_.token1DebtAmountRawAdjusted);

        // Convert raw adjusted amounts to normal amounts
        // Also explicitly rounding up to be 100% sure that the protocol is on the winning side (user pays more when paying back)
        v_.amount0 = (v_.token0DebtAmountRawAdjusted * c_.token0DenominatorPrecision * c_.token0BorrowExchangePrice * ROUNDING_FACTOR_PLUS_ONE) / 
            (c_.token0NumeratorPrecision * LC.EXCHANGE_PRICES_PRECISION * ROUNDING_FACTOR);
        if (v_.amount0 > 0) {
            v_.amount0 += 1; // Just adding 1 so protocol remains on the winning side
            // _verifyAmountLimits(v_.amount0); // NOTE: no checks in payback so liquidations dont get stuck   
        }

        v_.amount1 = (v_.token1DebtAmountRawAdjusted * c_.token1DenominatorPrecision * c_.token1BorrowExchangePrice * ROUNDING_FACTOR_PLUS_ONE) / 
            (c_.token1NumeratorPrecision * LC.EXCHANGE_PRICES_PRECISION * ROUNDING_FACTOR);
        if (v_.amount1 > 0) {
            v_.amount1 += 1; // Just adding 1 so protocol remains on the winning side
            // _verifyAmountLimits(v_.amount1); // NOTE: no checks in payback so liquidations dont get stuck
        }

        // Convert adjusted fee amounts to normal fee amounts
        // Also explicitly rounding down to be 100% sure that the protocol is on the winning side
        v_.feeAccruedToken0 = (v_.feeAccruedToken0Adjusted * c_.token0DenominatorPrecision * ROUNDING_FACTOR_MINUS_ONE) / (c_.token0NumeratorPrecision * ROUNDING_FACTOR);
        if (v_.feeAccruedToken0 > 0) v_.feeAccruedToken0 -= 1; // Just subtracting 1 so protocol remains on the winning side

        v_.feeAccruedToken1 = (v_.feeAccruedToken1Adjusted * c_.token1DenominatorPrecision * ROUNDING_FACTOR_MINUS_ONE) / (c_.token1NumeratorPrecision * ROUNDING_FACTOR);
        if (v_.feeAccruedToken1 > 0) v_.feeAccruedToken1 -= 1; // Just subtracting 1 so protocol remains on the winning side

        // Verify amounts are not less than minimums
        if (v_.amount0 < params_.amount0Min || v_.amount1 < params_.amount1Min) {
            revert FluidDexV2D3D4Error(ErrorTypes.UserModule__AmountsLessThanMinimum);
        }

        // Update Pending Transfers for token 0
        PT.addPendingBorrow(msg.sender, params_.dexKey.token0, -int256(v_.amount0)); // When user removes liquidity, he/she is paying back tokens to the protocol, hence a negative pending borrow 
        PT.addPendingSupply(msg.sender, params_.dexKey.token0, -int256(v_.feeAccruedToken0)); // when fee was accrued during swap we made it +ve supply, hence now we make it -ve

        // Update Pending Transfers for token 1
        PT.addPendingBorrow(msg.sender, params_.dexKey.token1, -int256(v_.amount1)); // When user removes liquidity, he/she is paying back tokens to the protocol, hence a negative pending borrow 
        PT.addPendingSupply(msg.sender, params_.dexKey.token1, -int256(v_.feeAccruedToken1)); // when fee was accrued during swap we made it +ve supply, hence now we make it -ve

        emit LogPayback(
            dexType_, 
            dexId_,
            msg.sender, 
            params_.tickLower, 
            params_.tickUpper, 
            params_.positionSalt, 
            v_.amount0, 
            v_.amount1, 
            v_.feeAccruedToken0, 
            v_.feeAccruedToken1, 
            v_.liquidityDecreaseRaw
        );

        PL.unlock(dexId_);

        return (v_.amount0, v_.amount1, v_.feeAccruedToken0, v_.feeAccruedToken1, v_.liquidityDecreaseRaw);
    }

    /// @notice Initializes a new D4 pool with initial price
    /// @dev Only callable by whitelisted users. Sets the initial sqrt price for the pool.
    /// @param params_ InitializeParams containing dexKey and initial sqrtPriceX96
    function initialize(InitializeParams calldata params_) external _onlyDelegateCall _onlyWhitelistedUsers {
        _initialize(InitializeInternalParams({
            dexKey: params_.dexKey,
            sqrtPriceX96: params_.sqrtPriceX96,
            dexType: DEX_TYPE_WITH_VERSION / DEX_TYPE_DIVISOR
        }));

        // NOTE: LogInitialize event is emitted in the internal _initialize function
    }
}
