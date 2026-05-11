// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import "../../common/d1d2common/commonImport.sol";
struct CalculatedVars {
    uint256 token0NumeratorPrecision;
    uint256 token0DenominatorPrecision;
    uint256 token1NumeratorPrecision;
    uint256 token1DenominatorPrecision;
    uint256 token0SupplyExchangePrice;
    uint256 token1SupplyExchangePrice;
    uint256 token0TotalSupplyRaw;
    uint256 token1TotalSupplyRaw;
    uint256 token0TotalSupplyAdjusted;
    uint256 token1TotalSupplyAdjusted;
}

struct CollateralReserves {
    uint token0RealReserves;
    uint token1RealReserves;
    uint token0ImaginaryReserves;
    uint token1ImaginaryReserves;
}

struct CollateralReservesSwap {
    uint tokenInRealReserves;
    uint tokenOutRealReserves;
    uint tokenInImaginaryReserves;
    uint tokenOutImaginaryReserves;
}

struct SwapInMemory {
    address tokenIn;
    address tokenOut;
    uint256 amtInAdjusted;
    uint256 amtOutAdjusted;
    uint256 amtIn; // after fee
    address withdrawTo;
    // address borrowTo;
    uint price; // price of pool after swap
    uint fee; // fee of pool
    uint revenueCut; // revenue cut of pool
    bool swap0to1;
    // int swapRoutingAmt;
    bytes data; // just added to avoid stack-too-deep error
}

struct SwapInVariables {
    bytes32 dexId;
    uint256 dexVariables;
    uint256 dexVariables2;
    CalculatedVars calculatedVars;
    SwapInMemory s;
    Prices prices;
    uint256 temp;
    CollateralReservesSwap cs;
    CollateralReserves c;
}

struct SwapOutMemory {
    address tokenIn;
    address tokenOut;
    uint256 amtOutAdjusted;
    uint256 amtInAdjusted;
    uint256 amtOut; // after fee
    address withdrawTo;
    // address borrowTo;
    uint price; // price of pool after swap
    uint fee;
    uint revenueCut; // revenue cut of pool
    bool swap0to1;
    // int swapRoutingAmt;
    bytes data; // just added to avoid stack-too-deep error
    uint msgValue;
}

struct SwapOutVariables {
    bytes32 dexId;
    uint256 dexVariables;
    uint256 dexVariables2;
    CalculatedVars calculatedVars;
    SwapOutMemory s;
    Prices prices;
    uint256 temp;
    CollateralReservesSwap cs;
    CollateralReserves c;
}

struct DepositColMemory {
    uint256 token0AmtAdjusted;
    uint256 token1AmtAdjusted;
    uint256 token0ReservesInitial;
    uint256 token1ReservesInitial;
}

struct DepositVariables {
    bytes32 dexId;
    uint256 dexVariables;
    uint256 dexVariables2;
    uint256 userSupplyData;
    uint256 temp;
    uint256 temp2;
    uint256 totalSupplyShares;
    CalculatedVars calculatedVars;
    Prices prices;
    DepositColMemory d;
    CollateralReserves c;
    CollateralReserves c2;
}

struct WithdrawColMemory {
    uint256 token0AmtAdjusted;
    uint256 token1AmtAdjusted;
    uint256 token0ReservesInitial;
    uint256 token1ReservesInitial;
}

struct WithdrawVariables {
    bytes32 dexId;
    uint256 dexVariables;
    uint256 dexVariables2;
    CalculatedVars calculatedVars;
    uint256 userSupplyData;
    WithdrawColMemory w;
    Prices prices;
    uint256 token0Reserves;
    uint256 token1Reserves;
    uint256 temp;
    uint256 temp2;
    uint256 totalSupplyShares;
    uint256 token0ImaginaryReservesOutsideRange;
    uint256 token1ImaginaryReservesOutsideRange;
}

struct DepositPerfectVariables {
    bytes32 dexId;
    uint256 dexVariables2;
    CalculatedVars calculatedVars;
    uint256 userSupplyData;
    uint256 totalSupplyShares;
    uint256 userSupply;
    uint256 newWithdrawalLimit;
}

struct WithdrawPerfectVariables {
    bytes32 dexId;
    uint256 dexVariables2;
    CalculatedVars calculatedVars;
    uint256 userSupplyData;
    uint256 totalSupplyShares;
    uint256 userSupply;
    uint256 newWithdrawalLimit;
}

struct WithdrawPerfectInOneTokenVariables {
    bytes32 dexId;
    uint256 dexVariables;
    uint256 dexVariables2;
    uint256 userSupplyData;
    uint256 totalSupplyShares;
    uint256 token0Amt;
    uint256 token1Amt;
    CollateralReserves c;
    CollateralReserves c2;
    uint256 userSupply;
    uint256 temp;
}
