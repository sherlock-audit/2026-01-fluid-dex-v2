// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import "./structs.sol";

/// @notice Emitted when a position is liquidated
/// @param nftId The NFT ID of the liquidated position
/// @param liquidator The address that performed the liquidation
/// @param paybackPositionIndex The index of the debt position paid back
/// @param withdrawPositionIndex The index of the collateral position withdrawn
/// @param to The address that received the liquidated collateral
/// @param paybackData Encoded payback amounts (NORMAL_BORROW: uint256 amount; D4: uint256 amount0, uint256 amount1)
/// @param withdrawData Encoded withdraw amounts (NORMAL_SUPPLY: uint256 amount; D3/D4: uint256 amount0, uint256 amount1)
event LogLiquidate(
    uint256 indexed nftId,
    address indexed liquidator,
    uint256 paybackPositionIndex,
    uint256 withdrawPositionIndex,
    address to,
    bytes paybackData,
    bytes withdrawData
);
