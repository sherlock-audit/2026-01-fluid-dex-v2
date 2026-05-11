// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { IFluidLiquidity } from "../../../../liquidity/interfaces/iLiquidity.sol";

/// @dev Interface for ERC-1822 UUPS compatibility check
interface IERC1822Proxiable {
    function proxiableUUID() external view returns (bytes32);
}

interface IDexV2Implementation {
    function getDexTypeAndLiquidityAddr() external view returns (uint256, address);
}

interface IDexV2Callbacks {
    function startOperationCallback(bytes calldata data_) external returns (bytes memory);

    function dexCallback(address token_, address to_, uint256 amount_) external;
}