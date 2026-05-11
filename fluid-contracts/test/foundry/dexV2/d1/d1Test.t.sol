// //SPDX-License-Identifier: MIT
// pragma solidity ^0.8.34;

// // TODO: @Vaibhav Add more tests

// import "forge-std/Test.sol";
// import "forge-std/console2.sol";

// import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import { DexV2BaseSetup } from "../baseSetup.t.sol";
// import { FluidDexV2D1 } from "../../../../contracts/protocols/dexV2/dexTypes/d1/core/main.sol";
// import { FluidDexV2D1Admin } from "../../../../contracts/protocols/dexV2/dexTypes/d1/admin/main.sol";
// import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// contract DexV2D1Test is DexV2BaseSetup {
//     using SafeERC20 for IERC20;

//     FluidDexV2D1 public dexV2D1Implementation;
//     FluidDexV2D1Admin public dexV2D1AdminImplementation;

//     function setUp() public virtual override {
//         super.setUp();

//         // Fund address(this) with 1000 USDC and 1000 USDT
//         deal(address(USDT), address(this), 1000 * 1e6);
//         deal(address(USDC), address(this), 1000 * 1e6);

//         dexV2D1Implementation = new FluidDexV2D1(address(mockProtocol), address(this)); // TODO: add address of deployer contract
//         dexV2.setDexTypeToImplementation(1, address(dexV2D1Implementation));

//         dexV2D1AdminImplementation = new FluidDexV2D1Admin(address(mockProtocol), address(this)); // TODO: add address of deployer contract
//         dexV2.setDexTypeToAdminImplementation(1, address(dexV2D1AdminImplementation));
//     }

//     function testSetUp() public {
//         assertNotEq(address(dexV2), address(0));

//         assertNotEq(address(dexV2D1Implementation), address(0));
//         assertEq(dexV2.getDexTypeToImplementation(1), address(dexV2D1Implementation));

//         assertNotEq(address(dexV2D1AdminImplementation), address(0));
//         assertEq(dexV2.getDexTypeToAdminImplementation(1), address(dexV2D1AdminImplementation));
//     }
// }
