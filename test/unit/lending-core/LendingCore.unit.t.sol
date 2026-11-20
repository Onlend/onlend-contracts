// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IAccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {Authorisable} from "src/authorisation/abstract/Authorisable.sol";
import {IAuthorisable} from "src/authorisation/interfaces/IAuthorisable.sol";
import {Phase} from "src/hooks/interfaces/IHookReceiver.sol";
import {ActionLib} from "src/hooks/lib/ActionLib.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IPool} from "src/pool/interfaces/IPool.sol";
import {ILendingCore} from "src/lending-core/interfaces/ILendingCore.sol";
import {LendingCore} from "src/lending-core/LendingCore.sol";
import {ILiquidationEngine} from "src/liquidation/interfaces/ILiquidationEngine.sol";
import {ILoanEvaluator} from "src/loan/interfaces/ILoanEvaluator.sol";
import {MockLoanEvaluator} from "../loan/mocks/MockLoanEvaluator.sol";
import {MockLiquidationEngine} from "../liquidation/mocks/MockLiquidationEngine.sol";
import {MockPool} from "../pool/mocks/MockPool.sol";
import {MockHookReceiver} from "../hooks/mocks/MockHookReceiver.sol";
import {LoanHelpers} from "../../helpers/LoanHelpers.sol";

