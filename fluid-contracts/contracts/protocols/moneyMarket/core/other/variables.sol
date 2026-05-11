// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./error.sol";

abstract contract ConstantVariables {
    // NFT Metadata
    string internal constant NFT_NAME = "Fluid Money Market";

    string internal constant NFT_SYMBOL = "fMM";

    /// @dev EIP-1967 implementation storage slot
    /// This is bytes32(uint256(keccak256('eip1967.proxy.implementation')) - 1)
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1
    /// The exact slot which stored the admin address in infinite proxy of liquidity contracts
    bytes32 internal constant LIQUIDITY_GOVERNANCE_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /// @dev Address of MoneyMarket Admin module implementation
    address internal constant ADMIN_MODULE_IMPLEMENTATION = 0xe8dc788818033232EF9772CB2e6622F1Ec8bc840; // TODO: Change to actual addresses before deployment

    /// @dev Address of MoneyMarket Callbacks module implementation
    address internal constant CALLBACK_MODULE_IMPLEMENTATION = 0x796f2974e3C1af763252512dd6d521E9E984726C; // TODO: Change to actual addresses before deployment

    /// @dev Address of MoneyMarket Operate module implementation
    address internal constant OPERATE_MODULE_IMPLEMENTATION = 0x3Cff5E7eBecb676c3Cb602D0ef2d46710b88854E; // TODO: Change to actual addresses before deployment

    /// @dev Address of MoneyMarket Liquidate module implementation
    address internal constant LIQUIDATE_MODULE_IMPLEMENTATION = 0x27cc01A4676C73fe8b6d0933Ac991BfF1D77C4da; // TODO: Change to actual addresses before deployment

    // protocol identifier for money market
    bytes32 internal constant MONEY_MARKET_IDENTIFIER = keccak256(bytes("MONEY_MARKET"));

    // action identifier for create normal supply position
    bytes32 internal constant CREATE_NORMAL_SUPPLY_POSITION_ACTION_IDENTIFIER = keccak256(bytes("CREATE_NORMAL_SUPPLY_POSITION"));
    // action identifier for create normal borrow position
    bytes32 internal constant CREATE_NORMAL_BORROW_POSITION_ACTION_IDENTIFIER = keccak256(bytes("CREATE_NORMAL_BORROW_POSITION"));
    // action identifier for normal supply
    bytes32 internal constant NORMAL_SUPPLY_ACTION_IDENTIFIER = keccak256(bytes("NORMAL_SUPPLY"));
    // action identifier for normal borrow
    bytes32 internal constant NORMAL_BORROW_ACTION_IDENTIFIER = keccak256(bytes("NORMAL_BORROW"));
    // action identifier for normal withdraw
    bytes32 internal constant NORMAL_WITHDRAW_ACTION_IDENTIFIER = keccak256(bytes("NORMAL_WITHDRAW"));
    // action identifier for normal payback
    bytes32 internal constant NORMAL_PAYBACK_ACTION_IDENTIFIER = keccak256(bytes("NORMAL_PAYBACK"));
    // action identifier for liquidate normal payback
    bytes32 internal constant LIQUIDATE_NORMAL_PAYBACK_ACTION_IDENTIFIER = keccak256(bytes("LIQUIDATE_NORMAL_PAYBACK"));
    // action identifier for liquidate normal withdraw
    bytes32 internal constant LIQUIDATE_NORMAL_WITHDRAW_ACTION_IDENTIFIER = keccak256(bytes("LIQUIDATE_NORMAL_WITHDRAW"));

    uint256 internal constant THREE_DECIMALS = 1e3;
    uint256 internal constant FOUR_DECIMALS = 1e4;
    uint256 internal constant SIX_DECIMALS = 1e6;
    uint256 internal constant NINE_DECIMALS = 1e9;
    uint256 internal constant TEN_DECIMALS = 1e10;
    uint256 internal constant EIGHTEEN_DECIMALS = 1e18;

    uint256 internal constant ROUNDING_FACTOR = NINE_DECIMALS;
    uint256 internal constant ROUNDING_FACTOR_PLUS_ONE = ROUNDING_FACTOR + 1;
    uint256 internal constant ROUNDING_FACTOR_MINUS_ONE = ROUNDING_FACTOR - 1;

    uint256 internal constant SMALL_COEFFICIENT_SIZE = 10;
    uint256 internal constant DEFAULT_COEFFICIENT_SIZE = 56;
    uint256 internal constant DEFAULT_EXPONENT_SIZE = 8;
    uint256 internal constant DEFAULT_EXPONENT_MASK = 0xFF;

    uint256 internal constant Q96 = 1 << 96;
    uint256 internal constant Q102 = 1 << 102;
    uint256 internal constant Q192 = 1 << 192;

    address internal constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 internal constant NATIVE_TOKEN_DECIMALS = 18;

    // Same as dex v2
    uint24 internal constant TOKENS_DECIMALS_PRECISION = 9;
    uint8 internal constant MIN_TOKEN_DECIMALS = 6;
    uint8 internal constant MAX_TOKEN_DECIMALS = 18;

    uint256 internal constant X1 = 0x1;
    uint256 internal constant X3 = 0x7;
    uint256 internal constant X5 = 0x1F;
    uint256 internal constant X9 = 0x1FF;
    uint256 internal constant X10 = 0x3FF;
    uint256 internal constant X12 = 0xFFF;
    uint256 internal constant X13 = 0x1FFF;
    uint256 internal constant X17 = 0x1FFFF;
    uint256 internal constant X18 = 0x3FFFF;
    uint256 internal constant X19 = 0x7FFFF;
    uint256 internal constant X32 = 0xFFFFFFFF;
    uint256 internal constant X64 = 0xFFFFFFFFFFFFFFFF;
    uint256 internal constant X72 = 0xFFFFFFFFFFFFFFFFFF;
    uint256 internal constant X82 = 0x3FFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant X128 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant X160 = 0x00FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    uint24 internal constant DYNAMIC_FEE_FLAG = type(uint24).max; // 0xFFFFFF
    int24 internal constant MIN_TICK = -524287; // NOTE: Uniswap uses -887272
    int24 internal constant MAX_TICK = -MIN_TICK;

    uint24 internal constant MAX_TICK_SPACING = 500;

    bytes4 internal constant DEX_V2_DEPOSIT_SELECTOR =
        bytes4(keccak256("deposit(((address,address,uint24,uint24,address),int24,int24,bytes32,uint256,uint256,uint256,uint256))"));
    bytes4 internal constant DEX_V2_WITHDRAW_SELECTOR =
        bytes4(keccak256("withdraw(((address,address,uint24,uint24,address),int24,int24,bytes32,uint256,uint256,uint256,uint256))"));
    bytes4 internal constant DEX_V2_BORROW_SELECTOR =
        bytes4(keccak256("borrow(((address,address,uint24,uint24,address),int24,int24,bytes32,uint256,uint256,uint256,uint256))"));
    bytes4 internal constant DEX_V2_PAYBACK_SELECTOR =
        bytes4(keccak256("payback(((address,address,uint24,uint24,address),int24,int24,bytes32,uint256,uint256,uint256,uint256))"));

    uint256 internal constant NO_NFT_DATA = 0;
    uint256 internal constant NO_EMODE = 0;

    bool internal constant ROUND_UP = true;
    bool internal constant ROUND_DOWN = false;

    bool internal constant IS_CALLBACK = true;

    bool internal constant IS_OPERATE = true;
    bool internal constant IS_LIQUIDATE = false;

    bool internal constant IS_COLLATERAL = true;
    bool internal constant IS_DEBT = false;

    bool internal constant POSITION_DELETED = true;
    bool internal constant POSITION_NOT_DELETED = false;

    uint256 internal constant AT_POOL_PRICE = 0;

    uint256 internal constant NORMAL_SUPPLY_POSITION_TYPE = 1;
    uint256 internal constant NORMAL_BORROW_POSITION_TYPE = 2;
    uint256 internal constant D3_POSITION_TYPE = 3;
    uint256 internal constant D4_POSITION_TYPE = 4;

    uint256 internal constant D3_DEX_TYPE = 3;
    uint256 internal constant D4_DEX_TYPE = 4;

    uint256 internal constant D3_USER_MODULE_IMPLEMENTATION_ID = 2;
    uint256 internal constant D4_USER_MODULE_IMPLEMENTATION_ID = 2;

    uint256 internal constant COLLATERAL_CLASS_NOT_ENABLED = 0;
    uint256 internal constant COLLATERAL_CLASS_PERMISSIONED = 1;
    uint256 internal constant COLLATERAL_CLASS_PERMISSIONLESS = 2;
    uint256 internal constant COLLATERAL_CLASS_ISOLATED = 3;

    uint256 internal constant DEBT_CLASS_NOT_ENABLED = 0;
    uint256 internal constant DEBT_CLASS_PERMISSIONED = 1;
    uint256 internal constant DEBT_CLASS_PERMISSIONLESS = 2;
}

