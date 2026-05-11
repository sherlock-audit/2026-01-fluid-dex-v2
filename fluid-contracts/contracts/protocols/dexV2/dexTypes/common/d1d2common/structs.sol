// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import "./interfaces.sol";

struct DexKey {
    address token0;
    address token1;
}

struct Prices {
    uint lastStoredPrice; // last stored price in 1e27 decimals
    uint centerPrice; // last stored price in 1e27 decimals
    uint upperRange; // price at upper range in 1e27 decimals
    uint lowerRange; // price at lower range in 1e27 decimals
    uint geometricMean; // geometric mean of upper range & lower range in 1e27 decimals
}

// TODO: Added this here for compilation, need to remove later because this has been removed from dexV2 base
struct TotalAmounts {
    address token;
    int256 totalSupplyWithInterest;
    int256 totalSupplyWithoutInterest;
    int256 totalBorrowWithInterest;
    int256 totalBorrowWithoutInterest;
}
