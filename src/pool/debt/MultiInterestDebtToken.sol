// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {
    AccessControlEnumerableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "../../interfaces/IVersioned.sol";
import {MathUtils} from "../../lib/MathUtils.sol";
import {OrderedAddressArray} from "../../lib/OrderedAddressArray.sol";
import {IIRM} from "../irm/interfaces/IIRM.sol";
import {InterestMath} from "../lib/InterestMath.sol";
import {DebtToken} from "./abstract/DebtToken.sol";
import {IDebtToken} from "./interfaces/IDebtToken.sol";

/// @title  MultiInterestDebtToken
/// @notice Debt token whose interest accrues through a set of interest rate models (IRMs), assigning each account to a
///         single IRM and tracking its debt against that IRM's compounding borrow index.
/// @dev    Each account holding debt is assigned to exactly one IRM, so instead of tracking per-loan rates the token
///         aggregates debt into per-IRM buckets — this keeps deposit-rate accrual O(#IRMs) rather than O(#loans).
///
///         Every supported IRM lives in `_supportedIrmIds`, which is what accounting iterates — deprecated IRMs keep
///         accruing. Active IRMs additionally live in `_activeIrmIds` ordered by priority (lower index = higher
///         priority), which is the assignment rule: an account is placed in the highest-priority active IRM whose
///         account-condition it meets. Each `IrmData` carries its own compounding borrow index, borrow rate and
///         retention rate, plus an aggregate `totalScaledDebt`.
///
///         Debt is stored scaled by the assigned IRM's borrow index — the inherited `ERC20` balance holds an account's
///         scaled debt, not the debt it owes — so interest accrues through the index alone and no stored balance is
///         rewritten as it accrues. A bucket's `totalScaledDebt` therefore stays exactly equal to the sum of its
///         accounts' scaled balances, because both sides only ever move by the same integer. `Transfer` events carry
///         the same scaled amounts, so they add up to `scaledBalanceOf` rather than `balanceOf`.
///         Implementation for EIP-1167 clones; configured via `initialize`, not a constructor.
contract MultiInterestDebtToken is DebtToken, AccessControlEnumerableUpgradeable {
    using OrderedAddressArray for address[];

    /// @notice Lifecycle status for an IRM.
    enum IrmStatus {
        NONE,
        ACTIVE,
        DEPRECATED
    }

    /// @notice Accounting data for a supported IRM.
    struct IrmData {
        /// @notice IRM lifecycle status.
        IrmStatus status;
        /// @notice Borrow index as of the last update, scaled to 18dp; see `updatedBorrowIndex` for the current value.
        uint256 storedBorrowIndex;
        /// @notice Current borrow rate for this IRM, scaled to 18dp.
        uint256 borrowRate;
        /// @notice Current retention rate for this IRM, scaled to 18dp.
        uint256 retentionRate;
        /// @notice Total scaled debt assigned to this IRM, equal to the sum of its accounts' scaled balances.
        uint256 totalScaledDebt;
    }

    /// @notice Role allowed to add, deprecate, undeprecate and reorder IRMs.
    bytes32 public constant IRM_UPDATER_ROLE = keccak256("IRM_UPDATER_ROLE");
    /// @notice Maximum number of active IRMs that can be checked when assigning accounts.
    uint256 public constant MAX_ACTIVE_IRMS = 32;
    /// @notice Maximum number of supported IRMs that can be accounted for, including deprecated IRMs.
    uint256 public constant MAX_SUPPORTED_IRMS = 64;

    /// @notice Timestamp when borrow indexes were last updated.
    uint256 internal _lastUpdateTs;
    /// @notice Active IRMs ordered by priority.
    address[] internal _activeIrmIds;
    /// @notice All supported IRMs, active and deprecated, in the order they were added.
    address[] internal _supportedIrmIds;
    /// @notice Accounting data of each supported IRM, keyed by IRM address.
    mapping(address irmId => IrmData) internal _irmData;
    /// @notice IRM each account is currently assigned to.
    mapping(address account => address irmId) internal _accountIrmId;

    /// @notice Emitted when an IRM is added.
    /// @param  irm      Added IRM address.
    /// @param  priority Priority where the IRM was inserted.
    event IrmAdded(address indexed irm, uint8 priority);
    /// @notice Emitted when an IRM is deprecated.
    /// @param  irm Deprecated IRM address.
    event IrmDeprecated(address indexed irm);
    /// @notice Emitted when an IRM is undeprecated.
    /// @param  irm      Undeprecated IRM address.
    /// @param  priority Priority where the IRM was inserted.
    event IrmUndeprecated(address indexed irm, uint8 priority);
    /// @notice Emitted when an IRM is removed.
    /// @param  irm Removed IRM address.
    event IrmRemoved(address indexed irm);
    /// @notice Emitted when active IRM priorities are updated.
    /// @param  irmIds Active IRM ids ordered by priority.
    event IrmPrioritiesUpdated(address[] irmIds);
    /// @notice Emitted when an IRM's borrow and retention rates are recomputed.
    /// @dev    Emitted for every supported IRM, deprecated ones included, on each `updateBorrowRates`.
    /// @param  irm           IRM address.
    /// @param  borrowIndex   Borrow index the new rates accrue from, scaled to 18dp.
    /// @param  borrowRate    New borrow rate, scaled to 18dp.
    /// @param  retentionRate New retention rate, scaled to 18dp.
    event IrmRatesUpdated(address indexed irm, uint256 borrowIndex, uint256 borrowRate, uint256 retentionRate);
    /// @notice Emitted when an account is assigned an IRM, moved from one IRM to another along with its debt, or
    ///         unassigned on repaying all of its debt.
    /// @param  account Account whose assignment changed.
    /// @param  oldIrm  IRM the account was assigned to, or the zero address if it was unassigned.
    /// @param  newIrm  IRM the account is now assigned to, or the zero address if it is now unassigned.
    event AccountIrmAssigned(address indexed account, address indexed oldIrm, address indexed newIrm);

    /// @notice Reverts when an IRM is not supported.
    /// @param  irm IRM address that is not supported.
    error IrmNotSupported(address irm);
    /// @notice Reverts when an IRM does not support `IIRM`.
    /// @param  irm Invalid IRM address.
    error InvalidIrm(address irm);
    /// @notice Reverts when an IRM is already registered.
    /// @param  irm Existing IRM address.
    error IrmAlreadyAdded(address irm);
    /// @notice Reverts when the IRM priority is out of bounds.
    /// @param  priority Invalid priority.
    error InvalidIrmPriority(uint8 priority);
    /// @notice Reverts when an operation would exceed the active IRM limit.
    error MaxActiveIrmsReached();
    /// @notice Reverts when adding an IRM would exceed the supported IRM limit.
    error MaxSupportedIrmsReached();
    /// @notice Reverts when an operation requires an active IRM.
    /// @param  irm IRM address that is not active.
    error IrmNotActive(address irm);
    /// @notice Reverts when an operation requires a deprecated IRM.
    /// @param  irm IRM address that is not deprecated.
    error IrmNotDeprecated(address irm);
    /// @notice Reverts when removing an IRM which still holds debt.
    /// @param  irm IRM address holding debt.
    error IrmHasDebt(address irm);
    /// @notice Reverts when a priorities update does not include exactly all active IRMs.
    /// @param  length         Provided IRM ids length.
    /// @param  expectedLength Expected active IRM ids length.
    error InvalidIrmPrioritiesLength(uint256 length, uint256 expectedLength);
    /// @notice Reverts when a priorities update includes the same IRM more than once.
    /// @param  irm Duplicate IRM address.
    error DuplicateIrm(address irm);
    /// @notice Reverts when an operation requires borrow indexes accrued to the current block and they are not.
    error BorrowIndexesStale();
    /// @notice Reverts when no active IRM is applicable to an account.
    error NoApplicableIrmFound();

    /// @notice Locks the Implementation so it can never be initialized or used directly.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes a multi-interest debt token clone.
    /// @dev Callable once per clone.
    /// @param  pool_        Pool contract authorised to manage debt.
    /// @param  name_        Debt token name.
    /// @param  symbol_      Debt token symbol.
    /// @param  decimals_    Decimals to report, matching the underlying asset.
    /// @param  defaultAdmin Initial default admin role member.
    /// @param  irmUpdater   Initial IRM updater role member.
    /// @param  irmIds       Initial active IRM ids ordered by priority.
    function initialize(
        address pool_,
        string calldata name_,
        string calldata symbol_,
        uint8 decimals_,
        address defaultAdmin,
        address irmUpdater,
        address[] calldata irmIds
    ) external initializer {
        _initializeDebtToken(pool_, name_, symbol_, decimals_);
        __AccessControlEnumerable_init();

        if (defaultAdmin != address(0)) _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        if (irmUpdater != address(0)) _grantRole(IRM_UPDATER_ROLE, irmUpdater);

        for (uint8 priority; priority < irmIds.length; priority++) {
            _addIrm(irmIds[priority], priority);
        }

        _lastUpdateTs = block.timestamp;
    }

    /// @notice Adds an IRM at a priority.
    /// @dev    Lower priorities are evaluated first. Inserting at `priority` places `irm` at that priority and shifts
    ///         the existing IRMs at `priority` and below one position to the right.
    /// @param  irmId    IRM address to add.
    /// @param  priority Priority where the IRM should be inserted.
    function addIrm(address irmId, uint8 priority) external onlyRole(IRM_UPDATER_ROLE) {
        _addIrm(irmId, priority);
    }

    /// @notice Deprecates an IRM so it can no longer be assigned to accounts.
    /// @dev    Deprecated IRMs keep their accounting data for existing accounts.
    /// @param  irmId IRM address to deprecate.
    function deprecateIrm(address irmId) external onlyRole(IRM_UPDATER_ROLE) {
        _requireIrmSupported(irmId);

        (bool found, uint256 index) = _activeIrmIds.indexOf(irmId);
        if (!found) revert IrmNotActive(irmId);

        _activeIrmIds.removeAt(index);
        _irmData[irmId].status = IrmStatus.DEPRECATED;

        emit IrmDeprecated(irmId);
    }

    /// @notice Undeprecates an IRM so it can be assigned to accounts again.
    /// @dev    Inserting at `priority` places `irm` at that priority and shifts the existing active IRMs at `priority`
    ///         and below one position to the right.
    /// @param  irmId    IRM address to undeprecate.
    /// @param  priority Priority where the IRM should be inserted.
    function undeprecateIrm(address irmId, uint8 priority) external onlyRole(IRM_UPDATER_ROLE) {
        _requireIrmSupported(irmId);
        if (_irmData[irmId].status != IrmStatus.DEPRECATED) revert IrmNotDeprecated(irmId);
        if (priority > _activeIrmIds.length) revert InvalidIrmPriority(priority);
        if (_activeIrmIds.length >= MAX_ACTIVE_IRMS) revert MaxActiveIrmsReached();

        _activeIrmIds.insertAt(irmId, priority);
        _irmData[irmId].status = IrmStatus.ACTIVE;

        emit IrmUndeprecated(irmId, priority);
    }

    /// @notice Removes an IRM which holds no debt, so it is no longer accounted for.
    /// @dev    Active and deprecated IRMs can both be removed. An IRM holding no debt has no accounts assigned to it,
    ///         so removing it leaves none pointing at a removed IRM. Re-adding `irmId` later starts it again from a
    ///         fresh borrow index.
    /// @param  irmId IRM address to remove.
    function removeIrm(address irmId) external onlyRole(IRM_UPDATER_ROLE) {
        _requireIrmSupported(irmId);
        if (_irmData[irmId].totalScaledDebt != 0) revert IrmHasDebt(irmId);

        (bool isActive, uint256 activeIndex) = _activeIrmIds.indexOf(irmId);
        if (isActive) _activeIrmIds.removeAt(activeIndex);

        (, uint256 supportedIndex) = _supportedIrmIds.indexOf(irmId);
        _supportedIrmIds.removeAt(supportedIndex);

        delete _irmData[irmId];

        emit IrmRemoved(irmId);
    }

    /// @notice Reorders all active IRMs in a single call.
    /// @dev    `newActiveIrmIds` must include each active IRM exactly once. Deprecated IRMs are not affected.
    /// @param  newActiveIrmIds Active IRM ids ordered by priority.
    function setIrmPriorities(address[] calldata newActiveIrmIds) external onlyRole(IRM_UPDATER_ROLE) {
        uint256 length = _activeIrmIds.length;
        if (newActiveIrmIds.length != length) revert InvalidIrmPrioritiesLength(newActiveIrmIds.length, length);

        for (uint256 i; i < length; i++) {
            address irmId = newActiveIrmIds[i];
            if (_irmData[irmId].status != IrmStatus.ACTIVE) revert IrmNotActive(irmId);

            for (uint256 j = i + 1; j < length; j++) {
                if (irmId == newActiveIrmIds[j]) revert DuplicateIrm(irmId);
            }

            _activeIrmIds[i] = irmId;
        }

        emit IrmPrioritiesUpdated(newActiveIrmIds);
    }

    /// @notice Returns the timestamp when borrow indexes were last updated.
    /// @return Timestamp of the last borrow index update.
    function lastUpdateTs() external view returns (uint256) {
        return _lastUpdateTs;
    }

    /// @inheritdoc IDebtToken
    /// @dev    Sums the interest and retention each supported IRM has accrued since `_lastUpdateTs`. Returns early once
    ///         indexes are fresh: no IRM can have accrued over a zero-length period.
    function pendingInterest() external view override(IDebtToken) returns (uint256 accrued, uint256 retained) {
        // Exact equality checks same-block synchronization, regardless of the timestamp chosen.
        // forge-lint: disable-next-line(block-timestamp)
        if (_lastUpdateTs == block.timestamp) return (0, 0);

        for (uint256 i; i < _supportedIrmIds.length; i++) {
            (uint256 irmAccrued, uint256 irmRetained) = _pendingIrmInterest(_supportedIrmIds[i]);
            accrued += irmAccrued;
            retained += irmRetained;
        }
    }

    /// @inheritdoc IDebtToken
    /// @dev    Sums what each supported IRM's debt generates at its stored rates, so deprecated IRMs contribute for as
    ///         long as they carry debt.
    function annualInterest() external view override(IDebtToken) returns (uint256 interest, uint256 retained) {
        for (uint256 i; i < _supportedIrmIds.length; i++) {
            address irmId = _supportedIrmIds[i];
            IrmData storage irmData = _irmData[irmId];

            uint256 irmInterest = InterestMath.calcAnnualInterest(updatedTotalDebt(irmId), irmData.borrowRate);
            interest += irmInterest;
            retained += InterestMath.calcRetained(irmInterest, irmData.retentionRate);
        }
    }

    /// @notice Returns all active IRM ids ordered by priority.
    /// @return activeIrmIds Active IRM ids.
    function getActiveIrmIds() external view returns (address[] memory activeIrmIds) {
        return _activeIrmIds;
    }

    /// @notice Returns all deprecated IRM ids.
    /// @dev    Filtered out of the supported IRM ids, so these are ordered by when each IRM was added, not by when it
    ///         was deprecated.
    /// @return deprecatedIrmIds Deprecated IRM ids.
    function getDeprecatedIrmIds() external view returns (address[] memory deprecatedIrmIds) {
        uint256 length = _supportedIrmIds.length;

        /// @dev Every supported IRM is either active or deprecated, so the active ones account for the whole remainder.
        deprecatedIrmIds = new address[](length - _activeIrmIds.length);

        uint256 count;
        for (uint256 i; i < length; i++) {
            address irmId = _supportedIrmIds[i];
            if (_irmData[irmId].status == IrmStatus.DEPRECATED) deprecatedIrmIds[count++] = irmId;
        }
    }

    /// @notice Returns all supported IRM ids, active and deprecated, in the order they were added.
    /// @return supportedIrmIds Supported IRM ids.
    function getSupportedIrmIds() external view returns (address[] memory supportedIrmIds) {
        return _supportedIrmIds;
    }

    /// @notice Returns accounting data for an IRM.
    /// @param  irmId IRM address.
    /// @return Accounting data for `irmId`.
    function getIrmData(address irmId) external view returns (IrmData memory) {
        return _irmData[irmId];
    }

    /// @notice Returns the IRM an account is currently assigned to.
    /// @dev    Zero if the account holds no debt.
    /// @param  account Account to query.
    /// @return IRM address `account` is assigned to.
    function accountIrmId(address account) external view returns (address) {
        return _accountIrmId[account];
    }

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory name_) {
        return "MultiInterestDebtToken";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    /// @notice Returns whether an IRM is supported, i.e. active or deprecated.
    /// @param  irmId IRM address.
    /// @return True if `irmId` is supported.
    function isIrmSupported(address irmId) public view returns (bool) {
        return _irmData[irmId].status != IrmStatus.NONE;
    }

    /// @notice Returns the highest-priority active IRM applicable to an account.
    /// @dev    Reverts with `NoApplicableIrmFound` if no active IRM applies to `account`.
    /// @param  account Account to resolve an IRM for.
    /// @return IRM address applicable to `account`.
    function findIrmForAccount(address account) public view returns (address) {
        (bool found, address irmId) = _tryFindIrmForAccount(account);
        if (found) return irmId;
        revert NoApplicableIrmFound();
    }

    /// @notice Returns an account's debt balance including interest accrued to the current block.
    /// @param  account Account to query.
    /// @return Current debt balance of `account`.
    function balanceOf(address account) public view override(IERC20, ERC20Upgradeable) returns (uint256) {
        /// @dev An account holding no debt has no IRM assigned, so has no borrow index to state it at.
        uint256 scaledBalance = scaledBalanceOf(account);
        if (scaledBalance == 0) return 0;

        /// @dev State the account's scaled debt at the IRM's current borrow index to reflect interest accrued.
        return InterestMath.toActualDebt(scaledBalance, updatedBorrowIndex(_accountIrmId[account]));
    }

    /// @notice Returns an account's scaled debt, i.e. its debt normalised by the borrow index of its assigned IRM.
    /// @dev    Unlike `balanceOf` this does not grow as interest accrues; it only changes when debt is minted, burned
    ///         or moved to another IRM.
    /// @param  account Account to query.
    /// @return Scaled debt of `account`.
    function scaledBalanceOf(address account) public view returns (uint256) {
        return ERC20Upgradeable.balanceOf(account);
    }

    /// @notice Returns the total outstanding debt across all IRMs including interest accrued to the current block.
    /// @return totalDebt Current total debt.
    function totalSupply() public view override(IERC20, ERC20Upgradeable) returns (uint256 totalDebt) {
        for (uint256 i; i < _supportedIrmIds.length; i++) {
            totalDebt += updatedTotalDebt(_supportedIrmIds[i]);
        }
    }

    /// @notice Returns an IRM's borrow index including interest accrued to the current block.
    /// @param  irmId IRM address.
    /// @return Current borrow index.
    function updatedBorrowIndex(address irmId) public view returns (uint256) {
        _requireIrmSupported(irmId);
        IrmData storage irmData = _irmData[irmId];
        return
            InterestMath.calcBorrowIndex(irmData.storedBorrowIndex, irmData.borrowRate, block.timestamp - _lastUpdateTs);
    }

    /// @notice Returns an IRM's total outstanding debt including interest accrued to the current block.
    /// @param  irmId IRM address.
    /// @return Current total debt.
    function updatedTotalDebt(address irmId) public view returns (uint256) {
        _requireIrmSupported(irmId);
        return InterestMath.toActualDebt(_irmData[irmId].totalScaledDebt, updatedBorrowIndex(irmId));
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(DebtToken, AccessControlEnumerableUpgradeable)
        returns (bool)
    {
        return DebtToken.supportsInterface(interfaceId)
            || AccessControlEnumerableUpgradeable.supportsInterface(interfaceId);
    }

    function _addIrm(address irmId, uint8 priority) internal {
        if (!ERC165Checker.supportsInterface(irmId, type(IIRM).interfaceId)) revert InvalidIrm(irmId);
        if (isIrmSupported(irmId)) revert IrmAlreadyAdded(irmId);
        if (priority > _activeIrmIds.length) revert InvalidIrmPriority(priority);
        if (_activeIrmIds.length >= MAX_ACTIVE_IRMS) revert MaxActiveIrmsReached();
        if (_supportedIrmIds.length >= MAX_SUPPORTED_IRMS) revert MaxSupportedIrmsReached();

        _irmData[irmId] = IrmData({
            status: IrmStatus.ACTIVE,
            storedBorrowIndex: MathUtils.ONE_18_DP,
            borrowRate: 0,
            retentionRate: 0,
            totalScaledDebt: 0
        });
        _activeIrmIds.insertAt(irmId, priority);
        _supportedIrmIds.push(irmId);

        emit IrmAdded(irmId, priority);
    }

    /// @dev Moves `account`'s debt into the highest-priority active IRM applicable to it. An account holding no debt
    ///      has no IRM assigned, so is left untouched.
    function _syncAccount(address account) internal override(DebtToken) {
        /// @dev Debt may only be moved between IRMs once interest has been accrued up to the current block; a stale
        /// index restates it without the elapsed interest, repricing that period at the new IRM's rate.
        _requireBorrowIndexesUpdated();

        /// @dev There is nothing to sync for an account with no debt.
        uint256 scaledBalance = scaledBalanceOf(account);
        if (scaledBalance == 0) return;

        /// @dev An account keeps its current IRM when no active IRM applies to it, and has nothing to move when the
        /// applicable IRM is the one it is already assigned to.
        address currentIrmId = _accountIrmId[account];
        (bool found, address newIrmId) = _tryFindIrmForAccount(account);
        if (!found || newIrmId == currentIrmId) return;

        /// @dev We have a new IRM so we need to restate the account's debt against the new IRM's borrow index and move
        /// it between the two buckets. Both buckets move by exactly the scaled amount the account gives up or takes on.
        uint256 debt = InterestMath.toActualDebt(scaledBalance, _irmData[currentIrmId].storedBorrowIndex);
        uint256 newScaledBalance = InterestMath.toScaledDebt(debt, _irmData[newIrmId].storedBorrowIndex);

        _burnScaledDebt(currentIrmId, account, scaledBalance);
        _mintScaledDebt(newIrmId, account, newScaledBalance);

        _accountIrmId[account] = newIrmId;

        emit AccountIrmAssigned(account, currentIrmId, newIrmId);
    }

    function _accrueInterest() internal override(DebtToken) returns (uint256 accrued, uint256 retained) {
        for (uint256 i; i < _supportedIrmIds.length; i++) {
            (uint256 irmAccrued, uint256 irmRetained) = _updateIrmBorrowIndex(_supportedIrmIds[i]);
            accrued += irmAccrued;
            retained += irmRetained;
        }
        _lastUpdateTs = block.timestamp;
    }

    function _updateBorrowRates(uint256 idleLiquidity) internal override(DebtToken) {
        /// @dev Rates may only be recomputed once interest has been accrued up to the current block; otherwise a new
        /// rate would be applied retroactively over the elapsed period on the next borrow index update.
        _requireBorrowIndexesUpdated();

        uint256 totalDebt = totalSupply();

        /// @dev Assumes no IRM or borrow rate module calls back into the pool. A nested pool operation recomputes every
        /// rate, then this loop overwrites the current IRM and those after it with rates computed from the pool state read before it.
        for (uint256 i; i < _supportedIrmIds.length; i++) {
            _updateIrmBorrowRate(_supportedIrmIds[i], idleLiquidity, totalDebt);
        }
    }

    function _mintDebt(address account, uint256 amount) internal override(DebtToken) {
        /// @dev Debt may only be created once interest has been accrued up to the current block; a stale index
        /// overstates the scaled amount, charging the account the elapsed interest.
        _requireBorrowIndexesUpdated();

        /// @dev An account holding no debt has no IRM assigned, so is first assigned one to hold the new debt.
        address irmId;
        if (scaledBalanceOf(account) == 0) {
            irmId = findIrmForAccount(account);

            _accountIrmId[account] = irmId;
            emit AccountIrmAssigned(account, address(0), irmId);
        } else {
            irmId = _accountIrmId[account];
        }

        uint256 scaledAmount = InterestMath.toScaledDebt(amount, _irmData[irmId].storedBorrowIndex);

        _mintScaledDebt(irmId, account, scaledAmount);

        /// @dev The account's IRM is re-evaluated on every change to its debt, rather than relying on the caller to
        /// sync it.
        _syncAccount(account);
    }

    /// @dev Reverts when `amount` exceeds the account's debt: on the IRM's total if the account holds all of it,
    /// through `ERC20._burn` otherwise.
    function _burnDebt(address account, uint256 amount) internal override(DebtToken) {
        /// @dev Debt may only be retired once interest has been accrued up to the current block; a stale index
        /// overstates the scaled amount, crediting the account the elapsed interest.
        _requireBorrowIndexesUpdated();

        /// @dev Check IRM is supported so an unassigned account reverts.
        address irmId = _accountIrmId[account];
        _requireIrmSupported(irmId);

        uint256 scaledAmount = InterestMath.toScaledRepayment(amount, _irmData[irmId].storedBorrowIndex);

        _burnScaledDebt(irmId, account, scaledAmount);

        /// @dev An account holding no debt has no IRM assigned. Otherwise its IRM is re-evaluated, as on every change
        /// to its debt, rather than relying on the caller to sync it.
        if (scaledBalanceOf(account) == 0) {
            delete _accountIrmId[account];
            emit AccountIrmAssigned(account, irmId, address(0));
        } else {
            _syncAccount(account);
        }
    }

    function _mintScaledDebt(address irmId, address account, uint256 scaledAmount) internal {
        _irmData[irmId].totalScaledDebt += scaledAmount;
        ERC20Upgradeable._mint(account, scaledAmount);
    }

    function _burnScaledDebt(address irmId, address account, uint256 scaledAmount) internal {
        _irmData[irmId].totalScaledDebt -= scaledAmount;
        ERC20Upgradeable._burn(account, scaledAmount);
    }

    function _updateIrmBorrowIndex(address irmId) internal returns (uint256 accrued, uint256 retained) {
        IrmData storage irmData = _irmData[irmId];
        uint256 prevBorrowIndex = irmData.storedBorrowIndex;

        uint256 newBorrowIndex =
            InterestMath.calcBorrowIndex(prevBorrowIndex, irmData.borrowRate, block.timestamp - _lastUpdateTs);
        accrued = InterestMath.calcAccruedInterest(irmData.totalScaledDebt, prevBorrowIndex, newBorrowIndex);
        retained = InterestMath.calcRetained(accrued, irmData.retentionRate);

        irmData.storedBorrowIndex = newBorrowIndex;
    }

    function _updateIrmBorrowRate(address irmId, uint256 idleLiquidity, uint256 totalDebt) private {
        IrmData storage irmData = _irmData[irmId];
        uint256 borrowIndex = irmData.storedBorrowIndex;
        uint256 irmDebt = InterestMath.toActualDebt(irmData.totalScaledDebt, borrowIndex);

        uint256 borrowRate = IIRM(irmId).borrowRate(idleLiquidity, totalDebt, irmDebt);
        uint256 retentionRate = IIRM(irmId).retentionRate(idleLiquidity, totalDebt, irmDebt);
        irmData.borrowRate = borrowRate;
        irmData.retentionRate = retentionRate;

        emit IrmRatesUpdated(irmId, borrowIndex, borrowRate, retentionRate);
    }

    function _tryFindIrmForAccount(address account) private view returns (bool found, address irmId) {
        for (uint256 i; i < _activeIrmIds.length; i++) {
            address activeIrmId = _activeIrmIds[i];
            if (IIRM(activeIrmId).isApplicable(account)) return (true, activeIrmId);
        }
    }

    function _pendingIrmInterest(address irmId) private view returns (uint256 accrued, uint256 retained) {
        IrmData storage irmData = _irmData[irmId];
        accrued = InterestMath.calcAccruedInterest(
            irmData.totalScaledDebt, irmData.storedBorrowIndex, updatedBorrowIndex(irmId)
        );
        retained = InterestMath.calcRetained(accrued, irmData.retentionRate);
    }

    function _requireIrmSupported(address irmId) private view {
        if (!isIrmSupported(irmId)) revert IrmNotSupported(irmId);
    }

    function _requireBorrowIndexesUpdated() private view {
        // Exact equality checks same-block synchronization, regardless of the timestamp chosen.
        // forge-lint: disable-next-line(block-timestamp)
        if (_lastUpdateTs != block.timestamp) revert BorrowIndexesStale();
    }
}
