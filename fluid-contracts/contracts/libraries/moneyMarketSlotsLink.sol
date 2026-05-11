// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

/// @notice library that helps in reading / working with storage slot data of Fluid Money Market.
/// @dev as all data for Fluid Money Market is internal, any data must be fetched directly through manual
library MoneyMarketSlotsLink {
    /// @dev storage slot for is auth mapping
    uint256 internal constant MONEY_MARKET_IS_AUTH_MAPPING_SLOT = 0;
    /// @dev storage slot for money market variables
    uint256 internal constant MONEY_MARKET_VARIABLES_SLOT = 1;
    /// @dev storage slot for nft configs mapping
    uint256 internal constant MONEY_MARKET_NFT_CONFIGS_MAPPING_SLOT = 2;
    /// @dev storage slot for nft owner config mapping
    uint256 internal constant MONEY_MARKET_NFT_OWNER_CONFIG_MAPPING_SLOT = 3;
    /// @dev storage slot for nft approved mapping
    uint256 internal constant MONEY_MARKET_NFT_APPROVED_MAPPING_SLOT = 4;
    /// @dev storage slot for nft approved for all mapping
    uint256 internal constant MONEY_MARKET_NFT_APPROVED_FOR_ALL_MAPPING_SLOT = 5;
    /// @dev storage slot for token configs mapping
    uint256 internal constant MONEY_MARKET_TOKEN_CONFIGS_MAPPING_SLOT = 6;
    /// @dev storage slot for position cap configs mapping
    uint256 internal constant MONEY_MARKET_POSITION_CAP_CONFIGS_MAPPING_SLOT = 7;
    /// @dev storage slot for default permissionless dex cap configs mapping
    uint256 internal constant MONEY_MARKET_DEFAULT_PERMISSIONLESS_DEX_CAP_CONFIGS_MAPPING_SLOT = 8;
    /// @dev storage slot for global default permissionless dex cap configs mapping
    uint256 internal constant MONEY_MARKET_GLOBAL_DEFAULT_PERMISSIONLESS_DEX_CAP_CONFIGS_MAPPING_SLOT = 9;
    /// @dev storage slot for isolated cap configs mapping
    uint256 internal constant MONEY_MARKET_ISOLATED_CAP_CONFIGS_MAPPING_SLOT = 10;
    /// @dev storage slot for emode map mapping
    uint256 internal constant MONEY_MARKET_EMODE_MAP_MAPPING_SLOT = 11;
    /// @dev storage slot for nft position data mapping
    uint256 internal constant MONEY_MARKET_POSITION_DATA_MAPPING_SLOT = 12;
    /// @dev storage slot for position fee stored mapping
    uint256 internal constant MONEY_MARKET_POSITION_FEE_STORED_MAPPING_SLOT = 13;
    /// @dev storage slot for token index mapping
    uint256 internal constant MONEY_MARKET_TOKEN_INDEX_MAPPING_SLOT = 14;
    /// @dev storage slot for permissioned d3 dexes list
    uint256 internal constant MONEY_MARKET_D3_PERMISSIONED_DEXES_LIST_SLOT = 15;
    /// @dev storage slot for permissioned d4 dexes list
    uint256 internal constant MONEY_MARKET_D4_PERMISSIONED_DEXES_LIST_SLOT = 16;
    /// @dev storage slot for isolated token to whitelisted debt tokens mapping
    uint256 internal constant MONEY_MARKET_ISOLATED_TOKEN_TO_WHITELISTED_DEBT_TOKENS_MAPPING_SLOT = 17;

    // --------------------------------
    /// @dev stacked uint256 storage slots bits position data for each:

    /// @dev Money Market Variables
    uint256 internal constant BITS_MONEY_MARKET_VARIABLES_ORACLE_ADDRESS = 0;
    uint256 internal constant BITS_MONEY_MARKET_VARIABLES_MAX_POSITIONS_PER_NFT = 160;
    uint256 internal constant BITS_MONEY_MARKET_VARIABLES_MIN_NORMALIZED_COLLATERAL_VALUE = 170;
    uint256 internal constant BITS_MONEY_MARKET_VARIABLES_HF_LIMIT_FOR_LIQUIDATION = 182;
    uint256 internal constant BITS_MONEY_MARKET_VARIABLES_TOTAL_TOKENS = 200;
    uint256 internal constant BITS_MONEY_MARKET_VARIABLES_TOTAL_EMODES = 212;
    uint256 internal constant BITS_MONEY_MARKET_VARIABLES_TOTAL_NFTS = 224;

    /// @dev NFT Configs
    uint256 internal constant BITS_NFT_CONFIGS_NFT_OWNER_ADDRESS = 0;
    uint256 internal constant BITS_NFT_CONFIGS_NFT_INDEX = 160;
    uint256 internal constant BITS_NFT_CONFIGS_EMODE = 192;
    uint256 internal constant BITS_NFT_CONFIGS_NUMBER_OF_POSITIONS = 204;
    uint256 internal constant BITS_NFT_CONFIGS_ISOLATED_COLLATERAL_FLAG = 214;
    uint256 internal constant BITS_NFT_CONFIGS_ISOLATED_COLLATERAL_TOKEN_INDEX = 215;

    /// @dev Token Configs
    uint256 internal constant BITS_TOKEN_CONFIGS_TOKEN_ADDRESS = 0;
    uint256 internal constant BITS_TOKEN_CONFIGS_TOKEN_DECIMALS = 160;
    uint256 internal constant BITS_TOKEN_CONFIGS_COLLATERAL_CLASS = 165;
    uint256 internal constant BITS_TOKEN_CONFIGS_DEBT_CLASS = 168;
    uint256 internal constant BITS_TOKEN_CONFIGS_COLLATERAL_FACTOR = 171;
    uint256 internal constant BITS_TOKEN_CONFIGS_LIQUIDATION_THRESHOLD = 181;
    uint256 internal constant BITS_TOKEN_CONFIGS_LIQUIDATION_PENALTY = 191;

    /// @dev Position Cap Configs
    /// FOR POSITION TYPE 1 & 2
    uint256 internal constant BITS_POSITION_CAP_CONFIGS_TYPE_1_AND_2_MAX_TOTAL_TOKEN_RAW_AMOUNT = 0;
    uint256 internal constant BITS_POSITION_CAP_CONFIGS_TYPE_1_AND_2_TOTAL_TOKEN_RAW_AMOUNT = 18;
    /// FOR POSITION TYPE 3 & 4
    uint256 internal constant BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_MIN_TICK_SIGN = 0;
    uint256 internal constant BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_ABSOLUTE_MIN_TICK = 1;
    uint256 internal constant BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_MAX_TICK_SIGN = 20;
    uint256 internal constant BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_ABSOLUTE_MAX_TICK = 21;
    uint256 internal constant BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_MAX_RAW_ADJUSTED_AMOUNT_0_CAP = 40;
    uint256 internal constant BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_CURRENT_MAX_RAW_ADJUSTED_AMOUNT_0 = 58;
    uint256 internal constant BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_MAX_RAW_ADJUSTED_AMOUNT_1_CAP = 122;
    uint256 internal constant BITS_POSITION_CAP_CONFIGS_TYPE_3_AND_4_CURRENT_MAX_RAW_ADJUSTED_AMOUNT_1 = 140;

    /// @dev Isolated Cap Configs
    uint256 internal constant BITS_ISOLATED_CAP_CONFIGS_MAX_TOTAL_TOKEN_RAW_BORROW = 0;
    uint256 internal constant BITS_ISOLATED_CAP_CONFIGS_TOTAL_TOKEN_RAW_BORROW = 18;

    /// @dev NFT Position Data
    uint256 internal constant BITS_POSITION_DATA_POSITION_TYPE = 0;
    /// POSITION TYPE 1 and 2
    uint256 internal constant BITS_POSITION_DATA_POSITION_TYPE_1_AND_2_TOKEN_INDEX = 5;
    uint256 internal constant BITS_POSITION_DATA_POSITION_TYPE_1_AND_2_TOKEN_RAW_AMOUNT = 17;
    /// POSITION TYPE 3 and 4
    //// DEX KEY
    uint256 internal constant BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_TOKEN_0_INDEX = 5;
    uint256 internal constant BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_TOKEN_1_INDEX = 17;
    uint256 internal constant BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_IS_DYNAMIC_FEE_POOL = 29;
    uint256 internal constant BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_FEE = 30;
    uint256 internal constant BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_TICK_SPACING = 47;
    uint256 internal constant BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_CONTROLLER_ADDRESS = 56;
    //// POSITION DATA
    uint256 internal constant BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_LOWER_TICK_SIGN = 216;
    uint256 internal constant BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_ABSOLUTE_LOWER_TICK = 217;
    uint256 internal constant BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_UPPER_TICK_SIGN = 236;
    uint256 internal constant BITS_POSITION_DATA_POSITION_TYPE_3_AND_4_ABSOLUTE_UPPER_TICK = 237;

    /// @dev Position Fee Stored
    uint256 internal constant BITS_POSITION_FEE_STORED_FEE_STORED_TOKEN_0 = 0;
    uint256 internal constant BITS_POSITION_FEE_STORED_FEE_STORED_TOKEN_1 = 128;

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