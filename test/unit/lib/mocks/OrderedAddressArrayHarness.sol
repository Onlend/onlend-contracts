// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {OrderedAddressArray} from "src/lib/OrderedAddressArray.sol";

contract OrderedAddressArrayHarness {
    using OrderedAddressArray for address[];

    address[] private _values;

    function insertAt(address value, uint256 index) external {
        _values.insertAt(value, index);
    }

    function removeAt(uint256 index) external returns (address removed) {
        return _values.removeAt(index);
    }

    function setValues(address[] calldata values_) external {
        _values = values_;
    }

    function indexOf(address value) external view returns (bool found, uint256 index) {
        return _values.indexOf(value);
    }

    function values() external view returns (address[] memory) {
        return _values;
    }

    function length() external view returns (uint256) {
        return _values.length;
    }
}
