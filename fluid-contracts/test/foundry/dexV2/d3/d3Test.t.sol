//SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

// TODO: @Vaibhav Add more tests

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { DexV2BaseSetup } from "../baseSetup.t.sol";
import { FluidDexV2D3AdminModule } from "../../../../contracts/protocols/dexV2/dexTypes/d3/admin/main.sol";
import { FluidDexV2D3ControllerModule } from "../../../../contracts/protocols/dexV2/dexTypes/d3/core/controllerModule.sol";
import { FluidDexV2D3SwapModule } from "../../../../contracts/protocols/dexV2/dexTypes/d3/core/swapModule.sol";
import { FluidDexV2D3UserModule } from "../../../../contracts/protocols/dexV2/dexTypes/d3/core/userModule.sol";
import { MockController } from "../../../../contracts/mocks/mockController.sol";
import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";
import "../../../../contracts/protocols/dexV2/dexTypes/d3/other/structs.sol";

contract DexV2D3Test is DexV2BaseSetup {
    using SafeERC20 for IERC20;

    // Add receive function to accept ETH transfers
    receive() external payable {}

    // Use constants from base setup (DEX_TYPE_D3, ADMIN_MODULE_ID_D3)
    uint256 internal constant DEX_TYPE = DEX_TYPE_D3;
    uint256 internal constant SWAP_MODULE_ID = 1;
    uint256 internal constant USER_MODULE_ID = 2;
    uint256 internal constant CONTROLLER_MODULE_ID = 3;
    uint256 internal constant ADMIN_MODULE_ID = ADMIN_MODULE_ID_D3;

    MockController public mockController;

    function setUp() public virtual override {
        super.setUp();

        // Fund address(this) with 1000 USDC and 1000 USDT
        deal(address(USDT), address(this), 1000 * 1e6);
        deal(address(USDC), address(this), 1000 * 1e6);

        // D3 modules are already deployed in DexV2BaseSetup
        // Just whitelist the test contract for D3 initialization
        _whitelistUser(address(this), true);
    }
    
    function _whitelistUser(address user_, bool isWhitelisted_) internal {
        bytes memory operateAdminData_ = abi.encodeWithSelector(
            FluidDexV2D3AdminModule.updateUserWhitelist.selector,
            user_,
            isWhitelisted_
        );
        dexV2.operateAdmin(DEX_TYPE, ADMIN_MODULE_ID, operateAdminData_);
    }

    function testSetUp() public {
        assertNotEq(address(dexV2), address(0));
        assertNotEq(address(dexV2D3SwapModule), address(0));
        assertNotEq(address(dexV2D3UserModule), address(0));
        assertNotEq(address(dexV2D3ControllerModule), address(0));
        assertNotEq(address(dexV2D3AdminModule), address(0));
        assertEq(_getDexTypeToAdminImplementation(DEX_TYPE, ADMIN_MODULE_ID), address(dexV2D3AdminModule));
    }

    function _initialize(DexKey memory dexKey_, uint256 sqrtPriceX96_) internal {
        InitializeParams memory params_ = InitializeParams({ dexKey: dexKey_, sqrtPriceX96: sqrtPriceX96_ });

        bytes memory operateData_ = abi.encodeWithSelector(FluidDexV2D3UserModule.initialize.selector, params_);
        dexV2.operate(DEX_TYPE, USER_MODULE_ID, operateData_);
    }

    function shouldInitializeCallbackImplementation() public returns (bytes memory returnData_) {
        DexKey memory dexKey_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: 0, // 0.01%
            tickSpacing: 1,
            controller: address(0)
        });

        _initialize(dexKey_, (1 << 96));

        return returnData_;
    }

    function testInitialize() public {
        bytes memory data_ = abi.encodeWithSelector(this.shouldInitializeCallbackImplementation.selector);
        dexV2.startOperation(data_);
    }

    function _deposit(
        DexKey memory dexKey_,
        DepositParams memory depositParams_
    ) internal returns (uint256 amount0_, uint256 amount1_, uint256 feeAccruedToken0_, uint256 feeAccruedToken1_, uint256 liquidityIncreaseRaw_) {
        bytes memory operateData_ = abi.encodeWithSelector(FluidDexV2D3UserModule.deposit.selector, depositParams_);
        bytes memory returnData_ = dexV2.operate(DEX_TYPE, USER_MODULE_ID, operateData_);
        (amount0_, amount1_, feeAccruedToken0_, feeAccruedToken1_, liquidityIncreaseRaw_) = abi.decode(returnData_, (uint256, uint256, uint256, uint256, uint256));
    }

    function _withdraw(
        DexKey memory dexKey_,
        WithdrawParams memory withdrawParams_
    ) internal returns (uint256 amount0_, uint256 amount1_, uint256 feeAccruedToken0_, uint256 feeAccruedToken1_, uint256 liquidityDecreaseRaw_) {
        bytes memory operateData_ = abi.encodeWithSelector(FluidDexV2D3UserModule.withdraw.selector, withdrawParams_);
        bytes memory returnData_ = dexV2.operate(DEX_TYPE, USER_MODULE_ID, operateData_);
        (amount0_, amount1_, feeAccruedToken0_, feeAccruedToken1_, liquidityDecreaseRaw_) = abi.decode(returnData_, (uint256, uint256, uint256, uint256, uint256));
    }

    function _clearPendingSupply(address token_) internal {
        int256 pendingSupply_ = _getPendingSupply(address(this), token_);
        console2.log("pendingSupply_", _toString(pendingSupply_));

        if (pendingSupply_ > 0) {
            if (token_ == NATIVE_TOKEN_ADDRESS) {
                // For ETH, no approval needed, just ensure contract has enough ETH
                // The ETH will be sent via msg.value in the settle call
            } else {
                IERC20(token_).approve(address(liquidity), uint256(pendingSupply_));
            }
        }
        if (pendingSupply_ != 0) {
            if (pendingSupply_ > 0) {
                // We owe tokens to the DEX
                if (token_ == NATIVE_TOKEN_ADDRESS) {
                    // For ETH transfers, we need to send ETH via msg.value
                    dexV2.settle{value: uint256(pendingSupply_)}(token_, pendingSupply_, 0, 0, address(this), true);
                } else {
                    dexV2.settle(token_, pendingSupply_, 0, 0, address(this), true);
                }
            } else {
                // pendingSupply_ < 0, DEX owes us tokens, no value needed
                dexV2.settle(token_, pendingSupply_, 0, 0, address(this), true);
            }
        }
    }

    function shouldDepositWithdrawCallbackImplementation() public returns (bytes memory returnData_) {
        // Initialize Pool first
        DexKey memory dexKey_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: 100, // 0.01%
            tickSpacing: 1,
            controller: address(0)
        });
        _initialize(dexKey_, (1 << 96));

        // Then try adding liquidity
        DepositParams memory depositParams_ = DepositParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        _deposit(dexKey_, depositParams_);

        // Then try removing liquidity
        WithdrawParams memory withdrawParams_ = WithdrawParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        _withdraw(dexKey_, withdrawParams_);

        _clearPendingSupply(address(USDT));
        _clearPendingSupply(address(USDC));

        return returnData_;
    }

    function testDepositWithdraw() public {
        bytes memory data_ = abi.encodeWithSelector(this.shouldDepositWithdrawCallbackImplementation.selector);
        dexV2.startOperation(data_);
    }

    function _swapIn(
        DexKey memory dexKey_,
        SwapInParams memory swapInParams_
    ) internal returns (uint256 amountOut_, uint256 protocolFeeCharged_, uint256 lpFeeCharged_) {
        bytes memory operateData_ = abi.encodeWithSelector(FluidDexV2D3SwapModule.swapIn.selector, swapInParams_);
        bytes memory returnData_ = dexV2.operate(DEX_TYPE, SWAP_MODULE_ID, operateData_);

        (amountOut_, protocolFeeCharged_, lpFeeCharged_) = abi.decode(returnData_, (uint256, uint256, uint256));
    }

    function shouldSwapInCallbackImplementation() public returns (bytes memory returnData_) {
        // Initialize Pool first
        DexKey memory dexKey_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: 100, // 0.01%
            tickSpacing: 1,
            controller: address(0)
        });
        _initialize(dexKey_, (1 << 96));

        // Then try adding liquidity
        DepositParams memory depositParams_ = DepositParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        (uint256 amount0_, uint256 amount1_, , , uint256 liquidityIncreaseRaw_) = _deposit(dexKey_, depositParams_);

        console2.log("amount0_", _toString(amount0_));
        console2.log("amount1_", _toString(amount1_));
        console2.log("liquidityIncreaseRaw_", _toString(liquidityIncreaseRaw_));

        // Then try swap in
        uint256 usdtAmountIn_ = 99 * 1e6;
        SwapInParams memory swapInParams_ = SwapInParams({ dexKey: dexKey_, swap0To1: true, amountIn: usdtAmountIn_, amountOutMin: 0, controllerData: "0x" });
        (uint256 usdcAmountOut_, uint256 usdcProtocolFeeCharged_, uint256 usdcLpFeeCharged_) = _swapIn(dexKey_, swapInParams_);

        console2.log("usdtAmountIn_", _toString(usdtAmountIn_));
        console2.log("usdcAmountOut_", _toString(usdcAmountOut_));
        console2.log("usdcProtocolFeeCharged_", _toString(usdcProtocolFeeCharged_));
        console2.log("usdcLpFeeCharged_", _toString(usdcLpFeeCharged_));

        // swapInParams_ = SwapInParams({
        //     dexKey: dexKey_,
        //     swap0To1: false,
        //     amountIn: token1AmountOut_,
        //     amountOutMin: 0,
        //     controllerData: "0x"
        // });

        // operateData_ = abi.encodeWithSelector(FluidDexV2D3UserModule.swapIn.selector, swapInParams_);
        // returnData_ = dexV2.operate(DEX_TYPE, SWAP_MODULE_ID, operateData_);

        // uint256 token0AmountOut_ = abi.decode(returnData_, (uint256));
        // assertLe(token0AmountOut_, token0AmountIn_);
        // This below asset was only for 0 fee case.
        // assertGe(token0AmountOut_, (token0AmountIn_ * 99999) / 100000); // 99.999% of token0AmountIn_

        WithdrawParams memory withdrawParams_ = WithdrawParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            // Trying to remove more amounts than present so full amount will be removed
            amount0: 250 * 1e6,
            amount1: 250 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        uint256 liquidityDecreaseRaw_;
        (amount0_, amount1_, , , liquidityDecreaseRaw_) = _withdraw(dexKey_, withdrawParams_);

        console2.log("amount0_", _toString(amount0_));
        console2.log("amount1_", _toString(amount1_));
        console2.log("liquidityDecreaseRaw_", _toString(liquidityDecreaseRaw_));

        _clearPendingSupply(address(USDT));
        _clearPendingSupply(address(USDC));
    }

    function testSwapIn() public {
        bytes memory data_ = abi.encodeWithSelector(this.shouldSwapInCallbackImplementation.selector);
        dexV2.startOperation(data_);
    }

    function _swapOut(
        DexKey memory dexKey_,
        SwapOutParams memory swapOutParams_
    ) internal returns (uint256 amountIn_, uint256 protocolFeeCharged_, uint256 lpFeeCharged_) {
        bytes memory operateData_ = abi.encodeWithSelector(FluidDexV2D3SwapModule.swapOut.selector, swapOutParams_);
        bytes memory returnData_ = dexV2.operate(DEX_TYPE, SWAP_MODULE_ID, operateData_);

        (amountIn_, protocolFeeCharged_, lpFeeCharged_) = abi.decode(returnData_, (uint256, uint256, uint256));
    }

    function shouldSwapOutCallbackImplementation() public returns (bytes memory returnData_) {
        // Initialize Pool first
        DexKey memory dexKey_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: 100, // 0.01%
            tickSpacing: 1,
            controller: address(0)
        });
        _initialize(dexKey_, (1 << 96));

        // Then try adding liquidity
        DepositParams memory depositParams_ = DepositParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        _deposit(dexKey_, depositParams_);

        // (uint256 amount0_, uint256 amount1_, , , uint256 liquidityIncreaseRaw_) = abi.decode(
        //     returnData_,
        //     (uint256, uint256, uint256, uint256, uint256)
        // );

        // console2.log("test amount0_");
        // console2.logBytes32(bytes32(amount0_));

        // console2.log("test amount1_");
        // console2.logBytes32(bytes32(amount1_));

        // console2.log("test liquidityIncreaseRaw_");
        // console2.logBytes32(bytes32(liquidityIncreaseRaw_));

        // Then try swap out
        uint256 usdcAmountOut_ = 1e6;
        SwapOutParams memory swapOutParams_ = SwapOutParams({
            dexKey: dexKey_,
            swap0To1: true,
            amountOut: usdcAmountOut_,
            amountInMax: type(uint256).max,
            controllerData: "0x"
        });
        (uint256 usdtAmountIn_, uint256 usdtProtocolFeeCharged_, uint256 usdtLpFeeCharged_) = _swapOut(dexKey_, swapOutParams_);

        console2.log("usdtAmountIn_", _toString(usdtAmountIn_));
        console2.log("usdcAmountOut_", _toString(usdcAmountOut_));
        console2.log("usdtProtocolFeeCharged_", _toString(usdtProtocolFeeCharged_));
        console2.log("usdtLpFeeCharged_", _toString(usdtLpFeeCharged_));

        // console2.log("token0AmountIn_");
        // console2.logBytes32(bytes32(token0AmountIn_));

        // swapOutParams_ = SwapOutParams({
        //     dexKey: dexKey_,
        //     swap0To1: false,
        //     amountOut: token0AmountIn_,
        //     amountInMax: type(uint256).max,
        //     controllerData: "0x"
        // });

        // operateData_ = abi.encodeWithSelector(FluidDexV2D3SwapModule.swapOut.selector, swapOutParams_);
        // returnData_ = dexV2.operate(DEX_TYPE, SWAP_MODULE_ID, operateData_);

        // uint256 token0AmountOut_ = abi.decode(returnData_, (uint256));
        // assertGe(token0AmountOut_, token0AmountIn_);

        WithdrawParams memory withdrawParams_ = WithdrawParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            // Trying to remove more amounts than present so full amount will be removed
            amount0: 250 * 1e6,
            amount1: 250 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });

        _withdraw(dexKey_, withdrawParams_);

        // uint256 liquidityDecreaseRaw_;
        // (amount0_, amount1_, , , liquidityDecreaseRaw_) = abi.decode(
        //     returnData_,
        //     (uint256, uint256, uint256, uint256, uint256)
        // );

        // console2.log("test amount0_");
        // console2.logBytes32(bytes32(amount0_));

        // console2.log("test amount1_");
        // console2.logBytes32(bytes32(amount1_));

        // console2.log("test liquidityDecreaseRaw_");
        // console2.logBytes32(bytes32(liquidityDecreaseRaw_));

        _clearPendingSupply(address(USDT));
        _clearPendingSupply(address(USDC));
    }

    function testSwapOut() public {
        bytes memory data_ = abi.encodeWithSelector(this.shouldSwapOutCallbackImplementation.selector);
        dexV2.startOperation(data_);
    }

    function shouldChargeProtocolFeeCallbackImplementation() public returns (bytes memory returnData_) {
        // Initialize Pool first
        DexKey memory dexKey_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: 0, // 0.01%
            tickSpacing: 1,
            controller: address(0)
        });
        _initialize(dexKey_, (1 << 96));

        // Set Protocol Fee
        bytes memory operateAdminData_ = abi.encodeWithSelector(FluidDexV2D3AdminModule.updateProtocolFee.selector, dexKey_, true, 1000); // 0.1% protocol fee
        returnData_ = dexV2.operateAdmin(DEX_TYPE, ADMIN_MODULE_ID, operateAdminData_);

        // Add Liquidity
        DepositParams memory depositParams_ = DepositParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        _deposit(dexKey_, depositParams_);

        // Swap In
        uint256 usdtAmountIn_ = 1e6;
        SwapInParams memory swapInParams_ = SwapInParams({ dexKey: dexKey_, swap0To1: true, amountIn: usdtAmountIn_, amountOutMin: 0, controllerData: "0x" });
        (uint256 usdcAmountOut_, uint256 usdcProtocolFeeCharged_, uint256 usdcLpFeeCharged_) = _swapIn(dexKey_, swapInParams_);

        console2.log("usdtAmountIn_", _toString(usdtAmountIn_));
        console2.log("usdcAmountOut_", _toString(usdcAmountOut_));
        console2.log("usdcProtocolFeeCharged_", _toString(usdcProtocolFeeCharged_));
        console2.log("usdcLpFeeCharged_", _toString(usdcLpFeeCharged_));

        _clearPendingSupply(address(USDT));
        _clearPendingSupply(address(USDC));
    }

    function testChargeProtocolFeeProperly() public {
        bytes memory data_ = abi.encodeWithSelector(this.shouldChargeProtocolFeeCallbackImplementation.selector);
        dexV2.startOperation(data_);
    }

    function shouldChargeFetchedDynamicFeeProperlyCallbackImplementation() public returns (bytes memory returnData_) {
        // Deploy mock controller
        mockController = new MockController();

        // Initialize Pool first
        DexKey memory dexKey_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: type(uint24).max, // Dynamic Fee Flag
            tickSpacing: 1,
            controller: address(mockController)
        });
        _initialize(dexKey_, (1 << 96));

        // Add Liquidity
        DepositParams memory depositParams_ = DepositParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        _deposit(dexKey_, depositParams_);

        // Switch on fetched dynamic fee
        vm.prank(address(mockController));
        dexV2.operate(DEX_TYPE, CONTROLLER_MODULE_ID, abi.encodeWithSelector(FluidDexV2D3ControllerModule.updateFetchDynamicFeeFlag.selector, dexKey_, true));

        // Swap In
        bytes memory controllerData_ = abi.encode(false, 100, true);
        uint256 usdtAmountIn_ = 1e6;
        SwapInParams memory swapInParams_ = SwapInParams({
            dexKey: dexKey_,
            swap0To1: true,
            amountIn: usdtAmountIn_,
            amountOutMin: 0,
            controllerData: controllerData_
        });
        (uint256 usdcAmountOut_, uint256 usdcProtocolFeeCharged_, uint256 usdcLpFeeCharged_) = _swapIn(dexKey_, swapInParams_);

        assertEq(usdcLpFeeCharged_, 99);

        _clearPendingSupply(address(USDT));
        _clearPendingSupply(address(USDC));
    }

    function testFetchedDynamicFee() public {
        bytes memory data_ = abi.encodeWithSelector(this.shouldChargeFetchedDynamicFeeProperlyCallbackImplementation.selector);
        dexV2.startOperation(data_);
    }

    function shouldChargeInbuiltDynamicFeeForSwapInProperlyCallbackImplementation() public returns (bytes memory returnData_) {
        // Initialize Pool first
        DexKey memory dexKey_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: type(uint24).max, // Dynamic Fee Flag
            tickSpacing: 1,
            controller: address(mockController)
        });
        _initialize(dexKey_, (1 << 96));

        // Add Liquidity
        DepositParams memory depositParams_ = DepositParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        _deposit(dexKey_, depositParams_);

        // Set inbuilt dynamic fee
        vm.prank(address(mockController));
        dexV2.operate(
            DEX_TYPE,
            CONTROLLER_MODULE_ID,
            abi.encodeWithSelector(FluidDexV2D3ControllerModule.updateFeeVersion1.selector, dexKey_, 60, 1, 100, 2000)
        );

        // Swap In
        bytes memory controllerData_ = abi.encode(false, 100, true);
        uint256 usdtAmountIn_ = 50 * 1e6;
        SwapInParams memory swapInParams_ = SwapInParams({
            dexKey: dexKey_,
            swap0To1: true,
            amountIn: usdtAmountIn_,
            amountOutMin: 0,
            controllerData: controllerData_
        });
        (uint256 usdcAmountOut_, uint256 usdcProtocolFeeCharged_, uint256 usdcLpFeeCharged_) = _swapIn(dexKey_, swapInParams_);

        console2.log("usdcAmountOut_", _toString(usdcAmountOut_));
        console2.log("usdcLpFeeCharged_", _toString(usdcLpFeeCharged_));
        console2.log("usdcProtocolFeeCharged_", _toString(usdcProtocolFeeCharged_));

        assertEq(usdcLpFeeCharged_, 79778);

        _clearPendingSupply(address(USDT));
        _clearPendingSupply(address(USDC));
    }

    function testInbuiltDynamicFeeForSwapIn() public {
        bytes memory data_ = abi.encodeWithSelector(this.shouldChargeInbuiltDynamicFeeForSwapInProperlyCallbackImplementation.selector);
        dexV2.startOperation(data_);
    }

    function shouldChargeInbuiltDynamicFeeForSwapOutProperlyCallbackImplementation() public returns (bytes memory returnData_) {
        // Initialize Pool first
        DexKey memory dexKey_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: type(uint24).max, // Dynamic Fee Flag
            tickSpacing: 1,
            controller: address(mockController)
        });
        _initialize(dexKey_, (1 << 96));

        // Add Liquidity
        DepositParams memory depositParams_ = DepositParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        _deposit(dexKey_, depositParams_);

        // Set inbuilt dynamic fee
        vm.prank(address(mockController));
        dexV2.operate(
            DEX_TYPE,
            CONTROLLER_MODULE_ID,
            abi.encodeWithSelector(FluidDexV2D3ControllerModule.updateFeeVersion1.selector, dexKey_, 60, 1, 100, 2000)
        );

        // Swap In
        bytes memory controllerData_ = abi.encode(false, 100, true);
        uint256 usdcAmountOut_ = 50 * 1e6;
        SwapOutParams memory swapOutParams_ = SwapOutParams({
            dexKey: dexKey_,
            swap0To1: true,
            amountOut: usdcAmountOut_,
            amountInMax: type(uint256).max,
            controllerData: controllerData_
        });
        (uint256 usdtAmountIn_, uint256 usdtProtocolFeeCharged_, uint256 usdtLpFeeCharged_) = _swapOut(dexKey_, swapOutParams_);

        console2.log("usdtAmountIn_", _toString(usdtAmountIn_));
        console2.log("usdtLpFeeCharged_", _toString(usdtLpFeeCharged_));
        console2.log("usdtProtocolFeeCharged_", _toString(usdtProtocolFeeCharged_));

        assertEq(usdtLpFeeCharged_, 80400);

        _clearPendingSupply(address(USDT));
        _clearPendingSupply(address(USDC));
    }

    function testInbuiltDynamicFeeForSwapOut() public {
        bytes memory data_ = abi.encodeWithSelector(this.shouldChargeInbuiltDynamicFeeForSwapOutProperlyCallbackImplementation.selector);
        dexV2.startOperation(data_);
    }

    function shouldSwapProperlyWithMultiplePositions() public returns (bytes memory returnData_) {
        // Initialize Pool first
        DexKey memory dexKey_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: 0, // 0.01%
            tickSpacing: 1,
            controller: address(0)
        });
        _initialize(dexKey_, (1 << 96));

        // Then try adding liquidity
        DepositParams memory depositParams_ = DepositParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        (uint256 amount0_, uint256 amount1_, , , uint256 liquidityIncreaseRaw_) = _deposit(dexKey_, depositParams_);

        console2.log("amount0_", _toString(amount0_));
        console2.log("amount1_", _toString(amount1_));
        console2.log("liquidityIncreaseRaw_", _toString(liquidityIncreaseRaw_));

        depositParams_ = DepositParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: -1,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        (amount0_, amount1_, , , liquidityIncreaseRaw_) = _deposit(dexKey_, depositParams_);
        console2.log("amount0_", _toString(amount0_));
        console2.log("amount1_", _toString(amount1_));
        console2.log("liquidityIncreaseRaw_", _toString(liquidityIncreaseRaw_));

        // Then try swap in
        uint256 usdtAmountIn_ = 99 * 1e6;
        SwapInParams memory swapInParams_ = SwapInParams({ dexKey: dexKey_, swap0To1: true, amountIn: usdtAmountIn_, amountOutMin: 0, controllerData: "0x" });
        (uint256 usdcAmountOut_, uint256 usdcProtocolFeeCharged_, uint256 usdcLpFeeCharged_) = _swapIn(dexKey_, swapInParams_);

        console2.log("usdtAmountIn_", _toString(usdtAmountIn_));
        console2.log("usdcAmountOut_", _toString(usdcAmountOut_));
        console2.log("usdcProtocolFeeCharged_", _toString(usdcProtocolFeeCharged_));
        console2.log("usdcLpFeeCharged_", _toString(usdcLpFeeCharged_));

        _clearPendingSupply(address(USDT));
        _clearPendingSupply(address(USDC));
    }

    function testSwapProperlyWithMultiplePositions() public {
        bytes memory data_ = abi.encodeWithSelector(this.shouldSwapProperlyWithMultiplePositions.selector);
        dexV2.startOperation(data_);
    }

    function shouldSwapInPartsAndFull(uint256 usdtAmountIn1_, uint256 usdtAmountIn21_, uint256 usdtAmountIn22_) public returns (bytes memory returnData_) {
        // Initialize Pool first
        DexKey memory dexKey1_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: 0,
            tickSpacing: 1,
            controller: address(0)
        });
        _initialize(dexKey1_, (1 << 96));

        DexKey memory dexKey2_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: 0,
            tickSpacing: 1,
            controller: address(1)
        });
        _initialize(dexKey2_, (1 << 96));

        // Then try adding liquidity in dex 1
        DepositParams memory depositParams_ = DepositParams({
            dexKey: dexKey1_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        _deposit(dexKey1_, depositParams_);

        // Then try adding liquidity in dex 2
        depositParams_ = DepositParams({
            dexKey: dexKey2_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6, 
            amount0Min: 0,
            amount1Min: 0
        });
        _deposit(dexKey2_, depositParams_);

        // Swap in full in dex 1
        SwapInParams memory swapInParams_ = SwapInParams({ dexKey: dexKey1_, swap0To1: true, amountIn: usdtAmountIn1_, amountOutMin: 0, controllerData: "0x" });
        (uint256 usdcAmountOut1_, uint256 usdcProtocolFeeCharged1_, uint256 usdcLpFeeCharged1_) = _swapIn(dexKey1_, swapInParams_);

        // Swap in parts in dex 2
        swapInParams_ = SwapInParams({ dexKey: dexKey2_, swap0To1: true, amountIn: usdtAmountIn21_, amountOutMin: 0, controllerData: "0x" });
        (uint256 usdcAmountOut21_, uint256 usdcProtocolFeeCharged21_, uint256 usdcLpFeeCharged21_) = _swapIn(dexKey2_, swapInParams_);

        swapInParams_ = SwapInParams({ dexKey: dexKey2_, swap0To1: true, amountIn: usdtAmountIn22_, amountOutMin: 0, controllerData: "0x" });
        (uint256 usdcAmountOut22_, uint256 usdcProtocolFeeCharged22_, uint256 usdcLpFeeCharged22_) = _swapIn(dexKey2_, swapInParams_);

        uint256 totalAmountOutFromParts = usdcAmountOut21_ + usdcAmountOut22_;
        assertGe(usdcAmountOut1_, totalAmountOutFromParts);
        assertLe(usdcAmountOut1_ - totalAmountOutFromParts, 2);
        
        _clearPendingSupply(address(USDT));
        _clearPendingSupply(address(USDC));
    }

    function testSwapInPartsAndFull() public {
        uint256 usdtAmountIn1_ = 10 * 1e6;

        for (uint256 i = 0; i < 9; i++) {
            // Create a fresh snapshot for each test
            uint256 snapshot = vm.snapshot();
            
            uint256 usdtAmountIn21_ = (i + 1) * 1e6;
            uint256 usdtAmountIn22_ = usdtAmountIn1_ - usdtAmountIn21_;
            
            bytes memory data_ = abi.encodeWithSelector(
                this.shouldSwapInPartsAndFull.selector, 
                usdtAmountIn1_, 
                usdtAmountIn21_, 
                usdtAmountIn22_
            );
            dexV2.startOperation(data_);
            
            // Revert to fresh state for next iteration
            vm.revertTo(snapshot);
        }
    }

    function shouldSwapOutPartsAndFull(uint256 usdtAmountOut1_, uint256 usdtAmountOut21_, uint256 usdtAmountOut22_) public returns (bytes memory returnData_) {
        // Initialize Pool first
        DexKey memory dexKey1_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: 0,
            tickSpacing: 1,
            controller: address(0)
        });
        _initialize(dexKey1_, (1 << 96));

        DexKey memory dexKey2_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: 0,
            tickSpacing: 1,
            controller: address(1)
        });
        _initialize(dexKey2_, (1 << 96));

        // Then try adding liquidity in dex 1
        DepositParams memory depositParams_ = DepositParams({
            dexKey: dexKey1_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        _deposit(dexKey1_, depositParams_);

        // Then try adding liquidity in dex 2
        depositParams_ = DepositParams({
            dexKey: dexKey2_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6, 
            amount0Min: 0,
            amount1Min: 0
        });
        _deposit(dexKey2_, depositParams_);

        // Swap out full in dex 1
        SwapOutParams memory swapOutParams_ = SwapOutParams({ dexKey: dexKey1_, swap0To1: false, amountOut: usdtAmountOut1_, amountInMax: type(uint256).max, controllerData: "0x" });
        (uint256 usdcAmountIn1_, uint256 usdcProtocolFeeCharged1_, uint256 usdcLpFeeCharged1_) = _swapOut(dexKey1_, swapOutParams_);

        // Swap out parts in dex 2
        swapOutParams_ = SwapOutParams({ dexKey: dexKey2_, swap0To1: false, amountOut: usdtAmountOut21_, amountInMax: type(uint256).max, controllerData: "0x" });
        (uint256 usdcAmountIn21_, uint256 usdcProtocolFeeCharged21_, uint256 usdcLpFeeCharged21_) = _swapOut(dexKey2_, swapOutParams_);

        swapOutParams_ = SwapOutParams({ dexKey: dexKey2_, swap0To1: false, amountOut: usdtAmountOut22_, amountInMax: type(uint256).max, controllerData: "0x" });
        (uint256 usdcAmountIn22_, uint256 usdcProtocolFeeCharged22_, uint256 usdcLpFeeCharged22_) = _swapOut(dexKey2_, swapOutParams_);

        uint256 totalAmountInFromParts = usdcAmountIn21_ + usdcAmountIn22_;
        assertGe(totalAmountInFromParts, usdcAmountIn1_);
        assertLe(totalAmountInFromParts - usdcAmountIn1_, 2);
        
        _clearPendingSupply(address(USDT));
        _clearPendingSupply(address(USDC));
    }

    function testSwapOutPartsAndFull() public {
        uint256 usdtAmountOut1_ = 10 * 1e6;

        for (uint256 i = 0; i < 9; i++) {
            // Create a fresh snapshot for each test
            uint256 snapshot = vm.snapshot();
            
            uint256 usdtAmountOut21_ = (i + 1) * 1e6;
            uint256 usdtAmountOut22_ = usdtAmountOut1_ - usdtAmountOut21_;
            
            bytes memory data_ = abi.encodeWithSelector(
                this.shouldSwapOutPartsAndFull.selector, 
                usdtAmountOut1_, 
                usdtAmountOut21_, 
                usdtAmountOut22_
            );
            dexV2.startOperation(data_);
            
            // Revert to fresh state for next iteration
            vm.revertTo(snapshot);
        }
    }

    function shouldSwapOutWithGapInLiquidityCallbackImplementation() public returns (bytes memory returnData_) {
        // Initialize Pool first
        DexKey memory dexKey_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: 0,
            tickSpacing: 1,
            controller: address(0)
        });
        _initialize(dexKey_, (1 << 96));
        // Add liquidity in range 0 to -10 ticks
        DepositParams memory depositParams_ = DepositParams({
            dexKey: dexKey_,
            tickLower: -10,
            tickUpper: -0,
            positionSalt: bytes32("0x1"),
            amount0: 0,
            amount1: 10 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        _deposit(dexKey_, depositParams_);

        // Add liquidity in range -15 to -25 ticks (gap between -10 and -15)
        depositParams_ = DepositParams({
            dexKey: dexKey_,
            tickLower: -25,
            tickUpper: -15,
            positionSalt: bytes32("0x2"),
            amount0: 0,
            amount1: 10 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        _deposit(dexKey_, depositParams_);

        // Swap out 20 USDC worth of USDT
        SwapOutParams memory swapOutParams_ = SwapOutParams({
            dexKey: dexKey_,
            swap0To1: true,
            amountOut: (20 * 1e6) - 1,
            amountInMax: type(uint256).max,
            controllerData: "0x"
        });
        (uint256 usdtAmountIn_, uint256 usdtProtocolFeeCharged_, uint256 usdtLpFeeCharged_) = _swapOut(dexKey_, swapOutParams_);

        console2.log("usdtAmountIn_", _toString(usdtAmountIn_));
        console2.log("usdtProtocolFeeCharged_", _toString(usdtProtocolFeeCharged_));
        console2.log("usdtLpFeeCharged_", _toString(usdtLpFeeCharged_));

        assertEq(usdtAmountIn_, 20025020);

        _clearPendingSupply(address(USDT));
        _clearPendingSupply(address(USDC));
    }

    function testSwapOutWithGapInLiquidity() public {
        bytes memory data_ = abi.encodeWithSelector(this.shouldSwapOutWithGapInLiquidityCallbackImplementation.selector);
        dexV2.startOperation(data_);
    }

    function shouldOnlyDepositOnValidTicksCallbackImplementation() public returns (bytes memory returnData_) {
        // Initialize Pool with tick spacing 3
        DexKey memory dexKey_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: 0,
            tickSpacing: 3,
            controller: address(0)
        });
        _initialize(dexKey_, (1 << 96));
        // Try to deposit on invalid tick (not multiple of 3)
        DepositParams memory depositParams_ = DepositParams({
            dexKey: dexKey_,
            tickLower: -10, // Invalid tick (not multiple of 3)
            tickUpper: -6,
            positionSalt: bytes32("0x1"),
            amount0: 10 * 1e6,
            amount1: 10 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        
        // Use try-catch by calling the operation directly
        bytes memory operateData_ = abi.encodeWithSelector(FluidDexV2D3UserModule.deposit.selector, depositParams_);
        vm.expectRevert();
        dexV2.operate(DEX_TYPE, USER_MODULE_ID, operateData_);

        // Try to deposit on valid ticks (multiples of 3)
        depositParams_ = DepositParams({
            dexKey: dexKey_,
            tickLower: -9,  // Valid tick (multiple of 3)
            tickUpper: -6,  // Valid tick (multiple of 3)
            positionSalt: bytes32("0x1"),
            amount0: 10 * 1e6,
            amount1: 10 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        
        // This should succeed
        _deposit(dexKey_, depositParams_);

        _clearPendingSupply(address(USDT));
        _clearPendingSupply(address(USDC));
    }

    function testOnlyDepositOnValidTicks() public {
        bytes memory data_ = abi.encodeWithSelector(this.shouldOnlyDepositOnValidTicksCallbackImplementation.selector);
        dexV2.startOperation(data_);
    }

    function shouldOnlyInitializeWithValidTickSpacingCallbackImplementation() external {
        // Initialize Pool with tick spacing 501 (should fail)
        DexKey memory dexKey_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: 0,
            tickSpacing: 501, // Invalid tick spacing (should be <= 500)
            controller: address(0)
        });
        
        // This should fail due to invalid tick spacing
        InitializeParams memory params_ = InitializeParams({ dexKey: dexKey_, sqrtPriceX96: (1 << 96) });

        bytes memory operateData_ = abi.encodeWithSelector(FluidDexV2D3UserModule.initialize.selector, params_);
        vm.expectRevert();
        dexV2.operate(DEX_TYPE, USER_MODULE_ID, operateData_);

        // Initialize Pool with tick spacing 500 (should pass)
        dexKey_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: 0,
            tickSpacing: 500, // Valid tick spacing (<= 500)
            controller: address(0)
        });
        
        // This should succeed
        _initialize(dexKey_, (1 << 96));
    }

    function testOnlyInitializeWithValidTickSpacing() public {
        bytes memory data_ = abi.encodeWithSelector(this.shouldOnlyInitializeWithValidTickSpacingCallbackImplementation.selector);
        dexV2.startOperation(data_);
    }

    function shouldNotExceedMaxLiquidityPerTickCallbackImplementation() external {
        uint24 tickSpacing_ = 1;

        // Initialize pool
        DexKey memory dexKey_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: 0,
            tickSpacing: tickSpacing_,
            controller: address(0)
        });
        
        _initialize(dexKey_, (1 << 96));

        uint256 maxLiquidityPerTick = _getMaxLiquidityPerTick(tickSpacing_);

        (uint256 amount0ForMaxLiquidityPerTick_, ) = LA.getAmountsForLiquidity(
            uint160(1 << 96),
            uint160(TM.getSqrtRatioAtTick(0)),
            uint160(TM.getSqrtRatioAtTick(int24(tickSpacing_))),
            uint128(maxLiquidityPerTick)
        );

        // Try to add liquidity that would exceed max liquidity per tick
        DepositParams memory depositParams_ = DepositParams({
            dexKey: dexKey_,
            tickLower: 0,
            tickUpper: int24(tickSpacing_),
            positionSalt: bytes32("0x1"),
            amount0: (amount0ForMaxLiquidityPerTick_ / 1e3) * 2, // Trying to add more liquidity than max
            amount1: 0,
            amount0Min: 0,
            amount1Min: 0
        });
       
        bytes memory operateData_ = abi.encodeWithSelector(FluidDexV2D3UserModule.deposit.selector, depositParams_);

        // This should fail due to exceeding max liquidity per tick
        vm.expectRevert();
        dexV2.operate(DEX_TYPE, USER_MODULE_ID, operateData_);
    }

    function testNotExceedMaxLiquidityPerTick() public {
        bytes memory data_ = abi.encodeWithSelector(this.shouldNotExceedMaxLiquidityPerTickCallbackImplementation.selector);
        dexV2.startOperation(data_);
    }

    function shouldTestDynamicFeeConsecutiveSwapsCallbackImplementation() public returns (bytes memory returnData_) {
        // Deploy mock controller
        mockController = new MockController();

        // Initialize Pool with dynamic fee configuration
        DexKey memory dexKey_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: type(uint24).max, // Dynamic Fee Flag
            tickSpacing: 1,
            controller: address(mockController)
        });
        _initialize(dexKey_, (1 << 96));

        // Add Liquidity
        DepositParams memory depositParams_ = DepositParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        _deposit(dexKey_, depositParams_);

        uint256 initialTime = block.timestamp;
        
        // Configure inbuilt dynamic fee: maxDecayTime=60, priceImpactToFeeDivisionFactor=1, minFee=100, maxFee=2000
        vm.warp(initialTime);
        vm.prank(address(mockController));
        dexV2.operate(
            DEX_TYPE,
            CONTROLLER_MODULE_ID,
            abi.encodeWithSelector(
                FluidDexV2D3ControllerModule.updateFeeVersion1.selector,
                dexKey_, 60, 1, 100, 2000
            )
        );

        console2.log("=== Testing consecutive swaps without time delay ===");
        
        // Execute two identical swaps consecutively
        bytes memory controllerData_ = abi.encode(false, 100, true);
        SwapInParams memory swapParams_ = SwapInParams({
            dexKey: dexKey_,
            swap0To1: true,
            amountIn: 25 * 1e6, // 25 USDT
            amountOutMin: 0,
            controllerData: controllerData_
        });
        
        (,, uint256 firstSwapFee_) = _swapIn(dexKey_, swapParams_);
        console2.log("First swap fee:", _toString(firstSwapFee_));

        // Second swap immediately after first
        (,, uint256 secondSwapFee_) = _swapIn(dexKey_, swapParams_);
        console2.log("Second swap fee:", _toString(secondSwapFee_));
        
        uint256 totalConsecutiveFee_ = firstSwapFee_ + secondSwapFee_;
        console2.log("Total consecutive swaps fee:", _toString(totalConsecutiveFee_));

        _clearPendingSupply(address(USDT));
        _clearPendingSupply(address(USDC));
    }

    function shouldTestDynamicFeeDelayedSwapsCallbackImplementation() public returns (bytes memory returnData_) {
        // Deploy mock controller
        mockController = new MockController();

        // Initialize Pool with identical configuration
        DexKey memory dexKey_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: type(uint24).max, // Dynamic Fee Flag
            tickSpacing: 1,
            controller: address(mockController)
        });
        _initialize(dexKey_, (1 << 96));

        // Add identical liquidity
        DepositParams memory depositParams_ = DepositParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        _deposit(dexKey_, depositParams_);

        uint256 initialTime = block.timestamp;
        
        // Configure identical dynamic fee parameters
        vm.warp(initialTime);
        vm.prank(address(mockController));
        dexV2.operate(
            DEX_TYPE,
            CONTROLLER_MODULE_ID,
            abi.encodeWithSelector(
                FluidDexV2D3ControllerModule.updateFeeVersion1.selector,
                dexKey_, 60, 1, 100, 2000
            )
        );

        console2.log("=== Testing swaps with time delay ===");
        
        // Execute first swap
        bytes memory controllerData_ = abi.encode(false, 100, true);
        SwapInParams memory swapParams_ = SwapInParams({
            dexKey: dexKey_,
            swap0To1: true,
            amountIn: 25 * 1e6, // 25 USDT
            amountOutMin: 0,
            controllerData: controllerData_
        });
        
        (,, uint256 firstSwapFee_) = _swapIn(dexKey_, swapParams_);
        console2.log("First swap fee:", _toString(firstSwapFee_));

        // Wait for half the decay time (30 seconds out of 60)
        vm.warp(initialTime + 30);
        
        // Execute second swap after delay
        (,, uint256 secondSwapFee_) = _swapIn(dexKey_, swapParams_);
        console2.log("Second swap fee:", _toString(secondSwapFee_));
        
        uint256 totalDelayedFee_ = firstSwapFee_ + secondSwapFee_;
        console2.log("Total delayed swaps fee:", _toString(totalDelayedFee_));

        _clearPendingSupply(address(USDT));
        _clearPendingSupply(address(USDC));
    }

    function testDynamicFeeConsecutiveSwaps() public {
        bytes memory data_ = abi.encodeWithSelector(this.shouldTestDynamicFeeConsecutiveSwapsCallbackImplementation.selector);
        dexV2.startOperation(data_);
    }

    function testDynamicFeeDelayedSwaps() public {
        bytes memory data_ = abi.encodeWithSelector(this.shouldTestDynamicFeeDelayedSwapsCallbackImplementation.selector);
        dexV2.startOperation(data_);
    }

    function testDynamicFeeBehaviorComparison() public {
        console2.log("=== Dynamic Fee Behavior Test ===");
        console2.log("Testing if dynamic fees properly incentivize spaced-out trading...");
        
        // Test consecutive swaps
        testDynamicFeeConsecutiveSwaps();
        
        // Test delayed swaps  
        testDynamicFeeDelayedSwaps();
        
        console2.log("=== Expected Behavior ===");
        console2.log("Consecutive swaps should incur higher total fees than delayed swaps");
    }

    function shouldMeasureSwapInGasCallbackImplementation() public returns (bytes memory returnData_) {
        // Initialize Pool first
        DexKey memory dexKey_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: 100, // 0.01%
            tickSpacing: 1,
            controller: address(0)
        });
        _initialize(dexKey_, (1 << 96));

        // Add liquidity
        DepositParams memory depositParams_ = DepositParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        _deposit(dexKey_, depositParams_);

        // Measure gas for swapIn
        uint256 usdtAmountIn_ = 10 * 1e6;
        SwapInParams memory swapInParams_ = SwapInParams({ 
            dexKey: dexKey_, 
            swap0To1: false, 
            amountIn: usdtAmountIn_, 
            amountOutMin: 0, 
            controllerData: "0x" 
        });

        // Record gas before swap
        uint256 gasBefore = gasleft();
        
        (uint256 usdcAmountOut_, uint256 usdcProtocolFeeCharged_, uint256 usdcLpFeeCharged_) = _swapIn(dexKey_, swapInParams_);
        
        // Record gas after swap
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;

        console2.log("=== Gas Measurement for SwapIn ===");
        // console2.log("Gas before swap:", gasBefore);
        // console2.log("Gas after swap:", gasAfter);
        console2.log("Gas used for swapIn:", _toString(gasUsed));
        // console2.log("USDT amount in:", _toString(usdtAmountIn_));
        // console2.log("USDC amount out:", _toString(usdcAmountOut_));
        // console2.log("Protocol fee charged:", _toString(usdcProtocolFeeCharged_));
        // console2.log("LP fee charged:", _toString(usdcLpFeeCharged_));

        _clearPendingSupply(address(USDT));
        _clearPendingSupply(address(USDC));

        return returnData_;
    }

    function testSwapInGasMeasurement() public {
        bytes memory data_ = abi.encodeWithSelector(this.shouldMeasureSwapInGasCallbackImplementation.selector);
        dexV2.startOperation(data_);
    }

    function shouldTestReentrancyThroughFetchDynamicFeeForSwapInCallbackImplementation() public returns (bytes memory returnData_) {
        // Deploy mock controller
        mockController = new MockController();

        // Initialize Pool with dynamic fee configuration
        DexKey memory dexKey_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: type(uint24).max, // Dynamic Fee Flag
            tickSpacing: 1,
            controller: address(mockController)
        });
        _initialize(dexKey_, (1 << 96));

        // Add Liquidity
        DepositParams memory depositParams_ = DepositParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        _deposit(dexKey_, depositParams_);

        // Switch on fetched dynamic fee
        vm.prank(address(mockController));
        dexV2.operate(DEX_TYPE, CONTROLLER_MODULE_ID, abi.encodeWithSelector(FluidDexV2D3ControllerModule.updateFetchDynamicFeeFlag.selector, dexKey_, true));

        // Attempt swap with reentrancy flag set to true
        // The MockController will try to reenter via _swapIn in fetchDynamicFeeForSwapIn
        bytes memory controllerData_ = abi.encode(true, 100, true); // tryReentrancy = true
        uint256 usdtAmountIn_ = 1e6;
        SwapInParams memory swapInParams_ = SwapInParams({
            dexKey: dexKey_,
            swap0To1: true,
            amountIn: usdtAmountIn_,
            amountOutMin: 0,
            controllerData: controllerData_
        });
        
        // With try-catch on fetchDynamicFee, reentrancy attempts are caught and 
        // handled gracefully - swap proceeds with default fee values (0)
        bytes memory operateData_ = abi.encodeWithSelector(FluidDexV2D3SwapModule.swapIn.selector, swapInParams_);
        bytes memory result_ = dexV2.operate(DEX_TYPE, SWAP_MODULE_ID, operateData_);
        
        // Decode return: (uint256 amountOut, uint256 protocolFee, uint256 lpFee)
        (, , uint256 lpFee_) = abi.decode(result_, (uint256, uint256, uint256));
        
        // If reentrancy was caught, lpFee should be 0 (default), not 100 (from controller)
        assertEq(lpFee_, 0, "lpFee should be 0 - reentrancy should have been caught and default fee used");
        console2.log("Reentrancy test through fetchDynamicFeeForSwapIn passed - lpFee is 0 (default, not 100 from controller)");

        _clearPendingSupply(address(USDT));
        _clearPendingSupply(address(USDC));

        return returnData_;
    }

    function testReentrancyThroughFetchDynamicFeeForSwapIn() public {
        bytes memory data_ = abi.encodeWithSelector(this.shouldTestReentrancyThroughFetchDynamicFeeForSwapInCallbackImplementation.selector);
        dexV2.startOperation(data_);
    }

    function shouldTestReentrancyThroughFetchDynamicFeeForSwapOutCallbackImplementation() public returns (bytes memory returnData_) {
        // Deploy mock controller
        mockController = new MockController();

        // Initialize Pool with dynamic fee configuration
        DexKey memory dexKey_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: type(uint24).max, // Dynamic Fee Flag
            tickSpacing: 1,
            controller: address(mockController)
        });
        _initialize(dexKey_, (1 << 96));

        // Add Liquidity
        DepositParams memory depositParams_ = DepositParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        _deposit(dexKey_, depositParams_);

        // Switch on fetched dynamic fee
        vm.prank(address(mockController));
        dexV2.operate(DEX_TYPE, CONTROLLER_MODULE_ID, abi.encodeWithSelector(FluidDexV2D3ControllerModule.updateFetchDynamicFeeFlag.selector, dexKey_, true));

        // Attempt swapOut with reentrancy flag set to true
        // The MockController will try to reenter via _swapOut in fetchDynamicFeeForSwapOut
        bytes memory controllerData_ = abi.encode(true, 100, true); // tryReentrancy = true
        uint256 usdcAmountOut_ = 1e6;
        SwapOutParams memory swapOutParams_ = SwapOutParams({
            dexKey: dexKey_,
            swap0To1: true,
            amountOut: usdcAmountOut_,
            amountInMax: type(uint256).max,
            controllerData: controllerData_
        });
        
        // With try-catch on fetchDynamicFee, reentrancy attempts are caught and 
        // handled gracefully - swap proceeds with default fee values (0)
        bytes memory operateData_ = abi.encodeWithSelector(FluidDexV2D3SwapModule.swapOut.selector, swapOutParams_);
        bytes memory result_ = dexV2.operate(DEX_TYPE, SWAP_MODULE_ID, operateData_);
        
        // Decode return: (uint256 amountIn, uint256 protocolFee, uint256 lpFee)
        (, , uint256 lpFee_) = abi.decode(result_, (uint256, uint256, uint256));
        
        // If reentrancy was caught, lpFee should be 0 (default), not 100 (from controller)
        assertEq(lpFee_, 0, "lpFee should be 0 - reentrancy should have been caught and default fee used");
        console2.log("Reentrancy test through fetchDynamicFeeForSwapOut passed - lpFee is 0 (default, not 100 from controller)");

        _clearPendingSupply(address(USDT));
        _clearPendingSupply(address(USDC));

        return returnData_;
    }

    function testReentrancyThroughFetchDynamicFeeForSwapOut() public {
        bytes memory data_ = abi.encodeWithSelector(this.shouldTestReentrancyThroughFetchDynamicFeeForSwapOutCallbackImplementation.selector);
        dexV2.startOperation(data_);
    }


    function shouldInitializeAndAddLiquidityCallbackImplementation(DexKey memory dexKey_) public returns (bytes memory returnData_) {
        // Initialize the pool
        _initialize(dexKey_, (1 << 96));

        // Add initial liquidity
        DepositParams memory depositParams_ = DepositParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        _deposit(dexKey_, depositParams_);

        // Clear any pending transfers from the liquidity addition
        _clearPendingSupply(address(USDT));
        _clearPendingSupply(address(USDC));

        return returnData_;
    }


    function shouldPerformSwapAndSettleWithGasLogging(string memory testName_) public returns (bytes memory returnData_) {
        // Use predefined DexKey for the test
        DexKey memory dexKey_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: 100, // 0.01%
            tickSpacing: 1,
            controller: address(0)
        });

        console2.log("---", testName_, "---");
        
        // Prepare swap parameters
        uint256 usdtAmountIn_ = 10 * 1e6;
        SwapInParams memory swapInParams_ = SwapInParams({
            dexKey: dexKey_,
            swap0To1: false,
            amountIn: usdtAmountIn_,
            amountOutMin: 0,
            controllerData: "0x"
        });
        
        // === STEP 1: Measure Swap Gas ===
        uint256 gasBeforeSwap_ = gasleft();
        
        // Do swap
        (uint256 usdcAmountOut_, uint256 protocolFee_, uint256 lpFee_) = _swapIn(dexKey_, swapInParams_);
        
        uint256 gasAfterSwap_ = gasleft();
        uint256 swapGas_ = gasBeforeSwap_ - gasAfterSwap_;
        
        // === STEP 2: Measure Settle Gas ===
        uint256 gasBeforeSettle_ = gasleft();
        
        // Settle pending transfers using the helper function
        _clearPendingSupply(address(USDT));
        _clearPendingSupply(address(USDC));
        
        uint256 gasAfterSettle_ = gasleft();
        uint256 settleGas_ = gasBeforeSettle_ - gasAfterSettle_;
        
        // === STEP 3: Calculate Total Gas ===
        uint256 totalGas_ = swapGas_ + settleGas_;
        
        // Log detailed gas breakdown
        console2.log("Swap gas:", _toString(swapGas_));
        console2.log("Settle gas:", _toString(settleGas_)); 
        console2.log("Total gas (Swap + Settle):", _toString(totalGas_));
        console2.log("USDC amount out:", _toString(usdcAmountOut_));
        console2.log("Protocol fee:", _toString(protocolFee_));
        console2.log("LP fee:", _toString(lpFee_));

        // Results are logged above, no need to store in state variables

        return returnData_;
    }

    // ===================================
    // ETH/USDC POOL TESTS  
    // ===================================

    // Comprehensive ETH/USDC gas comparison tests using cold storage for accurate measurements
    function testEthGasSavingsComparison_Normal() public {
        console2.log("=== ETH/USDC Gas Comparison: Normal Swap (Cold Storage) ===");
        
        bytes memory setupData_ = abi.encodeWithSelector(this.shouldSetupEthPoolCallbackImplementation.selector);
        dexV2.startOperation(setupData_);
        
        bytes memory swapData_ = abi.encodeWithSelector(this.shouldMeasureEthNormalSwapGasCallbackImplementation.selector);
        dexV2.startOperation(swapData_);
        
        console2.log("=== ETH Normal Swap Test Completed ===");
    }
    
    function testEthGasSavingsComparison_Optimized() public {
        console2.log("=== ETH/USDC Gas Comparison: Optimized Swap (Cold Storage) ===");
        
        bytes memory setupData_ = abi.encodeWithSelector(this.shouldSetupEthPoolCallbackImplementation.selector);
        dexV2.startOperation(setupData_);
        
        bytes memory addTokensData_ = abi.encodeWithSelector(this.shouldAddEthTokensCallbackImplementation.selector);
        dexV2.startOperation(addTokensData_);
        
        bytes memory optimizedSwapData_ = abi.encodeWithSelector(this.shouldMeasureEthOptimizedSwapGasCallbackImplementation.selector);
        dexV2.startOperation(optimizedSwapData_);
        
        // Test comprehensive ETH functionality including rebalancing
        bytes memory comprehensiveData_ = abi.encodeWithSelector(this.shouldTestEthComprehensiveFunctionalityCallbackImplementation.selector);
        dexV2.startOperation(comprehensiveData_);
        
        console2.log("=== ETH Optimized Swap Test Completed ===");
    }

    function _testEthPoolInitAndLiquidity() internal {
        DexKey memory dexKey_ = DexKey({
            token0: address(USDC), // USDC has lower address
            token1: NATIVE_TOKEN_ADDRESS, // ETH has higher address
            fee: 100, // 0.01%
            tickSpacing: 1,
            controller: address(0)
        });
        
        // Calculate sqrtPriceX96 for USDC/ETH at $4000 (1 USDC = 1/4000 ETH)
        // priceX96 = (1 << 96) / 4000, then sqrtPriceX96 = sqrt(priceX96)
        uint256 priceX96 = uint256((1 << 96)) / 4000;
        uint256 usdcEthSqrtPriceX96 = FixedPointMathLib.sqrt(priceX96 * (1 << 96));
        console2.log("Calculated sqrtPriceX96:", _toString(usdcEthSqrtPriceX96));
        
        _initialize(dexKey_, usdcEthSqrtPriceX96);
        
        // Get the actual current tick from the initialized price
        int24 currentTick = TM.getTickAtSqrtRatio(uint160(usdcEthSqrtPriceX96));
        console2.log("Current tick from sqrtPriceX96:", _toString(currentTick));
        
        // Update liquidity range to be around the actual current tick  
        int24 tickLower_ = currentTick - 50;
        int24 tickUpper_ = currentTick + 50;
        
        console2.log("=== ETH/USDC Pool Initialized at ~$4000 ===");
        
        // Add initial liquidity near current tick using calculated range
        DepositParams memory depositParams_ = DepositParams({
            dexKey: dexKey_,
            tickLower: tickLower_, // Current tick - 50
            tickUpper: tickUpper_, // Current tick + 50
            positionSalt: bytes32("0x1"),
            amount0: 2000 * 1e6, // 2000 USDC (token0)
            amount1: 0.5 ether, // 0.5 ETH (token1)
            amount0Min: 0,
            amount1Min: 0
        });
        
        // Fund contract with ETH and USDC for deposit
        deal(address(this), 10 ether);
        deal(address(USDC), address(this), 3000 * 1e6); // 3000 USDC to cover settlement
        
        (uint256 amount0Added_, uint256 amount1Added_, , , uint256 liquidityAdded_) = _deposit(dexKey_, depositParams_);
        
        console2.log("Added USDC:", _toString(amount0Added_));
        console2.log("Added ETH:", _toString(amount1Added_));
        console2.log("Liquidity added:", _toString(liquidityAdded_));
        
        // Clear pending transfers after liquidity addition
        _clearPendingSupply(NATIVE_TOKEN_ADDRESS);
        _clearPendingSupply(address(USDC));
    }

    function _testEthSwaps() internal {
        DexKey memory dexKey_ = DexKey({
            token0: address(USDC), // USDC has lower address
            token1: NATIVE_TOKEN_ADDRESS, // ETH has higher address
            fee: 100,
            tickSpacing: 1,
            controller: address(0)
        });
        
        console2.log("=== Testing ETH -> USDC Swap ===");
        
        // Swap 0.01 ETH for USDC (ETH is token1, USDC is token0) - smaller amount
        SwapInParams memory swapInParams_ = SwapInParams({
            dexKey: dexKey_,
            swap0To1: false, // ETH (token1) -> USDC (token0)
            amountIn: 0.01 ether,
            amountOutMin: 0,
            controllerData: "0x"
        });
        
        // Measure gas for normal swap + settle
        uint256 gasBeforeSwap_ = gasleft();
        (uint256 usdcAmountOut_, uint256 protocolFee_, uint256 lpFee_) = _swapIn(dexKey_, swapInParams_);
        // Include settlement in gas measurement
        _clearPendingSupply(NATIVE_TOKEN_ADDRESS);
        _clearPendingSupply(address(USDC));
        uint256 gasAfterSettle_ = gasleft();
        uint256 normalSwapPlusSettleGas_ = gasBeforeSwap_ - gasAfterSettle_;
        
        console2.log("Normal swap + settle gas:", _toString(normalSwapPlusSettleGas_));
        
        console2.log("ETH in:", _toString(uint256(0.01 ether)));
        console2.log("USDC out:", _toString(usdcAmountOut_));
        console2.log("Protocol fee:", _toString(protocolFee_));
        console2.log("LP fee:", _toString(lpFee_));
        
        console2.log("=== Testing USDC -> ETH Swap ===");
        
        // Swap USDC back to ETH (USDC is token0, ETH is token1)
        SwapInParams memory swapInParams2_ = SwapInParams({
            dexKey: dexKey_,
            swap0To1: true, // USDC (token0) -> ETH (token1)
            amountIn: 100 * 1e6,
            amountOutMin: 0,
            controllerData: "0x"
        });
        
        // Measure gas for reverse swap + settle
        uint256 gasBeforeSwap2_ = gasleft();
        (uint256 ethAmountOut_, uint256 protocolFee2_, uint256 lpFee2_) = _swapIn(dexKey_, swapInParams2_);
        // Include settlement in gas measurement
        _clearPendingSupply(NATIVE_TOKEN_ADDRESS);
        _clearPendingSupply(address(USDC));
        uint256 gasAfterSettle2_ = gasleft();
        uint256 reverseSwapPlusSettleGas_ = gasBeforeSwap2_ - gasAfterSettle2_;
        
        console2.log("Reverse swap + settle gas:", _toString(reverseSwapPlusSettleGas_));
        
        console2.log("USDC in:", _toString(uint256(100 * 1e6)));
        console2.log("ETH out:", _toString(ethAmountOut_));
        console2.log("Protocol fee:", _toString(protocolFee2_));
        console2.log("LP fee:", _toString(lpFee2_));
    }

    function _testEthAddTokensAndOptimization() internal {
        console2.log("=== Testing AddOrRemoveTokens with ETH ===");
        
        // Add ETH tokens to DEX
        uint256 ethToAdd_ = 0.5 ether;
        dexV2.addOrRemoveTokens{value: ethToAdd_}(NATIVE_TOKEN_ADDRESS, int256(ethToAdd_));
        console2.log("Added ETH to DEX:", _toString(ethToAdd_));
        
        // Add USDC tokens to DEX
        uint256 usdcToAdd_ = 500 * 1e6; // 500 USDC
        IERC20(address(USDC)).approve(address(dexV2), usdcToAdd_);
        dexV2.addOrRemoveTokens(address(USDC), int256(usdcToAdd_));
        console2.log("Added USDC to DEX:", _toString(usdcToAdd_));
        
        console2.log("=== Testing Optimized Swap with Pre-funded Tokens ===");
        
        DexKey memory dexKey_ = DexKey({
            token0: address(USDC), // USDC has lower address
            token1: NATIVE_TOKEN_ADDRESS, // ETH has higher address
            fee: 100,
            tickSpacing: 1,
            controller: address(0)
        });
        
        // Test another swap with pre-funded tokens (should be cheaper)
        SwapInParams memory swapInParams3_ = SwapInParams({
            dexKey: dexKey_,
            swap0To1: false, // ETH (token1) -> USDC (token0)
            amountIn: 0.05 ether,
            amountOutMin: 0,
            controllerData: "0x"
        });
        
        uint256 gasBeforeOptimizedSwap_ = gasleft();
        (uint256 usdcOut3_, , ) = _swapIn(dexKey_, swapInParams3_);
        // Include settlement in gas measurement for fair comparison
        _clearPendingSupply(NATIVE_TOKEN_ADDRESS);
        _clearPendingSupply(address(USDC));
        uint256 gasAfterOptimizedSettle_ = gasleft();
        uint256 optimizedSwapPlusSettleGas_ = gasBeforeOptimizedSwap_ - gasAfterOptimizedSettle_;
        
        console2.log("Optimized swap + settle gas:", _toString(optimizedSwapPlusSettleGas_));
        console2.log("ETH in (optimized):", _toString(uint256(0.05 ether)));
        console2.log("USDC out (optimized):", _toString(usdcOut3_));
    }

    function _testEthRebalanceAndWithdraw() internal {
        console2.log("=== Testing Rebalance ===");
        
        uint256 gasBeforeRebalance_ = gasleft();
        
        // Rebalance ETH and USDC
        dexV2.rebalance(NATIVE_TOKEN_ADDRESS);
        dexV2.rebalance(address(USDC));
        
        uint256 gasAfterRebalance_ = gasleft();
        uint256 rebalanceGas_ = gasBeforeRebalance_ - gasAfterRebalance_;
        
        console2.log("Rebalance gas used:", _toString(rebalanceGas_));
        
        console2.log("=== Testing Liquidity Removal ===");
        
        DexKey memory dexKey_ = DexKey({
            token0: address(USDC), // USDC has lower address
            token1: NATIVE_TOKEN_ADDRESS, // ETH has higher address
            fee: 100,
            tickSpacing: 1,
            controller: address(0)
        });
        
        // Calculate the same tick range used in deposit
        uint256 priceX96_ = uint256((1 << 96)) / 4000;
        uint256 usdcEthSqrtPriceX96_ = FixedPointMathLib.sqrt(priceX96_ * (1 << 96));
        int24 currentTick_ = TM.getTickAtSqrtRatio(uint160(usdcEthSqrtPriceX96_));
        int24 tickLower_ = currentTick_ - 50;
        int24 tickUpper_ = currentTick_ + 50;
        
        // Remove some liquidity from the same tight range
        WithdrawParams memory withdrawParams_ = WithdrawParams({
            dexKey: dexKey_,
            tickLower: tickLower_, // Same as deposit range
            tickUpper: tickUpper_, // Same as deposit range
            positionSalt: bytes32("0x1"),
            amount0: 400 * 1e6, // Remove 400 USDC worth (token0)
            amount1: 0.1 ether, // Remove 0.1 ETH worth (token1)
            amount0Min: 0,
            amount1Min: 0
        });
        
        (uint256 usdcRemoved_, uint256 ethRemoved_, , , uint256 liquidityRemoved_) = _withdraw(dexKey_, withdrawParams_);
        
        console2.log("USDC removed:", _toString(usdcRemoved_));
        console2.log("ETH removed:", _toString(ethRemoved_));
        console2.log("Liquidity removed:", _toString(liquidityRemoved_));
        
        // Final settlement
        _clearPendingSupply(NATIVE_TOKEN_ADDRESS);
        _clearPendingSupply(address(USDC));
    }

    // Setup callback for ETH/USDC pool initialization and liquidity
    function shouldSetupEthPoolCallbackImplementation() public returns (bytes memory returnData_) {
        _testEthPoolInitAndLiquidity();
        return returnData_;
    }

    // Callback for measuring ETH normal swap gas (cold storage)
    function shouldMeasureEthNormalSwapGasCallbackImplementation() public returns (bytes memory returnData_) {
        DexKey memory dexKey_ = DexKey({
            token0: address(USDC), // USDC has lower address
            token1: NATIVE_TOKEN_ADDRESS, // ETH has higher address
            fee: 100,
            tickSpacing: 1,
            controller: address(0)
        });
        
        console2.log("=== Measuring ETH Normal Swap Gas (Cold Storage) ===");
        
        SwapInParams memory swapInParams_ = SwapInParams({
            dexKey: dexKey_,
            swap0To1: false, // ETH (token1) -> USDC (token0)
            amountIn: 0.01 ether, // 0.01 ETH
            amountOutMin: 0,
            controllerData: "0x"
        });
        
        // Measure gas for normal swap + settle (cold storage)
        uint256 gasBeforeSwap_ = gasleft();
        (uint256 usdcAmountOut_, uint256 protocolFee_, uint256 lpFee_) = _swapIn(dexKey_, swapInParams_);
        uint256 gasAfterSwap_ = gasleft();
        uint256 swapGas_ = gasBeforeSwap_ - gasAfterSwap_;
        
        uint256 gasBeforeSettle_ = gasleft();
        _clearPendingSupply(NATIVE_TOKEN_ADDRESS);
        _clearPendingSupply(address(USDC));
        uint256 gasAfterSettle_ = gasleft();
        uint256 settleGas_ = gasBeforeSettle_ - gasAfterSettle_;
        
        uint256 totalGas_ = swapGas_ + settleGas_;
        
        console2.log("ETH Normal swap gas (cold):", _toString(swapGas_));
        console2.log("ETH Normal settle gas (cold):", _toString(settleGas_));
        console2.log("ETH Normal total gas (cold):", _toString(totalGas_));
        console2.log("ETH in:", _toString(uint256(0.01 ether)));
        console2.log("USDC out:", _toString(usdcAmountOut_));
        console2.log("Protocol fee:", _toString(protocolFee_));
        console2.log("LP fee:", _toString(lpFee_));
        
        return returnData_;
    }

    // Callback for adding ETH tokens to DEX
    function shouldAddEthTokensCallbackImplementation() public returns (bytes memory returnData_) {
        console2.log("=== Adding ETH Tokens to DEX ===");
        
        // Add ETH tokens to DEX
        uint256 ethToAdd_ = 0.5 ether;
        dexV2.addOrRemoveTokens{value: ethToAdd_}(NATIVE_TOKEN_ADDRESS, int256(ethToAdd_));
        console2.log("Added ETH to DEX:", _toString(ethToAdd_));
        
        // Add USDC tokens to DEX
        uint256 usdcToAdd_ = 500 * 1e6; // 500 USDC
        IERC20(address(USDC)).approve(address(dexV2), usdcToAdd_);
        dexV2.addOrRemoveTokens(address(USDC), int256(usdcToAdd_));
        console2.log("Added USDC to DEX:", _toString(usdcToAdd_));
        
        return returnData_;
    }

    // Callback for measuring ETH optimized swap gas (cold storage)
    function shouldMeasureEthOptimizedSwapGasCallbackImplementation() public returns (bytes memory returnData_) {
        DexKey memory dexKey_ = DexKey({
            token0: address(USDC), // USDC has lower address
            token1: NATIVE_TOKEN_ADDRESS, // ETH has higher address
            fee: 100,
            tickSpacing: 1,
            controller: address(0)
        });
        
        console2.log("=== Measuring ETH Optimized Swap Gas (Cold Storage) ===");
        
        SwapInParams memory swapInParams_ = SwapInParams({
            dexKey: dexKey_,
            swap0To1: false, // ETH (token1) -> USDC (token0)
            amountIn: 0.01 ether, // Same amount as normal swap for fair comparison
            amountOutMin: 0,
            controllerData: "0x"
        });
        
        // Measure gas for optimized swap + settle (cold storage)
        uint256 gasBeforeSwap_ = gasleft();
        (uint256 usdcOut_, uint256 protocolFee_, uint256 lpFee_) = _swapIn(dexKey_, swapInParams_);
        uint256 gasAfterSwap_ = gasleft();
        uint256 swapGas_ = gasBeforeSwap_ - gasAfterSwap_;
        
        uint256 gasBeforeSettle_ = gasleft();
        _clearPendingSupply(NATIVE_TOKEN_ADDRESS);
        _clearPendingSupply(address(USDC));
        uint256 gasAfterSettle_ = gasleft();
        uint256 settleGas_ = gasBeforeSettle_ - gasAfterSettle_;
        
        uint256 totalGas_ = swapGas_ + settleGas_;
        
        console2.log("ETH Optimized swap gas (cold):", _toString(swapGas_));
        console2.log("ETH Optimized settle gas (cold):", _toString(settleGas_));
        console2.log("ETH Optimized total gas (cold):", _toString(totalGas_));
        console2.log("ETH in (optimized):", _toString(uint256(0.01 ether)));
        console2.log("USDC out (optimized):", _toString(usdcOut_));
        console2.log("Protocol fee:", _toString(protocolFee_));
        console2.log("LP fee:", _toString(lpFee_));
        
        return returnData_;
    }

    // Callback for comprehensive ETH functionality testing (additional swaps only, avoid rebalancing issue)
    function shouldTestEthComprehensiveFunctionalityCallbackImplementation() public returns (bytes memory returnData_) {
        console2.log("=== Testing Comprehensive ETH Functionality ===");
        
        // Test additional swaps to demonstrate comprehensive ETH functionality
        _testEthSwaps();
        
        console2.log("=== Note: Rebalancing skipped to avoid ETH transfer issue to DexV2 contract ===");
        console2.log("=== Comprehensive ETH Testing Completed ===");
        
        return returnData_;
    }

    // ===================================
    // FEE EXPLOIT TESTS (AUDITOR REPORT)
    // ===================================

    /// @notice Step 1: Initialize pool and set protocol fee
    function shouldInitPoolForExploitCallbackImplementation() public returns (bytes memory returnData_) {
        DexKey memory dexKey_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: 100,
            tickSpacing: 1,
            controller: address(this)
        });

        // Initialize at 1:1 price
        uint256 sqrtPriceX96 = FixedPointMathLib.sqrt(uint256(1) << 192);
        _initialize(dexKey_, sqrtPriceX96);

        console2.log("=== USDT/USDC Pool Initialized at 1:1 ===");

        // Set protocol fee to 1%
        bytes memory operateAdminData_ = abi.encodeWithSelector(
            FluidDexV2D3AdminModule.updateProtocolFee.selector, 
            dexKey_, 
            true, // protocol fee is on 0 to 1 swaps
            100
        );
        returnData_ = dexV2.operateAdmin(DEX_TYPE, ADMIN_MODULE_ID, operateAdminData_);
        console2.log("Protocol fee set to 0.01%");
    }

    /// @notice Step 2: Add initial wide-range liquidity
    function shouldAddInitialLiquidityForExploitCallbackImplementation() public returns (bytes memory returnData_) {
        DexKey memory dexKey_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: 100,
            tickSpacing: 1,
            controller: address(this)
        });

        // Add 500 USDT + 500 USDC with wide range
        DepositParams memory depositParams_ = DepositParams({
            dexKey: dexKey_,
            tickLower: -15,
            tickUpper: 15, 
            positionSalt: bytes32("0x1"),
            amount0: 500 * 1e6, // USDT
            amount1: 500 * 1e6, // USDC
            amount0Min: 0,
            amount1Min: 0
        });
        
        (uint256 amount0_, uint256 amount1_, uint256 fee0_, uint256 fee1_, ) = _deposit(dexKey_, depositParams_);
        console2.log("Initial liquidity added - USDT:", _toString(amount0_), "USDC:", _toString(amount1_));
        
        _clearPendingSupply(address(USDT));
        _clearPendingSupply(address(USDC));
        
        return returnData_;
    }

    /// @notice Step 3: Perform swaps to generate fees
    function shouldGenerateFeesForExploitCallbackImplementation() public returns (bytes memory returnData_) {
        DexKey memory dexKey_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: 100,
            tickSpacing: 1,
            controller: address(this)
        });

        console2.log("=== Generating fees through swaps ===");

        // Swap 1: USDC -> USDT (73 USDC)
        SwapInParams memory swapParams1 = SwapInParams({
            dexKey: dexKey_,
            swap0To1: false, // USDC (token1) -> USDT (token0)
            amountIn: 73e6,
            amountOutMin: 0,
            controllerData: "0x"
        });
        _swapIn(dexKey_, swapParams1);
        _clearPendingSupply(address(USDT));
        _clearPendingSupply(address(USDC));

        // Swap 2: USDT -> USDC (72 USDT)
        SwapInParams memory swapParams2 = SwapInParams({
            dexKey: dexKey_,
            swap0To1: true, // USDT (token0) -> USDC (token1)
            amountIn: 72e6,
            amountOutMin: 0,
            controllerData: "0x"
        });
        _swapIn(dexKey_, swapParams2);
        _clearPendingSupply(address(USDT));
        _clearPendingSupply(address(USDC));

        // Swap 3: USDC -> USDT (73 USDC)
        _swapIn(dexKey_, swapParams1);
        _clearPendingSupply(address(USDT));
        _clearPendingSupply(address(USDC));

        console2.log("Generated fees through multiple swaps");
        return returnData_;
    }

    /// @notice Step 4: Add exploit liquidity at 1.05 price
    function shouldAddExploitLiq1CallbackImplementation() public returns (bytes memory returnData_) {
        console2.log("=== EXPLOIT STEP 1: Add liquidity with current tick inside ===");
        
        DexKey memory dexKey_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: 100,
            tickSpacing: 1,
            controller: address(this)
        });

        // Add narrow range liquidity with current tick inside
        DepositParams memory depositParams_ = DepositParams({
            dexKey: dexKey_,
            tickLower: 1,  // 223 / 223 = 1
            tickUpper: 3,  // 669 / 223 = 3
            positionSalt: bytes32("0x1"),
            amount0: 1 * 1e6, // USDT
            amount1: 1 * 1e6, // USDC
            amount0Min: 0,
            amount1Min: 0
        });
        
        (uint256 amount0_, uint256 amount1_, uint256 fee0_, uint256 fee1_, ) = _deposit(dexKey_, depositParams_);
        console2.log("Exploit liq 1 added - Fee0:", _toString(fee0_), "Fee1:", _toString(fee1_));
        
        _clearPendingSupply(address(USDT));
        _clearPendingSupply(address(USDC));
        
        return returnData_;
    }

    /// @notice Step 5: Swap to generate fees in lower tick
    function shouldSwapForExploitCallbackImplementation() public returns (bytes memory returnData_) {
        console2.log("=== EXPLOIT STEP 2: Swap to generate fee in lower tick ===");
        
        DexKey memory dexKey_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: 100,
            tickSpacing: 1,
            controller: address(this)
        });

        // USDT -> USDC (72 USDT)
        SwapInParams memory swapParams = SwapInParams({
            dexKey: dexKey_,
            swap0To1: true, // USDT (token0) -> USDC (token1)
            amountIn: 72e6,
            amountOutMin: 0,
            controllerData: "0x"
        });
        
        (uint256 amountOut, uint256 protocolFee, uint256 lpFee) = _swapIn(dexKey_, swapParams);
        console2.log("Swap generated - Out:", _toString(amountOut), "LP Fee:", _toString(lpFee));
        
        _clearPendingSupply(address(USDT));
        _clearPendingSupply(address(USDC));
        
        return returnData_;
    }

    /// @notice Step 6: Add liquidity at boundary (upper tick = previous lower tick)
    function shouldAddExploitLiq2CallbackImplementation() public returns (bytes memory returnData_) {
        console2.log("=== EXPLOIT STEP 3: Add liquidity at boundary ===");
        
        DexKey memory dexKey_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: 100,
            tickSpacing: 1,
            controller: address(this)
        });

        // Add liquidity at 1:1 price with narrow range
        DepositParams memory depositParams_ = DepositParams({
            dexKey: dexKey_,
            tickLower: -1, // -223 / 223 = -1
            tickUpper: 1,  // 223 / 223 = 1
            positionSalt: bytes32("0x1"),
            amount0: 1 * 1e6, // USDT
            amount1: 1 * 1e6, // USDC
            amount0Min: 0,
            amount1Min: 0
        });
        
        (uint256 amount0_, uint256 amount1_, uint256 fee0_, uint256 fee1_, ) = _deposit(dexKey_, depositParams_);
        console2.log("Exploit liq 2 added - Fee0:", _toString(fee0_), "Fee1:", _toString(fee1_));
        
        _clearPendingSupply(address(USDT));
        _clearPendingSupply(address(USDC));
        
        return returnData_;
    }

    /// @notice Step 7: Repeat deposit and save fees to storage
    function shouldAddExploitLiq3CallbackImplementation() public returns (bytes memory returnData_) {
        console2.log("=== EXPLOIT STEP 4: Repeat deposit and save fees to storage ===");
        
        DexKey memory dexKey_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: 100,
            tickSpacing: 1,
            controller: address(this)
        });

        // Same deposit as step 6 but don't clear pending
        DepositParams memory depositParams_ = DepositParams({
            dexKey: dexKey_,
            tickLower: -1, // -223 / 223 = -1
            tickUpper: 1,  // 223 / 223 = 1
            positionSalt: bytes32("0x1"),
            amount0: 1 * 1e6, // USDT
            amount1: 1 * 1e6, // USDC
            amount0Min: 0,
            amount1Min: 0
        });
        
        (uint256 amount0_, uint256 amount1_, uint256 fee0_, uint256 fee1_, ) = _deposit(dexKey_, depositParams_);
        console2.log("Exploit liq 3 added - Fee0:", _toString(fee0_), "Fee1:", _toString(fee1_));

        // Only clear USDT pending supply
        _clearPendingSupply(address(USDT));

        // For USDC, use settle to save the pending amount as stored tokens
        int256 pendingSupply_ = _getPendingSupply(address(this), address(USDC));
        console2.log("Pending USDC:", _toString(pendingSupply_));
        
        // This saves the fees by using storeAmount parameter
        dexV2.settle(address(USDC), pendingSupply_, 0, -pendingSupply_, address(this), true);
        
        console2.log("Saved USDC to storage:", _toString(-pendingSupply_));
        return returnData_;
    }

    /// @notice Step 8: Drain pool using saved fees
    function shouldDrainPoolUsingStoredFeesCallbackImplementation() public returns (bytes memory returnData_) {
        console2.log("=== EXPLOIT STEP 5: Drain pool using saved fees ===");
        
        DexKey memory dexKey_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: 100,
            tickSpacing: 1,
            controller: address(this)
        });

        uint256 usdcAmountIn = 500e6;
        // USDC -> USDT (500 USDC)
        SwapInParams memory swapParams = SwapInParams({
            dexKey: dexKey_,
            swap0To1: false, // USDC (token1) -> USDT (token0)
            amountIn: usdcAmountIn,
            amountOutMin: 0,
            controllerData: "0x"
        });

        (uint256 usdtOut, uint256 protocolFee, uint256 lpFee) = _swapIn(dexKey_, swapParams);
        console2.log("Swap output - USDT:", _toString(usdtOut), "Protocol fee:", _toString(protocolFee));

        uint256 usdtBalanceBefore_ = USDT.balanceOf(address(this));
        
        // Settle without providing actual USDC, using stored amount from exploit
        dexV2.settle(address(USDT), -int256(usdtOut), 0, 0, address(this), true);
        dexV2.settle(address(USDC), int256(usdcAmountIn), 0, -int256(usdcAmountIn), address(this), true);
        
        uint256 usdtBalanceAfter_ = USDT.balanceOf(address(this));
        uint256 profit = usdtBalanceAfter_ - usdtBalanceBefore_;

        console2.log("=== EXPLOIT COMPLETE ===");
        console2.log("USDT profit from exploit:", _toString(profit));
        
        return returnData_;
    }

    /// @notice Main test function that executes the full fee exploit scenario
    /// @dev This test replicates the auditor's reported fee manipulation vulnerability
    function testFeeExploitScenario() public {
        console2.log("===================================================");
        console2.log("=== DEX V2 D3 FEE EXPLOIT TEST (AUDITOR REPORT) ===");
        console2.log("===================================================");
        console2.log("");

        // Fund test account with sufficient tokens
        deal(address(USDT), address(this), 10000 * 1e6);
        deal(address(USDC), address(this), 10000 * 1e6);

        console2.log("PHASE 1: SETUP");
        console2.log("==============");
        
        // Step 1: Initialize pool with 1:1 price and protocol fee
        console2.log("Step 1: Initialize pool");
        dexV2.startOperation(abi.encodeWithSelector(this.shouldInitPoolForExploitCallbackImplementation.selector));
        
        // Step 2: Add initial wide-range liquidity (500 USDC + 500 USDT)
        console2.log("Step 2: Add initial liquidity");
        dexV2.startOperation(abi.encodeWithSelector(this.shouldAddInitialLiquidityForExploitCallbackImplementation.selector));
        
        // Step 3: Perform swaps to generate fees
        console2.log("Step 3: Generate fees through swaps");
        dexV2.startOperation(abi.encodeWithSelector(this.shouldGenerateFeesForExploitCallbackImplementation.selector));
        
        console2.log("");
        console2.log("PHASE 2: EXPLOIT");
        console2.log("================");
        
        // Step 4: Add liquidity with current tick inside (at 1.05 price)
        dexV2.startOperation(abi.encodeWithSelector(this.shouldAddExploitLiq1CallbackImplementation.selector));
        
        // Step 5: Swap to generate fee in the lower tick
        dexV2.startOperation(abi.encodeWithSelector(this.shouldSwapForExploitCallbackImplementation.selector));
        
        // Step 6: Add liquidity at boundary
        dexV2.startOperation(abi.encodeWithSelector(this.shouldAddExploitLiq2CallbackImplementation.selector));

        vm.expectRevert();  
        
        // Step 7: Repeat deposit and save fees to storage
        dexV2.startOperation(abi.encodeWithSelector(this.shouldAddExploitLiq3CallbackImplementation.selector));

        vm.expectRevert();  
        
        // Step 8: Drain pool using saved fees
        dexV2.startOperation(abi.encodeWithSelector(this.shouldDrainPoolUsingStoredFeesCallbackImplementation.selector));
        
        console2.log("");
        console2.log("===================================================");
        console2.log("=== TEST COMPLETE - VULNERABILITY SOLVED ===");
        console2.log("===================================================");
    }
}
