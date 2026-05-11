// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

library PoolLock {
    // bytes32(uint256(keccak256("FLUID_DEX_V2_REENTRANCY_LOCK")) - 1)
    bytes32 constant REENTRANCY_LOCK_SLOT = 0x161c735efd49ae2a49fd9dbcfbe3be02e3cc6b3161408603cddfa1851b1278ea;

    function lock(bytes32 dexId_) internal {
        bytes32 key = keccak256(abi.encode(REENTRANCY_LOCK_SLOT, dexId_));
        assembly {
            if tload(key) { revert(0, 0) }
            tstore(key, 1)
        }
    }

    function unlock(bytes32 dexId_) internal {
        bytes32 key = keccak256(abi.encode(REENTRANCY_LOCK_SLOT, dexId_));
        assembly { tstore(key, 0) }
    }
}
