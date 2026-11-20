// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IAccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Test} from "forge-std/Test.sol";

import {FlashLendable} from "src/pool/abstract/FlashLendable.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockFlashBorrower} from "../mocks/MockFlashBorrower.sol";
import {FlashLendableHarness} from "./mocks/FlashLendableHarness.sol";

contract FlashLendableFuzzTest is Test {
    FlashLendableHarness lender;
    MockERC20 token;
    MockFlashBorrower borrower;

    address defaultAdmin = makeAddr("defaultAdmin");
    address flashLoanConfigurator = makeAddr("flashLoanConfigurator");

    uint256 constant LENDER_BALANCE = 2000e18;
    uint256 constant MAX_LENDER_BALANCE = type(uint128).max;

    function setUp() public {
        FlashLendableHarness implementation = new FlashLendableHarness();
        lender = FlashLendableHarness(Clones.clone(address(implementation)));
        lender.initialize(defaultAdmin, flashLoanConfigurator, true);
        token = new MockERC20();
        lender.setFlashLoanToken(address(token));
        borrower = new MockFlashBorrower();
    }

    // flashFee()

    function testFuzz_FlashFee_ReturnsZeroForFlashLoanToken(uint256 amount) public view {
        assertEq(lender.flashFee(address(token), amount), 0);
    }

    function testFuzz_FlashFee_Revert_WhenTokenIsNotFlashLoanToken(address otherToken, uint256 amount) public {
        vm.assume(otherToken != address(token));

        vm.expectRevert(abi.encodeWithSelector(FlashLendable.ERC3156UnsupportedToken.selector, otherToken));
        lender.flashFee(otherToken, amount);
    }

    // flashLoan()

    function testFuzz_FlashLoan_LendsAndRecoversAmount(address initiator, uint256 lenderBalance, uint256 amount)
        public
    {
        lenderBalance = bound(lenderBalance, 1, MAX_LENDER_BALANCE);
        amount = bound(amount, 1, lenderBalance);
        token.mint(address(lender), lenderBalance);

        vm.prank(initiator);
        lender.flashLoan(borrower, address(token), amount, "");

        assertEq(borrower.balanceDuringCallback(), amount);
        assertEq(token.balanceOf(address(lender)), lenderBalance);
        assertEq(token.balanceOf(address(borrower)), 0);
    }

    function testFuzz_FlashLoan_CallsReceiverWithArguments(address initiator, uint256 amount, bytes calldata data)
        public
    {
        amount = bound(amount, 1, LENDER_BALANCE);
        token.mint(address(lender), LENDER_BALANCE);

        vm.expectCall(
            address(borrower),
            abi.encodeCall(IERC3156FlashBorrower.onFlashLoan, (initiator, address(token), amount, 0, data)),
            1
        );

        vm.prank(initiator);
        lender.flashLoan(borrower, address(token), amount, data);
    }

    function testFuzz_FlashLoan_EmitsFlashLoan(address initiator, uint256 amount) public {
        amount = bound(amount, 1, LENDER_BALANCE);
        token.mint(address(lender), LENDER_BALANCE);

        vm.expectEmit(address(lender));
        emit FlashLendable.FlashLoan(initiator, address(borrower), address(token), amount);

        vm.prank(initiator);
        lender.flashLoan(borrower, address(token), amount, "");
    }

    function testFuzz_FlashLoan_Revert_WhenAmountExceedsLenderBalance(uint256 lenderBalance, uint256 amount) public {
        lenderBalance = bound(lenderBalance, 0, MAX_LENDER_BALANCE);
        amount = bound(amount, lenderBalance + 1, type(uint256).max);
        token.mint(address(lender), lenderBalance);

        vm.expectRevert(abi.encodeWithSelector(FlashLendable.ERC3156ExceededMaxLoan.selector, lenderBalance));
        lender.flashLoan(borrower, address(token), amount, "");
    }

    // maxFlashLoan()

    function testFuzz_MaxFlashLoan_ReturnsLenderBalanceOfFlashLoanToken(uint256 lenderBalance) public {
        lenderBalance = bound(lenderBalance, 0, MAX_LENDER_BALANCE);
        token.mint(address(lender), lenderBalance);

        assertEq(lender.maxFlashLoan(address(token)), lenderBalance);
    }

    // supportsInterface()

    function testFuzz_SupportsInterface_Unknown_ReturnsFalse(bytes4 interfaceId) public view {
        interfaceId = _unsupportedInterfaceId(interfaceId);

        assertFalse(lender.supportsInterface(interfaceId));
    }

    function _unsupportedInterfaceId(bytes4 interfaceId) internal pure returns (bytes4) {
        if (
            interfaceId == type(IERC3156FlashLender).interfaceId || interfaceId == type(IERC165).interfaceId
                || interfaceId == type(IAccessControl).interfaceId
                || interfaceId == type(IAccessControlEnumerable).interfaceId
        ) {
            return 0xffffffff;
        }

        return interfaceId;
    }
}
