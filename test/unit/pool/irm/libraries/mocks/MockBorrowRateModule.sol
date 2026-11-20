// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IBorrowRateModule} from "src/pool/irm/interfaces/IBorrowRateModule.sol";
import {IValidatableModule} from "src/pool/irm/interfaces/IValidatableModule.sol";

contract MockBorrowRateModule is IBorrowRateModule {
    error ValidationReverted();
    error BorrowRateCalculationReverted();

    bool private _valid = true;
    bool private _supportsBorrowRateInterface = true;
    bool private _shouldRevertValidation;
    uint256 private _borrowRate;
    uint256 private _previewBorrowRate;
    bool private _shouldRevertBorrowRateCalculation;

    function setValid(bool valid) external {
        _valid = valid;
    }

    function setSupportsBorrowRateInterface(bool supported) external {
        _supportsBorrowRateInterface = supported;
    }

    function setShouldRevertValidation(bool shouldRevert) external {
        _shouldRevertValidation = shouldRevert;
    }

    function setBorrowRate(uint256 borrowRate_) external {
        _borrowRate = borrowRate_;
    }

    function setPreviewBorrowRate(uint256 previewBorrowRate_) external {
        _previewBorrowRate = previewBorrowRate_;
    }

    function setShouldRevertBorrowRateCalculation(bool shouldRevert) external {
        _shouldRevertBorrowRateCalculation = shouldRevert;
    }

    function isValid(bytes calldata) external view override returns (bool) {
        if (_shouldRevertValidation) revert ValidationReverted();
        return _valid;
    }

    function borrowRate(bytes calldata, uint256, uint256, uint256) external view override returns (uint256) {
        if (_shouldRevertBorrowRateCalculation) revert BorrowRateCalculationReverted();
        return _borrowRate;
    }

    function previewBorrowRate(bytes calldata, uint256, uint256, uint256) external view override returns (uint256) {
        if (_shouldRevertBorrowRateCalculation) revert BorrowRateCalculationReverted();
        return _previewBorrowRate;
    }

    function supportsInterface(bytes4 interfaceId) external view override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IVersioned).interfaceId
            || interfaceId == type(IValidatableModule).interfaceId
            || (interfaceId == type(IBorrowRateModule).interfaceId && _supportsBorrowRateInterface);
    }

    function contractName() external pure override returns (string memory) {
        return "MockBorrowRateModule";
    }

    function contractVersion() external pure override returns (string memory) {
        return "1.0.0";
    }
}
