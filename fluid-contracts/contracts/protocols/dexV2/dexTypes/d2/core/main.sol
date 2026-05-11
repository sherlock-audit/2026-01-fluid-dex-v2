// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import "./coreInternals.sol";
import { PendingTransfers } from "../../../../../libraries/pendingTransfers.sol";

// TODO: @Vaibhav add events

// import { ErrorTypes } from "../../../errorTypes.sol"; // TODO: Update this and all reverts
// import { IFluidDexT1 } from "../../../interfaces/iDexT1.sol"; // TODO: Update this

interface IDexCallback {
    function dexCallback(address token_, uint256 amount_) external;
}

/// @title FluidDexT1
/// @notice Implements core logics for Fluid Dex protocol.
/// Note Token transfers happen directly from user to Liquidity contract and vice-versa.
contract FluidDexV2D2 is CoreInternals {
    using BigMathMinified for uint256;

    constructor(address liquidityAddress_, address deployerContract_) CommonImmutableVariables(liquidityAddress_, deployerContract_) {}

    modifier _onlyDelegateCall() {
        if (address(this) == THIS_CONTRACT) {
            revert(); // FluidDexError(ErrorTypes.DexT1__OnlyDelegateCallAllowed);
        }
        _;
    }

    /// @dev Swap tokens with perfect amount in
    /// @param swap0To1_ Direction of swap. If true, swaps token0 for token1; if false, swaps token1 for token0
    /// @param amountIn_ The exact amount of tokens to swap in
    /// @param amountOutMin_ The minimum amount of tokens to receive after swap
    /// @param estimate_ If true, function will revert with estimated amountOut_ without executing the swap
    function swapIn(
        DexKey calldata dexKey_,
        bool swap0To1_,
        uint256 amountIn_,
        uint256 amountOutMin_,
        bool estimate_
    ) external _onlyDelegateCall returns (TotalAmounts[] memory totalAmountsChange_, bytes memory returnData_) {
        TotalAmounts memory token0TotalAmountsChange_;
        token0TotalAmountsChange_.token = dexKey_.token0;

        TotalAmounts memory token1TotalAmountsChange_;
        token1TotalAmountsChange_.token = dexKey_.token1;

        uint256 amountOut_;
        (amountOut_, token0TotalAmountsChange_.totalBorrowWithInterest, token1TotalAmountsChange_.totalBorrowWithInterest) = _swapIn(
            dexKey_,
            swap0To1_,
            amountIn_,
            amountOutMin_,
            estimate_
        );

        if (swap0To1_) {
            PendingTransfers.addPendingBorrow(msg.sender, dexKey_.token0, -int256(amountIn_));
            PendingTransfers.addPendingBorrow(msg.sender, dexKey_.token1, int256(amountOut_));
        } else {
            PendingTransfers.addPendingBorrow(msg.sender, dexKey_.token1, -int256(amountIn_));
            PendingTransfers.addPendingBorrow(msg.sender, dexKey_.token0, int256(amountOut_));
        }

        totalAmountsChange_ = new TotalAmounts[](2);
        totalAmountsChange_[0] = token0TotalAmountsChange_;
        totalAmountsChange_[1] = token1TotalAmountsChange_;

        returnData_ = abi.encode(amountOut_);
    }

    /// @dev Swap tokens with perfect amount out
    /// @param swap0To1_ Direction of swap. If true, swaps token0 for token1; if false, swaps token1 for token0
    /// @param amountOut_ The exact amount of tokens to receive after swap
    /// @param amountInMax_ Maximum amount of tokens to swap in
    /// @param estimate_ If true, function will revert with estimated amountIn_ without executing the swap
    function swapOut(
        DexKey calldata dexKey_,
        bool swap0To1_,
        uint256 amountOut_,
        uint256 amountInMax_,
        bool estimate_
    ) external _onlyDelegateCall returns (TotalAmounts[] memory totalAmountsChange_, bytes memory returnData_) {
        TotalAmounts memory token0TotalAmountsChange_;
        token0TotalAmountsChange_.token = dexKey_.token0;

        TotalAmounts memory token1TotalAmountsChange_;
        token1TotalAmountsChange_.token = dexKey_.token1;

        uint256 amountIn_;
        (amountIn_, token0TotalAmountsChange_.totalBorrowWithInterest, token1TotalAmountsChange_.totalBorrowWithInterest) = _swapOut(
            dexKey_,
            swap0To1_,
            amountOut_,
            amountInMax_,
            estimate_
        );

        if (swap0To1_) {
            PendingTransfers.addPendingBorrow(msg.sender, dexKey_.token0, -int256(amountIn_));
            PendingTransfers.addPendingBorrow(msg.sender, dexKey_.token1, int256(amountOut_));
        } else {
            PendingTransfers.addPendingBorrow(msg.sender, dexKey_.token1, -int256(amountIn_));
            PendingTransfers.addPendingBorrow(msg.sender, dexKey_.token0, int256(amountOut_));
        }

        totalAmountsChange_ = new TotalAmounts[](2);
        totalAmountsChange_[0] = token0TotalAmountsChange_;
        totalAmountsChange_[1] = token1TotalAmountsChange_;

        returnData_ = abi.encode(amountIn_);
    }

    /// @dev This function allows users to borrow tokens in any proportion from the debt pool
    /// @param token0Amt_ The amount of token0 to borrow
    /// @param token1Amt_ The amount of token1 to borrow
    /// @param maxSharesAmt_ The maximum amount of shares the user is willing to receive
    /// @param estimate_ If true, function will revert with estimated shares without executing the borrow
    function borrow(
        DexKey calldata dexKey_,
        uint256 token0Amt_,
        uint256 token1Amt_,
        uint256 maxSharesAmt_,
        bool estimate_
    ) external _onlyDelegateCall returns (TotalAmounts[] memory totalAmountsChange_, bytes memory returnData_) {
        TotalAmounts memory token0TotalAmountsChange_;
        token0TotalAmountsChange_.token = dexKey_.token0;

        TotalAmounts memory token1TotalAmountsChange_;
        token1TotalAmountsChange_.token = dexKey_.token1;

        uint256 shares_;
        (shares_, token0TotalAmountsChange_.totalBorrowWithInterest, token1TotalAmountsChange_.totalBorrowWithInterest) = _borrow(
            dexKey_,
            token0Amt_,
            token1Amt_,
            maxSharesAmt_,
            estimate_
        );

        PendingTransfers.addPendingBorrow(msg.sender, dexKey_.token0, int256(token0Amt_));
        PendingTransfers.addPendingBorrow(msg.sender, dexKey_.token1, int256(token1Amt_));

        totalAmountsChange_ = new TotalAmounts[](2);
        totalAmountsChange_[0] = token0TotalAmountsChange_;
        totalAmountsChange_[1] = token1TotalAmountsChange_;

        returnData_ = abi.encode(shares_);
    }

    /// @dev This function allows users to payback tokens in any proportion to the debt pool
    /// @param token0Amt_ The amount of token0 to payback
    /// @param token1Amt_ The amount of token1 to payback
    /// @param minSharesAmt_ The minimum amount of shares the user expects to burn
    /// @param estimate_ If true, function will revert with estimated shares without executing the payback
    function payback(
        DexKey calldata dexKey_,
        uint256 token0Amt_,
        uint256 token1Amt_,
        uint256 minSharesAmt_,
        bool estimate_
    ) external _onlyDelegateCall returns (TotalAmounts[] memory totalAmountsChange_, bytes memory returnData_) {
        TotalAmounts memory token0TotalAmountsChange_;
        token0TotalAmountsChange_.token = dexKey_.token0;

        TotalAmounts memory token1TotalAmountsChange_;
        token1TotalAmountsChange_.token = dexKey_.token1;

        uint256 shares_;
        (shares_, token0TotalAmountsChange_.totalBorrowWithInterest, token1TotalAmountsChange_.totalBorrowWithInterest) = _payback(
            dexKey_,
            token0Amt_,
            token1Amt_,
            minSharesAmt_,
            estimate_
        );

        PendingTransfers.addPendingBorrow(msg.sender, dexKey_.token0, -int256(token0Amt_));
        PendingTransfers.addPendingBorrow(msg.sender, dexKey_.token1, -int256(token1Amt_));

        totalAmountsChange_ = new TotalAmounts[](2);
        totalAmountsChange_[0] = token0TotalAmountsChange_;
        totalAmountsChange_[1] = token1TotalAmountsChange_;

        returnData_ = abi.encode(shares_);
    }

    /// @dev This function allows users to borrow tokens in equal proportion to the current debt pool ratio
    /// @param shares_ The number of shares to borrow
    /// @param minToken0Borrow_ Minimum amount of token0 to borrow
    /// @param minToken1Borrow_ Minimum amount of token1 to borrow
    /// @param estimate_ If true, function will revert with estimated token0Amt_ & token1Amt_ without executing the borrow
    function borrowPerfect(
        DexKey calldata dexKey_,
        uint256 shares_,
        uint256 minToken0Borrow_,
        uint256 minToken1Borrow_,
        bool estimate_
    ) external _onlyDelegateCall returns (TotalAmounts[] memory totalAmountsChange_, bytes memory returnData_) {
        TotalAmounts memory token0TotalAmountsChange_;
        token0TotalAmountsChange_.token = dexKey_.token0;

        TotalAmounts memory token1TotalAmountsChange_;
        token1TotalAmountsChange_.token = dexKey_.token1;

        uint256 token0Amt_;
        uint256 token1Amt_;
        (token0Amt_, token1Amt_, token0TotalAmountsChange_.totalBorrowWithInterest, token1TotalAmountsChange_.totalBorrowWithInterest) = _borrowPerfect(
            dexKey_,
            shares_,
            minToken0Borrow_,
            minToken1Borrow_,
            estimate_
        );

        PendingTransfers.addPendingBorrow(msg.sender, dexKey_.token0, int256(token0Amt_));
        PendingTransfers.addPendingBorrow(msg.sender, dexKey_.token1, int256(token1Amt_));

        totalAmountsChange_ = new TotalAmounts[](2);
        totalAmountsChange_[0] = token0TotalAmountsChange_;
        totalAmountsChange_[1] = token1TotalAmountsChange_;

        returnData_ = abi.encode(token0Amt_, token1Amt_);
    }

    /// @dev This function allows users to pay back borrowed tokens in equal proportion to the current debt pool ratio
    /// @param shares_ The number of shares to pay back
    /// @param maxToken0Payback_ Maximum amount of token0 to pay back
    /// @param maxToken1Payback_ Maximum amount of token1 to pay back
    /// @param estimate_ If true, function will revert with estimated payback amounts without executing the payback
    function paybackPerfect(
        DexKey calldata dexKey_,
        uint256 shares_,
        uint256 maxToken0Payback_,
        uint256 maxToken1Payback_,
        bool estimate_
    ) external _onlyDelegateCall returns (TotalAmounts[] memory totalAmountsChange_, bytes memory returnData_) {
        TotalAmounts memory token0TotalAmountsChange_;
        token0TotalAmountsChange_.token = dexKey_.token0;

        TotalAmounts memory token1TotalAmountsChange_;
        token1TotalAmountsChange_.token = dexKey_.token1;

        uint256 token0Amt_;
        uint256 token1Amt_;
        (token0Amt_, token1Amt_, token0TotalAmountsChange_.totalBorrowWithInterest, token1TotalAmountsChange_.totalBorrowWithInterest) = _paybackPerfect(
            dexKey_,
            shares_,
            maxToken0Payback_,
            maxToken1Payback_,
            estimate_
        );

        PendingTransfers.addPendingBorrow(msg.sender, dexKey_.token0, -int256(token0Amt_));
        PendingTransfers.addPendingBorrow(msg.sender, dexKey_.token1, -int256(token1Amt_));

        totalAmountsChange_ = new TotalAmounts[](2);
        totalAmountsChange_[0] = token0TotalAmountsChange_;
        totalAmountsChange_[1] = token1TotalAmountsChange_;

        returnData_ = abi.encode(token0Amt_, token1Amt_);
    }

    /// @dev This function allows users to payback their debt with perfect shares in one token
    /// @param shares_ The number of shares to burn for payback
    /// @param maxToken0_ The maximum amount of token0 the user is willing to pay (set to 0 if paying back in token1)
    /// @param maxToken1_ The maximum amount of token1 the user is willing to pay (set to 0 if paying back in token0)
    /// @param estimate_ If true, the function will revert with the estimated payback amount without executing the payback
    function paybackPerfectInOneToken(
        DexKey calldata dexKey_,
        uint256 shares_,
        uint256 maxToken0_,
        uint256 maxToken1_,
        bool estimate_
    ) external _onlyDelegateCall returns (TotalAmounts[] memory totalAmountsChange_, bytes memory returnData_) {
        address token_;
        if (maxToken0_ > 0) {
            token_ = dexKey_.token0;
        } else {
            token_ = dexKey_.token1;
        }

        TotalAmounts memory token0TotalAmountsChange_;
        token0TotalAmountsChange_.token = dexKey_.token0;

        TotalAmounts memory token1TotalAmountsChange_;
        token1TotalAmountsChange_.token = dexKey_.token1;

        uint256 paybackAmt_;
        (paybackAmt_, token0TotalAmountsChange_.totalBorrowWithInterest, token1TotalAmountsChange_.totalBorrowWithInterest) = _paybackPerfectInOneToken(
            dexKey_,
            shares_,
            maxToken0_,
            maxToken1_,
            estimate_
        );

        PendingTransfers.addPendingBorrow(msg.sender, token_, -int256(paybackAmt_));

        totalAmountsChange_ = new TotalAmounts[](2);
        totalAmountsChange_[0] = token0TotalAmountsChange_;
        totalAmountsChange_[1] = token1TotalAmountsChange_;

        returnData_ = abi.encode(paybackAmt_);
    }
}
