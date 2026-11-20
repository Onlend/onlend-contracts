// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {ICloneFactory} from "src/factories/interfaces/ICloneFactory.sol";
import {UsdCapsHookReceiverFactory} from "src/factories/hooks/modules/UsdCapsHookReceiverFactory.sol";
import {UsdCapsHookReceiver} from "src/hooks/modules/UsdCapsHookReceiver.sol";
import {CapsHookReceiver} from "src/hooks/modules/abstract/CapsHookReceiver.sol";
import {MockOracle} from "../../../../mocks/MockOracle.sol";

contract UsdCapsHookReceiverFactoryUnitTest is Test {
    UsdCapsHookReceiverFactory factory;
    UsdCapsHookReceiver implementation;

    address defaultAdmin = makeAddr("defaultAdmin");
    address capsConfigurator = makeAddr("capsConfigurator");
    address oracleUpdater = makeAddr("oracleUpdater");
    MockOracle oracle;
    address pool = makeAddr("pool");

    uint256 constant LIMIT = 1000e18;
    bytes32 constant SALT = keccak256("salt");

    function setUp() public {
        implementation = new UsdCapsHookReceiver();
        factory = new UsdCapsHookReceiverFactory(address(implementation));
        oracle = new MockOracle();
    }

    // clone()

    function test_Clone_InitializesCloneWithDecodedRolesAndConfiguration() public {
        CapsHookReceiver.PoolCapConfig[] memory initialCaps = _initialCaps();

        address instance = factory.clone(
            SALT, abi.encode(defaultAdmin, capsConfigurator, oracleUpdater, address(oracle), initialCaps)
        );

        UsdCapsHookReceiver capsHookReceiver = UsdCapsHookReceiver(instance);
        CapsHookReceiver.CapConfig memory cap = capsHookReceiver.getCap(pool, CapsHookReceiver.CapType.Supply);
        assertTrue(capsHookReceiver.hasRole(capsHookReceiver.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertTrue(capsHookReceiver.hasRole(capsHookReceiver.CAPS_CONFIG_ROLE(), capsConfigurator));
        assertTrue(capsHookReceiver.hasRole(capsHookReceiver.ORACLE_UPDATER_ROLE(), oracleUpdater));
        assertEq(capsHookReceiver.oracle(), address(oracle));
        assertTrue(cap.isAdded);
        assertEq(cap.limit, LIMIT);
    }

    function test_Clone_EmitsClonedEvent() public {
        address predicted = factory.predictAddress(address(this), SALT);

        vm.expectEmit();
        emit ICloneFactory.Cloned(predicted, SALT);
        factory.clone(SALT, abi.encode(defaultAdmin, capsConfigurator, oracleUpdater, address(oracle), _initialCaps()));
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(factory.contractName(), "UsdCapsHookReceiver1.0.0Factory");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(factory.contractVersion(), "1.0.0");
    }

    // Helpers

    function _initialCaps() internal view returns (CapsHookReceiver.PoolCapConfig[] memory initialCaps) {
        initialCaps = new CapsHookReceiver.PoolCapConfig[](1);
        initialCaps[0] =
            CapsHookReceiver.PoolCapConfig({pool: pool, capType: CapsHookReceiver.CapType.Supply, limit: LIMIT});
    }
}
