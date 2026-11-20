// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "../../../interfaces/IVersioned.sol";
import {IDebtToken} from "../interfaces/IDebtToken.sol";

/// @title  DebtToken
/// @notice Non-transferable ERC-20 representing an account's debt position in a pool.
/// @dev    `transfer`, `transferFrom` and `approve` revert unconditionally; balances only change via pool-only
///         functions.
abstract contract DebtToken is IDebtToken, ERC20Upgradeable {
    /// @notice Pool contract this debt token belongs to.
    address private _pool;
    /// @notice Decimals this token reports, matching the underlying asset.
    uint8 private _decimals;

    /// @notice Thrown when calling `transfer`, `transferFrom` or `approve`.
    error FunctionNotSupported();
    /// @notice Thrown when calling a pool-only function from an account other than `pool`.
    error NotPoolCaller();
    /// @notice Thrown when minting or burning a zero amount.
    error ZeroAmount();

    /// @notice Restricts a function to `pool`.
    modifier onlyPool() {
        if (msg.sender != _pool) revert NotPoolCaller();
        _;
    }

    /// @notice Initializes debt-token state for an inheriting contract.
    /// @dev Must be called from the concrete debt token's initializer.
    /// @param  pool_     Pool contract authorised to manage debt
    /// @param  name_     Debt token name
    /// @param  symbol_   Debt token symbol
    /// @param  decimals_ Decimals to report, matching the underlying asset
    function _initializeDebtToken(address pool_, string memory name_, string memory symbol_, uint8 decimals_)
        internal
        onlyInitializing
    {
        __ERC20_init(name_, symbol_);

        _pool = pool_;
        _decimals = decimals_;
    }

    /// @inheritdoc IDebtToken
    function accrueInterest() external override(IDebtToken) onlyPool returns (uint256 accrued, uint256 retained) {
        (accrued, retained) = _accrueInterest();
    }

    /// @inheritdoc IDebtToken
    function syncAccount(address account) external override(IDebtToken) onlyPool {
        _syncAccount(account);
    }

    /// @inheritdoc IDebtToken
    function updateBorrowRates(uint256 idleLiquidity) external override(IDebtToken) onlyPool {
        _updateBorrowRates(idleLiquidity);
    }

    /// @inheritdoc IDebtToken
    /// @dev Reverts with `ZeroAmount` if `amount` is zero.
    function mint(address account, uint256 amount) external override(IDebtToken) onlyPool {
        if (amount == 0) revert ZeroAmount();
        _mintDebt(account, amount);
    }

    /// @inheritdoc IDebtToken
    /// @dev Reverts with `ZeroAmount` if `amount` is zero.
    function burn(address account, uint256 amount) external override(IDebtToken) onlyPool {
        if (amount == 0) revert ZeroAmount();
        _burnDebt(account, amount);
    }

    /// @inheritdoc IDebtToken
    function pool() external view returns (address) {
        return _pool;
    }

    /// @notice Number of decimals, matching the underlying asset.
    /// @return Decimals set during initialization
    function decimals() public view override(ERC20Upgradeable) returns (uint8) {
        return _decimals;
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165) returns (bool) {
        return interfaceId == type(IDebtToken).interfaceId || interfaceId == type(IERC20).interfaceId
            || interfaceId == type(IVersioned).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /// @notice Always reverts; debt tokens are non-transferable.
    function transfer(address, uint256) public pure override(IERC20, ERC20Upgradeable) returns (bool) {
        revert FunctionNotSupported();
    }

    /// @notice Always reverts; debt tokens are non-transferable.
    function transferFrom(address, address, uint256) public pure override(IERC20, ERC20Upgradeable) returns (bool) {
        revert FunctionNotSupported();
    }

    /// @notice Always reverts; debt tokens are non-transferable.
    function approve(address, uint256) public pure override(IERC20, ERC20Upgradeable) returns (bool) {
        revert FunctionNotSupported();
    }

    function _syncAccount(address account) internal virtual;
    function _accrueInterest() internal virtual returns (uint256 accrued, uint256 retained);
    function _updateBorrowRates(uint256 idleLiquidity) internal virtual;
    function _mintDebt(address account, uint256 amount) internal virtual;
    function _burnDebt(address account, uint256 amount) internal virtual;
}
