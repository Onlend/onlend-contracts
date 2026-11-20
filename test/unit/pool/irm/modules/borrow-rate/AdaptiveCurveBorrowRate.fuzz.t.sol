// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

import {IRMConstants} from "src/pool/irm/libraries/IRMConstants.sol";
import {AdaptiveCurveBorrowRate} from "src/pool/irm/modules/borrow-rate/AdaptiveCurveBorrowRate.sol";

contract AdaptiveCurveBorrowRateFuzzTest is Test {
    uint256 internal constant MAX_ELAPSED = 10 * 365 days;

    address internal borrowRateCaller;
    AdaptiveCurveBorrowRate internal module;

    function setUp() public {
        borrowRateCaller = makeAddr("borrowRateCaller");

        module = AdaptiveCurveBorrowRate(Clones.clone(address(new AdaptiveCurveBorrowRate())));
        module.initialize(borrowRateCaller);
    }

    // borrowRate()

    function testFuzz_borrowRate_KeepsTargetRateAtOptimalUtilisation(
        AdaptiveCurveBorrowRate.Params memory params,
        uint256 elapsed
    ) public {
        params = _boundParams(params);
        elapsed = bound(elapsed, 0, MAX_ELAPSED);
        (uint256 idle, uint256 debt) = _liquidity(params.optimalUtilisation);
        _borrowRate(params, idle, debt);
        vm.warp(block.timestamp + elapsed);

        _borrowRate(params, idle, debt);

        assertEq(module.lastUpdate().targetRate, params.initialTargetRate);
    }

    function testFuzz_borrowRate_RaisesTargetRateAboveOptimalUtilisation(
        AdaptiveCurveBorrowRate.Params memory params,
        uint256 firstUtilisation,
        uint256 elapsed,
        uint256 idle,
        uint256 debt
    ) public {
        params = _boundParams(params);
        firstUtilisation = bound(firstUtilisation, params.optimalUtilisation + 1, 1e18);
        elapsed = bound(elapsed, 0, MAX_ELAPSED);
        (idle, debt) = _boundLiquidity(idle, debt, 0);
        (uint256 firstIdle, uint256 firstDebt) = _liquidity(firstUtilisation);
        _borrowRate(params, firstIdle, firstDebt);
        vm.warp(block.timestamp + elapsed);

        _borrowRate(params, idle, debt);

        assertGe(module.lastUpdate().targetRate, params.initialTargetRate);
    }

    function testFuzz_borrowRate_LowersTargetRateBelowOptimalUtilisation(
        AdaptiveCurveBorrowRate.Params memory params,
        uint256 firstUtilisation,
        uint256 elapsed,
        uint256 idle,
        uint256 debt
    ) public {
        params = _boundParams(params);
        // An optimum of at least 2 leaves a utilisation strictly below it with debt to record.
        params.optimalUtilisation = bound(params.optimalUtilisation, 2, 1e18 - 1);
        firstUtilisation = bound(firstUtilisation, 1, params.optimalUtilisation - 1);
        elapsed = bound(elapsed, 0, MAX_ELAPSED);
        (idle, debt) = _boundLiquidity(idle, debt, 0);
        (uint256 firstIdle, uint256 firstDebt) = _liquidity(firstUtilisation);
        _borrowRate(params, firstIdle, firstDebt);
        vm.warp(block.timestamp + elapsed);

        _borrowRate(params, idle, debt);

        assertLe(module.lastUpdate().targetRate, params.initialTargetRate);
    }

    function testFuzz_borrowRate_KeepsTargetRateWithinBounds(
        AdaptiveCurveBorrowRate.Params memory params,
        uint256 firstIdle,
        uint256 firstDebt,
        uint256 elapsed,
        uint256 idle,
        uint256 debt
    ) public {
        params = _boundParams(params);
        (firstIdle, firstDebt) = _boundLiquidity(firstIdle, firstDebt, 1);
        elapsed = bound(elapsed, 0, MAX_ELAPSED);
        (idle, debt) = _boundLiquidity(idle, debt, 0);
        _borrowRate(params, firstIdle, firstDebt);
        vm.warp(block.timestamp + elapsed);

        _borrowRate(params, idle, debt);

        uint256 targetRate = module.lastUpdate().targetRate;
        assertGe(targetRate, params.targetRateMin);
        assertLe(targetRate, params.targetRateMax);
    }

    function testFuzz_borrowRate_IsAtMostMaxBorrowRate(
        AdaptiveCurveBorrowRate.Params memory params,
        uint256 firstIdle,
        uint256 firstDebt,
        uint256 elapsed,
        uint256 idle,
        uint256 debt
    ) public {
        params = _boundParams(params);
        (firstIdle, firstDebt) = _boundLiquidity(firstIdle, firstDebt, 1);
        elapsed = bound(elapsed, 0, MAX_ELAPSED);
        (idle, debt) = _boundLiquidity(idle, debt, 0);
        _borrowRate(params, firstIdle, firstDebt);
        vm.warp(block.timestamp + elapsed);

        uint256 rate = _borrowRate(params, idle, debt);

        assertLe(rate, IRMConstants.MAX_BORROW_RATE);
    }

    // previewBorrowRate()

    function testFuzz_previewBorrowRate_EqualsBorrowRate(
        AdaptiveCurveBorrowRate.Params memory params,
        uint256 firstIdle,
        uint256 firstDebt,
        uint256 elapsed,
        uint256 idle,
        uint256 debt
    ) public {
        params = _boundParams(params);
        (firstIdle, firstDebt) = _boundLiquidity(firstIdle, firstDebt, 1);
        elapsed = bound(elapsed, 0, MAX_ELAPSED);
        (idle, debt) = _boundLiquidity(idle, debt, 0);
        _borrowRate(params, firstIdle, firstDebt);
        vm.warp(block.timestamp + elapsed);

        uint256 previewedRate = module.previewBorrowRate(abi.encode(params), idle, debt, 0);
        uint256 rate = _borrowRate(params, idle, debt);

        assertEq(previewedRate, rate);
    }

    function testFuzz_previewBorrowRate_IsUnchangedWhenLiquidityIsScaled(
        AdaptiveCurveBorrowRate.Params memory params,
        uint256 firstIdle,
        uint256 firstDebt,
        uint256 elapsed,
        uint256 idle,
        uint256 debt,
        uint256 scale
    ) public {
        params = _boundParams(params);
        (firstIdle, firstDebt) = _boundLiquidity(firstIdle, firstDebt, 1);
        elapsed = bound(elapsed, 0, MAX_ELAPSED);
        idle = bound(idle, 0, type(uint128).max);
        debt = bound(debt, 0, type(uint128).max);
        scale = bound(scale, 2, type(uint64).max);
        _borrowRate(params, firstIdle, firstDebt);
        vm.warp(block.timestamp + elapsed);
        bytes memory encodedParams = abi.encode(params);

        uint256 rate = module.previewBorrowRate(encodedParams, idle, debt, 0);
        uint256 scaledRate = module.previewBorrowRate(encodedParams, idle * scale, debt * scale, 0);

        assertEq(scaledRate, rate);
    }

    function testFuzz_previewBorrowRate_IgnoresTotalIrmDebt(
        AdaptiveCurveBorrowRate.Params memory params,
        uint256 firstIdle,
        uint256 firstDebt,
        uint256 elapsed,
        uint256 idle,
        uint256 debt,
        uint256 totalIrmDebt,
        uint256 otherTotalIrmDebt
    ) public {
        params = _boundParams(params);
        (firstIdle, firstDebt) = _boundLiquidity(firstIdle, firstDebt, 1);
        elapsed = bound(elapsed, 0, MAX_ELAPSED);
        (idle, debt) = _boundLiquidity(idle, debt, 0);
        _borrowRate(params, firstIdle, firstDebt);
        vm.warp(block.timestamp + elapsed);
        bytes memory encodedParams = abi.encode(params);

        uint256 rate = module.previewBorrowRate(encodedParams, idle, debt, totalIrmDebt);
        uint256 otherRate = module.previewBorrowRate(encodedParams, idle, debt, otherTotalIrmDebt);

        assertEq(otherRate, rate);
    }

    function testFuzz_previewBorrowRate_IsNonDecreasingInUtilisation(
        AdaptiveCurveBorrowRate.Params memory params,
        uint256 firstIdle,
        uint256 firstDebt,
        uint256 elapsed,
        uint256 lowerUtilisation,
        uint256 higherUtilisation
    ) public {
        params = _boundParams(params);
        (firstIdle, firstDebt) = _boundLiquidity(firstIdle, firstDebt, 1);
        elapsed = bound(elapsed, 0, MAX_ELAPSED);
        lowerUtilisation = bound(lowerUtilisation, 0, 1e18);
        higherUtilisation = bound(higherUtilisation, lowerUtilisation, 1e18);
        _borrowRate(params, firstIdle, firstDebt);
        vm.warp(block.timestamp + elapsed);
        bytes memory encodedParams = abi.encode(params);
        (uint256 lowerIdle, uint256 lowerDebt) = _liquidity(lowerUtilisation);
        (uint256 higherIdle, uint256 higherDebt) = _liquidity(higherUtilisation);

        uint256 lowerRate = module.previewBorrowRate(encodedParams, lowerIdle, lowerDebt, 0);
        uint256 higherRate = module.previewBorrowRate(encodedParams, higherIdle, higherDebt, 0);

        assertLe(lowerRate, higherRate);
    }

    // isValid()

    function testFuzz_isValid_ReturnsTrueForParamsWithinBounds(AdaptiveCurveBorrowRate.Params memory params)
        public
        view
    {
        params = _boundParams(params);

        assertTrue(module.isValid(abi.encode(params)));
    }

    function testFuzz_isValid_ReturnsFalseWhenParamsLengthIsBelow192(uint256 paramsLength) public view {
        paramsLength = bound(paramsLength, 0, 191);

        assertFalse(module.isValid(new bytes(paramsLength)));
    }

    function testFuzz_isValid_ReturnsFalseWhenParamsLengthIsAbove192(uint256 paramsLength) public view {
        paramsLength = bound(paramsLength, 193, 1024);

        assertFalse(module.isValid(new bytes(paramsLength)));
    }

    function testFuzz_isValid_ReturnsFalseWhenOptimalUtilisationIsAtLeastOne(
        AdaptiveCurveBorrowRate.Params memory params
    ) public view {
        params = _boundParams(params);
        params.optimalUtilisation = bound(params.optimalUtilisation, 1e18, type(uint256).max);

        assertFalse(module.isValid(abi.encode(params)));
    }

    function testFuzz_isValid_ReturnsFalseWhenTargetRateMinIsBelowLowest(AdaptiveCurveBorrowRate.Params memory params)
        public
        view
    {
        params = _boundParams(params);
        params.targetRateMin = bound(params.targetRateMin, 0, module.MIN_TARGET_RATE() - 1);

        assertFalse(module.isValid(abi.encode(params)));
    }

    function testFuzz_isValid_ReturnsFalseWhenTargetRateMinExceedsInitialTargetRate(
        AdaptiveCurveBorrowRate.Params memory params
    ) public view {
        params = _boundParams(params);
        params.targetRateMin = bound(params.targetRateMin, params.initialTargetRate + 1, type(uint256).max);

        assertFalse(module.isValid(abi.encode(params)));
    }

    function testFuzz_isValid_ReturnsFalseWhenInitialTargetRateExceedsTargetRateMax(
        AdaptiveCurveBorrowRate.Params memory params
    ) public view {
        params = _boundParams(params);
        params.initialTargetRate = bound(params.initialTargetRate, params.targetRateMax + 1, type(uint256).max);

        assertFalse(module.isValid(abi.encode(params)));
    }

    function testFuzz_isValid_ReturnsFalseWhenCurveMultiplierIsBelowLowest(AdaptiveCurveBorrowRate.Params memory params)
        public
        view
    {
        params = _boundParams(params);
        params.curveMultiplier = bound(params.curveMultiplier, 0, module.MIN_CURVE_MULTIPLIER() - 1);

        assertFalse(module.isValid(abi.encode(params)));
    }

    function testFuzz_isValid_ReturnsFalseWhenCurveMultiplierIsAboveHighest(
        AdaptiveCurveBorrowRate.Params memory params
    ) public view {
        params = _boundParams(params);
        params.curveMultiplier = bound(params.curveMultiplier, module.MAX_CURVE_MULTIPLIER() + 1, type(uint256).max);

        assertFalse(module.isValid(abi.encode(params)));
    }

    function testFuzz_isValid_ReturnsFalseWhenAdjustmentSpeedIsBelowLowest(AdaptiveCurveBorrowRate.Params memory params)
        public
        view
    {
        params = _boundParams(params);
        params.adjustmentSpeed = bound(params.adjustmentSpeed, 0, module.MIN_ADJUSTMENT_SPEED() - 1);

        assertFalse(module.isValid(abi.encode(params)));
    }

    function testFuzz_isValid_ReturnsFalseWhenAdjustmentSpeedIsAboveHighest(
        AdaptiveCurveBorrowRate.Params memory params
    ) public view {
        params = _boundParams(params);
        params.adjustmentSpeed = bound(params.adjustmentSpeed, module.MAX_ADJUSTMENT_SPEED() + 1, type(uint256).max);

        assertFalse(module.isValid(abi.encode(params)));
    }

    function testFuzz_isValid_ReturnsFalseWhenHighestBorrowRateExceedsMaximum(
        AdaptiveCurveBorrowRate.Params memory params
    ) public view {
        params = _boundParams(params);
        // The lower bound rounds the first invalid rate up, as `mulDiv` rounds the highest borrow rate down, and the
        // upper bound stops the highest borrow rate overflowing.
        params.targetRateMax = bound(
            params.targetRateMax,
            (IRMConstants.MAX_BORROW_RATE + 1) * 1e18 / params.curveMultiplier + 1,
            type(uint256).max / params.curveMultiplier
        );

        assertFalse(module.isValid(abi.encode(params)));
    }

    function _borrowRate(AdaptiveCurveBorrowRate.Params memory params, uint256 idle, uint256 debt)
        internal
        returns (uint256)
    {
        vm.prank(borrowRateCaller);
        return module.borrowRate(abi.encode(params), idle, debt, 0);
    }

    /// @dev Splits a total liquidity of 1e18 into idle liquidity and debt at exactly `utilisation`.
    function _liquidity(uint256 utilisation) internal pure returns (uint256 idle, uint256 debt) {
        return (1e18 - utilisation, utilisation);
    }

    /// @dev Bounds idle liquidity and debt to any amounts whose total fits, with at least `minDebt` of debt.
    function _boundLiquidity(uint256 idle, uint256 debt, uint256 minDebt) internal pure returns (uint256, uint256) {
        debt = bound(debt, minDebt, type(uint256).max);
        return (bound(idle, 0, type(uint256).max - debt), debt);
    }

    function _boundParams(AdaptiveCurveBorrowRate.Params memory params)
        internal
        view
        returns (AdaptiveCurveBorrowRate.Params memory)
    {
        params.optimalUtilisation = bound(params.optimalUtilisation, 1, 1e18 - 1);
        params.curveMultiplier =
            bound(params.curveMultiplier, module.MIN_CURVE_MULTIPLIER(), module.MAX_CURVE_MULTIPLIER());
        params.targetRateMax = bound(
            params.targetRateMax, module.MIN_TARGET_RATE(), IRMConstants.MAX_BORROW_RATE * 1e18 / params.curveMultiplier
        );
        params.targetRateMin = bound(params.targetRateMin, module.MIN_TARGET_RATE(), params.targetRateMax);
        params.initialTargetRate = bound(params.initialTargetRate, params.targetRateMin, params.targetRateMax);
        params.adjustmentSpeed =
            bound(params.adjustmentSpeed, module.MIN_ADJUSTMENT_SPEED(), module.MAX_ADJUSTMENT_SPEED());
        return params;
    }
}
