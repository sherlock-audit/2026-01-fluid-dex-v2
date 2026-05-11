// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import "./interfaces.sol";

/// @dev Emitted when fee and revenue cut are updated
/// @param fee The new fee value
/// @param revenueCut The new revenue cut value
event LogUpdateFeeAndRevenueCut(uint256 dexType, bytes32 dexId, uint fee, uint revenueCut);

/// @dev Emitted when range percents are updated
/// @param upperPercent The new upper percent value
/// @param lowerPercent The new lower percent value
/// @param shiftTime The new shift time value
event LogUpdateRangePercents(uint256 dexType, bytes32 dexId, uint upperPercent, uint lowerPercent, uint shiftTime);

/// @dev Emitted when threshold percent is updated
/// @param upperThresholdPercent The new upper threshold percent value
/// @param lowerThresholdPercent The new lower threshold percent value
/// @param thresholdShiftTime The new threshold shift time value
/// @param shiftTime The new shift time value
event LogUpdateThresholdPercent(
    uint256 dexType,
    bytes32 dexId,
    uint upperThresholdPercent,
    uint lowerThresholdPercent,
    uint thresholdShiftTime,
    uint shiftTime
);

/// @dev Emitted when center price address is updated
/// @param centerPriceAddress The new center price address nonce
/// @param percent The new percent value
/// @param time The new time value
event LogUpdateCenterPriceAddress(uint256 dexType, bytes32 dexId, uint centerPriceAddress, uint percent, uint time);

/// @dev Emitted when hook address is updated
/// @param hookAddress The new hook address nonce
event LogUpdateHookAddress(uint256 dexType, bytes32 dexId, uint hookAddress);

/// @dev Emitted when center price limits are updated
/// @param maxCenterPrice The new maximum center price
/// @param minCenterPrice The new minimum center price
event LogUpdateCenterPriceLimits(uint256 dexType, bytes32 dexId, uint maxCenterPrice, uint minCenterPrice);

/// @dev Emitted when utilization limit is updated
/// @param token0UtilizationLimit The new utilization limit for token0
/// @param token1UtilizationLimit The new utilization limit for token1
event LogUpdateUtilizationLimit(uint256 dexType, bytes32 dexId, uint token0UtilizationLimit, uint token1UtilizationLimit);

/// @dev Emitted when user borrow configs are updated
/// @param userBorrowConfigs The array of updated user borrow configurations
event LogUpdateUserBorrowConfigs(uint256 dexType, bytes32 dexId, UserBorrowConfig[] userBorrowConfigs);

/// @dev Emitted when a user is paused
/// @param user The address of the paused user
event LogPauseUser(uint256 dexType, bytes32 dexId, address user);

/// @dev Emitted when a user is unpaused
/// @param user The address of the unpaused user
event LogUnpauseUser(uint256 dexType, bytes32 dexId, address user);

/// @notice Emitted when the pool configuration is initialized
/// @param smartCol Whether smart collateral is enabled
/// @param smartDebt Whether smart debt is enabled
// /// @param token0ColAmt The amount of token0 collateral
/// @param token0DebtAmt The amount of token0 debt
/// @param fee The fee percentage (in 4 decimals, 10000 = 1%)
/// @param revenueCut The revenue cut percentage (in 4 decimals, 100000 = 10%)
/// @param centerPriceAddress The nonce for the center price contract address
/// @param hookAddress The nonce for the hook contract address
event LogInitializePoolConfig(
    uint256 dexType,
    bytes32 dexId,
    uint token0DebtAmt,
    uint fee,
    uint revenueCut,
    uint centerPriceAddress,
    uint hookAddress
);

/// @notice Emitted when the price parameters are initialized
/// @param upperPercent The upper range percent (in 4 decimals, 10000 = 1%)
/// @param lowerPercent The lower range percent (in 4 decimals, 10000 = 1%)
/// @param upperShiftThreshold The upper shift threshold (in 4 decimals, 10000 = 1%)
/// @param lowerShiftThreshold The lower shift threshold (in 4 decimals, 10000 = 1%)
/// @param thresholdShiftTime The time for threshold shift (in seconds)
/// @param maxCenterPrice The maximum center price
/// @param minCenterPrice The minimum center price
event LogInitializePriceParams(
    uint256 dexType,
    bytes32 dexId,
    uint upperPercent,
    uint lowerPercent,
    uint upperShiftThreshold,
    uint lowerShiftThreshold,
    uint thresholdShiftTime,
    uint maxCenterPrice,
    uint minCenterPrice
);

/// @notice emitted when user withdrawal limit is updated
event LogUpdateUserWithdrawalLimit(uint256 dexType, bytes32 dexId, address user, uint256 newLimit);

/// @notice emitted when swap is paused
event LogPauseSwap(uint256 dexType, bytes32 dexId);

/// @notice emitted when swap is unpaused
event LogUnpauseSwap(uint256 dexType, bytes32 dexId);

/// @dev Emitted when max borrow shares are updated
/// @param maxBorrowShares The new maximum borrow shares
event LogUpdateMaxBorrowShares(uint256 dexType, bytes32 dexId, uint maxBorrowShares);