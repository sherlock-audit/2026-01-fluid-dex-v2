// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./structs.sol";

/// @notice Emitted when the auth is updated
/// @param auth The auth address
/// @param isAuth The new auth status
event LogUpdateAuth(address indexed auth, bool indexed isAuth);

/// @notice emitted when the implementation is upgraded
event LogUpgraded(address indexed implementation);

/// @notice Emitted when the oracle address is updated
/// @param oldOracle The previous oracle address
/// @param newOracle The new oracle address
event OracleUpdated(address indexed oldOracle, address indexed newOracle);

/// @notice Emitted when max positions per NFT is updated
/// @param oldMaxPositions The previous max positions per NFT
/// @param newMaxPositions The new max positions per NFT
event MaxPositionsPerNFTUpdated(uint256 indexed oldMaxPositions, uint256 indexed newMaxPositions);

/// @notice Emitted when min normalized collateral value is updated
/// @param oldMinNormalizedCollateralValue The previous min normalized collateral value (in 18 decimals)
/// @param newMinNormalizedCollateralValue The new min normalized collateral value (in 18 decimals)
event MinNormalizedCollateralValueUpdated(uint256 indexed oldMinNormalizedCollateralValue, uint256 indexed newMinNormalizedCollateralValue);

/// @notice Emitted when HF limit for liquidation is updated
/// @param oldHfLimit The previous HF limit (in big number format)
/// @param newHfLimit The new HF limit (in big number format)
event HfLimitForLiquidationUpdated(uint256 indexed oldHfLimit, uint256 indexed newHfLimit);

/// @notice Emitted when a new token is listed
/// @param token The token address
/// @param tokenIndex The assigned token index
/// @param tokenDecimals The token decimals
/// @param collateralClass The collateral class
/// @param debtClass The debt class
/// @param collateralFactor The collateral factor
/// @param liquidationThreshold The liquidation threshold
/// @param liquidationPenalty The liquidation penalty
event TokenListed(
    address indexed token,
    uint256 indexed tokenIndex,
    uint256 tokenDecimals,
    uint256 collateralClass,
    uint256 debtClass,
    uint256 collateralFactor,
    uint256 liquidationThreshold,
    uint256 liquidationPenalty
);

/// @notice Emitted when a new emode is listed
/// @param emode The emode that was listed
/// @param tokenConfigsList Array of token configurations for this emode
/// @param debtTokens Array of token addresses that are allowed as debt in this emode
event EmodeListed(
    uint256 indexed emode,
    TokenConfig[] tokenConfigsList,
    address[] debtTokens
);

// /// @notice Emitted when a token config is added to an emode
// /// @param emode The emode
// /// @param token The token address
// /// @param tokenIndex The token index
// /// @param collateralClass The collateral class
// /// @param debtClass The debt class
// /// @param collateralFactor The collateral factor
// /// @param liquidationThreshold The liquidation threshold
// /// @param liquidationPenalty The liquidation penalty
// event TokenConfigAddedToEmode(
//     uint256 indexed emode,
//     address indexed token,
//     uint256 indexed tokenIndex,
//     uint256 collateralClass,
//     uint256 debtClass,
//     uint256 collateralFactor,
//     uint256 liquidationThreshold,
//     uint256 liquidationPenalty
// );

// /// @notice Emitted when a token config is removed from an emode
// /// @param emode The emode
// /// @param token The token address
// /// @param tokenIndex The token index
// event TokenConfigRemovedFromEmode(
//     uint256 indexed emode,
//     address indexed token,
//     uint256 indexed tokenIndex
// );

/// @notice Emitted when a debt token is added to an emode
/// @param emode The emode
/// @param token The token address
/// @param tokenIndex The token index
event DebtAddedToEmode(
    uint256 indexed emode,
    address indexed token,
    uint256 indexed tokenIndex
);

/// @notice Emitted when a debt token is removed from an emode
/// @param emode The emode
/// @param token The token address
/// @param tokenIndex The token index
event DebtRemovedFromEmode(
    uint256 indexed emode,
    address indexed token,
    uint256 indexed tokenIndex
);

/// @notice Emitted when collateral factor is updated for a token
/// @param emode The emode (0 for NO_EMODE)
/// @param token The token address
/// @param tokenIndex The token index
/// @param oldCollateralFactor The old collateral factor
/// @param newCollateralFactor The new collateral factor
event CollateralFactorUpdated(
    uint256 indexed emode,
    address indexed token,
    uint256 indexed tokenIndex,
    uint256 oldCollateralFactor,
    uint256 newCollateralFactor
);

/// @notice Emitted when liquidation penalty is updated for a token
/// @param emode The emode (0 for NO_EMODE)
/// @param token The token address
/// @param tokenIndex The token index
/// @param oldLiquidationPenalty The old liquidation penalty
/// @param newLiquidationPenalty The new liquidation penalty
event LiquidationPenaltyUpdated(
    uint256 indexed emode,
    address indexed token,
    uint256 indexed tokenIndex,
    uint256 oldLiquidationPenalty,
    uint256 newLiquidationPenalty
);

