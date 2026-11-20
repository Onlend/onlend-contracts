// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {
    AccessControlEnumerableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "../../interfaces/IVersioned.sol";
import {IIRM} from "./interfaces/IIRM.sol";
import {CappedIRM} from "./abstract/CappedIRM.sol";
import {AlwaysApplicableCondition} from "./libraries/condition/AlwaysApplicableCondition.sol";
import {DoublePiecewiseLinearBorrowRate} from "./libraries/borrow-rate/DoublePiecewiseLinearBorrowRate.sol";
import {ExternalBorrowRate} from "./libraries/borrow-rate/ExternalBorrowRate.sol";
import {ExternalCondition} from "./libraries/condition/ExternalCondition.sol";
import {ExternalRetentionRate} from "./libraries/retention-rate/ExternalRetentionRate.sol";
import {FixedBorrowRate} from "./libraries/borrow-rate/FixedBorrowRate.sol";
import {FixedRetentionRate} from "./libraries/retention-rate/FixedRetentionRate.sol";
import {LinearBorrowRate} from "./libraries/borrow-rate/LinearBorrowRate.sol";
import {PiecewiseLinearBorrowRate} from "./libraries/borrow-rate/PiecewiseLinearBorrowRate.sol";
import {PowerBorrowRate} from "./libraries/borrow-rate/PowerBorrowRate.sol";
import {TokenBalanceCondition} from "./libraries/condition/TokenBalanceCondition.sol";
import {YieldTrackingBorrowRate} from "./libraries/borrow-rate/YieldTrackingBorrowRate.sol";

