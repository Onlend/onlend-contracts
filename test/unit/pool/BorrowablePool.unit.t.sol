// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

import {BasePool} from "src/pool/abstract/BasePool.sol";
import {BorrowablePool} from "src/pool/BorrowablePool.sol";
import {MockDebtToken} from "./mocks/MockDebtToken.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockOnlendFeeRegistry} from "./mocks/MockOnlendFeeRegistry.sol";

contract BorrowablePoolUnitTest is Test {
    BorrowablePool internal pool;
    MockERC20 internal asset;
    MockDebtToken internal debtToken;
    MockOnlendFeeRegistry internal feeRegistry;

    address internal defaultAdmin = makeAddr("defaultAdmin");
    address internal hookUpdater = makeAddr("hookUpdater");
    address internal flashLoanConfigurator = makeAddr("flashLoanConfigurator");
    address internal operatorFeeConfigurator = makeAddr("operatorFeeConfigurator");
    address internal operatorFeeRecipient = makeAddr("operatorFeeRecipient");
    address internal lendingCore = makeAddr("lendingCore");
    address internal caller = makeAddr("caller");
    address internal receiver = makeAddr("receiver");

    string internal constant POOL_NAME = "fOnlend USD Coin";
    string internal constant POOL_SYMBOL = "fOnlend USDC";

    uint256 internal constant COLLATERAL_ASSETS = 1000;

    function setUp() public {
        asset = new MockERC20();
        feeRegistry = new MockOnlendFeeRegistry(makeAddr("onlendFeeRecipient"));
        BorrowablePool implementation = new BorrowablePool();
        pool = BorrowablePool(Clones.clone(address(implementation)));
        debtToken = new MockDebtToken(address(pool), asset.decimals());
        pool.initialize(
            defaultAdmin,
            hookUpdater,
            flashLoanConfigurator,
            operatorFeeConfigurator,
            address(0),
            0,
            0,
            lendingCore,
            true,
            asset,
            POOL_NAME,
            POOL_SYMBOL,
            address(debtToken),
            address(feeRegistry),
            operatorFeeRecipient
        );
    }

    // initialize()

    function test_initialize_ConfiguresPoolRolesAndLendingCore() public view {
        assertTrue(pool.hasRole(pool.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertTrue(pool.hasRole(pool.HOOK_UPDATER_ROLE(), hookUpdater));
        assertTrue(pool.hasRole(pool.OPERATOR_FEE_CONFIG_ROLE(), operatorFeeConfigurator));
        assertEq(pool.lendingCore(), lendingCore);
    }

    function test_initialize_AllowsZeroAddressRoleMembers() public {
        BorrowablePool rolelessPool = BorrowablePool(Clones.clone(address(new BorrowablePool())));
        MockDebtToken testDebtToken = new MockDebtToken(address(rolelessPool), asset.decimals());

        rolelessPool.initialize(
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            0,
            0,
            lendingCore,
            false,
            asset,
            POOL_NAME,
            POOL_SYMBOL,
            address(testDebtToken),
            address(feeRegistry),
            operatorFeeRecipient
        );

        assertEq(rolelessPool.getRoleMemberCount(rolelessPool.DEFAULT_ADMIN_ROLE()), 0);
        assertEq(rolelessPool.getRoleMemberCount(rolelessPool.HOOK_UPDATER_ROLE()), 0);
        assertEq(rolelessPool.getRoleMemberCount(rolelessPool.OPERATOR_FEE_CONFIG_ROLE()), 0);
    }

    function test_initialize_UsesDefaultAdminAsRoleAdmin() public view {
        assertEq(pool.getRoleAdmin(pool.HOOK_UPDATER_ROLE()), pool.DEFAULT_ADMIN_ROLE());
    }

    function test_initialize_WiresBorrowableDependencies() public view {
        assertEq(pool.asset(), address(asset));
        assertEq(pool.debtToken(), address(debtToken));
        assertEq(pool.feeRegistry(), address(feeRegistry));
        assertEq(pool.operatorFeeRecipient(), operatorFeeRecipient);
    }

    function test_initialize_EmitsPoolInitialised() public {
        BorrowablePool instance = BorrowablePool(Clones.clone(address(new BorrowablePool())));
        MockDebtToken testDebtToken = new MockDebtToken(address(instance), asset.decimals());

        vm.expectEmit(address(instance));
        emit BorrowablePool.PoolInitialised(lendingCore, address(asset), address(testDebtToken));

        instance.initialize(
            defaultAdmin,
            hookUpdater,
            flashLoanConfigurator,
            operatorFeeConfigurator,
            address(0),
            0,
            0,
            lendingCore,
            true,
            asset,
            POOL_NAME,
            POOL_SYMBOL,
            address(testDebtToken),
            address(feeRegistry),
            operatorFeeRecipient
        );
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(pool.contractName(), "BorrowablePool");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(pool.contractVersion(), "1.0.0");
    }

    // collateral operations

    function test_depositCollateral_RevertsBecausePoolHoldsNoCollateral() public {
        vm.expectRevert(BasePool.FunctionNotAvailable.selector);
        vm.prank(lendingCore);
        pool.depositCollateral(caller, COLLATERAL_ASSETS, 0, receiver);
    }

    function test_withdrawCollateral_RevertsBecausePoolHoldsNoCollateral() public {
        vm.expectRevert(BasePool.FunctionNotAvailable.selector);
        vm.prank(lendingCore);
        pool.withdrawCollateral(caller, COLLATERAL_ASSETS, 0, receiver);
    }

    function test_seizeCollateral_RevertsBecausePoolHoldsNoCollateral() public {
        vm.expectRevert(BasePool.FunctionNotAvailable.selector);
        vm.prank(lendingCore);
        pool.seizeCollateral(caller, COLLATERAL_ASSETS, receiver);
    }

    function test_totalCollateral_ReturnsZeroBecausePoolHoldsNoCollateral() public view {
        assertEq(pool.totalCollateral(), 0);
    }
}
