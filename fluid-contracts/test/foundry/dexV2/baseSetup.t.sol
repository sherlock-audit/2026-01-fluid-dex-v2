//SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { LiquidityAmounts as LA } from "lib/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import { TickMath as TM } from "lib/v3-core/contracts/libraries/TickMath.sol";
import { DexV2BaseSlotsLink } from "../../../contracts/libraries/dexV2BaseSlotsLink.sol";
import { LiquidityBaseTest } from "../liquidity/liquidityBaseTest.t.sol";
import { FluidDexV2 } from "../../../contracts/protocols/dexV2/base/core/main.sol";
import { FluidDexV2Proxy } from "../../../contracts/protocols/dexV2/base/proxy.sol";
import { FullMath as FM } from "lib/v3-core/contracts/libraries/FullMath.sol";

// D3 module imports
import { FluidDexV2D3AdminModule } from "../../../contracts/protocols/dexV2/dexTypes/d3/admin/main.sol";
import { FluidDexV2D3ControllerModule } from "../../../contracts/protocols/dexV2/dexTypes/d3/core/controllerModule.sol";
import { FluidDexV2D3SwapModule } from "../../../contracts/protocols/dexV2/dexTypes/d3/core/swapModule.sol";
import { FluidDexV2D3UserModule } from "../../../contracts/protocols/dexV2/dexTypes/d3/core/userModule.sol";

// D4 module imports
import { FluidDexV2D4AdminModule } from "../../../contracts/protocols/dexV2/dexTypes/d4/admin/main.sol";
import { FluidDexV2D4ControllerModule } from "../../../contracts/protocols/dexV2/dexTypes/d4/core/controllerModule.sol";
import { FluidDexV2D4SwapModule } from "../../../contracts/protocols/dexV2/dexTypes/d4/core/swapModule.sol";
import { FluidDexV2D4UserModule } from "../../../contracts/protocols/dexV2/dexTypes/d4/core/userModule.sol";


