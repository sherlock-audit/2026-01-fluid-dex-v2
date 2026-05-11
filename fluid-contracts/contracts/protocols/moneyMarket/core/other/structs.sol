// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./interfaces.sol";

import { DexKey } from "../../../dexV2/dexTypes/common/d3d4common/structs.sol";
import { DepositParams, WithdrawParams } from "../../../dexV2/dexTypes/d3/other/structs.sol";
import { BorrowParams, PaybackParams } from "../../../dexV2/dexTypes/d4/other/structs.sol";
import { PositionData } from "../../../dexV2/dexTypes/common/d3d4common/structs.sol";

struct StartOperationParams {
    bool isOperate;
    uint256 positionType; 
    uint256 nftId; 
    uint256 nftConfig; 
    uint256 token0Index;
    uint256 token1Index;
    uint256 positionIndex; 
    int24 tickLower; 
    int24 tickUpper; 
    bytes32 positionSalt; 
    uint256 emode;
    bool permissionlessTokens;
    bytes actionData;
}

struct GetDexV2FeeAccruedAmountsVariables {
    uint256 feeGrowthGlobal0X102;
    uint256 feeGrowthGlobal1X102;
    uint256 feeGrowthBelow0X102;
    uint256 feeGrowthBelow1X102;
    uint256 feeGrowthAbove0X102;
    uint256 feeGrowthAbove1X102;
}

struct GetD3D4AmountsParams {
    int24 tickLower;
    int24 tickUpper;
    bytes32 positionSalt;
    uint256 token0Decimals;
    uint256 token1Decimals;
    uint256 token0ExchangePrice;
    uint256 token1ExchangePrice;
    uint256 sqrtPriceX96;
}

struct HfInfo {
    uint256 hf;
    uint256 collateralValue;
    uint256 debtValue;
    uint256 normalizedCollateralValue;
    uint256 minNormalizedCollateralValue;
}

struct GetHfVariables {
    IOracle oracle;
    uint256 emode;
    uint256 numberOfPositions;
    uint256 normalizedCollateralValue;
    uint256 debtValue;
}

struct GetHfD3D4Variables {
    uint256 token0Configs;
    uint256 token1Configs;
    int24 tickLower;
    int24 tickUpper;
    bytes32 positionSalt;
    uint256 positionFeeStored;
    uint256 token0Price;
    uint256 token1Price;
}

/// @notice Parameters for the liquidate function
struct LiquidateParams {
    uint256 nftId;
    uint256 paybackPositionIndex;
    uint256 withdrawPositionIndex;
    address to;
    bool estimate;
    bytes paybackData;
}