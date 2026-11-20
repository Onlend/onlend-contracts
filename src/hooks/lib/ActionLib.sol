// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

/// @title ActionLib
/// @notice Hook action identifiers, each the bit position that enables its hook in a hook bitmap.
/// @dev Identifiers are persisted in deployed contracts' hook bitmaps and interpreted by hook receivers across contract
///      versions, so once deployed they are append-only. An identifier is never renumbered or reused, and an action
///      whose hook data changes shape takes a new identifier. Each group reserves a range so that there is space for
///      new actions to join their group. Identifier zero is left unused, so an unset identifier matches no action.
///
///      Each action's hook data opens with:
///      - `account`: the account whose position the action changes.
///      - `counterparty`: the account paying in when the action moves funds in, or receiving when it moves funds out.
///      - `initiator`: the caller that started the action, which may differ from `account`.
///      An identifier notes where its hook data departs from this.
library ActionLib {
    // LendingCore user operations: 1-15
    uint8 internal constant LC_DEPOSIT_COLLATERAL = 1;
    uint8 internal constant LC_WITHDRAW_COLLATERAL = 2;
    uint8 internal constant LC_BORROW = 3;
    uint8 internal constant LC_REPAY = 4;
    /// @dev The AFTER hook data carries the collateral seized, the borrows repaid and the debt written off, as the
    ///      pools applied them, in place of the positions requested.
    uint8 internal constant LC_LIQUIDATE = 5;

    // Pool operations routed through LendingCore: 16-31
    // Hook data has no `initiator`, since LendingCore is always the caller. Its own hook data carries the initiator.
    uint8 internal constant POOL_DEPOSIT_COLLATERAL = 16;
    uint8 internal constant POOL_WITHDRAW_COLLATERAL = 17;
    uint8 internal constant POOL_SEIZE_COLLATERAL = 18;
    uint8 internal constant POOL_BORROW = 19;
    uint8 internal constant POOL_REPAY = 20;
    /// @dev Moves no funds, so has no `counterparty`: hook data follows `account` directly.
    uint8 internal constant POOL_WRITE_OFF_DEBT = 21;

    // Pool operations called directly: 32-47
    uint8 internal constant POOL_DEPOSIT = 32;
    uint8 internal constant POOL_MINT = 33;
    uint8 internal constant POOL_WITHDRAW = 34;
    uint8 internal constant POOL_REDEEM = 35;
    uint8 internal constant POOL_TRANSFER = 36;
    /// @dev Changes no position, so hook data opens with the caller that took the loan in place of `account`. The
    ///      `counterparty` is the borrower, which both receives the loan and repays it. It has no separate `initiator`.
    uint8 internal constant POOL_FLASH_LOAN = 37;
    /// @dev Moves no funds, so has no `counterparty`, and has no `initiator`: hook data is `account` alone.
    uint8 internal constant POOL_SYNC_ACCOUNT = 38;
    /// @dev Credits two accounts, so hook data opens with the caller that triggered the claim in place of `account`,
    ///      followed by the operator fee recipient and the Onlend fee recipient.
    uint8 internal constant POOL_CLAIM_FEE_SHARES = 39;
}
