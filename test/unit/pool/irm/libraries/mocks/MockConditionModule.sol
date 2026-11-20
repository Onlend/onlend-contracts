// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IConditionModule} from "src/pool/irm/interfaces/IConditionModule.sol";
import {IValidatableModule} from "src/pool/irm/interfaces/IValidatableModule.sol";

contract MockConditionModule is IConditionModule {
    error ValidationReverted();
    error ApplicabilityCheckReverted();

    bool private _valid = true;
    bool private _supportsConditionInterface = true;
    bool private _shouldRevertValidity;
    bool private _applicable;
    bool private _shouldRevertApplicability;

    function setValid(bool valid) external {
        _valid = valid;
    }

    function setSupportsConditionInterface(bool supported) external {
        _supportsConditionInterface = supported;
    }

    function setShouldRevertValidity(bool shouldRevert) external {
        _shouldRevertValidity = shouldRevert;
    }

    function setApplicable(bool applicable) external {
        _applicable = applicable;
    }

    function setShouldRevertApplicability(bool shouldRevert) external {
        _shouldRevertApplicability = shouldRevert;
    }

    function isValid(bytes calldata) external view override returns (bool) {
        if (_shouldRevertValidity) revert ValidationReverted();
        return _valid;
    }

    function isApplicable(bytes calldata, address) external view override returns (bool) {
        if (_shouldRevertApplicability) revert ApplicabilityCheckReverted();
        return _applicable;
    }

    function supportsInterface(bytes4 interfaceId) external view override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IVersioned).interfaceId
            || interfaceId == type(IValidatableModule).interfaceId
            || (interfaceId == type(IConditionModule).interfaceId && _supportsConditionInterface);
    }

    function contractName() external pure override returns (string memory) {
        return "MockConditionModule";
    }

    function contractVersion() external pure override returns (string memory) {
        return "1.0.0";
    }
}
