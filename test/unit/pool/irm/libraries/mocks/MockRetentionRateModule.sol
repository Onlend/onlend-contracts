// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IRetentionRateModule} from "src/pool/irm/interfaces/IRetentionRateModule.sol";
import {IValidatableModule} from "src/pool/irm/interfaces/IValidatableModule.sol";

contract MockRetentionRateModule is IRetentionRateModule {
    error ValidationReverted();
    error RetentionRateCalculationReverted();

    bool private _valid = true;
    bool private _supportsRetentionRateInterface = true;
    bool private _shouldRevertValidation;
    uint256 private _retentionRate;
    bool private _shouldRevertRetentionRateCalculation;

    function setValid(bool valid) external {
        _valid = valid;
    }

    function setSupportsRetentionRateInterface(bool supported) external {
        _supportsRetentionRateInterface = supported;
    }

    function setShouldRevertValidation(bool shouldRevert) external {
        _shouldRevertValidation = shouldRevert;
    }

    function setRetentionRate(uint256 retentionRate_) external {
        _retentionRate = retentionRate_;
    }

    function setShouldRevertRetentionRateCalculation(bool shouldRevert) external {
        _shouldRevertRetentionRateCalculation = shouldRevert;
    }

    function isValid(bytes calldata) external view override returns (bool) {
        if (_shouldRevertValidation) revert ValidationReverted();
        return _valid;
    }

    function retentionRate(bytes calldata, uint256, uint256, uint256) external view override returns (uint256) {
        if (_shouldRevertRetentionRateCalculation) revert RetentionRateCalculationReverted();
        return _retentionRate;
    }

    function supportsInterface(bytes4 interfaceId) external view override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IVersioned).interfaceId
            || interfaceId == type(IValidatableModule).interfaceId
            || (interfaceId == type(IRetentionRateModule).interfaceId && _supportsRetentionRateInterface);
    }

    function contractName() external pure override returns (string memory) {
        return "MockRetentionRateModule";
    }

    function contractVersion() external pure override returns (string memory) {
        return "1.0.0";
    }
}
