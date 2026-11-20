// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {ICloneFactory} from "src/factories/interfaces/ICloneFactory.sol";
import {CollateralisablePoolFactory} from "src/factories/pool/CollateralisablePoolFactory.sol";
import {CollateralisablePool} from "src/pool/CollateralisablePool.sol";
import {MockHookReceiver} from "../../hooks/mocks/MockHookReceiver.sol";
import {MockCollateralToken} from "../../pool/mocks/MockCollateralToken.sol";
import {MockERC20} from "../../pool/mocks/MockERC20.sol";

contract CollateralisablePoolFactoryUnitTest is Test {
    bytes32 internal constant SALT = keccak256("salt");
    uint256 internal constant INITIAL_BEFORE_HOOK_BITMAP = uint256(1) << 3;
    uint256 internal constant INITIAL_AFTER_HOOK_BITMAP = uint256(1) << 5;

    CollateralisablePoolFactory internal factory;
    MockHookReceiver internal hookReceiver;
    MockERC20 internal asset;
    address internal defaultAdmin = makeAddr("defaultAdmin");
    address internal hookUpdater = makeAddr("hookUpdater");
    address internal flashLoanConfigurator = makeAddr("flashLoanConfigurator");
    address internal lendingCore = makeAddr("lendingCore");
    address internal collateralToken;

    function setUp() public {
        CollateralisablePool implementation = new CollateralisablePool();
        factory = new CollateralisablePoolFactory(address(implementation));
        hookReceiver = new MockHookReceiver();
        asset = new MockERC20();
        collateralToken = address(new MockCollateralToken(address(0), asset.decimals()));
    }

    // clone()

    function test_Clone_InitializesPoolWithDecodedRolesAndConfiguration() public {
        address instance = factory.clone(SALT, _initializationData());

        CollateralisablePool pool = CollateralisablePool(instance);
        assertTrue(pool.hasRole(pool.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertTrue(pool.hasRole(pool.HOOK_UPDATER_ROLE(), hookUpdater));
        assertTrue(pool.hasRole(pool.FLASH_LOAN_CONFIG_ROLE(), flashLoanConfigurator));
        assertEq(pool.hookReceiver(), address(hookReceiver));
        (uint256 beforeHookBitmap, uint256 afterHookBitmap) = pool.hookBitmaps();
        assertEq(beforeHookBitmap, INITIAL_BEFORE_HOOK_BITMAP);
        assertEq(afterHookBitmap, INITIAL_AFTER_HOOK_BITMAP);
        assertEq(pool.lendingCore(), lendingCore);
        assertTrue(pool.flashLoansEnabled());
        assertEq(pool.asset(), address(asset));
        assertEq(pool.collateralToken(), collateralToken);
    }

    function test_Clone_EmitsClonedEvent() public {
        address predicted = factory.predictAddress(address(this), SALT);

        vm.expectEmit();
        emit ICloneFactory.Cloned(predicted, SALT);
        factory.clone(SALT, _initializationData());
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(factory.contractName(), "CollateralisablePool1.0.0Factory");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(factory.contractVersion(), "1.0.0");
    }

    function _initializationData() internal view returns (bytes memory) {
        return abi.encode(
            defaultAdmin,
            hookUpdater,
            flashLoanConfigurator,
            address(hookReceiver),
            INITIAL_BEFORE_HOOK_BITMAP,
            INITIAL_AFTER_HOOK_BITMAP,
            lendingCore,
            true,
            asset,
            collateralToken
        );
    }
}
