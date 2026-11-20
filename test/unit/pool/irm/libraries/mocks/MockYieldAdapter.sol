// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IYieldAdapter} from "src/pool/irm/interfaces/IYieldAdapter.sol";

contract MockYieldAdapter is IYieldAdapter {
    error IsValidWindowReverted();
    error AprReverted();

    bool private _validWindow = true;
    bool private _shouldRevertIsValidWindow;
    int256 private _apr;
    uint256 private _updatedAt;
    bool private _shouldRevertApr;
    bool private _supportsYieldAdapterInterface = true;

    function setValidWindow(bool validWindow) external {
        _validWindow = validWindow;
    }

    function setShouldRevertIsValidWindow(bool shouldRevert) external {
        _shouldRevertIsValidWindow = shouldRevert;
    }

    function setApr(int256 apr_, uint256 updatedAt) external {
        _apr = apr_;
        _updatedAt = updatedAt;
    }

    function setShouldRevertApr(bool shouldRevert) external {
        _shouldRevertApr = shouldRevert;
    }

    function setSupportsYieldAdapterInterface(bool supported) external {
        _supportsYieldAdapterInterface = supported;
    }

    function isValidWindow(uint256) external view override returns (bool) {
        if (_shouldRevertIsValidWindow) revert IsValidWindowReverted();
        return _validWindow;
    }

    function apr(uint256) external view override returns (int256, uint256) {
        if (_shouldRevertApr) revert AprReverted();
        return (_apr, _updatedAt);
    }

    function supportsInterface(bytes4 interfaceId) external view override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IVersioned).interfaceId
            || (interfaceId == type(IYieldAdapter).interfaceId && _supportsYieldAdapterInterface);
    }

    function contractName() external pure override returns (string memory) {
        return "MockYieldAdapter";
    }

    function contractVersion() external pure override returns (string memory) {
        return "1.0.0";
    }
}
