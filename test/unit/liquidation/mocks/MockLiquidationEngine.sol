// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "src/interfaces/IVersioned.sol";
import {ILendingCore} from "src/lending-core/interfaces/ILendingCore.sol";
import {ILoanEvaluator} from "src/loan/interfaces/ILoanEvaluator.sol";
import {ILiquidationEngine} from "src/liquidation/interfaces/ILiquidationEngine.sol";

contract MockLiquidationEngine is ILiquidationEngine {
    ILendingCore.LoanPosition[] internal _colsToSeize;
    ILendingCore.LoanPosition[] internal _borsToRepay;

    event Liquidated(address account);

    function setColsToSeize(ILendingCore.LoanPosition[] calldata colsToSeize) external {
        _colsToSeize = colsToSeize;
    }

    function setBorsToRepay(ILendingCore.LoanPosition[] calldata borsToRepay) external {
        _borsToRepay = borsToRepay;
    }

    function liquidate(
        ILendingCore.Loan calldata loan,
        uint256,
        ILendingCore.LoanPosition[] calldata,
        ILendingCore.LoanPosition[] calldata,
        ILoanEvaluator
    )
        external
        returns (ILendingCore.LoanPosition[] memory colsToSeize, ILendingCore.LoanPosition[] memory borsToRepay)
    {
        emit Liquidated(loan.account);
        return (_colsToSeize, _borsToRepay);
    }

    function contractName() external pure returns (string memory name_) {
        return "MockLiquidationEngine";
    }

    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(ILiquidationEngine).interfaceId || interfaceId == type(IVersioned).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }
}
