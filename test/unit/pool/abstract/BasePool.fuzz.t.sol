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
import {IPool} from "src/pool/interfaces/IPool.sol";
import {MockHookReceiver} from "../../hooks/mocks/MockHookReceiver.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockFlashBorrower} from "../mocks/MockFlashBorrower.sol";
import {BasePoolHarness} from "./mocks/BasePoolHarness.sol";

contract BasePoolFuzzTest is Test {
    BasePoolHarness pool;
    MockHookReceiver hookReceiver;
    MockERC20 asset;
    MockFlashBorrower borrower;

    address defaultAdmin = makeAddr("defaultAdmin");
    address hookUpdater = makeAddr("hookUpdater");
    address flashLoanConfigurator = makeAddr("flashLoanConfigurator");
    address lendingCore = makeAddr("lendingCore");

    uint256 constant POOL_BALANCE = 2000e18;

    function setUp() public {
        BasePoolHarness implementation = new BasePoolHarness();
        pool = BasePoolHarness(Clones.clone(address(implementation)));
        pool.initialize(defaultAdmin, hookUpdater, flashLoanConfigurator, address(0), 0, 0, lendingCore, true);
        hookReceiver = new MockHookReceiver();
        asset = new MockERC20();
        pool.setAsset(address(asset));
        borrower = new MockFlashBorrower();
    }

    // depositCollateral()

    function testFuzz_DepositCollateral_ForwardsArguments(
        address caller,
        uint256 assets,
        uint256 shares,
        address receiver
    ) public {
        vm.expectEmit(address(pool));
        emit BasePoolHarness.DepositCollateralCalled(caller, assets, shares, receiver);

        vm.prank(lendingCore);
        pool.depositCollateral(caller, assets, shares, receiver);
    }

    function testFuzz_DepositCollateral_FiresHooksWithArguments(
        address caller,
        uint256 assets,
        uint256 shares,
        address receiver
    ) public {
        _configureHooks(ActionLib.POOL_DEPOSIT_COLLATERAL);

        vm.expectCall(
            address(hookReceiver),
            abi.encodeCall(
                IHookReceiver.onHook,
                (
                    address(pool),
                    Phase.BEFORE,
                    ActionLib.POOL_DEPOSIT_COLLATERAL,
                    abi.encode(receiver, caller, assets, shares)
                )
            ),
            1
        );
        vm.expectCall(
            address(hookReceiver),
            abi.encodeCall(
                IHookReceiver.onHook,
                (
                    address(pool),
                    Phase.AFTER,
                    ActionLib.POOL_DEPOSIT_COLLATERAL,
                    abi.encode(receiver, caller, assets, shares)
                )
            ),
            1
        );

        vm.prank(lendingCore);
        pool.depositCollateral(caller, assets, shares, receiver);
    }

    function testFuzz_DepositCollateral_ReturnsAmountsResolvedByInternal(
        address caller,
        uint256 assets,
        uint256 shares,
        address receiver,
        uint256 resolvedAssets,
        uint256 resolvedShares
    ) public {
        pool.setCollateralResult(resolvedAssets, resolvedShares);

        vm.prank(lendingCore);
        (uint256 assetsDeposited, uint256 sharesMinted) = pool.depositCollateral(caller, assets, shares, receiver);

        assertEq(assetsDeposited, resolvedAssets);
        assertEq(sharesMinted, resolvedShares);
    }

    function testFuzz_DepositCollateral_Revert_WhenCallerIsNotLendingCore(
        uint160 unauthorizedSeed,
        address caller,
        uint256 assets,
        uint256 shares,
        address receiver
    ) public {
        address unauthorized = _boundUnauthorized(unauthorizedSeed);

        vm.expectRevert(BasePool.NotLendingCoreCaller.selector);
        vm.prank(unauthorized);
        pool.depositCollateral(caller, assets, shares, receiver);
    }

    // withdrawCollateral()

    function testFuzz_WithdrawCollateral_ForwardsArguments(
        address caller,
        uint256 assets,
        uint256 shares,
        address receiver
    ) public {
        vm.expectEmit(address(pool));
        emit BasePoolHarness.WithdrawCollateralCalled(caller, assets, shares, receiver);

        vm.prank(lendingCore);
        pool.withdrawCollateral(caller, assets, shares, receiver);
    }

    function testFuzz_WithdrawCollateral_FiresHooksWithArguments(
        address caller,
        uint256 assets,
        uint256 shares,
        address receiver
    ) public {
        _configureHooks(ActionLib.POOL_WITHDRAW_COLLATERAL);

        bytes memory hookData = abi.encode(caller, receiver, assets, shares);
        _expectBeforeAndAfterHooks(ActionLib.POOL_WITHDRAW_COLLATERAL, hookData);

        vm.prank(lendingCore);
        pool.withdrawCollateral(caller, assets, shares, receiver);
    }

    function testFuzz_WithdrawCollateral_ReturnsAmountsResolvedByInternal(
        address caller,
        uint256 assets,
        uint256 shares,
        address receiver,
        uint256 resolvedAssets,
        uint256 resolvedShares
    ) public {
        pool.setCollateralResult(resolvedAssets, resolvedShares);

        vm.prank(lendingCore);
        (uint256 assetsWithdrawn, uint256 sharesBurned) = pool.withdrawCollateral(caller, assets, shares, receiver);

        assertEq(assetsWithdrawn, resolvedAssets);
        assertEq(sharesBurned, resolvedShares);
    }

    function testFuzz_WithdrawCollateral_Revert_WhenCallerIsNotLendingCore(
        uint160 unauthorizedSeed,
        address caller,
        uint256 assets,
        uint256 shares,
        address receiver
    ) public {
        address unauthorized = _boundUnauthorized(unauthorizedSeed);

        vm.expectRevert(BasePool.NotLendingCoreCaller.selector);
        vm.prank(unauthorized);
        pool.withdrawCollateral(caller, assets, shares, receiver);
    }

    // seizeCollateral()

    function testFuzz_SeizeCollateral_ForwardsArguments(address violator, uint256 assets, address receiver) public {
        vm.expectEmit(address(pool));
        emit BasePoolHarness.SeizeCollateralCalled(violator, assets, receiver);

        vm.prank(lendingCore);
        pool.seizeCollateral(violator, assets, receiver);
    }

    function testFuzz_SeizeCollateral_FiresHooksWithArguments(address violator, uint256 assets, address receiver)
        public
    {
        _configureHooks(ActionLib.POOL_SEIZE_COLLATERAL);

        bytes memory beforeData = abi.encode(violator, receiver, assets);
        bytes memory afterData = abi.encode(violator, receiver, assets, uint256(0));
        _expectBeforeAndAfterHooks(ActionLib.POOL_SEIZE_COLLATERAL, beforeData, afterData);

        vm.prank(lendingCore);
        pool.seizeCollateral(violator, assets, receiver);
    }

    function testFuzz_SeizeCollateral_ReturnsAmountsResolvedByInternal(
        address violator,
        uint256 assets,
        address receiver,
        uint256 resolvedAssets,
        uint256 resolvedShares
    ) public {
        pool.setCollateralResult(resolvedAssets, resolvedShares);

        vm.prank(lendingCore);
        (uint256 assetsSeized, uint256 sharesSeized) = pool.seizeCollateral(violator, assets, receiver);

        assertEq(assetsSeized, resolvedAssets);
        assertEq(sharesSeized, resolvedShares);
    }

    function testFuzz_SeizeCollateral_Revert_WhenCallerIsNotLendingCore(
        uint160 unauthorizedSeed,
        address violator,
        uint256 assets,
        address receiver
    ) public {
        address unauthorized = _boundUnauthorized(unauthorizedSeed);

        vm.expectRevert(BasePool.NotLendingCoreCaller.selector);
        vm.prank(unauthorized);
        pool.seizeCollateral(violator, assets, receiver);
    }

    // borrow()

    function testFuzz_Borrow_ForwardsArguments(address caller, uint256 amount, address receiver) public {
        vm.expectEmit(address(pool));
        emit BasePoolHarness.BorrowCalled(caller, amount, receiver);

        vm.prank(lendingCore);
        pool.borrow(caller, amount, receiver);
    }

    function testFuzz_Borrow_FiresHooksWithArguments(address caller, uint256 amount, address receiver) public {
        _configureHooks(ActionLib.POOL_BORROW);

        vm.expectCall(
            address(hookReceiver),
            abi.encodeCall(
                IHookReceiver.onHook,
                (address(pool), Phase.BEFORE, ActionLib.POOL_BORROW, abi.encode(caller, receiver, amount))
            ),
            1
        );
        vm.expectCall(
            address(hookReceiver),
            abi.encodeCall(
                IHookReceiver.onHook,
                (address(pool), Phase.AFTER, ActionLib.POOL_BORROW, abi.encode(caller, receiver, amount))
            ),
            1
        );

        vm.prank(lendingCore);
        pool.borrow(caller, amount, receiver);
    }

    function testFuzz_Borrow_Revert_WhenCallerIsNotLendingCore(
        uint160 unauthorizedSeed,
        address caller,
        uint256 amount,
        address receiver
    ) public {
        address unauthorized = _boundUnauthorized(unauthorizedSeed);

        vm.expectRevert(BasePool.NotLendingCoreCaller.selector);
        vm.prank(unauthorized);
        pool.borrow(caller, amount, receiver);
    }

    // repay()

    function testFuzz_Repay_ForwardsArguments(address caller, uint256 amount, address receiver) public {
        vm.expectEmit(address(pool));
        emit BasePoolHarness.RepayCalled(caller, amount, receiver);

        vm.prank(lendingCore);
        pool.repay(caller, amount, receiver);
    }

    function testFuzz_Repay_FiresHooksWithArguments(address caller, uint256 amount, address receiver, uint256 repayment)
        public
    {
        pool.setRepayment(repayment);
        _configureHooks(ActionLib.POOL_REPAY);

        bytes memory beforeData = abi.encode(receiver, caller, amount);
        bytes memory afterData = abi.encode(receiver, caller, repayment);
        _expectBeforeAndAfterHooks(ActionLib.POOL_REPAY, beforeData, afterData);

        vm.prank(lendingCore);
        pool.repay(caller, amount, receiver);
    }

    function testFuzz_Repay_Revert_WhenCallerIsNotLendingCore(
        uint160 unauthorizedSeed,
        address caller,
        uint256 amount,
        address receiver
    ) public {
        address unauthorized = _boundUnauthorized(unauthorizedSeed);

        vm.expectRevert(BasePool.NotLendingCoreCaller.selector);
        vm.prank(unauthorized);
        pool.repay(caller, amount, receiver);
    }

    // writeOffDebt()

    function testFuzz_WriteOffDebt_ForwardsArguments(address account) public {
        vm.expectEmit(address(pool));
        emit BasePoolHarness.WriteOffDebtCalled(account);

        vm.prank(lendingCore);
        pool.writeOffDebt(account);
    }

    function testFuzz_WriteOffDebt_FiresHooksWithArguments(address account, uint256 writtenOff) public {
        pool.setWrittenOff(writtenOff);
        _configureHooks(ActionLib.POOL_WRITE_OFF_DEBT);

        bytes memory beforeData = abi.encode(account);
        bytes memory afterData = abi.encode(account, writtenOff);
        _expectBeforeAndAfterHooks(ActionLib.POOL_WRITE_OFF_DEBT, beforeData, afterData);

        vm.prank(lendingCore);
        pool.writeOffDebt(account);
    }

    function testFuzz_WriteOffDebt_Revert_WhenCallerIsNotLendingCore(uint160 unauthorizedSeed, address account) public {
        address unauthorized = _boundUnauthorized(unauthorizedSeed);

        vm.expectRevert(BasePool.NotLendingCoreCaller.selector);
        vm.prank(unauthorized);
        pool.writeOffDebt(account);
    }

    // flashLoan()

    function testFuzz_FlashLoan_FiresHooksWithArguments(address initiator, uint256 amount) public {
        amount = bound(amount, 1, POOL_BALANCE);
        asset.mint(address(pool), POOL_BALANCE);
        _configureHooks(ActionLib.POOL_FLASH_LOAN);

        _expectBeforeAndAfterHooks(ActionLib.POOL_FLASH_LOAN, abi.encode(initiator, address(borrower), amount));

        vm.prank(initiator);
        pool.flashLoan(borrower, address(asset), amount, "");
    }

    // supportsInterface()

    function testFuzz_SupportsInterface_Unknown_ReturnsFalse(bytes4 interfaceId) public view {
        interfaceId = _unsupportedInterfaceId(interfaceId);

        assertFalse(pool.supportsInterface(interfaceId));
    }

    function _configureHooks(uint8 action) internal {
        vm.startPrank(hookUpdater);
        pool.setHookReceiver(address(hookReceiver));
        pool.setHookBitmaps(_bit(action), _bit(action));
        vm.stopPrank();
    }

    function _expectBeforeAndAfterHooks(uint8 action, bytes memory data) internal {
        _expectBeforeAndAfterHooks(action, data, data);
    }

    function _expectBeforeAndAfterHooks(uint8 action, bytes memory beforeData, bytes memory afterData) internal {
        vm.expectCall(
            address(hookReceiver),
            abi.encodeCall(IHookReceiver.onHook, (address(pool), Phase.BEFORE, action, beforeData)),
            1
        );
        vm.expectCall(
            address(hookReceiver),
            abi.encodeCall(IHookReceiver.onHook, (address(pool), Phase.AFTER, action, afterData)),
            1
        );
    }

    function _boundUnauthorized(uint160 seed) internal view returns (address) {
        uint160 unauthorized = uint160(bound(seed, 1, type(uint160).max));
        uint160 lendingCore_ = uint160(lendingCore);

        if (unauthorized == lendingCore_) {
            unauthorized = lendingCore_ == type(uint160).max ? lendingCore_ - 1 : lendingCore_ + 1;
        }

        return address(unauthorized);
    }

    function _unsupportedInterfaceId(bytes4 interfaceId) internal pure returns (bytes4) {
        if (
            interfaceId == type(IPool).interfaceId || interfaceId == type(IERC3156FlashLender).interfaceId
                || interfaceId == type(IERC165).interfaceId || interfaceId == type(IVersioned).interfaceId
                || interfaceId == type(IAccessControl).interfaceId
                || interfaceId == type(IAccessControlEnumerable).interfaceId
        ) {
            return 0xffffffff;
        }

        return interfaceId;
    }

    function _bit(uint8 action) internal pure returns (uint256) {
        return uint256(1) << action;
    }
}
