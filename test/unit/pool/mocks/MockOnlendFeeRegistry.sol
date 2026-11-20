// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IOnlendFeeRegistry} from "src/pool/interfaces/IOnlendFeeRegistry.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";

contract MockOnlendFeeRegistry is IOnlendFeeRegistry {
    uint16 private _fixedFeeBps;
    uint16 private _splitFeeBps;
    address private _feeRecipient;
    bool private _supportsInterfaceOverride = true;

    constructor(address feeRecipient_) {
        _feeRecipient = feeRecipient_;
    }

    function setFeeConfig(uint16 fixedFeeBps, uint16 splitFeeBps) external {
        _fixedFeeBps = fixedFeeBps;
        _splitFeeBps = splitFeeBps;
    }

    function setFeeRecipient(address feeRecipient_) external {
        _feeRecipient = feeRecipient_;
    }

    /// @dev Set to false to make the registry fail the pool's interface validation.
    function setSupportsInterfaceOverride(bool value) external {
        _supportsInterfaceOverride = value;
    }

    /// @inheritdoc IOnlendFeeRegistry
    function feeConfig(address) external view override(IOnlendFeeRegistry) returns (uint16, uint16) {
        return (_fixedFeeBps, _splitFeeBps);
    }

    /// @inheritdoc IOnlendFeeRegistry
    function feeRecipient() external view override(IOnlendFeeRegistry) returns (address) {
        return _feeRecipient;
    }

    function contractName() external pure returns (string memory name_) {
        return "MockOnlendFeeRegistry";
    }

    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external view override(IERC165) returns (bool) {
        if (!_supportsInterfaceOverride) return false;
        return interfaceId == type(IOnlendFeeRegistry).interfaceId || interfaceId == type(IVersioned).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }
}
