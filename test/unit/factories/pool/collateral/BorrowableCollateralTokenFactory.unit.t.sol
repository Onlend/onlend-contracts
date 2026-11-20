// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {ICloneFactory} from "src/factories/interfaces/ICloneFactory.sol";
import {BorrowableCollateralTokenFactory} from "src/factories/pool/collateral/BorrowableCollateralTokenFactory.sol";
import {BorrowableCollateralToken} from "src/pool/collateral/BorrowableCollateralToken.sol";

contract BorrowableCollateralTokenFactoryUnitTest is Test {
    string internal constant NAME = "USD Coin";
    string internal constant SYMBOL = "USDC";
    uint8 internal constant DECIMALS = 6;
    bytes32 internal constant SALT = keccak256("salt");

    BorrowableCollateralTokenFactory internal factory;
    address internal pool = makeAddr("pool");

    function setUp() public {
        BorrowableCollateralToken implementation = new BorrowableCollateralToken();
        factory = new BorrowableCollateralTokenFactory(address(implementation));
    }

    // clone()

    function test_Clone_InitializesCollateralTokenWithDecodedConfiguration() public {
        address instance = factory.clone(SALT, _initializationData());

        BorrowableCollateralToken collateralToken = BorrowableCollateralToken(instance);
        assertEq(collateralToken.pool(), pool);
        assertEq(collateralToken.name(), NAME);
        assertEq(collateralToken.symbol(), SYMBOL);
        assertEq(collateralToken.decimals(), DECIMALS);
    }

    function test_Clone_EmitsClonedEvent() public {
        address predicted = factory.predictAddress(address(this), SALT);

        vm.expectEmit();
        emit ICloneFactory.Cloned(predicted, SALT);
        factory.clone(SALT, _initializationData());
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(factory.contractName(), "BorrowableCollateralToken1.0.0Factory");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(factory.contractVersion(), "1.0.0");
    }

    function _initializationData() internal view returns (bytes memory) {
        return abi.encode(pool, NAME, SYMBOL, DECIMALS);
    }
}
