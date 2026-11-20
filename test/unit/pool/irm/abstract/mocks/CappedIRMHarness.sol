// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "src/interfaces/IVersioned.sol";
import {CappedIRM} from "src/pool/irm/abstract/CappedIRM.sol";
import {IIRM} from "src/pool/irm/interfaces/IIRM.sol";

contract CappedIRMHarness is CappedIRM {
    uint256 private _uncappedBorrowRate;
    uint256 private _uncappedPreviewBorrowRate;
    uint256 private _uncappedRetentionRate;

    function setUncappedBorrowRate(uint256 uncappedBorrowRate) external {
        _uncappedBorrowRate = uncappedBorrowRate;
    }

    function setUncappedPreviewBorrowRate(uint256 uncappedPreviewBorrowRate) external {
        _uncappedPreviewBorrowRate = uncappedPreviewBorrowRate;
    }

    function setUncappedRetentionRate(uint256 uncappedRetentionRate) external {
        _uncappedRetentionRate = uncappedRetentionRate;
    }

    function isApplicable(address) external pure returns (bool) {
        return true;
    }

    function contractName() external pure returns (string memory) {
        return "CappedIRMHarness";
    }

    function contractVersion() external pure returns (string memory) {
        return "1.0.0";
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IIRM).interfaceId || interfaceId == type(IVersioned).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    function _borrowRate(uint256, uint256, uint256) internal view override returns (uint256) {
        return _uncappedBorrowRate;
    }

    function _previewBorrowRate(uint256, uint256, uint256) internal view override returns (uint256) {
        return _uncappedPreviewBorrowRate;
    }

    function _retentionRate(uint256, uint256, uint256) internal view override returns (uint256) {
        return _uncappedRetentionRate;
    }
}
