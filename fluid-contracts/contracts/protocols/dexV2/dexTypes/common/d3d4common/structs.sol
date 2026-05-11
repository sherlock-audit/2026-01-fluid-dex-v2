// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

struct DexKey {
    address token0;
    address token1;
    uint24 fee; // The fee here tells the fee if its a static fee pool or acts as a dynamic fee flag, i.e, type(uint24).max or 0xFFFFFF for dynamic fee pools.
    uint24 tickSpacing;
    address controller;
}

struct DexVariables {
    int256 currentTick;
    uint256 sqrtPriceX96;
    uint256 feeGrowthGlobal0X102;
    uint256 feeGrowthGlobal1X102;
}

struct TickData {
    int256 liquidityNet;
    uint256 feeGrowthOutside0X102;
    uint256 feeGrowthOutside1X102;
}

struct PositionData {
    uint256 liquidity;
    uint256 feeGrowthInside0X102;
    uint256 feeGrowthInside1X102;
}

struct DynamicFeeVariables {
    uint256 minFee;
    uint256 maxFee;
    uint256 priceImpactToFeeDivisionFactor;
    uint256 zeroPriceImpactPriceX96;
    uint256 minFeeKinkPriceX96;
    uint256 minFeeKinkSqrtPriceX96;
    uint256 maxFeeKinkPriceX96;
    uint256 maxFeeKinkSqrtPriceX96;
}

struct ComputeSwapStepForSwapInWithDynamicFeeParams {
    bool swap0To1;
    uint256 sqrtPriceCurrentX96;
    uint256 sqrtPriceTargetX96;
    uint256 liquidity;
    uint256 amountInRemaining;
    uint256 protocolFee;
    DynamicFeeVariables dynamicFeeVariables;
}

struct ComputeSwapStepForSwapOutWithDynamicFeeParams {
    bool swap0To1;
    uint256 sqrtPriceCurrentX96;
    uint256 sqrtPriceTargetX96;
    uint256 liquidity;
    uint256 amountOutRemaining;
    uint256 protocolFee;
    DynamicFeeVariables dynamicFeeVariables;
}

struct SwapInParams {
    DexKey dexKey;
    bool swap0To1;
    uint256 amountIn;
    uint256 amountOutMin;
    bytes controllerData;
}

struct SwapInInternalParams {
    DexKey dexKey;
    uint256 dexVariables;
    uint256 dexVariables2;
    bool swap0To1;
    uint256 amountInRaw;
    bytes controllerData;
    uint256 token0ExchangePrice; // NOTE: can be token0SupplyExchangePrice (for D3) or token0BorrowExchangePrice (for D4)
    uint256 token1ExchangePrice; // NOTE: can be token1SupplyExchangePrice (for D3) or token1BorrowExchangePrice (for D4)
    uint256 dexType;
    bytes32 dexId;
}

struct SwapInInternalVariables {
    uint256 dexVariablesStart;
    uint256 sqrtPriceStartX96;
    uint256 activeLiquidityStart;
    uint256 protocolFee;
    uint256 protocolCutFee;
    uint256 feeGrowthGlobal0X102;
    uint256 feeGrowthGlobal1X102;
    uint256 feeVersion;
    bool isConstantLpFee;
    uint256 constantLpFee;
    uint256 sqrtPriceStepStartX96;
    int256 nextTick;
    bool initialized;
    uint256 sqrtPriceNextX96;
    bool sqrtPriceStartX96Changed;
}

struct SwapOutParams {
    DexKey dexKey;
    bool swap0To1;
    uint256 amountOut;
    uint256 amountInMax;
    bytes controllerData;
}

struct SwapOutInternalParams {
    DexKey dexKey;
    uint256 dexVariables;
    uint256 dexVariables2;
    bool swap0To1;
    uint256 amountOutRaw;
    bytes controllerData;
    uint256 token0ExchangePrice; // NOTE: can be token0SupplyExchangePrice (for D3) or token0BorrowExchangePrice (for D4)
    uint256 token1ExchangePrice; // NOTE: can be token1SupplyExchangePrice (for D3) or token1BorrowExchangePrice (for D4)
    uint256 dexType;
    bytes32 dexId;
}

struct SwapOutInternalVariables {
    uint256 dexVariablesStart;
    uint256 sqrtPriceStartX96;
    uint256 activeLiquidityStart;
    uint256 protocolFee;
    uint256 protocolCutFee;
    uint256 feeGrowthGlobal0X102;
    uint256 feeGrowthGlobal1X102;
    uint256 feeVersion;
    bool isConstantLpFee;
    uint256 constantLpFee;
    uint256 sqrtPriceStepStartX96;
    int256 nextTick;
    bool initialized;
    uint256 sqrtPriceNextX96;
    bool sqrtPriceStartX96Changed;
}

struct AddLiquidityInternalParams {
    DexKey dexKey;
    DexVariables dexVariables;
    uint256 dexVariables2;
    int24 tickLower;
    int24 tickUpper;
    uint256 sqrtPriceLowerX96;
    uint256 sqrtPriceUpperX96;
    bytes32 positionSalt; // NOTE: positionSalt for 2 positions can be same for different ranges or different owners, the overall id for a position is a combination of owner, tickLower, tickUpper & positionSalt
    uint256 amount0DesiredRaw;
    uint256 amount1DesiredRaw;
    uint256 dexType;
    bytes32 dexId;
    bool isSmartCollateral;
}

struct AddLiquidityInternalVariables {
    bytes32 positionId;
    uint256 maxLiquidityPerTick;
    uint256 feeGrowthInside0X102;
    uint256 feeGrowthInside1X102;
    uint256 feeGrowthBelow0X102;
    uint256 feeGrowthBelow1X102;
    uint256 feeGrowthAbove0X102;
    uint256 feeGrowthAbove1X102;
}

struct RemoveLiquidityInternalParams {
    DexKey dexKey;
    DexVariables dexVariables;
    uint256 dexVariables2;
    int24 tickLower;
    int24 tickUpper;
    uint256 sqrtPriceLowerX96;
    uint256 sqrtPriceUpperX96;
    bytes32 positionSalt; // NOTE: positionSalt for 2 positions can be same for different ranges or different owners, the overall id for a position is a combination of owner, tickLower, tickUpper & positionSalt
    uint256 amount0DesiredRaw;
    uint256 amount1DesiredRaw;
    uint256 dexType;
    bytes32 dexId;
}

struct RemoveLiquidityInternalVariables {
    bytes32 positionId;
    uint256 feeGrowthInside0X102;
    uint256 feeGrowthInside1X102;
    uint256 feeGrowthBelow0X102;
    uint256 feeGrowthBelow1X102;
    uint256 feeGrowthAbove0X102;
    uint256 feeGrowthAbove1X102;
}

struct InitializeParams {
    DexKey dexKey;
    uint256 sqrtPriceX96;
}

struct InitializeInternalParams {
    DexKey dexKey;
    uint256 sqrtPriceX96;
    uint256 dexType;
}

struct InitializeVariables {
    bytes32 dexId;
    uint256 lpFee;
    int24 tick;
    uint256 token0Decimals;
    uint256 token1Decimals;
}
