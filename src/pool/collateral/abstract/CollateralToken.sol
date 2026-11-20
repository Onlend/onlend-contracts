// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "../../../interfaces/IVersioned.sol";
import {ICollateralToken} from "../interfaces/ICollateralToken.sol";

/// @title  CollateralToken
/// @notice Non-transferable ERC-20 representing an account's collateral position in a pool.
/// @dev    `transfer`, `transferFrom` and `approve` revert unconditionally; balances only change via `mint`/`burn` by
///         the pool.
abstract contract CollateralToken is ICollateralToken, ERC20Upgradeable {
    /// @notice Pool contract this collateral token belongs to.
    address private _pool;
    /// @notice Decimals this token reports, matching the underlying asset.
    uint8 private _decimals;

    /// @notice Thrown when calling `transfer`, `transferFrom` or `approve`.
    error FunctionNotSupported();

    /// @notice Thrown when calling a pool-only function from an account other than `pool`.
    error NotPoolCaller();

    /// @notice Restricts a function to `pool`.
    modifier onlyPool() {
        if (msg.sender != _pool) revert NotPoolCaller();
        _;
    }

    /// @notice Initializes collateral-token state for an inheriting contract.
    /// @dev Must be called from the concrete collateral token's initializer.
    /// @param  pool_     Pool contract authorised to `mint`/`burn`
    /// @param  name_     Collateral asset name
    /// @param  symbol_   Collateral asset symbol
    /// @param  decimals_ Decimals to report, matching the underlying asset
    function _initializeCollateralToken(address pool_, string memory name_, string memory symbol_, uint8 decimals_)
        internal
        onlyInitializing
    {
        __ERC20_init(name_, symbol_);

        _decimals = decimals_;
        _pool = pool_;
    }

    /// @inheritdoc ICollateralToken
    function mint(address account, uint256 amount) external override(ICollateralToken) onlyPool {
        _mint(account, amount);
    }

    /// @inheritdoc ICollateralToken
    function burn(address account, uint256 amount) external override(ICollateralToken) onlyPool {
        _burn(account, amount);
    }

    /// @inheritdoc ICollateralToken
    function pool() public view returns (address) {
        return _pool;
    }

    /// @notice Number of decimals, matching the underlying asset.
    /// @return Decimals set during initialization
    function decimals() public view override(ERC20Upgradeable) returns (uint8) {
        return _decimals;
    }

    /// @notice Always reverts; collateral tokens are non-transferable.
    function transfer(address, uint256) public pure override(IERC20, ERC20Upgradeable) returns (bool) {
        revert FunctionNotSupported();
    }

    /// @notice Always reverts; collateral tokens are non-transferable.
    function transferFrom(address, address, uint256) public pure override(IERC20, ERC20Upgradeable) returns (bool) {
        revert FunctionNotSupported();
    }

    /// @notice Always reverts; collateral tokens are non-transferable.
    function approve(address, uint256) public pure override(IERC20, ERC20Upgradeable) returns (bool) {
        revert FunctionNotSupported();
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public pure override(IERC165) returns (bool) {
        return interfaceId == type(ICollateralToken).interfaceId || interfaceId == type(IERC20).interfaceId
            || interfaceId == type(IVersioned).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
