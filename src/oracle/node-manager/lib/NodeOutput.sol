// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {NodeDefinition} from "./NodeDefinition.sol";

/// @title  NodeOutput
/// @notice Result type produced by processing an oracle feed node.
library NodeOutput {
    /// @notice Result produced by processing a node.
    /// @param  price             Asset price expressed in 18 decimal places.
    /// @param  timestamp         Time at which the price was observed or computed.
    /// @param  nodeType          Type of the node that produced this output.
    /// @param  additionalParam1  First auxiliary value; interpretation is node-type specific.
    /// @param  additionalParam2  Second auxiliary value; interpretation is node-type specific.
    struct Data {
        uint256 price;
        uint256 timestamp;
        NodeDefinition.NodeType nodeType;
        uint256 additionalParam1;
        uint256 additionalParam2;
    }
}
