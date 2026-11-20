// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {ICloneFactory} from "src/factories/interfaces/ICloneFactory.sol";
import {CollateralisableBorrowablePoolFactory} from "src/factories/pool/CollateralisableBorrowablePoolFactory.sol";
import {CollateralisableBorrowablePool} from "src/pool/CollateralisableBorrowablePool.sol";
import {MockHookReceiver} from "../../hooks/mocks/MockHookReceiver.sol";
import {MockCollateralToken} from "../../pool/mocks/MockCollateralToken.sol";
import {MockDebtToken} from "../../pool/mocks/MockDebtToken.sol";
import {MockERC20} from "../../pool/mocks/MockERC20.sol";
import {MockOnlendFeeRegistry} from "../../pool/mocks/MockOnlendFeeRegistry.sol";

contract CollateralisableBorrowablePoolFactoryUnitTest is Test {
    string internal constant POOL_NAME = "fOnlend USD Coin";
    string internal constant POOL_SYMBOL = "fOnlend USDC";
    bytes32 internal constant SALT = keccak256("salt");
    uint256 internal constant INITIAL_BEFORE_HOOK_BITMAP = uint256(1) << 3;
    uint256 internal constant INITIAL_AFTER_HOOK_BITMAP = uint256(1) << 5;

    CollateralisableBorrowablePoolFactory internal factory;
    MockHookReceiver internal hookReceiver;
    MockERC20 internal asset;
    MockOnlendFeeRegistry internal feeRegistry;
    address internal defaultAdmin = makeAddr("defaultAdmin");
    address internal hookUpdater = makeAddr("hookUpdater");
    address internal flashLoanConfigurator = makeAddr("flashLoanConfigurator");
    address internal operatorFeeConfigurator = makeAddr("operatorFeeConfigurator");
    address internal operatorFeeRecipient = makeAddr("operatorFeeRecipient");
    address internal lendingCore = makeAddr("lendingCore");
    address internal collateralToken;
    address internal debtToken;

    function setUp() public {
        CollateralisableBorrowablePool implementation = new CollateralisableBorrowablePool();
        feeRegistry = new MockOnlendFeeRegistry(makeAddr("onlendFeeRecipient"));
        factory = new CollateralisableBorrowablePoolFactory(address(implementation), address(feeRegistry));
        hookReceiver = new MockHookReceiver();
        asset = new MockERC20();
        collateralToken = address(new MockCollateralToken(address(0), asset.decimals()));
        debtToken = address(new MockDebtToken(address(0), asset.decimals()));
    }

    // constructor()

    function test_constructor_StoresFeeRegistry() public view {
        assertEq(factory.FEE_REGISTRY(), address(feeRegistry));
    }

    // clone()

    function test_Clone_InitializesPoolWithDecodedRolesAndConfiguration() public {
        address instance = factory.clone(SALT, _initializationData());

        CollateralisableBorrowablePool pool = CollateralisableBorrowablePool(instance);
        assertTrue(pool.hasRole(pool.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertTrue(pool.hasRole(pool.HOOK_UPDATER_ROLE(), hookUpdater));
        assertTrue(pool.hasRole(pool.FLASH_LOAN_CONFIG_ROLE(), flashLoanConfigurator));
        assertTrue(pool.hasRole(pool.OPERATOR_FEE_CONFIG_ROLE(), operatorFeeConfigurator));
        assertEq(pool.hookReceiver(), address(hookReceiver));
        (uint256 beforeHookBitmap, uint256 afterHookBitmap) = pool.hookBitmaps();
        assertEq(beforeHookBitmap, INITIAL_BEFORE_HOOK_BITMAP);
        assertEq(afterHookBitmap, INITIAL_AFTER_HOOK_BITMAP);
        assertEq(pool.lendingCore(), lendingCore);
        assertTrue(pool.flashLoansEnabled());
        assertEq(pool.asset(), address(asset));
        assertEq(pool.name(), POOL_NAME);
        assertEq(pool.symbol(), POOL_SYMBOL);
        assertEq(pool.collateralToken(), collateralToken);
        assertEq(pool.debtToken(), debtToken);
        assertEq(pool.feeRegistry(), address(feeRegistry));
        assertEq(pool.operatorFeeRecipient(), operatorFeeRecipient);
    }

    function test_Clone_EmitsClonedEvent() public {
        address predicted = factory.predictAddress(address(this), SALT);

        vm.expectEmit();
        emit ICloneFactory.Cloned(predicted, SALT);
        factory.clone(SALT, _initializationData());
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(factory.contractName(), "CollateralisableBorrowablePool1.0.0Factory");
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
            operatorFeeConfigurator,
            address(hookReceiver),
            INITIAL_BEFORE_HOOK_BITMAP,
            INITIAL_AFTER_HOOK_BITMAP,
            lendingCore,
            true,
            asset,
            POOL_NAME,
            POOL_SYMBOL,
            collateralToken,
            debtToken,
            operatorFeeRecipient
        );
    }
}
