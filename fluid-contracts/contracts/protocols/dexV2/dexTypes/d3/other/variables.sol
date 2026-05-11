// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./structs.sol";

abstract contract ImmutableVariables is CommonImportD3D4Common {
    address internal immutable THIS_CONTRACT;
    IFluidLiquidity internal immutable LIQUIDITY;
}

abstract contract Variables is ImmutableVariables {}
