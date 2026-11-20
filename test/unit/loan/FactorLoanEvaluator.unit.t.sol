// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IAccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Test} from "forge-std/Test.sol";

import {IVersioned} from "src/interfaces/IVersioned.sol";
import {ILendingCore} from "src/lending-core/interfaces/ILendingCore.sol";
import {FactorLoanEvaluator} from "src/loan/FactorLoanEvaluator.sol";
import {ILoanEvaluator} from "src/loan/interfaces/ILoanEvaluator.sol";
import {IPool} from "src/pool/interfaces/IPool.sol";
import {LoanHelpers} from "../../helpers/LoanHelpers.sol";
import {MockOracle} from "../../mocks/MockOracle.sol";

contract FactorLoanEvaluatorUnitTest is Test {
    uint256 internal constant MIN_HEALTH_FACTOR = 1.1e18;

    /// @dev The two pools are priced differently and hold assets of different decimals.  One whole `firstPool` token
    ///      is worth 2 of numeraire, and one whole `secondPool` token 3.
    uint256 internal constant FIRST_POOL_PRICE = 2e18;
    uint8 internal constant FIRST_POOL_DECIMALS = 18;
    uint256 internal constant SECOND_POOL_PRICE = 3e18;
    uint8 internal constant SECOND_POOL_DECIMALS = 6;

    address internal defaultAdmin;
    address internal oracleUpdater;
    address internal factorConfigurator;
    address internal nonFactorConfigurator;
    address internal borrower;
    MockOracle internal oracle;
    IPool internal firstPool;
    IPool internal secondPool;
    IPool internal unknownPool;

    FactorLoanEvaluator internal implementation;
    FactorLoanEvaluator internal evaluator;

    function setUp() public {
        defaultAdmin = makeAddr("defaultAdmin");
        oracleUpdater = makeAddr("oracleUpdater");
        factorConfigurator = makeAddr("factorConfigurator");
        nonFactorConfigurator = makeAddr("nonFactorConfigurator");
        borrower = makeAddr("borrower");
        firstPool = IPool(makeAddr("firstPool"));
        secondPool = IPool(makeAddr("secondPool"));
        unknownPool = IPool(makeAddr("unknownPool"));

        oracle = new MockOracle();
        oracle.setPrice(firstPool, FIRST_POOL_PRICE, FIRST_POOL_DECIMALS);
        oracle.setPrice(secondPool, SECOND_POOL_PRICE, SECOND_POOL_DECIMALS);

        implementation = new FactorLoanEvaluator();
        evaluator = _deploy(new FactorLoanEvaluator.PoolFactorConfig[](0));
    }

    // initialize()

    function test_initialize_GrantsInitialRoles() public view {
        assertTrue(evaluator.hasRole(evaluator.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertTrue(evaluator.hasRole(evaluator.ORACLE_UPDATER_ROLE(), oracleUpdater));
        assertTrue(evaluator.hasRole(evaluator.FACTOR_CONFIG_ROLE(), factorConfigurator));
    }

    function test_initialize_UsesDefaultAdminAsRoleAdmin() public view {
        assertEq(evaluator.getRoleAdmin(evaluator.ORACLE_UPDATER_ROLE()), evaluator.DEFAULT_ADMIN_ROLE());
        assertEq(evaluator.getRoleAdmin(evaluator.FACTOR_CONFIG_ROLE()), evaluator.DEFAULT_ADMIN_ROLE());
    }

    function test_initialize_AllowsZeroAddressRoleMembers() public {
        FactorLoanEvaluator instance = _clone();
        instance.initialize(
            address(0),
            address(0),
            address(0),
            address(oracle),
            MIN_HEALTH_FACTOR,
            new FactorLoanEvaluator.PoolFactorConfig[](0)
        );

        assertEq(instance.getRoleMemberCount(instance.DEFAULT_ADMIN_ROLE()), 0);
        assertEq(instance.getRoleMemberCount(instance.ORACLE_UPDATER_ROLE()), 0);
        assertEq(instance.getRoleMemberCount(instance.FACTOR_CONFIG_ROLE()), 0);
    }

    function test_initialize_SetsOracleMinHealthFactorAndMultiplePoolFactors() public {
        FactorLoanEvaluator.PoolFactorConfig[] memory configs = _poolFactorConfigs();

        FactorLoanEvaluator instance = _deploy(configs);

        FactorLoanEvaluator.PoolFactors memory firstFactors = instance.getPoolFactors(firstPool);
        FactorLoanEvaluator.PoolFactors memory secondFactors = instance.getPoolFactors(secondPool);
        assertEq(address(instance.oracle()), address(oracle));
        assertEq(instance.minHealthFactor(), MIN_HEALTH_FACTOR);
        assertEq(firstFactors.collateralFactor, configs[0].collateralFactor);
        assertEq(firstFactors.borrowFactor, configs[0].borrowFactor);
        assertTrue(firstFactors.isAdded);
        assertEq(secondFactors.collateralFactor, configs[1].collateralFactor);
        assertEq(secondFactors.borrowFactor, configs[1].borrowFactor);
        assertTrue(secondFactors.isAdded);
    }

    function test_initialize_AllowsNoInitialPools() public view {
        assertFalse(evaluator.isPoolAdded(firstPool));
        assertFalse(evaluator.isPoolAdded(secondPool));
    }

    function test_initialize_RevertsWhenMinHealthFactorIsTooLow() public {
        uint256 invalidMinHealthFactor = 1e18 - 1;
        FactorLoanEvaluator instance = _clone();

        vm.expectRevert(
            abi.encodeWithSelector(FactorLoanEvaluator.MinHealthFactorTooLow.selector, invalidMinHealthFactor)
        );
        instance.initialize(
            defaultAdmin,
            oracleUpdater,
            factorConfigurator,
            address(oracle),
            invalidMinHealthFactor,
            new FactorLoanEvaluator.PoolFactorConfig[](0)
        );
    }

    function test_initialize_RevertsAtomicallyWhenCollateralFactorIsTooHigh() public {
        FactorLoanEvaluator.PoolFactorConfig[] memory configs = _poolFactorConfigs();
        configs[1].collateralFactor = 10_001;
        FactorLoanEvaluator instance = _clone();

        vm.expectRevert(
            abi.encodeWithSelector(FactorLoanEvaluator.CollateralFactorTooHigh.selector, configs[1].collateralFactor)
        );
        instance.initialize(
            defaultAdmin, oracleUpdater, factorConfigurator, address(oracle), MIN_HEALTH_FACTOR, configs
        );

        _assertInitializationRolledBack(instance);
    }

    function test_initialize_RevertsAtomicallyWhenBorrowFactorIsTooLow() public {
        FactorLoanEvaluator.PoolFactorConfig[] memory configs = _poolFactorConfigs();
        configs[1].borrowFactor = 9999;
        FactorLoanEvaluator instance = _clone();

        vm.expectRevert(
            abi.encodeWithSelector(FactorLoanEvaluator.BorrowFactorTooLow.selector, configs[1].borrowFactor)
        );
        instance.initialize(
            defaultAdmin, oracleUpdater, factorConfigurator, address(oracle), MIN_HEALTH_FACTOR, configs
        );

        _assertInitializationRolledBack(instance);
    }

    function test_initialize_RevertsAtomicallyWhenPoolIsDuplicated() public {
        FactorLoanEvaluator.PoolFactorConfig[] memory configs = _poolFactorConfigs();
        configs[1].pool = firstPool;
        FactorLoanEvaluator instance = _clone();

        vm.expectRevert(abi.encodeWithSelector(FactorLoanEvaluator.PoolAlreadyAdded.selector, firstPool));
        instance.initialize(
            defaultAdmin, oracleUpdater, factorConfigurator, address(oracle), MIN_HEALTH_FACTOR, configs
        );

        _assertInitializationRolledBack(instance);
    }

    // updateMinHealthFactor()

    function test_updateMinHealthFactor_UpdatesValue() public {
        vm.prank(factorConfigurator);
        evaluator.updateMinHealthFactor(1.2e18);

        assertEq(evaluator.minHealthFactor(), 1.2e18);
    }

    function test_updateMinHealthFactor_EmitsEvent() public {
        vm.expectEmit();
        emit FactorLoanEvaluator.MinHealthFactorUpdated(MIN_HEALTH_FACTOR, 1.2e18);

        vm.prank(factorConfigurator);
        evaluator.updateMinHealthFactor(1.2e18);
    }

    function test_updateMinHealthFactor_AllowsOne() public {
        vm.prank(factorConfigurator);
        evaluator.updateMinHealthFactor(1e18);

        assertEq(evaluator.minHealthFactor(), 1e18);
    }

    function test_updateMinHealthFactor_RevertsWhenBelowOne() public {
        vm.expectRevert(abi.encodeWithSelector(FactorLoanEvaluator.MinHealthFactorTooLow.selector, 1e18 - 1));
        vm.prank(factorConfigurator);
        evaluator.updateMinHealthFactor(1e18 - 1);
    }

    function test_updateMinHealthFactor_RevertsWhenCallerLacksRole() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonFactorConfigurator,
                evaluator.FACTOR_CONFIG_ROLE()
            )
        );
        vm.prank(nonFactorConfigurator);
        evaluator.updateMinHealthFactor(1.2e18);
    }

    // addPool()

    function test_addPool_AddsFactors() public {
        vm.prank(factorConfigurator);
        evaluator.addPool(firstPool, 8000, 11_000);

        FactorLoanEvaluator.PoolFactors memory poolFactors = evaluator.getPoolFactors(firstPool);
        assertTrue(evaluator.isPoolAdded(firstPool));
        assertEq(poolFactors.collateralFactor, 8000);
        assertEq(poolFactors.borrowFactor, 11_000);
        assertTrue(poolFactors.isAdded);
    }

    function test_addPool_EmitsEvent() public {
        vm.expectEmit();
        emit FactorLoanEvaluator.PoolAdded(firstPool, 8000, 11_000);

        vm.prank(factorConfigurator);
        evaluator.addPool(firstPool, 8000, 11_000);
    }

    function test_addPool_AllowsZeroAddressPool() public {
        vm.prank(factorConfigurator);
        evaluator.addPool(IPool(address(0)), 8000, 11_000);

        assertTrue(evaluator.isPoolAdded(IPool(address(0))));
    }

    function test_addPool_AllowsCollateralFactorOfOne() public {
        vm.prank(factorConfigurator);
        evaluator.addPool(firstPool, 10_000, 11_000);

        assertEq(evaluator.getPoolFactors(firstPool).collateralFactor, 10_000);
    }

    function test_addPool_AllowsBorrowFactorOfOne() public {
        vm.prank(factorConfigurator);
        evaluator.addPool(firstPool, 8000, 10_000);

        assertEq(evaluator.getPoolFactors(firstPool).borrowFactor, 10_000);
    }

    function test_addPool_RevertsWhenCollateralFactorIsAboveOne() public {
        vm.expectRevert(abi.encodeWithSelector(FactorLoanEvaluator.CollateralFactorTooHigh.selector, 10_001));
        vm.prank(factorConfigurator);
        evaluator.addPool(firstPool, 10_001, 11_000);
    }

    function test_addPool_RevertsWhenBorrowFactorIsBelowOne() public {
        vm.expectRevert(abi.encodeWithSelector(FactorLoanEvaluator.BorrowFactorTooLow.selector, 9999));
        vm.prank(factorConfigurator);
        evaluator.addPool(firstPool, 8000, 9999);
    }

    function test_addPool_RevertsWhenPoolIsAlreadyAdded() public {
        vm.prank(factorConfigurator);
        evaluator.addPool(firstPool, 8000, 11_000);

        vm.expectRevert(abi.encodeWithSelector(FactorLoanEvaluator.PoolAlreadyAdded.selector, firstPool));
        vm.prank(factorConfigurator);
        evaluator.addPool(firstPool, 7000, 12_000);
    }

    function test_addPool_RevertsWhenCallerLacksRole() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonFactorConfigurator,
                evaluator.FACTOR_CONFIG_ROLE()
            )
        );
        vm.prank(nonFactorConfigurator);
        evaluator.addPool(firstPool, 8000, 11_000);
    }

    // updateCollateralFactor()

    function test_updateCollateralFactor_UpdatesFactor() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        vm.prank(factorConfigurator);
        instance.updateCollateralFactor(firstPool, 9000);

        assertEq(instance.getPoolFactors(firstPool).collateralFactor, 9000);
    }

    function test_updateCollateralFactor_LeavesBorrowFactorUnchanged() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        vm.prank(factorConfigurator);
        instance.updateCollateralFactor(firstPool, 9000);

        assertEq(instance.getPoolFactors(firstPool).borrowFactor, 11_000);
    }

    function test_updateCollateralFactor_LeavesOtherPoolsUnchanged() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        vm.prank(factorConfigurator);
        instance.updateCollateralFactor(firstPool, 9000);

        assertEq(instance.getPoolFactors(secondPool).collateralFactor, 7000);
    }

    function test_updateCollateralFactor_EmitsEvent() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        vm.expectEmit();
        emit FactorLoanEvaluator.CollateralFactorUpdated(firstPool, 8000, 9000);
        vm.prank(factorConfigurator);
        instance.updateCollateralFactor(firstPool, 9000);
    }

    function test_updateCollateralFactor_AllowsCollateralFactorOfOne() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        vm.prank(factorConfigurator);
        instance.updateCollateralFactor(firstPool, 10_000);

        assertEq(instance.getPoolFactors(firstPool).collateralFactor, 10_000);
    }

    function test_updateCollateralFactor_RevertsWhenCollateralFactorIsAboveOne() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        vm.expectRevert(abi.encodeWithSelector(FactorLoanEvaluator.CollateralFactorTooHigh.selector, 10_001));
        vm.prank(factorConfigurator);
        instance.updateCollateralFactor(firstPool, 10_001);
    }

    function test_updateCollateralFactor_RevertsWhenPoolIsUnknown() public {
        vm.expectRevert(abi.encodeWithSelector(FactorLoanEvaluator.PoolUnknown.selector, firstPool));
        vm.prank(factorConfigurator);
        evaluator.updateCollateralFactor(firstPool, 9000);
    }

    function test_updateCollateralFactor_RevertsWhenCallerLacksRole() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonFactorConfigurator,
                instance.FACTOR_CONFIG_ROLE()
            )
        );
        vm.prank(nonFactorConfigurator);
        instance.updateCollateralFactor(firstPool, 9000);
    }

    // updateBorrowFactor()

    function test_updateBorrowFactor_UpdatesFactor() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        vm.prank(factorConfigurator);
        instance.updateBorrowFactor(firstPool, 13_000);

        assertEq(instance.getPoolFactors(firstPool).borrowFactor, 13_000);
    }

    function test_updateBorrowFactor_LeavesCollateralFactorUnchanged() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        vm.prank(factorConfigurator);
        instance.updateBorrowFactor(firstPool, 13_000);

        assertEq(instance.getPoolFactors(firstPool).collateralFactor, 8000);
    }

    function test_updateBorrowFactor_LeavesOtherPoolsUnchanged() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        vm.prank(factorConfigurator);
        instance.updateBorrowFactor(firstPool, 13_000);

        assertEq(instance.getPoolFactors(secondPool).borrowFactor, 12_000);
    }

    function test_updateBorrowFactor_EmitsEvent() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        vm.expectEmit();
        emit FactorLoanEvaluator.BorrowFactorUpdated(firstPool, 11_000, 13_000);
        vm.prank(factorConfigurator);
        instance.updateBorrowFactor(firstPool, 13_000);
    }

    function test_updateBorrowFactor_AllowsBorrowFactorOfOne() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        vm.prank(factorConfigurator);
        instance.updateBorrowFactor(firstPool, 10_000);

        assertEq(instance.getPoolFactors(firstPool).borrowFactor, 10_000);
    }

    function test_updateBorrowFactor_RevertsWhenBorrowFactorIsBelowOne() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        vm.expectRevert(abi.encodeWithSelector(FactorLoanEvaluator.BorrowFactorTooLow.selector, 9999));
        vm.prank(factorConfigurator);
        instance.updateBorrowFactor(firstPool, 9999);
    }

    function test_updateBorrowFactor_RevertsWhenPoolIsUnknown() public {
        vm.expectRevert(abi.encodeWithSelector(FactorLoanEvaluator.PoolUnknown.selector, firstPool));
        vm.prank(factorConfigurator);
        evaluator.updateBorrowFactor(firstPool, 13_000);
    }

    function test_updateBorrowFactor_RevertsWhenCallerLacksRole() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonFactorConfigurator,
                instance.FACTOR_CONFIG_ROLE()
            )
        );
        vm.prank(nonFactorConfigurator);
        instance.updateBorrowFactor(firstPool, 13_000);
    }

    // isLoanHealthy()

    function test_isLoanHealthy_ReturnsTrueWhenCollateralExceedsRequirement() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        bool healthy = instance.isLoanHealthy(
            _loan(LoanHelpers.positions(firstPool, 55e18), LoanHelpers.positions(firstPool, 20e18))
        );

        assertTrue(healthy);
    }

    function test_isLoanHealthy_ReturnsTrueAtExactlyMinHealthFactor() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        // 20 tokens of borrow is 44 of effective debt, so a 1.1 minimum demands 48.4 of effective collateral,
        // which is what 30.25 tokens discounted by 20% come to.
        bool healthy = instance.isLoanHealthy(
            _loan(LoanHelpers.positions(firstPool, 30.25e18), LoanHelpers.positions(firstPool, 20e18))
        );

        assertTrue(healthy);
    }

    function test_isLoanHealthy_ReturnsFalseJustBelowMinHealthFactor() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        bool healthy = instance.isLoanHealthy(
            _loan(LoanHelpers.positions(firstPool, 30.25e18 - 1), LoanHelpers.positions(firstPool, 20e18))
        );

        assertFalse(healthy);
    }

    function test_isLoanHealthy_ReturnsFalseForSolventLoanBelowMinHealthFactor() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        // 44 of collateral against 44 of debt is a health of exactly one, i.e. solvent and not liquidatable, but
        // still short of the 1.1 a healthy loan must hold.
        bool healthy = instance.isLoanHealthy(
            _loan(LoanHelpers.positions(firstPool, 27.5e18), LoanHelpers.positions(firstPool, 20e18))
        );

        assertFalse(healthy);
    }

    function test_isLoanHealthy_RoundsRequiredCollateralUp() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        // Two base units of collateral are worth 4, discounted to 3; one base unit of borrow is worth 2, inflated
        // to 3. The 3.3 required is rounded up to 4, which 3 of collateral does not meet; rounding down would.
        bool healthy =
            instance.isLoanHealthy(_loan(LoanHelpers.positions(firstPool, 2), LoanHelpers.positions(firstPool, 1)));

        assertFalse(healthy);
    }

    function test_isLoanHealthy_ReturnsTrueWhenLoanHasNoBorrows() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        bool healthy = instance.isLoanHealthy(LoanHelpers.loanWithSingleCollateral(borrower, firstPool, 55e18));

        assertTrue(healthy);
    }

    function test_isLoanHealthy_ReturnsTrueWhenLoanIsEmpty() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        bool healthy = instance.isLoanHealthy(LoanHelpers.emptyLoan());

        assertTrue(healthy);
    }

    function test_isLoanHealthy_ReturnsFalseWhenLoanHasNoCollateral() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        bool healthy = instance.isLoanHealthy(LoanHelpers.loanWithSingleBorrow(borrower, firstPool, 20e18));

        assertFalse(healthy);
    }

    // isLoanLiquidatable()

    function test_isLoanLiquidatable_ReturnsFalseForOverCollateralisedLoan() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        (bool liquidatable, uint256 health) = instance.isLoanLiquidatable(
            _loan(LoanHelpers.positions(firstPool, 55e18), LoanHelpers.positions(firstPool, 20e18))
        );

        assertFalse(liquidatable);
        assertEq(health, 2e18);
    }

    function test_isLoanLiquidatable_ReturnsTrueForUnderCollateralisedLoan() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        // 88 of collateral against 132 of debt, i.e. a health of two thirds.
        (bool liquidatable, uint256 health) = instance.isLoanLiquidatable(
            _loan(LoanHelpers.positions(firstPool, 55e18), LoanHelpers.positions(firstPool, 60e18))
        );

        assertTrue(liquidatable);
        assertEq(health, 666_666_666_666_666_666);
    }

    function test_isLoanLiquidatable_ReturnsFalseAtExactlyOne() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        // 44 of collateral against 44 of debt, i.e. the loan is exactly solvent and not yet liquidatable.
        (bool liquidatable, uint256 health) = instance.isLoanLiquidatable(
            _loan(LoanHelpers.positions(firstPool, 27.5e18), LoanHelpers.positions(firstPool, 20e18))
        );

        assertFalse(liquidatable);
        assertEq(health, 1e18);
    }

    function test_isLoanLiquidatable_ReturnsTrueJustBelowOne() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        (bool liquidatable,) = instance.isLoanLiquidatable(
            _loan(LoanHelpers.positions(firstPool, 27.5e18 - 1), LoanHelpers.positions(firstPool, 20e18))
        );

        assertTrue(liquidatable);
    }

    function test_isLoanLiquidatable_ReturnsFalseWhenLoanHasNoBorrows() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        (bool liquidatable, uint256 health) =
            instance.isLoanLiquidatable(LoanHelpers.loanWithSingleCollateral(borrower, firstPool, 55e18));

        assertFalse(liquidatable);
        assertEq(health, type(uint256).max);
    }

    function test_isLoanLiquidatable_ReturnsFalseWhenLoanIsEmpty() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        (bool liquidatable, uint256 health) = instance.isLoanLiquidatable(LoanHelpers.emptyLoan());

        assertFalse(liquidatable);
        assertEq(health, type(uint256).max);
    }

    function test_isLoanLiquidatable_ReturnsTrueWhenLoanHasNoCollateral() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        (bool liquidatable, uint256 health) =
            instance.isLoanLiquidatable(LoanHelpers.loanWithSingleBorrow(borrower, firstPool, 20e18));

        assertTrue(liquidatable);
        assertEq(health, 0);
    }

    // getPoolFactors()

    function test_getPoolFactors_ReturnsFactorsOfAddedPool() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        FactorLoanEvaluator.PoolFactors memory poolFactors = instance.getPoolFactors(secondPool);

        assertEq(poolFactors.collateralFactor, 7000);
        assertEq(poolFactors.borrowFactor, 12_000);
        assertTrue(poolFactors.isAdded);
    }

    function test_getPoolFactors_RevertsWhenPoolIsUnknown() public {
        vm.expectRevert(abi.encodeWithSelector(FactorLoanEvaluator.PoolUnknown.selector, unknownPool));
        evaluator.getPoolFactors(unknownPool);
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(evaluator.contractName(), "FactorLoanEvaluator");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(evaluator.contractVersion(), "1.0.0");
    }

    // supportsInterface()

    function test_supportsInterface_ReturnsTrueForILoanEvaluator() public view {
        assertTrue(evaluator.supportsInterface(type(ILoanEvaluator).interfaceId));
    }

    function test_supportsInterface_ReturnsTrueForIVersioned() public view {
        assertTrue(evaluator.supportsInterface(type(IVersioned).interfaceId));
    }

    function test_supportsInterface_ReturnsTrueForIERC165() public view {
        assertTrue(evaluator.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_ReturnsTrueForIAccessControl() public view {
        assertTrue(evaluator.supportsInterface(type(IAccessControl).interfaceId));
    }

    function test_supportsInterface_ReturnsTrueForIAccessControlEnumerable() public view {
        assertTrue(evaluator.supportsInterface(type(IAccessControlEnumerable).interfaceId));
    }

    function test_supportsInterface_ReturnsFalseForUnknown() public view {
        assertFalse(evaluator.supportsInterface(bytes4(0xdeadbeef)));
    }

    // isPoolAdded()

    function test_isPoolAdded_ReturnsTrueOnlyForTheAddedPool() public {
        vm.prank(factorConfigurator);
        evaluator.addPool(firstPool, 8000, 11_000);

        assertTrue(evaluator.isPoolAdded(firstPool));
        assertFalse(evaluator.isPoolAdded(secondPool));
    }

    // getLoanHealth()

    function test_getLoanHealth_DiscountsCollateralAndInflatesBorrow() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        // 55 tokens at 2 each is 110 of value, discounted 20% to 88. 20 tokens at 2 each is 40, inflated 10% to
        // 44. The health is 88 / 44.
        uint256 health = instance.getLoanHealth(
            _loan(LoanHelpers.positions(firstPool, 55e18), LoanHelpers.positions(firstPool, 20e18))
        );

        assertEq(health, 2e18);
    }

    function test_getLoanHealth_SumsEveryPosition() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        // The second pool's asset has 6 decimals and is worth 3, so 40 tokens are 120 of value, discounted 30% to
        // 84, and 10 tokens are 30, inflated 20% to 36. The health is (88 + 84) / (44 + 36).
        uint256 health = instance.getLoanHealth(
            _loan(
                LoanHelpers.positions(firstPool, 55e18, secondPool, 40e6),
                LoanHelpers.positions(firstPool, 20e18, secondPool, 10e6)
            )
        );

        assertEq(health, 2.15e18);
    }

    function test_getLoanHealth_RoundsHealthDown() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        // 88 of collateral against 60 tokens worth 120, inflated 10% to 132, i.e. a health of exactly two thirds.
        uint256 health = instance.getLoanHealth(
            _loan(LoanHelpers.positions(firstPool, 55e18), LoanHelpers.positions(firstPool, 60e18))
        );

        assertEq(health, 666_666_666_666_666_666);
    }

    function test_getLoanHealth_RoundsCollateralDownAndBorrowUp() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        // One base unit is worth 2, so the collateral is 1.6 rounded down to 1 and the borrow 2.2 rounded up to 3,
        // leaving a health of one third. Rounding the other way would leave both at 2 and a health of one.
        uint256 health =
            instance.getLoanHealth(_loan(LoanHelpers.positions(firstPool, 1), LoanHelpers.positions(firstPool, 1)));

        assertEq(health, 333_333_333_333_333_333);
    }

    function test_getLoanHealth_ReturnsMaxWhenLoanHasNoBorrows() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        uint256 health = instance.getLoanHealth(LoanHelpers.loanWithSingleCollateral(borrower, firstPool, 55e18));

        assertEq(health, type(uint256).max);
    }

    function test_getLoanHealth_ReturnsMaxWhenLoanIsEmpty() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        uint256 health = instance.getLoanHealth(LoanHelpers.emptyLoan());

        assertEq(health, type(uint256).max);
    }

    function test_getLoanHealth_ReturnsZeroWhenLoanHasNoCollateral() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        uint256 health = instance.getLoanHealth(LoanHelpers.loanWithSingleBorrow(borrower, firstPool, 20e18));

        assertEq(health, 0);
    }

    function test_getLoanHealth_RevertsWhenCollateralPoolIsUnknown() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        vm.expectRevert(abi.encodeWithSelector(FactorLoanEvaluator.PoolUnknown.selector, unknownPool));
        instance.getLoanHealth(
            _loan(LoanHelpers.positions(unknownPool, 55e18), LoanHelpers.positions(firstPool, 20e18))
        );
    }

    function test_getLoanHealth_RevertsWhenBorrowPoolIsUnknown() public {
        FactorLoanEvaluator instance = _deploy(_poolFactorConfigs());

        vm.expectRevert(abi.encodeWithSelector(FactorLoanEvaluator.PoolUnknown.selector, unknownPool));
        instance.getLoanHealth(
            _loan(LoanHelpers.positions(firstPool, 55e18), LoanHelpers.positions(unknownPool, 20e18))
        );
    }

    // Helpers

    function _deploy(FactorLoanEvaluator.PoolFactorConfig[] memory configs)
        internal
        returns (FactorLoanEvaluator instance)
    {
        instance = _clone();
        instance.initialize(
            defaultAdmin, oracleUpdater, factorConfigurator, address(oracle), MIN_HEALTH_FACTOR, configs
        );
    }

    function _clone() internal returns (FactorLoanEvaluator) {
        return FactorLoanEvaluator(Clones.clone(address(implementation)));
    }

    function _poolFactorConfigs() internal view returns (FactorLoanEvaluator.PoolFactorConfig[] memory configs) {
        configs = new FactorLoanEvaluator.PoolFactorConfig[](2);
        configs[0] =
            FactorLoanEvaluator.PoolFactorConfig({pool: firstPool, collateralFactor: 8000, borrowFactor: 11_000});
        configs[1] =
            FactorLoanEvaluator.PoolFactorConfig({pool: secondPool, collateralFactor: 7000, borrowFactor: 12_000});
    }

    function _loan(ILendingCore.LoanPosition[] memory collaterals, ILendingCore.LoanPosition[] memory borrows)
        internal
        view
        returns (ILendingCore.Loan memory)
    {
        return ILendingCore.Loan({account: borrower, collaterals: collaterals, borrows: borrows});
    }

    function _assertInitializationRolledBack(FactorLoanEvaluator instance) internal view {
        assertEq(address(instance.oracle()), address(0));
        assertEq(instance.minHealthFactor(), 0);
        assertFalse(instance.isPoolAdded(firstPool));
        assertFalse(instance.isPoolAdded(secondPool));
    }
}
