// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import "../other/commonImport.sol";

/// @notice struct to set user borrow & payback config
struct UserBorrowConfig {
    ///
    /// @param user address
    address user;
    ///
    /// @param expandPercent debt limit expand percent. in 1e2: 100% = 10_000; 1% = 100
    /// Also used to calculate rate at which debt limit should decrease (instant).
    uint256 expandPercent;
    ///
    /// @param expandDuration debt limit expand duration in seconds.
    /// used to calculate rate together with expandPercent
    uint256 expandDuration;
    ///
    /// @param baseDebtCeiling base borrow limit. until here, borrow limit remains as baseDebtCeiling
    /// (user can borrow until this point at once without stepped expansion). Above this, automated limit comes in place.
    /// amount in raw (to be multiplied with exchange price) or normal depends on configured mode in user config for the token:
    /// with interest -> raw, without interest -> normal
    uint256 baseDebtCeiling;
    ///
    /// @param maxDebtCeiling max borrow ceiling, maximum amount the user can borrow.
    /// amount in raw (to be multiplied with exchange price) or normal depends on configured mode in user config for the token:
    /// with interest -> raw, without interest -> normal
    uint256 maxDebtCeiling;
}

struct LockInitialAmountVariables {
    uint256 token0NumeratorPrecision;
    uint256 token0DenominatorPrecision;
    uint256 token1NumeratorPrecision;
    uint256 token1DenominatorPrecision;
    uint token0AmtAdjusted;
    uint token1AmtAdjusted;
    uint token1Amt;
    address token;
    uint amt;
    uint totalBorrowShares;
}

struct InitializeParams {
    DexKey dexKey;
    uint token0DebtAmt;
    uint centerPrice;
    uint fee;
    uint revenueCut;
    uint upperPercent;
    uint lowerPercent;
    uint upperShiftThreshold;
    uint lowerShiftThreshold;
    uint thresholdShiftTime;
    uint centerPriceAddress;
    uint hookAddress;
    uint maxCenterPrice;
    uint minCenterPrice;
}

struct InitializeVariables {
    bytes32 dexId;
    uint dexVariables2;
    uint token0Decimals;
    uint token1Decimals;
}
