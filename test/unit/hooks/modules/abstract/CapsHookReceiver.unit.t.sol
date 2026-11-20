// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IAccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Test} from "forge-std/Test.sol";

import {CapsHookReceiver} from "src/hooks/modules/abstract/CapsHookReceiver.sol";
import {IHookReceiver, Phase} from "src/hooks/interfaces/IHookReceiver.sol";
import {ActionLib} from "src/hooks/lib/ActionLib.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {MockPool} from "../../../pool/mocks/MockPool.sol";
import {CapsHookReceiverHarness} from "./mocks/CapsHookReceiverHarness.sol";

contract CapsHookReceiverUnitTest is Test {
    CapsHookReceiver.CapType internal constant SUPPLY_CAP = CapsHookReceiver.CapType.Supply;
    CapsHookReceiver.CapType internal constant COLLATERAL_CAP = CapsHookReceiver.CapType.Collateral;
    CapsHookReceiver.CapType internal constant BORROW_CAP = CapsHookReceiver.CapType.Borrow;

    address internal defaultAdmin;
    address internal capsConfigurator;
    address internal nonCapsConfigurator;
    address internal nonHookCaller;
    CapsHookReceiverHarness internal implementation;
    CapsHookReceiverHarness internal capsHookReceiver;

    function setUp() public {
        defaultAdmin = makeAddr("defaultAdmin");
        capsConfigurator = makeAddr("capsConfigurator");
        nonCapsConfigurator = makeAddr("nonCapsConfigurator");
        nonHookCaller = makeAddr("nonHookCaller");
        implementation = new CapsHookReceiverHarness();

        capsHookReceiver = _clone();
        capsHookReceiver.initialize(defaultAdmin, capsConfigurator, new CapsHookReceiver.PoolCapConfig[](0));
    }

    // initialize()

    function test_initialize_GrantsCapsConfiguratorRole() public view {
        assertTrue(capsHookReceiver.hasRole(capsHookReceiver.CAPS_CONFIG_ROLE(), capsConfigurator));
    }

    function test_initialize_UsesDefaultAdminAsCapsConfigRoleAdmin() public view {
        assertEq(
            capsHookReceiver.getRoleAdmin(capsHookReceiver.CAPS_CONFIG_ROLE()), capsHookReceiver.DEFAULT_ADMIN_ROLE()
        );
    }

    function test_initialize_AllowsZeroCapsConfigurator() public {
        CapsHookReceiverHarness instance = _clone();

        instance.initialize(defaultAdmin, address(0), new CapsHookReceiver.PoolCapConfig[](0));

        assertEq(instance.getRoleMemberCount(instance.CAPS_CONFIG_ROLE()), 0);
    }

    function test_initialize_AddsInitialCaps() public {
        CapsHookReceiverHarness instance = _clone();
        address pool = makeAddr("pool");
        CapsHookReceiver.PoolCapConfig[] memory poolCapConfigs = new CapsHookReceiver.PoolCapConfig[](2);
        poolCapConfigs[0] = CapsHookReceiver.PoolCapConfig({pool: pool, capType: SUPPLY_CAP, limit: 1000});
        poolCapConfigs[1] = CapsHookReceiver.PoolCapConfig({pool: pool, capType: COLLATERAL_CAP, limit: 0});

        instance.initialize(defaultAdmin, capsConfigurator, poolCapConfigs);

        CapsHookReceiver.CapConfig memory supplyConfig = instance.getCap(pool, SUPPLY_CAP);
        assertEq(supplyConfig.limit, 1000);
        assertTrue(supplyConfig.isAdded);

        CapsHookReceiver.CapConfig memory collateralConfig = instance.getCap(pool, COLLATERAL_CAP);
        assertEq(collateralConfig.limit, 0);
        assertTrue(collateralConfig.isAdded);
    }

    function test_initialize_EmitsCapAddedForEachInitialCap() public {
        CapsHookReceiverHarness instance = _clone();
        address pool = makeAddr("pool");
        CapsHookReceiver.PoolCapConfig[] memory poolCapConfigs = new CapsHookReceiver.PoolCapConfig[](2);
        poolCapConfigs[0] = CapsHookReceiver.PoolCapConfig({pool: pool, capType: SUPPLY_CAP, limit: 1000});
        poolCapConfigs[1] = CapsHookReceiver.PoolCapConfig({pool: pool, capType: COLLATERAL_CAP, limit: 0});

        vm.expectEmit(address(instance));
        emit CapsHookReceiver.CapAdded(pool, SUPPLY_CAP, 1000);
        vm.expectEmit(address(instance));
        emit CapsHookReceiver.CapAdded(pool, COLLATERAL_CAP, 0);

        instance.initialize(defaultAdmin, capsConfigurator, poolCapConfigs);
    }

    function test_initialize_RevertsWhenInitialCapIsDuplicated() public {
        CapsHookReceiverHarness instance = _clone();
        address pool = makeAddr("pool");
        CapsHookReceiver.PoolCapConfig[] memory poolCapConfigs = new CapsHookReceiver.PoolCapConfig[](2);
        poolCapConfigs[0] = CapsHookReceiver.PoolCapConfig({pool: pool, capType: SUPPLY_CAP, limit: 1000});
        poolCapConfigs[1] = CapsHookReceiver.PoolCapConfig({pool: pool, capType: SUPPLY_CAP, limit: 500});

        vm.expectRevert(abi.encodeWithSelector(CapsHookReceiver.CapAlreadyAdded.selector, pool, SUPPLY_CAP));
        instance.initialize(defaultAdmin, capsConfigurator, poolCapConfigs);
    }

    // addCap()

    function test_addCap_AddsCap() public {
        address pool = makeAddr("pool");
        uint256 limit = 1000;

        vm.prank(capsConfigurator);
        capsHookReceiver.addCap(pool, SUPPLY_CAP, limit);

        CapsHookReceiver.CapConfig memory config = capsHookReceiver.getCap(pool, SUPPLY_CAP);
        assertEq(config.limit, limit);
        assertTrue(config.isAdded);
    }

    function test_addCap_AddsZeroLimit() public {
        address pool = makeAddr("pool");

        vm.prank(capsConfigurator);
        capsHookReceiver.addCap(pool, SUPPLY_CAP, 0);

        CapsHookReceiver.CapConfig memory config = capsHookReceiver.getCap(pool, SUPPLY_CAP);
        assertEq(config.limit, 0);
        assertTrue(config.isAdded);
    }

    function test_addCap_AddsMaxLimit() public {
        address pool = makeAddr("pool");

        vm.prank(capsConfigurator);
        capsHookReceiver.addCap(pool, SUPPLY_CAP, type(uint256).max);

        CapsHookReceiver.CapConfig memory config = capsHookReceiver.getCap(pool, SUPPLY_CAP);
        assertEq(config.limit, type(uint256).max);
        assertTrue(config.isAdded);
    }

    function test_addCap_EmitsCapAdded() public {
        address pool = makeAddr("pool");
        uint256 limit = 1000;

        vm.expectEmit(address(capsHookReceiver));
        emit CapsHookReceiver.CapAdded(pool, SUPPLY_CAP, limit);

        vm.prank(capsConfigurator);
        capsHookReceiver.addCap(pool, SUPPLY_CAP, limit);
    }

    function test_addCap_RevertsWhenCallerIsNotCapsConfigurator() public {
        address pool = makeAddr("pool");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonCapsConfigurator,
                capsHookReceiver.CAPS_CONFIG_ROLE()
            )
        );
        vm.prank(nonCapsConfigurator);
        capsHookReceiver.addCap(pool, SUPPLY_CAP, 1000);
    }

    function test_addCap_RevertsWhenCapAlreadyExists() public {
        address pool = makeAddr("pool");

        vm.startPrank(capsConfigurator);
        capsHookReceiver.addCap(pool, SUPPLY_CAP, 1000);

        vm.expectRevert(abi.encodeWithSelector(CapsHookReceiver.CapAlreadyAdded.selector, pool, SUPPLY_CAP));
        capsHookReceiver.addCap(pool, SUPPLY_CAP, 2000);
        vm.stopPrank();
    }

    function test_addCap_RevertsWhenZeroCapAlreadyExists() public {
        address pool = makeAddr("pool");

        vm.startPrank(capsConfigurator);
        capsHookReceiver.addCap(pool, SUPPLY_CAP, 0);

        vm.expectRevert(abi.encodeWithSelector(CapsHookReceiver.CapAlreadyAdded.selector, pool, SUPPLY_CAP));
        capsHookReceiver.addCap(pool, SUPPLY_CAP, 1000);
        vm.stopPrank();
    }

    // updateCap()

    function test_updateCap_UpdatesLimit() public {
        address pool = makeAddr("pool");

        vm.startPrank(capsConfigurator);
        capsHookReceiver.addCap(pool, SUPPLY_CAP, 1000);
        capsHookReceiver.updateCap(pool, SUPPLY_CAP, 1500);
        vm.stopPrank();

        CapsHookReceiver.CapConfig memory config = capsHookReceiver.getCap(pool, SUPPLY_CAP);
        assertEq(config.limit, 1500);
        assertTrue(config.isAdded);
    }

    function test_updateCap_UpdatesLimitToZero() public {
        address pool = makeAddr("pool");

        vm.startPrank(capsConfigurator);
        capsHookReceiver.addCap(pool, SUPPLY_CAP, 1000);
        capsHookReceiver.updateCap(pool, SUPPLY_CAP, 0);
        vm.stopPrank();

        CapsHookReceiver.CapConfig memory config = capsHookReceiver.getCap(pool, SUPPLY_CAP);
        assertEq(config.limit, 0);
        assertTrue(config.isAdded);
    }

    function test_updateCap_UpdatesLimitToMax() public {
        address pool = makeAddr("pool");

        vm.startPrank(capsConfigurator);
        capsHookReceiver.addCap(pool, SUPPLY_CAP, 1000);
        capsHookReceiver.updateCap(pool, SUPPLY_CAP, type(uint256).max);
        vm.stopPrank();

        CapsHookReceiver.CapConfig memory config = capsHookReceiver.getCap(pool, SUPPLY_CAP);
        assertEq(config.limit, type(uint256).max);
        assertTrue(config.isAdded);
    }

    function test_updateCap_UpdatesExistingZeroLimit() public {
        address pool = makeAddr("pool");

        vm.startPrank(capsConfigurator);
        capsHookReceiver.addCap(pool, SUPPLY_CAP, 0);
        capsHookReceiver.updateCap(pool, SUPPLY_CAP, 1000);
        vm.stopPrank();

        CapsHookReceiver.CapConfig memory config = capsHookReceiver.getCap(pool, SUPPLY_CAP);
        assertEq(config.limit, 1000);
        assertTrue(config.isAdded);
    }

    function test_updateCap_EmitsCapUpdated() public {
        address pool = makeAddr("pool");

        vm.startPrank(capsConfigurator);
        capsHookReceiver.addCap(pool, SUPPLY_CAP, 1000);

        vm.expectEmit(address(capsHookReceiver));
        emit CapsHookReceiver.CapUpdated(pool, SUPPLY_CAP, 1500);
        capsHookReceiver.updateCap(pool, SUPPLY_CAP, 1500);
        vm.stopPrank();
    }

    function test_updateCap_RevertsWhenCallerIsNotCapsConfigurator() public {
        address pool = makeAddr("pool");

        vm.prank(capsConfigurator);
        capsHookReceiver.addCap(pool, SUPPLY_CAP, 1000);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonCapsConfigurator,
                capsHookReceiver.CAPS_CONFIG_ROLE()
            )
        );
        vm.prank(nonCapsConfigurator);
        capsHookReceiver.updateCap(pool, SUPPLY_CAP, 1500);
    }

    function test_updateCap_RevertsWhenCapDoesNotExist() public {
        address pool = makeAddr("pool");

        vm.expectRevert(abi.encodeWithSelector(CapsHookReceiver.CapNotFound.selector, pool, SUPPLY_CAP));
        vm.prank(capsConfigurator);
        capsHookReceiver.updateCap(pool, SUPPLY_CAP, 1500);
    }

    // removeCap()

    function test_removeCap_RemovesCap() public {
        address pool = makeAddr("pool");

        vm.startPrank(capsConfigurator);
        capsHookReceiver.addCap(pool, SUPPLY_CAP, 1000);

        capsHookReceiver.removeCap(pool, SUPPLY_CAP);
        vm.stopPrank();

        CapsHookReceiver.CapConfig memory config = capsHookReceiver.getCap(pool, SUPPLY_CAP);
        assertEq(config.limit, 0);
        assertFalse(config.isAdded);
    }

    function test_removeCap_RemovesCapWithZeroLimit() public {
        address pool = makeAddr("pool");

        vm.startPrank(capsConfigurator);
        capsHookReceiver.addCap(pool, SUPPLY_CAP, 0);

        capsHookReceiver.removeCap(pool, SUPPLY_CAP);
        vm.stopPrank();

        CapsHookReceiver.CapConfig memory config = capsHookReceiver.getCap(pool, SUPPLY_CAP);
        assertEq(config.limit, 0);
        assertFalse(config.isAdded);
    }

    function test_removeCap_EmitsCapRemoved() public {
        address pool = makeAddr("pool");

        vm.startPrank(capsConfigurator);
        capsHookReceiver.addCap(pool, SUPPLY_CAP, 1000);

        vm.expectEmit(address(capsHookReceiver));
        emit CapsHookReceiver.CapRemoved(pool, SUPPLY_CAP);
        capsHookReceiver.removeCap(pool, SUPPLY_CAP);
        vm.stopPrank();
    }

    function test_removeCap_AllowsCapToBeAddedAgain() public {
        address pool = makeAddr("pool");

        vm.startPrank(capsConfigurator);
        capsHookReceiver.addCap(pool, SUPPLY_CAP, 1000);
        capsHookReceiver.removeCap(pool, SUPPLY_CAP);

        capsHookReceiver.addCap(pool, SUPPLY_CAP, 2000);
        vm.stopPrank();

        CapsHookReceiver.CapConfig memory config = capsHookReceiver.getCap(pool, SUPPLY_CAP);
        assertEq(config.limit, 2000);
        assertTrue(config.isAdded);
    }

    function test_removeCap_AllowsTotalAboveRemovedLimit() public {
        address pool = _deployPool(1001, 0, 0);
        uint256 removedLimit = 1000;

        vm.startPrank(capsConfigurator);
        capsHookReceiver.addCap(pool, SUPPLY_CAP, removedLimit);
        capsHookReceiver.removeCap(pool, SUPPLY_CAP);
        vm.stopPrank();

        capsHookReceiver.onHook(pool, Phase.AFTER, ActionLib.POOL_DEPOSIT, "");
    }

    function test_removeCap_RevertsWhenCallerIsNotCapsConfigurator() public {
        address pool = makeAddr("pool");

        vm.prank(capsConfigurator);
        capsHookReceiver.addCap(pool, SUPPLY_CAP, 1000);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonCapsConfigurator,
                capsHookReceiver.CAPS_CONFIG_ROLE()
            )
        );
        vm.prank(nonCapsConfigurator);
        capsHookReceiver.removeCap(pool, SUPPLY_CAP);
    }

    function test_removeCap_RevertsWhenCapDoesNotExist() public {
        address pool = makeAddr("pool");

        vm.expectRevert(abi.encodeWithSelector(CapsHookReceiver.CapNotFound.selector, pool, SUPPLY_CAP));
        vm.prank(capsConfigurator);
        capsHookReceiver.removeCap(pool, SUPPLY_CAP);
    }

    // getCap()

    function test_getCap_ReturnsEmptyConfigWhenCapDoesNotExist() public view {
        address pool = address(0x1234);

        CapsHookReceiver.CapConfig memory config = capsHookReceiver.getCap(pool, SUPPLY_CAP);
        assertEq(config.limit, 0);
        assertFalse(config.isAdded);
    }

    // onHook()

    function test_onHook_CanBeCalledByAnyAccount() public {
        address pool = makeAddr("pool");

        vm.prank(nonHookCaller);
        capsHookReceiver.onHook(pool, Phase.AFTER, ActionLib.POOL_DEPOSIT, "");
    }

    function test_onHook_AllowsWhenCapDoesNotExistWithoutReadingPoolOrValuation() public {
        capsHookReceiver.setRevertOnValue(true);
        // Has no code, so reading any of its totals would revert.
        address pool = makeAddr("pool");

        capsHookReceiver.onHook(pool, Phase.AFTER, ActionLib.POOL_DEPOSIT, "");
    }

    function test_onHook_AllowsWhenValuedTotalEqualsCapEvenIfRawTotalExceedsCap() public {
        address pool = _deployPool(1001, 0, 0);
        _addCap(pool, SUPPLY_CAP, 1000);
        capsHookReceiver.setValueResult(1000);

        capsHookReceiver.onHook(pool, Phase.AFTER, ActionLib.POOL_DEPOSIT, "");
    }

    function test_onHook_AfterDepositAllowsTotalAssetsEqualToCap() public {
        address pool = _deployPool(1000, 2000, 2000);
        _addCap(pool, SUPPLY_CAP, 1000);

        capsHookReceiver.onHook(pool, Phase.AFTER, ActionLib.POOL_DEPOSIT, "");
    }

    function test_onHook_AfterDepositAllowsZeroTotalAssetsWithZeroCap() public {
        address pool = _deployPool(0, 2000, 2000);
        _addCap(pool, SUPPLY_CAP, 0);

        capsHookReceiver.onHook(pool, Phase.AFTER, ActionLib.POOL_DEPOSIT, "");
    }

    function test_onHook_AfterMintAllowsTotalAssetsEqualToCap() public {
        address pool = _deployPool(1000, 2000, 2000);
        _addCap(pool, SUPPLY_CAP, 1000);

        capsHookReceiver.onHook(pool, Phase.AFTER, ActionLib.POOL_MINT, "");
    }

    function test_onHook_AfterBorrowAllowsTotalDebtEqualToCap() public {
        address pool = _deployPool(2000, 2000, 1000);
        _addCap(pool, BORROW_CAP, 1000);

        capsHookReceiver.onHook(pool, Phase.AFTER, ActionLib.POOL_BORROW, "");
    }

    function test_onHook_AfterDepositCollateralAllowsTotalsEqualToCaps() public {
        address pool = _deployPool(1000, 500, 2000);
        _addCap(pool, SUPPLY_CAP, 1000);
        _addCap(pool, COLLATERAL_CAP, 500);

        capsHookReceiver.onHook(pool, Phase.AFTER, ActionLib.POOL_DEPOSIT_COLLATERAL, "");
    }

    function test_onHook_RevertsWhenPhaseIsBefore() public {
        vm.expectRevert(abi.encodeWithSelector(CapsHookReceiver.UnsupportedPhase.selector, Phase.BEFORE));
        capsHookReceiver.onHook(makeAddr("pool"), Phase.BEFORE, ActionLib.POOL_DEPOSIT, "");
    }

    function test_onHook_RevertsWhenActionIsUnsupported() public {
        uint8 unsupportedAction = type(uint8).max;

        vm.expectRevert(abi.encodeWithSelector(CapsHookReceiver.UnsupportedAction.selector, unsupportedAction));
        capsHookReceiver.onHook(makeAddr("pool"), Phase.AFTER, unsupportedAction, "");
    }

    function test_onHook_RevertsWhenValuedTotalExceedsCap() public {
        address pool = _deployPool(500, 0, 0);
        _addCap(pool, SUPPLY_CAP, 1000);
        capsHookReceiver.setValueResult(1001);

        vm.expectRevert(
            abi.encodeWithSelector(
                CapsHookReceiver.CapExceeded.selector, pool, SUPPLY_CAP, uint256(1000), uint256(1001)
            )
        );
        capsHookReceiver.onHook(pool, Phase.AFTER, ActionLib.POOL_DEPOSIT, "");
    }

    function test_onHook_AfterMintRevertsWhenTotalAssetsExceedsCap() public {
        address pool = _deployPool(1001, 0, 0);
        _addCap(pool, SUPPLY_CAP, 1000);

        vm.expectRevert(
            abi.encodeWithSelector(
                CapsHookReceiver.CapExceeded.selector, pool, SUPPLY_CAP, uint256(1000), uint256(1001)
            )
        );
        capsHookReceiver.onHook(pool, Phase.AFTER, ActionLib.POOL_MINT, "");
    }

    function test_onHook_AfterDepositRevertsWhenTotalAssetsExceedsCap() public {
        address pool = _deployPool(1001, 0, 0);
        _addCap(pool, SUPPLY_CAP, 1000);

        vm.expectRevert(
            abi.encodeWithSelector(
                CapsHookReceiver.CapExceeded.selector, pool, SUPPLY_CAP, uint256(1000), uint256(1001)
            )
        );
        capsHookReceiver.onHook(pool, Phase.AFTER, ActionLib.POOL_DEPOSIT, "");
    }

    function test_onHook_AfterDepositRevertsWhenZeroCapIsExceeded() public {
        address pool = _deployPool(1, 0, 0);
        _addCap(pool, SUPPLY_CAP, 0);

        vm.expectRevert(
            abi.encodeWithSelector(CapsHookReceiver.CapExceeded.selector, pool, SUPPLY_CAP, uint256(0), uint256(1))
        );
        capsHookReceiver.onHook(pool, Phase.AFTER, ActionLib.POOL_DEPOSIT, "");
    }

    function test_onHook_AfterBorrowRevertsWhenTotalDebtExceedsCap() public {
        address pool = _deployPool(0, 0, 1001);
        _addCap(pool, BORROW_CAP, 1000);

        vm.expectRevert(
            abi.encodeWithSelector(
                CapsHookReceiver.CapExceeded.selector, pool, BORROW_CAP, uint256(1000), uint256(1001)
            )
        );
        capsHookReceiver.onHook(pool, Phase.AFTER, ActionLib.POOL_BORROW, "");
    }

    function test_onHook_AfterDepositCollateralChecksSupplyCapBeforeCollateralCap() public {
        address pool = _deployPool(1001, 1001, 0);
        _addCap(pool, SUPPLY_CAP, 1000);
        _addCap(pool, COLLATERAL_CAP, 1000);

        vm.expectRevert(
            abi.encodeWithSelector(
                CapsHookReceiver.CapExceeded.selector, pool, SUPPLY_CAP, uint256(1000), uint256(1001)
            )
        );
        capsHookReceiver.onHook(pool, Phase.AFTER, ActionLib.POOL_DEPOSIT_COLLATERAL, "");
    }

    function test_onHook_AfterDepositCollateralRevertsWhenOnlyCollateralCapIsExceeded() public {
        address pool = _deployPool(500, 1001, 0);
        _addCap(pool, COLLATERAL_CAP, 1000);

        vm.expectRevert(
            abi.encodeWithSelector(
                CapsHookReceiver.CapExceeded.selector, pool, COLLATERAL_CAP, uint256(1000), uint256(1001)
            )
        );
        capsHookReceiver.onHook(pool, Phase.AFTER, ActionLib.POOL_DEPOSIT_COLLATERAL, "");
    }

    function test_onHook_AfterDepositCollateralRevertsWhenTotalCollateralExceedsCap() public {
        address pool = _deployPool(1000, 1001, 0);
        _addCap(pool, SUPPLY_CAP, 1000);
        _addCap(pool, COLLATERAL_CAP, 1000);

        vm.expectRevert(
            abi.encodeWithSelector(
                CapsHookReceiver.CapExceeded.selector, pool, COLLATERAL_CAP, uint256(1000), uint256(1001)
            )
        );
        capsHookReceiver.onHook(pool, Phase.AFTER, ActionLib.POOL_DEPOSIT_COLLATERAL, "");
    }

    // isCapAdded()

    function test_isCapAdded_ReturnsTrueWhenCapExists() public {
        address pool = makeAddr("pool");

        vm.prank(capsConfigurator);
        capsHookReceiver.addCap(pool, SUPPLY_CAP, 1000);

        assertTrue(capsHookReceiver.isCapAdded(pool, SUPPLY_CAP));
    }

    function test_isCapAdded_ReturnsFalseWhenCapDoesNotExist() public view {
        address pool = address(0x1234);

        assertFalse(capsHookReceiver.isCapAdded(pool, SUPPLY_CAP));
    }

    // supportsInterface()

    function test_supportsInterface_HookReceiver_ReturnsTrue() public view {
        assertTrue(capsHookReceiver.supportsInterface(type(IHookReceiver).interfaceId));
    }

    function test_supportsInterface_Versioned_ReturnsTrue() public view {
        assertTrue(capsHookReceiver.supportsInterface(type(IVersioned).interfaceId));
    }

    function test_supportsInterface_ERC165_ReturnsTrue() public view {
        assertTrue(capsHookReceiver.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_AccessControl_ReturnsTrue() public view {
        assertTrue(capsHookReceiver.supportsInterface(type(IAccessControl).interfaceId));
    }

    function test_supportsInterface_AccessControlEnumerable_ReturnsTrue() public view {
        assertTrue(capsHookReceiver.supportsInterface(type(IAccessControlEnumerable).interfaceId));
    }

    function test_supportsInterface_Unknown_ReturnsFalse() public view {
        assertFalse(capsHookReceiver.supportsInterface(bytes4(0xffffffff)));
        assertFalse(capsHookReceiver.supportsInterface(bytes4(0xdeadbeef)));
    }

    function _addCap(address pool, CapsHookReceiver.CapType capType, uint256 limit) internal {
        vm.prank(capsConfigurator);
        capsHookReceiver.addCap(pool, capType, limit);
    }

    function _deployPool(uint256 totalAssets, uint256 totalCollateral, uint256 totalDebt) internal returns (address) {
        MockPool pool = new MockPool();
        pool.setTotals(totalAssets, totalCollateral, totalDebt);
        return address(pool);
    }

    function _clone() internal returns (CapsHookReceiverHarness) {
        return CapsHookReceiverHarness(Clones.clone(address(implementation)));
    }
}
