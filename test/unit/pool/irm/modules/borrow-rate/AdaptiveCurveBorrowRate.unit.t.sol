// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {stdError} from "forge-std/StdError.sol";
import {Test} from "forge-std/Test.sol";

import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IBorrowRateModule} from "src/pool/irm/interfaces/IBorrowRateModule.sol";
import {IValidatableModule} from "src/pool/irm/interfaces/IValidatableModule.sol";
import {ExpLib} from "src/lib/ExpLib.sol";
import {AdaptiveCurveBorrowRate} from "src/pool/irm/modules/borrow-rate/AdaptiveCurveBorrowRate.sol";

contract AdaptiveCurveBorrowRateUnitTest is Test {
    uint256 internal constant OPTIMAL_UTILISATION = 0.9e18;
    uint256 internal constant INITIAL_TARGET_RATE = 0.04e18;
    uint256 internal constant TARGET_RATE_MIN = 0.001e18;
    uint256 internal constant TARGET_RATE_MAX = 2e18;
    uint256 internal constant CURVE_MULTIPLIER = 4e18;
    uint256 internal constant ADJUSTMENT_SPEED = 50e18 / uint256(365 days);
    // ln(2) per day, so a day at zero or full utilisation adapts the target rate by e^ln(2) = 2.
    uint256 internal constant LN_2_PER_DAY = uint256(ExpLib.LN_2_INT) / 1 days;
    // Truncating ln(2) to a per-second speed leaves the day's exponent short by under 1e-13.
    uint256 internal constant LN_2_PER_DAY_TOLERANCE = 1e6;

    address internal borrowRateCaller;
    AdaptiveCurveBorrowRate internal implementation;
    AdaptiveCurveBorrowRate internal module;

    function setUp() public {
        borrowRateCaller = makeAddr("borrowRateCaller");
        implementation = new AdaptiveCurveBorrowRate();

        module = AdaptiveCurveBorrowRate(Clones.clone(address(implementation)));
        module.initialize(borrowRateCaller);
    }

    // initialize()

    function test_initialize_SetsBorrowRateCaller() public view {
        assertEq(module.borrowRateCaller(), borrowRateCaller);
    }

    // borrowRate()

    function test_borrowRate_ReturnsLowestRateWithoutRecordingBeforeFirstBorrow() public {
        uint256 rate = _borrowRate(_params(), 100e18, 0);

        // Zero utilisation is a quarter of the 4% initial target rate.
        assertEq(rate, 0.01e18);
        assertEq(module.lastUpdate().timestamp, 0);
    }

    function test_borrowRate_EmitsNothingBeforeFirstBorrow() public {
        vm.expectEmit(false, false, false, false, address(module), 0);
        emit AdaptiveCurveBorrowRate.TargetRateUpdated(0, 0);

        _borrowRate(_params(), 100e18, 0);
    }

    function test_borrowRate_ReturnsInitialTargetRateAtOptimalUtilisationOnFirstBorrow() public {
        uint256 rate = _borrowRate(_params(), 10e18, 90e18);

        assertEq(rate, INITIAL_TARGET_RATE);
    }

    function test_borrowRate_RecordsFirstBorrow() public {
        _borrowRate(_params(), 10e18, 90e18);

        AdaptiveCurveBorrowRate.TargetRateUpdate memory last = module.lastUpdate();
        assertEq(last.targetRate, INITIAL_TARGET_RATE);
        assertEq(last.utilisation, 0.9e18);
        assertEq(last.timestamp, block.timestamp);
    }

    function test_borrowRate_EmitsTargetRateUpdatedOnFirstBorrow() public {
        vm.expectEmit(address(module));
        emit AdaptiveCurveBorrowRate.TargetRateUpdated(INITIAL_TARGET_RATE, 0.9e18);

        _borrowRate(_params(), 10e18, 90e18);
    }

    function test_borrowRate_RecordsWithoutDebtAfterFirstBorrow() public {
        _borrowRate(_params(), 10e18, 90e18);
        vm.warp(block.timestamp + 1 days);

        _borrowRate(_params(), 100e18, 0);

        // The day at the optimum leaves the target rate unchanged.
        AdaptiveCurveBorrowRate.TargetRateUpdate memory last = module.lastUpdate();
        assertEq(last.targetRate, INITIAL_TARGET_RATE);
        assertEq(last.utilisation, 0);
        assertEq(last.timestamp, vm.getBlockTimestamp());
    }

    function test_borrowRate_ReturnsMultipliedTargetRateAtFullUtilisation() public {
        uint256 rate = _borrowRate(_params(), 0, 100e18);

        // Full utilisation is four times the 4% target rate.
        assertEq(rate, 0.16e18);
    }

    function test_borrowRate_InterpolatesAboveOptimalUtilisation() public {
        uint256 rate = _borrowRate(_params(), 5e18, 95e18);

        // 95% is halfway from the 90% optimum to full, so halfway from 1x to 4x: 2.5x the 4% target rate.
        assertEq(rate, 0.1e18);
    }

    function test_borrowRate_InterpolatesBelowOptimalUtilisation() public {
        uint256 rate = _borrowRate(_params(), 55e18, 45e18);

        // 45% is halfway from the 90% optimum to zero, so halfway from 1x to 0.25x: 0.625x the 4% target rate.
        assertEq(rate, 0.025e18);
    }

    function test_borrowRate_KeepsTargetRateAtOptimalUtilisation() public {
        _borrowRate(_params(), 10e18, 90e18);
        vm.warp(block.timestamp + 365 days);

        uint256 rate = _borrowRate(_params(), 10e18, 90e18);

        assertEq(rate, INITIAL_TARGET_RATE);
        assertEq(module.lastUpdate().targetRate, INITIAL_TARGET_RATE);
    }

    function test_borrowRate_DoublesTargetRateAfterDayAtFullUtilisation() public {
        AdaptiveCurveBorrowRate.Params memory params = _params();
        params.adjustmentSpeed = LN_2_PER_DAY;
        _borrowRate(params, 0, 100e18);
        vm.warp(block.timestamp + 1 days);

        _borrowRate(params, 0, 100e18);

        assertApproxEqRel(module.lastUpdate().targetRate, 0.08e18, LN_2_PER_DAY_TOLERANCE);
    }

    function test_borrowRate_DoublesTargetRateAfterTwoDaysHalfwayAboveOptimalUtilisation() public {
        AdaptiveCurveBorrowRate.Params memory params = _params();
        params.adjustmentSpeed = LN_2_PER_DAY;
        _borrowRate(params, 5e18, 95e18);
        vm.warp(block.timestamp + 2 days);

        _borrowRate(params, 5e18, 95e18);

        // 95% is halfway from the 90% optimum to full, so the target rate adapts at half speed and doubles in two days.
        assertApproxEqRel(module.lastUpdate().targetRate, 0.08e18, LN_2_PER_DAY_TOLERANCE);
    }

    function test_borrowRate_HalvesTargetRateAfterDayAtZeroUtilisation() public {
        AdaptiveCurveBorrowRate.Params memory params = _params();
        params.adjustmentSpeed = LN_2_PER_DAY;
        _borrowRate(params, 10e18, 90e18);
        _borrowRate(params, 100e18, 0);
        vm.warp(block.timestamp + 1 days);

        _borrowRate(params, 100e18, 0);

        assertApproxEqRel(module.lastUpdate().targetRate, 0.02e18, LN_2_PER_DAY_TOLERANCE);
    }

    function test_borrowRate_ClampsTargetRateToMaximum() public {
        _borrowRate(_params(), 0, 100e18);
        vm.warp(block.timestamp + 365 days);

        uint256 rate = _borrowRate(_params(), 0, 100e18);

        // A year at full utilisation adapts by e^50, far past the 200% maximum, which is quadrupled at full.
        assertEq(module.lastUpdate().targetRate, TARGET_RATE_MAX);
        assertEq(rate, 8e18);
    }

    function test_borrowRate_ClampsTargetRateToMinimum() public {
        _borrowRate(_params(), 10e18, 90e18);
        _borrowRate(_params(), 100e18, 0);
        vm.warp(block.timestamp + 365 days);

        uint256 rate = _borrowRate(_params(), 100e18, 0);

        // A year at zero utilisation adapts by e^-50, far past the 0.1% minimum, which is quartered at zero.
        assertEq(module.lastUpdate().targetRate, TARGET_RATE_MIN);
        assertEq(rate, 0.00025e18);
    }

    function test_borrowRate_ClampsTargetRateToLoweredMaximumWithoutElapsedTime() public {
        _borrowRate(_params(), 10e18, 90e18);
        AdaptiveCurveBorrowRate.Params memory lowered = _params();
        lowered.initialTargetRate = 0.02e18;
        lowered.targetRateMax = 0.02e18;

        uint256 rate = _borrowRate(lowered, 10e18, 90e18);

        assertEq(module.lastUpdate().targetRate, 0.02e18);
        assertEq(rate, 0.02e18);
    }

    function test_borrowRate_RecordsUtilisationWithoutAdaptingWithinBlock() public {
        _borrowRate(_params(), 10e18, 90e18);

        uint256 rate = _borrowRate(_params(), 0, 100e18);

        AdaptiveCurveBorrowRate.TargetRateUpdate memory last = module.lastUpdate();
        assertEq(last.targetRate, INITIAL_TARGET_RATE);
        assertEq(last.utilisation, 1e18);
        assertEq(rate, 0.16e18);
    }

    function test_borrowRate_RevertsWhenCallerIsNotBorrowRateCaller() public {
        address caller = makeAddr("caller");
        bytes memory params = abi.encode(_params());

        vm.expectRevert(AdaptiveCurveBorrowRate.NotBorrowRateCaller.selector);
        vm.prank(caller);
        module.borrowRate(params, 10e18, 90e18, 0);
    }

    function test_borrowRate_RevertsWhenParamsCannotBeDecoded() public {
        vm.expectRevert();
        vm.prank(borrowRateCaller);
        module.borrowRate(new bytes(191), 10e18, 90e18, 0);
    }

    function test_borrowRate_RevertsWhenTotalLiquidityOverflows() public {
        bytes memory params = abi.encode(_params());

        vm.expectRevert(stdError.arithmeticError);
        vm.prank(borrowRateCaller);
        module.borrowRate(params, type(uint256).max, 1, 0);
    }

    // previewBorrowRate()

    function test_previewBorrowRate_ReturnsBorrowRateWithoutRecording() public {
        _borrowRate(_params(), 0, 100e18);
        uint256 recordedAt = vm.getBlockTimestamp();
        vm.warp(block.timestamp + 365 days);
        address caller = makeAddr("caller");
        bytes memory params = abi.encode(_params());

        vm.prank(caller);
        uint256 rate = module.previewBorrowRate(params, 0, 100e18, 0);

        // The target rate would clamp to the 200% maximum, quadrupled at full utilisation.
        assertEq(rate, 8e18);
        AdaptiveCurveBorrowRate.TargetRateUpdate memory last = module.lastUpdate();
        assertEq(last.targetRate, INITIAL_TARGET_RATE);
        assertEq(last.utilisation, 1e18);
        assertEq(last.timestamp, recordedAt);
    }

    function test_previewBorrowRate_RevertsWhenParamsCannotBeDecoded() public {
        vm.expectRevert();
        module.previewBorrowRate(new bytes(191), 10e18, 90e18, 0);
    }

    function test_previewBorrowRate_RevertsWhenTotalLiquidityOverflows() public {
        bytes memory params = abi.encode(_params());

        vm.expectRevert(stdError.arithmeticError);
        module.previewBorrowRate(params, type(uint256).max, 1, 0);
    }

    // isValid()

    function test_isValid_ReturnsTrueForValidParams() public view {
        assertTrue(module.isValid(abi.encode(_params())));
    }

    function test_isValid_ReturnsFalseWhenParamsAreEmpty() public view {
        assertFalse(module.isValid(""));
    }

    function test_isValid_ReturnsFalseWhenParamsLengthIsBelow192() public view {
        assertFalse(module.isValid(new bytes(191)));
    }

    function test_isValid_ReturnsFalseWhenParamsLengthIsAbove192() public view {
        assertFalse(module.isValid(new bytes(193)));
    }

    function test_isValid_ReturnsTrueWhenOptimalUtilisationIsLowest() public view {
        AdaptiveCurveBorrowRate.Params memory params = _params();
        params.optimalUtilisation = 1;

        assertTrue(module.isValid(abi.encode(params)));
    }

    function test_isValid_ReturnsFalseWhenOptimalUtilisationIsZero() public view {
        AdaptiveCurveBorrowRate.Params memory params = _params();
        params.optimalUtilisation = 0;

        assertFalse(module.isValid(abi.encode(params)));
    }

    function test_isValid_ReturnsTrueWhenOptimalUtilisationIsHighest() public view {
        AdaptiveCurveBorrowRate.Params memory params = _params();
        params.optimalUtilisation = 1e18 - 1;

        assertTrue(module.isValid(abi.encode(params)));
    }

    function test_isValid_ReturnsFalseWhenOptimalUtilisationIsFull() public view {
        AdaptiveCurveBorrowRate.Params memory params = _params();
        params.optimalUtilisation = 1e18;

        assertFalse(module.isValid(abi.encode(params)));
    }

    function test_isValid_ReturnsTrueWhenTargetRateMinIsLowest() public view {
        AdaptiveCurveBorrowRate.Params memory params = _params();
        params.targetRateMin = module.MIN_TARGET_RATE();

        assertTrue(module.isValid(abi.encode(params)));
    }

    function test_isValid_ReturnsFalseWhenTargetRateMinIsBelowLowest() public view {
        AdaptiveCurveBorrowRate.Params memory params = _params();
        params.targetRateMin = module.MIN_TARGET_RATE() - 1;

        assertFalse(module.isValid(abi.encode(params)));
    }

    function test_isValid_ReturnsTrueWhenTargetRateMinEqualsInitialTargetRate() public view {
        AdaptiveCurveBorrowRate.Params memory params = _params();
        params.targetRateMin = INITIAL_TARGET_RATE;

        assertTrue(module.isValid(abi.encode(params)));
    }

    function test_isValid_ReturnsFalseWhenTargetRateMinExceedsInitialTargetRate() public view {
        AdaptiveCurveBorrowRate.Params memory params = _params();
        params.targetRateMin = INITIAL_TARGET_RATE + 1;

        assertFalse(module.isValid(abi.encode(params)));
    }

    function test_isValid_ReturnsTrueWhenInitialTargetRateEqualsTargetRateMax() public view {
        AdaptiveCurveBorrowRate.Params memory params = _params();
        params.initialTargetRate = TARGET_RATE_MAX;

        assertTrue(module.isValid(abi.encode(params)));
    }

    function test_isValid_ReturnsFalseWhenInitialTargetRateExceedsTargetRateMax() public view {
        AdaptiveCurveBorrowRate.Params memory params = _params();
        params.initialTargetRate = TARGET_RATE_MAX + 1;

        assertFalse(module.isValid(abi.encode(params)));
    }

    function test_isValid_ReturnsTrueWhenCurveMultiplierIsLowest() public view {
        AdaptiveCurveBorrowRate.Params memory params = _params();
        params.curveMultiplier = module.MIN_CURVE_MULTIPLIER();

        assertTrue(module.isValid(abi.encode(params)));
    }

    function test_isValid_ReturnsFalseWhenCurveMultiplierIsBelowLowest() public view {
        AdaptiveCurveBorrowRate.Params memory params = _params();
        params.curveMultiplier = module.MIN_CURVE_MULTIPLIER() - 1;

        assertFalse(module.isValid(abi.encode(params)));
    }

    function test_isValid_ReturnsTrueWhenCurveMultiplierIsHighest() public view {
        // A 10% maximum target rate keeps the highest attainable borrow rate at 1,000%.
        AdaptiveCurveBorrowRate.Params memory params = _params();
        params.curveMultiplier = module.MAX_CURVE_MULTIPLIER();
        params.targetRateMax = 0.1e18;

        assertTrue(module.isValid(abi.encode(params)));
    }

    function test_isValid_ReturnsFalseWhenCurveMultiplierIsAboveHighest() public view {
        AdaptiveCurveBorrowRate.Params memory params = _params();
        params.curveMultiplier = module.MAX_CURVE_MULTIPLIER() + 1;
        params.targetRateMax = 0.09e18;

        assertFalse(module.isValid(abi.encode(params)));
    }

    function test_isValid_ReturnsTrueWhenAdjustmentSpeedIsLowest() public view {
        AdaptiveCurveBorrowRate.Params memory params = _params();
        params.adjustmentSpeed = module.MIN_ADJUSTMENT_SPEED();

        assertTrue(module.isValid(abi.encode(params)));
    }

    function test_isValid_ReturnsFalseWhenAdjustmentSpeedIsBelowLowest() public view {
        AdaptiveCurveBorrowRate.Params memory params = _params();
        params.adjustmentSpeed = module.MIN_ADJUSTMENT_SPEED() - 1;

        assertFalse(module.isValid(abi.encode(params)));
    }

    function test_isValid_ReturnsTrueWhenAdjustmentSpeedIsHighest() public view {
        AdaptiveCurveBorrowRate.Params memory params = _params();
        params.adjustmentSpeed = module.MAX_ADJUSTMENT_SPEED();

        assertTrue(module.isValid(abi.encode(params)));
    }

    function test_isValid_ReturnsFalseWhenAdjustmentSpeedIsAboveHighest() public view {
        AdaptiveCurveBorrowRate.Params memory params = _params();
        params.adjustmentSpeed = module.MAX_ADJUSTMENT_SPEED() + 1;

        assertFalse(module.isValid(abi.encode(params)));
    }

    function test_isValid_ReturnsTrueWhenHighestBorrowRateIsMaximum() public view {
        // A 250% maximum target rate quadrupled at full utilisation reaches exactly 1,000%.
        AdaptiveCurveBorrowRate.Params memory params = _params();
        params.targetRateMax = 2.5e18;

        assertTrue(module.isValid(abi.encode(params)));
    }

    function test_isValid_ReturnsFalseWhenHighestBorrowRateExceedsMaximum() public view {
        AdaptiveCurveBorrowRate.Params memory params = _params();
        params.targetRateMax = 2.5e18 + 1;

        assertFalse(module.isValid(abi.encode(params)));
    }

    function test_isValid_RevertsWhenHighestBorrowRateOverflows() public {
        AdaptiveCurveBorrowRate.Params memory params = _params();
        params.targetRateMax = type(uint256).max;

        vm.expectRevert(stdError.arithmeticError);
        module.isValid(abi.encode(params));
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(module.contractName(), "AdaptiveCurveBorrowRate");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(module.contractVersion(), "1.0.0");
    }

    // supportsInterface()

    function test_supportsInterface_BorrowRateModule_ReturnsTrue() public view {
        assertTrue(module.supportsInterface(type(IBorrowRateModule).interfaceId));
    }

    function test_supportsInterface_ValidatableModule_ReturnsTrue() public view {
        assertTrue(module.supportsInterface(type(IValidatableModule).interfaceId));
    }

    function test_supportsInterface_Versioned_ReturnsTrue() public view {
        assertTrue(module.supportsInterface(type(IVersioned).interfaceId));
    }

    function test_supportsInterface_ERC165_ReturnsTrue() public view {
        assertTrue(module.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_Unknown_ReturnsFalse() public view {
        assertFalse(module.supportsInterface(0xffffffff));
        assertFalse(module.supportsInterface(0xdeadbeef));
    }

    function _borrowRate(AdaptiveCurveBorrowRate.Params memory params, uint256 idleLiquidity, uint256 totalDebt)
        internal
        returns (uint256)
    {
        vm.prank(borrowRateCaller);
        return module.borrowRate(abi.encode(params), idleLiquidity, totalDebt, 0);
    }

    function _params() internal pure returns (AdaptiveCurveBorrowRate.Params memory) {
        return AdaptiveCurveBorrowRate.Params({
            optimalUtilisation: OPTIMAL_UTILISATION,
            initialTargetRate: INITIAL_TARGET_RATE,
            targetRateMin: TARGET_RATE_MIN,
            targetRateMax: TARGET_RATE_MAX,
            curveMultiplier: CURVE_MULTIPLIER,
            adjustmentSpeed: ADJUSTMENT_SPEED
        });
    }
}