/// @notice Emitted when token supply cap is updated
/// @param token The token address
/// @param tokenIndex The token index
/// @param oldMaxSupplyCapRaw The old max supply cap (raw amount)
/// @param newMaxSupplyCapRaw The new max supply cap (raw amount)
event TokenSupplyCapUpdated(
    address indexed token,
    uint256 indexed tokenIndex,
    uint256 oldMaxSupplyCapRaw,
    uint256 newMaxSupplyCapRaw
);

/// @notice Emitted when token debt cap is updated
/// @param token The token address
/// @param tokenIndex The token index
/// @param oldMaxDebtCapRaw The old max debt cap (raw amount)
/// @param newMaxDebtCapRaw The new max debt cap (raw amount)
event TokenDebtCapUpdated(
    address indexed token,
    uint256 indexed tokenIndex,
    uint256 oldMaxDebtCapRaw,
    uint256 newMaxDebtCapRaw
);

/// @notice Emitted when D3 position cap is updated
/// @param dexKey The dex key
/// @param minTick The minimum tick
/// @param maxTick The maximum tick
/// @param maxRawAdjustedAmount0Cap The maximum raw adjusted token0 amount cap
/// @param maxRawAdjustedAmount1Cap The maximum raw adjusted token1 amount cap
event D3PositionCapUpdated(
    DexKey indexed dexKey,
    int24 minTick,
    int24 maxTick,
    uint256 maxRawAdjustedAmount0Cap,
    uint256 maxRawAdjustedAmount1Cap
);

/// @notice Emitted when D4 position cap is updated
/// @param dexKey The dex key
/// @param minTick The minimum tick
/// @param maxTick The maximum tick
/// @param maxRawAdjustedAmount0Cap The maximum raw adjusted token0 amount cap
/// @param maxRawAdjustedAmount1Cap The maximum raw adjusted token1 amount cap
event D4PositionCapUpdated(
    DexKey indexed dexKey,
    int24 minTick,
    int24 maxTick,
    uint256 maxRawAdjustedAmount0Cap,
    uint256 maxRawAdjustedAmount1Cap
);

/// @notice Emitted when isolated cap is updated
/// @param isolatedToken The isolated collateral token address
/// @param isolatedTokenIndex The isolated token index
/// @param debtToken The debt token address
/// @param debtTokenIndex The debt token index
/// @param newMaxDebtCapRaw The new max debt cap (raw amount)
event IsolatedCapUpdated(
    address indexed isolatedToken,
    uint256 isolatedTokenIndex,
    address indexed debtToken,
    uint256 debtTokenIndex,
    uint256 newMaxDebtCapRaw
);

/// @notice Emitted when default permissionless dex cap is updated for a D3 token pair
/// @param token0 The first token address
/// @param token1 The second token address
/// @param minTick The minimum tick
/// @param maxTick The maximum tick
/// @param maxRawAdjustedAmount0Cap The maximum raw adjusted token0 amount cap
/// @param maxRawAdjustedAmount1Cap The maximum raw adjusted token1 amount cap
event D3DefaultPermissionlessDexCapUpdated(
    address indexed token0,
    address indexed token1,
    int24 minTick,
    int24 maxTick,
    uint256 maxRawAdjustedAmount0Cap,
    uint256 maxRawAdjustedAmount1Cap
);

/// @notice Emitted when default permissionless dex cap is updated for a D4 token pair
/// @param token0 The first token address
/// @param token1 The second token address
/// @param minTick The minimum tick
/// @param maxTick The maximum tick
/// @param maxRawAdjustedAmount0Cap The maximum raw adjusted token0 amount cap
/// @param maxRawAdjustedAmount1Cap The maximum raw adjusted token1 amount cap
event D4DefaultPermissionlessDexCapUpdated(
    address indexed token0,
    address indexed token1,
    int24 minTick,
    int24 maxTick,
    uint256 maxRawAdjustedAmount0Cap,
    uint256 maxRawAdjustedAmount1Cap
);

/// @notice Emitted when global default permissionless dex cap is updated for D3
/// @param minTick The minimum tick
/// @param maxTick The maximum tick
/// @param maxRawAdjustedAmount0Cap The maximum raw adjusted token0 amount cap
/// @param maxRawAdjustedAmount1Cap The maximum raw adjusted token1 amount cap
event D3GlobalDefaultPermissionlessDexCapUpdated(
    int24 minTick,
    int24 maxTick,
    uint256 maxRawAdjustedAmount0Cap,
    uint256 maxRawAdjustedAmount1Cap
);

/// @notice Emitted when global default permissionless dex cap is updated for D4
/// @param minTick The minimum tick
/// @param maxTick The maximum tick
/// @param maxRawAdjustedAmount0Cap The maximum raw adjusted token0 amount cap
/// @param maxRawAdjustedAmount1Cap The maximum raw adjusted token1 amount cap
event D4GlobalDefaultPermissionlessDexCapUpdated(
    int24 minTick,
    int24 maxTick,
    uint256 maxRawAdjustedAmount0Cap,
    uint256 maxRawAdjustedAmount1Cap
);