// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {ExternalBorrowRate} from "src/pool/irm/libraries/borrow-rate/ExternalBorrowRate.sol";
import {IRMConstants} from "src/pool/irm/libraries/IRMConstants.sol";
import {IBorrowRateModule} from "src/pool/irm/interfaces/IBorrowRateModule.sol";
import {IValidatableModule} from "src/pool/irm/interfaces/IValidatableModule.sol";
import {MockBorrowRateModule} from "../mocks/MockBorrowRateModule.sol";

contract ExternalBorrowRateUnitTest is Test {
    MockBorrowRateModule internal borrowRateModule;

    function setUp() public {
        borrowRateModule = new MockBorrowRateModule();
    }

    // isValid()

    function test_isValid_ReturnsTrueForSupportedModuleWithValidParams() public view {
        bytes memory externalModuleParams = abi.encode(uint256(7));

        bool valid = ExternalBorrowRate.isValid(_externalParams(address(borrowRateModule), externalModuleParams));

        assertTrue(valid);
    }

    function test_isValid_ReturnsTrueForMinimumLengthEncoding() public view {
        bytes memory minimumLengthParams = _externalParams(address(borrowRateModule), "");

        bool valid = ExternalBorrowRate.isValid(minimumLengthParams);

        assertTrue(valid);
    }

    function test_isValid_ForwardsExternalModuleParams() public {
        bytes memory externalModuleParams = abi.encode(uint256(7));

        vm.expectCall(address(borrowRateModule), abi.encodeCall(IValidatableModule.isValid, (externalModuleParams)));

        ExternalBorrowRate.isValid(_externalParams(address(borrowRateModule), externalModuleParams));
    }

    function test_isValid_ReturnsFalseWhenParamsAreEmpty() public view {
        assertFalse(ExternalBorrowRate.isValid(""));
    }

    function test_isValid_ReturnsFalseWhenParamsLengthIsBelowMinimum() public view {
        assertFalse(ExternalBorrowRate.isValid(new bytes(95)));
    }

    function test_isValid_ReturnsFalseWhenModuleDoesNotSupportBorrowRateInterface() public {
        borrowRateModule.setSupportsBorrowRateInterface(false);

        bool valid = ExternalBorrowRate.isValid(_externalParams(address(borrowRateModule), ""));

        assertFalse(valid);
    }

    function test_isValid_ReturnsFalseWhenExternalModuleRejectsParams() public {
        borrowRateModule.setValid(false);

        bool valid = ExternalBorrowRate.isValid(_externalParams(address(borrowRateModule), abi.encode(uint256(7))));

        assertFalse(valid);
    }

    function test_isValid_RevertsWhenParamsCannotBeDecoded() public {
        bytes memory malformedParams = _malformedExternalParams(address(borrowRateModule));

        vm.expectRevert();
        this.isValid(malformedParams);
    }

    function test_isValid_PropagatesExternalModuleRevert() public {
        borrowRateModule.setShouldRevertValidation(true);

        vm.expectRevert(MockBorrowRateModule.ValidationReverted.selector);
        this.isValid(_externalParams(address(borrowRateModule), abi.encode(uint256(7))));
    }

    // borrowRate()

    function test_borrowRate_ReturnsRateFromExternalModule() public {
        uint256 expectedBorrowRate = 0.1e18;
        borrowRateModule.setBorrowRate(expectedBorrowRate);
        borrowRateModule.setPreviewBorrowRate(0.2e18);

        uint256 actualBorrowRate = ExternalBorrowRate.borrowRate(
            _externalParams(address(borrowRateModule), abi.encode(uint256(7))), 100e18, 50e18, 25e18
        );

        assertEq(actualBorrowRate, expectedBorrowRate);
    }

    function test_borrowRate_ReturnsZeroWhenExternalModuleReturnsZero() public {
        uint256 actualBorrowRate =
            ExternalBorrowRate.borrowRate(_externalParams(address(borrowRateModule), ""), 0, 0, 0);

        assertEq(actualBorrowRate, 0);
    }

    function test_borrowRate_ReturnsRateForMinimumLengthEncoding() public {
        uint256 expectedBorrowRate = 0.1e18;
        borrowRateModule.setBorrowRate(expectedBorrowRate);

        uint256 actualBorrowRate =
            ExternalBorrowRate.borrowRate(_externalParams(address(borrowRateModule), ""), 100e18, 50e18, 25e18);

        assertEq(actualBorrowRate, expectedBorrowRate);
    }

    function test_borrowRate_ForwardsExternalModuleParamsAndPoolState() public {
        bytes memory externalModuleParams = abi.encode(uint256(7));
        uint256 idleLiquidity = 100e18;
        uint256 totalDebt = 50e18;
        uint256 totalIrmDebt = 25e18;

        vm.expectCall(
            address(borrowRateModule),
            abi.encodeCall(IBorrowRateModule.borrowRate, (externalModuleParams, idleLiquidity, totalDebt, totalIrmDebt))
        );

        ExternalBorrowRate.borrowRate(
            _externalParams(address(borrowRateModule), externalModuleParams), idleLiquidity, totalDebt, totalIrmDebt
        );
    }

    function test_borrowRate_ReturnsRateAboveProtocolMaximumUnchanged() public {
        uint256 externalModuleRate = IRMConstants.MAX_BORROW_RATE + 1;
        borrowRateModule.setBorrowRate(externalModuleRate);

        uint256 actualBorrowRate =
            ExternalBorrowRate.borrowRate(_externalParams(address(borrowRateModule), ""), 0, 0, 0);

        assertEq(actualBorrowRate, externalModuleRate);
    }

    function test_borrowRate_RevertsWhenParamsCannotBeDecoded() public {
        bytes memory malformedParams = _malformedExternalParams(address(borrowRateModule));

        vm.expectRevert();
        this.borrowRate(malformedParams, 100e18, 50e18, 25e18);
    }

    function test_borrowRate_PropagatesExternalModuleRevert() public {
        borrowRateModule.setShouldRevertBorrowRateCalculation(true);

        vm.expectRevert(MockBorrowRateModule.BorrowRateCalculationReverted.selector);
        this.borrowRate(_externalParams(address(borrowRateModule), abi.encode(uint256(7))), 100e18, 50e18, 25e18);
    }

    // previewBorrowRate()

    function test_previewBorrowRate_ReturnsPreviewFromExternalModule() public {
        uint256 expectedPreviewBorrowRate = 0.2e18;
        borrowRateModule.setBorrowRate(0.1e18);
        borrowRateModule.setPreviewBorrowRate(expectedPreviewBorrowRate);

        uint256 actualPreviewBorrowRate = ExternalBorrowRate.previewBorrowRate(
            _externalParams(address(borrowRateModule), abi.encode(uint256(7))), 100e18, 50e18, 25e18
        );

        assertEq(actualPreviewBorrowRate, expectedPreviewBorrowRate);
    }

    function test_previewBorrowRate_ForwardsExternalModuleParamsAndPoolState() public {
        bytes memory externalModuleParams = abi.encode(uint256(7));
        uint256 idleLiquidity = 100e18;
        uint256 totalDebt = 50e18;
        uint256 totalIrmDebt = 25e18;

        vm.expectCall(
            address(borrowRateModule),
            abi.encodeCall(
                IBorrowRateModule.previewBorrowRate, (externalModuleParams, idleLiquidity, totalDebt, totalIrmDebt)
            )
        );

        ExternalBorrowRate.previewBorrowRate(
            _externalParams(address(borrowRateModule), externalModuleParams), idleLiquidity, totalDebt, totalIrmDebt
        );
    }

    function test_previewBorrowRate_RevertsWhenParamsCannotBeDecoded() public {
        bytes memory malformedParams = _malformedExternalParams(address(borrowRateModule));

        vm.expectRevert();
        this.previewBorrowRate(malformedParams, 100e18, 50e18, 25e18);
    }

    function test_previewBorrowRate_PropagatesExternalModuleRevert() public {
        borrowRateModule.setShouldRevertBorrowRateCalculation(true);

        vm.expectRevert(MockBorrowRateModule.BorrowRateCalculationReverted.selector);
        this.previewBorrowRate(_externalParams(address(borrowRateModule), abi.encode(uint256(7))), 100e18, 50e18, 25e18);
    }

    function isValid(bytes calldata params) external view returns (bool) {
        return ExternalBorrowRate.isValid(params);
    }

    function borrowRate(bytes calldata params, uint256 idleLiquidity, uint256 totalDebt, uint256 totalIrmDebt)
        external
        returns (uint256)
    {
        return ExternalBorrowRate.borrowRate(params, idleLiquidity, totalDebt, totalIrmDebt);
    }

    function previewBorrowRate(bytes calldata params, uint256 idleLiquidity, uint256 totalDebt, uint256 totalIrmDebt)
        external
        view
        returns (uint256)
    {
        return ExternalBorrowRate.previewBorrowRate(params, idleLiquidity, totalDebt, totalIrmDebt);
    }

    function _externalParams(address module, bytes memory externalModuleParams) private pure returns (bytes memory) {
        return abi.encode(module, externalModuleParams);
    }

    function _malformedExternalParams(address module) private pure returns (bytes memory params) {
        params = _externalParams(module, "");
        assembly ("memory-safe") {
            mstore(add(params, 0x40), not(0))
        }
    }
}
