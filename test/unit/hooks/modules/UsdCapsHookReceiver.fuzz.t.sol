// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

import {Phase} from "src/hooks/interfaces/IHookReceiver.sol";
import {ActionLib} from "src/hooks/lib/ActionLib.sol";
import {CapsHookReceiver} from "src/hooks/modules/abstract/CapsHookReceiver.sol";
import {UsdCapsHookReceiver} from "src/hooks/modules/UsdCapsHookReceiver.sol";
import {IOracle} from "src/oracle/interfaces/IOracle.sol";
import {IPool} from "src/pool/interfaces/IPool.sol";
import {MockOracle} from "../../../mocks/MockOracle.sol";
import {MockPool} from "../../pool/mocks/MockPool.sol";

contract UsdCapsHookReceiverFuzzTest is Test {
    CapsHookReceiver.CapType internal constant SUPPLY_CAP = CapsHookReceiver.CapType.Supply;

    address internal capsConfigurator;
    MockOracle internal oracle;
    UsdCapsHookReceiver internal capsHookReceiver;

    function setUp() public {
        capsConfigurator = makeAddr("capsConfigurator");
        oracle = new MockOracle();
        UsdCapsHookReceiver implementation = new UsdCapsHookReceiver();
        capsHookReceiver = UsdCapsHookReceiver(Clones.clone(address(implementation)));
        capsHookReceiver.initialize(
            makeAddr("defaultAdmin"),
            capsConfigurator,
            makeAddr("oracleUpdater"),
            address(oracle),
            new CapsHookReceiver.PoolCapConfig[](0)
        );
    }

    function testFuzz_onHook_AfterDepositAllowsWhenPositivePriceDoesNotExceedUnitScale(
        uint256 amount,
        uint256 price,
        uint8 decimals
    ) public {
        decimals = uint8(bound(decimals, 0, 77));
        uint256 unitScale = 10 ** decimals;
        price = bound(price, 1, unitScale);
        address pool = _deployPool(amount);
        _mockPrice(pool, price, decimals);
        _addCap(pool, amount);

        capsHookReceiver.onHook(pool, Phase.AFTER, ActionLib.POOL_DEPOSIT, "");
    }

    function testFuzz_onHook_AfterDepositRevertsWhenPriceExceedsUnitScale(uint128 amount, uint256 price, uint8 decimals)
        public
    {
        amount = uint128(bound(amount, 1, type(uint128).max));
        decimals = uint8(bound(decimals, 0, 77));
        uint256 unitScale = 10 ** decimals;
        uint256 maxPrice = unitScale > type(uint256).max / 2 ? type(uint256).max : unitScale * 2;
        price = bound(price, unitScale + 1, maxPrice);
        address pool = _deployPool(amount);
        _mockPrice(pool, price, decimals);
        _addCap(pool, amount);

        vm.expectPartialRevert(CapsHookReceiver.CapExceeded.selector);
        capsHookReceiver.onHook(pool, Phase.AFTER, ActionLib.POOL_DEPOSIT, "");
    }

    function _addCap(address pool, uint256 limit) internal {
        vm.prank(capsConfigurator);
        capsHookReceiver.addCap(pool, SUPPLY_CAP, limit);
    }

    function _deployPool(uint256 totalAssets) internal returns (address) {
        MockPool pool = new MockPool();
        pool.setTotals(totalAssets, 0, 0);
        return address(pool);
    }

    function _mockPrice(address pool, uint256 price, uint8 decimals) internal {
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(IOracle.getPrice.selector, IPool(pool)),
            abi.encode(IOracle.PriceFeed({price: price, assetDecimals: decimals}))
        );
    }
}
