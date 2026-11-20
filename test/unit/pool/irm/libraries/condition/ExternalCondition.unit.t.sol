// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {ExternalCondition} from "src/pool/irm/libraries/condition/ExternalCondition.sol";
import {IConditionModule} from "src/pool/irm/interfaces/IConditionModule.sol";
import {IValidatableModule} from "src/pool/irm/interfaces/IValidatableModule.sol";
import {MockConditionModule} from "../mocks/MockConditionModule.sol";

contract ExternalConditionUnitTest is Test {
    MockConditionModule internal conditionModule;

    function setUp() public {
        conditionModule = new MockConditionModule();
    }

    // isValid()

    function test_isValid_ReturnsTrueForSupportedModuleWithValidParams() public view {
        bytes memory externalModuleParams = abi.encode(uint256(7));

        bool valid = ExternalCondition.isValid(_externalParams(address(conditionModule), externalModuleParams));

        assertTrue(valid);
    }

    function test_isValid_ReturnsTrueForMinimumLengthEncoding() public view {
        bytes memory minimumLengthParams = _externalParams(address(conditionModule), "");

        bool valid = ExternalCondition.isValid(minimumLengthParams);

        assertTrue(valid);
    }

    function test_isValid_ForwardsExternalModuleParams() public {
        bytes memory externalModuleParams = abi.encode(uint256(7));

        vm.expectCall(address(conditionModule), abi.encodeCall(IValidatableModule.isValid, (externalModuleParams)));

        ExternalCondition.isValid(_externalParams(address(conditionModule), externalModuleParams));
    }

    function test_isValid_ReturnsFalseWhenParamsAreEmpty() public view {
        assertFalse(ExternalCondition.isValid(""));
    }

    function test_isValid_ReturnsFalseWhenParamsLengthIsBelowMinimum() public view {
        assertFalse(ExternalCondition.isValid(new bytes(95)));
    }

    function test_isValid_ReturnsFalseWhenModuleDoesNotSupportConditionInterface() public {
        conditionModule.setSupportsConditionInterface(false);

        bool valid = ExternalCondition.isValid(_externalParams(address(conditionModule), ""));

        assertFalse(valid);
    }

    function test_isValid_ReturnsFalseWhenExternalModuleRejectsParams() public {
        conditionModule.setValid(false);

        bool valid = ExternalCondition.isValid(_externalParams(address(conditionModule), abi.encode(uint256(7))));

        assertFalse(valid);
    }

    function test_isValid_RevertsWhenParamsCannotBeDecoded() public {
        bytes memory malformedParams = _malformedExternalParams(address(conditionModule));

        vm.expectRevert();
        this.isValid(malformedParams);
    }

    function test_isValid_PropagatesExternalModuleRevert() public {
        conditionModule.setShouldRevertValidity(true);

        vm.expectRevert(MockConditionModule.ValidationReverted.selector);
        this.isValid(_externalParams(address(conditionModule), abi.encode(uint256(7))));
    }

    // isApplicable()

    function test_isApplicable_ReturnsTrueWhenExternalModuleApplies() public {
        conditionModule.setApplicable(true);

        bool applicable = ExternalCondition.isApplicable(
            _externalParams(address(conditionModule), abi.encode(uint256(7))), address(this)
        );

        assertTrue(applicable);
    }

    function test_isApplicable_ReturnsFalseWhenExternalModuleDoesNotApply() public view {
        bool applicable = ExternalCondition.isApplicable(
            _externalParams(address(conditionModule), abi.encode(uint256(7))), address(this)
        );

        assertFalse(applicable);
    }

    function test_isApplicable_ReturnsTrueForMinimumLengthEncoding() public {
        conditionModule.setApplicable(true);

        bool applicable = ExternalCondition.isApplicable(_externalParams(address(conditionModule), ""), address(this));

        assertTrue(applicable);
    }

    function test_isApplicable_ForwardsExternalModuleParamsAndAccount() public {
        bytes memory externalModuleParams = abi.encode(uint256(7));
        address account = makeAddr("account");

        vm.expectCall(
            address(conditionModule), abi.encodeCall(IConditionModule.isApplicable, (externalModuleParams, account))
        );

        ExternalCondition.isApplicable(_externalParams(address(conditionModule), externalModuleParams), account);
    }

    function test_isApplicable_RevertsWhenParamsCannotBeDecoded() public {
        bytes memory malformedParams = _malformedExternalParams(address(conditionModule));

        vm.expectRevert();
        this.isApplicable(malformedParams, address(this));
    }

    function test_isApplicable_PropagatesExternalModuleRevert() public {
        conditionModule.setShouldRevertApplicability(true);

        vm.expectRevert(MockConditionModule.ApplicabilityCheckReverted.selector);
        this.isApplicable(_externalParams(address(conditionModule), abi.encode(uint256(7))), address(this));
    }

    function isValid(bytes calldata params) external view returns (bool) {
        return ExternalCondition.isValid(params);
    }

    function isApplicable(bytes calldata params, address account) external view returns (bool) {
        return ExternalCondition.isApplicable(params, account);
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
