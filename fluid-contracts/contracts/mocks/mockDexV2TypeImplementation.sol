// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;
import { PendingTransfers } from "../libraries/pendingTransfers.sol";

contract ImplementationEssentials {
    address public immutable LIQUIDITY_ADDR;
    uint256 public immutable DEX_TYPE;

    constructor(uint256 dexType_, address liquidityContract_) {
        LIQUIDITY_ADDR = liquidityContract_;
        DEX_TYPE = dexType_;
    }

    function getDexTypeAndLiquidityAddr() external view returns (uint256, address) {
        return (DEX_TYPE, LIQUIDITY_ADDR);
    }
}

contract MockDexV2TypeImplementation is ImplementationEssentials {
    constructor(uint256 dexType_, address liquidityContract_) ImplementationEssentials(dexType_, liquidityContract_) {}

    function operate(
        address supplyToken_,
        int256 supplyAmount_,
        address borrowToken_,
        int256 borrowAmount_
    ) external {
        PendingTransfers.addPendingSupply(msg.sender, supplyToken_, supplyAmount_);
        PendingTransfers.addPendingBorrow(msg.sender, borrowToken_, borrowAmount_);
    }
}
