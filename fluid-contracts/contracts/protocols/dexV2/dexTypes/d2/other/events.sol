// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import "./structs.sol";

/// @notice Emitted on token swaps
/// @param swap0to1 Indicates whether the swap is from token0 to token1 or vice-versa.
/// @param amountIn The amount of tokens to be sent to the vault to swap.
/// @param amountOut The amount of tokens user got from the swap.
/// @param to Recepient of swapped tokens.
event Swap(bool swap0to1, uint256 amountIn, uint256 amountOut, address to);

/// @notice Emitted when liquidity is borrowed with shares specified.
/// @param shares shares minted
/// @param token0Amt Amount of token0 borrowed.
/// @param token1Amt Amount of token1 borrowed.
event LogBorrowPerfectDebtLiquidity(uint shares, uint token0Amt, uint token1Amt);

/// @notice Emitted when liquidity is paid back with shares specified.
/// @param shares shares burned
/// @param token0Amt Amount of token0 paid back.
/// @param token1Amt Amount of token1 paid back.
event LogPaybackPerfectDebtLiquidity(uint shares, uint token0Amt, uint token1Amt);

/// @notice Emitted when liquidity is borrowed with specified token0 & token1 amount
/// @param amount0 Amount of token0 borrowed.
/// @param amount1 Amount of token1 borrowed.
/// @param shares Amount of shares minted.
event LogBorrowDebtLiquidity(uint amount0, uint amount1, uint shares);

/// @notice Emitted when liquidity is paid back with specified token0 & token1 amount
/// @param amount0 Amount of token0 paid back.
/// @param amount1 Amount of token1 paid back.
/// @param shares Amount of shares burned.
event LogPaybackDebtLiquidity(uint amount0, uint amount1, uint shares);

/// @notice Emitted when liquidity is paid back with shares specified from one token only.
/// @param shares shares burned
/// @param token0Amt Amount of token0 paid back.
/// @param token1Amt Amount of token1 paid back.
event LogPaybackDebtInOneToken(uint shares, uint token0Amt, uint token1Amt);
