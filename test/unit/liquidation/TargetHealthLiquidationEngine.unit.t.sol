// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IAccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "src/interfaces/IVersioned.sol";
import {ILendingCore} from "src/lending-core/interfaces/ILendingCore.sol";
import {ILiquidationEngine} from "src/liquidation/interfaces/ILiquidationEngine.sol";
import {TargetHealthLiquidationEngine} from "src/liquidation/TargetHealthLiquidationEngine.sol";
import {IPool} from "src/pool/interfaces/IPool.sol";
import {MockLoanEvaluator} from "../loan/mocks/MockLoanEvaluator.sol";
import {MockOracle} from "../../mocks/MockOracle.sol";
import {LoanHelpers} from "../../helpers/LoanHelpers.sol";

contract TargetHealthLiquidationEngineUnitTest is Test {
    /// @dev Every pool is priced at one unit of numeraire per token unit, so a position's value is its amount and
    ///      every expected figure below can be read off the amounts directly.
    uint256 constant UNIT_PRICE = 1;
    uint8 constant UNIT_PRICE_DECIMALS = 0;

    uint256 constant TARGET_HEALTH_FACTOR = 1.05e18;
    uint256 constant RAMP_START_HEALTH = 1e18;
    uint256 constant RAMP_END_HEALTH = 0.9e18;

    /// @dev Flat 10% at every health, so tests that are not about the ramp can ignore it.
    uint16 constant FLAT_MIN_BONUS = 1000;
    uint16 constant FLAT_MAX_BONUS = 1000;

    /// @dev Ramps 0% to 20% across the bounds above, so the midpoint health pays 10%.
    uint16 constant RAMPED_MIN_BONUS = 0;
    uint16 constant RAMPED_MAX_BONUS = 2000;

    /// @dev Halfway between the ramp bounds, where the ramped collateral pays half of its maximum bonus.
    uint256 constant MID_RAMP_HEALTH = 0.95e18;

    uint256 constant FLAT_COLLATERAL = 55e18;
    uint256 constant RAMPED_COLLATERAL = 120e18;
    uint256 constant FIRST_BORROW = 60e18;
    uint256 constant SECOND_BORROW = 20e18;

    uint256 constant MIN_LEFTOVER_VALUE = 50e18;
    /// @dev Twice the minimum leftover value, and above the default loan's 80e18 of debt, so closing that loan out
    ///      never meets the cap.
    uint256 constant CLOSE_OUT_THRESHOLD = 100e18;

    address internal defaultAdmin;
    address internal oracleUpdater;
    address internal liquidationConfigurator;
    address internal nonLiquidationConfigurator;
    address internal violator;

    MockOracle internal oracle;
    MockLoanEvaluator internal evaluator;
    IPool internal flatBonusCollateralPool;
    IPool internal rampedBonusCollateralPool;
    IPool internal firstBorrowPool;
    IPool internal secondBorrowPool;
    IPool internal unlistedPool;

    TargetHealthLiquidationEngine internal implementation;
    TargetHealthLiquidationEngine internal engine;

    function setUp() public {
        defaultAdmin = makeAddr("defaultAdmin");
        oracleUpdater = makeAddr("oracleUpdater");
        liquidationConfigurator = makeAddr("liquidationConfigurator");
        nonLiquidationConfigurator = makeAddr("nonLiquidationConfigurator");
        violator = makeAddr("violator");

        flatBonusCollateralPool = IPool(makeAddr("flatBonusCollateralPool"));
        rampedBonusCollateralPool = IPool(makeAddr("rampedBonusCollateralPool"));
        firstBorrowPool = IPool(makeAddr("firstBorrowPool"));
        secondBorrowPool = IPool(makeAddr("secondBorrowPool"));
        unlistedPool = IPool(makeAddr("unlistedPool"));

        // The two healths a liquidation is measured against are set independently: the one before it is the
        // argument passed to `liquidate`, which fixes the bonus, while the evaluator answers only for the loan
        // the liquidation leaves behind. The evaluator defaults to maximum health, which no target would admit,
        // so every test starts from a value the target accepts.
        evaluator = new MockLoanEvaluator();
        evaluator.setHealth(1e18);

        oracle = new MockOracle();
        oracle.setPrice(flatBonusCollateralPool, UNIT_PRICE, UNIT_PRICE_DECIMALS);
        oracle.setPrice(rampedBonusCollateralPool, UNIT_PRICE, UNIT_PRICE_DECIMALS);
        oracle.setPrice(firstBorrowPool, UNIT_PRICE, UNIT_PRICE_DECIMALS);
        oracle.setPrice(secondBorrowPool, UNIT_PRICE, UNIT_PRICE_DECIMALS);

        implementation = new TargetHealthLiquidationEngine();
        engine = _newEngine();
        engine.initialize(
            defaultAdmin,
            oracleUpdater,
            liquidationConfigurator,
            address(oracle),
            TARGET_HEALTH_FACTOR,
            RAMP_START_HEALTH,
            RAMP_END_HEALTH,
            0,
            CLOSE_OUT_THRESHOLD,
            _bonusConfigs()
        );
    }

    // initialize()

    function test_initialize_GrantsRoles() public view {
        assertTrue(engine.hasRole(engine.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertTrue(engine.hasRole(engine.ORACLE_UPDATER_ROLE(), oracleUpdater));
        assertTrue(engine.hasRole(engine.LIQUIDATION_CONFIG_ROLE(), liquidationConfigurator));
    }

    function test_initialize_UsesDefaultAdminAsRoleAdmin() public view {
        assertEq(engine.getRoleAdmin(engine.LIQUIDATION_CONFIG_ROLE()), engine.DEFAULT_ADMIN_ROLE());
    }

    function test_initialize_AllowsZeroAddressRoleMembers() public {
        TargetHealthLiquidationEngine rolelessEngine = _newEngine();

        rolelessEngine.initialize(
            address(0),
            address(0),
            address(0),
            address(oracle),
            TARGET_HEALTH_FACTOR,
            RAMP_START_HEALTH,
            RAMP_END_HEALTH,
            0,
            CLOSE_OUT_THRESHOLD,
            _bonusConfigs()
        );

        assertEq(rolelessEngine.getRoleMemberCount(rolelessEngine.DEFAULT_ADMIN_ROLE()), 0);
        assertEq(rolelessEngine.getRoleMemberCount(rolelessEngine.ORACLE_UPDATER_ROLE()), 0);
        assertEq(rolelessEngine.getRoleMemberCount(rolelessEngine.LIQUIDATION_CONFIG_ROLE()), 0);
    }

    function test_initialize_SetsOracleAndParameters() public view {
        (uint256 startHealth, uint256 endHealth) = engine.bonusRamp();
        assertEq(engine.oracle(), address(oracle));
        assertEq(engine.targetHealthFactor(), TARGET_HEALTH_FACTOR);
        assertEq(startHealth, RAMP_START_HEALTH);
        assertEq(endHealth, RAMP_END_HEALTH);
        assertEq(engine.minLeftoverValue(), 0);
        assertEq(engine.closeOutThreshold(), CLOSE_OUT_THRESHOLD);
    }

    function test_initialize_AddsCollateralBonuses() public view {
        TargetHealthLiquidationEngine.CollateralBonus memory rampedBonus =
            engine.getCollateralBonus(rampedBonusCollateralPool);
        assertEq(rampedBonus.minBonus, RAMPED_MIN_BONUS);
        assertEq(rampedBonus.maxBonus, RAMPED_MAX_BONUS);
        assertTrue(rampedBonus.isAdded);
    }

    function test_initialize_AddsCollateralBonusWithEqualMinAndMax() public view {
        TargetHealthLiquidationEngine.CollateralBonus memory flatBonus =
            engine.getCollateralBonus(flatBonusCollateralPool);
        assertEq(flatBonus.minBonus, FLAT_MIN_BONUS);
        assertEq(flatBonus.maxBonus, FLAT_MAX_BONUS);
        assertTrue(flatBonus.isAdded);
    }

    function test_initialize_RevertsWhenTargetHealthFactorIsBelowOne() public {
        TargetHealthLiquidationEngine newEngine = _newEngine();

        vm.expectRevert(
            abi.encodeWithSelector(TargetHealthLiquidationEngine.TargetHealthFactorTooLow.selector, 1e18 - 1)
        );
        newEngine.initialize(
            defaultAdmin,
            oracleUpdater,
            liquidationConfigurator,
            address(oracle),
            1e18 - 1,
            RAMP_START_HEALTH,
            RAMP_END_HEALTH,
            0,
            CLOSE_OUT_THRESHOLD,
            _bonusConfigs()
        );
    }

    function test_initialize_RevertsWhenBonusRampDoesNotFall() public {
        TargetHealthLiquidationEngine newEngine = _newEngine();

        vm.expectRevert(
            abi.encodeWithSelector(
                TargetHealthLiquidationEngine.BonusRampInvalid.selector, RAMP_START_HEALTH, RAMP_START_HEALTH
            )
        );
        newEngine.initialize(
            defaultAdmin,
            oracleUpdater,
            liquidationConfigurator,
            address(oracle),
            TARGET_HEALTH_FACTOR,
            RAMP_START_HEALTH,
            RAMP_START_HEALTH,
            0,
            CLOSE_OUT_THRESHOLD,
            _bonusConfigs()
        );
    }

    function test_initialize_RevertsWhenBonusRampStartsAboveOne() public {
        TargetHealthLiquidationEngine newEngine = _newEngine();

        vm.expectRevert(abi.encodeWithSelector(TargetHealthLiquidationEngine.BonusRampStartTooHigh.selector, 1e18 + 1));
        newEngine.initialize(
            defaultAdmin,
            oracleUpdater,
            liquidationConfigurator,
            address(oracle),
            TARGET_HEALTH_FACTOR,
            1e18 + 1,
            RAMP_END_HEALTH,
            0,
            CLOSE_OUT_THRESHOLD,
            _bonusConfigs()
        );
    }

    function test_initialize_RevertsWhenCloseOutWindowIsEmpty() public {
        TargetHealthLiquidationEngine newEngine = _newEngine();

        vm.expectRevert(
            abi.encodeWithSelector(
                TargetHealthLiquidationEngine.CloseOutWindowEmpty.selector, CLOSE_OUT_THRESHOLD, CLOSE_OUT_THRESHOLD
            )
        );
        newEngine.initialize(
            defaultAdmin,
            oracleUpdater,
            liquidationConfigurator,
            address(oracle),
            TARGET_HEALTH_FACTOR,
            RAMP_START_HEALTH,
            RAMP_END_HEALTH,
            CLOSE_OUT_THRESHOLD,
            CLOSE_OUT_THRESHOLD,
            _bonusConfigs()
        );
    }

    function test_initialize_RevertsWhenBonusRangeIsInverted() public {
        TargetHealthLiquidationEngine newEngine = _newEngine();
        TargetHealthLiquidationEngine.CollateralBonusConfig[] memory configs =
            new TargetHealthLiquidationEngine.CollateralBonusConfig[](1);
        configs[0] = TargetHealthLiquidationEngine.CollateralBonusConfig({
            pool: flatBonusCollateralPool, minBonus: 1001, maxBonus: 1000
        });

        vm.expectRevert(abi.encodeWithSelector(TargetHealthLiquidationEngine.BonusRangeInvalid.selector, 1001, 1000));
        newEngine.initialize(
            defaultAdmin,
            oracleUpdater,
            liquidationConfigurator,
            address(oracle),
            TARGET_HEALTH_FACTOR,
            RAMP_START_HEALTH,
            RAMP_END_HEALTH,
            0,
            CLOSE_OUT_THRESHOLD,
            configs
        );
    }

    function test_initialize_RevertsWhenPoolIsConfiguredTwice() public {
        TargetHealthLiquidationEngine newEngine = _newEngine();
        TargetHealthLiquidationEngine.CollateralBonusConfig[] memory configs =
            new TargetHealthLiquidationEngine.CollateralBonusConfig[](2);
        configs[0] = TargetHealthLiquidationEngine.CollateralBonusConfig({
            pool: flatBonusCollateralPool, minBonus: FLAT_MIN_BONUS, maxBonus: FLAT_MAX_BONUS
        });
        configs[1] = configs[0];

        vm.expectRevert(
            abi.encodeWithSelector(TargetHealthLiquidationEngine.PoolAlreadyAdded.selector, flatBonusCollateralPool)
        );
        newEngine.initialize(
            defaultAdmin,
            oracleUpdater,
            liquidationConfigurator,
            address(oracle),
            TARGET_HEALTH_FACTOR,
            RAMP_START_HEALTH,
            RAMP_END_HEALTH,
            0,
            CLOSE_OUT_THRESHOLD,
            configs
        );
    }

    // updateTargetHealthFactor()

    function test_updateTargetHealthFactor_UpdatesValue() public {
        vm.prank(liquidationConfigurator);
        engine.updateTargetHealthFactor(1.2e18);

        assertEq(engine.targetHealthFactor(), 1.2e18);
    }

    function test_updateTargetHealthFactor_EmitsEvent() public {
        vm.expectEmit();
        emit TargetHealthLiquidationEngine.TargetHealthFactorUpdated(TARGET_HEALTH_FACTOR, 1.2e18);

        vm.prank(liquidationConfigurator);
        engine.updateTargetHealthFactor(1.2e18);
    }

    function test_updateTargetHealthFactor_AllowsOne() public {
        vm.prank(liquidationConfigurator);
        engine.updateTargetHealthFactor(1e18);

        assertEq(engine.targetHealthFactor(), 1e18);
    }

    function test_updateTargetHealthFactor_RevertsWhenBelowOne() public {
        vm.expectRevert(
            abi.encodeWithSelector(TargetHealthLiquidationEngine.TargetHealthFactorTooLow.selector, 1e18 - 1)
        );
        vm.prank(liquidationConfigurator);
        engine.updateTargetHealthFactor(1e18 - 1);
    }

    function test_updateTargetHealthFactor_RevertsWhenCallerLacksRole() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonLiquidationConfigurator,
                engine.LIQUIDATION_CONFIG_ROLE()
            )
        );
        vm.prank(nonLiquidationConfigurator);
        engine.updateTargetHealthFactor(1.2e18);
    }

    // updateBonusRamp()

    function test_updateBonusRamp_UpdatesBounds() public {
        vm.prank(liquidationConfigurator);
        engine.updateBonusRamp(0.99e18, 0.8e18);

        (uint256 startHealth, uint256 endHealth) = engine.bonusRamp();
        assertEq(startHealth, 0.99e18);
        assertEq(endHealth, 0.8e18);
    }

    function test_updateBonusRamp_EmitsEvent() public {
        vm.expectEmit();
        emit TargetHealthLiquidationEngine.BonusRampUpdated(RAMP_START_HEALTH, RAMP_END_HEALTH, 0.99e18, 0.8e18);

        vm.prank(liquidationConfigurator);
        engine.updateBonusRamp(0.99e18, 0.8e18);
    }

    function test_updateBonusRamp_AllowsStartAtOne() public {
        vm.prank(liquidationConfigurator);
        engine.updateBonusRamp(1e18, 0.8e18);

        (uint256 startHealth, uint256 endHealth) = engine.bonusRamp();
        assertEq(startHealth, 1e18);
        assertEq(endHealth, 0.8e18);
    }

    function test_updateBonusRamp_AllowsStartOneAboveEnd() public {
        vm.prank(liquidationConfigurator);
        engine.updateBonusRamp(0.9e18 + 1, 0.9e18);

        (uint256 startHealth, uint256 endHealth) = engine.bonusRamp();
        assertEq(startHealth, 0.9e18 + 1);
        assertEq(endHealth, 0.9e18);
    }

    function test_updateBonusRamp_RevertsWhenRampDoesNotFall() public {
        vm.expectRevert(abi.encodeWithSelector(TargetHealthLiquidationEngine.BonusRampInvalid.selector, 0.9e18, 0.9e18));
        vm.prank(liquidationConfigurator);
        engine.updateBonusRamp(0.9e18, 0.9e18);
    }

    function test_updateBonusRamp_RevertsWhenStartIsAboveOne() public {
        vm.expectRevert(abi.encodeWithSelector(TargetHealthLiquidationEngine.BonusRampStartTooHigh.selector, 1e18 + 1));
        vm.prank(liquidationConfigurator);
        engine.updateBonusRamp(1e18 + 1, 0.8e18);
    }

    function test_updateBonusRamp_RevertsWhenCallerLacksRole() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonLiquidationConfigurator,
                engine.LIQUIDATION_CONFIG_ROLE()
            )
        );
        vm.prank(nonLiquidationConfigurator);
        engine.updateBonusRamp(0.99e18, 0.8e18);
    }

    // updateMinLeftoverValue()

    function test_updateMinLeftoverValue_UpdatesValue() public {
        vm.prank(liquidationConfigurator);
        engine.updateMinLeftoverValue(MIN_LEFTOVER_VALUE);

        assertEq(engine.minLeftoverValue(), MIN_LEFTOVER_VALUE);
    }

    function test_updateMinLeftoverValue_EmitsEvent() public {
        vm.expectEmit();
        emit TargetHealthLiquidationEngine.MinLeftoverValueUpdated(0, MIN_LEFTOVER_VALUE);

        vm.prank(liquidationConfigurator);
        engine.updateMinLeftoverValue(MIN_LEFTOVER_VALUE);
    }

    function test_updateMinLeftoverValue_AllowsOneBelowCloseOutThreshold() public {
        vm.prank(liquidationConfigurator);
        engine.updateMinLeftoverValue(CLOSE_OUT_THRESHOLD - 1);

        assertEq(engine.minLeftoverValue(), CLOSE_OUT_THRESHOLD - 1);
    }

    function test_updateMinLeftoverValue_RevertsWhenAtCloseOutThreshold() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                TargetHealthLiquidationEngine.CloseOutWindowEmpty.selector, CLOSE_OUT_THRESHOLD, CLOSE_OUT_THRESHOLD
            )
        );
        vm.prank(liquidationConfigurator);
        engine.updateMinLeftoverValue(CLOSE_OUT_THRESHOLD);
    }

    function test_updateMinLeftoverValue_RevertsWhenCallerLacksRole() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonLiquidationConfigurator,
                engine.LIQUIDATION_CONFIG_ROLE()
            )
        );
        vm.prank(nonLiquidationConfigurator);
        engine.updateMinLeftoverValue(MIN_LEFTOVER_VALUE);
    }

    // updateCloseOutThreshold()

    function test_updateCloseOutThreshold_UpdatesValue() public {
        vm.prank(liquidationConfigurator);
        engine.updateCloseOutThreshold(200e18);

        assertEq(engine.closeOutThreshold(), 200e18);
    }

    function test_updateCloseOutThreshold_EmitsEvent() public {
        vm.expectEmit();
        emit TargetHealthLiquidationEngine.CloseOutThresholdUpdated(CLOSE_OUT_THRESHOLD, 200e18);

        vm.prank(liquidationConfigurator);
        engine.updateCloseOutThreshold(200e18);
    }

    function test_updateCloseOutThreshold_AllowsOneAboveMinLeftoverValue() public {
        _setMinLeftoverValue(MIN_LEFTOVER_VALUE);

        vm.prank(liquidationConfigurator);
        engine.updateCloseOutThreshold(MIN_LEFTOVER_VALUE + 1);

        assertEq(engine.closeOutThreshold(), MIN_LEFTOVER_VALUE + 1);
    }

    function test_updateCloseOutThreshold_RevertsWhenAtMinLeftoverValue() public {
        _setMinLeftoverValue(MIN_LEFTOVER_VALUE);

        vm.expectRevert(
            abi.encodeWithSelector(
                TargetHealthLiquidationEngine.CloseOutWindowEmpty.selector, MIN_LEFTOVER_VALUE, MIN_LEFTOVER_VALUE
            )
        );
        vm.prank(liquidationConfigurator);
        engine.updateCloseOutThreshold(MIN_LEFTOVER_VALUE);
    }

    function test_updateCloseOutThreshold_RevertsWhenCallerLacksRole() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonLiquidationConfigurator,
                engine.LIQUIDATION_CONFIG_ROLE()
            )
        );
        vm.prank(nonLiquidationConfigurator);
        engine.updateCloseOutThreshold(200e18);
    }

    // addPool()

    function test_addPool_AddsBonuses() public {
        vm.prank(liquidationConfigurator);
        engine.addPool(firstBorrowPool, 100, 900);

        TargetHealthLiquidationEngine.CollateralBonus memory bonus = engine.getCollateralBonus(firstBorrowPool);
        assertEq(bonus.minBonus, 100);
        assertEq(bonus.maxBonus, 900);
        assertTrue(bonus.isAdded);
    }

    function test_addPool_EmitsEvent() public {
        vm.expectEmit();
        emit TargetHealthLiquidationEngine.PoolAdded(firstBorrowPool, 100, 900);

        vm.prank(liquidationConfigurator);
        engine.addPool(firstBorrowPool, 100, 900);
    }

    function test_addPool_AllowsEqualMinAndMaxBonus() public {
        vm.prank(liquidationConfigurator);
        engine.addPool(firstBorrowPool, 900, 900);

        assertTrue(engine.isPoolAdded(firstBorrowPool));
    }

    function test_addPool_RevertsWhenPoolIsAlreadyAdded() public {
        vm.expectRevert(
            abi.encodeWithSelector(TargetHealthLiquidationEngine.PoolAlreadyAdded.selector, flatBonusCollateralPool)
        );
        vm.prank(liquidationConfigurator);
        engine.addPool(flatBonusCollateralPool, 100, 900);
    }

    function test_addPool_RevertsWhenBonusRangeIsInverted() public {
        vm.expectRevert(abi.encodeWithSelector(TargetHealthLiquidationEngine.BonusRangeInvalid.selector, 901, 900));
        vm.prank(liquidationConfigurator);
        engine.addPool(firstBorrowPool, 901, 900);
    }

    function test_addPool_RevertsWhenCallerLacksRole() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonLiquidationConfigurator,
                engine.LIQUIDATION_CONFIG_ROLE()
            )
        );
        vm.prank(nonLiquidationConfigurator);
        engine.addPool(firstBorrowPool, 100, 900);
    }

    // updatePoolBonuses()

    function test_updatePoolBonuses_UpdatesBonuses() public {
        vm.prank(liquidationConfigurator);
        engine.updatePoolBonuses(flatBonusCollateralPool, 300, 1500);

        TargetHealthLiquidationEngine.CollateralBonus memory bonus = engine.getCollateralBonus(flatBonusCollateralPool);
        assertEq(bonus.minBonus, 300);
        assertEq(bonus.maxBonus, 1500);
    }

    function test_updatePoolBonuses_EmitsEvent() public {
        vm.expectEmit();
        emit TargetHealthLiquidationEngine.PoolBonusesUpdated(
            flatBonusCollateralPool, FLAT_MIN_BONUS, FLAT_MAX_BONUS, 300, 1500
        );

        vm.prank(liquidationConfigurator);
        engine.updatePoolBonuses(flatBonusCollateralPool, 300, 1500);
    }

    function test_updatePoolBonuses_RevertsWhenPoolIsUnknown() public {
        vm.expectRevert(abi.encodeWithSelector(TargetHealthLiquidationEngine.PoolUnknown.selector, firstBorrowPool));
        vm.prank(liquidationConfigurator);
        engine.updatePoolBonuses(firstBorrowPool, 300, 1500);
    }

    function test_updatePoolBonuses_RevertsWhenBonusRangeIsInverted() public {
        vm.expectRevert(abi.encodeWithSelector(TargetHealthLiquidationEngine.BonusRangeInvalid.selector, 1501, 1500));
        vm.prank(liquidationConfigurator);
        engine.updatePoolBonuses(flatBonusCollateralPool, 1501, 1500);
    }

    function test_updatePoolBonuses_RevertsWhenCallerLacksRole() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonLiquidationConfigurator,
                engine.LIQUIDATION_CONFIG_ROLE()
            )
        );
        vm.prank(nonLiquidationConfigurator);
        engine.updatePoolBonuses(flatBonusCollateralPool, 300, 1500);
    }

    // liquidate()

    function test_liquidate_ReturnsResolvedSeizuresAndRepayments() public view {
        // 22e18 of collateral at a 10% bonus is paid for by 20e18 of repayment.
        (ILendingCore.LoanPosition[] memory colsToSeize, ILendingCore.LoanPosition[] memory borsToRepay) = engine.liquidate(
            _loan(),
            RAMP_START_HEALTH,
            LoanHelpers.positions(flatBonusCollateralPool, 22e18),
            LoanHelpers.positions(firstBorrowPool, 20e18),
            evaluator
        );

        assertEq(address(colsToSeize[0].pool), address(flatBonusCollateralPool));
        assertEq(colsToSeize[0].amount, 22e18);
        assertEq(address(borsToRepay[0].pool), address(firstBorrowPool));
        assertEq(borsToRepay[0].amount, 20e18);
    }

    function test_liquidate_ResolvesMaxToWholeCollateralPosition() public view {
        // The whole 55e18 position at a 10% bonus is paid for by 50e18 of repayment.
        (ILendingCore.LoanPosition[] memory colsToSeize,) = engine.liquidate(
            _loan(),
            RAMP_START_HEALTH,
            LoanHelpers.positions(flatBonusCollateralPool, type(uint256).max),
            LoanHelpers.positions(firstBorrowPool, 50e18),
            evaluator
        );

        assertEq(colsToSeize[0].amount, FLAT_COLLATERAL);
    }

    function test_liquidate_ResolvesMaxCollateralNotInLoanToZero() public view {
        ILendingCore.Loan memory loan = _singlePositionLoan(FLAT_COLLATERAL, FIRST_BORROW);
        ILendingCore.LoanPosition[] memory reqCols =
            LoanHelpers.positions(rampedBonusCollateralPool, type(uint256).max, flatBonusCollateralPool, 22e18);

        (ILendingCore.LoanPosition[] memory colsToSeize,) =
            engine.liquidate(loan, RAMP_START_HEALTH, reqCols, LoanHelpers.positions(firstBorrowPool, 20e18), evaluator);

        assertEq(address(colsToSeize[0].pool), address(rampedBonusCollateralPool));
        assertEq(colsToSeize[0].amount, 0);
        assertEq(colsToSeize[1].amount, 22e18);
    }

    function test_liquidate_AllowsMaxOnUnconfiguredCollateralNotInLoan() public view {
        // The unlisted pool has neither a bonus nor a price, so this passes because a zero seizure is never valued.
        (ILendingCore.LoanPosition[] memory colsToSeize,) = engine.liquidate(
            _loan(),
            RAMP_START_HEALTH,
            LoanHelpers.positions(unlistedPool, type(uint256).max),
            LoanHelpers.positions(firstBorrowPool, 20e18),
            evaluator
        );

        assertEq(colsToSeize[0].amount, 0);
    }

    function test_liquidate_AllowsZeroOnUnconfiguredCollateralNotInLoan() public view {
        // As with `type(uint256).max`, the unlisted pool is never valued because its seizure is zero.
        (ILendingCore.LoanPosition[] memory colsToSeize,) = engine.liquidate(
            _loan(),
            RAMP_START_HEALTH,
            LoanHelpers.positions(unlistedPool, 0),
            LoanHelpers.positions(firstBorrowPool, 20e18),
            evaluator
        );

        assertEq(colsToSeize[0].amount, 0);
    }

    function test_liquidate_CapsRepaymentAtDebtOwed() public view {
        (, ILendingCore.LoanPosition[] memory borsToRepay) = engine.liquidate(
            _loan(),
            RAMP_START_HEALTH,
            LoanHelpers.positions(flatBonusCollateralPool, 22e18),
            LoanHelpers.positions(firstBorrowPool, FIRST_BORROW * 100),
            evaluator
        );

        assertEq(borsToRepay[0].amount, FIRST_BORROW);
    }

    function test_liquidate_ResolvesBorrowNotInLoanToZero() public view {
        ILendingCore.Loan memory loan = _singlePositionLoan(FLAT_COLLATERAL, FIRST_BORROW);
        ILendingCore.LoanPosition[] memory reqBors =
            LoanHelpers.positions(secondBorrowPool, 10e18, firstBorrowPool, 20e18);

        (, ILendingCore.LoanPosition[] memory borsToRepay) = engine.liquidate(
            loan, RAMP_START_HEALTH, LoanHelpers.positions(flatBonusCollateralPool, 22e18), reqBors, evaluator
        );

        assertEq(address(borsToRepay[0].pool), address(secondBorrowPool));
        assertEq(borsToRepay[0].amount, 0);
        assertEq(borsToRepay[1].amount, 20e18);
    }

    function test_liquidate_AllowsUnpricedBorrowNotInLoan() public view {
        // The unlisted pool has no price, so this passes because a zero repayment is never valued.
        ILendingCore.LoanPosition[] memory reqBors = LoanHelpers.positions(unlistedPool, 10e18, firstBorrowPool, 20e18);

        (, ILendingCore.LoanPosition[] memory borsToRepay) = engine.liquidate(
            _loan(), RAMP_START_HEALTH, LoanHelpers.positions(flatBonusCollateralPool, 22e18), reqBors, evaluator
        );

        assertEq(borsToRepay[0].amount, 0);
    }

    function test_liquidate_AllowsSeizingNothing() public view {
        (ILendingCore.LoanPosition[] memory colsToSeize,) = engine.liquidate(
            _loan(),
            RAMP_START_HEALTH,
            LoanHelpers.noPositions(),
            LoanHelpers.positions(firstBorrowPool, 20e18),
            evaluator
        );

        assertEq(colsToSeize.length, 0);
    }

    function test_liquidate_AllowsClaimingLessThanEntitlement() public view {
        // 20e18 of repayment entitles the liquidator to 22e18 of collateral; they take 11e18 and forfeit the rest.
        (ILendingCore.LoanPosition[] memory colsToSeize,) = engine.liquidate(
            _loan(),
            RAMP_START_HEALTH,
            LoanHelpers.positions(flatBonusCollateralPool, 11e18),
            LoanHelpers.positions(firstBorrowPool, 20e18),
            evaluator
        );

        assertEq(colsToSeize[0].amount, 11e18);
    }

    function test_liquidate_SeizesEachCollateralAtItsOwnBonus() public view {
        // At the ramp's end the collaterals pay 10% and 20%, so 22e18 and 24e18 together cost 20e18 + 20e18.
        ILendingCore.LoanPosition[] memory reqCols =
            LoanHelpers.positions(flatBonusCollateralPool, 22e18, rampedBonusCollateralPool, 24e18);

        (ILendingCore.LoanPosition[] memory colsToSeize,) = engine.liquidate(
            _loan(), RAMP_END_HEALTH, reqCols, LoanHelpers.positions(firstBorrowPool, 40e18), evaluator
        );

        assertEq(colsToSeize[0].amount, 22e18);
        assertEq(colsToSeize[1].amount, 24e18);
    }

    function test_liquidate_AppliesMinBonusAtRampStart() public view {
        // At the ramp's start the second collateral pays nothing, so 20e18 of it costs a full 20e18.
        (ILendingCore.LoanPosition[] memory colsToSeize,) = engine.liquidate(
            _loan(),
            RAMP_START_HEALTH,
            LoanHelpers.positions(rampedBonusCollateralPool, 20e18),
            LoanHelpers.positions(firstBorrowPool, 20e18),
            evaluator
        );

        assertEq(colsToSeize[0].amount, 20e18);
    }

    function test_liquidate_AppliesMaxBonusAtRampEnd() public view {
        // At the ramp's end the second collateral pays 20%, so 20e18 of repayment takes 24e18.
        (ILendingCore.LoanPosition[] memory colsToSeize,) = engine.liquidate(
            _loan(),
            RAMP_END_HEALTH,
            LoanHelpers.positions(rampedBonusCollateralPool, 24e18),
            LoanHelpers.positions(firstBorrowPool, 20e18),
            evaluator
        );

        assertEq(colsToSeize[0].amount, 24e18);
    }

    function test_liquidate_InterpolatesBonusInsideRamp() public view {
        // Halfway between the bounds the 0% to 20% ramp pays 10%, so 20e18 of repayment takes 22e18.
        (ILendingCore.LoanPosition[] memory colsToSeize,) = engine.liquidate(
            _loan(),
            MID_RAMP_HEALTH,
            LoanHelpers.positions(rampedBonusCollateralPool, 22e18),
            LoanHelpers.positions(firstBorrowPool, 20e18),
            evaluator
        );

        assertEq(colsToSeize[0].amount, 22e18);
    }

    function test_liquidate_AllowsCloseOutAtCloseOutThreshold() public view {
        // The loan owes exactly the threshold, and 110e18 of collateral at a 10% bonus is paid for by all of it.
        ILendingCore.Loan memory loan = _singlePositionLoan(200e18, CLOSE_OUT_THRESHOLD);

        (, ILendingCore.LoanPosition[] memory borsToRepay) = engine.liquidate(
            loan,
            RAMP_START_HEALTH,
            LoanHelpers.positions(flatBonusCollateralPool, 110e18),
            LoanHelpers.positions(firstBorrowPool, CLOSE_OUT_THRESHOLD),
            evaluator
        );

        assertEq(borsToRepay[0].amount, CLOSE_OUT_THRESHOLD);
    }

    function test_liquidate_AllowsHealthAfterAtTarget() public {
        evaluator.setHealth(TARGET_HEALTH_FACTOR);

        (ILendingCore.LoanPosition[] memory colsToSeize,) = engine.liquidate(
            _loan(),
            RAMP_START_HEALTH,
            LoanHelpers.positions(flatBonusCollateralPool, 22e18),
            LoanHelpers.positions(firstBorrowPool, 20e18),
            evaluator
        );

        assertEq(colsToSeize[0].amount, 22e18);
    }

    function test_liquidate_SkipsTargetHealthWhenAllBorrowsRepaid() public {
        // A loan with no debt left reports maximum health, which only passes because the check is waived.
        evaluator.setHealth(type(uint256).max);
        ILendingCore.LoanPosition[] memory reqBors =
            LoanHelpers.positions(firstBorrowPool, FIRST_BORROW, secondBorrowPool, SECOND_BORROW);

        (, ILendingCore.LoanPosition[] memory borsToRepay) = engine.liquidate(
            _loan(),
            RAMP_START_HEALTH,
            LoanHelpers.positions(flatBonusCollateralPool, FLAT_COLLATERAL),
            reqBors,
            evaluator
        );

        assertEq(borsToRepay[0].amount, FIRST_BORROW);
        assertEq(borsToRepay[1].amount, SECOND_BORROW);
    }

    function test_liquidate_AllowsLeftoversAtMinLeftoverValue() public {
        // Repaying 30e18 leaves 50e18 of debt, exactly the threshold, against 142e18 of collateral.
        _setMinLeftoverValue(MIN_LEFTOVER_VALUE);

        (, ILendingCore.LoanPosition[] memory borsToRepay) = engine.liquidate(
            _loan(),
            RAMP_START_HEALTH,
            LoanHelpers.positions(flatBonusCollateralPool, 33e18),
            LoanHelpers.positions(firstBorrowPool, 30e18),
            evaluator
        );

        assertEq(borsToRepay[0].amount, 30e18);
    }

    function test_liquidate_AllowsDustWhenAllBorrowsRepaid() public {
        // 11e18 of collateral is left below the threshold, which only passes because the loan is closed out.
        _setMinLeftoverValue(MIN_LEFTOVER_VALUE);
        ILendingCore.Loan memory loan = _singlePositionLoan(FLAT_COLLATERAL, 40e18);

        (ILendingCore.LoanPosition[] memory colsToSeize,) = engine.liquidate(
            loan,
            RAMP_START_HEALTH,
            LoanHelpers.positions(flatBonusCollateralPool, 44e18),
            LoanHelpers.positions(firstBorrowPool, 40e18),
            evaluator
        );

        assertEq(colsToSeize[0].amount, 44e18);
    }

    function test_liquidate_AllowsDustWhenAllCollateralSeized() public {
        // 10e18 of debt is left below the threshold, which only passes because no collateral remains to pay it.
        _setMinLeftoverValue(MIN_LEFTOVER_VALUE);
        ILendingCore.Loan memory loan = _singlePositionLoan(FLAT_COLLATERAL, 100e18);

        (, ILendingCore.LoanPosition[] memory borsToRepay) = engine.liquidate(
            loan,
            RAMP_START_HEALTH,
            LoanHelpers.positions(flatBonusCollateralPool, type(uint256).max),
            LoanHelpers.positions(firstBorrowPool, 90e18),
            evaluator
        );

        assertEq(borsToRepay[0].amount, 90e18);
    }

    function test_liquidate_AllowsDustWhenAllCollateralSeizedAndMaxNamesPoolNotInLoan() public {
        // Naming the ramped pool, which the loan does not hold, leaves the close-out intact: 10e18 of debt is
        // still left below the threshold with no collateral remaining to pay it.
        _setMinLeftoverValue(MIN_LEFTOVER_VALUE);
        ILendingCore.Loan memory loan = _singlePositionLoan(FLAT_COLLATERAL, 100e18);
        ILendingCore.LoanPosition[] memory reqCols = LoanHelpers.positions(
            flatBonusCollateralPool, type(uint256).max, rampedBonusCollateralPool, type(uint256).max
        );

        (, ILendingCore.LoanPosition[] memory borsToRepay) =
            engine.liquidate(loan, RAMP_START_HEALTH, reqCols, LoanHelpers.positions(firstBorrowPool, 90e18), evaluator);

        assertEq(borsToRepay[0].amount, 90e18);
    }

    function test_liquidate_RevertsWhenCollateralIsRequestedTwice() public {
        ILendingCore.LoanPosition[] memory reqCols =
            LoanHelpers.positions(flatBonusCollateralPool, 11e18, flatBonusCollateralPool, 11e18);

        vm.expectRevert(TargetHealthLiquidationEngine.DuplicateRequestedCollateral.selector);
        engine.liquidate(_loan(), RAMP_START_HEALTH, reqCols, LoanHelpers.positions(firstBorrowPool, 20e18), evaluator);
    }

    function test_liquidate_RevertsWhenBorrowIsRequestedTwice() public {
        ILendingCore.LoanPosition[] memory reqBors =
            LoanHelpers.positions(firstBorrowPool, 10e18, firstBorrowPool, 10e18);

        vm.expectRevert(TargetHealthLiquidationEngine.DuplicateRequestedBorrow.selector);
        engine.liquidate(
            _loan(), RAMP_START_HEALTH, LoanHelpers.positions(flatBonusCollateralPool, 11e18), reqBors, evaluator
        );
    }

    function test_liquidate_RevertsWhenCollateralIsNotInLoanAndAmountIsOne() public {
        vm.expectRevert(
            abi.encodeWithSelector(TargetHealthLiquidationEngine.InsufficientCollateral.selector, unlistedPool, 1, 0)
        );
        engine.liquidate(
            _loan(),
            RAMP_START_HEALTH,
            LoanHelpers.positions(unlistedPool, 1),
            LoanHelpers.positions(firstBorrowPool, 20e18),
            evaluator
        );
    }

    function test_liquidate_RevertsWhenCollateralIsNotInLoanAndAmountIsOneBelowMax() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                TargetHealthLiquidationEngine.InsufficientCollateral.selector, unlistedPool, type(uint256).max - 1, 0
            )
        );
        engine.liquidate(
            _loan(),
            RAMP_START_HEALTH,
            LoanHelpers.positions(unlistedPool, type(uint256).max - 1),
            LoanHelpers.positions(firstBorrowPool, 20e18),
            evaluator
        );
    }

    function test_liquidate_RevertsWhenCollateralExceedsLoanPosition() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                TargetHealthLiquidationEngine.InsufficientCollateral.selector,
                flatBonusCollateralPool,
                FLAT_COLLATERAL + 1,
                FLAT_COLLATERAL
            )
        );
        engine.liquidate(
            _loan(),
            RAMP_START_HEALTH,
            LoanHelpers.positions(flatBonusCollateralPool, FLAT_COLLATERAL + 1),
            LoanHelpers.positions(firstBorrowPool, 60e18),
            evaluator
        );
    }

    function test_liquidate_RevertsWhenNothingIsRepaid() public {
        vm.expectRevert(TargetHealthLiquidationEngine.NoRepayment.selector);
        engine.liquidate(
            _loan(),
            RAMP_START_HEALTH,
            LoanHelpers.positions(flatBonusCollateralPool, 11e18),
            LoanHelpers.positions(firstBorrowPool, 0),
            evaluator
        );
    }

    function test_liquidate_RevertsWhenRepaymentIsInsufficient() public {
        // At the ramp's start the second collateral pays no bonus, so 22e18 of it costs 22e18, not 20e18.
        vm.expectRevert(
            abi.encodeWithSelector(TargetHealthLiquidationEngine.InsufficientRepayment.selector, 20e18, 22e18)
        );
        engine.liquidate(
            _loan(),
            RAMP_START_HEALTH,
            LoanHelpers.positions(rampedBonusCollateralPool, 22e18),
            LoanHelpers.positions(firstBorrowPool, 20e18),
            evaluator
        );
    }

    function test_liquidate_RevertsWhenRepaymentIsInsufficientAcrossCollaterals() public {
        // At the ramp's end the collaterals pay 10% and 20%, so 22e18 and 24e18 together cost 20e18 + 20e18.
        ILendingCore.LoanPosition[] memory reqCols =
            LoanHelpers.positions(flatBonusCollateralPool, 22e18, rampedBonusCollateralPool, 24e18);

        vm.expectRevert(
            abi.encodeWithSelector(TargetHealthLiquidationEngine.InsufficientRepayment.selector, 39e18, 40e18)
        );
        engine.liquidate(_loan(), RAMP_END_HEALTH, reqCols, LoanHelpers.positions(firstBorrowPool, 39e18), evaluator);
    }

    function test_liquidate_RevertsWhenCollateralIsUnconfigured() public {
        ILendingCore.Loan memory loan = _singlePositionLoan(FLAT_COLLATERAL, 100e18);
        loan.collaterals = LoanHelpers.positions(unlistedPool, 10e18);

        vm.expectRevert(abi.encodeWithSelector(TargetHealthLiquidationEngine.PoolUnknown.selector, unlistedPool));
        engine.liquidate(
            loan,
            RAMP_START_HEALTH,
            LoanHelpers.positions(unlistedPool, 10e18),
            LoanHelpers.positions(firstBorrowPool, 20e18),
            evaluator
        );
    }

    function test_liquidate_RevertsWhenCloseOutIsAboveCloseOutThreshold() public {
        // The loan owes one unit more than the threshold, so repaying all of it is rejected.
        ILendingCore.Loan memory loan = _singlePositionLoan(200e18, CLOSE_OUT_THRESHOLD + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                TargetHealthLiquidationEngine.CloseOutTooLarge.selector, CLOSE_OUT_THRESHOLD + 1, CLOSE_OUT_THRESHOLD
            )
        );
        engine.liquidate(
            loan,
            RAMP_START_HEALTH,
            LoanHelpers.positions(flatBonusCollateralPool, 110e18),
            LoanHelpers.positions(firstBorrowPool, CLOSE_OUT_THRESHOLD + 1),
            evaluator
        );
    }

    function test_liquidate_RevertsWhenTargetHealthIsExceeded() public {
        evaluator.setHealth(TARGET_HEALTH_FACTOR + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                TargetHealthLiquidationEngine.TargetHealthExceeded.selector,
                TARGET_HEALTH_FACTOR + 1,
                TARGET_HEALTH_FACTOR
            )
        );
        engine.liquidate(
            _loan(),
            RAMP_START_HEALTH,
            LoanHelpers.positions(flatBonusCollateralPool, 22e18),
            LoanHelpers.positions(firstBorrowPool, 20e18),
            evaluator
        );
    }

    function test_liquidate_RevertsWhenLeavingDustOnBorrows() public {
        // Repaying 31e18 leaves 49e18 of debt, one unit of threshold short.
        _setMinLeftoverValue(MIN_LEFTOVER_VALUE);

        vm.expectRevert(abi.encodeWithSelector(TargetHealthLiquidationEngine.MustNotLeaveDust.selector, 142e18, 49e18));
        engine.liquidate(
            _loan(),
            RAMP_START_HEALTH,
            LoanHelpers.positions(flatBonusCollateralPool, 33e18),
            LoanHelpers.positions(firstBorrowPool, 31e18),
            evaluator
        );
    }

    function test_liquidate_RevertsWhenLeavingDustOnCollateral() public {
        // Seizing 22e18 of the only collateral leaves 33e18, below the threshold, against 80e18 of debt.
        _setMinLeftoverValue(MIN_LEFTOVER_VALUE);
        ILendingCore.Loan memory loan = _singlePositionLoan(FLAT_COLLATERAL, 100e18);

        vm.expectRevert(abi.encodeWithSelector(TargetHealthLiquidationEngine.MustNotLeaveDust.selector, 33e18, 80e18));
        engine.liquidate(
            loan,
            RAMP_START_HEALTH,
            LoanHelpers.positions(flatBonusCollateralPool, 22e18),
            LoanHelpers.positions(firstBorrowPool, 20e18),
            evaluator
        );
    }

    function test_liquidate_RevertsWhenLeavingDustOnCollateralAndMaxNamesPoolNotInLoan() public {
        // Naming the ramped pool, which the loan does not hold, leaves the 33e18 on the only collateral intact, so the
        // dust rule still applies.
        _setMinLeftoverValue(MIN_LEFTOVER_VALUE);
        ILendingCore.Loan memory loan = _singlePositionLoan(FLAT_COLLATERAL, 100e18);
        ILendingCore.LoanPosition[] memory reqCols =
            LoanHelpers.positions(flatBonusCollateralPool, 22e18, rampedBonusCollateralPool, type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(TargetHealthLiquidationEngine.MustNotLeaveDust.selector, 33e18, 80e18));
        engine.liquidate(loan, RAMP_START_HEALTH, reqCols, LoanHelpers.positions(firstBorrowPool, 20e18), evaluator);
    }

    // getCollateralBonus()

    function test_getCollateralBonus_RevertsWhenPoolIsUnknown() public {
        vm.expectRevert(abi.encodeWithSelector(TargetHealthLiquidationEngine.PoolUnknown.selector, firstBorrowPool));
        engine.getCollateralBonus(firstBorrowPool);
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(engine.contractName(), "TargetHealthLiquidationEngine");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(engine.contractVersion(), "1.0.0");
    }

    // supportsInterface()

    function test_supportsInterface_ReturnsTrueForILiquidationEngine() public view {
        assertTrue(engine.supportsInterface(type(ILiquidationEngine).interfaceId));
    }

    function test_supportsInterface_ReturnsTrueForIVersioned() public view {
        assertTrue(engine.supportsInterface(type(IVersioned).interfaceId));
    }

    function test_supportsInterface_ReturnsTrueForIERC165() public view {
        assertTrue(engine.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_ReturnsTrueForIAccessControl() public view {
        assertTrue(engine.supportsInterface(type(IAccessControl).interfaceId));
    }

    function test_supportsInterface_ReturnsTrueForIAccessControlEnumerable() public view {
        assertTrue(engine.supportsInterface(type(IAccessControlEnumerable).interfaceId));
    }

    function test_supportsInterface_ReturnsFalseForUnknown() public view {
        assertFalse(engine.supportsInterface(bytes4(0xdeadbeef)));
    }

    // isPoolAdded()

    function test_isPoolAdded_ReturnsFalseForUnconfiguredPool() public view {
        assertFalse(engine.isPoolAdded(firstBorrowPool));
    }

    // Helpers

    function _newEngine() internal returns (TargetHealthLiquidationEngine) {
        return TargetHealthLiquidationEngine(Clones.clone(address(implementation)));
    }

    function _setMinLeftoverValue(uint256 minLeftoverValue) internal {
        vm.prank(liquidationConfigurator);
        engine.updateMinLeftoverValue(minLeftoverValue);
    }

    /// @dev The loan every liquidation test starts from: 55e18 and 120e18 of collateral against 60e18 and 20e18
    ///      of debt, all priced one for one.
    function _loan() internal view returns (ILendingCore.Loan memory loan) {
        loan.account = violator;
        loan.collaterals = LoanHelpers.positions(
            flatBonusCollateralPool, FLAT_COLLATERAL, rampedBonusCollateralPool, RAMPED_COLLATERAL
        );
        loan.borrows = LoanHelpers.positions(firstBorrowPool, FIRST_BORROW, secondBorrowPool, SECOND_BORROW);
    }

    /// @dev A loan with one collateral and one borrow, for tests that need to seize all of a loan's collateral or
    ///      leave a sliver of it behind. The default loan holds more collateral than its debt could ever pay for,
    ///      so its collateral side can never be run down.
    function _singlePositionLoan(uint256 collateral, uint256 borrow)
        internal
        view
        returns (ILendingCore.Loan memory loan)
    {
        loan.account = violator;
        loan.collaterals = LoanHelpers.positions(flatBonusCollateralPool, collateral);
        loan.borrows = LoanHelpers.positions(firstBorrowPool, borrow);
    }

    function _bonusConfigs()
        internal
        view
        returns (TargetHealthLiquidationEngine.CollateralBonusConfig[] memory configs)
    {
        configs = new TargetHealthLiquidationEngine.CollateralBonusConfig[](2);
        configs[0] = TargetHealthLiquidationEngine.CollateralBonusConfig({
            pool: flatBonusCollateralPool, minBonus: FLAT_MIN_BONUS, maxBonus: FLAT_MAX_BONUS
        });
        configs[1] = TargetHealthLiquidationEngine.CollateralBonusConfig({
            pool: rampedBonusCollateralPool, minBonus: RAMPED_MIN_BONUS, maxBonus: RAMPED_MAX_BONUS
        });
    }
}
