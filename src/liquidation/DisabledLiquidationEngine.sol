// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "../interfaces/IVersioned.sol";
import {ILendingCore} from "../lending-core/interfaces/ILendingCore.sol";
import {ILoanEvaluator} from "../loan/interfaces/ILoanEvaluator.sol";
import {ILiquidationEngine} from "./interfaces/ILiquidationEngine.sol";

/// @title DisabledLiquidationEngine
/// @notice Liquidation engine that disables liquidations entirely; every call to {liquidate} reverts.
/// @dev Set as the active engine on the lending core when liquidations must be turned off.
///      Implementation for EIP-1167 clones; configured via `initialize`, not a constructor.
contract DisabledLiquidationEngine is ILiquidationEngine, Initializable {
    /// @notice Thrown whenever a liquidation is attempted while liquidations are disabled.
    error LiquidationsDisabled();

    /// @notice Disables initialization on the implementation contract.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes a stateless clone.
    /// @dev Callable once per clone.
    function initialize() external initializer {}

    /// @inheritdoc ILiquidationEngine
    function liquidate(
        ILendingCore.Loan calldata,
        uint256,
        ILendingCore.LoanPosition[] calldata,
        ILendingCore.LoanPosition[] calldata,
        ILoanEvaluator
    ) external pure returns (ILendingCore.LoanPosition[] memory, ILendingCore.LoanPosition[] memory) {
        revert LiquidationsDisabled();
    }

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "DisabledLiquidationEngine";
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
}
