// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { Structs } from "./structs.sol";

abstract contract Constants {
    int8 internal constant MAX_MULTIPLIER = 21; // a source rate with less than 6 decimals precision is not known to exist
    int8 internal constant MIN_MULTIPLIER = -12; // a source rate with more than 39 decimals precision is not known to exist

    uint256 internal constant ORACLE_PRECISION = 1e27;

    /// @dev address that is mapped to the chain native token at Liquidity
    address internal constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @dev Maximum allowed timespan for Chainlink oracles in operate() mode (25 hours)
    uint256 internal constant MAX_UPDATE_TIMESPAN_OPERATE = 25 hours;
    /// @dev Maximum allowed timespan for Chainlink oracles in liquidate() mode (10 days)
    uint256 internal constant MAX_UPDATE_TIMESPAN_LIQUIDATE = 10 days;

    /// This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1
    /// The exact slot which stored the admin address in infinite proxy of liquidity contracts
    bytes32 internal constant LIQUIDITY_GOVERNANCE_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    uint256 internal constant MM_SLOT_TOTAL_EMODES = 1; // Emodes stored in MM variables, slot 1
    uint256 internal constant MM_BITPOS_TOTAL_EMODES = 212; // from MM variables: Next 12  bits => 212 - 223 => Total Emodes listed
    uint256 internal constant MM_MASK_TOTAL_EMODES = 0xFFF; // 12 bits mask

    /// @notice Team multisig allowed to trigger certain config changes
    address public constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;

    /// @notice Address of the liquidity contract.
    address public immutable LIQUIDITY;

    /// @notice Address of the money market proxy contract.
    address public immutable MONEY_MARKET;
}

abstract contract Variables is Constants, Structs {
    // ----------------------- slot 0 ---------------------------

    /// @notice maps token => eMode => isOperate ((0 = liquidate, 1 = operate)) => isCollateral (0 = debt, 1 = collateral)
    mapping(address => mapping(uint256 => mapping(uint256 => mapping(uint256 => OracleConfig)))) public config;

    // ----------------------- slot 1 ---------------------------

    mapping(address => ConfigMap[]) public configsMap;

    // ----------------------- slot 2 ---------------------------

    // /// @dev guardians can pause/unpause oracles. todo?
    // /// guardians could pause all markets related to a certain token / oracle / col debt mode etc. at once
    // /// governance can add/remove guardians.
    // /// governance is guardian by default.
    // mapping(address => uint256) internal _guardians;
}
