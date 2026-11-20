// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IAccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Test} from "forge-std/Test.sol";

import {FlashLendable} from "src/pool/abstract/FlashLendable.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockFlashBorrower} from "../mocks/MockFlashBorrower.sol";
import {FlashLendableHarness} from "./mocks/FlashLendableHarness.sol";

contract FlashLendableUnitTest is Test {
    FlashLendableHarness implementation;
    FlashLendableHarness lender;
    MockERC20 token;
    MockFlashBorrower borrower;

    address defaultAdmin = makeAddr("defaultAdmin");
    address flashLoanConfigurator = makeAddr("flashLoanConfigurator");
    address caller = makeAddr("caller");

    uint256 constant AMOUNT = 250e18;
    uint256 constant LENDER_BALANCE = 2000e18;

    function setUp() public {
        implementation = new FlashLendableHarness();
        lender = FlashLendableHarness(Clones.clone(address(implementation)));
        lender.initialize(defaultAdmin, flashLoanConfigurator, true);
        token = new MockERC20();
        lender.setFlashLoanToken(address(token));
        token.mint(address(lender), LENDER_BALANCE);
        borrower = new MockFlashBorrower();
    }

    // initialize()

    function test_Initialize_ConfiguresFlashLoanConfiguratorAndStatus() public view {
        assertTrue(lender.hasRole(lender.FLASH_LOAN_CONFIG_ROLE(), flashLoanConfigurator));
        assertTrue(lender.flashLoansEnabled());
    }

    function test_Initialize_EmitsFlashLoansEnabledSet() public {
        FlashLendableHarness newLender = FlashLendableHarness(Clones.clone(address(implementation)));

        vm.expectEmit(address(newLender));
        emit FlashLendable.FlashLoansEnabledSet(true);
        newLender.initialize(defaultAdmin, flashLoanConfigurator, true);
    }

    function test_Initialize_UsesDefaultAdminAsRoleAdmin() public view {
        assertEq(lender.getRoleAdmin(lender.FLASH_LOAN_CONFIG_ROLE()), lender.DEFAULT_ADMIN_ROLE());
    }

    function test_Initialize_AllowsZeroFlashLoanConfiguratorAndDisabledFlashLoans() public {
        FlashLendableHarness rolelessLender = FlashLendableHarness(Clones.clone(address(implementation)));
        rolelessLender.initialize(defaultAdmin, address(0), false);

        assertEq(rolelessLender.getRoleMemberCount(rolelessLender.FLASH_LOAN_CONFIG_ROLE()), 0);
        assertFalse(rolelessLender.flashLoansEnabled());
    }

    // setFlashLoansEnabled()

    function test_SetFlashLoansEnabled_DisablesFlashLoans() public {
        vm.prank(flashLoanConfigurator);
        lender.setFlashLoansEnabled(false);

        assertFalse(lender.flashLoansEnabled());
    }

    function test_SetFlashLoansEnabled_EnablesFlashLoans() public {
        vm.prank(flashLoanConfigurator);
        lender.setFlashLoansEnabled(false);

        vm.prank(flashLoanConfigurator);
        lender.setFlashLoansEnabled(true);

        assertTrue(lender.flashLoansEnabled());
    }

    function test_SetFlashLoansEnabled_EmitsFlashLoansEnabledSet() public {
        vm.expectEmit(address(lender));
        emit FlashLendable.FlashLoansEnabledSet(false);

        vm.prank(flashLoanConfigurator);
        lender.setFlashLoansEnabled(false);
    }

    function test_SetFlashLoansEnabled_Revert_WhenCallerLacksFlashLoanConfigRole() public {
        bytes32 role = lender.FLASH_LOAN_CONFIG_ROLE();

        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, role));
        vm.prank(caller);
        lender.setFlashLoansEnabled(false);
    }

    function test_SetFlashLoansEnabled_Revert_WhenAlreadyEnabled() public {
        vm.expectRevert(abi.encodeWithSelector(FlashLendable.FlashLoansEnabledUnchanged.selector, true));
        vm.prank(flashLoanConfigurator);
        lender.setFlashLoansEnabled(true);
    }

    function test_SetFlashLoansEnabled_Revert_WhenAlreadyDisabled() public {
        vm.prank(flashLoanConfigurator);
        lender.setFlashLoansEnabled(false);

        vm.expectRevert(abi.encodeWithSelector(FlashLendable.FlashLoansEnabledUnchanged.selector, false));
        vm.prank(flashLoanConfigurator);
        lender.setFlashLoansEnabled(false);
    }

    // flashLoan()

    function test_FlashLoan_ReturnsTrue() public {
        vm.prank(caller);
        bool success = lender.flashLoan(borrower, address(token), AMOUNT, "");

        assertTrue(success);
    }

    function test_FlashLoan_LendsWholeBalance() public {
        vm.prank(caller);
        lender.flashLoan(borrower, address(token), LENDER_BALANCE, "");

        assertEq(borrower.balanceDuringCallback(), LENDER_BALANCE);
        assertEq(token.balanceOf(address(lender)), LENDER_BALANCE);
    }

    function test_FlashLoan_LendsOne() public {
        vm.prank(caller);
        lender.flashLoan(borrower, address(token), 1, "");

        assertEq(borrower.balanceDuringCallback(), 1);
        assertEq(token.balanceOf(address(lender)), LENDER_BALANCE);
    }

    function test_FlashLoan_AllowsReentrantFlashLoan() public {
        MockFlashBorrower innerBorrower = new MockFlashBorrower();
        uint256 innerAmount = LENDER_BALANCE - AMOUNT;
        borrower.addCallbackCall(
            address(lender),
            abi.encodeCall(IERC3156FlashLender.flashLoan, (innerBorrower, address(token), innerAmount, ""))
        );

        vm.prank(caller);
        lender.flashLoan(borrower, address(token), AMOUNT, "");

        assertEq(innerBorrower.balanceDuringCallback(), innerAmount);
        assertEq(token.balanceOf(address(lender)), LENDER_BALANCE);
    }

    function test_FlashLoan_Revert_WhenFlashLoansDisabled() public {
        vm.prank(flashLoanConfigurator);
        lender.setFlashLoansEnabled(false);

        vm.expectRevert(FlashLendable.FlashLoansDisabled.selector);
        vm.prank(caller);
        lender.flashLoan(borrower, address(token), AMOUNT, "");
    }

    function test_FlashLoan_Revert_WhenTokenIsNotFlashLoanTokenEvenIfHeldByLender() public {
        MockERC20 otherToken = new MockERC20();
        otherToken.mint(address(lender), LENDER_BALANCE);

        vm.expectRevert(abi.encodeWithSelector(FlashLendable.ERC3156UnsupportedToken.selector, address(otherToken)));
        vm.prank(caller);
        lender.flashLoan(borrower, address(otherToken), AMOUNT, "");
    }

    function test_FlashLoan_Revert_WhenAmountIsZero() public {
        vm.expectRevert(FlashLendable.ZeroFlashLoanAmount.selector);
        vm.prank(caller);
        lender.flashLoan(borrower, address(token), 0, "");
    }

    function test_FlashLoan_Revert_WhenAmountIsOneAboveLenderBalance() public {
        vm.expectRevert(abi.encodeWithSelector(FlashLendable.ERC3156ExceededMaxLoan.selector, LENDER_BALANCE));
        vm.prank(caller);
        lender.flashLoan(borrower, address(token), LENDER_BALANCE + 1, "");
    }

    function test_FlashLoan_Revert_WhenReceiverRejectsLoan() public {
        borrower.setCallbackReturnValue(keccak256("rejected"));

        vm.expectRevert(abi.encodeWithSelector(FlashLendable.ERC3156InvalidReceiver.selector, address(borrower)));
        vm.prank(caller);
        lender.flashLoan(borrower, address(token), AMOUNT, "");
    }

    function test_FlashLoan_Revert_WhenReceiverDoesNotApproveRepayment() public {
        borrower.setApproveRepayment(false);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(lender), 0, AMOUNT)
        );
        vm.prank(caller);
        lender.flashLoan(borrower, address(token), AMOUNT, "");
    }

    /// @dev Sending the loan straight back restores the lender's balance, which a balance check would accept.
    ///      Repayment is pulled instead, so the receiver must still hold the loan once the callback returns.
    function test_FlashLoan_Revert_WhenReceiverSendsLoanBackInsteadOfRepaying() public {
        borrower.addCallbackCall(address(token), abi.encodeCall(IERC20.transfer, (address(lender), AMOUNT)));

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(borrower), 0, AMOUNT)
        );
        vm.prank(caller);
        lender.flashLoan(borrower, address(token), AMOUNT, "");
    }

    // maxFlashLoan()

    function test_MaxFlashLoan_ReturnsZeroWhenFlashLoansDisabled() public {
        vm.prank(flashLoanConfigurator);
        lender.setFlashLoansEnabled(false);

        assertEq(lender.maxFlashLoan(address(token)), 0);
    }

    function test_MaxFlashLoan_ReturnsZeroForOtherTokenHeldByLender() public {
        MockERC20 otherToken = new MockERC20();
        otherToken.mint(address(lender), LENDER_BALANCE);

        assertEq(lender.maxFlashLoan(address(otherToken)), 0);
    }

    // supportsInterface()

    function test_SupportsInterface_ERC3156FlashLender_ReturnsTrue() public view {
        assertTrue(lender.supportsInterface(type(IERC3156FlashLender).interfaceId));
    }

    function test_SupportsInterface_ERC165_ReturnsTrue() public view {
        assertTrue(lender.supportsInterface(type(IERC165).interfaceId));
    }

    function test_SupportsInterface_AccessControl_ReturnsTrue() public view {
        assertTrue(lender.supportsInterface(type(IAccessControl).interfaceId));
    }

    function test_SupportsInterface_AccessControlEnumerable_ReturnsTrue() public view {
        assertTrue(lender.supportsInterface(type(IAccessControlEnumerable).interfaceId));
    }

    function test_SupportsInterface_Unknown_ReturnsFalse() public view {
        assertFalse(lender.supportsInterface(bytes4(0xffffffff)));
    }
}
