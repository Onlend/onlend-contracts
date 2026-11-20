// SPDX-License-Identifier: BUSL-1.1
// Portions adapted from Morpho's AdaptiveCurveIrm via Euler's IRMAdaptiveCurve, Copyright (c) 2023 Morpho Association,
// licensed under MIT.
// https://github.com/morpho-org/morpho-blue-irm/blob/a824ce06a53f45f12d0ffedb51abd756896b29fa/src/adaptive-curve-irm/AdaptiveCurveIrm.sol
// https://github.com/euler-xyz/evk-periphery/blob/9068992ad4747915d5ccd1b52ff7e4a9bade2b54/src/IRM/IRMAdaptiveCurve.sol
pragma solidity ^0.8.34;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {IVersioned} from "../../../../interfaces/IVersioned.sol";
import {ExpLib} from "../../../../lib/ExpLib.sol";
import {MathUtils} from "../../../../lib/MathUtils.sol";
import {InterestMath} from "../../../lib/InterestMath.sol";
import {IBorrowRateModule} from "../../interfaces/IBorrowRateModule.sol";
import {IValidatableModule} from "../../interfaces/IValidatableModule.sol";
import {IRMConstants} from "../../libraries/IRMConstants.sol";

/// @title  Adaptive Curve Borrow Rate
/// @notice External borrow rate module whose curve shifts over time to steer utilisation towards its optimum.
/// @dev    The borrow rate is the target rate scaled by a curve through the current utilisation: the target rate at
///         optimal utilisation, rising to `curveMultiplier` times it at full utilisation and falling to
///         `1 / curveMultiplier` times it at zero. While utilisation sits above the optimum the target rate rises
///         exponentially over time, and while below it falls, within `[targetRateMin, targetRateMax]`. The target rate
///         adapts only when `borrowRate` is called, over the whole period since the last call and with the parameters
///         it is called with, so after a period without calls it resumes from its last state. The rate returned is the
///         rate as of the call, not an average over the period since the last call.
///         Implementation for EIP-1167 clones; configured via `initialize`, not a constructor.
contract AdaptiveCurveBorrowRate is IBorrowRateModule, Initializable {
    using SafeCast for int256;
    using SafeCast for uint256;

    /// @notice Curve parameters, encoded as the module parameters.
    /// @param optimalUtilisation Utilisation the curve steers towards, scaled to 18dp.
    /// @param initialTargetRate Target rate until the first update, scaled to 18dp.
    /// @param targetRateMin Floor the target rate adapts down to, scaled to 18dp.
    /// @param targetRateMax Cap the target rate adapts up to, scaled to 18dp.
    /// @param curveMultiplier Ratio of the borrow rate at full utilisation to the target rate, scaled to 18dp.
    /// @param adjustmentSpeed Rate at which the target rate adapts at zero or full utilisation, per second, scaled to
    ///        18dp.
    struct Params {
        uint256 optimalUtilisation;
        uint256 initialTargetRate;
        uint256 targetRateMin;
        uint256 targetRateMax;
        uint256 curveMultiplier;
        uint256 adjustmentSpeed;
    }

    /// @notice What was recorded at the last update.
    /// @param targetRate Target rate, scaled to 18dp.
    /// @param utilisation Utilisation, scaled to 18dp.
    /// @param timestamp Timestamp of the update. Zero until the first update.
    struct TargetRateUpdate {
        uint144 targetRate;
        uint64 utilisation;
        uint48 timestamp;
    }

    /// @notice Lowest supported `targetRateMin` of 0.1%, scaled to 18dp.
    uint256 public constant MIN_TARGET_RATE = 0.001e18;
    /// @notice Lowest supported `curveMultiplier`, scaled to 18dp.
    uint256 public constant MIN_CURVE_MULTIPLIER = 1.01e18;
    /// @notice Highest supported `curveMultiplier`, scaled to 18dp.
    uint256 public constant MAX_CURVE_MULTIPLIER = 100e18;
    /// @notice Lowest supported `adjustmentSpeed` of 2 per year, per second, scaled to 18dp.
    uint256 public constant MIN_ADJUSTMENT_SPEED = 2e18 / MathUtils.SECONDS_IN_YEAR;
    /// @notice Highest supported `adjustmentSpeed` of 1,000 per year, per second, scaled to 18dp.
    uint256 public constant MAX_ADJUSTMENT_SPEED = 1000e18 / MathUtils.SECONDS_IN_YEAR;

    /// @notice `MathUtils.ONE_18_DP`, signed for the curve arithmetic.
    int256 private constant ONE_18_DP_INT = int256(MathUtils.ONE_18_DP);

    /// @notice Only account allowed to call `borrowRate`.
    address private _borrowRateCaller;
    /// @notice What was recorded at the last update.
    TargetRateUpdate private _lastUpdate;

    /// @notice Emitted when the target rate and utilisation are recorded.
    /// @param targetRate Target rate recorded, scaled to 18dp.
    /// @param utilisation Utilisation recorded, scaled to 18dp.
    event TargetRateUpdated(uint256 targetRate, uint256 utilisation);

    /// @notice Reverts when `borrowRate` is called by an account other than the borrow rate caller.
    error NotBorrowRateCaller();

    /// @notice Restricts a function to the borrow rate caller.
    modifier onlyBorrowRateCaller() {
        if (msg.sender != _borrowRateCaller) revert NotBorrowRateCaller();
        _;
    }

    /// @notice Locks the Implementation so it can never be initialized or used directly.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes a clone with its borrow rate caller.
    /// @dev Callable once per clone.
    /// @param borrowRateCaller_ Only account allowed to call `borrowRate`.
    function initialize(address borrowRateCaller_) external initializer {
        _borrowRateCaller = borrowRateCaller_;
    }

    /// @inheritdoc IBorrowRateModule
    /// @dev Total IRM debt is ignored because this model depends only on utilisation.
    function borrowRate(bytes calldata params, uint256 idleLiquidity, uint256 totalDebt, uint256)
        external
        override
        onlyBorrowRateCaller
        returns (uint256 rate)
    {
        TargetRateUpdate memory next;
        (rate, next) = _borrowRate(abi.decode(params, (Params)), idleLiquidity, totalDebt);

        /// @dev Nothing is recorded until there is debt, so adaptation starts from the utilisation and time of the
        ///      first borrow rather than from an idle period before it.
        if (totalDebt != 0 || _lastUpdate.timestamp != 0) {
            _lastUpdate = next;
            emit TargetRateUpdated(next.targetRate, next.utilisation);
        }
    }

    /// @inheritdoc IBorrowRateModule
    /// @dev Total IRM debt is ignored because this model depends only on utilisation.
    function previewBorrowRate(bytes calldata params, uint256 idleLiquidity, uint256 totalDebt, uint256)
        external
        view
        override
        returns (uint256 rate)
    {
        (rate,) = _borrowRate(abi.decode(params, (Params)), idleLiquidity, totalDebt);
    }

    /// @inheritdoc IValidatableModule
    /// @dev `params` must be `abi.encode(Params)`. Reverts from ABI decoding or arithmetic overflow are propagated.
    function isValid(bytes calldata params) external pure override returns (bool) {
        if (params.length != 192) return false;

        Params memory p = abi.decode(params, (Params));

        if (
            p.optimalUtilisation == 0 || p.optimalUtilisation >= MathUtils.ONE_18_DP
                || p.targetRateMin < MIN_TARGET_RATE || p.targetRateMin > p.initialTargetRate
                || p.initialTargetRate > p.targetRateMax || p.curveMultiplier < MIN_CURVE_MULTIPLIER
                || p.curveMultiplier > MAX_CURVE_MULTIPLIER || p.adjustmentSpeed < MIN_ADJUSTMENT_SPEED
                || p.adjustmentSpeed > MAX_ADJUSTMENT_SPEED
        ) return false;

        /// @dev The highest attainable borrow rate, `targetRateMax` times `curveMultiplier`, must not exceed the
        ///      maximum supported borrow rate.
        return Math.mulDiv(p.targetRateMax, p.curveMultiplier, MathUtils.ONE_18_DP) <= IRMConstants.MAX_BORROW_RATE;
    }

    /// @notice Returns the only account allowed to call `borrowRate`.
    /// @return Borrow rate caller.
    function borrowRateCaller() external view returns (address) {
        return _borrowRateCaller;
    }

    /// @notice Returns what was recorded at the last update.
    /// @return What was recorded at the last update, all zero until the first update.
    function lastUpdate() external view returns (TargetRateUpdate memory) {
        return _lastUpdate;
    }

    /// @inheritdoc IVersioned
    function contractName() external pure override returns (string memory name_) {
        return "AdaptiveCurveBorrowRate";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure override returns (string memory version_) {
        return "1.0.0";
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IBorrowRateModule).interfaceId || interfaceId == type(IValidatableModule).interfaceId
            || interfaceId == type(IVersioned).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /// @notice Calculates the borrow rate, with the update it would record.
    /// @dev `p` is assumed to have previously passed `isValid`, which bounds every parameter used here.
    /// @param p Curve parameters.
    /// @param idleLiquidity Current idle liquidity.
    /// @param totalDebt Current total debt.
    /// @return rate Borrow rate, scaled to 18dp.
    /// @return next Update as of now.
    function _borrowRate(Params memory p, uint256 idleLiquidity, uint256 totalDebt)
        private
        view
        returns (uint256 rate, TargetRateUpdate memory next)
    {
        uint256 utilisation = InterestMath.calcUtilisation(idleLiquidity, totalDebt);
        TargetRateUpdate memory last = _lastUpdate;

        uint256 targetRate;
        if (last.timestamp == 0) {
            targetRate = p.initialTargetRate;
        } else {
            /// @dev The target rate adapts over the period since the last update by the utilisation it was left at.
            ///      Cannot overflow: `isValid` bounds the adjustment speed by 1,000 per year and the normalised
            ///      distance is within [-1, 1].
            int256 speed = p.adjustmentSpeed.toInt256() * _err(last.utilisation, p.optimalUtilisation) / ONE_18_DP_INT;
            /// @dev Cannot overflow: the elapsed time fits the 48-bit timestamp it is measured from.
            int256 exponent = speed * (block.timestamp - last.timestamp).toInt256();
            /// @dev The cast cannot underflow as the exponential is non-negative. The result cannot overflow: the
            ///      stored target rate is bounded by the maximum borrow rate and the exponential by
            ///      `ExpLib.WEXP_UPPER_VALUE`.
            uint256 adaptedTargetRate =
                Math.mulDiv(last.targetRate, ExpLib.wExp(exponent).toUint256(), MathUtils.ONE_18_DP);

            /// @dev Clamped on every update, not only after adapting, as the bounds may have changed since the last.
            targetRate = Math.min(Math.max(adaptedTargetRate, p.targetRateMin), p.targetRateMax);
        }

        /// @dev The casts in cannot overflow as `isValid` bounds the target rate and multiplier. The cast out cannot
        ///      underflow: the target rate is at least `targetRateMin`, so the curve rate is non-negative.
        rate = _curve(targetRate.toInt256(), _err(utilisation, p.optimalUtilisation), p.curveMultiplier.toInt256())
            .toUint256();

        /// @dev Cannot overflow: the target rate is bounded by the maximum borrow rate, utilisation is at most 100%,
        ///      and the timestamp fits 48 bits.
        next = TargetRateUpdate({
            targetRate: targetRate.toUint144(),
            utilisation: utilisation.toUint64(),
            timestamp: block.timestamp.toUint48()
        });
    }

    /// @notice Returns the distance of a utilisation from the optimum, normalised by the distance from the optimum to
    ///         full utilisation above it or to zero below it.
    /// @param utilisation Utilisation, scaled to 18dp.
    /// @param optimalUtilisation Optimal utilisation, scaled to 18dp.
    /// @return Normalised distance in `[-1, 1]`, scaled to 18dp.
    function _err(uint256 utilisation, uint256 optimalUtilisation) private pure returns (int256) {
        uint256 range = utilisation > optimalUtilisation ? MathUtils.ONE_18_DP - optimalUtilisation : optimalUtilisation;
        /// @dev The casts cannot overflow as both are at most 100%. Cannot divide by zero: `isValid` bounds the optimal
        ///      utilisation strictly between 0 and 100%.
        return (utilisation.toInt256() - optimalUtilisation.toInt256()) * ONE_18_DP_INT / range.toInt256();
    }

    /// @notice Returns the curve through the target rate at a normalised distance from the optimum.
    /// @param targetRate Target rate, scaled to 18dp.
    /// @param err Normalised distance from the optimum, scaled to 18dp.
    /// @param curveMultiplier Ratio of the curve at full utilisation to the target rate, scaled to 18dp.
    /// @return Curve rate, scaled to 18dp.
    function _curve(int256 targetRate, int256 err, int256 curveMultiplier) private pure returns (int256) {
        /// @dev Non-negative as `1 - 1 / curveMultiplier` and `curveMultiplier - 1` are, and cannot divide by zero, as
        ///      `isValid` bounds the multiplier above 1.
        int256 coefficient =
            err < 0 ? ONE_18_DP_INT - ONE_18_DP_INT * ONE_18_DP_INT / curveMultiplier : curveMultiplier - ONE_18_DP_INT;
        /// @dev Non-negative for a non-negative target rate, as the coefficient is at most 1 when `err` is negative.
        ///      Cannot overflow: the coefficient is below 100 as `isValid` bounds `curveMultiplier` by 100, `err` is
        ///      within [-1, 1], and the target rate is bounded by the maximum borrow rate.
        return (coefficient * err / ONE_18_DP_INT + ONE_18_DP_INT) * targetRate / ONE_18_DP_INT;
    }
}
