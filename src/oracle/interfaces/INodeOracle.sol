// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IPool} from "../../pool/interfaces/IPool.sol";
import {IVersioned} from "../../interfaces/IVersioned.sol";
import {INodeManager} from "../node-manager/interfaces/INodeManager.sol";
import {IOracle} from "./IOracle.sol";

/// @title  INodeOracle
/// @notice Maps pools to oracle nodes and exposes management of that configuration.
interface INodeOracle is IOracle, IVersioned {
    /// @notice Node configuration assigned to a pool.
    /// @param  nodeId         Identifier of the node in the node manager
    /// @param  assetDecimals  Decimals of the pool's underlying asset
    struct OracleNode {
        bytes32 nodeId;
        uint8 assetDecimals;
    }

    /// @notice Emitted when a pool's node configuration is set.
    /// @param  pool           Pool the configuration applies to
    /// @param  nodeId         Identifier of the node in the node manager
    /// @param  assetDecimals  Decimals of the pool's underlying asset
    event NodeIdSetForPool(IPool indexed pool, bytes32 nodeId, uint8 assetDecimals);

    /// @notice Emitted when the node manager is set.
    /// @param  nodeManager  Node manager contract
    event NodeManagerSet(address indexed nodeManager);

    /// @notice Thrown when the given address is not a valid node manager.
    /// @param  nodeManager  The invalid node manager address
    error InvalidNodeManager(address nodeManager);

    /// @notice Thrown when a pool has no node configured.
    /// @param  pool  The unconfigured pool
    error NoNodeIdForPool(IPool pool);

    /// @notice Sets the node manager used to resolve pool prices.
    /// @param  nodeManager  Node manager contract
    function setNodeManager(address nodeManager) external;

    /// @notice Sets the node configuration for a pool.
    /// @param  pool           Pool to configure
    /// @param  nodeId         Identifier of the node in the node manager
    /// @param  assetDecimals  Decimals of the pool's underlying asset
    function setNodeId(address pool, bytes32 nodeId, uint8 assetDecimals) external;

    /// @notice Returns the node manager used to resolve pool prices.
    /// @return Node manager contract
    function getNodeManager() external view returns (INodeManager);

    /// @notice Returns the node configuration for a pool.
    /// @param  pool  Pool to query
    /// @return       Node configuration assigned to the pool
    function getPoolNode(IPool pool) external view returns (OracleNode memory);
}
