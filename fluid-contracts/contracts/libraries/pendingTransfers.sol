// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

/// @notice Library for managing pending token transfers using transient storage
/// @dev These transfers are temporary and only exist within a single transaction
library PendingTransfers {
    // Custom errors
    error PendingSupplyNotCleared();
    error PendingBorrowNotCleared();
    error PendingTransfersNotCleared();

    // bytes32(uint256(keccak256("FLUID_DEX_V2_PENDING_SUPPLY")) - 1)
    bytes32 constant PENDING_SUPPLY_SLOT = 0x1f9fe0a780efbf168c8fd810da059a7db6663cde8eba217dd821a7835cf20a90;

    // bytes32(uint256(keccak256("FLUID_DEX_V2_PENDING_BORROW")) - 1)
    bytes32 constant PENDING_BORROW_SLOT = 0xc635a7f3d9cd0b7d4d1f19812847a3c1f84d9f5e2122dad3be5b18f057c49939;

    // Slot for tracking the count of tokens with pending supply
    // bytes32(uint256(keccak256("FLUID_DEX_V2_PENDING_SUPPLY_COUNT")) - 1)
    bytes32 constant PENDING_SUPPLY_COUNT_SLOT = 0x160e3eae53eb5e6bab86ba926e1fc6aa97060a9a6c4c61fefab056c4c92aee16;

    // Slot for tracking the count of tokens with pending borrow
    // bytes32(uint256(keccak256("FLUID_DEX_V2_PENDING_BORROW_COUNT")) - 1)
    bytes32 constant PENDING_BORROW_COUNT_SLOT = 0x53abf9dcada09a46758e0e7f58efc5c79e938aa3968f2844595df8b0794c5ab8;

    /// @notice Get the pending supply amount for a token and user
    /// @param token_ The token address
    /// @param user_ The user address
    /// @return amount_ The pending supply amount (can be negative)
    function getPendingSupply(address user_, address token_) internal view returns (int256 amount_) {
        bytes32 key_ = keccak256(abi.encode(PENDING_SUPPLY_SLOT, user_, token_));
        assembly ("memory-safe") {
            amount_ := tload(key_)
        }
    }

    /// @notice Get the pending borrow amount for a token and user
    /// @param token_ The token address
    /// @param user_ The user address
    /// @return amount_ The pending borrow amount (can be negative)
    function getPendingBorrow(address user_, address token_) internal view returns (int256 amount_) {
        bytes32 key_ = keccak256(abi.encode(PENDING_BORROW_SLOT, user_, token_));
        assembly ("memory-safe") {
            amount_ := tload(key_)
        }
    }

    /// @notice Set the pending supply amount for a token and user
    /// @param token_ The token address
    /// @param user_ The user address
    /// @param amount_ The amount to set
    function setPendingSupply(address user_, address token_, int256 amount_) internal {
        bytes32 key_ = keccak256(abi.encode(PENDING_SUPPLY_SLOT, user_, token_));
        int256 previousAmount_;

        assembly ("memory-safe") {
            previousAmount_ := tload(key_)
            tstore(key_, amount_)
        }

        // Update the pending tokens count
        if (previousAmount_ == 0 && amount_ != 0) {
            incrementPendingSupplyCount();
        } else if (previousAmount_ != 0 && amount_ == 0) {
            decrementPendingSupplyCount();
        }
    }

    /// @notice Set the pending borrow amount for a token and user
    /// @param token_ The token address
    /// @param user_ The user address
    /// @param amount_ The amount to set
    function setPendingBorrow(address user_, address token_, int256 amount_) internal {
        bytes32 key_ = keccak256(abi.encode(PENDING_BORROW_SLOT, user_, token_));
        int256 previousAmount_;

        assembly ("memory-safe") {
            previousAmount_ := tload(key_)
            tstore(key_, amount_)
        }

        // Update the pending tokens count
        if (previousAmount_ == 0 && amount_ != 0) {
            incrementPendingBorrowCount();
        } else if (previousAmount_ != 0 && amount_ == 0) {
            decrementPendingBorrowCount();
        }
    }

    /// @notice Update the pending supply amount for a token and user
    /// @param user_ The user address
    /// @param token_ The token address
    /// @param amount_ The amount to add (can be negative)
    function addPendingSupply(address user_, address token_, int256 amount_) internal {
        if (amount_ == 0) return;

        bytes32 key_ = keccak256(abi.encode(PENDING_SUPPLY_SLOT, user_, token_));
        int256 previousAmount_;
        assembly ("memory-safe") {
            previousAmount_ := tload(key_)
        }
        int256 newAmount_ = previousAmount_ + amount_;
        assembly ("memory-safe") {
            tstore(key_, newAmount_)
        }

        // Update the pending tokens count
        if (previousAmount_ == 0 && newAmount_ != 0) {
            incrementPendingSupplyCount();
        } else if (previousAmount_ != 0 && newAmount_ == 0) {
            decrementPendingSupplyCount();
        }
    }

    /// @notice Update the pending borrow amount for a token and user
    /// @param user_ The user address
    /// @param token_ The token address
    /// @param amount_ The amount to add (can be negative)
    function addPendingBorrow(address user_, address token_, int256 amount_) internal {
        if (amount_ == 0) return;

        bytes32 key_ = keccak256(abi.encode(PENDING_BORROW_SLOT, user_, token_));
        int256 previousAmount_;
        assembly ("memory-safe") {
            previousAmount_ := tload(key_)
        }
        int256 newAmount_ = previousAmount_ + amount_;
        assembly ("memory-safe") {
            tstore(key_, newAmount_)
        }

        // Update the pending tokens count
        if (previousAmount_ == 0 && newAmount_ != 0) {
            incrementPendingBorrowCount();
        } else if (previousAmount_ != 0 && newAmount_ == 0) {
            decrementPendingBorrowCount();
        }
    }

    /// @notice Get the count of tokens with pending supply
    /// @return count_ The number of tokens with non-zero pending supply
    function getPendingSupplyCount() internal view returns (uint256 count_) {
        assembly ("memory-safe") {
            count_ := tload(PENDING_SUPPLY_COUNT_SLOT)
        }
    }

    /// @notice Get the count of tokens with pending borrow
    /// @return count_ The number of tokens with non-zero pending borrow
    function getPendingBorrowCount() internal view returns (uint256 count_) {
        assembly ("memory-safe") {
            count_ := tload(PENDING_BORROW_COUNT_SLOT)
        }
    }

    /// @notice Increment the count of tokens with pending supply
    function incrementPendingSupplyCount() internal {
        assembly ("memory-safe") {
            tstore(PENDING_SUPPLY_COUNT_SLOT, add(tload(PENDING_SUPPLY_COUNT_SLOT), 1))
        }
    }

    /// @notice Increment the count of tokens with pending borrow
    function incrementPendingBorrowCount() internal {
        assembly ("memory-safe") {
            tstore(PENDING_BORROW_COUNT_SLOT, add(tload(PENDING_BORROW_COUNT_SLOT), 1))
        }
    }

    /// @notice Decrement the count of tokens with pending supply
    function decrementPendingSupplyCount() internal {
        assembly ("memory-safe") {
            tstore(PENDING_SUPPLY_COUNT_SLOT, sub(tload(PENDING_SUPPLY_COUNT_SLOT), 1))
        }
    }

    /// @notice Decrement the count of tokens with pending borrow
    function decrementPendingBorrowCount() internal {
        assembly ("memory-safe") {
            tstore(PENDING_BORROW_COUNT_SLOT, sub(tload(PENDING_BORROW_COUNT_SLOT), 1))
        }
    }

    /// @notice Check if all pending supply transfers have been cleared
    /// @return True if all pending supply transfers are zero
    function allPendingSupplyCleared() internal view returns (bool) {
        return getPendingSupplyCount() == 0;
    }

    /// @notice Check if all pending borrow transfers have been cleared
    /// @return True if all pending borrow transfers are zero
    function allPendingBorrowCleared() internal view returns (bool) {
        return getPendingBorrowCount() == 0;
    }

    /// @notice Check if all pending transfers (both supply and borrow) have been cleared
    /// @return True if all pending transfers are zero
    function allPendingTransfersCleared() internal view returns (bool) {
        return allPendingSupplyCleared() && allPendingBorrowCleared();
    }

    /// @notice Require that all pending supply transfers have been cleared
    function requireAllPendingSupplyCleared() internal view {
        if(!allPendingSupplyCleared()) revert PendingSupplyNotCleared();
    }

    /// @notice Require that all pending borrow transfers have been cleared
    function requireAllPendingBorrowCleared() internal view {
        if(!allPendingBorrowCleared()) revert PendingBorrowNotCleared();
    }

    /// @notice Require that all pending transfers (both supply and borrow) have been cleared
    /// @dev Call this at the end of transactions to ensure all tokens are properly settled
    function requireAllPendingTransfersCleared() internal view {
        if(!allPendingTransfersCleared()) revert PendingTransfersNotCleared();
    }
}
