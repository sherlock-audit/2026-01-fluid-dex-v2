// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import "../other/commonImport.sol";

/// @notice struct to set user supply & withdrawal config
struct UserSupplyConfig {
    ///
    /// @param user address
    address user;
    ///
    /// @param expandPercent withdrawal limit expand percent. in 1e2: 100% = 10_000; 1% = 100
    /// Also used to calculate rate at which withdrawal limit should decrease (instant).
    uint256 expandPercent;
    ///
    /// @param expandDuration withdrawal limit expand duration in seconds.
    /// used to calculate rate together with expandPercent
    uint256 expandDuration;
    ///
    /// @param baseWithdrawalLimit base limit, below this, user can withdraw the entire amount.
    /// amount in raw (to be multiplied with exchange price) or normal depends on configured mode in user config for the token:
    /// with interest -> raw, without interest -> normal
    uint256 baseWithdrawalLimit;
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
    uint totalSupplyShares;
}

struct InitializeParams {
    DexKey dexKey;
    uint token0ColAmt;
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
