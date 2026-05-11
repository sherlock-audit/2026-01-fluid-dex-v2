// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

/// @notice library that helps in reading / working with storage slot data of Fluid Dex V2 D3D3 Common
library DexV2D3D4CommonSlotsLink {
    /// @dev storage slot for dex variables
    uint256 internal constant DEX_V2_VARIABLES_SLOT = 0;
    /// @dev storage slot for dex variables 2
    uint256 internal constant DEX_V2_VARIABLES2_SLOT = 1;
    /// @dev storage slot for tick bitmap mapping
    uint256 internal constant DEX_V2_TICK_BITMAP_MAPPING_SLOT = 2;
    /// @dev storage slot for tick data mapping
    uint256 internal constant DEX_V2_TICK_LIQUIDITY_GROSS_MAPPING_SLOT = 3;
    /// @dev storage slot for tick data2 mapping
    uint256 internal constant DEX_V2_TICK_DATA_MAPPING_SLOT = 4;
    /// @dev storage slot for position data mapping
    uint256 internal constant DEX_V2_POSITION_DATA_MAPPING_SLOT = 5;
    /// @dev storage slot for token reserves mapping
    uint256 internal constant DEX_V2_TOKEN_RESERVES_MAPPING_SLOT = 6;
    /// @dev storage slot for whitelisted users mapping
    uint256 internal constant DEX_V2_WHITELISTED_USERS_MAPPING_SLOT = 7;
    /// @dev storage slot for dex key mapping
    uint256 internal constant DEX_V2_DEX_KEY_MAPPING_SLOT = 8;
    // --------------------------------
    // @dev stacked uint256 storage slots bits position data for each:

    // DexVariables
    uint256 internal constant BITS_DEX_V2_VARIABLES_CURRENT_TICK_SIGN = 0;
    uint256 internal constant BITS_DEX_V2_VARIABLES_ABSOLUTE_CURRENT_TICK = 1;
    uint256 internal constant BITS_DEX_V2_VARIABLES_CURRENT_SQRT_PRICE = 20;
    uint256 internal constant BITS_DEX_V2_VARIABLES_FEE_GROWTH_GLOBAL_0_X102 = 92;
    uint256 internal constant BITS_DEX_V2_VARIABLES_FEE_GROWTH_GLOBAL_1_X102 = 174;

    // DexVariables2
    uint256 internal constant BITS_DEX_V2_VARIABLES2_PROTOCOL_FEE_0_TO_1 = 0;
    uint256 internal constant BITS_DEX_V2_VARIABLES2_PROTOCOL_FEE_1_TO_0 = 12;
    uint256 internal constant BITS_DEX_V2_VARIABLES2_PROTOCOL_CUT_FEE = 24;
    uint256 internal constant BITS_DEX_V2_VARIABLES2_TOKEN_0_DECIMALS = 30;
    uint256 internal constant BITS_DEX_V2_VARIABLES2_TOKEN_1_DECIMALS = 34;
    uint256 internal constant BITS_DEX_V2_VARIABLES2_ACTIVE_LIQUIDITY = 38;
    uint256 internal constant BITS_DEX_V2_VARIABLES2_POOL_ACCOUNTING_FLAG = 140;
    uint256 internal constant BITS_DEX_V2_VARIABLES2_FETCH_DYNAMIC_FEE_FLAG = 141;
    // FEE VARIABLES
    uint256 internal constant BITS_DEX_V2_VARIABLES2_FEE_VERSION = 152;
    // Fee Version 0: Static Fee
    uint256 internal constant BITS_DEX_V2_VARIABLES2_LP_FEE = 156;
    // Fee Version 1: Pool Inbuilt Dynamic Fee
    /// Dynamic Fee Configs
    uint256 internal constant BITS_DEX_V2_VARIABLES2_MAX_DECAY_TIME = 156;
    uint256 internal constant BITS_DEX_V2_VARIABLES2_PRICE_IMPACT_TO_FEE_DIVISION_FACTOR = 168;
    uint256 internal constant BITS_DEX_V2_VARIABLES2_MIN_FEE = 176;
    uint256 internal constant BITS_DEX_V2_VARIABLES2_MAX_FEE = 192;
    /// Dynamic Fee Variables
    uint256 internal constant BITS_DEX_V2_VARIABLES2_NET_PRICE_IMPACT_SIGN = 208;
    uint256 internal constant BITS_DEX_V2_VARIABLES2_ABSOLUTE_NET_PRICE_IMPACT = 209;
    uint256 internal constant BITS_DEX_V2_VARIABLES2_LAST_UPDATE_TIMESTAMP = 229;
    uint256 internal constant BITS_DEX_V2_VARIABLES2_DECAY_TIME_REMAINING = 244;

    // Token Reserves
    uint256 internal constant BITS_DEX_V2_TOKEN_RESERVES_TOKEN_0_RESERVES = 0;
    uint256 internal constant BITS_DEX_V2_TOKEN_RESERVES_TOKEN_1_RESERVES = 128;

    // --------------------------------

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
