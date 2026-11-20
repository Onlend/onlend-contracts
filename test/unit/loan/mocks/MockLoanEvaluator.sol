// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "src/interfaces/IVersioned.sol";
import {ILendingCore} from "src/lending-core/interfaces/ILendingCore.sol";
import {ILoanEvaluator} from "src/loan/interfaces/ILoanEvaluator.sol";

contract MockLoanEvaluator is ILoanEvaluator {
    uint256 public health = type(uint256).max;
    bool public healthy = true;
    bool public liquidatable;

    function setHealth(uint256 health_) external {
        health = health_;
    }

    function setHealthy(bool healthy_) external {
        healthy = healthy_;
    }

    function setLiquidatable(bool liquidatable_) external {
        liquidatable = liquidatable_;
    }

    function getLoanHealth(ILendingCore.Loan calldata) external view returns (uint256) {
        return health;
    }

    function isLoanHealthy(ILendingCore.Loan calldata) external view returns (bool) {
        return healthy;
    }

    function isLoanLiquidatable(ILendingCore.Loan calldata) external view returns (bool, uint256) {
        return (liquidatable, health);
    }

    function contractName() external pure returns (string memory name_) {
        return "MockLoanEvaluator";
    }

    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(ILoanEvaluator).interfaceId || interfaceId == type(IVersioned).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }
}
