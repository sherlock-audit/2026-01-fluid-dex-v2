// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import "./structs.sol";
import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IERC20WithDecimals is IERC20 {
    function decimals() external view returns (uint8);
}
