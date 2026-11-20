// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {stdError} from "forge-std/StdError.sol";
import {Test} from "forge-std/Test.sol";

import {VaultSharePriceNode} from "src/oracle/node-manager/lib/nodes/VaultSharePriceNode.sol";
import {NodeDefinition} from "src/oracle/node-manager/lib/NodeDefinition.sol";
import {NodeOutput} from "src/oracle/node-manager/lib/NodeOutput.sol";
import {MockERC20Decimals} from "../../mocks/MockERC20Decimals.sol";
import {MockERC4626Vault} from "../../mocks/MockERC4626Vault.sol";

contract VaultSharePriceNodeFuzzTest is Test {
    uint256 internal constant PARENT_TIMESTAMP = 900;

    /// @dev Bounds on prices and rates, so `price * rate` fits `uint256` at any supported decimals.
    uint256 internal constant MAX_PRICE = 1e36;
    uint256 internal constant MAX_RATE = 1e36;

    /// @dev Largest decimals for which `10 ** decimals` fits `uint256`.
    uint8 internal constant MAX_DECIMALS = 77;

    MockERC20Decimals internal asset;
    MockERC4626Vault internal vault;

    function setUp() public {
        asset = new MockERC20Decimals(6);
        vault = new MockERC4626Vault(address(asset), 6, 1.05e6);
    }

    // process()

    function testFuzz_Process_PreservesWholeUnitsAtAnyDecimals(
        uint256 parentPrice,
        uint256 units,
        uint8 shareDecimals,
        uint8 assetDecimals
    ) public {
        parentPrice = bound(parentPrice, 0, MAX_PRICE);
        shareDecimals = uint8(bound(shareDecimals, 0, MAX_DECIMALS));
        assetDecimals = uint8(bound(assetDecimals, 0, MAX_DECIMALS));
        units = bound(units, 1, Math.min(1e6, type(uint256).max / 10 ** assetDecimals));
        asset.setDecimals(assetDecimals);
        vault.setDecimals(shareDecimals);
        vault.setRate(units * 10 ** assetDecimals);

        NodeOutput.Data memory output = VaultSharePriceNode.process(_parent(parentPrice), _params());

        assertEq(output.price, parentPrice * units);
    }

    function testFuzz_Process_IsNonDecreasingInParentPrice(
        uint256 lower,
        uint256 higher,
        uint256 rate,
        uint8 assetDecimals
    ) public {
        lower = bound(lower, 0, MAX_PRICE - 1);
        higher = bound(higher, lower + 1, MAX_PRICE);
        rate = bound(rate, 1, MAX_RATE);
        assetDecimals = uint8(bound(assetDecimals, 0, MAX_DECIMALS));
        asset.setDecimals(assetDecimals);
        vault.setRate(rate);
        uint256 lowerPrice = VaultSharePriceNode.process(_parent(lower), _params()).price;

        uint256 higherPrice = VaultSharePriceNode.process(_parent(higher), _params()).price;

        assertGe(higherPrice, lowerPrice);
    }

    function testFuzz_Process_IsNonDecreasingInRate(uint256 parentPrice, uint256 lower, uint256 higher) public {
        parentPrice = bound(parentPrice, 0, MAX_PRICE);
        lower = bound(lower, 1, MAX_RATE - 1);
        higher = bound(higher, lower + 1, MAX_RATE);
        vault.setRate(lower);
        uint256 lowerPrice = VaultSharePriceNode.process(_parent(parentPrice), _params()).price;
        vault.setRate(higher);

        uint256 higherPrice = VaultSharePriceNode.process(_parent(parentPrice), _params()).price;

        assertGe(higherPrice, lowerPrice);
    }

    function testFuzz_Process_ReturnsParentTimestamp(uint256 now_, uint256 parentTimestamp) public {
        now_ = bound(now_, 0, type(uint64).max);
        vm.warp(now_);
        NodeOutput.Data[] memory parentNodeOutputs = _parent(1e18);
        parentNodeOutputs[0].timestamp = parentTimestamp;

        NodeOutput.Data memory output = VaultSharePriceNode.process(parentNodeOutputs, _params());

        assertEq(output.timestamp, parentTimestamp);
        assertEq(uint8(output.nodeType), uint8(NodeDefinition.NodeType.VAULT_SHARE_PRICE));
    }

    function testFuzz_Process_RevertsWhenShareDecimalsOverflow(uint8 shareDecimals) public {
        shareDecimals = uint8(bound(shareDecimals, MAX_DECIMALS + 1, type(uint8).max));
        vault.setDecimals(shareDecimals);

        vm.expectRevert(stdError.arithmeticError);
        this.process(_parent(1e18), _params());
    }

    function testFuzz_Process_RevertsWhenAssetDecimalsOverflow(uint8 assetDecimals) public {
        assetDecimals = uint8(bound(assetDecimals, MAX_DECIMALS + 1, type(uint8).max));
        asset.setDecimals(assetDecimals);

        vm.expectRevert(stdError.arithmeticError);
        this.process(_parent(1e18), _params());
    }

    function testFuzz_Process_ReturnsZeroForZeroRate(uint256 parentPrice, uint8 shareDecimals) public {
        shareDecimals = uint8(bound(shareDecimals, 0, MAX_DECIMALS));
        vault.setDecimals(shareDecimals);
        vault.setRate(0);

        NodeOutput.Data memory output = VaultSharePriceNode.process(_parent(parentPrice), _params());

        assertEq(output.price, 0);
    }

    // isValid()

    function testFuzz_IsValid_ReturnsTrueWhenDecimalsFit(uint8 shareDecimals, uint8 assetDecimals, uint256 rate)
        public
    {
        shareDecimals = uint8(bound(shareDecimals, 0, MAX_DECIMALS));
        assetDecimals = uint8(bound(assetDecimals, 0, MAX_DECIMALS));
        rate = bound(rate, 0, MAX_RATE);
        vault.setDecimals(shareDecimals);
        asset.setDecimals(assetDecimals);
        vault.setRate(rate);

        assertTrue(VaultSharePriceNode.isValid(_definition(_params(), 1)));
    }

    function testFuzz_IsValid_RevertsWhenShareDecimalsOverflow(uint8 shareDecimals) public {
        shareDecimals = uint8(bound(shareDecimals, MAX_DECIMALS + 1, type(uint8).max));
        vault.setDecimals(shareDecimals);

        vm.expectRevert(stdError.arithmeticError);
        this.isValid(_definition(_params(), 1));
    }

    function testFuzz_IsValid_ReturnsFalseWhenParentCountNotOne(uint256 parentCount) public view {
        parentCount = bound(parentCount, 0, 15);
        if (parentCount >= 1) ++parentCount;

        assertFalse(VaultSharePriceNode.isValid(_definition(_params(), parentCount)));
    }

    function testFuzz_IsValid_ReturnsFalseWhenParamsLengthNot32(uint256 length) public view {
        length = bound(length, 0, 255);
        if (length >= 32) ++length;

        assertFalse(VaultSharePriceNode.isValid(_definition(new bytes(length), 1)));
    }

    function testFuzz_IsValid_RevertsWhenVaultAddressAboveMax(uint256 raw) public {
        raw = bound(raw, uint256(type(uint160).max) + 1, type(uint256).max);

        vm.expectRevert();
        this.isValid(_definition(abi.encode(raw), 1));
    }

    function testFuzz_IsValid_RevertsWhenVaultHasNoCode(uint256 privateKey) public {
        privateKey = bound(privateKey, 1, SECP256K1_ORDER - 1);

        vm.expectRevert();
        this.isValid(_definition(abi.encode(vm.addr(privateKey)), 1));
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

    function _params() internal view returns (bytes memory) {
        return abi.encode(address(vault));
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
