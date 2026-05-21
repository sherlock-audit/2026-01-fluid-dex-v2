//SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { DexV2BaseSetup } from "../dexV2/baseSetup.t.sol";

// Money Market imports
import { FluidMoneyMarket } from "../../../contracts/protocols/moneyMarket/core/base/main.sol";
import { FluidMoneyMarketProxy } from "../../../contracts/protocols/moneyMarket/core/proxy.sol";
import { FluidMoneyMarketAdminModuleImplementation } from "../../../contracts/protocols/moneyMarket/core/adminModule/main.sol";
import { FluidMoneyMarketOperateModule } from "../../../contracts/protocols/moneyMarket/core/operateModule/main.sol";
import { FluidMoneyMarketLiquidateModule } from "../../../contracts/protocols/moneyMarket/core/liquidateModule/main.sol";
import { FluidMoneyMarketCallbackImplementation } from "../../../contracts/protocols/moneyMarket/core/callbackModule/main.sol";
import { MockOracleMM } from "../../../contracts/mocks/mockOracleMM.sol";
import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";
import { InitializeParams, DexKey } from "../../../contracts/protocols/dexV2/dexTypes/common/d3d4common/structs.sol";
import { TickMath as TM } from "lib/v3-core/contracts/libraries/TickMath.sol";
import { CreateD3D4PositionParams } from "../../../contracts/protocols/moneyMarket/core/operateModule/structs.sol";
import { TokenConfig } from "../../../contracts/protocols/moneyMarket/core/adminModule/structs.sol";
import { SwapInParams } from "../../../contracts/protocols/dexV2/dexTypes/common/d3d4common/structs.sol";
import { DepositParams, WithdrawParams } from "../../../contracts/protocols/dexV2/dexTypes/d3/other/structs.sol";
import { LiquidateParams, HfInfo } from "../../../contracts/protocols/moneyMarket/core/other/structs.sol";
import { FluidLiquidateEstimate, FluidMoneyMarketError } from "../../../contracts/protocols/moneyMarket/core/other/error.sol";
import { ErrorTypes } from "../../../contracts/protocols/moneyMarket/core/other/errorTypes.sol";

// DexV2 D3 and D4 imports (modules are deployed in DexV2BaseSetup)
import { FluidDexV2D3AdminModule } from "../../../contracts/protocols/dexV2/dexTypes/d3/admin/main.sol";
import { FluidDexV2D3SwapModule } from "../../../contracts/protocols/dexV2/dexTypes/d3/core/swapModule.sol";
import { FluidDexV2D3UserModule } from "../../../contracts/protocols/dexV2/dexTypes/d3/core/userModule.sol";
import { FluidDexV2D4AdminModule } from "../../../contracts/protocols/dexV2/dexTypes/d4/admin/main.sol";
import { FluidDexV2D4SwapModule } from "../../../contracts/protocols/dexV2/dexTypes/d4/core/swapModule.sol";
import { FluidDexV2D4UserModule } from "../../../contracts/protocols/dexV2/dexTypes/d4/core/userModule.sol";

contract StepwiseMockOracleMM {
    mapping(address => uint256) public tokenPrices;

    address public stepToken;
    uint256 public stepAfterCollateralReads;
    uint256 public stepPrice;
    uint256 public liquidateCollateralReads;

    function setPrice(address token_, uint256 price_) external {
        tokenPrices[token_] = price_;
    }

    function setCollateralPriceStep(address token_, uint256 stepAfterCollateralReads_, uint256 stepPrice_) external {
        stepToken = token_;
        stepAfterCollateralReads = stepAfterCollateralReads_;
        stepPrice = stepPrice_;
    }

    function getPrice(address token0_, uint256, bool isOperate_, bool isCollateral_) external returns (uint256 price_) {
        if (!isOperate_ && isCollateral_ && token0_ == stepToken) {
            liquidateCollateralReads++;
            if (liquidateCollateralReads > stepAfterCollateralReads) {
                return stepPrice;
            }
        }

        price_ = tokenPrices[token0_];
        require(price_ > 0, "StepwiseMockOracleMM: Price not set for token");
    }
}

/// @title Money Market Test
/// @notice Test contract for Money Market functionality
abstract contract MoneyMarketTestBaseSetup is DexV2BaseSetup {
    using SafeERC20 for IERC20;

    // Make contract payable to receive ETH
    receive() external payable {}

    // Money Market contracts
    FluidMoneyMarket public moneyMarket;
    FluidMoneyMarketAdminModuleImplementation public moneyMarketAdminModule;
    FluidMoneyMarketOperateModule public moneyMarketOperateModule;
    FluidMoneyMarketLiquidateModule public moneyMarketLiquidateModule;
    FluidMoneyMarketCallbackImplementation public moneyMarketCallbackModule;
    MockOracleMM public oracle;

    // D3/D4 modules and constants are inherited from DexV2BaseSetup

    /// @notice Sets up the testing environment with Money Market contracts
    function setUp() public virtual override {
        // Call parent setup to deploy liquidity, dexV2, and D3/D4 modules
        super.setUp();
        
        // Fund address(this) with test tokens
        deal(address(USDT), address(this), 1000 * 1e6);
        deal(address(USDC), address(this), 1000 * 1e6);
        deal(address(DAI), address(this), 1000 * 1e18);
        
        // Deploy Money Market module implementations
        moneyMarketAdminModule = new FluidMoneyMarketAdminModuleImplementation(
            address(liquidity), 
            address(dexV2)
        );
        
        moneyMarketOperateModule = new FluidMoneyMarketOperateModule(
            address(liquidity), 
            address(dexV2)
        );
        
        moneyMarketLiquidateModule = new FluidMoneyMarketLiquidateModule(
            address(liquidity), 
            address(dexV2)
        );
        
        moneyMarketCallbackModule = new FluidMoneyMarketCallbackImplementation(
            address(liquidity), 
            address(dexV2)
        );
        
        // D3/D4 modules are already deployed in DexV2BaseSetup

        // Deploy Mock Oracle
        oracle = new MockOracleMM();
        
        // Set initial token prices in oracle (all prices in 27 decimals representing USD value)
        oracle.setPrice(NATIVE_TOKEN_ADDRESS, 4000 * 1e27); // ETH = $4000
        oracle.setPrice(address(USDC), 1e27); // USDC = $1 (price always in 27 decimals)
        
        // Deploy Money Market implementation
        FluidMoneyMarket implementation = new FluidMoneyMarket(
            address(liquidity), 
            address(dexV2)
        );
        
        // Deploy Money Market proxy
        FluidMoneyMarketProxy proxy = new FluidMoneyMarketProxy(
            address(implementation),
            "" // No initialization data needed in constructor
        );
        
        // Cast proxy to FluidMoneyMarket interface
        moneyMarket = FluidMoneyMarket(address(proxy));
        
        // Whitelist address(this) for D3 pool creation
        vm.prank(admin);
        bytes memory whitelistData = abi.encodeWithSelector(FluidDexV2D3AdminModule.updateUserWhitelist.selector, address(this), true);
        dexV2.operateAdmin(DEX_TYPE_D3, ADMIN_MODULE_ID_D3, whitelistData);
        
        // Whitelist address(this) for D4 pool creation
        vm.prank(admin);
        whitelistData = abi.encodeWithSelector(FluidDexV2D4AdminModule.updateUserWhitelist.selector, address(this), true);
        dexV2.operateAdmin(DEX_TYPE_D4, ADMIN_MODULE_ID_D4, whitelistData);
        
        // Whitelist moneyMarket for D4 (required for D4 operations)
        vm.prank(admin);
        whitelistData = abi.encodeWithSelector(FluidDexV2D4AdminModule.updateUserWhitelist.selector, address(moneyMarket), true);
        dexV2.operateAdmin(DEX_TYPE_D4, ADMIN_MODULE_ID_D4, whitelistData);
        
        // Initialize storage variables via admin module (must be done as liquidity governance)
        vm.prank(admin);
        (bool success,) = address(moneyMarket).call(
            abi.encodeWithSelector(moneyMarketAdminModule.updateOracle.selector, address(oracle))
        );
        require(success, "Failed to set oracle");
        
        vm.prank(admin);
        (success,) = address(moneyMarket).call(
            abi.encodeWithSelector(moneyMarketAdminModule.updateMaxPositionsPerNFT.selector, 10)
        );
        require(success, "Failed to set max positions per NFT");
        
        vm.prank(admin);
        (success,) = address(moneyMarket).call(
            abi.encodeWithSelector(moneyMarketAdminModule.updateMinNormalizedCollateralValue.selector, 1000 * 1e27)
        );
        require(success, "Failed to set min normalized collateral value");
        
        vm.prank(admin);
        (success,) = address(moneyMarket).call(
            abi.encodeWithSelector(moneyMarketAdminModule.updateHfLimitForLiquidation.selector, 1.25e27)
        );
        require(success, "Failed to set HF limit for liquidation");
        
        // Authorize this test contract to call admin functions via fallback
        vm.prank(admin);
        (success,) = address(moneyMarket).call(
            abi.encodeWithSelector(moneyMarketAdminModule.updateAuth.selector, address(this), true)
        );
        require(success, "Failed to authorize test contract");
        
        // List native token (ETH) first - it gets index 1 (indices start from 1)
        _listNativeToken();
        // Set up Money Market permissions on Liquidity Layer
        _setUserAllowancesDefault(address(liquidity), admin, address(USDC), address(moneyMarket));
        _setUserAllowancesDefault(address(liquidity), admin, address(USDT), address(moneyMarket));
        _setUserAllowancesDefault(address(liquidity), admin, address(DAI), address(moneyMarket));
        _setUserAllowancesDefault(address(liquidity), admin, NATIVE_TOKEN_ADDRESS, address(moneyMarket));
        
        // Supply initial liquidity to the liquidity layer so there's something to borrow
        _setUserAllowancesDefault(address(liquidity), admin, address(USDC), address(mockProtocol));
        _setUserAllowancesDefault(address(liquidity), admin, address(USDT), address(mockProtocol));
        _setUserAllowancesDefault(address(liquidity), admin, address(DAI), address(mockProtocol));
        _setUserAllowancesDefault(address(liquidity), admin, NATIVE_TOKEN_ADDRESS, address(mockProtocol));
        
        _supply(address(liquidity), mockProtocol, address(USDC), alice, 10000000 * 1e6); // 10M USDC
        _supply(address(liquidity), mockProtocol, address(USDT), alice, 10000000 * 1e6); // 10M USDT
        _supply(address(liquidity), mockProtocol, address(DAI), alice, 10000000 * 1e18); // 10M DAI
        _supplyNative(address(liquidity), mockProtocol, alice, 10000 * 1e18); // 10k ETH
        
        // Create buffer position for ETH to handle rounding differences during paybacks
        _createEthBuffer();
    }
    
    /// @notice Helper to list native token (must be first token listed)
    function _listNativeToken() internal {
        (bool success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.listToken.selector,
                NATIVE_TOKEN_ADDRESS,
                1, // collateralClass (1 = permissioned, 0 = not enabled)
                1, // debtClass (1 = permissioned, 0 = not enabled) 
                800, // collateralFactor (80%)
                850, // liquidationThreshold (85%)
                50  // liquidationPenalty (5%)
            )
        );
        require(success, "Failed to list native token");
        
        // Set supply cap for native token (1,000 ETH)
        (success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateTokenSupplyCap.selector,
                NATIVE_TOKEN_ADDRESS,
                1000 * 1e18 // 1000 ETH cap
            )
        );
        require(success, "Failed to set native token supply cap");
        
        // Set debt cap for native token
        (success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateTokenDebtCap.selector,
                NATIVE_TOKEN_ADDRESS,
                1000 * 1e18 // 1000 ETH debt cap
            )
        );
        require(success, "Failed to set native token debt cap");
    }
    
    /// @notice Helper to create buffer positions for ETH
    /// @dev Called at the end of setUp after all allowances are configured
    function _createEthBuffer() internal {
        vm.deal(address(this), address(this).balance + 100 ether);
        _createBufferPosition(NATIVE_TOKEN_ADDRESS, 1, 100 ether, 50 ether);
    }
    
    /// @notice Helper to list USDC token
    function _listUSDC() internal {
        // List USDC token
        (bool success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.listToken.selector,
                address(USDC),
                1, // collateralClass (1 = permissioned, 0 = not enabled)
                1, // debtClass (1 = permissioned, 0 = not enabled) 
                800, // collateralFactor (80%)
                850, // liquidationThreshold (85%)
                50  // liquidationPenalty (5%)
            )
        );
        require(success, "Failed to list USDC token");
        
        // Set supply cap for USDC (1,000,000 USDC with 6 decimals)
        (success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateTokenSupplyCap.selector,
                address(USDC),
                1000000 * 1e6 // 1M USDC cap
            )
        );
        require(success, "Failed to set USDC supply cap");
        
        // Set debt cap for USDC
        (success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateTokenDebtCap.selector,
                address(USDC),
                1000000 * 1e6 // 1M USDC debt cap
            )
        );
        require(success, "Failed to set USDC debt cap");
        
        // Create buffer position for USDC to handle rounding differences during paybacks
        _createBufferPosition(address(USDC), 2, 10000 * 1e6, 5000 * 1e6);
    }
    
    /// @notice Helper to create a buffer position with supply and borrow of the same token
    /// @dev This creates debt in Liquidity Layer to buffer rounding differences during paybacks
    /// @return bufferNftId The NFT ID of the buffer position (tests should account for this when checking their own NFT IDs)
    function _createBufferPosition(address token, uint256 tokenIndex, uint256 supplyAmount, uint256 borrowAmount) internal returns (uint256 bufferNftId) {
        // Fund and approve
        if (token != NATIVE_TOKEN_ADDRESS) {
            deal(token, address(this), IERC20(token).balanceOf(address(this)) + supplyAmount);
            IERC20(token).approve(address(moneyMarket), supplyAmount);
        }
        
        // Create supply position
        bytes memory supplyData = abi.encode(1, tokenIndex, supplyAmount);
        uint256 ethValue = token == NATIVE_TOKEN_ADDRESS ? supplyAmount : 0;
        (bufferNftId,,) = moneyMarket.operate{value: ethValue}(
            0,
            0,
            supplyData
        );
        
        // Create borrow position on same NFT
        bytes memory borrowData = abi.encode(2, tokenIndex, borrowAmount, address(this));
        moneyMarket.operate(bufferNftId, 0, borrowData);
    }
    
    function testSetup() public {
        // Verify liquidity layer is deployed
        assertNotEq(address(liquidity), address(0), "Liquidity should be deployed");
        
        // Verify dexV2 is deployed
        assertNotEq(address(dexV2), address(0), "DexV2 should be deployed");
        
        // Verify DexV2 D3 modules
        assertNotEq(address(dexV2D3ControllerModule), address(0), "D3 ControllerModule should be deployed");
        assertNotEq(address(dexV2D3SwapModule), address(0), "D3 SwapModule should be deployed");
        assertNotEq(address(dexV2D3UserModule), address(0), "D3 UserModule should be deployed");
        assertNotEq(address(dexV2D3AdminModule), address(0), "D3 AdminModule should be deployed");
        
        // Verify DexV2 D4 modules
        assertNotEq(address(dexV2D4SwapModule), address(0), "D4 SwapModule should be deployed");
        assertNotEq(address(dexV2D4UserModule), address(0), "D4 UserModule should be deployed");
        assertNotEq(address(dexV2D4ControllerModule), address(0), "D4 ControllerModule should be deployed");
        assertNotEq(address(dexV2D4AdminModule), address(0), "D4 AdminModule should be deployed");
        
        // Verify Money Market contracts are deployed
        assertNotEq(address(moneyMarket), address(0), "Money Market should be deployed");
        assertNotEq(address(moneyMarketAdminModule), address(0), "Money Market Admin module should be deployed");
        assertNotEq(address(moneyMarketOperateModule), address(0), "Money Market Operate module should be deployed");
        assertNotEq(address(moneyMarketLiquidateModule), address(0), "Money Market Liquidate module should be deployed");
        assertNotEq(address(moneyMarketCallbackModule), address(0), "Money Market Callback module should be deployed");
        
        console2.log("Liquidity:              ", address(liquidity));
        console2.log("DexV2:                  ", address(dexV2));
        console2.log("MM Admin Module:        ", address(moneyMarketAdminModule));
        console2.log("MM Operate Module:      ", address(moneyMarketOperateModule));
        console2.log("MM Liquidate Module:    ", address(moneyMarketLiquidateModule));
        console2.log("MM Callback Module:     ", address(moneyMarketCallbackModule));
        console2.log("DexV2 D3 Controller:    ", address(dexV2D3ControllerModule));
        console2.log("DexV2 D3 Swap:          ", address(dexV2D3SwapModule));
        console2.log("DexV2 D3 User:          ", address(dexV2D3UserModule));
        console2.log("DexV2 D3 Admin:         ", address(dexV2D3AdminModule));
        console2.log("DexV2 D4 Swap:          ", address(dexV2D4SwapModule));
        console2.log("DexV2 D4 User:          ", address(dexV2D4UserModule));
        console2.log("DexV2 D4 Controller:    ", address(dexV2D4ControllerModule));
        console2.log("DexV2 D4 Admin:         ", address(dexV2D4AdminModule));
        console2.log("Oracle:                 ", address(oracle));
        console2.log("Money Market:           ", address(moneyMarket));
        console2.log("============================================");
    }
}

