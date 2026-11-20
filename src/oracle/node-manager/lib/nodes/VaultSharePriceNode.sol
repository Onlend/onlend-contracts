// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {NodeDefinition} from "../NodeDefinition.sol";
import {NodeOutput} from "../NodeOutput.sol";

/// @title  VaultSharePriceNode
/// @notice Prices one whole share of an ERC-4626 vault from its parent's price of one whole underlying asset.
/// @dev    The rate is the vault's `convertToAssets` of one whole share, i.e. asset base units per whole share. The
///         price is `parentPrice * rate / 10 ** assetDecimals`, so share and asset decimals may differ.
///
///         Security considerations, all on the operator registering the node:
///         - Manipulation: the rate is read live. A donation raises it by real, redeemable value, but a vault whose
///           `totalAssets` can be moved temporarily, e.g. via a spot price, lets anyone skew the price.
///         - Read-only reentrancy: some vaults report an inconsistent `convertToAssets` while one of their own
///           operations is in progress, e.g. during a callback. Only use vaults whose conversion is consistent whenever
///           it can be read.
///         - Redeemable value: `convertToAssets` is the vault's fee-free accounting value, not what redeeming a share
///           returns. Exit fees, withdrawal queues, lockups or a paused vault make the price overstate what a
///           liquidation recovers. Only use vaults with immediate, fee-free redemption, or cover the gap with a
///           haircut.
///         - Rounding: the price rounds down, which is conservative for collateral but slightly undervalues the share
///           as debt; the error is below one asset base unit per whole share.
library VaultSharePriceNode {
    /// @notice Processes a VAULT_SHARE_PRICE node and returns its output.
    /// @dev    Reads the vault's decimals, asset, asset decimals and `convertToAssets` on every call, so an upgradeable
    ///         vault or asset is re-checked. Both `convertToAssets` and the price computation round down, so the price
    ///         is never above the exact value; the error is below one asset base unit per whole share. A zero rate, a
    ///         zero parent price, or a price that rounds down to zero is returned as a zero price. The timestamp is the
    ///         parent's, although the rate is read at `block.timestamp`. Reverts from the vault or asset are bubbled
    ///         up, and decimals above 77 or a price above `uint256` revert with an arithmetic panic.
    /// @param  parentNodeOutputs  Output of the parent node pricing one whole underlying asset
    /// @param  parameters         ABI-encoded vault address
    function process(NodeOutput.Data[] memory parentNodeOutputs, bytes memory parameters)
        internal
        view
        returns (NodeOutput.Data memory)
    {
        IERC4626 vault = IERC4626(abi.decode(parameters, (address)));

        uint256 rate = vault.convertToAssets(10 ** vault.decimals());

        uint256 price = Math.mulDiv(parentNodeOutputs[0].price, rate, 10 ** IERC20Metadata(vault.asset()).decimals());

        return NodeOutput.Data(price, parentNodeOutputs[0].timestamp, NodeDefinition.NodeType.VAULT_SHARE_PRICE, 0, 0);
    }

    /// @notice Returns true when the node definition is valid for a VAULT_SHARE_PRICE node.
    /// @dev    Requires exactly one parent and the vault to currently answer the calls made by `process`; reverts from
    ///         the vault or asset are bubbled up. None of this guarantees later behavior.
    /// @param  nodeDefinition  Node definition to validate
    function isValid(NodeDefinition.Data memory nodeDefinition) internal view returns (bool) {
        if (nodeDefinition.parents.length != 1 || nodeDefinition.parameters.length != 32) return false;

        /// @dev Check the vault and its asset answer the calls made by `process`
        IERC4626 vault = IERC4626(abi.decode(nodeDefinition.parameters, (address)));
        vault.convertToAssets(10 ** vault.decimals());
        IERC20Metadata(vault.asset()).decimals();

        return true;
    }
}
