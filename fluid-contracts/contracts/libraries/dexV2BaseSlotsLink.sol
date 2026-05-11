// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

/// @notice library that helps in reading / working with storage slot data of Fluid Dex V2 Base.
library DexV2BaseSlotsLink {
    /// @dev storage slot for is auth mapping
    uint256 internal constant DEX_V2_IS_AUTH_MAPPING_SLOT = 0;
    /// @dev storage slot for dex type to admin implementation mapping
    uint256 internal constant DEX_V2_DEX_TYPE_TO_ADMIN_IMPLEMENTATION_MAPPING_SLOT = 1;
    /// @dev storage slot for user stored token amount mapping
    uint256 internal constant DEX_V2_USER_STORED_TOKEN_AMOUNT_MAPPING_SLOT = 2;
    /// @dev storage slot for total auth added amount mapping
    uint256 internal constant DEX_V2_TOTAL_AUTH_ADDED_AMOUNT_MAPPING_SLOT = 3;
    /// @dev storage slot for unaccounted borrow amount mapping
    uint256 internal constant DEX_V2_UNACCOUNTED_BORROW_AMOUNT_MAPPING_SLOT = 4;

    /// @notice Calculating the slot ID for Dex contract for single mapping at `slot_` for `key_`
    function calculateMappingStorageSlot(uint256 slot_, bytes32 key_) internal pure returns (bytes32) {
        return keccak256(abi.encode(key_, slot_));
    }

    /// @notice Calculating the slot ID for Dex contract for double mapping at `slot_` for `key1_` and `key2_`
    function calculateDoubleMappingStorageSlot(
        uint256 slot_,
        bytes32 key1_,
        bytes32 key2_
    ) internal pure returns (bytes32) {
        bytes32 intermediateSlot_ = keccak256(abi.encode(key1_, slot_));
        return keccak256(abi.encode(key2_, intermediateSlot_));
    }

    /// @notice Calculating the slot ID for Dex contract for triple mapping at `slot_` for `key1_`, `key2_` and `key3_`
    function calculateTripleMappingStorageSlot(
        uint256 slot_,
        bytes32 key1_,
        bytes32 key2_,
        bytes32 key3_
    ) internal pure returns (bytes32) {
        bytes32 intermediateSlot1_ = keccak256(abi.encode(key1_, slot_));
        bytes32 intermediateSlot2_ = keccak256(abi.encode(key2_, intermediateSlot1_));
        return keccak256(abi.encode(key3_, intermediateSlot2_));
    }
}
