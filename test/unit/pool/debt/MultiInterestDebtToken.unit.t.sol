// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IAccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {stdError} from "forge-std/StdError.sol";
import {Test} from "forge-std/Test.sol";

import {IVersioned} from "src/interfaces/IVersioned.sol";
import {MathUtils} from "src/lib/MathUtils.sol";
import {MultiInterestDebtToken} from "src/pool/debt/MultiInterestDebtToken.sol";
import {IDebtToken} from "src/pool/debt/interfaces/IDebtToken.sol";
import {IIRM} from "src/pool/irm/interfaces/IIRM.sol";
import {MockIrm} from "../irm/mocks/MockIrm.sol";
import {MultiInterestDebtTokenHarness} from "./mocks/MultiInterestDebtTokenHarness.sol";

contract MultiInterestDebtTokenUnitTest is Test {
    MultiInterestDebtTokenHarness implementation;
    MultiInterestDebtTokenHarness debtToken;
    MockIrm firstIrm;
    MockIrm secondIrm;
    MockIrm thirdIrm;
    MockIrm fourthIrm;
    MockIrm[] irms;

    address pool = makeAddr("pool");
    address defaultAdmin = makeAddr("defaultAdmin");
    address irmUpdater = makeAddr("irmUpdater");
    address nonIrmUpdater = makeAddr("nonIrmUpdater");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    string constant NAME = "dOnlend USD Coin";
    string constant SYMBOL = "dOnlend USDC";
    // Deliberately not eighteen, so a decimals getter falling back to the ERC-20 default would be visible.
    uint8 constant DECIMALS = 6;

    uint256 constant AMOUNT = 1000e18;
    uint256 constant IDLE_LIQUIDITY = 5000e18;
    uint256 constant BORROW_RATE = 0.1e18;
    uint256 constant RETENTION_RATE = 0.2e18;
    // Borrow rate whose truncated per-second rate is exactly 1%, so a single second of accrual multiplies the borrow
    // index by exactly 1.01 and the debt and retention it produces are round numbers rather than compounded ones.
    uint256 constant ONE_PERCENT_PER_SECOND_BORROW_RATE = 0.01e18 * 365 days;

    function setUp() public {
        implementation = new MultiInterestDebtTokenHarness();
        debtToken = _deployDebtToken(defaultAdmin, irmUpdater);
        firstIrm = new MockIrm(true, 0, 0);
        secondIrm = new MockIrm(true, 0, 0);
        thirdIrm = new MockIrm(true, 0, 0);
        fourthIrm = new MockIrm(true, 0, 0);
    }

    // initialize()

    function test_initialize_GrantsDefaultAdminAndIrmUpdaterRoles() public view {
        assertTrue(debtToken.hasRole(debtToken.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertTrue(debtToken.hasRole(debtToken.IRM_UPDATER_ROLE(), irmUpdater));
    }

    function test_initialize_SetsDecimals() public view {
        assertEq(debtToken.decimals(), DECIMALS);
    }

    function test_initialize_UsesDefaultAdminAsRoleAdmin() public view {
        assertEq(debtToken.getRoleAdmin(debtToken.IRM_UPDATER_ROLE()), debtToken.DEFAULT_ADMIN_ROLE());
    }

    function test_initialize_SetsLastUpdateTsToInitializationTimestamp() public {
        vm.warp(100 days);

        MultiInterestDebtTokenHarness newDebtToken = _deployDebtToken(defaultAdmin, irmUpdater);

        assertEq(newDebtToken.lastUpdateTs(), 100 days);
    }

    function test_initialize_AllowsZeroAddressRoleMembers() public {
        MultiInterestDebtTokenHarness rolelessDebtToken = _deployDebtToken(address(0), address(0));

        assertEq(rolelessDebtToken.getRoleMemberCount(rolelessDebtToken.DEFAULT_ADMIN_ROLE()), 0);
        assertEq(rolelessDebtToken.getRoleMemberCount(rolelessDebtToken.IRM_UPDATER_ROLE()), 0);
    }

    function test_initialize_AllowsEmptyInitialIrms() public view {
        assertEq(debtToken.getActiveIrmIds(), new address[](0));
        assertEq(debtToken.getSupportedIrmIds(), new address[](0));
    }

    function test_initialize_AddsInitialIrmsInPriorityOrder() public {
        MockIrm initialFirstIrm = new MockIrm(true, 0, 0);
        MockIrm initialSecondIrm = new MockIrm(true, 0, 0);
        address[] memory initialIrmIds = _irmIds(address(initialFirstIrm), address(initialSecondIrm));

        MultiInterestDebtTokenHarness initializedDebtToken = _deployDebtToken(defaultAdmin, irmUpdater, initialIrmIds);

        assertEq(initializedDebtToken.getActiveIrmIds(), initialIrmIds);
        assertEq(initializedDebtToken.getSupportedIrmIds(), initialIrmIds);
    }

    // addIrm()

    function test_addIrm_AddsFirstIrm() public {
        _addIrm(firstIrm, 0);

        assertEq(debtToken.getActiveIrmIds(), _irmIds(address(firstIrm)));
        assertEq(debtToken.getDeprecatedIrmIds(), new address[](0));
        assertEq(debtToken.getSupportedIrmIds(), _irmIds(address(firstIrm)));
    }

    function test_addIrm_InsertsIrmAtEnd() public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);

        assertEq(debtToken.getActiveIrmIds(), _irmIds(address(firstIrm), address(secondIrm)));
        assertEq(debtToken.getDeprecatedIrmIds(), new address[](0));
        assertEq(debtToken.getSupportedIrmIds(), _irmIds(address(firstIrm), address(secondIrm)));
    }

    function test_addIrm_InsertsIrmAtBeginning() public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 0);

        assertEq(debtToken.getActiveIrmIds(), _irmIds(address(secondIrm), address(firstIrm)));
        assertEq(debtToken.getDeprecatedIrmIds(), new address[](0));
        assertEq(debtToken.getSupportedIrmIds(), _irmIds(address(firstIrm), address(secondIrm)));
    }

    function test_addIrm_InsertsIrmInMiddle() public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        _addIrm(thirdIrm, 1);

        assertEq(debtToken.getActiveIrmIds(), _irmIds(address(firstIrm), address(thirdIrm), address(secondIrm)));
        assertEq(debtToken.getDeprecatedIrmIds(), new address[](0));
        assertEq(debtToken.getSupportedIrmIds(), _irmIds(address(firstIrm), address(secondIrm), address(thirdIrm)));
    }

    function test_addIrm_InsertsIrmAmongActiveIrmsWhenDeprecatedIrmsExist() public {
        _addThreeIrms();
        MockIrm newIrm = new MockIrm(true, 0, 0);

        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(secondIrm));

        vm.prank(irmUpdater);
        debtToken.addIrm(address(newIrm), 1);

        assertEq(debtToken.getActiveIrmIds(), _irmIds(address(firstIrm), address(newIrm), address(thirdIrm)));
        assertEq(debtToken.getDeprecatedIrmIds(), _irmIds(address(secondIrm)));
        assertEq(
            debtToken.getSupportedIrmIds(),
            _irmIds(address(firstIrm), address(secondIrm), address(thirdIrm), address(newIrm))
        );
    }

    function test_addIrm_AppendsIrmToActiveIrmsWhenDeprecatedIrmsExist() public {
        _addThreeIrms();
        MockIrm newIrm = new MockIrm(true, 0, 0);

        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(secondIrm));

        vm.prank(irmUpdater);
        debtToken.addIrm(address(newIrm), 2);

        assertEq(debtToken.getActiveIrmIds(), _irmIds(address(firstIrm), address(thirdIrm), address(newIrm)));
        assertEq(debtToken.getDeprecatedIrmIds(), _irmIds(address(secondIrm)));
        assertEq(
            debtToken.getSupportedIrmIds(),
            _irmIds(address(firstIrm), address(secondIrm), address(thirdIrm), address(newIrm))
        );
    }

    function test_addIrm_InitializesIrmData() public {
        _addIrm(firstIrm, 0);

        MultiInterestDebtToken.IrmData memory irmData = debtToken.getIrmData(address(firstIrm));

        assertEq(uint8(irmData.status), uint8(MultiInterestDebtToken.IrmStatus.ACTIVE));
        assertEq(irmData.storedBorrowIndex, MathUtils.ONE_18_DP);
        assertEq(irmData.borrowRate, 0);
        assertEq(irmData.retentionRate, 0);
        assertEq(irmData.totalScaledDebt, 0);
    }

    function test_addIrm_EmitsIrmAdded() public {
        _addIrm(firstIrm, 0);

        vm.expectEmit();
        emit MultiInterestDebtToken.IrmAdded(address(secondIrm), 1);

        vm.prank(irmUpdater);
        debtToken.addIrm(address(secondIrm), 1);
    }

    function test_addIrm_RevertsWhenCallerIsNotIrmUpdater() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonIrmUpdater, debtToken.IRM_UPDATER_ROLE()
            )
        );
        vm.prank(nonIrmUpdater);
        debtToken.addIrm(address(firstIrm), 0);
    }

    function test_addIrm_RevertsWhenIrmIsInvalid() public {
        address invalidIrm = makeAddr("invalidIrm");

        vm.expectRevert(abi.encodeWithSelector(MultiInterestDebtToken.InvalidIrm.selector, invalidIrm));
        vm.prank(irmUpdater);
        debtToken.addIrm(invalidIrm, 0);
    }

    function test_addIrm_RevertsWhenIrmIsAlreadyAdded() public {
        _addIrm(firstIrm, 0);

        vm.expectRevert(abi.encodeWithSelector(MultiInterestDebtToken.IrmAlreadyAdded.selector, address(firstIrm)));
        vm.prank(irmUpdater);
        debtToken.addIrm(address(firstIrm), 0);
    }

    function test_addIrm_RevertsWhenIrmIsAlreadyDeprecated() public {
        _addIrm(firstIrm, 0);

        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(firstIrm));

        vm.expectRevert(abi.encodeWithSelector(MultiInterestDebtToken.IrmAlreadyAdded.selector, address(firstIrm)));
        vm.prank(irmUpdater);
        debtToken.addIrm(address(firstIrm), 0);
    }

    function test_addIrm_RevertsWhenPriorityIsGreaterThanActiveIrmCount() public {
        _addThreeIrms();
        MockIrm newIrm = new MockIrm(true, 0, 0);

        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(secondIrm));

        vm.expectRevert(abi.encodeWithSelector(MultiInterestDebtToken.InvalidIrmPriority.selector, 3));
        vm.prank(irmUpdater);
        debtToken.addIrm(address(newIrm), 3);
    }

    function test_addIrm_RevertsWhenMaxActiveIrmsReached() public {
        _addIrms(uint8(debtToken.MAX_ACTIVE_IRMS()));

        MockIrm extraIrm = new MockIrm(true, 0, 0);

        assertEq(debtToken.getActiveIrmIds().length, debtToken.MAX_ACTIVE_IRMS());
        assertEq(debtToken.getDeprecatedIrmIds().length, 0);
        assertEq(debtToken.getSupportedIrmIds().length, debtToken.MAX_ACTIVE_IRMS());

        vm.expectRevert(MultiInterestDebtToken.MaxActiveIrmsReached.selector);
        vm.prank(irmUpdater);
        debtToken.addIrm(address(extraIrm), 0);
    }

    function test_addIrm_AllowsAddingWhenActiveSlotsRemainDespiteDeprecatedIrms() public {
        _addIrms(uint8(debtToken.MAX_ACTIVE_IRMS()));
        MockIrm extraIrm = new MockIrm(true, 0, 0);
        uint8 priority = uint8(debtToken.MAX_ACTIVE_IRMS() - 1);

        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(irms[0]));

        vm.prank(irmUpdater);
        debtToken.addIrm(address(extraIrm), priority);

        assertEq(debtToken.getActiveIrmIds().length, debtToken.MAX_ACTIVE_IRMS());
        assertEq(debtToken.getActiveIrmIds()[priority], address(extraIrm));
        assertEq(debtToken.getDeprecatedIrmIds(), _irmIds(address(irms[0])));
        assertEq(debtToken.getSupportedIrmIds().length, debtToken.MAX_ACTIVE_IRMS() + 1);
        assertEq(debtToken.getSupportedIrmIds()[debtToken.MAX_ACTIVE_IRMS()], address(extraIrm));
    }

    function test_addIrm_RevertsWhenMaxSupportedIrmsReachedIncludingDeprecatedIrms() public {
        _addDeprecatedIrms(uint8(debtToken.MAX_SUPPORTED_IRMS() - debtToken.MAX_ACTIVE_IRMS() + 1));
        _addIrms(uint8(debtToken.MAX_ACTIVE_IRMS() - 1));

        MockIrm extraIrm = new MockIrm(true, 0, 0);

        assertEq(debtToken.getActiveIrmIds().length, debtToken.MAX_ACTIVE_IRMS() - 1);
        assertEq(
            debtToken.getDeprecatedIrmIds().length, debtToken.MAX_SUPPORTED_IRMS() - debtToken.MAX_ACTIVE_IRMS() + 1
        );
        assertEq(debtToken.getSupportedIrmIds().length, debtToken.MAX_SUPPORTED_IRMS());

        vm.expectRevert(MultiInterestDebtToken.MaxSupportedIrmsReached.selector);
        vm.prank(irmUpdater);
        debtToken.addIrm(address(extraIrm), 0);
    }

    // deprecateIrm()

    function test_deprecateIrm_MovesFirstActiveIrmToDeprecatedIrms() public {
        _addThreeIrms();

        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(firstIrm));

        assertEq(debtToken.getActiveIrmIds(), _irmIds(address(secondIrm), address(thirdIrm)));
        assertEq(debtToken.getDeprecatedIrmIds(), _irmIds(address(firstIrm)));
        assertEq(debtToken.getSupportedIrmIds(), _irmIds(address(firstIrm), address(secondIrm), address(thirdIrm)));
    }

    function test_deprecateIrm_MovesMiddleActiveIrmToDeprecatedIrms() public {
        _addThreeIrms();

        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(secondIrm));

        assertEq(debtToken.getActiveIrmIds(), _irmIds(address(firstIrm), address(thirdIrm)));
        assertEq(debtToken.getDeprecatedIrmIds(), _irmIds(address(secondIrm)));
        assertEq(debtToken.getSupportedIrmIds(), _irmIds(address(firstIrm), address(secondIrm), address(thirdIrm)));
    }

    function test_deprecateIrm_MovesLastActiveIrmToDeprecatedIrms() public {
        _addThreeIrms();

        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(thirdIrm));

        assertEq(debtToken.getActiveIrmIds(), _irmIds(address(firstIrm), address(secondIrm)));
        assertEq(debtToken.getDeprecatedIrmIds(), _irmIds(address(thirdIrm)));
        assertEq(debtToken.getSupportedIrmIds(), _irmIds(address(firstIrm), address(secondIrm), address(thirdIrm)));
    }

    function test_deprecateIrm_SetsStatusDeprecatedAndKeepsIrmAccountingData() public {
        _addAccruingIrm(firstIrm);
        debtToken.setIrmStoredBorrowIndex(address(firstIrm), 2e18);
        MultiInterestDebtToken.IrmData memory expectedIrmData = debtToken.getIrmData(address(firstIrm));
        expectedIrmData.status = MultiInterestDebtToken.IrmStatus.DEPRECATED;

        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(firstIrm));

        assertEq(abi.encode(debtToken.getIrmData(address(firstIrm))), abi.encode(expectedIrmData));
    }

    function test_deprecateIrm_EmitsIrmDeprecated() public {
        _addIrm(firstIrm, 0);

        vm.expectEmit();
        emit MultiInterestDebtToken.IrmDeprecated(address(firstIrm));

        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(firstIrm));
    }

    function test_deprecateIrm_RevertsWhenCallerIsNotIrmUpdater() public {
        _addIrm(firstIrm, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonIrmUpdater, debtToken.IRM_UPDATER_ROLE()
            )
        );
        vm.prank(nonIrmUpdater);
        debtToken.deprecateIrm(address(firstIrm));
    }

    function test_deprecateIrm_RevertsWhenIrmIsNotSupported() public {
        vm.expectRevert(abi.encodeWithSelector(MultiInterestDebtToken.IrmNotSupported.selector, address(firstIrm)));
        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(firstIrm));
    }

    function test_deprecateIrm_RevertsWhenIrmIsAlreadyDeprecated() public {
        _addIrm(firstIrm, 0);

        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(firstIrm));

        vm.expectRevert(abi.encodeWithSelector(MultiInterestDebtToken.IrmNotActive.selector, address(firstIrm)));
        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(firstIrm));
    }

    function test_deprecateIrm_AllowsUndeprecatedIrmToBeDeprecatedAgain() public {
        _addThreeIrms();

        vm.startPrank(irmUpdater);
        debtToken.deprecateIrm(address(secondIrm));
        debtToken.undeprecateIrm(address(secondIrm), 1);
        debtToken.deprecateIrm(address(secondIrm));
        vm.stopPrank();

        assertEq(debtToken.getDeprecatedIrmIds(), _irmIds(address(secondIrm)));
        assertEq(
            uint8(debtToken.getIrmData(address(secondIrm)).status), uint8(MultiInterestDebtToken.IrmStatus.DEPRECATED)
        );
    }

    // undeprecateIrm()

    function test_undeprecateIrm_MovesDeprecatedIrmToActiveAtBeginning() public {
        _addThreeIrms();

        vm.startPrank(irmUpdater);
        debtToken.deprecateIrm(address(secondIrm));
        debtToken.undeprecateIrm(address(secondIrm), 0);
        vm.stopPrank();

        assertEq(debtToken.getActiveIrmIds(), _irmIds(address(secondIrm), address(firstIrm), address(thirdIrm)));
        assertEq(debtToken.getDeprecatedIrmIds(), new address[](0));
        assertEq(debtToken.getSupportedIrmIds(), _irmIds(address(firstIrm), address(secondIrm), address(thirdIrm)));
    }

    function test_undeprecateIrm_MovesDeprecatedIrmToActiveInMiddle() public {
        _addThreeIrms();

        vm.startPrank(irmUpdater);
        debtToken.deprecateIrm(address(secondIrm));
        debtToken.undeprecateIrm(address(secondIrm), 1);
        vm.stopPrank();

        assertEq(debtToken.getActiveIrmIds(), _irmIds(address(firstIrm), address(secondIrm), address(thirdIrm)));
        assertEq(debtToken.getDeprecatedIrmIds(), new address[](0));
        assertEq(debtToken.getSupportedIrmIds(), _irmIds(address(firstIrm), address(secondIrm), address(thirdIrm)));
    }

    function test_undeprecateIrm_MovesDeprecatedIrmToActiveAtEnd() public {
        _addThreeIrms();

        vm.startPrank(irmUpdater);
        debtToken.deprecateIrm(address(secondIrm));
        debtToken.undeprecateIrm(address(secondIrm), 2);
        vm.stopPrank();

        assertEq(debtToken.getActiveIrmIds(), _irmIds(address(firstIrm), address(thirdIrm), address(secondIrm)));
        assertEq(debtToken.getDeprecatedIrmIds(), new address[](0));
        assertEq(debtToken.getSupportedIrmIds(), _irmIds(address(firstIrm), address(secondIrm), address(thirdIrm)));
    }

    function test_undeprecateIrm_KeepsOtherDeprecatedIrmsUnchanged() public {
        _addThreeIrms();

        vm.startPrank(irmUpdater);
        debtToken.deprecateIrm(address(firstIrm));
        debtToken.deprecateIrm(address(secondIrm));
        debtToken.deprecateIrm(address(thirdIrm));
        debtToken.undeprecateIrm(address(secondIrm), 0);
        vm.stopPrank();

        assertEq(debtToken.getActiveIrmIds(), _irmIds(address(secondIrm)));
        assertEq(debtToken.getDeprecatedIrmIds(), _irmIds(address(firstIrm), address(thirdIrm)));
        assertEq(debtToken.getSupportedIrmIds(), _irmIds(address(firstIrm), address(secondIrm), address(thirdIrm)));
    }

    function test_undeprecateIrm_MovesLastDeprecatedIrmToActive() public {
        _addThreeIrms();

        vm.startPrank(irmUpdater);
        debtToken.deprecateIrm(address(firstIrm));
        debtToken.deprecateIrm(address(secondIrm));
        debtToken.deprecateIrm(address(thirdIrm));
        debtToken.undeprecateIrm(address(thirdIrm), 0);
        vm.stopPrank();

        assertEq(debtToken.getActiveIrmIds(), _irmIds(address(thirdIrm)));
        assertEq(debtToken.getDeprecatedIrmIds(), _irmIds(address(firstIrm), address(secondIrm)));
        assertEq(debtToken.getSupportedIrmIds(), _irmIds(address(firstIrm), address(secondIrm), address(thirdIrm)));
    }

    function test_undeprecateIrm_AllowsUndeprecatingAfterAddingNewIrm() public {
        _addThreeIrms();
        MockIrm newIrm = new MockIrm(true, 0, 0);

        vm.startPrank(irmUpdater);
        debtToken.deprecateIrm(address(secondIrm));
        debtToken.addIrm(address(newIrm), 1);
        debtToken.undeprecateIrm(address(secondIrm), 2);
        vm.stopPrank();

        assertEq(
            debtToken.getActiveIrmIds(),
            _irmIds(address(firstIrm), address(newIrm), address(secondIrm), address(thirdIrm))
        );
        assertEq(debtToken.getDeprecatedIrmIds(), new address[](0));
        assertEq(
            debtToken.getSupportedIrmIds(),
            _irmIds(address(firstIrm), address(secondIrm), address(thirdIrm), address(newIrm))
        );
    }

    function test_undeprecateIrm_SetsStatusActiveAndKeepsIrmAccountingData() public {
        _addAccruingIrm(firstIrm);
        debtToken.setIrmStoredBorrowIndex(address(firstIrm), 2e18);
        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(firstIrm));
        MultiInterestDebtToken.IrmData memory expectedIrmData = debtToken.getIrmData(address(firstIrm));
        expectedIrmData.status = MultiInterestDebtToken.IrmStatus.ACTIVE;

        vm.prank(irmUpdater);
        debtToken.undeprecateIrm(address(firstIrm), 0);

        assertEq(abi.encode(debtToken.getIrmData(address(firstIrm))), abi.encode(expectedIrmData));
    }

    function test_undeprecateIrm_EmitsIrmUndeprecated() public {
        _addThreeIrms();

        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(secondIrm));

        vm.expectEmit();
        emit MultiInterestDebtToken.IrmUndeprecated(address(secondIrm), 1);

        vm.prank(irmUpdater);
        debtToken.undeprecateIrm(address(secondIrm), 1);
    }

    function test_undeprecateIrm_RevertsWhenCallerIsNotIrmUpdater() public {
        _addIrm(firstIrm, 0);

        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(firstIrm));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonIrmUpdater, debtToken.IRM_UPDATER_ROLE()
            )
        );
        vm.prank(nonIrmUpdater);
        debtToken.undeprecateIrm(address(firstIrm), 0);
    }

    function test_undeprecateIrm_RevertsWhenIrmIsNotSupported() public {
        vm.expectRevert(abi.encodeWithSelector(MultiInterestDebtToken.IrmNotSupported.selector, address(firstIrm)));
        vm.prank(irmUpdater);
        debtToken.undeprecateIrm(address(firstIrm), 0);
    }

    function test_undeprecateIrm_RevertsWhenIrmIsActive() public {
        _addIrm(firstIrm, 0);

        vm.expectRevert(abi.encodeWithSelector(MultiInterestDebtToken.IrmNotDeprecated.selector, address(firstIrm)));
        vm.prank(irmUpdater);
        debtToken.undeprecateIrm(address(firstIrm), 0);
    }

    function test_undeprecateIrm_RevertsWhenPriorityIsGreaterThanActiveIrmCount() public {
        _addIrm(firstIrm, 0);

        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(firstIrm));

        vm.expectRevert(abi.encodeWithSelector(MultiInterestDebtToken.InvalidIrmPriority.selector, 1));
        vm.prank(irmUpdater);
        debtToken.undeprecateIrm(address(firstIrm), 1);
    }

    function test_undeprecateIrm_RevertsWhenMaxActiveIrmsReached() public {
        _addIrm(firstIrm, 0);

        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(firstIrm));

        _addIrms(uint8(debtToken.MAX_ACTIVE_IRMS()));

        vm.expectRevert(MultiInterestDebtToken.MaxActiveIrmsReached.selector);
        vm.prank(irmUpdater);
        debtToken.undeprecateIrm(address(firstIrm), 0);
    }

    // removeIrm()

    function test_removeIrm_RemovesActiveIrm() public {
        _addThreeIrms();

        vm.prank(irmUpdater);
        debtToken.removeIrm(address(secondIrm));

        assertEq(debtToken.getActiveIrmIds(), _irmIds(address(firstIrm), address(thirdIrm)));
        assertEq(debtToken.getDeprecatedIrmIds(), new address[](0));
        assertEq(debtToken.getSupportedIrmIds(), _irmIds(address(firstIrm), address(thirdIrm)));
    }

    function test_removeIrm_RemovesDeprecatedIrm() public {
        _addThreeIrms();
        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(secondIrm));

        vm.prank(irmUpdater);
        debtToken.removeIrm(address(secondIrm));

        assertEq(debtToken.getActiveIrmIds(), _irmIds(address(firstIrm), address(thirdIrm)));
        assertEq(debtToken.getDeprecatedIrmIds(), new address[](0));
        assertEq(debtToken.getSupportedIrmIds(), _irmIds(address(firstIrm), address(thirdIrm)));
    }

    function test_removeIrm_DeletesIrmAccountingData() public {
        _addIrm(firstIrm, 0);
        debtToken.setIrmStoredBorrowIndex(address(firstIrm), 2e18);
        _setIrmRates(firstIrm, BORROW_RATE, RETENTION_RATE);
        MultiInterestDebtToken.IrmData memory emptyIrmData;

        vm.prank(irmUpdater);
        debtToken.removeIrm(address(firstIrm));

        assertEq(abi.encode(debtToken.getIrmData(address(firstIrm))), abi.encode(emptyIrmData));
    }

    function test_removeIrm_EmitsIrmRemoved() public {
        _addIrm(firstIrm, 0);

        vm.expectEmit();
        emit MultiInterestDebtToken.IrmRemoved(address(firstIrm));

        vm.prank(irmUpdater);
        debtToken.removeIrm(address(firstIrm));
    }

    function test_removeIrm_UnblocksBorrowRateUpdatesWhenIrmReverts() public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        debtToken.setLastUpdateTs(block.timestamp);
        // Replace the IRM's code with `PUSH1 0 PUSH1 0 REVERT`, so that every call to it reverts.
        vm.etch(address(secondIrm), hex"60006000fd");
        vm.expectRevert(bytes(""));
        vm.prank(pool);
        debtToken.updateBorrowRates(IDLE_LIQUIDITY);

        vm.prank(irmUpdater);
        debtToken.removeIrm(address(secondIrm));

        vm.prank(pool);
        debtToken.updateBorrowRates(IDLE_LIQUIDITY);
    }

    function test_removeIrm_RevertsWhenCallerIsNotIrmUpdater() public {
        _addIrm(firstIrm, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonIrmUpdater, debtToken.IRM_UPDATER_ROLE()
            )
        );
        vm.prank(nonIrmUpdater);
        debtToken.removeIrm(address(firstIrm));
    }

    function test_removeIrm_RevertsWhenIrmIsNotSupported() public {
        vm.expectRevert(abi.encodeWithSelector(MultiInterestDebtToken.IrmNotSupported.selector, address(firstIrm)));
        vm.prank(irmUpdater);
        debtToken.removeIrm(address(firstIrm));
    }

    function test_removeIrm_RevertsWhenIrmHasDebt() public {
        _addIrm(firstIrm, 0);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), 1);

        vm.expectRevert(abi.encodeWithSelector(MultiInterestDebtToken.IrmHasDebt.selector, address(firstIrm)));
        vm.prank(irmUpdater);
        debtToken.removeIrm(address(firstIrm));
    }

    // setIrmPriorities()

    function test_setIrmPriorities_ReordersActiveIrms() public {
        _addThreeIrms();

        vm.prank(irmUpdater);
        debtToken.setIrmPriorities(_irmIds(address(thirdIrm), address(firstIrm), address(secondIrm)));

        assertEq(debtToken.getActiveIrmIds(), _irmIds(address(thirdIrm), address(firstIrm), address(secondIrm)));
        assertEq(debtToken.getDeprecatedIrmIds(), new address[](0));
        assertEq(debtToken.getSupportedIrmIds(), _irmIds(address(firstIrm), address(secondIrm), address(thirdIrm)));
    }

    function test_setIrmPriorities_AllowsEmptyPrioritiesWhenNoIrmsAreActive() public {
        address[] memory newPriorities = new address[](0);

        vm.prank(irmUpdater);
        debtToken.setIrmPriorities(newPriorities);

        assertEq(debtToken.getActiveIrmIds(), newPriorities);
        assertEq(debtToken.getDeprecatedIrmIds(), newPriorities);
        assertEq(debtToken.getSupportedIrmIds(), newPriorities);
    }

    function test_setIrmPriorities_AllowsEmptyPrioritiesWhenAllIrmsAreDeprecated() public {
        _addThreeIrms();
        address[] memory newPriorities = new address[](0);

        vm.startPrank(irmUpdater);
        debtToken.deprecateIrm(address(firstIrm));
        debtToken.deprecateIrm(address(secondIrm));
        debtToken.deprecateIrm(address(thirdIrm));
        debtToken.setIrmPriorities(newPriorities);
        vm.stopPrank();

        assertEq(debtToken.getActiveIrmIds(), newPriorities);
        assertEq(debtToken.getDeprecatedIrmIds(), _irmIds(address(firstIrm), address(secondIrm), address(thirdIrm)));
        assertEq(debtToken.getSupportedIrmIds(), _irmIds(address(firstIrm), address(secondIrm), address(thirdIrm)));
    }

    function test_setIrmPriorities_KeepsDeprecatedIrmsUnchanged() public {
        _addThreeIrms();

        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(secondIrm));

        vm.prank(irmUpdater);
        debtToken.setIrmPriorities(_irmIds(address(thirdIrm), address(firstIrm)));

        assertEq(debtToken.getActiveIrmIds(), _irmIds(address(thirdIrm), address(firstIrm)));
        assertEq(debtToken.getDeprecatedIrmIds(), _irmIds(address(secondIrm)));
        assertEq(debtToken.getSupportedIrmIds(), _irmIds(address(firstIrm), address(secondIrm), address(thirdIrm)));
    }

    function test_setIrmPriorities_EmitsIrmPrioritiesUpdated() public {
        _addThreeIrms();
        address[] memory newPriorities = _irmIds(address(thirdIrm), address(firstIrm), address(secondIrm));

        vm.expectEmit();
        emit MultiInterestDebtToken.IrmPrioritiesUpdated(newPriorities);

        vm.prank(irmUpdater);
        debtToken.setIrmPriorities(newPriorities);
    }

    function test_setIrmPriorities_RevertsWhenCallerIsNotIrmUpdater() public {
        _addThreeIrms();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonIrmUpdater, debtToken.IRM_UPDATER_ROLE()
            )
        );
        vm.prank(nonIrmUpdater);
        debtToken.setIrmPriorities(_irmIds(address(thirdIrm), address(firstIrm), address(secondIrm)));
    }

    function test_setIrmPriorities_RevertsWhenLengthIsTooShort() public {
        _addThreeIrms();

        vm.expectRevert(abi.encodeWithSelector(MultiInterestDebtToken.InvalidIrmPrioritiesLength.selector, 2, 3));
        vm.prank(irmUpdater);
        debtToken.setIrmPriorities(_irmIds(address(firstIrm), address(secondIrm)));
    }

    function test_setIrmPriorities_RevertsWhenLengthIsTooLong() public {
        _addThreeIrms();
        MockIrm extraIrm = new MockIrm(true, 0, 0);

        vm.expectRevert(abi.encodeWithSelector(MultiInterestDebtToken.InvalidIrmPrioritiesLength.selector, 4, 3));
        vm.prank(irmUpdater);
        debtToken.setIrmPriorities(_irmIds(address(firstIrm), address(secondIrm), address(thirdIrm), address(extraIrm)));
    }

    function test_setIrmPriorities_RevertsWhenIrmIsNotSupported() public {
        _addThreeIrms();
        address missingIrm = makeAddr("missingIrm");

        vm.expectRevert(abi.encodeWithSelector(MultiInterestDebtToken.IrmNotActive.selector, missingIrm));
        vm.prank(irmUpdater);
        debtToken.setIrmPriorities(_irmIds(address(firstIrm), missingIrm, address(thirdIrm)));
    }

    function test_setIrmPriorities_RevertsWhenIrmIsDeprecated() public {
        _addThreeIrms();

        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(secondIrm));

        vm.expectRevert(abi.encodeWithSelector(MultiInterestDebtToken.IrmNotActive.selector, address(secondIrm)));
        vm.prank(irmUpdater);
        debtToken.setIrmPriorities(_irmIds(address(firstIrm), address(secondIrm)));
    }

    function test_setIrmPriorities_RevertsWhenIrmIsDuplicated() public {
        _addThreeIrms();

        vm.expectRevert(abi.encodeWithSelector(MultiInterestDebtToken.DuplicateIrm.selector, address(firstIrm)));
        vm.prank(irmUpdater);
        debtToken.setIrmPriorities(_irmIds(address(thirdIrm), address(firstIrm), address(firstIrm)));

        assertEq(debtToken.getActiveIrmIds(), _irmIds(address(firstIrm), address(secondIrm), address(thirdIrm)));
        assertEq(debtToken.getDeprecatedIrmIds(), new address[](0));
        assertEq(debtToken.getSupportedIrmIds(), _irmIds(address(firstIrm), address(secondIrm), address(thirdIrm)));
    }

    // lastUpdateTs()

    /// @dev Unlike `pendingInterest`, this reports stored state rather than accruing to the current block.
    function test_lastUpdateTs_DoesNotChangeAsTimePasses() public {
        uint256 lastUpdateTs = 100 days;
        vm.warp(lastUpdateTs);
        debtToken.setLastUpdateTs(lastUpdateTs);

        vm.warp(lastUpdateTs + 30 days);

        assertEq(debtToken.lastUpdateTs(), lastUpdateTs);
    }

    // pendingInterest()

    function test_pendingInterest_ReturnsZeroWhenNoIrmsAreSupported() public view {
        (uint256 accrued, uint256 retained) = debtToken.pendingInterest();

        assertEq(accrued, 0);
        assertEq(retained, 0);
    }

    function test_pendingInterest_DoesNotAccrueWhenBorrowIndexIsSame() public {
        _addIrm(firstIrm, 0);
        _setIrmRates(firstIrm, 0, RETENTION_RATE);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);
        vm.warp(debtToken.lastUpdateTs() + 365 days);

        (uint256 accrued, uint256 retained) = debtToken.pendingInterest();

        assertEq(debtToken.updatedBorrowIndex(address(firstIrm)), MathUtils.ONE_18_DP);
        assertEq(accrued, 0);
        assertEq(retained, 0);
    }

    function test_pendingInterest_DoesNotAccrueWhenDebtIsZero() public {
        _addIrm(firstIrm, 0);
        _setIrmRates(firstIrm, BORROW_RATE, RETENTION_RATE);
        vm.warp(debtToken.lastUpdateTs() + 30 days);

        (uint256 accrued, uint256 retained) = debtToken.pendingInterest();

        assertEq(accrued, 0);
        assertEq(retained, 0);
    }

    function test_pendingInterest_DoesNotRetainWhenRetentionRateIsZero() public {
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        _setIrmRates(firstIrm, ONE_PERCENT_PER_SECOND_BORROW_RATE, 0);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);
        vm.warp(lastUpdateTs + 1 seconds);

        (uint256 accrued, uint256 retained) = debtToken.pendingInterest();

        assertEq(accrued, 10e18);
        assertEq(retained, 0);
    }

    function test_pendingInterest_AccruesInterestAndRetainedAmount() public {
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        _setIrmRates(firstIrm, ONE_PERCENT_PER_SECOND_BORROW_RATE, RETENTION_RATE);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);
        vm.warp(lastUpdateTs + 1 seconds);

        (uint256 accrued, uint256 retained) = debtToken.pendingInterest();

        // 1000e18 of debt accrues 1% over the second, i.e. 10e18 of interest, of which 20% is retained.
        assertEq(accrued, 10e18);
        assertEq(retained, 2e18);
    }

    /// @dev Interest is handed over on accrual rather than accumulated, so what a past period accrued leaves nothing
    ///      behind for the next projection to build on.
    function test_pendingInterest_ExcludesInterestAlreadyAccrued() public {
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        _setIrmRates(firstIrm, ONE_PERCENT_PER_SECOND_BORROW_RATE, RETENTION_RATE);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);
        vm.warp(lastUpdateTs + 1 seconds);
        vm.prank(pool);
        debtToken.accrueInterest();
        vm.warp(lastUpdateTs + 2 seconds);

        (uint256 accrued, uint256 retained) = debtToken.pendingInterest();

        // The index is now 1.01, so the second second accrues 10.1e18 of interest and retains 20% of that alone.
        assertEq(accrued, 10.1e18);
        assertEq(retained, 2.02e18);
    }

    function test_pendingInterest_SumsAcrossActiveAndDeprecatedIrms() public {
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        _setIrmRates(firstIrm, ONE_PERCENT_PER_SECOND_BORROW_RATE, RETENTION_RATE);
        _setIrmRates(secondIrm, ONE_PERCENT_PER_SECOND_BORROW_RATE, RETENTION_RATE);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);
        debtToken.setIrmTotalScaledDebt(address(secondIrm), AMOUNT * 2);
        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(firstIrm));
        vm.warp(lastUpdateTs + 1 seconds);

        (uint256 accrued, uint256 retained) = debtToken.pendingInterest();

        // First IRM accrues 10e18 and retains 2e18; second IRM accrues 20e18 and retains 4e18.
        assertEq(accrued, 30e18);
        assertEq(retained, 6e18);
    }

    /// @dev Complements the sum above: an IRM with rates but no debt is skipped rather than contributing, so the total
    ///      is what the one funded IRM accrued.
    function test_pendingInterest_ExcludesSupportedIrmsWithoutDebt() public {
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        _setIrmRates(firstIrm, ONE_PERCENT_PER_SECOND_BORROW_RATE, RETENTION_RATE);
        _setIrmRates(secondIrm, ONE_PERCENT_PER_SECOND_BORROW_RATE, RETENTION_RATE);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);
        vm.warp(lastUpdateTs + 1 seconds);

        (uint256 accrued, uint256 retained) = debtToken.pendingInterest();

        // Only `firstIrm` carries debt, so the totals are the 10e18 it alone accrues and the 2e18 it retains.
        assertEq(accrued, 10e18);
        assertEq(retained, 2e18);
    }

    // annualInterest()

    function test_annualInterest_ReturnsInterestAndRetainedPart() public {
        _addIrm(firstIrm, 0);
        _setIrmRates(firstIrm, BORROW_RATE, RETENTION_RATE);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);

        (uint256 interest, uint256 retained) = debtToken.annualInterest();

        // 1000e18 debt * 10% borrow rate = 100e18, of which 20% is retained.
        assertEq(interest, 100e18);
        assertEq(retained, 20e18);
    }

    function test_annualInterest_ReturnsZeroWhenNoIrmsAreSupported() public view {
        (uint256 interest, uint256 retained) = debtToken.annualInterest();

        assertEq(interest, 0);
        assertEq(retained, 0);
    }

    function test_annualInterest_ReturnsZeroWhenNoDebt() public {
        _addIrm(firstIrm, 0);
        _setIrmRates(firstIrm, BORROW_RATE, RETENTION_RATE);

        (uint256 interest, uint256 retained) = debtToken.annualInterest();

        assertEq(interest, 0);
        assertEq(retained, 0);
    }

    function test_annualInterest_ReturnsZeroWhenBorrowRateIsZero() public {
        _addIrm(firstIrm, 0);
        _setIrmRates(firstIrm, 0, RETENTION_RATE);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);

        (uint256 interest, uint256 retained) = debtToken.annualInterest();

        assertEq(interest, 0);
        assertEq(retained, 0);
    }

    function test_annualInterest_RetainsAllInterestWhenRetentionRateIsFull() public {
        _addIrm(firstIrm, 0);
        _setIrmRates(firstIrm, BORROW_RATE, MathUtils.ONE_18_DP);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);

        (uint256 interest, uint256 retained) = debtToken.annualInterest();

        assertEq(interest, 100e18);
        assertEq(retained, 100e18);
    }

    function test_annualInterest_SumsAcrossActiveAndDeprecatedIrms() public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        _addIrm(thirdIrm, 2);
        _addIrm(fourthIrm, 3);
        _setIrmRates(firstIrm, 0.1e18, 0.2e18);
        _setIrmRates(secondIrm, 0.3e18, 0.1e18);
        _setIrmRates(thirdIrm, 0.05e18, 0.4e18);
        _setIrmRates(fourthIrm, 0.2e18, 0.25e18);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), 1000e18);
        debtToken.setIrmTotalScaledDebt(address(secondIrm), 2000e18);
        debtToken.setIrmTotalScaledDebt(address(thirdIrm), 3000e18);
        debtToken.setIrmTotalScaledDebt(address(fourthIrm), 4000e18);
        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(firstIrm));
        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(secondIrm));

        (uint256 interest, uint256 retained) = debtToken.annualInterest();

        // Each IRM generates debt * borrowRate, of which retentionRate is retained:
        // deprecated first:  1000e18 * 10% =  100e18, retaining 20% =  20e18
        // deprecated second: 2000e18 * 30% =  600e18, retaining 10% =  60e18
        // active third:      3000e18 *  5% =  150e18, retaining 40% =  60e18
        // active fourth:     4000e18 * 20% =  800e18, retaining 25% = 200e18
        assertEq(interest, 1650e18);
        assertEq(retained, 340e18);
    }

    /// @dev Interest is earned on the debt a bucket actually owes rather than the scaled units behind it, so a doubled
    ///      index doubles the interest the same scaled debt produces.
    function test_annualInterest_PricesDebtStatedAtBorrowIndex() public {
        _addIrm(firstIrm, 0);
        _setIrmRates(firstIrm, BORROW_RATE, RETENTION_RATE);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);
        debtToken.setIrmStoredBorrowIndex(address(firstIrm), 2e18);

        (uint256 interest, uint256 retained) = debtToken.annualInterest();

        // 1000e18 of scaled debt states 2000e18 at the doubled index: 2000e18 * 10% = 200e18, retaining 20%.
        assertEq(interest, 200e18);
        assertEq(retained, 40e18);
    }

    /// @dev Debt is stated at the index the current block would produce rather than the stored one, so interest the
    ///      elapsed period has already earned is priced before anyone accrues it.
    function test_annualInterest_PricesDebtAccruedToCurrentBlock() public {
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        _setIrmRates(firstIrm, ONE_PERCENT_PER_SECOND_BORROW_RATE, RETENTION_RATE);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);
        (uint256 interestBeforeAccrual, uint256 retainedBeforeAccrual) = debtToken.annualInterest();

        vm.warp(lastUpdateTs + 1 seconds);

        // The second grows the 1000e18 of debt by 1% while the rates pricing it stay put, so the interest the 1010e18
        // now generates, and its retained part, are 1% above what the 1000e18 did.
        (uint256 interest, uint256 retained) = debtToken.annualInterest();
        assertEq(interest, (interestBeforeAccrual * 101) / 100);
        assertEq(retained, (retainedBeforeAccrual * 101) / 100);
    }

    /// @dev Accrual folds the projected index into storage without changing what the debt is worth, so the interest
    ///      the view reports is the same on either side of it.
    function test_annualInterest_IsUnchangedByAccruingInterest() public {
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        _setIrmRates(firstIrm, ONE_PERCENT_PER_SECOND_BORROW_RATE, RETENTION_RATE);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);
        vm.warp(lastUpdateTs + 1 seconds);
        (uint256 interestBeforeAccrual, uint256 retainedBeforeAccrual) = debtToken.annualInterest();

        vm.prank(pool);
        debtToken.accrueInterest();

        (uint256 interest, uint256 retained) = debtToken.annualInterest();
        assertEq(interest, interestBeforeAccrual);
        assertEq(retained, retainedBeforeAccrual);
    }

    // getActiveIrmIds()

    function test_getActiveIrmIds_ReturnsActiveIrmIdsOrderedByPriority() public {
        _addThreeIrms();

        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(secondIrm));

        assertEq(debtToken.getActiveIrmIds(), _irmIds(address(firstIrm), address(thirdIrm)));
    }

    function test_getActiveIrmIds_ReturnsEmptyWhenNoIrmsAreActive() public view {
        assertEq(debtToken.getActiveIrmIds(), new address[](0));
    }

    // getDeprecatedIrmIds()

    function test_getDeprecatedIrmIds_ReturnsDeprecatedIrmIds() public {
        _addThreeIrms();

        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(firstIrm));

        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(thirdIrm));

        assertEq(debtToken.getDeprecatedIrmIds(), _irmIds(address(firstIrm), address(thirdIrm)));
    }

    function test_getDeprecatedIrmIds_ReturnsEmptyWhenNoIrmsAreDeprecated() public {
        _addThreeIrms();

        assertEq(debtToken.getDeprecatedIrmIds(), new address[](0));
    }

    // getSupportedIrmIds()

    function test_getSupportedIrmIds_ReturnsActiveAndDeprecatedIrmIdsInAddedOrder() public {
        _addThreeIrms();

        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(firstIrm));

        assertEq(debtToken.getSupportedIrmIds(), _irmIds(address(firstIrm), address(secondIrm), address(thirdIrm)));
    }

    function test_getSupportedIrmIds_KeepsIrmWhenUndeprecated() public {
        _addThreeIrms();

        vm.startPrank(irmUpdater);
        debtToken.deprecateIrm(address(secondIrm));
        debtToken.undeprecateIrm(address(secondIrm), 0);
        vm.stopPrank();

        assertEq(debtToken.getSupportedIrmIds(), _irmIds(address(firstIrm), address(secondIrm), address(thirdIrm)));
    }

    function test_getSupportedIrmIds_ReturnsEmptyWhenNoIrmsAreAdded() public view {
        assertEq(debtToken.getSupportedIrmIds(), new address[](0));
    }

    // getIrmData()

    function test_getIrmData_ReturnsIrmData() public {
        _addIrm(firstIrm, 0);
        debtToken.setIrmStoredBorrowIndex(address(firstIrm), 2e18);
        _setIrmRates(firstIrm, BORROW_RATE, RETENTION_RATE);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);

        MultiInterestDebtToken.IrmData memory irmData = debtToken.getIrmData(address(firstIrm));

        assertEq(uint8(irmData.status), uint8(MultiInterestDebtToken.IrmStatus.ACTIVE));
        assertEq(irmData.storedBorrowIndex, 2e18);
        assertEq(irmData.borrowRate, BORROW_RATE);
        assertEq(irmData.retentionRate, RETENTION_RATE);
        assertEq(irmData.totalScaledDebt, AMOUNT);
    }

    function test_getIrmData_ReturnsEmptyDataWhenIrmIsNotFound() public view {
        MultiInterestDebtToken.IrmData memory irmData = debtToken.getIrmData(address(firstIrm));

        assertEq(uint8(irmData.status), uint8(MultiInterestDebtToken.IrmStatus.NONE));
        assertEq(irmData.storedBorrowIndex, 0);
        assertEq(irmData.borrowRate, 0);
        assertEq(irmData.retentionRate, 0);
        assertEq(irmData.totalScaledDebt, 0);
    }

    // accountIrmId()

    function test_accountIrmId_ReturnsZeroWhenAccountHasNeverBorrowed() public {
        _addIrm(firstIrm, 0);

        assertEq(debtToken.accountIrmId(alice), address(0));
    }

    function test_accountIrmId_ReturnsAssignedIrm() public {
        _addIrm(firstIrm, 0);

        _mint(alice, firstIrm, AMOUNT);

        assertEq(debtToken.accountIrmId(alice), address(firstIrm));
    }

    function test_accountIrmId_IsUnaffectedByAnotherAccountsAssignment() public {
        _addIrm(firstIrm, 0);

        _mint(alice, firstIrm, AMOUNT);

        assertEq(debtToken.accountIrmId(bob), address(0));
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(debtToken.contractName(), "MultiInterestDebtToken");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(debtToken.contractVersion(), "1.0.0");
    }

    // isIrmSupported()

    function test_isIrmSupported_ReturnsTrueWhenIrmIsActive() public {
        _addIrm(firstIrm, 0);

        assertTrue(debtToken.isIrmSupported(address(firstIrm)));
    }

    function test_isIrmSupported_ReturnsTrueWhenIrmIsDeprecated() public {
        _addIrm(firstIrm, 0);

        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(firstIrm));

        assertTrue(debtToken.isIrmSupported(address(firstIrm)));
    }

    function test_isIrmSupported_ReturnsFalseWhenIrmIsNotSupported() public view {
        assertFalse(debtToken.isIrmSupported(address(firstIrm)));
    }

    // findIrmForAccount()

    function test_findIrmForAccount_ReturnsOnlyApplicableIrm() public {
        _addIrm(firstIrm, 0);

        assertEq(debtToken.findIrmForAccount(alice), address(firstIrm));
    }

    function test_findIrmForAccount_ReturnsHighestPriorityApplicableIrm() public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);

        assertEq(debtToken.findIrmForAccount(alice), address(firstIrm));
    }

    function test_findIrmForAccount_SkipsIrmsThatAreNotApplicable() public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        firstIrm.setIsApplicable(false);

        assertEq(debtToken.findIrmForAccount(alice), address(secondIrm));
    }

    function test_findIrmForAccount_FollowsUpdatedPriorities() public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);

        vm.prank(irmUpdater);
        debtToken.setIrmPriorities(_irmIds(address(secondIrm), address(firstIrm)));

        assertEq(debtToken.findIrmForAccount(alice), address(secondIrm));
    }

    function test_findIrmForAccount_IgnoresDeprecatedIrms() public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);

        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(firstIrm));

        assertEq(debtToken.findIrmForAccount(alice), address(secondIrm));
    }

    function test_findIrmForAccount_RevertsWhenNoIrmsAreSupported() public {
        vm.expectRevert(MultiInterestDebtToken.NoApplicableIrmFound.selector);
        debtToken.findIrmForAccount(alice);
    }

    function test_findIrmForAccount_RevertsWhenNoActiveIrmIsApplicable() public {
        _addIrm(firstIrm, 0);
        firstIrm.setIsApplicable(false);

        vm.expectRevert(MultiInterestDebtToken.NoApplicableIrmFound.selector);
        debtToken.findIrmForAccount(alice);
    }

    function test_findIrmForAccount_RevertsWhenOnlyApplicableIrmIsDeprecated() public {
        _addIrm(firstIrm, 0);

        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(firstIrm));

        vm.expectRevert(MultiInterestDebtToken.NoApplicableIrmFound.selector);
        debtToken.findIrmForAccount(alice);
    }

    // balanceOf()

    function test_balanceOf_ReturnsZeroWhenAccountHasNoDebt() public {
        _addIrm(firstIrm, 0);

        assertEq(debtToken.balanceOf(alice), 0);
    }

    function test_balanceOf_ReturnsStoredBalanceWhenNoInterestHasAccrued() public {
        _addIrm(firstIrm, 0);
        _setIrmRates(firstIrm, BORROW_RATE, RETENTION_RATE);
        _mint(alice, firstIrm, AMOUNT);

        assertEq(debtToken.balanceOf(alice), AMOUNT);
    }

    function test_balanceOf_DoesNotAccrueWhenBorrowRateIsZero() public {
        _addIrm(firstIrm, 0);
        _setIrmRates(firstIrm, 0, RETENTION_RATE);
        _mint(alice, firstIrm, AMOUNT);
        vm.warp(block.timestamp + 365 days);

        assertEq(debtToken.balanceOf(alice), AMOUNT);
    }

    function test_balanceOf_AccruesInterestAtAssignedIrmIndex() public {
        _addIrm(firstIrm, 0);
        _setIrmRates(firstIrm, ONE_PERCENT_PER_SECOND_BORROW_RATE, RETENTION_RATE);
        _mint(alice, firstIrm, AMOUNT);
        vm.warp(block.timestamp + 1 seconds);

        // Alice borrowed 1000e18 at a par index, so her debt accrues the IRM's full 1% for the second.
        assertEq(debtToken.balanceOf(alice), 1010e18);
    }

    function test_balanceOf_AccruesInterestWhenAssignedIrmIsDeprecated() public {
        _addIrm(firstIrm, 0);
        _setIrmRates(firstIrm, BORROW_RATE, RETENTION_RATE);
        _mint(alice, firstIrm, AMOUNT);
        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(firstIrm));
        vm.warp(block.timestamp + 365 days);

        assertGt(debtToken.balanceOf(alice), AMOUNT);
    }

    /// @dev A borrow is scaled by the index in force when it is minted, so it carries none of the interest the IRM
    ///      accrued beforehand.
    function test_balanceOf_ExcludesInterestAccruedBeforeMint() public {
        _addIrm(firstIrm, 0);
        _setIrmRates(firstIrm, ONE_PERCENT_PER_SECOND_BORROW_RATE, RETENTION_RATE);
        _mint(alice, firstIrm, AMOUNT);
        vm.warp(block.timestamp + 1 seconds);

        _mint(bob, firstIrm, AMOUNT);

        assertEq(debtToken.balanceOf(alice), 1010e18);
        // Bob borrows once the index is 1.01, so he owes his 1000e18 and none of Alice's interest. His scaled debt is
        // rounded up by a single unit above what he borrowed.
        assertEq(debtToken.balanceOf(bob), AMOUNT + 1);
    }

    function test_balanceOf_IsUnaffectedByAccrualOnOtherIrms() public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        _setIrmRates(secondIrm, BORROW_RATE, RETENTION_RATE);
        _mint(alice, firstIrm, AMOUNT);
        vm.warp(block.timestamp + 365 days);

        assertEq(debtToken.balanceOf(alice), AMOUNT);
    }

    // totalSupply()

    function test_totalSupply_ReturnsZeroWhenNoIrmsAreSupported() public view {
        assertEq(debtToken.totalSupply(), 0);
    }

    function test_totalSupply_SumsStoredDebtAcrossActiveAndDeprecatedIrms() public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);
        debtToken.setIrmTotalScaledDebt(address(secondIrm), 2 * AMOUNT);
        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(firstIrm));

        assertEq(debtToken.totalSupply(), 3 * AMOUNT);
    }

    function test_totalSupply_SumsAccruedDebtAcrossActiveAndDeprecatedIrms() public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        _setIrmRates(firstIrm, ONE_PERCENT_PER_SECOND_BORROW_RATE, RETENTION_RATE);
        _setIrmRates(secondIrm, ONE_PERCENT_PER_SECOND_BORROW_RATE, RETENTION_RATE);
        _mint(alice, firstIrm, AMOUNT);
        _mint(bob, secondIrm, 2 * AMOUNT);
        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(firstIrm));
        vm.warp(block.timestamp + 1 seconds);

        // Alice's 1000e18 on the deprecated IRM and Bob's 2000e18 on the active one each accrue 1% over the second.
        assertEq(debtToken.totalSupply(), 3030e18);
    }

    // updatedBorrowIndex()

    function test_updatedBorrowIndex_DoesNotAccrueWhenBorrowRateIsZero() public {
        _addIrm(firstIrm, 0);
        _setIrmRates(firstIrm, 0, RETENTION_RATE);
        vm.warp(block.timestamp + 365 days);

        assertEq(debtToken.updatedBorrowIndex(address(firstIrm)), MathUtils.ONE_18_DP);
    }

    function test_updatedBorrowIndex_DoesNotAccrueWhenNoTimeHasElapsed() public {
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        debtToken.setIrmBorrowRate(address(firstIrm), BORROW_RATE);
        uint256 oldStoredBorrowIndex = debtToken.getIrmData(address(firstIrm)).storedBorrowIndex;
        vm.warp(lastUpdateTs);

        assertEq(debtToken.updatedBorrowIndex(address(firstIrm)), oldStoredBorrowIndex);
    }

    function test_updatedBorrowIndex_ReturnsExpectedHardcodedValue() public {
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        debtToken.setIrmBorrowRate(address(firstIrm), BORROW_RATE);
        vm.warp(lastUpdateTs + 1 seconds);

        // 10% APR for 1 second: 1e18 * (1 + 0.1e18 / 365 days).
        assertEq(debtToken.updatedBorrowIndex(address(firstIrm)), 1_000_000_003_170_979_198);
    }

    function test_updatedBorrowIndex_CompoundsOverTimeElapsedSinceLastUpdate() public {
        uint256 lastUpdateTs = 100 days;
        vm.warp(lastUpdateTs);
        debtToken.setLastUpdateTs(lastUpdateTs);
        _addIrm(firstIrm, 0);
        _setIrmRates(firstIrm, ONE_PERCENT_PER_SECOND_BORROW_RATE, RETENTION_RATE);
        vm.warp(lastUpdateTs + 2 seconds);

        // Two seconds elapse since the seeded last update, so the par index compounds 1% twice: 1.01 * 1.01 = 1.0201.
        assertEq(debtToken.updatedBorrowIndex(address(firstIrm)), 1.0201e18);
    }

    function test_updatedBorrowIndex_UsesStoredBorrowIndex() public {
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        debtToken.setIrmStoredBorrowIndex(address(firstIrm), 2e18);
        debtToken.setIrmBorrowRate(address(firstIrm), ONE_PERCENT_PER_SECOND_BORROW_RATE);
        vm.warp(lastUpdateTs + 1 seconds);

        // The second's 1% compounds onto the stored 2e18 index rather than onto par: 2 * 1.01 = 2.02.
        assertEq(debtToken.updatedBorrowIndex(address(firstIrm)), 2.02e18);
    }

    function test_updatedBorrowIndex_AccruesWhenIrmIsDeprecated() public {
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        debtToken.setIrmBorrowRate(address(firstIrm), ONE_PERCENT_PER_SECOND_BORROW_RATE);
        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(firstIrm));
        vm.warp(lastUpdateTs + 1 seconds);

        // Deprecation does not freeze accrual, so the par index still takes the second's full 1%.
        assertEq(debtToken.updatedBorrowIndex(address(firstIrm)), 1.01e18);
    }

    function test_updatedBorrowIndex_RevertsWhenIrmIsNotSupported() public {
        vm.expectRevert(abi.encodeWithSelector(MultiInterestDebtToken.IrmNotSupported.selector, address(firstIrm)));
        debtToken.updatedBorrowIndex(address(firstIrm));
    }

    // updatedTotalDebt()

    function test_updatedTotalDebt_DoesNotAccrueWhenBorrowIndexIsSame() public {
        _addIrm(firstIrm, 0);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);
        vm.warp(block.timestamp + 365 days);

        assertEq(debtToken.updatedTotalDebt(address(firstIrm)), AMOUNT);
    }

    function test_updatedTotalDebt_AccruesDebt() public {
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);
        debtToken.setIrmBorrowRate(address(firstIrm), ONE_PERCENT_PER_SECOND_BORROW_RATE);
        vm.warp(lastUpdateTs + 1 seconds);

        // 1000e18 of scaled debt stated at the 1.01 index the second accrues.
        assertEq(debtToken.updatedTotalDebt(address(firstIrm)), 1010e18);
    }

    function test_updatedTotalDebt_ReturnsExpectedHardcodedValue() public {
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);
        debtToken.setIrmBorrowRate(address(firstIrm), BORROW_RATE);
        vm.warp(lastUpdateTs + 1 seconds);

        // 10% APR for 1 second: 1000e18 * (1 + 0.1e18 / 365 days).
        assertEq(debtToken.updatedTotalDebt(address(firstIrm)), 1_000_000_003_170_979_198_000);
    }

    function test_updatedTotalDebt_StatesScaledDebtAtCurrentBorrowIndex() public {
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);
        debtToken.setIrmStoredBorrowIndex(address(firstIrm), 2e18);
        debtToken.setIrmBorrowRate(address(firstIrm), ONE_PERCENT_PER_SECOND_BORROW_RATE);
        vm.warp(lastUpdateTs + 1 seconds);

        // The stored 2e18 index accrues 1% over the second to 2.02e18, which 1000e18 of scaled debt states as 2020e18.
        assertEq(debtToken.updatedTotalDebt(address(firstIrm)), 2020e18);
    }

    function test_updatedTotalDebt_AccruesWhenIrmIsDeprecated() public {
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);
        debtToken.setIrmBorrowRate(address(firstIrm), ONE_PERCENT_PER_SECOND_BORROW_RATE);
        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(firstIrm));
        vm.warp(lastUpdateTs + 1 seconds);

        // Deprecation does not freeze accrual, so the debt matches the active-IRM value above.
        assertEq(debtToken.updatedTotalDebt(address(firstIrm)), 1010e18);
    }

    function test_updatedTotalDebt_RevertsWhenIrmIsNotSupported() public {
        vm.expectRevert(abi.encodeWithSelector(MultiInterestDebtToken.IrmNotSupported.selector, address(firstIrm)));
        debtToken.updatedTotalDebt(address(firstIrm));
    }

    // supportsInterface()

    function test_supportsInterface_DebtToken_ReturnsTrue() public view {
        assertTrue(debtToken.supportsInterface(type(IDebtToken).interfaceId));
    }

    function test_supportsInterface_ERC20_ReturnsTrue() public view {
        assertTrue(debtToken.supportsInterface(type(IERC20).interfaceId));
    }

    function test_supportsInterface_Versioned_ReturnsTrue() public view {
        assertTrue(debtToken.supportsInterface(type(IVersioned).interfaceId));
    }

    function test_supportsInterface_AccessControl_ReturnsTrue() public view {
        assertTrue(debtToken.supportsInterface(type(IAccessControl).interfaceId));
    }

    function test_supportsInterface_AccessControlEnumerable_ReturnsTrue() public view {
        assertTrue(debtToken.supportsInterface(type(IAccessControlEnumerable).interfaceId));
    }

    function test_supportsInterface_ERC165_ReturnsTrue() public view {
        assertTrue(debtToken.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_Unknown_ReturnsFalse() public view {
        assertFalse(debtToken.supportsInterface(bytes4(0xffffffff)));
    }

    // syncAccount()

    function test_syncAccount_LeavesAccountWithoutDebtUnassigned() public {
        _addIrm(firstIrm, 0);

        _syncAccount(alice);

        assertEq(debtToken.accountIrmId(alice), address(0));
    }

    function test_syncAccount_KeepsExistingIrmWhenNoActiveIrmIsApplicable() public {
        _addIrm(firstIrm, 0);
        _mint(alice, firstIrm, AMOUNT);
        firstIrm.setIsApplicable(false);

        _syncAccount(alice);

        assertEq(debtToken.accountIrmId(alice), address(firstIrm));
        assertEq(debtToken.scaledBalanceOf(alice), AMOUNT);
        assertEq(debtToken.getIrmData(address(firstIrm)).totalScaledDebt, AMOUNT);
    }

    function test_syncAccount_KeepsExistingIrmWhenEveryIrmIsDeprecated() public {
        _addIrm(firstIrm, 0);
        _mint(alice, firstIrm, AMOUNT);
        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(firstIrm));

        _syncAccount(alice);

        assertEq(debtToken.accountIrmId(alice), address(firstIrm));
        assertEq(debtToken.scaledBalanceOf(alice), AMOUNT);
        assertEq(debtToken.getIrmData(address(firstIrm)).totalScaledDebt, AMOUNT);
    }

    function test_syncAccount_LeavesBucketsUnchangedWhenIrmIsUnchanged() public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        _mint(alice, firstIrm, AMOUNT);

        _syncAccountTo(alice, firstIrm);

        assertEq(debtToken.accountIrmId(alice), address(firstIrm));
        assertEq(debtToken.scaledBalanceOf(alice), AMOUNT);
        assertEq(debtToken.getIrmData(address(firstIrm)).totalScaledDebt, AMOUNT);
        assertEq(debtToken.getIrmData(address(secondIrm)).totalScaledDebt, 0);
    }

    function test_syncAccount_MovesToHighestPriorityApplicableIrm() public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        _mint(alice, secondIrm, AMOUNT);

        _syncAccount(alice);

        assertEq(debtToken.accountIrmId(alice), address(firstIrm));
    }

    function test_syncAccount_MovesScaledDebtBetweenIrmBuckets() public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        _mint(alice, firstIrm, AMOUNT);

        _syncAccountTo(alice, secondIrm);

        assertEq(debtToken.accountIrmId(alice), address(secondIrm));
        assertEq(debtToken.getIrmData(address(firstIrm)).totalScaledDebt, 0);
        assertEq(debtToken.getIrmData(address(secondIrm)).totalScaledDebt, AMOUNT);
        assertEq(debtToken.balanceOf(alice), AMOUNT);
    }

    /// @dev The scaled amount stored is normalised by the assigned IRM's index, so moving to an IRM whose index sits
    ///      at twice par halves it. The debt owed is what has to survive the restatement, not the scaled amount.
    function test_syncAccount_RestatesScaledDebtAtNewIrmBorrowIndex() public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        _mint(alice, firstIrm, AMOUNT);
        debtToken.setIrmStoredBorrowIndex(address(secondIrm), 2 * MathUtils.ONE_18_DP);

        _syncAccountTo(alice, secondIrm);

        assertEq(debtToken.scaledBalanceOf(alice), AMOUNT / 2);
        assertEq(debtToken.getIrmData(address(secondIrm)).totalScaledDebt, AMOUNT / 2);
        assertEq(debtToken.balanceOf(alice), AMOUNT);
    }

    function test_syncAccount_CarriesAccruedDebtToNewIrm() public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        _mint(alice, firstIrm, AMOUNT);
        debtToken.setIrmBorrowRate(address(firstIrm), BORROW_RATE);
        vm.warp(debtToken.lastUpdateTs() + 30 days);
        uint256 accruedDebt = debtToken.balanceOf(alice);

        _syncAccountTo(alice, secondIrm);

        assertEq(debtToken.balanceOf(alice), accruedDebt);
        assertGt(accruedDebt, AMOUNT);
        assertEq(debtToken.getIrmData(address(firstIrm)).totalScaledDebt, 0);
    }

    function test_syncAccount_EmitsAccountIrmAssignedWhenMovingDebtToNewIrm() public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        _mint(alice, firstIrm, AMOUNT);
        firstIrm.setIsApplicable(false);

        vm.expectEmit(address(debtToken));
        emit MultiInterestDebtToken.AccountIrmAssigned(alice, address(firstIrm), address(secondIrm));

        vm.prank(pool);
        debtToken.syncAccount(alice);
    }

    function test_syncAccount_EmitsNothingWhenIrmIsUnchanged() public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        _mint(alice, firstIrm, AMOUNT);

        vm.expectEmit(false, false, false, false, address(debtToken), 0);
        emit MultiInterestDebtToken.AccountIrmAssigned(address(0), address(0), address(0));

        vm.prank(pool);
        debtToken.syncAccount(alice);
    }

    function test_syncAccount_RevertsWhenBorrowIndexesStale() public {
        _addIrm(firstIrm, 0);
        vm.warp(block.timestamp + 365 days);

        vm.expectRevert(MultiInterestDebtToken.BorrowIndexesStale.selector);
        vm.prank(pool);
        debtToken.syncAccount(alice);
    }

    // accrueInterest()

    /// @dev Per-IRM accrual is covered against `_updateIrmBorrowIndex` directly; what belongs here is the wrapper's own
    ///      work — visiting every supported IRM, summing their interest and retention and advancing `lastUpdateTs`.
    function test_accrueInterest_ReturnsInterestAndRetainedAmount() public {
        _addIrm(firstIrm, 0);
        _setIrmRates(firstIrm, ONE_PERCENT_PER_SECOND_BORROW_RATE, RETENTION_RATE);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);
        vm.warp(debtToken.lastUpdateTs() + 1 seconds);

        vm.prank(pool);
        (uint256 accrued, uint256 retained) = debtToken.accrueInterest();

        // 1000e18 of debt accrues 1% over the second, i.e. 10e18 of interest, of which 20% is retained.
        assertEq(accrued, 10e18);
        assertEq(retained, 2e18);
    }

    function test_accrueInterest_IsIdempotentWithinSameTimestamp() public {
        _addIrm(firstIrm, 0);
        _setIrmRates(firstIrm, ONE_PERCENT_PER_SECOND_BORROW_RATE, RETENTION_RATE);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);
        vm.warp(debtToken.lastUpdateTs() + 1 seconds);
        vm.prank(pool);
        debtToken.accrueInterest();
        uint256 indexAfterFirst = debtToken.getIrmData(address(firstIrm)).storedBorrowIndex;
        uint256 debtAfterFirst = debtToken.getIrmData(address(firstIrm)).totalScaledDebt;

        vm.prank(pool);
        (uint256 accrued, uint256 retained) = debtToken.accrueInterest();

        assertEq(debtToken.getIrmData(address(firstIrm)).storedBorrowIndex, indexAfterFirst);
        assertEq(debtToken.getIrmData(address(firstIrm)).totalScaledDebt, debtAfterFirst);
        assertEq(accrued, 0);
        assertEq(retained, 0);
    }

    function test_accrueInterest_UpdatesActiveAndDeprecatedIrms() public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        _addIrm(thirdIrm, 2);
        _addIrm(fourthIrm, 3);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);
        debtToken.setIrmTotalScaledDebt(address(secondIrm), 2 * AMOUNT);
        debtToken.setIrmTotalScaledDebt(address(thirdIrm), 3 * AMOUNT);
        debtToken.setIrmTotalScaledDebt(address(fourthIrm), 4 * AMOUNT);
        _setIrmRates(firstIrm, ONE_PERCENT_PER_SECOND_BORROW_RATE, 0.2e18);
        _setIrmRates(secondIrm, ONE_PERCENT_PER_SECOND_BORROW_RATE, 0.1e18);
        _setIrmRates(thirdIrm, ONE_PERCENT_PER_SECOND_BORROW_RATE, 0.4e18);
        _setIrmRates(fourthIrm, ONE_PERCENT_PER_SECOND_BORROW_RATE, 0.25e18);
        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(firstIrm));
        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(secondIrm));
        vm.warp(debtToken.lastUpdateTs() + 1 seconds);

        vm.prank(pool);
        (uint256 accrued, uint256 retained) = debtToken.accrueInterest();

        // The two deprecated IRMs take the second's 1% just as the two active ones do, each stating its own debt 1%
        // higher.
        MockIrm[4] memory allIrms = [firstIrm, secondIrm, thirdIrm, fourthIrm];
        uint256[4] memory expectedDebt = [uint256(1010e18), 2020e18, 3030e18, 4040e18];
        for (uint256 i; i < allIrms.length; i++) {
            assertEq(debtToken.getIrmData(address(allIrms[i])).storedBorrowIndex, 1.01e18);
            assertEq(debtToken.updatedTotalDebt(address(allIrms[i])), expectedDebt[i]);
        }
        // Each IRM accrues 1% of its own debt and retains its own share of that: 10 * 0.2 + 20 * 0.1 + 30 * 0.4 +
        // 40 * 0.25.
        assertEq(accrued, 100e18);
        assertEq(retained, 26e18);
    }

    function test_accrueInterest_SetsLastUpdateTs() public {
        _addIrm(firstIrm, 0);
        _setIrmRates(firstIrm, ONE_PERCENT_PER_SECOND_BORROW_RATE, RETENTION_RATE);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);
        vm.warp(debtToken.lastUpdateTs() + 1 seconds);

        vm.prank(pool);
        debtToken.accrueInterest();

        assertEq(debtToken.lastUpdateTs(), block.timestamp);
    }

    function test_accrueInterest_SetsLastUpdateTsWhenNoIrmsAreSupported() public {
        vm.warp(debtToken.lastUpdateTs() + 365 days);

        vm.prank(pool);
        (uint256 accrued, uint256 retained) = debtToken.accrueInterest();

        // With nothing to iterate the timestamp still moves, so the freshness guard is satisfied on an empty token.
        assertEq(debtToken.lastUpdateTs(), block.timestamp);
        assertEq(accrued, 0);
        assertEq(retained, 0);
    }

    // updateBorrowRates()

    function test_updateBorrowRates_StoresBorrowRateAndRetentionRate() public {
        _addIrm(firstIrm, 0);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);
        firstIrm.setBorrowRate(BORROW_RATE);
        firstIrm.setRetentionRate(RETENTION_RATE);
        debtToken.setLastUpdateTs(block.timestamp);

        vm.prank(pool);
        debtToken.updateBorrowRates(IDLE_LIQUIDITY);

        assertEq(debtToken.getIrmData(address(firstIrm)).borrowRate, BORROW_RATE);
        assertEq(debtToken.getIrmData(address(firstIrm)).retentionRate, RETENTION_RATE);
    }

    function test_updateBorrowRates_SucceedsWhenNoIrmsAreSupported() public {
        vm.prank(pool);
        debtToken.updateBorrowRates(IDLE_LIQUIDITY);
    }

    function test_updateBorrowRates_RevertsWhenBorrowIndexesStale() public {
        _addIrm(firstIrm, 0);
        debtToken.setLastUpdateTs(block.timestamp);
        vm.warp(block.timestamp + 365 days);

        vm.expectRevert(MultiInterestDebtToken.BorrowIndexesStale.selector);
        vm.prank(pool);
        debtToken.updateBorrowRates(IDLE_LIQUIDITY);
    }

    function test_updateBorrowRates_SucceedsAfterUpdateBorrowIndexes() public {
        _addIrm(firstIrm, 0);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);
        firstIrm.setBorrowRate(BORROW_RATE);
        firstIrm.setRetentionRate(RETENTION_RATE);
        // Leave lastUpdateTs stale so only the real index update can satisfy the guard.
        vm.warp(block.timestamp + 365 days);

        vm.prank(pool);
        debtToken.accrueInterest();

        // Guard passes because updating the indexes refreshed lastUpdateTs to the current block.
        vm.prank(pool);
        debtToken.updateBorrowRates(IDLE_LIQUIDITY);
    }

    // _mintDebt()

    function test_mintDebt_AssignsHighestPriorityApplicableIrmToAccountWithoutDebt() public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        firstIrm.setIsApplicable(false);

        vm.prank(pool);
        debtToken.mint(alice, AMOUNT);

        assertEq(debtToken.accountIrmId(alice), address(secondIrm));
    }

    function test_mintDebt_StoresAmountAsScaledDebtAtParIndex() public {
        _addIrm(firstIrm, 0);

        _mint(alice, firstIrm, AMOUNT);

        assertEq(debtToken.scaledBalanceOf(alice), AMOUNT);
        assertEq(debtToken.balanceOf(alice), AMOUNT);
        assertEq(debtToken.getIrmData(address(firstIrm)).totalScaledDebt, AMOUNT);
    }

    /// @dev Borrowing at an accrued index stores fewer scaled units than the amount borrowed, because each scaled unit
    ///      states more than one unit of debt by then.
    function test_mintDebt_StoresScaledDebtAtAccruedIndex() public {
        _addIrm(firstIrm, 0);
        _setIrmRates(firstIrm, ONE_PERCENT_PER_SECOND_BORROW_RATE, RETENTION_RATE);
        vm.warp(block.timestamp + 1 seconds);

        _mint(alice, firstIrm, 1010e18);

        // The second of accrual stepped the index to 1.01, so 1010e18 of new debt is stored as 1000e18 scaled units
        // and reads back as the 1010e18 borrowed.
        assertEq(debtToken.scaledBalanceOf(alice), 1000e18);
        assertEq(debtToken.balanceOf(alice), 1010e18);
    }

    /// @dev A deprecated IRM can no longer be assigned but keeps accounting for the accounts already in it, so an
    ///      account assigned to one can still take on more debt there.
    function test_mintDebt_StoresScaledDebtWhenIrmIsDeprecated() public {
        _addIrm(firstIrm, 0);
        _mint(alice, firstIrm, AMOUNT);
        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(firstIrm));

        vm.prank(pool);
        debtToken.mint(alice, 250e18);

        assertEq(debtToken.scaledBalanceOf(alice), AMOUNT + 250e18);
        assertEq(debtToken.getIrmData(address(firstIrm)).totalScaledDebt, AMOUNT + 250e18);
    }

    function test_mintDebt_MovesDebtToHighestPriorityApplicableIrm() public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        _mint(alice, secondIrm, AMOUNT);

        vm.prank(pool);
        debtToken.mint(alice, AMOUNT);

        assertEq(debtToken.accountIrmId(alice), address(firstIrm));
        assertEq(debtToken.getIrmData(address(firstIrm)).totalScaledDebt, 2 * AMOUNT);
        assertEq(debtToken.getIrmData(address(secondIrm)).totalScaledDebt, 0);
    }

    function test_mintDebt_EmitsAccountIrmAssignedWhenAssigningIrm() public {
        _addIrm(firstIrm, 0);

        vm.expectEmit(address(debtToken));
        emit MultiInterestDebtToken.AccountIrmAssigned(alice, address(0), address(firstIrm));

        vm.prank(pool);
        debtToken.mint(alice, AMOUNT);
    }

    function test_mintDebt_RevertsWhenBorrowIndexesStale() public {
        _addIrm(firstIrm, 0);
        _mint(alice, firstIrm, AMOUNT);
        vm.warp(block.timestamp + 365 days);

        vm.expectRevert(MultiInterestDebtToken.BorrowIndexesStale.selector);
        vm.prank(pool);
        debtToken.mint(alice, AMOUNT);
    }

    function test_mintDebt_RevertsWhenNoActiveIrmIsApplicableToAccountWithoutDebt() public {
        _addIrm(firstIrm, 0);
        firstIrm.setIsApplicable(false);

        vm.expectRevert(MultiInterestDebtToken.NoApplicableIrmFound.selector);
        vm.prank(pool);
        debtToken.mint(alice, AMOUNT);
    }

    // _burnDebt()

    function test_burnDebt_ClearsPositionWhenFullBalanceIsRepaid() public {
        _addIrm(firstIrm, 0);
        _mint(alice, firstIrm, AMOUNT);
        _setIrmRates(firstIrm, BORROW_RATE, RETENTION_RATE);
        vm.warp(block.timestamp + 365 days);
        vm.startPrank(pool);
        debtToken.accrueInterest();

        debtToken.burn(alice, debtToken.balanceOf(alice));
        vm.stopPrank();

        assertEq(debtToken.balanceOf(alice), 0);
        assertEq(debtToken.scaledBalanceOf(alice), 0);
        assertEq(debtToken.getIrmData(address(firstIrm)).totalScaledDebt, 0);
    }

    function test_burnDebt_LeavesRemainderWhenPartialBalanceIsRepaid() public {
        _addIrm(firstIrm, 0);
        _mint(alice, firstIrm, AMOUNT);

        vm.prank(pool);
        debtToken.burn(alice, AMOUNT / 4);

        assertEq(debtToken.balanceOf(alice), AMOUNT - AMOUNT / 4);
        assertEq(debtToken.getIrmData(address(firstIrm)).totalScaledDebt, AMOUNT - AMOUNT / 4);
    }

    /// @dev Repaying at an accrued index clears fewer scaled units than the amount repaid, because each scaled unit
    ///      states more than one unit of debt by then.
    function test_burnDebt_ClearsScaledDebtAtAccruedIndex() public {
        _addIrm(firstIrm, 0);
        _mint(alice, firstIrm, 2000e18);
        _setIrmRates(firstIrm, ONE_PERCENT_PER_SECOND_BORROW_RATE, RETENTION_RATE);
        vm.warp(block.timestamp + 1 seconds);
        vm.startPrank(pool);
        debtToken.accrueInterest();

        debtToken.burn(alice, 1010e18);
        vm.stopPrank();

        // The second of accrual stepped the index to 1.01, making the 2000e18 scaled units worth 2020e18 of debt.
        // Repaying 1010e18 of that clears 1000e18 scaled units, leaving 1000e18 scaled worth 1010e18.
        assertEq(debtToken.scaledBalanceOf(alice), 1000e18);
        assertEq(debtToken.balanceOf(alice), 1010e18);
        assertEq(debtToken.getIrmData(address(firstIrm)).totalScaledDebt, 1000e18);
    }

    /// @dev A repayment is floored into scaled units, so an overpayment smaller than the index buys no extra scaled
    ///      debt and does not revert. It closes the position and the excess stays in the pool.
    function test_burnDebt_AbsorbsOverRepaymentSmallerThanIndex() public {
        _addIrm(firstIrm, 0);
        _mint(alice, firstIrm, 2000e18);
        _setIrmRates(firstIrm, ONE_PERCENT_PER_SECOND_BORROW_RATE, RETENTION_RATE);
        vm.warp(block.timestamp + 1 seconds);
        vm.startPrank(pool);
        debtToken.accrueInterest();

        debtToken.burn(alice, 2020e18 + 1);
        vm.stopPrank();

        // The index stepped to 1.01, so the whole debt is 2020e18 and the extra unit is a hundredth of a scaled unit.
        assertEq(debtToken.scaledBalanceOf(alice), 0);
        assertEq(debtToken.getIrmData(address(firstIrm)).totalScaledDebt, 0);
    }

    /// @dev A deprecated IRM can no longer be assigned but keeps accounting for the accounts already in it, so an
    ///      account assigned to one can still retire debt there.
    function test_burnDebt_ClearsScaledDebtWhenIrmIsDeprecated() public {
        _addIrm(firstIrm, 0);
        _mint(alice, firstIrm, AMOUNT);
        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(firstIrm));

        vm.prank(pool);
        debtToken.burn(alice, 250e18);

        assertEq(debtToken.scaledBalanceOf(alice), AMOUNT - 250e18);
        assertEq(debtToken.getIrmData(address(firstIrm)).totalScaledDebt, AMOUNT - 250e18);
    }

    function test_burnDebt_UnassignsAccountWhenFullBalanceIsRepaid() public {
        _addIrm(firstIrm, 0);
        _mint(alice, firstIrm, AMOUNT);

        vm.prank(pool);
        debtToken.burn(alice, AMOUNT);

        assertEq(debtToken.accountIrmId(alice), address(0));
    }

    function test_burnDebt_MovesRemainingDebtToHighestPriorityApplicableIrm() public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        _mint(alice, secondIrm, AMOUNT);

        vm.prank(pool);
        debtToken.burn(alice, AMOUNT / 4);

        assertEq(debtToken.accountIrmId(alice), address(firstIrm));
        assertEq(debtToken.getIrmData(address(firstIrm)).totalScaledDebt, AMOUNT - AMOUNT / 4);
        assertEq(debtToken.getIrmData(address(secondIrm)).totalScaledDebt, 0);
    }

    function test_burnDebt_EmitsAccountIrmAssignedWhenUnassigningAccount() public {
        _addIrm(firstIrm, 0);
        _mint(alice, firstIrm, AMOUNT);

        vm.expectEmit(address(debtToken));
        emit MultiInterestDebtToken.AccountIrmAssigned(alice, address(firstIrm), address(0));

        vm.prank(pool);
        debtToken.burn(alice, AMOUNT);
    }

    function test_burnDebt_RevertsWhenBorrowIndexesStale() public {
        _addIrm(firstIrm, 0);
        _mint(alice, firstIrm, AMOUNT);
        vm.warp(block.timestamp + 365 days);

        vm.expectRevert(MultiInterestDebtToken.BorrowIndexesStale.selector);
        vm.prank(pool);
        debtToken.burn(alice, AMOUNT);
    }

    function test_burnDebt_RevertsWhenAccountHasNoIrmAssigned() public {
        debtToken.setLastUpdateTs(block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(MultiInterestDebtToken.IrmNotSupported.selector, address(0)));
        vm.prank(pool);
        debtToken.burn(alice, AMOUNT);
    }

    /// @dev A sole borrower's debt is its IRM's whole total, so the repayment exceeds the total and reverts there
    ///      before the balance check in `ERC20._burn` is reached.
    function test_burnDebt_RevertsWhenAmountExceedsIrmTotalScaledDebt() public {
        _addIrm(firstIrm, 0);
        _mint(alice, firstIrm, AMOUNT);

        vm.expectRevert(stdError.arithmeticError);
        vm.prank(pool);
        debtToken.burn(alice, AMOUNT + 1);
    }

    /// @dev The IRM's total is decreased before the account's balance, so an account repaying more than its own debt
    ///      but no more than its IRM's total fails on the balance rather than on the total.
    function test_burnDebt_RevertsWhenAmountExceedsBalance() public {
        _addIrm(firstIrm, 0);
        _mint(alice, firstIrm, AMOUNT);
        _mint(bob, firstIrm, AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, AMOUNT, AMOUNT + 1)
        );
        vm.prank(pool);
        debtToken.burn(alice, AMOUNT + 1);
    }

    // _updateIrmBorrowIndex()

    function test_updateIrmBorrowIndex_AccruesBorrowIndexDebtAndRetained() public {
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);
        _setIrmRates(firstIrm, ONE_PERCENT_PER_SECOND_BORROW_RATE, RETENTION_RATE);
        vm.warp(lastUpdateTs + 1 seconds);

        (uint256 accrued, uint256 retained) = debtToken.updateIrmBorrowIndex(address(firstIrm));
        // `lastUpdateTs` must be set manually as the internal function does not.
        debtToken.setLastUpdateTs(block.timestamp);

        // The par index takes the second's 1%, restating 1000e18 of scaled debt as 1010e18. Of the 10e18 of interest
        // that produces, 20% is retained.
        assertEq(debtToken.getIrmData(address(firstIrm)).storedBorrowIndex, 1.01e18);
        assertEq(debtToken.updatedTotalDebt(address(firstIrm)), 1010e18);
        assertEq(accrued, 10e18);
        assertEq(retained, 2e18);
    }

    function test_updateIrmBorrowIndex_DoesNotAccrueWhenNoTimeHasElapsed() public {
        _addIrm(firstIrm, 0);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);
        _setIrmRates(firstIrm, BORROW_RATE, RETENTION_RATE);
        debtToken.setLastUpdateTs(block.timestamp);

        (uint256 accrued, uint256 retained) = debtToken.updateIrmBorrowIndex(address(firstIrm));

        assertEq(debtToken.getIrmData(address(firstIrm)).storedBorrowIndex, MathUtils.ONE_18_DP);
        assertEq(debtToken.getIrmData(address(firstIrm)).totalScaledDebt, AMOUNT);
        assertEq(accrued, 0);
        assertEq(retained, 0);
    }

    function test_updateIrmBorrowIndex_DoesNotAccrueRetainedWhenRetentionRateIsZero() public {
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);
        debtToken.setIrmBorrowRate(address(firstIrm), ONE_PERCENT_PER_SECOND_BORROW_RATE);
        vm.warp(lastUpdateTs + 1 seconds);

        (uint256 accrued, uint256 retained) = debtToken.updateIrmBorrowIndex(address(firstIrm));
        // `lastUpdateTs` must be set manually as the internal function does not.
        debtToken.setLastUpdateTs(block.timestamp);

        // The second's 1% accrued into the borrow index and so into the debt, but no share of it was retained.
        assertEq(debtToken.getIrmData(address(firstIrm)).storedBorrowIndex, 1.01e18);
        assertEq(debtToken.updatedTotalDebt(address(firstIrm)), 1010e18);
        assertEq(accrued, 10e18);
        assertEq(retained, 0);
    }

    function test_updateIrmBorrowIndex_RetainsAllAccruedInterestWhenRetentionRateIsFull() public {
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        _setIrmRates(firstIrm, ONE_PERCENT_PER_SECOND_BORROW_RATE, MathUtils.ONE_18_DP);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);
        vm.warp(lastUpdateTs + 1 seconds);

        (uint256 accrued, uint256 retained) = debtToken.updateIrmBorrowIndex(address(firstIrm));
        // `lastUpdateTs` must be set manually as the internal function does not.
        debtToken.setLastUpdateTs(block.timestamp);

        // A full retention rate leaves depositors none of the second's 10e18 of interest.
        assertEq(accrued, 10e18);
        assertEq(retained, 10e18);
    }

    function test_updateIrmBorrowIndex_LeavesTotalScaledDebtUnchanged() public {
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        _setIrmRates(firstIrm, ONE_PERCENT_PER_SECOND_BORROW_RATE, RETENTION_RATE);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);
        vm.warp(lastUpdateTs + 1 seconds);

        debtToken.updateIrmBorrowIndex(address(firstIrm));

        // Interest lands in the index alone: the scaled debt behind it is the same 1000e18 that was seeded.
        assertEq(debtToken.getIrmData(address(firstIrm)).storedBorrowIndex, 1.01e18);
        assertEq(debtToken.getIrmData(address(firstIrm)).totalScaledDebt, AMOUNT);
    }

    function test_updateIrmBorrowIndex_DoesNotAccrueWhenTotalDebtIsZero() public {
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        _setIrmRates(firstIrm, ONE_PERCENT_PER_SECOND_BORROW_RATE, RETENTION_RATE);
        vm.warp(lastUpdateTs + 1 seconds);

        (uint256 accrued, uint256 retained) = debtToken.updateIrmBorrowIndex(address(firstIrm));
        // `lastUpdateTs` must be set manually as the internal function does not.
        debtToken.setLastUpdateTs(block.timestamp);

        // The index still advances by the second's 1%, but with no debt behind it there is nothing to retain.
        assertEq(debtToken.getIrmData(address(firstIrm)).storedBorrowIndex, 1.01e18);
        assertEq(debtToken.getIrmData(address(firstIrm)).totalScaledDebt, 0);
        assertEq(accrued, 0);
        assertEq(retained, 0);
    }

    function test_updateIrmBorrowIndex_DoesNotAccrueWhenBorrowRateIsZero() public {
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        _setIrmRates(firstIrm, 0, RETENTION_RATE);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);
        vm.warp(lastUpdateTs + 365 days);

        (uint256 accrued, uint256 retained) = debtToken.updateIrmBorrowIndex(address(firstIrm));
        // `lastUpdateTs` must be set manually as the internal function does not.
        debtToken.setLastUpdateTs(block.timestamp);

        // A zero rate holds the index at par however long elapses, so there is no interest to take a share of.
        assertEq(debtToken.getIrmData(address(firstIrm)).storedBorrowIndex, MathUtils.ONE_18_DP);
        assertEq(debtToken.getIrmData(address(firstIrm)).totalScaledDebt, AMOUNT);
        assertEq(accrued, 0);
        assertEq(retained, 0);
    }

    /// @dev Each IRM carries its own index, so accruing one must not touch another's — a property the caller that loops
    ///      over every supported IRM cannot show.
    function test_updateIrmBorrowIndex_LeavesOtherIrmsUnchanged() public {
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);
        debtToken.setIrmTotalScaledDebt(address(secondIrm), AMOUNT);
        _setIrmRates(firstIrm, ONE_PERCENT_PER_SECOND_BORROW_RATE, RETENTION_RATE);
        _setIrmRates(secondIrm, ONE_PERCENT_PER_SECOND_BORROW_RATE, RETENTION_RATE);
        vm.warp(lastUpdateTs + 1 seconds);

        (uint256 accrued, uint256 retained) = debtToken.updateIrmBorrowIndex(address(firstIrm));
        // `lastUpdateTs` must be set manually as the internal function does not.
        debtToken.setLastUpdateTs(block.timestamp);

        // Only the first IRM took the second's 1%; the second is left at par and only the first IRM's 2e18 is retained.
        assertEq(debtToken.getIrmData(address(firstIrm)).storedBorrowIndex, 1.01e18);
        assertEq(debtToken.getIrmData(address(secondIrm)).storedBorrowIndex, MathUtils.ONE_18_DP);
        assertEq(accrued, 10e18);
        assertEq(retained, 2e18);
    }

    /// @dev `lastUpdateTs` is advanced by the caller, not here, so two calls at the same timestamp both see the full
    ///      elapsed period and compound it twice. This is why the timestamp write belongs to `_accrueInterest`.
    function test_updateIrmBorrowIndex_AccruesAgainWhenCalledTwiceAtSameTimestamp() public {
        uint256 lastUpdateTs = debtToken.lastUpdateTs();
        _addIrm(firstIrm, 0);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);
        _setIrmRates(firstIrm, ONE_PERCENT_PER_SECOND_BORROW_RATE, RETENTION_RATE);
        vm.warp(lastUpdateTs + 1 seconds);

        (uint256 firstAccrued, uint256 firstRetained) = debtToken.updateIrmBorrowIndex(address(firstIrm));
        (uint256 secondAccrued, uint256 secondRetained) = debtToken.updateIrmBorrowIndex(address(firstIrm));
        // `lastUpdateTs` must be set manually as the internal function does not.
        debtToken.setLastUpdateTs(block.timestamp);

        // The second call compounds another 1% on 1.01, and retains 20% of the further 10.1e18 it states.
        assertEq(debtToken.getIrmData(address(firstIrm)).storedBorrowIndex, 1.0201e18);
        assertEq(debtToken.updatedTotalDebt(address(firstIrm)), 1020.1e18);
        assertEq(firstAccrued, 10e18);
        assertEq(firstRetained, 2e18);
        assertEq(secondAccrued, 10.1e18);
        assertEq(secondRetained, 2.02e18);
    }

    // _updateIrmBorrowRate()

    /// @dev Both rate hooks are quoted the same pool-wide state — the idle liquidity passed in and the total debt across
    ///      every IRM — alongside the debt of the bucket being repriced. All three values differ here, so a misordered
    ///      or duplicated argument cannot pass unnoticed.
    function test_updateIrmBorrowRate_QuotesEachIrmPoolStateAndItsOwnDebt() public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), 1000e18);
        debtToken.setIrmTotalScaledDebt(address(secondIrm), 3000e18);
        debtToken.setLastUpdateTs(block.timestamp);

        // The two buckets hold 4000e18 between them, which each IRM prices its own share against.
        vm.expectCall(address(firstIrm), abi.encodeCall(IIRM.borrowRate, (IDLE_LIQUIDITY, 4000e18, 1000e18)));
        vm.expectCall(address(firstIrm), abi.encodeCall(IIRM.retentionRate, (IDLE_LIQUIDITY, 4000e18, 1000e18)));
        vm.expectCall(address(secondIrm), abi.encodeCall(IIRM.borrowRate, (IDLE_LIQUIDITY, 4000e18, 3000e18)));
        vm.expectCall(address(secondIrm), abi.encodeCall(IIRM.retentionRate, (IDLE_LIQUIDITY, 4000e18, 3000e18)));

        vm.prank(pool);
        debtToken.updateBorrowRates(IDLE_LIQUIDITY);
    }

    /// @dev Deprecated buckets keep accruing, so their debt belongs in the pool-wide total every IRM prices against and
    ///      they are repriced alongside the active ones.
    function test_updateIrmBorrowRate_CountsDeprecatedDebtInTotalDebt() public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), 1000e18);
        debtToken.setIrmTotalScaledDebt(address(secondIrm), 3000e18);
        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(secondIrm));
        debtToken.setLastUpdateTs(block.timestamp);

        // The deprecated bucket's 3000e18 counts toward the 4000e18 total the active IRM is quoted.
        vm.expectCall(address(firstIrm), abi.encodeCall(IIRM.borrowRate, (IDLE_LIQUIDITY, 4000e18, 1000e18)));
        vm.expectCall(address(secondIrm), abi.encodeCall(IIRM.borrowRate, (IDLE_LIQUIDITY, 4000e18, 3000e18)));

        vm.prank(pool);
        debtToken.updateBorrowRates(IDLE_LIQUIDITY);
    }

    /// @dev A bucket's debt is its scaled debt stated at its own borrow index, so two buckets holding the same scaled
    ///      amount are quoted different debts once their indexes diverge.
    function test_updateIrmBorrowRate_QuotesDebtStatedAtItsBorrowIndex() public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        debtToken.setIrmTotalScaledDebt(address(firstIrm), AMOUNT);
        debtToken.setIrmTotalScaledDebt(address(secondIrm), AMOUNT);
        debtToken.setIrmStoredBorrowIndex(address(firstIrm), 2e18);
        debtToken.setLastUpdateTs(block.timestamp);

        // The same 1000e18 of scaled debt states 2000e18 at the doubled index and 1000e18 at par, totalling 3000e18.
        vm.expectCall(address(firstIrm), abi.encodeCall(IIRM.borrowRate, (IDLE_LIQUIDITY, 3000e18, 2000e18)));
        vm.expectCall(address(secondIrm), abi.encodeCall(IIRM.borrowRate, (IDLE_LIQUIDITY, 3000e18, 1000e18)));

        vm.prank(pool);
        debtToken.updateBorrowRates(IDLE_LIQUIDITY);
    }

    function test_updateIrmBorrowRate_EmitsIrmRatesUpdatedForEachSupportedIrmIncludingDeprecated() public {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        vm.prank(irmUpdater);
        debtToken.deprecateIrm(address(secondIrm));
        debtToken.setIrmStoredBorrowIndex(address(firstIrm), 1.5e18);
        debtToken.setIrmStoredBorrowIndex(address(secondIrm), 2e18);
        firstIrm.setBorrowRate(0.1e18);
        firstIrm.setRetentionRate(0.2e18);
        secondIrm.setBorrowRate(0.3e18);
        secondIrm.setRetentionRate(0.4e18);
        debtToken.setLastUpdateTs(block.timestamp);

        vm.expectEmit(address(debtToken));
        emit MultiInterestDebtToken.IrmRatesUpdated(address(firstIrm), 1.5e18, 0.1e18, 0.2e18);
        vm.expectEmit(address(debtToken));
        emit MultiInterestDebtToken.IrmRatesUpdated(address(secondIrm), 2e18, 0.3e18, 0.4e18);

        vm.prank(pool);
        debtToken.updateBorrowRates(IDLE_LIQUIDITY);
    }

    function _addIrm(MockIrm irm, uint8 priority) internal {
        vm.prank(irmUpdater);
        debtToken.addIrm(address(irm), priority);
    }

    function _deployDebtToken(address defaultAdmin_, address irmUpdater_)
        internal
        returns (MultiInterestDebtTokenHarness instance)
    {
        return _deployDebtToken(defaultAdmin_, irmUpdater_, new address[](0));
    }

    function _deployDebtToken(address defaultAdmin_, address irmUpdater_, address[] memory irmIds)
        internal
        returns (MultiInterestDebtTokenHarness instance)
    {
        instance = MultiInterestDebtTokenHarness(Clones.clone(address(implementation)));
        instance.initialize(pool, NAME, SYMBOL, DECIMALS, defaultAdmin_, irmUpdater_, irmIds);
    }

    /// @dev Seeds the stored borrow and retention rate for `irm` directly, so index accrual can be exercised without
    ///      routing through the rate subsystem (`updateBorrowRates`).
    function _setIrmRates(MockIrm irm, uint256 borrowRate, uint256 retentionRate) internal {
        debtToken.setIrmBorrowRate(address(irm), borrowRate);
        debtToken.setIrmRetentionRate(address(irm), retentionRate);
    }

    /// @dev Adds `irm` at priority 0, gives it debt and seeds a positive borrow and retention rate directly into
    ///      storage so subsequent time warps accrue interest without driving the rate subsystem.
    function _addAccruingIrm(MockIrm irm) internal {
        _addIrm(irm, 0);
        debtToken.setIrmTotalScaledDebt(address(irm), AMOUNT);
        _setIrmRates(irm, BORROW_RATE, RETENTION_RATE);
    }

    /// @dev Moves `account`'s debt to its highest-priority applicable active IRM. Indexes are refreshed first to satisfy
    ///      `syncAccount`'s freshness precondition.
    function _syncAccount(address account) internal {
        vm.startPrank(pool);
        debtToken.accrueInterest();
        debtToken.syncAccount(account);
        vm.stopPrank();
    }

    /// @dev Reassigns `account` to `irm`, which `syncAccount` only does if `irm` is the highest-priority applicable active
    ///      IRM. Indexes are refreshed first to satisfy `syncAccount`'s freshness precondition.
    function _syncAccountTo(address account, MockIrm irm) internal {
        firstIrm.setIsApplicable(address(irm) == address(firstIrm));
        secondIrm.setIsApplicable(address(irm) == address(secondIrm));

        vm.startPrank(pool);
        debtToken.accrueInterest();
        debtToken.syncAccount(account);
        vm.stopPrank();

        firstIrm.setIsApplicable(true);
        secondIrm.setIsApplicable(true);
    }

    /// @dev `mint` places the account's debt in its highest-priority applicable active IRM, so `irm` is made the only
    ///      applicable one for the duration of the mint. Indexes are refreshed first to satisfy `mint`'s freshness
    ///      precondition.
    function _mint(address account, MockIrm irm, uint256 amount) internal {
        firstIrm.setIsApplicable(address(irm) == address(firstIrm));
        secondIrm.setIsApplicable(address(irm) == address(secondIrm));

        vm.startPrank(pool);
        debtToken.accrueInterest();
        debtToken.mint(account, amount);
        vm.stopPrank();

        firstIrm.setIsApplicable(true);
        secondIrm.setIsApplicable(true);
    }

    function _addThreeIrms() internal {
        _addIrm(firstIrm, 0);
        _addIrm(secondIrm, 1);
        _addIrm(thirdIrm, 2);
    }

    function _addIrms(uint8 count) internal {
        for (uint8 i; i < count; i++) {
            MockIrm irm = new MockIrm(true, 0, 0);
            irms.push(irm);
            _addIrm(irm, i);
        }
    }

    function _addDeprecatedIrms(uint8 count) internal {
        for (uint8 i; i < count; i++) {
            MockIrm irm = new MockIrm(true, 0, 0);
            irms.push(irm);
            _addIrm(irm, 0);

            vm.prank(irmUpdater);
            debtToken.deprecateIrm(address(irm));
        }
    }

    function _irmIds(address first) internal pure returns (address[] memory irmIds) {
        irmIds = new address[](1);
        irmIds[0] = first;
    }

    function _irmIds(address first, address second) internal pure returns (address[] memory irmIds) {
        irmIds = new address[](2);
        irmIds[0] = first;
        irmIds[1] = second;
    }

    function _irmIds(address first, address second, address third) internal pure returns (address[] memory irmIds) {
        irmIds = new address[](3);
        irmIds[0] = first;
        irmIds[1] = second;
        irmIds[2] = third;
    }

    function _irmIds(address first, address second, address third, address fourth)
        internal
        pure
        returns (address[] memory irmIds)
    {
        irmIds = new address[](4);
        irmIds[0] = first;
        irmIds[1] = second;
        irmIds[2] = third;
        irmIds[3] = fourth;
    }
}
