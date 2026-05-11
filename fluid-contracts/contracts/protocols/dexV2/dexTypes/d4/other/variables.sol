// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./structs.sol";

abstract contract ConstantVariables is CommonImportD3D4Common {
    uint256 internal constant Q192 = (1 << 192);
}

abstract contract ImmutableVariables is ConstantVariables {
    address internal immutable THIS_CONTRACT;
    IFluidLiquidity internal immutable LIQUIDITY;
}

abstract contract Variables is ImmutableVariables {}
