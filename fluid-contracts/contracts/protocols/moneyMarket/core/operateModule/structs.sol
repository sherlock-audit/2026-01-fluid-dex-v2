// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./interfaces.sol";

struct CreateD3D4PositionParams {
    uint256 token0Index;
    uint256 token1Index;
    uint24 tickSpacing;
    uint24 fee;
    address controller;
    int24 tickLower;
    int24 tickUpper;
    uint256 amount0;
    uint256 amount1;
    uint256 amount0Min;
    uint256 amount1Min;
    address to;
}

struct CreateD3D4PositionVariables {
    uint256 token0Configs;
    uint256 token1Configs;
    bool permissionlessTokens;
    uint256 isDynamicFeeFlag;
    bytes32 positionSalt;
}