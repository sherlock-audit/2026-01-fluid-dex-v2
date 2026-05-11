// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

library OperationControl {
    // Slot for the Operation state in transient storage
    // bytes32(uint256(keccak256("FLUID_DEX_V2_OPERATION_ACTIVE")) - 1)
    bytes32 private constant OPERATION_ACTIVE_SLOT = 0x3951e0acca6b3e761373733cbf29a850d1b2d764474f1915f718668e96e36ab7;

    function isOperationActive() internal view returns (bool) {
        uint256 value;
        assembly {
            value := tload(OPERATION_ACTIVE_SLOT)
        }
        return value == 1;
    }

    function activateOperation() internal {
        assembly {
            if tload(OPERATION_ACTIVE_SLOT) { revert(0, 0) }
            tstore(OPERATION_ACTIVE_SLOT, 1)
        }
    }

    function deactivateOperation() internal {
        assembly {
            tstore(OPERATION_ACTIVE_SLOT, 0)
        }
    }
}
