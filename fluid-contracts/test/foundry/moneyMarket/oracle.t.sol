//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import { MoneyMarketTestBaseSetup } from "./main.t.sol";
import { FluidMoneyMarketOracle } from "../../../contracts/protocols/moneyMarket/oracle/main.sol";
import { IMMOracle } from "../../../contracts/protocols/moneyMarket/oracle/iMMOracle.sol";
import { ErrorTypes as MMErrorTypes } from "../../../contracts/protocols/moneyMarket/oracle/errorTypes.sol";
import { Error } from "../../../contracts/protocols/moneyMarket/oracle/error.sol";
import { Structs } from "../../../contracts/protocols/moneyMarket/oracle/structs.sol";

interface IChainlinkAggregatorV3 {
    /// @notice represents the number of decimals the aggregator responses represent.
    function decimals() external view returns (uint8);

    function description() external view returns (string memory);

    function version() external view returns (uint256);

    function getRoundData(uint80 _roundId) external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

contract MockChainlinkFeed is IChainlinkAggregatorV3 {
    IChainlinkAggregatorV3 chainlinkFeed;
    int256 exchangeRate;

    constructor(IChainlinkAggregatorV3 originalChainLinkFeed) {
        chainlinkFeed = originalChainLinkFeed;
        (, int256 exchangeRate_, , , ) = chainlinkFeed.latestRoundData();
        exchangeRate = exchangeRate_;
    }

    function setExchangeRate(int256 newExchangeRate_) external {
        exchangeRate = newExchangeRate_;
    }

    function decimals() external view returns (uint8) {
        return chainlinkFeed.decimals();
    }

    function description() external view returns (string memory) {
        return chainlinkFeed.description();
    }

    function version() external view returns (uint256) {
        return chainlinkFeed.version();
    }

    function getRoundData(uint80 _roundId) external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
        return chainlinkFeed.getRoundData(_roundId);
    }

    function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
        (uint80 roundIdOrg, , uint256 startedAtOrg, uint256 updatedAtOrg, uint80 answeredInRoundOrg) = chainlinkFeed.latestRoundData();
        return (roundIdOrg, exchangeRate, startedAtOrg, updatedAtOrg, answeredInRoundOrg);
    }
}

