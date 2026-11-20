// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Test} from "forge-std/Test.sol";

import {IPool} from "src/pool/interfaces/IPool.sol";
import {MockOracle} from "../../../mocks/MockOracle.sol";
import {OracleConsumerHarness} from "./mocks/OracleConsumerHarness.sol";

contract OracleConsumerFuzzTest is Test {
    /// @dev Keeps the converted value inside uint256 for every fuzzed combination.
    uint256 internal constant MAX_AMOUNT = 1e30;
    uint256 internal constant MAX_PRICE = 1e30;

    /// @dev Largest underlying-asset decimals for which `10 ** decimals` fits in uint256.
    uint8 internal constant MAX_ASSET_DECIMALS = 77;

    IPool internal pool;
    MockOracle internal oracle;
    OracleConsumerHarness internal consumer;

    function setUp() public {
        pool = IPool(makeAddr("pool"));
        oracle = new MockOracle();

        OracleConsumerHarness implementation = new OracleConsumerHarness();
        consumer = OracleConsumerHarness(Clones.clone(address(implementation)));
        consumer.initialize(makeAddr("defaultAdmin"), makeAddr("oracleUpdater"), address(oracle));
    }

    // _oracleValue()

    function testFuzz_oracleValue_ReturnsAmountWhenPriceIsOne(uint256 amount, uint8 decimals) public {
        amount = bound(amount, 0, MAX_AMOUNT);
        decimals = uint8(bound(decimals, 0, MAX_ASSET_DECIMALS));
        oracle.setPrice(pool, 10 ** decimals, decimals);

        assertEq(consumer.oracleValue(pool, amount, Math.Rounding.Floor), amount);
        assertEq(consumer.oracleValue(pool, amount, Math.Rounding.Ceil), amount);
    }

    function testFuzz_oracleValue_ReturnsZeroWhenAmountIsZero(uint256 price, uint8 decimals) public {
        price = bound(price, 0, MAX_PRICE);
        decimals = uint8(bound(decimals, 0, MAX_ASSET_DECIMALS));
        oracle.setPrice(pool, price, decimals);

        assertEq(consumer.oracleValue(pool, 0, Math.Rounding.Ceil), 0);
    }

    function testFuzz_oracleValue_ReturnsZeroWhenPriceIsZero(uint256 amount, uint8 decimals) public {
        amount = bound(amount, 0, MAX_AMOUNT);
        decimals = uint8(bound(decimals, 0, MAX_ASSET_DECIMALS));
        oracle.setPrice(pool, 0, decimals);

        assertEq(consumer.oracleValue(pool, amount, Math.Rounding.Ceil), 0);
    }

    function testFuzz_oracleValue_CeilExceedsFloorByAtMostOne(uint256 amount, uint256 price, uint8 decimals) public {
        amount = bound(amount, 0, MAX_AMOUNT);
        price = bound(price, 0, MAX_PRICE);
        decimals = uint8(bound(decimals, 0, MAX_ASSET_DECIMALS));
        oracle.setPrice(pool, price, decimals);

        uint256 floorValue = consumer.oracleValue(pool, amount, Math.Rounding.Floor);
        uint256 ceilValue = consumer.oracleValue(pool, amount, Math.Rounding.Ceil);

        assertGe(ceilValue, floorValue);
        assertLe(ceilValue - floorValue, 1);
    }
}
