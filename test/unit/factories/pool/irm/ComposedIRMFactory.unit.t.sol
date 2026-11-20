// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {ICloneFactory} from "src/factories/interfaces/ICloneFactory.sol";
import {ComposedIRMFactory} from "src/factories/pool/irm/ComposedIRMFactory.sol";
import {ComposedIRM} from "src/pool/irm/ComposedIRM.sol";

contract ComposedIRMFactoryUnitTest is Test {
    ComposedIRMFactory factory;
    ComposedIRM implementation;

    address borrowRateCaller = makeAddr("borrowRateCaller");
    address defaultAdmin = makeAddr("defaultAdmin");
    address borrowRateUpdater = makeAddr("borrowRateUpdater");
    address retentionRateUpdater = makeAddr("retentionRateUpdater");
    address conditionUpdater = makeAddr("conditionUpdater");

    uint256 constant FIXED_BORROW_RATE = 0.05e18;
    uint256 constant FIXED_RETENTION_RATE = 0.1e18;
    bytes32 constant SALT = keccak256("salt");

    function setUp() public {
        implementation = new ComposedIRM();
        factory = new ComposedIRMFactory(address(implementation));
    }

    // clone()

    function test_Clone_InitializesCloneWithDecodedRolesAndConfiguration() public {
        address instance = factory.clone(SALT, _initializationData());

        ComposedIRM irm = ComposedIRM(instance);
        (ComposedIRM.BorrowRateType borrowRateType, bytes memory borrowRateParams) = irm.borrowRateConfig();
        (ComposedIRM.RetentionRateType retentionRateType, bytes memory retentionRateParams) = irm.retentionRateConfig();
        (ComposedIRM.ConditionType conditionType, bytes memory conditionParams) = irm.conditionConfig();
        assertEq(irm.borrowRateCaller(), borrowRateCaller);
        assertEq(uint256(borrowRateType), uint256(ComposedIRM.BorrowRateType.FIXED));
        assertEq(borrowRateParams, abi.encode(FIXED_BORROW_RATE));
        assertEq(uint256(retentionRateType), uint256(ComposedIRM.RetentionRateType.FIXED));
        assertEq(retentionRateParams, abi.encode(FIXED_RETENTION_RATE));
        assertEq(uint256(conditionType), uint256(ComposedIRM.ConditionType.ALWAYS_APPLICABLE));
        assertEq(conditionParams, "");
        assertTrue(irm.hasRole(irm.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertTrue(irm.hasRole(irm.BORROW_RATE_UPDATER_ROLE(), borrowRateUpdater));
        assertTrue(irm.hasRole(irm.RETENTION_RATE_UPDATER_ROLE(), retentionRateUpdater));
        assertTrue(irm.hasRole(irm.CONDITION_UPDATER_ROLE(), conditionUpdater));
    }

    function test_Clone_EmitsClonedEvent() public {
        address predicted = factory.predictAddress(address(this), SALT);

        vm.expectEmit();
        emit ICloneFactory.Cloned(predicted, SALT);
        factory.clone(SALT, _initializationData());
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(factory.contractName(), "ComposedIRM1.0.0Factory");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(factory.contractVersion(), "1.0.0");
    }

    // Helpers

    function _initializationData() internal view returns (bytes memory) {
        return abi.encode(
            borrowRateCaller,
            ComposedIRM.BorrowRateType.FIXED,
            abi.encode(FIXED_BORROW_RATE),
            ComposedIRM.RetentionRateType.FIXED,
            abi.encode(FIXED_RETENTION_RATE),
            ComposedIRM.ConditionType.ALWAYS_APPLICABLE,
            "",
            defaultAdmin,
            borrowRateUpdater,
            retentionRateUpdater,
            conditionUpdater
        );
    }
}
