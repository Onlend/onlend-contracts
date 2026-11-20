// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {ICloneFactory} from "src/factories/interfaces/ICloneFactory.sol";
import {FullLiquidationEngineFactory} from "src/factories/liquidation/FullLiquidationEngineFactory.sol";
import {FullLiquidationEngine} from "src/liquidation/FullLiquidationEngine.sol";
import {ILiquidationEngine} from "src/liquidation/interfaces/ILiquidationEngine.sol";

contract FullLiquidationEngineFactoryUnitTest is Test {
    FullLiquidationEngineFactory factory;
    FullLiquidationEngine implementation;

    bytes32 constant SALT = keccak256("salt");

    function setUp() public {
        implementation = new FullLiquidationEngine();
        factory = new FullLiquidationEngineFactory(address(implementation));
    }

    // clone()

    function test_Clone_DeploysWorkingLiquidationEngine() public {
        address instance = factory.clone(SALT, "");

        FullLiquidationEngine engine = FullLiquidationEngine(instance);
        assertTrue(engine.supportsInterface(type(ILiquidationEngine).interfaceId));
    }

    function test_Clone_EmitsClonedEvent() public {
        address predicted = factory.predictAddress(address(this), SALT);

        vm.expectEmit();
        emit ICloneFactory.Cloned(predicted, SALT);
        factory.clone(SALT, "");
    }

    function test_Clone_RevertsWhenInitializationDataIsNotEmpty() public {
        vm.expectRevert(FullLiquidationEngineFactory.UnexpectedInitializationData.selector);
        factory.clone(SALT, hex"01");
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(factory.contractName(), "FullLiquidationEngine1.0.0Factory");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(factory.contractVersion(), "1.0.0");
    }
}
