// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import "./events.sol";

import { PendingTransfers } from "../../../../libraries/pendingTransfers.sol";

abstract contract Helpers is CommonImport {
    function _useFeeStoredForLiquidation(
        uint256 feeAmountToken0_,
        uint256 feeAmountToken1_,
        uint256 withdrawValue_,
        uint256 token0Price_,
        uint256 token1Price_,
        uint256 token0LiquidationPenalty_,
        uint256 token1LiquidationPenalty_
    ) internal pure returns (uint256 feeCollectionAmountToken0_, uint256 feeCollectionAmountToken1_) {
        if (feeAmountToken0_ > 0) {
            // Scaling up the withdraw value by the token0 liquidation penalty
            // rounded down so protocol is on the winning side
            withdrawValue_ = ((withdrawValue_ * (THREE_DECIMALS + token0LiquidationPenalty_)) - 1) / THREE_DECIMALS;
            if (withdrawValue_ > 0) withdrawValue_ -= 1;

            uint256 feeValue_ = (((feeAmountToken0_ * token0Price_) + 1) / EIGHTEEN_DECIMALS) + 1; // rounded up so protocol is on the winning side

            if (feeValue_ < withdrawValue_) {
                // Full fee amount 0 will be collected
                feeCollectionAmountToken0_ = feeAmountToken0_;
                withdrawValue_ -= feeValue_;

                // This withdraw value was scaled up by liquidation penalty, hence now the remaining portion needs to be scaled down
                // rounded down so protocol is on the winning side
                withdrawValue_ = ((withdrawValue_ * THREE_DECIMALS) - 1) / (THREE_DECIMALS + token0LiquidationPenalty_);
                if (withdrawValue_ > 0) withdrawValue_ -= 1;
            } else {
                // rounded down so protocol is on the winning side
                if (withdrawValue_ > 0) {
                    feeCollectionAmountToken0_ = ((withdrawValue_ * EIGHTEEN_DECIMALS) - 1) / token0Price_;
                    if (feeCollectionAmountToken0_ > 0) feeCollectionAmountToken0_ -= 1;
                }

                // added this check for safety
                if (feeCollectionAmountToken0_ > feeAmountToken0_) {
                    feeCollectionAmountToken0_ = feeAmountToken0_;
                }

                withdrawValue_ = 0;
            }
        }

        // NOTE: We will process further withdrawal using fee stored only if the withdraw value is greater than $0.01 i.e. 1 cent
        if (withdrawValue_ > 1e25 && feeAmountToken1_ > 0) {
            // Scaling up the withdraw value by the token1 liquidation penalty
            // rounded down so protocol is on the winning side
            withdrawValue_ = ((withdrawValue_ * (THREE_DECIMALS + token1LiquidationPenalty_)) - 1) / THREE_DECIMALS;
            if (withdrawValue_ > 0) withdrawValue_ -= 1;

            uint256 feeValue_ = (((feeAmountToken1_ * token1Price_) + 1) / EIGHTEEN_DECIMALS) + 1; // rounded up so protocol is on the winning side

            if (feeValue_ < withdrawValue_) {
                // Reverting here because the the fee wont be able to cover the withdraw value
                revert FluidMoneyMarketError(ErrorTypes.LiquidateModule__InvalidParams);
            } else {
                // rounded down so protocol is on the winning side
                feeCollectionAmountToken1_ = ((withdrawValue_ * EIGHTEEN_DECIMALS) - 1) / token1Price_;
                if (feeCollectionAmountToken1_ > 0) feeCollectionAmountToken1_ -= 1;

                // added this check for safety
                if (feeCollectionAmountToken1_ > feeAmountToken1_) {
                    feeCollectionAmountToken1_ = feeAmountToken1_;
                }

                withdrawValue_ = 0;
            }
        }

        if (withdrawValue_ > 1e25) {
            revert FluidMoneyMarketError(ErrorTypes.LiquidateModule__InvalidParams);
        }
    }

    /// @dev Calls DEX_V2.startOperation, handling estimate mode by extracting data from PendingTransfersNotCleared error.
    ///      If estimate_ is true and the error is NOT PendingTransfersNotCleared, the error is propagated (reverts).
    /// @param data_ The encoded data to pass to startOperation
    /// @param estimate_ Whether this is an estimate call (will extract data from revert)
    /// @return result_ The result bytes (either from success or extracted from error)
    function _startOperationWithEstimate(bytes memory data_, bool estimate_) internal returns (bytes memory result_) {
        if (estimate_) {
            try DEX_V2.startOperation(data_) returns (bytes memory res_) {
                result_ = res_;
            } catch (bytes memory lowLevelData_) {
                // Check if the error data is long enough to contain a selector + offset + length
                // PendingTransfersNotCleared(bytes data_) error format: selector(4) + offset(32) + length(32) + data
                if (lowLevelData_.length >= 68) {
                    bytes4 errorSelector_;
                    assembly {
                        // Extract the selector from the error data
                        errorSelector_ := mload(add(lowLevelData_, 0x20))
                    }
                    if (errorSelector_ == PendingTransfers.PendingTransfersNotCleared.selector) {
                        uint256 innerDataLen_;
                        assembly {
                            innerDataLen_ := mload(add(lowLevelData_, 0x44)) // length at offset 0x44
                        }
                        // Only extract data when it's exactly 96 bytes (bool, uint256, uint256)
                        // This is the only format that callers decode. Other lengths (e.g., 32 bytes for fee collection)
                        // are from operations where result is ignored, so returning empty bytes is fine.
                        // Also verify lowLevelData_ has enough bytes (68 header + 96 data = 164) for safe memory reads
                        if (innerDataLen_ == 96 && lowLevelData_.length >= 164) {
                            assembly {
                                result_ := mload(0x40) // free memory pointer
                                mstore(result_, 96) // store length
                                // Copy 3 words (96 bytes) directly
                                let src := add(lowLevelData_, 0x64) // data starts at 0x64
                                mstore(add(result_, 0x20), mload(src))            // bool (word 1)
                                mstore(add(result_, 0x40), mload(add(src, 0x20))) // uint256 (word 2)
                                mstore(add(result_, 0x60), mload(add(src, 0x40))) // uint256 (word 3)
                                mstore(0x40, add(result_, 0x80)) // update free memory pointer
                            }
                        }
                        // For PendingTransfersNotCleared with non-96-byte data (e.g., fee collection),
                        // result_ stays empty which is fine since those callers ignore the result
                        return result_;
                    }
                }
                // Not PendingTransfersNotCleared - propagate the original error
                assembly {
                    let size := returndatasize()
                    returndatacopy(0x00, 0x00, size)
                    revert(0x00, size)
                }
            }
        } else {
            result_ = DEX_V2.startOperation(data_);
        }
    }
}