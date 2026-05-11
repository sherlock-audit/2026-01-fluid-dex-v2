// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./error.sol";

abstract contract CommonConstantVariables {
    uint256 internal constant DEX_TYPE_DIVISOR = 10_000;

    address internal constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 internal constant NATIVE_TOKEN_DECIMALS = 18;

    uint24 internal constant TOKENS_DECIMALS_PRECISION = 9;
    uint8 internal constant MIN_TOKEN_DECIMALS = 6;
    uint8 internal constant MAX_TOKEN_DECIMALS = 18;

    uint256 internal constant SMALL_COEFFICIENT_SIZE = 64;
    uint256 internal constant BIG_COEFFICIENT_SIZE = 74;
    
    uint256 internal constant DEFAULT_EXPONENT_SIZE = 8;
    uint256 internal constant DEFAULT_EXPONENT_MASK = 0xFF;

    bool internal constant ROUND_DOWN = false;
    bool internal constant ROUND_UP = true;

    bool internal constant IS_0_TO_1_SWAP = true;

    uint256 internal constant X1 = 0x1;
    uint256 internal constant X4 = 0xF;
    uint256 internal constant X6 = 0x3F;
    uint256 internal constant X8 = 0xFF;
    uint256 internal constant X12 = 0xFFF;
    uint256 internal constant X15 = 0x7FFF;
    uint256 internal constant X16 = 0xFFFF;
    uint256 internal constant X19 = 0x7FFFF;
    uint256 internal constant X20 = 0xFFFFF;
    uint256 internal constant X21 = 0x1FFFFF;
    uint256 internal constant X53 = 0x1FFFFFFFFFFFFF;
    uint256 internal constant X58 = 0x3FFFFFFFFFFFFFF;
    uint256 internal constant X72 = 0xFFFFFFFFFFFFFFFFFF;
    uint256 internal constant X82 = 0x3FFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant X86 = 0x3FFFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant X91 = 0x7FFFFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant X96 = 0xFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant X102 = 0x3FFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant X104 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant X128 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant X160 = 0x00FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    uint256 internal constant Q96 = 1 << 96;
    uint256 internal constant Q102 = 1 << 102;

    uint256 internal constant TWO_DECIMALS = 1e2;
    uint256 internal constant FOUR_DECIMALS = 1e4;
    uint256 internal constant SIX_DECIMALS = 1e6;
    uint256 internal constant NINE_DECIMALS = 1e9;
    uint256 internal constant TEN_DECIMALS = 1e10;

    uint256 internal constant ROUNDING_FACTOR = NINE_DECIMALS;
    uint256 internal constant ROUNDING_FACTOR_PLUS_ONE = ROUNDING_FACTOR + 1;
    uint256 internal constant ROUNDING_FACTOR_MINUS_ONE = ROUNDING_FACTOR - 1;

    int24 internal constant MIN_TICK = -524287; // NOTE: Uniswap uses -887272
    int24 internal constant MAX_TICK = -MIN_TICK;

    uint160 internal constant MIN_SQRT_PRICE_X96 = 327115581591561469; // getSqrtRatioAtTick(MIN_TICK)
    uint160 internal constant MAX_SQRT_PRICE_X96 = 19189247130466284822469633870301185392758; // getSqrtRatioAtTick(MAX_TICK)

    uint256 internal constant MIN_PRICE_X96 = 1350587; // FM.mulDiv(MIN_SQRT_PRICE_X96, MIN_SQRT_PRICE_X96, 1 << 96);
    uint256 internal constant MAX_PRICE_X96 = 4647680745692069522618647333321942173198062861119228; // FM.mulDiv(MAX_SQRT_PRICE_X96, MAX_SQRT_PRICE_X96, 1 << 96);

    uint24 internal constant MIN_TICK_SPACING = 1;
    uint24 internal constant MAX_TICK_SPACING = 500;

    uint24 internal constant DYNAMIC_FEE_FLAG = type(uint24).max; // 0xFFFFFF

    uint24 internal constant MAX_TICK_RANGE = 8000;

    uint256 internal constant MAX_LIQUIDITY = X102;

    uint256 internal constant MAX_SQRT_PRICE_CHANGE_PERCENTAGE = 2_000_000_000; // 20% (This is in 10 decimals) // 20% change in sqrt price means max 44% price change on the upside, and 36% change on the downside
    uint256 internal constant MIN_SQRT_PRICE_CHANGE_PERCENTAGE = 5; // 0.00000005% (This is in 10 decimals) // 0.00000005% change in sqrt price means min about 0.0000001% price change on both sides

    bool internal constant IS_SMART_COLLATERAL = true;
    bool internal constant IS_SMART_DEBT = false;
}