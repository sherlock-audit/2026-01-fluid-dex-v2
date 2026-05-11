// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./structs.sol";

/// @notice Emitted when a user operates on a position (create, supply, borrow, withdraw, payback, etc.)
/// @param nftId The NFT ID of the position
/// @param positionIndex The index of the position within the NFT
/// @param operator The address that performed the operation
/// @param actionData The encoded action data containing operation details
event LogOperate(
    uint256 indexed nftId,
    uint256 indexed positionIndex,
    address indexed operator,
    bytes actionData
);

