// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import {Test} from "forge-std/Test.sol";

import {MathUtils} from "src/lib/MathUtils.sol";
import {IRMConstants} from "src/pool/irm/libraries/IRMConstants.sol";
import {YieldTrackingBorrowRate} from "src/pool/irm/libraries/borrow-rate/YieldTrackingBorrowRate.sol";
import {MockYieldAdapter} from "../mocks/MockYieldAdapter.sol";

contract YieldTrackingBorrowRateFuzzTest is Test {
    MockYieldAdapter internal adapter;

    function setUp() public {
        vm.warp(1_000_000);
        adapter = new MockYieldAdapter();
    }

    // isValid()

    function testFuzz_isValid_ReturnsTrueForValidParams(YieldTrackingBorrowRate.Params memory params) public view {
        _boundValidParams(params);

        assertTrue(YieldTrackingBorrowRate.isValid(abi.encode(params)));
    }

    function testFuzz_isValid_ReturnsFalseWhenAprMinIsAboveAprMax(YieldTrackingBorrowRate.Params memory params)
        public
        view
    {
        _boundValidParams(params);
        params.aprMin = bound(params.aprMin, params.aprMax + 1, type(uint256).max);

        assertFalse(YieldTrackingBorrowRate.isValid(abi.encode(params)));
    }

    function testFuzz_isValid_ReturnsFalseWhenOptimalUtilisationIsAtLeastOne(
        YieldTrackingBorrowRate.Params memory params
    ) public view {
        _boundValidParams(params);
        params.optimalUtilisation = bound(params.optimalUtilisation, MathUtils.ONE_18_DP, type(uint256).max);

        assertFalse(YieldTrackingBorrowRate.isValid(abi.encode(params)));
    }

    function testFuzz_isValid_ReturnsFalseWhenMaxBorrowRateFromTrackedAprIsExceeded(
        YieldTrackingBorrowRate.Params memory params
    ) public view {
        _boundValidParams(params);
        params.spread = 0;
        params.fallbackTarget = bound(params.fallbackTarget, 0, params.aprMax);
        params.slope =
            bound(params.slope, IRMConstants.MAX_BORROW_RATE - params.aprMax + 1, type(uint256).max - params.aprMax);

        assertFalse(YieldTrackingBorrowRate.isValid(abi.encode(params)));
    }

    function testFuzz_isValid_ReturnsFalseWhenMaxBorrowRateFromFallbackTargetIsExceeded(
        YieldTrackingBorrowRate.Params memory params
    ) public view {
        _boundValidParams(params);
        params.spread = bound(params.spread, SafeCast.toInt256(params.aprMax), type(int256).max);
        params.slope = bound(
            params.slope,
            IRMConstants.MAX_BORROW_RATE - params.fallbackTarget + 1,
            type(uint256).max - params.fallbackTarget
        );

        assertFalse(YieldTrackingBorrowRate.isValid(abi.encode(params)));
    }

    function testFuzz_isValid_ReturnsFalseWhenParamsLengthIsBelow288(uint256 paramsLength) public view {
        paramsLength = bound(paramsLength, 0, 287);

        assertFalse(YieldTrackingBorrowRate.isValid(new bytes(paramsLength)));
    }

    function testFuzz_isValid_ReturnsFalseWhenParamsLengthIsAbove288(uint256 paramsLength) public view {
        paramsLength = bound(paramsLength, 289, 1024);

        assertFalse(YieldTrackingBorrowRate.isValid(new bytes(paramsLength)));
    }

    // borrowRate()

    function testFuzz_borrowRate_ReturnsTargetRateUpToOptimalUtilisation(
        YieldTrackingBorrowRate.Params memory params,
        int256 trackedApr,
        uint256 utilisation
    ) public {
        _boundValidParams(params);
        utilisation = bound(utilisation, 0, params.optimalUtilisation);
        adapter.setApr(trackedApr, block.timestamp);
        bytes memory encodedParams = abi.encode(params);

        uint256 targetRate = YieldTrackingBorrowRate.borrowRate(encodedParams, 0, 0, 0);
        uint256 rate = _borrowRateAtUtilisation(encodedParams, utilisation);

        assertEq(rate, targetRate);
    }

    function testFuzz_borrowRate_ReturnsTargetRatePlusSlopeAtFullUtilisation(
        YieldTrackingBorrowRate.Params memory params,
        int256 trackedApr,
        uint256 totalDebt
    ) public {
        _boundValidParams(params);
        totalDebt = bound(totalDebt, 1, type(uint256).max);
        adapter.setApr(trackedApr, block.timestamp);
        bytes memory encodedParams = abi.encode(params);

        uint256 targetRate = YieldTrackingBorrowRate.borrowRate(encodedParams, 0, 0, 0);
        uint256 rate = YieldTrackingBorrowRate.borrowRate(encodedParams, 0, totalDebt, 0);

        assertEq(rate, targetRate + params.slope);
    }

    function testFuzz_borrowRate_StaysWithinSlopeAboveOptimalUtilisation(
        YieldTrackingBorrowRate.Params memory params,
        int256 trackedApr,
        uint256 utilisation
    ) public {
        _boundValidParams(params);
        utilisation = bound(utilisation, params.optimalUtilisation + 1, MathUtils.ONE_18_DP);
        adapter.setApr(trackedApr, block.timestamp);
        bytes memory encodedParams = abi.encode(params);

        uint256 targetRate = YieldTrackingBorrowRate.borrowRate(encodedParams, 0, 0, 0);
        uint256 rate = _borrowRateAtUtilisation(encodedParams, utilisation);

        assertGe(rate, targetRate);
        assertLe(rate, targetRate + params.slope);
    }

    function testFuzz_borrowRate_NeverDecreasesAsUtilisationIncreases(
        YieldTrackingBorrowRate.Params memory params,
        int256 trackedApr,
        uint256 utilisation,
        uint256 higherUtilisation
    ) public {
        _boundValidParams(params);
        utilisation = bound(utilisation, 0, MathUtils.ONE_18_DP - 1);
        higherUtilisation = bound(higherUtilisation, utilisation + 1, MathUtils.ONE_18_DP);
        adapter.setApr(trackedApr, block.timestamp);
        bytes memory encodedParams = abi.encode(params);

        uint256 rate = _borrowRateAtUtilisation(encodedParams, utilisation);
        uint256 higherRate = _borrowRateAtUtilisation(encodedParams, higherUtilisation);

        assertGe(higherRate, rate);
    }

    function testFuzz_borrowRate_NeverExceedsMaxBorrowRateForValidParams(
        YieldTrackingBorrowRate.Params memory params,
        int256 trackedApr,
        uint256 updatedAt,
        uint256 totalLiquidity,
        uint256 totalDebt
    ) public {
        _boundValidParams(params);
        totalDebt = bound(totalDebt, 0, totalLiquidity);
        adapter.setApr(trackedApr, updatedAt);

        uint256 rate = YieldTrackingBorrowRate.borrowRate(abi.encode(params), totalLiquidity - totalDebt, totalDebt, 0);

        assertLe(rate, IRMConstants.MAX_BORROW_RATE);
    }

    function testFuzz_borrowRate_ReturnsTrackedAprWithinBoundsWhenSpreadIsZero(
        YieldTrackingBorrowRate.Params memory params,
        uint256 trackedApr
    ) public {
        _boundValidParams(params);
        params.spread = 0;
        trackedApr = bound(trackedApr, params.aprMin, params.aprMax);
        adapter.setApr(SafeCast.toInt256(trackedApr), block.timestamp);

        uint256 rate = YieldTrackingBorrowRate.borrowRate(abi.encode(params), 0, 0, 0);

        assertEq(rate, trackedApr);
    }

    function testFuzz_borrowRate_ReturnsSameRateForAnyTrackedAprBelowAprMin(
        YieldTrackingBorrowRate.Params memory params,
        int256 trackedApr
    ) public {
        _boundValidParams(params);
        trackedApr = bound(trackedApr, type(int256).min, SafeCast.toInt256(params.aprMin));
        bytes memory encodedParams = abi.encode(params);
        adapter.setApr(SafeCast.toInt256(params.aprMin), block.timestamp);
        uint256 rateAtAprMin = YieldTrackingBorrowRate.borrowRate(encodedParams, 0, 0, 0);
        adapter.setApr(trackedApr, block.timestamp);

        uint256 rate = YieldTrackingBorrowRate.borrowRate(encodedParams, 0, 0, 0);

        assertEq(rate, rateAtAprMin);
    }

    function testFuzz_borrowRate_ReturnsSameRateForAnyTrackedAprAboveAprMax(
        YieldTrackingBorrowRate.Params memory params,
        int256 trackedApr
    ) public {
        _boundValidParams(params);
        trackedApr = bound(trackedApr, SafeCast.toInt256(params.aprMax), type(int256).max);
        bytes memory encodedParams = abi.encode(params);
        adapter.setApr(SafeCast.toInt256(params.aprMax), block.timestamp);
        uint256 rateAtAprMax = YieldTrackingBorrowRate.borrowRate(encodedParams, 0, 0, 0);
        adapter.setApr(trackedApr, block.timestamp);

        uint256 rate = YieldTrackingBorrowRate.borrowRate(encodedParams, 0, 0, 0);

        assertEq(rate, rateAtAprMax);
    }

    function testFuzz_borrowRate_NeverDecreasesAsTrackedAprIncreases(
        YieldTrackingBorrowRate.Params memory params,
        int256 trackedApr,
        int256 higherTrackedApr
    ) public {
        _boundValidParams(params);
        higherTrackedApr = bound(higherTrackedApr, trackedApr, type(int256).max);
        bytes memory encodedParams = abi.encode(params);
        adapter.setApr(trackedApr, block.timestamp);
        uint256 rate = YieldTrackingBorrowRate.borrowRate(encodedParams, 0, 0, 0);
        adapter.setApr(higherTrackedApr, block.timestamp);

        uint256 higherRate = YieldTrackingBorrowRate.borrowRate(encodedParams, 0, 0, 0);

        assertGe(higherRate, rate);
    }

    function testFuzz_borrowRate_NeverIncreasesAsSpreadIncreases(
        YieldTrackingBorrowRate.Params memory params,
        int256 trackedApr,
        int256 higherSpread
    ) public {
        _boundValidParams(params);
        higherSpread = bound(higherSpread, params.spread, type(int256).max);
        adapter.setApr(trackedApr, block.timestamp);
        uint256 rate = YieldTrackingBorrowRate.borrowRate(abi.encode(params), 0, 0, 0);
        params.spread = higherSpread;

        uint256 rateWithHigherSpread = YieldTrackingBorrowRate.borrowRate(abi.encode(params), 0, 0, 0);

        assertLe(rateWithHigherSpread, rate);
    }

    function testFuzz_borrowRate_PositiveSpreadLowersRateBySpread(
        YieldTrackingBorrowRate.Params memory params,
        int256 trackedApr,
        uint256 spread
    ) public {
        _boundValidParams(params);
        params.spread = 0;
        adapter.setApr(trackedApr, block.timestamp);
        uint256 rateWithoutSpread = YieldTrackingBorrowRate.borrowRate(abi.encode(params), 0, 0, 0);
        spread = bound(spread, 0, rateWithoutSpread);
        params.spread = SafeCast.toInt256(spread);

        uint256 rate = YieldTrackingBorrowRate.borrowRate(abi.encode(params), 0, 0, 0);

        assertEq(rate + spread, rateWithoutSpread);
    }

    function testFuzz_borrowRate_ReturnsZeroRateWhenSpreadExceedsRateWithoutSpread(
        YieldTrackingBorrowRate.Params memory params,
        int256 trackedApr,
        uint256 spread
    ) public {
        _boundValidParams(params);
        params.spread = 0;
        adapter.setApr(trackedApr, block.timestamp);
        uint256 rateWithoutSpread = YieldTrackingBorrowRate.borrowRate(abi.encode(params), 0, 0, 0);
        spread = bound(spread, rateWithoutSpread, IRMConstants.MAX_BORROW_RATE);
        params.spread = SafeCast.toInt256(spread);

        uint256 rate = YieldTrackingBorrowRate.borrowRate(abi.encode(params), 0, 0, 0);

        assertEq(rate, 0);
    }

    function testFuzz_borrowRate_NegativeSpreadRaisesRateByPremium(
        YieldTrackingBorrowRate.Params memory params,
        int256 trackedApr,
        uint256 premium
    ) public {
        _boundValidParams(params);
        params.spread = 0;
        premium = bound(premium, 0, IRMConstants.MAX_BORROW_RATE);
        adapter.setApr(trackedApr, block.timestamp);
        uint256 rateWithoutSpread = YieldTrackingBorrowRate.borrowRate(abi.encode(params), 0, 0, 0);
        params.spread = -SafeCast.toInt256(premium);

        uint256 rate = YieldTrackingBorrowRate.borrowRate(abi.encode(params), 0, 0, 0);

        assertEq(rate, rateWithoutSpread + premium);
    }

    function testFuzz_borrowRate_ReturnsFallbackTargetWhenAdapterReportsNoApr(
        YieldTrackingBorrowRate.Params memory params,
        int256 trackedApr
    ) public {
        _boundValidParams(params);
        adapter.setApr(trackedApr, 0);

        uint256 rate = YieldTrackingBorrowRate.borrowRate(abi.encode(params), 0, 0, 0);

        assertEq(rate, params.fallbackTarget);
    }

    function testFuzz_borrowRate_ReturnsFallbackTargetWhenTrackedAprIsStale(
        YieldTrackingBorrowRate.Params memory params,
        int256 trackedApr,
        uint256 updatedAt
    ) public {
        _boundValidParams(params);
        params.staleAfter = bound(params.staleAfter, 0, block.timestamp - 1);
        updatedAt = bound(updatedAt, 0, block.timestamp - params.staleAfter - 1);
        adapter.setApr(trackedApr, updatedAt);

        uint256 rate = YieldTrackingBorrowRate.borrowRate(abi.encode(params), 0, 0, 0);

        assertEq(rate, params.fallbackTarget);
    }

    function testFuzz_borrowRate_ReturnsSameRateForDifferentTotalIrmDebt(
        YieldTrackingBorrowRate.Params memory params,
        int256 trackedApr,
        uint256 utilisation,
        uint256 totalIrmDebt
    ) public {
        _boundValidParams(params);
        utilisation = bound(utilisation, 0, MathUtils.ONE_18_DP);
        totalIrmDebt = bound(totalIrmDebt, 1, type(uint256).max);
        adapter.setApr(trackedApr, block.timestamp);
        bytes memory encodedParams = abi.encode(params);
        uint256 idleLiquidity = MathUtils.ONE_18_DP - utilisation;

        uint256 rateWithoutIrmDebt = YieldTrackingBorrowRate.borrowRate(encodedParams, idleLiquidity, utilisation, 0);
        uint256 rateWithIrmDebt =
            YieldTrackingBorrowRate.borrowRate(encodedParams, idleLiquidity, utilisation, totalIrmDebt);

        assertEq(rateWithIrmDebt, rateWithoutIrmDebt);
    }

    /// @dev Bounds the slope by the maximum attainable target rate, mirroring the validity constraint rather than an
    ///      expected value. The unit tests pin that constraint with hand-checked boundaries.
    function _boundValidParams(YieldTrackingBorrowRate.Params memory params) private view {
        params.adapter = adapter;
        params.aprMin = bound(params.aprMin, 0, IRMConstants.MAX_BORROW_RATE);
        params.aprMax = bound(params.aprMax, params.aprMin, IRMConstants.MAX_BORROW_RATE);
        int256 maxBorrowRate = SafeCast.toInt256(IRMConstants.MAX_BORROW_RATE);
        params.spread = bound(params.spread, SafeCast.toInt256(params.aprMax) - maxBorrowRate, maxBorrowRate);
        params.fallbackTarget = bound(params.fallbackTarget, 0, IRMConstants.MAX_BORROW_RATE);
        params.optimalUtilisation = bound(params.optimalUtilisation, 1, MathUtils.ONE_18_DP - 1);
        uint256 maxTrackedTargetRate =
            SafeCast.toUint256(SignedMath.max(SafeCast.toInt256(params.aprMax) - params.spread, 0));
        uint256 maxTargetRate = Math.max(maxTrackedTargetRate, params.fallbackTarget);
        params.slope = bound(params.slope, 0, IRMConstants.MAX_BORROW_RATE - maxTargetRate);
    }

    /// @dev A total liquidity of 1e18 makes `totalDebt` numerically equal to the 18dp utilisation under test.
    function _borrowRateAtUtilisation(bytes memory params, uint256 utilisation) private view returns (uint256) {
        return YieldTrackingBorrowRate.borrowRate(params, MathUtils.ONE_18_DP - utilisation, utilisation, 0);
    }
}
