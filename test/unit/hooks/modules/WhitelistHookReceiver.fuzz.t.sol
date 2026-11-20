// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

import {WhitelistHookReceiver} from "src/hooks/modules/WhitelistHookReceiver.sol";
import {Phase} from "src/hooks/interfaces/IHookReceiver.sol";
import {ActionLib} from "src/hooks/lib/ActionLib.sol";
import {Whitelistable} from "src/whitelist/abstract/Whitelistable.sol";

contract WhitelistHookReceiverFuzzTest is Test {
    address internal whitelistConfigurator;
    WhitelistHookReceiver internal implementation;
    WhitelistHookReceiver internal whitelistHookReceiver;

    function setUp() public {
        whitelistConfigurator = makeAddr("whitelistConfigurator");
        implementation = new WhitelistHookReceiver();

        whitelistHookReceiver = WhitelistHookReceiver(Clones.clone(address(implementation)));
        whitelistHookReceiver.initialize(
            makeAddr("defaultAdmin"), whitelistConfigurator, new Whitelistable.WhitelistUpdate[](0)
        );
    }

    // onHook()

    function testFuzz_onHook_AllowsAccountActionsWhenOnlyAccountIsWhitelisted(
        uint256 actionSeed,
        address account,
        address counterparty
    ) public {
        vm.assume(account != counterparty);
        _setWhitelisted(account, true);

        whitelistHookReceiver.onHook(
            makeAddr("hookSource"), Phase.BEFORE, _accountAction(actionSeed), abi.encode(account, counterparty)
        );
    }

    function testFuzz_onHook_RevertsAccountActionsWhenAccountIsNotWhitelisted(
        uint256 actionSeed,
        address account,
        address counterparty
    ) public {
        vm.assume(account != counterparty);
        _setWhitelisted(counterparty, true);

        vm.expectRevert(abi.encodeWithSelector(Whitelistable.AccountNotWhitelisted.selector, account));
        whitelistHookReceiver.onHook(
            makeAddr("hookSource"), Phase.BEFORE, _accountAction(actionSeed), abi.encode(account, counterparty)
        );
    }

    function testFuzz_onHook_AllowsCounterpartyActionsWhenOnlyCounterpartyIsWhitelisted(
        uint256 actionSeed,
        address account,
        address counterparty
    ) public {
        vm.assume(account != counterparty);
        _setWhitelisted(counterparty, true);

        whitelistHookReceiver.onHook(
            makeAddr("hookSource"), Phase.BEFORE, _counterpartyAction(actionSeed), abi.encode(account, counterparty)
        );
    }

    function testFuzz_onHook_RevertsCounterpartyActionsWhenCounterpartyIsNotWhitelisted(
        uint256 actionSeed,
        address account,
        address counterparty
    ) public {
        vm.assume(account != counterparty);
        _setWhitelisted(account, true);

        vm.expectRevert(abi.encodeWithSelector(Whitelistable.AccountNotWhitelisted.selector, counterparty));
        whitelistHookReceiver.onHook(
            makeAddr("hookSource"), Phase.BEFORE, _counterpartyAction(actionSeed), abi.encode(account, counterparty)
        );
    }

    function testFuzz_onHook_RevertsWhenActionIsUnsupported(uint256 actionSeed, address account) public {
        uint8 action = _unsupportedAction(actionSeed);
        _setWhitelisted(account, true);

        vm.expectRevert(abi.encodeWithSelector(WhitelistHookReceiver.UnsupportedAction.selector, action));
        whitelistHookReceiver.onHook(makeAddr("hookSource"), Phase.BEFORE, action, abi.encode(account, account));
    }

    function testFuzz_onHook_RevertsWhenDataIsShorterThanAccount(uint256 dataLength, uint256 actionSeed) public {
        dataLength = bound(dataLength, 0, 31);

        vm.expectRevert(WhitelistHookReceiver.InvalidHookData.selector);
        whitelistHookReceiver.onHook(
            makeAddr("hookSource"), Phase.BEFORE, _accountAction(actionSeed), new bytes(dataLength)
        );
    }

    function testFuzz_onHook_RevertsWhenDataIsShorterThanCounterparty(uint256 dataLength, uint256 actionSeed) public {
        dataLength = bound(dataLength, 0, 63);

        vm.expectRevert(WhitelistHookReceiver.InvalidHookData.selector);
        whitelistHookReceiver.onHook(
            makeAddr("hookSource"), Phase.BEFORE, _counterpartyAction(actionSeed), new bytes(dataLength)
        );
    }

    function _setWhitelisted(address account, bool isWhitelisted) internal {
        Whitelistable.WhitelistUpdate[] memory updates = new Whitelistable.WhitelistUpdate[](1);
        updates[0] = Whitelistable.WhitelistUpdate({account: account, isWhitelisted: isWhitelisted});

        vm.prank(whitelistConfigurator);
        whitelistHookReceiver.setWhitelisted(updates);
    }

    function _accountAction(uint256 actionSeed) internal pure returns (uint8) {
        uint8[6] memory actions = [
            ActionLib.LC_DEPOSIT_COLLATERAL,
            ActionLib.LC_BORROW,
            ActionLib.POOL_DEPOSIT_COLLATERAL,
            ActionLib.POOL_BORROW,
            ActionLib.POOL_DEPOSIT,
            ActionLib.POOL_MINT
        ];
        return actions[bound(actionSeed, 0, actions.length - 1)];
    }

    function _counterpartyAction(uint256 actionSeed) internal pure returns (uint8) {
        uint8[3] memory actions = [ActionLib.LC_LIQUIDATE, ActionLib.POOL_SEIZE_COLLATERAL, ActionLib.POOL_TRANSFER];
        return actions[bound(actionSeed, 0, actions.length - 1)];
    }

    function _unsupportedAction(uint256 actionSeed) internal pure returns (uint8) {
        uint8[10] memory actions = [
            ActionLib.LC_WITHDRAW_COLLATERAL,
            ActionLib.LC_REPAY,
            ActionLib.POOL_WITHDRAW_COLLATERAL,
            ActionLib.POOL_REPAY,
            ActionLib.POOL_WRITE_OFF_DEBT,
            ActionLib.POOL_WITHDRAW,
            ActionLib.POOL_REDEEM,
            ActionLib.POOL_FLASH_LOAN,
            ActionLib.POOL_SYNC_ACCOUNT,
            ActionLib.POOL_CLAIM_FEE_SHARES
        ];
        return actions[bound(actionSeed, 0, actions.length - 1)];
    }
}
