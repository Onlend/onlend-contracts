// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {IVersioned} from "../../interfaces/IVersioned.sol";
import {IAggregatorV3} from "../../oracle/node-manager/interfaces/external/IAggregatorV3.sol";
import {IYieldAdapter} from "../../pool/irm/interfaces/IYieldAdapter.sol";

/// @title  FeedYieldAdapter
/// @notice Reports an APR published off-chain through an `AggregatorV3Interface` feed.
/// @dev    The feed's answer is the APR itself, `answer / 10 ** aprDecimals`, scaled here to 18dp. The publisher has
///         already measured it, so no lookback window applies and the only valid window is zero.
///
///         Deployed once per feed by Onlend and shared by every lending app that tracks it.
///
///         Security considerations, all on the operator choosing the feed:
///         - Trusted publisher: the APR is whatever the publisher last wrote rather than a value derived on-chain, so
///           the feed is trusted as much as its publisher and whoever controls its proxy.
///         - Units: the feed must report an APR, not an APY or a price. `aprDecimals` is fixed at deployment, so a feed
///           that later changes its decimals or units is misreported until a new adapter replaces this one.
///         - Availability: the feed is read on every call, and its reverts are bubbled up.
contract FeedYieldAdapter is IYieldAdapter {
    /// @notice Decimal places of the reported APR.
    uint8 private constant PRECISION = 18;

    /// @notice Feed the APR is read from.
    IAggregatorV3 public immutable FEED;
    /// @notice Decimal places of the feed's answer as a fraction of one, e.g. 10 for a percentage with 8 decimals.
    uint8 public immutable APR_DECIMALS;

    /// @dev    Reads the APR once, so deployment reverts if the feed reverts, returns data that does not decode, or
    ///         reports an answer `aprDecimals_` cannot scale. This does not guarantee later behaviour.
    /// @param  feed_        Feed the APR is read from.
    /// @param  aprDecimals_ Decimal places of the feed's answer as a fraction of one, e.g. 10 for a percentage with 8
    ///                      decimals.
    constructor(IAggregatorV3 feed_, uint8 aprDecimals_) {
        FEED = feed_;
        APR_DECIMALS = aprDecimals_;

        _apr();
    }

    /// @inheritdoc IYieldAdapter
    /// @dev    `window` is ignored. See `_apr` for scaling, rounding and reverts.
    function apr(uint256) external view override(IYieldAdapter) returns (int256 apr_, uint256 updatedAt) {
        return _apr();
    }

    /// @inheritdoc IYieldAdapter
    /// @dev    Only a zero window is valid, since the publisher has already measured the APR.
    function isValidWindow(uint256 window) external pure override(IYieldAdapter) returns (bool) {
        return window == 0;
    }

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "FeedYieldAdapter";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure override(IERC165) returns (bool) {
        return interfaceId == type(IYieldAdapter).interfaceId || interfaceId == type(IVersioned).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    /// @notice Returns the feed's latest answer scaled to 18dp, and when it was updated.
    /// @dev    `roundId`, `startedAt` and `answeredInRound` are ignored, since their meaning varies between publishers.
    ///         `updatedAt` is returned unchanged, including zero for an incomplete round. Scaling down rounds toward
    ///         zero. Reverts if `aprDecimals` exceeds 94, since the divisor no longer fits in an `int256`, or if
    ///         scaling up overflows. Reverts from the feed are bubbled up.
    /// @return apr_      APR, scaled to 18dp.
    /// @return updatedAt Timestamp the feed's latest answer was updated at.
    function _apr() private view returns (int256 apr_, uint256 updatedAt) {
        int256 answer;
        (, answer,, updatedAt,) = FEED.latestRoundData();

        /// @dev The multiplier's cast cannot fail: it is at most `10 ** 18`.
        apr_ = APR_DECIMALS > PRECISION
            ? answer / SafeCast.toInt256(10 ** (APR_DECIMALS - PRECISION))
            : answer * SafeCast.toInt256(10 ** (PRECISION - APR_DECIMALS));
    }
}