contract FluidMoneyMarketOracleTest is MoneyMarketTestBaseSetup, Structs {
    FluidMoneyMarketOracle public mmOracle;
    MockChainlinkFeed public clOracle; // Chainlink oracle mock

    address constant DUMMY_TOKEN = address(0x123);

    // USDC / ETH feed
    IChainlinkAggregatorV3 CHAINLINK_FEED = IChainlinkAggregatorV3(0x986b5E1e1755e3C2440e960477f25201B0a8bbD4);

    event OracleConfigSet(
        address indexed token,
        uint256 indexed eMode,
        uint8 indexed isOperate,
        uint8 isCollateral,
        uint8 sourceType1,
        address source1,
        int8 multiplier1,
        uint8 sourceType2,
        address source2,
        int8 multiplier2,
        uint8 sourceType3,
        address source3,
        int8 multiplier3
    );

    function setUp() public virtual override {
        super.setUp();

        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(21148750);

        mmOracle = new FluidMoneyMarketOracle(address(liquidity), address(moneyMarket));
        // Deploy a mock Chainlink feed with a dummy (address(0)) base aggregator for isolation;
        // Its underlying aggregator never called because mock overrides latestRoundData()
        clOracle = new MockChainlinkFeed(IChainlinkAggregatorV3(address(CHAINLINK_FEED)));
    }

    // --- Access Control Tests ---

    function testAccessControl_onlyGovernanceOrInitialMultisigAllowed() public {
        // Use Type 2 (Chainlink) and ensure it's a valid feed for the check
        SetSourceConfig memory source = SetSourceConfig({ sourceType: 2, source: address(clOracle), multiplier: 1 });

        // Non-gov fails
        vm.expectRevert(abi.encodeWithSelector(Error.FluidMMOracleError.selector, MMErrorTypes.MMOracle__Unauthorized));
        mmOracle.setConfigSingle(address(USDC), 0, 1, 1, source, _emptyCfg(), _emptyCfg());

        // Gov works
        vm.prank(admin);
        mmOracle.setConfigSingle(address(USDC), 0, 1, 1, source, _emptyCfg(), _emptyCfg());

        // Governance can MODIFY an existing config
        vm.prank(admin);
        SetSourceConfig memory newSourceCfg = SetSourceConfig({ sourceType: 2, source: address(clOracle), multiplier: 2 }); // change multiplier
        mmOracle.setConfigSingle(address(USDC), 0, 1, 1, newSourceCfg, _emptyCfg(), _emptyCfg());

        // Config written is actually updated (spot check)
        {
            Structs.ConfiguredTokenOracle[] memory infos = mmOracle.getConfiguredTokenOracles(address(USDC));
            require(infos.length > 0, "No configs found for USDC");
            // Since we only set config for eMode=0, isOperate=1, isCollateral=1, find it in the array
            Structs.ConfiguredTokenOracle memory info;
            bool found = false;
            for (uint256 i = 0; i < infos.length; ++i) {
                if (infos[i].eMode == 0 && infos[i].isOperate == true && infos[i].isCollateral == true) {
                    info = infos[i];
                    found = true;
                    break;
                }
            }
            require(found, "Config not found for expected mode");
            assertEq(info.sourceType1, newSourceCfg.sourceType, "Governance should be able to modify sourceType");
            assertEq(info.source1, newSourceCfg.source, "Governance should be able to modify source address");
            assertEq(info.multiplier1, newSourceCfg.multiplier, "Governance should be able to modify multiplier");
        }

        // Multisig works for NEW configs
        address multisig = mmOracle.TEAM_MULTISIG();
        SetSourceConfig memory source2 = SetSourceConfig({ sourceType: 2, source: address(clOracle), multiplier: 1 });
        vm.prank(multisig);
        mmOracle.setConfigSingle(address(USDT), 0, 1, 1, source2, _emptyCfg(), _emptyCfg());

        // Multisig modify old config: forbidden
        vm.prank(multisig);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidMMOracleError.selector, MMErrorTypes.MMOracle__Unauthorized));
        mmOracle.setConfigSingle(address(USDT), 0, 1, 1, source2, _emptyCfg(), _emptyCfg());
    }

    function testAccessControl_setConfigMultiple_onlyGovernanceOrInitialMultisigAllowed() public {
        // Use Type 2 (Chainlink) and ensure it's a valid feed for the check
        SetSourceConfig memory source = SetSourceConfig({ sourceType: 2, source: address(clOracle), multiplier: 1 });

        // Non-gov fails
        vm.expectRevert(abi.encodeWithSelector(Error.FluidMMOracleError.selector, MMErrorTypes.MMOracle__Unauthorized));
        mmOracle.setConfigMultiple(address(USDC), 0, 2, 1, source, _emptyCfg(), _emptyCfg());

        // Gov works
        vm.prank(admin);
        mmOracle.setConfigMultiple(address(USDC), 0, 2, 1, source, _emptyCfg(), _emptyCfg());

        // Governance can MODIFY an existing config using setConfigMultiple
        vm.prank(admin);
        SetSourceConfig memory newSourceCfg = SetSourceConfig({ sourceType: 2, source: address(clOracle), multiplier: 2 });
        mmOracle.setConfigMultiple(address(USDC), 0, 2, 1, newSourceCfg, _emptyCfg(), _emptyCfg());

        // Multisig works for NEW configs
        address multisig = mmOracle.TEAM_MULTISIG();
        SetSourceConfig memory source2 = SetSourceConfig({ sourceType: 2, source: address(clOracle), multiplier: 1 });
        vm.prank(multisig);
        mmOracle.setConfigMultiple(address(USDT), 0, 2, 1, source2, _emptyCfg(), _emptyCfg());

        // Multisig modify old config: forbidden
        vm.prank(multisig);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidMMOracleError.selector, MMErrorTypes.MMOracle__Unauthorized));
        mmOracle.setConfigMultiple(address(USDT), 0, 2, 1, source2, _emptyCfg(), _emptyCfg());
    }

    // --- OracleConfig CRUD ---

    function testOracleConfig_invalidMultiplierReverts() public {
        vm.startPrank(admin);

        // Multiplier > 21 is invalid
        SetSourceConfig memory badCfg = SetSourceConfig({ sourceType: 2, source: address(clOracle), multiplier: 22 });
        vm.expectRevert(abi.encodeWithSelector(Error.FluidMMOracleError.selector, MMErrorTypes.MMOracle__InvalidMultiplier));
        mmOracle.setConfigSingle(DUMMY_TOKEN, 0, 1, 1, badCfg, _emptyCfg(), _emptyCfg());

        // Multiplier < -12 is invalid
        SetSourceConfig memory badCfgNeg = SetSourceConfig({ sourceType: 2, source: address(clOracle), multiplier: -13 });
        vm.expectRevert(abi.encodeWithSelector(Error.FluidMMOracleError.selector, MMErrorTypes.MMOracle__InvalidMultiplier));
        mmOracle.setConfigSingle(DUMMY_TOKEN, 0, 1, 1, badCfgNeg, _emptyCfg(), _emptyCfg());

        // Multiplier == 0 is valid (should not revert), test that value is not changed
        SetSourceConfig memory zeroMult = SetSourceConfig({ sourceType: 2, source: address(clOracle), multiplier: 0 });
        mmOracle.setConfigSingle(DUMMY_TOKEN, 0, 1, 1, zeroMult, _emptyCfg(), _emptyCfg());

        // Set up Chainlink oracle mock to return 1e27 (same as ORACLE_PRECISION)
        clOracle.setExchangeRate(1e27);
        // Call getPrice -- multiplier=0, so no scaling. Should return 1e27 exactly.
        uint expected = 1e27;
        uint actual = mmOracle.getPrice(DUMMY_TOKEN, 0, true, true);
        assertEq(actual, expected, "Multiplier 0 did not result in passthrough as expected (1e27).");

        // Try positive multiplier (multiply by 10)
        SetSourceConfig memory posMult = SetSourceConfig({ sourceType: 2, source: address(clOracle), multiplier: 1 });
        mmOracle.setConfigSingle(DUMMY_TOKEN, 0, 1, 1, posMult, _emptyCfg(), _emptyCfg());
        expected = 1e28;
        actual = mmOracle.getPrice(DUMMY_TOKEN, 0, true, true);
        assertEq(actual, expected, "Positive multiplier not applied correctly (expected 1e28)");

        // Try negative multiplier (divide by 10)
        SetSourceConfig memory negMult = SetSourceConfig({ sourceType: 2, source: address(clOracle), multiplier: -1 });
        mmOracle.setConfigSingle(DUMMY_TOKEN, 0, 1, 1, negMult, _emptyCfg(), _emptyCfg());
        expected = 1e26;
        actual = mmOracle.getPrice(DUMMY_TOKEN, 0, true, true);
        assertEq(actual, expected, "Negative multiplier not applied correctly (expected 1e26)");

        vm.stopPrank();
    }

    function test_setConfigSingle_invalidEmodeShouldRevert() public {
        vm.startPrank(admin);

        // Get total eModes listed from the oracle (readFromStorage mocked for test)
        uint256 totalEmodesListed = 3;
        // Set eMode to a value greater than totalEmodesListed to trigger revert
        uint256 invalidEmode = totalEmodesListed + 1;

        SetSourceConfig memory validCfg = SetSourceConfig({ sourceType: 2, source: address(clOracle), multiplier: 1 });

        // Expect revert for invalid eMode
        vm.expectRevert(abi.encodeWithSelector(Error.FluidMMOracleError.selector, MMErrorTypes.MMOracle__InvalidEMode));
        mmOracle.setConfigSingle(DUMMY_TOKEN, invalidEmode, 1, 1, validCfg, _emptyCfg(), _emptyCfg());

        vm.stopPrank();
    }

    function testOracleConfig_revertOnZeroAddressSource() public {
        SetSourceConfig memory zeroSource = _emptyCfg();
        vm.startPrank(admin);
        // Reverts at _verifySourceConfig because source == address(0)
        vm.expectRevert(abi.encodeWithSelector(Error.FluidMMOracleError.selector, MMErrorTypes.MMOracle__AddressZero));
        mmOracle.setConfigSingle(DUMMY_TOKEN, 0, 1, 1, zeroSource, zeroSource, zeroSource);
        vm.stopPrank();
    }

    function testOracleConfig_setConfigMultiple_andInvalid() public {
        SetSourceConfig memory cfg = SetSourceConfig({ sourceType: 2, source: address(clOracle), multiplier: 1 });
        vm.startPrank(admin);

        // Valid set: both liquidate and operate for collateral (isCollateral = 1)
        mmOracle.setConfigMultiple(address(USDC), 0, 2, 1, cfg, _emptyCfg(), _emptyCfg());

        // Test invalid params (isOperate > 2)
        vm.expectRevert(abi.encodeWithSelector(Error.FluidMMOracleError.selector, MMErrorTypes.MMOracle__InvalidParams));
        mmOracle.setConfigMultiple(address(USDC), 0, 3, 1, cfg, _emptyCfg(), _emptyCfg());

        vm.stopPrank();
    }

    function test_setConfigMultiple_shouldRevertIfBothNot2() public {
        SetSourceConfig memory cfg = SetSourceConfig({ sourceType: 2, source: address(clOracle), multiplier: 1 });
        vm.startPrank(admin);

        // Both isOperate and isCollateral are NOT 2 - only one config at a time allowed
        // isOperate = 1, isCollateral = 1 (neither 2)
        vm.expectRevert(abi.encodeWithSelector(Error.FluidMMOracleError.selector, MMErrorTypes.MMOracle__InvalidParams));
        mmOracle.setConfigMultiple(address(USDC), 0, 1, 1, cfg, _emptyCfg(), _emptyCfg());

        // isOperate = 0, isCollateral = 1 (neither 2)
        vm.expectRevert(abi.encodeWithSelector(Error.FluidMMOracleError.selector, MMErrorTypes.MMOracle__InvalidParams));
        mmOracle.setConfigMultiple(address(USDC), 0, 0, 1, cfg, _emptyCfg(), _emptyCfg());

        // isOperate = 1, isCollateral = 0 (neither 2)
        vm.expectRevert(abi.encodeWithSelector(Error.FluidMMOracleError.selector, MMErrorTypes.MMOracle__InvalidParams));
        mmOracle.setConfigMultiple(address(USDC), 0, 1, 0, cfg, _emptyCfg(), _emptyCfg());

        // isOperate = 0, isCollateral = 0 (neither 2)
        vm.expectRevert(abi.encodeWithSelector(Error.FluidMMOracleError.selector, MMErrorTypes.MMOracle__InvalidParams));
        mmOracle.setConfigMultiple(address(USDC), 0, 0, 0, cfg, _emptyCfg(), _emptyCfg());

        // isOperate > 2 (invalid)
        vm.expectRevert(abi.encodeWithSelector(Error.FluidMMOracleError.selector, MMErrorTypes.MMOracle__InvalidParams));
        mmOracle.setConfigMultiple(address(USDC), 0, 99, 2, cfg, _emptyCfg(), _emptyCfg());

        // isCollateral > 2 (invalid)
        vm.expectRevert(abi.encodeWithSelector(Error.FluidMMOracleError.selector, MMErrorTypes.MMOracle__InvalidParams));
        mmOracle.setConfigMultiple(address(USDC), 0, 2, 88, cfg, _emptyCfg(), _emptyCfg());

        // isOperate > 2, isCollateral > 2 (both invalid)
        vm.expectRevert(abi.encodeWithSelector(Error.FluidMMOracleError.selector, MMErrorTypes.MMOracle__InvalidParams));
        mmOracle.setConfigMultiple(address(USDC), 0, 255, 255, cfg, _emptyCfg(), _emptyCfg());

        vm.stopPrank();
    }

    function testOracleConfig_removeConfig_revertsIfMissing() public {
        vm.startPrank(admin);
        // Contract has: if (!_configExists(...)) revert MMOracle__ConfigDoesNotExist
        vm.expectRevert(abi.encodeWithSelector(Error.FluidMMOracleError.selector, MMErrorTypes.MMOracle__ConfigDoesNotExist));
        mmOracle.removeConfigSingle(address(USDC), 0, 1, 1);
        vm.stopPrank();
    }

    function testOracleConfig_removeConfig_succeedsIfPresent() public {
        SetSourceConfig memory cfg = SetSourceConfig({ sourceType: 2, source: address(clOracle), multiplier: 1 });
        vm.startPrank(admin);

        // Add a config so it exists
        mmOracle.setConfigSingle(address(USDC), 0, 1, 1, cfg, _emptyCfg(), _emptyCfg());

        // Confirm config exists using getConfiguredTokenOracles
        {
            ConfiguredTokenOracle[] memory infos = mmOracle.getConfiguredTokenOracles(address(USDC));
            bool found = false;
            for (uint256 i = 0; i < infos.length; ++i) {
                ConfiguredTokenOracle memory info = infos[i];
                if (
                    info.eMode == 0 &&
                    info.isOperate == true &&
                    info.isCollateral == true &&
                    info.sourceType1 == 2 &&
                    info.source1 == address(clOracle) &&
                    info.multiplier1 == 1 &&
                    info.sourceType2 == 0 &&
                    info.source2 == address(0) &&
                    info.multiplier2 == 0 &&
                    info.sourceType3 == 0 &&
                    info.source3 == address(0) &&
                    info.multiplier3 == 0
                ) {
                    found = true;
                    break;
                }
            }
            assertTrue(found, "Expected config not found in getConfiguredTokenOracles before removal");
        }

        // Remove config (should not revert)
        mmOracle.removeConfigSingle(address(USDC), 0, 1, 1);

        // Confirm the config was removed: config should not be present in getConfiguredTokenOracles
        {
            ConfiguredTokenOracle[] memory infos = mmOracle.getConfiguredTokenOracles(address(USDC));
            bool found = false;
            for (uint256 i = 0; i < infos.length; ++i) {
                ConfiguredTokenOracle memory info = infos[i];
                if (info.eMode == 0 && info.isOperate == true && info.isCollateral == true && info.sourceType1 == 2 && info.source1 == address(clOracle)) {
                    found = true;
                    break;
                }
            }
            assertTrue(!found, "Removed config still found in getConfiguredTokenOracles");
        }

        // Confirm that subsequent attempt reverts (was removed)
        vm.expectRevert(abi.encodeWithSelector(Error.FluidMMOracleError.selector, MMErrorTypes.MMOracle__ConfigDoesNotExist));
        mmOracle.removeConfigSingle(address(USDC), 0, 1, 1);

        vm.stopPrank();
    }

    function test_removeConfig_onlyGovernance() public {
        // Try as non-governance
        SetSourceConfig memory source = SetSourceConfig({ sourceType: 2, source: address(clOracle), multiplier: 1 });
        vm.prank(admin);
        mmOracle.setConfigSingle(address(USDC), 0, 0, 0, source, _emptyCfg(), _emptyCfg());

        address attacker = address(123456);
        // Try to remove as attacker (not governance)
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidMMOracleError.selector, MMErrorTypes.MMOracle__Unauthorized));
        mmOracle.removeConfigSingle(address(USDC), 0, 0, 0);
    }

    function test_removeConfig_invalidParams_isOperateTooHigh() public {
        SetSourceConfig memory source = SetSourceConfig({ sourceType: 2, source: address(clOracle), multiplier: 1 });
        vm.prank(admin);
        mmOracle.setConfigSingle(address(USDC), 0, 0, 0, source, _emptyCfg(), _emptyCfg());

        // isOperate > 1 is invalid
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidMMOracleError.selector, MMErrorTypes.MMOracle__InvalidParams));
        mmOracle.removeConfigSingle(address(USDC), 0, 2, 0);
    }

    function test_removeConfig_invalidParams_isCollateralTooHigh() public {
        SetSourceConfig memory source = SetSourceConfig({ sourceType: 2, source: address(clOracle), multiplier: 1 });
        vm.prank(admin);
        mmOracle.setConfigSingle(address(USDC), 0, 0, 0, source, _emptyCfg(), _emptyCfg());

        // isCollateral > 1 is invalid
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidMMOracleError.selector, MMErrorTypes.MMOracle__InvalidParams));
        mmOracle.removeConfigSingle(address(USDC), 0, 0, 2);
    }

    function test_removeConfig_revertsOnNonExistentConfig() public {
        // Try to remove when config doesn't exist at all (valid params, but entry missing)
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidMMOracleError.selector, MMErrorTypes.MMOracle__ConfigDoesNotExist));
        mmOracle.removeConfigSingle(address(USDC), 99, 0, 0);
    }

    function test_removeConfig_revertsOnZeroAddress() public {
        SetSourceConfig memory source = SetSourceConfig({ sourceType: 2, source: address(clOracle), multiplier: 1 });
        vm.prank(admin);
        mmOracle.setConfigSingle(address(USDC), 0, 0, 0, source, _emptyCfg(), _emptyCfg());

        // Should revert if passing address(0)
        vm.prank(admin);
        vm.expectRevert();
        mmOracle.removeConfigSingle(address(0), 0, 0, 0);
    }

    function _buildTestSetup(
        address[2] memory tokensArr,
        uint256[2] memory eModesArr,
        uint8[2][5] memory possible
    ) internal pure returns (address[] memory tokens, uint256[] memory eModes, uint8[] memory isOperate, uint8[] memory isCollat) {
        uint256 count = tokensArr.length * eModesArr.length * possible.length;
        // preallocate arrays
        tokens = new address[](count);
        eModes = new uint256[](count);
        isOperate = new uint8[](count);
        isCollat = new uint8[](count);

        uint256 idx = 0;

        unchecked {
            for (uint256 t = 0; t < tokensArr.length; ++t) {
                address tok = tokensArr[t];
                for (uint256 e = 0; e < eModesArr.length; ++e) {
                    uint256 emode = eModesArr[e];
                    for (uint256 c = 0; c < possible.length; ++c) {
                        tokens[idx] = tok;
                        eModes[idx] = emode;
                        isOperate[idx] = possible[c][0];
                        isCollat[idx] = possible[c][1];
                        idx++;
                    }
                }
            }
        }
        // returned as per signature
    }

    function test_setOracleConfigMultiple_combinations_and_updates() public {
        // Move almost everything to memory arrays to reduce stack usage.
        address[2] memory tokensArr = [address(USDC), address(DAI)];
        uint256[2] memory eModesArr = [uint256(0), uint256(1)];
        uint8[2][5] memory possible = [[2, 0], [2, 1], [2, 2], [0, 2], [1, 2]];

        (address[] memory tokens, uint256[] memory eModes, uint8[] memory isOperate, uint8[] memory isCollat) = _buildTestSetup(tokensArr, eModesArr, possible);
        uint256 count = tokens.length;

        {
            // Mock the call to Money Market to return a valid number of EModes (e.g., 20)
            // This is required because _validateEMode reads the totalEmodesListed_ from storage on the MM contract.
            // The MM_SLOT_TOTAL_EMODES is likely a storage slot, must match oracle contract.
            // Assume oracle contract assigns MM_SLOT_TOTAL_EMODES = 0 and positions to lower bits.
            // Usually, the emode count is read as (value >> MM_BITPOS_TOTAL_EMODES) & MM_MASK_TOTAL_EMODES;
            // We'll return a storage value that will result in totalEmodesListed_ == 20.

            // These constants should match those in the oracle implementation.
            bytes32 MM_SLOT_TOTAL_EMODES = bytes32(uint256(1));
            uint256 MM_BITPOS_TOTAL_EMODES = 212;
            uint256 MM_MASK_TOTAL_EMODES = 0xFFF;

            // Compose the storage value: place 20 at the correct bit position
            uint256 totalEmodes = 20;
            uint256 storageValue = (totalEmodes & MM_MASK_TOTAL_EMODES) << MM_BITPOS_TOTAL_EMODES;

            // Mock the call; the oracle reads MM_SLOT_TOTAL_EMODES from the MM contract via readFromStorage
            vm.mockCall(address(moneyMarket), abi.encodeWithSelector(bytes4(keccak256("readFromStorage(bytes32)")), MM_SLOT_TOTAL_EMODES), abi.encode(storageValue));
        }

        for (uint256 i = 0; i < count; i++) {
            SetSourceConfig memory config = SetSourceConfig({ sourceType: 2, source: address(clOracle), multiplier: 1 });
            vm.prank(admin);
            mmOracle.setConfigMultiple(tokens[i], eModes[i], isOperate[i], isCollat[i], config, config, config);
        }

        for (uint256 i = 0; i < count; i++) {
            uint8 checkedIo = isOperate[i] == 2 ? 0 : isOperate[i];
            uint8 checkedIc = isCollat[i] == 2 ? 0 : isCollat[i];
            (address source1, int8 multiplier1, uint8 sourceType1, , , , , , , , , ) = mmOracle.config(tokens[i], eModes[i], checkedIo, checkedIc);
            assertEq(sourceType1, 2, string(abi.encodePacked("cfgType mismatch at i=", vm.toString(i))));
            assertEq(source1, address(clOracle), string(abi.encodePacked("source mismatch at i=", vm.toString(i))));
            assertEq(multiplier1, 1, string(abi.encodePacked("multiplier mismatch at i=", vm.toString(i))));
        }

        // Update a single entry and check
        uint8 updateIdx = 3;
        {
            uint8 updateIo = isOperate[updateIdx];
            uint8 updateIc = isCollat[updateIdx];
            SetSourceConfig memory updateConfig = SetSourceConfig({ sourceType: 2, source: address(clOracle), multiplier: 1 });
            vm.prank(admin);
            mmOracle.setConfigMultiple(tokens[updateIdx], eModes[updateIdx], updateIo, updateIc, updateConfig, updateConfig, updateConfig);
        }

        for (uint256 i = 0; i < count; i++) {
            uint8 cIo = isOperate[i] == 2 ? 0 : isOperate[i];
            uint8 cIc = isCollat[i] == 2 ? 0 : isCollat[i];
            (address source, int8 multiplier, uint8 sourceType, , , , , , , , , ) = mmOracle.config(tokens[i], eModes[i], cIo, cIc);
            assertEq(multiplier, 1, string(abi.encodePacked("multiplier mismatch at i=", vm.toString(i))));
        }

        // Negative test: using setConfigMultiple with both isOperate and isCollateral < 2 should revert
        address testToken = address(USDC);
        uint256 testEmode = 0;
        SetSourceConfig memory example = SetSourceConfig({ sourceType: 2, source: address(clOracle), multiplier: 1 });
        for (uint8 io = 0; io <= 1; io++) {
            for (uint8 ic = 0; ic <= 1; ic++) {
                vm.prank(admin);
                vm.expectRevert(abi.encodeWithSelector(Error.FluidMMOracleError.selector, MMErrorTypes.MMOracle__InvalidParams));
                mmOracle.setConfigMultiple(testToken, testEmode, io, ic, example, example, example);
            }
        }
    }

    // --- Fallback & Pricing ---

    function test_getPrice_fallbackToEmodeZeroIfNotFound() public {
        SetSourceConfig memory source = SetSourceConfig({ sourceType: 2, source: address(clOracle), multiplier: 1 });
        vm.startPrank(admin);
        mmOracle.setConfigSingle(address(USDC), 0, 1, 1, source, _emptyCfg(), _emptyCfg());
        vm.stopPrank();

        // Set mock Chainlink price (exchangeRate)
        clOracle.setExchangeRate(133e24);

        // Emode=1 not found -> fallback to 0. Result: 133e24 * 10^1 = 133e25
        uint256 price = mmOracle.getPrice(address(USDC), 1, true, true);
        assertEq(price, 133e25);
    }

    function test_getPrice_chainlinkStaleOperate() public {
        SetSourceConfig memory source = SetSourceConfig({ sourceType: 2, source: address(clOracle), multiplier: 1 });
        vm.prank(admin);
        mmOracle.setConfigSingle(address(USDC), 0, 1, 1, source, _emptyCfg(), _emptyCfg());

        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(bytes4(keccak256("latestRoundData()"))),
            abi.encode(uint80(1), int256(1e18), uint256(0), block.timestamp - 26 hours, uint80(0))
        );

        vm.expectRevert(abi.encodeWithSelector(Error.FluidMMOracleError.selector, MMErrorTypes.MMOracle__ChainlinkStale));
        mmOracle.getPrice(address(USDC), 0, true, true);
    }

    function test_getPrice_chainlinkStaleLiquidate() public {
        SetSourceConfig memory source = SetSourceConfig({ sourceType: 2, source: address(clOracle), multiplier: 1 });
        vm.prank(admin);
        mmOracle.setConfigSingle(address(USDC), 0, 0, 1, source, _emptyCfg(), _emptyCfg());

        // updatedAt older than MAX_UPDATE_TIMESPAN_LIQUIDATE (10 days)
        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(bytes4(keccak256("latestRoundData()"))),
            abi.encode(uint80(1), int256(1e18), uint256(0), block.timestamp - 11 days, uint80(0))
        );

        vm.expectRevert(abi.encodeWithSelector(Error.FluidMMOracleError.selector, MMErrorTypes.MMOracle__ChainlinkStale));
        mmOracle.getPrice(address(USDC), 0, false, true);
    }

    function test_getPrice_chainlinkNotStaleLiquidate() public {
        SetSourceConfig memory source = SetSourceConfig({ sourceType: 2, source: address(clOracle), multiplier: 1 });
        vm.prank(admin);
        mmOracle.setConfigSingle(address(USDC), 0, 0, 1, source, _emptyCfg(), _emptyCfg());

        // updatedAt within MAX_UPDATE_TIMESPAN_LIQUIDATE (10 days) should succeed
        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(bytes4(keccak256("latestRoundData()"))),
            abi.encode(uint80(1), int256(1e18), uint256(0), block.timestamp - 9 days, uint80(0))
        );

        uint256 price = mmOracle.getPrice(address(USDC), 0, false, true);
        assertGt(price, 0, "Price should be non-zero for non-stale liquidate feed");
    }

    function test_getPrice_revertsZeroAfterNegativeMultiplier() public {
        SetSourceConfig memory source = SetSourceConfig({ sourceType: 2, source: address(clOracle), multiplier: -4 });
        vm.prank(admin);
        mmOracle.setConfigSingle(address(USDC), 0, 1, 1, source, _emptyCfg(), _emptyCfg());

        // Source returns 1000, multiplier -4 => 1000 / 10000 = 0 => should revert with RateZero
        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(bytes4(keccak256("latestRoundData()"))),
            abi.encode(uint80(1), int256(1000), uint256(0), block.timestamp, uint80(0))
        );

        vm.expectRevert(abi.encodeWithSelector(Error.FluidMMOracleError.selector, MMErrorTypes.MMOracle__RateZero));
        mmOracle.getPrice(address(USDC), 0, true, true);
    }

    function test_getPrice_revertsOnInvalidSource() public {
        // sourceType 88 is > 2, triggers MMOracle__InvalidSource in _verifySourceConfig
        SetSourceConfig memory src = SetSourceConfig({ sourceType: 88, source: address(clOracle), multiplier: 1 });
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidMMOracleError.selector, MMErrorTypes.MMOracle__InvalidSource));
        mmOracle.setConfigSingle(address(DAI), 0, 1, 1, src, _emptyCfg(), _emptyCfg());
    }

    function _emptyCfg() internal pure returns (SetSourceConfig memory) {
        return SetSourceConfig({ sourceType: 0, source: address(0), multiplier: 0 });
    }
}
