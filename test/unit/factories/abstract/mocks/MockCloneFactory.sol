// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {ICloneFactory} from "src/factories/interfaces/ICloneFactory.sol";

contract MockCloneFactory is ICloneFactory {
    address public immutable IMPLEMENTATION;

    address private _cloneReturn;
    address private _predictReturn;

    function setCloneReturn(address instance) external {
        _cloneReturn = instance;
    }

    function setPredictReturn(address predicted) external {
        _predictReturn = predicted;
    }

    function clone(bytes32 salt, bytes calldata) external returns (address instance) {
        instance = _cloneReturn;
        emit Cloned(instance, salt);
    }

    function predictAddress(address, bytes32) external view returns (address predicted) {
        return _predictReturn;
    }

    function contractName() external pure returns (string memory name_) {
        return "MockCloneFactory";
    }

    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }
}
