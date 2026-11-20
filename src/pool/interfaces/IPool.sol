// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "../../interfaces/IVersioned.sol";

/// @title Pool Interface
/// @notice Pool operations routed through LendingCore.
/// @dev Every pool answers this whole interface, but not every pool supports every operation: a pool that cannot hold
///      collateral or cannot be borrowed from reverts the operations it does not support and reports zero for the total
///      behind them.
interface IPool is IERC165, IVersioned {
    /// @notice Deposits collateral into the pool.
    /// @dev Collateral amounts may be requested in underlying units (`assets`) or share units (`shares`). A concrete
    ///      pool defines which denominations it supports and rejects ambiguous requests.
    /// @param caller Account providing the collateral assets.
    /// @param assets Collateral amount denominated in underlying units.
    /// @param shares Collateral amount denominated in pool share units, when supported by the pool.
    /// @param receiver Account whose loan is credited with the collateral.
    /// @return assetsDeposited Underlying amount actually deposited.
    /// @return sharesMinted Pool shares the deposit minted, or zero for a pool without shares.
    function depositCollateral(address caller, uint256 assets, uint256 shares, address receiver)
        external
        returns (uint256 assetsDeposited, uint256 sharesMinted);

    /// @notice Withdraws collateral from the pool.
    /// @dev Collateral amounts may be requested in underlying units (`assets`) or share units (`shares`). A concrete
    ///      pool defines which denominations it supports and rejects ambiguous requests.
    /// @param caller Account whose collateral position is debited.
    /// @param assets Collateral amount denominated in underlying units.
    /// @param shares Collateral amount denominated in pool share units, when supported by the pool.
    /// @param receiver Account that receives the withdrawn underlying.
    /// @return assetsWithdrawn Underlying amount actually withdrawn.
    /// @return sharesBurned Pool shares the withdrawal burned, or zero for a pool without shares.
    function withdrawCollateral(address caller, uint256 assets, uint256 shares, address receiver)
        external
        returns (uint256 assetsWithdrawn, uint256 sharesBurned);

    /// @notice Seizes collateral from a liquidated account's position.
    /// @dev Seizure amounts are always denominated in underlying units, which is what liquidation math produces. A pool
    ///      must settle a seizure out of the position itself rather than out of its available liquidity, so that a
    ///      liquidation cannot be blocked by the pool being lent out. What `receiver` is paid in therefore depends on
    ///      the pool: a pool holding transferable claims hands those over instead of redeeming them.
    /// @param violator Account whose collateral position is debited.
    /// @param assets Collateral amount to seize, denominated in underlying units.
    /// @param receiver Account that receives the seized collateral.
    /// @return assetsSeized Underlying amount the seizure was priced at.
    /// @return sharesSeized Pool shares transferred to `receiver`, or zero when settled in underlying.
    function seizeCollateral(address violator, uint256 assets, address receiver)
        external
        returns (uint256 assetsSeized, uint256 sharesSeized);

    /// @notice Borrows from the pool.
    /// @param caller Account whose loan records the borrow.
    /// @param amount Borrow amount denominated in underlying units.
    /// @param receiver Account that receives the borrowed underlying.
    function borrow(address caller, uint256 amount, address receiver) external;

    /// @notice Repays debt in the pool.
    /// @param caller Account providing the repayment funds.
    /// @param amount Repayment amount denominated in underlying units, capped by the receiver's debt.
    /// @param receiver Account whose debt is repaid.
    /// @return repayment Actual underlying amount repaid.
    function repay(address caller, uint256 amount, address receiver) external returns (uint256 repayment);

    /// @notice Writes off an account's outstanding debt in full without any repayment.
    /// @dev The debt leaves the pool's total assets with no underlying coming in to replace it, so the loss falls on
    ///      the pool's depositors pro rata through the share price.
    /// @param account Account whose debt is written off.
    /// @return writtenOff Underlying amount of debt written off.
    function writeOffDebt(address account) external returns (uint256 writtenOff);

    /// @notice Underlying asset the pool operates on.
    /// @dev The asset every pool operation moves: collateral is deposited, withdrawn and seized in it, and borrows are
    ///      drawn and repaid in it. Amounts the pool reports in underlying units are amounts of this asset.
    /// @return Underlying asset address.
    function asset() external view returns (address);

    /// @notice Total underlying assets accounted for by the pool.
    /// @dev Includes assets represented by collateral positions and interest where applicable. Current as of this
    ///      block, including interest not yet accrued. Does not represent immediately available or borrowable
    ///      liquidity.
    /// @return Total accounted assets in underlying asset units.
    function totalAssets() external view returns (uint256);

    /// @notice Total assets represented by outstanding collateral positions.
    /// @dev Current as of this block, including interest not yet accrued. Returns zero when the pool does not support
    ///      collateral.
    /// @return Total collateral in underlying asset units.
    function totalCollateral() external view returns (uint256);

    /// @notice Current aggregate outstanding debt in the pool.
    /// @dev Current as of this block, including interest not yet accrued. Returns zero when the pool does not support
    ///      borrowing.
    /// @return Outstanding debt in underlying asset units.
    function totalDebt() external view returns (uint256);

    /// @notice Collateral held by `account` in the pool.
    /// @dev Current as of this block, including interest not yet accrued. Returns zero when the pool does not support
    ///      collateral.
    /// @param account Account to query.
    /// @return Collateral in underlying asset units.
    function collateralOf(address account) external view returns (uint256);

    /// @notice Outstanding debt owed by `account` to the pool.
    /// @dev Current as of this block, including interest not yet accrued. Returns zero when the pool does not support
    ///      borrowing.
    /// @param account Account to query.
    /// @return Outstanding debt in underlying asset units.
    function debtOf(address account) external view returns (uint256);

    /// @notice LendingCore contract allowed to execute pool operations.
    /// @return LendingCore contract address.
    function lendingCore() external view returns (address);
}
