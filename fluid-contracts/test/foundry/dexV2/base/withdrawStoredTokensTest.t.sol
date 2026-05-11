//SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { DexV2BaseSetup } from "../baseSetup.t.sol";
import { DexV2BaseSlotsLink } from "../../../../contracts/libraries/dexV2BaseSlotsLink.sol";
import { MockDexV2TypeImplementation } from "../../../../contracts/mocks/mockDexV2TypeImplementation.sol";

error FluidDexV2Error(uint256 errorId_);

event LogSettle(
    address user,
    address token,
    int256 supplyAmount,
    int256 borrowAmount,
    int256 storeAmount,
    address to
);

contract WithdrawStoredTokensTest is DexV2BaseSetup {
    using SafeERC20 for IERC20;

    uint256 internal constant ERROR_DexV2Main__OperateAmountsZero = 201002;
    uint256 internal constant ERROR_DexV2Main__InsufficientStoredTokenAmount = 201014;
    uint256 internal constant MOCK_DEX_TYPE = 99;
    uint256 internal constant MOCK_IMPLEMENTATION_ID = 1;

    MockDexV2TypeImplementation public mockDexV2TypeImplementation;

    function setUp() public virtual override {
        super.setUp();

        mockDexV2TypeImplementation = new MockDexV2TypeImplementation(MOCK_DEX_TYPE, address(liquidity));

        vm.prank(admin);
        dexV2.updateDexTypeToAdminImplementation(MOCK_DEX_TYPE, MOCK_IMPLEMENTATION_ID, address(mockDexV2TypeImplementation));
    }

    // ═══════════════════════════════════════════════════════════════
    //                     Storage helpers
    // ═══════════════════════════════════════════════════════════════

    function _getStoredTokenSlot(address user_, address token_) internal pure returns (bytes32) {
        return DexV2BaseSlotsLink.calculateTripleMappingStorageSlot(
            DexV2BaseSlotsLink.DEX_V2_USER_STORED_TOKEN_AMOUNT_MAPPING_SLOT,
            BASE_SLOT,
            bytes32(uint256(uint160(user_))),
            bytes32(uint256(uint160(token_)))
        );
    }

    function _setStoredTokenAmount(address user_, address token_, uint256 amount_) internal {
        bytes32 slot_ = _getStoredTokenSlot(user_, token_);
        vm.store(address(dexV2), slot_, bytes32(amount_));
    }

    function _getStoredTokenAmount(address user_, address token_) internal view returns (uint256) {
        bytes32 slot_ = _getStoredTokenSlot(user_, token_);
        return dexV2.readFromStorage(slot_);
    }

    function _addPendingWithdraw(address token_, uint256 amount_) internal {
        bytes memory operateData_ = abi.encodeWithSelector(
            MockDexV2TypeImplementation.operate.selector,
            token_,
            -int256(amount_),
            address(0),
            int256(0)
        );

        dexV2.operateAdmin(MOCK_DEX_TYPE, MOCK_IMPLEMENTATION_ID, operateData_);
    }

    function createStoredBalanceViaSettleFallback(address token_, uint256 amount_, address to_) external returns (bytes memory) {
        _addPendingWithdraw(token_, amount_);
        dexV2.settle(token_, -int256(amount_), 0, 0, to_, false);
        return "";
    }

    // ═══════════════════════════════════════════════════════════════
    //                     Revert tests
    // ═══════════════════════════════════════════════════════════════

    function testWithdrawStoredTokens_RevertsOnZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(FluidDexV2Error.selector, ERROR_DexV2Main__OperateAmountsZero));
        dexV2.withdrawStoredTokens(address(USDC), 0, address(this));
    }

    function testWithdrawStoredTokens_RevertsOnInsufficientBalance() public {
        _setStoredTokenAmount(address(this), address(USDC), 100e6);

        vm.expectRevert(abi.encodeWithSelector(FluidDexV2Error.selector, ERROR_DexV2Main__InsufficientStoredTokenAmount));
        dexV2.withdrawStoredTokens(address(USDC), 101e6, address(this));
    }

    function testWithdrawStoredTokens_RevertsOnNoStoredBalance() public {
        vm.expectRevert(abi.encodeWithSelector(FluidDexV2Error.selector, ERROR_DexV2Main__InsufficientStoredTokenAmount));
        dexV2.withdrawStoredTokens(address(USDC), 1e6, address(this));
    }

    // ═══════════════════════════════════════════════════════════════
    //              ERC20 — local balance path
    // ═══════════════════════════════════════════════════════════════

    function testWithdrawStoredTokens_ERC20_LocalBalance() public {
        uint256 storedAmount_ = 500e6;

        _setStoredTokenAmount(address(this), address(USDC), storedAmount_);

        // Seed DEX with enough tokens
        deal(address(USDC), address(dexV2), storedAmount_);

        uint256 balBefore_ = USDC.balanceOf(address(this));

        dexV2.withdrawStoredTokens(address(USDC), storedAmount_, address(this));

        assertEq(USDC.balanceOf(address(this)), balBefore_ + storedAmount_, "recipient should receive tokens");
        assertEq(_getStoredTokenAmount(address(this), address(USDC)), 0, "stored balance should be zero");
    }

    function testWithdrawStoredTokens_ERC20_LocalBalance_ToOtherAddress() public {
        uint256 storedAmount_ = 500e6;

        _setStoredTokenAmount(address(this), address(USDC), storedAmount_);
        deal(address(USDC), address(dexV2), storedAmount_);

        uint256 bobBalBefore_ = USDC.balanceOf(bob);

        dexV2.withdrawStoredTokens(address(USDC), storedAmount_, bob);

        assertEq(USDC.balanceOf(bob), bobBalBefore_ + storedAmount_, "bob should receive tokens");
        assertEq(_getStoredTokenAmount(address(this), address(USDC)), 0, "stored balance should be zero");
    }

    function testWithdrawStoredTokens_ERC20_DefaultsToMsgSender() public {
        uint256 storedAmount_ = 500e6;

        _setStoredTokenAmount(address(this), address(USDC), storedAmount_);
        deal(address(USDC), address(dexV2), storedAmount_);

        uint256 balBefore_ = USDC.balanceOf(address(this));

        // Pass address(0) as to_ — should default to msg.sender
        dexV2.withdrawStoredTokens(address(USDC), storedAmount_, address(0));

        assertEq(USDC.balanceOf(address(this)), balBefore_ + storedAmount_, "msg.sender should receive tokens");
    }

    function testWithdrawStoredTokens_ERC20_PartialWithdraw() public {
        uint256 storedAmount_ = 1000e6;
        uint256 withdrawAmount_ = 400e6;

        _setStoredTokenAmount(address(this), address(USDC), storedAmount_);
        deal(address(USDC), address(dexV2), storedAmount_);

        uint256 balBefore_ = USDC.balanceOf(address(this));

        dexV2.withdrawStoredTokens(address(USDC), withdrawAmount_, address(this));

        assertEq(USDC.balanceOf(address(this)), balBefore_ + withdrawAmount_, "should receive partial amount");
        assertEq(
            _getStoredTokenAmount(address(this), address(USDC)),
            storedAmount_ - withdrawAmount_,
            "remaining stored balance should be correct"
        );
    }

    // ═══════════════════════════════════════════════════════════════
    //          Native token — local balance path
    // ═══════════════════════════════════════════════════════════════

    function testWithdrawStoredTokens_NativeToken_LocalBalance() public {
        uint256 storedAmount_ = 1 ether;

        _setStoredTokenAmount(address(this), NATIVE_TOKEN_ADDRESS, storedAmount_);
        deal(address(dexV2), storedAmount_);

        uint256 balBefore_ = address(this).balance;

        dexV2.withdrawStoredTokens(NATIVE_TOKEN_ADDRESS, storedAmount_, address(this));

        assertEq(address(this).balance, balBefore_ + storedAmount_, "should receive native tokens");
        assertEq(_getStoredTokenAmount(address(this), NATIVE_TOKEN_ADDRESS), 0, "stored balance should be zero");
    }

    function testWithdrawStoredTokens_NativeToken_LocalBalance_ToOtherAddress() public {
        uint256 storedAmount_ = 1 ether;

        _setStoredTokenAmount(address(this), NATIVE_TOKEN_ADDRESS, storedAmount_);
        deal(address(dexV2), storedAmount_);

        uint256 bobBalBefore_ = bob.balance;

        dexV2.withdrawStoredTokens(NATIVE_TOKEN_ADDRESS, storedAmount_, bob);

        assertEq(bob.balance, bobBalBefore_ + storedAmount_, "bob should receive native tokens");
    }

    // ═══════════════════════════════════════════════════════════════
    //          ERC20 — Liquidity layer path
    // ═══════════════════════════════════════════════════════════════

    /// @dev Seeds DEX with tokens via deal() (not addOrRemoveTokens, so _totalAuthAddedAmount stays 0)
    ///      then rebalances so the supply flows into the Liquidity layer.
    function _seedDexSupplyAtLiquidity(address token_, uint256 amount_) internal {
        if (token_ == NATIVE_TOKEN_ADDRESS) {
            deal(address(dexV2), amount_);
            dexV2.rebalance(token_);
        } else {
            deal(token_, address(dexV2), amount_);
            dexV2.rebalance(token_);
        }
    }

    function testWithdrawStoredTokens_ERC20_ViaLiquidity() public {
        uint256 storedAmount_ = 500e6;

        // DexV2 supplies to Liquidity (deal bypasses _totalAuthAddedAmount, so rebalance sees net supply)
        _seedDexSupplyAtLiquidity(address(USDC), storedAmount_);
        assertEq(USDC.balanceOf(address(dexV2)), 0, "DEX should have no local balance after rebalance");

        _setStoredTokenAmount(address(this), address(USDC), storedAmount_);

        uint256 balBefore_ = USDC.balanceOf(address(this));

        dexV2.withdrawStoredTokens(address(USDC), storedAmount_, address(this));

        assertEq(USDC.balanceOf(address(this)), balBefore_ + storedAmount_, "should receive tokens via Liquidity");
        assertEq(_getStoredTokenAmount(address(this), address(USDC)), 0, "stored balance should be zero");
    }

    function testWithdrawStoredTokens_ERC20_ViaLiquidity_ToOtherAddress() public {
        uint256 storedAmount_ = 500e6;

        _seedDexSupplyAtLiquidity(address(USDC), storedAmount_);

        _setStoredTokenAmount(address(this), address(USDC), storedAmount_);

        uint256 bobBalBefore_ = USDC.balanceOf(bob);

        dexV2.withdrawStoredTokens(address(USDC), storedAmount_, bob);

        assertEq(USDC.balanceOf(bob), bobBalBefore_ + storedAmount_, "bob should receive tokens via Liquidity");
    }

    // ═══════════════════════════════════════════════════════════════
    //       Native token — Liquidity layer path
    // ═══════════════════════════════════════════════════════════════

    function testWithdrawStoredTokens_NativeToken_ViaLiquidity() public {
        uint256 storedAmount_ = 1 ether;

        // Supply ETH to Liquidity via deal + rebalance
        _seedDexSupplyAtLiquidity(NATIVE_TOKEN_ADDRESS, storedAmount_);
        assertEq(address(dexV2).balance, 0, "DEX should have no local ETH after rebalance");

        _setStoredTokenAmount(address(this), NATIVE_TOKEN_ADDRESS, storedAmount_);

        uint256 balBefore_ = address(this).balance;

        dexV2.withdrawStoredTokens(NATIVE_TOKEN_ADDRESS, storedAmount_, address(this));

        assertEq(address(this).balance, balBefore_ + storedAmount_, "should receive native tokens via Liquidity");
        assertEq(_getStoredTokenAmount(address(this), NATIVE_TOKEN_ADDRESS), 0, "stored balance should be zero");
    }

    // ═══════════════════════════════════════════════════════════════
    //       Revert — Liquidity layer also fails
    // ═══════════════════════════════════════════════════════════════

    function testWithdrawStoredTokens_RevertsWhenBothLocalAndLiquidityFail() public {
        uint256 storedAmount_ = 500e6;

        // Set stored amount but DON'T seed DEX or Liquidity with tokens
        // DEX has no local USDC and no supply at Liquidity to withdraw from
        _setStoredTokenAmount(address(this), address(USDC), storedAmount_);

        // Drain any accidental DEX balance
        uint256 dexBalance_ = USDC.balanceOf(address(dexV2));
        if (dexBalance_ > 0) {
            dexV2.addOrRemoveTokens(address(USDC), -int256(dexBalance_));
        }

        // Should revert because: no local balance AND no Liquidity supply to withdraw from
        vm.expectRevert();
        dexV2.withdrawStoredTokens(address(USDC), storedAmount_, address(this));

        // Stored balance should be unchanged (tx reverted)
        assertEq(
            _getStoredTokenAmount(address(this), address(USDC)),
            storedAmount_,
            "stored balance should be unchanged after revert"
        );
    }

    // ═══════════════════════════════════════════════════════════════
    //                     Event emission
    // ═══════════════════════════════════════════════════════════════

    function testWithdrawStoredTokens_EmitsLogSettle() public {
        uint256 storedAmount_ = 500e6;

        _setStoredTokenAmount(address(this), address(USDC), storedAmount_);
        deal(address(USDC), address(dexV2), storedAmount_);

        vm.expectEmit(true, true, true, true, address(dexV2));
        emit LogSettle(address(this), address(USDC), 0, 0, -int256(storedAmount_), bob);

        dexV2.withdrawStoredTokens(address(USDC), storedAmount_, bob);
    }

    function testWithdrawStoredTokens_EmitsLogSettle_DefaultTo() public {
        uint256 storedAmount_ = 500e6;

        _setStoredTokenAmount(address(this), address(USDC), storedAmount_);
        deal(address(USDC), address(dexV2), storedAmount_);

        // When to_ = address(0), event should show msg.sender as to
        vm.expectEmit(true, true, true, true, address(dexV2));
        emit LogSettle(address(this), address(USDC), 0, 0, -int256(storedAmount_), address(this));

        dexV2.withdrawStoredTokens(address(USDC), storedAmount_, address(0));
    }

    // ═══════════════════════════════════════════════════════════════
    //       EOA scenario (the original bug fix)
    // ═══════════════════════════════════════════════════════════════

    function testWithdrawStoredTokens_EOACanWithdraw() public {
        uint256 storedAmount_ = 500e6;

        // Simulate: settle() fallback credited bob (an EOA) with stored tokens
        _setStoredTokenAmount(bob, address(USDC), storedAmount_);
        deal(address(USDC), address(dexV2), storedAmount_);

        uint256 bobBalBefore_ = USDC.balanceOf(bob);

        // Bob (EOA) calls withdrawStoredTokens directly — no startOperation needed
        vm.prank(bob);
        dexV2.withdrawStoredTokens(address(USDC), storedAmount_, bob);

        assertEq(USDC.balanceOf(bob), bobBalBefore_ + storedAmount_, "EOA bob should receive tokens");
        assertEq(_getStoredTokenAmount(bob, address(USDC)), 0, "bob's stored balance should be zero");
    }

    function testWithdrawStoredTokens_EOACanWithdrawNativeToken() public {
        uint256 storedAmount_ = 1 ether;

        _setStoredTokenAmount(bob, NATIVE_TOKEN_ADDRESS, storedAmount_);
        deal(address(dexV2), storedAmount_);

        uint256 bobBalBefore_ = bob.balance;

        vm.prank(bob);
        dexV2.withdrawStoredTokens(NATIVE_TOKEN_ADDRESS, storedAmount_, bob);

        assertEq(bob.balance, bobBalBefore_ + storedAmount_, "EOA bob should receive native tokens");
    }

    function testWithdrawStoredTokens_EOACanWithdrawToOtherEOA() public {
        uint256 storedAmount_ = 500e6;

        _setStoredTokenAmount(alice, address(USDC), storedAmount_);
        deal(address(USDC), address(dexV2), storedAmount_);

        uint256 bobBalBefore_ = USDC.balanceOf(bob);

        // Alice withdraws her stored tokens but sends them to Bob
        vm.prank(alice);
        dexV2.withdrawStoredTokens(address(USDC), storedAmount_, bob);

        assertEq(USDC.balanceOf(bob), bobBalBefore_ + storedAmount_, "bob should receive alice's stored tokens");
        assertEq(_getStoredTokenAmount(alice, address(USDC)), 0, "alice's stored balance should be zero");
    }

    function testWithdrawStoredTokens_CanWithdrawBalanceCreditedBySettleFallback() public {
        uint256 storedAmount_ = 2_000_000e6;

        dexV2.startOperation(
            abi.encodeWithSelector(
                this.createStoredBalanceViaSettleFallback.selector,
                address(USDC),
                storedAmount_,
                bob
            )
        );

        assertEq(_getStoredTokenAmount(bob, address(USDC)), storedAmount_, "fallback settle should credit stored balance");

        deal(address(USDC), address(dexV2), storedAmount_);

        uint256 bobBalBefore_ = USDC.balanceOf(bob);

        vm.prank(bob);
        dexV2.withdrawStoredTokens(address(USDC), storedAmount_, bob);

        assertEq(USDC.balanceOf(bob), bobBalBefore_ + storedAmount_, "bob should recover fallback-credited balance");
        assertEq(_getStoredTokenAmount(bob, address(USDC)), 0, "bob's stored balance should be zero");
    }

    // ═══════════════════════════════════════════════════════════════
    //       Isolation: only msg.sender's balance is affected
    // ═══════════════════════════════════════════════════════════════

    function testWithdrawStoredTokens_OnlyAffectsMsgSenderBalance() public {
        uint256 aliceStored_ = 500e6;
        uint256 bobStored_ = 300e6;

        _setStoredTokenAmount(alice, address(USDC), aliceStored_);
        _setStoredTokenAmount(bob, address(USDC), bobStored_);
        deal(address(USDC), address(dexV2), aliceStored_ + bobStored_);

        // Alice withdraws her stored tokens
        vm.prank(alice);
        dexV2.withdrawStoredTokens(address(USDC), aliceStored_, alice);

        // Bob's stored balance should be untouched
        assertEq(_getStoredTokenAmount(alice, address(USDC)), 0, "alice's balance should be zero");
        assertEq(_getStoredTokenAmount(bob, address(USDC)), bobStored_, "bob's balance should be unchanged");
    }

    function testWithdrawStoredTokens_CannotWithdrawOtherUsersBalance() public {
        uint256 aliceStored_ = 500e6;

        _setStoredTokenAmount(alice, address(USDC), aliceStored_);
        deal(address(USDC), address(dexV2), aliceStored_);

        // Bob tries to withdraw — he has no stored balance
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(FluidDexV2Error.selector, ERROR_DexV2Main__InsufficientStoredTokenAmount));
        dexV2.withdrawStoredTokens(address(USDC), aliceStored_, bob);
    }

    // ═══════════════════════════════════════════════════════════════
    //       Multiple sequential withdrawals
    // ═══════════════════════════════════════════════════════════════

    function testWithdrawStoredTokens_MultiplePartialWithdraws() public {
        uint256 storedAmount_ = 1000e6;

        _setStoredTokenAmount(address(this), address(USDC), storedAmount_);
        deal(address(USDC), address(dexV2), storedAmount_);

        uint256 balBefore_ = USDC.balanceOf(address(this));

        dexV2.withdrawStoredTokens(address(USDC), 300e6, address(this));
        assertEq(_getStoredTokenAmount(address(this), address(USDC)), 700e6, "after 1st withdraw");

        dexV2.withdrawStoredTokens(address(USDC), 500e6, address(this));
        assertEq(_getStoredTokenAmount(address(this), address(USDC)), 200e6, "after 2nd withdraw");

        dexV2.withdrawStoredTokens(address(USDC), 200e6, address(this));
        assertEq(_getStoredTokenAmount(address(this), address(USDC)), 0, "after 3rd withdraw");

        assertEq(USDC.balanceOf(address(this)), balBefore_ + storedAmount_, "total received should match");
    }

    // Need receive() to accept native token transfers in tests
    receive() external payable {}
}
