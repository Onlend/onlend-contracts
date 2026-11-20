// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IOracle} from "src/oracle/interfaces/IOracle.sol";
import {IPool} from "src/pool/interfaces/IPool.sol";

contract MockOracle is IOracle {
    mapping(IPool pool => PriceFeed) private _feeds;

    function setPrice(IPool pool, uint256 price, uint8 assetDecimals) external {
        _feeds[pool] = PriceFeed({price: price, assetDecimals: assetDecimals});
    }

    function getPrice(IPool pool) external view returns (PriceFeed memory) {
        return _feeds[pool];
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IOracle).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
