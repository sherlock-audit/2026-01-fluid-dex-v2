// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "../other/commonImport.sol";
import { PendingTransfers as PT } from "../../../../../libraries/pendingTransfers.sol";

/// @title FluidDexV2D3UserModule
/// @notice User module for D3 (smart collateral) DEX positions
/// @dev Handles deposits (supply), withdrawals, and pool initialization for concentrated liquidity positions
contract FluidDexV2D3UserModule is CommonImportD3Other {
    uint256 internal constant DEX_TYPE_WITH_VERSION = 30_000;

    /// @notice Initializes the D3 User Module
    /// @param liquidityAddress_ The FluidLiquidity contract address
    constructor(address liquidityAddress_) {
        THIS_CONTRACT = address(this);
        LIQUIDITY = IFluidLiquidity(liquidityAddress_);
    }

    /// @dev Ensures caller is whitelisted for D3 operations
    modifier _onlyWhitelistedUsers() {
        if (_whitelistedUsers[DEX_TYPE_WITH_VERSION / DEX_TYPE_DIVISOR][msg.sender] == 0) {
            revert FluidDexV2D3D4Error(ErrorTypes.UserModule__UserNotWhitelisted);
        }
        _;
    }

    /// @notice Deposits tokens into a concentrated liquidity position
    /// @param params_ DepositParams containing dexKey, tick range, positionSalt, amounts, and minimums
    /// @return amount0 supplied, amount1 supplied, fee0 accrued, fee1 accrued, liquidity increase
    function deposit(DepositParams calldata params_) external _onlyDelegateCall 
        returns (uint256, uint256, uint256, uint256, uint256) {
        unchecked {
            DepositVariables memory v_;

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

                // Convert amounts to raw adjusted amounts
                // NOTE: This calculation is inside unchecked but it wont overflow because params_.amount0 is limited to X128
                v_.amount0RawAdjusted = (params_.amount0 * LC.EXCHANGE_PRICES_PRECISION * c_.token0NumeratorPrecision) / (c_.token0SupplyExchangePrice * c_.token0DenominatorPrecision);
                // NOTE: This calculation is inside unchecked but it wont overflow because params_.amount1 is limited to X128
                v_.amount1RawAdjusted = (params_.amount1 * LC.EXCHANGE_PRICES_PRECISION * c_.token1NumeratorPrecision) / (c_.token1SupplyExchangePrice * c_.token1DenominatorPrecision);

                if (
                    (v_.amount0RawAdjusted == 0 && params_.amount0 > 0) ||
                    (v_.amount1RawAdjusted == 0 && params_.amount1 > 0) ||
                    (v_.amount0RawAdjusted == 0 && v_.amount1RawAdjusted == 0)
                ) {
                    revert FluidDexV2D3D4Error(ErrorTypes.UserModule__AmountRoundsToZero);
                }

                if (v_.amount0RawAdjusted > 0) _verifyAdjustedAmountLimits(v_.amount0RawAdjusted);
                if (v_.amount1RawAdjusted > 0) _verifyAdjustedAmountLimits(v_.amount1RawAdjusted);

                // no matter the user is adding/removing liquidity, the fee is being collected
                (
                    v_.amount0RawAdjusted, // actual amount which got used
                    v_.amount1RawAdjusted, // actual amount which got used
                    v_.feeAccruedToken0Adjusted,
                    v_.feeAccruedToken1Adjusted,
                    v_.liquidityIncreaseRaw
                ) = _addLiquidity(AddLiquidityInternalParams({
                    dexKey: params_.dexKey,
                    dexVariables: dexVariables_,
                    dexVariables2: dexVariables2_,
                    tickLower: params_.tickLower,
                    tickUpper: params_.tickUpper,
                    sqrtPriceLowerX96: TM.getSqrtRatioAtTick(params_.tickLower),
                    sqrtPriceUpperX96: TM.getSqrtRatioAtTick(params_.tickUpper),
                    positionSalt: params_.positionSalt,
                    amount0DesiredRaw: v_.amount0RawAdjusted,
                    amount1DesiredRaw: v_.amount1RawAdjusted,
                    dexType: dexType_,
                    dexId: dexId_,
                    isSmartCollateral: IS_SMART_COLLATERAL
                }));
            }

            if (v_.amount0RawAdjusted > 0) {
                _verifyAdjustedAmountLimits(v_.amount0RawAdjusted);
                // Convert raw adjusted amount to normal amount
                // NOTE: This calculation is inside unchecked but it wont overflow because v_.amount0RawAdjusted is limited to X86
                v_.amount0 = (v_.amount0RawAdjusted * c_.token0DenominatorPrecision * c_.token0SupplyExchangePrice) / (c_.token0NumeratorPrecision * LC.EXCHANGE_PRICES_PRECISION);
            }
            if (v_.amount1RawAdjusted > 0) {
                _verifyAdjustedAmountLimits(v_.amount1RawAdjusted);
                // Convert raw adjusted amount to normal amount
                // NOTE: This calculation is inside unchecked but it wont overflow because v_.amount1RawAdjusted is limited to X86
                v_.amount1 = (v_.amount1RawAdjusted * c_.token1DenominatorPrecision * c_.token1SupplyExchangePrice) / (c_.token1NumeratorPrecision * LC.EXCHANGE_PRICES_PRECISION);
            }

            if (v_.amount0 > 0) {
                // Explicit Rounding Up of amount0 to be 100% sure that the protocol is on the winning side
                v_.amount0 = ((v_.amount0 * ROUNDING_FACTOR_PLUS_ONE) / ROUNDING_FACTOR) + 1;
                _verifyAmountLimits(v_.amount0);
            }
            
            if (v_.amount1 > 0) {
                // Explicit Rounding Up of amount1 to be 100% sure that the protocol is on the winning side
                v_.amount1 = ((v_.amount1 * ROUNDING_FACTOR_PLUS_ONE) / ROUNDING_FACTOR) + 1;
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

            // When user adds liquidity, he/she is supplying tokens to the protocol, hence a positive pending pending supply 
            // Subtracting fee accrued because user has to pay net less tokens
            PT.addPendingSupply(msg.sender, params_.dexKey.token0, int256(v_.amount0) - int256(v_.feeAccruedToken0));
            PT.addPendingSupply(msg.sender, params_.dexKey.token1, int256(v_.amount1) - int256(v_.feeAccruedToken1));

            emit LogDeposit(
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

    /// @notice Withdraws tokens from a concentrated liquidity position
    /// @param params_ WithdrawParams containing dexKey, tick range, positionSalt, amounts, and minimums
    /// @return amount0 withdrawn, amount1 withdrawn, fee0 accrued, fee1 accrued, liquidity decrease
    function withdraw(WithdrawParams calldata params_) external _onlyDelegateCall 
        returns (uint256, uint256, uint256, uint256, uint256) {
        // NOTE: No overall unchecked in withdraw because we are not doing amount limit checks
        WithdrawVariables memory v_;

        bytes32 dexId_ = keccak256(abi.encode(params_.dexKey));
        PL.lock(dexId_);

        uint256 dexType_ = DEX_TYPE_WITH_VERSION / DEX_TYPE_DIVISOR;

        CalculatedVars memory c_;
        {
            DexVariables memory dexVariables_ = _getDexVariables(dexType_, dexId_);
            uint256 dexVariables2_ = _dexVariables2[dexType_][dexId_];

            if (dexVariables_.sqrtPriceX96 == 0) revert FluidDexV2D3D4Error(ErrorTypes.UserModule__DexNotInitialized);

            // NOTE: no checks in withdraw so liquidations dont get stuck
            // if (params_.amount0 > 0) _verifyAmountLimits(params_.amount0);
            // if (params_.amount1 > 0) _verifyAmountLimits(params_.amount1);

            c_ = _calculateVars(params_.dexKey.token0, params_.dexKey.token1, dexVariables2_);

            // Convert normal amounts to raw adjusted amounts
            v_.amount0RawAdjusted = (params_.amount0 * LC.EXCHANGE_PRICES_PRECISION * c_.token0NumeratorPrecision) / (c_.token0SupplyExchangePrice * c_.token0DenominatorPrecision);
            v_.amount1RawAdjusted = (params_.amount1 * LC.EXCHANGE_PRICES_PRECISION * c_.token1NumeratorPrecision) / (c_.token1SupplyExchangePrice * c_.token1DenominatorPrecision);

            // NOTE: no checks in withdraw so liquidations dont get stuck
            // if (
            //     (v_.amount0RawAdjusted == 0 && params_.amount0 > 0) ||
            //     (v_.amount1RawAdjusted == 0 && params_.amount1 > 0)
            // ) {
            //     revert FluidDexV2D3D4Error(ErrorTypes.UserModule__AmountRoundsToZero);
            // }

            // NOTE: no checks in withdraw so liquidations dont get stuck
            // if (v_.amount0RawAdjusted > 0) _verifyAdjustedAmountLimits(v_.amount0RawAdjusted);
            // if (v_.amount1RawAdjusted > 0) _verifyAdjustedAmountLimits(v_.amount1RawAdjusted);

            // no matter the user is adding/removing liquidity, the fee is being collected
            (
                v_.amount0RawAdjusted,
                v_.amount1RawAdjusted,
                v_.feeAccruedToken0Adjusted,
                v_.feeAccruedToken1Adjusted,
                v_.liquidityDecreaseRaw
            ) = _removeLiquidity(RemoveLiquidityInternalParams({
                dexKey: params_.dexKey,
                dexVariables: dexVariables_,
                dexVariables2: dexVariables2_,
                tickLower: params_.tickLower,
                tickUpper: params_.tickUpper,
                sqrtPriceLowerX96: TM.getSqrtRatioAtTick(params_.tickLower),
                sqrtPriceUpperX96: TM.getSqrtRatioAtTick(params_.tickUpper),
                positionSalt: params_.positionSalt,
                amount0DesiredRaw: v_.amount0RawAdjusted,
                amount1DesiredRaw: v_.amount1RawAdjusted,
                dexType: dexType_,
                dexId: dexId_
            }));
        }

        // NOTE: no checks in withdraw so liquidations dont get stuck
        // if (v_.amount0RawAdjusted > 0) _verifyAdjustedAmountLimits(v_.amount0RawAdjusted);
        // if (v_.amount1RawAdjusted > 0) _verifyAdjustedAmountLimits(v_.amount1RawAdjusted);

        // Convert raw adjusted amounts to normal amounts
        // Also explicitly rounding down to be 100% sure that the protocol is on the winning side
        v_.amount0 = (v_.amount0RawAdjusted * c_.token0DenominatorPrecision * c_.token0SupplyExchangePrice * ROUNDING_FACTOR_MINUS_ONE) /
            (c_.token0NumeratorPrecision * LC.EXCHANGE_PRICES_PRECISION * ROUNDING_FACTOR);
        if (v_.amount0 > 0) {
            v_.amount0 -= 1; // Just subtracting 1 so protocol remains on the winning side
            // _verifyAmountLimits(v_.amount0); // NOTE: no checks in withdraw so liquidations dont get stuck
        }

        v_.amount1 = (v_.amount1RawAdjusted * c_.token1DenominatorPrecision * c_.token1SupplyExchangePrice * ROUNDING_FACTOR_MINUS_ONE) / 
            (c_.token1NumeratorPrecision * LC.EXCHANGE_PRICES_PRECISION * ROUNDING_FACTOR);
        if (v_.amount1 > 0) {
            v_.amount1 -= 1; // Just subtracting 1 so protocol remains on the winning side
            // _verifyAmountLimits(v_.amount1); // NOTE: no checks in withdraw so liquidations dont get stuck
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

        // Add user pending supply
        PT.addPendingSupply(msg.sender, params_.dexKey.token0, -int256(v_.amount0 + v_.feeAccruedToken0));
        PT.addPendingSupply(msg.sender, params_.dexKey.token1, -int256(v_.amount1 + v_.feeAccruedToken1));

        emit LogWithdraw(
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

    /// @notice Initializes a new D3 pool with initial price
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
