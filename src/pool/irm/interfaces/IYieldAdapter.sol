// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IVersioned} from "../../../interfaces/IVersioned.sol";

/// @title Yield Adapter Interface
/// @notice Reports an external APR, measured over a caller-chosen lookback window.
interface IYieldAdapter is IERC165, IVersioned {
    /// @notice Returns whether the adapter can report an APR measured over a lookback window.
    /// @param window Lookback window, in seconds.
    /// @return True if `apr` supports `window`.
    function isValidWindow(uint256 window) external view returns (bool);

    /// @notice Returns the APR measured over a lookback window.
    /// @dev `window` must have previously been accepted by `isValidWindow`.
    /// @param window Lookback window, in seconds.
    /// @return apr_ APR, scaled to 18dp. Negative if the source lost value over the window.
    /// @return updatedAt Timestamp of the most recent observation `apr_` is derived from, or zero if no APR is
    ///         available.
    function apr(uint256 window) external view returns (int256 apr_, uint256 updatedAt);
}