abstract contract ImmutableVariables is ConstantVariables {
    /*//////////////////////////////////////////////////////////////
                          IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @dev Address of liquidity contract
    IFluidLiquidity internal immutable LIQUIDITY;

    /// @dev Address of DexV2 contract
    IFluidDexV2 internal immutable DEX_V2;
}

abstract contract TransientVariables is ImmutableVariables {
    /// @dev Transient storage for tracking from address during dex/liquidity callbacks
    /// @dev Automatically cleared at the end of the transaction (EIP-1153)
    address internal transient _msgSender;

    /// @dev Transient storage for tracking the eth value sent by caller for operate or liquidate
    /// @dev Automatically cleared at the end of the transaction (EIP-1153)
    uint256 internal transient _msgValue;
}

abstract contract StorageVariables is TransientVariables {
    /// Governance & Auths can add/remove Auths
    /// Governance is auth by default
    /// address => is auth
    mapping(address => uint256) internal _isAuth;

    // First 160 bits => 0   - 159 => Oracle Address
    // Next  10  bits => 160 - 169 => Max Positions per NFT
    // Next  12  bits => 170 - 181 => Min Normalized Collateral Value (in 18 decimals) (If this is 1000, then it means 1000 * 1e18 of normalized collateral value is required to borrow)
    // Next  18  bits => 182 - 199 => HF Limit for liquidation (10|8 big number) (in 18 decimals)
    // Next  12  bits => 200 - 211 => Total Number of tokens listed
    // Next  12  bits => 212 - 223 => Total Emodes listed
    // Next  32  bits => 224 - 255 => Total NFTs minted
    uint256 internal _moneyMarketVariables;

    /// NFT ID => NFT Configs
    // First 160 bits => 0   - 159 => NFT owner address
    // Next  32  bits => 160 - 191 => NFT Index (In the _nftOwnerConfig mapping)
    // Next  12  bits => 192 - 203 => Emode
    // Next  10  bits => 204 - 213 => Number of Positions in this NFT
    // Next  1   bit  => 214       => Isolated Collateral Flag
    // Next  12  bits => 215 - 226 => Isolated Collateral Token Index
    // Last 29 bits left empty
    mapping(uint256 => uint256) internal _nftConfigs;

    // owner => slot => index
    /*
    // slot 0: 
    // uint32 0 - 31: uint32:: balanceOf
    // uint224 32 - 255: 7 tokenIds each of uint32 packed
    // slot N (N >= 1)
    // uint32 * 8 each tokenId
    */
    mapping(address => mapping(uint256 => uint256)) internal _nftOwnerConfig;

    /// @notice tracks if a NFT id is approved for a certain address
    mapping(uint256 => address) internal _nftApproved;

    /// @notice tracks if all the NFTs of an owner are approved for a certain other address
    mapping(address => mapping(address => bool)) internal _nftApprovedForAll;

    /// emode => token index => configs
    // First 160 bits => 0   - 159 => token address
    // Next  5   bits => 160 - 164 => token decimals
    // Next  3   bits => 165 - 167 => collateral class (0 => not enabled, 1 => permissioned, 2 => permissionless, 3 => isolated) (Max 8 classes)
    // Next  3   bits => 168 - 170 => debt class (0 => not enabled, 1 => permissioned, 2 => permissionless) (Max 8 classes)
    // Next  10  bits => 171 - 180 => collateral factor. 800 = 0.8 = 80% (max precision of 0.1%)
    // Next  10  bits => 181 - 190 => liquidation Threshold. 900 = 0.9 = 90% (max precision of 0.1%)
    // Next  10  bits => 191 - 200 => liquidation penalty. 100 = 0.1 = 10%. (max precision of 0.1%)
    // Last 55 bits left empty
    mapping(uint256 => mapping(uint256 => uint256)) internal _tokenConfigs;

    // position id => position cap configs
    /// @dev this mapping is maintained for capping of all types of positions in some way
    // Position hash will be generated based on different types of positions
    // Position config data will be stored based on that type of position
    /// FOR POSITION TYPE 1 & 2
    // Position id will be the hash of (position type, token index)
    // The position cap configs uint256 will look like:
    // Next  18 bits => 0   - 17  => Max Total Token Raw Amount (Supply/Borrow) (10|8 big number)
    // Next  64 bits => 18  - 81  => Total Token Raw Amount (Supply/Borrow) (56|8 big number)
    // Last 173 bits left empty

    /// FOR POSITION TYPE 3 & 4
    // Position id will be the hash of (position type, dex key)
    // First 1  bit  => 0         => min tick sign
    // Next  19 bits => 1   - 19  => absolute min tick
    // Next  1  bit  => 20        => max tick sign
    // Next  19 bits => 21  - 39  => absolute max tick
    // Next  18 bits => 40  - 57  => max raw adjusted amount 0 cap (10|8 big number)
    // Next  64 bits => 58  - 121 => current max raw adjusted amount 0 (56|8 big number)
    // Next  18 bits => 122 - 139 => max raw adjusted amount 1 cap (10|8 big number)
    // Next  64 bits => 140 - 203 => current max raw adjusted amount 1 (56|8 big number)
    // Last 52 bits left empty
    mapping(bytes32 => uint256) internal _positionCapConfigs;

    /// NOTE: If both tokens are permissionless and _positionCapConfigs are not set for this dex, then we'll fallback to using the default permissionless dex cap configs
    /// dex type => token0 address => token1 address => default permissionless dex cap configs
    /// FOR POSITION TYPE 3 & 4
    // First 1  bit  => 0         => min tick sign
    // Next  19 bits => 1   - 19  => absolute min tick
    // Next  1  bit  => 20        => max tick sign
    // Next  19 bits => 21  - 39  => absolute max tick
    // Next  18 bits => 40  - 57  => max raw adjusted amount 0 cap (10|8 big number)
    // Next  64 bits => 58  - 121 => empty so this variable can be directly copied in _positionCapConfigs
    // Next  18 bits => 122 - 139 => max raw adjusted amount 1 cap (10|8 big number)
    // Next  64 bits => 140 - 203 => empty so this variable can be directly copied in _positionCapConfigs
    // Last 52 bits left empty
    mapping(uint256 => mapping(address => mapping (address => uint256))) internal _defaultPermissionlessDexCapConfigs;

    /// NOTE: If both tokens are permissionless and _positionCapConfigs and _defaultPermissionlessDexCapConfigs are not set for this dex, then we'll fallback to using the global default permissionless dex cap configs
    /// dex type => global default permissionless dex cap configs
    /// FOR POSITION TYPE 3 & 4
    // First 1  bit  => 0         => min tick sign
    // Next  19 bits => 1   - 19  => absolute min tick
    // Next  1  bit  => 20        => max tick sign
    // Next  19 bits => 21  - 39  => absolute max tick
    // Next  18 bits => 40  - 57  => max raw adjusted amount 0 cap (10|8 big number)
    // Next  64 bits => 58  - 121 => empty so this variable can be directly copied in _positionCapConfigs
    // Next  18 bits => 122 - 139 => max raw adjusted amount 1 cap (10|8 big number)
    // Next  64 bits => 140 - 203 => empty so this variable can be directly copied in _positionCapConfigs
    // Last 52 bits left empty
    mapping(uint256 => uint256) internal _globalDefaultPermissionlessDexCapConfigs;

    // isolated token index => debt token index => isolated cap configs
    // If there is an isolated collateral, then the flag in the nftConfigs mapping will be ON, and then we'll check:
    // 1. All position type 2 (single token debt positions) should have less debt than the caps
    // 2. No positions of type 4 (smart debt) are allowed
    // First 18 bits => 0  - 17 => Max Total Token Raw Borrow (10|8 big number)
    // Next  64 bits => 18 - 81 => Total Token Raw Borrow with this isolated collateral (56|8 big number)
    // Last 174 bits left empty
    mapping(uint256 => mapping(uint256 => uint256)) internal _isolatedCapConfigs;

    /// emode => parent => config
    /// Emode Map include data about 128 tokens (2 bits each)
    /// 0th bit => if 1 then when token index 1's config changes for this emode, else it doesn't
    /// 1st bit => if 1 then token index 1 is allowed as debt for this emode, else its not
    /// 2nd bit => if 1 then when token index 2's config changes for this emode, else it doesn't
    /// 3rd bit => if 1 then token index 2 is allowed as debt for this emode, else its not
    /// and so on...
    mapping(uint256 => mapping(uint256 => uint256)) internal _emodeMap;

    /// NFT ID => Position Index => Position Data
    // First 5   bits => 0   - 4   => Position Type

    /// Position Type 1 & 2 (Normal single token collateral or debt)
    // Next  12  bits => 5   - 16  => Token Index
    // Next  64  bits => 17  - 80  => Token Raw Amount (Supply/Borrow) (56|8 big number)
    // Last  175 bits left empty

    /// Position Type 3 & 4 (D3 & D4)
    //// DEX KEY
    // Next  12  bits => 5   - 16  => Token 0 Index
    // Next  12  bits => 17  - 28  => Token 1 Index
    // Next  1   bit  => 29        => Is Dynamic Fee Pool
    // Next  17  bits => 30  - 46  => Fee
    // Next  9   bits => 47  - 55  => Tick Spacing (max tick spacing in d3 and d4 can be 500)
    // Next  160 bits => 56  - 215 => Controller Address
    //// POSITION DATA
    // Next  1   bit  => 216       => Lower Tick Sign
    // Next  19  bits => 217 - 235 => Absolute Lower Tick
    // Next  1   bit  => 236       => Upper Tick Sign
    // Next  19  bits => 237 - 255 => Absolute Upper Tick
    mapping(uint256 => mapping(uint256 => uint256)) internal _positionData;

    // NFT ID => Position ID => Dex V2 Position ID => Fee Stored Data
    // First 128 bits => 0   - 127 => Fee Stored Token 0
    // Next  128 bits => 128 - 255 => Fee Stored Token 1
    mapping(uint256 => mapping(bytes32 => mapping(bytes32 => uint256))) internal _positionFeeStored;

    /// NOTE: The following variables are only for backend use and are not used during any user interactions

    /// @dev token address => token index
    mapping(address => uint256) internal _tokenIndex;

    /// @dev list of permissioned d3 dexes
    DexKey[] internal _d3PermissionedDexesList;

    /// @dev list of permissioned d4 dexes
    DexKey[] internal _d4PermissionedDexesList;

    /// @dev mapping of isolated token to whitelisted debt tokens
    mapping(address => address[]) internal _isolatedTokenToWhitelistedDebtTokens;
}

abstract contract Variables is StorageVariables {}