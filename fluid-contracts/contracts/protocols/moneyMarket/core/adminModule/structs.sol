// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./interfaces.sol";

/// @notice Struct for token configuration in an emode
struct TokenConfig {
    address token;
    uint256 collateralClass;
    uint256 debtClass;
    uint256 collateralFactor;
    uint256 liquidationThreshold;
    uint256 liquidationPenalty;
}

/// @notice Struct to hold local variables for updateD3PositionCap and updateD4PositionCap
struct UpdatePositionCapVars {
    uint256 positionCapConfigs;
    uint256 currentMaxRawAdjustedAmount0;
    uint256 currentMaxRawAdjustedAmount1;
    uint256 exchangePrice0;
    uint256 exchangePrice1;
    uint256 token0Index;
    uint256 token1Index;
    uint256 token0Decimals;
    uint256 token1Decimals;
    uint256 token0NumeratorPrecision;
    uint256 token0DenominatorPrecision;
    uint256 token1NumeratorPrecision;
    uint256 token1DenominatorPrecision;
    uint256 maxRawAdjustedAmount0Cap;
    uint256 maxRawAdjustedAmount1Cap;
}