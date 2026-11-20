// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Phase} from "../../hooks/interfaces/IHookReceiver.sol";
import {ActionLib} from "../../hooks/lib/ActionLib.sol";

import {IDebtToken} from "../debt/interfaces/IDebtToken.sol";
import {IBorrowable} from "../interfaces/IBorrowable.sol";
import {IOnlendFeeRegistry} from "../interfaces/IOnlendFeeRegistry.sol";
import {InterestMath} from "../lib/InterestMath.sol";
import {ShareMath} from "../lib/ShareMath.sol";
import {BasePool} from "./BasePool.sol";

/// @title  Borrowable
/// @notice Gives a pool an ERC-4626 supply side whose deposited assets can be borrowed through LendingCore. See
///         {IBorrowable}.
/// @dev    Total assets cover idle liquidity and outstanding debt. Idle liquidity is accounted as assets move rather
///         than read from the pool's balance, so underlying transferred in outside a pool operation raises neither the
///         share price nor the liquidity borrowers can draw on. The pool's balance may therefore exceed what it has
///         accounted for.
///
///         Fee-on-transfer assets are not supported. A transfer that delivers less than it was asked for is still
///         booked in full, so the pool would account for underlying it never received.
///
///         Rebasing assets are not supported. A balance restated in place moves without any transfer to account for, so
///         the pool would account for underlying it no longer holds.
///
///         Accrued interest is split between depositors, the operator and Onlend. The debt token reports the interest
///         and the part of it retained under the retention rate, and the pool splits that into the operator's fee and
///         Onlend's fee using the configuration read from the fee registry. Both fees are held as pool shares, so they
///         earn the deposit rate and bear loss alongside depositors. Operator and Onlend fee shares count towards
///         `totalSupply` from the moment they accrue but are only minted as ERC-20 balances when claimed, so
///         `totalSupply` exceeds the sum of all `balanceOf` by `totalOperatorFeeShares` plus `totalOnlendFeeShares`.
///
///         Debt accounting and interest-rate-model assignment are delegated to the deployed debt token.
abstract contract Borrowable is IBorrowable, BasePool, ERC4626Upgradeable {
    /// @notice Role allowed to set the account the operator's fee shares are minted to.
    bytes32 public constant OPERATOR_FEE_CONFIG_ROLE = keccak256("OPERATOR_FEE_CONFIG_ROLE");

    /// @notice Debt token responsible for debt, borrow-index and interest-rate accounting.
    IDebtToken private _debtToken;
    /// @notice Registry the Onlend fee configuration and fee recipient are read from.
    /// @dev Trusted: its fee configuration and recipient are used without bounds checks.
    IOnlendFeeRegistry private _feeRegistry;
    /// @notice Account the operator's fee shares are minted to.
    address private _operatorFeeRecipient;
    /// @notice Onlend fixed fee in force since the last rate update, in bps.
    uint16 private _fixedFeeBps;
    /// @notice Onlend split fee in force since the last rate update, in bps.
    uint16 private _splitFeeBps;
    /// @notice Underlying held by the pool and not lent to borrowers, as the pool has accounted for it.
    uint256 internal _idleLiquidity;
    /// @notice Pool shares accrued from the operator's fee and not yet minted as ERC-20 balances.
    uint256 internal _storedOperatorFeeShares;
    /// @notice Pool shares accrued from Onlend's fee and not yet minted as ERC-20 balances.
    uint256 internal _storedOnlendFeeShares;

    /// @notice Emitted when operator and Onlend fee shares are claimed.
    /// @param  caller               Account that claimed.
    /// @param  operatorFeeRecipient Account the operator fee shares were minted to.
    /// @param  onlendFeeRecipient   Account the Onlend fee shares were minted to.
    /// @param  operatorFeeShares    Operator fee shares claimed.
    /// @param  onlendFeeShares      Onlend fee shares claimed.
    event FeeSharesClaimed(
        address indexed caller,
        address indexed operatorFeeRecipient,
        address indexed onlendFeeRecipient,
        uint256 operatorFeeShares,
        uint256 onlendFeeShares
    );
    /// @notice Emitted when the operator fee recipient is set.
    /// @param  operatorFeeRecipient New operator fee recipient.
    event OperatorFeeRecipientSet(address indexed operatorFeeRecipient);
    /// @notice Emitted when an account's debt is written off without repayment.
    /// @param  account Account whose debt was written off.
    /// @param  amount  Underlying amount of debt written off.
    event DebtWrittenOff(address indexed account, uint256 amount);
    /// @notice Emitted when interest is accrued and the operator's and Onlend's fees on it are booked as fee shares.
    /// @param  interest          Interest accrued since the last accrual, in underlying assets.
    /// @param  operatorFee       Operator's fee on the interest, in underlying assets.
    /// @param  onlendFee         Onlend's fee on the interest, in underlying assets.
    /// @param  operatorFeeShares Operator fee shares `operatorFee` bought.
    /// @param  onlendFeeShares   Onlend fee shares `onlendFee` bought.
    event InterestAccrued(
        uint256 interest, uint256 operatorFee, uint256 onlendFee, uint256 operatorFeeShares, uint256 onlendFeeShares
    );
    /// @notice Emitted when the pool picks up a changed Onlend fee configuration from the fee registry.
    /// @dev    The registry is read on every rate update; this is emitted only when what it returns has changed.
    /// @param  fixedFeeBps Share of all accrued interest taken by Onlend on top of the retention, in bps.
    /// @param  splitFeeBps Share of the retained interest taken by Onlend, in bps.
    event OnlendFeeConfigUpdated(uint16 fixedFeeBps, uint16 splitFeeBps);
    /// @notice Emitted each time the pool recomputes its interest rates, with its state at that point.
    /// @dev    Every operation that changes any of the three ends by recomputing rates, so the latest event gives the
    ///         pool's state as of the last operation.
    /// @param  idleLiquidity Underlying held by the pool and not lent to borrowers, as the pool has accounted for it.
    /// @param  totalDebt     Outstanding debt, including interest accrued to the current block.
    /// @param  totalSupply   Pool shares, including operator and Onlend fee shares not yet claimed.
    event PoolStateUpdated(uint256 idleLiquidity, uint256 totalDebt, uint256 totalSupply);

    /// @notice Reverts when a debt token does not support `IDebtToken`.
    /// @param  debtToken Invalid debt token address.
    error InvalidDebtToken(address debtToken);
    /// @notice Reverts when a fee registry does not support `IOnlendFeeRegistry`.
    /// @param  feeRegistry Invalid fee registry address.
    error InvalidFeeRegistry(address feeRegistry);
    /// @notice Reverts when an operation requests or resolves to zero assets or zero shares.
    error ZeroAmount();
    /// @notice Reverts when the operator fee recipient is the zero address.
    error InvalidOperatorFeeRecipient();
    /// @notice Reverts when borrowing more underlying than the pool holds idle.
    /// @param  amount    Requested borrow amount.
    /// @param  available Idle liquidity available to borrow.
    error InsufficientIdleLiquidity(uint256 amount, uint256 available);
    /// @notice Reverts when attempting to repay an account with no outstanding debt.
    /// @param  account Account with no debt.
    error NoDebt(address account);

    /// @notice Initializes the ERC-4626 vault, debt token and fee registry dependencies for an inheriting pool.
    /// @dev Must be called from the concrete pool's initializer. Grants only `OPERATOR_FEE_CONFIG_ROLE`.
    /// @param  operatorFeeConfigurator Initial operator fee config role member.
    /// @param  asset_                  Underlying asset managed by the ERC-4626 vault.
    /// @param  name_                   Pool share token name.
    /// @param  symbol_                 Pool share token symbol.
    /// @param  debtToken_              Debt token associated with this pool.
    /// @param  feeRegistry_            Registry the Onlend fee configuration and fee recipient are read from.
    /// @param  operatorFeeRecipient_   Initial account the operator's fee shares are minted to.
    function _initializeBorrowable(
        address operatorFeeConfigurator,
        IERC20Metadata asset_,
        string calldata name_,
        string calldata symbol_,
        address debtToken_,
        address feeRegistry_,
        address operatorFeeRecipient_
    ) internal onlyInitializing {
        _validateDebtToken(debtToken_);
        _validateTokenDecimals(debtToken_, asset_.decimals());
        _validateFeeRegistry(feeRegistry_);

        __ERC20_init(name_, symbol_);
        __ERC4626_init(asset_);

        _debtToken = IDebtToken(debtToken_);
        _feeRegistry = IOnlendFeeRegistry(feeRegistry_);
        _setOperatorFeeRecipient(operatorFeeRecipient_);
        _updateOnlendFeeConfig();

        if (operatorFeeConfigurator != address(0)) _grantRole(OPERATOR_FEE_CONFIG_ROLE, operatorFeeConfigurator);
    }

    /// @inheritdoc IBorrowable
    /// @dev Accrues interest and then recomputes borrow, retention and deposit interest rates and refreshes the Onlend
    ///      fee configuration. IRM borrow and retention rates, and the Onlend fee configuration, may change without any
    ///      pool accounting operation. Interest is accrued first so the previous rates and fees apply to the elapsed
    ///      period and the new ones apply from the current timestamp onward.
    function syncInterestRate() external {
        _accrueInterest();
        _updateInterestRates();
    }

    /// @inheritdoc IBorrowable
    /// @dev Fires `POOL_SYNC_ACCOUNT` hooks before and after synchronization. Interest is accrued before the account is
    ///      synchronized and rates are recomputed.
    function syncAccount(address account) external {
        _fireHook(Phase.BEFORE, ActionLib.POOL_SYNC_ACCOUNT, abi.encode(account));

        _accrueInterest();

        _debtToken.syncAccount(account);

        _updateInterestRates();

        _fireHook(Phase.AFTER, ActionLib.POOL_SYNC_ACCOUNT, abi.encode(account));
    }

    /// @notice Mints all accrued operator and Onlend fee shares to their recipients as ERC-20 pool shares.
    /// @dev Callable by anyone: each bucket can only go to its configured recipient, the pool's operator fee recipient
    ///      and the fee registry's recipient, so the caller decides only when they are claimed. Both buckets are always
    ///      claimed together, so a hook that blocks the claim blocks the operator's fee along with Onlend's. Interest
    ///      is accrued first so shares accrued up to the current timestamp are claimed. `totalSupply` is unchanged by
    ///      the claim: the shares already counted towards it, so claiming dilutes nobody. The recipients redeem them
    ///      like any other share holder, subject to idle liquidity. Fires `POOL_CLAIM_FEE_SHARES` hooks around the
    ///      claim: fee shares are held by no account until they are claimed, so this is the point at which they enter a
    ///      balance.
    /// @return operatorFeeShares Operator fee shares claimed.
    /// @return onlendFeeShares   Onlend fee shares claimed.
    function claimFeeShares() external returns (uint256 operatorFeeShares, uint256 onlendFeeShares) {
        address operatorFeeRecipient_ = _operatorFeeRecipient;
        address onlendFeeRecipient = _feeRegistry.feeRecipient();

        _fireHook(
            Phase.BEFORE,
            ActionLib.POOL_CLAIM_FEE_SHARES,
            abi.encode(msg.sender, operatorFeeRecipient_, onlendFeeRecipient)
        );

        _accrueInterest();

        operatorFeeShares = _storedOperatorFeeShares;
        onlendFeeShares = _storedOnlendFeeShares;
        if (operatorFeeShares == 0 && onlendFeeShares == 0) revert ZeroAmount();

        _storedOperatorFeeShares = 0;
        _storedOnlendFeeShares = 0;
        if (operatorFeeShares > 0) ERC20Upgradeable._mint(operatorFeeRecipient_, operatorFeeShares);
        if (onlendFeeShares > 0) ERC20Upgradeable._mint(onlendFeeRecipient, onlendFeeShares);

        emit FeeSharesClaimed(msg.sender, operatorFeeRecipient_, onlendFeeRecipient, operatorFeeShares, onlendFeeShares);

        _fireHook(
            Phase.AFTER,
            ActionLib.POOL_CLAIM_FEE_SHARES,
            abi.encode(msg.sender, operatorFeeRecipient_, onlendFeeRecipient, operatorFeeShares, onlendFeeShares)
        );
    }

    /// @notice Sets the account the operator's fee shares are minted to.
    /// @dev Applies to every claim made from now on, including shares already accrued but not yet claimed.
    /// @param  operatorFeeRecipient_ New operator fee recipient.
    function setOperatorFeeRecipient(address operatorFeeRecipient_) external onlyRole(OPERATOR_FEE_CONFIG_ROLE) {
        _setOperatorFeeRecipient(operatorFeeRecipient_);
    }

    /// @inheritdoc IBorrowable
    function debtToken() external view returns (address) {
        return address(_debtToken);
    }

    /// @notice Returns the registry the Onlend fee configuration and fee recipient are read from.
    /// @return Fee registry address.
    function feeRegistry() external view returns (address) {
        return address(_feeRegistry);
    }

    /// @notice Returns the account the operator's fee shares are minted to.
    /// @return Operator fee recipient address.
    function operatorFeeRecipient() external view returns (address) {
        return _operatorFeeRecipient;
    }

    /// @notice Returns the Onlend fee configuration in force since the last rate update.
    /// @dev Read from the fee registry alongside the borrow and retention rates, so a change made in the registry
    ///      applies from the pool's next rate update onward and never to interest already accruing.
    /// @return fixedFeeBps Share of all accrued interest taken by Onlend on top of the retention, in bps.
    /// @return splitFeeBps Share of the retained interest taken by Onlend, in bps.
    function onlendFeeConfig() external view returns (uint16 fixedFeeBps, uint16 splitFeeBps) {
        return (_fixedFeeBps, _splitFeeBps);
    }

    /// @inheritdoc IBorrowable
    /// @dev Accounted as assets move rather than read from the pool's balance, so underlying donated to the pool is not
    ///      counted and the pool's balance may exceed it. Flash loans do not move it, so during a flash loan's callback
    ///      it may exceed the pool's balance instead. Caps what a borrow can draw and what a redemption can pay out.
    function idleLiquidity() external view returns (uint256) {
        return _idleLiquidity;
    }

    /// @notice Returns the pool shares accrued from the operator's fee and not yet claimed.
    /// @dev Counted by `totalSupply` but held by no account, so these shares are backed by pool assets while unminted.
    ///      Includes the operator fee shares on interest accrued since the last pool operation.
    /// @return Unclaimed operator fee shares.
    function totalOperatorFeeShares() external view returns (uint256) {
        (uint256 pendingOperatorFeeShares,) = _pendingFeeShares();
        return _storedOperatorFeeShares + pendingOperatorFeeShares;
    }

    /// @notice Returns the pool shares accrued from Onlend's fee and not yet claimed.
    /// @dev Counted by `totalSupply` but held by no account, so these shares are backed by pool assets while unminted.
    ///      Includes the Onlend fee shares on interest accrued since the last pool operation.
    /// @return Unclaimed Onlend fee shares.
    function totalOnlendFeeShares() external view returns (uint256) {
        (, uint256 pendingOnlendFeeShares) = _pendingFeeShares();
        return _storedOnlendFeeShares + pendingOnlendFeeShares;
    }

    /// @inheritdoc IBorrowable
    /// @dev Derived on read rather than stored, so the debt and assets it prices against are current as of this block.
    ///      The rates behind the yield are still the stored ones, so a debt token whose rate moves with external state
    ///      is not reflected until the next pool operation recomputes them. The same holds for the Onlend fee
    ///      configuration. The virtual shares take the same cut of an incoming yield as they do of the assets backing
    ///      it.
    function depositInterestRate() external view returns (uint256) {
        (uint256 interest, uint256 retained) = _debtToken.annualInterest();
        (uint256 operatorFee, uint256 onlendFee) = InterestMath.calcFees(interest, retained, _fixedFeeBps, _splitFeeBps);

        return InterestMath.calcDepositInterestRate(
            interest - operatorFee - onlendFee, totalAssets() + ShareMath.VIRTUAL_ASSETS
        );
    }

    /// @inheritdoc IERC4626
    /// @dev Accrues interest before calculating shares, recomputes rates after depositing, and fires `POOL_DEPOSIT`
    ///      hooks around the operation.
    function deposit(uint256 assets, address receiver) public override(ERC4626Upgradeable) returns (uint256 shares) {
        _fireHook(Phase.BEFORE, ActionLib.POOL_DEPOSIT, abi.encode(receiver, msg.sender, msg.sender, assets));

        _accrueInterest();

        shares = super.deposit(assets, receiver);

        _updateInterestRates();

        _fireHook(Phase.AFTER, ActionLib.POOL_DEPOSIT, abi.encode(receiver, msg.sender, msg.sender, assets, shares));
    }

    /// @inheritdoc IERC4626
    /// @dev Accrues interest before calculating assets, recomputes rates after minting, and fires `POOL_MINT` hooks
    ///      around the operation.
    function mint(uint256 shares, address receiver) public override(ERC4626Upgradeable) returns (uint256 assets) {
        _fireHook(Phase.BEFORE, ActionLib.POOL_MINT, abi.encode(receiver, msg.sender, msg.sender, shares));

        _accrueInterest();

        assets = super.mint(shares, receiver);

        _updateInterestRates();

        _fireHook(Phase.AFTER, ActionLib.POOL_MINT, abi.encode(receiver, msg.sender, msg.sender, assets, shares));
    }

    /// @inheritdoc IERC4626
    /// @dev Accrues interest before calculating shares, recomputes rates after withdrawing, and fires `POOL_WITHDRAW`
    ///      hooks around the operation. Available assets are limited by idle liquidity.
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override(ERC4626Upgradeable)
        returns (uint256 shares)
    {
        _fireHook(Phase.BEFORE, ActionLib.POOL_WITHDRAW, abi.encode(owner, receiver, msg.sender, assets));

        _accrueInterest();

        shares = super.withdraw(assets, receiver, owner);

        _updateInterestRates();

        _fireHook(Phase.AFTER, ActionLib.POOL_WITHDRAW, abi.encode(owner, receiver, msg.sender, assets, shares));
    }

    /// @inheritdoc IERC4626
    /// @dev Accrues interest before calculating assets, recomputes rates after redeeming, and fires `POOL_REDEEM` hooks
    ///      around the operation. Redeemable shares are limited by idle liquidity.
    function redeem(uint256 shares, address receiver, address owner)
        public
        override(ERC4626Upgradeable)
        returns (uint256 assets)
    {
        _fireHook(Phase.BEFORE, ActionLib.POOL_REDEEM, abi.encode(owner, receiver, msg.sender, shares));

        _accrueInterest();

        assets = super.redeem(shares, receiver, owner);

        _updateInterestRates();

        _fireHook(Phase.AFTER, ActionLib.POOL_REDEEM, abi.encode(owner, receiver, msg.sender, assets, shares));
    }

    /// @inheritdoc IERC20
    /// @dev Fires `POOL_TRANSFER` hooks before and after transferring pool shares.
    function transfer(address to, uint256 amount) public override(ERC20Upgradeable, IERC20) returns (bool) {
        _fireHook(Phase.BEFORE, ActionLib.POOL_TRANSFER, abi.encode(msg.sender, to, msg.sender, amount));

        bool ok = super.transfer(to, amount);

        _fireHook(Phase.AFTER, ActionLib.POOL_TRANSFER, abi.encode(msg.sender, to, msg.sender, amount));

        return ok;
    }

    /// @inheritdoc IERC20
    /// @dev Fires `POOL_TRANSFER` hooks before and after transferring pool shares using an allowance.
    function transferFrom(address from, address to, uint256 amount)
        public
        override(ERC20Upgradeable, IERC20)
        returns (bool)
    {
        _fireHook(Phase.BEFORE, ActionLib.POOL_TRANSFER, abi.encode(from, to, msg.sender, amount));

        bool ok = super.transferFrom(from, to, amount);

        _fireHook(Phase.AFTER, ActionLib.POOL_TRANSFER, abi.encode(from, to, msg.sender, amount));

        return ok;
    }

    /// @inheritdoc IERC4626
    function asset() public view virtual override(BasePool, ERC4626Upgradeable) returns (address) {
        return ERC4626Upgradeable.asset();
    }

    /// @inheritdoc IERC4626
    /// @dev Includes idle liquidity and outstanding debt. The operator's and Onlend's fees are not deducted; they are
    ///      claimed by the operator and Onlend fee shares counted in `totalSupply`.
    function totalAssets() public view virtual override(BasePool, ERC4626Upgradeable) returns (uint256) {
        return _idleLiquidity + totalDebt();
    }

    /// @inheritdoc BasePool
    function totalDebt() public view virtual override(BasePool) returns (uint256) {
        return _debtToken.totalSupply();
    }

    /// @inheritdoc BasePool
    function debtOf(address account) public view virtual override(BasePool) returns (uint256) {
        return _debtToken.balanceOf(account);
    }

    /// @inheritdoc IERC20
    /// @dev Includes operator and Onlend fee shares, which have accrued but are not yet held by any account. Also
    ///      includes the operator and Onlend fee shares on interest accrued since the last pool operation.
    function totalSupply() public view override(ERC20Upgradeable, IERC20) returns (uint256) {
        (uint256 pendingOperatorFeeShares, uint256 pendingOnlendFeeShares) = _pendingFeeShares();
        return _storedSupply() + pendingOperatorFeeShares + pendingOnlendFeeShares;
    }

    /// @inheritdoc IERC4626
    /// @dev Limits deposits to the assets whose shares, rounded down, keep total supply within
    ///      `ShareMath.MAX_DEPOSIT_SHARES`.
    function maxDeposit(address receiver) public view override(ERC4626Upgradeable) returns (uint256) {
        return convertToAssets(maxMint(receiver));
    }

    /// @inheritdoc IERC4626
    /// @dev Limits minted shares to those that keep total supply within `ShareMath.MAX_DEPOSIT_SHARES`. Shares issued
    ///      on interest can take total supply past it, leaving nothing to mint.
    function maxMint(address) public view override(ERC4626Upgradeable) returns (uint256) {
        return Math.saturatingSub(ShareMath.MAX_DEPOSIT_SHARES, totalSupply());
    }

    /// @inheritdoc IERC4626
    /// @dev Conservatively limits redeemable shares by the underlying currently held by the pool. Overriding this alone
    ///      is sufficient: `maxWithdraw` is defined as `previewRedeem(maxRedeem(owner))` and so inherits the same cap.
    function maxRedeem(address owner) public view override(ERC4626Upgradeable) returns (uint256) {
        return Math.min(ERC4626Upgradeable.maxRedeem(owner), convertToShares(_idleLiquidity));
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IBorrowable).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @notice Applies debt accounting and transfers borrowed underlying to a receiver.
    /// @dev Interest is accrued before debt is minted. Only the liquidity the pool has accounted for can be lent out,
    ///      so underlying donated to the pool is not borrowable.
    /// @param  caller   Account whose debt is increased.
    /// @param  amount   Amount of underlying borrowed.
    /// @param  receiver Account receiving the borrowed underlying.
    function _borrow(address caller, uint256 amount, address receiver) internal virtual override(BasePool) {
        if (amount == 0) revert ZeroAmount();
        if (amount > _idleLiquidity) revert InsufficientIdleLiquidity(amount, _idleLiquidity);

        _accrueInterest();

        _debtToken.mint(caller, amount);

        _transferOut(receiver, amount);

        _updateInterestRates();
    }

    /// @notice Applies repayment accounting for an account's debt.
    /// @dev Interest is accrued before reading `receiver`'s debt. The amount transferred and burned is capped to the
    ///      outstanding debt.
    /// @param  caller   Account providing the repayment funds.
    /// @param  amount   Requested repayment amount.
    /// @param  receiver Account whose debt is reduced.
    /// @return repayment Actual underlying amount transferred and applied to the debt.
    function _repay(address caller, uint256 amount, address receiver)
        internal
        virtual
        override(BasePool)
        returns (uint256 repayment)
    {
        if (amount == 0) revert ZeroAmount();

        _accrueInterest();

        uint256 debt = _debtToken.balanceOf(receiver);
        if (debt == 0) revert NoDebt(receiver);

        repayment = Math.min(amount, debt);

        // LendingCore binds `caller` to the account providing the repayment funds.
        // slither-disable-next-line arbitrary-send-erc20
        _transferIn(caller, repayment);
        _debtToken.burn(receiver, repayment);

        _updateInterestRates();
    }

    /// @notice Applies write-off accounting for an account's debt.
    /// @dev Burns the debt as `_repay` does but with no underlying transferred in, so total assets fall by the amount
    ///      written off while total supply is unchanged. Interest is accrued first, so retention up to now is booked
    ///      against the debt it accrued on before that debt is removed.
    ///
    ///      Writing off nearly all of the pool's assets drives the share price close to zero, and new deposits buy
    ///      shares at that same price rather than restoring it, so each such write-off multiplies the supply by up to
    ///      the ratio of shares to the assets left. Deposits stop at `ShareMath.MAX_DEPOSIT_SHARES` and fee shares at
    ///      `ShareMath.MAX_TOTAL_SHARES`, so a pool wiped out again and again stops taking deposits rather than
    ///      overflowing.
    /// @param  account Account whose debt is written off.
    /// @return writtenOff Underlying amount of debt written off.
    function _writeOffDebt(address account) internal virtual override(BasePool) returns (uint256 writtenOff) {
        _accrueInterest();

        writtenOff = _debtToken.balanceOf(account);
        if (writtenOff == 0) revert NoDebt(account);

        _debtToken.burn(account, writtenOff);

        emit DebtWrittenOff(account, writtenOff);

        _updateInterestRates();
    }

    /// @notice Accrues interest and converts the operator's and Onlend's fees on it into operator and Onlend fee
    ///         shares.
    /// @dev Sole caller of `IDebtToken.accrueInterest`, whose return value is destroyed if it is not booked here. Must
    ///      run before any conversion between assets and shares, so those price against the accrued state.
    ///
    ///      Debt is borrowed out of the pool's assets, which deposits bring to at most about
    ///      `ShareMath.MAX_DEPOSIT_SHARES` times the share price, and the price rises no faster than interest
    ///      compounds. Debt therefore overflows only once interest has compounded about 2^128-fold since deployment,
    ///      which takes at least about 9 years at a 1,000% rate. Once it does, accrual reverts and blocks the
    ///      repayment, liquidation and write-off that would clear the debt. This is an accepted risk.
    function _accrueInterest() internal {
        (uint256 accrued, uint256 retained) = _debtToken.accrueInterest();
        if (accrued == 0) return;

        (uint256 operatorFee, uint256 onlendFee, uint256 operatorFeeShares, uint256 onlendFeeShares) =
            _feeShares(accrued, retained);
        _storedOperatorFeeShares += operatorFeeShares;
        _storedOnlendFeeShares += onlendFeeShares;

        emit InterestAccrued(accrued, operatorFee, onlendFee, operatorFeeShares, onlendFeeShares);
    }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev Ensures users aren't depositing assets for zero shares.
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares)
        internal
        override(ERC4626Upgradeable)
    {
        if (assets == 0 || shares == 0) revert ZeroAmount();

        super._deposit(caller, receiver, assets, shares);
    }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev Ensures users' aren't withdrawing shares for zero assets.
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override(ERC4626Upgradeable)
    {
        if (assets == 0 || shares == 0) revert ZeroAmount();

        super._withdraw(caller, receiver, owner, assets, shares);
    }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev Books the underlying into idle liquidity once it has arrived, so a reentrant caller never sees liquidity
    ///      the pool has not received.
    function _transferIn(address from, uint256 assets) internal override(ERC4626Upgradeable) {
        super._transferIn(from, assets);

        _idleLiquidity += assets;
    }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev Books the underlying out of idle liquidity before it leaves, so a reentrant caller never sees liquidity the
    ///      pool has already committed.
    function _transferOut(address to, uint256 assets) internal override(ERC4626Upgradeable) {
        _idleLiquidity -= assets;

        super._transferOut(to, assets);
    }

    /// @notice Recomputes the debt token's borrow and retention rates against current idle liquidity, and refreshes the
    ///         Onlend fee configuration from the fee registry.
    /// @dev Interest must already be accrued to the current block. Borrow rates price against real idle liquidity
    ///      alone, which is what a borrower can actually draw on. The fee configuration is refreshed alongside the
    ///      rates so that, like them, a change made in the registry applies from the current timestamp onward and never
    ///      to interest already accruing. Emits `PoolStateUpdated` with the resulting pool state, reading the stored
    ///      supply since, with interest accrued, no fee shares are pending.
    function _updateInterestRates() internal {
        _debtToken.updateBorrowRates(_idleLiquidity);
        _updateOnlendFeeConfig();

        emit PoolStateUpdated(_idleLiquidity, totalDebt(), _storedSupply());
    }

    /// @notice Sets the account the operator's fee shares are minted to.
    /// @dev Rejects the zero address, to which minting reverts, so a misconfigured recipient cannot leave every claim
    ///      reverting until it is replaced.
    /// @param  operatorFeeRecipient_ New operator fee recipient.
    function _setOperatorFeeRecipient(address operatorFeeRecipient_) internal {
        if (operatorFeeRecipient_ == address(0)) revert InvalidOperatorFeeRecipient();

        _operatorFeeRecipient = operatorFeeRecipient_;

        emit OperatorFeeRecipientSet(operatorFeeRecipient_);
    }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev Prices against `ShareMath`'s virtual amounts rather than the inherited single unit.
    function _convertToShares(uint256 assets, Math.Rounding rounding)
        internal
        view
        override(ERC4626Upgradeable)
        returns (uint256)
    {
        return ShareMath.toShares(assets, totalSupply(), totalAssets(), rounding);
    }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev Prices against `ShareMath`'s virtual amounts rather than the inherited single unit.
    function _convertToAssets(uint256 shares, Math.Rounding rounding)
        internal
        view
        override(ERC4626Upgradeable)
        returns (uint256)
    {
        return ShareMath.toAssets(shares, totalSupply(), totalAssets(), rounding);
    }

    /// @notice Validates a debt token dependency.
    /// @param  debtToken_ Debt token dependency to validate.
    function _validateDebtToken(address debtToken_) internal view {
        if (!ERC165Checker.supportsInterface(debtToken_, type(IDebtToken).interfaceId)) {
            revert InvalidDebtToken(debtToken_);
        }
    }

    /// @notice Validates a fee registry dependency.
    /// @param  feeRegistry_ Fee registry dependency to validate.
    function _validateFeeRegistry(address feeRegistry_) internal view {
        if (!ERC165Checker.supportsInterface(feeRegistry_, type(IOnlendFeeRegistry).interfaceId)) {
            revert InvalidFeeRegistry(feeRegistry_);
        }
    }

    /// @notice Reads the Onlend fee configuration that applies to this pool from the fee registry.
    function _updateOnlendFeeConfig() private {
        (uint16 fixedFeeBps, uint16 splitFeeBps) = _feeRegistry.feeConfig(address(this));
        if (fixedFeeBps == _fixedFeeBps && splitFeeBps == _splitFeeBps) return;

        _fixedFeeBps = fixedFeeBps;
        _splitFeeBps = splitFeeBps;

        emit OnlendFeeConfigUpdated(fixedFeeBps, splitFeeBps);
    }

    /// @notice Returns the operator and Onlend fee shares on interest accrued since the last pool operation.
    /// @return operatorFeeShares Shares the pending operator fee buys, or zero when no interest is pending.
    /// @return onlendFeeShares   Shares the pending Onlend fee buys, or zero when no interest is pending.
    function _pendingFeeShares() private view returns (uint256 operatorFeeShares, uint256 onlendFeeShares) {
        (uint256 accrued, uint256 retained) = _debtToken.pendingInterest();
        if (accrued == 0) return (0, 0);

        (,, operatorFeeShares, onlendFeeShares) = _feeShares(accrued, retained);
    }

    /// @notice Splits accrued interest into the operator's and Onlend's fees and converts each into the pool shares
    ///         that claim it.
    /// @dev Both fees are already included in total debt, so converting them at the post-accrual rate would price them
    ///      against assets they are themselves part of. Subtracting both gives the value the pre-existing share base is
    ///      entitled to, and pricing both against that same base means neither dilutes the other. Rounding down leaves
    ///      any remainder with depositors.
    /// @param  accrued  Interest accrued, in underlying assets.
    /// @param  retained Part of `accrued` retained under the retention rate, in underlying assets.
    /// @return operatorFee       Operator's fee on the accrued interest, in underlying assets.
    /// @return onlendFee         Onlend's fee on the accrued interest, in underlying assets.
    /// @return operatorFeeShares Shares the operator's fee buys at the price before it is counted.
    /// @return onlendFeeShares   Shares Onlend's fee buys at the price before it is counted.
    function _feeShares(uint256 accrued, uint256 retained)
        private
        view
        returns (uint256 operatorFee, uint256 onlendFee, uint256 operatorFeeShares, uint256 onlendFeeShares)
    {
        (operatorFee, onlendFee) = InterestMath.calcFees(accrued, retained, _fixedFeeBps, _splitFeeBps);

        uint256 supply = _storedSupply();
        uint256 assets = totalAssets() - operatorFee - onlendFee;

        /// @dev Fees whose shares would take total supply past what a conversion can price against are left with
        ///      depositors. Checked before converting, as the conversion itself would overflow first. Checking both
        ///      fees together covers each conversion, since the floored parts never exceed the floored whole.
        if (!ShareMath.sharesFit(operatorFee + onlendFee, supply, assets)) return (0, 0, 0, 0);

        operatorFeeShares = ShareMath.toShares(operatorFee, supply, assets, Math.Rounding.Floor);
        onlendFeeShares = ShareMath.toShares(onlendFee, supply, assets, Math.Rounding.Floor);
    }

    /// @notice Returns the shares the pool has already issued, held, operator fee and Onlend fee alike.
    /// @dev The base every fee conversion prices against. Excludes fees on interest accrued since the last pool
    ///      operation, so a pending fee and that same fee once booked buy the same number of shares.
    /// @return Shares issued as of the last accrual.
    function _storedSupply() private view returns (uint256) {
        return ERC20Upgradeable.totalSupply() + _storedOperatorFeeShares + _storedOnlendFeeShares;
    }
}
