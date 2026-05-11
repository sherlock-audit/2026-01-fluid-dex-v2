// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "../other/commonImport.sol";
import { PendingTransfers as PT } from "../../../../../libraries/pendingTransfers.sol";

/// @title FluidDexV2D3SwapModule
/// @notice Swap module for D3 (smart collateral) DEX pools
/// @dev Implements concentrated liquidity swaps with supply-based exchange prices
contract FluidDexV2D3SwapModule is CommonImportD3Other {
    uint256 internal constant DEX_TYPE_WITH_VERSION = 30_000;

    /// @notice Initializes the D3 Swap Module
    /// @param liquidityAddress_ The FluidLiquidity contract address
    constructor(address liquidityAddress_) {
        THIS_CONTRACT = address(this);
        LIQUIDITY = IFluidLiquidity(liquidityAddress_);
    }

    /// @notice Executes a swap with exact input amount
    /// @param params_ SwapInParams containing dexKey, swap direction, amountIn, amountOutMin, and controllerData
    /// @return amountOut_ The actual output amount received
    /// @return protocolFeeAccrued_ Protocol fee deducted from output
    /// @return lpFeeAccrued_ LP fee deducted from output
    function swapIn(SwapInParams calldata params_) external _onlyDelegateCall returns (uint256 amountOut_, uint256 protocolFeeAccrued_, uint256 lpFeeAccrued_) {
        unchecked {
            bytes32 dexId_ = keccak256(abi.encode(params_.dexKey));
            PL.lock(dexId_);

            uint256 dexType_ = DEX_TYPE_WITH_VERSION / DEX_TYPE_DIVISOR;

            CalculatedVars memory c_;
            uint256 amountOutRawAdjusted_;
            uint256 protocolFeeAccruedRawAdjusted_;
            uint256 lpFeeAccruedRawAdjusted_;

            {
                uint256 dexVariables_ = _dexVariables[dexType_][dexId_];
                uint256 dexVariables2_ = _dexVariables2[dexType_][dexId_];

                if (dexVariables_ == 0) {
                    revert FluidDexV2D3D4Error(ErrorTypes.SwapModule__DexNotInitialized);
                }

                _verifyAmountLimits(params_.amountIn);

                c_ = _calculateVars(params_.dexKey.token0, params_.dexKey.token1, dexVariables2_);
                
                {
                    uint256 amountInRawAdjusted_;
                    if (params_.swap0To1) {
                        // NOTE: This calculation is inside unchecked but it wont overflow because params_.amountIn is limited to X128
                        amountInRawAdjusted_ = (params_.amountIn * LC.EXCHANGE_PRICES_PRECISION * c_.token0NumeratorPrecision) / (c_.token0SupplyExchangePrice * c_.token0DenominatorPrecision);
                    } else {
                        // NOTE: This calculation is inside unchecked but it wont overflow because params_.amountIn is limited to X128
                        amountInRawAdjusted_ = (params_.amountIn * LC.EXCHANGE_PRICES_PRECISION * c_.token1NumeratorPrecision) / (c_.token1SupplyExchangePrice * c_.token1DenominatorPrecision);
                    }

                    // Explicit Rounding Down of amountInRawAdjusted to be 100% sure that the protocol is on the winning side
                    amountInRawAdjusted_ = (amountInRawAdjusted_ * ROUNDING_FACTOR_MINUS_ONE) / ROUNDING_FACTOR; 
                    if (amountInRawAdjusted_ > 0) amountInRawAdjusted_ -= 1;

                    _verifyAdjustedAmountLimits(amountInRawAdjusted_);

                    (amountOutRawAdjusted_, protocolFeeAccruedRawAdjusted_, lpFeeAccruedRawAdjusted_) = _swapIn(SwapInInternalParams({
                        dexKey: params_.dexKey,
                        dexVariables: dexVariables_,
                        dexVariables2: dexVariables2_,
                        swap0To1: params_.swap0To1,
                        amountInRaw: amountInRawAdjusted_,
                        controllerData: params_.controllerData,
                        token0ExchangePrice: c_.token0SupplyExchangePrice,
                        token1ExchangePrice: c_.token1SupplyExchangePrice,
                        dexType: dexType_,
                        dexId: dexId_
                    }));
                }
            }

            // Explicit Rounding Down of amountOutRawAdjusted to be 100% sure that the protocol is on the winning side
            amountOutRawAdjusted_ = (amountOutRawAdjusted_ * ROUNDING_FACTOR_MINUS_ONE) / ROUNDING_FACTOR; 
            if (amountOutRawAdjusted_ > 0) amountOutRawAdjusted_ -= 1;

            _verifyAdjustedAmountLimits(amountOutRawAdjusted_);

            if (params_.swap0To1) {
                // NOTE: This calculation is inside unchecked but it wont overflow because amountOutRawAdjusted_ is limited to X86
                amountOut_ = ((amountOutRawAdjusted_ * c_.token1DenominatorPrecision * c_.token1SupplyExchangePrice) / (c_.token1NumeratorPrecision * LC.EXCHANGE_PRICES_PRECISION));
                if (amountOut_ > 0) amountOut_ -= 1; // Just subtracting 1 so protocol remains on the winning side
                _verifyAmountLimits(amountOut_);

                if (amountOut_ < params_.amountOutMin) {
                    revert FluidDexV2D3D4Error(ErrorTypes.SwapModule__AmountOutLessThanMin);
                }

                // NOTE: Fee is cut from tokenOut in swap in
                // NOTE: This calculation is inside unchecked but it wont overflow because amountOutRawAdjusted_ is limited to X86, hence protocolFeeAccruedRawAdjusted_ will be surely less than that
                protocolFeeAccrued_ = (protocolFeeAccruedRawAdjusted_ * c_.token1DenominatorPrecision * c_.token1SupplyExchangePrice) / (c_.token1NumeratorPrecision * LC.EXCHANGE_PRICES_PRECISION);
                // NOTE: This calculation is inside unchecked but it wont overflow because amountOutRawAdjusted_ is limited to X86, hence lpFeeAccruedRawAdjusted_ will be surely less than that
                lpFeeAccrued_ = (lpFeeAccruedRawAdjusted_ * c_.token1DenominatorPrecision * c_.token1SupplyExchangePrice) / (c_.token1NumeratorPrecision * LC.EXCHANGE_PRICES_PRECISION);

                PT.addPendingSupply(msg.sender, params_.dexKey.token0, int256(params_.amountIn));
                PT.addPendingSupply(msg.sender, params_.dexKey.token1, -int256(amountOut_));
            } else {
                // NOTE: This calculation is inside unchecked but it wont overflow because amountOutRawAdjusted_ is limited to X86
                amountOut_ = ((amountOutRawAdjusted_ * c_.token0DenominatorPrecision * c_.token0SupplyExchangePrice) / (c_.token0NumeratorPrecision * LC.EXCHANGE_PRICES_PRECISION));
                if (amountOut_ > 0) amountOut_ -= 1; // Just subtracting 1 so protocol remains on the winning side
                _verifyAmountLimits(amountOut_);

                if (amountOut_ < params_.amountOutMin) {
                    revert FluidDexV2D3D4Error(ErrorTypes.SwapModule__AmountOutLessThanMin);
                }

                // NOTE: Fee is cut from tokenOut in swap in
                // NOTE: This calculation is inside unchecked but it wont overflow because amountOutRawAdjusted_ is limited to X86, hence protocolFeeAccruedRawAdjusted_ will be surely less than that
                protocolFeeAccrued_ = (protocolFeeAccruedRawAdjusted_ * c_.token0DenominatorPrecision * c_.token0SupplyExchangePrice) / (c_.token0NumeratorPrecision * LC.EXCHANGE_PRICES_PRECISION);
                // NOTE: This calculation is inside unchecked but it wont overflow because amountOutRawAdjusted_ is limited to X86, hence lpFeeAccruedRawAdjusted_ will be surely less than that
                lpFeeAccrued_ = (lpFeeAccruedRawAdjusted_ * c_.token0DenominatorPrecision * c_.token0SupplyExchangePrice) / (c_.token0NumeratorPrecision * LC.EXCHANGE_PRICES_PRECISION);

                PT.addPendingSupply(msg.sender, params_.dexKey.token1, int256(params_.amountIn));
                PT.addPendingSupply(msg.sender, params_.dexKey.token0, -int256(amountOut_));
            }

            emit LogSwapIn(dexType_, dexId_, msg.sender, params_.swap0To1, params_.amountIn, amountOut_, protocolFeeAccrued_, lpFeeAccrued_);

            PL.unlock(dexId_);
        }
    }

    /// @notice Executes a swap with exact output amount
    /// @param params_ SwapOutParams containing dexKey, swap direction, amountOut, amountInMax, and controllerData
    /// @return amountIn_ The actual input amount required
    /// @return protocolFeeAccrued_ Protocol fee deducted from input
    /// @return lpFeeAccrued_ LP fee deducted from input
    function swapOut(SwapOutParams calldata params_) external _onlyDelegateCall returns (uint256 amountIn_, uint256 protocolFeeAccrued_, uint256 lpFeeAccrued_) {
        unchecked {
            bytes32 dexId_ = keccak256(abi.encode(params_.dexKey));
            PL.lock(dexId_);

            uint256 dexType_ = DEX_TYPE_WITH_VERSION / DEX_TYPE_DIVISOR;

            CalculatedVars memory c_;
            uint256 amountInRawAdjusted_;
            uint256 protocolFeeAccruedRawAdjusted_;
            uint256 lpFeeAccruedRawAdjusted_;

            {
                uint256 dexVariables_ = _dexVariables[dexType_][dexId_];
                uint256 dexVariables2_ = _dexVariables2[dexType_][dexId_];

                if (dexVariables_ == 0) {
                    revert FluidDexV2D3D4Error(ErrorTypes.SwapModule__DexNotInitialized);
                }

                _verifyAmountLimits(params_.amountOut);

                c_ = _calculateVars(params_.dexKey.token0, params_.dexKey.token1, dexVariables2_);
                
                {
                    uint256 amountOutRawAdjusted_;
                    if (params_.swap0To1) {
                        // NOTE: This calculation is inside unchecked but it wont overflow because params_.amountOut is limited to X128
                        amountOutRawAdjusted_ = (params_.amountOut * LC.EXCHANGE_PRICES_PRECISION * c_.token1NumeratorPrecision) / (c_.token1SupplyExchangePrice * c_.token1DenominatorPrecision);
                    } else {
                        // NOTE: This calculation is inside unchecked but it wont overflow because params_.amountOut is limited to X128
                        amountOutRawAdjusted_ = (params_.amountOut * LC.EXCHANGE_PRICES_PRECISION * c_.token0NumeratorPrecision) / (c_.token0SupplyExchangePrice * c_.token0DenominatorPrecision);
                    }

                    // Explicit Rounding Up of amountOutRawAdjusted to be 100% sure that the protocol is on the winning side
                    amountOutRawAdjusted_ = ((amountOutRawAdjusted_ * ROUNDING_FACTOR_PLUS_ONE) / ROUNDING_FACTOR) + 1;

                    _verifyAdjustedAmountLimits(amountOutRawAdjusted_);

                    (amountInRawAdjusted_, protocolFeeAccruedRawAdjusted_, lpFeeAccruedRawAdjusted_) = _swapOut(SwapOutInternalParams({
                        dexKey: params_.dexKey,
                        dexVariables: dexVariables_,
                        dexVariables2: dexVariables2_,
                        swap0To1: params_.swap0To1,
                        amountOutRaw: amountOutRawAdjusted_,
                        controllerData: params_.controllerData,
                        token0ExchangePrice: c_.token0SupplyExchangePrice,
                        token1ExchangePrice: c_.token1SupplyExchangePrice,
                        dexType: dexType_,
                        dexId: dexId_
                    }));
                }
            }

            // Explicit Rounding Up of amountInRawAdjusted to be 100% sure that the protocol is on the winning side
            amountInRawAdjusted_ = ((amountInRawAdjusted_ * ROUNDING_FACTOR_PLUS_ONE) / ROUNDING_FACTOR) + 1;

            _verifyAdjustedAmountLimits(amountInRawAdjusted_);

            if (params_.swap0To1) {
                // NOTE: This calculation is inside unchecked but it wont overflow because amountInRawAdjusted_ is limited to X86
                amountIn_ = ((amountInRawAdjusted_ * c_.token0DenominatorPrecision * c_.token0SupplyExchangePrice) / (c_.token0NumeratorPrecision * LC.EXCHANGE_PRICES_PRECISION)) + 1; // Just adding 1 so protocol remains on the winning side
                _verifyAmountLimits(amountIn_);

                if (amountIn_ > params_.amountInMax) {
                    revert FluidDexV2D3D4Error(ErrorTypes.SwapModule__AmountInMoreThanMax);
                }

                // NOTE: Fee is cut from tokenIn in swap out
                // NOTE: This calculation is inside unchecked but it wont overflow because amountInRawAdjusted_ is limited to X86, hence protocolFeeAccruedRawAdjusted_ will be surely less than that
                protocolFeeAccrued_ = (protocolFeeAccruedRawAdjusted_ * c_.token0DenominatorPrecision * c_.token0SupplyExchangePrice) / (c_.token0NumeratorPrecision * LC.EXCHANGE_PRICES_PRECISION);
                // NOTE: This calculation is inside unchecked but it wont overflow because amountInRawAdjusted_ is limited to X86, hence lpFeeAccruedRawAdjusted_ will be surely less than that
                lpFeeAccrued_ = (lpFeeAccruedRawAdjusted_ * c_.token0DenominatorPrecision * c_.token0SupplyExchangePrice) / (c_.token0NumeratorPrecision * LC.EXCHANGE_PRICES_PRECISION);

                PT.addPendingSupply(msg.sender, params_.dexKey.token0, int256(amountIn_));
                PT.addPendingSupply(msg.sender, params_.dexKey.token1, -int256(params_.amountOut));
            } else {
                // NOTE: This calculation is inside unchecked but it wont overflow because amountInRawAdjusted_ is limited to X86
                amountIn_ = ((amountInRawAdjusted_ * c_.token1DenominatorPrecision * c_.token1SupplyExchangePrice) / (c_.token1NumeratorPrecision * LC.EXCHANGE_PRICES_PRECISION)) + 1; // Just adding 1 so protocol remains on the winning side
                _verifyAmountLimits(amountIn_);
                
                if (amountIn_ > params_.amountInMax) {
                    revert FluidDexV2D3D4Error(ErrorTypes.SwapModule__AmountInMoreThanMax);
                }

                // NOTE: Fee is cut from tokenIn in swap out
                // NOTE: This calculation is inside unchecked but it wont overflow because amountInRawAdjusted_ is limited to X86, hence protocolFeeAccruedRawAdjusted_ will be surely less than that
                protocolFeeAccrued_ = (protocolFeeAccruedRawAdjusted_ * c_.token1DenominatorPrecision * c_.token1SupplyExchangePrice) / (c_.token1NumeratorPrecision * LC.EXCHANGE_PRICES_PRECISION);
                // NOTE: This calculation is inside unchecked but it wont overflow because amountInRawAdjusted_ is limited to X86, hence lpFeeAccruedRawAdjusted_ will be surely less than that
                lpFeeAccrued_ = (lpFeeAccruedRawAdjusted_ * c_.token1DenominatorPrecision * c_.token1SupplyExchangePrice) / (c_.token1NumeratorPrecision * LC.EXCHANGE_PRICES_PRECISION);

                PT.addPendingSupply(msg.sender, params_.dexKey.token1, int256(amountIn_));
                PT.addPendingSupply(msg.sender, params_.dexKey.token0, -int256(params_.amountOut));
            }

            emit LogSwapOut(dexType_, dexId_, msg.sender, params_.swap0To1, amountIn_, params_.amountOut, protocolFeeAccrued_, lpFeeAccrued_);

            PL.unlock(dexId_);
        }
    }
}
