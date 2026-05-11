// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./structs.sol";

/// @notice Emitted when a position is liquidated
/// @param nftId The NFT ID of the liquidated position
/// @param liquidator The address that performed the liquidation
/// @param to The address that received the liquidated collateral
/// @param paybackValue The total value of debt paid back (in base currency with 18 decimals)
/// @param withdrawValue The total value of collateral withdrawn including penalties (in base currency with 18 decimals)
event LogLiquidate(
    uint256 indexed nftId,
    address indexed liquidator,
    address indexed to,
    uint256 paybackValue,
    uint256 withdrawValue
);
