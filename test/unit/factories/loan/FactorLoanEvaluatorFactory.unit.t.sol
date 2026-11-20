// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {FactorLoanEvaluatorFactory} from "src/factories/loan/FactorLoanEvaluatorFactory.sol";
import {ICloneFactory} from "src/factories/interfaces/ICloneFactory.sol";
import {FactorLoanEvaluator} from "src/loan/FactorLoanEvaluator.sol";
import {IPool} from "src/pool/interfaces/IPool.sol";
import {MockOracle} from "../../../mocks/MockOracle.sol";

contract FactorLoanEvaluatorFactoryUnitTest is Test {
    FactorLoanEvaluatorFactory factory;
    FactorLoanEvaluator implementation;

    address defaultAdmin = makeAddr("defaultAdmin");
    address oracleUpdater = makeAddr("oracleUpdater");
    address factorConfigurator = makeAddr("factorConfigurator");
    MockOracle oracle;
    IPool pool = IPool(makeAddr("pool"));

    uint256 constant MIN_HEALTH_FACTOR = 1.1e18;
    bytes32 constant SALT = keccak256("salt");

    function setUp() public {
        implementation = new FactorLoanEvaluator();
        factory = new FactorLoanEvaluatorFactory(address(implementation));
        oracle = new MockOracle();
    }

    // clone()

    function test_Clone_InitializesCloneWithDecodedRolesAndConfiguration() public {
        FactorLoanEvaluator.PoolFactorConfig[] memory configs = _configs();

        address instance = factory.clone(
            SALT,
            abi.encode(defaultAdmin, oracleUpdater, factorConfigurator, address(oracle), MIN_HEALTH_FACTOR, configs)
        );

        FactorLoanEvaluator evaluator = FactorLoanEvaluator(instance);
        FactorLoanEvaluator.PoolFactors memory poolFactors = evaluator.getPoolFactors(pool);
        assertTrue(evaluator.hasRole(evaluator.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertTrue(evaluator.hasRole(evaluator.ORACLE_UPDATER_ROLE(), oracleUpdater));
        assertTrue(evaluator.hasRole(evaluator.FACTOR_CONFIG_ROLE(), factorConfigurator));
        assertEq(address(evaluator.oracle()), address(oracle));
        assertEq(evaluator.minHealthFactor(), MIN_HEALTH_FACTOR);
        assertEq(poolFactors.collateralFactor, configs[0].collateralFactor);
        assertEq(poolFactors.borrowFactor, configs[0].borrowFactor);
        assertTrue(poolFactors.isAdded);
    }

    function test_Clone_EmitsClonedEvent() public {
        address predicted = factory.predictAddress(address(this), SALT);

        vm.expectEmit();
        emit ICloneFactory.Cloned(predicted, SALT);
        factory.clone(
            SALT,
            abi.encode(defaultAdmin, oracleUpdater, factorConfigurator, address(oracle), MIN_HEALTH_FACTOR, _configs())
        );
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(factory.contractName(), "FactorLoanEvaluator1.0.0Factory");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(factory.contractVersion(), "1.0.0");
    }

    // Helpers

    function _configs() internal view returns (FactorLoanEvaluator.PoolFactorConfig[] memory configs) {
        configs = new FactorLoanEvaluator.PoolFactorConfig[](1);
        configs[0] = FactorLoanEvaluator.PoolFactorConfig({pool: pool, collateralFactor: 8000, borrowFactor: 11_000});
    }
}
