// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "../other/commonImport.sol";

interface IExternalCallForMint {
    function mint() external returns (uint256 nftId_);
}