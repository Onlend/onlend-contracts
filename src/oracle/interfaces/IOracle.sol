// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IPool} from "../../pool/interfaces/IPool.sol";

/// @title  IOracle
/// @notice Prices the underlying asset of a pool in the oracle numeraire.
interface IOracle is IERC165 {
    /// @notice Price of a pool's underlying asset.
    /// @param  price          Value of one whole unit of the underlying asset in the oracle numeraire, scaled by 18
    ///                        decimals
    /// @param  assetDecimals  Decimals of the pool's underlying asset, i.e. how many base units make one whole unit
    struct PriceFeed {
        uint256 price;
        uint8 assetDecimals;
    }

    /// @notice Returns the price of a pool's underlying asset.
    /// @param  pool  Pool whose underlying asset is priced
    /// @return       Price of one whole unit of the underlying asset, with that asset's decimals
    function getPrice(IPool pool) external view returns (PriceFeed calldata);
}
