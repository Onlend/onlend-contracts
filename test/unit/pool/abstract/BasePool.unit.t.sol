// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IAccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Test} from "forge-std/Test.sol";

import {ActionLib} from "src/hooks/lib/ActionLib.sol";
import {IHookReceiver, Phase} from "src/hooks/interfaces/IHookReceiver.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {BasePool} from "src/pool/abstract/BasePool.sol";
import {FlashLendable} from "src/pool/abstract/FlashLendable.sol";
import {IPool} from "src/pool/interfaces/IPool.sol";
import {MockHookReceiver} from "../../hooks/mocks/MockHookReceiver.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockFlashBorrower} from "../mocks/MockFlashBorrower.sol";
import {MockDecimalsToken} from "./mocks/MockDecimalsToken.sol";
import {BasePoolHarness} from "./mocks/BasePoolHarness.sol";
import {BasePoolNoCapabilitiesHarness} from "./mocks/BasePoolNoCapabilitiesHarness.sol";

contract BasePoolUnitTest is Test {
    BasePoolHarness implementation;
    BasePoolHarness pool;
    MockHookReceiver hookReceiver;
    MockERC20 asset;
    MockFlashBorrower borrower;

    address defaultAdmin = makeAddr("defaultAdmin");
    address hookUpdater = makeAddr("hookUpdater");
    address flashLoanConfigurator = makeAddr("flashLoanConfigurator");
    address lendingCore = makeAddr("lendingCore");
    address nonLendingCore = makeAddr("nonLendingCore");
    address caller = makeAddr("caller");
    address receiver = makeAddr("receiver");

    uint256 constant ASSETS = 1000e18;
    uint256 constant SHARES = 500e18;
    uint256 constant AMOUNT = 250e18;
    uint256 constant REPAYMENT = 200e18;
    uint256 constant WRITTEN_OFF = 300e18;

    /// @dev Deliberately unequal to ASSETS and SHARES, so an assertion cannot pass on the requested amounts.
    uint256 constant RESOLVED_ASSETS = 1200e18;
    uint256 constant RESOLVED_SHARES = 600e18;

    uint256 constant POOL_BALANCE = 2000e18;

    function setUp() public {
        implementation = new BasePoolHarness();
        pool = BasePoolHarness(Clones.clone(address(implementation)));
        pool.initialize(defaultAdmin, hookUpdater, flashLoanConfigurator, address(0), 0, 0, lendingCore, true);
        hookReceiver = new MockHookReceiver();
        asset = new MockERC20();
        pool.setAsset(address(asset));
        asset.mint(address(pool), POOL_BALANCE);
        borrower = new MockFlashBorrower();
    }

    // initialize()

    function test_Initialize_ConfiguresHookUpdaterAndLendingCore() public view {
        assertTrue(pool.hasRole(pool.HOOK_UPDATER_ROLE(), hookUpdater));
        assertEq(pool.lendingCore(), lendingCore);
    }

    function test_Initialize_ConfiguresFlashLoanConfiguratorAndStatus() public view {
        assertTrue(pool.hasRole(pool.FLASH_LOAN_CONFIG_ROLE(), flashLoanConfigurator));
        assertTrue(pool.flashLoansEnabled());
    }

    function test_Initialize_UsesDefaultAdminAsRoleAdmin() public view {
        assertEq(pool.getRoleAdmin(pool.HOOK_UPDATER_ROLE()), pool.DEFAULT_ADMIN_ROLE());
    }

    function test_Initialize_AllowsZeroHookUpdaterAndLendingCore() public {
        BasePoolHarness rolelessPool = BasePoolHarness(Clones.clone(address(implementation)));
        rolelessPool.initialize(defaultAdmin, address(0), address(0), address(0), 0, 0, address(0), false);

        assertEq(rolelessPool.getRoleMemberCount(rolelessPool.HOOK_UPDATER_ROLE()), 0);
        assertEq(rolelessPool.lendingCore(), address(0));
    }

    function test_Initialize_ForwardsDisabledFlashLoans() public {
        BasePoolHarness disabledPool = BasePoolHarness(Clones.clone(address(implementation)));
        disabledPool.initialize(defaultAdmin, hookUpdater, flashLoanConfigurator, address(0), 0, 0, lendingCore, false);

        assertFalse(disabledPool.flashLoansEnabled());
    }

    // depositCollateral()

    function test_DepositCollateral_CallsInternalDepositCollateral() public {
        vm.expectEmit(address(pool));
        emit BasePoolHarness.DepositCollateralCalled(caller, ASSETS, SHARES, receiver);

        vm.prank(lendingCore);
        pool.depositCollateral(caller, ASSETS, SHARES, receiver);
    }

    function test_DepositCollateral_ReturnsAmountsResolvedByInternal() public {
        pool.setCollateralResult(RESOLVED_ASSETS, RESOLVED_SHARES);

        vm.prank(lendingCore);
        (uint256 assetsDeposited, uint256 sharesMinted) = pool.depositCollateral(caller, ASSETS, SHARES, receiver);

        assertEq(assetsDeposited, RESOLVED_ASSETS);
        assertEq(sharesMinted, RESOLVED_SHARES);
    }

    function test_DepositCollateral_FiresAfterHookWithResolvedAmounts() public {
        pool.setCollateralResult(RESOLVED_ASSETS, RESOLVED_SHARES);
        _configureAfterHook(ActionLib.POOL_DEPOSIT_COLLATERAL);

        vm.expectCall(
            address(hookReceiver),
            abi.encodeCall(
                IHookReceiver.onHook,
                (
                    address(pool),
                    Phase.AFTER,
                    ActionLib.POOL_DEPOSIT_COLLATERAL,
                    abi.encode(receiver, caller, RESOLVED_ASSETS, RESOLVED_SHARES)
                )
            ),
            1
        );

        vm.prank(lendingCore);
        pool.depositCollateral(caller, ASSETS, SHARES, receiver);
    }

    function test_DepositCollateral_Revert_WhenCallerIsNotLendingCore() public {
        vm.expectRevert(BasePool.NotLendingCoreCaller.selector);
        vm.prank(nonLendingCore);
        pool.depositCollateral(caller, ASSETS, SHARES, receiver);
    }

    function test_DepositCollateral_Revert_WhenInternalReverts() public {
        _configureHooks(ActionLib.POOL_DEPOSIT_COLLATERAL);
        pool.setShouldRevert(true);

        bytes memory beforeHookData = abi.encode(receiver, caller, ASSETS, SHARES);
        vm.expectCall(
            address(hookReceiver),
            abi.encodeCall(
                IHookReceiver.onHook, (address(pool), Phase.BEFORE, ActionLib.POOL_DEPOSIT_COLLATERAL, beforeHookData)
            ),
            1
        );
        _expectNoAfterHook();

        vm.expectRevert(BasePoolHarness.HarnessReverted.selector);
        vm.prank(lendingCore);
        pool.depositCollateral(caller, ASSETS, SHARES, receiver);
    }

    // withdrawCollateral()

    function test_WithdrawCollateral_CallsInternalWithdrawCollateral() public {
        vm.expectEmit(address(pool));
        emit BasePoolHarness.WithdrawCollateralCalled(caller, ASSETS, SHARES, receiver);

        vm.prank(lendingCore);
        pool.withdrawCollateral(caller, ASSETS, SHARES, receiver);
    }

    function test_WithdrawCollateral_ReturnsAmountsResolvedByInternal() public {
        pool.setCollateralResult(RESOLVED_ASSETS, RESOLVED_SHARES);

        vm.prank(lendingCore);
        (uint256 assetsWithdrawn, uint256 sharesBurned) = pool.withdrawCollateral(caller, ASSETS, SHARES, receiver);

        assertEq(assetsWithdrawn, RESOLVED_ASSETS);
        assertEq(sharesBurned, RESOLVED_SHARES);
    }

    function test_WithdrawCollateral_FiresAfterHookWithResolvedAmounts() public {
        pool.setCollateralResult(RESOLVED_ASSETS, RESOLVED_SHARES);
        _configureAfterHook(ActionLib.POOL_WITHDRAW_COLLATERAL);

        vm.expectCall(
            address(hookReceiver),
            abi.encodeCall(
                IHookReceiver.onHook,
                (
                    address(pool),
                    Phase.AFTER,
                    ActionLib.POOL_WITHDRAW_COLLATERAL,
                    abi.encode(caller, receiver, RESOLVED_ASSETS, RESOLVED_SHARES)
                )
            ),
            1
        );

        vm.prank(lendingCore);
        pool.withdrawCollateral(caller, ASSETS, SHARES, receiver);
    }

    function test_WithdrawCollateral_Revert_WhenCallerIsNotLendingCore() public {
        vm.expectRevert(BasePool.NotLendingCoreCaller.selector);
        vm.prank(nonLendingCore);
        pool.withdrawCollateral(caller, ASSETS, SHARES, receiver);
    }

    function test_WithdrawCollateral_Revert_WhenInternalReverts() public {
        _configureHooks(ActionLib.POOL_WITHDRAW_COLLATERAL);
        pool.setShouldRevert(true);

        bytes memory hookData = abi.encode(caller, receiver, ASSETS, SHARES);
        vm.expectCall(
            address(hookReceiver),
            abi.encodeCall(
                IHookReceiver.onHook, (address(pool), Phase.BEFORE, ActionLib.POOL_WITHDRAW_COLLATERAL, hookData)
            ),
            1
        );
        _expectNoAfterHook();

        vm.expectRevert(BasePoolHarness.HarnessReverted.selector);
        vm.prank(lendingCore);
        pool.withdrawCollateral(caller, ASSETS, SHARES, receiver);
    }

    // seizeCollateral()

    function test_SeizeCollateral_CallsInternalSeizeCollateral() public {
        vm.expectEmit(address(pool));
        emit BasePoolHarness.SeizeCollateralCalled(caller, ASSETS, receiver);

        vm.prank(lendingCore);
        pool.seizeCollateral(caller, ASSETS, receiver);
    }

    function test_SeizeCollateral_ReturnsAmountsResolvedByInternal() public {
        pool.setCollateralResult(RESOLVED_ASSETS, RESOLVED_SHARES);

        vm.prank(lendingCore);
        (uint256 assetsSeized, uint256 sharesSeized) = pool.seizeCollateral(caller, ASSETS, receiver);

        assertEq(assetsSeized, RESOLVED_ASSETS);
        assertEq(sharesSeized, RESOLVED_SHARES);
    }

    function test_SeizeCollateral_FiresAfterHookWithResolvedAmounts() public {
        pool.setCollateralResult(RESOLVED_ASSETS, RESOLVED_SHARES);
        _configureAfterHook(ActionLib.POOL_SEIZE_COLLATERAL);

        vm.expectCall(
            address(hookReceiver),
            abi.encodeCall(
                IHookReceiver.onHook,
                (
                    address(pool),
                    Phase.AFTER,
                    ActionLib.POOL_SEIZE_COLLATERAL,
                    abi.encode(caller, receiver, RESOLVED_ASSETS, RESOLVED_SHARES)
                )
            ),
            1
        );

        vm.prank(lendingCore);
        pool.seizeCollateral(caller, ASSETS, receiver);
    }

    function test_SeizeCollateral_Revert_WhenCallerIsNotLendingCore() public {
        vm.expectRevert(BasePool.NotLendingCoreCaller.selector);
        vm.prank(nonLendingCore);
        pool.seizeCollateral(caller, ASSETS, receiver);
    }

    function test_SeizeCollateral_Revert_WhenInternalReverts() public {
        _configureHooks(ActionLib.POOL_SEIZE_COLLATERAL);
        pool.setShouldRevert(true);

        bytes memory hookData = abi.encode(caller, receiver, ASSETS);
        vm.expectCall(
            address(hookReceiver),
            abi.encodeCall(
                IHookReceiver.onHook, (address(pool), Phase.BEFORE, ActionLib.POOL_SEIZE_COLLATERAL, hookData)
            ),
            1
        );
        _expectNoAfterHook();

        vm.expectRevert(BasePoolHarness.HarnessReverted.selector);
        vm.prank(lendingCore);
        pool.seizeCollateral(caller, ASSETS, receiver);
    }

    // borrow()

    function test_Borrow_CallsInternalBorrow() public {
        vm.expectEmit(address(pool));
        emit BasePoolHarness.BorrowCalled(caller, AMOUNT, receiver);

        vm.prank(lendingCore);
        pool.borrow(caller, AMOUNT, receiver);
    }

    function test_Borrow_Revert_WhenCallerIsNotLendingCore() public {
        vm.expectRevert(BasePool.NotLendingCoreCaller.selector);
        vm.prank(nonLendingCore);
        pool.borrow(caller, AMOUNT, receiver);
    }

    function test_Borrow_Revert_WhenInternalReverts() public {
        _configureHooks(ActionLib.POOL_BORROW);
        pool.setShouldRevert(true);

        bytes memory beforeHookData = abi.encode(caller, receiver, AMOUNT);
        vm.expectCall(
            address(hookReceiver),
            abi.encodeCall(IHookReceiver.onHook, (address(pool), Phase.BEFORE, ActionLib.POOL_BORROW, beforeHookData)),
            1
        );
        _expectNoAfterHook();

        vm.expectRevert(BasePoolHarness.HarnessReverted.selector);
        vm.prank(lendingCore);
        pool.borrow(caller, AMOUNT, receiver);
    }

    // repay()

    function test_Repay_CallsInternalRepay() public {
        vm.expectEmit(address(pool));
        emit BasePoolHarness.RepayCalled(caller, AMOUNT, receiver);

        vm.prank(lendingCore);
        pool.repay(caller, AMOUNT, receiver);
    }

    function test_Repay_ReturnsInternalRepayment() public {
        pool.setRepayment(REPAYMENT);

        vm.prank(lendingCore);
        uint256 actualRepayment = pool.repay(caller, AMOUNT, receiver);

        assertEq(actualRepayment, REPAYMENT);
    }

    function test_Repay_FiresAfterHookWithRepayment() public {
        pool.setRepayment(REPAYMENT);
        _configureAfterHook(ActionLib.POOL_REPAY);

        vm.expectCall(
            address(hookReceiver),
            abi.encodeCall(
                IHookReceiver.onHook,
                (address(pool), Phase.AFTER, ActionLib.POOL_REPAY, abi.encode(receiver, caller, REPAYMENT))
            ),
            1
        );

        vm.prank(lendingCore);
        pool.repay(caller, AMOUNT, receiver);
    }

    function test_Repay_Revert_WhenCallerIsNotLendingCore() public {
        vm.expectRevert(BasePool.NotLendingCoreCaller.selector);
        vm.prank(nonLendingCore);
        pool.repay(caller, AMOUNT, receiver);
    }

    function test_Repay_Revert_WhenInternalReverts() public {
        _configureHooks(ActionLib.POOL_REPAY);
        pool.setShouldRevert(true);

        bytes memory hookData = abi.encode(receiver, caller, AMOUNT);
        vm.expectCall(
            address(hookReceiver),
            abi.encodeCall(IHookReceiver.onHook, (address(pool), Phase.BEFORE, ActionLib.POOL_REPAY, hookData)),
            1
        );
        _expectNoAfterHook();

        vm.expectRevert(BasePoolHarness.HarnessReverted.selector);
        vm.prank(lendingCore);
        pool.repay(caller, AMOUNT, receiver);
    }

    // writeOffDebt()

    function test_WriteOffDebt_CallsInternalWriteOffDebt() public {
        vm.expectEmit(address(pool));
        emit BasePoolHarness.WriteOffDebtCalled(caller);

        vm.prank(lendingCore);
        pool.writeOffDebt(caller);
    }

    function test_WriteOffDebt_ReturnsInternalWrittenOff() public {
        pool.setWrittenOff(WRITTEN_OFF);

        vm.prank(lendingCore);
        uint256 actualWrittenOff = pool.writeOffDebt(caller);

        assertEq(actualWrittenOff, WRITTEN_OFF);
    }

    function test_WriteOffDebt_Revert_WhenCallerIsNotLendingCore() public {
        vm.expectRevert(BasePool.NotLendingCoreCaller.selector);
        vm.prank(nonLendingCore);
        pool.writeOffDebt(caller);
    }

    function test_WriteOffDebt_Revert_WhenInternalReverts() public {
        _configureHooks(ActionLib.POOL_WRITE_OFF_DEBT);
        pool.setShouldRevert(true);

        bytes memory hookData = abi.encode(caller);
        vm.expectCall(
            address(hookReceiver),
            abi.encodeCall(
                IHookReceiver.onHook, (address(pool), Phase.BEFORE, ActionLib.POOL_WRITE_OFF_DEBT, hookData)
            ),
            1
        );
        _expectNoAfterHook();

        vm.expectRevert(BasePoolHarness.HarnessReverted.selector);
        vm.prank(lendingCore);
        pool.writeOffDebt(caller);
    }

    // flashLoan()

    function test_FlashLoan_LendsAsset() public {
        vm.prank(caller);
        pool.flashLoan(borrower, address(asset), AMOUNT, "");

        assertEq(borrower.balanceDuringCallback(), AMOUNT);
    }

    function test_FlashLoan_Revert_WhenFlashLoanReverts() public {
        borrower.setCallbackReturnValue(keccak256("rejected"));
        _configureHooks(ActionLib.POOL_FLASH_LOAN);

        bytes memory hookData = abi.encode(caller, address(borrower), AMOUNT);
        vm.expectCall(
            address(hookReceiver),
            abi.encodeCall(IHookReceiver.onHook, (address(pool), Phase.BEFORE, ActionLib.POOL_FLASH_LOAN, hookData)),
            1
        );
        _expectNoAfterHook();

        vm.expectRevert(abi.encodeWithSelector(FlashLendable.ERC3156InvalidReceiver.selector, address(borrower)));
        vm.prank(caller);
        pool.flashLoan(borrower, address(asset), AMOUNT, "");
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(pool.contractName(), "BasePoolHarness");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(pool.contractVersion(), "1.0.0");
    }

    // supportsInterface()

    function test_SupportsInterface_Pool_ReturnsTrue() public view {
        assertTrue(pool.supportsInterface(type(IPool).interfaceId));
    }

    function test_SupportsInterface_ERC3156FlashLender_ReturnsTrue() public view {
        assertTrue(pool.supportsInterface(type(IERC3156FlashLender).interfaceId));
    }

    function test_SupportsInterface_Versioned_ReturnsTrue() public view {
        assertTrue(pool.supportsInterface(type(IVersioned).interfaceId));
    }

    function test_SupportsInterface_ERC165_ReturnsTrue() public view {
        assertTrue(pool.supportsInterface(type(IERC165).interfaceId));
    }

    function test_SupportsInterface_AccessControl_ReturnsTrue() public view {
        assertTrue(pool.supportsInterface(type(IAccessControl).interfaceId));
    }

    function test_SupportsInterface_AccessControlEnumerable_ReturnsTrue() public view {
        assertTrue(pool.supportsInterface(type(IAccessControlEnumerable).interfaceId));
    }

    function test_SupportsInterface_Unknown_ReturnsFalse() public view {
        assertFalse(pool.supportsInterface(bytes4(0xffffffff)));
    }

    // unsupported operations

    function test_DepositCollateral_Revert_WhenPoolDoesNotSupportCollateral() public {
        BasePoolNoCapabilitiesHarness pool_ = _deployNoCapabilitiesPool();

        vm.expectRevert(BasePool.FunctionNotAvailable.selector);
        vm.prank(lendingCore);
        pool_.depositCollateral(caller, ASSETS, SHARES, receiver);
    }

    function test_WithdrawCollateral_Revert_WhenPoolDoesNotSupportCollateral() public {
        BasePoolNoCapabilitiesHarness pool_ = _deployNoCapabilitiesPool();

        vm.expectRevert(BasePool.FunctionNotAvailable.selector);
        vm.prank(lendingCore);
        pool_.withdrawCollateral(caller, ASSETS, SHARES, receiver);
    }

    function test_SeizeCollateral_Revert_WhenPoolDoesNotSupportCollateral() public {
        BasePoolNoCapabilitiesHarness pool_ = _deployNoCapabilitiesPool();

        vm.expectRevert(BasePool.FunctionNotAvailable.selector);
        vm.prank(lendingCore);
        pool_.seizeCollateral(caller, ASSETS, receiver);
    }

    function test_Borrow_Revert_WhenPoolDoesNotSupportBorrowing() public {
        BasePoolNoCapabilitiesHarness pool_ = _deployNoCapabilitiesPool();

        vm.expectRevert(BasePool.FunctionNotAvailable.selector);
        vm.prank(lendingCore);
        pool_.borrow(caller, AMOUNT, receiver);
    }

    function test_Repay_Revert_WhenPoolDoesNotSupportBorrowing() public {
        BasePoolNoCapabilitiesHarness pool_ = _deployNoCapabilitiesPool();

        vm.expectRevert(BasePool.FunctionNotAvailable.selector);
        vm.prank(lendingCore);
        pool_.repay(caller, AMOUNT, receiver);
    }

    function test_WriteOffDebt_Revert_WhenPoolDoesNotSupportBorrowing() public {
        BasePoolNoCapabilitiesHarness pool_ = _deployNoCapabilitiesPool();

        vm.expectRevert(BasePool.FunctionNotAvailable.selector);
        vm.prank(lendingCore);
        pool_.writeOffDebt(caller);
    }

    function test_TotalCollateral_ReturnsZeroWhenPoolDoesNotSupportCollateral() public {
        BasePoolNoCapabilitiesHarness pool_ = _deployNoCapabilitiesPool();

        assertEq(pool_.totalCollateral(), 0);
    }

    function test_TotalDebt_ReturnsZeroWhenPoolDoesNotSupportBorrowing() public {
        BasePoolNoCapabilitiesHarness pool_ = _deployNoCapabilitiesPool();

        assertEq(pool_.totalDebt(), 0);
    }

    function test_CollateralOf_ReturnsZeroWhenPoolDoesNotSupportCollateral() public {
        BasePoolNoCapabilitiesHarness pool_ = _deployNoCapabilitiesPool();

        assertEq(pool_.collateralOf(caller), 0);
    }

    function test_DebtOf_ReturnsZeroWhenPoolDoesNotSupportBorrowing() public {
        BasePoolNoCapabilitiesHarness pool_ = _deployNoCapabilitiesPool();

        assertEq(pool_.debtOf(caller), 0);
    }

    // _validateTokenDecimals()

    function test_ValidateTokenDecimals_AcceptsTokenReportingExpectedDecimals() public {
        MockDecimalsToken token = new MockDecimalsToken(6);

        pool.validateTokenDecimals(address(token), 6);
    }

    function test_ValidateTokenDecimals_Revert_WhenTokenReportsOtherDecimals() public {
        MockDecimalsToken token = new MockDecimalsToken(6);

        vm.expectRevert(abi.encodeWithSelector(BasePool.InvalidTokenDecimals.selector, address(token), 6, 18));
        pool.validateTokenDecimals(address(token), 18);
    }

    function _deployNoCapabilitiesPool() internal returns (BasePoolNoCapabilitiesHarness pool_) {
        BasePoolNoCapabilitiesHarness implementation_ = new BasePoolNoCapabilitiesHarness();
        pool_ = BasePoolNoCapabilitiesHarness(Clones.clone(address(implementation_)));
        pool_.initialize(defaultAdmin, hookUpdater, address(0), address(0), 0, 0, lendingCore, false);
    }

    function _configureHooks(uint8 action) internal {
        vm.startPrank(hookUpdater);
        pool.setHookReceiver(address(hookReceiver));
        pool.setHookBitmaps(_bit(action), _bit(action));
        vm.stopPrank();
    }

    function _configureAfterHook(uint8 action) internal {
        vm.startPrank(hookUpdater);
        pool.setHookReceiver(address(hookReceiver));
        pool.setHookBitmaps(0, _bit(action));
        vm.stopPrank();
    }

    function _expectNoAfterHook() internal {
        vm.expectCall(
            address(hookReceiver), abi.encodeWithSelector(IHookReceiver.onHook.selector, address(pool), Phase.AFTER), 0
        );
    }

    function _bit(uint8 action) internal pure returns (uint256) {
        return uint256(1) << action;
    }
}
