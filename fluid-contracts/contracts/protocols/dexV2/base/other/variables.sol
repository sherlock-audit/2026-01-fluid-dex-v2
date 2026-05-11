// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./error.sol";

abstract contract ConstantVariables {
    /*//////////////////////////////////////////////////////////////
                          CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev EIP-1967 implementation storage slot
    /// This is bytes32(uint256(keccak256('eip1967.proxy.implementation')) - 1)
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// bytes32(uint256(keccak256("FLUID_DEX_V2_BASE")) - 1)
    bytes32 internal constant BASE_SLOT = 0x7336ba09d90d0a79967e434a915d72dfb7e2f59fd8575a830210387fd4c1ab7c;

    /// This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1
    /// The exact slot which stored the admin address in infinite proxy of liquidity contracts
    bytes32 internal constant LIQUIDITY_GOVERNANCE_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    address internal constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// To skip transfers in liquidity layer if token in & out is same and liquidity layer is on the winning side
    bytes32 internal constant SKIP_TRANSFERS = keccak256(bytes("SKIP_TRANSFERS"));
    /// @dev if this bytes32 is set in the calldata, then token transfers are only done for net input - output.
    bytes32 internal constant NET_TRANSFERS = keccak256(bytes("NET_TRANSFERS"));

    // protocol identifier for dexV2
    bytes32 internal constant DEXV2_IDENTIFIER = keccak256(bytes("DEXV2"));
    // action identifier for settle
    bytes32 internal constant SETTLE_ACTION_IDENTIFIER = keccak256(bytes("SETTLE"));
    // action identifier for rebalance
    bytes32 internal constant REBALANCE_ACTION_IDENTIFIER = keccak256(bytes("REBALANCE"));

    uint256 internal constant D3_SWAP_MODULE_IMPLEMENTATION_ID = 1;
    address internal constant D3_SWAP_MODULE_IMPLEMENTATION = 0x3D7Ebc40AF7092E3F1C81F2e996cbA5Cae2090d7; // TODO: Update before deployment

    uint256 internal constant D3_USER_MODULE_IMPLEMENTATION_ID = 2;
    address internal constant D3_USER_MODULE_IMPLEMENTATION = 0xD16d567549A2a2a2005aEACf7fB193851603dd70; // TODO: Update before deployment

    uint256 internal constant D3_CONTROLLER_MODULE_IMPLEMENTATION_ID = 3;
    address internal constant D3_CONTROLLER_MODULE_IMPLEMENTATION = 0x96d3F6c20EEd2697647F543fE6C08bC2Fbf39758; // TODO: Update before deployment

    uint256 internal constant D4_SWAP_MODULE_IMPLEMENTATION_ID = 1;
    address internal constant D4_SWAP_MODULE_IMPLEMENTATION = 0xDB25A7b768311dE128BBDa7B8426c3f9C74f3240; // TODO: Update before deployment

    uint256 internal constant D4_USER_MODULE_IMPLEMENTATION_ID = 2;
    address internal constant D4_USER_MODULE_IMPLEMENTATION = 0x3381cD18e2Fb4dB236BF0525938AB6E43Db0440f; // TODO: Update before deployment

    uint256 internal constant D4_CONTROLLER_MODULE_IMPLEMENTATION_ID = 3;
    address internal constant D4_CONTROLLER_MODULE_IMPLEMENTATION = 0x756e0562323ADcDA4430d6cb456d9151f605290B; // TODO: Update before deployment 
}

abstract contract ImmutableVariables is ConstantVariables {
    /*//////////////////////////////////////////////////////////////
                          IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @dev Address of liquidity contract
    IFluidLiquidity internal immutable LIQUIDITY;
}

abstract contract Variables is ImmutableVariables {
    /*//////////////////////////////////////////////////////////////
                          STORAGE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// Governance can add/remove auths
    /// Governance is auth by default
    /// base slot => address => is auth
    mapping(bytes32 => mapping(address => uint256)) internal _isAuth;

    /// base slot => dex type => admin implementation id => admin implementation address
    mapping(bytes32 => mapping(uint256 => mapping(uint256 => address))) internal _dexTypeToAdminImplementation;

    /// base slot => user => token => stored token amount
    /// @dev this is so the users can skip token transfers by keeping their assets in the dex itself
    mapping(bytes32 => mapping(address => mapping(address => uint256))) internal _userStoredTokenAmount;

    /// base slot => token => total amount added by auth
    /// @dev auth seeds the dex with some tokens so liquidity interactions can be skipped for smaller amounts
    mapping(bytes32 => mapping(address => uint256)) internal _totalAuthAddedAmount;

    /// base slot => token => unaccounted borrow amount
    /// @dev this is so liquidity interactions can be skipped and the record for borrow side is maintained in this variable
    mapping(bytes32 => mapping(address => int256)) internal _unaccountedBorrowAmount;
}
