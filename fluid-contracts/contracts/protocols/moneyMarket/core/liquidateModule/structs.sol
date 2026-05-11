// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "../other/commonImport.sol";

struct LiquidateVariables {
    uint256 moneyMarketVariables;
    IOracle oracle;
    uint256 maxLiquidationPenalty;
    uint256 nftConfig;
    uint256 emode;
    uint256 numberOfPositions;
    uint256 paybackPositionData;
    uint256 paybackPositionType;
    bool positionDeleted;
    uint256 paybackValue;
    uint256 withdrawPositionData;
    uint256 withdrawPositionType;
    uint256 withdrawValue;
}

struct LiquidateNormalWithdrawVariables {
    uint256 tokenIndex;
    address token;
    uint256 tokenPrice;
    uint256 rawSupplyAmount;
    uint256 withdrawAmount;
    uint256 withdrawAmountRaw;
}

struct LiquidateD3WithdrawVariables {
    uint256 token0Decimals;
    uint256 token1Decimals;
    uint256 token0LiquidationPenalty;
    uint256 token1LiquidationPenalty;
    uint256 token0SupplyAmount;
    uint256 token1SupplyAmount;
    uint256 feeAmountToken0;
    uint256 feeAmountToken1;
    uint256 token0Price;
    uint256 token1Price;
    uint256 withdrawAmount0;
    uint256 withdrawAmount1;
}

struct LiquidateD4WithdrawVariables {
    uint256 token0Decimals;
    uint256 token1Decimals;
    uint256 token0LiquidationPenalty;
    uint256 token1LiquidationPenalty;
}