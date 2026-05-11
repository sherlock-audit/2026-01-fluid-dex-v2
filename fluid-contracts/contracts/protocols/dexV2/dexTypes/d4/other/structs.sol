// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "../../common/d3d4common/commonImport.sol";

struct CalculatedVars {
    uint256 token0NumeratorPrecision;
    uint256 token0DenominatorPrecision;
    uint256 token1NumeratorPrecision;
    uint256 token1DenominatorPrecision;
    uint256 token0BorrowExchangePrice;
    uint256 token1BorrowExchangePrice;
}

struct BorrowParams {
    DexKey dexKey;
    int24 tickLower;
    int24 tickUpper;
    bytes32 positionSalt; // NOTE: positionSalt for 2 positions can be same for different ranges or different owners, the overall id for a position is a combination of owner, tickLower, tickUpper & positionSalt
    uint256 amount0;
    uint256 amount1;
    uint256 amount0Min;
    uint256 amount1Min;
}

struct BorrowVariables {
    uint256 token0DebtAmountRawAdjusted;
    uint256 token1DebtAmountRawAdjusted;
    uint256 sqrtPriceLowerX96;
    uint256 sqrtPriceUpperX96;
    uint256 geometricMeanPriceX96;
    uint256 priceLowerX96;
    uint256 priceUpperX96;
    uint256 token0ReserveAmountRawAdjusted;
    uint256 token1ReserveAmountRawAdjusted;
    uint256 feeAccruedToken0Adjusted;
    uint256 feeAccruedToken1Adjusted;
    uint256 liquidityIncreaseRaw;
    uint256 amount0;
    uint256 amount1;
    uint256 feeAccruedToken0;
    uint256 feeAccruedToken1;
}

struct PaybackParams {
    DexKey dexKey;
    int24 tickLower;
    int24 tickUpper;
    bytes32 positionSalt; // NOTE: positionSalt for 2 positions can be same for different ranges or different owners, the overall id for a position is a combination of owner, tickLower, tickUpper & positionSalt
    uint256 amount0;
    uint256 amount1;
    uint256 amount0Min;
    uint256 amount1Min;
}

struct PaybackVariables {
    uint256 token0DebtAmountRawAdjusted;
    uint256 token1DebtAmountRawAdjusted;
    uint256 sqrtPriceLowerX96;
    uint256 sqrtPriceUpperX96;
    uint256 geometricMeanPriceX96;
    uint256 priceLowerX96;
    uint256 priceUpperX96;
    uint256 token0ReserveAmountRawAdjusted;
    uint256 token1ReserveAmountRawAdjusted;
    uint256 feeAccruedToken0Adjusted;
    uint256 feeAccruedToken1Adjusted;
    uint256 liquidityDecreaseRaw;
    uint256 amount0;
    uint256 amount1;
    uint256 feeAccruedToken0;
    uint256 feeAccruedToken1;
}
