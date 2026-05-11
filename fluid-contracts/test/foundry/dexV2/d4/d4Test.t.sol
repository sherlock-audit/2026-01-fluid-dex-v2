//SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

// TODO: @Vaibhav Add more tests

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { DexV2BaseSetup } from "../baseSetup.t.sol";
import { FluidDexV2D4AdminModule } from "../../../../contracts/protocols/dexV2/dexTypes/d4/admin/main.sol";
import { FluidDexV2D4ControllerModule } from "../../../../contracts/protocols/dexV2/dexTypes/d4/core/controllerModule.sol";
import { FluidDexV2D4UserModule } from "../../../../contracts/protocols/dexV2/dexTypes/d4/core/userModule.sol";
import { FluidDexV2D4SwapModule } from "../../../../contracts/protocols/dexV2/dexTypes/d4/core/swapModule.sol";
import { MockController } from "../../../../contracts/mocks/mockController.sol";
import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";
import "../../../../contracts/protocols/dexV2/dexTypes/d4/other/structs.sol";

contract DexV2D4Test is DexV2BaseSetup {
    using SafeERC20 for IERC20;

    // Add receive function to accept ETH transfers
    receive() external payable {}

    // Use constants from base setup (DEX_TYPE_D4, ADMIN_MODULE_ID_D4)
    uint256 internal constant DEX_TYPE = DEX_TYPE_D4;
    uint256 internal constant SWAP_MODULE_ID = 1;
    uint256 internal constant USER_MODULE_ID = 2;
    uint256 internal constant CONTROLLER_MODULE_ID = 3;
    uint256 internal constant ADMIN_MODULE_ID = ADMIN_MODULE_ID_D4;

    MockController public mockController;

    function setUp() public virtual override {
        super.setUp();

        // D4 modules are already deployed in DexV2BaseSetup
        
        // Whitelist address(this)
        bytes memory data_ = abi.encodeWithSelector(FluidDexV2D4AdminModule.updateUserWhitelist.selector, address(this), true);
        dexV2.operateAdmin(DEX_TYPE, ADMIN_MODULE_ID, data_);
        
        // Add tokens to DEX reserves
        // Add 1M USDC
        deal(address(USDC), address(this), 1000000 * 1e6);
        USDC.approve(address(dexV2), 1000000 * 1e6);
        dexV2.addOrRemoveTokens(address(USDC), int256(1000000 * 1e6));
        
        // Add 1M USDT
        deal(address(USDT), address(this), 1000000 * 1e6);
        USDT.approve(address(dexV2), 1000000 * 1e6);
        dexV2.addOrRemoveTokens(address(USDT), int256(1000000 * 1e6));
        
        // Add 250 ETH
        deal(address(this), 250 ether);
        dexV2.addOrRemoveTokens{value: 250 ether}(NATIVE_TOKEN_ADDRESS, int256(250 ether));

        // Fund address(this) with 1000 USDC and 1000 USDT
        deal(address(USDT), address(this), 1000 * 1e6);
        deal(address(USDC), address(this), 1000 * 1e6);
    }

    function testSetUp() public {
        assertNotEq(address(dexV2), address(0));
        assertNotEq(address(dexV2D4SwapModule), address(0));
        assertNotEq(address(dexV2D4UserModule), address(0));
        assertNotEq(address(dexV2D4ControllerModule), address(0));
        assertNotEq(address(dexV2D4AdminModule), address(0));
        assertEq(_getDexTypeToAdminImplementation(DEX_TYPE, ADMIN_MODULE_ID), address(dexV2D4AdminModule));
    }

    function _initialize(DexKey memory dexKey_, uint256 sqrtPriceX96_) internal {
        InitializeParams memory params_ = InitializeParams({ dexKey: dexKey_, sqrtPriceX96: sqrtPriceX96_ });

        bytes memory operateData_ = abi.encodeWithSelector(FluidDexV2D4UserModule.initialize.selector, params_);
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

    function _borrow(
        DexKey memory dexKey_,
        BorrowParams memory borrowParams_
    ) internal returns (uint256 amount0_, uint256 amount1_, uint256 feeAccruedToken0_, uint256 feeAccruedToken1_, uint256 liquidityIncreaseRaw_) {
        bytes memory operateData_ = abi.encodeWithSelector(FluidDexV2D4UserModule.borrow.selector, borrowParams_);
        bytes memory returnData_ = dexV2.operate(DEX_TYPE, USER_MODULE_ID, operateData_);
        (amount0_, amount1_, feeAccruedToken0_, feeAccruedToken1_, liquidityIncreaseRaw_) = abi.decode(returnData_, (uint256, uint256, uint256, uint256, uint256));
    }

    function _payback(
        DexKey memory dexKey_,
        PaybackParams memory paybackParams_
    ) internal returns (uint256 amount0_, uint256 amount1_, uint256 feeAccruedToken0_, uint256 feeAccruedToken1_, uint256 liquidityDecreaseRaw_) {
        bytes memory operateData_ = abi.encodeWithSelector(FluidDexV2D4UserModule.payback.selector, paybackParams_);
        bytes memory returnData_ = dexV2.operate(DEX_TYPE, USER_MODULE_ID, operateData_);
        (amount0_, amount1_, feeAccruedToken0_, feeAccruedToken1_, liquidityDecreaseRaw_) = abi.decode(returnData_, (uint256, uint256, uint256, uint256, uint256));
    }

    function shouldBorrowPaybackCallbackImplementation() public returns (bytes memory returnData_) {
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
        BorrowParams memory borrowParams_ = BorrowParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });

        _borrow(dexKey_, borrowParams_);

        // Then try removing liquidity
        PaybackParams memory paybackParams_ = PaybackParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });

        _payback(dexKey_, paybackParams_);

        _clearPendingTransfers(address(USDT));
        _clearPendingTransfers(address(USDC));

        return returnData_;
    }

    function testBorrowPayback() public {
        bytes memory data_ = abi.encodeWithSelector(this.shouldBorrowPaybackCallbackImplementation.selector);
        dexV2.startOperation(data_);
    }

    function _swapIn(
        DexKey memory dexKey_,
        SwapInParams memory swapInParams_
    ) internal returns (uint256 token1AmountOut_, uint256 protocolFeeCharged_, uint256 lpFeeCharged_) {
        bytes memory operateData_ = abi.encodeWithSelector(FluidDexV2D4SwapModule.swapIn.selector, swapInParams_);
        bytes memory returnData_ = dexV2.operate(DEX_TYPE, SWAP_MODULE_ID, operateData_);

        (token1AmountOut_, protocolFeeCharged_, lpFeeCharged_) = abi.decode(returnData_, (uint256, uint256, uint256));
    }

    function _clearPendingTransfers(address token_) internal {
        int256 pendingSupply_ = _getPendingSupply(address(this), token_);
        int256 pendingBorrow_ = _getPendingBorrow(address(this), token_);
        console2.log("pendingSupply_", _toString(pendingSupply_));
        console2.log("pendingBorrow_", _toString(pendingBorrow_));

        uint256 amountToSend_;
        if (pendingSupply_ > 0) amountToSend_ += uint256(pendingSupply_);
        if (pendingBorrow_ < 0) amountToSend_ += uint256(-pendingBorrow_);
        if (token_ != NATIVE_TOKEN_ADDRESS && amountToSend_ > 0) {
            IERC20(token_).approve(address(liquidity), amountToSend_);
        }
        
        if (pendingSupply_ != 0 || pendingBorrow_ != 0) {
            if (token_ == NATIVE_TOKEN_ADDRESS) {
                dexV2.settle{value: amountToSend_}(token_, pendingSupply_, pendingBorrow_, 0, address(this), true);
            } else {
                dexV2.settle(token_, pendingSupply_, pendingBorrow_, 0, address(this), true);
            }
        }
    }

    function shouldSwapInCallbackImplementation() public returns (bytes memory returnData_) {
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
        BorrowParams memory borrowParams_ = BorrowParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });

        (uint256 amount0_, uint256 amount1_, , , uint256 liquidityIncreaseRaw_) = _borrow(dexKey_, borrowParams_);

        console2.log("amount0_", _toString(amount0_));
        console2.log("amount1_", _toString(amount1_));
        console2.log("liquidityIncreaseRaw_", _toString(liquidityIncreaseRaw_));

        // Then try swap in
        uint256 token0AmountIn_ = 99 * 1e6;
        SwapInParams memory swapInParams_ = SwapInParams({ dexKey: dexKey_, swap0To1: false, amountIn: token0AmountIn_, amountOutMin: 0, controllerData: "0x" });

        (uint256 token1AmountOut_, uint256 token1ProtocolFeeCharged_, uint256 token1LpFeeCharged_) = _swapIn(dexKey_, swapInParams_);

        console2.log("token0AmountIn_", _toString(token0AmountIn_));
        console2.log("token1AmountOut_", _toString(token1AmountOut_));
        console2.log("token1ProtocolFeeCharged_", _toString(token1ProtocolFeeCharged_));
        console2.log("token1LpFeeCharged_", _toString(token1LpFeeCharged_));

        // swapInParams_ = SwapInParams({
        // swapInParams_ = SwapInParams({
        //     dexKey: dexKey_,
        //     swap0To1: false,
        //     amountIn: token1AmountOut_,
        //     amountOutMin: 0,
        //     controllerData: "0x"
        // });

        // operateData_ = abi.encodeWithSelector(FluidDexV2D4SwapModule.swapIn.selector, swapInParams_);
        // returnData_ = dexV2.operate(DEX_TYPE, SWAP_MODULE_ID, operateData_);

        // uint256 token0AmountOut_ = abi.decode(returnData_, (uint256));
        // assertLe(token0AmountOut_, token0AmountIn_);
        // This below asset was only for 0 fee case.
        // assertGe(token0AmountOut_, (token0AmountIn_ * 99999) / 100000); // 99.999% of token0AmountIn_

        PaybackParams memory paybackParams_ = PaybackParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 250 * 1e6,
            amount1: 250 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });

        uint256 liquidityDecreaseRaw_;
        (amount0_, amount1_, , , liquidityDecreaseRaw_) = _payback(dexKey_, paybackParams_);

        console2.log("amount0_", _toString(amount0_));
        console2.log("amount1_", _toString(amount1_));
        console2.log("liquidityDecreaseRaw_", _toString(liquidityDecreaseRaw_));

        _clearPendingTransfers(address(USDT));
        _clearPendingTransfers(address(USDC));
    }

    function testSwapIn() public {
        bytes memory data_ = abi.encodeWithSelector(this.shouldSwapInCallbackImplementation.selector);
        dexV2.startOperation(data_);
    }

    function _swapOut(
        DexKey memory dexKey_,
        SwapOutParams memory swapOutParams_
    ) internal returns (uint256 token0AmountIn_, uint256 protocolFeeCharged_, uint256 lpFeeCharged_) {
        bytes memory operateData_ = abi.encodeWithSelector(FluidDexV2D4SwapModule.swapOut.selector, swapOutParams_);
        bytes memory returnData_ = dexV2.operate(DEX_TYPE, SWAP_MODULE_ID, operateData_);

        (token0AmountIn_, protocolFeeCharged_, lpFeeCharged_) = abi.decode(returnData_, (uint256, uint256, uint256));
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
        BorrowParams memory borrowParams_ = BorrowParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });

        (uint256 amount0_, uint256 amount1_, , , uint256 liquidityIncreaseRaw_) = _borrow(dexKey_, borrowParams_);

        console2.log("amount0_", _toString(amount0_));
        console2.log("amount1_", _toString(amount1_));
        console2.log("liquidityIncreaseRaw_", _toString(liquidityIncreaseRaw_));

        // Then try swap out
        uint256 token1AmountOut_ = 1 * 1e6;
        SwapOutParams memory swapOutParams_ = SwapOutParams({
            dexKey: dexKey_,
            swap0To1: true,
            amountOut: token1AmountOut_,
            amountInMax: type(uint256).max,
            controllerData: "0x"
        });
        (uint256 token0AmountIn_, uint256 token0ProtocolFeeCharged_, uint256 token0LpFeeCharged_) = _swapOut(dexKey_, swapOutParams_);

        console2.log("token0AmountIn_", _toString(token0AmountIn_));
        console2.log("token1AmountOut_", _toString(token1AmountOut_));
        console2.log("token0ProtocolFeeCharged_", _toString(token0ProtocolFeeCharged_));
        console2.log("token0LpFeeCharged_", _toString(token0LpFeeCharged_));

        // swapOutParams_ = SwapOutParams({ dexKey: dexKey_, swap0To1: false, amountOut: token0AmountIn_, amountInMax: type(uint256).max, controllerData: "0x" });

        // operateData_ = abi.encodeWithSelector(FluidDexV2D4SwapModule.swapOut.selector, swapOutParams_);
        // returnData_ = dexV2.operate(DEX_TYPE, SWAP_MODULE_ID, operateData_);

        // uint256 token0AmountOut_ = abi.decode(returnData_, (uint256));
        // assertGe(token0AmountOut_, token0AmountIn_);

        PaybackParams memory paybackParams_ = PaybackParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 115 * 1e6,
            amount1: 115 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });

        uint256 liquidityDecreaseRaw_;
        (amount0_, amount1_, , , liquidityDecreaseRaw_) = _payback(dexKey_, paybackParams_);

        console2.log("amount0_", _toString(amount0_));
        console2.log("amount1_", _toString(amount1_));
        console2.log("liquidityDecreaseRaw_", _toString(liquidityDecreaseRaw_));

        _clearPendingTransfers(address(USDT)); // -100
        _clearPendingTransfers(address(USDC)); // 100
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
        bytes memory operateAdminData_ = abi.encodeWithSelector(FluidDexV2D4AdminModule.updateProtocolFee.selector, dexKey_, true, 1000); // 0.1% protocol fee
        returnData_ = dexV2.operateAdmin(DEX_TYPE, ADMIN_MODULE_ID, operateAdminData_);

        // Add Liquidity
        BorrowParams memory borrowParams_ = BorrowParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        _borrow(dexKey_, borrowParams_);

        // Swap In
        uint256 usdtAmountIn_ = 1e6;
        SwapInParams memory swapInParams_ = SwapInParams({ dexKey: dexKey_, swap0To1: true, amountIn: usdtAmountIn_, amountOutMin: 0, controllerData: "0x" });
        (uint256 usdcAmountOut_, uint256 usdcProtocolFeeCharged_, uint256 usdcLpFeeCharged_) = _swapIn(dexKey_, swapInParams_);

        console2.log("usdtAmountIn_", _toString(usdtAmountIn_));
        console2.log("usdcAmountOut_", _toString(usdcAmountOut_));
        console2.log("usdcProtocolFeeCharged_", _toString(usdcProtocolFeeCharged_));
        console2.log("usdcLpFeeCharged_", _toString(usdcLpFeeCharged_));

        _clearPendingTransfers(address(USDT));
        _clearPendingTransfers(address(USDC));
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
        BorrowParams memory borrowParams_ = BorrowParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        _borrow(dexKey_, borrowParams_);

        // Switch on fetched dynamic fee
        vm.prank(address(mockController));
        dexV2.operate(DEX_TYPE, CONTROLLER_MODULE_ID, abi.encodeWithSelector(FluidDexV2D4ControllerModule.updateFetchDynamicFeeFlag.selector, dexKey_, true));

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

        _clearPendingTransfers(address(USDT));
        _clearPendingTransfers(address(USDC));
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
        BorrowParams memory borrowParams_ = BorrowParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        _borrow(dexKey_, borrowParams_);

        // Set inbuilt dynamic fee
        vm.prank(address(mockController));
        dexV2.operate(
            DEX_TYPE,
            CONTROLLER_MODULE_ID,
            abi.encodeWithSelector(FluidDexV2D4ControllerModule.updateFeeVersion1.selector, dexKey_, 60, 1, 100, 2000)
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

        assertEq(usdcLpFeeCharged_, 79877);

        _clearPendingTransfers(address(USDT));
        _clearPendingTransfers(address(USDC));
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
        BorrowParams memory borrowParams_ = BorrowParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        _borrow(dexKey_, borrowParams_);

        // Set inbuilt dynamic fee
        vm.prank(address(mockController));
        dexV2.operate(
            DEX_TYPE,
            CONTROLLER_MODULE_ID,
            abi.encodeWithSelector(FluidDexV2D4ControllerModule.updateFeeVersion1.selector, dexKey_, 60, 1, 100, 2000)
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

        assertEq(usdtLpFeeCharged_, 80501);

        _clearPendingTransfers(address(USDT));
        _clearPendingTransfers(address(USDC));
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
        BorrowParams memory borrowParams_ = BorrowParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        (uint256 amount0_, uint256 amount1_, , , uint256 liquidityIncreaseRaw_) = _borrow(dexKey_, borrowParams_);

        console2.log("amount0_", _toString(amount0_));
        console2.log("amount1_", _toString(amount1_));
        console2.log("liquidityIncreaseRaw_", _toString(liquidityIncreaseRaw_));

        borrowParams_ = BorrowParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: -1,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        (amount0_, amount1_, , , liquidityIncreaseRaw_) = _borrow(dexKey_, borrowParams_);
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

        _clearPendingTransfers(address(USDT));
        _clearPendingTransfers(address(USDC));
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
        BorrowParams memory borrowParams_ = BorrowParams({
            dexKey: dexKey1_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        _borrow(dexKey1_, borrowParams_);

        // Then try adding liquidity in dex 2
        borrowParams_ = BorrowParams({
            dexKey: dexKey2_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6, 
            amount0Min: 0,
            amount1Min: 0
        });
        _borrow(dexKey2_, borrowParams_);

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
        
        _clearPendingTransfers(address(USDT));
        _clearPendingTransfers(address(USDC));
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
        BorrowParams memory borrowParams_ = BorrowParams({
            dexKey: dexKey1_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        _borrow(dexKey1_, borrowParams_);

        // Then try adding liquidity in dex 2
        borrowParams_ = BorrowParams({
            dexKey: dexKey2_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6, 
            amount0Min: 0,
            amount1Min: 0
        });
        _borrow(dexKey2_, borrowParams_);

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
        
        _clearPendingTransfers(address(USDT));
        _clearPendingTransfers(address(USDC));
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

    function shouldSwapInWithGapInLiquidityCallbackImplementation() public returns (bytes memory returnData_) {
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
        BorrowParams memory borrowParams_ = BorrowParams({
            dexKey: dexKey_,
            tickLower: -10,
            tickUpper: -0,
            positionSalt: bytes32("0x1"),
            amount0: 10 * 1e6,
            amount1: 0,
            amount0Min: 0,
            amount1Min: 0
        });
        _borrow(dexKey_, borrowParams_);
        // Add liquidity in range -15 to -25 ticks (gap between -10 and -15)
        borrowParams_ = BorrowParams({
            dexKey: dexKey_,
            tickLower: -25,
            tickUpper: -15,
            positionSalt: bytes32("0x2"),
            amount0: 10 * 1e6,
            amount1: 0,
            amount0Min: 0,
            amount1Min: 0
        });
        _borrow(dexKey_, borrowParams_);
        // Swap in 20 USDT for USDC
        SwapInParams memory swapInParams_ = SwapInParams({
            dexKey: dexKey_,
            swap0To1: true,
            amountIn: (20 * 1e6) - 1,
            amountOutMin: 0,
            controllerData: "0x"
        });
        (uint256 usdcAmountOut_, uint256 usdcProtocolFeeCharged_, uint256 usdcLpFeeCharged_) = _swapIn(dexKey_, swapInParams_);
        console2.log("usdcAmountOut_", _toString(usdcAmountOut_));
        console2.log("usdcProtocolFeeCharged_", _toString(usdcProtocolFeeCharged_));
        console2.log("usdcLpFeeCharged_", _toString(usdcLpFeeCharged_));

        assertEq(usdcAmountOut_, 19975020);
        _clearPendingTransfers(address(USDT));
        _clearPendingTransfers(address(USDC));
    }

    function testSwapInWithGapInLiquidity() public {
        bytes memory data_ = abi.encodeWithSelector(this.shouldSwapInWithGapInLiquidityCallbackImplementation.selector);
        dexV2.startOperation(data_);
    }

    function shouldOnlyBorrowOnValidTicksCallbackImplementation() public returns (bytes memory returnData_) {
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
        BorrowParams memory borrowParams_ = BorrowParams({
            dexKey: dexKey_,
            tickLower: -10,
            tickUpper: -6,
            positionSalt: bytes32("0x1"),
            amount0: 10 * 1e6,
            amount1: 10 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        
        // Use try-catch by calling the operation directly
        bytes memory operateData_ = abi.encodeWithSelector(FluidDexV2D4UserModule.borrow.selector, borrowParams_);
        vm.expectRevert();
        dexV2.operate(DEX_TYPE, USER_MODULE_ID, operateData_);

        // Try to deposit on valid ticks (multiples of 3)
        borrowParams_ = BorrowParams({
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
        _borrow(dexKey_, borrowParams_);

        _clearPendingTransfers(address(USDT));
        _clearPendingTransfers(address(USDC));
    }

    function testOnlyBorrowOnValidTicks() public {
        bytes memory data_ = abi.encodeWithSelector(this.shouldOnlyBorrowOnValidTicksCallbackImplementation.selector);
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

        bytes memory operateData_ = abi.encodeWithSelector(FluidDexV2D4UserModule.initialize.selector, params_);
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

        int24 tickLower_ = 0;
        int24 tickUpper_ = int24(tickSpacing_);
        uint256 gp_ = TM.getSqrtRatioAtTick(tickUpper_); // because gp = (sqrtPriceX96Upper * sqrtPriceX96Lower) / (1<<96)
        uint256 debtAmount1ForMaxLiquidityPerTick_ = FM.mulDiv(amount0ForMaxLiquidityPerTick_, gp_, 1 << 96);

        // Try to add liquidity that would exceed max liquidity per tick
        BorrowParams memory borrowParams_ = BorrowParams({
            dexKey: dexKey_,
            tickLower: tickLower_,
            tickUpper: tickUpper_,
            positionSalt: bytes32("0x1"),
            amount0: 0, // Trying to add more liquidity than max
            amount1: (debtAmount1ForMaxLiquidityPerTick_ / 1e3) + 1,
            amount0Min: 0,
            amount1Min: 0
        });
       
        bytes memory operateData_ = abi.encodeWithSelector(FluidDexV2D4UserModule.borrow.selector, borrowParams_);

        // This should fail due to exceeding max liquidity per tick
        vm.expectRevert();
        dexV2.operate(DEX_TYPE, USER_MODULE_ID, operateData_);
    }

    function testNotExceedMaxLiquidityPerTick() public {
        bytes memory data_ = abi.encodeWithSelector(this.shouldNotExceedMaxLiquidityPerTickCallbackImplementation.selector);
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
        BorrowParams memory borrowParams_ = BorrowParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        _borrow(dexKey_, borrowParams_);

        // Switch on fetched dynamic fee
        vm.prank(address(mockController));
        dexV2.operate(DEX_TYPE, CONTROLLER_MODULE_ID, abi.encodeWithSelector(FluidDexV2D4ControllerModule.updateFetchDynamicFeeFlag.selector, dexKey_, true));

        // Attempt swap with reentrancy flag set to true
        // The MockController will try to reenter via _swapIn in fetchDynamicFeeForSwapIn
        // For D4, we use the special 3-parameter format for reentrancy testing
        bytes memory controllerData_ = abi.encode(true, 100, true); // tryReentrancy = true, fetchedDynamicFee = 100, overrideDynamicFee = true
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
        bytes memory operateData_ = abi.encodeWithSelector(FluidDexV2D4SwapModule.swapIn.selector, swapInParams_);
        bytes memory result_ = dexV2.operate(DEX_TYPE, SWAP_MODULE_ID, operateData_);
        
        // Decode return: (uint256 amountOut, uint256 protocolFee, uint256 lpFee)
        (, , uint256 lpFee_) = abi.decode(result_, (uint256, uint256, uint256));
        
        // If reentrancy was caught, lpFee should be 0 (default), not 100 (from controller)
        assertEq(lpFee_, 0, "lpFee should be 0 - reentrancy should have been caught and default fee used");
        console2.log("Reentrancy test through fetchDynamicFeeForSwapIn passed - lpFee is 0 (default, not 100 from controller)");

        _clearPendingTransfers(address(USDT));
        _clearPendingTransfers(address(USDC));

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
        BorrowParams memory borrowParams_ = BorrowParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        _borrow(dexKey_, borrowParams_);

        // Switch on fetched dynamic fee
        vm.prank(address(mockController));
        dexV2.operate(DEX_TYPE, CONTROLLER_MODULE_ID, abi.encodeWithSelector(FluidDexV2D4ControllerModule.updateFetchDynamicFeeFlag.selector, dexKey_, true));

        // Attempt swapOut with reentrancy flag set to true
        // The MockController will try to reenter via _swapOut in fetchDynamicFeeForSwapOut
        // For D4, we use the special 3-parameter format for reentrancy testing
        bytes memory controllerData_ = abi.encode(true, 100, true); // tryReentrancy = true, fetchedDynamicFee = 100, overrideDynamicFee = true
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
        bytes memory operateData_ = abi.encodeWithSelector(FluidDexV2D4SwapModule.swapOut.selector, swapOutParams_);
        bytes memory result_ = dexV2.operate(DEX_TYPE, SWAP_MODULE_ID, operateData_);
        
        // Decode return: (uint256 amountIn, uint256 protocolFee, uint256 lpFee)
        (, , uint256 lpFee_) = abi.decode(result_, (uint256, uint256, uint256));
        
        // If reentrancy was caught, lpFee should be 0 (default), not 100 (from controller)
        assertEq(lpFee_, 0, "lpFee should be 0 - reentrancy should have been caught and default fee used");
        console2.log("Reentrancy test through fetchDynamicFeeForSwapOut passed - lpFee is 0 (default, not 100 from controller)");

        _clearPendingTransfers(address(USDT));
        _clearPendingTransfers(address(USDC));

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
        BorrowParams memory borrowParams_ = BorrowParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 100 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });
        _borrow(dexKey_, borrowParams_);

        // Clear any pending transfers from the liquidity addition
        _clearPendingTransfers(address(USDT));
        _clearPendingTransfers(address(USDC));

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
        _clearPendingTransfers(address(USDT));
        _clearPendingTransfers(address(USDC));
        
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

    // Comprehensive ETH/USDC gas comparison tests using cold storage for accurate measurements - D4
    function testEthGasSavingsComparison_Normal() public {
        console2.log("=== ETH/USDC Gas Comparison: Normal Swap (Cold Storage) - D4 ===");
        
        bytes memory setupData_ = abi.encodeWithSelector(this.shouldSetupEthPoolCallbackImplementation.selector);
        dexV2.startOperation(setupData_);
        
        bytes memory swapData_ = abi.encodeWithSelector(this.shouldMeasureEthNormalSwapGasCallbackImplementation.selector);
        dexV2.startOperation(swapData_);
        
        console2.log("=== ETH Normal Swap Test Completed (D4) ===");
    }
    
    function testEthGasSavingsComparison_Optimized() public {
        console2.log("=== ETH/USDC Gas Comparison: Optimized Swap (Cold Storage) - D4 ===");
        
        bytes memory setupData_ = abi.encodeWithSelector(this.shouldSetupEthPoolCallbackImplementation.selector);
        dexV2.startOperation(setupData_);
        
        bytes memory addTokensData_ = abi.encodeWithSelector(this.shouldAddEthTokensCallbackImplementation.selector);
        dexV2.startOperation(addTokensData_);
        
        bytes memory optimizedSwapData_ = abi.encodeWithSelector(this.shouldMeasureEthOptimizedSwapGasCallbackImplementation.selector);
        dexV2.startOperation(optimizedSwapData_);
        
        // Test comprehensive ETH functionality including rebalancing
        bytes memory comprehensiveData_ = abi.encodeWithSelector(this.shouldTestEthComprehensiveFunctionalityCallbackImplementation.selector);
        dexV2.startOperation(comprehensiveData_);
        
        console2.log("=== ETH Optimized Swap Test Completed (D4) ===");
    }

    // Setup callback for ETH/USDC pool initialization and liquidity (D4)
    function shouldSetupEthPoolCallbackImplementation() public returns (bytes memory returnData_) {
        _testEthPoolInitAndLiquidity();
        return returnData_;
    }

    // Callback for measuring ETH normal swap gas (cold storage) - D4
    function shouldMeasureEthNormalSwapGasCallbackImplementation() public returns (bytes memory returnData_) {
        DexKey memory dexKey_ = DexKey({
            token0: address(USDC), // USDC has lower address
            token1: NATIVE_TOKEN_ADDRESS, // ETH has higher address
            fee: 100,
            tickSpacing: 1,
            controller: address(0)
        });
        
        console2.log("=== Measuring ETH Normal Swap Gas (Cold Storage) - D4 ===");
        
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
        _clearPendingTransfers(NATIVE_TOKEN_ADDRESS);
        _clearPendingTransfers(address(USDC));
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

    // Callback for adding ETH tokens to DEX - D4
    function shouldAddEthTokensCallbackImplementation() public returns (bytes memory returnData_) {
        console2.log("=== Adding ETH Tokens to DEX - D4 ===");
        
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

    // Callback for measuring ETH optimized swap gas (cold storage) - D4
    function shouldMeasureEthOptimizedSwapGasCallbackImplementation() public returns (bytes memory returnData_) {
        DexKey memory dexKey_ = DexKey({
            token0: address(USDC), // USDC has lower address
            token1: NATIVE_TOKEN_ADDRESS, // ETH has higher address
            fee: 100,
            tickSpacing: 1,
            controller: address(0)
        });
        
        console2.log("=== Measuring ETH Optimized Swap Gas (Cold Storage) - D4 ===");
        
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
        _clearPendingTransfers(NATIVE_TOKEN_ADDRESS);
        _clearPendingTransfers(address(USDC));
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

    // Callback for comprehensive ETH functionality testing (additional swaps only, avoid rebalancing issue) - D4
    function shouldTestEthComprehensiveFunctionalityCallbackImplementation() public returns (bytes memory returnData_) {
        console2.log("=== Testing Comprehensive ETH Functionality - D4 ===");
        
        // Test additional swaps to demonstrate comprehensive ETH functionality
        _testEthSwaps();
        
        console2.log("=== Note: Rebalancing skipped to avoid ETH transfer issue to DexV2 contract ===");
        console2.log("=== Comprehensive ETH Testing Completed - D4 ===");
        
        return returnData_;
    }

    // ===================================
    // ETH/USDC POOL TESTS  
    // ===================================

    function _testEthPoolInitAndLiquidity() internal {
        DexKey memory dexKey_ = DexKey({
            token0: address(USDC), // USDC has lower address
            token1: NATIVE_TOKEN_ADDRESS, // ETH has higher address
            fee: 100, // 0.01%
            tickSpacing: 1,
            controller: address(0)
        });
        
        // Calculate sqrtPriceX96 for USDC/ETH at $4000 (1 USDC = 1/4000 ETH)
        uint256 priceX96 = uint256((1 << 96)) / 4000;
        uint256 usdcEthSqrtPriceX96 = FixedPointMathLib.sqrt(priceX96 * (1 << 96));
        console2.log("Calculated sqrtPriceX96:", _toString(usdcEthSqrtPriceX96));
        
        _initialize(dexKey_, usdcEthSqrtPriceX96);
        
        console2.log("=== ETH/USDC Pool Initialized at ~$4000 (D4) ===");
        
        // Get the actual current tick from the initialized price
        int24 currentTick = TM.getTickAtSqrtRatio(uint160(usdcEthSqrtPriceX96));
        console2.log("Current tick from sqrtPriceX96:", _toString(currentTick));
        
        // Update liquidity range to be around the actual current tick  
        int24 tickLower_ = currentTick - 50;
        int24 tickUpper_ = currentTick + 50;
        
        // Add initial liquidity near current tick via borrowing
        BorrowParams memory borrowParams_ = BorrowParams({
            dexKey: dexKey_,
            tickLower: tickLower_, // Current tick - 50
            tickUpper: tickUpper_, // Current tick + 50
            positionSalt: bytes32("0x1"),
            amount0: 2000 * 1e6, // 2000 USDC (token0)
            amount1: 0.5 ether, // 0.5 ETH (token1)
            amount0Min: 0,
            amount1Min: 0
        });
        
        // Fund contract with enough ETH and USDC for borrow repayment + settlement
        deal(address(this), 20 ether); // Extra ETH to cover borrow repayment
        deal(address(USDC), address(this), 5000 * 1e6); // Extra USDC to cover borrow repayment
        
        (uint256 amount0Added_, uint256 amount1Added_, , , uint256 liquidityAdded_) = _borrow(dexKey_, borrowParams_);
        
        console2.log("Borrowed USDC:", _toString(amount0Added_));
        console2.log("Borrowed ETH:", _toString(amount1Added_));
        console2.log("Liquidity added:", _toString(liquidityAdded_));
        
        // Clear pending transfers after liquidity addition
        _clearPendingTransfers(NATIVE_TOKEN_ADDRESS);
        _clearPendingTransfers(address(USDC));
    }

    function _testEthSwaps() internal {
        DexKey memory dexKey_ = DexKey({
            token0: address(USDC), // USDC has lower address
            token1: NATIVE_TOKEN_ADDRESS, // ETH has higher address
            fee: 100,
            tickSpacing: 1,
            controller: address(0)
        });
        
        console2.log("=== Testing ETH -> USDC Swap (D4) ===");
        
        // Swap 0.01 ETH for USDC (ETH is token1, USDC is token0) - smaller amount
        SwapInParams memory swapInParams_ = SwapInParams({
            dexKey: dexKey_,
            swap0To1: false, // ETH (token1) -> USDC (token0)
            amountIn: 0.01 ether,
            amountOutMin: 0,
            controllerData: "0x"
        });
        
        (uint256 usdcAmountOut_, uint256 protocolFee_, uint256 lpFee_) = _swapIn(dexKey_, swapInParams_);
        
        console2.log("ETH in:", _toString(uint256(0.01 ether)));
        console2.log("USDC out:", _toString(usdcAmountOut_));
        console2.log("Protocol fee:", _toString(protocolFee_));
        console2.log("LP fee:", _toString(lpFee_));
        
        // Settle ETH and USDC transfers
        _clearPendingTransfers(NATIVE_TOKEN_ADDRESS);
        _clearPendingTransfers(address(USDC));
        
        console2.log("=== Testing USDC -> ETH Swap (D4) ===");
        
        // Swap USDC back to ETH (USDC is token0, ETH is token1)
        SwapInParams memory swapInParams2_ = SwapInParams({
            dexKey: dexKey_,
            swap0To1: true, // USDC (token0) -> ETH (token1)
            amountIn: 100 * 1e6,
            amountOutMin: 0,
            controllerData: "0x"
        });
        
        (uint256 ethAmountOut_, , ) = _swapIn(dexKey_, swapInParams2_);
        
        console2.log("USDC in:", _toString(uint256(100 * 1e6)));
        console2.log("ETH out:", _toString(ethAmountOut_));
        
        // Settle transfers
        _clearPendingTransfers(NATIVE_TOKEN_ADDRESS);
        _clearPendingTransfers(address(USDC));
    }

    function _testEthAddTokensAndOptimization() internal {
        console2.log("=== Testing AddOrRemoveTokens with ETH (D4) ===");
        
        // Add ETH tokens to DEX
        uint256 ethToAdd_ = 0.5 ether;
        dexV2.addOrRemoveTokens{value: ethToAdd_}(NATIVE_TOKEN_ADDRESS, int256(ethToAdd_));
        console2.log("Added ETH to DEX:", _toString(ethToAdd_));
        
        // Add USDC tokens to DEX
        uint256 usdcToAdd_ = 500 * 1e6; // 500 USDC
        IERC20(address(USDC)).approve(address(dexV2), usdcToAdd_);
        dexV2.addOrRemoveTokens(address(USDC), int256(usdcToAdd_));
        console2.log("Added USDC to DEX:", _toString(usdcToAdd_));
        
        console2.log("=== Testing Optimized Swap with Pre-funded Tokens (D4) ===");
        
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
        uint256 gasAfterOptimizedSwap_ = gasleft();
        uint256 optimizedSwapGas_ = gasBeforeOptimizedSwap_ - gasAfterOptimizedSwap_;
        
        console2.log("Optimized swap gas:", _toString(optimizedSwapGas_));
        console2.log("ETH in (optimized):", _toString(uint256(0.05 ether)));
        console2.log("USDC out (optimized):", _toString(usdcOut3_));
        
        // Settle optimized swap
        _clearPendingTransfers(NATIVE_TOKEN_ADDRESS);
        _clearPendingTransfers(address(USDC));
    }

    function _testEthRebalanceAndPayback() internal {
        console2.log("=== Testing Rebalance (D4) ===");
        
        uint256 gasBeforeRebalance_ = gasleft();
        
        // Rebalance ETH and USDC
        dexV2.rebalance(NATIVE_TOKEN_ADDRESS);
        dexV2.rebalance(address(USDC));
        
        uint256 gasAfterRebalance_ = gasleft();
        uint256 rebalanceGas_ = gasBeforeRebalance_ - gasAfterRebalance_;
        
        console2.log("Rebalance gas used:", _toString(rebalanceGas_));
        
        console2.log("=== Testing Liquidity Payback (D4) ===");
        
        DexKey memory dexKey_ = DexKey({
            token0: address(USDC), // USDC has lower address
            token1: NATIVE_TOKEN_ADDRESS, // ETH has higher address
            fee: 100,
            tickSpacing: 1,
            controller: address(0)
        });
        
        // Calculate the same tick range used in borrow
        uint256 priceX96_ = uint256((1 << 96)) / 4000;
        uint256 usdcEthSqrtPriceX96_ = FixedPointMathLib.sqrt(priceX96_ * (1 << 96));
        int24 currentTick_ = TM.getTickAtSqrtRatio(uint160(usdcEthSqrtPriceX96_));
        int24 tickLower_ = currentTick_ - 50;
        int24 tickUpper_ = currentTick_ + 50;
        
        // Payback some liquidity from the same tight range
        PaybackParams memory paybackParams_ = PaybackParams({
            dexKey: dexKey_,
            tickLower: tickLower_, // Same as borrow range
            tickUpper: tickUpper_, // Same as borrow range
            positionSalt: bytes32("0x1"),
            amount0: 400 * 1e6, // Payback 400 USDC worth (token0)
            amount1: 0.1 ether, // Payback 0.1 ETH worth (token1)
            amount0Min: 0,
            amount1Min: 0
        });
        
        (uint256 usdcPayback_, uint256 ethPayback_, , , uint256 liquidityPayback_) = _payback(dexKey_, paybackParams_);
        
        console2.log("USDC payback:", _toString(usdcPayback_));
        console2.log("ETH payback:", _toString(ethPayback_));
        console2.log("Liquidity payback:", _toString(liquidityPayback_));
        
        // Final settlement
        _clearPendingTransfers(NATIVE_TOKEN_ADDRESS);
        _clearPendingTransfers(address(USDC));
    }

    // Ceiling division for unsigned integers
    function _ceilDiv(uint256 x, uint256 y) internal pure returns (uint256) {
        return x == 0 ? 0 : (x - 1) / y + 1;
    }

    // Local container for the "Right2000" scenarios
    struct Right2000Locals {
        // Pool key
        DexKey dexKey;

        // Ticks: current, lower, middle (for split), upper
        int24 currentTick;
        int24 tickLower;
        int24 tickMiddle;
        int24 tickUpper;

        // sqrt prices (Q96): current, lower, middle, upper
        uint160 sqrtPriceX96;
        uint160 sqrtPriceLowerX96;
        uint160 sqrtPriceMiddleX96;
        uint160 sqrtPriceUpperX96;

        // Target liquidity for logs (estimation)
        uint128 targetLiquidity;

        // Wide position: provided amounts and minted liquidity
        uint256 depositAmount0Wide;
        uint256 depositAmount1Wide;
        uint256 usedAmount0Wide;
        uint256 usedAmount1Wide;
        uint256 mintedLiquidityWide;

        // Split positions: actually used amounts and minted liquidity
        uint256 usedAmount0Range1;
        uint256 usedAmount1Range1;
        uint256 mintedLiquidityRange1;

        uint256 usedAmount0Range2;
        uint256 usedAmount1Range2;
        uint256 mintedLiquidityRange2;

        // Swap variables
        uint256 tokenOut_;
        uint256 feeProt_;
        uint256 feeLp_;
    }

    function should_Borrow_Swap_TryPayback_Right2000_oneWide() public returns (bytes memory) {
        Right2000Locals memory vars;

        // Initialize USDT/USDC pool
        vars.dexKey = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: 100,
            tickSpacing: 1,
            controller: address(0)
        });

        vars.currentTick = 0;
        // Wide range [1, 2001]
        vars.tickLower = 1;
        vars.tickUpper = 2001;

        // Compute sqrt prices (Q96)
        vars.sqrtPriceX96      = uint160(1 << 96);
        vars.sqrtPriceLowerX96 = TM.getSqrtRatioAtTick(vars.tickLower);
        vars.sqrtPriceUpperX96 = TM.getSqrtRatioAtTick(vars.tickUpper);

        // Set initial price S=1 (tick≈0)
        _initialize(vars.dexKey, vars.sqrtPriceX96); // √P=Q96 → P=1

        // Estimate target liquidity
        vars.targetLiquidity = LA.getLiquidityForAmounts(
            vars.sqrtPriceX96,
            vars.sqrtPriceLowerX96,
            vars.sqrtPriceUpperX96,
            100e6,
            0 // amount1 = 0, because sqrtPriceX96 < sqrtPriceLowerX96 for Uniswap math
        );
        console2.log("WIDE2000: targetLiquidity", _toString(int256(uint256(vars.targetLiquidity))));

        // With sqrtPriceX96 < sqrtPriceLowerX96, Uniswap math expects depositAmount0Wide > 0, depositAmount1Wide = 0.
        (vars.depositAmount0Wide, vars.depositAmount1Wide) = LA.getAmountsForLiquidity(
            vars.sqrtPriceX96,
            vars.sqrtPriceLowerX96,
            vars.sqrtPriceUpperX96,
            vars.targetLiquidity
        );
        console2.log("WIDE2000: depositAmount0Wide", _toString(int256(vars.depositAmount0Wide)));
        console2.log("WIDE2000: depositAmount1Wide", _toString(int256(vars.depositAmount1Wide)));

        // Borrow (LP-debt mint analogue)
        (vars.usedAmount0Wide, vars.usedAmount1Wide, , , vars.mintedLiquidityWide) = _borrow(
            vars.dexKey,
            BorrowParams({
                dexKey: vars.dexKey,
                tickLower: vars.tickLower,
                tickUpper: vars.tickUpper,
                positionSalt: bytes32("right-wide-2000"),
                amount0: 0,
                amount1: vars.depositAmount0Wide,
                amount0Min: 0,
                amount1Min: 0
            })
        );
        console2.log("WIDE2000: mintedLiquidityWide", _toString(int256(vars.mintedLiquidityWide)));
        console2.log("WIDE2000: usedAmount0Wide    ", _toString(int256(vars.usedAmount0Wide)));
        console2.log("WIDE2000: usedAmount1Wide    ", _toString(int256(vars.usedAmount1Wide)));

        _clearPendingTransfers(address(USDT));
        _clearPendingTransfers(address(USDC));

        {
            // Swap in the direction 1 → 0 of the placed liquidity.
            SwapInParams memory swapInParams_ = SwapInParams({
                dexKey: vars.dexKey,
                swap0To1: false,
                amountIn: vars.usedAmount1Wide,
                amountOutMin: 0,
                controllerData: "0x"
            });
            (vars.tokenOut_, vars.feeProt_, vars.feeLp_) = _swapIn(vars.dexKey, swapInParams_);
            console2.log("WIDE2000: swap tokenOut", _toString(int256(vars.tokenOut_)));
            console2.log("WIDE2000: swap protFee ", _toString(int256(vars.feeProt_)));
            console2.log("WIDE2000: swap lpFee   ", _toString(int256(vars.feeLp_)));
        }

        _clearPendingTransfers(address(USDT));
        _clearPendingTransfers(address(USDC));

        // An attempt to payback(close position) a position after the swapIn(moving the current price out of the price range) results in a reversal
        // when calculating _getReservesFromDebtAmounts / _getDebtAmountsFromReserves or 0 borrow amounts.
        // This prevents the removal of liquidity from the logic of the Uniswap position.

        PaybackParams memory paybackParams_ = PaybackParams({
            dexKey: vars.dexKey,
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            positionSalt: bytes32("right-wide-2000"),
            amount0: 0, // 0 or vars.depositAmount0Wide
            amount1: 0, // 0 or vars.depositAmount0Wide
            amount0Min: 0,
            amount1Min: 0
        });
        _payback(vars.dexKey, paybackParams_);
        _clearPendingTransfers(address(USDT));
        _clearPendingTransfers(address(USDC));


        // The reverse exchange confirms the availability of liquidity in the price range.
        {
            // Swap in the direction 0 → 1 of the placed liquidity.
            SwapInParams memory swapInParams_ = SwapInParams({
                dexKey: vars.dexKey,
                swap0To1: true,
                amountIn: vars.tokenOut_,
                amountOutMin: 0,
                controllerData: "0x"
            });
            (vars.tokenOut_, vars.feeProt_, vars.feeLp_) = _swapIn(vars.dexKey, swapInParams_);
            console2.log("WIDE2000: swap tokenOut", _toString(int256(vars.tokenOut_)));
            console2.log("WIDE2000: swap protFee ", _toString(int256(vars.feeProt_)));
            console2.log("WIDE2000: swap lpFee   ", _toString(int256(vars.feeLp_)));
        }
        _clearPendingTransfers(address(USDT));
        _clearPendingTransfers(address(USDC));

        // In the production pool, the authorized user initially creates a borrowed position,
        // and exchanges can transfer debt between tokens.
        // As result, the contract should make it possible to close all open debt positions,
        // remove tick liquidity from price ranges, and repay all debt to the liquidity layer,
        // which cannot be done in the current configuration due to the described behavior.

        return "";
    }

    function test_Borrow_Swap_TryPayback_Right2000_oneWide() public {
        bytes memory data_ = abi.encodeWithSelector(this.should_Borrow_Swap_TryPayback_Right2000_oneWide.selector);
        dexV2.startOperation(data_);
    }

    function should_Borrow_Swap_TryPayback_Right2000_twoRanges() public returns (bytes memory) {
        Right2000Locals memory vars;

        // Initialize USDT/USDC pool
        vars.dexKey = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: 100,
            tickSpacing: 1,
            controller: address(0)
        });

        // Two sub-ranges: [1,1001] and [1001,2001]
        vars.currentTick = 0;
        vars.tickLower = 1;
        vars.tickMiddle = 1001;
        vars.tickUpper = 2001;

        // Compute sqrt prices (Q96)
        vars.sqrtPriceX96 = uint160(1 << 96);
        vars.sqrtPriceLowerX96 = TM.getSqrtRatioAtTick(vars.tickLower);
        vars.sqrtPriceMiddleX96 = TM.getSqrtRatioAtTick(vars.tickMiddle);
        vars.sqrtPriceUpperX96 = TM.getSqrtRatioAtTick(vars.tickUpper);

        // Set initial price S=1 (tick≈0)
        _initialize(vars.dexKey, vars.sqrtPriceX96); // √P=Q96 → P=1

        // Reference metrics from test_Borrow_Swap_TryPayback_Right2000_oneWide (fixed from logs for replication)
        uint128 wideLiquidityRef = 950835601891; // targetLiquidity value
        uint256 amount1TotalRef = 99999997;     // depositAmount1Wide value
        console2.log("SPLIT2000: amount1TotalRef", _toString(int256(amount1TotalRef)));

        // Base proportional split by Δ√P across sub-ranges
        uint256 deltaAll = uint256(vars.sqrtPriceUpperX96) - uint256(vars.sqrtPriceLowerX96);
        uint256 deltaR1 = uint256(vars.sqrtPriceMiddleX96) - uint256(vars.sqrtPriceLowerX96);
        uint256 amount1ForR1 = _ceilDiv(amount1TotalRef * deltaR1, deltaAll);
        uint256 amount1ForR2 = amount1TotalRef - amount1ForR1;

        // The contract does not use the fully specified amount0, amount1.
        // Therefore, compensation for under-saturation (tunable multiplier).
        // IF amount0 > 0 & amount1 > 0 for wide and split test scenario under-saturation increases.
        // NOTE: K_NUM must be re-calibrated when pair/fee/range changes.
        uint256 K_NUM = 10_000_000_500_000;
        uint256 K_DEN = 10_000_000_000_000;
        amount1ForR1 = (amount1ForR1 * K_NUM) / K_DEN;
        amount1ForR2 = (amount1ForR2 * K_NUM) / K_DEN;
        console2.log("SPLIT2000: amount1ForR1", _toString(int256(amount1ForR1)));
        console2.log("SPLIT2000: amount1ForR2", _toString(int256(amount1ForR2)));

        // Sub-range [1,1001]
        (vars.usedAmount0Range1, vars.usedAmount1Range1,,, vars.mintedLiquidityRange1) = _borrow(
            vars.dexKey,
            BorrowParams({
                dexKey: vars.dexKey,
                tickLower: vars.tickLower,
                tickUpper: vars.tickMiddle,
                positionSalt: bytes32("right-1of2"),
                amount0: 0,
                amount1: amount1ForR1,
                amount0Min: 0,
                amount1Min: 0
            })
        );
        _clearPendingTransfers(address(USDT));
        _clearPendingTransfers(address(USDC));

        // Sub-range [1001,2001]
        (vars.usedAmount0Range2, vars.usedAmount1Range2,,, vars.mintedLiquidityRange2) = _borrow(
            vars.dexKey,
            BorrowParams({
                dexKey: vars.dexKey,
                tickLower: vars.tickMiddle,
                tickUpper: vars.tickUpper,
                positionSalt: bytes32("right-2of2"),
                amount0: 0,
                amount1: amount1ForR2,
                amount0Min: 0,
                amount1Min: 0
            })
        );

        // Logs and invariants
        console2.log("SPLIT2000: mintedLiquidityRange1", _toString(int256(vars.mintedLiquidityRange1)));
        console2.log("SPLIT2000: mintedLiquidityRange2", _toString(int256(vars.mintedLiquidityRange2)));
        console2.log("SPLIT2000: usedAmount0Range1", _toString(int256(vars.usedAmount0Range1)));
        console2.log("SPLIT2000: usedAmount0Range2", _toString(int256(vars.usedAmount0Range2)));
        console2.log("SPLIT2000: usedAmount1Range1", _toString(int256(vars.usedAmount1Range1)));
        console2.log("SPLIT2000: usedAmount1Range2", _toString(int256(vars.usedAmount1Range2)));
        console2.log(
            "SPLIT2000: amount1TotalRef - usedAmount1Range1 - usedAmount1Range2",
            _toString(int256(amount1TotalRef) - int256(vars.usedAmount1Range1) - int256(vars.usedAmount1Range2))
        );

        // On the right side of the price we expect token0 to be unused in both splits
        assertEq(vars.usedAmount0Range1, 0, "split[1]: token0 must be 0");
        assertEq(vars.usedAmount0Range2, 0, "split[2]: token0 must be 0");

        // Liquidity profile should approximately match the wide case (allow rounding/convert deltas)
        // 3% tolerance
        assertApproxEqRel(vars.mintedLiquidityRange1, wideLiquidityRef, 3e16, "L_R1 ~ L_wide");
        assertApproxEqRel(vars.mintedLiquidityRange2, wideLiquidityRef, 3e16, "L_R2 ~ L_wide");

        // K_NUM is selected so that the amount of tokens used is completely identical for the wide and split scenarios.
        // Conservation of input amount1: sum of actually used equals wide amount1_used
        assertApproxEqAbs(
            int256(vars.usedAmount1Range1 + vars.usedAmount1Range2),
            int256(amount1TotalRef),
            0,
            "sum(usedAmount1Range{0,1}) != amount1TotalRef"
        );
        _clearPendingTransfers(address(USDT));
        _clearPendingTransfers(address(USDC));

        // Same swap pattern to verify behavior parity
        {
            SwapInParams memory swapInParams_ = SwapInParams({
                dexKey: vars.dexKey,
                swap0To1: false,
                amountIn: amount1TotalRef,
                amountOutMin: 0,
                controllerData: "0x"
            });
            (vars.tokenOut_, vars.feeProt_, vars.feeLp_) = _swapIn(vars.dexKey, swapInParams_);
            console2.log("SPLIT2000: swap tokenOut", _toString(int256(vars.tokenOut_)));
            console2.log("SPLIT2000: swap protFee ", _toString(int256(vars.feeProt_)));
            console2.log("SPLIT2000: swap lpFee   ", _toString(int256(vars.feeLp_)));
        }
        _clearPendingTransfers(address(USDT));
        _clearPendingTransfers(address(USDC));

        // An attempt to payback(close position) a position after the swapIn(moving the current price out of the price range) results in a reversal
        // when calculating _getReservesFromDebtAmounts / _getDebtAmountsFromReserves or 0 borrow amounts.
        // This prevents the removal of liquidity from the logic of the Uniswap position.
        PaybackParams memory paybackParams_ = PaybackParams({
            dexKey: vars.dexKey,
            tickLower: vars.tickLower,
            tickUpper: vars.tickMiddle,
            positionSalt: bytes32("right-1of2"),
            amount0: 0,             // 0 or amount1ForR1
            amount1: amount1ForR1,  // 0 or amount1ForR1
            amount0Min: 0,
            amount1Min: 0
        });
        _payback(vars.dexKey, paybackParams_);
        _clearPendingTransfers(address(USDT));
        _clearPendingTransfers(address(USDC));

        paybackParams_ = PaybackParams({
            dexKey: vars.dexKey,
            tickLower: vars.tickMiddle,
            tickUpper: vars.tickUpper,
            positionSalt: bytes32("right-2of2"),
            amount0: 0,             // 0 or amount1ForR2
            amount1: amount1ForR2,  // 0 or amount1ForR1
            amount0Min: 0,
            amount1Min: 0
        });
        _payback(vars.dexKey, paybackParams_);
        _clearPendingTransfers(address(USDT));
        _clearPendingTransfers(address(USDC));

        // The reverse exchange confirms the availability of liquidity in the price range.
        {
            // Swap in the direction 0 → 1 of the placed liquidity.
            SwapInParams memory swapInParams_ = SwapInParams({
                dexKey: vars.dexKey,
                swap0To1: true,
                amountIn: vars.tokenOut_,
                amountOutMin: 0,
                controllerData: "0x"
            });
            (vars.tokenOut_, vars.feeProt_, vars.feeLp_) = _swapIn(vars.dexKey, swapInParams_);
            console2.log("SPLIT2000: swap tokenOut", _toString(int256(vars.tokenOut_)));
            console2.log("SPLIT2000: swap protFee ", _toString(int256(vars.feeProt_)));
            console2.log("SPLIT2000: swap lpFee   ", _toString(int256(vars.feeLp_)));
        }
        _clearPendingTransfers(address(USDT));
        _clearPendingTransfers(address(USDC));

        // In the production pool, the authorized user initially creates a borrowed position,
        // and exchanges can transfer debt between tokens.
        // As result, the contract should make it possible to close all open debt positions,
        // remove tick liquidity from price ranges, and repay all debt to the liquidity layer,
        // which cannot be done in the current configuration due to the described behavior.

        return "";
    }

    function test_Borrow_Swap_TryPayback_Right2000_twoRanges() public {
        bytes memory data_ = abi.encodeWithSelector(this.should_Borrow_Swap_TryPayback_Right2000_twoRanges.selector);
        dexV2.startOperation(data_);
    }

    /* USDT and USDC balances have to be checked separately due to StackTooDeepException */
    function shouldBorrowPayback__LiquidityNotSettled() public returns (bytes memory returnData_) {
        DexKey memory dexKey_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: 100,
            tickSpacing: 1,
            controller: address(0)
        });
        _initialize(dexKey_, (1 << 96));

        BorrowParams memory borrowParams_ = BorrowParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,
            amount1: 200 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });

        console2.log("===== initial balances =====");
        uint32 initialUserBalanceUSDT = uint32(USDT.balanceOf(address(this)));
        uint32 initialDexBalanceUSDT = uint32(USDT.balanceOf(address(dexV2)));
        uint32 initialLiquidityBalanceUSDT = uint32(USDT.balanceOf(address(liquidity)));
        // uint32 initialUserBalanceUSDC = uint32(USDC.balanceOf(address(this)));
        // uint32 initialDexBalanceUSDC = uint32(USDC.balanceOf(address(dexV2)));
        // uint32 initialLiquidityBalanceUSDC = uint32(USDC.balanceOf(address(liquidity)));

        console2.log("user USDT balance", _toString(initialUserBalanceUSDT));
        console2.log("dex USDT balance", _toString(initialDexBalanceUSDT));
        console2.log("liquidity USDT balance", _toString(initialLiquidityBalanceUSDT));
        // console2.log("user USDC balance", _toString(initialUserBalanceUSDC));
        // console2.log("dex USDC balance", _toString(initialDexBalanceUSDC));
        // console2.log("liquidity USDC balance", _toString(initialLiquidityBalanceUSDC));
        console2.log();

        (uint256 amount0_, uint256 amount1_, , , uint256 liquidityIncreaseRaw_) = _borrow(dexKey_, borrowParams_);

        console2.log("[borrow] amount0_", _toString(amount0_));
        console2.log("[borrow] amount1_", _toString(amount1_));
        // console2.log("[borrow] feeAccruedToken0_", _toString(feeAccruedToken0_));
        // console2.log("[borrow] feeAccruedToken1_", _toString(feeAccruedToken1_));
        console2.log("[borrow] liquidityIncreaseRaw_", _toString(liquidityIncreaseRaw_));
        console2.log();

        // console2.log("----- USDT settle -----");
        // _clearPendingTransfers(address(USDT));
        // console2.log("----- USDC settle -----");
        // _clearPendingTransfers(address(USDC));
        // console2.log();

        // console2.log("===== balances after borrow =====");
        // console2.log("user USDT balance", _toString(USDT.balanceOf(address(this))));
        // console2.log("dex USDT balance", _toString(USDT.balanceOf(address(dexV2))));
        // console2.log("liquidity USDT balance", _toString(USDT.balanceOf(address(liquidity))));
        // console2.log("user USDC balance", _toString(USDC.balanceOf(address(this))));
        // console2.log("dex USDC balance", _toString(USDC.balanceOf(address(dexV2))));
        // console2.log("liquidity USDC balance", _toString(USDC.balanceOf(address(liquidity))));
        // console2.log();

        PaybackParams memory paybackParams_ = PaybackParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 100 * 1e6,      // payback all borrowed tokens
            amount1: 100 * 1e6,      // payback all borrowed tokens
            amount0Min: 0,
            amount1Min: 0
        });

        uint256 liquidityDecreaseRaw_;
        (amount0_, amount1_, , , liquidityDecreaseRaw_) = _payback(dexKey_, paybackParams_);

        console2.log("[payback] amount0_", _toString(amount0_));
        console2.log("[payback] amount1_", _toString(amount1_));
        // console2.log("[payback] feeAccruedToken0_", _toString(feeAccruedToken0_));
        // console2.log("[payback] feeAccruedToken1_", _toString(feeAccruedToken1_));
        console2.log("[payback] liquidityDecreaseRaw_", _toString(liquidityDecreaseRaw_));
        console2.log();

        _clearPendingTransfers(address(USDT));
        _clearPendingTransfers(address(USDC));
        console2.log();

        console2.log("===== balances after payback =====");
        uint32 resultUserBalanceUSDT = uint32(USDT.balanceOf(address(this)));
        uint32 resultDexBalanceUSDT = uint32(USDT.balanceOf(address(dexV2)));
        uint32 resultLiquidityBalanceUSDT = uint32(USDT.balanceOf(address(liquidity)));
        // uint32 resultUserBalanceUSDC = uint32(USDC.balanceOf(address(this)));
        // uint32 resultDexBalanceUSDC = uint32(USDC.balanceOf(address(dexV2)));
        // uint32 resultLiquidityBalanceUSDC = uint32(USDC.balanceOf(address(liquidity)));


        // checking settled balances and remaining liquidity
        console2.log("user USDT balance", _toString(resultUserBalanceUSDT));
        console2.log("dex USDT balance", _toString(resultDexBalanceUSDT));
        console2.log("liquidity USDT balance", _toString(resultLiquidityBalanceUSDT));
        // console2.log("user USDC balance", _toString(resultUserBalanceUSDC));
        // console2.log("dex USDC balance", _toString(resultDexBalanceUSDC));
        // console2.log("liquidity USDC balance", _toString(resultLiquidityBalanceUSDC));
        
        // assertEq(initialUserBalanceUSDT, resultUserBalanceUSDT);
        // assertEq(initialDexBalanceUSDT, resultDexBalanceUSDT);
        // assertEq(initialLiquidityBalanceUSDT, resultLiquidityBalanceUSDT);
        // assertEq(initialUserBalanceUSDC, resultUserBalanceUSDC);
        // assertEq(initialDexBalanceUSDC, resultDexBalanceUSDC);
        // assertEq(initialLiquidityBalanceUSDC, resultLiquidityBalanceUSDC);

        // assertEq(liquidityIncreaseRaw_ - liquidityDecreaseRaw_, 267281);
    }

    function testBorrowPayback__LiquidityNotSettled() public {
        bytes memory data_ = abi.encodeWithSelector(this.shouldBorrowPayback__LiquidityNotSettled.selector);
        dexV2.startOperation(data_);
    }


    function shouldBorrowPayback__FullSettleWithoutWinningSideOperations() public returns (bytes memory returnData_) {
        DexKey memory dexKey_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: 100,
            tickSpacing: 1,
            controller: address(0)
        });
        _initialize(dexKey_, (1 << 96));
    
        BorrowParams memory borrowParams_ = BorrowParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 200 * 1e6,
            amount1: 300 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });

        console2.log("===== initial balances =====");
        uint32 initialUserBalanceUSDT = uint32(USDT.balanceOf(address(this)));
        uint32 initialDexBalanceUSDT = uint32(USDT.balanceOf(address(dexV2)));
        uint32 initialLiquidityBalanceUSDT = uint32(USDT.balanceOf(address(liquidity)));
        // uint32 initialUserBalanceUSDC = uint32(USDC.balanceOf(address(this)));
        // uint32 initialDexBalanceUSDC = uint32(USDC.balanceOf(address(dexV2)));
        // uint32 initialLiquidityBalanceUSDC = uint32(USDC.balanceOf(address(liquidity)));

        console2.log("user USDT balance", _toString(initialUserBalanceUSDT));
        console2.log("dex USDT balance", _toString(initialDexBalanceUSDT));
        console2.log("liquidity USDT balance", _toString(initialLiquidityBalanceUSDT));
        // console2.log("user USDC balance", _toString(initialUserBalanceUSDC));
        // console2.log("dex USDC balance", _toString(initialDexBalanceUSDC));
        // console2.log("liquidity USDC balance", _toString(initialLiquidityBalanceUSDC));
        console2.log();

        (uint256 amount0_, uint256 amount1_, , , uint256 liquidityIncreaseRaw_) = _borrow(dexKey_, borrowParams_);

        console2.log("[borrow] amount0_", _toString(amount0_));
        console2.log("[borrow] amount1_", _toString(amount1_));
        // console2.log("[borrow] feeAccruedToken0_", _toString(feeAccruedToken0_));
        // console2.log("[borrow] feeAccruedToken1_", _toString(feeAccruedToken1_));
        console2.log("[borrow] liquidityIncreaseRaw_", _toString(liquidityIncreaseRaw_));
        console2.log();

        PaybackParams memory paybackParams_ = PaybackParams({
            dexKey: dexKey_,
            tickLower: -100,
            tickUpper: 100,
            positionSalt: bytes32("0x1"),
            amount0: 200 * 1e6,
            amount1: 300 * 1e6,
            amount0Min: 0,
            amount1Min: 0
        });

        uint256 liquidityDecreaseRaw_;
        (amount0_, amount1_, , , liquidityDecreaseRaw_) = _payback(dexKey_, paybackParams_);

        console2.log("[payback] amount0_", _toString(amount0_));
        console2.log("[payback] amount1_", _toString(amount1_));
        // console2.log("[payback] feeAccruedToken0_", _toString(feeAccruedToken0_));
        // console2.log("[payback] feeAccruedToken1_", _toString(feeAccruedToken1_));
        console2.log("[payback] liquidityDecreaseRaw_", _toString(liquidityDecreaseRaw_));
        console2.log();

        _clearPendingTransfers(address(USDT));
        _clearPendingTransfers(address(USDC));
        console2.log();

        console2.log("===== balances after payback =====");
        uint32 resultUserBalanceUSDT = uint32(USDT.balanceOf(address(this)));
        uint32 resultDexBalanceUSDT = uint32(USDT.balanceOf(address(dexV2)));
        uint32 resultLiquidityBalanceUSDT = uint32(USDT.balanceOf(address(liquidity)));
        // uint32 resultUserBalanceUSDC = uint32(USDC.balanceOf(address(this)));
        // uint32 resultDexBalanceUSDC = uint32(USDC.balanceOf(address(dexV2)));
        // uint32 resultLiquidityBalanceUSDC = uint32(USDC.balanceOf(address(liquidity)));

        // // checking settled balances and remaining liquidity
        console2.log("user USDT balance", _toString(resultUserBalanceUSDT));
        console2.log("dex USDT balance", _toString(resultDexBalanceUSDT));
        console2.log("liquidity USDT balance", _toString(resultLiquidityBalanceUSDT));
        // console2.log("user USDC balance", _toString(resultUserBalanceUSDC));
        // console2.log("dex USDC balance", _toString(resultDexBalanceUSDC));
        // console2.log("liquidity USDC balance", _toString(resultLiquidityBalanceUSDC));
        
        // assertEq(initialUserBalanceUSDT, resultUserBalanceUSDT);
        // assertEq(initialDexBalanceUSDT, resultDexBalanceUSDT);
        // assertEq(initialLiquidityBalanceUSDT, resultLiquidityBalanceUSDT);
        // assertEq(initialUserBalanceUSDC, resultUserBalanceUSDC);
        // assertEq(initialDexBalanceUSDC, resultDexBalanceUSDC);
        // assertEq(initialLiquidityBalanceUSDC, resultLiquidityBalanceUSDC);

        // check for position removed
        // assertEq(liquidityIncreaseRaw_, liquidityDecreaseRaw_);
    }

    function testBorrowPayback__FullSettleWithoutWinningSideOperations() public {
        bytes memory data_ = abi.encodeWithSelector(this.shouldBorrowPayback__FullSettleWithoutWinningSideOperations.selector);
        dexV2.startOperation(data_);
    }

    function shouldBorrowPayback__AsymmetricalLiquidityCalcs() public returns (bytes memory returnData_) {
        DexKey memory dexKey_ = DexKey({
            token0: address(USDT),
            token1: address(USDC),
            fee: 100,
            tickSpacing: 1,
            controller: address(0)
        });
        _initialize(dexKey_, (1 << 96));
        uint256 snapshotId = vm.snapshot();

        // uint32 initialUserBalanceUSDT = uint32(USDT.balanceOf(address(this)));
        // uint32 initialDexBalanceUSDT = uint32(USDT.balanceOf(address(dexV2)));
        // uint32 initialLiquidityBalanceUSDT = uint32(USDT.balanceOf(address(liquidity)));
        // uint32 initialUserBalanceUSDC = uint32(USDC.balanceOf(address(this)));
        // uint32 initialDexBalanceUSDC = uint32(USDC.balanceOf(address(dexV2)));
        // uint32 initialLiquidityBalanceUSDC = uint32(USDC.balanceOf(address(liquidity)));

        assertEq(USDT.balanceOf(address(dexV2)), USDC.balanceOf(address(dexV2)));
        assertEq(USDT.balanceOf(address(liquidity)), USDC.balanceOf(address(liquidity)));

        uint32 amountBorrowed1;
        uint32 amountBorrowed2;

        uint64 liquidityIncreaseRaw1_;
        uint64 liquidityIncreaseRaw2_;
        uint256 liquidityDecreaseRaw1_;
        uint256 liquidityDecreaseRaw2_;

        // 1st borrow and payback
        // call borrow with amounts 100 USDT and 200 USDC
        {
            BorrowParams memory borrowParams_ = BorrowParams({
                dexKey: dexKey_,
                tickLower: -100,
                tickUpper: 100,
                positionSalt: bytes32("0x1"),
                amount0: 100 * 1e6,
                amount1: 200 * 1e6,
                amount0Min: 0,
                amount1Min: 0
            });

            (uint256 amount0_, uint256 amount1_, , , uint256 liquidityIncreaseRaw_) = _borrow(dexKey_, borrowParams_);
            liquidityIncreaseRaw1_ = uint64(liquidityIncreaseRaw_);

            console2.log("[borrow] amount0_", _toString(amount0_));
            console2.log("[borrow] amount1_", _toString(amount1_));
            console2.log("[borrow] liquidityIncreaseRaw1_", _toString(liquidityIncreaseRaw1_));
            console2.log();

            assertEq(amount0_, amount1_);
            amountBorrowed1 = uint32(amount0_);

            PaybackParams memory paybackParams_ = PaybackParams({
                dexKey: dexKey_,
                tickLower: -100,
                tickUpper: 100,
                positionSalt: bytes32("0x1"),
                amount0: 100 * 1e6,      // payback all borrowed tokens
                amount1: 100 * 1e6,      // payback all borrowed tokens
                amount0Min: 0,
                amount1Min: 0
            });

            (amount0_, amount1_, , , liquidityDecreaseRaw1_) = _payback(dexKey_, paybackParams_);

            console2.log("[payback] amount0_", _toString(amount0_));
            console2.log("[payback] amount1_", _toString(amount1_));
            console2.log("[payback] liquidityDecreaseRaw1_", _toString(liquidityDecreaseRaw1_));
            console2.log();

            _clearPendingTransfers(address(USDT));
            _clearPendingTransfers(address(USDC));
            console2.log();
        }

        vm.revertTo(snapshotId);

        assertEq(USDT.balanceOf(address(dexV2)), USDC.balanceOf(address(dexV2)));
        assertEq(USDT.balanceOf(address(liquidity)), USDC.balanceOf(address(liquidity)));

        // 2nd borrow and payback
        // call borrow with amounts 200 USDT and 100 USDC
        {
            BorrowParams memory borrowParams_ = BorrowParams({
                dexKey: dexKey_,
                tickLower: -100,
                tickUpper: 100,
                positionSalt: bytes32("0x1"),
                amount0: 200 * 1e6,
                amount1: 100 * 1e6,
                amount0Min: 0,
                amount1Min: 0
            });

            (uint256 amount0_, uint256 amount1_, , , uint256 liquidityIncreaseRaw_) = _borrow(dexKey_, borrowParams_);
            liquidityIncreaseRaw2_ = uint64(liquidityIncreaseRaw_);

            console2.log("[borrow] amount0_", _toString(amount0_));
            console2.log("[borrow] amount1_", _toString(amount1_));
            console2.log("[borrow] liquidityIncreaseRaw2_", _toString(liquidityIncreaseRaw2_));
            console2.log();

            assertEq(amount0_, amount1_);
            amountBorrowed2 = uint32(amount0_);

            PaybackParams memory paybackParams_ = PaybackParams({
                dexKey: dexKey_,
                tickLower: -100,
                tickUpper: 100,
                positionSalt: bytes32("0x1"),
                amount0: 100 * 1e6,      // payback all borrowed tokens
                amount1: 100 * 1e6,      // payback all borrowed tokens
                amount0Min: 0,
                amount1Min: 0
            });

            (amount0_, amount1_, , , liquidityDecreaseRaw2_) = _payback(dexKey_, paybackParams_);

            console2.log("[payback] amount0_", _toString(amount0_));
            console2.log("[payback] amount1_", _toString(amount1_));
            console2.log("[payback] liquidityDecreaseRaw2_", _toString(liquidityDecreaseRaw2_));
            console2.log();

            _clearPendingTransfers(address(USDT));
            _clearPendingTransfers(address(USDC));
            console2.log();
        }

        // uint32 resultUserBalanceUSDT = uint32(USDT.balanceOf(address(this)));
        // uint32 resultDexBalanceUSDT = uint32(USDT.balanceOf(address(dexV2)));
        // uint32 resultLiquidityBalanceUSDT = uint32(USDT.balanceOf(address(liquidity)));
        // uint32 resultUserBalanceUSDC = uint32(USDC.balanceOf(address(this)));
        // uint32 resultDexBalanceUSDC = uint32(USDC.balanceOf(address(dexV2)));
        // uint32 resultLiquidityBalanceUSDC = uint32(USDC.balanceOf(address(liquidity)));
        
        // assertEq(initialUserBalanceUSDT, resultUserBalanceUSDT);
        // assertEq(initialDexBalanceUSDT, resultDexBalanceUSDT);
        // assertEq(initialLiquidityBalanceUSDT, resultLiquidityBalanceUSDT);
        // assertEq(initialUserBalanceUSDC, resultUserBalanceUSDC);
        // assertEq(initialDexBalanceUSDC, resultDexBalanceUSDC);
        // assertEq(initialLiquidityBalanceUSDC, resultLiquidityBalanceUSDC);

        // equal borrowed amounts
        // assertEq(amountBorrowed1, amountBorrowed2);

        // not equal liquidity calcs
        // assertEq(liquidityIncreaseRaw1_ - liquidityIncreaseRaw2_, 401);
        // assertEq(liquidityDecreaseRaw1_, liquidityDecreaseRaw2_);
        // assertNotEq(liquidityIncreaseRaw1_ - liquidityDecreaseRaw1_, liquidityIncreaseRaw2_ - liquidityDecreaseRaw2_);
    }

    function testBorrowPayback__AsymmetricalLiquidityCalcs() public {
        bytes memory data_ = abi.encodeWithSelector(this.shouldBorrowPayback__AsymmetricalLiquidityCalcs.selector);
        dexV2.startOperation(data_);
    }
}
