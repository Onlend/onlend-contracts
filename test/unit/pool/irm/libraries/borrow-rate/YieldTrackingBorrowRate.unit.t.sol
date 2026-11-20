// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {stdError} from "forge-std/StdError.sol";
import {Test} from "forge-std/Test.sol";

import {MathUtils} from "src/lib/MathUtils.sol";
import {IYieldAdapter} from "src/pool/irm/interfaces/IYieldAdapter.sol";
import {IRMConstants} from "src/pool/irm/libraries/IRMConstants.sol";
import {YieldTrackingBorrowRate} from "src/pool/irm/libraries/borrow-rate/YieldTrackingBorrowRate.sol";
import {MockYieldAdapter} from "../mocks/MockYieldAdapter.sol";

contract YieldTrackingBorrowRateUnitTest is Test {
    uint256 internal constant WINDOW = 7 days;
    int256 internal constant POSITIVE_SPREAD = 0.01e18;
    int256 internal constant NEGATIVE_SPREAD = -0.01e18;
    uint256 internal constant APR_MIN = 0.02e18;
    uint256 internal constant APR_MAX = 0.1e18;
    uint256 internal constant STALE_AFTER = 1 days;
    uint256 internal constant FALLBACK_TARGET = 0.03e18;
    uint256 internal constant OPTIMAL_UTILISATION = 0.8e18;
    uint256 internal constant SLOPE = 0.5e18;

    int256 internal constant TRACKED_APR = 0.06e18;
    uint256 internal constant TARGET_RATE = 0.05e18;

    MockYieldAdapter internal adapter;

    function setUp() public {
        vm.warp(1_000_000);
        adapter = new MockYieldAdapter();
        adapter.setApr(TRACKED_APR, block.timestamp);
    }

    // isValid()

    function test_isValid_ReturnsTrueForValidParams() public view {
        assertTrue(YieldTrackingBorrowRate.isValid(_encode(_defaultParams())));
    }

    function test_isValid_ForwardsWindowToAdapter() public {
        vm.expectCall(address(adapter), abi.encodeCall(IYieldAdapter.isValidWindow, (WINDOW)));

        YieldTrackingBorrowRate.isValid(_encode(_defaultParams()));
    }

    function test_isValid_ReturnsTrueWhenAprMinEqualsAprMax() public view {
        YieldTrackingBorrowRate.Params memory params = _defaultParams();
        params.aprMin = APR_MAX;

        assertTrue(YieldTrackingBorrowRate.isValid(_encode(params)));
    }

    function test_isValid_ReturnsTrueForMaxStaleAfter() public view {
        YieldTrackingBorrowRate.Params memory params = _defaultParams();
        params.staleAfter = type(uint256).max;

        assertTrue(YieldTrackingBorrowRate.isValid(_encode(params)));
    }

    function test_isValid_ReturnsTrueForMinOptimalUtilisation() public view {
        YieldTrackingBorrowRate.Params memory params = _defaultParams();
        params.optimalUtilisation = 1;

        assertTrue(YieldTrackingBorrowRate.isValid(_encode(params)));
    }

    function test_isValid_ReturnsTrueForMaxOptimalUtilisation() public view {
        YieldTrackingBorrowRate.Params memory params = _defaultParams();
        params.optimalUtilisation = MathUtils.ONE_18_DP - 1;

        assertTrue(YieldTrackingBorrowRate.isValid(_encode(params)));
    }

    function test_isValid_ReturnsTrueForMaxBorrowRateFromTrackedApr() public view {
        YieldTrackingBorrowRate.Params memory params = _defaultParams();
        params.slope = IRMConstants.MAX_BORROW_RATE - (APR_MAX - SafeCast.toUint256(POSITIVE_SPREAD));

        assertTrue(YieldTrackingBorrowRate.isValid(_encode(params)));
    }

    function test_isValid_ReturnsTrueForMaxBorrowRateFromFallbackTarget() public view {
        YieldTrackingBorrowRate.Params memory params = _defaultParams();
        params.fallbackTarget = IRMConstants.MAX_BORROW_RATE - SLOPE;

        assertTrue(YieldTrackingBorrowRate.isValid(_encode(params)));
    }

    function test_isValid_ReturnsTrueWhenSpreadExceedsAprMax() public view {
        YieldTrackingBorrowRate.Params memory params = _defaultParams();
        params.spread = SafeCast.toInt256(APR_MAX) + 1;

        assertTrue(YieldTrackingBorrowRate.isValid(_encode(params)));
    }

    function test_isValid_ReturnsTrueForMaxBorrowRateFromNegativeSpread() public view {
        YieldTrackingBorrowRate.Params memory params = _defaultParams();
        params.spread = NEGATIVE_SPREAD;
        params.slope = IRMConstants.MAX_BORROW_RATE - (APR_MAX + SafeCast.toUint256(-NEGATIVE_SPREAD));

        assertTrue(YieldTrackingBorrowRate.isValid(_encode(params)));
    }

    function test_isValid_ReturnsFalseWhenParamsAreEmpty() public view {
        assertFalse(YieldTrackingBorrowRate.isValid(""));
    }

    function test_isValid_ReturnsFalseWhenParamsLengthIsBelow288() public view {
        assertFalse(YieldTrackingBorrowRate.isValid(new bytes(287)));
    }

    function test_isValid_ReturnsFalseWhenParamsLengthIsAbove288() public view {
        assertFalse(YieldTrackingBorrowRate.isValid(new bytes(289)));
    }

    function test_isValid_ReturnsFalseWhenAprMinIsAboveAprMax() public view {
        YieldTrackingBorrowRate.Params memory params = _defaultParams();
        params.aprMin = APR_MAX + 1;

        assertFalse(YieldTrackingBorrowRate.isValid(_encode(params)));
    }

    function test_isValid_ReturnsFalseWhenOptimalUtilisationIsZero() public view {
        YieldTrackingBorrowRate.Params memory params = _defaultParams();
        params.optimalUtilisation = 0;

        assertFalse(YieldTrackingBorrowRate.isValid(_encode(params)));
    }

    function test_isValid_ReturnsFalseWhenOptimalUtilisationIsOne() public view {
        YieldTrackingBorrowRate.Params memory params = _defaultParams();
        params.optimalUtilisation = MathUtils.ONE_18_DP;

        assertFalse(YieldTrackingBorrowRate.isValid(_encode(params)));
    }

    function test_isValid_ReturnsFalseWhenMaxBorrowRateFromTrackedAprIsExceeded() public view {
        YieldTrackingBorrowRate.Params memory params = _defaultParams();
        params.slope = IRMConstants.MAX_BORROW_RATE - (APR_MAX - SafeCast.toUint256(POSITIVE_SPREAD)) + 1;

        assertFalse(YieldTrackingBorrowRate.isValid(_encode(params)));
    }

    function test_isValid_ReturnsFalseWhenMaxBorrowRateFromFallbackTargetIsExceeded() public view {
        YieldTrackingBorrowRate.Params memory params = _defaultParams();
        params.fallbackTarget = IRMConstants.MAX_BORROW_RATE - SLOPE + 1;

        assertFalse(YieldTrackingBorrowRate.isValid(_encode(params)));
    }

    function test_isValid_ReturnsFalseWhenMaxBorrowRateFromNegativeSpreadIsExceeded() public view {
        YieldTrackingBorrowRate.Params memory params = _defaultParams();
        params.spread = NEGATIVE_SPREAD;
        params.slope = IRMConstants.MAX_BORROW_RATE - (APR_MAX + SafeCast.toUint256(-NEGATIVE_SPREAD)) + 1;

        assertFalse(YieldTrackingBorrowRate.isValid(_encode(params)));
    }

    function test_isValid_ReturnsFalseWhenAdapterDoesNotSupportYieldAdapterInterface() public {
        adapter.setSupportsYieldAdapterInterface(false);

        assertFalse(YieldTrackingBorrowRate.isValid(_encode(_defaultParams())));
    }

    function test_isValid_ReturnsFalseWhenAdapterRejectsWindow() public {
        adapter.setValidWindow(false);

        assertFalse(YieldTrackingBorrowRate.isValid(_encode(_defaultParams())));
    }

    function test_isValid_RevertsWhenParamsCannotBeDecoded() public {
        bytes memory params = _malformedParams();

        vm.expectRevert();
        this.isValid(params);
    }

    function test_isValid_RevertsWhenBorrowRatesOverflow() public {
        YieldTrackingBorrowRate.Params memory params = _defaultParams();
        params.slope = type(uint256).max;

        vm.expectRevert(stdError.arithmeticError);
        this.isValid(_encode(params));
    }

    function test_isValid_RevertsWhenSpreadOverflowsTargetRate() public {
        YieldTrackingBorrowRate.Params memory params = _defaultParams();
        params.spread = type(int256).min;

        vm.expectRevert(stdError.arithmeticError);
        this.isValid(_encode(params));
    }

    function test_isValid_RevertsWhenAprMaxExceedsInt256() public {
        YieldTrackingBorrowRate.Params memory params = _defaultParams();
        params.aprMax = SafeCast.toUint256(type(int256).max) + 1;

        vm.expectRevert(abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintToInt.selector, params.aprMax));
        this.isValid(_encode(params));
    }

    function test_isValid_PropagatesAdapterRevert() public {
        adapter.setShouldRevertIsValidWindow(true);

        vm.expectRevert(MockYieldAdapter.IsValidWindowReverted.selector);
        this.isValid(_encode(_defaultParams()));
    }

    // borrowRate()

    function test_borrowRate_ReturnsTargetRateWhenPoolHasNoLiquidity() public view {
        assertEq(YieldTrackingBorrowRate.borrowRate(_encode(_defaultParams()), 0, 0, 0), TARGET_RATE);
    }

    function test_borrowRate_ReturnsTargetRateWhenPoolHasNoDebt() public view {
        assertEq(YieldTrackingBorrowRate.borrowRate(_encode(_defaultParams()), 100e18, 0, 0), TARGET_RATE);
    }

    function test_borrowRate_ReturnsTargetRateBelowOptimalUtilisation() public view {
        assertEq(YieldTrackingBorrowRate.borrowRate(_encode(_defaultParams()), 50e18, 50e18, 0), TARGET_RATE);
    }

    function test_borrowRate_ReturnsTargetRateAtOptimalUtilisation() public view {
        assertEq(YieldTrackingBorrowRate.borrowRate(_encode(_defaultParams()), 20e18, 80e18, 0), TARGET_RATE);
    }

    function test_borrowRate_ReturnsSlopedRateAboveOptimalUtilisation() public view {
        // 90% utilisation is halfway from optimal to full, adding half of the 50% slope.
        assertEq(YieldTrackingBorrowRate.borrowRate(_encode(_defaultParams()), 10e18, 90e18, 0), 0.3e18);
    }

    function test_borrowRate_ReturnsMaxConfiguredRateAtFullUtilisation() public view {
        assertEq(YieldTrackingBorrowRate.borrowRate(_encode(_defaultParams()), 0, 100e18, 0), 0.55e18);
    }

    function test_borrowRate_ReturnsRoundedRateImmediatelyAboveOptimalUtilisation() public view {
        uint256 totalDebt = OPTIMAL_UTILISATION + 1;
        uint256 idleLiquidity = MathUtils.ONE_18_DP - totalDebt;

        uint256 rate = YieldTrackingBorrowRate.borrowRate(_encode(_defaultParams()), idleLiquidity, totalDebt, 0);

        // At optimal + 1, the slope contribution is 2.5 wei and rounds down to 2 wei.
        assertEq(rate, TARGET_RATE + 2);
    }

    function test_borrowRate_ForwardsWindowToAdapter() public {
        vm.expectCall(address(adapter), abi.encodeCall(IYieldAdapter.apr, (WINDOW)));

        YieldTrackingBorrowRate.borrowRate(_encode(_defaultParams()), 0, 0, 0);
    }

    function test_borrowRate_RaisesTrackedAprBelowAprMinToAprMin() public {
        adapter.setApr(0.01e18, block.timestamp);

        assertEq(
            YieldTrackingBorrowRate.borrowRate(_encode(_defaultParams()), 0, 0, 0),
            APR_MIN - SafeCast.toUint256(POSITIVE_SPREAD)
        );
    }

    function test_borrowRate_RaisesNegativeTrackedAprToAprMin() public {
        adapter.setApr(-0.05e18, block.timestamp);

        assertEq(
            YieldTrackingBorrowRate.borrowRate(_encode(_defaultParams()), 0, 0, 0),
            APR_MIN - SafeCast.toUint256(POSITIVE_SPREAD)
        );
    }

    function test_borrowRate_CapsTrackedAprAboveAprMaxToAprMax() public {
        adapter.setApr(0.2e18, block.timestamp);

        assertEq(
            YieldTrackingBorrowRate.borrowRate(_encode(_defaultParams()), 0, 0, 0),
            APR_MAX - SafeCast.toUint256(POSITIVE_SPREAD)
        );
    }

    function test_borrowRate_ReturnsZeroTargetRateWhenSpreadExceedsBoundedApr() public view {
        YieldTrackingBorrowRate.Params memory params = _defaultParams();
        params.spread = TRACKED_APR + 1;

        assertEq(YieldTrackingBorrowRate.borrowRate(_encode(params), 0, 0, 0), 0);
    }

    function test_borrowRate_AddsPremiumToTrackedAprWhenSpreadIsNegative() public view {
        YieldTrackingBorrowRate.Params memory params = _defaultParams();
        params.spread = NEGATIVE_SPREAD;

        assertEq(
            YieldTrackingBorrowRate.borrowRate(_encode(params), 0, 0, 0),
            SafeCast.toUint256(TRACKED_APR) + SafeCast.toUint256(-NEGATIVE_SPREAD)
        );
    }

    function test_borrowRate_ReturnsTargetRateAboveAprMaxWhenSpreadIsNegative() public {
        adapter.setApr(0.2e18, block.timestamp);
        YieldTrackingBorrowRate.Params memory params = _defaultParams();
        params.spread = NEGATIVE_SPREAD;

        assertEq(
            YieldTrackingBorrowRate.borrowRate(_encode(params), 0, 0, 0), APR_MAX + SafeCast.toUint256(-NEGATIVE_SPREAD)
        );
    }

    function test_borrowRate_ReturnsTargetRateWhenTrackedAprIsExactlyStaleAfterOld() public {
        adapter.setApr(TRACKED_APR, block.timestamp - STALE_AFTER);

        assertEq(YieldTrackingBorrowRate.borrowRate(_encode(_defaultParams()), 0, 0, 0), TARGET_RATE);
    }

    function test_borrowRate_ReturnsTargetRateWhenTrackedAprIsUpdatedInFuture() public {
        adapter.setApr(TRACKED_APR, block.timestamp + 1);

        assertEq(YieldTrackingBorrowRate.borrowRate(_encode(_defaultParams()), 0, 0, 0), TARGET_RATE);
    }

    function test_borrowRate_ReturnsFallbackTargetWhenAdapterReportsNoApr() public {
        YieldTrackingBorrowRate.Params memory params = _defaultParams();
        params.staleAfter = type(uint256).max;
        adapter.setApr(TRACKED_APR, 0);

        assertEq(YieldTrackingBorrowRate.borrowRate(_encode(params), 0, 0, 0), FALLBACK_TARGET);
    }

    function test_borrowRate_ReturnsFallbackTargetWhenTrackedAprIsStale() public {
        adapter.setApr(TRACKED_APR, block.timestamp - STALE_AFTER - 1);

        assertEq(YieldTrackingBorrowRate.borrowRate(_encode(_defaultParams()), 0, 0, 0), FALLBACK_TARGET);
    }

    function test_borrowRate_ReturnsSlopedRateFromFallbackTargetAboveOptimalUtilisation() public {
        adapter.setApr(TRACKED_APR, block.timestamp - STALE_AFTER - 1);

        // 90% utilisation adds half of the 50% slope to the 3% fallback target.
        assertEq(YieldTrackingBorrowRate.borrowRate(_encode(_defaultParams()), 10e18, 90e18, 0), 0.28e18);
    }

    function test_borrowRate_RevertsWhenParamsCannotBeDecoded() public {
        bytes memory params = _malformedParams();

        vm.expectRevert();
        this.borrowRate(params, 0, 0, 0);
    }

    function test_borrowRate_RevertsWhenTotalLiquidityOverflows() public {
        bytes memory params = _encode(_defaultParams());

        vm.expectRevert(stdError.arithmeticError);
        this.borrowRate(params, type(uint256).max, 1, 0);
    }

    function test_borrowRate_PropagatesAdapterRevert() public {
        adapter.setShouldRevertApr(true);

        vm.expectRevert(MockYieldAdapter.AprReverted.selector);
        this.borrowRate(_encode(_defaultParams()), 0, 0, 0);
    }

    function isValid(bytes memory params) external view returns (bool) {
        return YieldTrackingBorrowRate.isValid(params);
    }

    function borrowRate(bytes memory params, uint256 idleLiquidity, uint256 totalDebt, uint256 totalIrmDebt)
        external
        view
        returns (uint256)
    {
        return YieldTrackingBorrowRate.borrowRate(params, idleLiquidity, totalDebt, totalIrmDebt);
    }

    function _defaultParams() private view returns (YieldTrackingBorrowRate.Params memory) {
        return YieldTrackingBorrowRate.Params({
            adapter: adapter,
            window: WINDOW,
            spread: POSITIVE_SPREAD,
            aprMin: APR_MIN,
            aprMax: APR_MAX,
            staleAfter: STALE_AFTER,
            fallbackTarget: FALLBACK_TARGET,
            optimalUtilisation: OPTIMAL_UTILISATION,
            slope: SLOPE
        });
    }

    function _encode(YieldTrackingBorrowRate.Params memory params) private pure returns (bytes memory) {
        return abi.encode(params);
    }

    /// @dev Dirties the upper bits of the `adapter` word, so the params have a valid length but fail to decode.
    function _malformedParams() private view returns (bytes memory params) {
        params = _encode(_defaultParams());
        assembly ("memory-safe") {
            mstore(add(params, 0x20), not(0))
        }
    }
}
