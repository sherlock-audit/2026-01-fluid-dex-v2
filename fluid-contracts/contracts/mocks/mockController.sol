// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { SwapInInternalParams, SwapOutInternalParams, SwapInParams, SwapOutParams } from "../protocols/dexV2/dexTypes/common/d3d4common/structs.sol";
import { FluidDexV2D3SwapModule } from "../protocols/dexV2/dexTypes/d3/core/swapModule.sol";
import { FluidDexV2D4SwapModule } from "../protocols/dexV2/dexTypes/d4/core/swapModule.sol";
import { FluidDexV2 } from "../protocols/dexV2/base/core/main.sol";
import "forge-std/Test.sol";

contract MockController is Test {
    uint256 public SWAP_MODULE_ID = 1;

    function _swapIn(
        uint256 dexType_,
        SwapInParams memory swapInParams_
    ) internal returns (uint256 amountOut_, uint256 protocolFeeCharged_, uint256 lpFeeCharged_) {
        bytes memory operateData_;
        if (dexType_ == 3) {
            operateData_ = abi.encodeWithSelector(FluidDexV2D3SwapModule.swapIn.selector, swapInParams_);
        } else if (dexType_ == 4) {
            operateData_ = abi.encodeWithSelector(FluidDexV2D4SwapModule.swapIn.selector, swapInParams_);
        } else revert();

        // This should revert due to reentrancy protection
        bytes memory returnData_ = FluidDexV2(payable(msg.sender)).operate(dexType_, SWAP_MODULE_ID, operateData_);

        (amountOut_, protocolFeeCharged_, lpFeeCharged_) = abi.decode(returnData_, (uint256, uint256, uint256));
    }

    function _swapOut(
        uint256 dexType_,
        SwapOutParams memory swapOutParams_
    ) internal returns (uint256 amountIn_, uint256 protocolFeeCharged_, uint256 lpFeeCharged_) {
        bytes memory operateData_;
        if (dexType_ == 3) {
            operateData_ = abi.encodeWithSelector(FluidDexV2D3SwapModule.swapOut.selector, swapOutParams_);
        } else if (dexType_ == 4) {
            operateData_ = abi.encodeWithSelector(FluidDexV2D4SwapModule.swapOut.selector, swapOutParams_);
        } else revert();

        // This should revert due to reentrancy protection
        bytes memory returnData_ = FluidDexV2(payable(msg.sender)).operate(dexType_, SWAP_MODULE_ID, operateData_);

        (amountIn_, protocolFeeCharged_, lpFeeCharged_) = abi.decode(returnData_, (uint256, uint256, uint256));
    }

    function fetchDynamicFeeForSwapIn(SwapInInternalParams memory params_) external returns (uint256 fetchedDynamicFee_, bool overrideDynamicFee_) {
        bool tryReentrancy_;
        (tryReentrancy_, fetchedDynamicFee_, overrideDynamicFee_) = abi.decode(params_.controllerData, (bool, uint256, bool));

        if (tryReentrancy_) {
            _swapIn(params_.dexType, SwapInParams({
                dexKey: params_.dexKey,
                swap0To1: true,
                amountIn: 1e9,
                amountOutMin: 0,
                controllerData: "0x"
            }));
        }
    }

    function fetchDynamicFeeForSwapOut(SwapOutInternalParams memory params_) external returns (uint256 fetchedDynamicFee_, bool overrideDynamicFee_) {
        bool tryReentrancy_;
        (tryReentrancy_, fetchedDynamicFee_, overrideDynamicFee_) = abi.decode(params_.controllerData, (bool, uint256, bool));

        if (tryReentrancy_) {
            _swapOut(params_.dexType, SwapOutParams({
                dexKey: params_.dexKey,
                swap0To1: true,
                amountOut: 1e9,
                amountInMax: type(uint256).max,
                controllerData: "0x"
            }));
        }
    }
}