/// @title Composed Interest Rate Model
/// @notice Composes borrow rate, retention rate, and applicability condition modules into one IRM.
/// @dev    Inherits `CappedIRM`, so rates from every built-in or external module are capped before being returned to
///         consumers. Only the borrow rate caller set at initialisation can call `borrowRate`, since an external module
///         may update its state on that call. Module dispatch falls through to `EXTERNAL` without checking for it,
///         since ABI decoding rejects out-of-range enum values and every stored type has passed validation.
///         Implementation for EIP-1167 clones; configured via `initialize`, not a constructor.
contract ComposedIRM is CappedIRM, AccessControlEnumerableUpgradeable {
    /// @notice Supported borrow rate module types.
    enum BorrowRateType {
        FIXED,
        LINEAR,
        PIECEWISE_LINEAR,
        DOUBLE_PIECEWISE_LINEAR,
        POWER,
        YIELD_TRACKING,
        EXTERNAL
    }

    /// @notice Supported retention rate module types.
    enum RetentionRateType {
        FIXED,
        EXTERNAL
    }

    /// @notice Supported condition module types.
    enum ConditionType {
        ALWAYS_APPLICABLE,
        TOKEN_BALANCE,
        EXTERNAL
    }

    /// @notice Role allowed to update borrow rate configuration.
    bytes32 public constant BORROW_RATE_UPDATER_ROLE = keccak256("BORROW_RATE_UPDATER_ROLE");
    /// @notice Role allowed to update retention rate configuration.
    bytes32 public constant RETENTION_RATE_UPDATER_ROLE = keccak256("RETENTION_RATE_UPDATER_ROLE");
    /// @notice Role allowed to update condition configuration.
    bytes32 public constant CONDITION_UPDATER_ROLE = keccak256("CONDITION_UPDATER_ROLE");

    /// @notice Only account allowed to call `borrowRate`.
    address private _borrowRateCaller;

    /// @notice Current borrow rate module type.
    BorrowRateType private _borrowRateType;
    /// @notice Current retention rate module type.
    RetentionRateType private _retentionRateType;
    /// @notice Current condition module type.
    ConditionType private _conditionType;

    /// @notice Encoded parameters for the current borrow rate module.
    bytes private _borrowRateParams;
    /// @notice Encoded parameters for the current retention rate module.
    bytes private _retentionRateParams;
    /// @notice Encoded parameters for the current condition module.
    bytes private _conditionParams;

    /// @notice Emitted when the borrow rate module type and parameters are updated.
    /// @param oldBorrowRateType Previous borrow rate module type.
    /// @param oldParams Previous encoded borrow rate parameters.
    /// @param newBorrowRateType New borrow rate module type.
    /// @param newParams New encoded borrow rate parameters.
    event BorrowRateUpdated(
        BorrowRateType indexed oldBorrowRateType,
        bytes oldParams,
        BorrowRateType indexed newBorrowRateType,
        bytes newParams
    );
    /// @notice Emitted when the retention rate module type and parameters are updated.
    /// @param oldRetentionRateType Previous retention rate module type.
    /// @param oldParams Previous encoded retention rate parameters.
    /// @param newRetentionRateType New retention rate module type.
    /// @param newParams New encoded retention rate parameters.
    event RetentionRateUpdated(
        RetentionRateType indexed oldRetentionRateType,
        bytes oldParams,
        RetentionRateType indexed newRetentionRateType,
        bytes newParams
    );
    /// @notice Emitted when the condition module type and parameters are updated.
    /// @param oldConditionType Previous condition module type.
    /// @param oldParams Previous encoded condition parameters.
    /// @param newConditionType New condition module type.
    /// @param newParams New encoded condition parameters.
    event ConditionUpdated(
        ConditionType indexed oldConditionType, bytes oldParams, ConditionType indexed newConditionType, bytes newParams
    );

    /// @notice Reverts when borrow rate parameters are invalid for a module type.
    /// @param borrowRateType Borrow rate module type being validated.
    /// @param params Encoded borrow rate parameters.
    error InvalidBorrowRateParams(BorrowRateType borrowRateType, bytes params);
    /// @notice Reverts when retention rate parameters are invalid for a module type.
    /// @param retentionRateType Retention rate module type being validated.
    /// @param params Encoded retention rate parameters.
    error InvalidRetentionRateParams(RetentionRateType retentionRateType, bytes params);
    /// @notice Reverts when condition parameters are invalid for a module type.
    /// @param conditionType Condition module type being validated.
    /// @param params Encoded condition parameters.
    error InvalidConditionParams(ConditionType conditionType, bytes params);
    /// @notice Reverts when `borrowRate` is called by an account other than the borrow rate caller.
    error NotBorrowRateCaller();

    /// @notice Restricts a function to the borrow rate caller.
    modifier onlyBorrowRateCaller() {
        if (msg.sender != _borrowRateCaller) revert NotBorrowRateCaller();
        _;
    }

    /// @notice Locks the Implementation so it can never be initialized or used directly.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes a clone with its borrow rate caller, module types, parameters, and role members.
    /// @dev Callable once per clone.
    /// @param borrowRateCaller_ Only account allowed to call `borrowRate`.
    /// @param borrowRateType_ Initial borrow rate module type.
    /// @param borrowRateParams_ Initial encoded borrow rate parameters.
    /// @param retentionRateType_ Initial retention rate module type.
    /// @param retentionRateParams_ Initial encoded retention rate parameters.
    /// @param conditionType_ Initial condition module type.
    /// @param conditionParams_ Initial encoded condition parameters.
    /// @param defaultAdmin Initial default admin role member.
    /// @param borrowRateUpdater Initial borrow rate updater role member.
    /// @param retentionRateUpdater Initial retention rate updater role member.
    /// @param conditionUpdater Initial condition updater role member.
    function initialize(
        address borrowRateCaller_,
        BorrowRateType borrowRateType_,
        bytes calldata borrowRateParams_,
        RetentionRateType retentionRateType_,
        bytes calldata retentionRateParams_,
        ConditionType conditionType_,
        bytes calldata conditionParams_,
        address defaultAdmin,
        address borrowRateUpdater,
        address retentionRateUpdater,
        address conditionUpdater
    ) external initializer {
        __AccessControlEnumerable_init();

        _borrowRateCaller = borrowRateCaller_;

        _setBorrowRate(borrowRateType_, borrowRateParams_);
        _setRetentionRate(retentionRateType_, retentionRateParams_);
        _setCondition(conditionType_, conditionParams_);

        if (defaultAdmin != address(0)) _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        if (borrowRateUpdater != address(0)) _grantRole(BORROW_RATE_UPDATER_ROLE, borrowRateUpdater);
        if (retentionRateUpdater != address(0)) _grantRole(RETENTION_RATE_UPDATER_ROLE, retentionRateUpdater);
        if (conditionUpdater != address(0)) _grantRole(CONDITION_UPDATER_ROLE, conditionUpdater);
    }

    /// @notice Updates the borrow rate module type and parameters.
    /// @dev `newParams` must be valid for `newType`.
    /// @param newType New borrow rate module type.
    /// @param newParams New encoded borrow rate parameters.
    function setBorrowRate(BorrowRateType newType, bytes calldata newParams)
        external
        onlyRole(BORROW_RATE_UPDATER_ROLE)
    {
        _setBorrowRate(newType, newParams);
    }

    /// @notice Updates the retention rate module type and parameters.
    /// @dev `newParams` must be valid for `newType`.
    /// @param newType New retention rate module type.
    /// @param newParams New encoded retention rate parameters.
    function setRetentionRate(RetentionRateType newType, bytes calldata newParams)
        external
        onlyRole(RETENTION_RATE_UPDATER_ROLE)
    {
        _setRetentionRate(newType, newParams);
    }

    /// @notice Updates the condition module type and parameters.
    /// @dev `newParams` must be valid for `newType`.
    /// @param newType New condition module type.
    /// @param newParams New encoded condition parameters.
    function setCondition(ConditionType newType, bytes calldata newParams) external onlyRole(CONDITION_UPDATER_ROLE) {
        _setCondition(newType, newParams);
    }

    /// @inheritdoc IIRM
    function isApplicable(address account) external view override returns (bool) {
        return _isApplicable(account);
    }

    /// @notice Returns the only account allowed to call `borrowRate`.
    /// @return Borrow rate caller.
    function borrowRateCaller() external view returns (address) {
        return _borrowRateCaller;
    }

    /// @notice Returns the current borrow rate module type and parameters.
    /// @return type_ Current borrow rate module type.
    /// @return params Encoded parameters for the current borrow rate module.
    function borrowRateConfig() external view returns (BorrowRateType type_, bytes memory params) {
        return (_borrowRateType, _borrowRateParams);
    }

    /// @notice Returns the current retention rate module type and parameters.
    /// @return type_ Current retention rate module type.
    /// @return params Encoded parameters for the current retention rate module.
    function retentionRateConfig() external view returns (RetentionRateType type_, bytes memory params) {
        return (_retentionRateType, _retentionRateParams);
    }

    /// @notice Returns the current condition module type and parameters.
    /// @return type_ Current condition module type.
    /// @return params Encoded parameters for the current condition module.
    function conditionConfig() external view returns (ConditionType type_, bytes memory params) {
        return (_conditionType, _conditionParams);
    }

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "ComposedIRM";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    /// @notice Returns whether this contract supports an interface.
    /// @param interfaceId Interface identifier.
    /// @return True if `interfaceId` is supported.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(IERC165, AccessControlEnumerableUpgradeable)
        returns (bool)
    {
        return interfaceId == type(IIRM).interfaceId || interfaceId == type(IVersioned).interfaceId
            || super.supportsInterface(interfaceId);
    }

    function _setBorrowRate(BorrowRateType newType, bytes memory newParams) internal {
        if (!_isValidBorrowRateParams(newType, newParams)) revert InvalidBorrowRateParams(newType, newParams);

        BorrowRateType oldType = _borrowRateType;
        bytes memory oldParams = _borrowRateParams;
        _borrowRateType = newType;
        _borrowRateParams = newParams;

        emit BorrowRateUpdated(oldType, oldParams, newType, newParams);
    }

    function _setRetentionRate(RetentionRateType newType, bytes memory newParams) internal {
        if (!_isValidRetentionRateParams(newType, newParams)) revert InvalidRetentionRateParams(newType, newParams);

        RetentionRateType oldType = _retentionRateType;
        bytes memory oldParams = _retentionRateParams;
        _retentionRateType = newType;
        _retentionRateParams = newParams;

        emit RetentionRateUpdated(oldType, oldParams, newType, newParams);
    }

    function _setCondition(ConditionType newType, bytes memory newParams) internal {
        if (!_isValidConditionParams(newType, newParams)) revert InvalidConditionParams(newType, newParams);

        ConditionType oldType = _conditionType;
        bytes memory oldParams = _conditionParams;
        _conditionType = newType;
        _conditionParams = newParams;

        emit ConditionUpdated(oldType, oldParams, newType, newParams);
    }

    function _borrowRate(uint256 idleLiquidity, uint256 totalDebt, uint256 totalIrmDebt)
        internal
        override
        onlyBorrowRateCaller
        returns (uint256)
    {
        /// @dev Only an external module can keep state, so every other type returns its preview.
        if (_borrowRateType == BorrowRateType.EXTERNAL) {
            return ExternalBorrowRate.borrowRate(_borrowRateParams, idleLiquidity, totalDebt, totalIrmDebt);
        }
        return _previewBorrowRate(idleLiquidity, totalDebt, totalIrmDebt);
    }

    function _previewBorrowRate(uint256 idleLiquidity, uint256 totalDebt, uint256 totalIrmDebt)
        internal
        view
        override
        returns (uint256)
    {
        if (_borrowRateType == BorrowRateType.FIXED) {
            return FixedBorrowRate.borrowRate(_borrowRateParams, idleLiquidity, totalDebt, totalIrmDebt);
        }
        if (_borrowRateType == BorrowRateType.LINEAR) {
            return LinearBorrowRate.borrowRate(_borrowRateParams, idleLiquidity, totalDebt, totalIrmDebt);
        }
        if (_borrowRateType == BorrowRateType.PIECEWISE_LINEAR) {
            return PiecewiseLinearBorrowRate.borrowRate(_borrowRateParams, idleLiquidity, totalDebt, totalIrmDebt);
        }
        if (_borrowRateType == BorrowRateType.DOUBLE_PIECEWISE_LINEAR) {
            return DoublePiecewiseLinearBorrowRate.borrowRate(_borrowRateParams, idleLiquidity, totalDebt, totalIrmDebt);
        }
        if (_borrowRateType == BorrowRateType.POWER) {
            return PowerBorrowRate.borrowRate(_borrowRateParams, idleLiquidity, totalDebt, totalIrmDebt);
        }
        if (_borrowRateType == BorrowRateType.YIELD_TRACKING) {
            return YieldTrackingBorrowRate.borrowRate(_borrowRateParams, idleLiquidity, totalDebt, totalIrmDebt);
        }
        return ExternalBorrowRate.previewBorrowRate(_borrowRateParams, idleLiquidity, totalDebt, totalIrmDebt);
    }

    function _retentionRate(uint256 idleLiquidity, uint256 totalDebt, uint256 totalIrmDebt)
        internal
        view
        override
        returns (uint256)
    {
        if (_retentionRateType == RetentionRateType.FIXED) {
            return FixedRetentionRate.retentionRate(_retentionRateParams, idleLiquidity, totalDebt, totalIrmDebt);
        }
        return ExternalRetentionRate.retentionRate(_retentionRateParams, idleLiquidity, totalDebt, totalIrmDebt);
    }

    function _isValidBorrowRateParams(BorrowRateType type_, bytes memory params) private view returns (bool) {
        if (type_ == BorrowRateType.FIXED) return FixedBorrowRate.isValid(params);
        if (type_ == BorrowRateType.LINEAR) return LinearBorrowRate.isValid(params);
        if (type_ == BorrowRateType.PIECEWISE_LINEAR) return PiecewiseLinearBorrowRate.isValid(params);
        if (type_ == BorrowRateType.DOUBLE_PIECEWISE_LINEAR) return DoublePiecewiseLinearBorrowRate.isValid(params);
        if (type_ == BorrowRateType.POWER) return PowerBorrowRate.isValid(params);
        if (type_ == BorrowRateType.YIELD_TRACKING) return YieldTrackingBorrowRate.isValid(params);
        return ExternalBorrowRate.isValid(params);
    }

    function _isValidRetentionRateParams(RetentionRateType type_, bytes memory params) private view returns (bool) {
        if (type_ == RetentionRateType.FIXED) return FixedRetentionRate.isValid(params);
        return ExternalRetentionRate.isValid(params);
    }

    function _isValidConditionParams(ConditionType type_, bytes memory params) private view returns (bool) {
        if (type_ == ConditionType.ALWAYS_APPLICABLE) return AlwaysApplicableCondition.isValid(params);
        if (type_ == ConditionType.TOKEN_BALANCE) return TokenBalanceCondition.isValid(params);
        return ExternalCondition.isValid(params);
    }

    function _isApplicable(address account) private view returns (bool) {
        if (_conditionType == ConditionType.ALWAYS_APPLICABLE) {
            return AlwaysApplicableCondition.isApplicable(_conditionParams, account);
        }
        if (_conditionType == ConditionType.TOKEN_BALANCE) {
            return TokenBalanceCondition.isApplicable(_conditionParams, account);
        }
        return ExternalCondition.isApplicable(_conditionParams, account);
    }
}