abstract contract DexV2BaseSetup is LiquidityBaseTest {
    using SafeERC20 for IERC20;

    // bytes32(uint256(keccak256("FLUID_DEX_V2_BASE")) - 1)
    bytes32 constant BASE_SLOT = 0x7336ba09d90d0a79967e434a915d72dfb7e2f59fd8575a830210387fd4c1ab7c;

    // bytes32(uint256(keccak256("FLUID_DEX_V2_PENDING_SUPPLY")) - 1)
    bytes32 constant PENDING_SUPPLY_SLOT = 0x1f9fe0a780efbf168c8fd810da059a7db6663cde8eba217dd821a7835cf20a90;

    // bytes32(uint256(keccak256("FLUID_DEX_V2_PENDING_BORROW")) - 1)
    bytes32 constant PENDING_BORROW_SLOT = 0xc635a7f3d9cd0b7d4d1f19812847a3c1f84d9f5e2122dad3be5b18f057c49939;

    uint256 internal constant X102 = 0x3FFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant MAX_LIQUIDITY = X102;
    
    int24 internal constant MIN_TICK = -524287; // Not -887272
    int24 internal constant MAX_TICK = -MIN_TICK;

    FluidDexV2 public dexV2;

    // D3 module constants and contracts
    uint256 internal constant DEX_TYPE_D3 = 3;
    uint256 internal constant ADMIN_MODULE_ID_D3 = 1;
    FluidDexV2D3AdminModule public dexV2D3AdminModule;
    FluidDexV2D3ControllerModule public dexV2D3ControllerModule;
    FluidDexV2D3SwapModule public dexV2D3SwapModule;
    FluidDexV2D3UserModule public dexV2D3UserModule;

    // D4 module constants and contracts
    uint256 internal constant DEX_TYPE_D4 = 4;
    uint256 internal constant ADMIN_MODULE_ID_D4 = 1;
    FluidDexV2D4AdminModule public dexV2D4AdminModule;
    FluidDexV2D4ControllerModule public dexV2D4ControllerModule;
    FluidDexV2D4SwapModule public dexV2D4SwapModule;
    FluidDexV2D4UserModule public dexV2D4UserModule;

    function startOperationCallback(bytes calldata data_) external returns (bytes memory) {
        (bool success, bytes memory result) = address(this).call(data_);
        require(success, "Callback call failed");
        return result;
    }

    function dexCallback(address token_, address to_, uint256 amount_) external virtual {
        IERC20(token_).safeTransfer(to_, amount_);
    }

    function setUp() public virtual override {
        super.setUp();

        // Set up allowances for mockProtocol (required for protocol interaction)
        _setUserAllowancesDefault(address(liquidity), admin, address(USDT), address(mockProtocol));
        _setUserAllowancesDefault(address(liquidity), admin, address(USDC), address(mockProtocol));
        _setUserAllowancesDefault(address(liquidity), admin, address(DAI), address(mockProtocol));
        _setUserAllowancesDefault(address(liquidity), admin, address(SUSDE), address(mockProtocol));
        _setUserAllowancesDefault(address(liquidity), admin, NATIVE_TOKEN_ADDRESS, address(mockProtocol));

        _supply(address(liquidity), mockProtocol, address(USDT), alice, 1e6 * 1e6);
        _supply(address(liquidity), mockProtocol, address(USDC), alice, 1e6 * 1e6);
        _supply(address(liquidity), mockProtocol, address(DAI), alice, 1e6 * 1e18);
        _supply(address(liquidity), mockProtocol, address(SUSDE), alice, 1e6 * 1e18);
        _supplyNative(address(liquidity), mockProtocol, alice, 1e6 * 1e18);

        _updateRevenueCollector(address(liquidity), admin, address(this));

        // Deploy DEX V2 with UUPS proxy
        // 1. Deploy implementation
        FluidDexV2 dexV2Implementation = new FluidDexV2(address(liquidity));
        
        // 2. Deploy proxy with empty initialization data (no initialize function needed)
        FluidDexV2Proxy dexV2Proxy = new FluidDexV2Proxy(address(dexV2Implementation), "");
        
        // 3. Wrap proxy address as FluidDexV2 for interactions
        dexV2 = FluidDexV2(payable(address(dexV2Proxy)));

        _setUserAllowancesDefault(address(liquidity), admin, address(USDT), address(dexV2));
        _setUserAllowancesDefault(address(liquidity), admin, address(USDC), address(dexV2));
        _setUserAllowancesDefault(address(liquidity), admin, address(DAI), address(dexV2));
        _setUserAllowancesDefault(address(liquidity), admin, address(SUSDE), address(dexV2));
        _setUserAllowancesDefault(address(liquidity), admin, NATIVE_TOKEN_ADDRESS, address(dexV2));

        vm.prank(admin);
        dexV2.updateAuth(address(this), true);

        // Deploy D3 modules in consistent order (matches hardcoded addresses in variables.sol)
        dexV2D3SwapModule = new FluidDexV2D3SwapModule(address(liquidity));
        dexV2D3UserModule = new FluidDexV2D3UserModule(address(liquidity));
        dexV2D3ControllerModule = new FluidDexV2D3ControllerModule(address(liquidity));
        dexV2D3AdminModule = new FluidDexV2D3AdminModule(address(liquidity));

        vm.prank(admin);
        dexV2.updateDexTypeToAdminImplementation(DEX_TYPE_D3, ADMIN_MODULE_ID_D3, address(dexV2D3AdminModule));

        // Deploy D4 modules in consistent order (matches hardcoded addresses in variables.sol)
        dexV2D4SwapModule = new FluidDexV2D4SwapModule(address(liquidity));
        dexV2D4UserModule = new FluidDexV2D4UserModule(address(liquidity));
        dexV2D4ControllerModule = new FluidDexV2D4ControllerModule(address(liquidity));
        dexV2D4AdminModule = new FluidDexV2D4AdminModule(address(liquidity));

        vm.prank(admin);
        dexV2.updateDexTypeToAdminImplementation(DEX_TYPE_D4, ADMIN_MODULE_ID_D4, address(dexV2D4AdminModule));
    }

    function _toString(uint256 x) internal pure returns (string memory) {
        return Strings.toString(x);
    }

    function _toString(int256 x) internal pure returns (string memory) {
        if (x == 0) {
            return "0";
        }
        bool neg = x < 0;
        uint256 ux = neg ? uint256(-x) : uint256(x);
        string memory s = Strings.toString(ux);
        return neg ? string.concat("-", s) : s;
    }

    function _getDexTypeToAdminImplementation(uint256 dexType_, uint256 moduleId_) internal view returns (address) {
        return
            address(
                uint160(
                    dexV2.readFromStorage(
                        DexV2BaseSlotsLink.calculateTripleMappingStorageSlot(
                            DexV2BaseSlotsLink.DEX_V2_DEX_TYPE_TO_ADMIN_IMPLEMENTATION_MAPPING_SLOT,
                            BASE_SLOT,
                            bytes32(dexType_),
                            bytes32(moduleId_)
                        )
                    )
                )
            );
    }

    function _getPendingSupply(address user_, address token_) internal view returns (int256) {
        return int256(dexV2.readFromTransientStorage(keccak256(abi.encode(PENDING_SUPPLY_SLOT, user_, token_))));
    }

    function _getPendingBorrow(address user_, address token_) internal view returns (int256) {
        return int256(dexV2.readFromTransientStorage(keccak256(abi.encode(PENDING_BORROW_SLOT, user_, token_))));
    }

    function _getMaxLiquidityPerTick(uint24 tickSpacing_) internal pure returns (uint256) {
        int24 minTick = MIN_TICK / int24(tickSpacing_);
        if (MIN_TICK % int24(tickSpacing_) != 0) minTick--;

        int24 maxTick = MAX_TICK / int24(tickSpacing_);
        uint24 numTicks = uint24(int24(maxTick - minTick) + 1);

        return MAX_LIQUIDITY / numTicks;
    }
}