contract LendingCoreUnitTest is Test {
    string internal constant INITIAL_METADATA = '{"name":"Onlend"}';
    string internal constant UPDATED_METADATA = '{"name":"Updated Onlend"}';

    address internal defaultAdmin;
    address internal hookUpdater;
    address internal poolLister;
    address internal loanUpdater;
    address internal liquidationUpdater;
    address internal badDebtConfigurator;
    address internal metadataConfigurator;

    MockLoanEvaluator internal loanEvaluator;
    MockLiquidationEngine internal liquidationEngine;
    MockPool internal pool;
    MockHookReceiver internal hookReceiver;
    LendingCore internal implementation;
    LendingCore internal lendingCore;

    function setUp() public {
        defaultAdmin = makeAddr("defaultAdmin");
        hookUpdater = makeAddr("hookUpdater");
        poolLister = makeAddr("poolLister");
        loanUpdater = makeAddr("loanUpdater");
        liquidationUpdater = makeAddr("liquidationUpdater");
        badDebtConfigurator = makeAddr("badDebtConfigurator");
        metadataConfigurator = makeAddr("metadataConfigurator");

        loanEvaluator = new MockLoanEvaluator();
        liquidationEngine = new MockLiquidationEngine();
        pool = new MockPool();
        hookReceiver = new MockHookReceiver();
        implementation = new LendingCore();

        lendingCore = _deployLendingCore(
            address(loanEvaluator),
            address(liquidationEngine),
            defaultAdmin,
            hookUpdater,
            poolLister,
            loanUpdater,
            liquidationUpdater,
            badDebtConfigurator,
            metadataConfigurator
        );
    }

    // initialize()

    function test_initialize_GrantsRoles() public view {
        assertTrue(lendingCore.hasRole(lendingCore.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertTrue(lendingCore.hasRole(lendingCore.HOOK_UPDATER_ROLE(), hookUpdater));
        assertTrue(lendingCore.hasRole(lendingCore.POOL_LISTING_ROLE(), poolLister));
        assertTrue(lendingCore.hasRole(lendingCore.LOAN_UPDATER_ROLE(), loanUpdater));
        assertTrue(lendingCore.hasRole(lendingCore.LIQUIDATION_UPDATER_ROLE(), liquidationUpdater));
        assertTrue(lendingCore.hasRole(lendingCore.BAD_DEBT_CONFIG_ROLE(), badDebtConfigurator));
        assertTrue(lendingCore.hasRole(lendingCore.METADATA_CONFIG_ROLE(), metadataConfigurator));
    }

    function test_initialize_UsesDefaultAdminAsRoleAdmin() public view {
        assertEq(lendingCore.getRoleAdmin(lendingCore.POOL_LISTING_ROLE()), lendingCore.DEFAULT_ADMIN_ROLE());
        assertEq(lendingCore.getRoleAdmin(lendingCore.LOAN_UPDATER_ROLE()), lendingCore.DEFAULT_ADMIN_ROLE());
        assertEq(lendingCore.getRoleAdmin(lendingCore.LIQUIDATION_UPDATER_ROLE()), lendingCore.DEFAULT_ADMIN_ROLE());
        assertEq(lendingCore.getRoleAdmin(lendingCore.BAD_DEBT_CONFIG_ROLE()), lendingCore.DEFAULT_ADMIN_ROLE());
        assertEq(lendingCore.getRoleAdmin(lendingCore.METADATA_CONFIG_ROLE()), lendingCore.DEFAULT_ADMIN_ROLE());
    }

    function test_initialize_AllowsZeroAddressRoleMembers() public {
        LendingCore rolelessLendingCore = _deployLendingCore(
            address(loanEvaluator),
            address(liquidationEngine),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0)
        );

        assertEq(rolelessLendingCore.getRoleMemberCount(rolelessLendingCore.DEFAULT_ADMIN_ROLE()), 0);
        assertEq(rolelessLendingCore.getRoleMemberCount(rolelessLendingCore.HOOK_UPDATER_ROLE()), 0);
        assertEq(rolelessLendingCore.getRoleMemberCount(rolelessLendingCore.POOL_LISTING_ROLE()), 0);
        assertEq(rolelessLendingCore.getRoleMemberCount(rolelessLendingCore.LOAN_UPDATER_ROLE()), 0);
        assertEq(rolelessLendingCore.getRoleMemberCount(rolelessLendingCore.LIQUIDATION_UPDATER_ROLE()), 0);
        assertEq(rolelessLendingCore.getRoleMemberCount(rolelessLendingCore.BAD_DEBT_CONFIG_ROLE()), 0);
        assertEq(rolelessLendingCore.getRoleMemberCount(rolelessLendingCore.METADATA_CONFIG_ROLE()), 0);
    }

    function test_initialize_SetsEip712Domain() public view {
        (, string memory name, string memory version,,,,) = lendingCore.eip712Domain();

        assertEq(name, "LendingCore");
        assertEq(version, "1");
    }

    function test_initialize_SetsLoanEvaluator() public view {
        assertEq(lendingCore.loanEvaluator(), address(loanEvaluator));
    }

    function test_initialize_SetsLiquidationEngine() public view {
        assertEq(lendingCore.liquidationEngine(), address(liquidationEngine));
    }

    function test_initialize_EnablesBadDebtSocialisation() public {
        LendingCore socialisingLendingCore = _deployLendingCore(
            address(loanEvaluator),
            address(liquidationEngine),
            defaultAdmin,
            hookUpdater,
            poolLister,
            loanUpdater,
            liquidationUpdater,
            badDebtConfigurator,
            metadataConfigurator,
            true,
            new address[](0)
        );

        assertTrue(socialisingLendingCore.socialiseBadDebt());
    }

    function test_initialize_DisablesBadDebtSocialisation() public view {
        assertFalse(lendingCore.socialiseBadDebt());
    }

    function test_initialize_EmitsBadDebtSocialisationSet() public {
        vm.expectEmit();
        emit LendingCore.BadDebtSocialisationSet(true);

        _deployLendingCore(
            address(loanEvaluator),
            address(liquidationEngine),
            defaultAdmin,
            hookUpdater,
            poolLister,
            loanUpdater,
            liquidationUpdater,
            badDebtConfigurator,
            metadataConfigurator,
            true,
            new address[](0)
        );
    }

    function test_initialize_EmitsMetadataSet() public {
        vm.expectEmit();
        emit LendingCore.MetadataSet(INITIAL_METADATA);

        _deployLendingCore(
            address(loanEvaluator),
            address(liquidationEngine),
            defaultAdmin,
            hookUpdater,
            poolLister,
            loanUpdater,
            liquidationUpdater,
            badDebtConfigurator,
            metadataConfigurator
        );
    }

    function test_initialize_AllowsNoInitialPools() public view {
        assertEq(uint256(lendingCore.poolStatus(address(pool))), uint256(LendingCore.PoolStatus.NONE));
    }

    function test_initialize_ListsInitialPoolsAsActive() public {
        MockPool secondPool = new MockPool();
        address[] memory initialPools = _poolAddresses(address(pool), address(secondPool));

        LendingCore initializedLendingCore = _deployLendingCore(
            address(loanEvaluator),
            address(liquidationEngine),
            defaultAdmin,
            hookUpdater,
            poolLister,
            loanUpdater,
            liquidationUpdater,
            badDebtConfigurator,
            metadataConfigurator,
            false,
            initialPools
        );

        assertEq(uint256(initializedLendingCore.poolStatus(address(pool))), uint256(LendingCore.PoolStatus.ACTIVE));
        assertEq(
            uint256(initializedLendingCore.poolStatus(address(secondPool))), uint256(LendingCore.PoolStatus.ACTIVE)
        );
    }

    function test_initialize_RevertsWhenLoanEvaluatorIsInvalid() public {
        address invalidLoanEvaluator = makeAddr("invalidLoanEvaluator");
        LendingCore instance = LendingCore(Clones.clone(address(implementation)));

        vm.expectRevert(abi.encodeWithSelector(LendingCore.InvalidLoanEvaluator.selector, invalidLoanEvaluator));
        instance.initialize(
            invalidLoanEvaluator,
            address(liquidationEngine),
            defaultAdmin,
            hookUpdater,
            address(0),
            0,
            0,
            poolLister,
            loanUpdater,
            liquidationUpdater,
            badDebtConfigurator,
            metadataConfigurator,
            false,
            INITIAL_METADATA,
            new address[](0)
        );
    }

    function test_initialize_RevertsWhenLiquidationEngineIsInvalid() public {
        address invalidLiquidationEngine = makeAddr("invalidLiquidationEngine");
        LendingCore instance = LendingCore(Clones.clone(address(implementation)));

        vm.expectRevert(abi.encodeWithSelector(LendingCore.InvalidLiquidationEngine.selector, invalidLiquidationEngine));
        instance.initialize(
            address(loanEvaluator),
            invalidLiquidationEngine,
            defaultAdmin,
            hookUpdater,
            address(0),
            0,
            0,
            poolLister,
            loanUpdater,
            liquidationUpdater,
            badDebtConfigurator,
            metadataConfigurator,
            false,
            INITIAL_METADATA,
            new address[](0)
        );
    }

    // setLoanEvaluator()

    function test_setLoanEvaluator_SetsLoanEvaluator() public {
        MockLoanEvaluator newLoanEvaluator = new MockLoanEvaluator();

        vm.expectEmit(true, true, false, false);
        emit LendingCore.LoanEvaluatorSet(address(loanEvaluator), address(newLoanEvaluator));

        vm.prank(loanUpdater);
        lendingCore.setLoanEvaluator(address(newLoanEvaluator));

        assertEq(lendingCore.loanEvaluator(), address(newLoanEvaluator));
    }

    function test_setLoanEvaluator_RevertsWhenLoanEvaluatorIsInvalid() public {
        address invalidLoanEvaluator = makeAddr("invalidLoanEvaluator");

        vm.expectRevert(abi.encodeWithSelector(LendingCore.InvalidLoanEvaluator.selector, invalidLoanEvaluator));
        vm.prank(loanUpdater);
        lendingCore.setLoanEvaluator(invalidLoanEvaluator);
    }

    function test_setLoanEvaluator_RevertsWhenCallerIsNotLoanUpdater() public {
        address nonLoanUpdater = makeAddr("nonLoanUpdater");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonLoanUpdater,
                lendingCore.LOAN_UPDATER_ROLE()
            )
        );
        vm.prank(nonLoanUpdater);
        lendingCore.setLoanEvaluator(address(loanEvaluator));
    }

    // setLiquidationEngine()

    function test_setLiquidationEngine_SetsLiquidationEngine() public {
        MockLiquidationEngine newLiquidationEngine = new MockLiquidationEngine();

        vm.expectEmit(true, true, false, false);
        emit LendingCore.LiquidationEngineSet(address(liquidationEngine), address(newLiquidationEngine));

        vm.prank(liquidationUpdater);
        lendingCore.setLiquidationEngine(address(newLiquidationEngine));

        assertEq(lendingCore.liquidationEngine(), address(newLiquidationEngine));
    }

    function test_setLiquidationEngine_RevertsWhenLiquidationEngineIsInvalid() public {
        address invalidLiquidationEngine = makeAddr("invalidLiquidationEngine");

        vm.expectRevert(abi.encodeWithSelector(LendingCore.InvalidLiquidationEngine.selector, invalidLiquidationEngine));
        vm.prank(liquidationUpdater);
        lendingCore.setLiquidationEngine(invalidLiquidationEngine);
    }

    function test_setLiquidationEngine_RevertsWhenCallerIsNotLiquidationUpdater() public {
        address nonLiquidationUpdater = makeAddr("nonLiquidationUpdater");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonLiquidationUpdater,
                lendingCore.LIQUIDATION_UPDATER_ROLE()
            )
        );
        vm.prank(nonLiquidationUpdater);
        lendingCore.setLiquidationEngine(address(liquidationEngine));
    }

    // setSocialiseBadDebt()

    function test_setSocialiseBadDebt_EnablesBadDebtSocialisation() public {
        vm.prank(badDebtConfigurator);
        lendingCore.setSocialiseBadDebt(true);

        assertTrue(lendingCore.socialiseBadDebt());
    }

    function test_setSocialiseBadDebt_DisablesBadDebtSocialisation() public {
        vm.prank(badDebtConfigurator);
        lendingCore.setSocialiseBadDebt(true);

        vm.prank(badDebtConfigurator);
        lendingCore.setSocialiseBadDebt(false);

        assertFalse(lendingCore.socialiseBadDebt());
    }

    function test_setSocialiseBadDebt_EmitsBadDebtSocialisationSet() public {
        vm.expectEmit(address(lendingCore));
        emit LendingCore.BadDebtSocialisationSet(true);

        vm.prank(badDebtConfigurator);
        lendingCore.setSocialiseBadDebt(true);
    }

    function test_setSocialiseBadDebt_RevertsWhenAlreadyEnabled() public {
        vm.prank(badDebtConfigurator);
        lendingCore.setSocialiseBadDebt(true);

        vm.expectRevert(abi.encodeWithSelector(LendingCore.SocialiseBadDebtUnchanged.selector, true));
        vm.prank(badDebtConfigurator);
        lendingCore.setSocialiseBadDebt(true);
    }

    function test_setSocialiseBadDebt_RevertsWhenAlreadyDisabled() public {
        vm.expectRevert(abi.encodeWithSelector(LendingCore.SocialiseBadDebtUnchanged.selector, false));
        vm.prank(badDebtConfigurator);
        lendingCore.setSocialiseBadDebt(false);
    }

    function test_setSocialiseBadDebt_RevertsWhenCallerIsNotBadDebtConfigurator() public {
        address nonBadDebtConfigurator = makeAddr("nonBadDebtConfigurator");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonBadDebtConfigurator,
                lendingCore.BAD_DEBT_CONFIG_ROLE()
            )
        );
        vm.prank(nonBadDebtConfigurator);
        lendingCore.setSocialiseBadDebt(true);
    }

    // setMetadata()

    function test_setMetadata_EmitsMetadataSet() public {
        vm.expectEmit();
        emit LendingCore.MetadataSet(UPDATED_METADATA);

        vm.prank(metadataConfigurator);
        lendingCore.setMetadata(UPDATED_METADATA);
    }

    function test_setMetadata_RevertsWhenCallerIsNotMetadataConfigurator() public {
        address unauthorizedAccount = makeAddr("unauthorizedAccount");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorizedAccount,
                lendingCore.METADATA_CONFIG_ROLE()
            )
        );
        vm.prank(unauthorizedAccount);
        lendingCore.setMetadata(UPDATED_METADATA);
    }

    // addPool()

    function test_addPool_AddsPool() public {
        vm.expectEmit();
        emit LendingCore.PoolAdded(address(pool));

        vm.prank(poolLister);
        lendingCore.addPool(address(pool));

        assertTrue(lendingCore.isPoolAdded(address(pool)));
    }

    function test_addPool_RevertsWhenPoolIsInvalid() public {
        address invalidPool = makeAddr("invalidPool");

        vm.expectRevert(abi.encodeWithSelector(LendingCore.InvalidPool.selector, invalidPool));
        vm.prank(poolLister);
        lendingCore.addPool(invalidPool);
    }

    function test_addPool_RevertsWhenPoolIsAlreadyAdded() public {
        vm.prank(poolLister);
        lendingCore.addPool(address(pool));

        vm.expectRevert(abi.encodeWithSelector(LendingCore.PoolAlreadyAdded.selector, address(pool)));
        vm.prank(poolLister);
        lendingCore.addPool(address(pool));
    }

    function test_addPool_RevertsWhenCallerIsNotPoolLister() public {
        address nonPoolLister = makeAddr("nonPoolLister");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonPoolLister, lendingCore.POOL_LISTING_ROLE()
            )
        );
        vm.prank(nonPoolLister);
        lendingCore.addPool(address(pool));
    }

    // setDeprecatePool()

    function test_setDeprecatePool_DeprecatesPool() public {
        _addPool();

        vm.expectEmit();
        emit LendingCore.PoolDeprecationSet(address(pool), true);

        vm.prank(poolLister);
        lendingCore.setDeprecatePool(address(pool), true);

        assertEq(uint256(lendingCore.poolStatus(address(pool))), uint256(LendingCore.PoolStatus.DEPRECATED));
        assertTrue(lendingCore.isPoolAdded(address(pool)));
    }

    function test_setDeprecatePool_ReactivatesPool() public {
        _addAndDeprecatePool();

        vm.expectEmit();
        emit LendingCore.PoolDeprecationSet(address(pool), false);

        vm.prank(poolLister);
        lendingCore.setDeprecatePool(address(pool), false);

        assertEq(uint256(lendingCore.poolStatus(address(pool))), uint256(LendingCore.PoolStatus.ACTIVE));
    }

    function test_setDeprecatePool_RevertsWhenPoolIsNotListed() public {
        vm.expectRevert(abi.encodeWithSelector(LendingCore.PoolNotListed.selector, address(pool)));
        vm.prank(poolLister);
        lendingCore.setDeprecatePool(address(pool), true);
    }

    function test_setDeprecatePool_RevertsWhenPoolIsAlreadyDeprecated() public {
        _addAndDeprecatePool();

        vm.expectRevert(abi.encodeWithSelector(LendingCore.PoolDeprecatedUnchanged.selector, address(pool), true));
        vm.prank(poolLister);
        lendingCore.setDeprecatePool(address(pool), true);
    }

    function test_setDeprecatePool_RevertsWhenPoolIsAlreadyActive() public {
        _addPool();

        vm.expectRevert(abi.encodeWithSelector(LendingCore.PoolDeprecatedUnchanged.selector, address(pool), false));
        vm.prank(poolLister);
        lendingCore.setDeprecatePool(address(pool), false);
    }

    function test_setDeprecatePool_RevertsWhenCallerIsNotPoolLister() public {
        _addPool();

        address nonPoolLister = makeAddr("nonPoolLister");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonPoolLister, lendingCore.POOL_LISTING_ROLE()
            )
        );
        vm.prank(nonPoolLister);
        lendingCore.setDeprecatePool(address(pool), true);
    }

    // depositCollateral()

    function test_depositCollateral_ForwardsToPool() public {
        address user = makeAddr("user");
        address onBehalfOf = makeAddr("onBehalfOf");
        uint256 assets = 100;
        uint256 shares = 0;
        _addPool();

        vm.expectCall(address(pool), abi.encodeCall(IPool.depositCollateral, (user, assets, shares, onBehalfOf)));

        vm.prank(user);
        lendingCore.depositCollateral(IPool(address(pool)), assets, shares, onBehalfOf);
    }

    function test_depositCollateral_ForwardsZeroAmounts() public {
        address user = makeAddr("user");
        address onBehalfOf = makeAddr("onBehalfOf");
        _addPool();

        vm.expectCall(address(pool), abi.encodeCall(IPool.depositCollateral, (user, 0, 0, onBehalfOf)));

        vm.prank(user);
        lendingCore.depositCollateral(IPool(address(pool)), 0, 0, onBehalfOf);
    }

    function test_depositCollateral_ReturnsAmountsResolvedByPool() public {
        address user = makeAddr("user");
        address onBehalfOf = makeAddr("onBehalfOf");
        _addPool();
        pool.setResolvedCollateral(100, 80);

        vm.prank(user);
        (uint256 assetsDeposited, uint256 sharesMinted) =
            lendingCore.depositCollateral(IPool(address(pool)), 0, 80, onBehalfOf);

        assertEq(assetsDeposited, 100);
        assertEq(sharesMinted, 80);
    }

    function test_depositCollateral_EmitsCollateralDeposited() public {
        address user = makeAddr("user");
        address onBehalfOf = makeAddr("onBehalfOf");
        _addPool();
        pool.setResolvedCollateral(100, 80);

        vm.expectEmit(address(lendingCore));
        emit LendingCore.CollateralDeposited(IPool(address(pool)), onBehalfOf, user, 100, 80);

        vm.prank(user);
        lendingCore.depositCollateral(IPool(address(pool)), 0, 80, onBehalfOf);
    }

    function test_depositCollateral_FiresBeforeAndAfterHooks() public {
        address user = makeAddr("user");
        address onBehalfOf = makeAddr("onBehalfOf");
        uint256 assets = 0;
        uint256 shares = 80;
        _addPool();
        pool.setResolvedCollateral(100, shares);
        _enableHooks(ActionLib.LC_DEPOSIT_COLLATERAL);
        bytes memory beforeData = abi.encode(onBehalfOf, user, user, address(pool), assets, shares);
        bytes memory afterData = abi.encode(onBehalfOf, user, user, address(pool), uint256(100), shares);

        _expectBeforeAndAfterHooks(ActionLib.LC_DEPOSIT_COLLATERAL, beforeData, afterData);

        vm.prank(user);
        lendingCore.depositCollateral(IPool(address(pool)), assets, shares, onBehalfOf);
    }

    function test_depositCollateral_RevertsWhenPoolIsNotListed() public {
        address onBehalfOf = makeAddr("onBehalfOf");

        vm.expectRevert(abi.encodeWithSelector(LendingCore.PoolNotListed.selector, address(pool)));
        lendingCore.depositCollateral(IPool(address(pool)), 100, 0, onBehalfOf);
    }

    function test_depositCollateral_RevertsWhenPoolIsDeprecated() public {
        address onBehalfOf = makeAddr("onBehalfOf");
        _addAndDeprecatePool();

        vm.expectRevert(abi.encodeWithSelector(LendingCore.PoolDeprecated.selector, address(pool)));
        lendingCore.depositCollateral(IPool(address(pool)), 100, 0, onBehalfOf);
    }

    function test_depositCollateral_RevertsWhenReentered() public {
        address user = makeAddr("user");
        address receiver = makeAddr("receiver");
        _addPool();
        pool.setBorrowReentry(
            address(lendingCore), abi.encodeCall(ILendingCore.depositCollateral, (IPool(address(pool)), 100, 0, user))
        );

        vm.expectRevert(abi.encodeWithSelector(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector));
        vm.prank(user);
        lendingCore.borrow(IPool(address(pool)), 100, user, receiver);
    }

    // withdrawCollateral()

    function test_withdrawCollateral_ForwardsToPool() public {
        address user = makeAddr("user");
        address receiver = makeAddr("receiver");
        uint256 assets = 100;
        uint256 shares = 0;
        _addPool();

        vm.expectCall(address(pool), abi.encodeCall(IPool.withdrawCollateral, (user, assets, shares, receiver)));

        vm.prank(user);
        lendingCore.withdrawCollateral(IPool(address(pool)), assets, shares, user, receiver);
    }

    function test_withdrawCollateral_ForwardsToPoolWhenCallerIsAuthorised() public {
        address user = makeAddr("user");
        address operator = makeAddr("operator");
        address receiver = makeAddr("receiver");
        uint256 assets = 100;
        uint256 shares = 0;
        _addPool();
        _authorise(user, operator);

        vm.expectCall(address(pool), abi.encodeCall(IPool.withdrawCollateral, (user, assets, shares, receiver)));

        vm.prank(operator);
        lendingCore.withdrawCollateral(IPool(address(pool)), assets, shares, user, receiver);
    }

    function test_withdrawCollateral_ForwardsToPoolWhenDeprecated() public {
        address user = makeAddr("user");
        address receiver = makeAddr("receiver");
        uint256 assets = 100;
        uint256 shares = 0;
        _addAndDeprecatePool();

        vm.expectCall(address(pool), abi.encodeCall(IPool.withdrawCollateral, (user, assets, shares, receiver)));

        vm.prank(user);
        lendingCore.withdrawCollateral(IPool(address(pool)), assets, shares, user, receiver);
    }

    function test_withdrawCollateral_ForwardsZeroAmounts() public {
        address user = makeAddr("user");
        address receiver = makeAddr("receiver");
        _addPool();

        vm.expectCall(address(pool), abi.encodeCall(IPool.withdrawCollateral, (user, 0, 0, receiver)));

        vm.prank(user);
        lendingCore.withdrawCollateral(IPool(address(pool)), 0, 0, user, receiver);
    }

    function test_withdrawCollateral_ReturnsAmountsResolvedByPool() public {
        address user = makeAddr("user");
        address receiver = makeAddr("receiver");
        _addPool();
        pool.setResolvedCollateral(100, 80);

        vm.prank(user);
        (uint256 assetsWithdrawn, uint256 sharesBurned) =
            lendingCore.withdrawCollateral(IPool(address(pool)), 0, 80, user, receiver);

        assertEq(assetsWithdrawn, 100);
        assertEq(sharesBurned, 80);
    }

    function test_withdrawCollateral_EvaluatesHealthOfOnBehalfOfLoan() public {
        address user = makeAddr("user");
        address operator = makeAddr("operator");
        address receiver = makeAddr("receiver");
        _addPool();
        _authorise(user, operator);
        pool.setCollateralOf(user, 100e18);
        pool.setDebtOf(user, 40e18);
        pool.setCollateralOf(operator, 999e18);
        pool.setDebtOf(operator, 999e18);

        vm.expectCall(address(loanEvaluator), abi.encodeCall(ILoanEvaluator.isLoanHealthy, (lendingCore.loanOf(user))));

        vm.prank(operator);
        lendingCore.withdrawCollateral(IPool(address(pool)), 100, 0, user, receiver);
    }

    function test_withdrawCollateral_EvaluatesHealthAfterWithdrawal() public {
        address user = makeAddr("user");
        address receiver = makeAddr("receiver");
        _addPool();
        pool.setCollateralOf(user, 100e18);
        pool.setCollateralOfAfterWithdraw(user, 60e18);
        ILendingCore.Loan memory loan;
        loan.account = user;
        loan.collaterals = LoanHelpers.positions(pool, 60e18);
        loan.borrows = LoanHelpers.noPositions();

        vm.expectCall(address(loanEvaluator), abi.encodeCall(ILoanEvaluator.isLoanHealthy, (loan)));

        vm.prank(user);
        lendingCore.withdrawCollateral(IPool(address(pool)), 40e18, 0, user, receiver);
    }

    function test_withdrawCollateral_EmitsCollateralWithdrawn() public {
        address user = makeAddr("user");
        address operator = makeAddr("operator");
        address receiver = makeAddr("receiver");
        _addPool();
        _authorise(user, operator);
        pool.setResolvedCollateral(100, 80);

        vm.expectEmit(address(lendingCore));
        emit LendingCore.CollateralWithdrawn(IPool(address(pool)), user, operator, receiver, 100, 80);

        vm.prank(operator);
        lendingCore.withdrawCollateral(IPool(address(pool)), 0, 80, user, receiver);
    }

    function test_withdrawCollateral_FiresBeforeAndAfterHooks() public {
        address user = makeAddr("user");
        address operator = makeAddr("operator");
        address receiver = makeAddr("receiver");
        uint256 assets = 0;
        uint256 shares = 80;
        _addPool();
        _authorise(user, operator);
        pool.setResolvedCollateral(100, shares);
        _enableHooks(ActionLib.LC_WITHDRAW_COLLATERAL);
        bytes memory beforeData = abi.encode(user, receiver, operator, address(pool), assets, shares);
        bytes memory afterData = abi.encode(user, receiver, operator, address(pool), uint256(100), shares);

        _expectBeforeAndAfterHooks(ActionLib.LC_WITHDRAW_COLLATERAL, beforeData, afterData);

        vm.prank(operator);
        lendingCore.withdrawCollateral(IPool(address(pool)), assets, shares, user, receiver);
    }

    function test_withdrawCollateral_RevertsWhenCallerIsNotAuthorised() public {
        address user = makeAddr("user");
        address operator = makeAddr("operator");
        address receiver = makeAddr("receiver");
        _addPool();

        vm.expectRevert(abi.encodeWithSelector(Authorisable.Unauthorised.selector, user, operator));
        vm.prank(operator);
        lendingCore.withdrawCollateral(IPool(address(pool)), 100, 0, user, receiver);
    }

    function test_withdrawCollateral_RevertsWhenPoolIsNotListed() public {
        address user = makeAddr("user");
        address receiver = makeAddr("receiver");

        vm.expectRevert(abi.encodeWithSelector(LendingCore.PoolNotListed.selector, address(pool)));
        vm.prank(user);
        lendingCore.withdrawCollateral(IPool(address(pool)), 100, 0, user, receiver);
    }

    function test_withdrawCollateral_RevertsWhenLoanIsUnhealthy() public {
        address user = makeAddr("user");
        address operator = makeAddr("operator");
        address receiver = makeAddr("receiver");
        _addPool();
        _authorise(user, operator);
        loanEvaluator.setHealthy(false);

        vm.expectRevert(abi.encodeWithSelector(LendingCore.LoanUnhealthy.selector, user));
        vm.prank(operator);
        lendingCore.withdrawCollateral(IPool(address(pool)), 100, 0, user, receiver);
    }

    function test_withdrawCollateral_RevertsWhenReentered() public {
        address user = makeAddr("user");
        address receiver = makeAddr("receiver");
        _addPool();
        pool.setBorrowReentry(
            address(lendingCore),
            abi.encodeCall(ILendingCore.withdrawCollateral, (IPool(address(pool)), 100, 0, user, receiver))
        );

        vm.expectRevert(abi.encodeWithSelector(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector));
        vm.prank(user);
        lendingCore.borrow(IPool(address(pool)), 100, user, receiver);
    }

    // borrow()

    function test_borrow_ForwardsToPool() public {
        address user = makeAddr("user");
        address receiver = makeAddr("receiver");
        uint256 amount = 100;
        _addPool();

        vm.expectCall(address(pool), abi.encodeCall(IPool.borrow, (user, amount, receiver)));

        vm.prank(user);
        lendingCore.borrow(IPool(address(pool)), amount, user, receiver);
    }

    function test_borrow_ForwardsToPoolWhenCallerIsAuthorised() public {
        address user = makeAddr("user");
        address operator = makeAddr("operator");
        address receiver = makeAddr("receiver");
        uint256 amount = 100;
        _addPool();
        _authorise(user, operator);

        vm.expectCall(address(pool), abi.encodeCall(IPool.borrow, (user, amount, receiver)));

        vm.prank(operator);
        lendingCore.borrow(IPool(address(pool)), amount, user, receiver);
    }

    function test_borrow_ForwardsZeroAmount() public {
        address user = makeAddr("user");
        address receiver = makeAddr("receiver");
        _addPool();

        vm.expectCall(address(pool), abi.encodeCall(IPool.borrow, (user, 0, receiver)));

        vm.prank(user);
        lendingCore.borrow(IPool(address(pool)), 0, user, receiver);
    }

    function test_borrow_EvaluatesHealthOfOnBehalfOfLoan() public {
        address user = makeAddr("user");
        address operator = makeAddr("operator");
        address receiver = makeAddr("receiver");
        _addPool();
        _authorise(user, operator);
        pool.setCollateralOf(user, 100e18);
        pool.setDebtOf(user, 40e18);
        pool.setCollateralOf(operator, 999e18);
        pool.setDebtOf(operator, 999e18);

        vm.expectCall(address(loanEvaluator), abi.encodeCall(ILoanEvaluator.isLoanHealthy, (lendingCore.loanOf(user))));

        vm.prank(operator);
        lendingCore.borrow(IPool(address(pool)), 100, user, receiver);
    }

    function test_borrow_EvaluatesHealthAfterBorrow() public {
        address user = makeAddr("user");
        address receiver = makeAddr("receiver");
        _addPool();
        pool.setCollateralOf(user, 100e18);
        pool.setDebtOf(user, 40e18);
        pool.setDebtOfAfterBorrow(user, 60e18);
        ILendingCore.Loan memory loan;
        loan.account = user;
        loan.collaterals = LoanHelpers.positions(pool, 100e18);
        loan.borrows = LoanHelpers.positions(pool, 60e18);

        vm.expectCall(address(loanEvaluator), abi.encodeCall(ILoanEvaluator.isLoanHealthy, (loan)));

        vm.prank(user);
        lendingCore.borrow(IPool(address(pool)), 20e18, user, receiver);
    }

    function test_borrow_EmitsBorrowed() public {
        address user = makeAddr("user");
        address operator = makeAddr("operator");
        address receiver = makeAddr("receiver");
        _addPool();
        _authorise(user, operator);

        vm.expectEmit(address(lendingCore));
        emit LendingCore.Borrowed(IPool(address(pool)), user, operator, receiver, 100);

        vm.prank(operator);
        lendingCore.borrow(IPool(address(pool)), 100, user, receiver);
    }

    function test_borrow_FiresBeforeAndAfterHooks() public {
        address user = makeAddr("user");
        address operator = makeAddr("operator");
        address receiver = makeAddr("receiver");
        uint256 amount = 100;
        _addPool();
        _authorise(user, operator);
        _enableHooks(ActionLib.LC_BORROW);
        bytes memory data = abi.encode(user, receiver, operator, address(pool), amount);

        _expectBeforeAndAfterHooks(ActionLib.LC_BORROW, data);

        vm.prank(operator);
        lendingCore.borrow(IPool(address(pool)), amount, user, receiver);
    }

    function test_borrow_RevertsWhenCallerIsNotAuthorised() public {
        address user = makeAddr("user");
        address operator = makeAddr("operator");
        address receiver = makeAddr("receiver");
        _addPool();

        vm.expectRevert(abi.encodeWithSelector(Authorisable.Unauthorised.selector, user, operator));
        vm.prank(operator);
        lendingCore.borrow(IPool(address(pool)), 100, user, receiver);
    }

    function test_borrow_RevertsWhenPoolIsNotListed() public {
        address user = makeAddr("user");
        address receiver = makeAddr("receiver");

        vm.expectRevert(abi.encodeWithSelector(LendingCore.PoolNotListed.selector, address(pool)));
        vm.prank(user);
        lendingCore.borrow(IPool(address(pool)), 100, user, receiver);
    }

    function test_borrow_RevertsWhenPoolIsDeprecated() public {
        address user = makeAddr("user");
        address receiver = makeAddr("receiver");
        _addAndDeprecatePool();

        vm.expectRevert(abi.encodeWithSelector(LendingCore.PoolDeprecated.selector, address(pool)));
        vm.prank(user);
        lendingCore.borrow(IPool(address(pool)), 100, user, receiver);
    }

    function test_borrow_RevertsWhenLoanIsUnhealthy() public {
        address user = makeAddr("user");
        address operator = makeAddr("operator");
        address receiver = makeAddr("receiver");
        _addPool();
        _authorise(user, operator);
        loanEvaluator.setHealthy(false);

        vm.expectRevert(abi.encodeWithSelector(LendingCore.LoanUnhealthy.selector, user));
        vm.prank(operator);
        lendingCore.borrow(IPool(address(pool)), 100, user, receiver);
    }

    function test_borrow_RevertsWhenReentered() public {
        address user = makeAddr("user");
        address receiver = makeAddr("receiver");
        _addPool();
        pool.setBorrowReentry(
            address(lendingCore), abi.encodeCall(ILendingCore.borrow, (IPool(address(pool)), 100, user, receiver))
        );

        vm.expectRevert(abi.encodeWithSelector(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector));
        vm.prank(user);
        lendingCore.borrow(IPool(address(pool)), 100, user, receiver);
    }

    // repay()

    function test_repay_ForwardsToPool() public {
        address user = makeAddr("user");
        address onBehalfOf = makeAddr("onBehalfOf");
        uint256 amount = 100;
        _addPool();

        vm.expectCall(address(pool), abi.encodeCall(IPool.repay, (user, amount, onBehalfOf)));

        vm.prank(user);
        lendingCore.repay(IPool(address(pool)), amount, onBehalfOf);
    }

    function test_repay_ReturnsActualRepaymentFromPool() public {
        address user = makeAddr("user");
        address onBehalfOf = makeAddr("onBehalfOf");
        uint256 requestedAmount = 100;
        uint256 actualRepayment = 80;
        _addPool();
        pool.setRepayment(actualRepayment);

        vm.prank(user);
        uint256 returnedRepayment = lendingCore.repay(IPool(address(pool)), requestedAmount, onBehalfOf);

        assertEq(returnedRepayment, actualRepayment);
    }

    function test_repay_ForwardsToPoolWhenDeprecated() public {
        address user = makeAddr("user");
        address onBehalfOf = makeAddr("onBehalfOf");
        uint256 amount = 100;
        _addAndDeprecatePool();

        vm.expectCall(address(pool), abi.encodeCall(IPool.repay, (user, amount, onBehalfOf)));

        vm.prank(user);
        lendingCore.repay(IPool(address(pool)), amount, onBehalfOf);
    }

    function test_repay_ForwardsZeroAmount() public {
        address user = makeAddr("user");
        address onBehalfOf = makeAddr("onBehalfOf");
        _addPool();

        vm.expectCall(address(pool), abi.encodeCall(IPool.repay, (user, 0, onBehalfOf)));

        vm.prank(user);
        lendingCore.repay(IPool(address(pool)), 0, onBehalfOf);
    }

    function test_repay_EmitsRepaid() public {
        address user = makeAddr("user");
        address onBehalfOf = makeAddr("onBehalfOf");
        _addPool();
        pool.setRepayment(80);

        vm.expectEmit(address(lendingCore));
        emit LendingCore.Repaid(IPool(address(pool)), onBehalfOf, user, 80);

        vm.prank(user);
        lendingCore.repay(IPool(address(pool)), 100, onBehalfOf);
    }

    function test_repay_FiresBeforeAndAfterHooks() public {
        address user = makeAddr("user");
        address onBehalfOf = makeAddr("onBehalfOf");
        uint256 amount = 100;
        _addPool();
        pool.setRepayment(60);
        _enableHooks(ActionLib.LC_REPAY);
        bytes memory beforeData = abi.encode(onBehalfOf, user, user, address(pool), amount);
        bytes memory afterData = abi.encode(onBehalfOf, user, user, address(pool), uint256(60));

        _expectBeforeAndAfterHooks(ActionLib.LC_REPAY, beforeData, afterData);

        vm.prank(user);
        lendingCore.repay(IPool(address(pool)), amount, onBehalfOf);
    }

    function test_repay_RevertsWhenPoolIsNotListed() public {
        address onBehalfOf = makeAddr("onBehalfOf");

        vm.expectRevert(abi.encodeWithSelector(LendingCore.PoolNotListed.selector, address(pool)));
        lendingCore.repay(IPool(address(pool)), 100, onBehalfOf);
    }

    function test_repay_RevertsWhenReentered() public {
        address user = makeAddr("user");
        address receiver = makeAddr("receiver");
        _addPool();
        pool.setBorrowReentry(
            address(lendingCore), abi.encodeCall(ILendingCore.repay, (IPool(address(pool)), 100, user))
        );

        vm.expectRevert(abi.encodeWithSelector(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector));
        vm.prank(user);
        lendingCore.borrow(IPool(address(pool)), 100, user, receiver);
    }

    // liquidate()

    function test_liquidate_RepaysBorrowsAndSeizesCollateral() public {
        address liquidator = makeAddr("liquidator");
        address violator = makeAddr("violator");
        uint256 repayAmount = 100;
        uint256 seizeAmount = 50;
        loanEvaluator.setLiquidatable(true);
        _setLiquidation(LoanHelpers.positions(pool, repayAmount), LoanHelpers.positions(pool, seizeAmount));

        vm.expectCall(address(pool), abi.encodeCall(IPool.repay, (liquidator, repayAmount, violator)));
        vm.expectCall(address(pool), abi.encodeCall(IPool.seizeCollateral, (violator, seizeAmount, liquidator)));

        vm.prank(liquidator);
        lendingCore.liquidate(violator, LoanHelpers.noPositions(), LoanHelpers.noPositions());
    }

    function test_liquidate_HandlesMultipleBorrowsAndCollaterals() public {
        address liquidator = makeAddr("liquidator");
        address violator = makeAddr("violator");
        MockPool borrowPoolA = new MockPool();
        MockPool borrowPoolB = new MockPool();
        MockPool borrowPoolC = new MockPool();
        MockPool collateralPoolA = new MockPool();
        MockPool collateralPoolB = new MockPool();
        loanEvaluator.setLiquidatable(true);
        ILendingCore.LoanPosition[] memory borsToRepay =
            LoanHelpers.positions(borrowPoolA, 100, borrowPoolB, 200, borrowPoolC, 300);
        ILendingCore.LoanPosition[] memory colsToSeize = LoanHelpers.positions(collateralPoolA, 30, collateralPoolB, 40);
        liquidationEngine.setBorsToRepay(borsToRepay);
        liquidationEngine.setColsToSeize(colsToSeize);

        vm.expectCall(address(borrowPoolA), abi.encodeCall(IPool.repay, (liquidator, 100, violator)));
        vm.expectCall(address(borrowPoolB), abi.encodeCall(IPool.repay, (liquidator, 200, violator)));
        vm.expectCall(address(borrowPoolC), abi.encodeCall(IPool.repay, (liquidator, 300, violator)));
        vm.expectCall(address(collateralPoolA), abi.encodeCall(IPool.seizeCollateral, (violator, 30, liquidator)));
        vm.expectCall(address(collateralPoolB), abi.encodeCall(IPool.seizeCollateral, (violator, 40, liquidator)));

        vm.prank(liquidator);
        lendingCore.liquidate(violator, LoanHelpers.noPositions(), LoanHelpers.noPositions());
    }

    function test_liquidate_RepaysBorrowsWhenNoCollateralSeized() public {
        address liquidator = makeAddr("liquidator");
        address violator = makeAddr("violator");
        loanEvaluator.setLiquidatable(true);
        _setLiquidation(LoanHelpers.positions(pool, 100), LoanHelpers.noPositions());

        vm.expectCall(address(pool), abi.encodeCall(IPool.repay, (liquidator, 100, violator)));
        vm.expectCall(address(pool), abi.encodeCall(IPool.seizeCollateral, (violator, 0, liquidator)), 0);

        vm.prank(liquidator);
        lendingCore.liquidate(violator, LoanHelpers.noPositions(), LoanHelpers.noPositions());
    }

    function test_liquidate_SeizesCollateralWhenNoBorrowsRepaid() public {
        address liquidator = makeAddr("liquidator");
        address violator = makeAddr("violator");
        loanEvaluator.setLiquidatable(true);
        _setLiquidation(LoanHelpers.noPositions(), LoanHelpers.positions(pool, 50));

        vm.expectCall(address(pool), abi.encodeCall(IPool.seizeCollateral, (violator, 50, liquidator)));
        vm.expectCall(address(pool), abi.encodeCall(IPool.repay, (liquidator, 0, violator)), 0);

        vm.prank(liquidator);
        lendingCore.liquidate(violator, LoanHelpers.noPositions(), LoanHelpers.noPositions());
    }

    function test_liquidate_MakesNoPoolCallsWhenNothingToRepayOrSeize() public {
        address liquidator = makeAddr("liquidator");
        address violator = makeAddr("violator");
        loanEvaluator.setLiquidatable(true);
        _setLiquidation(LoanHelpers.noPositions(), LoanHelpers.noPositions());

        vm.expectCall(address(pool), abi.encodeCall(IPool.repay, (liquidator, 0, violator)), 0);
        vm.expectCall(address(pool), abi.encodeCall(IPool.seizeCollateral, (violator, 0, liquidator)), 0);

        vm.prank(liquidator);
        lendingCore.liquidate(violator, LoanHelpers.noPositions(), LoanHelpers.noPositions());
    }

    function test_liquidate_MakesNoPoolCallsForZeroAmountPositions() public {
        address liquidator = makeAddr("liquidator");
        address violator = makeAddr("violator");
        loanEvaluator.setLiquidatable(true);
        _setLiquidation(LoanHelpers.positions(pool, 0), LoanHelpers.positions(pool, 0));

        vm.expectCall(address(pool), abi.encodeCall(IPool.repay, (liquidator, 0, violator)), 0);
        vm.expectCall(address(pool), abi.encodeCall(IPool.seizeCollateral, (violator, 0, liquidator)), 0);

        vm.prank(liquidator);
        lendingCore.liquidate(violator, LoanHelpers.noPositions(), LoanHelpers.noPositions());
    }

    function test_liquidate_EvaluatesLiquidatabilityOfViolatorLoan() public {
        address liquidator = makeAddr("liquidator");
        address violator = makeAddr("violator");
        _addPool();
        loanEvaluator.setLiquidatable(true);
        pool.setCollateralOf(violator, 100e18);
        pool.setDebtOf(violator, 40e18);
        pool.setCollateralOf(liquidator, 999e18);
        pool.setDebtOf(liquidator, 999e18);

        vm.expectCall(
            address(loanEvaluator), abi.encodeCall(ILoanEvaluator.isLoanLiquidatable, (lendingCore.loanOf(violator)))
        );

        vm.prank(liquidator);
        lendingCore.liquidate(violator, LoanHelpers.noPositions(), LoanHelpers.noPositions());
    }

    function test_liquidate_EvaluatesLoanBeforeRepayingAndSeizing() public {
        address liquidator = makeAddr("liquidator");
        address violator = makeAddr("violator");
        ILendingCore.LoanPosition[] memory reqCols = LoanHelpers.noPositions();
        ILendingCore.LoanPosition[] memory reqBors = LoanHelpers.noPositions();
        _addPool();
        loanEvaluator.setLiquidatable(true);
        loanEvaluator.setHealth(0.9e18);
        pool.setCollateralOf(violator, 100e18);
        pool.setDebtOf(violator, 40e18);
        pool.setDebtOfAfterRepay(violator, 0);
        pool.setCollateralOfAfterSeize(violator, 50e18);
        _setLiquidation(LoanHelpers.positions(pool, 40e18), LoanHelpers.positions(pool, 50e18));
        ILendingCore.Loan memory loan;
        loan.account = violator;
        loan.collaterals = LoanHelpers.positions(pool, 100e18);
        loan.borrows = LoanHelpers.positions(pool, 40e18);

        vm.expectCall(address(loanEvaluator), abi.encodeCall(ILoanEvaluator.isLoanLiquidatable, (loan)));
        vm.expectCall(
            address(liquidationEngine),
            abi.encodeCall(ILiquidationEngine.liquidate, (loan, 0.9e18, reqCols, reqBors, loanEvaluator))
        );

        vm.prank(liquidator);
        lendingCore.liquidate(violator, reqCols, reqBors);

        assertEq(pool.collateralOf(violator), 50e18);
        assertEq(pool.debtOf(violator), 0);
    }

    function test_liquidate_EmitsLiquidationRepaidForEachBorrowWithAmountThePoolApplied() public {
        address liquidator = makeAddr("liquidator");
        address violator = makeAddr("violator");
        MockPool borrowPoolA = new MockPool();
        MockPool borrowPoolB = new MockPool();
        loanEvaluator.setLiquidatable(true);
        _setLiquidation(LoanHelpers.positions(borrowPoolA, 100, borrowPoolB, 200), LoanHelpers.noPositions());
        borrowPoolA.setRepayment(60);
        borrowPoolB.setRepayment(150);

        vm.expectEmit(address(lendingCore));
        emit LendingCore.LiquidationRepaid(IPool(address(borrowPoolA)), violator, liquidator, 60);
        vm.expectEmit(address(lendingCore));
        emit LendingCore.LiquidationRepaid(IPool(address(borrowPoolB)), violator, liquidator, 150);

        vm.prank(liquidator);
        lendingCore.liquidate(violator, LoanHelpers.noPositions(), LoanHelpers.noPositions());
    }

    function test_liquidate_EmitsCollateralSeizedForEachCollateralWithAmountsThePoolApplied() public {
        address liquidator = makeAddr("liquidator");
        address violator = makeAddr("violator");
        MockPool collateralPoolA = new MockPool();
        MockPool collateralPoolB = new MockPool();
        loanEvaluator.setLiquidatable(true);
        _setLiquidation(LoanHelpers.noPositions(), LoanHelpers.positions(collateralPoolA, 50, collateralPoolB, 30));
        collateralPoolA.setResolvedCollateral(40, 35);
        collateralPoolB.setResolvedCollateral(25, 20);

        vm.expectEmit(address(lendingCore));
        emit LendingCore.CollateralSeized(IPool(address(collateralPoolA)), violator, liquidator, 40, 35);
        vm.expectEmit(address(lendingCore));
        emit LendingCore.CollateralSeized(IPool(address(collateralPoolB)), violator, liquidator, 25, 20);

        vm.prank(liquidator);
        lendingCore.liquidate(violator, LoanHelpers.noPositions(), LoanHelpers.noPositions());
    }

    function test_liquidate_EmitsLiquidated() public {
        address liquidator = makeAddr("liquidator");
        address violator = makeAddr("violator");
        loanEvaluator.setLiquidatable(true);
        loanEvaluator.setHealth(0.9e18);

        vm.expectEmit(address(lendingCore));
        emit LendingCore.Liquidated(violator, liquidator, 0.9e18);

        vm.prank(liquidator);
        lendingCore.liquidate(violator, LoanHelpers.noPositions(), LoanHelpers.noPositions());
    }

    function test_liquidate_FiresBeforeAndAfterHooks() public {
        address liquidator = makeAddr("liquidator");
        address violator = makeAddr("violator");
        loanEvaluator.setLiquidatable(true);
        ILendingCore.LoanPosition[] memory reqCols = LoanHelpers.noPositions();
        ILendingCore.LoanPosition[] memory reqBors = LoanHelpers.noPositions();
        _enableHooks(ActionLib.LC_LIQUIDATE);
        bytes memory beforeData = abi.encode(violator, liquidator, liquidator, reqCols, reqBors);
        bytes memory afterData = abi.encode(
            violator,
            liquidator,
            liquidator,
            LoanHelpers.noPositions(),
            LoanHelpers.noPositions(),
            LoanHelpers.noPositions()
        );

        _expectBeforeAndAfterHooks(ActionLib.LC_LIQUIDATE, beforeData, afterData);

        vm.prank(liquidator);
        lendingCore.liquidate(violator, reqCols, reqBors);
    }

    function test_liquidate_AfterHookCarriesAmountsThePoolsApplied() public {
        address liquidator = makeAddr("liquidator");
        address violator = makeAddr("violator");
        MockPool repayPool = new MockPool();
        MockPool seizePool = new MockPool();
        loanEvaluator.setLiquidatable(true);
        _setLiquidation(LoanHelpers.positions(repayPool, 100), LoanHelpers.positions(seizePool, 50));
        repayPool.setRepayment(60);
        seizePool.setResolvedCollateral(40, 0);
        _enableHooks(ActionLib.LC_LIQUIDATE);
        bytes memory beforeData =
            abi.encode(violator, liquidator, liquidator, LoanHelpers.noPositions(), LoanHelpers.noPositions());
        bytes memory afterData = abi.encode(
            violator,
            liquidator,
            liquidator,
            LoanHelpers.positions(seizePool, 40),
            LoanHelpers.positions(repayPool, 60),
            LoanHelpers.noPositions()
        );

        _expectBeforeAndAfterHooks(ActionLib.LC_LIQUIDATE, beforeData, afterData);

        vm.prank(liquidator);
        lendingCore.liquidate(violator, LoanHelpers.noPositions(), LoanHelpers.noPositions());
    }

    function test_liquidate_AfterHookCarriesDebtWrittenOff() public {
        address liquidator = makeAddr("liquidator");
        address violator = makeAddr("violator");
        _addPool(pool);
        _enableBadDebtSocialisation();
        loanEvaluator.setLiquidatable(true);
        pool.setCollateralOf(violator, 100e18);
        pool.setDebtOf(violator, 40e18);
        pool.setCollateralOfAfterSeize(violator, 0);
        pool.setResolvedCollateral(100e18, 0);
        _setLiquidation(LoanHelpers.noPositions(), LoanHelpers.positions(pool, 100e18));
        _enableHooks(ActionLib.LC_LIQUIDATE);
        bytes memory beforeData =
            abi.encode(violator, liquidator, liquidator, LoanHelpers.noPositions(), LoanHelpers.noPositions());
        bytes memory afterData = abi.encode(
            violator,
            liquidator,
            liquidator,
            LoanHelpers.positions(pool, 100e18),
            LoanHelpers.noPositions(),
            LoanHelpers.positions(pool, 40e18)
        );

        _expectBeforeAndAfterHooks(ActionLib.LC_LIQUIDATE, beforeData, afterData);

        vm.prank(liquidator);
        lendingCore.liquidate(violator, LoanHelpers.noPositions(), LoanHelpers.noPositions());
    }

    function test_liquidate_WritesOffDebtWhenSeizureLeavesNoCollateral() public {
        address liquidator = makeAddr("liquidator");
        address violator = makeAddr("violator");
        _addPool(pool);
        _enableBadDebtSocialisation();
        loanEvaluator.setLiquidatable(true);
        pool.setCollateralOf(violator, 100e18);
        pool.setDebtOf(violator, 40e18);
        pool.setCollateralOfAfterSeize(violator, 0);
        _setLiquidation(LoanHelpers.noPositions(), LoanHelpers.positions(pool, 100e18));

        vm.expectCall(address(pool), abi.encodeCall(IPool.writeOffDebt, (violator)), 1);

        vm.prank(liquidator);
        lendingCore.liquidate(violator, LoanHelpers.noPositions(), LoanHelpers.noPositions());

        assertEq(pool.debtOf(violator), 0);
    }

    function test_liquidate_WritesOffDebtInEveryPoolThatCarriesIt() public {
        address liquidator = makeAddr("liquidator");
        address violator = makeAddr("violator");
        MockPool borrowPoolA = new MockPool();
        MockPool borrowPoolB = new MockPool();
        _addPool(pool);
        _addPool(borrowPoolA);
        _addPool(borrowPoolB);
        _enableBadDebtSocialisation();
        loanEvaluator.setLiquidatable(true);
        pool.setCollateralOf(violator, 100e18);
        pool.setCollateralOfAfterSeize(violator, 0);
        borrowPoolA.setDebtOf(violator, 40e18);
        borrowPoolB.setDebtOf(violator, 30e18);
        _setLiquidation(LoanHelpers.noPositions(), LoanHelpers.positions(pool, 100e18));

        vm.expectCall(address(borrowPoolA), abi.encodeCall(IPool.writeOffDebt, (violator)), 1);
        vm.expectCall(address(borrowPoolB), abi.encodeCall(IPool.writeOffDebt, (violator)), 1);
        vm.expectCall(address(pool), abi.encodeCall(IPool.writeOffDebt, (violator)), 0);

        vm.prank(liquidator);
        lendingCore.liquidate(violator, LoanHelpers.noPositions(), LoanHelpers.noPositions());
    }

    function test_liquidate_EmitsBadDebtSocialisedForEachPoolThatCarriesDebt() public {
        address liquidator = makeAddr("liquidator");
        address violator = makeAddr("violator");
        MockPool borrowPoolA = new MockPool();
        MockPool borrowPoolB = new MockPool();
        _addPool(pool);
        _addPool(borrowPoolA);
        _addPool(borrowPoolB);
        _enableBadDebtSocialisation();
        loanEvaluator.setLiquidatable(true);
        pool.setCollateralOf(violator, 100e18);
        pool.setCollateralOfAfterSeize(violator, 0);
        borrowPoolA.setDebtOf(violator, 40e18);
        borrowPoolB.setDebtOf(violator, 30e18);
        _setLiquidation(LoanHelpers.noPositions(), LoanHelpers.positions(pool, 100e18));

        vm.expectEmit(address(lendingCore));
        emit LendingCore.BadDebtSocialised(IPool(address(borrowPoolA)), violator, liquidator, 40e18);
        vm.expectEmit(address(lendingCore));
        emit LendingCore.BadDebtSocialised(IPool(address(borrowPoolB)), violator, liquidator, 30e18);

        vm.prank(liquidator);
        lendingCore.liquidate(violator, LoanHelpers.noPositions(), LoanHelpers.noPositions());
    }

    function test_liquidate_DoesNotWriteOffBorrowsTheLiquidationRepaid() public {
        address liquidator = makeAddr("liquidator");
        address violator = makeAddr("violator");
        MockPool repaidPool = new MockPool();
        MockPool borrowPool = new MockPool();
        _addPool(pool);
        _addPool(repaidPool);
        _addPool(borrowPool);
        _enableBadDebtSocialisation();
        loanEvaluator.setLiquidatable(true);
        pool.setCollateralOf(violator, 100e18);
        pool.setCollateralOfAfterSeize(violator, 0);
        repaidPool.setDebtOf(violator, 40e18);
        repaidPool.setDebtOfAfterRepay(violator, 0);
        borrowPool.setDebtOf(violator, 30e18);
        _setLiquidation(LoanHelpers.positions(repaidPool, 40e18), LoanHelpers.positions(pool, 100e18));

        vm.expectCall(address(repaidPool), abi.encodeCall(IPool.writeOffDebt, (violator)), 0);
        vm.expectCall(address(borrowPool), abi.encodeCall(IPool.writeOffDebt, (violator)), 1);

        vm.prank(liquidator);
        lendingCore.liquidate(violator, LoanHelpers.noPositions(), LoanHelpers.noPositions());
    }

    function test_liquidate_DoesNotWriteOffDebtWhenSeizureLeavesCollateral() public {
        address liquidator = makeAddr("liquidator");
        address violator = makeAddr("violator");
        _addPool(pool);
        _enableBadDebtSocialisation();
        loanEvaluator.setLiquidatable(true);
        pool.setCollateralOf(violator, 100e18);
        pool.setDebtOf(violator, 40e18);
        pool.setCollateralOfAfterSeize(violator, 1);
        _setLiquidation(LoanHelpers.noPositions(), LoanHelpers.positions(pool, 100e18 - 1));

        vm.expectCall(address(pool), abi.encodeCall(IPool.writeOffDebt, (violator)), 0);

        vm.prank(liquidator);
        lendingCore.liquidate(violator, LoanHelpers.noPositions(), LoanHelpers.noPositions());
    }

    function test_liquidate_DoesNotWriteOffDebtWhenCollateralRemainsInAnotherPool() public {
        address liquidator = makeAddr("liquidator");
        address violator = makeAddr("violator");
        MockPool untouchedPool = new MockPool();
        _addPool(pool);
        _addPool(untouchedPool);
        _enableBadDebtSocialisation();
        loanEvaluator.setLiquidatable(true);
        pool.setCollateralOf(violator, 100e18);
        pool.setDebtOf(violator, 40e18);
        pool.setCollateralOfAfterSeize(violator, 0);
        untouchedPool.setCollateralOf(violator, 1);
        _setLiquidation(LoanHelpers.noPositions(), LoanHelpers.positions(pool, 100e18));

        vm.expectCall(address(pool), abi.encodeCall(IPool.writeOffDebt, (violator)), 0);

        vm.prank(liquidator);
        lendingCore.liquidate(violator, LoanHelpers.noPositions(), LoanHelpers.noPositions());
    }

    function test_liquidate_DoesNotWriteOffDebtWhenSocialisationIsDisabled() public {
        address liquidator = makeAddr("liquidator");
        address violator = makeAddr("violator");
        _addPool(pool);
        loanEvaluator.setLiquidatable(true);
        pool.setCollateralOf(violator, 100e18);
        pool.setDebtOf(violator, 40e18);
        pool.setCollateralOfAfterSeize(violator, 0);
        _setLiquidation(LoanHelpers.noPositions(), LoanHelpers.positions(pool, 100e18));

        vm.expectCall(address(pool), abi.encodeCall(IPool.writeOffDebt, (violator)), 0);

        vm.prank(liquidator);
        lendingCore.liquidate(violator, LoanHelpers.noPositions(), LoanHelpers.noPositions());
    }

    function test_liquidate_RevertsWhenLoanIsNotLiquidatable() public {
        address liquidator = makeAddr("liquidator");
        address violator = makeAddr("violator");
        loanEvaluator.setLiquidatable(false);

        vm.expectRevert(abi.encodeWithSelector(LendingCore.LoanNotLiquidatable.selector, violator));
        vm.prank(liquidator);
        lendingCore.liquidate(violator, LoanHelpers.noPositions(), LoanHelpers.noPositions());
    }

    function test_liquidate_RevertsWhenReentered() public {
        address user = makeAddr("user");
        address receiver = makeAddr("receiver");
        _addPool();
        pool.setBorrowReentry(
            address(lendingCore),
            abi.encodeCall(ILendingCore.liquidate, (user, LoanHelpers.noPositions(), LoanHelpers.noPositions()))
        );

        vm.expectRevert(abi.encodeWithSelector(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector));
        vm.prank(user);
        lendingCore.borrow(IPool(address(pool)), 100, user, receiver);
    }

    // poolStatus()

    function test_poolStatus_ReturnsNoneWhenPoolIsNotListed() public view {
        assertEq(uint256(lendingCore.poolStatus(address(pool))), uint256(LendingCore.PoolStatus.NONE));
    }

    function test_poolStatus_ReturnsActiveWhenPoolIsActive() public {
        _addPool();

        assertEq(uint256(lendingCore.poolStatus(address(pool))), uint256(LendingCore.PoolStatus.ACTIVE));
    }

    function test_poolStatus_ReturnsDeprecatedWhenPoolIsDeprecated() public {
        _addAndDeprecatePool();

        assertEq(uint256(lendingCore.poolStatus(address(pool))), uint256(LendingCore.PoolStatus.DEPRECATED));
    }

    // isPoolAdded()

    function test_isPoolAdded_ReturnsFalseWhenPoolIsNotListed() public view {
        assertFalse(lendingCore.isPoolAdded(address(pool)));
    }

    // pools()

    function test_pools_ReturnsEmptyArrayWhenNoPoolsListed() public view {
        assertEq(lendingCore.pools().length, 0);
    }

    function test_pools_ReturnsAllPoolsWithStatusInInsertionOrder() public {
        MockPool secondPool = new MockPool();
        vm.startPrank(poolLister);
        lendingCore.addPool(address(pool));
        lendingCore.addPool(address(secondPool));
        lendingCore.setDeprecatePool(address(secondPool), true);
        vm.stopPrank();

        LendingCore.PoolInfo[] memory infos = lendingCore.pools();

        assertEq(infos.length, 2);
        assertEq(infos[0].pool, address(pool));
        assertEq(uint256(infos[0].status), uint256(LendingCore.PoolStatus.ACTIVE));
        assertEq(infos[1].pool, address(secondPool));
        assertEq(uint256(infos[1].status), uint256(LendingCore.PoolStatus.DEPRECATED));
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(lendingCore.contractName(), "LendingCore");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(lendingCore.contractVersion(), "1.0.0");
    }

    // supportsInterface()

    function test_supportsInterface_ReturnsTrueForLendingCore() public view {
        assertTrue(lendingCore.supportsInterface(type(ILendingCore).interfaceId));
    }

    function test_supportsInterface_ReturnsTrueForVersioned() public view {
        assertTrue(lendingCore.supportsInterface(type(IVersioned).interfaceId));
    }

    function test_supportsInterface_ReturnsTrueForAuthorisable() public view {
        assertTrue(lendingCore.supportsInterface(type(IAuthorisable).interfaceId));
    }

    function test_supportsInterface_ReturnsTrueForERC165() public view {
        assertTrue(lendingCore.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_ReturnsTrueForAccessControl() public view {
        assertTrue(lendingCore.supportsInterface(type(IAccessControl).interfaceId));
    }

    function test_supportsInterface_ReturnsTrueForAccessControlEnumerable() public view {
        assertTrue(lendingCore.supportsInterface(type(IAccessControlEnumerable).interfaceId));
    }

    function test_supportsInterface_ReturnsFalseForUnknownInterface() public view {
        assertFalse(lendingCore.supportsInterface(bytes4(0xffffffff)));
    }

    // loanOf()

    function test_loanOf_IncludesPositionsOnEachListedPool() public {
        address account = makeAddr("account");
        address otherAccount = makeAddr("otherAccount");
        MockPool secondPool = new MockPool();
        vm.startPrank(poolLister);
        lendingCore.addPool(address(pool));
        lendingCore.addPool(address(secondPool));
        vm.stopPrank();
        pool.setCollateralOf(account, 100e18);
        pool.setDebtOf(account, 40e18);
        secondPool.setCollateralOf(account, 200e18);
        secondPool.setDebtOf(account, 30e18);
        pool.setCollateralOf(otherAccount, 999e18);
        secondPool.setDebtOf(otherAccount, 999e18);

        ILendingCore.Loan memory loan = lendingCore.loanOf(account);

        assertEq(loan.account, account);
        _assertPositions(loan.collaterals, LoanHelpers.positions(pool, 100e18, secondPool, 200e18));
        _assertPositions(loan.borrows, LoanHelpers.positions(pool, 40e18, secondPool, 30e18));
    }

    function test_loanOf_OmitsZeroPositions() public {
        address account = makeAddr("account");
        MockPool secondPool = new MockPool();
        vm.startPrank(poolLister);
        lendingCore.addPool(address(pool));
        lendingCore.addPool(address(secondPool));
        vm.stopPrank();
        pool.setCollateralOf(account, 100e18);
        secondPool.setDebtOf(account, 30e18);

        ILendingCore.Loan memory loan = lendingCore.loanOf(account);

        _assertPositions(loan.collaterals, LoanHelpers.positions(pool, 100e18));
        _assertPositions(loan.borrows, LoanHelpers.positions(secondPool, 30e18));
    }

    function test_loanOf_IncludesPositionsOnDeprecatedPools() public {
        address account = makeAddr("account");
        _addAndDeprecatePool();
        pool.setCollateralOf(account, 100e18);
        pool.setDebtOf(account, 40e18);

        ILendingCore.Loan memory loan = lendingCore.loanOf(account);

        _assertPositions(loan.collaterals, LoanHelpers.positions(pool, 100e18));
        _assertPositions(loan.borrows, LoanHelpers.positions(pool, 40e18));
    }

    function test_loanOf_ExcludesPositionsOnUnlistedPools() public {
        address account = makeAddr("account");
        MockPool unlistedPool = new MockPool();
        _addPool();
        unlistedPool.setCollateralOf(account, 100e18);
        unlistedPool.setDebtOf(account, 40e18);

        ILendingCore.Loan memory loan = lendingCore.loanOf(account);

        assertEq(loan.account, account);
        assertEq(loan.collaterals.length, 0);
        assertEq(loan.borrows.length, 0);
    }

    function _addPool() internal {
        vm.prank(poolLister);
        lendingCore.addPool(address(pool));
    }

    function _addPool(MockPool pool_) internal {
        vm.prank(poolLister);
        lendingCore.addPool(address(pool_));
    }

    function _enableBadDebtSocialisation() internal {
        vm.prank(badDebtConfigurator);
        lendingCore.setSocialiseBadDebt(true);
    }

    function _addAndDeprecatePool() internal {
        vm.startPrank(poolLister);
        lendingCore.addPool(address(pool));
        lendingCore.setDeprecatePool(address(pool), true);
        vm.stopPrank();
    }

    /// @dev Authorises `authorised` to act on behalf of `authoriser`.
    function _authorise(address authoriser, address authorised) internal {
        vm.prank(authoriser);
        lendingCore.setAuthorisation(authorised, true);
    }

    /// @dev Configures the liquidation engine to return the given borrows to repay and collateral to seize.
    function _setLiquidation(ILendingCore.LoanPosition[] memory bors, ILendingCore.LoanPosition[] memory cols)
        internal
    {
        liquidationEngine.setBorsToRepay(bors);
        liquidationEngine.setColsToSeize(cols);
    }

    /// @dev Sets `hookReceiver` and enables `action`'s before and after hook bits.
    function _enableHooks(uint8 action) internal {
        uint256 bitmap = uint256(1) << action;
        vm.startPrank(hookUpdater);
        lendingCore.setHookReceiver(address(hookReceiver));
        lendingCore.setHookBitmaps(bitmap, bitmap);
        vm.stopPrank();
    }

    /// @dev Expects the before and after `HookCalled` events from `lendingCore` for `action` with `data`, in order.
    function _expectBeforeAndAfterHooks(uint8 action, bytes memory data) internal {
        _expectBeforeAndAfterHooks(action, data, data);
    }

    function _expectBeforeAndAfterHooks(uint8 action, bytes memory beforeData, bytes memory afterData) internal {
        vm.expectEmit(address(hookReceiver));
        emit MockHookReceiver.HookCalled(address(lendingCore), Phase.BEFORE, action, beforeData);
        vm.expectEmit(address(hookReceiver));
        emit MockHookReceiver.HookCalled(address(lendingCore), Phase.AFTER, action, afterData);
    }

    function _deployLendingCore(
        address loanEvaluator_,
        address liquidationEngine_,
        address defaultAdmin_,
        address hookUpdater_,
        address poolLister_,
        address loanUpdater_,
        address liquidationUpdater_,
        address badDebtConfigurator_,
        address metadataConfigurator_
    ) internal returns (LendingCore instance) {
        return _deployLendingCore(
            loanEvaluator_,
            liquidationEngine_,
            defaultAdmin_,
            hookUpdater_,
            poolLister_,
            loanUpdater_,
            liquidationUpdater_,
            badDebtConfigurator_,
            metadataConfigurator_,
            false,
            new address[](0)
        );
    }

    function _deployLendingCore(
        address loanEvaluator_,
        address liquidationEngine_,
        address defaultAdmin_,
        address hookUpdater_,
        address poolLister_,
        address loanUpdater_,
        address liquidationUpdater_,
        address badDebtConfigurator_,
        address metadataConfigurator_,
        bool initialSocialiseBadDebt,
        address[] memory initialPools
    ) internal returns (LendingCore instance) {
        instance = LendingCore(Clones.clone(address(implementation)));
        instance.initialize(
            loanEvaluator_,
            liquidationEngine_,
            defaultAdmin_,
            hookUpdater_,
            address(0),
            0,
            0,
            poolLister_,
            loanUpdater_,
            liquidationUpdater_,
            badDebtConfigurator_,
            metadataConfigurator_,
            initialSocialiseBadDebt,
            INITIAL_METADATA,
            initialPools
        );
    }

    function _poolAddresses(address firstPool) internal pure returns (address[] memory pools) {
        pools = new address[](1);
        pools[0] = firstPool;
    }

    function _poolAddresses(address firstPool, address secondPool) internal pure returns (address[] memory pools) {
        pools = new address[](2);
        pools[0] = firstPool;
        pools[1] = secondPool;
    }

    function _assertPositions(ILendingCore.LoanPosition[] memory actual, ILendingCore.LoanPosition[] memory expected)
        internal
        pure
    {
        assertEq(actual.length, expected.length);
        for (uint256 i; i < expected.length; ++i) {
            assertEq(address(actual[i].pool), address(expected[i].pool));
            assertEq(actual[i].amount, expected[i].amount);
        }
    }
}
