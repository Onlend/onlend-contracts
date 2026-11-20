// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {ExternalRetentionRate} from "src/pool/irm/libraries/retention-rate/ExternalRetentionRate.sol";
import {IRMConstants} from "src/pool/irm/libraries/IRMConstants.sol";
import {IRetentionRateModule} from "src/pool/irm/interfaces/IRetentionRateModule.sol";
import {IValidatableModule} from "src/pool/irm/interfaces/IValidatableModule.sol";
import {MockRetentionRateModule} from "../mocks/MockRetentionRateModule.sol";

contract ExternalRetentionRateUnitTest is Test {
    MockRetentionRateModule internal retentionRateModule;

    function setUp() public {
        retentionRateModule = new MockRetentionRateModule();
    }

    // isValid()

    function test_isValid_ReturnsTrueForSupportedModuleWithValidParams() public view {
        bytes memory externalModuleParams = abi.encode(uint256(7));

        bool valid = ExternalRetentionRate.isValid(_externalParams(address(retentionRateModule), externalModuleParams));

        assertTrue(valid);
    }

    function test_isValid_ReturnsTrueForMinimumLengthEncoding() public view {
        bytes memory minimumLengthParams = _externalParams(address(retentionRateModule), "");

        bool valid = ExternalRetentionRate.isValid(minimumLengthParams);

        assertTrue(valid);
    }

    function test_isValid_ForwardsExternalModuleParams() public {
        bytes memory externalModuleParams = abi.encode(uint256(7));

        vm.expectCall(address(retentionRateModule), abi.encodeCall(IValidatableModule.isValid, (externalModuleParams)));

        ExternalRetentionRate.isValid(_externalParams(address(retentionRateModule), externalModuleParams));
    }

    function test_isValid_ReturnsFalseWhenParamsAreEmpty() public view {
        assertFalse(ExternalRetentionRate.isValid(""));
    }

    function test_isValid_ReturnsFalseWhenParamsLengthIsBelowMinimum() public view {
        assertFalse(ExternalRetentionRate.isValid(new bytes(95)));
    }

    function test_isValid_ReturnsFalseWhenModuleDoesNotSupportRetentionRateInterface() public {
        retentionRateModule.setSupportsRetentionRateInterface(false);

        bool valid = ExternalRetentionRate.isValid(_externalParams(address(retentionRateModule), ""));

        assertFalse(valid);
    }

    function test_isValid_ReturnsFalseWhenExternalModuleRejectsParams() public {
        retentionRateModule.setValid(false);

        bool valid =
            ExternalRetentionRate.isValid(_externalParams(address(retentionRateModule), abi.encode(uint256(7))));

        assertFalse(valid);
    }

    function test_isValid_RevertsWhenParamsCannotBeDecoded() public {
        bytes memory malformedParams = _malformedExternalParams(address(retentionRateModule));

        vm.expectRevert();
        this.isValid(malformedParams);
    }

    function test_isValid_PropagatesExternalModuleRevert() public {
        retentionRateModule.setShouldRevertValidation(true);

        vm.expectRevert(MockRetentionRateModule.ValidationReverted.selector);
        this.isValid(_externalParams(address(retentionRateModule), abi.encode(uint256(7))));
    }

    // retentionRate()

    function test_retentionRate_ReturnsRateFromExternalModule() public {
        uint256 expectedRetentionRate = 0.2e18;
        retentionRateModule.setRetentionRate(expectedRetentionRate);

        uint256 actualRetentionRate = ExternalRetentionRate.retentionRate(
            _externalParams(address(retentionRateModule), abi.encode(uint256(7))), 100e18, 50e18, 25e18
        );

        assertEq(actualRetentionRate, expectedRetentionRate);
    }

    function test_retentionRate_ReturnsZeroWhenExternalModuleReturnsZero() public view {
        uint256 actualRetentionRate =
            ExternalRetentionRate.retentionRate(_externalParams(address(retentionRateModule), ""), 0, 0, 0);

        assertEq(actualRetentionRate, 0);
    }

    function test_retentionRate_ReturnsRateForMinimumLengthEncoding() public {
        uint256 expectedRetentionRate = 0.2e18;
        retentionRateModule.setRetentionRate(expectedRetentionRate);

        uint256 actualRetentionRate = ExternalRetentionRate.retentionRate(
            _externalParams(address(retentionRateModule), ""), 100e18, 50e18, 25e18
        );

        assertEq(actualRetentionRate, expectedRetentionRate);
    }

    function test_retentionRate_ForwardsExternalModuleParamsAndPoolState() public {
        bytes memory externalModuleParams = abi.encode(uint256(7));
        uint256 idleLiquidity = 100e18;
        uint256 totalDebt = 50e18;
        uint256 totalIrmDebt = 25e18;

        vm.expectCall(
            address(retentionRateModule),
            abi.encodeCall(
                IRetentionRateModule.retentionRate, (externalModuleParams, idleLiquidity, totalDebt, totalIrmDebt)
            )
        );

        ExternalRetentionRate.retentionRate(
            _externalParams(address(retentionRateModule), externalModuleParams), idleLiquidity, totalDebt, totalIrmDebt
        );
    }

    function test_retentionRate_ReturnsRateAboveProtocolMaximumUnchanged() public {
        uint256 externalModuleRate = IRMConstants.MAX_RETENTION_RATE + 1;
        retentionRateModule.setRetentionRate(externalModuleRate);

        uint256 actualRetentionRate =
            ExternalRetentionRate.retentionRate(_externalParams(address(retentionRateModule), ""), 0, 0, 0);

        assertEq(actualRetentionRate, externalModuleRate);
    }

    function test_retentionRate_RevertsWhenParamsCannotBeDecoded() public {
        bytes memory malformedParams = _malformedExternalParams(address(retentionRateModule));

        vm.expectRevert();
        this.retentionRate(malformedParams, 100e18, 50e18, 25e18);
    }

    function test_retentionRate_PropagatesExternalModuleRevert() public {
        retentionRateModule.setShouldRevertRetentionRateCalculation(true);

        vm.expectRevert(MockRetentionRateModule.RetentionRateCalculationReverted.selector);
        this.retentionRate(_externalParams(address(retentionRateModule), abi.encode(uint256(7))), 100e18, 50e18, 25e18);
    }

    function isValid(bytes calldata params) external view returns (bool) {
        return ExternalRetentionRate.isValid(params);
    }

    function retentionRate(bytes calldata params, uint256 idleLiquidity, uint256 totalDebt, uint256 totalIrmDebt)
        external
        view
        returns (uint256)
    {
        return ExternalRetentionRate.retentionRate(params, idleLiquidity, totalDebt, totalIrmDebt);
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
