// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import "./coreInternals.sol";
import { PendingTransfers } from "../../../../../libraries/pendingTransfers.sol";

// TODO: @Vaibhav add events

// import { ErrorTypes } from "../../../errorTypes.sol"; // TODO: Update this and all reverts
// import { IFluidDexT1 } from "../../../interfaces/iDexT1.sol"; // TODO: Update this

/// @title FluidDexT1
/// @notice Implements core logics for Fluid Dex protocol.
/// Note Token transfers happen directly from user to Liquidity contract and vice-versa.
contract FluidDexV2D1 is CoreInternals {
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
        (amountOut_, token0TotalAmountsChange_.totalSupplyWithInterest, token1TotalAmountsChange_.totalSupplyWithInterest) = _swapIn(
            dexKey_,
            swap0To1_,
            amountIn_,
            amountOutMin_,
            estimate_
        );

        if (swap0To1_) {
            PendingTransfers.addPendingSupply(msg.sender, dexKey_.token0, int256(amountIn_));
            PendingTransfers.addPendingSupply(msg.sender, dexKey_.token1, -int256(amountOut_));
        } else {
            PendingTransfers.addPendingSupply(msg.sender, dexKey_.token1, int256(amountIn_));
            PendingTransfers.addPendingSupply(msg.sender, dexKey_.token0, -int256(amountOut_));
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
        (amountIn_, token0TotalAmountsChange_.totalSupplyWithInterest, token1TotalAmountsChange_.totalSupplyWithInterest) = _swapOut(
            dexKey_,
            swap0To1_,
            amountOut_,
            amountInMax_,
            estimate_
        );

        if (swap0To1_) {
            PendingTransfers.addPendingSupply(msg.sender, dexKey_.token0, int256(amountIn_));
            PendingTransfers.addPendingSupply(msg.sender, dexKey_.token1, -int256(amountOut_));
        } else {
            PendingTransfers.addPendingSupply(msg.sender, dexKey_.token1, int256(amountIn_));
            PendingTransfers.addPendingSupply(msg.sender, dexKey_.token0, -int256(amountOut_));
        }

        totalAmountsChange_ = new TotalAmounts[](2);
        totalAmountsChange_[0] = token0TotalAmountsChange_;
        totalAmountsChange_[1] = token1TotalAmountsChange_;

        returnData_ = abi.encode(amountIn_);
    }

    /// @dev This function allows users to deposit tokens in any proportion into the col pool
    /// @param token0Amt_ The amount of token0 to deposit
    /// @param token1Amt_ The amount of token1 to deposit
    /// @param minSharesAmt_ The minimum amount of shares the user expects to receive
    /// @param estimate_ If true, function will revert with estimated shares without executing the deposit
    function deposit(
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
        (shares_, token0TotalAmountsChange_.totalSupplyWithInterest, token1TotalAmountsChange_.totalSupplyWithInterest) = _deposit(
            dexKey_,
            token0Amt_,
            token1Amt_,
            minSharesAmt_,
            estimate_
        );

        PendingTransfers.addPendingSupply(msg.sender, dexKey_.token0, int256(token0Amt_));
        PendingTransfers.addPendingSupply(msg.sender, dexKey_.token1, int256(token1Amt_));

        totalAmountsChange_ = new TotalAmounts[](2);
        totalAmountsChange_[0] = token0TotalAmountsChange_;
        totalAmountsChange_[1] = token1TotalAmountsChange_;

        returnData_ = abi.encode(shares_);
    }

    /// @dev This function allows users to withdraw tokens in any proportion from the col pool
    /// @param token0Amt_ The amount of token0 to withdraw
    /// @param token1Amt_ The amount of token1 to withdraw
    /// @param maxSharesAmt_ The maximum number of shares the user is willing to burn
    /// @param estimate_ If true, function will revert with estimated shares without executing the withdrawal
    function withdraw(
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
        (shares_, token0TotalAmountsChange_.totalSupplyWithInterest, token1TotalAmountsChange_.totalSupplyWithInterest) = _withdraw(
            dexKey_,
            token0Amt_,
            token1Amt_,
            maxSharesAmt_,
            estimate_
        );

        PendingTransfers.addPendingSupply(msg.sender, dexKey_.token0, -int256(token0Amt_));
        PendingTransfers.addPendingSupply(msg.sender, dexKey_.token1, -int256(token1Amt_));

        totalAmountsChange_ = new TotalAmounts[](2);
        totalAmountsChange_[0] = token0TotalAmountsChange_;
        totalAmountsChange_[1] = token1TotalAmountsChange_;

        returnData_ = abi.encode(shares_);
    }

    /// @dev Deposit tokens in equal proportion to the current pool ratio
    /// @param shares_ The number of shares to mint
    /// @param maxToken0Deposit_ Maximum amount of token0 to deposit
    /// @param maxToken1Deposit_ Maximum amount of token1 to deposit
    /// @param estimate_ If true, function will revert with estimated deposit amounts without executing the deposit
    function depositPerfect(
        DexKey calldata dexKey_,
        uint256 shares_,
        uint256 maxToken0Deposit_,
        uint256 maxToken1Deposit_,
        bool estimate_
    ) external _onlyDelegateCall returns (TotalAmounts[] memory totalAmountsChange_, bytes memory returnData_) {
        TotalAmounts memory token0TotalAmountsChange_;
        token0TotalAmountsChange_.token = dexKey_.token0;

        TotalAmounts memory token1TotalAmountsChange_;
        token1TotalAmountsChange_.token = dexKey_.token1;

        uint256 token0Amt_;
        uint256 token1Amt_;
        (token0Amt_, token1Amt_, token0TotalAmountsChange_.totalSupplyWithInterest, token1TotalAmountsChange_.totalSupplyWithInterest) = _depositPerfect(
            dexKey_,
            shares_,
            maxToken0Deposit_,
            maxToken1Deposit_,
            estimate_
        );

        PendingTransfers.addPendingSupply(msg.sender, dexKey_.token0, int256(token0Amt_));
        PendingTransfers.addPendingSupply(msg.sender, dexKey_.token1, int256(token1Amt_));

        totalAmountsChange_ = new TotalAmounts[](2);
        totalAmountsChange_[0] = token0TotalAmountsChange_;
        totalAmountsChange_[1] = token1TotalAmountsChange_;

        returnData_ = abi.encode(token0Amt_, token1Amt_);
    }

    /// @dev This function allows users to withdraw a perfect amount of collateral liquidity
    /// @param shares_ The number of shares to withdraw
    /// @param minToken0Withdraw_ The minimum amount of token0 the user is willing to accept
    /// @param minToken1Withdraw_ The minimum amount of token1 the user is willing to accept
    /// @param estimate_ If true, function will revert with estimated token0Amt_ & token1Amt_ without executing the withdrawal
    function withdrawPerfect(
        DexKey calldata dexKey_,
        uint256 shares_,
        uint256 minToken0Withdraw_,
        uint256 minToken1Withdraw_,
        bool estimate_
    ) external _onlyDelegateCall returns (TotalAmounts[] memory totalAmountsChange_, bytes memory returnData_) {
        TotalAmounts memory token0TotalAmountsChange_;
        token0TotalAmountsChange_.token = dexKey_.token0;

        TotalAmounts memory token1TotalAmountsChange_;
        token1TotalAmountsChange_.token = dexKey_.token1;

        uint256 token0Amt_;
        uint256 token1Amt_;
        (token0Amt_, token1Amt_, token0TotalAmountsChange_.totalSupplyWithInterest, token1TotalAmountsChange_.totalSupplyWithInterest) = _withdrawPerfect(
            dexKey_,
            shares_,
            minToken0Withdraw_,
            minToken1Withdraw_,
            estimate_
        );

        PendingTransfers.addPendingSupply(msg.sender, dexKey_.token0, -int256(token0Amt_));
        PendingTransfers.addPendingSupply(msg.sender, dexKey_.token1, -int256(token1Amt_));

        totalAmountsChange_ = new TotalAmounts[](2);
        totalAmountsChange_[0] = token0TotalAmountsChange_;
        totalAmountsChange_[1] = token1TotalAmountsChange_;

        returnData_ = abi.encode(token0Amt_, token1Amt_);
    }

    /// @dev This function allows users to withdraw their collateral with perfect shares in one token
    /// @param shares_ The number of shares to burn for withdrawal
    /// @param minToken0_ The minimum amount of token0 the user expects to receive (set to 0 if withdrawing in token1)
    /// @param minToken1_ The minimum amount of token1 the user expects to receive (set to 0 if withdrawing in token0)
    function withdrawPerfectInOneToken(
        DexKey calldata dexKey_,
        uint256 shares_,
        uint256 minToken0_,
        uint256 minToken1_,
        bool estimate_
    ) external _onlyDelegateCall returns (TotalAmounts[] memory totalAmountsChange_, bytes memory returnData_) {
        TotalAmounts memory token0TotalAmountsChange_;
        token0TotalAmountsChange_.token = dexKey_.token0;

        TotalAmounts memory token1TotalAmountsChange_;
        token1TotalAmountsChange_.token = dexKey_.token1;

        address token_;
        if (minToken0_ > 0) {
            token_ = dexKey_.token0;
        } else {
            token_ = dexKey_.token1;
        }

        uint256 withdrawAmt_;
        (withdrawAmt_, token0TotalAmountsChange_.totalSupplyWithInterest, token1TotalAmountsChange_.totalSupplyWithInterest) = _withdrawPerfectInOneToken(
            dexKey_,
            shares_,
            minToken0_,
            minToken1_,
            estimate_
        );

        PendingTransfers.addPendingSupply(msg.sender, token_, -int256(withdrawAmt_));

        totalAmountsChange_ = new TotalAmounts[](2);
        totalAmountsChange_[0] = token0TotalAmountsChange_;
        totalAmountsChange_[1] = token1TotalAmountsChange_;

        returnData_ = abi.encode(withdrawAmt_);
    }
}
