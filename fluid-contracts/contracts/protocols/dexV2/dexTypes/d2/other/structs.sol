// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import "../../common/d1d2common/commonImport.sol";

struct CalculatedVars {
    uint256 token0NumeratorPrecision;
    uint256 token0DenominatorPrecision;
    uint256 token1NumeratorPrecision;
    uint256 token1DenominatorPrecision;
    uint256 token0BorrowExchangePrice;
    uint256 token1BorrowExchangePrice;
    uint256 token0TotalBorrowRaw;
    uint256 token1TotalBorrowRaw;
    uint256 token0TotalBorrowAdjusted;
    uint256 token1TotalBorrowAdjusted;
}

struct DebtReserves {
    uint token0Debt;
    uint token1Debt;
    uint token0RealReserves;
    uint token1RealReserves;
    uint token0ImaginaryReserves;
    uint token1ImaginaryReserves;
}

struct DebtReservesSwap {
    uint tokenInDebt;
    uint tokenOutDebt;
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
    // address withdrawTo;
    address borrowTo;
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
    DebtReservesSwap ds;
    DebtReserves d;
}

struct SwapOutMemory {
    address tokenIn;
    address tokenOut;
    uint256 amtOutAdjusted;
    uint256 amtInAdjusted;
    uint256 amtOut; // after fee
    // address withdrawTo;
    address borrowTo;
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
    DebtReservesSwap ds;
    DebtReserves d;
}

struct BorrowDebtMemory {
    uint256 token0AmtAdjusted;
    uint256 token1AmtAdjusted;
    uint256 token0DebtInitial;
    uint256 token1DebtInitial;
}

struct PaybackDebtMemory {
    uint256 token0AmtAdjusted;
    uint256 token1AmtAdjusted;
    uint256 token0DebtInitial;
    uint256 token1DebtInitial;
}
