// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IAccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Test} from "forge-std/Test.sol";

import {PauseHookReceiver} from "src/hooks/modules/PauseHookReceiver.sol";
import {IHookReceiver, Phase} from "src/hooks/interfaces/IHookReceiver.sol";
import {ActionLib} from "src/hooks/lib/ActionLib.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";

contract PauseHookReceiverUnitTest is Test {
    address internal defaultAdmin;
    address internal pauseConfigurator;
    address internal secondPauseConfigurator;
    address internal unpauseConfigurator;
    address internal hookSource;
    address internal otherHookSource;
    address internal allSources;
    PauseHookReceiver internal implementation;
    PauseHookReceiver internal pauseHookReceiver;

    function setUp() public {
        defaultAdmin = makeAddr("defaultAdmin");
        pauseConfigurator = makeAddr("pauseConfigurator");
        secondPauseConfigurator = makeAddr("secondPauseConfigurator");
        unpauseConfigurator = makeAddr("unpauseConfigurator");
        hookSource = makeAddr("hookSource");
        otherHookSource = makeAddr("otherHookSource");
        implementation = new PauseHookReceiver();

        pauseHookReceiver = _clone();
        pauseHookReceiver.initialize(defaultAdmin, _pauseConfigurators(), unpauseConfigurator);
        allSources = pauseHookReceiver.ALL_SOURCES();
    }

    // initialize()

    function test_initialize_GrantsDefaultAdminPauseConfigAndUnpauseConfigRoles() public view {
        assertTrue(pauseHookReceiver.hasRole(pauseHookReceiver.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertTrue(pauseHookReceiver.hasRole(pauseHookReceiver.PAUSE_CONFIG_ROLE(), pauseConfigurator));
        assertTrue(pauseHookReceiver.hasRole(pauseHookReceiver.PAUSE_CONFIG_ROLE(), secondPauseConfigurator));
        assertTrue(pauseHookReceiver.hasRole(pauseHookReceiver.UNPAUSE_CONFIG_ROLE(), unpauseConfigurator));
    }

    function test_initialize_UsesDefaultAdminAsRoleAdmin() public view {
        assertEq(
            pauseHookReceiver.getRoleAdmin(pauseHookReceiver.PAUSE_CONFIG_ROLE()),
            pauseHookReceiver.DEFAULT_ADMIN_ROLE()
        );
        assertEq(
            pauseHookReceiver.getRoleAdmin(pauseHookReceiver.UNPAUSE_CONFIG_ROLE()),
            pauseHookReceiver.DEFAULT_ADMIN_ROLE()
        );
    }

    function test_initialize_AllowsNoInitialRoleMembers() public {
        PauseHookReceiver instance = _clone();

        instance.initialize(address(0), new address[](0), address(0));

        assertEq(instance.getRoleMemberCount(instance.DEFAULT_ADMIN_ROLE()), 0);
        assertEq(instance.getRoleMemberCount(instance.PAUSE_CONFIG_ROLE()), 0);
        assertEq(instance.getRoleMemberCount(instance.UNPAUSE_CONFIG_ROLE()), 0);
    }

    // pause()

    function test_pause_PausesActions() public {
        uint256 actions = _bitmap(ActionLib.POOL_BORROW, ActionLib.POOL_DEPOSIT);

        vm.expectEmit();
        emit PauseHookReceiver.ActionsPaused(hookSource, actions);

        vm.prank(pauseConfigurator);
        pauseHookReceiver.pause(hookSource, actions);

        assertEq(pauseHookReceiver.getPausedActions(hookSource), actions);
    }

    function test_pause_KeepsActionsAlreadyPaused() public {
        _pause(hookSource, _bitmap(ActionLib.POOL_BORROW, ActionLib.POOL_DEPOSIT));

        vm.prank(pauseConfigurator);
        pauseHookReceiver.pause(hookSource, _bitmap(ActionLib.POOL_DEPOSIT, ActionLib.POOL_MINT));

        assertEq(
            pauseHookReceiver.getPausedActions(hookSource),
            _bitmap(ActionLib.POOL_BORROW, ActionLib.POOL_DEPOSIT, ActionLib.POOL_MINT)
        );
    }

    function test_pause_RevertsWhenCallerIsNotPauseConfigurator() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unpauseConfigurator,
                pauseHookReceiver.PAUSE_CONFIG_ROLE()
            )
        );
        vm.prank(unpauseConfigurator);
        pauseHookReceiver.pause(hookSource, _bitmap(ActionLib.POOL_BORROW));
    }

    // unpause()

    function test_unpause_UnpausesActions() public {
        _pause(hookSource, _bitmap(ActionLib.POOL_BORROW, ActionLib.POOL_DEPOSIT, ActionLib.POOL_MINT));
        uint256 actions = _bitmap(ActionLib.POOL_DEPOSIT);

        vm.expectEmit();
        emit PauseHookReceiver.ActionsUnpaused(hookSource, actions);

        vm.prank(unpauseConfigurator);
        pauseHookReceiver.unpause(hookSource, actions);

        assertEq(pauseHookReceiver.getPausedActions(hookSource), _bitmap(ActionLib.POOL_BORROW, ActionLib.POOL_MINT));
    }

    function test_unpause_IgnoresActionsNotPaused() public {
        _pause(hookSource, _bitmap(ActionLib.POOL_BORROW));

        vm.prank(unpauseConfigurator);
        pauseHookReceiver.unpause(hookSource, _bitmap(ActionLib.POOL_DEPOSIT));

        assertEq(pauseHookReceiver.getPausedActions(hookSource), _bitmap(ActionLib.POOL_BORROW));
    }

    function test_unpause_UnderAllSourcesLeavesActionsPausedUnderHookSource() public {
        _pause(hookSource, _bitmap(ActionLib.POOL_BORROW));
        _pause(allSources, _bitmap(ActionLib.POOL_BORROW));

        vm.prank(unpauseConfigurator);
        pauseHookReceiver.unpause(allSources, _bitmap(ActionLib.POOL_BORROW));

        assertTrue(pauseHookReceiver.isPaused(hookSource, ActionLib.POOL_BORROW));
    }

    function test_unpause_UnderHookSourceLeavesActionsPausedUnderAllSources() public {
        _pause(hookSource, _bitmap(ActionLib.POOL_BORROW));
        _pause(allSources, _bitmap(ActionLib.POOL_BORROW));

        vm.prank(unpauseConfigurator);
        pauseHookReceiver.unpause(hookSource, _bitmap(ActionLib.POOL_BORROW));

        assertTrue(pauseHookReceiver.isPaused(hookSource, ActionLib.POOL_BORROW));
    }

    function test_unpause_RevertsWhenCallerIsNotUnpauseConfigurator() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                pauseConfigurator,
                pauseHookReceiver.UNPAUSE_CONFIG_ROLE()
            )
        );
        vm.prank(pauseConfigurator);
        pauseHookReceiver.unpause(hookSource, _bitmap(ActionLib.POOL_BORROW));
    }

    // onHook()

    function test_onHook_AllowsActionWhenNotPaused() public {
        _pause(hookSource, _bitmap(ActionLib.POOL_DEPOSIT));

        pauseHookReceiver.onHook(hookSource, Phase.BEFORE, ActionLib.POOL_BORROW, "");
    }

    function test_onHook_RevertsWhenPhaseIsAfter() public {
        vm.expectRevert(abi.encodeWithSelector(PauseHookReceiver.UnsupportedPhase.selector, Phase.AFTER));
        pauseHookReceiver.onHook(hookSource, Phase.AFTER, ActionLib.POOL_BORROW, "");
    }

    function test_onHook_RevertsWhenActionIsPausedUnderHookSource() public {
        _pause(hookSource, _bitmap(ActionLib.POOL_BORROW));

        vm.expectRevert(
            abi.encodeWithSelector(PauseHookReceiver.ActionPaused.selector, hookSource, ActionLib.POOL_BORROW)
        );
        pauseHookReceiver.onHook(hookSource, Phase.BEFORE, ActionLib.POOL_BORROW, "");
    }

    function test_onHook_RevertsWhenActionIsPausedUnderAllSources() public {
        _pause(allSources, _bitmap(ActionLib.POOL_BORROW));

        vm.expectRevert(
            abi.encodeWithSelector(PauseHookReceiver.ActionPaused.selector, hookSource, ActionLib.POOL_BORROW)
        );
        pauseHookReceiver.onHook(hookSource, Phase.BEFORE, ActionLib.POOL_BORROW, "");
    }

    // getPausedActions()

    function test_getPausedActions_ExcludesActionsPausedUnderAllSources() public {
        _pause(hookSource, _bitmap(ActionLib.POOL_BORROW));
        _pause(allSources, _bitmap(ActionLib.POOL_DEPOSIT));

        assertEq(pauseHookReceiver.getPausedActions(hookSource), _bitmap(ActionLib.POOL_BORROW));
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(pauseHookReceiver.contractName(), "PauseHookReceiver");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(pauseHookReceiver.contractVersion(), "1.0.0");
    }

    // isPaused()

    function test_isPaused_ReturnsFalseWhenActionIsPausedUnderDifferentHookSource() public {
        _pause(otherHookSource, _bitmap(ActionLib.POOL_BORROW));

        assertFalse(pauseHookReceiver.isPaused(hookSource, ActionLib.POOL_BORROW));
    }

    function test_isPaused_ReturnsFalseForActionsAdjacentToPausedAction() public {
        _pause(hookSource, _bitmap(ActionLib.POOL_BORROW));

        assertTrue(pauseHookReceiver.isPaused(hookSource, ActionLib.POOL_BORROW));
        assertFalse(pauseHookReceiver.isPaused(hookSource, ActionLib.POOL_BORROW - 1));
        assertFalse(pauseHookReceiver.isPaused(hookSource, ActionLib.POOL_BORROW + 1));
    }

    function test_isPaused_ReturnsTrueForLowestAction() public {
        _pause(hookSource, _bitmap(0));

        assertTrue(pauseHookReceiver.isPaused(hookSource, 0));
    }

    function test_isPaused_ReturnsTrueForHighestAction() public {
        _pause(hookSource, _bitmap(type(uint8).max));

        assertTrue(pauseHookReceiver.isPaused(hookSource, type(uint8).max));
    }

    // supportsInterface()

    function test_supportsInterface_HookReceiver_ReturnsTrue() public view {
        assertTrue(pauseHookReceiver.supportsInterface(type(IHookReceiver).interfaceId));
    }

    function test_supportsInterface_Versioned_ReturnsTrue() public view {
        assertTrue(pauseHookReceiver.supportsInterface(type(IVersioned).interfaceId));
    }

    function test_supportsInterface_ERC165_ReturnsTrue() public view {
        assertTrue(pauseHookReceiver.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_AccessControl_ReturnsTrue() public view {
        assertTrue(pauseHookReceiver.supportsInterface(type(IAccessControl).interfaceId));
    }

    function test_supportsInterface_AccessControlEnumerable_ReturnsTrue() public view {
        assertTrue(pauseHookReceiver.supportsInterface(type(IAccessControlEnumerable).interfaceId));
    }

    function test_supportsInterface_Unknown_ReturnsFalse() public view {
        assertFalse(pauseHookReceiver.supportsInterface(bytes4(0xffffffff)));
        assertFalse(pauseHookReceiver.supportsInterface(bytes4(0xdeadbeef)));
    }

    function _pause(address hookSource_, uint256 actions) internal {
        vm.prank(pauseConfigurator);
        pauseHookReceiver.pause(hookSource_, actions);
    }

    function _clone() internal returns (PauseHookReceiver) {
        return PauseHookReceiver(Clones.clone(address(implementation)));
    }

    function _pauseConfigurators() internal view returns (address[] memory pauseConfigurators) {
        pauseConfigurators = new address[](2);
        pauseConfigurators[0] = pauseConfigurator;
        pauseConfigurators[1] = secondPauseConfigurator;
    }

    function _bitmap(uint8 action) internal pure returns (uint256) {
        return uint256(1) << action;
    }

    function _bitmap(uint8 firstAction, uint8 secondAction) internal pure returns (uint256) {
        return _bitmap(firstAction) | _bitmap(secondAction);
    }

    function _bitmap(uint8 firstAction, uint8 secondAction, uint8 thirdAction) internal pure returns (uint256) {
        return _bitmap(firstAction, secondAction) | _bitmap(thirdAction);
    }
}
