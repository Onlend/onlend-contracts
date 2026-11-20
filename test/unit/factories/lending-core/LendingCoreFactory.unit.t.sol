// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {ICloneFactory} from "src/factories/interfaces/ICloneFactory.sol";
import {LendingCoreFactory} from "src/factories/lending-core/LendingCoreFactory.sol";
import {LendingCore} from "src/lending-core/LendingCore.sol";
import {MockHookReceiver} from "../../hooks/mocks/MockHookReceiver.sol";
import {MockLiquidationEngine} from "../../liquidation/mocks/MockLiquidationEngine.sol";
import {MockLoanEvaluator} from "../../loan/mocks/MockLoanEvaluator.sol";
import {MockPool} from "../../pool/mocks/MockPool.sol";

contract LendingCoreFactoryUnitTest is Test {
    bytes32 internal constant SALT = keccak256("salt");
    uint256 internal constant INITIAL_BEFORE_HOOK_BITMAP = uint256(1) << 3;
    uint256 internal constant INITIAL_AFTER_HOOK_BITMAP = uint256(1) << 5;
    bool internal constant INITIAL_SOCIALISE_BAD_DEBT = true;
    string internal constant INITIAL_METADATA = '{"name":"Atlas"}';

    LendingCoreFactory internal factory;
    MockHookReceiver internal hookReceiver;
    MockLoanEvaluator internal loanEvaluator;
    MockLiquidationEngine internal liquidationEngine;
    MockPool internal firstPool;
    MockPool internal secondPool;

    address internal defaultAdmin = makeAddr("defaultAdmin");
    address internal hookUpdater = makeAddr("hookUpdater");
    address internal poolLister = makeAddr("poolLister");
    address internal loanUpdater = makeAddr("loanUpdater");
    address internal liquidationUpdater = makeAddr("liquidationUpdater");
    address internal badDebtConfigurator = makeAddr("badDebtConfigurator");
    address internal metadataConfigurator = makeAddr("metadataConfigurator");

    function setUp() public {
        LendingCore implementation = new LendingCore();
        factory = new LendingCoreFactory(address(implementation));
        hookReceiver = new MockHookReceiver();
        loanEvaluator = new MockLoanEvaluator();
        liquidationEngine = new MockLiquidationEngine();
        firstPool = new MockPool();
        secondPool = new MockPool();
    }

    // clone()

    function test_Clone_InitializesLendingCoreWithDecodedRolesAndConfiguration() public {
        address instance = factory.clone(SALT, _initializationData());

        LendingCore lendingCore = LendingCore(instance);
        assertTrue(lendingCore.hasRole(lendingCore.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertTrue(lendingCore.hasRole(lendingCore.HOOK_UPDATER_ROLE(), hookUpdater));
        assertTrue(lendingCore.hasRole(lendingCore.POOL_LISTING_ROLE(), poolLister));
        assertTrue(lendingCore.hasRole(lendingCore.LOAN_UPDATER_ROLE(), loanUpdater));
        assertTrue(lendingCore.hasRole(lendingCore.LIQUIDATION_UPDATER_ROLE(), liquidationUpdater));
        assertTrue(lendingCore.hasRole(lendingCore.BAD_DEBT_CONFIG_ROLE(), badDebtConfigurator));
        assertTrue(lendingCore.hasRole(lendingCore.METADATA_CONFIG_ROLE(), metadataConfigurator));
        assertEq(lendingCore.hookReceiver(), address(hookReceiver));
        (uint256 beforeHookBitmap, uint256 afterHookBitmap) = lendingCore.hookBitmaps();
        assertEq(beforeHookBitmap, INITIAL_BEFORE_HOOK_BITMAP);
        assertEq(afterHookBitmap, INITIAL_AFTER_HOOK_BITMAP);
        assertEq(lendingCore.loanEvaluator(), address(loanEvaluator));
        assertEq(lendingCore.liquidationEngine(), address(liquidationEngine));
        assertEq(lendingCore.socialiseBadDebt(), INITIAL_SOCIALISE_BAD_DEBT);
        assertTrue(lendingCore.isPoolAdded(address(firstPool)));
        assertTrue(lendingCore.isPoolAdded(address(secondPool)));
    }

    function test_Clone_EmitsMetadataSet() public {
        address predicted = factory.predictAddress(address(this), SALT);

        vm.expectEmit(predicted);
        emit LendingCore.MetadataSet(INITIAL_METADATA);
        factory.clone(SALT, _initializationData());
    }

    function test_Clone_EmitsClonedEvent() public {
        address predicted = factory.predictAddress(address(this), SALT);

        vm.expectEmit();
        emit ICloneFactory.Cloned(predicted, SALT);
        factory.clone(SALT, _initializationData());
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(factory.contractName(), "LendingCore1.0.0Factory");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(factory.contractVersion(), "1.0.0");
    }

    // Helpers

    function _initializationData() internal view returns (bytes memory) {
        return abi.encode(
            address(loanEvaluator),
            address(liquidationEngine),
            defaultAdmin,
            hookUpdater,
            address(hookReceiver),
            INITIAL_BEFORE_HOOK_BITMAP,
            INITIAL_AFTER_HOOK_BITMAP,
            poolLister,
            loanUpdater,
            liquidationUpdater,
            badDebtConfigurator,
            metadataConfigurator,
            INITIAL_SOCIALISE_BAD_DEBT,
            INITIAL_METADATA,
            _initialPools()
        );
    }

    function _initialPools() internal view returns (address[] memory pools) {
        pools = new address[](2);
        pools[0] = address(firstPool);
        pools[1] = address(secondPool);
    }
}
