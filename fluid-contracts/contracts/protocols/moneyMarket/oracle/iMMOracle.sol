//SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

// NOTE: 1 unit of base currency means 1e27
// Eg: If base currency is USD, then 1 USD of value means 1e27
interface IMMOracle {
    function getPrice(address token0_, uint256 emode_, bool isOperate_, bool isCollateral_) external returns (uint256 price_);
}
