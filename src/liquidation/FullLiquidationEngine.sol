// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "../interfaces/IVersioned.sol";
import {ILendingCore} from "../lending-core/interfaces/ILendingCore.sol";
import {LoanPositionLib} from "../lib/LoanPositionLib.sol";
import {ILoanEvaluator} from "../loan/interfaces/ILoanEvaluator.sol";
import {IPool} from "../pool/interfaces/IPool.sol";
import {ILiquidationEngine} from "./interfaces/ILiquidationEngine.sol";

/// @title FullLiquidationEngine
/// @notice Liquidation engine that always closes the whole loan: every borrow is repaid in full and every collateral is
///         seized in full. There are no partial liquidations and no capped liquidation bonus, so the liquidator
///         receives whatever collateral remains in excess of the debt they repay.
/// @dev The engine performs no arithmetic; it validates the liquidator's requested amounts against the loan and then
///      returns the loan's positions unchanged. `reqCols` amounts are treated as minimums and `reqBors` amounts as
///      maximums, bounding what the liquidator receives and pays without requiring them to predict the loan exactly.
///      Implementation for EIP-1167 clones; configured via `initialize`, not a constructor.
contract FullLiquidationEngine is ILiquidationEngine, Initializable {
    using LoanPositionLib for ILendingCore.LoanPosition[];

    /// @notice Thrown when `reqCols` names the same pool more than once.
    error DuplicateRequestedCollateral();
    /// @notice Thrown when `reqBors` names the same pool more than once.
    error DuplicateRequestedBorrow();
    /// @notice Thrown when the loan holds less collateral than the liquidator requires to seize.
    /// @param pool The pool whose collateral falls short.
    /// @param minAmount The minimum amount the liquidator requested to seize.
    /// @param loanAmount The amount the loan actually holds, all of which would be seized.
    error InsufficientCollateral(IPool pool, uint256 minAmount, uint256 loanAmount);
    /// @notice Thrown when the loan holds a borrow the liquidator did not request to repay.
    /// @param pool The pool whose borrow was left out of `reqBors`.
    error BorrowNotRequested(IPool pool);
    /// @notice Thrown when the loan owes more than the liquidator is willing to repay.
    /// @param pool The pool whose debt exceeds the request.
    /// @param maxAmount The maximum amount the liquidator requested to repay.
    /// @param loanAmount The amount the loan actually owes, all of which would be repaid.
    error ExcessiveRepayment(IPool pool, uint256 maxAmount, uint256 loanAmount);

    /// @notice Disables initialization on the implementation contract.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes a stateless clone.
    /// @dev Callable once per clone.
    function initialize() external initializer {}

    /// @inheritdoc ILiquidationEngine
    /// @dev Seizes every collateral and repays every borrow the loan holds, so the returned positions are always the
    ///      loan's own. The loan evaluator is unused: the resulting loan is empty and therefore healthy under any
    ///      evaluator.
    ///
    ///      The two validations are deliberately one-sided rather than requiring `reqCols`/`reqBors` to mirror the loan
    ///      exactly, since the loan may change between the request being made and the liquidation landing. A loan that
    ///      gains a collateral or loses a borrow in the meantime only hands the liquidator more or asks less of them,
    ///      so neither change trips the rules below, whereas requiring an exact match would let anyone invalidate a
    ///      pending liquidation for dust. Losing collateral or gaining debt trips them wherever the liquidator would
    ///      then receive less than they asked for or repay more than they agreed to, including a borrow they did not
    ///      name.
    ///
    ///      A violator can still inflate the caller's gas by dusting collateral into pools the loan does not yet hold,
    ///      lengthening the seizure. That is bounded by the number of positions a loan can hold and every dusted wei is
    ///      handed to the liquidator, so it is accepted rather than defended against.
    function liquidate(
        ILendingCore.Loan calldata loan,
        uint256,
        ILendingCore.LoanPosition[] calldata reqCols,
        ILendingCore.LoanPosition[] calldata reqBors,
        ILoanEvaluator
    ) external pure returns (ILendingCore.LoanPosition[] memory, ILendingCore.LoanPosition[] memory) {
        _validateRequestedCollaterals(loan.collaterals, reqCols);
        _validateRequestedBorrows(loan.borrows, reqBors);

        return (loan.collaterals, loan.borrows);
    }

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "FullLiquidationEngine";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(ILiquidationEngine).interfaceId || interfaceId == type(IVersioned).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    /// @dev Checks each requested collateral against the loan, whose balance must cover the requested minimum. A
    ///      collateral the loan does not hold is treated as a position of zero, so only a minimum of zero may name it.
    ///      Collaterals the loan holds but the request omits are seized regardless: extra collateral only ever benefits
    ///      the liquidator, and leaving them out of the check is what stops a dust deposit from blocking the
    ///      liquidation.
    /// @param cols The loan's collateral positions.
    /// @param reqCols The requested collateral positions, whose amounts are minimums. Every amount is taken as is so a
    ///        request of `type(uint256).max` is just a minimum the loan cannot meet and reverts. The whole position is
    ///        seized either way, so a liquidator wanting all of it can simply request zero.
    function _validateRequestedCollaterals(
        ILendingCore.LoanPosition[] calldata cols,
        ILendingCore.LoanPosition[] calldata reqCols
    ) private pure {
        if (reqCols.hasDuplicatePool()) {
            revert DuplicateRequestedCollateral();
        }

        for (uint256 i; i < reqCols.length; ++i) {
            IPool pool = reqCols[i].pool;

            (bool found, uint256 index) = cols.findPosition(pool);
            uint256 colAmount = found ? cols[index].amount : 0;
            if (reqCols[i].amount > colAmount) revert InsufficientCollateral(pool, reqCols[i].amount, colAmount);
        }
    }

    /// @dev Checks each of the loan's borrows against the request. Every borrow the loan holds must be named, and the
    ///      request's maximum must cover what is owed. Requests naming a borrow the loan does not hold are ignored
    ///      rather than rejected: the position may have been repaid since the request was made, and ignoring it is what
    ///      stops a third-party repayment from blocking the liquidation.
    /// @param bors The loan's borrow positions.
    /// @param reqBors The requested borrow positions, whose amounts are maximums.
    function _validateRequestedBorrows(
        ILendingCore.LoanPosition[] calldata bors,
        ILendingCore.LoanPosition[] calldata reqBors
    ) private pure {
        if (reqBors.hasDuplicatePool()) revert DuplicateRequestedBorrow();

        for (uint256 i; i < bors.length; ++i) {
            IPool pool = bors[i].pool;

            (bool found, uint256 index) = reqBors.findPosition(pool);
            if (!found) revert BorrowNotRequested(pool);
            if (reqBors[index].amount < bors[i].amount) {
                revert ExcessiveRepayment(pool, reqBors[index].amount, bors[i].amount);
            }
        }
    }
}
