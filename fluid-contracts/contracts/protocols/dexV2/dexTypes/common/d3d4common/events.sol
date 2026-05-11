// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./interfaces.sol";

/***********************************|
|        User Module Events         | 
|__________________________________*/

/// @notice emitted when a dex pool is initialized
event LogInitialize(
    uint256 indexed dexType,
    bytes32 indexed dexId,
    DexKey dexKey,
    uint256 sqrtPriceX96
);

/// @notice emitted when liquidity is deposited (D3)
event LogDeposit(
    uint256 indexed dexType,
    bytes32 indexed dexId,
    address indexed user,
    int24 tickLower,
    int24 tickUpper,
    bytes32 positionSalt,
    uint256 amount0,
    uint256 amount1,
    uint256 feeAccruedToken0,
    uint256 feeAccruedToken1,
    uint256 liquidityIncreaseRaw
);

/// @notice emitted when liquidity is withdrawn (D3)
event LogWithdraw(
    uint256 indexed dexType,
    bytes32 indexed dexId,
    address indexed user,
    int24 tickLower,
    int24 tickUpper,
    bytes32 positionSalt,
    uint256 amount0,
    uint256 amount1,
    uint256 feeAccruedToken0,
    uint256 feeAccruedToken1,
    uint256 liquidityDecreaseRaw
);

/// @notice emitted when liquidity is borrowed (D4)
event LogBorrow(
    uint256 indexed dexType,
    bytes32 indexed dexId,
    address indexed user,
    int24 tickLower,
    int24 tickUpper,
    bytes32 positionSalt,
    uint256 amount0,
    uint256 amount1,
    uint256 feeAccruedToken0,
    uint256 feeAccruedToken1,
    uint256 liquidityIncreaseRaw
);

/// @notice emitted when liquidity is paid back (D4)
event LogPayback(
    uint256 indexed dexType,
    bytes32 indexed dexId,
    address indexed user,
    int24 tickLower,
    int24 tickUpper,
    bytes32 positionSalt,
    uint256 amount0,
    uint256 amount1,
    uint256 feeAccruedToken0,
    uint256 feeAccruedToken1,
    uint256 liquidityDecreaseRaw
);

/***********************************|
|        Swap Module Events         | 
|__________________________________*/

/// @notice emitted when a swapIn is executed
event LogSwapIn(
    uint256 dexType,
    bytes32 dexId,
    address user,
    bool is0to1,
    uint256 amountIn,
    uint256 amountOut,
    uint256 protocolFee,
    uint256 lpFee
);

/// @notice emitted when a swapOut is executed
event LogSwapOut(
    uint256 dexType,
    bytes32 dexId,
    address user,
    bool is0to1,
    uint256 amountIn,
    uint256 amountOut,
    uint256 protocolFee,
    uint256 lpFee
);

/***********************************|
|      Admin Module Events          | 
|__________________________________*/

/// @notice emitted when protocol fee is updated
event LogUpdateProtocolFee(
    uint256 indexed dexType,
    bytes32 indexed dexId,
    uint256 protocolFee
);

/// @notice emitted when protocol cut fee is updated
event LogUpdateProtocolCutFee(
    uint256 indexed dexType,
    bytes32 indexed dexId,
    uint256 protocolCutFee
);

/// @notice emitted when per pool accounting is stopped
event LogStopPerPoolAccounting(
    uint256 indexed dexType,
    bytes32 indexed dexId
);

/// @notice emitted when user whitelist is updated
event LogUpdateUserWhitelist(
    uint256 indexed dexType,
    address indexed user,
    bool indexed isWhitelisted
);

/***********************************|
|    Controller Module Events       | 
|__________________________________*/

/// @notice emitted when fetch dynamic fee flag is updated
event LogUpdateFetchDynamicFeeFlag(
    uint256 indexed dexType,
    bytes32 indexed dexId,
    bool indexed flag
);

/// @notice emitted when fee version is updated to 0 or it was already 0 and some changes were made
event LogUpdateFeeVersion0(
    uint256 indexed dexType,
    bytes32 indexed dexId,
    uint256 lpFee
);

/// @notice emitted when fee version is updated to 1 or it was already 1 and some changes were made
event LogUpdateFeeVersion1(
    uint256 indexed dexType,
    bytes32 indexed dexId,
    uint256 maxDecayTime,
    uint256 priceImpactToFeeDivisionFactor,
    uint256 minFee,
    uint256 maxFee
);
