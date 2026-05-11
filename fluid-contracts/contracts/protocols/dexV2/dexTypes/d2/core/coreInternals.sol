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
    ) internal returns (uint256 amountOut_, int256 token0TotalBorrowRawChange_, int256 token1TotalBorrowRawChange_) {
        SwapInVariables memory v_;

        v_.dexId = keccak256(abi.encode(dexKey_));

        v_.dexVariables = _dexVariables[DEX_TYPE][v_.dexId];
        v_.dexVariables2 = _dexVariables2[DEX_TYPE][v_.dexId];

        v_.calculatedVars = _calculateVars(dexKey_.token0, dexKey_.token1, v_.dexVariables2, v_.dexId);

        if (v_.dexVariables2 & 1 == 0) revert(); // FluidDexError(ErrorTypes.DexT1__DexNotInitialized);
        if ((v_.dexVariables2 >> 255) == 1) revert(); // FluidDexError(ErrorTypes.DexT1__SwapAndArbitragePaused);

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

        v_.d = _getDebtReserves(
            v_.prices.geometricMean,
            v_.prices.upperRange,
            v_.prices.lowerRange,
            v_.calculatedVars.token0TotalBorrowAdjusted,
            v_.calculatedVars.token1TotalBorrowAdjusted
        );
        if (swap0To1_) {
            (
                v_.ds.tokenInDebt,
                v_.ds.tokenOutDebt,
                v_.ds.tokenInRealReserves,
                v_.ds.tokenOutRealReserves,
                v_.ds.tokenInImaginaryReserves,
                v_.ds.tokenOutImaginaryReserves
            ) = (v_.d.token0Debt, v_.d.token1Debt, v_.d.token0RealReserves, v_.d.token1RealReserves, v_.d.token0ImaginaryReserves, v_.d.token1ImaginaryReserves);
        } else {
            (
                v_.ds.tokenInDebt,
                v_.ds.tokenOutDebt,
                v_.ds.tokenInRealReserves,
                v_.ds.tokenOutRealReserves,
                v_.ds.tokenInImaginaryReserves,
                v_.ds.tokenOutImaginaryReserves
            ) = (v_.d.token1Debt, v_.d.token0Debt, v_.d.token1RealReserves, v_.d.token0RealReserves, v_.d.token1ImaginaryReserves, v_.d.token0ImaginaryReserves);
        }

        // limiting amtInAdjusted to be not more than 50% of debt imaginary tokenIn reserves combined
        // basically, if this throws that means user is trying to swap 0.5x tokenIn if current tokenIn imaginary reserves is x
        // let's take x as token0 here, that means, initially the pool pricing might be:
        // token1Reserve / x and new pool pricing will become token1Reserve / 1.5x (token1Reserve will decrease after swap but for simplicity ignoring that)
        // So pool price is decreased by ~33.33% (oracle will throw error in this case as it only allows 5% price difference but better to limit it before hand)
        unchecked {
            if (v_.s.amtInAdjusted > ((v_.ds.tokenInImaginaryReserves) / 2)) revert(); // FluidDexError(ErrorTypes.DexT1__SwapInLimitingAmounts);
        }

        v_.s.amtOutAdjusted = _getAmountOut(((v_.s.amtInAdjusted * v_.s.fee) / SIX_DECIMALS), v_.ds.tokenInImaginaryReserves, v_.ds.tokenOutImaginaryReserves);
        swap0To1_
            ? _verifyToken1Reserves(
                (v_.ds.tokenInRealReserves + v_.s.amtInAdjusted),
                (v_.ds.tokenOutRealReserves - v_.s.amtOutAdjusted),
                v_.prices.centerPrice,
                MINIMUM_LIQUIDITY_SWAP
            )
            : _verifyToken0Reserves(
                (v_.ds.tokenOutRealReserves - v_.s.amtOutAdjusted),
                (v_.ds.tokenInRealReserves + v_.s.amtInAdjusted),
                v_.prices.centerPrice,
                MINIMUM_LIQUIDITY_SWAP
            );

        v_.s.amtInAdjusted = (v_.s.amtInAdjusted * v_.s.revenueCut) / EIGHT_DECIMALS;

        // new pool price from debt pool
        v_.s.price = swap0To1_
            ? ((v_.ds.tokenOutImaginaryReserves - v_.s.amtOutAdjusted) * 1e27) / (v_.ds.tokenInImaginaryReserves + v_.s.amtInAdjusted)
            : ((v_.ds.tokenInImaginaryReserves + v_.s.amtInAdjusted) * 1e27) / (v_.ds.tokenOutImaginaryReserves - v_.s.amtOutAdjusted);

        // converting into normal token amounts
        if (swap0To1_) {
            v_.s.amtIn = ((v_.s.amtInAdjusted * v_.calculatedVars.token0DenominatorPrecision) / v_.calculatedVars.token0NumeratorPrecision);
            // only adding uncheck in out amount
            unchecked {
                amountOut_ = ((v_.s.amtOutAdjusted * v_.calculatedVars.token1DenominatorPrecision) / v_.calculatedVars.token1NumeratorPrecision);
            }
        } else {
            v_.s.amtIn = ((v_.s.amtInAdjusted * v_.calculatedVars.token1DenominatorPrecision) / v_.calculatedVars.token1NumeratorPrecision);
            // only adding uncheck in out amount
            unchecked {
                amountOut_ = ((v_.s.amtOutAdjusted * v_.calculatedVars.token0DenominatorPrecision) / v_.calculatedVars.token0NumeratorPrecision);
            }
        }

        // if address dead then reverting with amountOut
        if (estimate_) revert(); // FluidDexSwapResult(amountOut_);

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
            token0TotalBorrowRawChange_ = int256((amountIn_ * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token0BorrowExchangePrice);
            token1TotalBorrowRawChange_ = -int256((amountOut_ * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token1BorrowExchangePrice);
        } else {
            token0TotalBorrowRawChange_ = -int256((amountOut_ * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token1BorrowExchangePrice);
            token1TotalBorrowRawChange_ = int256((amountIn_ * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token0BorrowExchangePrice);
        }

        v_.calculatedVars.token0TotalBorrowRaw = uint256(int256(v_.calculatedVars.token0TotalBorrowRaw) + token0TotalBorrowRawChange_);
        v_.calculatedVars.token1TotalBorrowRaw = uint256(int256(v_.calculatedVars.token1TotalBorrowRaw) + token1TotalBorrowRawChange_);

        _setTotalBorrowRaw(v_.dexId, v_.calculatedVars.token0TotalBorrowRaw, v_.calculatedVars.token1TotalBorrowRaw);
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
    ) internal returns (uint256 amountIn_, int256 token0TotalBorrowRawChange_, int256 token1TotalBorrowRawChange_) {
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

        v_.d = _getDebtReserves(
            v_.prices.geometricMean,
            v_.prices.upperRange,
            v_.prices.lowerRange,
            v_.calculatedVars.token0TotalBorrowAdjusted,
            v_.calculatedVars.token1TotalBorrowAdjusted
        );
        if (swap0To1_) {
            (
                v_.ds.tokenInDebt,
                v_.ds.tokenOutDebt,
                v_.ds.tokenInRealReserves,
                v_.ds.tokenOutRealReserves,
                v_.ds.tokenInImaginaryReserves,
                v_.ds.tokenOutImaginaryReserves
            ) = (v_.d.token0Debt, v_.d.token1Debt, v_.d.token0RealReserves, v_.d.token1RealReserves, v_.d.token0ImaginaryReserves, v_.d.token1ImaginaryReserves);
        } else {
            (
                v_.ds.tokenInDebt,
                v_.ds.tokenOutDebt,
                v_.ds.tokenInRealReserves,
                v_.ds.tokenOutRealReserves,
                v_.ds.tokenInImaginaryReserves,
                v_.ds.tokenOutImaginaryReserves
            ) = (v_.d.token1Debt, v_.d.token0Debt, v_.d.token1RealReserves, v_.d.token0RealReserves, v_.d.token1ImaginaryReserves, v_.d.token0ImaginaryReserves);
        }

        // limiting amtOutAdjusted to be not more than 50% of both (collateral & debt) imaginary tokenOut reserves combined
        // basically, if this throws that means user is trying to swap 0.5x tokenOut if current tokenOut imaginary reserves is x
        // let's take x as token0 here, that means, initially the pool pricing might be:
        // token1Reserve / x and new pool pricing will become token1Reserve / 0.5x (token1Reserve will decrease after swap but for simplicity ignoring that)
        // So pool price is increased by ~50% (oracle will throw error in this case as it only allows 5% price difference but better to limit it before hand)
        unchecked {
            if (v_.s.amtOutAdjusted > (v_.ds.tokenOutImaginaryReserves / 2)) revert(); // FluidDexError(ErrorTypes.DexT1__SwapOutLimitingAmounts);
        }

        // temp4_ = amountInDebt_
        v_.s.amtInAdjusted = _getAmountIn(v_.s.amtOutAdjusted, v_.ds.tokenInImaginaryReserves, v_.ds.tokenOutImaginaryReserves);
        v_.s.amtInAdjusted = (v_.s.amtInAdjusted * SIX_DECIMALS) / v_.s.fee;
        swap0To1_
            ? _verifyToken1Reserves(
                (v_.ds.tokenInRealReserves + amountIn_),
                (v_.ds.tokenOutRealReserves - v_.s.amtOutAdjusted),
                v_.prices.centerPrice,
                MINIMUM_LIQUIDITY_SWAP
            )
            : _verifyToken0Reserves(
                (v_.ds.tokenOutRealReserves - v_.s.amtOutAdjusted),
                (v_.ds.tokenInRealReserves + amountIn_),
                v_.prices.centerPrice,
                MINIMUM_LIQUIDITY_SWAP
            );

        // cutting revenue off of amount in.
        v_.s.amtInAdjusted = (v_.s.amtInAdjusted * v_.s.revenueCut) / EIGHT_DECIMALS;

        // new pool price from debt pool
        v_.s.price = swap0To1_
            ? ((v_.ds.tokenOutImaginaryReserves - v_.s.amtOutAdjusted) * 1e27) / (v_.ds.tokenInImaginaryReserves + v_.s.amtInAdjusted)
            : ((v_.ds.tokenInImaginaryReserves + v_.s.amtInAdjusted) * 1e27) / (v_.ds.tokenOutImaginaryReserves - v_.s.amtOutAdjusted);

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

        // If address dead then reverting with amountIn
        if (estimate_) revert(); // FluidDexSwapResult(amountIn_);

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
            token0TotalBorrowRawChange_ = int256((amountIn_ * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token0BorrowExchangePrice);
            token1TotalBorrowRawChange_ = -int256((amountOut_ * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token1BorrowExchangePrice);
        } else {
            token0TotalBorrowRawChange_ = -int256((amountOut_ * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token1BorrowExchangePrice);
            token1TotalBorrowRawChange_ = int256((amountIn_ * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token0BorrowExchangePrice);
        }

        v_.calculatedVars.token0TotalBorrowRaw = uint256(int256(v_.calculatedVars.token0TotalBorrowRaw) + token0TotalBorrowRawChange_);
        v_.calculatedVars.token1TotalBorrowRaw = uint256(int256(v_.calculatedVars.token1TotalBorrowRaw) + token1TotalBorrowRawChange_);

        _setTotalBorrowRaw(v_.dexId, v_.calculatedVars.token0TotalBorrowRaw, v_.calculatedVars.token1TotalBorrowRaw);
    }
}

abstract contract UserOperationInternals is Helpers {
    struct BorrowVariables {
        bytes32 dexId;
        uint256 dexVariables;
        uint256 dexVariables2;
        CalculatedVars calculatedVars;
        uint256 userBorrowData;
        BorrowDebtMemory b;
        Prices prices;
        uint256 token0Debt;
        uint256 token1Debt;
        uint256 temp;
        uint256 temp2;
        uint256 totalBorrowShares;
        uint256 token0FinalImaginaryReserves;
        uint256 token1FinalImaginaryReserves;
    }

    /// @dev This function allows users to borrow tokens in any proportion from the debt pool
    /// @param token0Amt_ The amount of token0 to borrow
    /// @param token1Amt_ The amount of token1 to borrow
    /// @param maxSharesAmt_ The maximum amount of shares the user is willing to receive
    /// @param estimate_ If true, function will revert with estimated shares without executing the borrow
    /// @return shares_ The amount of borrow shares minted to represent the borrowed amount
    function _borrow(
        DexKey calldata dexKey_,
        uint256 token0Amt_,
        uint256 token1Amt_,
        uint256 maxSharesAmt_,
        bool estimate_
    ) internal returns (uint256 shares_, int256 token0TotalBorrowRawChange_, int256 token1TotalBorrowRawChange_) {
        BorrowVariables memory v_;

        v_.dexId = keccak256(abi.encode(dexKey_));

        v_.dexVariables = _dexVariables[DEX_TYPE][v_.dexId];
        v_.dexVariables2 = _dexVariables2[DEX_TYPE][v_.dexId];

        v_.calculatedVars = _calculateVars(dexKey_.token0, dexKey_.token1, v_.dexVariables2, v_.dexId);

        if (v_.dexVariables2 & 1 == 0) revert(); // FluidDexError(ErrorTypes.DexT1__DexNotInitialized);

        v_.userBorrowData = _userBorrowData[DEX_TYPE][v_.dexId][msg.sender];

        if (v_.userBorrowData & 1 == 0 && !estimate_) revert(); // FluidDexError(ErrorTypes.DexT1__UserDebtInNotOn);

        v_.prices = _getPrices(dexKey_, v_.dexVariables, v_.dexVariables2, DEX_TYPE, v_.dexId);

        v_.token0Debt = v_.calculatedVars.token0TotalBorrowAdjusted;
        v_.token1Debt = v_.calculatedVars.token1TotalBorrowAdjusted;
        v_.b.token0DebtInitial = v_.token0Debt;
        v_.b.token1DebtInitial = v_.token1Debt;

        if (token0Amt_ > 0) {
            v_.b.token0AmtAdjusted = (((token0Amt_ + 1) * v_.calculatedVars.token0NumeratorPrecision) / v_.calculatedVars.token0DenominatorPrecision) + 1;
            _verifySwapAndNonPerfectActions(v_.b.token0AmtAdjusted, token0Amt_);
            _verifyMint(v_.b.token0AmtAdjusted, v_.token0Debt);
        }

        if (token1Amt_ > 0) {
            v_.b.token1AmtAdjusted = (((token1Amt_ + 1) * v_.calculatedVars.token1NumeratorPrecision) / v_.calculatedVars.token1DenominatorPrecision) + 1;
            _verifySwapAndNonPerfectActions(v_.b.token1AmtAdjusted, token1Amt_);
            _verifyMint(v_.b.token1AmtAdjusted, v_.token1Debt);
        }

        v_.totalBorrowShares = _totalBorrowShares[DEX_TYPE][v_.dexId] & X128;
        if ((v_.token0Debt > 0) && (v_.token1Debt > 0)) {
            if (v_.b.token0AmtAdjusted > 0 && v_.b.token1AmtAdjusted > 0) {
                // mint shares in equal proportion
                // v_.temp => expected shares from token0 payback
                v_.temp = (v_.b.token0AmtAdjusted * 1e18) / v_.token0Debt;
                // v_.temp2 => expected shares from token1 payback
                v_.temp2 = (v_.b.token1AmtAdjusted * 1e18) / v_.token1Debt;
                if (v_.temp > v_.temp2) {
                    // use v_.temp2 shares
                    shares_ = (v_.temp2 * v_.totalBorrowShares) / 1e18;
                    // v_.temp => token0 to swap
                    v_.temp = ((v_.temp - v_.temp2) * v_.token0Debt) / 1e18;
                    v_.temp2 = 0;
                } else if (v_.temp2 > v_.temp) {
                    // use temp1_ shares
                    shares_ = (v_.temp * v_.totalBorrowShares) / 1e18;
                    // v_.temp2 => token1 to swap
                    v_.temp2 = ((v_.temp2 - v_.temp) * v_.token1Debt) / 1e18;
                    v_.temp = 0;
                } else {
                    // if equal then revert as swap will not be needed anymore which can create some issue, better to use perfect borrow in this case
                    revert(); // FluidDexError(ErrorTypes.DexT1__InvalidBorrowAmts);
                }

                // User borrowed in equal proportion here. Hence updating col reserves and the swap will happen on updated col reserves
                v_.token0Debt = v_.token0Debt + (v_.token0Debt * shares_) / v_.totalBorrowShares;
                v_.token1Debt = v_.token1Debt + (v_.token1Debt * shares_) / v_.totalBorrowShares;
                v_.totalBorrowShares += shares_;
            } else if (v_.b.token0AmtAdjusted > 0) {
                v_.temp = v_.b.token0AmtAdjusted;
                v_.temp2 = 0;
            } else if (v_.b.token1AmtAdjusted > 0) {
                v_.temp = 0;
                v_.temp2 = v_.b.token1AmtAdjusted;
            } else {
                // user sent both amounts as 0
                revert(); // FluidDexError(ErrorTypes.DexT1__InvalidBorrowAmts);
            }

            if (v_.prices.geometricMean < 1e27) {
                (, , v_.token0FinalImaginaryReserves, v_.token1FinalImaginaryReserves) = _calculateDebtReserves(
                    v_.prices.geometricMean,
                    v_.prices.lowerRange,
                    (v_.token0Debt + v_.temp),
                    (v_.token1Debt + v_.temp2)
                );
            } else {
                // inversing, something like `xy = k` so for calculation we are making everything related to x into y & y into x
                // 1 / geometricMean for new geometricMean
                // 1 / lowerRange will become upper range
                // 1 / upperRange will become lower range
                (, , v_.token1FinalImaginaryReserves, v_.token0FinalImaginaryReserves) = _calculateDebtReserves(
                    (1e54 / v_.prices.geometricMean),
                    (1e54 / v_.prices.upperRange),
                    (v_.token1Debt + v_.temp2),
                    (v_.token0Debt + v_.temp)
                );
            }

            if (v_.temp > 0) {
                // swap into token0
                v_.temp = _getBorrowAndSwap(
                    v_.token0Debt, // token0 debt
                    v_.token1Debt, // token1 debt
                    v_.token0FinalImaginaryReserves, // token0 imaginary reserves
                    v_.token1FinalImaginaryReserves, // token1 imaginary reserves
                    v_.temp // token0 to divide and swap into
                );
            } else if (v_.temp2 > 0) {
                // swap into token1
                v_.temp = _getBorrowAndSwap(
                    v_.token1Debt, // token1 debt
                    v_.token0Debt, // token0 debt
                    v_.token1FinalImaginaryReserves, // token1 imaginary reserves
                    v_.token0FinalImaginaryReserves, // token0 imaginary reserves
                    v_.temp2 // token1 to divide and swap into
                );
            } else {
                // maybe possible to happen due to some precision issue that both are 0
                revert(); // FluidDexError(ErrorTypes.DexT1__BorrowAmtsZero);
            }

            // new shares to mint from borrow & swap
            v_.temp = (v_.temp * v_.totalBorrowShares) / 1e18;
            // adding fee in case of borrow & swap
            // 1 + fee. If fee is 1% then withdrawing withFepex_ will be 1e6 + 1e4
            v_.temp = (v_.temp * (SIX_DECIMALS + ((v_.dexVariables2 >> 2) & X17))) / SIX_DECIMALS;
            // final new shares to mint for user
            shares_ += v_.temp;
            // final new debt shares
            v_.totalBorrowShares += v_.temp;
        } else {
            revert(); // FluidDexError(ErrorTypes.DexT1__InvalidDebtReserves);
        }

        if (estimate_) revert(); // FluidDexLiquidityOutput(shares_);

        if (shares_ > maxSharesAmt_) revert(); // FluidDexError(ErrorTypes.DexT1__BorrowExcessSharesMinted);

        // extract user borrow amount
        // userBorrow_ => v_.temp
        v_.temp = (v_.userBorrowData >> DexSlotsLink.BITS_USER_BORROW_AMOUNT) & X64;
        v_.temp = (v_.temp >> DEFAULT_EXPONENT_SIZE) << (v_.temp & DEFAULT_EXPONENT_MASK);

        // calculate current, updated (expanded etc.) borrow limit
        // newBorrowLimit_ => v_.temp2
        v_.temp2 = DexCalcs.calcBorrowLimitBeforeOperate(v_.userBorrowData, v_.temp);

        v_.temp += shares_;

        // user above debt limit
        if (v_.temp > v_.temp2) revert(); // FluidDexError(ErrorTypes.DexT1__DebtLimitReached);

        _updatingUserBorrowDataOnStorage(v_.userBorrowData, v_.temp, v_.temp2, v_.dexId);

        if (v_.b.token0AmtAdjusted > 0) {
            // comparing debt here rather than reserves to simply code, impact won't be much overall
            _verifyToken1Reserves(
                (v_.b.token0DebtInitial + v_.b.token0AmtAdjusted),
                (v_.b.token1DebtInitial + v_.b.token1AmtAdjusted),
                v_.prices.centerPrice,
                MINIMUM_LIQUIDITY_USER_OPERATIONS
            );
        }

        if (v_.b.token1AmtAdjusted > 0) {
            // comparing debt here rather than reserves to simply code, impact won't be much overall
            _verifyToken0Reserves(
                (v_.b.token0DebtInitial + v_.b.token0AmtAdjusted),
                (v_.b.token1DebtInitial + v_.b.token1AmtAdjusted),
                v_.prices.centerPrice,
                MINIMUM_LIQUIDITY_USER_OPERATIONS
            );
        }

        // updating total debt shares in storage
        _updateBorrowShares(v_.totalBorrowShares, v_.dexId);

        token0TotalBorrowRawChange_ = int256((token0Amt_ * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token0BorrowExchangePrice);
        token1TotalBorrowRawChange_ = int256((token1Amt_ * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token1BorrowExchangePrice);

        v_.calculatedVars.token0TotalBorrowRaw = uint256(int256(v_.calculatedVars.token0TotalBorrowRaw) + token0TotalBorrowRawChange_);
        v_.calculatedVars.token1TotalBorrowRaw = uint256(int256(v_.calculatedVars.token1TotalBorrowRaw) + token1TotalBorrowRawChange_);

        _setTotalBorrowRaw(v_.dexId, v_.calculatedVars.token0TotalBorrowRaw, v_.calculatedVars.token1TotalBorrowRaw);
    }

    struct PaybackVariables {
        bytes32 dexId;
        uint256 dexVariables;
        uint256 dexVariables2;
        CalculatedVars calculatedVars;
        uint256 userBorrowData;
        Prices prices;
        PaybackDebtMemory p;
        DebtReserves d;
        DebtReserves d2;
        uint256 temp;
        uint256 temp2;
        uint256 totalBorrowShares;
    }

    /// @dev This function allows users to payback tokens in any proportion to the debt pool
    /// @param token0Amt_ The amount of token0 to payback
    /// @param token1Amt_ The amount of token1 to payback
    /// @param minSharesAmt_ The minimum amount of shares the user expects to burn
    /// @param estimate_ If true, function will revert with estimated shares without executing the payback
    /// @return shares_ The amount of borrow shares burned for the payback
    function _payback(
        DexKey calldata dexKey_,
        uint256 token0Amt_,
        uint256 token1Amt_,
        uint256 minSharesAmt_,
        bool estimate_
    ) internal returns (uint256 shares_, int256 token0TotalBorrowRawChange_, int256 token1TotalBorrowRawChange_) {
        PaybackVariables memory v_;

        v_.dexId = keccak256(abi.encode(dexKey_));

        v_.dexVariables = _dexVariables[DEX_TYPE][v_.dexId];
        v_.dexVariables2 = _dexVariables2[DEX_TYPE][v_.dexId];

        v_.calculatedVars = _calculateVars(dexKey_.token0, dexKey_.token1, v_.dexVariables2, v_.dexId);

        if (v_.dexVariables2 & 1 == 0) revert(); // FluidDexError(ErrorTypes.DexT1__DexNotInitialized);

        v_.userBorrowData = _userBorrowData[DEX_TYPE][v_.dexId][msg.sender];

        if (v_.userBorrowData & 1 == 0 && !estimate_) revert(); // FluidDexError(ErrorTypes.DexT1__UserDebtInNotOn);

        v_.prices = _getPrices(dexKey_, v_.dexVariables, v_.dexVariables2, DEX_TYPE, v_.dexId);

        v_.d = _getDebtReserves(
            v_.prices.geometricMean,
            v_.prices.upperRange,
            v_.prices.lowerRange,
            v_.calculatedVars.token0TotalBorrowAdjusted,
            v_.calculatedVars.token1TotalBorrowAdjusted
        );
        v_.d2 = v_.d;

        if (token0Amt_ > 0) {
            v_.p.token0AmtAdjusted = (((token0Amt_ - 1) * v_.calculatedVars.token0NumeratorPrecision) / v_.calculatedVars.token0DenominatorPrecision) - 1;
            _verifySwapAndNonPerfectActions(v_.p.token0AmtAdjusted, token0Amt_);
            _verifyRedeem(v_.p.token0AmtAdjusted, v_.d.token0Debt);
        }

        if (token1Amt_ > 0) {
            v_.p.token1AmtAdjusted = (((token1Amt_ - 1) * v_.calculatedVars.token1NumeratorPrecision) / v_.calculatedVars.token1DenominatorPrecision) - 1;
            _verifySwapAndNonPerfectActions(v_.p.token1AmtAdjusted, token1Amt_);
            _verifyRedeem(v_.p.token1AmtAdjusted, v_.d.token1Debt);
        }

        v_.totalBorrowShares = _totalBorrowShares[DEX_TYPE][v_.dexId] & X128;
        if ((v_.d.token0Debt > 0) && (v_.d.token1Debt > 0)) {
            if (v_.p.token0AmtAdjusted > 0 && v_.p.token1AmtAdjusted > 0) {
                // burn shares in equal proportion
                // v_.temp => expected shares from token0 payback
                v_.temp = (v_.p.token0AmtAdjusted * 1e18) / v_.d.token0Debt;
                // v_.temp2 => expected shares from token1 payback
                v_.temp2 = (v_.p.token1AmtAdjusted * 1e18) / v_.d.token1Debt;
                if (v_.temp > v_.temp2) {
                    // use v_.temp2 shares
                    shares_ = ((v_.temp2 * v_.totalBorrowShares) / 1e18);
                    // v_.temp => token0 to swap
                    v_.temp = v_.p.token0AmtAdjusted - (v_.temp2 * v_.p.token0AmtAdjusted) / v_.temp;
                    v_.temp2 = 0;
                } else if (v_.temp2 > v_.temp) {
                    // use v_.temp shares
                    shares_ = ((v_.temp * v_.totalBorrowShares) / 1e18);
                    // v_.temp2 => token1 to swap
                    v_.temp2 = v_.p.token1AmtAdjusted - ((v_.temp * v_.p.token1AmtAdjusted) / v_.temp2); // to this
                    v_.temp = 0;
                } else {
                    // if equal then revert as swap will not be needed anymore which can create some issue, better to use perfect payback in this case
                    revert(); // FluidDexError(ErrorTypes.DexT1__InvalidPaybackAmts);
                }

                // User paid back in equal proportion here. Hence updating debt reserves and the swap will happen on updated debt reserves
                v_.d2 = _getUpdateDebtReserves(
                    shares_,
                    v_.totalBorrowShares,
                    v_.d,
                    false // true if mint, false if burn
                );
                v_.totalBorrowShares -= shares_;
            } else if (v_.p.token0AmtAdjusted > 0) {
                v_.temp = v_.p.token0AmtAdjusted;
                v_.temp2 = 0;
            } else if (v_.p.token1AmtAdjusted > 0) {
                v_.temp = 0;
                v_.temp2 = v_.p.token1AmtAdjusted;
            } else {
                // user sent both amounts as 0
                revert(); // FluidDexError(ErrorTypes.DexT1__InvalidPaybackAmts);
            }

            if (v_.temp > 0) {
                // swap token0 into token1 and payback equally
                v_.temp = _getSwapAndPayback(v_.d2.token0Debt, v_.d2.token1Debt, v_.d2.token0ImaginaryReserves, v_.d2.token1ImaginaryReserves, v_.temp);
            } else if (v_.temp2 > 0) {
                // swap token1 into token0 and payback equally
                v_.temp = _getSwapAndPayback(v_.d2.token1Debt, v_.d2.token0Debt, v_.d2.token1ImaginaryReserves, v_.d2.token0ImaginaryReserves, v_.temp2);
            } else {
                // maybe possible to happen due to some precision issue that both are 0
                revert(); // FluidDexError(ErrorTypes.DexT1__PaybackAmtsZero);
            }

            // new shares to burn from payback & swap
            v_.temp = ((v_.temp * v_.totalBorrowShares) / 1e18);

            // adding fee in case of payback & swap
            // 1 - fee. If fee is 1% then withdrawing withFepex_ will be 1e6 - 1e4
            v_.temp = (v_.temp * (SIX_DECIMALS - ((v_.dexVariables2 >> 2) & X17))) / SIX_DECIMALS;
            // final shares to burn for user
            shares_ += v_.temp;
            // final new debt shares
            v_.totalBorrowShares -= v_.temp;
        } else {
            revert(); // FluidDexError(ErrorTypes.DexT1__InvalidDebtReserves);
        }

        if (estimate_) revert(); // FluidDexLiquidityOutput(shares_);
        if (shares_ < minSharesAmt_) revert(); // FluidDexError(ErrorTypes.DexT1__PaybackSharedBurnedLess);

        if (token0Amt_ > 0) {
            // comparing debt here rather than reserves to simply code, impact won't be much overall
            _verifyToken0Reserves(
                (v_.d.token0Debt - v_.p.token0AmtAdjusted),
                (v_.d.token1Debt - v_.p.token1AmtAdjusted),
                v_.prices.centerPrice,
                MINIMUM_LIQUIDITY_USER_OPERATIONS
            );
        }

        if (token1Amt_ > 0) {
            // comparing debt here rather than reserves to simply code, impact won't be much overall
            _verifyToken1Reserves(
                (v_.d.token0Debt - v_.p.token0AmtAdjusted),
                (v_.d.token1Debt - v_.p.token1AmtAdjusted),
                v_.prices.centerPrice,
                MINIMUM_LIQUIDITY_USER_OPERATIONS
            );
        }

        // extract user borrow amount
        // userBorrow_ => v_.temp
        v_.temp = (v_.userBorrowData >> DexSlotsLink.BITS_USER_BORROW_AMOUNT) & X64;
        v_.temp = (v_.temp >> DEFAULT_EXPONENT_SIZE) << (v_.temp & DEFAULT_EXPONENT_MASK);

        // calculate current, updated (expanded etc.) borrow limit
        // newBorrowLimit_ => v_.temp2
        v_.temp2 = DexCalcs.calcBorrowLimitBeforeOperate(v_.userBorrowData, v_.temp);

        v_.temp -= shares_;

        _updatingUserBorrowDataOnStorage(v_.userBorrowData, v_.temp, v_.temp2, v_.dexId);
        // updating total debt shares in storage
        _updateBorrowShares(v_.totalBorrowShares, v_.dexId);

        token0TotalBorrowRawChange_ = -int256((token0Amt_ * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token0BorrowExchangePrice);
        token1TotalBorrowRawChange_ = -int256((token1Amt_ * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token1BorrowExchangePrice);

        v_.calculatedVars.token0TotalBorrowRaw = uint256(int256(v_.calculatedVars.token0TotalBorrowRaw) + token0TotalBorrowRawChange_);
        v_.calculatedVars.token1TotalBorrowRaw = uint256(int256(v_.calculatedVars.token1TotalBorrowRaw) + token1TotalBorrowRawChange_);

        _setTotalBorrowRaw(v_.dexId, v_.calculatedVars.token0TotalBorrowRaw, v_.calculatedVars.token1TotalBorrowRaw);
    }

    struct BorrowPerfectVariables {
        bytes32 dexId;
        uint256 dexVariables2;
        CalculatedVars calculatedVars;
        uint256 userBorrowData;
        uint256 totalBorrowShares;
        uint256 userBorrow;
        uint256 newBorrowLimit;
    }

    /// @dev This function allows users to borrow tokens in equal proportion to the current debt pool ratio
    /// @param shares_ The number of shares to borrow
    /// @param minToken0Borrow_ Minimum amount of token0 to borrow
    /// @param minToken1Borrow_ Minimum amount of token1 to borrow
    /// @param estimate_ If true, function will revert with estimated token0Amt_ & token1Amt_ without executing the borrow
    /// @return token0Amt_ Amount of token0 borrowed
    /// @return token1Amt_ Amount of token1 borrowed
    function _borrowPerfect(
        DexKey calldata dexKey_,
        uint256 shares_,
        uint256 minToken0Borrow_,
        uint256 minToken1Borrow_,
        bool estimate_
    ) internal returns (uint256 token0Amt_, uint256 token1Amt_, int256 token0TotalBorrowRawChange_, int256 token1TotalBorrowRawChange_) {
        BorrowPerfectVariables memory v_;

        v_.dexId = keccak256(abi.encode(dexKey_));
        v_.dexVariables2 = _dexVariables2[DEX_TYPE][v_.dexId];

        v_.calculatedVars = _calculateVars(dexKey_.token0, dexKey_.token1, v_.dexVariables2, v_.dexId);

        if (v_.dexVariables2 & 1 == 0) revert(); // FluidDexError(ErrorTypes.DexT1__DexNotInitialized);

        v_.userBorrowData = _userBorrowData[DEX_TYPE][v_.dexId][msg.sender];

        // user debt configs are not set yet
        if (v_.userBorrowData & 1 == 0 && !estimate_) revert(); // FluidDexError(ErrorTypes.DexT1__UserDebtInNotOn);

        v_.totalBorrowShares = _totalBorrowShares[DEX_TYPE][v_.dexId] & X128;

        _verifyMint(shares_, v_.totalBorrowShares);

        // Adding debt liquidity in equal proportion
        token0Amt_ = (v_.calculatedVars.token0TotalBorrowAdjusted * shares_) / v_.totalBorrowShares;
        token1Amt_ = (v_.calculatedVars.token1TotalBorrowAdjusted * shares_) / v_.totalBorrowShares;
        // converting back into normal token amounts
        token0Amt_ = (((token0Amt_ - 1) * v_.calculatedVars.token0DenominatorPrecision) / v_.calculatedVars.token0NumeratorPrecision) - 1;
        token1Amt_ = (((token1Amt_ - 1) * v_.calculatedVars.token1DenominatorPrecision) / v_.calculatedVars.token1NumeratorPrecision) - 1;

        if (estimate_) revert(); // FluidDexPerfectLiquidityOutput(token0Amt_, token1Amt_);

        if (token0Amt_ < minToken0Borrow_ || token1Amt_ < minToken1Borrow_) {
            revert(); // FluidDexError(ErrorTypes.DexT1__BelowBorrowMin);
        }

        // extract user borrow amount
        v_.userBorrow = (v_.userBorrowData >> DexSlotsLink.BITS_USER_BORROW_AMOUNT) & X64;
        v_.userBorrow = (v_.userBorrow >> DEFAULT_EXPONENT_SIZE) << (v_.userBorrow & DEFAULT_EXPONENT_MASK);

        // calculate current, updated (expanded etc.) borrow limit
        v_.newBorrowLimit = DexCalcs.calcBorrowLimitBeforeOperate(v_.userBorrowData, v_.userBorrow);

        v_.userBorrow += shares_;

        // user above debt limit
        if (v_.userBorrow > v_.newBorrowLimit) revert(); // FluidDexError(ErrorTypes.DexT1__DebtLimitReached);

        _updatingUserBorrowDataOnStorage(v_.userBorrowData, v_.userBorrow, v_.newBorrowLimit, v_.dexId);

        _updateBorrowShares(v_.totalBorrowShares + shares_, v_.dexId);

        token0TotalBorrowRawChange_ = int256((token0Amt_ * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token0BorrowExchangePrice);
        token1TotalBorrowRawChange_ = int256((token1Amt_ * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token1BorrowExchangePrice);

        v_.calculatedVars.token0TotalBorrowRaw = uint256(int256(v_.calculatedVars.token0TotalBorrowRaw) + token0TotalBorrowRawChange_);
        v_.calculatedVars.token1TotalBorrowRaw = uint256(int256(v_.calculatedVars.token1TotalBorrowRaw) + token1TotalBorrowRawChange_);

        _setTotalBorrowRaw(v_.dexId, v_.calculatedVars.token0TotalBorrowRaw, v_.calculatedVars.token1TotalBorrowRaw);
    }

    struct PaybackPerfectVariables {
        bytes32 dexId;
        uint256 dexVariables2;
        CalculatedVars calculatedVars;
        uint256 userBorrowData;
        uint256 totalBorrowShares;
        uint256 userBorrow;
        uint256 newBorrowLimit;
    }

    /// @dev This function allows users to pay back borrowed tokens in equal proportion to the current debt pool ratio
    /// @param shares_ The number of shares to pay back
    /// @param maxToken0Payback_ Maximum amount of token0 to pay back
    /// @param maxToken1Payback_ Maximum amount of token1 to pay back
    /// @param estimate_ If true, function will revert with estimated payback amounts without executing the payback
    /// @return token0Amt_ Amount of token0 paid back
    /// @return token1Amt_ Amount of token1 paid back
    function _paybackPerfect(
        DexKey calldata dexKey_,
        uint256 shares_,
        uint256 maxToken0Payback_,
        uint256 maxToken1Payback_,
        bool estimate_
    ) internal returns (uint256 token0Amt_, uint256 token1Amt_, int256 token0TotalBorrowRawChange_, int256 token1TotalBorrowRawChange_) {
        PaybackPerfectVariables memory v_;

        v_.dexId = keccak256(abi.encode(dexKey_));
        v_.dexVariables2 = _dexVariables2[DEX_TYPE][v_.dexId];

        v_.calculatedVars = _calculateVars(dexKey_.token0, dexKey_.token1, v_.dexVariables2, v_.dexId);

        if (v_.dexVariables2 & 1 == 0) revert(); // FluidDexError(ErrorTypes.DexT1__PoolNotInitialized);

        v_.userBorrowData = _userBorrowData[DEX_TYPE][v_.dexId][msg.sender];

        if (v_.userBorrowData & 1 == 0 && !estimate_) revert(); // FluidDexError(ErrorTypes.DexT1__UserDebtInNotOn);

        v_.totalBorrowShares = _totalBorrowShares[DEX_TYPE][v_.dexId] & X128;

        _verifyRedeem(shares_, v_.totalBorrowShares);

        // Removing debt liquidity in equal proportion
        token0Amt_ = (v_.calculatedVars.token0TotalBorrowAdjusted * shares_) / v_.totalBorrowShares;
        token1Amt_ = (v_.calculatedVars.token1TotalBorrowAdjusted * shares_) / v_.totalBorrowShares;
        // converting back into normal token amounts
        token0Amt_ = (((token0Amt_ + 1) * v_.calculatedVars.token0DenominatorPrecision) / v_.calculatedVars.token0NumeratorPrecision) + 1;
        token1Amt_ = (((token1Amt_ + 1) * v_.calculatedVars.token1DenominatorPrecision) / v_.calculatedVars.token1NumeratorPrecision) + 1;

        if (estimate_) revert(); // FluidDexPerfectLiquidityOutput(token0Amt_, token1Amt_);

        if (token0Amt_ > maxToken0Payback_ || token1Amt_ > maxToken1Payback_) {
            revert(); // FluidDexError(ErrorTypes.DexT1__AbovePaybackMax);
        }

        // extract user borrow amount
        v_.userBorrow = (v_.userBorrowData >> DexSlotsLink.BITS_USER_BORROW_AMOUNT) & X64;
        v_.userBorrow = (v_.userBorrow >> DEFAULT_EXPONENT_SIZE) << (v_.userBorrow & DEFAULT_EXPONENT_MASK);

        // calculate current, updated (expanded etc.) borrow limit
        v_.newBorrowLimit = DexCalcs.calcBorrowLimitBeforeOperate(v_.userBorrowData, v_.userBorrow);

        v_.userBorrow -= shares_;

        _updatingUserBorrowDataOnStorage(v_.userBorrowData, v_.userBorrow, v_.newBorrowLimit, v_.dexId);

        v_.totalBorrowShares = v_.totalBorrowShares - shares_;
        _updateBorrowShares(v_.totalBorrowShares, v_.dexId);

        token0TotalBorrowRawChange_ = -int256((token0Amt_ * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token0BorrowExchangePrice);
        token1TotalBorrowRawChange_ = -int256((token1Amt_ * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token1BorrowExchangePrice);

        v_.calculatedVars.token0TotalBorrowRaw = uint256(int256(v_.calculatedVars.token0TotalBorrowRaw) + token0TotalBorrowRawChange_);
        v_.calculatedVars.token1TotalBorrowRaw = uint256(int256(v_.calculatedVars.token1TotalBorrowRaw) + token1TotalBorrowRawChange_);

        _setTotalBorrowRaw(v_.dexId, v_.calculatedVars.token0TotalBorrowRaw, v_.calculatedVars.token1TotalBorrowRaw);
    }

    struct PaybackPerfectInOneTokenVariables {
        bytes32 dexId;
        uint256 dexVariables;
        uint256 dexVariables2;
        CalculatedVars calculatedVars;
        uint256 userBorrowData;
        Prices prices;
        uint256 totalBorrowShares;
        uint256 token0Amt;
        uint256 token1Amt;
        DebtReserves d;
        DebtReserves d2;
        uint256 userBorrow;
        uint256 temp;
    }

    /// @dev This function allows users to payback their debt with perfect shares in one token
    /// @param shares_ The number of shares to burn for payback
    /// @param maxToken0_ The maximum amount of token0 the user is willing to pay (set to 0 if paying back in token1)
    /// @param maxToken1_ The maximum amount of token1 the user is willing to pay (set to 0 if paying back in token0)
    /// @param estimate_ If true, the function will revert with the estimated payback amount without executing the payback
    /// @return paybackAmt_ The amount of tokens paid back in the chosen token
    function _paybackPerfectInOneToken(
        DexKey calldata dexKey_,
        uint256 shares_,
        uint256 maxToken0_,
        uint256 maxToken1_,
        bool estimate_
    ) internal returns (uint256 paybackAmt_, int256 token0TotalBorrowRawChange_, int256 token1TotalBorrowRawChange_) {
        PaybackPerfectInOneTokenVariables memory v_;

        v_.dexId = keccak256(abi.encode(dexKey_));

        v_.dexVariables = _dexVariables[DEX_TYPE][v_.dexId];
        v_.dexVariables2 = _dexVariables2[DEX_TYPE][v_.dexId];

        v_.calculatedVars = _calculateVars(dexKey_.token0, dexKey_.token1, v_.dexVariables2, v_.dexId);

        if (v_.dexVariables2 & 1 == 0) revert(); // FluidDexError(ErrorTypes.DexT1__DexNotInitialized);

        v_.userBorrowData = _userBorrowData[DEX_TYPE][v_.dexId][msg.sender];

        if (v_.userBorrowData & 1 == 0 && !estimate_) revert(); // FluidDexError(ErrorTypes.DexT1__UserDebtInNotOn);

        if ((maxToken0_ > 0 && maxToken1_ > 0) || (maxToken0_ == 0 && maxToken1_ == 0)) {
            // only 1 token should be > 0
            revert(); // FluidDexError(ErrorTypes.DexT1__InvalidWithdrawAmts);
        }

        v_.prices = _getPrices(dexKey_, v_.dexVariables, v_.dexVariables2, DEX_TYPE, v_.dexId);

        v_.totalBorrowShares = _totalBorrowShares[DEX_TYPE][v_.dexId] & X128;

        _verifyRedeem(shares_, v_.totalBorrowShares);

        v_.d = _getDebtReserves(
            v_.prices.geometricMean,
            v_.prices.upperRange,
            v_.prices.lowerRange,
            v_.calculatedVars.token0TotalBorrowAdjusted,
            v_.calculatedVars.token1TotalBorrowAdjusted
        );

        if ((v_.d.token0Debt == 0) || (v_.d.token1Debt == 0)) {
            revert(); // FluidDexError(ErrorTypes.DexT1__InvalidDebtReserves);
        }

        // Removing debt liquidity in equal proportion
        v_.d2 = _getUpdateDebtReserves(shares_, v_.totalBorrowShares, v_.d, false);

        if (maxToken0_ > 0) {
            // entire payback is in token0_
            v_.token0Amt = _getSwapAndPaybackOneTokenPerfectShares(
                v_.d2.token0ImaginaryReserves,
                v_.d2.token1ImaginaryReserves,
                v_.d.token0Debt,
                v_.d.token1Debt,
                v_.d2.token0RealReserves,
                v_.d2.token1RealReserves
            );
            _verifyToken0Reserves((v_.d.token0Debt - v_.token0Amt), v_.d.token1Debt, v_.prices.centerPrice, MINIMUM_LIQUIDITY_USER_OPERATIONS);

            // converting from raw/adjusted to normal token amounts
            v_.token0Amt = (((v_.token0Amt + 1) * v_.calculatedVars.token0DenominatorPrecision) / v_.calculatedVars.token0NumeratorPrecision) + 1;

            // adding fee on paying back in 1 token
            v_.token0Amt = (v_.token0Amt * (SIX_DECIMALS + ((v_.dexVariables2 >> 2) & X17))) / SIX_DECIMALS;

            paybackAmt_ = v_.token0Amt;
            if (estimate_) revert(); // FluidDexSingleTokenOutput(paybackAmt_);
            if (paybackAmt_ > maxToken0_) revert(); // FluidDexError(ErrorTypes.DexT1__PaybackAmtTooHigh);

            token0TotalBorrowRawChange_ = -int256((v_.token0Amt * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token0BorrowExchangePrice);

            v_.calculatedVars.token0TotalBorrowRaw = uint256(int256(v_.calculatedVars.token0TotalBorrowRaw) + token0TotalBorrowRawChange_);

            _setTotalBorrowRaw(v_.dexId, v_.calculatedVars.token0TotalBorrowRaw, v_.calculatedVars.token1TotalBorrowRaw);
        } else {
            // entire payback is in token1_
            v_.token1Amt = _getSwapAndPaybackOneTokenPerfectShares(
                v_.d2.token1ImaginaryReserves,
                v_.d2.token0ImaginaryReserves,
                v_.d.token1Debt,
                v_.d.token0Debt,
                v_.d2.token1RealReserves,
                v_.d2.token0RealReserves
            );
            _verifyToken1Reserves(v_.d.token0Debt, (v_.d.token1Debt - v_.token1Amt), v_.prices.centerPrice, MINIMUM_LIQUIDITY_USER_OPERATIONS);

            // converting from raw/adjusted to normal token amounts
            v_.token1Amt = (((v_.token1Amt + 1) * v_.calculatedVars.token1DenominatorPrecision) / v_.calculatedVars.token1NumeratorPrecision) + 1;

            // adding fee on paying back in 1 token
            v_.token1Amt = (v_.token1Amt * (SIX_DECIMALS + ((v_.dexVariables2 >> 2) & X17))) / SIX_DECIMALS;

            paybackAmt_ = v_.token1Amt;
            if (estimate_) revert(); // FluidDexSingleTokenOutput(paybackAmt_);
            if (paybackAmt_ > maxToken1_) revert(); // FluidDexError(ErrorTypes.DexT1__PaybackAmtTooHigh);

            token1TotalBorrowRawChange_ = -int256((v_.token1Amt * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / v_.calculatedVars.token1BorrowExchangePrice);

            v_.calculatedVars.token1TotalBorrowRaw = uint256(int256(v_.calculatedVars.token1TotalBorrowRaw) + token1TotalBorrowRawChange_);

            _setTotalBorrowRaw(v_.dexId, v_.calculatedVars.token0TotalBorrowRaw, v_.calculatedVars.token1TotalBorrowRaw);
        }

        // extract user borrow amount
        v_.userBorrow = (v_.userBorrowData >> DexSlotsLink.BITS_USER_BORROW_AMOUNT) & X64;
        v_.userBorrow = (v_.userBorrow >> DEFAULT_EXPONENT_SIZE) << (v_.userBorrow & DEFAULT_EXPONENT_MASK);

        // calculate current, updated (expanded etc.) borrow limit
        // v_.temp => newBorrowLimit_
        v_.temp = DexCalcs.calcBorrowLimitBeforeOperate(v_.userBorrowData, v_.userBorrow);
        v_.userBorrow -= shares_;

        _updatingUserBorrowDataOnStorage(v_.userBorrowData, v_.userBorrow, v_.temp, v_.dexId);

        v_.totalBorrowShares = v_.totalBorrowShares - shares_;
        _updateBorrowShares(v_.totalBorrowShares, v_.dexId);
    }
}

abstract contract CoreInternals is SwapInternals, UserOperationInternals {}
