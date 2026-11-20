// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IAccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Test} from "forge-std/Test.sol";

import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IIRM} from "src/pool/irm/interfaces/IIRM.sol";
import {ComposedIRM} from "src/pool/irm/ComposedIRM.sol";
import {IRMConstants} from "src/pool/irm/libraries/IRMConstants.sol";
import {YieldTrackingBorrowRate} from "src/pool/irm/libraries/borrow-rate/YieldTrackingBorrowRate.sol";
import {MockBalanceOf} from "./libraries/mocks/MockBalanceOf.sol";
import {MockBorrowRateModule} from "./libraries/mocks/MockBorrowRateModule.sol";
import {MockConditionModule} from "./libraries/mocks/MockConditionModule.sol";
import {MockRetentionRateModule} from "./libraries/mocks/MockRetentionRateModule.sol";
import {MockYieldAdapter} from "./libraries/mocks/MockYieldAdapter.sol";

contract ComposedIRMUnitTest is Test {
    // FIXED borrow rate
    uint256 internal constant FIXED_BORROW_RATE = 0.05e18;
    uint256 internal constant UPDATED_BORROW_RATE = 0.07e18;

    // LINEAR borrow rate
    uint256 internal constant LINEAR_BASE_RATE = 0.02e18;
    uint256 internal constant LINEAR_SLOPE = 0.2e18;

    // PIECEWISE_LINEAR borrow rate
    uint256 internal constant PIECEWISE_LINEAR_BASE_RATE = 0.02e18;
    uint256 internal constant PIECEWISE_LINEAR_OPTIMAL_UTILISATION = 0.8e18;
    uint256 internal constant PIECEWISE_LINEAR_SLOPE1 = 0.04e18;
    uint256 internal constant PIECEWISE_LINEAR_SLOPE2 = 0.6e18;

    // DOUBLE_PIECEWISE_LINEAR borrow rate
    uint256 internal constant DOUBLE_PIECEWISE_LINEAR_BASE_RATE = 0.01e18;
    uint256 internal constant DOUBLE_PIECEWISE_LINEAR_UTILISATION1 = 0.5e18;
    uint256 internal constant DOUBLE_PIECEWISE_LINEAR_UTILISATION2 = 0.8e18;
    uint256 internal constant DOUBLE_PIECEWISE_LINEAR_SLOPE1 = 0.04e18;
    uint256 internal constant DOUBLE_PIECEWISE_LINEAR_SLOPE2 = 0.1e18;
    uint256 internal constant DOUBLE_PIECEWISE_LINEAR_SLOPE3 = 1e18;

    // POWER borrow rate
    uint256 internal constant POWER_BASE_RATE = 0.1e18;
    uint256 internal constant POWER_SLOPE = 0.6e18;
    uint256 internal constant POWER_EXPONENT = 3;

    // YIELD_TRACKING borrow rate
    int256 internal constant TRACKED_APR = 0.06e18;
    int256 internal constant YIELD_TRACKING_SPREAD = 0.01e18;
    uint256 internal constant YIELD_TRACKING_OPTIMAL_UTILISATION = 0.8e18;
    uint256 internal constant YIELD_TRACKING_SLOPE = 0.5e18;

    // FIXED retention rate
    uint256 internal constant RETENTION_RATE = 0.1e18;
    uint256 internal constant UPDATED_RETENTION_RATE = 0.15e18;

    // TOKEN_BALANCE condition
    uint256 internal constant MINIMUM_TOKEN_BALANCE = 100;

    address internal borrowRateCaller;
    address internal defaultAdmin;
    address internal borrowRateUpdater;
    address internal retentionRateUpdater;
    address internal conditionUpdater;
    ComposedIRM internal implementation;
    ComposedIRM internal irm;

    function setUp() public {
        borrowRateCaller = makeAddr("borrowRateCaller");
        defaultAdmin = makeAddr("defaultAdmin");
        borrowRateUpdater = makeAddr("borrowRateUpdater");
        retentionRateUpdater = makeAddr("retentionRateUpdater");
        conditionUpdater = makeAddr("conditionUpdater");
        implementation = new ComposedIRM();

        irm = _deployFixedComposedIrm(
            _fixedBorrowRateParams(FIXED_BORROW_RATE),
            _fixedRetentionRateParams(RETENTION_RATE),
            _alwaysApplicableParams(),
            defaultAdmin,
            borrowRateUpdater,
            retentionRateUpdater,
            conditionUpdater
        );
    }

    // Module types

    function test_BorrowRateType_HasSevenTypes() public pure {
        assertEq(uint256(type(ComposedIRM.BorrowRateType).max), 6);
    }

    function test_RetentionRateType_HasTwoTypes() public pure {
        assertEq(uint256(type(ComposedIRM.RetentionRateType).max), 1);
    }

    function test_ConditionType_HasThreeTypes() public pure {
        assertEq(uint256(type(ComposedIRM.ConditionType).max), 2);
    }

    // initialize()

    function test_initialize_SetsBorrowRateCaller() public view {
        assertEq(irm.borrowRateCaller(), borrowRateCaller);
    }

    function test_initialize_SetsFixedBorrowRateFixedRetentionRateAndAlwaysApplicableCondition() public view {
        (ComposedIRM.BorrowRateType borrowRateType, bytes memory borrowRateParams) = irm.borrowRateConfig();
        (ComposedIRM.RetentionRateType retentionRateType, bytes memory retentionRateParams) = irm.retentionRateConfig();
        (ComposedIRM.ConditionType conditionType, bytes memory conditionParams) = irm.conditionConfig();

        assertEq(uint256(borrowRateType), uint256(ComposedIRM.BorrowRateType.FIXED));
        assertEq(uint256(retentionRateType), uint256(ComposedIRM.RetentionRateType.FIXED));
        assertEq(uint256(conditionType), uint256(ComposedIRM.ConditionType.ALWAYS_APPLICABLE));
        assertEq(borrowRateParams, _fixedBorrowRateParams(FIXED_BORROW_RATE));
        assertEq(retentionRateParams, _fixedRetentionRateParams(RETENTION_RATE));
        assertEq(conditionParams, _alwaysApplicableParams());
    }

    function test_initialize_SetsTokenBalanceCondition() public {
        MockBalanceOf token = new MockBalanceOf();
        bytes memory conditionParams = _tokenBalanceParams(address(token), MINIMUM_TOKEN_BALANCE);
        ComposedIRM instance = _clone();

        instance.initialize(
            borrowRateCaller,
            ComposedIRM.BorrowRateType.FIXED,
            _fixedBorrowRateParams(FIXED_BORROW_RATE),
            ComposedIRM.RetentionRateType.FIXED,
            _fixedRetentionRateParams(RETENTION_RATE),
            ComposedIRM.ConditionType.TOKEN_BALANCE,
            conditionParams,
            defaultAdmin,
            borrowRateUpdater,
            retentionRateUpdater,
            conditionUpdater
        );

        (ComposedIRM.ConditionType conditionType, bytes memory storedConditionParams) = instance.conditionConfig();
        assertEq(uint256(conditionType), uint256(ComposedIRM.ConditionType.TOKEN_BALANCE));
        assertEq(storedConditionParams, conditionParams);
    }

    function test_initialize_SetsExternalBorrowRateTypeAndParams() public {
        MockBorrowRateModule module = new MockBorrowRateModule();
        bytes memory params = _externalBorrowRateParams(address(module), abi.encode(uint256(7)));

        ComposedIRM externalIrm = _deployExternalComposedIrm(params);

        (ComposedIRM.BorrowRateType borrowRateType, bytes memory borrowRateParams) = externalIrm.borrowRateConfig();
        assertEq(uint256(borrowRateType), uint256(ComposedIRM.BorrowRateType.EXTERNAL));
        assertEq(borrowRateParams, params);
    }

    function test_initialize_SetsPowerBorrowRateTypeAndParams() public {
        bytes memory params = _powerBorrowRateParams(POWER_BASE_RATE, POWER_SLOPE, POWER_EXPONENT);

        ComposedIRM powerIrm = _deployPowerComposedIrm(params);

        (ComposedIRM.BorrowRateType borrowRateType, bytes memory borrowRateParams) = powerIrm.borrowRateConfig();
        assertEq(uint256(borrowRateType), uint256(ComposedIRM.BorrowRateType.POWER));
        assertEq(borrowRateParams, params);
    }

    function test_initialize_EmitsUpdatedEventsFromDefaultState() public {
        bytes memory borrowRateParams = _powerBorrowRateParams(POWER_BASE_RATE, POWER_SLOPE, POWER_EXPONENT);
        bytes memory retentionRateParams = _fixedRetentionRateParams(RETENTION_RATE);
        ComposedIRM instance = _clone();

        vm.expectEmit();
        emit ComposedIRM.BorrowRateUpdated(
            ComposedIRM.BorrowRateType.FIXED, "", ComposedIRM.BorrowRateType.POWER, borrowRateParams
        );
        vm.expectEmit();
        emit ComposedIRM.RetentionRateUpdated(
            ComposedIRM.RetentionRateType.FIXED, "", ComposedIRM.RetentionRateType.FIXED, retentionRateParams
        );
        vm.expectEmit();
        emit ComposedIRM.ConditionUpdated(
            ComposedIRM.ConditionType.ALWAYS_APPLICABLE, "", ComposedIRM.ConditionType.ALWAYS_APPLICABLE, ""
        );

        instance.initialize(
            borrowRateCaller,
            ComposedIRM.BorrowRateType.POWER,
            borrowRateParams,
            ComposedIRM.RetentionRateType.FIXED,
            retentionRateParams,
            ComposedIRM.ConditionType.ALWAYS_APPLICABLE,
            _alwaysApplicableParams(),
            defaultAdmin,
            borrowRateUpdater,
            retentionRateUpdater,
            conditionUpdater
        );
    }

    function test_initialize_GrantsDefaultAdminAndUpdaterRoles() public view {
        assertTrue(irm.hasRole(irm.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertTrue(irm.hasRole(irm.BORROW_RATE_UPDATER_ROLE(), borrowRateUpdater));
        assertTrue(irm.hasRole(irm.RETENTION_RATE_UPDATER_ROLE(), retentionRateUpdater));
        assertTrue(irm.hasRole(irm.CONDITION_UPDATER_ROLE(), conditionUpdater));
    }

    function test_initialize_UsesDefaultAdminAsRoleAdmin() public view {
        assertEq(irm.getRoleAdmin(irm.BORROW_RATE_UPDATER_ROLE()), irm.DEFAULT_ADMIN_ROLE());
        assertEq(irm.getRoleAdmin(irm.RETENTION_RATE_UPDATER_ROLE()), irm.DEFAULT_ADMIN_ROLE());
        assertEq(irm.getRoleAdmin(irm.CONDITION_UPDATER_ROLE()), irm.DEFAULT_ADMIN_ROLE());
    }

    function test_initialize_AllowsZeroAddressAdmins() public {
        ComposedIRM rolelessIrm = _deployFixedComposedIrm(
            _fixedBorrowRateParams(FIXED_BORROW_RATE),
            _fixedRetentionRateParams(RETENTION_RATE),
            _alwaysApplicableParams(),
            address(0),
            address(0),
            address(0),
            address(0)
        );

        assertEq(rolelessIrm.getRoleMemberCount(rolelessIrm.DEFAULT_ADMIN_ROLE()), 0);
        assertEq(rolelessIrm.getRoleMemberCount(rolelessIrm.BORROW_RATE_UPDATER_ROLE()), 0);
        assertEq(rolelessIrm.getRoleMemberCount(rolelessIrm.RETENTION_RATE_UPDATER_ROLE()), 0);
        assertEq(rolelessIrm.getRoleMemberCount(rolelessIrm.CONDITION_UPDATER_ROLE()), 0);
    }

    function test_initialize_AllowsMaxBorrowRate() public {
        ComposedIRM maxBorrowRateIrm = _deployFixedComposedIrm(
            _fixedBorrowRateParams(IRMConstants.MAX_BORROW_RATE),
            _fixedRetentionRateParams(RETENTION_RATE),
            _alwaysApplicableParams(),
            defaultAdmin,
            borrowRateUpdater,
            retentionRateUpdater,
            conditionUpdater
        );

        (, bytes memory borrowRateParams) = maxBorrowRateIrm.borrowRateConfig();
        assertEq(borrowRateParams, _fixedBorrowRateParams(IRMConstants.MAX_BORROW_RATE));
        assertEq(maxBorrowRateIrm.previewBorrowRate(0, 0, 0), IRMConstants.MAX_BORROW_RATE);
    }

    function test_initialize_RevertsWhenFixedBorrowRateParamsAreInvalid() public {
        bytes memory invalidParams = _fixedBorrowRateParams(IRMConstants.MAX_BORROW_RATE + 1);
        ComposedIRM instance = _clone();

        vm.expectRevert(
            abi.encodeWithSelector(
                ComposedIRM.InvalidBorrowRateParams.selector, ComposedIRM.BorrowRateType.FIXED, invalidParams
            )
        );
        instance.initialize(
            borrowRateCaller,
            ComposedIRM.BorrowRateType.FIXED,
            invalidParams,
            ComposedIRM.RetentionRateType.FIXED,
            _fixedRetentionRateParams(RETENTION_RATE),
            ComposedIRM.ConditionType.ALWAYS_APPLICABLE,
            _alwaysApplicableParams(),
            defaultAdmin,
            borrowRateUpdater,
            retentionRateUpdater,
            conditionUpdater
        );
    }

    function test_initialize_RevertsWhenExternalBorrowRateParamsAreInvalid() public {
        MockBorrowRateModule module = new MockBorrowRateModule();
        module.setValid(false);
        bytes memory invalidParams = _externalBorrowRateParams(address(module), abi.encode(uint256(7)));
        ComposedIRM instance = _clone();

        vm.expectRevert(
            abi.encodeWithSelector(
                ComposedIRM.InvalidBorrowRateParams.selector, ComposedIRM.BorrowRateType.EXTERNAL, invalidParams
            )
        );
        instance.initialize(
            borrowRateCaller,
            ComposedIRM.BorrowRateType.EXTERNAL,
            invalidParams,
            ComposedIRM.RetentionRateType.FIXED,
            _fixedRetentionRateParams(RETENTION_RATE),
            ComposedIRM.ConditionType.ALWAYS_APPLICABLE,
            _alwaysApplicableParams(),
            defaultAdmin,
            borrowRateUpdater,
            retentionRateUpdater,
            conditionUpdater
        );
    }

    function test_initialize_RevertsWhenPowerBorrowRateParamsAreInvalid() public {
        bytes memory invalidParams = _powerBorrowRateParams(POWER_BASE_RATE, POWER_SLOPE, 1);
        ComposedIRM instance = _clone();

        vm.expectRevert(
            abi.encodeWithSelector(
                ComposedIRM.InvalidBorrowRateParams.selector, ComposedIRM.BorrowRateType.POWER, invalidParams
            )
        );
        instance.initialize(
            borrowRateCaller,
            ComposedIRM.BorrowRateType.POWER,
            invalidParams,
            ComposedIRM.RetentionRateType.FIXED,
            _fixedRetentionRateParams(RETENTION_RATE),
            ComposedIRM.ConditionType.ALWAYS_APPLICABLE,
            _alwaysApplicableParams(),
            defaultAdmin,
            borrowRateUpdater,
            retentionRateUpdater,
            conditionUpdater
        );
    }

    function test_initialize_AllowsMaxRetentionRate() public {
        ComposedIRM maxRetentionRateIrm = _deployFixedComposedIrm(
            _fixedBorrowRateParams(FIXED_BORROW_RATE),
            _fixedRetentionRateParams(IRMConstants.MAX_RETENTION_RATE),
            _alwaysApplicableParams(),
            defaultAdmin,
            borrowRateUpdater,
            retentionRateUpdater,
            conditionUpdater
        );

        (, bytes memory retentionRateParams) = maxRetentionRateIrm.retentionRateConfig();
        assertEq(retentionRateParams, _fixedRetentionRateParams(IRMConstants.MAX_RETENTION_RATE));
        assertEq(maxRetentionRateIrm.retentionRate(0, 0, 0), IRMConstants.MAX_RETENTION_RATE);
    }

    function test_initialize_RevertsWhenFixedRetentionRateParamsAreInvalid() public {
        bytes memory invalidParams = _fixedRetentionRateParams(IRMConstants.MAX_RETENTION_RATE + 1);
        ComposedIRM instance = _clone();

        vm.expectRevert(
            abi.encodeWithSelector(
                ComposedIRM.InvalidRetentionRateParams.selector, ComposedIRM.RetentionRateType.FIXED, invalidParams
            )
        );
        instance.initialize(
            borrowRateCaller,
            ComposedIRM.BorrowRateType.FIXED,
            _fixedBorrowRateParams(FIXED_BORROW_RATE),
            ComposedIRM.RetentionRateType.FIXED,
            invalidParams,
            ComposedIRM.ConditionType.ALWAYS_APPLICABLE,
            _alwaysApplicableParams(),
            defaultAdmin,
            borrowRateUpdater,
            retentionRateUpdater,
            conditionUpdater
        );
    }

    function test_initialize_RevertsWhenAlwaysApplicableConditionParamsAreInvalid() public {
        bytes memory invalidParams = abi.encode(uint256(1));
        ComposedIRM instance = _clone();

        vm.expectRevert(
            abi.encodeWithSelector(
                ComposedIRM.InvalidConditionParams.selector, ComposedIRM.ConditionType.ALWAYS_APPLICABLE, invalidParams
            )
        );
        instance.initialize(
            borrowRateCaller,
            ComposedIRM.BorrowRateType.FIXED,
            _fixedBorrowRateParams(FIXED_BORROW_RATE),
            ComposedIRM.RetentionRateType.FIXED,
            _fixedRetentionRateParams(RETENTION_RATE),
            ComposedIRM.ConditionType.ALWAYS_APPLICABLE,
            invalidParams,
            defaultAdmin,
            borrowRateUpdater,
            retentionRateUpdater,
            conditionUpdater
        );
    }

    function test_initialize_RevertsWhenTokenBalanceConditionParamsAreInvalid() public {
        MockBalanceOf token = new MockBalanceOf();
        bytes memory invalidParams = _tokenBalanceParams(address(token), 0);
        ComposedIRM instance = _clone();

        vm.expectRevert(
            abi.encodeWithSelector(
                ComposedIRM.InvalidConditionParams.selector, ComposedIRM.ConditionType.TOKEN_BALANCE, invalidParams
            )
        );
        instance.initialize(
            borrowRateCaller,
            ComposedIRM.BorrowRateType.FIXED,
            _fixedBorrowRateParams(FIXED_BORROW_RATE),
            ComposedIRM.RetentionRateType.FIXED,
            _fixedRetentionRateParams(RETENTION_RATE),
            ComposedIRM.ConditionType.TOKEN_BALANCE,
            invalidParams,
            defaultAdmin,
            borrowRateUpdater,
            retentionRateUpdater,
            conditionUpdater
        );
    }

    // setBorrowRate()

    function test_setBorrowRate_UpdatesFixedBorrowRate() public {
        bytes memory oldParams = _fixedBorrowRateParams(FIXED_BORROW_RATE);
        bytes memory newParams = _fixedBorrowRateParams(UPDATED_BORROW_RATE);

        vm.expectEmit();
        emit ComposedIRM.BorrowRateUpdated(
            ComposedIRM.BorrowRateType.FIXED, oldParams, ComposedIRM.BorrowRateType.FIXED, newParams
        );

        vm.prank(borrowRateUpdater);
        irm.setBorrowRate(ComposedIRM.BorrowRateType.FIXED, newParams);

        (ComposedIRM.BorrowRateType borrowRateType, bytes memory borrowRateParams) = irm.borrowRateConfig();
        assertEq(uint256(borrowRateType), uint256(ComposedIRM.BorrowRateType.FIXED));
        assertEq(borrowRateParams, newParams);
        assertEq(irm.previewBorrowRate(0, 0, 0), UPDATED_BORROW_RATE);
    }

    function test_setBorrowRate_AllowsMaxBorrowRate() public {
        bytes memory maxParams = _fixedBorrowRateParams(IRMConstants.MAX_BORROW_RATE);

        vm.prank(borrowRateUpdater);
        irm.setBorrowRate(ComposedIRM.BorrowRateType.FIXED, maxParams);

        (, bytes memory borrowRateParams) = irm.borrowRateConfig();
        assertEq(borrowRateParams, maxParams);
        assertEq(irm.previewBorrowRate(0, 0, 0), IRMConstants.MAX_BORROW_RATE);
    }

    function test_setBorrowRate_RevertsWhenFixedBorrowRateParamsAreInvalid() public {
        bytes memory invalidParams = _fixedBorrowRateParams(IRMConstants.MAX_BORROW_RATE + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ComposedIRM.InvalidBorrowRateParams.selector, ComposedIRM.BorrowRateType.FIXED, invalidParams
            )
        );
        vm.prank(borrowRateUpdater);
        irm.setBorrowRate(ComposedIRM.BorrowRateType.FIXED, invalidParams);
    }

    function test_setBorrowRate_UpdatesToLinearBorrowRate() public {
        bytes memory oldParams = _fixedBorrowRateParams(FIXED_BORROW_RATE);
        bytes memory newParams = _linearBorrowRateParams(LINEAR_BASE_RATE, LINEAR_SLOPE);

        vm.expectEmit();
        emit ComposedIRM.BorrowRateUpdated(
            ComposedIRM.BorrowRateType.FIXED, oldParams, ComposedIRM.BorrowRateType.LINEAR, newParams
        );

        vm.prank(borrowRateUpdater);
        irm.setBorrowRate(ComposedIRM.BorrowRateType.LINEAR, newParams);

        (ComposedIRM.BorrowRateType borrowRateType, bytes memory borrowRateParams) = irm.borrowRateConfig();
        assertEq(uint256(borrowRateType), uint256(ComposedIRM.BorrowRateType.LINEAR));
        assertEq(borrowRateParams, newParams);
    }

    function test_setBorrowRate_RevertsWhenLinearBorrowRateParamsAreInvalid() public {
        bytes memory invalidParams = _linearBorrowRateParams(IRMConstants.MAX_BORROW_RATE, 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ComposedIRM.InvalidBorrowRateParams.selector, ComposedIRM.BorrowRateType.LINEAR, invalidParams
            )
        );
        vm.prank(borrowRateUpdater);
        irm.setBorrowRate(ComposedIRM.BorrowRateType.LINEAR, invalidParams);
    }

    function test_setBorrowRate_UpdatesToPiecewiseLinearBorrowRate() public {
        bytes memory oldParams = _fixedBorrowRateParams(FIXED_BORROW_RATE);
        bytes memory newParams = _piecewiseLinearBorrowRateParams(
            PIECEWISE_LINEAR_BASE_RATE,
            PIECEWISE_LINEAR_OPTIMAL_UTILISATION,
            PIECEWISE_LINEAR_SLOPE1,
            PIECEWISE_LINEAR_SLOPE2
        );

        vm.expectEmit();
        emit ComposedIRM.BorrowRateUpdated(
            ComposedIRM.BorrowRateType.FIXED, oldParams, ComposedIRM.BorrowRateType.PIECEWISE_LINEAR, newParams
        );

        vm.prank(borrowRateUpdater);
        irm.setBorrowRate(ComposedIRM.BorrowRateType.PIECEWISE_LINEAR, newParams);

        (ComposedIRM.BorrowRateType borrowRateType, bytes memory borrowRateParams) = irm.borrowRateConfig();
        assertEq(uint256(borrowRateType), uint256(ComposedIRM.BorrowRateType.PIECEWISE_LINEAR));
        assertEq(borrowRateParams, newParams);
    }

    function test_setBorrowRate_RevertsWhenPiecewiseLinearBorrowRateParamsAreInvalid() public {
        bytes memory invalidParams = _piecewiseLinearBorrowRateParams(
            PIECEWISE_LINEAR_BASE_RATE, 0, PIECEWISE_LINEAR_SLOPE1, PIECEWISE_LINEAR_SLOPE2
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ComposedIRM.InvalidBorrowRateParams.selector, ComposedIRM.BorrowRateType.PIECEWISE_LINEAR, invalidParams
            )
        );
        vm.prank(borrowRateUpdater);
        irm.setBorrowRate(ComposedIRM.BorrowRateType.PIECEWISE_LINEAR, invalidParams);
    }

    function test_setBorrowRate_UpdatesToDoublePiecewiseLinearBorrowRate() public {
        bytes memory oldParams = _fixedBorrowRateParams(FIXED_BORROW_RATE);
        bytes memory newParams = _doublePiecewiseLinearBorrowRateParams(
            DOUBLE_PIECEWISE_LINEAR_BASE_RATE,
            DOUBLE_PIECEWISE_LINEAR_UTILISATION1,
            DOUBLE_PIECEWISE_LINEAR_UTILISATION2,
            DOUBLE_PIECEWISE_LINEAR_SLOPE1,
            DOUBLE_PIECEWISE_LINEAR_SLOPE2,
            DOUBLE_PIECEWISE_LINEAR_SLOPE3
        );

        vm.expectEmit();
        emit ComposedIRM.BorrowRateUpdated(
            ComposedIRM.BorrowRateType.FIXED, oldParams, ComposedIRM.BorrowRateType.DOUBLE_PIECEWISE_LINEAR, newParams
        );

        vm.prank(borrowRateUpdater);
        irm.setBorrowRate(ComposedIRM.BorrowRateType.DOUBLE_PIECEWISE_LINEAR, newParams);

        (ComposedIRM.BorrowRateType borrowRateType, bytes memory borrowRateParams) = irm.borrowRateConfig();
        assertEq(uint256(borrowRateType), uint256(ComposedIRM.BorrowRateType.DOUBLE_PIECEWISE_LINEAR));
        assertEq(borrowRateParams, newParams);
    }

    function test_setBorrowRate_RevertsWhenDoublePiecewiseLinearBorrowRateParamsAreInvalid() public {
        // The utilisation points are swapped, so the first is not below the second.
        bytes memory invalidParams = _doublePiecewiseLinearBorrowRateParams(
            DOUBLE_PIECEWISE_LINEAR_BASE_RATE,
            DOUBLE_PIECEWISE_LINEAR_UTILISATION2,
            DOUBLE_PIECEWISE_LINEAR_UTILISATION1,
            DOUBLE_PIECEWISE_LINEAR_SLOPE1,
            DOUBLE_PIECEWISE_LINEAR_SLOPE2,
            DOUBLE_PIECEWISE_LINEAR_SLOPE3
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ComposedIRM.InvalidBorrowRateParams.selector,
                ComposedIRM.BorrowRateType.DOUBLE_PIECEWISE_LINEAR,
                invalidParams
            )
        );
        vm.prank(borrowRateUpdater);
        irm.setBorrowRate(ComposedIRM.BorrowRateType.DOUBLE_PIECEWISE_LINEAR, invalidParams);
    }

    function test_setBorrowRate_UpdatesToPowerBorrowRate() public {
        bytes memory oldParams = _fixedBorrowRateParams(FIXED_BORROW_RATE);
        bytes memory newParams = _powerBorrowRateParams(POWER_BASE_RATE, POWER_SLOPE, POWER_EXPONENT);

        vm.expectEmit();
        emit ComposedIRM.BorrowRateUpdated(
            ComposedIRM.BorrowRateType.FIXED, oldParams, ComposedIRM.BorrowRateType.POWER, newParams
        );

        vm.prank(borrowRateUpdater);
        irm.setBorrowRate(ComposedIRM.BorrowRateType.POWER, newParams);

        (ComposedIRM.BorrowRateType borrowRateType, bytes memory borrowRateParams) = irm.borrowRateConfig();
        assertEq(uint256(borrowRateType), uint256(ComposedIRM.BorrowRateType.POWER));
        assertEq(borrowRateParams, newParams);
    }

    function test_setBorrowRate_RevertsWhenPowerBorrowRateParamsAreInvalid() public {
        bytes memory invalidParams = _powerBorrowRateParams(POWER_BASE_RATE, POWER_SLOPE, 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ComposedIRM.InvalidBorrowRateParams.selector, ComposedIRM.BorrowRateType.POWER, invalidParams
            )
        );
        vm.prank(borrowRateUpdater);
        irm.setBorrowRate(ComposedIRM.BorrowRateType.POWER, invalidParams);
    }

    function test_setBorrowRate_UpdatesToYieldTrackingBorrowRate() public {
        bytes memory oldParams = _fixedBorrowRateParams(FIXED_BORROW_RATE);
        bytes memory newParams = _yieldTrackingBorrowRateParams(new MockYieldAdapter());

        vm.expectEmit();
        emit ComposedIRM.BorrowRateUpdated(
            ComposedIRM.BorrowRateType.FIXED, oldParams, ComposedIRM.BorrowRateType.YIELD_TRACKING, newParams
        );

        vm.prank(borrowRateUpdater);
        irm.setBorrowRate(ComposedIRM.BorrowRateType.YIELD_TRACKING, newParams);

        (ComposedIRM.BorrowRateType borrowRateType, bytes memory borrowRateParams) = irm.borrowRateConfig();
        assertEq(uint256(borrowRateType), uint256(ComposedIRM.BorrowRateType.YIELD_TRACKING));
        assertEq(borrowRateParams, newParams);
    }

    function test_setBorrowRate_RevertsWhenYieldTrackingBorrowRateParamsAreInvalid() public {
        MockYieldAdapter adapter = new MockYieldAdapter();
        adapter.setValidWindow(false);
        bytes memory invalidParams = _yieldTrackingBorrowRateParams(adapter);

        vm.expectRevert(
            abi.encodeWithSelector(
                ComposedIRM.InvalidBorrowRateParams.selector, ComposedIRM.BorrowRateType.YIELD_TRACKING, invalidParams
            )
        );
        vm.prank(borrowRateUpdater);
        irm.setBorrowRate(ComposedIRM.BorrowRateType.YIELD_TRACKING, invalidParams);
    }

    function test_setBorrowRate_AllowsChangingExternalBorrowRateModule() public {
        MockBorrowRateModule oldModule = new MockBorrowRateModule();
        MockBorrowRateModule newModule = new MockBorrowRateModule();
        bytes memory oldParams = _externalBorrowRateParams(address(oldModule), abi.encode(uint256(7)));
        bytes memory newParams = _externalBorrowRateParams(address(newModule), abi.encode(uint256(8)));
        ComposedIRM externalIrm = _deployExternalComposedIrm(oldParams);

        vm.expectEmit();
        emit ComposedIRM.BorrowRateUpdated(
            ComposedIRM.BorrowRateType.EXTERNAL, oldParams, ComposedIRM.BorrowRateType.EXTERNAL, newParams
        );

        vm.prank(borrowRateUpdater);
        externalIrm.setBorrowRate(ComposedIRM.BorrowRateType.EXTERNAL, newParams);

        (ComposedIRM.BorrowRateType borrowRateType, bytes memory borrowRateParams) = externalIrm.borrowRateConfig();
        assertEq(uint256(borrowRateType), uint256(ComposedIRM.BorrowRateType.EXTERNAL));
        assertEq(borrowRateParams, newParams);
    }

    function test_setBorrowRate_RevertsWhenExternalBorrowRateParamsAreInvalid() public {
        MockBorrowRateModule module = new MockBorrowRateModule();
        module.setValid(false);
        bytes memory invalidParams = _externalBorrowRateParams(address(module), abi.encode(uint256(7)));

        vm.expectRevert(
            abi.encodeWithSelector(
                ComposedIRM.InvalidBorrowRateParams.selector, ComposedIRM.BorrowRateType.EXTERNAL, invalidParams
            )
        );
        vm.prank(borrowRateUpdater);
        irm.setBorrowRate(ComposedIRM.BorrowRateType.EXTERNAL, invalidParams);
    }

    function test_setBorrowRate_RevertsWhenCallerDoesNotHaveRole() public {
        address caller = makeAddr("caller");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, irm.BORROW_RATE_UPDATER_ROLE()
            )
        );
        vm.prank(caller);
        irm.setBorrowRate(ComposedIRM.BorrowRateType.FIXED, _fixedBorrowRateParams(UPDATED_BORROW_RATE));
    }

    // setRetentionRate()

    function test_setRetentionRate_UpdatesFixedRetentionRate() public {
        bytes memory oldParams = _fixedRetentionRateParams(RETENTION_RATE);
        bytes memory newParams = _fixedRetentionRateParams(UPDATED_RETENTION_RATE);

        vm.expectEmit();
        emit ComposedIRM.RetentionRateUpdated(
            ComposedIRM.RetentionRateType.FIXED, oldParams, ComposedIRM.RetentionRateType.FIXED, newParams
        );

        vm.prank(retentionRateUpdater);
        irm.setRetentionRate(ComposedIRM.RetentionRateType.FIXED, newParams);

        (ComposedIRM.RetentionRateType retentionRateType, bytes memory retentionRateParams) = irm.retentionRateConfig();
        assertEq(uint256(retentionRateType), uint256(ComposedIRM.RetentionRateType.FIXED));
        assertEq(retentionRateParams, newParams);
        assertEq(irm.retentionRate(0, 0, 0), UPDATED_RETENTION_RATE);
    }

    function test_setRetentionRate_AllowsMaxRetentionRate() public {
        bytes memory maxParams = _fixedRetentionRateParams(IRMConstants.MAX_RETENTION_RATE);

        vm.prank(retentionRateUpdater);
        irm.setRetentionRate(ComposedIRM.RetentionRateType.FIXED, maxParams);

        (, bytes memory retentionRateParams) = irm.retentionRateConfig();
        assertEq(retentionRateParams, maxParams);
        assertEq(irm.retentionRate(0, 0, 0), IRMConstants.MAX_RETENTION_RATE);
    }

    function test_setRetentionRate_RevertsWhenFixedRetentionRateParamsAreInvalid() public {
        bytes memory invalidParams = _fixedRetentionRateParams(IRMConstants.MAX_RETENTION_RATE + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ComposedIRM.InvalidRetentionRateParams.selector, ComposedIRM.RetentionRateType.FIXED, invalidParams
            )
        );
        vm.prank(retentionRateUpdater);
        irm.setRetentionRate(ComposedIRM.RetentionRateType.FIXED, invalidParams);
    }

    function test_setRetentionRate_UpdatesToExternalRetentionRate() public {
        MockRetentionRateModule module = new MockRetentionRateModule();
        bytes memory oldParams = _fixedRetentionRateParams(RETENTION_RATE);
        bytes memory newParams = _externalRetentionRateParams(address(module), abi.encode(uint256(7)));

        vm.expectEmit();
        emit ComposedIRM.RetentionRateUpdated(
            ComposedIRM.RetentionRateType.FIXED, oldParams, ComposedIRM.RetentionRateType.EXTERNAL, newParams
        );

        vm.prank(retentionRateUpdater);
        irm.setRetentionRate(ComposedIRM.RetentionRateType.EXTERNAL, newParams);

        (ComposedIRM.RetentionRateType retentionRateType, bytes memory retentionRateParams) = irm.retentionRateConfig();
        assertEq(uint256(retentionRateType), uint256(ComposedIRM.RetentionRateType.EXTERNAL));
        assertEq(retentionRateParams, newParams);
    }

    function test_setRetentionRate_RevertsWhenExternalRetentionRateParamsAreInvalid() public {
        MockRetentionRateModule module = new MockRetentionRateModule();
        module.setValid(false);
        bytes memory invalidParams = _externalRetentionRateParams(address(module), abi.encode(uint256(7)));

        vm.expectRevert(
            abi.encodeWithSelector(
                ComposedIRM.InvalidRetentionRateParams.selector, ComposedIRM.RetentionRateType.EXTERNAL, invalidParams
            )
        );
        vm.prank(retentionRateUpdater);
        irm.setRetentionRate(ComposedIRM.RetentionRateType.EXTERNAL, invalidParams);
    }

    function test_setRetentionRate_RevertsWhenCallerDoesNotHaveRole() public {
        address caller = makeAddr("caller");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, irm.RETENTION_RATE_UPDATER_ROLE()
            )
        );
        vm.prank(caller);
        irm.setRetentionRate(ComposedIRM.RetentionRateType.FIXED, _fixedRetentionRateParams(UPDATED_RETENTION_RATE));
    }

    // setCondition()

    function test_setCondition_UpdatesToTokenBalanceCondition() public {
        MockBalanceOf token = new MockBalanceOf();
        bytes memory newParams = _tokenBalanceParams(address(token), MINIMUM_TOKEN_BALANCE);

        vm.expectEmit();
        emit ComposedIRM.ConditionUpdated(
            ComposedIRM.ConditionType.ALWAYS_APPLICABLE,
            _alwaysApplicableParams(),
            ComposedIRM.ConditionType.TOKEN_BALANCE,
            newParams
        );

        vm.prank(conditionUpdater);
        irm.setCondition(ComposedIRM.ConditionType.TOKEN_BALANCE, newParams);

        (ComposedIRM.ConditionType conditionType, bytes memory conditionParams) = irm.conditionConfig();
        assertEq(uint256(conditionType), uint256(ComposedIRM.ConditionType.TOKEN_BALANCE));
        assertEq(conditionParams, newParams);
    }

    function test_setCondition_UpdatesToAlwaysApplicableCondition() public {
        MockBalanceOf token = new MockBalanceOf();
        bytes memory oldParams = _tokenBalanceParams(address(token), MINIMUM_TOKEN_BALANCE);
        vm.prank(conditionUpdater);
        irm.setCondition(ComposedIRM.ConditionType.TOKEN_BALANCE, oldParams);

        vm.expectEmit();
        emit ComposedIRM.ConditionUpdated(
            ComposedIRM.ConditionType.TOKEN_BALANCE,
            oldParams,
            ComposedIRM.ConditionType.ALWAYS_APPLICABLE,
            _alwaysApplicableParams()
        );

        vm.prank(conditionUpdater);
        irm.setCondition(ComposedIRM.ConditionType.ALWAYS_APPLICABLE, _alwaysApplicableParams());

        (ComposedIRM.ConditionType conditionType, bytes memory conditionParams) = irm.conditionConfig();
        assertEq(uint256(conditionType), uint256(ComposedIRM.ConditionType.ALWAYS_APPLICABLE));
        assertEq(conditionParams, _alwaysApplicableParams());
    }

    function test_setCondition_UpdatesToExternalCondition() public {
        MockConditionModule module = new MockConditionModule();
        bytes memory newParams = _externalConditionParams(address(module), abi.encode(uint256(7)));

        vm.expectEmit();
        emit ComposedIRM.ConditionUpdated(
            ComposedIRM.ConditionType.ALWAYS_APPLICABLE,
            _alwaysApplicableParams(),
            ComposedIRM.ConditionType.EXTERNAL,
            newParams
        );

        vm.prank(conditionUpdater);
        irm.setCondition(ComposedIRM.ConditionType.EXTERNAL, newParams);

        (ComposedIRM.ConditionType conditionType, bytes memory conditionParams) = irm.conditionConfig();
        assertEq(uint256(conditionType), uint256(ComposedIRM.ConditionType.EXTERNAL));
        assertEq(conditionParams, newParams);
    }

    function test_setCondition_RevertsWhenAlwaysApplicableConditionParamsAreInvalid() public {
        bytes memory invalidParams = abi.encode(uint256(1));

        vm.expectRevert(
            abi.encodeWithSelector(
                ComposedIRM.InvalidConditionParams.selector, ComposedIRM.ConditionType.ALWAYS_APPLICABLE, invalidParams
            )
        );
        vm.prank(conditionUpdater);
        irm.setCondition(ComposedIRM.ConditionType.ALWAYS_APPLICABLE, invalidParams);
    }

    function test_setCondition_RevertsWhenTokenBalanceConditionParamsAreInvalid() public {
        MockBalanceOf token = new MockBalanceOf();
        bytes memory invalidParams = _tokenBalanceParams(address(token), 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                ComposedIRM.InvalidConditionParams.selector, ComposedIRM.ConditionType.TOKEN_BALANCE, invalidParams
            )
        );
        vm.prank(conditionUpdater);
        irm.setCondition(ComposedIRM.ConditionType.TOKEN_BALANCE, invalidParams);
    }

    function test_setCondition_RevertsWhenExternalConditionParamsAreInvalid() public {
        MockConditionModule module = new MockConditionModule();
        module.setValid(false);
        bytes memory invalidParams = _externalConditionParams(address(module), abi.encode(uint256(7)));

        vm.expectRevert(
            abi.encodeWithSelector(
                ComposedIRM.InvalidConditionParams.selector, ComposedIRM.ConditionType.EXTERNAL, invalidParams
            )
        );
        vm.prank(conditionUpdater);
        irm.setCondition(ComposedIRM.ConditionType.EXTERNAL, invalidParams);
    }

    function test_setCondition_RevertsWhenCallerDoesNotHaveRole() public {
        address caller = makeAddr("caller");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, irm.CONDITION_UPDATER_ROLE()
            )
        );
        vm.prank(caller);
        irm.setCondition(ComposedIRM.ConditionType.ALWAYS_APPLICABLE, _alwaysApplicableParams());
    }

    // borrowRate()

    function test_borrowRate_DelegatesToFixedBorrowRate() public {
        vm.prank(borrowRateCaller);
        uint256 actualBorrowRate = irm.borrowRate(100e18, 50e18, 25e18);

        assertEq(actualBorrowRate, FIXED_BORROW_RATE);
    }

    function test_borrowRate_DelegatesToLinearBorrowRate() public {
        vm.prank(borrowRateUpdater);
        irm.setBorrowRate(ComposedIRM.BorrowRateType.LINEAR, _linearBorrowRateParams(LINEAR_BASE_RATE, LINEAR_SLOPE));

        vm.prank(borrowRateCaller);
        uint256 actualBorrowRate = irm.borrowRate(10e18, 90e18, 0);

        // 90% utilisation adds 90% of the 20% slope to the 2% base rate.
        assertEq(actualBorrowRate, 0.2e18);
    }

    function test_borrowRate_DelegatesToPiecewiseLinearBorrowRate() public {
        vm.prank(borrowRateUpdater);
        irm.setBorrowRate(
            ComposedIRM.BorrowRateType.PIECEWISE_LINEAR,
            _piecewiseLinearBorrowRateParams(
                PIECEWISE_LINEAR_BASE_RATE,
                PIECEWISE_LINEAR_OPTIMAL_UTILISATION,
                PIECEWISE_LINEAR_SLOPE1,
                PIECEWISE_LINEAR_SLOPE2
            )
        );

        vm.prank(borrowRateCaller);
        uint256 actualBorrowRate = irm.borrowRate(10e18, 90e18, 0);

        // 90% utilisation is halfway from the 80% optimum to full, adding half of the 60% second slope to the 2% base
        // rate and the full 4% first slope.
        assertEq(actualBorrowRate, 0.36e18);
    }

    function test_borrowRate_DelegatesToDoublePiecewiseLinearBorrowRate() public {
        vm.prank(borrowRateUpdater);
        irm.setBorrowRate(
            ComposedIRM.BorrowRateType.DOUBLE_PIECEWISE_LINEAR,
            _doublePiecewiseLinearBorrowRateParams(
                DOUBLE_PIECEWISE_LINEAR_BASE_RATE,
                DOUBLE_PIECEWISE_LINEAR_UTILISATION1,
                DOUBLE_PIECEWISE_LINEAR_UTILISATION2,
                DOUBLE_PIECEWISE_LINEAR_SLOPE1,
                DOUBLE_PIECEWISE_LINEAR_SLOPE2,
                DOUBLE_PIECEWISE_LINEAR_SLOPE3
            )
        );

        vm.prank(borrowRateCaller);
        uint256 actualBorrowRate = irm.borrowRate(10e18, 90e18, 0);

        // 90% utilisation is halfway from the 80% second point to full, adding half of the 100% third slope to the 1%
        // base rate and the full 4% and 10% first and second slopes.
        assertEq(actualBorrowRate, 0.65e18);
    }

    function test_borrowRate_DelegatesToPowerBorrowRate() public {
        bytes memory params = _powerBorrowRateParams(POWER_BASE_RATE, POWER_SLOPE, POWER_EXPONENT);
        ComposedIRM powerIrm = _deployPowerComposedIrm(params);

        vm.prank(borrowRateCaller);
        uint256 actualBorrowRate = powerIrm.borrowRate(100e18, 100e18, 0);

        // 50% utilisation cubed is 12.5%, adding 12.5% of the 60% slope to the 10% base rate.
        assertEq(actualBorrowRate, 0.175e18);
    }

    function test_borrowRate_DelegatesToYieldTrackingBorrowRate() public {
        MockYieldAdapter adapter = new MockYieldAdapter();
        adapter.setApr(TRACKED_APR, block.timestamp);
        vm.prank(borrowRateUpdater);
        irm.setBorrowRate(ComposedIRM.BorrowRateType.YIELD_TRACKING, _yieldTrackingBorrowRateParams(adapter));

        vm.prank(borrowRateCaller);
        uint256 actualBorrowRate = irm.borrowRate(10e18, 90e18, 0);

        // 90% utilisation adds half of the 50% slope to the 6% tracked APR less the 1% spread.
        assertEq(actualBorrowRate, 0.3e18);
    }

    function test_borrowRate_DelegatesToExternalBorrowRateModule() public {
        MockBorrowRateModule module = new MockBorrowRateModule();
        uint256 moduleBorrowRate = 0.1e18;
        module.setBorrowRate(moduleBorrowRate);
        module.setPreviewBorrowRate(0.2e18);
        ComposedIRM externalIrm =
            _deployExternalComposedIrm(_externalBorrowRateParams(address(module), abi.encode(uint256(7))));

        vm.prank(borrowRateCaller);
        uint256 actualBorrowRate = externalIrm.borrowRate(100e18, 50e18, 25e18);

        assertEq(actualBorrowRate, moduleBorrowRate);
    }

    function test_borrowRate_RevertsWhenCallerIsNotBorrowRateCaller() public {
        address caller = makeAddr("caller");

        vm.expectRevert(ComposedIRM.NotBorrowRateCaller.selector);
        vm.prank(caller);
        irm.borrowRate(100e18, 50e18, 25e18);
    }

    // previewBorrowRate()

    function test_previewBorrowRate_DelegatesToFixedBorrowRateForAnyCaller() public {
        address caller = makeAddr("caller");

        vm.prank(caller);
        uint256 previewedBorrowRate = irm.previewBorrowRate(100e18, 50e18, 25e18);

        assertEq(previewedBorrowRate, FIXED_BORROW_RATE);
    }

    function test_previewBorrowRate_DelegatesToExternalBorrowRateModulePreview() public {
        MockBorrowRateModule module = new MockBorrowRateModule();
        uint256 modulePreviewBorrowRate = 0.2e18;
        module.setBorrowRate(0.1e18);
        module.setPreviewBorrowRate(modulePreviewBorrowRate);
        ComposedIRM externalIrm =
            _deployExternalComposedIrm(_externalBorrowRateParams(address(module), abi.encode(uint256(7))));

        uint256 previewedBorrowRate = externalIrm.previewBorrowRate(100e18, 50e18, 25e18);

        assertEq(previewedBorrowRate, modulePreviewBorrowRate);
    }

    // retentionRate()

    function test_retentionRate_DelegatesToFixedRetentionRate() public view {
        assertEq(irm.retentionRate(100e18, 50e18, 25e18), RETENTION_RATE);
    }

    function test_retentionRate_DelegatesToExternalRetentionRateModule() public {
        MockRetentionRateModule module = new MockRetentionRateModule();
        uint256 moduleRetentionRate = 0.3e18;
        module.setRetentionRate(moduleRetentionRate);
        vm.prank(retentionRateUpdater);
        irm.setRetentionRate(
            ComposedIRM.RetentionRateType.EXTERNAL,
            _externalRetentionRateParams(address(module), abi.encode(uint256(7)))
        );

        uint256 actualRetentionRate = irm.retentionRate(100e18, 50e18, 25e18);

        assertEq(actualRetentionRate, moduleRetentionRate);
    }

    // isApplicable()

    function test_isApplicable_DelegatesToAlwaysApplicableCondition() public view {
        assertTrue(irm.isApplicable(address(this)));
        assertTrue(irm.isApplicable(address(0)));
    }

    function test_isApplicable_ReturnsTrueWhenTokenBalanceIsAtLeastMinimum() public {
        MockBalanceOf token = new MockBalanceOf();
        address account = makeAddr("account");
        token.setBalance(account, MINIMUM_TOKEN_BALANCE);
        vm.prank(conditionUpdater);
        irm.setCondition(
            ComposedIRM.ConditionType.TOKEN_BALANCE, _tokenBalanceParams(address(token), MINIMUM_TOKEN_BALANCE)
        );

        bool applicable = irm.isApplicable(account);

        assertTrue(applicable);
    }

    function test_isApplicable_ReturnsFalseWhenTokenBalanceIsBelowMinimum() public {
        MockBalanceOf token = new MockBalanceOf();
        address account = makeAddr("account");
        token.setBalance(account, MINIMUM_TOKEN_BALANCE - 1);
        vm.prank(conditionUpdater);
        irm.setCondition(
            ComposedIRM.ConditionType.TOKEN_BALANCE, _tokenBalanceParams(address(token), MINIMUM_TOKEN_BALANCE)
        );

        bool applicable = irm.isApplicable(account);

        assertFalse(applicable);
    }

    function test_isApplicable_ReturnsTrueWhenExternalConditionModuleApplies() public {
        MockConditionModule module = new MockConditionModule();
        module.setApplicable(true);
        vm.prank(conditionUpdater);
        irm.setCondition(
            ComposedIRM.ConditionType.EXTERNAL, _externalConditionParams(address(module), abi.encode(uint256(7)))
        );

        bool applicable = irm.isApplicable(makeAddr("account"));

        assertTrue(applicable);
    }

    function test_isApplicable_ReturnsFalseWhenExternalConditionModuleDoesNotApply() public {
        MockConditionModule module = new MockConditionModule();
        module.setApplicable(false);
        vm.prank(conditionUpdater);
        irm.setCondition(
            ComposedIRM.ConditionType.EXTERNAL, _externalConditionParams(address(module), abi.encode(uint256(7)))
        );

        bool applicable = irm.isApplicable(makeAddr("account"));

        assertFalse(applicable);
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(irm.contractName(), "ComposedIRM");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(irm.contractVersion(), "1.0.0");
    }

    function test_iirm_ExposesContractMetadata() public view {
        IIRM versionedIrm = IIRM(address(irm));

        assertEq(versionedIrm.contractName(), "ComposedIRM");
        assertEq(versionedIrm.contractVersion(), "1.0.0");
    }

    // supportsInterface()

    function test_supportsInterface_ReturnsTrueForIIRM() public view {
        assertTrue(irm.supportsInterface(type(IIRM).interfaceId));
    }

    function test_supportsInterface_ReturnsTrueForIVersioned() public view {
        assertTrue(irm.supportsInterface(type(IVersioned).interfaceId));
    }

    function test_supportsInterface_ReturnsTrueForIERC165() public view {
        assertTrue(irm.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_ReturnsTrueForIAccessControl() public view {
        assertTrue(irm.supportsInterface(type(IAccessControl).interfaceId));
    }

    function test_supportsInterface_ReturnsTrueForIAccessControlEnumerable() public view {
        assertTrue(irm.supportsInterface(type(IAccessControlEnumerable).interfaceId));
    }

    function test_supportsInterface_ReturnsFalseForUnknownInterface() public view {
        assertFalse(irm.supportsInterface(0xffffffff));
        assertFalse(irm.supportsInterface(0xdeadbeef));
    }

    function _deployFixedComposedIrm(
        bytes memory borrowRateParams,
        bytes memory retentionRateParams,
        bytes memory conditionParams,
        address defaultAdmin_,
        address borrowRateUpdater_,
        address retentionRateUpdater_,
        address conditionUpdater_
    ) internal returns (ComposedIRM instance) {
        instance = _clone();
        instance.initialize(
            borrowRateCaller,
            ComposedIRM.BorrowRateType.FIXED,
            borrowRateParams,
            ComposedIRM.RetentionRateType.FIXED,
            retentionRateParams,
            ComposedIRM.ConditionType.ALWAYS_APPLICABLE,
            conditionParams,
            defaultAdmin_,
            borrowRateUpdater_,
            retentionRateUpdater_,
            conditionUpdater_
        );
    }

    function _deployExternalComposedIrm(bytes memory borrowRateParams) internal returns (ComposedIRM instance) {
        instance = _clone();
        instance.initialize(
            borrowRateCaller,
            ComposedIRM.BorrowRateType.EXTERNAL,
            borrowRateParams,
            ComposedIRM.RetentionRateType.FIXED,
            _fixedRetentionRateParams(RETENTION_RATE),
            ComposedIRM.ConditionType.ALWAYS_APPLICABLE,
            _alwaysApplicableParams(),
            defaultAdmin,
            borrowRateUpdater,
            retentionRateUpdater,
            conditionUpdater
        );
    }

    function _deployPowerComposedIrm(bytes memory borrowRateParams) internal returns (ComposedIRM instance) {
        instance = _clone();
        instance.initialize(
            borrowRateCaller,
            ComposedIRM.BorrowRateType.POWER,
            borrowRateParams,
            ComposedIRM.RetentionRateType.FIXED,
            _fixedRetentionRateParams(RETENTION_RATE),
            ComposedIRM.ConditionType.ALWAYS_APPLICABLE,
            _alwaysApplicableParams(),
            defaultAdmin,
            borrowRateUpdater,
            retentionRateUpdater,
            conditionUpdater
        );
    }

    function _clone() internal returns (ComposedIRM) {
        return ComposedIRM(Clones.clone(address(implementation)));
    }

    function _fixedBorrowRateParams(uint256 borrowRate_) internal pure returns (bytes memory) {
        return abi.encode(borrowRate_);
    }

    function _linearBorrowRateParams(uint256 baseRate, uint256 slope) internal pure returns (bytes memory) {
        return abi.encode(baseRate, slope);
    }

    function _piecewiseLinearBorrowRateParams(
        uint256 baseRate,
        uint256 optimalUtilisation,
        uint256 slope1,
        uint256 slope2
    ) internal pure returns (bytes memory) {
        return abi.encode(baseRate, optimalUtilisation, slope1, slope2);
    }

    function _doublePiecewiseLinearBorrowRateParams(
        uint256 baseRate,
        uint256 utilisation1,
        uint256 utilisation2,
        uint256 slope1,
        uint256 slope2,
        uint256 slope3
    ) internal pure returns (bytes memory) {
        return abi.encode(baseRate, utilisation1, utilisation2, slope1, slope2, slope3);
    }

    function _externalBorrowRateParams(address module, bytes memory externalModuleParams)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(module, externalModuleParams);
    }

    function _powerBorrowRateParams(uint256 baseRate, uint256 slope, uint256 exponent)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(baseRate, slope, exponent);
    }

    function _yieldTrackingBorrowRateParams(MockYieldAdapter adapter) internal pure returns (bytes memory) {
        return abi.encode(
            YieldTrackingBorrowRate.Params({
                adapter: adapter,
                window: 7 days,
                spread: YIELD_TRACKING_SPREAD,
                aprMin: 0,
                aprMax: 1e18,
                staleAfter: 0,
                fallbackTarget: 0,
                optimalUtilisation: YIELD_TRACKING_OPTIMAL_UTILISATION,
                slope: YIELD_TRACKING_SLOPE
            })
        );
    }

    function _fixedRetentionRateParams(uint256 retentionRate_) internal pure returns (bytes memory) {
        return abi.encode(retentionRate_);
    }

    function _externalRetentionRateParams(address module, bytes memory externalModuleParams)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(module, externalModuleParams);
    }

    function _alwaysApplicableParams() internal pure returns (bytes memory) {
        return "";
    }

    function _tokenBalanceParams(address token, uint256 minimumBalance) internal pure returns (bytes memory) {
        return abi.encode(token, minimumBalance);
    }

    function _externalConditionParams(address module, bytes memory externalModuleParams)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(module, externalModuleParams);
    }
}
