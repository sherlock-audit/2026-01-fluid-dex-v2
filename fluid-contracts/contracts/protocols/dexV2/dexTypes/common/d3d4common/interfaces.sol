// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./structs.sol";

import { IFluidLiquidity } from "../../../../../liquidity/interfaces/iLiquidity.sol";
import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IERC20WithDecimals is IERC20 {
    function decimals() external view returns (uint8);
}

interface IController {
    function fetchDynamicFeeForSwapIn(SwapInInternalParams memory params_) external returns (uint256 fetchedDynamicFee_, bool overrideDynamicFee_);

    function fetchDynamicFeeForSwapOut(SwapOutInternalParams memory params_) external returns (uint256 fetchedDynamicFee_, bool overrideDynamicFee_);
}
