// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import "./helpers.sol";

// TODO: Remove redundant stuff, name variables better, etc
// TODO: @Vaibhav dex initialized checks wherever necessary

abstract contract SwapInternals is Helpers {
    /// @dev This function allows users to swap a specific amount of input tokens for output tokens
    /// @param swap0To1_ Direction of swap. If true, swaps token0 for token1; if false, swaps token1 for token0
    /// @param amountIn_ The exact amount of input tokens to swap
    /// @return amountOut_ The amount of output tokens received from the swap
    function _swapIn(
        DexKey calldata dexKey_,
        bool swap0To1_,
        uint256 amountIn_,
        uint256 amountOutMin_,
        bool estimate_
    ) internal returns (uint256 amountOut_, int256 token0TotalSupplyRawChange_, int256 token1TotalSupplyRawChange_) {
        SwapInVariables memory v_;

        v_.dexId = keccak256(abi.encode(dexKey_));

        v_.dexVariables = _dexVariables[DEX_TYPE][v_.dexId];
        v_.dexVariables2 = _dexVariables2[DEX_TYPE][v_.dexId];

        v_.calculatedVars = _calculateVars(dexKey_.token0, dexKey_.token1, v_.dexVariables2, v_.dexId);

        if (v_.dexVariables2 & 1 == 0) revert(); // FluidDexError(ErrorTypes.DexT1__DexNotInitialized);
        if ((v_.dexVariables2 >> 255) == 1) revert(); // FluidDexError(ErrorTypes.DexT1__SwapAndArbitragePaused); // Swap Paused (we have removed arbitrage)

        if (swap0To1_) {
            (v_.s.tokenIn, v_.s.tokenOut) = (dexKey_.token0, dexKey_.token1);
            unchecked {
                v_.s.amtInAdjusted = (amountIn_ * v_.calculatedVars.token0NumeratorPrecision) / v_.calculatedVars.token0DenominatorPrecision;
            }
        } else {
            (v_.s.tokenIn, v_.s.tokenOut) = (dexKey_.token1, dexKey_.token0);
            unchecked {
                v_.s.amtInAdjusted = (amountIn_ * v_.calculatedVars.token1NumeratorPrecision) / v_.calculatedVars.token1DenominatorPrecision;
            }
        }

        _verifySwapAndNonPerfectActions(v_.s.amtInAdjusted, amountIn_);

        v_.prices = _getPrices(dexKey_, v_.dexVariables, v_.dexVariables2, DEX_TYPE, v_.dexId);

        if (msg.value > 0) {
            if (msg.value != amountIn_) revert(); // FluidDexError(ErrorTypes.DexT1__EthAndAmountInMisMatch);
            if (v_.s.tokenIn != NATIVE_TOKEN) revert(); // FluidDexError(ErrorTypes.DexT1__EthSentForNonNativeSwap);
        }

        // extracting fee
        v_.temp = ((v_.dexVariables2 >> 2) & X17);
        unchecked {
            // revenueCut in 6 decimals, to have proper precision
            // if fee = 1% and revenue cut = 10% then revenueCut = 1e8 - (10000 * 10) = 99900000
            v_.s.revenueCut = EIGHT_DECIMALS - ((((v_.dexVariables2 >> 19) & X7) * v_.temp));
            // fee in 4 decimals
            // 1 - fee. If fee is 1% then withoutFee will be 1e6 - 1e4
            // v_.s.fee => 1 - withdraw fee
            v_.s.fee = SIX_DECIMALS - v_.temp;
        }

        v_.c = _getCollateralReserves(
            v_.prices.geometricMean,
            v_.prices.upperRange,
            v_.prices.lowerRange,
            v_.calculatedVars.token0TotalSupplyAdjusted,
            v_.calculatedVars.token1TotalSupplyAdjusted
        );
        if (swap0To1_) {
            (v_.cs.tokenInRealReserves, v_.cs.tokenOutRealReserves, v_.cs.tokenInImaginaryReserves, v_.cs.tokenOutImaginaryReserves) = (
                v_.c.token0RealReserves,
                v_.c.token1RealReserves,
                v_.c.token0ImaginaryReserves,
                v_.c.token1ImaginaryReserves
            );
        } else {
            (v_.cs.tokenInRealReserves, v_.cs.tokenOutRealReserves, v_.cs.tokenInImaginaryReserves, v_.cs.tokenOutImaginaryReserves) = (
                v_.c.token1RealReserves,
                v_.c.token0RealReserves,
                v_.c.token1ImaginaryReserves,
                v_.c.token0ImaginaryReserves
            );
        }

        // limiting amtInAdjusted to be not more than 50% of imaginary tokenIn reserves
        // basically, if this throws that means user is trying to swap 0.5x tokenIn if current tokenIn imaginary reserves is x
        // let's take x as token0 here, that means, initially the pool pricing might be:
        // token1Reserve / x and new pool pricing will become token1Reserve / 1.5x (token1Reserve will decrease after swap but for simplicity ignoring that)
        // So pool price is decreased by ~33.33% (oracle will throw error in this case as it only allows 5% price difference but better to limit it before hand)
        unchecked {
            if (v_.s.amtInAdjusted > (v_.cs.tokenInImaginaryReserves / 2)) revert(); // FluidDexError(ErrorTypes.DexT1__SwapInLimitingAmounts);
        }

        if (v_.s.amtInAdjusted > 0) {
            // temp2_ = amountOutCol_
            v_.s.amtOutAdjusted = _getAmountOut(((v_.s.amtInAdjusted * v_.s.fee) / SIX_DECIMALS), v_.cs.tokenInImaginaryReserves, v_.cs.tokenOutImaginaryReserves);
            swap0To1_
                ? _verifyToken1Reserves(
                    (v_.cs.tokenInRealReserves + v_.s.amtInAdjusted),
                    (v_.cs.tokenOutRealReserves - v_.s.amtOutAdjusted),
                    v_.prices.centerPrice,
                    MINIMUM_LIQUIDITY_SWAP
                )
                : _verifyToken0Reserves(
                    (v_.cs.tokenOutRealReserves - v_.s.amtInAdjusted),
                    (v_.cs.tokenInRealReserves + v_.s.amtOutAdjusted),
                    v_.prices.centerPrice,
                    MINIMUM_LIQUIDITY_SWAP
                );
        }

        v_.s.amtInAdjusted = (v_.s.amtInAdjusted * v_.s.revenueCut) / EIGHT_DECIMALS;
        v_.s.price = swap0To1_
            ? ((v_.cs.tokenOutImaginaryReserves - v_.s.amtOutAdjusted) * 1e27) / (v_.cs.tokenInImaginaryReserves + v_.s.amtInAdjusted)
            : ((v_.cs.tokenInImaginaryReserves + v_.s.amtInAdjusted) * 1e27) / (v_.cs.tokenOutImaginaryReserves - v_.s.amtOutAdjusted);

        // converting into normal token amounts
        if (swap0To1_) {
            v_.s.amtIn = ((v_.s.amtInAdjusted * v_.calculatedVars.token0DenominatorPrecision) / v_.calculatedVars.token0NumeratorPrecision);
            unchecked {
                amountOut_ = ((v_.s.amtOutAdjusted * v_.calculatedVars.token1DenominatorPrecision) / v_.calculatedVars.token1NumeratorPrecision);
            }
        } else {
            v_.s.amtIn = ((v_.s.amtInAdjusted * v_.calculatedVars.token1DenominatorPrecision) / v_.calculatedVars.token1NumeratorPrecision);
            unchecked {
                amountOut_ = ((v_.s.amtOutAdjusted * v_.calculatedVars.token0DenominatorPrecision) / v_.calculatedVars.token0NumeratorPrecision);
            }
        }

        if (estimate_) revert(); // FluidDexLiquidityOutput(amountOut_);
        if (amountOut_ < amountOutMin_) revert(); // FluidDexError(ErrorTypes.DexT1__NotEnoughAmountOut);

        // if hook exists then calling hook
        v_.temp = (v_.dexVariables2 >> 142) & X30;
        if (v_.temp > 0) {
            v_.s.swap0to1 = swap0To1_;
            _hookVerify(dexKey_, v_.temp, 1, v_.s.swap0to1, v_.s.price);
        }

        // _dexVariables[DEX_TYPE][v_.dexId] = _updateOracle(v_.s.price, v_.prices.centerPrice, v_.dexVariables); // TODO: add this back after adding oracle and remove the updation of v_.dexVariables below
        _dexVariables[DEX_TYPE][v_.dexId] = _updateDexVariables(v_.s.price, v_.prices.centerPrice, v_.dexVariables);

        if (swap0To1_) {
            token0TotalSupplyRawChange_ = int256((amountIn_ * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token0SupplyExchangePrice);
            token1TotalSupplyRawChange_ = -int256((amountOut_ * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token1SupplyExchangePrice);
        } else {
            token0TotalSupplyRawChange_ = -int256((amountOut_ * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token1SupplyExchangePrice);
            token1TotalSupplyRawChange_ = int256((amountIn_ * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token0SupplyExchangePrice);
        }

        v_.calculatedVars.token0TotalSupplyRaw = uint256(int256(v_.calculatedVars.token0TotalSupplyRaw) + token0TotalSupplyRawChange_);
        v_.calculatedVars.token1TotalSupplyRaw = uint256(int256(v_.calculatedVars.token1TotalSupplyRaw) + token1TotalSupplyRawChange_);

        _setTotalSupplyRaw(v_.dexId, v_.calculatedVars.token0TotalSupplyRaw, v_.calculatedVars.token1TotalSupplyRaw);
    }

    /// @dev Swap tokens with perfect amount out. If NATIVE_TOKEN is sent then msg.value should be passed as amountInMax, amountInMax - amountIn of ETH are sent back to msg.sender
    /// @param swap0To1_ Direction of swap. If true, swaps token0 for token1; if false, swaps token1 for token0
    /// @param amountOut_ The exact amount of tokens to receive after swap
    /// @return amountIn_ The amount of input tokens used for the swap
    function _swapOut(
        DexKey calldata dexKey_,
        bool swap0To1_,
        uint256 amountOut_,
        uint256 amountInMax_,
        bool estimate_
    ) internal returns (uint256 amountIn_, int256 token0TotalSupplyRawChange_, int256 token1TotalSupplyRawChange_) {
        SwapOutVariables memory v_;

        v_.dexId = keccak256(abi.encode(dexKey_));

        v_.dexVariables = _dexVariables[DEX_TYPE][v_.dexId];
        v_.dexVariables2 = _dexVariables2[DEX_TYPE][v_.dexId];

        v_.calculatedVars = _calculateVars(dexKey_.token0, dexKey_.token1, v_.dexVariables2, v_.dexId);

        if (v_.dexVariables2 & 1 == 0) revert(); // FluidDexError(ErrorTypes.DexT1__DexNotInitialized);
        if ((v_.dexVariables2 >> 255) == 1) revert(); // FluidDexError(ErrorTypes.DexT1__SwapAndArbitragePaused);

        if (swap0To1_) {
            (v_.s.tokenIn, v_.s.tokenOut) = (dexKey_.token0, dexKey_.token1);
            unchecked {
                v_.s.amtOutAdjusted = (amountOut_ * v_.calculatedVars.token1NumeratorPrecision) / v_.calculatedVars.token1DenominatorPrecision;
            }
        } else {
            (v_.s.tokenIn, v_.s.tokenOut) = (dexKey_.token1, dexKey_.token0);
            unchecked {
                v_.s.amtOutAdjusted = (amountOut_ * v_.calculatedVars.token0NumeratorPrecision) / v_.calculatedVars.token0DenominatorPrecision;
            }
        }

        _verifySwapAndNonPerfectActions(v_.s.amtOutAdjusted, amountOut_);

        v_.prices = _getPrices(dexKey_, v_.dexVariables, v_.dexVariables2, DEX_TYPE, v_.dexId);

        if ((msg.value > 0) || ((v_.s.tokenIn == NATIVE_TOKEN) && (msg.value == 0))) {
            if (msg.value != amountInMax_) revert(); // FluidDexError(ErrorTypes.DexT1__EthAndAmountInMisMatch);
            if (v_.s.tokenIn != NATIVE_TOKEN) revert(); // FluidDexError(ErrorTypes.DexT1__EthSentForNonNativeSwap);
        }

        // extracting fee
        v_.temp = ((v_.dexVariables2 >> 2) & X17);
        unchecked {
            // revenueCut in 6 decimals, to have proper precision
            // if fee = 1% and revenue cut = 10% then revenueCut = 1e8 - (10000 * 10) = 99900000
            v_.s.revenueCut = EIGHT_DECIMALS - ((((v_.dexVariables2 >> 19) & X7) * v_.temp));
            // fee in 4 decimals
            // 1 - fee. If fee is 1% then withoutFee will be 1e6 - 1e4
            // v_.s.fee => 1 - withdraw fee
            v_.s.fee = SIX_DECIMALS - v_.temp;
        }

        v_.c = _getCollateralReserves(
            v_.prices.geometricMean,
            v_.prices.upperRange,
            v_.prices.lowerRange,
            v_.calculatedVars.token0TotalSupplyAdjusted,
            v_.calculatedVars.token1TotalSupplyAdjusted
        );
        if (swap0To1_) {
            (v_.cs.tokenInRealReserves, v_.cs.tokenOutRealReserves, v_.cs.tokenInImaginaryReserves, v_.cs.tokenOutImaginaryReserves) = (
                v_.c.token0RealReserves,
                v_.c.token1RealReserves,
                v_.c.token0ImaginaryReserves,
                v_.c.token1ImaginaryReserves
            );
        } else {
            (v_.cs.tokenInRealReserves, v_.cs.tokenOutRealReserves, v_.cs.tokenInImaginaryReserves, v_.cs.tokenOutImaginaryReserves) = (
                v_.c.token1RealReserves,
                v_.c.token0RealReserves,
                v_.c.token1ImaginaryReserves,
                v_.c.token0ImaginaryReserves
            );
        }

        // limiting amtOutAdjusted to be not more than 50% of both (collateral & debt) imaginary tokenOut reserves combined
        // basically, if this throws that means user is trying to swap 0.5x tokenOut if current tokenOut imaginary reserves is x
        // let's take x as token0 here, that means, initially the pool pricing might be:
        // token1Reserve / x and new pool pricing will become token1Reserve / 0.5x (token1Reserve will decrease after swap but for simplicity ignoring that)
        // So pool price is increased by ~50% (oracle will throw error in this case as it only allows 5% price difference but better to limit it before hand)
        unchecked {
            if (v_.s.amtOutAdjusted > (v_.cs.tokenOutImaginaryReserves / 2)) revert(); // FluidDexError(ErrorTypes.DexT1__SwapOutLimitingAmounts);
        }

        // temp2_ = amountInCol_
        v_.s.amtInAdjusted = _getAmountIn(v_.s.amtOutAdjusted, v_.cs.tokenInImaginaryReserves, v_.cs.tokenOutImaginaryReserves);
        v_.s.amtInAdjusted = (v_.s.amtInAdjusted * SIX_DECIMALS) / v_.s.fee;
        swap0To1_
            ? _verifyToken1Reserves(
                (v_.cs.tokenInRealReserves + v_.s.amtInAdjusted),
                (v_.cs.tokenOutRealReserves - v_.s.amtOutAdjusted),
                v_.prices.centerPrice,
                MINIMUM_LIQUIDITY_SWAP
            )
            : _verifyToken0Reserves(
                (v_.cs.tokenOutRealReserves - v_.s.amtOutAdjusted),
                (v_.cs.tokenInRealReserves + v_.s.amtInAdjusted),
                v_.prices.centerPrice,
                MINIMUM_LIQUIDITY_SWAP
            );
        // cutting revenue off of amount in.
        v_.s.amtInAdjusted = (v_.s.amtInAdjusted * v_.s.revenueCut) / EIGHT_DECIMALS;
        v_.s.price = swap0To1_
            ? ((v_.cs.tokenOutImaginaryReserves - v_.s.amtOutAdjusted) * 1e27) / (v_.cs.tokenInImaginaryReserves + v_.s.amtInAdjusted)
            : ((v_.cs.tokenInImaginaryReserves + v_.s.amtInAdjusted) * 1e27) / (v_.cs.tokenOutImaginaryReserves - v_.s.amtOutAdjusted);

        // Converting into normal token amounts
        if (swap0To1_) {
            // only adding uncheck in out amount
            unchecked {
                v_.s.amtOut = (v_.s.amtOutAdjusted * v_.calculatedVars.token1DenominatorPrecision) / v_.calculatedVars.token1NumeratorPrecision;
            }
            amountIn_ = (v_.s.amtInAdjusted * v_.calculatedVars.token0DenominatorPrecision) / v_.calculatedVars.token0NumeratorPrecision;
        } else {
            // only adding uncheck in out amount
            unchecked {
                v_.s.amtOut = (v_.s.amtOutAdjusted * v_.calculatedVars.token0DenominatorPrecision) / v_.calculatedVars.token0NumeratorPrecision;
            }
            amountIn_ = (v_.s.amtInAdjusted * v_.calculatedVars.token1DenominatorPrecision) / v_.calculatedVars.token1NumeratorPrecision;
        }

        if (estimate_) revert(); // FluidDexLiquidityOutput(amountIn_);
        if (amountIn_ > amountInMax_) revert(); // FluidDexError(ErrorTypes.DexT1__ExceedsAmountInMax);

        // If hook exists then calling hook
        v_.temp = (v_.dexVariables2 >> 142) & X30;
        if (v_.temp > 0) {
            v_.s.swap0to1 = swap0To1_;
            _hookVerify(dexKey_, v_.temp, 1, v_.s.swap0to1, v_.s.price);
        }

        // _dexVariables[DEX_TYPE][v_.dexId] = _updateOracle(v_.s.price, v_.prices.centerPrice, v_.dexVariables); // TODO: add this back after adding oracle and remove the updation of v_.dexVariables below
        _dexVariables[DEX_TYPE][v_.dexId] = _updateDexVariables(v_.s.price, v_.prices.centerPrice, v_.dexVariables);

        if (swap0To1_) {
            token0TotalSupplyRawChange_ = int256((amountIn_ * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token0SupplyExchangePrice);
            token1TotalSupplyRawChange_ = -int256((amountOut_ * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token1SupplyExchangePrice);
        } else {
            token0TotalSupplyRawChange_ = -int256((amountOut_ * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token1SupplyExchangePrice);
            token1TotalSupplyRawChange_ = int256((amountIn_ * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token0SupplyExchangePrice);
        }

        v_.calculatedVars.token0TotalSupplyRaw = uint256(int256(v_.calculatedVars.token0TotalSupplyRaw) + token0TotalSupplyRawChange_);
        v_.calculatedVars.token1TotalSupplyRaw = uint256(int256(v_.calculatedVars.token1TotalSupplyRaw) + token1TotalSupplyRawChange_);

        _setTotalSupplyRaw(v_.dexId, v_.calculatedVars.token0TotalSupplyRaw, v_.calculatedVars.token1TotalSupplyRaw);
    }
}

abstract contract UserOperationInternals is Helpers {
    /// @dev This function allows users to deposit tokens in any proportion into the col pool
    /// @param token0Amt_ The amount of token0 to deposit
    /// @param token1Amt_ The amount of token1 to deposit
    /// @param minSharesAmt_ The minimum amount of shares the user expects to receive
    /// @param estimate_ If true, function will revert with estimated shares without executing the deposit
    /// @return shares_ The amount of shares minted for the deposit
    function _deposit(
        DexKey calldata dexKey_,
        uint256 token0Amt_,
        uint256 token1Amt_,
        uint256 minSharesAmt_,
        bool estimate_
    ) internal returns (uint256 shares_, int256 token0TotalSupplyRawChange_, int256 token1TotalSupplyRawChange_) {
        DepositVariables memory v_;

        v_.dexId = keccak256(abi.encode(dexKey_));

        v_.dexVariables = _dexVariables[DEX_TYPE][v_.dexId];
        v_.dexVariables2 = _dexVariables2[DEX_TYPE][v_.dexId];

        v_.calculatedVars = _calculateVars(dexKey_.token0, dexKey_.token1, v_.dexVariables2, v_.dexId);

        if (v_.dexVariables2 & 1 == 0) revert(); // FluidDexError(ErrorTypes.DexT1__DexNotInitialized);

        v_.userSupplyData = _userSupplyData[DEX_TYPE][v_.dexId][msg.sender];

        if (v_.userSupplyData & 1 == 0 && !estimate_) revert(); // FluidDexError(ErrorTypes.DexT1__UserSupplyInNotOn);

        v_.prices = _getPrices(dexKey_, v_.dexVariables, v_.dexVariables2, DEX_TYPE, v_.dexId);

        v_.c = _getCollateralReserves(
            v_.prices.geometricMean,
            v_.prices.upperRange,
            v_.prices.lowerRange,
            v_.calculatedVars.token0TotalSupplyAdjusted,
            v_.calculatedVars.token1TotalSupplyAdjusted
        );
        v_.c2 = v_.c;

        if (token0Amt_ > 0) {
            v_.d.token0AmtAdjusted = (((token0Amt_ - 1) * v_.calculatedVars.token0NumeratorPrecision) / v_.calculatedVars.token0DenominatorPrecision) - 1;
            _verifySwapAndNonPerfectActions(v_.d.token0AmtAdjusted, token0Amt_);
            _verifyMint(v_.d.token0AmtAdjusted, v_.c.token0RealReserves);
        }

        if (token1Amt_ > 0) {
            v_.d.token1AmtAdjusted = (((token1Amt_ - 1) * v_.calculatedVars.token1NumeratorPrecision) / v_.calculatedVars.token1DenominatorPrecision) - 1;
            _verifySwapAndNonPerfectActions(v_.d.token1AmtAdjusted, token1Amt_);
            _verifyMint(v_.d.token1AmtAdjusted, v_.c.token1RealReserves);
        }

        v_.totalSupplyShares = _totalSupplyShares[DEX_TYPE][v_.dexId] & X128;
        if ((v_.c.token0RealReserves > 0) && (v_.c.token1RealReserves > 0)) {
            if (v_.d.token0AmtAdjusted > 0 && v_.d.token1AmtAdjusted > 0) {
                // mint shares in equal proportion
                // v_.temp => expected shares from token0 deposit
                v_.temp = (v_.d.token0AmtAdjusted * 1e18) / v_.c.token0RealReserves;
                // v_.temp2 => expected shares from token1 deposit
                v_.temp2 = (v_.d.token1AmtAdjusted * 1e18) / v_.c.token1RealReserves;
                if (v_.temp > v_.temp2) {
                    // use v_.temp2 shares
                    shares_ = (v_.temp2 * v_.totalSupplyShares) / 1e18;
                    // v_.temp => token0 to swap
                    v_.temp = ((v_.temp - v_.temp2) * v_.c.token0RealReserves) / 1e18;
                    v_.temp2 = 0;
                } else if (v_.temp2 > v_.temp) {
                    // use v_.temp shares
                    shares_ = (v_.temp * v_.totalSupplyShares) / 1e18;
                    // v_.temp2 => token1 to swap
                    v_.temp2 = ((v_.temp2 - v_.temp) * v_.c.token1RealReserves) / 1e18;
                    v_.temp = 0;
                } else {
                    // if equal then revert as swap will not be needed anymore which can create some issue, better to use depositPerfect in this case
                    revert(); // FluidDexError(ErrorTypes.DexT1__InvalidDepositAmts);
                }

                // User deposited in equal proportion here. Hence updating col reserves and the swap will happen on updated col reserves
                v_.c2 = _getUpdatedColReserves(shares_, v_.totalSupplyShares, v_.c, true);

                v_.totalSupplyShares += shares_;
            } else if (v_.d.token0AmtAdjusted > 0) {
                v_.temp = v_.d.token0AmtAdjusted;
                v_.temp2 = 0;
            } else if (v_.d.token1AmtAdjusted > 0) {
                v_.temp = 0;
                v_.temp2 = v_.d.token1AmtAdjusted;
            } else {
                // user sent both amounts as 0
                revert(); // FluidDexError(ErrorTypes.DexT1__InvalidDepositAmts);
            }

            if (v_.temp > 0) {
                // swap token0
                v_.temp = _getSwapAndDeposit(
                    v_.temp, // token0 to divide and swap
                    v_.c2.token1ImaginaryReserves, // token1 imaginary reserves
                    v_.c2.token0ImaginaryReserves, // token0 imaginary reserves
                    v_.c2.token0RealReserves, // token0 real reserves
                    v_.c2.token1RealReserves // token1 real reserves
                );
            } else if (v_.temp2 > 0) {
                // swap token1
                v_.temp = _getSwapAndDeposit(
                    v_.temp2, // token1 to divide and swap
                    v_.c2.token0ImaginaryReserves, // token0 imaginary reserves
                    v_.c2.token1ImaginaryReserves, // token1 imaginary reserves
                    v_.c2.token1RealReserves, // token1 real reserves
                    v_.c2.token0RealReserves // token0 real reserves
                );
            } else {
                // maybe possible to happen due to some precision issue that both are 0
                revert(); // FluidDexError(ErrorTypes.DexT1__DepositAmtsZero);
            }

            // new shares minted from swap & deposit
            v_.temp = (v_.temp * v_.totalSupplyShares) / 1e18;
            // adding fee in case of swap & deposit
            // 1 - fee. If fee is 1% then without fee will be 1e6 - 1e4
            // v_.temp => withdraw fee
            v_.temp = (v_.temp * (SIX_DECIMALS - ((v_.dexVariables2 >> 2) & X17))) / SIX_DECIMALS;
            // final new shares to mint for user
            shares_ += v_.temp;
            // final new collateral shares
            v_.totalSupplyShares += v_.temp;
        } else {
            revert(); // FluidDexError(ErrorTypes.DexT1__InvalidCollateralReserves);
        }

        if (estimate_) revert(); // FluidDexLiquidityOutput(shares_);
        if (shares_ < minSharesAmt_) revert(); // FluidDexError(ErrorTypes.DexT1__SharesMintedLess);

        if (token0Amt_ > 0) {
            _verifyToken1Reserves(
                (v_.c.token0RealReserves + v_.d.token0AmtAdjusted),
                (v_.c.token1RealReserves + v_.d.token1AmtAdjusted),
                v_.prices.centerPrice,
                MINIMUM_LIQUIDITY_USER_OPERATIONS
            );
        }

        if (token1Amt_ > 0) {
            _verifyToken0Reserves(
                (v_.c.token0RealReserves + v_.d.token0AmtAdjusted),
                (v_.c.token1RealReserves + v_.d.token1AmtAdjusted),
                v_.prices.centerPrice,
                MINIMUM_LIQUIDITY_USER_OPERATIONS
            );
        }

        // userSupply_ => v_.temp
        v_.temp = (v_.userSupplyData >> DexSlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64;
        // extracting exisiting shares and then adding new shares in it
        v_.temp = ((v_.temp >> DEFAULT_EXPONENT_SIZE) << (v_.temp & DEFAULT_EXPONENT_MASK));

        // calculate current, updated (expanded etc.) withdrawal limit
        // newWithdrawalLimit_ => v_.temp2
        v_.temp2 = DexCalcs.calcWithdrawalLimitBeforeOperate(v_.userSupplyData, v_.temp);

        v_.temp += shares_;

        _updatingUserSupplyDataOnStorage(v_.userSupplyData, v_.temp, v_.temp2, v_.dexId);

        // updating total col shares in storage
        _updateSupplyShares(v_.totalSupplyShares, v_.dexId);

        token0TotalSupplyRawChange_ = int256((token0Amt_ * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token0SupplyExchangePrice);
        token1TotalSupplyRawChange_ = int256((token1Amt_ * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token1SupplyExchangePrice);

        v_.calculatedVars.token0TotalSupplyRaw = uint256(int256(v_.calculatedVars.token0TotalSupplyRaw) + token0TotalSupplyRawChange_);
        v_.calculatedVars.token1TotalSupplyRaw = uint256(int256(v_.calculatedVars.token1TotalSupplyRaw) + token1TotalSupplyRawChange_);

        _setTotalSupplyRaw(v_.dexId, v_.calculatedVars.token0TotalSupplyRaw, v_.calculatedVars.token1TotalSupplyRaw);
    }

    /// @dev This function allows users to withdraw tokens in any proportion from the col pool
    /// @param token0Amt_ The amount of token0 to withdraw
    /// @param token1Amt_ The amount of token1 to withdraw
    /// @param maxSharesAmt_ The maximum number of shares the user is willing to burn
    /// @return shares_ The number of shares burned for the withdrawal
    function _withdraw(
        DexKey calldata dexKey_,
        uint256 token0Amt_,
        uint256 token1Amt_,
        uint256 maxSharesAmt_,
        bool estimate_
    ) internal returns (uint256 shares_, int256 token0TotalSupplyRawChange_, int256 token1TotalSupplyRawChange_) {
        WithdrawVariables memory v_;

        v_.dexId = keccak256(abi.encode(dexKey_));

        v_.dexVariables = _dexVariables[DEX_TYPE][v_.dexId];
        v_.dexVariables2 = _dexVariables2[DEX_TYPE][v_.dexId];

        v_.calculatedVars = _calculateVars(dexKey_.token0, dexKey_.token1, v_.dexVariables2, v_.dexId);

        if (v_.dexVariables2 & 1 == 0) revert(); // FluidDexError(ErrorTypes.DexT1__DexNotInitialized);

        v_.userSupplyData = _userSupplyData[DEX_TYPE][v_.dexId][msg.sender];

        if (v_.userSupplyData & 1 == 0 && !estimate_) revert(); // FluidDexError(ErrorTypes.DexT1__UserSupplyInNotOn);

        v_.prices = _getPrices(dexKey_, v_.dexVariables, v_.dexVariables2, DEX_TYPE, v_.dexId);

        v_.token0Reserves = v_.calculatedVars.token0TotalSupplyAdjusted;
        v_.token1Reserves = v_.calculatedVars.token1TotalSupplyAdjusted;
        v_.w.token0ReservesInitial = v_.token0Reserves;
        v_.w.token1ReservesInitial = v_.token1Reserves;

        if (token0Amt_ > 0) {
            unchecked {
                v_.w.token0AmtAdjusted = (((token0Amt_ + 1) * v_.calculatedVars.token0NumeratorPrecision) / v_.calculatedVars.token0DenominatorPrecision) + 1;
            }
            _verifySwapAndNonPerfectActions(v_.w.token0AmtAdjusted, token0Amt_);
            _verifyRedeem(v_.w.token0AmtAdjusted, v_.token0Reserves);
        }

        if (token1Amt_ > 0) {
            unchecked {
                v_.w.token1AmtAdjusted = (((token1Amt_ + 1) * v_.calculatedVars.token1NumeratorPrecision) / v_.calculatedVars.token1DenominatorPrecision) + 1;
            }
            _verifySwapAndNonPerfectActions(v_.w.token1AmtAdjusted, token1Amt_);
            _verifyRedeem(v_.w.token1AmtAdjusted, v_.token1Reserves);
        }

        v_.totalSupplyShares = _totalSupplyShares[DEX_TYPE][v_.dexId] & X128;
        if ((v_.token0Reserves > 0) && (v_.token1Reserves > 0)) {
            if (v_.w.token0AmtAdjusted > 0 && v_.w.token1AmtAdjusted > 0) {
                // mint shares in equal proportion
                // v_.temp => expected shares from token0 withdraw
                v_.temp = (v_.w.token0AmtAdjusted * 1e18) / v_.token0Reserves;
                // v_.temp2 => expected shares from token1 withdraw
                v_.temp2 = (v_.w.token1AmtAdjusted * 1e18) / v_.token1Reserves;
                if (v_.temp > v_.temp2) {
                    // use v_.temp2 shares
                    shares_ = ((v_.temp2 * v_.totalSupplyShares) / 1e18);
                    // v_.temp => token0 to swap
                    v_.temp = ((v_.temp - v_.temp2) * v_.token0Reserves) / 1e18;
                    v_.temp2 = 0;
                } else if (v_.temp2 > v_.temp) {
                    // use temp1_ shares
                    shares_ = ((v_.temp * v_.totalSupplyShares) / 1e18);
                    // v_.temp2 => token1 to swap
                    v_.temp2 = ((v_.temp2 - v_.temp) * v_.token1Reserves) / 1e18;
                    v_.temp = 0;
                } else {
                    // if equal then revert as swap will not be needed anymore which can create some issue, better to use withdraw in perfect proportion for this
                    revert(); // FluidDexError(ErrorTypes.DexT1__InvalidWithdrawAmts);
                }

                // User withdrew in equal proportion here. Hence updating col reserves and the swap will happen on updated col reserves
                v_.token0Reserves = v_.token0Reserves - ((v_.token0Reserves * shares_) / v_.totalSupplyShares);
                v_.token1Reserves = v_.token1Reserves - ((v_.token1Reserves * shares_) / v_.totalSupplyShares);
                v_.totalSupplyShares -= shares_;
            } else if (v_.w.token0AmtAdjusted > 0) {
                v_.temp = v_.w.token0AmtAdjusted;
                v_.temp2 = 0;
            } else if (v_.w.token1AmtAdjusted > 0) {
                v_.temp = 0;
                v_.temp2 = v_.w.token1AmtAdjusted;
            } else {
                // user sent both amounts as 0
                revert(); // FluidDexError(ErrorTypes.DexT1__WithdrawAmtsZero);
            }

            if (v_.prices.geometricMean < 1e27) {
                (v_.token0ImaginaryReservesOutsideRange, v_.token1ImaginaryReservesOutsideRange) = _calculateReservesOutsideRange(
                    v_.prices.geometricMean,
                    v_.prices.upperRange,
                    (v_.token0Reserves - v_.temp),
                    (v_.token1Reserves - v_.temp2)
                );
            } else {
                // inversing, something like `xy = k` so for calculation we are making everything related to x into y & y into x
                // 1 / geometricMean for new geometricMean
                // 1 / lowerRange will become upper range
                // 1 / upperRange will become lower range
                (v_.token1ImaginaryReservesOutsideRange, v_.token0ImaginaryReservesOutsideRange) = _calculateReservesOutsideRange(
                    (1e54 / v_.prices.geometricMean),
                    (1e54 / v_.prices.lowerRange),
                    (v_.token1Reserves - v_.temp2),
                    (v_.token0Reserves - v_.temp)
                );
            }

            if (v_.temp > 0) {
                // swap into token0
                v_.temp = _getWithdrawAndSwap(
                    v_.token0Reserves, // token0 real reserves
                    v_.token1Reserves, // token1 real reserves
                    v_.token0ImaginaryReservesOutsideRange, // token0 imaginary reserves
                    v_.token1ImaginaryReservesOutsideRange, // token1 imaginary reserves
                    v_.temp // token0 to divide and swap into
                );
            } else if (v_.temp2 > 0) {
                // swap into token1
                v_.temp = _getWithdrawAndSwap(
                    v_.token1Reserves, // token1 real reserves
                    v_.token0Reserves, // token0 real reserves
                    v_.token1ImaginaryReservesOutsideRange, // token1 imaginary reserves
                    v_.token0ImaginaryReservesOutsideRange, // token0 imaginary reserves
                    v_.temp2 // token0 to divide and swap into
                );
            } else {
                // maybe possible to happen due to some precision issue that both are 0
                revert(); // FluidDexError(ErrorTypes.DexT1__WithdrawAmtsZero);
            }

            // shares to burn from withdraw & swap
            v_.temp = ((v_.temp * v_.totalSupplyShares) / 1e18);
            // adding fee in case of withdraw & swap
            // 1 + fee. If fee is 1% then withdrawing withFepex_ will be 1e6 + 1e4
            v_.temp = (v_.temp * (SIX_DECIMALS + ((v_.dexVariables2 >> 2) & X17))) / SIX_DECIMALS;
            // updating shares to burn for user
            shares_ += v_.temp;
            // final new collateral shares
            v_.totalSupplyShares -= v_.temp;
        } else {
            revert(); // FluidDexError(ErrorTypes.DexT1__InvalidCollateralReserves);
        }

        if (estimate_) revert(); // FluidDexLiquidityOutput(shares_);

        if (shares_ > maxSharesAmt_) revert(); // FluidDexError(ErrorTypes.DexT1__WithdrawExcessSharesBurn);

        // userSupply_ => v_.temp
        v_.temp = (v_.userSupplyData >> DexSlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64;
        v_.temp = (v_.temp >> DEFAULT_EXPONENT_SIZE) << (v_.temp & DEFAULT_EXPONENT_MASK);

        // calculate current, updated (expanded etc.) withdrawal limit
        // newWithdrawalLimit_ => v_.temp2
        v_.temp2 = DexCalcs.calcWithdrawalLimitBeforeOperate(v_.userSupplyData, v_.temp);

        v_.temp -= shares_;

        // withdrawal limit reached
        if (v_.temp < v_.temp2) revert(); // FluidDexError(ErrorTypes.DexT1__WithdrawLimitReached);

        _updatingUserSupplyDataOnStorage(v_.userSupplyData, v_.temp, v_.temp2, v_.dexId);

        // updating total col shares in storage
        _updateSupplyShares(v_.totalSupplyShares, v_.dexId);

        if (v_.w.token0AmtAdjusted > 0) {
            _verifyToken0Reserves(
                (v_.w.token0ReservesInitial - v_.w.token0AmtAdjusted),
                (v_.w.token1ReservesInitial - v_.w.token1AmtAdjusted),
                v_.prices.centerPrice,
                MINIMUM_LIQUIDITY_USER_OPERATIONS
            );
        }

        if (v_.w.token1AmtAdjusted > 0) {
            _verifyToken1Reserves(
                (v_.w.token0ReservesInitial - v_.w.token0AmtAdjusted),
                (v_.w.token1ReservesInitial - v_.w.token1AmtAdjusted),
                v_.prices.centerPrice,
                MINIMUM_LIQUIDITY_USER_OPERATIONS
            );
        }

        token0TotalSupplyRawChange_ = -int256((token0Amt_ * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token0SupplyExchangePrice);
        token1TotalSupplyRawChange_ = -int256((token1Amt_ * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token1SupplyExchangePrice);

        v_.calculatedVars.token0TotalSupplyRaw = uint256(int256(v_.calculatedVars.token0TotalSupplyRaw) + token0TotalSupplyRawChange_);
        v_.calculatedVars.token1TotalSupplyRaw = uint256(int256(v_.calculatedVars.token1TotalSupplyRaw) + token1TotalSupplyRawChange_);

        _setTotalSupplyRaw(v_.dexId, v_.calculatedVars.token0TotalSupplyRaw, v_.calculatedVars.token1TotalSupplyRaw);
    }

    /// @dev Deposit tokens in equal proportion to the current pool ratio
    /// @param shares_ The number of shares to mint
    /// @param maxToken0Deposit_ Maximum amount of token0 to deposit
    /// @param maxToken1Deposit_ Maximum amount of token1 to deposit
    /// @param estimate_ If true, function will revert with estimated deposit amounts without executing the deposit
    /// @return token0Amt_ Amount of token0 deposited
    /// @return token1Amt_ Amount of token1 deposited
    function _depositPerfect(
        DexKey calldata dexKey_,
        uint256 shares_,
        uint256 maxToken0Deposit_,
        uint256 maxToken1Deposit_,
        bool estimate_
    ) internal returns (uint256 token0Amt_, uint256 token1Amt_, int256 token0TotalSupplyRawChange_, int256 token1TotalSupplyRawChange_) {
        DepositPerfectVariables memory v_;

        v_.dexId = keccak256(abi.encode(dexKey_));
        v_.dexVariables2 = _dexVariables2[DEX_TYPE][v_.dexId];

        v_.calculatedVars = _calculateVars(dexKey_.token0, dexKey_.token1, v_.dexVariables2, v_.dexId);

        if (v_.dexVariables2 & 1 == 0) revert(); // FluidDexError(ErrorTypes.DexT1__DexNotInitialized);

        v_.userSupplyData = _userSupplyData[DEX_TYPE][v_.dexId][msg.sender];

        // user collateral configs are not set yet
        if (v_.userSupplyData & 1 == 0 && !estimate_) revert(); // FluidDexError(ErrorTypes.DexT1__UserSupplyInNotOn);

        v_.totalSupplyShares = _totalSupplyShares[DEX_TYPE][v_.dexId];

        _verifyMint(shares_, v_.totalSupplyShares);

        // Adding col liquidity in equal proportion
        // Adding + 1, to keep protocol on the winning side
        token0Amt_ = (v_.calculatedVars.token0TotalSupplyAdjusted * shares_) / v_.totalSupplyShares;
        token1Amt_ = (v_.calculatedVars.token1TotalSupplyAdjusted * shares_) / v_.totalSupplyShares;

        // converting back into normal token amounts
        // Adding + 1, to keep protocol on the winning side
        token0Amt_ = (((token0Amt_ + 1) * v_.calculatedVars.token0DenominatorPrecision) / v_.calculatedVars.token0NumeratorPrecision) + 1;
        token1Amt_ = (((token1Amt_ + 1) * v_.calculatedVars.token1DenominatorPrecision) / v_.calculatedVars.token1NumeratorPrecision) + 1;

        if (estimate_) revert(); // FluidDexPerfectLiquidityOutput(token0Amt_, token1Amt_);

        if (token0Amt_ > maxToken0Deposit_ || token1Amt_ > maxToken1Deposit_) {
            revert(); // FluidDexError(ErrorTypes.DexT1__AboveDepositMax);
        }

        v_.userSupply = (v_.userSupplyData >> DexSlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64;
        // extracting exisiting shares and then adding new shares in it
        v_.userSupply = ((v_.userSupply >> DEFAULT_EXPONENT_SIZE) << (v_.userSupply & DEFAULT_EXPONENT_MASK));

        // calculate current, updated (expanded etc.) withdrawal limit
        v_.newWithdrawalLimit = DexCalcs.calcWithdrawalLimitBeforeOperate(v_.userSupplyData, v_.userSupply);

        v_.userSupply += shares_;

        // bigNumber the shares are not same as before
        _updatingUserSupplyDataOnStorage(v_.userSupplyData, v_.userSupply, v_.newWithdrawalLimit, v_.dexId);

        _updateSupplyShares(v_.totalSupplyShares + shares_, v_.dexId);

        token0TotalSupplyRawChange_ = int256((token0Amt_ * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token0SupplyExchangePrice);
        token1TotalSupplyRawChange_ = int256((token1Amt_ * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token1SupplyExchangePrice);

        v_.calculatedVars.token0TotalSupplyRaw = uint256(int256(v_.calculatedVars.token0TotalSupplyRaw) + token0TotalSupplyRawChange_);
        v_.calculatedVars.token1TotalSupplyRaw = uint256(int256(v_.calculatedVars.token1TotalSupplyRaw) + token1TotalSupplyRawChange_);

        _setTotalSupplyRaw(v_.dexId, v_.calculatedVars.token0TotalSupplyRaw, v_.calculatedVars.token1TotalSupplyRaw);
    }

    /// @dev This function allows users to withdraw a perfect amount of collateral liquidity
    /// @param shares_ The number of shares to withdraw
    /// @param minToken0Withdraw_ The minimum amount of token0 the user is willing to accept
    /// @param minToken1Withdraw_ The minimum amount of token1 the user is willing to accept
    /// @return token0Amt_ The amount of token0 withdrawn
    /// @return token1Amt_ The amount of token1 withdrawn
    function _withdrawPerfect(
        DexKey calldata dexKey_,
        uint256 shares_,
        uint256 minToken0Withdraw_,
        uint256 minToken1Withdraw_,
        bool estimate_
    ) internal returns (uint256 token0Amt_, uint256 token1Amt_, int256 token0TotalSupplyRawChange_, int256 token1TotalSupplyRawChange_) {
        WithdrawPerfectVariables memory v_;

        v_.dexId = keccak256(abi.encode(dexKey_));
        v_.dexVariables2 = _dexVariables2[DEX_TYPE][v_.dexId];

        v_.calculatedVars = _calculateVars(dexKey_.token0, dexKey_.token1, v_.dexVariables2, v_.dexId);

        if (v_.dexVariables2 & 1 == 0) revert(); // FluidDexError(ErrorTypes.DexT1__PoolNotInitialized);

        v_.userSupplyData = _userSupplyData[DEX_TYPE][v_.dexId][msg.sender];

        if (v_.userSupplyData & 1 == 0 && !estimate_) {
            revert(); // FluidDexError(ErrorTypes.DexT1__UserSupplyInNotOn);
        }

        v_.totalSupplyShares = _totalSupplyShares[DEX_TYPE][v_.dexId] & X128;

        _verifyRedeem(shares_, v_.totalSupplyShares);

        // Withdrawing col liquidity in equal proportion
        token0Amt_ = (v_.calculatedVars.token0TotalSupplyAdjusted * shares_) / v_.totalSupplyShares;
        token1Amt_ = (v_.calculatedVars.token1TotalSupplyAdjusted * shares_) / v_.totalSupplyShares;

        // converting back into normal token amounts
        token0Amt_ = (((token0Amt_ - 1) * v_.calculatedVars.token0DenominatorPrecision) / v_.calculatedVars.token0NumeratorPrecision) - 1;
        token1Amt_ = (((token1Amt_ - 1) * v_.calculatedVars.token1DenominatorPrecision) / v_.calculatedVars.token1NumeratorPrecision) - 1;

        if (estimate_) revert(); // FluidDexPerfectLiquidityOutput(token0Amt_, token1Amt_);

        if (token0Amt_ < minToken0Withdraw_ || token1Amt_ < minToken1Withdraw_) {
            revert(); // FluidDexError(ErrorTypes.DexT1__BelowWithdrawMin);
        }

        v_.userSupply = (v_.userSupplyData >> DexSlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64;
        v_.userSupply = (v_.userSupply >> DEFAULT_EXPONENT_SIZE) << (v_.userSupply & DEFAULT_EXPONENT_MASK);

        // calculate current, updated (expanded etc.) withdrawal limit
        v_.newWithdrawalLimit = DexCalcs.calcWithdrawalLimitBeforeOperate(v_.userSupplyData, v_.userSupply);
        v_.userSupply -= shares_;

        // withdraws below limit
        if (v_.userSupply < v_.newWithdrawalLimit) revert(); // FluidDexError(ErrorTypes.DexT1__WithdrawLimitReached);

        _updatingUserSupplyDataOnStorage(v_.userSupplyData, v_.userSupply, v_.newWithdrawalLimit, v_.dexId);

        v_.totalSupplyShares = v_.totalSupplyShares - shares_;
        _updateSupplyShares(v_.totalSupplyShares, v_.dexId);

        token0TotalSupplyRawChange_ = -int256((token0Amt_ * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token0SupplyExchangePrice);
        token1TotalSupplyRawChange_ = -int256((token1Amt_ * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token1SupplyExchangePrice);

        v_.calculatedVars.token0TotalSupplyRaw = uint256(int256(v_.calculatedVars.token0TotalSupplyRaw) + token0TotalSupplyRawChange_);
        v_.calculatedVars.token1TotalSupplyRaw = uint256(int256(v_.calculatedVars.token1TotalSupplyRaw) + token1TotalSupplyRawChange_);

        _setTotalSupplyRaw(v_.dexId, v_.calculatedVars.token0TotalSupplyRaw, v_.calculatedVars.token1TotalSupplyRaw);
    }

    /// @dev This function allows users to withdraw their collateral with perfect shares in one token
    /// @param shares_ The number of shares to burn for withdrawal
    /// @param minToken0_ The minimum amount of token0 the user expects to receive (set to 0 if withdrawing in token1)
    /// @param minToken1_ The minimum amount of token1 the user expects to receive (set to 0 if withdrawing in token0)
    /// @return withdrawAmt_ The amount of tokens withdrawn in the chosen token
    function _withdrawPerfectInOneToken(
        DexKey calldata dexKey_,
        uint256 shares_,
        uint256 minToken0_,
        uint256 minToken1_,
        bool estimate_
    ) internal returns (uint256 withdrawAmt_, int256 token0TotalSupplyRawChange_, int256 token1TotalSupplyRawChange_) {
        WithdrawPerfectInOneTokenVariables memory v_;

        v_.dexId = keccak256(abi.encode(dexKey_));

        v_.dexVariables = _dexVariables[DEX_TYPE][v_.dexId];
        v_.dexVariables2 = _dexVariables2[DEX_TYPE][v_.dexId];

        CalculatedVars memory calculatedVars_ = _calculateVars(dexKey_.token0, dexKey_.token1, v_.dexVariables2, v_.dexId);

        if (v_.dexVariables2 & 1 == 0) revert(); // FluidDexError(ErrorTypes.DexT1__PoolNotInitialized);

        v_.userSupplyData = _userSupplyData[DEX_TYPE][v_.dexId][msg.sender];

        if (v_.userSupplyData & 1 == 0 && !estimate_) {
            revert(); // FluidDexError(ErrorTypes.DexT1__UserSupplyInNotOn);
        }

        if ((minToken0_ > 0 && minToken1_ > 0) || (minToken0_ == 0 && minToken1_ == 0)) {
            // only 1 token should be > 0
            revert(); // FluidDexError(ErrorTypes.DexT1__InvalidWithdrawAmts);
        }

        Prices memory prices_ = _getPrices(dexKey_, v_.dexVariables, v_.dexVariables2, DEX_TYPE, v_.dexId);

        v_.totalSupplyShares = _totalSupplyShares[DEX_TYPE][v_.dexId];

        _verifyRedeem(shares_, v_.totalSupplyShares);

        v_.c = _getCollateralReserves(
            prices_.geometricMean,
            prices_.upperRange,
            prices_.lowerRange,
            calculatedVars_.token0TotalSupplyAdjusted,
            calculatedVars_.token1TotalSupplyAdjusted
        );

        if ((v_.c.token0RealReserves == 0) || (v_.c.token1RealReserves == 0)) {
            revert(); // FluidDexError(ErrorTypes.DexT1__InvalidCollateralReserves);
        }

        v_.c2 = _getUpdatedColReserves(shares_, v_.totalSupplyShares, v_.c, false);
        // Storing exact token0 & token1 raw/adjusted withdrawal amount after burning shares
        v_.token0Amt = v_.c.token0RealReserves - v_.c2.token0RealReserves - 1;
        v_.token1Amt = v_.c.token1RealReserves - v_.c2.token1RealReserves - 1;

        if (minToken0_ > 0) {
            // user wants to withdraw entirely in token0, hence swapping token1 into token0
            v_.token0Amt += _getAmountOut(v_.token1Amt, v_.c2.token1ImaginaryReserves, v_.c2.token0ImaginaryReserves);
            v_.token1Amt = 0;
            _verifyToken0Reserves((v_.c.token0RealReserves - v_.token0Amt), v_.c.token1RealReserves, prices_.centerPrice, MINIMUM_LIQUIDITY_USER_OPERATIONS);

            // converting v_.token0Amt from raw/adjusted to normal token amount
            v_.token0Amt = (((v_.token0Amt - 1) * calculatedVars_.token0DenominatorPrecision) / calculatedVars_.token0NumeratorPrecision) - 1;

            // deducting fee on withdrawing in 1 token
            v_.token0Amt = (v_.token0Amt * (SIX_DECIMALS - ((v_.dexVariables2 >> 2) & X17))) / SIX_DECIMALS;

            withdrawAmt_ = v_.token0Amt;
            if (estimate_) revert(); //  FluidDexLiquidityOutput(withdrawAmt_);
            if (withdrawAmt_ < minToken0_) revert(); // FluidDexError(ErrorTypes.DexT1__WithdrawalNotEnough);

            token0TotalSupplyRawChange_ = -int256((v_.token0Amt * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / calculatedVars_.token0SupplyExchangePrice);

            calculatedVars_.token0TotalSupplyRaw = uint256(int256(calculatedVars_.token0TotalSupplyRaw) + token0TotalSupplyRawChange_);

            _setTotalSupplyRaw(v_.dexId, calculatedVars_.token0TotalSupplyRaw, calculatedVars_.token1TotalSupplyRaw);
        } else {
            // user wants to withdraw entirely in token1, hence swapping token0 into token1
            v_.token1Amt += _getAmountOut(v_.token0Amt, v_.c2.token0ImaginaryReserves, v_.c2.token1ImaginaryReserves);
            v_.token0Amt = 0;
            _verifyToken1Reserves(v_.c.token0RealReserves, (v_.c.token1RealReserves - v_.token1Amt), prices_.centerPrice, MINIMUM_LIQUIDITY_USER_OPERATIONS);

            // converting v_.token1Amt from raw/adjusted to normal token amount
            v_.token1Amt = (((v_.token1Amt - 1) * calculatedVars_.token1DenominatorPrecision) / calculatedVars_.token1NumeratorPrecision) - 1;

            // deducting fee on withdrawing in 1 token
            v_.token1Amt = (v_.token1Amt * (SIX_DECIMALS - ((v_.dexVariables2 >> 2) & X17))) / SIX_DECIMALS;

            withdrawAmt_ = v_.token1Amt;
            if (estimate_) revert(); //  FluidDexLiquidityOutput(withdrawAmt_);
            if (withdrawAmt_ < minToken1_) revert(); // FluidDexError(ErrorTypes.DexT1__WithdrawalNotEnough);

            token1TotalSupplyRawChange_ = -int256((v_.token1Amt * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / calculatedVars_.token1SupplyExchangePrice);

            calculatedVars_.token1TotalSupplyRaw = uint256(int256(calculatedVars_.token1TotalSupplyRaw) + token1TotalSupplyRawChange_);

            _setTotalSupplyRaw(v_.dexId, calculatedVars_.token0TotalSupplyRaw, calculatedVars_.token1TotalSupplyRaw);
        }

        v_.userSupply = (v_.userSupplyData >> DexSlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64;
        v_.userSupply = (v_.userSupply >> DEFAULT_EXPONENT_SIZE) << (v_.userSupply & DEFAULT_EXPONENT_MASK);

        // calculate current, updated (expanded etc.) withdrawal limit
        // v_.temp => newWithdrawalLimit_
        v_.temp = DexCalcs.calcWithdrawalLimitBeforeOperate(v_.userSupplyData, v_.userSupply);

        v_.userSupply -= shares_;

        // withdraws below limit
        if (v_.userSupply < v_.temp) revert(); // FluidDexError(ErrorTypes.DexT1__WithdrawLimitReached);

        _updatingUserSupplyDataOnStorage(v_.userSupplyData, v_.userSupply, v_.temp, v_.dexId);

        v_.totalSupplyShares = v_.totalSupplyShares - shares_;
        _updateSupplyShares(v_.totalSupplyShares, v_.dexId);
    }
}

abstract contract CoreInternals is SwapInternals, UserOperationInternals {}
