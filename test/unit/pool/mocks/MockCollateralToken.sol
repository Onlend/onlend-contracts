// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "src/interfaces/IVersioned.sol";
import {ICollateralToken} from "src/pool/collateral/interfaces/ICollateralToken.sol";

/// @dev Collateral token stand-in for pool tests. Tracks balances through OpenZeppelin's `ERC20` and reports the
///      decimals it was constructed with, so a pool is exercised against a configurable dependency rather than
///      against the real collateral token's own wiring. Mint and burn are ungated so tests can seed positions.
contract MockCollateralToken is ERC20, ICollateralToken {
    address private immutable _POOL;
    uint8 private immutable _DECIMALS;

    event MintCalled(address account, uint256 amount);
    event BurnCalled(address account, uint256 amount);

    constructor(address pool_, uint8 decimals_) ERC20("Mock Collateral Token", "MCT") {
        _POOL = pool_;
        _DECIMALS = decimals_;
    }

    /// @inheritdoc ICollateralToken
    function mint(address account, uint256 amount) external override(ICollateralToken) {
        emit MintCalled(account, amount);
        _mint(account, amount);
    }

    /// @inheritdoc ICollateralToken
    function burn(address account, uint256 amount) external override(ICollateralToken) {
        emit BurnCalled(account, amount);
        _burn(account, amount);
    }

    /// @inheritdoc ICollateralToken
    function pool() external view override(ICollateralToken) returns (address) {
        return _POOL;
    }

    function contractName() external pure returns (string memory name_) {
        return "MockCollateralToken";
    }

    function contractVersion() external pure returns (string memory version_) {
        return "1.0.0";
    }

    /// @inheritdoc ICollateralToken
    function collateralBalanceOf(address account) public view override(ICollateralToken) returns (uint256) {
        return balanceOf(account);
    }

    /// @inheritdoc ICollateralToken
    function totalCollateral() public view override(ICollateralToken) returns (uint256) {
        return totalSupply();
    }

    function decimals() public view override(ERC20) returns (uint8) {
        return _DECIMALS;
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public pure override(IERC165) returns (bool) {
        return interfaceId == type(ICollateralToken).interfaceId || interfaceId == type(IERC20).interfaceId
            || interfaceId == type(IVersioned).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
