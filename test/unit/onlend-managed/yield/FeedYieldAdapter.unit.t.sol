// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {stdError} from "forge-std/StdError.sol";
import {Test} from "forge-std/Test.sol";

import {IVersioned} from "src/interfaces/IVersioned.sol";
import {FeedYieldAdapter} from "src/onlend-managed/yield/FeedYieldAdapter.sol";
import {IAggregatorV3} from "src/oracle/node-manager/interfaces/external/IAggregatorV3.sol";
import {IYieldAdapter} from "src/pool/irm/interfaces/IYieldAdapter.sol";
import {MockAggregatorV3} from "../../../mocks/MockAggregatorV3.sol";

contract FeedYieldAdapterUnitTest is Test {
    uint8 internal constant FEED_DECIMALS = 8;
    /// @dev A percentage with 8 decimals, so 4.33% is published as `433_000_000`.
    uint8 internal constant PERCENT_APR_DECIMALS = 10;
    int256 internal constant PERCENT_ANSWER = 433_000_000;
    int256 internal constant APR = 0.0433e18;
    uint256 internal constant UPDATED_AT = 1_000_000;

    MockAggregatorV3 internal feed;
    FeedYieldAdapter internal adapter;

    function setUp() public {
        feed = new MockAggregatorV3(FEED_DECIMALS, PERCENT_ANSWER, UPDATED_AT);
        adapter = new FeedYieldAdapter(feed, PERCENT_APR_DECIMALS);
    }

    // constructor()

    function test_constructor_SetsFeed() public view {
        assertEq(address(adapter.FEED()), address(feed));
    }

    function test_constructor_SetsAprDecimals() public view {
        assertEq(adapter.APR_DECIMALS(), PERCENT_APR_DECIMALS);
    }

    function test_constructor_AcceptsMaxScalableAprDecimals() public {
        FeedYieldAdapter maxAdapter = new FeedYieldAdapter(feed, 94);

        assertEq(maxAdapter.APR_DECIMALS(), 94);
    }

    function test_constructor_Revert_FeedHasNoCode() public {
        IAggregatorV3 eoa = IAggregatorV3(makeAddr("eoa"));

        vm.expectRevert();
        new FeedYieldAdapter(eoa, PERCENT_APR_DECIMALS);
    }

    function test_constructor_Revert_FeedReverts() public {
        feed.setShouldRevertOnLatestRoundData(true);

        vm.expectRevert(MockAggregatorV3.LatestRoundDataReverted.selector);
        new FeedYieldAdapter(feed, PERCENT_APR_DECIMALS);
    }

    function test_constructor_Revert_ReturnDataDoesNotDecode() public {
        vm.mockCall(address(feed), abi.encodeCall(IAggregatorV3.latestRoundData, ()), new bytes(159));

        vm.expectRevert();
        new FeedYieldAdapter(feed, PERCENT_APR_DECIMALS);
    }

    function test_constructor_Revert_DivisorAboveInt256Max() public {
        vm.expectRevert(abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintToInt.selector, 10 ** 77));
        new FeedYieldAdapter(feed, 95);
    }

    function test_constructor_Revert_DivisorAboveUint256Max() public {
        vm.expectRevert(stdError.arithmeticError);
        new FeedYieldAdapter(feed, 96);
    }

    // apr()

    function test_apr_ScalesUpAnswerBelow18Decimals() public view {
        (int256 apr,) = adapter.apr(0);

        assertEq(apr, APR);
    }

    function test_apr_ReturnsAnswerAt18Decimals() public {
        feed.setAnswer(APR, UPDATED_AT);
        FeedYieldAdapter fractionAdapter = new FeedYieldAdapter(feed, 18);

        (int256 apr,) = fractionAdapter.apr(0);

        assertEq(apr, APR);
    }

    function test_apr_ScalesDownAnswerAbove18Decimals() public {
        // A percentage with 18 decimals, so 4.33% is published as 4.33e18.
        feed.setAnswer(4.33e18, UPDATED_AT);
        FeedYieldAdapter percentAdapter = new FeedYieldAdapter(feed, 20);

        (int256 apr,) = percentAdapter.apr(0);

        assertEq(apr, APR);
    }

    function test_apr_RoundsPositiveAnswerTowardZero() public {
        feed.setAnswer(199, UPDATED_AT);
        FeedYieldAdapter percentAdapter = new FeedYieldAdapter(feed, 20);

        (int256 apr,) = percentAdapter.apr(0);

        assertEq(apr, 1);
    }

    function test_apr_RoundsNegativeAnswerTowardZero() public {
        feed.setAnswer(-199, UPDATED_AT);
        FeedYieldAdapter percentAdapter = new FeedYieldAdapter(feed, 20);

        (int256 apr,) = percentAdapter.apr(0);

        assertEq(apr, -1);
    }

    function test_apr_ReturnsNegativeAnswer() public {
        feed.setAnswer(-PERCENT_ANSWER, UPDATED_AT);

        (int256 apr,) = adapter.apr(0);

        assertEq(apr, -APR);
    }

    function test_apr_ReturnsUpdatedAt() public view {
        (, uint256 updatedAt) = adapter.apr(0);

        assertEq(updatedAt, UPDATED_AT);
    }

    function test_apr_ReturnsZeroUpdatedAtForIncompleteRound() public {
        feed.setAnswer(PERCENT_ANSWER, 0);

        (, uint256 updatedAt) = adapter.apr(0);

        assertEq(updatedAt, 0);
    }

    function test_apr_IgnoresRoundIdStartedAtAndAnsweredInRound() public {
        feed.setRoundData(7, PERCENT_ANSWER, 1, UPDATED_AT, 3);

        (int256 apr, uint256 updatedAt) = adapter.apr(0);

        assertEq(apr, APR);
        assertEq(updatedAt, UPDATED_AT);
    }

    function test_apr_IgnoresWindow() public view {
        (int256 apr, uint256 updatedAt) = adapter.apr(7 days);

        assertEq(apr, APR);
        assertEq(updatedAt, UPDATED_AT);
    }

    function test_apr_Revert_FeedReverts() public {
        feed.setShouldRevertOnLatestRoundData(true);

        vm.expectRevert(MockAggregatorV3.LatestRoundDataReverted.selector);
        adapter.apr(0);
    }

    function test_apr_Revert_ScaledUpAnswerOverflows() public {
        feed.setAnswer(type(int256).max, UPDATED_AT);

        vm.expectRevert(stdError.arithmeticError);
        adapter.apr(0);
    }

    // isValidWindow()

    function test_isValidWindow_ReturnsTrueForZeroWindow() public view {
        assertTrue(adapter.isValidWindow(0));
    }

    function test_isValidWindow_ReturnsFalseForWindowOfOne() public view {
        assertFalse(adapter.isValidWindow(1));
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(adapter.contractName(), "FeedYieldAdapter");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(adapter.contractVersion(), "1.0.0");
    }

    // supportsInterface()

    function test_supportsInterface_SupportsIYieldAdapter() public view {
        assertTrue(adapter.supportsInterface(type(IYieldAdapter).interfaceId));
    }

    function test_supportsInterface_SupportsIVersioned() public view {
        assertTrue(adapter.supportsInterface(type(IVersioned).interfaceId));
    }

    function test_supportsInterface_SupportsIERC165() public view {
        assertTrue(adapter.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_ReturnsFalseForUnsupportedInterface() public view {
        assertFalse(adapter.supportsInterface(0xffffffff));
    }
}
