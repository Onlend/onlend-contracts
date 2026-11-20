// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";

import {MathUtils} from "../../../../lib/MathUtils.sol";
import {InterestMath} from "../../../lib/InterestMath.sol";
import {IYieldAdapter} from "../../interfaces/IYieldAdapter.sol";
import {IRMConstants} from "../IRMConstants.sol";

/// @title Yield Tracking Borrow Rate Library
/// @notice Computes a borrow rate that is flat at a target rate tracking an external yield up to an optimal
///         utilisation, then rises linearly to full utilisation.
/// @dev The target rate is the tracked APR, bounded to `[aprMin, aprMax]`, less `spread` and floored at zero. A
///      negative `spread` adds a premium instead, so the target rate can exceed `aprMax`. While the adapter reports no
///      APR, or one older than `staleAfter`, `fallbackTarget` is the target rate instead.
library YieldTrackingBorrowRate {
    /// @notice Yield tracking borrow rate parameters.
    /// @param adapter Adapter the tracked APR is read from.
    /// @param window Lookback window the tracked APR is measured over, in seconds.
    /// @param spread Amount subtracted from the bounded tracked APR to give the target rate, scaled to 18dp. Negative
    ///        to add a premium instead.
    /// @param aprMin Floor applied to the tracked APR before the spread, scaled to 18dp.
    /// @param aprMax Cap applied to the tracked APR before the spread, scaled to 18dp.
    /// @param staleAfter Maximum age of the tracked APR before the fallback target rate applies, in seconds.
    /// @param fallbackTarget Target rate while the tracked APR is stale, scaled to 18dp.
    /// @param optimalUtilisation Utilisation up to which the borrow rate equals the target rate, scaled to 18dp.
    /// @param slope Rise in borrow rate from optimal to full utilisation, scaled to 18dp.
    struct Params {
        IYieldAdapter adapter;
        uint256 window;
        int256 spread;
        uint256 aprMin;
        uint256 aprMax;
        uint256 staleAfter;
        uint256 fallbackTarget;
        uint256 optimalUtilisation;
        uint256 slope;
    }

    /// @notice Validates yield tracking borrow rate parameters.
    /// @dev `params` must be `abi.encode(Params)`. Reverts from ABI decoding, arithmetic overflow or the adapter are
    ///      propagated.
    /// @param params Encoded `Params`.
    /// @return True if the adapter supports the yield adapter interface and the window, the APR bounds are ordered, and
    ///         the optimal utilisation and maximum attainable borrow rate are within the supported ranges.
    function isValid(bytes memory params) internal view returns (bool) {
        if (params.length != 288) return false;

        Params memory p = abi.decode(params, (Params));

        if (p.aprMin > p.aprMax || p.optimalUtilisation == 0 || p.optimalUtilisation >= MathUtils.ONE_18_DP) {
            return false;
        }

        uint256 maxTargetRate = Math.max(_applySpread(p.aprMax, p.spread), p.fallbackTarget);
        if (maxTargetRate + p.slope > IRMConstants.MAX_BORROW_RATE) return false;

        if (!ERC165Checker.supportsInterface(address(p.adapter), type(IYieldAdapter).interfaceId)) return false;

        return p.adapter.isValidWindow(p.window);
    }

    /// @notice Returns the yield tracking borrow rate for the current pool utilisation.
    /// @dev `params` must use the encoding documented in `isValid`. Total IRM debt is ignored because this model
    ///      depends only on pool utilisation. Reverts from ABI decoding or the adapter are propagated.
    /// @param params Encoded `Params`.
    /// @param idleLiquidity Current idle liquidity.
    /// @param totalDebt Current total debt.
    /// @return Borrow rate, scaled to 18dp.
    function borrowRate(bytes memory params, uint256 idleLiquidity, uint256 totalDebt, uint256)
        internal
        view
        returns (uint256)
    {
        Params memory p = abi.decode(params, (Params));

        uint256 targetRate = _targetRate(p);

        uint256 utilisation = InterestMath.calcUtilisation(idleLiquidity, totalDebt);
        if (utilisation <= p.optimalUtilisation) return targetRate;

        uint256 excessUtilisation = utilisation - p.optimalUtilisation;
        uint256 excessUtilisationRange = MathUtils.ONE_18_DP - p.optimalUtilisation;

        return targetRate + Math.mulDiv(excessUtilisation, p.slope, excessUtilisationRange);
    }

    /// @notice Returns the target rate for the flat region up to the optimal utilisation.
    /// @dev A zero `updatedAt` means the adapter has no APR, so the fallback target applies. A tracked APR with an
    ///      `updatedAt` in the future is treated as fresh. A non-positive tracked APR is raised to `aprMin`.
    /// @param p Decoded parameters.
    /// @return Target rate, scaled to 18dp.
    function _targetRate(Params memory p) private view returns (uint256) {
        (int256 trackedApr, uint256 updatedAt) = p.adapter.apr(p.window);

        // forge-lint: disable-next-line(block-timestamp)
        if (updatedAt == 0 || Math.saturatingSub(block.timestamp, updatedAt) > p.staleAfter) return p.fallbackTarget;

        /// @dev Cannot truncate: only a positive `trackedApr` is cast.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 positiveApr = trackedApr > 0 ? uint256(trackedApr) : 0;
        uint256 boundedApr = Math.min(Math.max(positiveApr, p.aprMin), p.aprMax);

        /// @dev Cannot overflow: `isValid` already applied the spread to `aprMax`, the largest APR passed here.
        return _applySpread(boundedApr, p.spread);
    }

    /// @notice Returns a bounded APR less a spread, floored at zero.
    /// @dev Reverts if `apr_` exceeds `type(int256).max` or the subtraction overflows.
    /// @param apr_ Bounded tracked APR, scaled to 18dp.
    /// @param spread Amount subtracted from `apr_`, scaled to 18dp. Negative to add a premium instead.
    /// @return Target rate, scaled to 18dp.
    function _applySpread(uint256 apr_, int256 spread) private pure returns (uint256) {
        return SafeCast.toUint256(SignedMath.max(SafeCast.toInt256(apr_) - spread, 0));
    }
}
