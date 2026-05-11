// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "../other/commonImport.sol";

struct FeeCollectionParams {
    uint256 nftId;
    bytes32 positionId;
    bytes32 dexV2PositionId;
    uint256 feeAccruedToken0;
    uint256 feeAccruedToken1;
    uint256 feeCollectionAmount0;
    uint256 feeCollectionAmount1;
    bool isOperate;
}
