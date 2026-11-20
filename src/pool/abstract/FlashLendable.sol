// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {
    AccessControlEnumerableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title FlashLendable
/// @notice Abstract contract that lets inheriting contracts offer fee-free ERC-3156 flash loans of a single token.
/// @dev Provides an internal initializer for EIP-1167-compatible inheriting contracts. The inheriting contract names
///      the token it lends through `_flashLoanToken`.
abstract contract FlashLendable is IERC3156FlashLender, AccessControlEnumerableUpgradeable {
    /// @notice Role allowed to enable and disable flash loans.
    bytes32 public constant FLASH_LOAN_CONFIG_ROLE = keccak256("FLASH_LOAN_CONFIG_ROLE");

    /// @notice Whether flash loans are currently offered.
    bool private _flashLoansEnabled;

    /// @notice Emitted when flash loans are enabled or disabled.
    /// @param enabled New flash loan status; true if enabled, false if disabled.
    event FlashLoansEnabledSet(bool enabled);

    /// @notice Emitted when a flash loan is repaid.
    /// @param initiator Account that requested the flash loan.
    /// @param receiver Receiver the flash loan was lent to and repaid by.
    /// @param token Token lent.
    /// @param amount Amount of `token` lent.
    event FlashLoan(address indexed initiator, address indexed receiver, address indexed token, uint256 amount);

    /// @notice Reverts when setting flash loans to the status they already have.
    /// @param enabled The unchanged flash loan status.
    error FlashLoansEnabledUnchanged(bool enabled);

    /// @notice Reverts when requesting a flash loan while flash loans are disabled.
    error FlashLoansDisabled();

    /// @notice Reverts when requesting a flash loan of zero.
    error ZeroFlashLoanAmount();

    /// @notice Reverts when requesting a flash loan of, or its fee for, a token other than the flash loan token.
    /// @param token Unsupported token.
    error ERC3156UnsupportedToken(address token);

    /// @notice Reverts when requesting a flash loan larger than can currently be lent.
    /// @param maxLoan Largest flash loan that can currently be made.
    error ERC3156ExceededMaxLoan(uint256 maxLoan);

    /// @notice Reverts when a flash loan receiver does not return the ERC-3156 callback success value.
    /// @param receiver Receiver that rejected the loan.
    error ERC3156InvalidReceiver(address receiver);

    /// @notice Initializes FlashLendable state for an inheriting contract.
    /// @dev Must be called from the inheriting contract's initializer, which is also responsible for initializing
    ///      access control and granting `DEFAULT_ADMIN_ROLE`.
    /// @param flashLoanConfigurator Initial flash loan config role member.
    /// @param initialFlashLoansEnabled Whether flash loans start enabled.
    function _initializeFlashLendable(address flashLoanConfigurator, bool initialFlashLoansEnabled)
        internal
        onlyInitializing
    {
        if (flashLoanConfigurator != address(0)) _grantRole(FLASH_LOAN_CONFIG_ROLE, flashLoanConfigurator);

        _setFlashLoansEnabled(initialFlashLoansEnabled);
    }

    /// @notice Enables or disables flash loans.
    /// @dev Reverts if flash loans already have the requested status.
    /// @param enabled True to enable flash loans, false to disable them.
    function setFlashLoansEnabled(bool enabled) external onlyRole(FLASH_LOAN_CONFIG_ROLE) {
        if (enabled == _flashLoansEnabled) revert FlashLoansEnabledUnchanged(enabled);

        _setFlashLoansEnabled(enabled);
    }

    /// @notice Returns whether flash loans are currently offered.
    /// @return True if flash loans are enabled.
    function flashLoansEnabled() external view returns (bool) {
        return _flashLoansEnabled;
    }

    /// @inheritdoc IERC3156FlashLender
    /// @dev Always zero for the flash loan token. Reverts for any other token, as ERC-3156 requires.
    function flashFee(address token, uint256) external view override(IERC3156FlashLender) returns (uint256) {
        if (token != _flashLoanToken()) revert ERC3156UnsupportedToken(token);
        return 0;
    }

    /// @inheritdoc IERC3156FlashLender
    /// @dev Lends out of this contract's balance. Reentrancy is permitted, so repayment is pulled from `receiver`
    ///      rather than inferred from the balance after the callback, which tokens credited through a reentrant call
    ///      would also satisfy. The fee is always zero. Emits `FlashLoan` once the loan is repaid.
    function flashLoan(IERC3156FlashBorrower receiver, address token, uint256 amount, bytes calldata data)
        public
        virtual
        override(IERC3156FlashLender)
        returns (bool)
    {
        if (!_flashLoansEnabled) revert FlashLoansDisabled();
        if (token != _flashLoanToken()) revert ERC3156UnsupportedToken(token);
        if (amount == 0) revert ZeroFlashLoanAmount();
        uint256 maxLoan = maxFlashLoan(token);
        if (amount > maxLoan) revert ERC3156ExceededMaxLoan(maxLoan);

        SafeERC20.safeTransfer(IERC20(token), address(receiver), amount);
        if (receiver.onFlashLoan(msg.sender, token, amount, 0, data) != keccak256("ERC3156FlashBorrower.onFlashLoan")) {
            revert ERC3156InvalidReceiver(address(receiver));
        }
        // `receiver` accepted the loan by returning the callback success value and approves its repayment.
        // slither-disable-next-line arbitrary-send-erc20
        SafeERC20.safeTransferFrom(IERC20(token), address(receiver), address(this), amount);

        emit FlashLoan(msg.sender, address(receiver), token, amount);

        return true;
    }

    /// @inheritdoc IERC3156FlashLender
    /// @dev This contract's whole balance of the flash loan token while flash loans are enabled, since a flash loan
    ///      returns what it lends within the same transaction. Zero while flash loans are disabled and for any other
    ///      token.
    function maxFlashLoan(address token) public view override(IERC3156FlashLender) returns (uint256) {
        if (!_flashLoansEnabled || token != _flashLoanToken()) return 0;

        return IERC20(token).balanceOf(address(this));
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC3156FlashLender).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @notice Sets whether flash loans are offered.
    /// @param enabled True to enable flash loans, false to disable them.
    function _setFlashLoansEnabled(bool enabled) internal {
        _flashLoansEnabled = enabled;
        emit FlashLoansEnabledSet(enabled);
    }

    /// @notice Returns the only token that can be flash loaned.
    /// @return Flash loan token.
    function _flashLoanToken() internal view virtual returns (address);
}
