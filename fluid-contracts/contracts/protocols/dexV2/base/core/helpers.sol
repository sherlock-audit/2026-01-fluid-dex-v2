// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { BigMathMinified as BM } from "../../../../libraries/bigMathMinified.sol";
import { DexV2BaseSlotsLink as DSL } from "../../../../libraries/dexV2BaseSlotsLink.sol";
import { LiquiditySlotsLink as LSL } from "../../../../libraries/liquiditySlotsLink.sol";
import { LiquidityCalcs as LC } from "../../../../libraries/liquidityCalcs.sol";
import { PendingTransfers as PT } from "../../../../libraries/pendingTransfers.sol";
import { SafeTransfer } from "../../../../libraries/safeTransfer.sol";
import { OperationControl as OC } from "../../../../libraries/operationControl.sol";
import { ReentrancyLock } from "../../../../libraries/reentrancyLock.sol";
import "../other/commonImport.sol";

abstract contract Helpers is CommonImport {
    /// @notice Modifier to ensure function is called only after operation has started
    /// @dev Reverts if operation is not active
    modifier _onlyAfterOperationStarted() {
        if (!OC.isOperationActive()) {
            revert FluidDexV2Error(ErrorTypes.DexV2Helpers__OperationNotActive);
        }
        _;
    }

    /// @notice Modifier to ensure function enforces reentrancy lock
    /// @dev Reverts if reentrancy occurs
    modifier _reentrancyLock() {
        ReentrancyLock.lock();
        _;
        ReentrancyLock.unlock();
    }

    /// @dev            do any arbitrary call
    /// @param target_  Address to which the call needs to be delegated
    /// @param data_    Data to execute at the delegated address
    function _spell(address target_, bytes memory data_) internal returns (bytes memory response_) {
        assembly {
            let succeeded := delegatecall(gas(), target_, add(data_, 0x20), mload(data_), 0, 0)
            let size := returndatasize()

            response_ := mload(0x40)
            mstore(0x40, add(response_, and(add(add(size, 0x20), 0x1f), not(0x1f))))
            mstore(response_, size)
            returndatacopy(add(response_, 0x20), 0, size)

            if iszero(succeeded) {
                // throw if delegatecall failed
                returndatacopy(0x00, 0x00, size)
                revert(0x00, size)
            }
        }
    }

    function _getGovernanceAddr() internal view returns (address governance_) {
        governance_ = address(uint160(LIQUIDITY.readFromStorage(LIQUIDITY_GOVERNANCE_SLOT)));
    }
    
    function _updateSettledAmountsOnStorage(address token_, int256 supplyAmount_, int256 borrowAmount_, int256 storeAmount_) internal {
        if (supplyAmount_ != 0) PT.addPendingSupply(msg.sender, token_, -supplyAmount_);
        if (borrowAmount_ != 0) PT.addPendingBorrow(msg.sender, token_, -borrowAmount_);
        if (storeAmount_ != 0) {
            // update user stored token amount
            int256 storedTokenAmount_ = int256(_userStoredTokenAmount[BASE_SLOT][msg.sender][token_]) + storeAmount_;
            if (storedTokenAmount_ < 0) {
                revert FluidDexV2Error(ErrorTypes.DexV2Helpers__StoredTokenAmountNegative);
            }
            _userStoredTokenAmount[BASE_SLOT][msg.sender][token_] = uint256(storedTokenAmount_);
        }
    }

    function _callLiquidityLayer(address token_, int256 supplyAmount_, int256 borrowAmount_, address to_, bool isCallback_) internal returns (bool success_) {
        if (supplyAmount_ == borrowAmount_) {
            // Supply and Borrow are cancelling each other out, hence we can skip transfers
            if (msg.value > 0) SafeTransfer.safeTransferNative(msg.sender, msg.value);
            try LIQUIDITY.operate(
                token_,
                supplyAmount_,
                borrowAmount_,
                address(this),
                address(this),
                abi.encode(DEXV2_IDENTIFIER, SETTLE_ACTION_IDENTIFIER, SKIP_TRANSFERS, address(this))
            ) { success_ = true; } catch { success_ = false; }
        } else if (borrowAmount_ == 0) {
            // Only Supply or Withdraw
            if (supplyAmount_ > 0) { 
                // Supply
                unchecked {
                    if (token_ == NATIVE_TOKEN) {
                        if (msg.value > uint256(supplyAmount_)) SafeTransfer.safeTransferNative(msg.sender, msg.value - uint256(supplyAmount_));
                        else if (msg.value < uint256(supplyAmount_)) {
                            revert FluidDexV2Error(ErrorTypes.DexV2Helpers__MsgValueMismatch);
                        }
                        try LIQUIDITY.operate{value: uint256(supplyAmount_)}(
                            token_,
                            supplyAmount_,
                            0,
                            address(0),
                            address(0),
                            abi.encode(DEXV2_IDENTIFIER, SETTLE_ACTION_IDENTIFIER)
                        ) { success_ = true; } catch { success_ = false; }
                    } else {
                        try LIQUIDITY.operate(
                            token_, 
                            supplyAmount_, 
                            0, 
                            address(0), 
                            address(0), 
                            abi.encode(DEXV2_IDENTIFIER, SETTLE_ACTION_IDENTIFIER, uint256(supplyAmount_), isCallback_, msg.sender)
                        ) { success_ = true; } catch { success_ = false; }
                    }
                }
            } else {
                // Withdraw
                if (msg.value > 0) SafeTransfer.safeTransferNative(msg.sender, msg.value);
                try LIQUIDITY.operate(
                    token_, 
                    supplyAmount_, 
                    0, 
                    to_, 
                    address(0), 
                    abi.encode(DEXV2_IDENTIFIER, SETTLE_ACTION_IDENTIFIER)
                ) { success_ = true; } catch { success_ = false; }
            }
        } else if (supplyAmount_ == 0) {
            // Only Borrow or Payback
            if (borrowAmount_ > 0) {
                // Borrow
                if (msg.value > 0) SafeTransfer.safeTransferNative(msg.sender, msg.value);
                try LIQUIDITY.operate(
                    token_, 
                    0, 
                    borrowAmount_, 
                    address(0), 
                    to_, 
                    abi.encode(DEXV2_IDENTIFIER, SETTLE_ACTION_IDENTIFIER)
                ) { success_ = true; } catch { success_ = false; }
            } else {
                // Payback
                unchecked {
                    if (token_ == NATIVE_TOKEN) {
                        if (msg.value > uint256(-borrowAmount_)) SafeTransfer.safeTransferNative(msg.sender, msg.value - uint256(-borrowAmount_));
                        else if (msg.value < uint256(-borrowAmount_)) {
                            revert FluidDexV2Error(ErrorTypes.DexV2Helpers__MsgValueMismatch);
                        }
                        try LIQUIDITY.operate{value: uint256(-borrowAmount_)}(
                            token_, 
                            0, 
                            borrowAmount_, 
                            address(0), 
                            address(0), 
                            abi.encode(DEXV2_IDENTIFIER, SETTLE_ACTION_IDENTIFIER)
                        ) { success_ = true; } catch { success_ = false; }
                    } else {
                        try LIQUIDITY.operate(
                            token_, 
                            0, 
                            borrowAmount_, 
                            address(0),
                            address(0), 
                            abi.encode(DEXV2_IDENTIFIER, SETTLE_ACTION_IDENTIFIER, uint256(-borrowAmount_), isCallback_, msg.sender)
                        ) { success_ = true; } catch { success_ = false; }
                    }
                }
            }
        } else if (supplyAmount_ > 0 && borrowAmount_ < 0) {
            // User is only paying (supply and payback)
            uint256 totalAmountIn_ = uint256(supplyAmount_ - borrowAmount_);
            if (token_ == NATIVE_TOKEN) {
                unchecked {
                    if (msg.value > totalAmountIn_) SafeTransfer.safeTransferNative(msg.sender, msg.value - totalAmountIn_);
                    else if (msg.value < totalAmountIn_) {
                        revert FluidDexV2Error(ErrorTypes.DexV2Helpers__MsgValueMismatch);
                    }
                }
                try LIQUIDITY.operate{value: totalAmountIn_}(
                    token_, 
                    supplyAmount_, 
                    borrowAmount_, 
                    address(0), 
                    address(0), 
                    abi.encode(DEXV2_IDENTIFIER, SETTLE_ACTION_IDENTIFIER)
                ) { success_ = true; } catch { success_ = false; }
            } else {
                // msg.value cannot be greater than zero because it would have already reverted earlier
                try LIQUIDITY.operate(
                    token_, 
                    supplyAmount_, 
                    borrowAmount_, 
                    address(0), 
                    address(0), 
                    abi.encode(DEXV2_IDENTIFIER, SETTLE_ACTION_IDENTIFIER, totalAmountIn_, isCallback_, msg.sender)
                ) { success_ = true; } catch { success_ = false; }
            }
        } else if (supplyAmount_ < 0 && borrowAmount_ > 0) {
            // User is only getting paid (withdraw and borrow)
            if (msg.value > 0) SafeTransfer.safeTransferNative(msg.sender, msg.value);
            try LIQUIDITY.operate(
                token_, 
                supplyAmount_, 
                borrowAmount_, 
                to_, 
                to_, 
                abi.encode(DEXV2_IDENTIFIER, SETTLE_ACTION_IDENTIFIER)
            ) { success_ = true; } catch { success_ = false; }
        } else {
            // NET TRANSFERS CASE: deposit & borrow or withdraw & payback (supplyAmount and borrowAmount are of the same sign in each case)
            if (supplyAmount_ > borrowAmount_) {
                // Net tokens in from user
                address withdrawTo_;
                address borrowTo_;
                if (supplyAmount_ < 0) {
                    withdrawTo_ = msg.sender; // using msg.sender instead of to_ here because it has to be equal to inFrom_ address passed, and inFrom_ is where callback will go so it has to msg.sender
                    borrowTo_ = address(0);
                } else {
                    withdrawTo_ = address(0);
                    borrowTo_ = msg.sender; // using msg.sender instead of to_ here because it has to be equal to inFrom_ address passed, and inFrom_ is where callback will go so it has to msg.sender
                }
                // can use unchecked here because both supplyAmount_ and borrowAmount_ have the same sign, so the absolute difference will be withing bounds of int256, and also we have already checked that supplyAmount_ > borrowAmount_
                uint256 netTokenInAmount_;
                unchecked {
                    netTokenInAmount_ = uint256(supplyAmount_ - borrowAmount_);
                }
                if (token_ == NATIVE_TOKEN) {
                    unchecked {
                        if (msg.value > netTokenInAmount_) SafeTransfer.safeTransferNative(msg.sender, msg.value - netTokenInAmount_);
                        else if (msg.value < netTokenInAmount_) {
                            revert FluidDexV2Error(ErrorTypes.DexV2Helpers__InvalidParams);
                        }
                    }
                    try LIQUIDITY.operate{value: netTokenInAmount_}(
                        token_,
                        supplyAmount_,
                        borrowAmount_,
                        withdrawTo_,
                        borrowTo_,
                        abi.encode(DEXV2_IDENTIFIER, SETTLE_ACTION_IDENTIFIER, NET_TRANSFERS, msg.sender)
                    ) { success_ = true; } catch { success_ = false; }
                } else {
                    // msg.value cannot be greater than zero because it would have already reverted earlier
                    try LIQUIDITY.operate(
                        token_,
                        supplyAmount_,
                        borrowAmount_,
                        withdrawTo_,
                        borrowTo_,
                        abi.encode(
                            DEXV2_IDENTIFIER,
                            SETTLE_ACTION_IDENTIFIER,
                            netTokenInAmount_,
                            isCallback_,
                            msg.sender,
                            NET_TRANSFERS,
                            msg.sender
                        )
                    ) { success_ = true; } catch { success_ = false; }
                }
            } else {
                // Net tokens out to user
                address withdrawTo_;
                address borrowTo_;
                if (supplyAmount_ < 0) {
                    withdrawTo_ = to_;
                } else {
                    borrowTo_ = to_;
                }

                if (token_ == NATIVE_TOKEN && msg.value > 0) {
                    SafeTransfer.safeTransferNative(msg.sender, msg.value);
                }
                try LIQUIDITY.operate(
                    token_,
                    supplyAmount_,
                    borrowAmount_,
                    withdrawTo_,
                    borrowTo_,
                    abi.encode(DEXV2_IDENTIFIER, SETTLE_ACTION_IDENTIFIER, NET_TRANSFERS, to_)
                ) { success_ = true; } catch { success_ = false; }
            }
        }
    }
}
