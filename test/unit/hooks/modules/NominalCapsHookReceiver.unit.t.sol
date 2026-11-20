// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

import {Phase} from "src/hooks/interfaces/IHookReceiver.sol";
import {ActionLib} from "src/hooks/lib/ActionLib.sol";
import {CapsHookReceiver} from "src/hooks/modules/abstract/CapsHookReceiver.sol";
import {NominalCapsHookReceiver} from "src/hooks/modules/NominalCapsHookReceiver.sol";
import {MockPool} from "../../pool/mocks/MockPool.sol";

contract NominalCapsHookReceiverUnitTest is Test {
    CapsHookReceiver.CapType internal constant SUPPLY_CAP = CapsHookReceiver.CapType.Supply;

    address internal defaultAdmin;
    address internal capsConfigurator;
    NominalCapsHookReceiver internal implementation;
    NominalCapsHookReceiver internal capsHookReceiver;

    function setUp() public {
        defaultAdmin = makeAddr("defaultAdmin");
        capsConfigurator = makeAddr("capsConfigurator");
        implementation = new NominalCapsHookReceiver();

        capsHookReceiver = _clone();
        capsHookReceiver.initialize(defaultAdmin, capsConfigurator, new CapsHookReceiver.PoolCapConfig[](0));
    }

    // initialize()

    function test_initialize_GrantsDefaultAdminAndCapsConfiguratorRoles() public view {
        assertTrue(capsHookReceiver.hasRole(capsHookReceiver.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertTrue(capsHookReceiver.hasRole(capsHookReceiver.CAPS_CONFIG_ROLE(), capsConfigurator));
    }

    function test_initialize_AllowsZeroDefaultAdmin() public {
        NominalCapsHookReceiver instance = _clone();

        instance.initialize(address(0), capsConfigurator, new CapsHookReceiver.PoolCapConfig[](0));

        assertEq(instance.getRoleMemberCount(instance.DEFAULT_ADMIN_ROLE()), 0);
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(capsHookReceiver.contractName(), "NominalCapsHookReceiver");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(capsHookReceiver.contractVersion(), "1.0.0");
    }

    // _value() through onHook()

    function test_onHook_AllowsNominalAmountEqualToCap() public {
        address pool = _deployPool(1000);

        vm.prank(capsConfigurator);
        capsHookReceiver.addCap(pool, SUPPLY_CAP, 1000);

        capsHookReceiver.onHook(pool, Phase.AFTER, ActionLib.POOL_DEPOSIT, "");
    }

    function test_onHook_RevertsWhenNominalAmountExceedsCap() public {
        address pool = _deployPool(1001);

        vm.prank(capsConfigurator);
        capsHookReceiver.addCap(pool, SUPPLY_CAP, 1000);

        vm.expectRevert(
            abi.encodeWithSelector(
                CapsHookReceiver.CapExceeded.selector, pool, SUPPLY_CAP, uint256(1000), uint256(1001)
            )
        );
        capsHookReceiver.onHook(pool, Phase.AFTER, ActionLib.POOL_DEPOSIT, "");
    }

    function _deployPool(uint256 totalAssets) internal returns (address) {
        MockPool pool = new MockPool();
        pool.setTotals(totalAssets, 0, 0);
        return address(pool);
    }

    function _clone() internal returns (NominalCapsHookReceiver) {
        return NominalCapsHookReceiver(Clones.clone(address(implementation)));
    }
}