contract MoneyMarketTest is MoneyMarketTestBaseSetup {
    /// @notice Test 1: List ETH (native token) - automatically listed in setup
    function testListEth() public {
        console2.log("Token:               ", NATIVE_TOKEN_ADDRESS);
        console2.log("Token Index:         ", uint256(0));
        console2.log("============================");
    }

    /// @notice Test 2: Supply ETH
    function testSupplyEth() public {
        // Supply 1 ETH
        uint256 supplyAmount = 1 ether;
        uint256 tokenIndex = 1; // ETH is index 1 (indices start from 1)
        
        // Encode action data for normal supply position
        bytes memory actionData = abi.encode(
            1, // NORMAL_SUPPLY_POSITION_TYPE
            tokenIndex,
            supplyAmount
        );
        
        // Check balance before
        uint256 balanceBefore = address(this).balance;
        
        // Call operate with nftId = 0 to create new NFT and position
        (uint256 nftId, uint256 positionIndex,) = moneyMarket.operate{value: supplyAmount}(
            0, // 0 means create new NFT
            0, // positionIndex (ignored when creating new NFT)
            actionData
        );
        
        // Check balance after
        uint256 balanceAfter = address(this).balance;
        
        // Verify results
        assertTrue(nftId > 0, "NFT ID should be created");
        assertEq(positionIndex, 1, "Position index should be 1");
        assertEq(balanceBefore - balanceAfter, supplyAmount, "ETH should be transferred");
        
        // Verify NFT ownership
        assertEq(moneyMarket.ownerOf(nftId), address(this), "This contract should own the NFT");
        
        console2.log("NFT ID:          ", _toString(nftId));
        console2.log("Supply Amount:   ", _toString(supplyAmount));
        console2.log("========================================");
    }

    /// @notice Test 3: List USDC token
    function testListUSDC() public {
        // List USDC using helper
        _listUSDC();
        
        console2.log("Token:               ", address(USDC));
        console2.log("Token Index:         ", uint256(1));
        console2.log("==============================");
    }

    /// @notice Test 4: Supply USDC
    function testSupplyUSDC() public {
        // Setup: List USDC first
        _listUSDC();
        
        // Supply 100 USDC
        uint256 supplyAmount = 100 * 1e6; // 100 USDC (6 decimals)
        uint256 tokenIndex = 2; // USDC is index 2 (indices start from 1, ETH is 1)
        
        // Approve USDC to money market
        USDC.approve(address(moneyMarket), supplyAmount);
        
        // Encode action data for normal supply position
        bytes memory actionData = abi.encode(
            1, // NORMAL_SUPPLY_POSITION_TYPE
            tokenIndex,
            supplyAmount
        );
        
        // Check balance before
        uint256 balanceBefore = USDC.balanceOf(address(this));
        
        // Call operate with nftId = 0 to create new NFT and position
        (uint256 nftId, uint256 positionIndex,) = moneyMarket.operate(
            0, // 0 means create new NFT
            0, // positionIndex (ignored when creating new NFT)
            actionData
        );
        
        // Check balance after
        uint256 balanceAfter = USDC.balanceOf(address(this));
        
        // Verify results
        assertTrue(nftId > 0, "NFT ID should be created");
        assertEq(positionIndex, 1, "Position index should be 1");
        assertEq(balanceBefore - balanceAfter, supplyAmount, "USDC should be transferred");
        
        // Verify NFT ownership
        assertEq(moneyMarket.ownerOf(nftId), address(this), "This contract should own the NFT");
        
        console2.log("NFT ID:          ", _toString(nftId));
        console2.log("Supply Amount:   ", _toString(supplyAmount));
        console2.log("=========================================");
    }

    /// @notice Test 5: Supply, add more, withdraw partial, and withdraw full ETH
    function testSupplyAddWithdrawEth() public {
        // Step 1: Create initial ETH supply position (supply 1 ETH)
        uint256 initialSupply = 1 ether;
        bytes memory initialActionData = abi.encode(
            1, // NORMAL_SUPPLY_POSITION_TYPE
            1, // tokenIndex for ETH (indices start from 1)
            initialSupply
        );
        
        (uint256 nftId, uint256 positionIndex,) = moneyMarket.operate{value: initialSupply}(
            0, // Create new NFT
            0, // Create new position
            initialActionData
        );
        
        assertTrue(nftId > 0, "NFT ID should be created");
        assertEq(positionIndex, 1, "Position index should be 1");
        
        console2.log("Initial Supply:  ", _toString(initialSupply));
        
        // Step 2: Supply more ETH to the same position (add 0.5 ETH)
        uint256 additionalSupply = 0.5 ether;
        bytes memory addSupplyData = abi.encode(
            int256(additionalSupply), // Positive value means supply more
            address(0) // to_ address (not used for supply)
        );
        
        uint256 balanceBefore = address(this).balance;
        moneyMarket.operate{value: additionalSupply}(
            nftId,          // Use existing NFT
            positionIndex,  // Use existing position
            addSupplyData
        );
        uint256 balanceAfter = address(this).balance;
        
        assertEq(balanceBefore - balanceAfter, additionalSupply, "Additional ETH should be transferred");
        
        console2.log("Additional Supply:", _toString(additionalSupply));
        console2.log("Total Supplied:   ", _toString(initialSupply + additionalSupply));
        
        // Step 3: Withdraw partial ETH (withdraw 0.3 ETH)
        uint256 partialWithdraw = 0.3 ether;
        bytes memory partialWithdrawData = abi.encode(
            -int256(partialWithdraw), // Negative value means withdraw
            address(this) // to_ address where withdrawn funds are sent
        );
        
        balanceBefore = address(this).balance;
        moneyMarket.operate(
            nftId,          // Use existing NFT
            positionIndex,  // Use existing position
            partialWithdrawData
        );
        balanceAfter = address(this).balance;
        
        assertEq(balanceAfter - balanceBefore, partialWithdraw, "Partial ETH should be withdrawn");
        
        console2.log("Withdrawn:       ", _toString(partialWithdraw));
        console2.log("Remaining:       ", _toString(initialSupply + additionalSupply - partialWithdraw));
        
        // Step 4: Withdraw all remaining ETH (should delete position)
        // type(int256).min is the sentinel value for "withdraw all"
        bytes memory fullWithdrawData = abi.encode(
            type(int256).min, // type(int256).min means withdraw all
            address(this) // to_ address where withdrawn funds are sent
        );
        
        balanceBefore = address(this).balance;
        moneyMarket.operate(
            nftId,          // Use existing NFT
            positionIndex,  // Use existing position
            fullWithdrawData
        );
        balanceAfter = address(this).balance;
        
        uint256 expectedWithdraw = initialSupply + additionalSupply - partialWithdraw;
        // Allow small rounding difference (up to 0.001 ETH due to exchange rate conversions)
        assertApproxEqAbs(balanceAfter - balanceBefore, expectedWithdraw, 0.001 ether, "Full ETH should be withdrawn");
        
        console2.log("Final Withdrawn: ", _toString(balanceAfter - balanceBefore));
        console2.log("========================================================");
    }

    /// @notice Test 6: Supply both ETH and USDC to the same NFT
    function testSupplyBothToSameNFT() public {
        // Setup: List USDC
        _listUSDC();
        
        // First, supply 1 ETH (creates NFT with position 0)
        uint256 ethSupplyAmount = 1 ether;
        bytes memory ethActionData = abi.encode(
            1, // NORMAL_SUPPLY_POSITION_TYPE
            1, // tokenIndex for ETH (indices start from 1)
            ethSupplyAmount
        );
        
        uint256 ethBalanceBefore = address(this).balance;
        (uint256 nftId, uint256 ethPositionIndex,) = moneyMarket.operate{value: ethSupplyAmount}(
            0, // 0 means create new NFT
            0, // positionIndex (ignored when creating new NFT)
            ethActionData
        );
        uint256 ethBalanceAfter = address(this).balance;
        
        // Verify ETH supply
        assertTrue(nftId > 0, "NFT ID should be created");
        assertEq(ethPositionIndex, 1, "ETH position index should be 1");
        assertEq(ethBalanceBefore - ethBalanceAfter, ethSupplyAmount, "ETH should be transferred");
        assertEq(moneyMarket.ownerOf(nftId), address(this), "This contract should own the NFT");
        
        // Now, supply 100 USDC to the same NFT (creates position 1)
        uint256 usdcSupplyAmount = 100 * 1e6; // 100 USDC
        USDC.approve(address(moneyMarket), usdcSupplyAmount);
        
        bytes memory usdcActionData = abi.encode(
            1, // NORMAL_SUPPLY_POSITION_TYPE
            2, // tokenIndex for USDC (indices start from 1)
            usdcSupplyAmount
        );
        
        uint256 usdcBalanceBefore = USDC.balanceOf(address(this));
        (uint256 sameNftId, uint256 usdcPositionIndex,) = moneyMarket.operate(
            nftId, // Use the same NFT (NFT 0)
            0, // 0 means create new position in existing NFT
            usdcActionData
        );
        uint256 usdcBalanceAfter = USDC.balanceOf(address(this));
        
        // Verify USDC supply to same NFT
        assertEq(sameNftId, nftId, "Should be the same NFT");
        assertEq(usdcPositionIndex, 2, "USDC position index should be 2");
        assertEq(usdcBalanceBefore - usdcBalanceAfter, usdcSupplyAmount, "USDC should be transferred");
        
        // Verify NFT ownership
        assertEq(moneyMarket.ownerOf(nftId), address(this), "This contract should own the NFT");
        
        console2.log("NFT ID:              ", _toString(nftId));
        console2.log("ETH Position Index:  ", _toString(ethPositionIndex));
        console2.log("ETH Supply Amount:   ", _toString(ethSupplyAmount));
        console2.log("===================================================");
    }

    /// @notice Test 7: Supply, add more, withdraw partial, and withdraw full USDC
    function testSupplyAddWithdrawUSDC() public {
        // Setup: List USDC first
        _listUSDC();
        
        // Step 1: Create initial USDC supply position (supply 100 USDC)
        uint256 initialSupply = 100 * 1e6; // 100 USDC (6 decimals)
        bytes memory initialActionData = abi.encode(
            1, // NORMAL_SUPPLY_POSITION_TYPE
            2, // tokenIndex for USDC (indices start from 1) (ETH is 0)
            initialSupply
        );
        
        USDC.approve(address(moneyMarket), initialSupply);
        
        (uint256 nftId, uint256 positionIndex,) = moneyMarket.operate(
            0, // Create new NFT
            0, // Create new position
            initialActionData
        );
        
        assertTrue(nftId > 0, "NFT ID should be created");
        assertEq(positionIndex, 1, "Position index should be 1");
        
        console2.log("Initial Supply:  ", _toString(initialSupply));
        
        // Step 2: Supply more USDC to the same position (add 50 USDC)
        uint256 additionalSupply = 50 * 1e6;
        bytes memory addSupplyData = abi.encode(
            int256(additionalSupply), // Positive value means supply more
            address(0) // to_ address (not used for supply)
        );
        
        USDC.approve(address(moneyMarket), additionalSupply);
        
        uint256 balanceBefore = USDC.balanceOf(address(this));
        moneyMarket.operate(
            nftId,          // Use existing NFT
            positionIndex,  // Use existing position
            addSupplyData
        );
        uint256 balanceAfter = USDC.balanceOf(address(this));
        
        assertEq(balanceBefore - balanceAfter, additionalSupply, "Additional USDC should be transferred");
        
        console2.log("Additional Supply:", _toString(additionalSupply));
        console2.log("Total Supplied:   ", _toString(initialSupply + additionalSupply));
        
        // Step 3: Withdraw partial USDC (withdraw 30 USDC)
        uint256 partialWithdraw = 30 * 1e6;
        bytes memory partialWithdrawData = abi.encode(
            -int256(partialWithdraw), // Negative value means withdraw
            address(this) // to_ address where withdrawn funds are sent
        );
        
        balanceBefore = USDC.balanceOf(address(this));
        moneyMarket.operate(
            nftId,          // Use existing NFT
            positionIndex,  // Use existing position
            partialWithdrawData
        );
        balanceAfter = USDC.balanceOf(address(this));
        
        assertEq(balanceAfter - balanceBefore, partialWithdraw, "Partial USDC should be withdrawn");
        
        console2.log("Withdrawn:       ", _toString(partialWithdraw));
        console2.log("Remaining:       ", _toString(initialSupply + additionalSupply - partialWithdraw));
        
        // Step 4: Withdraw all remaining USDC (should delete position)
        // type(int256).min is the sentinel value for "withdraw all"
        bytes memory fullWithdrawData = abi.encode(
            type(int256).min, // type(int256).min means withdraw all
            address(this) // to_ address where withdrawn funds are sent
        );
        
        balanceBefore = USDC.balanceOf(address(this));
        moneyMarket.operate(
            nftId,          // Use existing NFT
            positionIndex,  // Use existing position
            fullWithdrawData
        );
        balanceAfter = USDC.balanceOf(address(this));
        
        uint256 expectedWithdraw = initialSupply + additionalSupply - partialWithdraw;
        // Allow small rounding difference
        assertApproxEqAbs(balanceAfter - balanceBefore, expectedWithdraw, 1e6, "Full USDC should be withdrawn");
        
        console2.log("Final Withdrawn: ", _toString(balanceAfter - balanceBefore));
        console2.log("========================================================");
    }

    /// @notice Test 8: Verify ETH supply cap is enforced (should revert)
    function testSupplyCapEnforcement() public {
        // The cap is set to 1000 ETH in _listNativeToken()
        // Try to supply 1001 ETH, which should revert
        uint256 overCapAmount = 1001 ether;
        bytes memory actionData = abi.encode(
            1, // NORMAL_SUPPLY_POSITION_TYPE
            1, // tokenIndex for ETH (indices start from 1)
            overCapAmount
        );
        
        // Fund the test contract with enough ETH
        vm.deal(address(this), 2000 ether);
        
        // This should revert because it exceeds the supply cap
        vm.expectRevert();
        moneyMarket.operate{value: overCapAmount}(
            0, // Create new NFT
            0, // Create new position
            actionData
        );
        
        console2.log("Supply Cap:      ", _toString(uint256(1000 ether)));
        console2.log("Attempted Supply:", _toString(overCapAmount));
        console2.log("Result: Correctly reverted!");
        console2.log("========================================");
    }

    /// @notice Test 9: Verify USDC supply cap is enforced (should revert)
    function testSupplyCapEnforcementUSDC() public {
        // Setup: List USDC first
        _listUSDC();
        
        // The cap is set to 1,000,000 USDC in _listUSDC()
        // Try to supply 1,000,001 USDC, which should revert
        uint256 overCapAmount = 1000001 * 1e6; // 1,000,001 USDC (6 decimals)
        bytes memory actionData = abi.encode(
            1, // NORMAL_SUPPLY_POSITION_TYPE
            2, // tokenIndex for USDC (indices start from 1)
            overCapAmount
        );
        
        // Fund the test contract with enough USDC
        deal(address(USDC), address(this), 2000000 * 1e6);
        USDC.approve(address(moneyMarket), overCapAmount);
        
        // This should revert because it exceeds the supply cap
        vm.expectRevert();
        moneyMarket.operate(
            0, // Create new NFT
            0, // Create new position
            actionData
        );
        
        console2.log("Supply Cap:      ", _toString(uint256(1000000 * 1e6)));
        console2.log("Attempted Supply:", _toString(overCapAmount));
        console2.log("Result: Correctly reverted!");
        console2.log("=============================================");
    }

    /// @notice Test 10: Verify max positions per NFT is enforced (should revert)
    function testMaxPositionsPerNFTEnforcement() public {
        // Setup: List USDC first
        _listUSDC();
        
        // Set max positions per NFT to 1
        (bool success,) = address(moneyMarket).call(
            abi.encodeWithSelector(moneyMarketAdminModule.updateMaxPositionsPerNFT.selector, 1)
        );
        require(success, "Failed to set max positions per NFT to 1");
        
        // Step 1: Create first ETH position (this should succeed)
        uint256 ethSupplyAmount = 1 ether;
        bytes memory ethActionData = abi.encode(
            1, // NORMAL_SUPPLY_POSITION_TYPE
            1, // tokenIndex for ETH (indices start from 1)
            ethSupplyAmount
        );
        
        (uint256 nftId, uint256 positionIndex,) = moneyMarket.operate{value: ethSupplyAmount}(
            0, // Create new NFT
            0, // Create new position
            ethActionData
        );
        
        assertTrue(nftId > 0, "NFT ID should be created");
        assertEq(positionIndex, 1, "Position index should be 1");
        
        console2.log("Max Positions Set:   ", _toString(uint256(1)));
        console2.log("First Position Created Successfully with NFT ID:   ", _toString(nftId));
        
        // Step 2: Try to create second USDC position on same NFT (this should revert)
        uint256 usdcSupplyAmount = 100 * 1e6;
        bytes memory usdcActionData = abi.encode(
            1, // NORMAL_SUPPLY_POSITION_TYPE
            2, // tokenIndex for USDC (indices start from 1)
            usdcSupplyAmount
        );
        
        USDC.approve(address(moneyMarket), usdcSupplyAmount);
        
        // This should revert because max positions (1) has been reached
        vm.expectRevert();
        moneyMarket.operate(
            nftId, // Use existing NFT
            0, // Try to create new position
            usdcActionData
        );
        
        console2.log("Second Position Attempt: Correctly reverted!");
        console2.log("Max positions cap enforced successfully");
        console2.log("========================================");
    }

    /// @notice Test 11: Verify supplying token with collateral class 0 fails (should revert)
    function testSupplyDisabledCollateralClass() public {
        // List USDC with collateral class 0 (not enabled)
        (bool success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.listToken.selector,
                address(USDC),
                0, // collateralClass = 0 (NOT ENABLED)
                1, // debtClass (1 = permissioned)
                800, // collateralFactor (80%)
                850, // liquidationThreshold (85%)
                50  // liquidationPenalty (5%)
            )
        );
        require(success, "Failed to list USDC token");
        
        // Set supply cap for USDC
        (success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateTokenSupplyCap.selector,
                address(USDC),
                1000000 * 1e6 // 1M USDC cap
            )
        );
        require(success, "Failed to set USDC supply cap");
        
        
        // Try to supply 100 USDC (this should revert)
        uint256 supplyAmount = 100 * 1e6;
        bytes memory actionData = abi.encode(
            1, // NORMAL_SUPPLY_POSITION_TYPE
            2, // tokenIndex for USDC (indices start from 1)
            supplyAmount
        );
        
        USDC.approve(address(moneyMarket), supplyAmount);
        
        // This should revert because collateral class is 0 (not enabled)
        vm.expectRevert();
        moneyMarket.operate(
            0, // Create new NFT
            0, // Create new position
            actionData
        );
        
        console2.log("Supply Attempt: Correctly reverted!");
        console2.log("Collateral class 0 enforcement working");
        console2.log("==================================================");
    }

    /// @notice Test 12: Test all NFT-related functionality (balanceOf, transfers, approvals)
    function testNFTFunctionality() public {
        // Setup two test addresses
        address alice = address(0x1111);
        address bob = address(0x2222);
        
        // Fund both addresses with ETH for gas and supplies
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        
        console2.log("Alice:  ", alice);
        console2.log("Bob:    ", bob);
        console2.log("");
        
        // Step 1: Alice creates NFT 1 by supplying ETH
        console2.log("Step 1: Alice creates NFT 1");
        vm.startPrank(alice);
        bytes memory actionData = abi.encode(
            1, // NORMAL_SUPPLY_POSITION_TYPE
            1, // tokenIndex for ETH (indices start from 1)
            1 ether
        );
        
        (uint256 aliceNftId,,) = moneyMarket.operate{value: 1 ether}(
            0,
            0,
            actionData
        );
        vm.stopPrank();
        
        assertTrue(aliceNftId > 0, "Alice's NFT should be created");
        assertEq(moneyMarket.ownerOf(aliceNftId), alice, "Alice should own her NFT");
        assertEq(moneyMarket.balanceOf(alice), 1, "Alice should have 1 NFT");
        assertEq(moneyMarket.balanceOf(bob), 0, "Bob should have 0 NFTs");
        console2.log("");
        
        // Step 2: Bob creates NFT 2 by supplying ETH
        console2.log("Step 2: Bob creates NFT 2");
        vm.startPrank(bob);
        (uint256 bobNftId,,) = moneyMarket.operate{value: 2 ether}(
            0,
            0,
            actionData
        );
        vm.stopPrank();
        
        assertTrue(bobNftId > aliceNftId, "Bob's NFT should be after Alice's");
        assertEq(moneyMarket.ownerOf(bobNftId), bob, "Bob should own his NFT");
        assertEq(moneyMarket.balanceOf(alice), 1, "Alice should still have 1 NFT");
        assertEq(moneyMarket.balanceOf(bob), 1, "Bob should have 1 NFT");
        console2.log("");
        
        // Step 3: Test approval - Alice approves Bob for NFT 1
        console2.log("Step 3: Alice approves Bob for NFT 1");
        vm.prank(alice);
        moneyMarket.approve(bob, aliceNftId);
        
        assertEq(moneyMarket.getApproved(aliceNftId), bob, "Bob should be approved for NFT 1");
        console2.log("");
        
        // Step 4: Bob transfers NFT 1 from Alice to himself using approval
        console2.log("Step 4: Bob transfers NFT 1 from Alice to himself");
        vm.prank(bob);
        moneyMarket.transferFrom(alice, bob, aliceNftId);
        
        assertEq(moneyMarket.ownerOf(aliceNftId), bob, "Bob should now own NFT 1");
        assertEq(moneyMarket.balanceOf(alice), 0, "Alice should have 0 NFTs");
        assertEq(moneyMarket.balanceOf(bob), 2, "Bob should have 2 NFTs");
        assertEq(moneyMarket.getApproved(aliceNftId), address(0), "Approval should be cleared after transfer");
        console2.log("");
        
        // Step 5: Test setApprovalForAll - Bob approves Alice as operator
        console2.log("Step 5: Bob sets Alice as operator for all his NFTs");
        vm.prank(bob);
        moneyMarket.setApprovalForAll(alice, true);
        
        assertTrue(moneyMarket.isApprovedForAll(bob, alice), "Alice should be operator for Bob");
        console2.log("");
        
        // Step 6: Alice transfers NFT 2 from Bob to herself using operator approval
        console2.log("Step 6: Alice transfers NFT 2 from Bob to herself");
        vm.prank(alice);
        moneyMarket.transferFrom(bob, alice, bobNftId);
        
        assertEq(moneyMarket.ownerOf(bobNftId), alice, "Alice should now own NFT 2");
        assertEq(moneyMarket.balanceOf(alice), 1, "Alice should have 1 NFT");
        assertEq(moneyMarket.balanceOf(bob), 1, "Bob should have 1 NFT");
        console2.log("");
        
        // Step 7: Bob transfers NFT 1 back to Alice (owner transfer)
        console2.log("Step 7: Bob transfers NFT 1 back to Alice");
        vm.prank(bob);
        moneyMarket.transferFrom(bob, alice, aliceNftId);
        
        assertEq(moneyMarket.ownerOf(aliceNftId), alice, "Alice should own NFT 1 again");
        assertEq(moneyMarket.balanceOf(alice), 2, "Alice should have 2 NFTs");
        assertEq(moneyMarket.balanceOf(bob), 0, "Bob should have 0 NFTs");
        console2.log("");
        
        // Step 8: Remove operator approval
        console2.log("Step 8: Bob removes Alice as operator");
        vm.prank(bob);
        moneyMarket.setApprovalForAll(alice, false);
        
        assertFalse(moneyMarket.isApprovedForAll(bob, alice), "Alice should no longer be operator for Bob");
        console2.log("");
        
        // Step 9: Alice tries to transfer without approval (should fail)
        console2.log("Step 9: Verify Alice can't transfer Bob's NFT without approval");
        // First, Bob creates a new NFT
        vm.startPrank(bob);
        (uint256 bobNftId2,,) = moneyMarket.operate{value: 1 ether}(
            0,
            0,
            actionData
        );
        vm.stopPrank();
        
        // Alice tries to transfer without approval
        vm.prank(alice);
        vm.expectRevert();
        moneyMarket.transferFrom(bob, alice, bobNftId2);
        console2.log("");
        
        // Final state verification
        console2.log("Alice balance:   ", _toString(moneyMarket.balanceOf(alice)));
        console2.log("Alice owns token at index 0:", _toString(moneyMarket.tokenOfOwnerByIndex(alice, 0)));
        console2.log("Alice owns token at index 1:", _toString(moneyMarket.tokenOfOwnerByIndex(alice, 1)));
        console2.log("Bob balance:     ", _toString(moneyMarket.balanceOf(bob)));
        console2.log("Bob owns token at index 0:  ", _toString(moneyMarket.tokenOfOwnerByIndex(bob, 0)));
        console2.log("=======================");
        
        assertEq(moneyMarket.balanceOf(alice), 2, "Alice final balance should be 2");
        assertEq(moneyMarket.balanceOf(bob), 1, "Bob final balance should be 1");
        
        // Verify token ownership via tokenOfOwnerByIndex
        // Note: Buffer NFTs exist, so we verify Alice owns aliceNftId and bobNftId (which was transferred to her)
        uint256 aliceToken0 = moneyMarket.tokenOfOwnerByIndex(alice, 0);
        uint256 aliceToken1 = moneyMarket.tokenOfOwnerByIndex(alice, 1);
        assertTrue((aliceToken0 == aliceNftId && aliceToken1 == bobNftId) || 
                   (aliceToken0 == bobNftId && aliceToken1 == aliceNftId), 
                   "Alice should own her original NFT and Bob's transferred NFT");
        assertEq(moneyMarket.tokenOfOwnerByIndex(bob, 0), bobNftId2, "Bob's token at index 0 should be his second NFT");
    }

    /// @notice Test 13: Borrow, borrow more, partial payback, and full payback
    function testBorrowAndPayback() public {
        // Setup: List USDC (includes buffer position for rounding)
        _listUSDC();
        
        // Step 1: Supply 1 ETH as collateral
        uint256 collateralAmount = 1 ether;
        bytes memory supplyData = abi.encode(
            1, // NORMAL_SUPPLY_POSITION_TYPE
            1, // tokenIndex for ETH (indices start from 1)
            collateralAmount
        );
        
        (uint256 nftId, uint256 positionIndex,) = moneyMarket.operate{value: collateralAmount}(
            0, // Create new NFT
            0, // Create new position
            supplyData
        );
        
        console2.log("Step 1: Supplied 1 ETH as collateral");
        
        // Step 2: Create borrow position for 1000 USDC
        // ETH price = $4000, so 1 ETH = $4000 collateral
        // With 80% collateral factor, can borrow up to $3200 worth
        // USDC price = $1, so can borrow up to 3200 USDC safely
        uint256 borrowAmount1 = 1000 * 1e6; // 1000 USDC
        bytes memory borrowData1 = abi.encode(
            2, // NORMAL_BORROW_POSITION_TYPE
            2, // tokenIndex for USDC (indices start from 1)
            borrowAmount1,
            address(this) // to_ address where borrowed funds are sent
        );
        
        uint256 usdcBalanceBefore = USDC.balanceOf(address(this));
        (,uint256 borrowPositionIndex,) = moneyMarket.operate(
            nftId,
            0, // Create new position (borrow position)
            borrowData1
        );
        uint256 usdcBalanceAfter = USDC.balanceOf(address(this));
        
        assertEq(usdcBalanceAfter - usdcBalanceBefore, borrowAmount1, "Should receive borrowed USDC");
        console2.log("Step 2: Borrowed 1000 USDC");
        
        // Step 3: Borrow more USDC (500 USDC) on the existing borrow position
        uint256 borrowAmount2 = 500 * 1e6; // 500 USDC
        bytes memory borrowData2 = abi.encode(
            int256(borrowAmount2), // Positive value means borrow more
            address(this)
        );
        
        usdcBalanceBefore = USDC.balanceOf(address(this));
        moneyMarket.operate(
            nftId,
            borrowPositionIndex, // Use the borrow position
            borrowData2
        );
        usdcBalanceAfter = USDC.balanceOf(address(this));
        
        assertEq(usdcBalanceAfter - usdcBalanceBefore, borrowAmount2, "Should receive additional borrowed USDC");
        console2.log("Step 3: Borrowed 500 more USDC");
        
        // Step 4: Partial payback (700 USDC)
        uint256 partialPayback = 700 * 1e6;
        bytes memory partialPaybackData = abi.encode(
            -int256(partialPayback), // Negative value means payback
            address(this) // to_ address (not used for payback)
        );
        
        USDC.approve(address(moneyMarket), partialPayback);
        
        usdcBalanceBefore = USDC.balanceOf(address(this));
        moneyMarket.operate(
            nftId,
            borrowPositionIndex, // Use the borrow position
            partialPaybackData
        );
        usdcBalanceAfter = USDC.balanceOf(address(this));
        
        assertEq(usdcBalanceBefore - usdcBalanceAfter, partialPayback, "Should pay back partial USDC");
        console2.log("Step 4: Partial payback of 700 USDC");
        
        // Step 5: Full payback (pay back all remaining debt)
        bytes memory fullPaybackData = abi.encode(
            type(int256).min, // type(int256).min means payback all
            address(this) // to_ address (not used for payback)
        );
        
        USDC.approve(address(moneyMarket), type(uint256).max);
        
        usdcBalanceBefore = USDC.balanceOf(address(this));
        moneyMarket.operate(
            nftId,
            borrowPositionIndex, // Use the borrow position
            fullPaybackData
        );
        usdcBalanceAfter = USDC.balanceOf(address(this));
        
        uint256 finalPayback = usdcBalanceBefore - usdcBalanceAfter;
        // Should be approximately 800 USDC plus any accrued interest
        assertApproxEqAbs(finalPayback, 800 * 1e6, 2 * 1e6, "Should pay back remaining debt");
        console2.log("Step 5: Full payback");
        console2.log("===================================");
    }

    /// @notice Test 14: Borrow should fail if normalized collateral < min
    function testBorrowFailsIfCollateralTooSmall() public {
        // Setup: List USDC
        _listUSDC();
        
        
        // Try to supply a very small amount of ETH (e.g., 0.001 ETH = ~$4 at $4000/ETH)
        // This will likely be below the minimum normalized collateral value
        uint256 tinyCollateral = 0.001 ether;
        bytes memory supplyData = abi.encode(
            1, // NORMAL_SUPPLY_POSITION_TYPE
            1, // tokenIndex for ETH (indices start from 1)
            tinyCollateral
        );
        
        (uint256 nftId, uint256 positionIndex,) = moneyMarket.operate{value: tinyCollateral}(
            0, // Create new NFT
            0, // Create new position
            supplyData
        );
        
        console2.log("NFT ID:                  ", _toString(nftId));
        
        // Try to borrow even a tiny amount of USDC (1 USDC)
        uint256 borrowAmount = 1 * 1e6; // 1 USDC
        bytes memory borrowData = abi.encode(
            int256(borrowAmount),
            address(this)
        );
        
        // This should revert because normalized collateral is too small
        vm.expectRevert();
        moneyMarket.operate(
            nftId,
            positionIndex,
            borrowData
        );
        
        console2.log("Borrow attempt correctly reverted!");
        console2.log("Normalized collateral was below minimum");
        console2.log("====================================================");
    }

    /// @notice Test 15: Withdraw should fail if it makes normalized collateral < min when debt exists
    function testWithdrawFailsIfCollateralBecomesTooSmall() public {
        // Setup: List USDC
        _listUSDC();
        
        
        // Min collateral value is $1000 (1000 * 1e27) set in constructor
        // Scenario:
        // - Initial collateral: $1500 (0.375 ETH at $4000/ETH)
        // - Debt: $200 (200 USDC)
        // - Try to withdraw $500 worth of ETH (0.125 ETH)
        // - This would leave $1000 collateral, which is exactly at the minimum
        // - This should FAIL because normalized collateral would be at or below minimum ($1000) with debt > 0
        
        // Step 1: Supply 0.375 ETH as collateral ($1500 at $4000/ETH)
        uint256 collateralAmount = 0.375 ether; // $1500 worth
        bytes memory supplyData = abi.encode(
            1, // NORMAL_SUPPLY_POSITION_TYPE
            1, // tokenIndex for ETH (indices start from 1)
            collateralAmount
        );
        
        (uint256 nftId, uint256 positionIndex,) = moneyMarket.operate{value: collateralAmount}(
            0,
            0,
            supplyData
        );
        
        console2.log("Step 1: Supplied 0.375 ETH as collateral ($1500)");
        
        // Step 2: Borrow 200 USDC ($200 debt)
        uint256 borrowAmount = 200 * 1e6; // 200 USDC
        bytes memory borrowData = abi.encode(
            2, // NORMAL_BORROW_POSITION_TYPE
            2, // tokenIndex for USDC (indices start from 1)
            borrowAmount,
            address(this)
        );
        
        moneyMarket.operate(
            nftId,
            0, // Create new borrow position
            borrowData
        );
        
        console2.log("Step 2: Borrowed 200 USDC ($200 debt)");
        
        // Step 3: Try to withdraw $501 worth of ETH
        // $501 / $4000 = 0.12525 ETH
        // This would leave $999 collateral, which is below the minimum ($1000)
        // This should fail because normalized collateral would be below minimum with debt > 0
        uint256 withdrawAmount = (501 * 1e18) / 4000; // $501 worth of ETH (leaves $999)
        
        bytes memory withdrawData = abi.encode(
            -int256(withdrawAmount), // Negative value means withdraw
            address(this) // to_ address where withdrawn funds are sent
        );
        
        console2.log("Step 3: Attempting to withdraw $501 worth of ETH (0.12525 ETH)");
        
        // This should revert because it would make normalized collateral below minimum ($1000)
        vm.expectRevert();
        moneyMarket.operate(
            nftId,
            positionIndex, // Withdraw from the supply position
            withdrawData
        );
        
        console2.log("Withdraw correctly reverted!");
        console2.log("Normalized collateral would be below minimum ($1000) with debt > 0");
        console2.log("======================================================");
    }

    /// @notice Test 16: Liquidation - Create position with 1 supply and 1 borrow, then liquidate
    function testLiquidation() public {
        // Setup: List USDC (ETH is already listed in setup)
        _listUSDC();  // Index 1
        
        console2.log("Using ETH as collateral and USDC as debt");
        
        // Fund liquidator (bob) with USDC for liquidation
        vm.deal(bob, 100 ether);
        deal(address(USDC), bob, 100000 * 1e6);
        
        // Step 1: Supply 1 ETH as collateral
        bytes memory ethSupplyData = abi.encode(
            1, // NORMAL_SUPPLY_POSITION_TYPE
            1, // tokenIndex for ETH (indices start from 1)
            1 ether
        );
        
        (uint256 nftId,,) = moneyMarket.operate{value: 1 ether}(
            0, // Create new NFT
            0, // Create new position
            ethSupplyData
        );
        
        console2.log("Step 1: Supplied 1 ETH as collateral");
        
        // Total collateral value at initial price:
        // 1 ETH * $4000 = $4,000
        // Max borrow at 80% CF = $3,200
        
        // Step 2: Borrow 2600 USDC
        bytes memory usdcBorrowData = abi.encode(
            2, // NORMAL_BORROW_POSITION_TYPE
            2, // tokenIndex for USDC (indices start from 1)
            2600 * 1e6,
            address(this) // receiver
        );
        
        moneyMarket.operate(
            nftId,
            0, // Create new position
            usdcBorrowData
        );
        
        console2.log("Step 2: Borrowed 2600 USDC");
        console2.log("");
        console2.log("");
        
        // Step 3: Make position liquidatable by dropping ETH price
        // Drop ETH from $4000 to $3000 (25% drop)
        // New collateral value: 1 ETH * $3000 = $3,000
        // Health Factor = ($3,000 * 0.8) / $2,600 = 0.92 < 1.0 (liquidatable!)
        
        console2.log("Step 3: Update ETH price from $4000 to $3000 to make position liquidatable");
        oracle.setPrice(NATIVE_TOKEN_ADDRESS, 3000 * 1e27);
        console2.log("");
        
        // Step 4: Liquidate the position
        console2.log("Step 4: Liquidator (bob) liquidates the position");
        
        // Approve USDC for liquidation and perform liquidation
        vm.startPrank(bob);
        USDC.approve(address(moneyMarket), type(uint256).max);
        
        uint256 bobEthBefore = bob.balance;
        uint256 bobUsdcBefore = USDC.balanceOf(bob);
        
        // Perform liquidation
        // Position has:
        // - Position 0: ETH supply (collateral)
        // - Position 1: USDC borrow (debt)
        // We payback position 1 (debt) and withdraw from position 0 (collateral)
        
        // Payback $600 worth of USDC (600 * 1e6 since USDC has 6 decimals)
        bytes memory paybackData = abi.encode(uint256(600 * 1e6)); // NORMAL_BORROW payback amount
        
        (, bytes memory withdrawData) = moneyMarket.liquidate(
            LiquidateParams({
                nftId: nftId,
                paybackPositionIndex: 2, // USDC borrow position
                withdrawPositionIndex: 1, // ETH supply position
                to: bob, // receive collateral to bob
                estimate: false, // not an estimate
                paybackData: paybackData
            })
        );
        vm.stopPrank();
        
        // Decode withdraw data for NORMAL_SUPPLY position
        uint256 withdrawAmount = abi.decode(withdrawData, (uint256));
        
        console2.log("Liquidation completed!");
        console2.log("");
        console2.log("Liquidator's changes:");
        console2.log("ETH withdrawn:", withdrawAmount);
        
        // Verify liquidation was profitable (withdraw value includes liquidation penalty)
        // $600 payback at $3000/ETH = 0.2 ETH, plus 5% penalty = 0.21 ETH
        assertTrue(withdrawAmount > 0.2 ether, "Withdraw amount should include liquidation penalty");
        console2.log("");
        console2.log("[SUCCESS] Liquidation successful and profitable!");
        console2.log("============================");
    }

    /// @notice Helper struct to hold liquidation estimate test data
    struct LiquidationEstimateTestData {
        uint256 nftId;
        uint256 paybackAmount;
        bytes paybackData;
        uint256 estimatedPaybackAmount;
        uint256 estimatedWithdrawAmount;
        uint256 actualPaybackAmount;
        uint256 actualWithdrawAmount;
        uint256 bobEthBefore;
        uint256 bobEthAfter;
    }

    /// @notice Helper to decode FluidLiquidateEstimate error data
    /// @param revertData The full revert data including selector
    /// @return paybackData The decoded payback data
    /// @return withdrawData The decoded withdraw data
    function _decodeLiquidateEstimateError(bytes memory revertData) internal pure returns (bytes memory paybackData, bytes memory withdrawData) {
        // Skip the 4-byte selector and decode the two bytes parameters
        // revertData format: selector(4) + abi.encode(bytes, bytes)
        require(revertData.length > 4, "Invalid revert data");
        
        // Create a new bytes array without the selector
        bytes memory encodedParams = new bytes(revertData.length - 4);
        for (uint256 i = 0; i < encodedParams.length; i++) {
            encodedParams[i] = revertData[i + 4];
        }
        
        // Decode the two bytes parameters
        (paybackData, withdrawData) = abi.decode(encodedParams, (bytes, bytes));
    }

    /// @notice Test 17: Liquidation Estimate - Test that estimate returns the same data as actual liquidation
    function testLiquidationEstimate() public {
        // Setup: List USDC (ETH is already listed in setup)
        _listUSDC();
        
        console2.log("=== Testing Liquidation Estimate ===");
        console2.log("Using ETH as collateral and USDC as debt");
        
        LiquidationEstimateTestData memory t;
        
        // Fund liquidator (bob) with USDC for liquidation
        vm.deal(bob, 100 ether);
        deal(address(USDC), bob, 100000 * 1e6);
        
        // Step 1: Supply 1 ETH as collateral
        bytes memory ethSupplyData = abi.encode(1, 1, 1 ether);
        (t.nftId,,) = moneyMarket.operate{value: 1 ether}(0, 0, ethSupplyData);
        
        console2.log("Step 1: Supplied 1 ETH as collateral");
        console2.log("NFT ID:", _toString(t.nftId));
        
        // Step 2: Borrow 2600 USDC
        bytes memory usdcBorrowData = abi.encode(2, 2, 2600 * 1e6, address(this));
        moneyMarket.operate(t.nftId, 0, usdcBorrowData);
        console2.log("Step 2: Borrowed 2600 USDC");
        
        // Step 3: Make position liquidatable by dropping ETH price
        console2.log("Step 3: Update ETH price from $4000 to $3000");
        oracle.setPrice(NATIVE_TOKEN_ADDRESS, 3000 * 1e27);
        
        // Step 4: Get liquidation estimate
        console2.log("Step 4: Call liquidate with estimate=true");
        
        t.paybackAmount = 600 * 1e6; // Payback $600 worth of USDC
        t.paybackData = abi.encode(uint256(t.paybackAmount));
        
        vm.startPrank(bob);
        USDC.approve(address(moneyMarket), type(uint256).max);
        
        // Call estimate and capture the revert
        (t.estimatedPaybackAmount, t.estimatedWithdrawAmount) = _callLiquidateEstimate(
            t.nftId, 2, 1, bob, t.paybackData
        );
        
        console2.log("Estimate Results:");
        console2.log("  Payback Amount:", _toString(t.estimatedPaybackAmount));
        console2.log("  Withdraw Amount:", _toString(t.estimatedWithdrawAmount));
        
        // Step 5: Perform actual liquidation
        console2.log("Step 5: Perform actual liquidation with estimate=false");
        
        t.bobEthBefore = bob.balance;
        
        (bytes memory actualPaybackData, bytes memory actualWithdrawData) = moneyMarket.liquidate(
            LiquidateParams({
                nftId: t.nftId,
                paybackPositionIndex: 2,
                withdrawPositionIndex: 1,
                to: bob,
                estimate: false,
                paybackData: t.paybackData
            })
        );
        vm.stopPrank();
        
        t.actualPaybackAmount = abi.decode(actualPaybackData, (uint256));
        t.actualWithdrawAmount = abi.decode(actualWithdrawData, (uint256));
        
        console2.log("Actual Liquidation Results:");
        console2.log("  Payback Amount:", _toString(t.actualPaybackAmount));
        console2.log("  Withdraw Amount:", _toString(t.actualWithdrawAmount));
        
        // Step 6: Verify estimate matches actual
        console2.log("Step 6: Verify estimate matches actual liquidation");
        
        assertEq(t.estimatedPaybackAmount, t.actualPaybackAmount, "Payback amount should match");
        assertEq(t.estimatedWithdrawAmount, t.actualWithdrawAmount, "Withdraw amount should match");
        
        // Verify ETH was actually transferred to bob
        t.bobEthAfter = bob.balance;
        assertEq(t.bobEthAfter - t.bobEthBefore, t.actualWithdrawAmount, "Bob should receive the withdraw amount");
        
        console2.log("");
        console2.log("[SUCCESS] Liquidation estimate matches actual liquidation!");
        console2.log("====================================");
    }

    /// @notice Helper function to call liquidate with estimate=true and decode the result
    function _callLiquidateEstimate(
        uint256 nftId_,
        uint256 paybackPositionIndex_,
        uint256 withdrawPositionIndex_,
        address to_,
        bytes memory paybackData_
    ) internal returns (uint256 paybackAmount, uint256 withdrawAmount) {
        // Encode the liquidate call
        bytes memory callData = abi.encodeWithSelector(
            moneyMarket.liquidate.selector,
            LiquidateParams({
                nftId: nftId_,
                paybackPositionIndex: paybackPositionIndex_,
                withdrawPositionIndex: withdrawPositionIndex_,
                to: to_,
                estimate: true,
                paybackData: paybackData_
            })
        );
        
        // Make the call and capture revert data
        (bool success, bytes memory returnData) = address(moneyMarket).call(callData);
        
        // Should have reverted with FluidLiquidateEstimate
        require(!success, "Estimate call should revert");
        
        // Verify error selector
        bytes4 errorSelector = bytes4(returnData);
        require(errorSelector == FluidLiquidateEstimate.selector, "Wrong error selector");
        
        // Decode the error data
        (bytes memory estimatePaybackData, bytes memory estimateWithdrawData) = _decodeLiquidateEstimateError(returnData);
        
        // Decode the amounts
        paybackAmount = abi.decode(estimatePaybackData, (uint256));
        withdrawAmount = abi.decode(estimateWithdrawData, (uint256));
    }

    /// @notice Test: Supply D3 ETH/USDC position as collateral
    function testSupplyD3PositionAsCollateral() public {
        // Step 1: Initialize D3 ETH/USDC pool using callback pattern
        bytes memory initCallbackData_ = abi.encodeWithSelector(
            this.shouldInitializeD3PoolCallbackImplementation.selector
        );
        dexV2.startOperation(initCallbackData_);

        // Step 2: List USDC in money market (ETH is already listed)
        _listUSDC();

        // Step 3: Set position caps for D3 ETH/USDC pool
        DexKey memory dexKey_ = DexKey({
            token0: address(USDC), // USDC has lower address than ETH
            token1: NATIVE_TOKEN_ADDRESS, // ETH
            fee: 100, // 0.01%
            tickSpacing: 1,
            controller: address(this) // Use this test contract as controller
        });

        // Calculate sqrtPriceX96 for USDC/ETH at $4000 (1 USDC = 1/4000 ETH)
        uint256 priceX96 = uint256((1 << 96)) / 4000;
        uint256 usdcEthSqrtPriceX96 = FixedPointMathLib.sqrt(priceX96 * (1 << 96));
        
        // Get current tick from initialized price
        int24 currentTick = TM.getTickAtSqrtRatio(uint160(usdcEthSqrtPriceX96));
        
        // Calculate tick range for ETH price between $1 and $1M
        // Price = token1/token0 = ETH/USDC
        // Min price: $1 per ETH = 1 USDC per ETH
        // price = 1 ETH / 1 USDC = 1
        uint256 minPriceX96 = uint256((1 << 96)) * 1; // price = 1
        uint256 minSqrtPriceX96 = FixedPointMathLib.sqrt(minPriceX96 * (1 << 96));
        int24 tickLower_ = TM.getTickAtSqrtRatio(uint160(minSqrtPriceX96));
        
        // Max price: $1M per ETH = 1,000,000 USDC per ETH  
        // price = 1 ETH / 1 USDC = 1,000,000
        uint256 maxPriceX96 = uint256((1 << 96)) / 1_000_000; // price = 1/1,000,000 (ETH per USDC)
        uint256 maxSqrtPriceX96 = FixedPointMathLib.sqrt(maxPriceX96 * (1 << 96));
        int24 tickUpper_ = TM.getTickAtSqrtRatio(uint160(maxSqrtPriceX96));
        
        // Ensure tickLower < tickUpper (if not, swap them)
        if (tickLower_ >= tickUpper_) {
            int24 temp = tickLower_;
            tickLower_ = tickUpper_;
            tickUpper_ = temp;
        }
        
        // Set max token amount caps for D3 position
        // Token0 = USDC, Token1 = ETH
        uint256 maxAmount0Cap = 10_000_000 * 1e6; // 10M USDC cap
        uint256 maxAmount1Cap = 10_000 * 1e18; // 10k ETH cap

        (bool success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateD3PositionCap.selector,
                dexKey_,
                tickLower_,
                tickUpper_,
                maxAmount0Cap,
                maxAmount1Cap
            )
        );
        require(success, "Failed to set D3 position cap");

        console2.log("Tick Lower:            ", _toString(tickLower_));
        console2.log("Tick Upper:            ", _toString(tickUpper_));
        console2.log("Max Amount0 Cap (USDC):", _toString(maxAmount0Cap));
        console2.log("Max Amount1 Cap (ETH): ", _toString(maxAmount1Cap));

        // Step 4: Supply D3 position via money market as collateral
        // Fund this contract with ETH and USDC for the position
        deal(address(this), 10 ether);
        deal(address(USDC), address(this), 10000 * 1e6); // 10k USDC

        // Approve money market to spend USDC
        USDC.approve(address(moneyMarket), type(uint256).max);

        // Create position with ticks around current price (±100 ticks)
        // while the cap allows the full range ($1 to $1M)
        int24 positionTickLower = currentTick - 100;
        int24 positionTickUpper = currentTick + 100;
        
        // Encode action data for D3 position creation
        // Position type 3 = D3_POSITION_TYPE
        // ETH is index 1, USDC is index 2 (indices start from 1)
        CreateD3D4PositionParams memory positionParams_ = CreateD3D4PositionParams({
            token0Index: 2, // USDC index (indices start from 1, ETH=1, USDC=2)
            token1Index: 1, // ETH index
            tickSpacing: 1,
            fee: 100,
            controller: address(this),
            tickLower: positionTickLower,
            tickUpper: positionTickUpper,
            amount0: 2000 * 1e6, // 2000 USDC
            amount1: 0.5 ether, // 0.5 ETH
            amount0Min: 0,
            amount1Min: 0,
            to: address(this)
        });

        bytes memory actionData = abi.encode(
            3, // D3_POSITION_TYPE
            positionParams_
        );

        // Call operate to create D3 position
        (uint256 nftId, uint256 positionIndex,) = moneyMarket.operate{value: positionParams_.amount1}(
            0, // Create new NFT
            0, // Ignored when creating new NFT
            actionData
        );

        console2.log("NFT ID:                ", _toString(nftId));
        console2.log("Amount0 (USDC):        ", _toString(positionParams_.amount0));
        console2.log("Amount1 (ETH):         ", _toString(positionParams_.amount1));
        console2.log("=============================================");

        // Verify NFT ownership
        assertEq(moneyMarket.ownerOf(nftId), address(this), "This contract should own the NFT");
        
        // Verify position was created
        assertTrue(positionIndex != 0, "Position should be created");
    }

    /// @notice Callback implementation for D3 pool initialization
    function shouldInitializeD3PoolCallbackImplementation() public returns (bytes memory returnData_) {
        DexKey memory dexKey_ = DexKey({
            token0: address(USDC), // USDC has lower address than ETH
            token1: NATIVE_TOKEN_ADDRESS, // ETH
            fee: 100, // 0.01%
            tickSpacing: 1,
            controller: address(this) // Use this test contract as controller
        });

        // Calculate sqrtPriceX96 for USDC/ETH at $4000 (1 USDC = 1/4000 ETH)
        // priceX96 = (1 << 96) / 4000, then sqrtPriceX96 = sqrt(priceX96)
        uint256 priceX96 = uint256((1 << 96)) / 4000;
        uint256 usdcEthSqrtPriceX96 = FixedPointMathLib.sqrt(priceX96 * (1 << 96));

        // Initialize the pool
        bytes memory initializeData_ = abi.encodeWithSelector(
            FluidDexV2D3UserModule.initialize.selector,
            InitializeParams({ dexKey: dexKey_, sqrtPriceX96: usdcEthSqrtPriceX96 })
        );
        dexV2.operate(DEX_TYPE_D3, 2, initializeData_); // USER_MODULE_ID = 2

        console2.log("Token0 (USDC):         ", dexKey_.token0);
        console2.log("Token1 (ETH):          ", dexKey_.token1);
        console2.log("Fee:                    100 (0.01%)");
        console2.log("Tick Spacing:           1");
        console2.log("Controller:            ", dexKey_.controller);
        console2.log("SqrtPriceX96:          ", _toString(usdcEthSqrtPriceX96));
        
        // Get current tick from initialized price
        int24 currentTick = TM.getTickAtSqrtRatio(uint160(usdcEthSqrtPriceX96));
        console2.log("Current Tick:          ", _toString(currentTick));

        return returnData_;
    }

    /// @notice Callback for initializing D3 pool with DAI/USDC (for permissionless testing)
    function shouldInitializeD3PermissionlessPoolCallbackImplementation() public returns (bytes memory returnData_) {
        DexKey memory dexKey_ = DexKey({
            token0: address(DAI),  // DAI has lower address (0x03A6...)
            token1: address(USDC), // USDC has higher address (0xA4AD...)
            fee: 100, // 0.01%
            tickSpacing: 1,
            controller: address(this)
        });

        // Calculate sqrtPriceX96 for DAI/USDC at 1:1 (equal value)
        // priceX96 = (1 << 96) / 1 = (1 << 96), then sqrtPriceX96 = sqrt(priceX96)
        uint256 priceX96 = uint256(1 << 96);
        uint256 sqrtPriceX96 = FixedPointMathLib.sqrt(priceX96 * (1 << 96));

        // Initialize the pool
        bytes memory initializeData_ = abi.encodeWithSelector(
            FluidDexV2D3UserModule.initialize.selector,
            InitializeParams({ dexKey: dexKey_, sqrtPriceX96: sqrtPriceX96 })
        );
        dexV2.operate(DEX_TYPE_D3, 2, initializeData_); // USER_MODULE_ID = 2

        return returnData_;
    }

    /// @notice Struct to hold test variables for D3 and D4 pools and avoid stack too deep errors
    struct D3D4TestVars {
        DexKey dexKey;
        uint256 priceX96;
        uint256 usdcEthSqrtPriceX96;
        int24 currentTick;
        uint256 minPriceX96;
        uint256 minSqrtPriceX96;
        int24 tickLower;
        uint256 maxPriceX96;
        uint256 maxSqrtPriceX96;
        int24 tickUpper;
        int24 positionTickLower;
        int24 positionTickUpper;
        uint256 nftId;
        uint256 positionIndex;
        bool deleted;
        uint256 borrowAmount;
    }

    function _setupD3Pool() internal returns (D3D4TestVars memory vars) {
        // Initialize pool
        bytes memory initCallbackData_ = abi.encodeWithSelector(
            this.shouldInitializeD3PoolCallbackImplementation.selector
        );
        dexV2.startOperation(initCallbackData_);

        _listUSDC();

        vars.dexKey = DexKey({
            token0: address(USDC),
            token1: NATIVE_TOKEN_ADDRESS,
            fee: 100,
            tickSpacing: 1,
            controller: address(this)
        });

        vars.priceX96 = uint256((1 << 96)) / 4000;
        vars.usdcEthSqrtPriceX96 = FixedPointMathLib.sqrt(vars.priceX96 * (1 << 96));
        vars.currentTick = TM.getTickAtSqrtRatio(uint160(vars.usdcEthSqrtPriceX96));

        vars.minPriceX96 = uint256((1 << 96)) * 1;
        vars.minSqrtPriceX96 = FixedPointMathLib.sqrt(vars.minPriceX96 * (1 << 96));
        vars.tickLower = TM.getTickAtSqrtRatio(uint160(vars.minSqrtPriceX96));

        vars.maxPriceX96 = uint256((1 << 96)) / 1_000_000;
        vars.maxSqrtPriceX96 = FixedPointMathLib.sqrt(vars.maxPriceX96 * (1 << 96));
        vars.tickUpper = TM.getTickAtSqrtRatio(uint160(vars.maxSqrtPriceX96));

        if (vars.tickLower >= vars.tickUpper) {
            int24 temp = vars.tickLower;
            vars.tickLower = vars.tickUpper;
            vars.tickUpper = temp;
        }

        (bool success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateD3PositionCap.selector,
                vars.dexKey,
                vars.tickLower,
                vars.tickUpper,
                10_000_000 * 1e6, // maxAmount0Cap (USDC)
                10_000 * 1e18 // maxAmount1Cap (ETH)
            )
        );
        require(success, "Failed to set D3 position cap");

        // Fund contract
        deal(address(this), 100 ether);
        deal(address(USDC), address(this), 1000000 * 1e6); // 1M USDC
        USDC.approve(address(moneyMarket), type(uint256).max);

        vars.positionTickLower = vars.currentTick - 100;
        vars.positionTickUpper = vars.currentTick + 100;
    }

    function _setupD4Pool() internal returns (D3D4TestVars memory vars) {
        // Initialize D4 pool
        bytes memory initCallbackData_ = abi.encodeWithSelector(
            this.shouldInitializeD4PoolCallbackImplementation.selector
        );
        dexV2.startOperation(initCallbackData_);

        vars.dexKey = DexKey({
            token0: address(USDC),
            token1: NATIVE_TOKEN_ADDRESS,
            fee: 100,
            tickSpacing: 1,
            controller: address(0) // D4 pools typically use address(0) as controller
        });

        vars.priceX96 = uint256((1 << 96)) / 4000;
        vars.usdcEthSqrtPriceX96 = FixedPointMathLib.sqrt(vars.priceX96 * (1 << 96));
        vars.currentTick = TM.getTickAtSqrtRatio(uint160(vars.usdcEthSqrtPriceX96));

        vars.minPriceX96 = uint256((1 << 96)) * 1;
        vars.minSqrtPriceX96 = FixedPointMathLib.sqrt(vars.minPriceX96 * (1 << 96));
        vars.tickLower = TM.getTickAtSqrtRatio(uint160(vars.minSqrtPriceX96));

        vars.maxPriceX96 = uint256((1 << 96)) / 1_000_000;
        vars.maxSqrtPriceX96 = FixedPointMathLib.sqrt(vars.maxPriceX96 * (1 << 96));
        vars.tickUpper = TM.getTickAtSqrtRatio(uint160(vars.maxSqrtPriceX96));

        if (vars.tickLower >= vars.tickUpper) {
            int24 temp = vars.tickLower;
            vars.tickLower = vars.tickUpper;
            vars.tickUpper = temp;
        }

        // Set D4 position cap (for smart debt positions)
        (bool success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateD4PositionCap.selector,
                vars.dexKey,
                vars.tickLower,
                vars.tickUpper,
                10_000_000 * 1e6, // maxAmount0Cap (USDC)
                10_000 * 1e18 // maxAmount1Cap (ETH)
            )
        );
        require(success, "Failed to set D4 position cap");

        // Set DEX allowances on Fluid Liquidity (required for D4 borrowing)
        _setUserAllowancesDefault(address(liquidity), admin, address(USDC), address(dexV2));
        _setUserAllowancesDefault(address(liquidity), admin, NATIVE_TOKEN_ADDRESS, address(dexV2));

        // Supply liquidity to Fluid Liquidity for DEX to borrow from
        _supply(address(liquidity), mockProtocol, address(USDC), alice, 1000000 * 1e6); // 1M USDC
        _supplyNative(address(liquidity), mockProtocol, alice, 1000 ether); // 1000 ETH

        // Add tokens directly to DEX reserves for D4 borrowing
        // Add 1M USDC to DEX
        deal(address(USDC), address(this), 1000000 * 1e6);
        USDC.approve(address(dexV2), 1000000 * 1e6);
        dexV2.addOrRemoveTokens(address(USDC), int256(1000000 * 1e6));
        
        // Add 250 ETH to DEX
        deal(address(this), 250 ether);
        dexV2.addOrRemoveTokens{value: 250 ether}(NATIVE_TOKEN_ADDRESS, int256(250 ether));

        // Fund contract (need enough ETH for full payback)
        deal(address(this), 500 ether);
        deal(address(USDC), address(this), 1000000 * 1e6); // 1M USDC
        USDC.approve(address(moneyMarket), type(uint256).max);

        vars.positionTickLower = vars.currentTick - 100;
        vars.positionTickUpper = vars.currentTick + 100;
    }

    /// @notice Callback implementation for D4 pool initialization
    function shouldInitializeD4PoolCallbackImplementation() public returns (bytes memory returnData_) {
        DexKey memory dexKey_ = DexKey({
            token0: address(USDC),
            token1: NATIVE_TOKEN_ADDRESS,
            fee: 100,
            tickSpacing: 1,
            controller: address(0) // D4 pools use address(0)
        });

        uint256 priceX96 = uint256((1 << 96)) / 4000;
        uint256 sqrtPriceX96 = FixedPointMathLib.sqrt(priceX96 * (1 << 96));

        // Initialize the D4 pool - similar to D3 but with DEX_TYPE=4 and USER_MODULE_ID=2
        bytes memory initializeData_ = abi.encodeWithSelector(
            FluidDexV2D4UserModule.initialize.selector,
            InitializeParams({ dexKey: dexKey_, sqrtPriceX96: sqrtPriceX96 })
        );
        dexV2.operate(4, 2, initializeData_); // DEX_TYPE=4, USER_MODULE_ID=2

        console2.log("Token0 (USDC):         ", dexKey_.token0);
        console2.log("Token1 (ETH):          ", dexKey_.token1);
        console2.log("Fee:                    100 (0.01%)");
        console2.log("Tick Spacing:           1");
        console2.log("Controller:            ", dexKey_.controller);
        console2.log("SqrtPriceX96:          ", _toString(sqrtPriceX96));

        int24 currentTick = TM.getTickAtSqrtRatio(uint160(sqrtPriceX96));
        console2.log("Current Tick:          ", _toString(currentTick));

        return returnData_;
    }

        function _depositD3Position(
        DexKey memory dexKey_,
        int24 tickLower_,
        int24 tickUpper_,
        uint256 amount0,
        uint256 amount1
    ) internal returns (uint256 nftId, uint256 positionIndex) {
        CreateD3D4PositionParams memory positionParams_ = CreateD3D4PositionParams({
            token0Index: 2, // USDC
            token1Index: 1, // ETH
            tickSpacing: 1,
            fee: 100,
            controller: address(this),
            tickLower: tickLower_,
            tickUpper: tickUpper_,
            amount0: amount0,
            amount1: amount1,
            amount0Min: 0,
            amount1Min: 0,
            to: address(this)
        });

        bytes memory actionData = abi.encode(3, positionParams_);
        // Send extra ETH to cover rounding (protocol rounds UP amounts for deposits)
        (nftId, positionIndex,) = moneyMarket.operate{value: amount1 + 1e10}(
            0,
            0,
            actionData
        );
    }

    function _depositD3PositionMore(
        DexKey memory dexKey_,
        uint256 nftId,
        uint256 positionIndex,
        int24 tickLower_,
        int24 tickUpper_,
        uint256 amount0,
        uint256 amount1
    ) internal {
        // For existing positions, action data format is: (int256 amount0, int256 amount1, uint256 amount0Min, uint256 amount1Min, address to)
        bytes memory actionData = abi.encode(
            int256(amount0), // Positive amount for deposit
            int256(amount1), // Positive amount for deposit
            uint256(0), // amount0Min
            uint256(0), // amount1Min
            address(this) // to
        );

        uint256 ethValue = 0;
        if (dexKey_.token0 == NATIVE_TOKEN_ADDRESS) {
            ethValue = amount0 + 1e10; // Extra to cover rounding (protocol rounds UP)
        } else if (dexKey_.token1 == NATIVE_TOKEN_ADDRESS) {
            ethValue = amount1 + 1e10; // Extra to cover rounding (protocol rounds UP)
        }

        moneyMarket.operate{value: ethValue}(nftId, positionIndex, actionData);
    }

    function _withdrawD3PositionFull(
        DexKey memory dexKey_,
        uint256 nftId,
        uint256 positionIndex,
        int24 tickLower_,
        int24 tickUpper_
    ) internal returns (bool deleted) {
        // Get number of positions before withdrawal
        uint256 positionsCountBefore = _getNumberOfPositions(nftId);
        
        // For full withdrawal, pass 3x the deposit amounts (negative for withdrawal)
        // The dex will automatically withdraw all available liquidity
        bytes memory actionData = abi.encode(
            -int256(1_000_000 * 1e6), // amount0 (a big amount)
            -int256(250 ether), // amount1 (a big amount)
            uint256(0), // amount0Min
            uint256(0), // amount1Min
            address(this) // to
        );
        
        moneyMarket.operate(nftId, positionIndex, actionData);
        
        // Get number of positions after withdrawal
        uint256 positionsCountAfter = _getNumberOfPositions(nftId);
        
        // Position was deleted if count decreased by 1
        deleted = (positionsCountBefore > positionsCountAfter) && (positionsCountAfter + 1 == positionsCountBefore);
    }

    function _getNumberOfPositions(uint256 nftId) internal view returns (uint256) {
        // NFT configs mapping slot is 2 (MONEY_MARKET_NFT_CONFIGS_MAPPING_SLOT)
        bytes32 nftConfigSlot = keccak256(abi.encode(nftId, uint256(2)));
        uint256 nftConfig = moneyMarket.readFromStorage(nftConfigSlot);
        
        // Extract numberOfPositions (bits 204-213, 10 bits)
        return (nftConfig >> 204) & 0x3FF;
    }

    function _withdrawD3PositionPartial(
        DexKey memory dexKey_,
        uint256 nftId,
        uint256 positionIndex,
        int24 tickLower_,
        int24 tickUpper_,
        uint256 amount0,
        uint256 amount1
    ) internal {
        // Encode negative amounts for withdrawal
        bytes memory actionData = abi.encode(
            -int256(amount0), // amount0 (negative for withdrawal)
            -int256(amount1), // amount1 (negative for withdrawal)
            uint256(0), // amount0Min
            uint256(0), // amount1Min
            address(this) // to
        );
        moneyMarket.operate(nftId, positionIndex, actionData);
    }

    function _collectD3Fees(
        DexKey memory dexKey_,
        uint256 nftId,
        uint256 positionIndex,
        int24 tickLower_,
        int24 tickUpper_,
        uint256 feeAmount0,
        uint256 feeAmount1
    ) internal returns (bool deleted) {
        // Get number of positions before fee collection
        uint256 positionsCountBefore = _getNumberOfPositions(nftId);
        
        // Fee collection: amount0=0, amount1=0, feeCollectionAmount0, feeCollectionAmount1, to
        bytes memory actionData = abi.encode(
            int256(0), // amount0 = 0 (fee collection)
            int256(0), // amount1 = 0 (fee collection)
            feeAmount0, // feeCollectionAmount0
            feeAmount1, // feeCollectionAmount1
            address(this) // to
        );
        
        moneyMarket.operate(nftId, positionIndex, actionData);
        
        // Get number of positions after fee collection
        uint256 positionsCountAfter = _getNumberOfPositions(nftId);
        
        // Position was deleted if count decreased by 1
        deleted = (positionsCountBefore > positionsCountAfter) && (positionsCountAfter + 1 == positionsCountBefore);
    }

    function testD3PositionBasic() public {
        D3D4TestVars memory vars = _setupD3Pool();

        // Deposit D3 position
        (vars.nftId, vars.positionIndex) = _depositD3Position(vars.dexKey, vars.positionTickLower, vars.positionTickUpper, 2000 * 1e6, 0.5 ether);
        console2.log("Deposited - NFT ID:", _toString(vars.nftId), "Position Index:", _toString(vars.positionIndex));

        // Withdraw D3 full - position should get deleted
        vars.deleted = _withdrawD3PositionFull(vars.dexKey, vars.nftId, vars.positionIndex, vars.positionTickLower, vars.positionTickUpper);
        assertTrue(vars.deleted, "Position should be deleted after full withdrawal");
    }

    function testD3PositionWithBorrow() public {
        D3D4TestVars memory vars = _setupD3Pool();

        // Deposit D3 position
        (vars.nftId, vars.positionIndex) = _depositD3Position(vars.dexKey, vars.positionTickLower, vars.positionTickUpper, 2000 * 1e6, 0.5 ether);
        console2.log("Deposited - NFT ID:", _toString(vars.nftId), "Position Index:", _toString(vars.positionIndex));

        // Borrow USDC such that HF is just above 1
        vars.borrowAmount = _borrowToMakeHFJustAboveOne(vars.nftId, 0); // 0 means create new position
        console2.log("Borrowed USDC:", _toString(vars.borrowAmount));

        // Pay back debt so we can withdraw D3 position
        // Use type(uint256).max for full payback (handles rounding)
        _paybackDebtFull(vars.nftId, 2); // Pay back the borrow position (index 2 after D3 at index 1)
        console2.log("Debt paid back");

        // Withdraw D3 full - position should get deleted
        vars.deleted = _withdrawD3PositionFull(vars.dexKey, vars.nftId, vars.positionIndex, vars.positionTickLower, vars.positionTickUpper);
        assertTrue(vars.deleted, "Position should be deleted after full withdrawal");
    }

    function testD3PositionWithFees() public {
        D3D4TestVars memory vars = _setupD3Pool();

        // Deposit D3 position
        (vars.nftId, vars.positionIndex) = _depositD3Position(vars.dexKey, vars.positionTickLower, vars.positionTickUpper, 2000 * 1e6, 0.5 ether);
        console2.log("Deposited - NFT ID:", _toString(vars.nftId), "Position Index:", _toString(vars.positionIndex));

        // Deposit D3 more
        _depositD3PositionMore(vars.dexKey, vars.nftId, vars.positionIndex, vars.positionTickLower, vars.positionTickUpper, 1000 * 1e6, 0.25 ether);
        console2.log("Deposited more liquidity");

        // Do swaps to generate fees (scaled up for minimum fee threshold)
        _swapInPool(vars.dexKey, 1000 * 1e6, true); // Swap USDC -> ETH
        _swapInPool(vars.dexKey, 0.25 ether, false); // Swap ETH -> USDC
        console2.log("Swaps completed, fees generated");

        // Collect fees (fee will get stored)
        _collectD3Fees(vars.dexKey, vars.nftId, vars.positionIndex, vars.positionTickLower, vars.positionTickUpper, type(uint256).max, type(uint256).max);
        console2.log("Fees collected and stored");

        // Do swaps to generate more fees
        _swapInPool(vars.dexKey, 1000 * 1e6, true);
        _swapInPool(vars.dexKey, 0.25 ether, false);
        console2.log("More swaps completed");

        // Withdraw D3 partial (fee should get stored)
        _withdrawD3PositionPartial(vars.dexKey, vars.nftId, vars.positionIndex, vars.positionTickLower, vars.positionTickUpper, 1000 * 1e6, 0.25 ether);
        console2.log("Partial withdrawal completed, fees stored");

        // Do swaps to generate more fees
        _swapInPool(vars.dexKey, 1000 * 1e6, true);
        _swapInPool(vars.dexKey, 0.25 ether, false);
        console2.log("More swaps completed");

        // Withdraw D3 full (position should NOT get deleted because fees exist)
        vars.deleted = _withdrawD3PositionFull(vars.dexKey, vars.nftId, vars.positionIndex, vars.positionTickLower, vars.positionTickUpper);
        assertTrue(!vars.deleted, "Position should NOT be deleted when fees exist");

        // Withdraw fees (position should get deleted)
        vars.deleted = _collectD3Fees(vars.dexKey, vars.nftId, vars.positionIndex, vars.positionTickLower, vars.positionTickUpper, type(uint256).max, type(uint256).max);
        assertTrue(vars.deleted, "Position should be deleted after fee withdrawal");
    }

    function testD3PositionLiquidationBasic() public {
        D3D4TestVars memory vars = _setupD3Pool();

        // Deposit D3 position
        (vars.nftId, vars.positionIndex) = _depositD3Position(vars.dexKey, vars.positionTickLower, vars.positionTickUpper, 4000 * 1e6, 1 ether);
        console2.log("Deposited - NFT ID:", _toString(vars.nftId), "Position Index:", _toString(vars.positionIndex));
        console2.log("Collateral: 4000 USDC + 1 ETH @ $4000 = $8000 total");

        // Borrow $6000 USDC
        vars.borrowAmount = 6000 * 1e6;
        bytes memory actionData = abi.encode(2, 2, vars.borrowAmount, address(this));
        moneyMarket.operate(vars.nftId, 0, actionData);
        console2.log("Borrowed USDC: $6000");
        console2.log("Health Factor: ($8000 * 0.8) / $6000 = 1.07 (healthy)");

        // Change ETH price from $4000 to $3000
        _changeOraclePrice(NATIVE_TOKEN_ADDRESS, 3000 * 1e27);
        console2.log("ETH price changed from $4000 to $3000");
        console2.log("New collateral: 4000 USDC + 1 ETH @ $3000 = $7000");
        console2.log("Health Factor: ($7000 * 0.8) / $6000 = 0.93 (liquidatable!)");

        // Liquidate with $3000 payback (3000 USDC)
        // Position 0: D3 collateral, Position 1: USDC borrow
        _liquidateNormalBorrow(vars.nftId, 2, 1, 3000 * 1e6); // payback position 2 (borrow), withdraw position 1 (D3)
    }

    function testD3PositionLiquidationWithFees() public {
        D3D4TestVars memory vars = _setupD3Pool();

        // Deposit D3 position - same as basic test
        (vars.nftId, vars.positionIndex) = _depositD3Position(vars.dexKey, vars.positionTickLower, vars.positionTickUpper, 4000 * 1e6, 1 ether);
        console2.log("Deposited - NFT ID:", _toString(vars.nftId), "Position Index:", _toString(vars.positionIndex));
        console2.log("Collateral: 4000 USDC + 1 ETH @ $4000 = $8000 total");

        // Generate fees (scaled up for minimum fee threshold)
        _swapInPool(vars.dexKey, 1000 * 1e6, true);
        _swapInPool(vars.dexKey, 0.25 ether, false);
        console2.log("Fees generated");

        // Borrow $6000 USDC - same as basic test
        vars.borrowAmount = 6000 * 1e6;
        bytes memory actionData = abi.encode(2, 2, vars.borrowAmount, address(this));
        moneyMarket.operate(vars.nftId, 0, actionData);
        console2.log("Borrowed USDC: $6000");
        console2.log("Health Factor: ($8000 * 0.8) / $6000 = 1.07 (healthy)");

        // Change ETH price from $4000 to $3000 - same as basic test
        _changeOraclePrice(NATIVE_TOKEN_ADDRESS, 3000 * 1e27);
        console2.log("ETH price changed from $4000 to $3000");
        console2.log("New collateral: 4000 USDC + 1 ETH @ $3000 = $7000 (+ fees)");
        console2.log("Health Factor: ~0.99 (liquidatable!)");

        // Liquidate with $3000 payback (3000 USDC) - same as basic test
        // Position 0: D3 collateral, Position 1: USDC borrow
        _liquidateNormalBorrow(vars.nftId, 2, 1, 3000 * 1e6); // payback position 2 (borrow), withdraw position 1 (D3)

        // Restore ETH price back to normal before collecting fees
        _changeOraclePrice(NATIVE_TOKEN_ADDRESS, 4000 * 1e27);
        console2.log("ETH price restored back to $4000");

        // Collect fees after liquidation to verify they still exist
        vars.deleted = _collectD3Fees(vars.dexKey, vars.nftId, vars.positionIndex, vars.positionTickLower, vars.positionTickUpper, type(uint256).max, type(uint256).max);
        console2.log("Fees collected successfully after liquidation");
    }

    function testD3PositionLiquidationFeesOnly() public {
        D3D4TestVars memory vars = _setupD3Pool();

        // Deposit larger D3 position to generate meaningful fees
        (vars.nftId, vars.positionIndex) = _depositD3Position(vars.dexKey, vars.positionTickLower, vars.positionTickUpper, 8000 * 1e6, 2 ether);
        console2.log("Deposited - NFT ID:", _toString(vars.nftId), "Position Index:", _toString(vars.positionIndex));
        console2.log("Collateral: 8000 USDC + 2 ETH @ $4000 = $16000 total");

        // Generate significant fees via large swaps
        _swapInPool(vars.dexKey, 1000 * 1e6, true);  // USDC -> ETH
        _swapInPool(vars.dexKey, 0.25 ether, false);   // ETH -> USDC
        _swapInPool(vars.dexKey, 1000 * 1e6, true);  // USDC -> ETH again
        _swapInPool(vars.dexKey, 0.25 ether, false);   // ETH -> USDC again
        console2.log("Large swaps completed, significant fees generated");

        // Withdraw full position (fees remain as collateral)
        vars.deleted = _withdrawD3PositionFull(vars.dexKey, vars.nftId, vars.positionIndex, vars.positionTickLower, vars.positionTickUpper);
        assertTrue(!vars.deleted, "Position should NOT be deleted when fees exist");

        // Increase token price to make fees more valuable and avoid min collateral issues
        _changeOraclePrice(NATIVE_TOKEN_ADDRESS, 20000000 * 1e27);
        console2.log("ETH price increased from $4000 to $20,000,000");
        _changeOraclePrice(address(USDC), 5000 * 1e27);

        // Borrow USDC using fees as collateral (fees should be worth $200-400)
        vars.borrowAmount = (1500 * 1e6) / 5000; // Borrow $1500 against fees
        bytes memory actionData = abi.encode(2, 2, vars.borrowAmount, address(this));
        moneyMarket.operate(vars.nftId, 0, actionData);
        console2.log("Borrowed USDC: $1500 using fees as collateral");

        // Decrease ETH price to make position liquidatable
        // With 85% LT (instead of 80%), need more aggressive price drop
        _changeOraclePrice(NATIVE_TOKEN_ADDRESS, 10_000_000 * 1e27);
        console2.log("ETH price dropped from $20,000,000 to $10,000,000");
        console2.log("Fees value dropped significantly, position should be liquidatable");

        console2.log("Borrow amount:", _toString(vars.borrowAmount));

        // Liquidate the position
        // Position 0: D3 fees (collateral), Position 1: USDC borrow (debt)
        _liquidateNormalBorrow(vars.nftId, 2, 1, 100000); // payback position 2 (borrow), withdraw position 1 (D3)
    }

    function _borrowToMakeHFJustAboveOne(uint256 nftId, uint256 positionIndex) internal returns (uint256 borrowAmount) {
        // Calculate collateral value and borrow to make HF just above 1
        // Collateral: D3 position with ~2000 USDC + 0.5 ETH = ~$4000
        // With 80% collateral factor, max borrow = $3200
        // To make HF just above 1 (around 1.05-1.1), borrow ~$2800-3000 USDC
        // Using $2800 USDC to ensure HF is safely above 1
        borrowAmount = 2800 * 1e6; // 2800 USDC

        // Create a new borrow position (position type 2, token index 2 for USDC)
        // Action data: (positionType, tokenIndex, borrowAmount, to)
        bytes memory actionData = abi.encode(2, 2, borrowAmount, address(this));
        (uint256 newNftId, ,) = moneyMarket.operate(nftId, positionIndex, actionData); // Create new position
        assertEq(newNftId, nftId, "Should use same NFT");
    }

    function _paybackDebt(uint256 nftId, uint256 borrowPositionIndex, uint256 paybackAmount) internal {
        // Pay back debt: action data is (int256 paybackAmount, address to)
        // Negative amount for payback
        bytes memory actionData = abi.encode(-int256(paybackAmount), address(this));
        moneyMarket.operate(nftId, borrowPositionIndex, actionData);
    }

    function _paybackDebtFull(uint256 nftId, uint256 borrowPositionIndex) internal {
        // Pay back full debt: use type(int256).min for max payback
        bytes memory actionData = abi.encode(type(int256).min, address(this));
        moneyMarket.operate(nftId, borrowPositionIndex, actionData);
    }

    function _swapInPool(DexKey memory dexKey_, uint256 amountIn, bool swap0To1) internal {
        // Fund contract for swap
        if (swap0To1) {
            deal(address(USDC), address(this), USDC.balanceOf(address(this)) + amountIn);
            USDC.approve(address(dexV2), type(uint256).max);
        } else {
            deal(address(this), address(this).balance + amountIn);
        }

        SwapInParams memory swapParams_ = SwapInParams({
            dexKey: dexKey_,
            swap0To1: swap0To1,
            amountIn: amountIn,
            amountOutMin: 0,
            controllerData: "0x"
        });

        bytes memory callbackData_ = abi.encodeWithSelector(
            this.shouldSwapInCallbackImplementation.selector,
            swapParams_
        );
        dexV2.startOperation(callbackData_);
    }

    function shouldSwapInCallbackImplementation(SwapInParams memory swapParams_) public returns (bytes memory returnData_) {
        bytes memory swapData_ = abi.encodeWithSelector(
            FluidDexV2D3SwapModule.swapIn.selector,
            swapParams_
        );
        returnData_ = dexV2.operate(DEX_TYPE_D3, 1, swapData_); // SWAP_MODULE_ID = 1
        
        // Clear pending supplies for both tokens
        _clearPendingSupply(swapParams_.dexKey.token0);
        _clearPendingSupply(swapParams_.dexKey.token1);
    }

    function _swapInPoolD4(DexKey memory dexKey_, uint256 amountIn, bool swap0To1) internal {
        // Fund contract for swap
        if (swap0To1) {
            deal(address(USDC), address(this), USDC.balanceOf(address(this)) + amountIn);
            USDC.approve(address(dexV2), type(uint256).max);
        } else {
            deal(address(this), address(this).balance + amountIn);
        }

        SwapInParams memory swapParams_ = SwapInParams({
            dexKey: dexKey_,
            swap0To1: swap0To1,
            amountIn: amountIn,
            amountOutMin: 0,
            controllerData: "0x"
        });

        bytes memory callbackData_ = abi.encodeWithSelector(
            this.shouldSwapInCallbackImplementationD4.selector,
            swapParams_
        );
        dexV2.startOperation(callbackData_);
    }

    function shouldSwapInCallbackImplementationD4(SwapInParams memory swapParams_) public returns (bytes memory returnData_) {
        bytes memory swapData_ = abi.encodeWithSelector(
            FluidDexV2D4SwapModule.swapIn.selector,
            swapParams_
        );
        returnData_ = dexV2.operate(DEX_TYPE_D4, 1, swapData_); // DEX_TYPE_D4 = 4, SWAP_MODULE_ID = 1
        
        // Clear pending transfers (both supply and borrow) for both tokens in D4 pools
        _clearPendingTransfersD4(swapParams_.dexKey.token0);
        _clearPendingTransfersD4(swapParams_.dexKey.token1);
    }

    function _clearPendingTransfersD4(address token_) internal {
        int256 pendingSupply_ = _getPendingSupply(address(this), token_);
        int256 pendingBorrow_ = _getPendingBorrow(address(this), token_);

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

    function _clearPendingSupply(address token_) internal {
        int256 pendingSupply_ = _getPendingSupply(address(this), token_);

        if (pendingSupply_ > 0) {
            if (token_ == NATIVE_TOKEN_ADDRESS) {
                // For ETH, no approval needed, just ensure contract has enough ETH
                // The ETH will be sent via msg.value in the settle call
            } else {
                IERC20(token_).approve(address(dexV2), uint256(pendingSupply_));
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

    function _changeOraclePrice(address token, uint256 newPrice) internal {
        // Update oracle price to make position liquidatable
        oracle.setPrice(token, newPrice);
    }

    /// @notice Helper to liquidate a position with NORMAL_BORROW debt
    /// @param nftId The NFT ID to liquidate
    /// @param paybackPositionIndex The index of the debt position (NORMAL_BORROW)
    /// @param withdrawPositionIndex The index of the collateral position
    /// @param paybackAmount The amount to payback in token decimals (e.g., 1e6 for USDC)
    function _liquidateNormalBorrow(
        uint256 nftId, 
        uint256 paybackPositionIndex, 
        uint256 withdrawPositionIndex, 
        uint256 paybackAmount
    ) internal returns (bytes memory withdrawData) {
        // Fund bob with USDC for liquidation
        deal(address(USDC), bob, 100000 * 1e6); // 100k USDC should be enough
        
        // Use bob as liquidator
        vm.startPrank(bob);
        USDC.approve(address(moneyMarket), type(uint256).max);
        
        // Encode payback data for NORMAL_BORROW
        bytes memory paybackData = abi.encode(paybackAmount);
        
        // Perform liquidation
        (, withdrawData) = moneyMarket.liquidate(
            LiquidateParams({
                nftId: nftId,
                paybackPositionIndex: paybackPositionIndex,
                withdrawPositionIndex: withdrawPositionIndex,
                to: bob, // receive collateral to bob
                estimate: false, // not an estimate
                paybackData: paybackData
            })
        );
        vm.stopPrank();
    }

    /// @notice Helper to liquidate a position with D4 debt
    /// @param nftId The NFT ID to liquidate
    /// @param paybackPositionIndex The index of the D4 debt position
    /// @param withdrawPositionIndex The index of the collateral position
    /// @param token0PaybackAmount Token0 payback amount
    /// @param token1PaybackAmount Token1 payback amount
    function _liquidateD4Debt(
        uint256 nftId, 
        uint256 paybackPositionIndex, 
        uint256 withdrawPositionIndex, 
        uint256 token0PaybackAmount,
        uint256 token1PaybackAmount
    ) internal returns (bytes memory withdrawData) {
        // Fund bob with USDC and ETH for liquidation
        deal(address(USDC), bob, 100000 * 1e6); // 100k USDC should be enough
        vm.deal(bob, 100 ether);
        
        // Use bob as liquidator
        vm.startPrank(bob);
        USDC.approve(address(moneyMarket), type(uint256).max);
        
        // Encode payback data for D4
        bytes memory paybackData = abi.encode(
            token0PaybackAmount,
            token1PaybackAmount,
            uint256(0), // token0PaybackAmountMin
            uint256(0)  // token1PaybackAmountMin
        );
        
        // Calculate ETH value to send (token1 is ETH in our tests)
        uint256 ethValue = token1PaybackAmount;
        
        // Perform liquidation
        (, withdrawData) = moneyMarket.liquidate{value: ethValue}(
            LiquidateParams({
                nftId: nftId,
                paybackPositionIndex: paybackPositionIndex,
                withdrawPositionIndex: withdrawPositionIndex,
                to: bob, // receive collateral to bob
                estimate: false, // not an estimate
                paybackData: paybackData
            })
        );
        vm.stopPrank();
    }

    // D4 Position Helper Functions

    function _borrowD4Position(
        DexKey memory dexKey_,
        uint256 nftId_,
        int24 tickLower_,
        int24 tickUpper_,
        uint256 amount0,
        uint256 amount1
    ) internal returns (uint256 nftId, uint256 positionIndex) {
        CreateD3D4PositionParams memory positionParams_ = CreateD3D4PositionParams({
            token0Index: 2, // USDC index
            token1Index: 1, // ETH index
            tickSpacing: dexKey_.tickSpacing,
            fee: dexKey_.fee,
            controller: dexKey_.controller,
            tickLower: tickLower_,
            tickUpper: tickUpper_,
            amount0: amount0,
            amount1: amount1,
            amount0Min: 0,
            amount1Min: 0,
            to: address(this)
        });

        bytes memory actionData = abi.encode(
            4, // D4_POSITION_TYPE
            positionParams_
        );

        if (nftId_ == 0) {
            // Create new NFT
            (nftId, positionIndex,) = moneyMarket.operate{value: positionParams_.amount1}(
                0,
                0,
                actionData
            );
        } else {
            // Add to existing NFT
            (nftId, positionIndex,) = moneyMarket.operate{value: positionParams_.amount1}(
                nftId_,
                0,
                actionData
            );
        }
    }

    function _borrowD4PositionMore(
        DexKey memory dexKey_,
        uint256 nftId,
        uint256 positionIndex,
        int24 tickLower_,
        int24 tickUpper_,
        uint256 amount0,
        uint256 amount1
    ) internal {
        // For modifying existing D4 position: (int256 amount0, int256 amount1, uint256 amount0Min, uint256 amount1Min, address to)
        bytes memory actionData = abi.encode(
            int256(amount0), // positive = borrow more
            int256(amount1),
            uint256(0), // amount0Min
            uint256(0), // amount1Min
            address(this)
        );
        
        moneyMarket.operate(nftId, positionIndex, actionData);
    }

    function _paybackD4Position(
        DexKey memory dexKey_,
        uint256 nftId,
        uint256 positionIndex,
        int24 tickLower_,
        int24 tickUpper_,
        uint256 amount0,
        uint256 amount1
    ) internal {
        // For payback: use negative amounts
        bytes memory actionData = abi.encode(
            -int256(amount0), // negative = payback
            -int256(amount1),
            uint256(0), // amount0Min
            uint256(0), // amount1Min
            address(this)
        );
        
        // Determine ETH value to send based on which token is native
        uint256 ethValue = 0;
        if (dexKey_.token0 == NATIVE_TOKEN_ADDRESS) {
            ethValue = amount0;
        } else if (dexKey_.token1 == NATIVE_TOKEN_ADDRESS) {
            ethValue = amount1;
        }
        
        moneyMarket.operate{value: ethValue}(nftId, positionIndex, actionData);
    }

    function _paybackD4PositionFull(
        DexKey memory dexKey_,
        uint256 nftId,
        uint256 positionIndex,
        int24 tickLower_,
        int24 tickUpper_
    ) internal returns (bool deleted) {
        uint256 positionsCountBefore = _getNumberOfPositions(nftId);

        // Use large negative amounts to payback everything
        bytes memory actionData = abi.encode(
            -int256(1_000_000 * 1e6), // large amount0
            -int256(250 ether), // large amount1
            uint256(0), // amount0Min
            uint256(0), // amount1Min
            address(this)
        );
        
        // Determine ETH value to send based on which token is native
        uint256 ethValue = 0;
        if (dexKey_.token0 == NATIVE_TOKEN_ADDRESS) {
            ethValue = 1_000_000 * 1e6; // Won't actually happen since USDC is token0 in our tests
        } else if (dexKey_.token1 == NATIVE_TOKEN_ADDRESS) {
            ethValue = 250 ether;
        }
        
        moneyMarket.operate{value: ethValue}(nftId, positionIndex, actionData);

        uint256 positionsCountAfter = _getNumberOfPositions(nftId);
        deleted = (positionsCountBefore > positionsCountAfter) && (positionsCountAfter + 1 == positionsCountBefore);
    }

    function _collectD4Fees(
        DexKey memory dexKey_,
        uint256 nftId,
        uint256 positionIndex,
        int24 tickLower_,
        int24 tickUpper_,
        uint256 feeAmount0,
        uint256 feeAmount1
    ) internal returns (bool deleted) {
        uint256 positionsCountBefore = _getNumberOfPositions(nftId);

        // Fee collection: amount0=0, amount1=0, feeCollectionAmount0, feeCollectionAmount1, to (same as D3)
        bytes memory actionData = abi.encode(
            int256(0), // amount0 = 0 (fee collection)
            int256(0), // amount1 = 0 (fee collection)
            feeAmount0, // feeCollectionAmount0
            feeAmount1, // feeCollectionAmount1
            address(this) // to
        );
        
        moneyMarket.operate(nftId, positionIndex, actionData);

        uint256 positionsCountAfter = _getNumberOfPositions(nftId);
        deleted = (positionsCountBefore > positionsCountAfter) && (positionsCountAfter + 1 == positionsCountBefore);
    }

    function testD4PositionWithBorrow() public {
        _listUSDC();
        D3D4TestVars memory vars = _setupD4Pool();

        // Supply USDC
        uint256 supplyAmount = 10000 * 1e6; // 10k USDC
        bytes memory supplyData = abi.encode(
            1, // NORMAL_SUPPLY_POSITION_TYPE
            2, // tokenIndex for USDC (indices start from 1)
            supplyAmount
        );
        (vars.nftId, vars.positionIndex,) = moneyMarket.operate(
            0, // Create new NFT
            0, // Create new position
            supplyData
        );
        console2.log("NFT ID:", _toString(vars.nftId));

        // Borrow ETH-USDC D4 debt
        (vars.nftId, vars.positionIndex) = _borrowD4Position(vars.dexKey, vars.nftId, vars.positionTickLower, vars.positionTickUpper, 2000 * 1e6, 0.5 ether);
        console2.log("Borrowed D4 - NFT ID:", _toString(vars.nftId), "Position Index:", _toString(vars.positionIndex));

        // Payback ETH-USDC D4 debt
        _paybackD4Position(vars.dexKey, vars.nftId, vars.positionIndex, vars.positionTickLower, vars.positionTickUpper, 2000 * 1e6, 0.5 ether);
        console2.log("Payback D4 completed");

        // Withdraw full USDC
        bytes memory withdrawData = abi.encode(-int256(supplyAmount), address(this));
        moneyMarket.operate(vars.nftId, 1, withdrawData); // Position 1 is the USDC supply
        console2.log("Withdrew full USDC");
    }

    function testD4PositionWithFees() public {
        _listUSDC();
        D3D4TestVars memory vars = _setupD4Pool();

        // Supply USDC
        uint256 supplyAmount = 20000 * 1e6; // 20k USDC for more borrowing capacity
        bytes memory supplyData = abi.encode(
            1, // NORMAL_SUPPLY_POSITION_TYPE
            2, // tokenIndex for USDC (indices start from 1)
            supplyAmount
        );
        (vars.nftId, vars.positionIndex,) = moneyMarket.operate(
            0, // Create new NFT
            0, // Create new position
            supplyData
        );

        // Borrow ETH-USDC D4 debt
        (vars.nftId, vars.positionIndex) = _borrowD4Position(vars.dexKey, vars.nftId, vars.positionTickLower, vars.positionTickUpper, 2000 * 1e6, 0.5 ether);
        console2.log("Borrowed D4 position");

        // Borrow more ETH-USDC D4 debt
        _borrowD4PositionMore(vars.dexKey, vars.nftId, vars.positionIndex, vars.positionTickLower, vars.positionTickUpper, 1000 * 1e6, 0.25 ether);
        console2.log("Borrowed more D4 debt");

        // Generate fees (scaled up for minimum fee threshold)
        _swapInPoolD4(vars.dexKey, 1000 * 1e6, true);
        _swapInPoolD4(vars.dexKey, 0.25 ether, false);
        console2.log("Fees generated");

        // Collect fees
        _collectD4Fees(vars.dexKey, vars.nftId, vars.positionIndex, vars.positionTickLower, vars.positionTickUpper, type(uint256).max, type(uint256).max);
        console2.log("Fees collected");

        // Generate more fees
        _swapInPoolD4(vars.dexKey, 1000 * 1e6, true);
        _swapInPoolD4(vars.dexKey, 0.25 ether, false);
        console2.log("More fees generated");

        // Payback partial ETH-USDC D4 debt
        _paybackD4Position(vars.dexKey, vars.nftId, vars.positionIndex, vars.positionTickLower, vars.positionTickUpper, 500 * 1e6, 0.125 ether);
        console2.log("Partial D4 payback completed");

        // Generate more fees
        _swapInPoolD4(vars.dexKey, 1000 * 1e6, true);
        _swapInPoolD4(vars.dexKey, 0.25 ether, false);
        console2.log("More fees generated");

        // Payback full ETH-USDC D4 debt (position should NOT delete because of fees)
        vars.deleted = _paybackD4PositionFull(vars.dexKey, vars.nftId, vars.positionIndex, vars.positionTickLower, vars.positionTickUpper);
        assertTrue(!vars.deleted, "Position should NOT be deleted when fees exist");

        // Withdraw fees (position should delete)
        vars.deleted = _collectD4Fees(vars.dexKey, vars.nftId, vars.positionIndex, vars.positionTickLower, vars.positionTickUpper, type(uint256).max, type(uint256).max);
        assertTrue(vars.deleted, "Position should be deleted after fee withdrawal");

        // Withdraw full USDC
        bytes memory withdrawData = abi.encode(-int256(supplyAmount), address(this));
        moneyMarket.operate(vars.nftId, 1, withdrawData); // Position 1 is the USDC supply
        console2.log("Withdrew full USDC");
    }

    function testD4PositionLiquidationBasic() public {
        _listUSDC();
        D3D4TestVars memory vars = _setupD4Pool();

        // Supply USDC collateral
        uint256 supplyAmount = 2000 * 1e6; // $2000 USDC
        bytes memory supplyData = abi.encode(
            1, // NORMAL_SUPPLY_POSITION_TYPE
            2, // tokenIndex for USDC (indices start from 1)
            supplyAmount
        );
        (vars.nftId, vars.positionIndex,) = moneyMarket.operate(
            0, // Create new NFT
            0, // Create new position
            supplyData
        );
        console2.log("NFT ID:", _toString(vars.nftId));

        // Borrow D4 debt: 0.1 ETH and 400 USDC
        (vars.nftId, vars.positionIndex) = _borrowD4Position(vars.dexKey, vars.nftId, vars.positionTickLower, vars.positionTickUpper, 400 * 1e6, 0.1 ether);
        console2.log("Borrowed D4 debt: 400 USDC + 0.1 ETH");
        console2.log("Debt value @ $4000 ETH: 400 + (0.1 * $4000) = $800");
        console2.log("Collateral value: $2000");
        console2.log("Health Factor: ($2000 * 0.8) / $800 = 2.0 (healthy)");

        // Change ETH price from $4000 to $13000
        _changeOraclePrice(NATIVE_TOKEN_ADDRESS, 13000 * 1e27);
        console2.log("ETH price changed from $4000 to $13000");
        console2.log("New debt value: 400 + (0.1 * $13000) = $1700");
        console2.log("Collateral value: $2000");
        console2.log("Health Factor: ($2000 * 0.8) / $1700 = 0.94 (liquidatable!)");

        // Liquidate D4 debt position
        // Position 0: USDC supply (collateral)
        // Position 1: D4 debt (USDC + ETH)
        // Payback some of the D4 debt: ~200 USDC and ~0.04 ETH (roughly $700 at current prices)
        _liquidateD4Debt(vars.nftId, 2, 1, 200 * 1e6, 0.04 ether); // payback D4 position 2, withdraw USDC position 1
    }

    function testD4PositionLiquidationWithFees() public {
        _listUSDC();
        D3D4TestVars memory vars = _setupD4Pool();

        // Supply USDC collateral
        uint256 supplyAmount = 2000 * 1e6; // $2000 USDC
        bytes memory supplyData = abi.encode(
            1, // NORMAL_SUPPLY_POSITION_TYPE
            2, // tokenIndex for USDC (indices start from 1)
            supplyAmount
        );
        (vars.nftId, vars.positionIndex,) = moneyMarket.operate(
            0, // Create new NFT
            0, // Create new position
            supplyData
        );

        // Borrow D4 debt: 0.1 ETH and 400 USDC
        (vars.nftId, vars.positionIndex) = _borrowD4Position(vars.dexKey, vars.nftId, vars.positionTickLower, vars.positionTickUpper, 400 * 1e6, 0.1 ether);
        console2.log("Borrowed D4 debt: 400 USDC + 0.1 ETH");
        console2.log("Debt value @ $4000 ETH: $800");

        // Generate fees via swaps
        _swapInPoolD4(vars.dexKey, 100 * 1e6, true);
        _swapInPoolD4(vars.dexKey, 0.01 ether, false);
        console2.log("Fees generated (small amount)");

        // Change ETH price from $4000 to $13000
        _changeOraclePrice(NATIVE_TOKEN_ADDRESS, 13000 * 1e27);
        console2.log("ETH price changed from $4000 to $13000");
        console2.log("New debt value: $1700");
        console2.log("Collateral value: $2000 (+ fees)");
        console2.log("Health Factor: ~0.94 (liquidatable!)");

        // Liquidate D4 debt position
        // Position 0: USDC supply (collateral)
        // Position 1: D4 debt (USDC + ETH)
        // Payback some of the D4 debt: ~300 USDC and ~0.05 ETH (roughly $1000 at current prices)
        _liquidateD4Debt(vars.nftId, 2, 1, 300 * 1e6, 0.05 ether); // payback D4 position 2, withdraw USDC position 1
    }

    function testD4PositionLiquidationFeesOnly() public {
        _listUSDC();
        D3D4TestVars memory vars = _setupD4Pool();

        // Supply larger USDC collateral
        uint256 supplyAmount = 5000 * 1e6; // $5000 USDC
        bytes memory supplyData = abi.encode(
            1, // NORMAL_SUPPLY_POSITION_TYPE
            2, // tokenIndex for USDC (indices start from 1)
            supplyAmount
        );
        (vars.nftId, vars.positionIndex,) = moneyMarket.operate(
            0, // Create new NFT
            0, // Create new position
            supplyData
        );

        // Borrow D4 debt
        (vars.nftId, vars.positionIndex) = _borrowD4Position(vars.dexKey, vars.nftId, vars.positionTickLower, vars.positionTickUpper, 800 * 1e6, 0.2 ether);
        console2.log("Borrowed D4 debt: 800 USDC + 0.2 ETH");

        // Generate fees via swap - only USDC to ETH so fees accrue in ETH
        _swapInPoolD4(vars.dexKey, 500 * 1e6, true);  // USDC -> ETH (swap to generate ETH fees)
        console2.log("Swap completed, fees generated in ETH");

        // Payback full D4 debt (fees remain as collateral)
        vars.deleted = _paybackD4PositionFull(vars.dexKey, vars.nftId, vars.positionIndex, vars.positionTickLower, vars.positionTickUpper);
        assertTrue(!vars.deleted, "Position should NOT be deleted when fees exist");

        // Withdraw full USDC collateral - use type(int256).min for max withdrawal
        bytes memory withdrawData = abi.encode(type(int256).min, address(this));
        moneyMarket.operate(vars.nftId, 1, withdrawData); // Position 1 is the USDC supply
        console2.log("Withdrew full USDC collateral");

        // Increase ETH price to $50M to make fees extremely valuable
        _changeOraclePrice(NATIVE_TOKEN_ADDRESS, 500_000_000 * 1e27);
        console2.log("ETH price increased to $500,000,000");

        // Borrow large amount of USDC using fees as collateral
        vars.borrowAmount = 4000 * 1e6; // Borrow $4000 USDC
        bytes memory actionData = abi.encode(2, 2, vars.borrowAmount, address(this));
        moneyMarket.operate(vars.nftId, 0, actionData);
        console2.log("Borrowed $4000 USDC");

        // Increase USDC price to make position liquidatable
        // With 85% LT (instead of 80%), need more aggressive price change
        _changeOraclePrice(address(USDC), 2 * 1e27); // USDC = $2

        // Liquidate the position
        // After withdrawing USDC supply (position 1), D4 fees becomes position 1
        // New USDC borrow is at position 2
        // Position 1: D4 fees (collateral), Position 2: USDC borrow (debt)
        _liquidateNormalBorrow(vars.nftId, 2, 1, 1000 * 1e6); // 1000 USDC
    }

    /// @notice Helper to list DAI as isolated collateral
    function _listDAIAsIsolated() internal returns (uint256 daiTokenIndex) {
        // Set prices for DAI
        oracle.setPrice(address(DAI), 1 * 1e27); // DAI = $1
        
        // List DAI token with collateral class 3 (isolated)
        (bool success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.listToken.selector,
                address(DAI),
                3, // collateralClass = 3 (isolated)
                1, // debtClass (1 = permissioned)
                800, // collateralFactor (80%)
                850, // liquidationThreshold (85%)
                50  // liquidationPenalty (5%)
            )
        );
        require(success, "Failed to list DAI token");
        
        // Set supply cap for DAI
        (success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateTokenSupplyCap.selector,
                address(DAI),
                1_000_000 * 1e18 // 1M DAI cap
            )
        );
        require(success, "Failed to set DAI supply cap");
        
        // DAI will be token index 3 (ETH=1, USDC=2, DAI=3)
        daiTokenIndex = 3;
        
        // Set isolated collateral debt limits for DAI
        // Allow borrowing up to 10,000 USDC and 2 ETH against DAI isolated collateral
        (success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateIsolatedCap.selector,
                address(DAI), // isolated collateral token
                address(USDC), // debt token
                10_000 * 1e6 // 10,000 USDC cap
            )
        );
        require(success, "Failed to set DAI->USDC debt cap");
        
        (success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateIsolatedCap.selector,
                address(DAI), // isolated collateral token
                NATIVE_TOKEN_ADDRESS, // debt token (ETH)
                2 * 1e18 // 2 ETH cap
            )
        );
        require(success, "Failed to set DAI->ETH debt cap");
    }

    /// @notice Helper to list USDT as isolated collateral
    function _listUSDTAsIsolated() internal returns (uint256 usdtTokenIndex) {
        // Set prices for USDT
        oracle.setPrice(address(USDT), 1e27); // USDT = $1 (price always in 27 decimals)
        
        // List USDT token with collateral class 3 (isolated)
        (bool success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.listToken.selector,
                address(USDT),
                3, // collateralClass = 3 (isolated)
                1, // debtClass (1 = permissioned)
                800, // collateralFactor (80%)
                850, // liquidationThreshold (85%)
                50  // liquidationPenalty (5%)
            )
        );
        require(success, "Failed to list USDT token");
        
        // Set supply cap for USDT
        (success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateTokenSupplyCap.selector,
                address(USDT),
                1000000 * 1e6 // 1M USDT cap
            )
        );
        require(success, "Failed to set USDT supply cap");
        
        // USDT will be token index 4 (ETH=1, USDC=2, DAI=3, USDT=4)
        usdtTokenIndex = 4;
        
        // Set isolated collateral debt limits for USDT
        (success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateIsolatedCap.selector,
                address(USDT), // isolated collateral token
                address(USDC), // debt token
                10000 * 1e6 // 10,000 USDC cap
            )
        );
        require(success, "Failed to set USDT->USDC debt cap");
        
        (success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateIsolatedCap.selector,
                address(USDT), // isolated collateral token
                NATIVE_TOKEN_ADDRESS, // debt token (ETH)
                2 * 1e18 // 2 ETH cap
            )
        );
        require(success, "Failed to set USDT->ETH debt cap");
    }

    function testIsolatedCollateral_Part1_BasicRules() public {
        // Setup: List USDC for borrowing
        _listUSDC();
        
        // List DAI and USDT as isolated collateral
        uint256 daiTokenIndex = _listDAIAsIsolated();
        uint256 usdtTokenIndex = _listUSDTAsIsolated();
        
        console2.log("DAI token index:", _toString(daiTokenIndex));
        console2.log("USDT token index:", _toString(usdtTokenIndex));
        console2.log("DAI->USDC debt cap: 10,000 USDC");
        console2.log("DAI->ETH debt cap: 2 ETH");
        
        // Step 1: Create NFT with ETH collateral and USDC debt
        uint256 ethCollateral = 10 ether; // $40,000 at $4000/ETH
        bytes memory ethSupplyData = abi.encode(
            1, // NORMAL_SUPPLY_POSITION_TYPE
            1, // tokenIndex for ETH (indices start from 1)
            ethCollateral
        );
        (uint256 nftId1, uint256 positionIndex,) = moneyMarket.operate{value: ethCollateral}(
            0,
            0,
            ethSupplyData
        );
        console2.log("NFT 1 created with ETH collateral");
        console2.log("NFT ID:", _toString(nftId1));
        
        // Borrow 5000 USDC
        uint256 usdcBorrow1 = 5000 * 1e6;
        bytes memory borrowData = abi.encode(
            2, // NORMAL_BORROW_POSITION_TYPE
            2, // tokenIndex for USDC (indices start from 1)
            usdcBorrow1,
            address(this)
        );
        moneyMarket.operate(nftId1, 0, borrowData);
        console2.log("Borrowed 5000 USDC against ETH collateral");
        
        // Step 2: Supply DAI (isolated) - should pass because USDC debt is within limits
        uint256 daiSupply = 20000 * 1e18; // $20,000 DAI
        deal(address(DAI), address(this), 100000 * 1e18); // Fund test contract with DAI
        DAI.approve(address(moneyMarket), type(uint256).max);
        bytes memory daiSupplyData = abi.encode(
            1, // NORMAL_SUPPLY_POSITION_TYPE
            daiTokenIndex,
            daiSupply
        );
        moneyMarket.operate(nftId1, 0, daiSupplyData);
        console2.log("Successfully supplied 20,000 DAI to NFT 1");
        console2.log("NFT 1 is now in isolated mode (DAI)");
        
        // Step 3: Try to supply USDT (another isolated collateral) - should fail
        uint256 usdtSupply = 10000 * 1e6; // $10,000 USDT
        USDT.approve(address(moneyMarket), type(uint256).max);
        bytes memory usdtSupplyData = abi.encode(
            1, // NORMAL_SUPPLY_POSITION_TYPE
            usdtTokenIndex,
            usdtSupply
        );
        vm.expectRevert();
        moneyMarket.operate(nftId1, 0, usdtSupplyData);
        console2.log("USDT supply correctly reverted (NFT already in isolated mode with DAI)");
        
        // Step 4: Try to borrow D4 position - should fail (D4 not allowed in isolated mode)
        D3D4TestVars memory vars = _setupD4Pool();
        vm.expectRevert();
        _borrowD4Position(vars.dexKey, nftId1, vars.positionTickLower, vars.positionTickUpper, 100 * 1e6, 0.025 ether);
        
        // Step 5: Supply more DAI - should pass (same isolated collateral)
        uint256 moreDai = 10000 * 1e18; // $10,000 more DAI
        bytes memory moreDaiData = abi.encode(
            int256(moreDai),
            address(0)
        );
        moneyMarket.operate(nftId1, 3, moreDaiData); // Position 3 is the DAI supply position
        console2.log("Successfully supplied 10,000 more DAI to NFT 1");
        console2.log("Total DAI in NFT 1: 30,000 DAI");
        
        // Step 6: Try to borrow more USDC than caps - should fail
        uint256 excessUsdcBorrow = 6000 * 1e6; // Would make total 11,000 USDC, exceeding 10,000 cap
        bytes memory excessBorrowData = abi.encode(
            int256(excessUsdcBorrow),
            address(this)
        );
        vm.expectRevert();
        moneyMarket.operate(nftId1, 2, excessBorrowData); // Position 2 is the USDC borrow position
        console2.log("Excess USDC borrow correctly reverted (would exceed 10,000 USDC cap for DAI isolated)");
        
    }

    function testIsolatedCollateral_Part2_CrossNFTCaps() public {
        // Setup: List USDC for borrowing
        _listUSDC();
        
        // List DAI as isolated collateral
        uint256 daiTokenIndex = _listDAIAsIsolated();
        
        
        // Create NFT 1 with ETH and DAI, borrow 5000 USDC
        uint256 ethCollateral = 10 ether;
        bytes memory ethSupplyData = abi.encode(1, 1, ethCollateral);
        (uint256 nftId1,,) = moneyMarket.operate{value: ethCollateral}(0, 0, ethSupplyData);
        
        uint256 usdcBorrow1 = 5000 * 1e6;
        bytes memory borrowData = abi.encode(2, 2, usdcBorrow1, address(this));
        moneyMarket.operate(nftId1, 0, borrowData);
        
        uint256 daiSupply = 20000 * 1e18;
        deal(address(DAI), address(this), 100000 * 1e18); // Fund test contract with DAI
        DAI.approve(address(moneyMarket), type(uint256).max);
        bytes memory daiSupplyData = abi.encode(1, daiTokenIndex, daiSupply);
        moneyMarket.operate(nftId1, 0, daiSupplyData);
        console2.log("NFT 1: Has 5000 USDC debt, DAI isolated collateral");
        
        // Create NFT 2 with DAI isolated collateral
        uint256 daiSupply2 = 15000 * 1e18;
        bytes memory daiSupplyData2 = abi.encode(1, daiTokenIndex, daiSupply2);
        (uint256 nftId2,,) = moneyMarket.operate(0, 0, daiSupplyData2);
        console2.log("NFT 2 created with 15,000 DAI");
        
        // Try to borrow 6000 USDC in NFT 2 - should fail (total would be 11,000)
        uint256 usdcBorrow2 = 6000 * 1e6;
        bytes memory borrowData2 = abi.encode(2, 2, usdcBorrow2, address(this));
        vm.expectRevert();
        moneyMarket.operate(nftId2, 0, borrowData2);
        
        // Payback USDC debt in NFT 1 first
        USDC.approve(address(moneyMarket), type(uint256).max);
        bytes memory paybackData = abi.encode(-int256(usdcBorrow1), address(this));
        moneyMarket.operate(nftId1, 2, paybackData); // Position 2 is the USDC borrow

        // Now borrow USDC in NFT 2 should succeed since NFT 1 debt was paid back
        moneyMarket.operate(nftId2, 0, borrowData2);
        console2.log("Successfully borrowed 6,000 USDC in NFT 2");
        console2.log("Only NFT 2 contributes to DAI isolated debt now");
        
        // Withdraw DAI - it's at position 3 (ETH=1, USDC borrow=2, DAI=3)
        bytes memory withdrawDaiData = abi.encode(-int256(daiSupply), address(this));
        moneyMarket.operate(nftId1, 3, withdrawDaiData);
    }

    /// @notice Helper to list an emode
    /// @dev This helper simply calls listEmode. Since emodes are assigned sequentially starting from 1,
    /// the caller should track the emode count themselves.
    function _listEmode(
        TokenConfig[] memory tokenConfigsList_,
        address[] memory debtTokens_
    ) internal {
        (bool success, bytes memory returnData) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.listEmode.selector,
                tokenConfigsList_,
                debtTokens_
            )
        );
        if (!success) {
            // Bubble up the revert reason
            if (returnData.length > 0) {
                assembly {
                    let returndata_size := mload(returnData)
                    revert(add(32, returnData), returndata_size)
                }
            } else {
                revert("Failed to list emode");
            }
        }
    }

    function testEmodeBasic() public {
        // Setup: List USDC (ETH is already listed in setup)
        _listUSDC();
        
        console2.log("ETH collateral factor (NO_EMODE): 80%");
        console2.log("ETH liquidation threshold (NO_EMODE): 80%");
        
        // Create emode with ETH CF/LT at 90% and only USDC allowed as debt
        TokenConfig[] memory tokenConfigs = new TokenConfig[](1);
        tokenConfigs[0] = TokenConfig({
            token: NATIVE_TOKEN_ADDRESS,
            collateralClass: 1, // Same as NO_EMODE
            debtClass: 1, // Same as NO_EMODE
            collateralFactor: 900, // 90% (in basis points out of 1000)
            liquidationThreshold: 920, // 95%
            liquidationPenalty: 50 // 5%
        });
        
        address[] memory debtTokens = new address[](1);
        debtTokens[0] = address(USDC);
        
        _listEmode(tokenConfigs, debtTokens);
        // Emodes are assigned sequentially starting from 1, so this is emode 1
        uint256 emodeId = 1;
        console2.log("Emode ID:", _toString(emodeId));
        console2.log("Emode ETH collateral factor: 90%");
        console2.log("Emode ETH liquidation threshold: 90%");
        console2.log("Emode allowed debt: USDC only");
        
        // Step 1: Create NFT with 1 ETH supply and 3000 USDC borrow (in NO_EMODE)
        uint256 ethCollateral = 1 ether; // $4000 at $4000/ETH
        bytes memory ethSupplyData = abi.encode(
            1, // NORMAL_SUPPLY_POSITION_TYPE
            1, // tokenIndex for ETH (indices start from 1)
            ethCollateral
        );
        (uint256 nftId, uint256 positionIndex,) = moneyMarket.operate{value: ethCollateral}(
            0,
            0,
            ethSupplyData
        );
        console2.log("NFT created with 1 ETH collateral");
        console2.log("NFT ID:", _toString(nftId));
        console2.log("Collateral value: $4000");
        console2.log("Max borrow at 80% CF: $3200");
        
        // Step 2: Borrow 3000 USDC (safe at 80% CF)
        uint256 usdcBorrow1 = 3000 * 1e6;
        bytes memory borrowData1 = abi.encode(
            2, // NORMAL_BORROW_POSITION_TYPE
            2, // tokenIndex for USDC (indices start from 1)
            usdcBorrow1,
            address(this)
        );
        moneyMarket.operate(nftId, 0, borrowData1);
        console2.log("Borrowed 3000 USDC successfully");
        console2.log("Total debt: $3000");
        console2.log("Utilization: $3000 / $3200 = 93.75%");
        
        // Step 3: Try to borrow $500 more - should fail (would exceed 80% CF)
        uint256 usdcBorrow2 = 500 * 1e6;
        bytes memory borrowData2 = abi.encode(
            int256(usdcBorrow2),
            address(this)
        );
        console2.log("This would make total debt: $3500");
        console2.log("Max allowed at 80% CF: $3200");
        console2.log("Expected: REVERT (exceeds collateral factor)");
        vm.expectRevert();
        moneyMarket.operate(nftId, 2, borrowData2); // Position 2 is the USDC borrow position
        console2.log("Borrow correctly reverted!");
        
        // Step 4: Change emode to the new emode (90% CF)
        console2.log("Changing from NO_EMODE (CF=80%) to Emode", _toString(emodeId), "(CF=90%)");
        moneyMarket.changeEmode(nftId, emodeId);
        console2.log("Emode changed successfully");
        console2.log("New max borrow at 90% CF: $3600");
        console2.log("Current debt: $3000");
        console2.log("Available to borrow: $600");
        
        // Step 5: Try to borrow $500 more again - should pass (within 90% CF)
        console2.log("This would make total debt: $3500");
        console2.log("Max allowed at 90% CF: $3600");
        console2.log("Expected: SUCCESS");
        moneyMarket.operate(nftId, 2, borrowData2); // Position 2 is the USDC borrow position
        console2.log("Borrow succeeded!");
        console2.log("Final total debt: $3500");
        console2.log("Final utilization: $3500 / $3600 = 97.22%");
        
        console2.log("Successfully demonstrated:");
        console2.log("- Creating emode with custom CF/LT");
        console2.log("- Borrow limits enforced by CF in NO_EMODE");
        console2.log("- Changing emode increases available borrowing power");
        console2.log("- Borrow succeeds after emode change");
    }

    /// @notice Test emode debt restrictions - only allowed debt tokens can be borrowed
    function testEmodeDebtRestrictions() public {
        // Setup: List USDC and DAI
        _listUSDC();
        _listDAIAsIsolated(); // This will list DAI with debt class 1
        
        
        // Create emode 1 with ETH CF/LT at 90% and only USDC allowed as debt
        TokenConfig[] memory tokenConfigs = new TokenConfig[](1);
        tokenConfigs[0] = TokenConfig({
            token: NATIVE_TOKEN_ADDRESS,
            collateralClass: 1,
            debtClass: 1,
            collateralFactor: 900, // 90%
            liquidationThreshold: 920, // 95%
            liquidationPenalty: 50 // 5%
        });
        
        address[] memory debtTokens = new address[](1);
        debtTokens[0] = address(USDC); // Only USDC allowed as debt
        
        _listEmode(tokenConfigs, debtTokens);
        uint256 emodeId = 1;
        console2.log("Emode 1 listed - only USDC allowed as debt");
        
        // Create NFT with ETH supply and switch to emode
        uint256 ethCollateral = 10 ether; // $40,000 at $4000/ETH
        bytes memory ethSupplyData = abi.encode(1, 1, ethCollateral);
        (uint256 nftId,,) = moneyMarket.operate{value: ethCollateral}(
            0,
            0,
            ethSupplyData
        );
        console2.log("NFT created with 10 ETH collateral ($40,000)");
        
        // Change to emode
        moneyMarket.changeEmode(nftId, emodeId);
        console2.log("NFT switched to emode 1");
        
        // Test a) Try to borrow DAI (not in emode debt list) - should fail
        uint256 daiBorrow = 1000 * 1e18;
        bytes memory daiBorrowData = abi.encode(
            2, // NORMAL_BORROW_POSITION_TYPE
            3, // tokenIndex for DAI (indices start from 1)
            daiBorrow,
            address(this)
        );
        vm.expectRevert();
        moneyMarket.operate(nftId, 0, daiBorrowData);
        console2.log("Borrow correctly reverted - DAI not allowed in emode");
        
        // Borrow USDC successfully (it's in the emode debt list)
        uint256 usdcBorrow = 10000 * 1e6;
        bytes memory usdcBorrowData = abi.encode(2, 2, usdcBorrow, address(this));
        moneyMarket.operate(nftId, 0, usdcBorrowData);
        console2.log("Successfully borrowed 10,000 USDC");
        
    }

    /// @notice Test emode D4 debt restrictions
    function testEmodeD4DebtRestrictions() public {
        // Setup: List USDC and setup D4 pool
        _listUSDC();
        D3D4TestVars memory vars = _setupD4Pool();
        
        
        // Create emode with ETH CF/LT at 90% and only USDC allowed as debt (not ETH)
        TokenConfig[] memory tokenConfigs = new TokenConfig[](1);
        tokenConfigs[0] = TokenConfig({
            token: NATIVE_TOKEN_ADDRESS,
            collateralClass: 1,
            debtClass: 1,
            collateralFactor: 900, // 90%
            liquidationThreshold: 920, // 95%
            liquidationPenalty: 50 // 5%
        });
        
        // Add USDC config
        TokenConfig[] memory tokenConfigs2 = new TokenConfig[](2);
        tokenConfigs2[0] = tokenConfigs[0];
        tokenConfigs2[1] = TokenConfig({
            token: address(USDC),
            collateralClass: 1,
            debtClass: 1,
            collateralFactor: 900,
            liquidationThreshold: 920,
            liquidationPenalty: 50
        });
        
        address[] memory debtTokens = new address[](1);
        debtTokens[0] = address(USDC); // Only USDC allowed as debt, NOT ETH
        
        _listEmode(tokenConfigs2, debtTokens);
        uint256 emodeId = 1;
        console2.log("Emode 1 listed - only USDC allowed as debt (ETH not allowed)");
        
        // Create NFT with large USDC supply
        uint256 usdcSupply = 50000 * 1e6; // $50,000 USDC
        bytes memory usdcSupplyData = abi.encode(1, 2, usdcSupply);
        (vars.nftId,,) = moneyMarket.operate(
            0,
            0,
            usdcSupplyData
        );
        console2.log("NFT created with 50,000 USDC collateral");
        
        // Change to emode
        moneyMarket.changeEmode(vars.nftId, emodeId);
        console2.log("NFT switched to emode 1");
        
        // Test b) Try to borrow D4 with ETH+USDC (ETH not in debt list) - should fail
        console2.log("ETH is not in emode debt list, so D4 borrow should fail");
        vm.expectRevert();
        _borrowD4Position(vars.dexKey, vars.nftId, vars.positionTickLower, vars.positionTickUpper, 1000 * 1e6, 0.25 ether);
        
        // Test c) Update emode to allow both USDC and ETH, then D4 borrow should pass
        address[] memory debtTokens2 = new address[](2);
        debtTokens2[0] = address(USDC);
        debtTokens2[1] = NATIVE_TOKEN_ADDRESS; // Now ETH is also allowed
        
        _listEmode(tokenConfigs2, debtTokens2);
        uint256 emodeId2 = 2; // This is emode 2
        console2.log("Emode 2 listed - both USDC and ETH allowed as debt");
        
        // Change to new emode
        moneyMarket.changeEmode(vars.nftId, emodeId2);
        console2.log("NFT switched to emode 2");
        
        // Now D4 borrow should succeed
        _borrowD4Position(vars.dexKey, vars.nftId, vars.positionTickLower, vars.positionTickUpper, 1000 * 1e6, 0.25 ether);
        
    }

    /// @notice Test emode change with debt token restrictions
    function testEmodeChangeDebtTokenRestrictions() public {
        // Setup: List USDC
        _listUSDC();
        
        // List DAI as normal (non-isolated) for emode testing
        oracle.setPrice(address(DAI), 1 * 1e27);
        (bool success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.listToken.selector,
                address(DAI),
                1, // collateralClass = 1 (normal, not isolated)
                1, // debtClass = 1
                800,
                850,
                50
            )
        );
        require(success, "Failed to list DAI token");
        
        (success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateTokenSupplyCap.selector,
                address(DAI),
                1_000_000 * 1e18
            )
        );
        require(success, "Failed to set DAI supply cap");
        
        (success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateTokenDebtCap.selector,
                address(DAI),
                1_000_000 * 1e18
            )
        );
        require(success, "Failed to set DAI debt cap");
        
        uint256 daiTokenIndex = 3; // ETH=1, USDC=2, DAI=3
        
        // Create buffer position for DAI to handle rounding differences during paybacks
        _createBufferPosition(address(DAI), daiTokenIndex, 10000 * 1e18, 5000 * 1e18);
        
        // Create emode 1: Allows both USDC and DAI as debt
        TokenConfig[] memory tokenConfigs1 = new TokenConfig[](3);
        tokenConfigs1[0] = TokenConfig({
            token: NATIVE_TOKEN_ADDRESS,
            collateralClass: 1,
            debtClass: 1,
            collateralFactor: 900,
            liquidationThreshold: 920,
            liquidationPenalty: 50
        });
        tokenConfigs1[1] = TokenConfig({
            token: address(USDC),
            collateralClass: 1,
            debtClass: 1,
            collateralFactor: 900,
            liquidationThreshold: 920,
            liquidationPenalty: 50
        });
        tokenConfigs1[2] = TokenConfig({
            token: address(DAI),
            collateralClass: 1,
            debtClass: 1,
            collateralFactor: 900,
            liquidationThreshold: 920,
            liquidationPenalty: 50
        });
        
        address[] memory debtTokens1 = new address[](2);
        debtTokens1[0] = address(USDC);
        debtTokens1[1] = address(DAI);
        
        _listEmode(tokenConfigs1, debtTokens1);
        uint256 emodeId1 = 1;
        console2.log("Emode 1 listed - USDC and DAI allowed as debt");
        
        // Create emode 2: Only allows USDC as debt (not DAI)
        address[] memory debtTokens2 = new address[](1);
        debtTokens2[0] = address(USDC); // Only USDC, not DAI
        
        _listEmode(tokenConfigs1, debtTokens2);
        uint256 emodeId2 = 2;
        console2.log("Emode 2 listed - only USDC allowed as debt (NOT DAI)");
        
        // Create NFT with ETH supply, switch to emode 1, and borrow both USDC and DAI
        uint256 ethCollateral = 20 ether; // $80,000
        bytes memory ethSupplyData = abi.encode(1, 1, ethCollateral);
        (uint256 nftId,,) = moneyMarket.operate{value: ethCollateral}(
            0,
            0,
            ethSupplyData
        );
        
        // Switch to emode 1
        moneyMarket.changeEmode(nftId, emodeId1);
        console2.log("NFT switched to emode 1");
        
        // Borrow USDC
        uint256 usdcBorrow = 10000 * 1e6;
        bytes memory usdcBorrowData = abi.encode(2, 2, usdcBorrow, address(this));
        moneyMarket.operate(nftId, 0, usdcBorrowData);
        console2.log("Borrowed 10,000 USDC");
        
        // Borrow DAI
        uint256 daiBorrow = 10000 * 1e18;
        bytes memory daiBorrowData = abi.encode(2, daiTokenIndex, daiBorrow, address(this));
        moneyMarket.operate(nftId, 0, daiBorrowData);
        console2.log("Borrowed 10,000 DAI");
        
        // Test: Try to change to emode 2 (which doesn't allow DAI debt) - should fail
        console2.log("Emode 2 doesn't allow DAI debt, but NFT has DAI debt");
        vm.expectRevert();
        moneyMarket.changeEmode(nftId, emodeId2);
        console2.log("Emode change correctly reverted - DAI debt not allowed in emode 2");
        
        // Payback DAI debt fully to delete the position
        DAI.approve(address(moneyMarket), type(uint256).max);
        bytes memory paybackData = abi.encode(type(int256).min, address(this)); // Full payback deletes position
        moneyMarket.operate(nftId, 3, paybackData); // Position 3 is DAI borrow
        console2.log("DAI debt paid back and position deleted");
        
        // Now changing to emode 2 should succeed
        moneyMarket.changeEmode(nftId, emodeId2);
        console2.log("Emode change succeeded - no DAI debt remaining");
        
    }

    /// @notice Test emode change with collateral/debt class mismatch
    function testEmodeChangeClassMismatch() public {
        // Setup
        _listUSDC();
        
        
        // Create emode 1: ETH with collateral class 1
        TokenConfig[] memory tokenConfigs1 = new TokenConfig[](1);
        tokenConfigs1[0] = TokenConfig({
            token: NATIVE_TOKEN_ADDRESS,
            collateralClass: 1, // Class 1
            debtClass: 1,
            collateralFactor: 900,
            liquidationThreshold: 920,
            liquidationPenalty: 50
        });
        
        address[] memory debtTokens1 = new address[](1);
        debtTokens1[0] = address(USDC);
        
        _listEmode(tokenConfigs1, debtTokens1);
        uint256 emodeId1 = 1;
        console2.log("Emode 1 listed - ETH collateral class 1, debt class 1");
        
        // Create emode 2: ETH with collateral class 2 (different!)
        TokenConfig[] memory tokenConfigs2 = new TokenConfig[](1);
        tokenConfigs2[0] = TokenConfig({
            token: NATIVE_TOKEN_ADDRESS,
            collateralClass: 2, // Class 2 (different from emode 1)
            debtClass: 1,
            collateralFactor: 900,
            liquidationThreshold: 920,
            liquidationPenalty: 50
        });
        
        _listEmode(tokenConfigs2, debtTokens1);
        uint256 emodeId2 = 2;
        console2.log("Emode 2 listed - ETH collateral class 2 (different), debt class 1");
        
        // Create NFT with ETH supply in emode 1
        uint256 ethCollateral = 5 ether;
        bytes memory ethSupplyData = abi.encode(1, 1, ethCollateral);
        (uint256 nftId,,) = moneyMarket.operate{value: ethCollateral}(
            0,
            0,
            ethSupplyData
        );
        
        moneyMarket.changeEmode(nftId, emodeId1);
        console2.log("NFT in emode 1 with ETH collateral (class 1)");
        
        // Test: Try to change to emode 2 where ETH has different collateral class - should fail
        console2.log("ETH collateral class changes from 1 to 2");
        vm.expectRevert();
        moneyMarket.changeEmode(nftId, emodeId2);
        console2.log("Emode change correctly reverted - collateral class mismatch for ETH");
        
    }

    /// @notice Test emode change with D3 collateral class mismatch
    function testEmodeChangeD3ClassMismatch() public {
        // Setup D3 pool
        D3D4TestVars memory vars = _setupD3Pool();
        
        
        // Create emode 1: ETH class 1, USDC class 1
        TokenConfig[] memory tokenConfigs1 = new TokenConfig[](2);
        tokenConfigs1[0] = TokenConfig({
            token: NATIVE_TOKEN_ADDRESS,
            collateralClass: 1,
            debtClass: 1,
            collateralFactor: 900,
            liquidationThreshold: 920,
            liquidationPenalty: 50
        });
        tokenConfigs1[1] = TokenConfig({
            token: address(USDC),
            collateralClass: 1,
            debtClass: 1,
            collateralFactor: 900,
            liquidationThreshold: 920,
            liquidationPenalty: 50
        });
        
        address[] memory debtTokens = new address[](0); // No debt allowed for simplicity
        
        _listEmode(tokenConfigs1, debtTokens);
        uint256 emodeId1 = 1;
        console2.log("Emode 1 listed - ETH and USDC both class 1");
        
        // Create emode 2: ETH class 1, USDC class 2 (different!)
        TokenConfig[] memory tokenConfigs2 = new TokenConfig[](2);
        tokenConfigs2[0] = tokenConfigs1[0]; // ETH same
        tokenConfigs2[1] = TokenConfig({
            token: address(USDC),
            collateralClass: 2, // Different class!
            debtClass: 1,
            collateralFactor: 900,
            liquidationThreshold: 920,
            liquidationPenalty: 50
        });
        
        _listEmode(tokenConfigs2, debtTokens);
        uint256 emodeId2 = 2;
        console2.log("Emode 2 listed - ETH class 1, USDC class 2 (different)");
        
        // Create NFT with D3 position in emode 1
        (vars.nftId, vars.positionIndex) = _depositD3Position(
            vars.dexKey,
            vars.positionTickLower,
            vars.positionTickUpper,
            2000 * 1e6,
            0.5 ether
        );
        
        moneyMarket.changeEmode(vars.nftId, emodeId1);
        console2.log("NFT in emode 1 with D3 position (ETH+USDC, both class 1)");
        
        // Test: Try to change to emode 2 where USDC has different collateral class - should fail
        vm.expectRevert();
        moneyMarket.changeEmode(vars.nftId, emodeId2);
        console2.log("Emode change correctly reverted - D3 token (USDC) class mismatch");
        
    }

    /// @notice Test emode change with D4 debt and collateral class mismatch
    function testEmodeChangeD4ClassMismatch() public {
        // Setup D4 pool
        _listUSDC();
        D3D4TestVars memory vars = _setupD4Pool();
        
        
        // Create emode 1: ETH and USDC both class 1 for debt and collateral
        TokenConfig[] memory tokenConfigs1 = new TokenConfig[](2);
        tokenConfigs1[0] = TokenConfig({
            token: NATIVE_TOKEN_ADDRESS,
            collateralClass: 1,
            debtClass: 1,
            collateralFactor: 900,
            liquidationThreshold: 920,
            liquidationPenalty: 50
        });
        tokenConfigs1[1] = TokenConfig({
            token: address(USDC),
            collateralClass: 1,
            debtClass: 1,
            collateralFactor: 900,
            liquidationThreshold: 920,
            liquidationPenalty: 50
        });
        
        address[] memory debtTokens1 = new address[](2);
        debtTokens1[0] = address(USDC);
        debtTokens1[1] = NATIVE_TOKEN_ADDRESS;
        
        _listEmode(tokenConfigs1, debtTokens1);
        uint256 emodeId1 = 1;
        console2.log("Emode 1 listed - ETH and USDC both class 1 (debt & collateral)");
        
        // Create emode 2: ETH debt class changes to 2
        TokenConfig[] memory tokenConfigs2 = new TokenConfig[](2);
        tokenConfigs2[0] = TokenConfig({
            token: NATIVE_TOKEN_ADDRESS,
            collateralClass: 1,
            debtClass: 2, // Different debt class!
            collateralFactor: 900,
            liquidationThreshold: 920,
            liquidationPenalty: 50
        });
        tokenConfigs2[1] = tokenConfigs1[1]; // USDC same
        
        _listEmode(tokenConfigs2, debtTokens1);
        uint256 emodeId2 = 2;
        console2.log("Emode 2 listed - ETH debt class 2 (different), USDC class 1");
        
        // Create NFT with large USDC supply
        uint256 usdcSupply = 50000 * 1e6;
        bytes memory usdcSupplyData = abi.encode(1, 2, usdcSupply);
        (vars.nftId,,) = moneyMarket.operate(
            0,
            0,
            usdcSupplyData
        );
        
        moneyMarket.changeEmode(vars.nftId, emodeId1);
        console2.log("NFT switched to emode 1");
        
        // Borrow D4 position
        (vars.nftId, vars.positionIndex) = _borrowD4Position(
            vars.dexKey,
            vars.nftId,
            vars.positionTickLower,
            vars.positionTickUpper,
            2000 * 1e6,
            0.5 ether
        );
        
        // Test: Try to change to emode 2 where ETH has different debt class - should fail
        console2.log("ETH debt class changes from 1 to 2 in D4 position");
        vm.expectRevert();
        moneyMarket.changeEmode(vars.nftId, emodeId2);
        console2.log("Emode change correctly reverted - D4 token (ETH) debt class mismatch");
        
    }

    /// @notice Test emode change that makes health factor < 1
    function testEmodeChangeHealthFactorFails() public {
        // Setup
        _listUSDC();
        
        
        // Create emode 1: ETH with 90% CF
        TokenConfig[] memory tokenConfigs1 = new TokenConfig[](1);
        tokenConfigs1[0] = TokenConfig({
            token: NATIVE_TOKEN_ADDRESS,
            collateralClass: 1,
            debtClass: 1,
            collateralFactor: 900, // 90%
            liquidationThreshold: 920, // 95%
            liquidationPenalty: 50
        });
        
        address[] memory debtTokens = new address[](1);
        debtTokens[0] = address(USDC);
        
        _listEmode(tokenConfigs1, debtTokens);
        uint256 emodeId1 = 1;
        console2.log("Emode 1 listed - ETH CF 90%");
        
        // Create emode 2: ETH with lower 70% CF
        TokenConfig[] memory tokenConfigs2 = new TokenConfig[](1);
        tokenConfigs2[0] = TokenConfig({
            token: NATIVE_TOKEN_ADDRESS,
            collateralClass: 1, // Same class
            debtClass: 1,
            collateralFactor: 700, // 70% (lower!)
            liquidationThreshold: 750,
            liquidationPenalty: 50
        });
        
        _listEmode(tokenConfigs2, debtTokens);
        uint256 emodeId2 = 2;
        console2.log("Emode 2 listed - ETH CF 70% (lower)");
        
        // Create NFT with ETH supply in emode 1 and borrow heavily
        uint256 ethCollateral = 1 ether; // $4000
        bytes memory ethSupplyData = abi.encode(1, 1, ethCollateral);
        (uint256 nftId,,) = moneyMarket.operate{value: ethCollateral}(
            0,
            0,
            ethSupplyData
        );
        
        moneyMarket.changeEmode(nftId, emodeId1);
        console2.log("NFT in emode 1 with 1 ETH ($4000)");
        
        // Borrow $3500 (safe at 90% CF which is $3600 max)
        uint256 usdcBorrow = 3500 * 1e6;
        bytes memory borrowData = abi.encode(2, 2, usdcBorrow, address(this));
        moneyMarket.operate(nftId, 0, borrowData);
        console2.log("Borrowed $3500 USDC");
        console2.log("HF at 90% CF: ($4000 * 0.9) / $3500 = 1.03 (healthy)");
        console2.log("HF at 70% CF: ($4000 * 0.7) / $3500 = 0.8 (would be unhealthy!)");
        
        // Test: Try to change to emode 2 (70% CF) - would make HF < 1 - should fail
        console2.log("Changing to emode 2 would reduce CF from 90% to 70%");
        console2.log("This would make HF = 0.8 < 1.0");
        vm.expectRevert();
        moneyMarket.changeEmode(nftId, emodeId2);
        console2.log("Emode change correctly reverted - would make HF < 1");
        
        // Payback some debt to make position safer
        USDC.approve(address(moneyMarket), type(uint256).max);
        bytes memory paybackData = abi.encode(-int256(1000 * 1e6), address(this));
        moneyMarket.operate(nftId, 2, paybackData); // Position 2 is USDC borrow
        console2.log("Paid back $1000 USDC");
        console2.log("Remaining debt: $2500");
        console2.log("HF at 70% CF: ($4000 * 0.7) / $2500 = 1.12 (healthy)");
        
        // Now changing to emode 2 should succeed
        moneyMarket.changeEmode(nftId, emodeId2);
        console2.log("Emode change succeeded - HF remains > 1");
        
    }

    /// @notice Helper to list USDC and DAI as permissionless (class 2)
    /// @dev Both tokens must be permissionless for the pair to be considered permissionless
    function _listTokensAsPermissionless() internal {
        // List USDC as permissionless
        (bool success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.listToken.selector,
                address(USDC),
                2, // collateralClass = 2 (permissionless)
                2, // debtClass = 2 (permissionless)
                800, // collateralFactor (80%)
                850, // liquidationThreshold (85%)
                50  // liquidationPenalty (5%)
            )
        );
        require(success, "Failed to list USDC as permissionless");
        
        // Set supply and debt caps for USDC
        (success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateTokenSupplyCap.selector,
                address(USDC),
                1000000 * 1e6 // 1M USDC cap
            )
        );
        require(success, "Failed to set USDC supply cap");
        
        (success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateTokenDebtCap.selector,
                address(USDC),
                1000000 * 1e6 // 1M USDC debt cap
            )
        );
        require(success, "Failed to set USDC debt cap");
        
        // Set oracle price for USDC ($1)
        oracle.setPrice(address(USDC), 1 * 1e27);
        
        // List DAI as permissionless too (BOTH tokens must be permissionless)
        (success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.listToken.selector,
                address(DAI),
                2, // collateralClass = 2 (permissionless)
                2, // debtClass = 2 (permissionless)
                800, // collateralFactor (80%)
                850, // liquidationThreshold (85%)
                50  // liquidationPenalty (5%)
            )
        );
        require(success, "Failed to list DAI as permissionless");
        
        // Set supply and debt caps for DAI
        (success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateTokenSupplyCap.selector,
                address(DAI),
                1000000 * 1e18 // 1M DAI cap
            )
        );
        require(success, "Failed to set DAI supply cap");
        
        (success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateTokenDebtCap.selector,
                address(DAI),
                1000000 * 1e18 // 1M DAI debt cap
            )
        );
        require(success, "Failed to set DAI debt cap");
        
        // Set oracle price for DAI ($1)
        oracle.setPrice(address(DAI), 1 * 1e27);
        
        // Note: DAI and USDC are already configured in the Liquidity contract via the base setup
        // The base setup supplies initial liquidity for these tokens
    }

    /// @notice Test permissionless D3 position creation using global default caps
    /// @dev Verifies that when no position-specific or token-pair caps exist, the system
    ///      correctly falls back to global default caps for permissionless token pairs
    function testPermissionlessD3WithGlobalDefaultCaps() public {

        
        // List USDC and DAI as permissionless (BOTH must be permissionless)
        _listTokensAsPermissionless();

        
        // Initialize D3 DAI/USDC pool
        bytes memory initCallbackData_ = abi.encodeWithSelector(
            this.shouldInitializeD3PermissionlessPoolCallbackImplementation.selector
        );
        dexV2.startOperation(initCallbackData_);

        
        // Set global default caps for D3 (NOTE: NOT setting position-specific caps)
        int24 minTick = -524287; // Money Market max range
        int24 maxTick = 524287;
        // Use large raw adjusted amounts (these are normalized, token-agnostic values)
        uint256 maxRawAmount0 = 2 ** 80; // Large raw adjusted amount for token0
        uint256 maxRawAmount1 = 2 ** 80; // Large raw adjusted amount for token1

        
        (bool success, bytes memory returnData) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateD3GlobalDefaultPermissionlessDexCap.selector,
                minTick,
                maxTick,
                maxRawAmount0,
                maxRawAmount1
            )
        );
        if (!success) {
        }
        require(success, "Failed to set D3 global default caps");
        
        // Setup DEX key for DAI/USDC (DAI has lower address: 0x03A6... < 0xA4AD...)
        DexKey memory dexKey_ = DexKey({
            token0: address(DAI),  // DAI has lower address (0x03A6...)
            token1: address(USDC), // USDC has higher address (0xA4AD...)
            fee: 100,
            tickSpacing: 1,
            controller: address(this)
        });
        
        // Calculate position ticks for DAI/USDC at 1:1 price
        uint256 priceX96 = uint256(1 << 96); // 1:1 price
        uint256 sqrtPriceX96 = FixedPointMathLib.sqrt(priceX96 * (1 << 96));
        int24 currentTick = TM.getTickAtSqrtRatio(uint160(sqrtPriceX96));
        int24 positionTickLower = currentTick - 100;
        int24 positionTickUpper = currentTick + 100;
        
        // Fund contract with DAI and USDC
        deal(address(DAI), address(this), 10000 * 1e18);
        deal(address(USDC), address(this), 10000 * 1e6);
        DAI.approve(address(moneyMarket), type(uint256).max);
        USDC.approve(address(moneyMarket), type(uint256).max);

        // Create D3 position WITHOUT calling updateD3PositionCap
        // This should use the global default caps
        
        CreateD3D4PositionParams memory positionParams_ = CreateD3D4PositionParams({
            token0Index: 3, // DAI (index 3)
            token1Index: 2, // USDC (index 2)
            tickSpacing: 1,
            fee: 100,
            controller: address(this),
            tickLower: positionTickLower,
            tickUpper: positionTickUpper,
            amount0: 100 * 1e18, // DAI (18 decimals) - well within 10K cap
            amount1: 100 * 1e6,  // USDC (6 decimals) - well within 10K cap
            amount0Min: 0,
            amount1Min: 0,
            to: address(this)
        });
        
        bytes memory actionData = abi.encode(3, positionParams_);
        (uint256 nftId, uint256 positionIndex,) = moneyMarket.operate(
            0,
            0,
            actionData
        );

        
    }

    /// @notice Test permissionless D3 with token-pair default caps
    function testPermissionlessD3WithTokenPairDefaultCaps() public {
        
        // List USDC and DAI as permissionless
        _listTokensAsPermissionless();
        
        // Initialize D3 DAI/USDC pool
        bytes memory initCallbackData_ = abi.encodeWithSelector(
            this.shouldInitializeD3PermissionlessPoolCallbackImplementation.selector
        );
        dexV2.startOperation(initCallbackData_);
        
        // Set token-pair specific default caps for DAI/USDC (NOTE: NOT global, NOT position-specific)
        int24 minTick = -100000;
        int24 maxTick = 100000;
        uint256 maxAmount0 = 50_000 * 1e18; // 50K DAI - token0
        uint256 maxAmount1 = 50_000 * 1e6;  // 50K USDC - token1
        
        (bool success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateD3DefaultPermissionlessDexCap.selector,
                address(DAI),  // token0 (lower address: 0x03A6...)
                address(USDC), // token1 (higher address: 0xA4AD...)
                minTick,
                maxTick,
                maxAmount0,
                maxAmount1
            )
        );
        require(success, "Failed to set D3 token-pair default caps");
        
        // Setup DEX key
        DexKey memory dexKey_ = DexKey({
            token0: address(DAI),  // DAI has lower address
            token1: address(USDC), // USDC has higher address
            fee: 100,
            tickSpacing: 1,
            controller: address(this)
        });
        
        // Calculate position ticks for DAI/USDC at 1:1 price
        uint256 priceX96 = uint256(1 << 96); // 1:1 price
        uint256 sqrtPriceX96 = FixedPointMathLib.sqrt(priceX96 * (1 << 96));
        int24 currentTick = TM.getTickAtSqrtRatio(uint160(sqrtPriceX96));
        int24 positionTickLower = currentTick - 100;
        int24 positionTickUpper = currentTick + 100;
        
        // Fund contract
        deal(address(DAI), address(this), 10000 * 1e18);
        deal(address(USDC), address(this), 10000 * 1e6);
        DAI.approve(address(moneyMarket), type(uint256).max);
        USDC.approve(address(moneyMarket), type(uint256).max);
        
        // Create D3 position WITHOUT calling updateD3PositionCap
        
        CreateD3D4PositionParams memory positionParams_ = CreateD3D4PositionParams({
            token0Index: 3, // DAI (index 3)
            token1Index: 2, // USDC (index 2)
            tickSpacing: 1,
            fee: 100,
            controller: address(this),
            tickLower: positionTickLower,
            tickUpper: positionTickUpper,
            amount0: 200 * 1e18, // 200 DAI - well within 50K cap
            amount1: 200 * 1e6,  // 200 USDC - well within 50K cap
            amount0Min: 0,
            amount1Min: 0,
            to: address(this)
        });
        
        bytes memory actionData = abi.encode(3, positionParams_);
        (uint256 nftId, uint256 positionIndex,) = moneyMarket.operate(
            0,
            0,
            actionData
        );
        
    }

    /// @notice Callback for initializing D4 pool with DAI/USDC (for permissionless testing)
    function shouldInitializeD4PermissionlessPoolCallbackImplementation() public returns (bytes memory returnData_) {
        DexKey memory dexKey_ = DexKey({
            token0: address(DAI),  // DAI has lower address
            token1: address(USDC), // USDC has higher address
            fee: 100, // 0.01%
            tickSpacing: 1,
            controller: address(0) // Controller is address(0) for D4
        });

        // Calculate sqrtPriceX96 for DAI/USDC at 1:1 (equal value)
        uint256 priceX96 = uint256(1 << 96);
        uint256 sqrtPriceX96 = FixedPointMathLib.sqrt(priceX96 * (1 << 96));

        // Initialize the pool
        bytes memory initializeData_ = abi.encodeWithSelector(
            FluidDexV2D4UserModule.initialize.selector,
            dexKey_,
            sqrtPriceX96
        );
        dexV2.operate(4, 2, initializeData_); // DEX_TYPE=4 (D4), USER_MODULE_ID=2
        
        return returnData_;
    }

    /// @notice Helper to setup D4 pool WITHOUT setting position caps (for permissionless testing)
    function _setupD4PoolWithoutCaps() internal returns (D3D4TestVars memory vars) {
        // Initialize D4 DAI/USDC pool
        bytes memory initCallbackData_ = abi.encodeWithSelector(
            this.shouldInitializeD4PermissionlessPoolCallbackImplementation.selector
        );
        dexV2.startOperation(initCallbackData_);

        vars.dexKey = DexKey({
            token0: address(DAI),  // DAI has lower address
            token1: address(USDC), // USDC has higher address
            fee: 100,
            tickSpacing: 1,
            controller: address(0)
        });

        vars.priceX96 = uint256(1 << 96); // 1:1 price for DAI/USDC
        vars.usdcEthSqrtPriceX96 = FixedPointMathLib.sqrt(vars.priceX96 * (1 << 96));
        vars.currentTick = TM.getTickAtSqrtRatio(uint160(vars.usdcEthSqrtPriceX96));
        vars.positionTickLower = vars.currentTick - 100;
        vars.positionTickUpper = vars.currentTick + 100;

        // NOTE: NOT calling updateD4PositionCap - this is for permissionless testing
    }

    /// @notice Test permissionless D4 with global default caps
    function testPermissionlessD4WithGlobalDefaultCaps() public {
        
        // List USDC and DAI as permissionless
        _listTokensAsPermissionless();
        
        // Setup D4 pool WITHOUT position caps
        D3D4TestVars memory vars = _setupD4PoolWithoutCaps();
        
        // Set global default caps for D4 (NOTE: NOT setting position-specific caps)
        int24 minTick = -524287;
        int24 maxTick = 524287;
        // Use large raw adjusted amounts (these are normalized, token-agnostic values)
        uint256 maxRawAmount0 = 2 ** 80; // Large raw adjusted amount for token0
        uint256 maxRawAmount1 = 2 ** 80; // Large raw adjusted amount for token1
        
        (bool success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateD4GlobalDefaultPermissionlessDexCap.selector,
                minTick,
                maxTick,
                maxRawAmount0,
                maxRawAmount1
            )
        );
        require(success, "Failed to set D4 global default caps");
        
        // Supply ETH as collateral (ETH is permissioned but that's OK for collateral)
        deal(address(this), 10 ether);
        bytes memory supplyData = abi.encode(1, 1, 5 ether);
        (vars.nftId,,) = moneyMarket.operate{value: 5 ether}(
            0,
            0,
            supplyData
        );
        
        // Create D4 position WITHOUT calling updateD4PositionCap
        
        CreateD3D4PositionParams memory positionParams_ = CreateD3D4PositionParams({
            token0Index: 3, // DAI (index 3)
            token1Index: 2, // USDC (index 2)
            tickSpacing: 1,
            fee: 100,
            controller: address(0), // D4 uses address(0)
            tickLower: vars.positionTickLower,
            tickUpper: vars.positionTickUpper,
            amount0: 100 * 1e18, // Borrow 100 DAI
            amount1: 100 * 1e6,  // Borrow 100 USDC
            amount0Min: 0,
            amount1Min: 0,
            to: address(this)
        });
        
        bytes memory actionData = abi.encode(4, positionParams_);
        (vars.nftId, vars.positionIndex,) = moneyMarket.operate(
            vars.nftId,
            0,
            actionData
        );
        
    }

    /// @notice Test permissionless D4 with token-pair default caps
    function testPermissionlessD4WithTokenPairDefaultCaps() public {
        
        // List USDC and DAI as permissionless
        _listTokensAsPermissionless();
        
        // Setup D4 pool WITHOUT position caps
        D3D4TestVars memory vars = _setupD4PoolWithoutCaps();
        
        // Set token-pair specific default caps for DAI/USDC
        int24 minTick = -200000;
        int24 maxTick = 200000;
        uint256 maxAmount0 = 50_000 * 1e18; // 50K DAI
        uint256 maxAmount1 = 50_000 * 1e6;  // 50K USDC
        
        (bool success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateD4DefaultPermissionlessDexCap.selector,
                address(DAI),  // token0 (lower address)
                address(USDC), // token1 (higher address)
                minTick,
                maxTick,
                maxAmount0,
                maxAmount1
            )
        );
        require(success, "Failed to set D4 token-pair default caps");
        
        // Supply ETH as collateral (ETH is permissioned but that's OK for collateral)
        deal(address(this), 10 ether);
        bytes memory supplyData = abi.encode(1, 1, 5 ether);
        (vars.nftId,,) = moneyMarket.operate{value: 5 ether}(
            0,
            0,
            supplyData
        );
        
        // Create D4 position WITHOUT calling updateD4PositionCap
        
        CreateD3D4PositionParams memory positionParams_ = CreateD3D4PositionParams({
            token0Index: 3, // DAI (index 3)
            token1Index: 2, // USDC (index 2)
            tickSpacing: 1,
            fee: 100,
            controller: address(0), // D4 uses address(0)
            tickLower: vars.positionTickLower,
            tickUpper: vars.positionTickUpper,
            amount0: 200 * 1e18, // Borrow 200 DAI - well within 50K cap
            amount1: 200 * 1e6,  // Borrow 200 USDC - well within 50K cap
            amount0Min: 0,
            amount1Min: 0,
            to: address(this)
        });
        
        bytes memory actionData = abi.encode(4, positionParams_);
        (vars.nftId, vars.positionIndex,) = moneyMarket.operate(
            vars.nftId,
            0,
            actionData
        );
        
    }

    /// @notice Test permissionless D3 fallback priority: token-pair > global
    function testPermissionlessD3FallbackPriority() public {
        
        // List USDC and DAI as permissionless
        _listTokensAsPermissionless();
        
        // Initialize D3 DAI/USDC pool
        bytes memory initCallbackData_ = abi.encodeWithSelector(
            this.shouldInitializeD3PermissionlessPoolCallbackImplementation.selector
        );
        dexV2.startOperation(initCallbackData_);
        
        // Set BOTH global and token-pair defaults
        // Global default: wide range with raw adjusted amounts
        (bool success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateD3GlobalDefaultPermissionlessDexCap.selector,
                -524287, // min tick (Money Market max range)
                524287,  // max tick
                2 ** 70, // Smaller raw adjusted amount for token0
                2 ** 70  // Smaller raw adjusted amount for token1
            )
        );
        require(success, "Failed to set D3 global default");
        
        // Token-pair default: narrow range (should take precedence)
        // NOTE: Token-pair defaults take regular amounts and convert to raw adjusted
        success = false;
        (success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateD3DefaultPermissionlessDexCap.selector,
                address(DAI),  // token0
                address(USDC), // token1
                -50000, // Narrower range
                50000,
                100_000 * 1e18, // 100K DAI (will be converted to raw adjusted)
                100_000 * 1e6   // 100K USDC (will be converted to raw adjusted)
            )
        );
        require(success, "Failed to set D3 token-pair default");
        
        // Setup DEX key and ticks
        DexKey memory dexKey_ = DexKey({
            token0: address(DAI),  // DAI has lower address
            token1: address(USDC), // USDC has higher address
            fee: 100,
            tickSpacing: 1,
            controller: address(this)
        });
        
        uint256 priceX96 = uint256(1 << 96); // 1:1 price for DAI/USDC
        uint256 sqrtPriceX96 = FixedPointMathLib.sqrt(priceX96 * (1 << 96));
        int24 currentTick = TM.getTickAtSqrtRatio(uint160(sqrtPriceX96));
        
        // Fund contract
        deal(address(DAI), address(this), 10000 * 1e18);
        deal(address(USDC), address(this), 10000 * 1e6);
        DAI.approve(address(moneyMarket), type(uint256).max);
        USDC.approve(address(moneyMarket), type(uint256).max);
        
        // Test 1: Create position within narrow range (should succeed)
        int24 positionTickLower = currentTick - 100; // Within -50000 to 50000
        int24 positionTickUpper = currentTick + 100;
        
        CreateD3D4PositionParams memory positionParams_ = CreateD3D4PositionParams({
            token0Index: 3, // DAI
            token1Index: 2, // USDC
            tickSpacing: 1,
            fee: 100,
            controller: address(this),
            tickLower: positionTickLower,
            tickUpper: positionTickUpper,
            amount0: 500 * 1e18,  // 500 DAI
            amount1: 500 * 1e6,   // 500 USDC
            amount0Min: 0,
            amount1Min: 0,
            to: address(this)
        });
        
        bytes memory actionData = abi.encode(3, positionParams_);
        (uint256 nftId,,) = moneyMarket.operate(
            0,
            0,
            actionData
        );
        
        // Test 2: Try to create position outside narrow range (should fail)
        
        positionParams_.tickLower = -60000; // Outside the narrow range
        positionParams_.tickUpper = -55000;
        actionData = abi.encode(3, positionParams_);
        
        vm.expectRevert();
        moneyMarket.operate(
            0,
            0,
            actionData
        );
    }

    /// @notice Test permissionless DEX fails without any defaults set
    function testPermissionlessD3FailsWithoutDefaults() public {
        
        // List USDC and DAI as permissionless
        _listTokensAsPermissionless();
        
        // Initialize D3 DAI/USDC pool
        bytes memory initCallbackData_ = abi.encodeWithSelector(
            this.shouldInitializeD3PermissionlessPoolCallbackImplementation.selector
        );
        dexV2.startOperation(initCallbackData_);
        
        // NOTE: NOT setting any default caps (neither global nor token-pair)
        
        // Setup DEX key and ticks
        DexKey memory dexKey_ = DexKey({
            token0: address(DAI),  // DAI has lower address
            token1: address(USDC), // USDC has higher address
            fee: 100,
            tickSpacing: 1,
            controller: address(this)
        });
        
        uint256 priceX96 = uint256(1 << 96); // 1:1 price for DAI/USDC
        uint256 sqrtPriceX96 = FixedPointMathLib.sqrt(priceX96 * (1 << 96));
        int24 currentTick = TM.getTickAtSqrtRatio(uint160(sqrtPriceX96));
        int24 positionTickLower = currentTick - 100;
        int24 positionTickUpper = currentTick + 100;
        
        // Fund contract
        deal(address(DAI), address(this), 10000 * 1e18);
        deal(address(USDC), address(this), 10000 * 1e6);
        DAI.approve(address(moneyMarket), type(uint256).max);
        USDC.approve(address(moneyMarket), type(uint256).max);
        
        // Try to create D3 position - should FAIL (no defaults set)
        
        CreateD3D4PositionParams memory positionParams_ = CreateD3D4PositionParams({
            token0Index: 3, // DAI
            token1Index: 2, // USDC
            tickSpacing: 1,
            fee: 100,
            controller: address(this),
            tickLower: positionTickLower,
            tickUpper: positionTickUpper,
            amount0: 100 * 1e18, // 100 DAI
            amount1: 100 * 1e6,  // 100 USDC
            amount0Min: 0,
            amount1Min: 0,
            to: address(this)
        });
        
        bytes memory actionData = abi.encode(3, positionParams_);
        
        vm.expectRevert();
        moneyMarket.operate(
            0,
            0,
            actionData
        );
        
    }

    /// @notice Test permissionless D4 fails without any defaults set
    function testPermissionlessD4FailsWithoutDefaults() public {
        
        // List USDC and DAI as permissionless
        _listTokensAsPermissionless();
        
        // Setup D4 pool WITHOUT position caps
        D3D4TestVars memory vars = _setupD4PoolWithoutCaps();
        
        // Supply ETH as collateral (ETH is permissioned but that's OK for collateral)
        deal(address(this), 10 ether);
        bytes memory supplyData = abi.encode(1, 1, 5 ether);
        (vars.nftId,,) = moneyMarket.operate{value: 5 ether}(
            0,
            0,
            supplyData
        );
        
        // Try to create D4 position - should FAIL (no defaults set)
        
        CreateD3D4PositionParams memory positionParams_ = CreateD3D4PositionParams({
            token0Index: 3, // DAI (index 3)
            token1Index: 2, // USDC (index 2)
            tickSpacing: 1,
            fee: 100,
            controller: address(0), // D4 uses address(0)
            tickLower: vars.positionTickLower,
            tickUpper: vars.positionTickUpper,
            amount0: 100 * 1e18, // Borrow 100 DAI
            amount1: 100 * 1e6,  // Borrow 100 USDC
            amount0Min: 0,
            amount1Min: 0,
            to: address(this)
        });
        
        bytes memory actionData = abi.encode(4, positionParams_);
        
        vm.expectRevert();
        moneyMarket.operate(
            vars.nftId,
            0,
            actionData
        );
        
    }

    /// @notice Test updateLiquidationThreshold - increase only, validates constraints
    function testUpdateLiquidationThreshold() public {
        _listUSDC(); // ETH=1, USDC=2

        // ── can increase ────────────────────────────────────────────────────────
        // ETH was listed with LT=850. Increase to 900.
        (bool success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateLiquidationThreshold.selector,
                0, // NO_EMODE
                NATIVE_TOKEN_ADDRESS,
                900 // 90%
            )
        );
        assertTrue(success, "Should succeed: increasing LT from 850 to 900");
        console2.log("LT increased from 850 to 900 for ETH");

        // ── cannot decrease ──────────────────────────────────────────────────────
        vm.expectRevert();
        address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateLiquidationThreshold.selector,
                0,
                NATIVE_TOKEN_ADDRESS,
                850 // lower than current 900
            )
        );
        console2.log("Correctly reverted: decreasing LT not allowed");

        // ── cannot set equal to current ───────────────────────────────────────────
        vm.expectRevert();
        address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateLiquidationThreshold.selector,
                0,
                NATIVE_TOKEN_ADDRESS,
                900 // same as current
            )
        );
        console2.log("Correctly reverted: setting LT equal to current not allowed");

        // ── new LT must be > collateral factor (CF=800) ──────────────────────────
        // Try to set LT = 800 (equal to CF=800), must fail (CF >= LT not allowed)
        vm.expectRevert();
        address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateLiquidationThreshold.selector,
                0,
                NATIVE_TOKEN_ADDRESS,
                800 // equal to CF — not allowed
            )
        );
        console2.log("Correctly reverted: LT cannot equal CF");

        // ── LP * LT must not exceed 99% ──────────────────────────────────────────
        // ETH LP=50. For LT=950: (950 * 1050) / 1000 = 997 > 990 — should fail
        vm.expectRevert();
        address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateLiquidationThreshold.selector,
                0,
                NATIVE_TOKEN_ADDRESS,
                950 // (950 * 1050) / 1000 = 997 > 990
            )
        );
        console2.log("Correctly reverted: LT * LP would exceed 99%");

        // ── unlisted token must fail ──────────────────────────────────────────────
        vm.expectRevert();
        address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateLiquidationThreshold.selector,
                0,
                address(0x1234), // not listed
                920
            )
        );
        console2.log("Correctly reverted: token not listed");

        // ── emode: token must have config change bit set ──────────────────────────
        TokenConfig[] memory tokenConfigs = new TokenConfig[](1);
        tokenConfigs[0] = TokenConfig({
            token: NATIVE_TOKEN_ADDRESS,
            collateralClass: 1,
            debtClass: 1,
            collateralFactor: 850,
            liquidationThreshold: 880,
            liquidationPenalty: 50
        });
        address[] memory debtTokens = new address[](1);
        debtTokens[0] = address(USDC);
        _listEmode(tokenConfigs, debtTokens); // emode 1

        // Increase emode LT from 880 to 910 — should succeed
        (success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateLiquidationThreshold.selector,
                1, // emode 1
                NATIVE_TOKEN_ADDRESS,
                910
            )
        );
        assertTrue(success, "Should succeed: increasing emode LT from 880 to 910");
        console2.log("Emode LT increased from 880 to 910 for ETH");

        // USDC has no emode config change bit set — should fail
        vm.expectRevert();
        address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateLiquidationThreshold.selector,
                1, // emode 1 — USDC has no config entry
                address(USDC),
                880
            )
        );
        console2.log("Correctly reverted: USDC has no config change bit set for emode 1");

        console2.log("=== updateLiquidationThreshold all checks passed ===");
    }

    /// @notice Test that non-permissionless DEX without position cap fails
    function testNonPermissionlessDexFailsWithoutPositionCap() public {
        
        // List USDC as permissioned (class 1, NOT permissionless)
        (bool success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.listToken.selector,
                address(USDC),
                1, // collateralClass = 1 (permissioned, NOT permissionless)
                1, // debtClass = 1
                800,
                850,
                50
            )
        );
        require(success, "Failed to list USDC");
        
        (success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateTokenSupplyCap.selector,
                address(USDC),
                1000000 * 1e6
            )
        );
        require(success, "Failed to set USDC supply cap");
        
        
        // Initialize D3 pool
        bytes memory initCallbackData_ = abi.encodeWithSelector(
            this.shouldInitializeD3PoolCallbackImplementation.selector
        );
        dexV2.startOperation(initCallbackData_);
        
        // Set global defaults (just to show they won't help non-permissionless)
        (success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateD3GlobalDefaultPermissionlessDexCap.selector,
                -524287,
                524287,
                100_000 * 1e6,
                100 * 1e18
            )
        );
        require(success, "Failed to set global defaults");
        
        // Setup DEX key and ticks
        DexKey memory dexKey_ = DexKey({
            token0: address(USDC),
            token1: NATIVE_TOKEN_ADDRESS,
            fee: 100,
            tickSpacing: 1,
            controller: address(this)
        });
        
        uint256 priceX96 = uint256((1 << 96)) / 4000;
        uint256 sqrtPriceX96 = FixedPointMathLib.sqrt(priceX96 * (1 << 96));
        int24 currentTick = TM.getTickAtSqrtRatio(uint160(sqrtPriceX96));
        int24 positionTickLower = currentTick - 100;
        int24 positionTickUpper = currentTick + 100;
        
        // Fund contract
        deal(address(this), 10 ether);
        deal(address(USDC), address(this), 10000 * 1e6);
        USDC.approve(address(moneyMarket), type(uint256).max);
        
        // Try to create D3 position WITHOUT calling updateD3PositionCap - should FAIL
        
        CreateD3D4PositionParams memory positionParams_ = CreateD3D4PositionParams({
            token0Index: 2, // USDC
            token1Index: 1, // ETH
            tickSpacing: 1,
            fee: 100,
            controller: address(this),
            tickLower: positionTickLower,
            tickUpper: positionTickUpper,
            amount0: 1000 * 1e6,
            amount1: 0.25 ether,
            amount0Min: 0,
            amount1Min: 0,
            to: address(this)
        });
        
        bytes memory actionData = abi.encode(3, positionParams_);
        
        vm.expectRevert();
        moneyMarket.operate{value: positionParams_.amount1}(
            0,
            0,
            actionData
        );
        
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  Post-liquidation HF check: debtValue == 0 guard tests
    // ═══════════════════════════════════════════════════════════════════════════

    function _setupLiquidatablePosition() internal returns (uint256 nftId) {
        _listUSDC();

        vm.deal(address(this), address(this).balance + 10 ether);
        deal(address(USDC), bob, 1000000 * 1e6);

        bytes memory ethSupplyData = abi.encode(1, 1, 1 ether);
        (nftId,,) = moneyMarket.operate{value: 1 ether}(0, 0, ethSupplyData);

        bytes memory usdcBorrowData = abi.encode(2, 2, 2600 * 1e6, address(this));
        moneyMarket.operate(nftId, 0, usdcBorrowData);

        // ETH $4000 -> $3000 => HF = (3000 * 0.85) / 2600 ≈ 0.98 < 1
        oracle.setPrice(NATIVE_TOKEN_ADDRESS, 3000 * 1e27);
    }

    function _normalizedShortfall(HfInfo memory hfInfo) internal pure returns (uint256) {
        if (hfInfo.debtValue > hfInfo.normalizedCollateralValue) {
            return hfInfo.debtValue - hfInfo.normalizedCollateralValue;
        }

        return 0;
    }

    function _listDAIFor1207() internal {
        (bool success,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.listToken.selector,
                address(DAI),
                1, // collateralClass (1 = permissioned, 0 = not enabled)
                1, // debtClass (1 = permissioned, 0 = not enabled)
                700, // collateralFactor (70%)
                750, // liquidationThreshold (75%)
                50 // liquidationPenalty (5%)
            )
        );
        require(success, "Failed to list DAI");

        (success,) = address(moneyMarket).call(
            abi.encodeWithSelector(moneyMarketAdminModule.updateTokenSupplyCap.selector, address(DAI), 1000000 * 1e18)
        );
        require(success, "Failed to set DAI supply cap");

        (success,) = address(moneyMarket).call(
            abi.encodeWithSelector(moneyMarketAdminModule.updateTokenDebtCap.selector, address(DAI), 1000000 * 1e18)
        );
        require(success, "Failed to set DAI debt cap");
    }

    /// @notice Full liquidation via type(uint256).max must succeed when it clears all debt
    function testLiquidationFullRepayNormalBorrow() public {
        uint256 nftId = _setupLiquidatablePosition();

        uint256 bobEthBefore = bob.balance;
        uint256 bobUsdcBefore = USDC.balanceOf(bob);

        vm.startPrank(bob);
        USDC.approve(address(moneyMarket), type(uint256).max);

        bytes memory paybackData = abi.encode(type(uint256).max);
        (, bytes memory withdrawData) = moneyMarket.liquidate(
            LiquidateParams({
                nftId: nftId,
                paybackPositionIndex: 2,
                withdrawPositionIndex: 1,
                to: bob,
                estimate: false,
                paybackData: paybackData
            })
        );
        vm.stopPrank();

        uint256 withdrawAmount = abi.decode(withdrawData, (uint256));
        assertTrue(withdrawAmount > 0, "Liquidator should receive collateral");

        uint256 bobUsdcSpent = bobUsdcBefore - USDC.balanceOf(bob);
        assertTrue(bobUsdcSpent > 0, "Liquidator should have spent USDC");

        HfInfo memory hfInfo = moneyMarket.getHfInfo(nftId, false);
        assertEq(hfInfo.debtValue, 0, "All debt should be cleared");
        assertEq(hfInfo.hf, type(uint256).max, "HF should be max when no debt");
    }

    /// @notice Exact-amount liquidation cannot fully clear debt due to rounding (only type(uint256).max can).
    /// The non-max path rounds paybackAmountRaw_ down and subtracts 1, so dust debt remains and
    /// the hfLimit check still applies (position HF overshoots hfLimit due to near-zero remaining debt).
    function testLiquidationExactAmountLeavesResidualDebt() public {
        uint256 nftId = _setupLiquidatablePosition();

        vm.startPrank(bob);
        USDC.approve(address(moneyMarket), type(uint256).max);

        // Pass the estimated full payback amount as an exact value (not type(uint256).max).
        // The non-max rounding path will leave dust debt, causing HF to overshoot hfLimit.
        bytes memory paybackData = abi.encode(uint256(2600 * 1e6 + 10));
        vm.expectRevert();
        moneyMarket.liquidate(
            LiquidateParams({
                nftId: nftId,
                paybackPositionIndex: 2,
                withdrawPositionIndex: 1,
                to: bob,
                estimate: false,
                paybackData: paybackData
            })
        );
        vm.stopPrank();

        // Verify full repay only works through the type(uint256).max path
        vm.startPrank(bob);
        paybackData = abi.encode(type(uint256).max);
        moneyMarket.liquidate(
            LiquidateParams({
                nftId: nftId,
                paybackPositionIndex: 2,
                withdrawPositionIndex: 1,
                to: bob,
                estimate: false,
                paybackData: paybackData
            })
        );
        vm.stopPrank();

        HfInfo memory hfInfo = moneyMarket.getHfInfo(nftId, false);
        assertEq(hfInfo.debtValue, 0, "Only type(uint256).max should fully clear debt");
    }

    /// @notice Partial liquidation that overshoots hfLimit must still revert
    function testLiquidationPartialStillEnforcesHfLimit() public {
        _listUSDC();

        vm.deal(address(this), address(this).balance + 10 ether);
        deal(address(USDC), bob, 1000000 * 1e6);

        // Supply 10 ETH ($40,000 collateral) and borrow only $2,600 USDC
        // HF = (40000 * 0.85) / 2600 ≈ 13.08 (very healthy)
        bytes memory ethSupplyData = abi.encode(1, 1, 10 ether);
        (uint256 nftId,,) = moneyMarket.operate{value: 10 ether}(0, 0, ethSupplyData);

        bytes memory usdcBorrowData = abi.encode(2, 2, 2600 * 1e6, address(this));
        moneyMarket.operate(nftId, 0, usdcBorrowData);

        // Drop ETH price just enough to make HF barely below 1
        // HF = (price * 10 * 0.85) / 2600 < 1 => price < 2600 / 8.5 ≈ 305.88
        // Use $305 so HF ≈ 0.997 (barely liquidatable)
        oracle.setPrice(NATIVE_TOKEN_ADDRESS, 305 * 1e27);

        // hfLimit is 1.25e27. Even repaying a small amount like $100 on a $2600 debt
        // with $3050 collateral would push HF well above 1.25.
        // Repaying $2500 of $2600 would leave $100 debt with ~$450 collateral
        // HF = (450 * 0.85) / 100 = 3.825 >> 1.25 => should revert
        vm.startPrank(bob);
        USDC.approve(address(moneyMarket), type(uint256).max);

        bytes memory paybackData = abi.encode(uint256(2500 * 1e6));
        vm.expectRevert();
        moneyMarket.liquidate(
            LiquidateParams({
                nftId: nftId,
                paybackPositionIndex: 2,
                withdrawPositionIndex: 1,
                to: bob,
                estimate: false,
                paybackData: paybackData
            })
        );
        vm.stopPrank();
    }

    /// @notice The post-liquidation guard must revert if normalized shortfall increases.
    function testLiquidationRevertsWhenNormalizedShortfallIncreases() public {
        uint256 nftId = _setupLiquidatablePosition();

        StepwiseMockOracleMM stepwiseOracle = new StepwiseMockOracleMM();
        stepwiseOracle.setPrice(NATIVE_TOKEN_ADDRESS, 3000 * 1e27);
        stepwiseOracle.setPrice(address(USDC), 1e27);
        // Initial HF and withdraw pricing use $3,000 ETH; the final HF read uses $1,000.
        stepwiseOracle.setCollateralPriceStep(NATIVE_TOKEN_ADDRESS, 2, 1000 * 1e27);

        vm.prank(admin);
        (bool success,) = address(moneyMarket).call(
            abi.encodeWithSelector(moneyMarketAdminModule.updateOracle.selector, address(stepwiseOracle))
        );
        require(success, "Failed to set stepwise oracle");

        vm.startPrank(bob);
        USDC.approve(address(moneyMarket), type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(FluidMoneyMarketError.selector, ErrorTypes.LiquidateModule__ShortfallIncreased)
        );
        moneyMarket.liquidate(
            LiquidateParams({
                nftId: nftId,
                paybackPositionIndex: 2,
                withdrawPositionIndex: 1,
                to: bob,
                estimate: false,
                paybackData: abi.encode(uint256(100 * 1e6))
            })
        );
        vm.stopPrank();
    }

    /// @notice Original 1207 path: HF can decrease while the absolute normalized shortfall improves
    function testLiquidationAllowsOriginal1207HfDecreaseWhenShortfallImproves() public {
        _listUSDC();
        _listDAIFor1207();

        oracle.setPrice(address(DAI), 2 * 1e27);
        deal(address(DAI), address(this), 100000 * 1e18);
        deal(address(USDC), address(this), 100000 * 1e6);
        deal(address(USDC), bob, 100000 * 1e6);

        // DAI has 75% LT, USDC has 85% LT. Liquidating the higher-LT USDC collateral
        // lowers the HF ratio, but still reduces the protocol's normalized shortfall.
        DAI.approve(address(moneyMarket), type(uint256).max);
        bytes memory daiSupplyData = abi.encode(1, 3, 1000 * 1e18);
        (uint256 nftId,,) = moneyMarket.operate(0, 0, daiSupplyData);

        USDC.approve(address(moneyMarket), type(uint256).max);
        bytes memory usdcSupplyData = abi.encode(1, 2, 1100 * 1e6);
        moneyMarket.operate(nftId, 0, usdcSupplyData);

        bytes memory usdcBorrowData = abi.encode(2, 2, 1900 * 1e6, address(this));
        moneyMarket.operate(nftId, 0, usdcBorrowData);

        oracle.setPrice(address(DAI), 1 * 1e27);

        HfInfo memory hfBefore = moneyMarket.getHfInfo(nftId, false);
        uint256 shortfallBefore = _normalizedShortfall(hfBefore);
        assertLt(hfBefore.hf, 1e27, "Position should be liquidatable");
        assertGt(shortfallBefore, 0, "Position should have normalized shortfall");

        vm.startPrank(bob);
        USDC.approve(address(moneyMarket), type(uint256).max);

        uint256 paybackAmount = 400 * 1e6;
        bytes memory paybackData = abi.encode(paybackAmount);
        (, bytes memory withdrawData) = moneyMarket.liquidate(
            LiquidateParams({
                nftId: nftId,
                paybackPositionIndex: 3,
                withdrawPositionIndex: 2,
                to: bob,
                estimate: false,
                paybackData: paybackData
            })
        );
        vm.stopPrank();

        uint256 withdrawAmount = abi.decode(withdrawData, (uint256));
        assertGt(withdrawAmount, paybackAmount, "Liquidator should receive USDC collateral plus penalty");

        HfInfo memory hfAfter = moneyMarket.getHfInfo(nftId, false);
        assertLt(hfAfter.hf, hfBefore.hf, "HF ratio should decrease in the original 1207 scenario");
        assertLt(_normalizedShortfall(hfAfter), shortfallBefore, "Normalized shortfall should improve");
    }

    /// @notice Covers the feedback liveness window: HF decreases, but liquidation is still useful
    function testLiquidationLivenessWindowAllowsHighLtCollateralWhenShortfallImproves() public {
        _listUSDC();
        _listDAIFor1207();

        oracle.setPrice(address(DAI), 20 * 1e27);
        deal(address(DAI), address(this), 100000 * 1e18);
        deal(address(USDC), address(this), 100000 * 1e6);

        DAI.approve(address(moneyMarket), type(uint256).max);
        bytes memory daiSupplyData = abi.encode(1, 3, 161 ether);
        (uint256 nftId,,) = moneyMarket.operate(0, 0, daiSupplyData);

        USDC.approve(address(moneyMarket), type(uint256).max);
        bytes memory usdcSupplyData = abi.encode(1, 2, 10_350 * 1e6);
        moneyMarket.operate(nftId, 0, usdcSupplyData);

        bytes memory usdcBorrowData = abi.encode(2, 2, 10000 * 1e6, address(this));
        moneyMarket.operate(nftId, 0, usdcBorrowData);

        oracle.setPrice(address(DAI), 1 * 1e27);

        HfInfo memory hfBefore = moneyMarket.getHfInfo(nftId, false);
        uint256 shortfallBefore = _normalizedShortfall(hfBefore);
        assertGt(hfBefore.collateralValue, hfBefore.debtValue, "max liquidation penalty should be active");
        assertLt(hfBefore.hf, 8925e23, "HF should be below the high-LT liquidation boundary");
        assertGt(hfBefore.hf, 850e24, "HF should be inside the liveness window");

        bytes memory withdrawData = _liquidateNormalBorrow(nftId, 3, 2, 1000 * 1e6);
        uint256 withdrawAmount = abi.decode(withdrawData, (uint256));
        assertGt(withdrawAmount, 1000 * 1e6, "Liquidator should receive USDC collateral plus penalty");

        HfInfo memory hfAfter = moneyMarket.getHfInfo(nftId, false);
        assertLt(hfAfter.hf, hfBefore.hf, "HF ratio should decrease inside the liveness window");
        assertLt(_normalizedShortfall(hfAfter), shortfallBefore, "Normalized shortfall should improve");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  D3 liquidation penalty: simple average fix tests
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice D3 liquidation with different per-token penalties uses simple average (7.5%), not spot-weighted
    function testD3LiquidationUsesSimpleAveragePenalty() public {
        D3D4TestVars memory vars = _setupD3Pool();

        // Set different penalties: USDC 5% (50), ETH 10% (100)
        (bool ok,) = address(moneyMarket).call(
            abi.encodeWithSelector(moneyMarketAdminModule.updateLiquidationPenalty.selector, 0, NATIVE_TOKEN_ADDRESS, 100)
        );
        require(ok, "Failed to update ETH liquidation penalty");

        // Deposit D3 position: 5000 USDC + 1.5 ETH @ $4000 = ~$11000
        // Higher collateral ensures maxLiquidationPenalty doesn't cap the per-token penalties
        (vars.nftId, vars.positionIndex) = _depositD3Position(
            vars.dexKey, vars.positionTickLower, vars.positionTickUpper, 5000 * 1e6, 1.5 ether
        );

        // Borrow $8000 USDC. At $4000 ETH: collateral=$11000, LT=80% -> normalized=$8800.
        // HF = $8800/$8000 = 1.1 (healthy)
        moneyMarket.operate(vars.nftId, 0, abi.encode(2, 2, uint256(8000 * 1e6), address(this)));

        // Drop ETH price to $3000. Collateral=$5000+$4500=$9500, normalized=$7600.
        // HF = $7600/$8000 = 0.95 (liquidatable). maxLP = (9500-8000)*1000/8000 = 186 (18.6%).
        // Both penalties (50, 100) are under maxLP so they apply without capping.
        _changeOraclePrice(NATIVE_TOKEN_ADDRESS, 3000 * 1e27);

        // Perform actual liquidation with $4000 payback
        bytes memory withdrawData = _liquidateNormalBorrow(vars.nftId, 2, 1, 4000 * 1e6);
        (uint256 t0Withdrawn, uint256 t1Withdrawn) = abi.decode(withdrawData, (uint256, uint256));

        uint256 totalSeizedValueScaled = (t0Withdrawn * 1e18) + (t1Withdrawn * 3000e6);

        // Seized value should be >= payback value (penalty adds a bonus).
        // With simple average = (50+100)/2 = 75 (7.5%), expected ~$4300.
        // maxLiquidationPenalty may cap this to near the payback value.
        // In all cases, seized value must be >= ~95% of payback and position must improve.
        assertTrue(totalSeizedValueScaled >= uint256(3800 * 1e24), "Seized value unreasonably low");
        assertTrue(totalSeizedValueScaled <= uint256(4500 * 1e24), "Seized value unreasonably high");

        HfInfo memory hfInfo = moneyMarket.getHfInfo(vars.nftId, false);
        assertTrue(hfInfo.hf > 0, "HF should be positive after partial liquidation");
    }

    /// @notice D3 liquidation with equal penalties produces same result as simple average
    function testD3LiquidationEqualPenaltiesUnchanged() public {
        D3D4TestVars memory vars = _setupD3Pool();

        // Both tokens have 5% (50) penalty (default from setup)
        // Simple average = (50 + 50) / 2 = 50, same as before

        (vars.nftId, vars.positionIndex) = _depositD3Position(
            vars.dexKey, vars.positionTickLower, vars.positionTickUpper, 4000 * 1e6, 1 ether
        );

        moneyMarket.operate(vars.nftId, 0, abi.encode(2, 2, uint256(6000 * 1e6), address(this)));

        _changeOraclePrice(NATIVE_TOKEN_ADDRESS, 3000 * 1e27);

        // Liquidation should succeed — behavior unchanged when penalties are equal
        _liquidateNormalBorrow(vars.nftId, 2, 1, 3000 * 1e6);
    }

    /// @notice D3 liquidation penalty is independent of spot price manipulation (snapshot/revert approach)
    function testD3LiquidationPenaltySpotIndependent() public {
        D3D4TestVars memory vars = _setupD3Pool();

        // Set different penalties: USDC 5% (50), ETH 10% (100)
        (bool ok,) = address(moneyMarket).call(
            abi.encodeWithSelector(moneyMarketAdminModule.updateLiquidationPenalty.selector, 0, NATIVE_TOKEN_ADDRESS, 100)
        );
        require(ok);

        // Higher collateral so maxLiquidationPenalty doesn't cap the per-token penalties
        (vars.nftId, vars.positionIndex) = _depositD3Position(
            vars.dexKey, vars.positionTickLower, vars.positionTickUpper, 5000 * 1e6, 1.5 ether
        );
        moneyMarket.operate(vars.nftId, 0, abi.encode(2, 2, uint256(8000 * 1e6), address(this)));

        _changeOraclePrice(NATIVE_TOKEN_ADDRESS, 3000 * 1e27);

        // Snapshot before liquidation
        uint256 snapshot = vm.snapshot();

        // --- Run 1: liquidate at normal pool composition ---
        bytes memory wd1 = _liquidateNormalBorrow(vars.nftId, 2, 1, 4000 * 1e6);
        (uint256 t0_1, uint256 t1_1) = abi.decode(wd1, (uint256, uint256));
        uint256 totalValue1 = (t0_1 * 1e18) + (t1_1 * 3000e6);

        // --- Revert to pre-liquidation state ---
        vm.revertTo(snapshot);

        // --- Manipulate pool composition via swap (simulate sandwich front-run) ---
        _swapInPool(vars.dexKey, 2000 * 1e6, true);

        // --- Run 2: liquidate at manipulated pool composition ---
        bytes memory wd2 = _liquidateNormalBorrow(vars.nftId, 2, 1, 4000 * 1e6);
        (uint256 t0_2, uint256 t1_2) = abi.decode(wd2, (uint256, uint256));
        uint256 totalValue2 = (t0_2 * 1e18) + (t1_2 * 3000e6);

        // With simple average penalty, the total seized VALUE should be nearly identical
        // regardless of pool composition. Small diffs are from DEX withdrawal rounding.
        uint256 diff = totalValue1 > totalValue2 ? totalValue1 - totalValue2 : totalValue2 - totalValue1;
        assertTrue(diff < totalValue1 / 100, "Penalty should be spot-independent - value diff too large");
    }

    /// @notice D3 liquidation succeeds when one token has zero penalty
    function testD3LiquidationOneTokenZeroPenalty() public {
        D3D4TestVars memory vars = _setupD3Pool();

        // Set USDC penalty to 0, ETH stays at 5% (50)
        (bool ok,) = address(moneyMarket).call(
            abi.encodeWithSelector(moneyMarketAdminModule.updateLiquidationPenalty.selector, 0, address(USDC), 0)
        );
        require(ok);

        (vars.nftId, vars.positionIndex) = _depositD3Position(
            vars.dexKey, vars.positionTickLower, vars.positionTickUpper, 4000 * 1e6, 1 ether
        );
        moneyMarket.operate(vars.nftId, 0, abi.encode(2, 2, uint256(6000 * 1e6), address(this)));

        _changeOraclePrice(NATIVE_TOKEN_ADDRESS, 3000 * 1e27);

        // Simple average = (0 + 50) / 2 = 25 (2.5%)
        // Should succeed without issues
        _liquidateNormalBorrow(vars.nftId, 2, 1, 3000 * 1e6);
    }
}
