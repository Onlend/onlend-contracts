// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {stdError} from "forge-std/StdError.sol";
import {Test} from "forge-std/Test.sol";

import {VaultSharePriceNode} from "src/oracle/node-manager/lib/nodes/VaultSharePriceNode.sol";
import {NodeDefinition} from "src/oracle/node-manager/lib/NodeDefinition.sol";
import {NodeOutput} from "src/oracle/node-manager/lib/NodeOutput.sol";
import {MockERC20Decimals} from "../../mocks/MockERC20Decimals.sol";
import {MockERC4626Vault} from "../../mocks/MockERC4626Vault.sol";

contract VaultSharePriceNodeTest is Test {
    uint256 internal constant NOW = 1000;
    uint256 internal constant PARENT_TIMESTAMP = 900;

    MockERC20Decimals internal asset;
    MockERC4626Vault internal vault;

    function setUp() public {
        vm.warp(NOW);
        asset = new MockERC20Decimals(6);
        vault = new MockERC4626Vault(address(asset), 6, 1.05e6);
    }

    // process()

    function test_Process_ReturnsCorrectOutput() public view {
        NodeOutput.Data memory output = VaultSharePriceNode.process(_parent(1e18), abi.encode(address(vault)));

        assertEq(output.price, 1.05e18);
        assertEq(output.timestamp, PARENT_TIMESTAMP);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.VAULT_SHARE_PRICE));
        assertEq(output.additionalParam1, 0);
        assertEq(output.additionalParam2, 0);
    }

    function test_Process_ScalesWithParentPrice() public view {
        NodeOutput.Data memory output = VaultSharePriceNode.process(_parent(2000e18), abi.encode(address(vault)));

        assertEq(output.price, 2100e18);
    }

    function test_Process_UsesAssetDecimalsWithDecimalsOffset() public {
        vault.setDecimals(18);

        NodeOutput.Data memory output = VaultSharePriceNode.process(_parent(1e18), abi.encode(address(vault)));

        assertEq(output.price, 1.05e18);
    }

    function test_Process_UsesAssetDecimalsWhenSharesHaveFewerDecimals() public {
        asset.setDecimals(18);
        vault.setDecimals(6);
        vault.setRate(1.05e18);

        NodeOutput.Data memory output = VaultSharePriceNode.process(_parent(1e18), abi.encode(address(vault)));

        assertEq(output.price, 1.05e18);
    }

    function test_Process_ScalesFromZeroDecimals() public {
        asset.setDecimals(0);
        vault.setDecimals(0);
        vault.setRate(2);

        NodeOutput.Data memory output = VaultSharePriceNode.process(_parent(1e18), abi.encode(address(vault)));

        assertEq(output.price, 2e18);
    }

    function test_Process_ScalesFromAssetDecimalsBelowEighteen() public {
        asset.setDecimals(2);
        vault.setDecimals(2);
        vault.setRate(105);

        NodeOutput.Data memory output = VaultSharePriceNode.process(_parent(1e18), abi.encode(address(vault)));

        assertEq(output.price, 1.05e18);
    }

    function test_Process_ScalesFromEighteenDecimals() public {
        asset.setDecimals(18);
        vault.setDecimals(18);
        vault.setRate(1.05e18);

        NodeOutput.Data memory output = VaultSharePriceNode.process(_parent(1e18), abi.encode(address(vault)));

        assertEq(output.price, 1.05e18);
    }

    function test_Process_ScalesFromAssetDecimalsAboveEighteen() public {
        asset.setDecimals(24);
        vault.setDecimals(24);
        vault.setRate(1.05e24);

        NodeOutput.Data memory output = VaultSharePriceNode.process(_parent(1e18), abi.encode(address(vault)));

        assertEq(output.price, 1.05e18);
    }

    function test_Process_ScalesFromMaxDecimals() public {
        asset.setDecimals(77);
        vault.setDecimals(77);
        vault.setRate(1.05e77);

        NodeOutput.Data memory output = VaultSharePriceNode.process(_parent(1e18), abi.encode(address(vault)));

        assertEq(output.price, 1.05e18);
    }

    function test_Process_RoundsDown() public {
        vault.setRate(1.5e6);

        NodeOutput.Data memory output = VaultSharePriceNode.process(_parent(3), abi.encode(address(vault)));

        assertEq(output.price, 4);
    }

    function test_Process_ReturnsZeroWhenPriceRoundsDownToZero() public {
        vault.setRate(0.5e6);

        NodeOutput.Data memory output = VaultSharePriceNode.process(_parent(1), abi.encode(address(vault)));

        assertEq(output.price, 0);
    }

    function test_Process_ReturnsZeroForZeroRate() public {
        vault.setRate(0);

        NodeOutput.Data memory output = VaultSharePriceNode.process(_parent(1e18), abi.encode(address(vault)));

        assertEq(output.price, 0);
        assertEq(output.timestamp, PARENT_TIMESTAMP);
    }

    function test_Process_ReturnsZeroForZeroParentPrice() public view {
        NodeOutput.Data memory output = VaultSharePriceNode.process(_parent(0), abi.encode(address(vault)));

        assertEq(output.price, 0);
        assertEq(output.timestamp, PARENT_TIMESTAMP);
    }

    function test_Process_Revert_ShareDecimalsOverflow() public {
        vault.setDecimals(78);

        vm.expectRevert(stdError.arithmeticError);
        this.process(_parent(1e18), abi.encode(address(vault)));
    }

    function test_Process_Revert_AssetDecimalsOverflow() public {
        asset.setDecimals(78);

        vm.expectRevert(stdError.arithmeticError);
        this.process(_parent(1e18), abi.encode(address(vault)));
    }

    function test_Process_Revert_PriceOverflows() public {
        vm.expectRevert(stdError.arithmeticError);
        this.process(_parent(type(uint256).max), abi.encode(address(vault)));
    }

    function test_Process_Revert_ShareDecimalsReverts() public {
        vault.setShouldRevertOnDecimals(true);

        vm.expectRevert(MockERC4626Vault.DecimalsReverted.selector);
        this.process(_parent(1e18), abi.encode(address(vault)));
    }

    function test_Process_Revert_AssetReverts() public {
        vault.setShouldRevertOnAsset(true);

        vm.expectRevert(MockERC4626Vault.AssetReverted.selector);
        this.process(_parent(1e18), abi.encode(address(vault)));
    }

    function test_Process_Revert_AssetDecimalsReverts() public {
        asset.setShouldRevertOnDecimals(true);

        vm.expectRevert(MockERC20Decimals.DecimalsReverted.selector);
        this.process(_parent(1e18), abi.encode(address(vault)));
    }

    function test_Process_Revert_ConvertToAssetsReverts() public {
        vault.setShouldRevertOnConvertToAssets(true);

        vm.expectRevert(MockERC4626Vault.ConvertToAssetsReverted.selector);
        this.process(_parent(1e18), abi.encode(address(vault)));
    }

    function test_Process_Revert_VaultHasNoCode() public {
        vm.expectRevert();
        this.process(_parent(1e18), abi.encode(makeAddr("eoa")));
    }

    function test_Process_Revert_AssetHasNoCode() public {
        vault.setAsset(makeAddr("eoa"));

        vm.expectRevert();
        this.process(_parent(1e18), abi.encode(address(vault)));
    }

    // isValid()

    function test_IsValid_ReturnsTrueForVault() public view {
        assertTrue(VaultSharePriceNode.isValid(_definition(abi.encode(address(vault)), 1)));
    }

    function test_IsValid_ReturnsTrueWhenRateIsZero() public {
        vault.setRate(0);

        assertTrue(VaultSharePriceNode.isValid(_definition(abi.encode(address(vault)), 1)));
    }

    function test_IsValid_ReturnsFalseWhenHasNoParents() public view {
        assertFalse(VaultSharePriceNode.isValid(_definition(abi.encode(address(vault)), 0)));
    }

    function test_IsValid_ReturnsFalseWhenHasTwoParents() public view {
        assertFalse(VaultSharePriceNode.isValid(_definition(abi.encode(address(vault)), 2)));
    }

    function test_IsValid_ReturnsFalseWhenParamsEmpty() public view {
        assertFalse(VaultSharePriceNode.isValid(_definition("", 1)));
    }

    function test_IsValid_ReturnsFalseWhenParamsBelow32Bytes() public view {
        assertFalse(VaultSharePriceNode.isValid(_definition(new bytes(31), 1)));
    }

    function test_IsValid_ReturnsFalseWhenParamsAbove32Bytes() public view {
        assertFalse(VaultSharePriceNode.isValid(_definition(abi.encodePacked(abi.encode(address(vault)), uint8(0)), 1)));
    }

    function test_IsValid_ReturnsTrueForMaxDecimals() public {
        asset.setDecimals(77);
        vault.setDecimals(77);
        vault.setRate(1e77);

        assertTrue(VaultSharePriceNode.isValid(_definition(abi.encode(address(vault)), 1)));
    }

    function test_IsValid_Revert_ShareDecimalsOverflow() public {
        vault.setDecimals(78);

        vm.expectRevert(stdError.arithmeticError);
        this.isValid(_definition(abi.encode(address(vault)), 1));
    }

    function test_IsValid_Revert_ShareDecimalsReverts() public {
        vault.setShouldRevertOnDecimals(true);

        vm.expectRevert(MockERC4626Vault.DecimalsReverted.selector);
        this.isValid(_definition(abi.encode(address(vault)), 1));
    }

    function test_IsValid_Revert_AssetReverts() public {
        vault.setShouldRevertOnAsset(true);

        vm.expectRevert(MockERC4626Vault.AssetReverted.selector);
        this.isValid(_definition(abi.encode(address(vault)), 1));
    }

    function test_IsValid_Revert_AssetDecimalsReverts() public {
        asset.setShouldRevertOnDecimals(true);

        vm.expectRevert(MockERC20Decimals.DecimalsReverted.selector);
        this.isValid(_definition(abi.encode(address(vault)), 1));
    }

    function test_IsValid_Revert_ConvertToAssetsReverts() public {
        vault.setShouldRevertOnConvertToAssets(true);

        vm.expectRevert(MockERC4626Vault.ConvertToAssetsReverted.selector);
        this.isValid(_definition(abi.encode(address(vault)), 1));
    }

    function test_IsValid_Revert_VaultHasNoCode() public {
        vm.expectRevert();
        this.isValid(_definition(abi.encode(makeAddr("eoa")), 1));
    }

    function test_IsValid_Revert_AssetHasNoCode() public {
        vault.setAsset(makeAddr("eoa"));

        vm.expectRevert();
        this.isValid(_definition(abi.encode(address(vault)), 1));
    }

    /// @dev External wrapper so `vm.expectRevert` can catch reverts from the internal library call.
    function process(NodeOutput.Data[] memory parentNodeOutputs, bytes memory parameters)
        external
        view
        returns (NodeOutput.Data memory)
    {
        return VaultSharePriceNode.process(parentNodeOutputs, parameters);
    }

    /// @dev External wrapper so `vm.expectRevert` can catch reverts from the internal library call.
    function isValid(NodeDefinition.Data memory nodeDefinition) external view returns (bool) {
        return VaultSharePriceNode.isValid(nodeDefinition);
    }

    function _parent(uint256 price) internal pure returns (NodeOutput.Data[] memory parentNodeOutputs) {
        parentNodeOutputs = new NodeOutput.Data[](1);
        parentNodeOutputs[0] = NodeOutput.Data(price, PARENT_TIMESTAMP, NodeDefinition.NodeType.CONSTANT, 0, 0);
    }

    function _definition(bytes memory parameters, uint256 parentCount)
        internal
        pure
        returns (NodeDefinition.Data memory)
    {
        return NodeDefinition.Data({
            nodeType: NodeDefinition.NodeType.VAULT_SHARE_PRICE,
            parameters: parameters,
            parents: new bytes32[](parentCount)
        });
    }
}
