// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import {Test} from "forge-std/Test.sol";

import {FeedYieldAdapter} from "src/onlend-managed/yield/FeedYieldAdapter.sol";
import {MockAggregatorV3} from "../../../mocks/MockAggregatorV3.sol";

contract FeedYieldAdapterFuzzTest is Test {
    uint8 internal constant FEED_DECIMALS = 8;
    uint8 internal constant PRECISION = 18;
    /// @dev Largest `aprDecimals` whose divisor fits in an `int256`.
    uint8 internal constant MAX_APR_DECIMALS = 94;
    uint256 internal constant UPDATED_AT = 1_000_000;

    MockAggregatorV3 internal feed;

    function setUp() public {
        feed = new MockAggregatorV3(FEED_DECIMALS, 0, UPDATED_AT);
    }

    // apr()

    function testFuzz_apr_ReturnsAnswerAt18Decimals(int256 answer) public {
        assertEq(_apr(answer, PRECISION), answer);
    }

    function testFuzz_apr_IsUnchangedByShiftingAnswerAndDecimalsTogether(int256 answer, uint8 aprDecimals) public {
        aprDecimals = uint8(bound(aprDecimals, 0, MAX_APR_DECIMALS - 1));
        int256 maxAnswer = _maxScalableAnswer(aprDecimals + 1) / 10;
        answer = bound(answer, -maxAnswer, maxAnswer);

        assertEq(_apr(answer * 10, aprDecimals + 1), _apr(answer, aprDecimals));
    }

    function testFuzz_apr_RoundsTowardZeroWithinOneUnitAbove18Decimals(int256 answer, uint8 aprDecimals) public {
        aprDecimals = uint8(bound(aprDecimals, PRECISION + 1, MAX_APR_DECIMALS));
        uint256 divisor = 10 ** (aprDecimals - PRECISION);

        int256 apr = _apr(answer, aprDecimals);

        assertTrue(apr == 0 || (apr > 0) == (answer > 0));
        assertLe(SignedMath.abs(apr) * divisor, SignedMath.abs(answer));
        assertLt(SignedMath.abs(answer) - SignedMath.abs(apr) * divisor, divisor);
    }

    function testFuzz_apr_NegatingAnswerNegatesApr(int256 answer, uint8 aprDecimals) public {
        aprDecimals = uint8(bound(aprDecimals, 0, MAX_APR_DECIMALS));
        int256 maxAnswer = _maxScalableAnswer(aprDecimals);
        answer = bound(answer, -maxAnswer, maxAnswer);

        assertEq(_apr(-answer, aprDecimals), -_apr(answer, aprDecimals));
    }

    function testFuzz_apr_ReturnsUpdatedAt(uint256 updatedAt) public {
        feed.setAnswer(0, updatedAt);
        FeedYieldAdapter adapter = new FeedYieldAdapter(feed, PRECISION);

        (, uint256 returnedUpdatedAt) = adapter.apr(0);

        assertEq(returnedUpdatedAt, updatedAt);
    }

    // isValidWindow()

    function testFuzz_isValidWindow_ReturnsFalseForNonZeroWindow(uint256 window) public {
        window = bound(window, 1, type(uint256).max);
        FeedYieldAdapter adapter = new FeedYieldAdapter(feed, PRECISION);

        assertFalse(adapter.isValidWindow(window));
    }

    /// @dev Publishes `answer` and returns the APR an adapter with `aprDecimals` reports for it.
    function _apr(int256 answer, uint8 aprDecimals) internal returns (int256 apr) {
        feed.setAnswer(answer, UPDATED_AT);
        (apr,) = new FeedYieldAdapter(feed, aprDecimals).apr(0);
    }

    /// @dev Largest answer, in magnitude, an adapter with `aprDecimals` can scale without overflowing.
    function _maxScalableAnswer(uint8 aprDecimals) internal pure returns (int256) {
        if (aprDecimals >= PRECISION) return type(int256).max;
        return type(int256).max / int256(10 ** (PRECISION - aprDecimals));
    }
}
