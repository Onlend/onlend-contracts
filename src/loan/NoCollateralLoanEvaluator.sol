// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "../interfaces/IVersioned.sol";
import {ILendingCore} from "../lending-core/interfaces/ILendingCore.sol";
import {ILoanEvaluator} from "./interfaces/ILoanEvaluator.sol";

/// @title NoCollateralLoanEvaluator
/// @notice Loan evaluator that imposes no collateral requirements: every loan is treated as having maximal health,
///         always healthy and never liquidatable.
/// @dev Intended for lending apps where borrows are uncollateralised, so the loan's collateral and borrow are ignored
///      entirely.
///      Implementation for EIP-1167 clones; configured via `initialize`, not a constructor.
contract NoCollateralLoanEvaluator is ILoanEvaluator, Initializable {
    /// @notice Disables initialization on the implementation contract.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes a stateless clone.
    /// @dev Callable once per clone.
    function initialize() external initializer {}

    /// @inheritdoc ILoanEvaluator
    /// @return type(uint256).max, since the loan can never be undercollateralised.
    function getLoanHealth(ILendingCore.Loan calldata) external pure returns (uint256) {
        return type(uint256).max;
    }

    /// @inheritdoc ILoanEvaluator
    /// @return true always, since no collateral is required.
    function isLoanHealthy(ILendingCore.Loan calldata) external pure returns (bool) {
        return true;
    }

    /// @inheritdoc ILoanEvaluator
    /// @return liquidatable false always, since the loan can never become liquidatable.
    /// @return health type(uint256).max, since the loan can never be undercollateralised.
    function isLoanLiquidatable(ILendingCore.Loan calldata) external pure returns (bool liquidatable, uint256 health) {
        return (false, type(uint256).max);
    }

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "NoCollateralLoanEvaluator";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(ILoanEvaluator).interfaceId || interfaceId == type(IVersioned).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }
}
