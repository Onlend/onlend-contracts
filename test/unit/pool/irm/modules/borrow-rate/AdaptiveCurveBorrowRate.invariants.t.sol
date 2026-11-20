// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

import {IRMConstants} from "src/pool/irm/libraries/IRMConstants.sol";
import {AdaptiveCurveBorrowRate} from "src/pool/irm/modules/borrow-rate/AdaptiveCurveBorrowRate.sol";

/// @notice Stateful handler driving the module through rate updates at fuzzed utilisations (`borrowRate`), gaps between
///         them (`passTime`) and changes of parameters between them (`setParams`), standing in for its IRM.
/// @dev    Every action is guarded so the handler never reverts. The handler is the module's borrow rate caller.
///
///         Expectations recorded for invariants to check against:
///         - `lastPreviewedRate` / `lastRate` — the preview taken immediately before the last `borrowRate` and its
///           result.
///         - `hasRecorded` — whether any update has been recorded, which happens from the first call with debt on.
///         - `paramsAtLastUpdate` — the parameters the last recorded update was made with, whose bounds the stored
///           target rate must sit within until the next update.
// forge-lint: disable-next-line(multi-contract-file)
contract AdaptiveCurveBorrowRateHandler is Test {
    uint256 internal constant MAX_ELAPSED = 365 days;

    AdaptiveCurveBorrowRate public module;
    uint256 public lastPreviewedRate;
    uint256 public lastRate;
    bool public hasRecorded;

    AdaptiveCurveBorrowRate.Params internal _params;
    AdaptiveCurveBorrowRate.Params internal _paramsAtLastUpdate;

    constructor(AdaptiveCurveBorrowRate _module) {
        module = _module;
        _params = AdaptiveCurveBorrowRate.Params({
            optimalUtilisation: 0.9e18,
            initialTargetRate: 0.04e18,
            targetRateMin: 0.001e18,
            targetRateMax: 2e18,
            curveMultiplier: 4e18,
            adjustmentSpeed: 50e18 / uint256(365 days)
        });
    }

    /// @dev Updates the rate at fuzzed idle liquidity and debt, zero debt included, so total liquidity also changes
    ///      between updates. Records the preview taken just before.
    function borrowRate(uint256 idleSeed, uint256 debtSeed) external {
        uint256 debt = bound(debtSeed, 0, type(uint256).max);
        uint256 idle = bound(idleSeed, 0, type(uint256).max - debt);
        bytes memory encodedParams = abi.encode(_params);

        lastPreviewedRate = module.previewBorrowRate(encodedParams, idle, debt, 0);
        lastRate = module.borrowRate(encodedParams, idle, debt, 0);

        if (debt != 0 || hasRecorded) {
            hasRecorded = true;
            _paramsAtLastUpdate = _params;
        }
    }

    /// @dev Advances time between updates, so the target rate adapts over gaps of up to several years in a run.
    function passTime(uint256 elapsed) external {
        vm.warp(block.timestamp + bound(elapsed, 1, MAX_ELAPSED));
    }

    /// @dev Switches to fuzzed valid parameters, as the IRM's borrow rate updater may between updates.
    function setParams(AdaptiveCurveBorrowRate.Params memory newParams) external {
        _params = _boundParams(newParams);
    }

    function params() external view returns (AdaptiveCurveBorrowRate.Params memory) {
        return _params;
    }

    function paramsAtLastUpdate() external view returns (AdaptiveCurveBorrowRate.Params memory) {
        return _paramsAtLastUpdate;
    }

    function _boundParams(AdaptiveCurveBorrowRate.Params memory params_)
        internal
        view
        returns (AdaptiveCurveBorrowRate.Params memory)
    {
        params_.optimalUtilisation = bound(params_.optimalUtilisation, 1, 1e18 - 1);
        params_.curveMultiplier =
            bound(params_.curveMultiplier, module.MIN_CURVE_MULTIPLIER(), module.MAX_CURVE_MULTIPLIER());
        params_.targetRateMax = bound(
            params_.targetRateMax,
            module.MIN_TARGET_RATE(),
            IRMConstants.MAX_BORROW_RATE * 1e18 / params_.curveMultiplier
        );
        params_.targetRateMin = bound(params_.targetRateMin, module.MIN_TARGET_RATE(), params_.targetRateMax);
        params_.initialTargetRate = bound(params_.initialTargetRate, params_.targetRateMin, params_.targetRateMax);
        params_.adjustmentSpeed =
            bound(params_.adjustmentSpeed, module.MIN_ADJUSTMENT_SPEED(), module.MAX_ADJUSTMENT_SPEED());
        return params_;
    }
}

// forge-lint: disable-next-line(multi-contract-file)
contract AdaptiveCurveBorrowRateInvariantsTest is Test {
    AdaptiveCurveBorrowRate internal module;
    AdaptiveCurveBorrowRateHandler internal handler;

    function setUp() public {
        module = AdaptiveCurveBorrowRate(Clones.clone(address(new AdaptiveCurveBorrowRate())));
        handler = new AdaptiveCurveBorrowRateHandler(module);
        module.initialize(address(handler));

        targetContract(address(handler));
    }

    function invariant_PreviewMatchesBorrowRate() public view {
        assertEq(handler.lastPreviewedRate(), handler.lastRate());
    }

    function invariant_TargetRateWithinBoundsOfLastUpdate() public view {
        if (!handler.hasRecorded()) return;
        AdaptiveCurveBorrowRate.Params memory params = handler.paramsAtLastUpdate();

        uint256 targetRate = module.lastUpdate().targetRate;

        assertGe(targetRate, params.targetRateMin);
        assertLe(targetRate, params.targetRateMax);
    }

    function invariant_RateAtFullUtilisationIsAtMostMaxBorrowRate() public view {
        uint256 rate = module.previewBorrowRate(abi.encode(handler.params()), 0, 1e18, 0);

        assertLe(rate, IRMConstants.MAX_BORROW_RATE);
    }

    function invariant_RecordsOnlyOnceBorrowed() public view {
        assertEq(module.lastUpdate().timestamp != 0, handler.hasRecorded());
    }

    function invariant_LastUpdateNotInFuture() public view {
        assertLe(module.lastUpdate().timestamp, block.timestamp);
    }

    function invariant_RecordedUtilisationIsAtMostFull() public view {
        assertLe(module.lastUpdate().utilisation, 1e18);
    }
}
