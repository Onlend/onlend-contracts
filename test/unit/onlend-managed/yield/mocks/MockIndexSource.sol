// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

contract MockIndexSource {
    error IndexReverted();

    uint256 private _index;
    bool private _shouldRevert;

    constructor(uint256 index_) {
        _index = index_;
    }

    function setIndex(uint256 index_) external {
        _index = index_;
    }

    function setShouldRevert(bool shouldRevert) external {
        _shouldRevert = shouldRevert;
    }

    function index() external view returns (uint256) {
        if (_shouldRevert) revert IndexReverted();
        return _index;
    }

    /// @dev Succeeds without return data, which does not decode as a `uint256`.
    function noReturn() external view {}
}
