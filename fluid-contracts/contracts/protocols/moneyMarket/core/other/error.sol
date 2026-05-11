// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./errorTypes.sol";

error FluidMoneyMarketError(uint256 errorId_);

/// @notice Error thrown when estimate mode is enabled to return liquidation estimate data
/// @param paybackData The encoded payback data containing amounts paid back by the liquidator
///        - For NORMAL_BORROW: abi.encode(uint256 paybackAmount)
///        - For D4: abi.encode(uint256 token0PaybackAmount, uint256 token1PaybackAmount)
/// @param withdrawData The encoded withdraw data containing amounts sent to the liquidator
///        - For NORMAL_SUPPLY: abi.encode(uint256 withdrawAmount)
///        - For D3/D4: abi.encode(uint256 token0WithdrawAmount, uint256 token1WithdrawAmount)
error FluidLiquidateEstimate(bytes paybackData, bytes withdrawData);