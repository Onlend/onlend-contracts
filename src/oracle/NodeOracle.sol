// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {
    AccessControlEnumerableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {IPool} from "../pool/interfaces/IPool.sol";
import {INodeManager} from "./node-manager/interfaces/INodeManager.sol";
import {NodeOutput} from "./node-manager/lib/NodeOutput.sol";
import {IVersioned} from "../interfaces/IVersioned.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {INodeOracle} from "./interfaces/INodeOracle.sol";

/// @title  NodeOracle
/// @notice Maps pools to oracle nodes and resolves their prices via the node manager.
/// @dev    Implementation for EIP-1167 clones; configured via `initialize`, not a constructor.
contract NodeOracle is INodeOracle, AccessControlEnumerableUpgradeable {
    /// @notice Initial node configuration for a pool.
    /// @param  pool           Pool the configuration applies to
    /// @param  nodeId         Identifier of the node in the node manager
    /// @param  assetDecimals  Decimals of the pool's underlying asset
    struct PoolNodeConfig {
        address pool;
        bytes32 nodeId;
        uint8 assetDecimals;
    }

    /// @notice Role allowed to configure the node manager and pool nodes.
    bytes32 public constant NODE_UPDATER_ROLE = keccak256("NODE_UPDATER_ROLE");

    /// @dev Node manager used to resolve pool prices.
    INodeManager private _nodeManager;

    /// @dev Node configuration per pool.
    mapping(IPool pool => OracleNode node) private _poolNodes;

    /// @notice Locks the implementation so it can never be initialized or used directly.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes a clone with its role members and node manager.
    /// @dev Callable once per clone.
    /// @param  defaultAdmin      Account granted `DEFAULT_ADMIN_ROLE`, address(0) to leave unassigned
    /// @param  nodeUpdater       Account granted `NODE_UPDATER_ROLE`, address(0) to leave unassigned
    /// @param  nodeManager       Node manager used to resolve pool prices
    /// @param  poolNodes         Initial node configuration for each pool
    function initialize(
        address defaultAdmin,
        address nodeUpdater,
        address nodeManager,
        PoolNodeConfig[] calldata poolNodes
    ) external initializer {
        __AccessControlEnumerable_init();

        if (defaultAdmin != address(0)) _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        if (nodeUpdater != address(0)) _grantRole(NODE_UPDATER_ROLE, nodeUpdater);
        _setNodeManager(nodeManager);

        for (uint256 i; i < poolNodes.length; ++i) {
            PoolNodeConfig calldata poolNode = poolNodes[i];
            _setNodeId(poolNode.pool, poolNode.nodeId, poolNode.assetDecimals);
        }
    }

    /// @inheritdoc INodeOracle
    function setNodeManager(address nodeManager) external override onlyRole(NODE_UPDATER_ROLE) {
        _setNodeManager(nodeManager);
    }

    /// @inheritdoc INodeOracle
    /// @dev Reverts if `nodeId` cannot be processed so a pool's node can be replaced but not removed.
    function setNodeId(address pool, bytes32 nodeId, uint8 assetDecimals)
        external
        override
        onlyRole(NODE_UPDATER_ROLE)
    {
        _setNodeId(pool, nodeId, assetDecimals);
    }

    /// @inheritdoc IOracle
    function getPrice(IPool pool) external view override returns (IOracle.PriceFeed memory) {
        OracleNode memory node = _poolNodes[pool];
        if (node.nodeId == bytes32(0)) revert NoNodeIdForPool(pool);
        NodeOutput.Data memory output = _nodeManager.process(node.nodeId);
        return IOracle.PriceFeed({price: output.price, assetDecimals: node.assetDecimals});
    }

    /// @inheritdoc INodeOracle
    function getNodeManager() external view override returns (INodeManager) {
        return _nodeManager;
    }

    /// @inheritdoc INodeOracle
    function getPoolNode(IPool pool) external view override returns (OracleNode memory) {
        return _poolNodes[pool];
    }

    /// @inheritdoc IVersioned
    function contractName() external pure override returns (string memory) {
        return "NodeOracle";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure override returns (string memory) {
        return "1.0.0";
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlEnumerableUpgradeable, IERC165)
        returns (bool)
    {
        return interfaceId == type(IOracle).interfaceId || interfaceId == type(INodeOracle).interfaceId
            || interfaceId == type(IVersioned).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @notice Sets a pool's node configuration after validating the node.
    /// @param  pool           Pool to configure
    /// @param  nodeId         Identifier of the node in the node manager
    /// @param  assetDecimals  Decimals of the pool's underlying asset
    function _setNodeId(address pool, bytes32 nodeId, uint8 assetDecimals) private {
        _nodeManager.process(nodeId);
        _poolNodes[IPool(pool)] = OracleNode({nodeId: nodeId, assetDecimals: assetDecimals});
        emit NodeIdSetForPool(IPool(pool), nodeId, assetDecimals);
    }

    /// @notice Sets the node manager, validating it supports the expected interface.
    /// @param  nodeManager  Node manager used to resolve pool prices
    function _setNodeManager(address nodeManager) private {
        if (!ERC165Checker.supportsInterface(nodeManager, type(INodeManager).interfaceId)) {
            revert InvalidNodeManager(nodeManager);
        }
        _nodeManager = INodeManager(nodeManager);
        emit NodeManagerSet(nodeManager);
    }
}
