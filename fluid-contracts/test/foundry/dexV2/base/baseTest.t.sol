//SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { DexV2BaseSetup } from "../baseSetup.t.sol";
import { MockDexV2TypeImplementation } from "../../../../contracts/mocks/mockDexV2TypeImplementation.sol";
import { PendingTransfers } from "../../../../contracts/libraries/pendingTransfers.sol";

// NOTE: These are very basic tests for dexV2 base. Most things are tested in the other tests (d3, d4 tests)

contract DexV2BaseTest is DexV2BaseSetup {
    using SafeERC20 for IERC20;

    MockDexV2TypeImplementation public mockDexV2TypeImplementation;
    bool public shouldAttemptReentrancy;

    // Use a unique dex type for the mock (not 3 or 4 which are used by real implementations)
    uint256 internal constant MOCK_DEX_TYPE = 99;
    uint256 internal constant MOCK_IMPLEMENTATION_ID = 1;

    function setUp() public virtual override {
        super.setUp();
        // Deploy mock implementation with the mock dex type
        mockDexV2TypeImplementation = new MockDexV2TypeImplementation(MOCK_DEX_TYPE, address(liquidity));
        
        // Register the mock as an admin implementation
        vm.prank(admin);
        dexV2.updateDexTypeToAdminImplementation(MOCK_DEX_TYPE, MOCK_IMPLEMENTATION_ID, address(mockDexV2TypeImplementation));
    }

    // Override dexCallback to attempt reentrancy
    function dexCallback(address token_, address to_, uint256 amount_) external override {
        if (shouldAttemptReentrancy) {
            // Attempt to reenter settle function - this should revert due to reentrancy lock
            dexV2.settle(address(USDC), 0, 0, 0, address(this), false);
        }
        // Call the original callback - transfer tokens
        IERC20(token_).safeTransfer(to_, amount_);
    }

    function testSetup() public view {
        assertNotEq(address(dexV2), address(0));
        assertNotEq(address(mockDexV2TypeImplementation), address(0));
        // Verify mock implementation is registered
        assertEq(_getDexTypeToAdminImplementation(MOCK_DEX_TYPE, MOCK_IMPLEMENTATION_ID), address(mockDexV2TypeImplementation));
    }

    function shouldFailIfPendingSupplyCallbackImplementation() public returns (bytes memory) {
        bytes memory operateData_ = abi.encodeWithSelector(
            MockDexV2TypeImplementation.operate.selector,
            address(USDC), // supplyToken_
            int256(1e6), // supplyAmount_ (positive for supply)
            address(0), // borrowToken_
            int256(0) // borrowAmount_
        );

        // Use operateAdmin with the registered mock implementation
        bytes memory returnData_ = dexV2.operateAdmin(MOCK_DEX_TYPE, MOCK_IMPLEMENTATION_ID, operateData_);

        return returnData_;
    }

    function testShouldFailIfPendingSupply() public {
        // PendingTransfersNotCleared now has a bytes parameter, so we check the selector manually
        bytes memory data_ = abi.encodeWithSelector(this.shouldFailIfPendingSupplyCallbackImplementation.selector);
        (bool success, bytes memory returnData) = address(dexV2).call(
            abi.encodeWithSelector(dexV2.startOperation.selector, data_)
        );
        assertFalse(success, "Should have reverted");
        // Verify it reverted with PendingTransfersNotCleared error
        bytes4 errorSelector = bytes4(returnData);
        assertEq(errorSelector, PendingTransfers.PendingTransfersNotCleared.selector, "Wrong error selector");
    }

    function shouldFailIfPendingWithdrawCallbackImplementation() public returns (bytes memory) {
        bytes memory operateData_ = abi.encodeWithSelector(
            MockDexV2TypeImplementation.operate.selector,
            address(USDC), // supplyToken_
            -int256(1e6), // supplyAmount_ (negative for withdraw)
            address(0), // borrowToken_
            int256(0) // borrowAmount_
        );

        // Use operateAdmin with the registered mock implementation
        bytes memory returnData_ = dexV2.operateAdmin(MOCK_DEX_TYPE, MOCK_IMPLEMENTATION_ID, operateData_);

        return returnData_;
    }

    function testShouldFailIfPendingWithdraw() public {
        // PendingTransfersNotCleared now has a bytes parameter, so we check the selector manually
        bytes memory data_ = abi.encodeWithSelector(this.shouldFailIfPendingWithdrawCallbackImplementation.selector);
        (bool success, bytes memory returnData) = address(dexV2).call(
            abi.encodeWithSelector(dexV2.startOperation.selector, data_)
        );
        assertFalse(success, "Should have reverted");
        // Verify it reverted with PendingTransfersNotCleared error
        bytes4 errorSelector = bytes4(returnData);
        assertEq(errorSelector, PendingTransfers.PendingTransfersNotCleared.selector, "Wrong error selector");
    }

    function shouldFailOnReentrancyCallbackImplementation() public returns (bytes memory) {
        // This callback attempts to call startOperation again, which should revert
        vm.expectRevert();
        dexV2.startOperation("");
        
        return "";
    }

    function testShouldFailOnReentrancy() public {
        // Test reentrancy protection - the revert expectation is inside the callback
        bytes memory data_ = abi.encodeWithSelector(this.shouldFailOnReentrancyCallbackImplementation.selector);
        dexV2.startOperation(data_);
    }

    function shouldAttemptReentrancyViaCallbackImplementation() public returns (bytes memory) {
        // Enable reentrancy attempt in the dexCallback
        shouldAttemptReentrancy = true;
        
        // Set up some pending amounts by calling operateAdmin
        bytes memory operateData_ = abi.encodeWithSelector(
            MockDexV2TypeImplementation.operate.selector,
            address(USDC), // supplyToken_
            int256(1e6), // supplyAmount_ (positive for supply)
            address(0), // borrowToken_
            int256(0) // borrowAmount_
        );

        dexV2.operateAdmin(MOCK_DEX_TYPE, MOCK_IMPLEMENTATION_ID, operateData_);

        // Try to settle with callback - the callback will attempt reentrancy
        // This should revert because the dexCallback will try to call settle again
        dexV2.settle(address(USDC), int256(1e6), 0, 0, address(this), true);
        
        return "";
    }

    function testShouldFailOnSettleReentrancyViaCallback() public {
        // This test should fail because the reentrancy attempt in dexCallback should revert
        vm.expectRevert();
        bytes memory data_ = abi.encodeWithSelector(this.shouldAttemptReentrancyViaCallbackImplementation.selector);
        dexV2.startOperation(data_);
    }
}
