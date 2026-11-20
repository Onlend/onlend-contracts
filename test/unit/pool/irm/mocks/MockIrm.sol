// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IIRM} from "src/pool/irm/interfaces/IIRM.sol";

contract MockIrm is IIRM {
    bool private _isApplicable;
    uint256 private _borrowRate;
    uint256 private _retentionRate;

    constructor(bool isApplicable_, uint256 borrowRate_, uint256 retentionRate_) {
        _isApplicable = isApplicable_;
        _borrowRate = borrowRate_;
        _retentionRate = retentionRate_;
    }

    function setIsApplicable(bool isApplicable_) external {
        _isApplicable = isApplicable_;
    }

    function setBorrowRate(uint256 borrowRate_) external {
        _borrowRate = borrowRate_;
    }

    function setRetentionRate(uint256 retentionRate_) external {
        _retentionRate = retentionRate_;
    }

    function borrowRate(uint256, uint256, uint256) external view returns (uint256) {
        return _borrowRate;
    }

    function previewBorrowRate(uint256, uint256, uint256) external view returns (uint256) {
        return _borrowRate;
    }

    function retentionRate(uint256, uint256, uint256) external view returns (uint256) {
        return _retentionRate;
    }

    function isApplicable(address) external view returns (bool) {
        return _isApplicable;
    }

    function contractName() external pure returns (string memory) {
        return "MockIrm";
    }

    function contractVersion() external pure returns (string memory) {
        return "1.0.0";
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IIRM).interfaceId || interfaceId == type(IVersioned).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }
}
