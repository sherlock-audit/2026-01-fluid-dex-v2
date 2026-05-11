// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "../other/commonImport.sol";

import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @dev Interface for ERC-1822 UUPS compatibility check
interface IERC1822Proxiable {
    function proxiableUUID() external view returns (bytes32);
}

interface IERC20WithDecimals is IERC20 {
    function decimals() external view returns (uint8);
}