// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {TargetHealthLiquidationEngineFactory} from "src/factories/liquidation/TargetHealthLiquidationEngineFactory.sol";
import {ICloneFactory} from "src/factories/interfaces/ICloneFactory.sol";
import {TargetHealthLiquidationEngine} from "src/liquidation/TargetHealthLiquidationEngine.sol";
import {IPool} from "src/pool/interfaces/IPool.sol";
import {MockOracle} from "../../../mocks/MockOracle.sol";

contract TargetHealthLiquidationEngineFactoryUnitTest is Test {
    TargetHealthLiquidationEngineFactory factory;
    TargetHealthLiquidationEngine implementation;

    address defaultAdmin = makeAddr("defaultAdmin");
    address oracleUpdater = makeAddr("oracleUpdater");
    address liquidationConfigurator = makeAddr("liquidationConfigurator");
    MockOracle oracle;
    IPool pool = IPool(makeAddr("pool"));

    uint256 constant TARGET_HEALTH_FACTOR = 1.05e18;
    uint256 constant RAMP_START_HEALTH = 1e18;
    uint256 constant RAMP_END_HEALTH = 0.95e18;
    uint256 constant MIN_LEFTOVER_VALUE = 500e18;
    uint256 constant CLOSE_OUT_THRESHOLD = 1000e18;
    bytes32 constant SALT = keccak256("salt");

    function setUp() public {
        implementation = new TargetHealthLiquidationEngine();
        factory = new TargetHealthLiquidationEngineFactory(address(implementation));
        oracle = new MockOracle();
    }

    // clone()

    function test_Clone_InitializesCloneWithDecodedRolesAndConfiguration() public {
        TargetHealthLiquidationEngine.CollateralBonusConfig[] memory configs = _configs();

        address instance = factory.clone(SALT, _initData(configs));

        TargetHealthLiquidationEngine engine = TargetHealthLiquidationEngine(instance);
        TargetHealthLiquidationEngine.CollateralBonus memory collateralBonus = engine.getCollateralBonus(pool);
        (uint256 startHealth, uint256 endHealth) = engine.bonusRamp();
        assertTrue(engine.hasRole(engine.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertTrue(engine.hasRole(engine.ORACLE_UPDATER_ROLE(), oracleUpdater));
        assertTrue(engine.hasRole(engine.LIQUIDATION_CONFIG_ROLE(), liquidationConfigurator));
        assertEq(address(engine.oracle()), address(oracle));
        assertEq(engine.targetHealthFactor(), TARGET_HEALTH_FACTOR);
        assertEq(startHealth, RAMP_START_HEALTH);
        assertEq(endHealth, RAMP_END_HEALTH);
        assertEq(engine.minLeftoverValue(), MIN_LEFTOVER_VALUE);
        assertEq(engine.closeOutThreshold(), CLOSE_OUT_THRESHOLD);
        assertEq(collateralBonus.minBonus, configs[0].minBonus);
        assertEq(collateralBonus.maxBonus, configs[0].maxBonus);
        assertTrue(collateralBonus.isAdded);
    }

    function test_Clone_EmitsClonedEvent() public {
        address predicted = factory.predictAddress(address(this), SALT);

        vm.expectEmit();
        emit ICloneFactory.Cloned(predicted, SALT);
        factory.clone(SALT, _initData(_configs()));
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(factory.contractName(), "TargetHealthLiquidationEngine1.0.0Factory");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(factory.contractVersion(), "1.0.0");
    }

    // Helpers

    function _configs() internal view returns (TargetHealthLiquidationEngine.CollateralBonusConfig[] memory configs) {
        configs = new TargetHealthLiquidationEngine.CollateralBonusConfig[](1);
        configs[0] = TargetHealthLiquidationEngine.CollateralBonusConfig({pool: pool, minBonus: 200, maxBonus: 1000});
    }

    function _initData(TargetHealthLiquidationEngine.CollateralBonusConfig[] memory configs)
        internal
        view
        returns (bytes memory)
    {
        return abi.encode(
            defaultAdmin,
            oracleUpdater,
            liquidationConfigurator,
            address(oracle),
            TARGET_HEALTH_FACTOR,
            RAMP_START_HEALTH,
            RAMP_END_HEALTH,
            MIN_LEFTOVER_VALUE,
            CLOSE_OUT_THRESHOLD,
            configs
        );
    }
}
