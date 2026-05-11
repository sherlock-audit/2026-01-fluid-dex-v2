// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;
import "./constantVariables.sol";

// TODO
// import { IFluidDexFactory } from "../../interfaces/iDexFactory.sol";
// import { Error } from "../../error.sol";
// import { ErrorTypes } from "../../errorTypes.sol";

abstract contract CommonImmutableVariables is CommonConstantVariables {
    /*//////////////////////////////////////////////////////////////
                          CONSTANTS / IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    // TODO: Check all immutables again, we don't need many of them

    address internal immutable THIS_CONTRACT;

    /// @dev Address of liquidity contract
    IFluidLiquidity internal immutable LIQUIDITY;

    /// @dev Address of contract used for deploying center price & hook related contract
    address internal immutable DEPLOYER_CONTRACT;

    constructor(address liquidityAddress_, address deployerContract_) {
        THIS_CONTRACT = address(this);

        LIQUIDITY = IFluidLiquidity(liquidityAddress_);

        DEPLOYER_CONTRACT = deployerContract_;
    }
}
