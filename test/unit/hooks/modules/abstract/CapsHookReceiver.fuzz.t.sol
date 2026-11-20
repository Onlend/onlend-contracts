// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

import {CapsHookReceiver} from "src/hooks/modules/abstract/CapsHookReceiver.sol";
import {Phase} from "src/hooks/interfaces/IHookReceiver.sol";
import {ActionLib} from "src/hooks/lib/ActionLib.sol";
import {MockPool} from "../../../pool/mocks/MockPool.sol";
import {CapsHookReceiverHarness} from "./mocks/CapsHookReceiverHarness.sol";

contract CapsHookReceiverFuzzTest is Test {
    CapsHookReceiver.CapType internal constant SUPPLY_CAP = CapsHookReceiver.CapType.Supply;
    CapsHookReceiver.CapType internal constant BORROW_CAP = CapsHookReceiver.CapType.Borrow;

    address internal capsConfigurator;
    CapsHookReceiverHarness internal capsHookReceiver;

    function setUp() public {
        capsConfigurator = makeAddr("capsConfigurator");
        CapsHookReceiverHarness implementation = new CapsHookReceiverHarness();
        capsHookReceiver = CapsHookReceiverHarness(Clones.clone(address(implementation)));
        capsHookReceiver.initialize(makeAddr("defaultAdmin"), capsConfigurator, new CapsHookReceiver.PoolCapConfig[](0));
    }

    // addCap()

    function testFuzz_addCap_StoresConfig(address pool, uint8 capType, uint256 limit) public {
        capType = uint8(bound(capType, uint8(SUPPLY_CAP), uint8(BORROW_CAP)));
        CapsHookReceiver.CapType capType_ = CapsHookReceiver.CapType(capType);

        _addCap(pool, capType_, limit);

        CapsHookReceiver.CapConfig memory config = capsHookReceiver.getCap(pool, capType_);
        assertEq(config.limit, limit);
        assertTrue(config.isAdded);
    }

    // updateCap()

    function testFuzz_updateCap_StoresNewLimit(address pool, uint8 capType, uint256 oldLimit, uint256 newLimit) public {
        capType = uint8(bound(capType, uint8(SUPPLY_CAP), uint8(BORROW_CAP)));
        CapsHookReceiver.CapType capType_ = CapsHookReceiver.CapType(capType);
        _addCap(pool, capType_, oldLimit);

        vm.prank(capsConfigurator);
        capsHookReceiver.updateCap(pool, capType_, newLimit);

        CapsHookReceiver.CapConfig memory config = capsHookReceiver.getCap(pool, capType_);
        assertEq(config.limit, newLimit);
        assertTrue(config.isAdded);
    }

    // removeCap()

    function testFuzz_removeCap_RemovesConfig(address pool, uint8 capType, uint256 limit) public {
        capType = uint8(bound(capType, uint8(SUPPLY_CAP), uint8(BORROW_CAP)));
        CapsHookReceiver.CapType capType_ = CapsHookReceiver.CapType(capType);
        _addCap(pool, capType_, limit);

        vm.prank(capsConfigurator);
        capsHookReceiver.removeCap(pool, capType_);

        CapsHookReceiver.CapConfig memory config = capsHookReceiver.getCap(pool, capType_);
        assertEq(config.limit, 0);
        assertFalse(config.isAdded);
    }

    // onHook()

    function testFuzz_onHook_RevertsWhenPhaseIsBefore(uint8 action) public {
        vm.expectRevert(abi.encodeWithSelector(CapsHookReceiver.UnsupportedPhase.selector, Phase.BEFORE));
        capsHookReceiver.onHook(makeAddr("pool"), Phase.BEFORE, action, "");
    }

    function testFuzz_onHook_AfterDepositAllowsTotalAssetsWithinCap(uint256 limit, uint256 totalAssets) public {
        totalAssets = bound(totalAssets, 0, limit);
        address pool = _deployPool(totalAssets, 0, 0);
        _addCap(pool, SUPPLY_CAP, limit);

        capsHookReceiver.onHook(pool, Phase.AFTER, ActionLib.POOL_DEPOSIT, "");
    }

    function testFuzz_onHook_AfterDepositRevertsWhenTotalAssetsExceedsCap(uint256 limit, uint256 totalAssets) public {
        limit = bound(limit, 0, type(uint256).max - 1);
        totalAssets = bound(totalAssets, limit + 1, type(uint256).max);
        address pool = _deployPool(totalAssets, 0, 0);
        _addCap(pool, SUPPLY_CAP, limit);

        vm.expectRevert(
            abi.encodeWithSelector(CapsHookReceiver.CapExceeded.selector, pool, SUPPLY_CAP, limit, totalAssets)
        );
        capsHookReceiver.onHook(pool, Phase.AFTER, ActionLib.POOL_DEPOSIT, "");
    }

    function testFuzz_onHook_IgnoresHookData(bytes calldata data) public {
        address pool = _deployPool(1001, 0, 0);
        _addCap(pool, SUPPLY_CAP, 1000);

        vm.expectRevert(
            abi.encodeWithSelector(
                CapsHookReceiver.CapExceeded.selector, pool, SUPPLY_CAP, uint256(1000), uint256(1001)
            )
        );
        capsHookReceiver.onHook(pool, Phase.AFTER, ActionLib.POOL_DEPOSIT, data);
    }

    function testFuzz_onHook_CapForOnePoolDoesNotAffectAnotherPool(
        address cappedPool,
        uint256 limit,
        uint256 totalAmount
    ) public {
        limit = bound(limit, 0, type(uint256).max - 1);
        totalAmount = bound(totalAmount, limit + 1, type(uint256).max);
        address uncappedPool = _deployPool(totalAmount, 0, 0);
        vm.assume(cappedPool != uncappedPool);
        _addCap(cappedPool, SUPPLY_CAP, limit);

        capsHookReceiver.onHook(uncappedPool, Phase.AFTER, ActionLib.POOL_DEPOSIT, "");
    }

    function testFuzz_onHook_SupplyCapDoesNotAffectBorrowCap(uint256 limit, uint256 total) public {
        limit = bound(limit, 0, type(uint256).max - 1);
        total = bound(total, limit + 1, type(uint256).max);
        address pool = _deployPool(total, 0, total);
        _addCap(pool, SUPPLY_CAP, limit);

        capsHookReceiver.onHook(pool, Phase.AFTER, ActionLib.POOL_BORROW, "");
    }

    function testFuzz_onHook_RevertsWhenActionIsUnsupported(uint8 action) public {
        vm.assume(
            action != ActionLib.POOL_DEPOSIT && action != ActionLib.POOL_MINT && action != ActionLib.POOL_BORROW
                && action != ActionLib.POOL_DEPOSIT_COLLATERAL
        );

        vm.expectRevert(abi.encodeWithSelector(CapsHookReceiver.UnsupportedAction.selector, action));
        capsHookReceiver.onHook(makeAddr("pool"), Phase.AFTER, action, "");
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
}
