// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./interfaces.sol";

/***********************************|
|          Admin Module Events      | 
|__________________________________*/

/// @notice emitted when an auth is updated
event LogUpdateAuth(address indexed auth, bool indexed isAuth);

/// @notice emitted when the implementation is upgraded
event LogUpgraded(address indexed implementation);

/// @notice emitted when a dex type to admin implementation mapping is updated
event LogUpdateDexTypeToAdminImplementation(
    uint256 indexed dexType,
    uint256 indexed adminImplementationId,
    address indexed adminImplementation
);

/// @notice emitted when tokens are added or removed by admin
event LogAddOrRemoveTokens(address indexed token, int256 amount);

/// @notice emitted when rebalance is called for a token
event LogRebalance(
    address indexed token,
    int256 supplyAmount,
    int256 borrowAmount
);

/***********************************|
|           Main Module Events      | 
|__________________________________*/

/// @notice emitted when operate is called on a dex implementation
event LogOperate(
    address user,
    uint256 dexType,
    uint256 implementationId
);

/// @notice emitted when operateAdmin is called
event LogOperateAdmin(
    address indexed user,
    uint256 indexed dexType,
    uint256 indexed implementationId
);

/// @notice emitted when settle is called
event LogSettle(
    address user,
    address token,
    int256 supplyAmount,
    int256 borrowAmount,
    int256 storeAmount,
    address to
);