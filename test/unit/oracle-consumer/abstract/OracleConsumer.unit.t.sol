// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {stdError, Test} from "forge-std/Test.sol";

import {OracleConsumer} from "src/oracle-consumer/abstract/OracleConsumer.sol";
import {IOracle} from "src/oracle/interfaces/IOracle.sol";
import {IPool} from "src/pool/interfaces/IPool.sol";
import {MockOracle} from "../../../mocks/MockOracle.sol";
import {OracleConsumerHarness} from "./mocks/OracleConsumerHarness.sol";

contract OracleConsumerUnitTest is Test {
    /// @dev Largest underlying-asset decimals for which `10 ** decimals` fits in uint256.
    uint8 internal constant MAX_ASSET_DECIMALS = 77;

    address internal defaultAdmin;
    address internal oracleUpdater;
    address internal nonOracleUpdater;
    IPool internal pool;
    MockOracle internal oracle;

    OracleConsumerHarness internal implementation;
    OracleConsumerHarness internal consumer;

    function setUp() public {
        defaultAdmin = makeAddr("defaultAdmin");
        oracleUpdater = makeAddr("oracleUpdater");
        nonOracleUpdater = makeAddr("nonOracleUpdater");
        pool = IPool(makeAddr("pool"));
        oracle = new MockOracle();

        implementation = new OracleConsumerHarness();
        consumer = _deploy();
    }

    // _initializeOracleConsumer()

    function test_initializeOracleConsumer_SetsOracle() public view {
        assertEq(consumer.oracle(), address(oracle));
    }

    function test_initializeOracleConsumer_GrantsOracleUpdaterRole() public view {
        assertTrue(consumer.hasRole(consumer.ORACLE_UPDATER_ROLE(), oracleUpdater));
    }

    function test_initializeOracleConsumer_UsesDefaultAdminAsOracleUpdaterRoleAdmin() public view {
        assertEq(consumer.getRoleAdmin(consumer.ORACLE_UPDATER_ROLE()), consumer.DEFAULT_ADMIN_ROLE());
    }

    function test_initializeOracleConsumer_AllowsZeroOracleUpdater() public {
        OracleConsumerHarness instance = _clone();

        instance.initialize(defaultAdmin, address(0), address(oracle));

        assertEq(instance.getRoleMemberCount(instance.ORACLE_UPDATER_ROLE()), 0);
    }

    function test_initializeOracleConsumer_EmitsOracleUpdated() public {
        OracleConsumerHarness instance = _clone();

        vm.expectEmit(address(instance));
        emit OracleConsumer.OracleUpdated(address(0), address(oracle));

        instance.initialize(defaultAdmin, oracleUpdater, address(oracle));
    }

    function test_initializeOracleConsumer_RevertsWhenOracleIsInvalid() public {
        OracleConsumerHarness instance = _clone();
        address invalidOracle = makeAddr("invalidOracle");

        vm.expectRevert(abi.encodeWithSelector(OracleConsumer.InvalidOracle.selector, invalidOracle));
        instance.initialize(defaultAdmin, oracleUpdater, invalidOracle);
    }

    function test_initializeOracleConsumer_RevertsWhenOracleIsZeroAddress() public {
        OracleConsumerHarness instance = _clone();

        vm.expectRevert(abi.encodeWithSelector(OracleConsumer.InvalidOracle.selector, address(0)));
        instance.initialize(defaultAdmin, oracleUpdater, address(0));
    }

    // updateOracle()

    function test_updateOracle_SetsOracle() public {
        MockOracle newOracle = new MockOracle();

        vm.prank(oracleUpdater);
        consumer.updateOracle(address(newOracle));

        assertEq(consumer.oracle(), address(newOracle));
    }

    function test_updateOracle_EmitsOracleUpdated() public {
        MockOracle newOracle = new MockOracle();

        vm.expectEmit(address(consumer));
        emit OracleConsumer.OracleUpdated(address(oracle), address(newOracle));

        vm.prank(oracleUpdater);
        consumer.updateOracle(address(newOracle));
    }

    function test_updateOracle_RevertsWhenCallerIsNotOracleUpdater() public {
        MockOracle newOracle = new MockOracle();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonOracleUpdater,
                consumer.ORACLE_UPDATER_ROLE()
            )
        );
        vm.prank(nonOracleUpdater);
        consumer.updateOracle(address(newOracle));
    }

    function test_updateOracle_RevertsWhenOracleIsInvalid() public {
        address invalidOracle = makeAddr("invalidOracle");

        vm.expectRevert(abi.encodeWithSelector(OracleConsumer.InvalidOracle.selector, invalidOracle));
        vm.prank(oracleUpdater);
        consumer.updateOracle(invalidOracle);
    }

    function test_updateOracle_RevertsWhenOracleIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(OracleConsumer.InvalidOracle.selector, address(0)));
        vm.prank(oracleUpdater);
        consumer.updateOracle(address(0));
    }

    // _oracleValue()

    function test_oracleValue_RequestsPriceForPool() public {
        oracle.setPrice(pool, 1e18, 18);

        vm.expectCall(address(oracle), abi.encodeWithSelector(IOracle.getPrice.selector, pool));

        consumer.oracleValue(pool, 100e18, Math.Rounding.Floor);
    }

    function test_oracleValue_ScalesAmountByPrice() public {
        // One whole unit of an 18-decimal asset is worth 2, so 100 whole units are worth 200.
        oracle.setPrice(pool, 2e18, 18);

        assertEq(consumer.oracleValue(pool, 100e18, Math.Rounding.Floor), 200e18);
    }

    function test_oracleValue_ReturnsZeroForZeroAmount() public {
        oracle.setPrice(pool, 2e18, 18);

        assertEq(consumer.oracleValue(pool, 0, Math.Rounding.Floor), 0);
    }

    function test_oracleValue_ReturnsZeroForZeroPrice() public {
        oracle.setPrice(pool, 0, 18);

        assertEq(consumer.oracleValue(pool, 100e18, Math.Rounding.Ceil), 0);
    }

    function test_oracleValue_RoundsDownWhenRoundingIsFloor() public {
        // A 1-decimal asset priced at 1 makes 1001 base units, i.e. 100.1 whole units, worth 100.1.
        oracle.setPrice(pool, 1, 1);

        assertEq(consumer.oracleValue(pool, 1001, Math.Rounding.Floor), 100);
    }

    function test_oracleValue_RoundsUpWhenRoundingIsCeil() public {
        // A 1-decimal asset priced at 1 makes 1001 base units, i.e. 100.1 whole units, worth 100.1.
        oracle.setPrice(pool, 1, 1);

        assertEq(consumer.oracleValue(pool, 1001, Math.Rounding.Ceil), 101);
    }

    function test_oracleValue_DoesNotOverflowWhenIntermediateProductExceedsUint256() public {
        // The price matches the asset decimals, so the value equals the base-unit amount despite the
        // intermediate amount * price product exceeding uint256.
        oracle.setPrice(pool, 1e18, 18);

        assertEq(consumer.oracleValue(pool, type(uint256).max, Math.Rounding.Floor), type(uint256).max);
    }

    function test_oracleValue_SupportsMaxAssetDecimals() public {
        // 10 ** 77 is the largest power of ten that fits in uint256; the price matches the asset decimals,
        // so the value equals the base-unit amount.
        oracle.setPrice(pool, 10 ** MAX_ASSET_DECIMALS, MAX_ASSET_DECIMALS);

        assertEq(consumer.oracleValue(pool, 100, Math.Rounding.Floor), 100);
    }

    function test_oracleValue_RevertsWhenAssetDecimalsAreAboveMax() public {
        // 10 ** 78 exceeds uint256, so computing the base-unit divisor overflows.
        oracle.setPrice(pool, 1, MAX_ASSET_DECIMALS + 1);

        vm.expectRevert(stdError.arithmeticError);
        consumer.oracleValue(pool, 100, Math.Rounding.Floor);
    }

    function test_oracleValue_RevertsWhenValueExceedsUint256() public {
        // A 0-decimal asset is worth the whole uint256 range per whole unit, so two units cannot be represented.
        oracle.setPrice(pool, type(uint256).max, 0);

        vm.expectRevert(stdError.arithmeticError);
        consumer.oracleValue(pool, 2, Math.Rounding.Floor);
    }

    function _deploy() internal returns (OracleConsumerHarness instance) {
        instance = _clone();
        instance.initialize(defaultAdmin, oracleUpdater, address(oracle));
    }

    function _clone() internal returns (OracleConsumerHarness) {
        return OracleConsumerHarness(Clones.clone(address(implementation)));
    }
}
