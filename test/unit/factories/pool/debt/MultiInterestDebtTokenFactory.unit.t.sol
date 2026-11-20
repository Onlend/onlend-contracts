// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {ICloneFactory} from "src/factories/interfaces/ICloneFactory.sol";
import {MultiInterestDebtTokenFactory} from "src/factories/pool/debt/MultiInterestDebtTokenFactory.sol";
import {MultiInterestDebtToken} from "src/pool/debt/MultiInterestDebtToken.sol";
import {MockIrm} from "../../../pool/irm/mocks/MockIrm.sol";

contract MultiInterestDebtTokenFactoryUnitTest is Test {
    string internal constant NAME = "dOnlend USD Coin";
    string internal constant SYMBOL = "dOnlend USDC";
    uint8 internal constant DECIMALS = 6;
    bytes32 internal constant SALT = keccak256("salt");

    MultiInterestDebtTokenFactory internal factory;
    MockIrm internal firstIrm;
    MockIrm internal secondIrm;
    address internal pool = makeAddr("pool");
    address internal defaultAdmin = makeAddr("defaultAdmin");
    address internal irmUpdater = makeAddr("irmUpdater");

    function setUp() public {
        MultiInterestDebtToken implementation = new MultiInterestDebtToken();
        factory = new MultiInterestDebtTokenFactory(address(implementation));
        firstIrm = new MockIrm(true, 0, 0);
        secondIrm = new MockIrm(true, 0, 0);
    }

    // clone()

    function test_Clone_InitializesDebtTokenWithDecodedRolesAndConfiguration() public {
        address instance = factory.clone(SALT, _initializationData());

        MultiInterestDebtToken debtToken = MultiInterestDebtToken(instance);
        assertEq(debtToken.pool(), pool);
        assertEq(debtToken.name(), NAME);
        assertEq(debtToken.symbol(), SYMBOL);
        assertEq(debtToken.decimals(), DECIMALS);
        assertTrue(debtToken.hasRole(debtToken.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertTrue(debtToken.hasRole(debtToken.IRM_UPDATER_ROLE(), irmUpdater));
        assertEq(debtToken.getActiveIrmIds(), _initialIrmIds());
    }

    function test_Clone_EmitsClonedEvent() public {
        address predicted = factory.predictAddress(address(this), SALT);

        vm.expectEmit();
        emit ICloneFactory.Cloned(predicted, SALT);
        factory.clone(SALT, _initializationData());
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(factory.contractName(), "MultiInterestDebtToken1.0.0Factory");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(factory.contractVersion(), "1.0.0");
    }

    function _initializationData() internal view returns (bytes memory) {
        return abi.encode(pool, NAME, SYMBOL, DECIMALS, defaultAdmin, irmUpdater, _initialIrmIds());
    }

    function _initialIrmIds() internal view returns (address[] memory irmIds) {
        irmIds = new address[](2);
        irmIds[0] = address(firstIrm);
        irmIds[1] = address(secondIrm);
    }
}
