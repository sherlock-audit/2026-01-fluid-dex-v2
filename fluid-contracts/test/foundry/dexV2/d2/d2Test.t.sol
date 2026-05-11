// //SPDX-License-Identifier: MIT
// pragma solidity ^0.8.34;

// // TODO: @Vaibhav Add more tests

// import "forge-std/Test.sol";
// import "forge-std/console2.sol";

// import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import { DexV2BaseSetup } from "../baseSetup.t.sol";
// import { FluidDexV2D2 } from "../../../../contracts/protocols/dexV2/dexTypes/d2/core/main.sol";
// import { FluidDexV2D2Admin } from "../../../../contracts/protocols/dexV2/dexTypes/d2/admin/main.sol";
// import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// contract DexV2D2Test is DexV2BaseSetup {
//     using SafeERC20 for IERC20;

//     FluidDexV2D2 public dexV2D2Implementation;
//     FluidDexV2D2Admin public dexV2D2AdminImplementation;

//     function setUp() public virtual override {
//         super.setUp();

//         // Fund address(this) with 1000 USDC and 1000 USDT
//         deal(address(USDT), address(this), 1000 * 1e6);
//         deal(address(USDC), address(this), 1000 * 1e6);

//         dexV2D2Implementation = new FluidDexV2D2(address(mockProtocol), address(this)); // TODO: add address of deployer contract
//         dexV2.setDexTypeToImplementation(2, address(dexV2D2Implementation));

//         dexV2D2AdminImplementation = new FluidDexV2D2Admin(address(mockProtocol), address(this)); // TODO: add address of deployer contract
//         dexV2.setDexTypeToAdminImplementation(2, address(dexV2D2AdminImplementation));
//     }

//     function testSetUp() public {
//         assertNotEq(address(dexV2), address(0));

//         assertNotEq(address(dexV2D2Implementation), address(0));
//         assertEq(dexV2.getDexTypeToImplementation(2), address(dexV2D2Implementation));

//         assertNotEq(address(dexV2D2AdminImplementation), address(0));
//         assertEq(dexV2.getDexTypeToAdminImplementation(2), address(dexV2D2AdminImplementation));
//     }
// }
