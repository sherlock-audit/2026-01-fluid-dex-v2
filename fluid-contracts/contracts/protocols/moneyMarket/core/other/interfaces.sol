// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { IFluidLiquidity } from "../../../../liquidity/interfaces/iLiquidity.sol";
import { IFluidDexV2 } from "../../../dexV2/interfaces/iDexV2.sol";

// NOTE: 1 unit of base currency means 1e18
// Eg: If base currency is USD, then 1 USD of value means 1e18
interface IOracle {
    function getPrice(address token0_, uint256 emode_, bool isOperate_, bool isCollateral_) external returns (uint256 price_);
}
