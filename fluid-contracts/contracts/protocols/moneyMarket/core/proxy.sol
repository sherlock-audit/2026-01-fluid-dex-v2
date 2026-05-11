// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title    FluidMoneyMarketProxy
/// @notice   Default ERC1967Proxy for Fluid Money Market
contract FluidMoneyMarketProxy is ERC1967Proxy {
    constructor(address logic_, bytes memory data_) payable ERC1967Proxy(logic_, data_) {}
}