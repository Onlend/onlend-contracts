// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

import {Phase} from "src/hooks/interfaces/IHookReceiver.sol";
import {CapsHookReceiver} from "src/hooks/modules/abstract/CapsHookReceiver.sol";
import {ActionLib} from "src/hooks/lib/ActionLib.sol";
import {NominalCapsHookReceiver} from "src/hooks/modules/NominalCapsHookReceiver.sol";
import {MockPool} from "../../pool/mocks/MockPool.sol";

contract NominalCapsHookReceiverFuzzTest is Test {
    CapsHookReceiver.CapType internal constant SUPPLY_CAP = CapsHookReceiver.CapType.Supply;

    address internal capsConfigurator;
    NominalCapsHookReceiver internal capsHookReceiver;

    function setUp() public {
        capsConfigurator = makeAddr("capsConfigurator");
        NominalCapsHookReceiver implementation = new NominalCapsHookReceiver();
        capsHookReceiver = NominalCapsHookReceiver(Clones.clone(address(implementation)));
        capsHookReceiver.initialize(makeAddr("defaultAdmin"), capsConfigurator, new CapsHookReceiver.PoolCapConfig[](0));
    }

    function testFuzz_onHook_AfterDepositRevertsWhenNominalAmountExceedsCap(uint256 amount) public {
        amount = bound(amount, 1, type(uint256).max);
        uint256 limit = amount - 1;
        address pool = _deployPool(amount);
        vm.prank(capsConfigurator);
        capsHookReceiver.addCap(pool, SUPPLY_CAP, limit);

        vm.expectRevert(abi.encodeWithSelector(CapsHookReceiver.CapExceeded.selector, pool, SUPPLY_CAP, limit, amount));
        capsHookReceiver.onHook(pool, Phase.AFTER, ActionLib.POOL_DEPOSIT, "");
    }

    function _deployPool(uint256 totalAssets) internal returns (address) {
        MockPool pool = new MockPool();
        pool.setTotals(totalAssets, 0, 0);
        return address(pool);
    }
}
