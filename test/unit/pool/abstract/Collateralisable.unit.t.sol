// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IAccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Test} from "forge-std/Test.sol";

import {IVersioned} from "src/interfaces/IVersioned.sol";
import {BasePool} from "src/pool/abstract/BasePool.sol";
import {Collateralisable} from "src/pool/abstract/Collateralisable.sol";
import {ICollateralisable} from "src/pool/interfaces/ICollateralisable.sol";
import {IPool} from "src/pool/interfaces/IPool.sol";
import {CollateralTokenHarness} from "../collateral/abstract/mocks/CollateralTokenHarness.sol";
import {MockCollateralToken} from "../mocks/MockCollateralToken.sol";
import {CollateralisableHarness} from "./mocks/CollateralisableHarness.sol";

contract CollateralisableUnitTest is Test {
    uint8 constant ASSET_DECIMALS = 18;
    uint256 constant ASSETS = 1000e18;

    CollateralisableHarness implementation;
    CollateralisableHarness pool;
    MockCollateralToken collateralToken;

    address defaultAdmin = makeAddr("defaultAdmin");
    address hookUpdater = makeAddr("hookUpdater");
    address lendingCore = makeAddr("lendingCore");
    address caller = makeAddr("caller");
    address receiver = makeAddr("receiver");

    function setUp() public {
        collateralToken = new MockCollateralToken(address(0), ASSET_DECIMALS);
        implementation = new CollateralisableHarness();
        pool = _deployPool(address(collateralToken), ASSET_DECIMALS);
    }

    // _initializeCollateralisable()

    function test_Initialize_StoresCollateralToken() public view {
        assertEq(pool.collateralToken(), address(collateralToken));
    }

    function test_Initialize_Revert_WhenCollateralTokenDoesNotSupportInterface() public {
        address notCollateralToken = makeAddr("notCollateralToken");
        CollateralisableHarness pool_ = CollateralisableHarness(Clones.clone(address(implementation)));

        vm.expectRevert(abi.encodeWithSelector(Collateralisable.InvalidCollateralToken.selector, notCollateralToken));
        pool_.initialize(
            defaultAdmin,
            hookUpdater,
            address(0),
            address(0),
            0,
            0,
            lendingCore,
            false,
            notCollateralToken,
            ASSET_DECIMALS
        );
    }

    function test_Initialize_Revert_WhenCollateralTokenReportsOtherDecimals() public {
        MockCollateralToken sixDecimalsToken = new MockCollateralToken(address(0), 6);
        CollateralisableHarness pool_ = CollateralisableHarness(Clones.clone(address(implementation)));

        vm.expectRevert(
            abi.encodeWithSelector(BasePool.InvalidTokenDecimals.selector, address(sixDecimalsToken), 6, ASSET_DECIMALS)
        );
        pool_.initialize(
            defaultAdmin,
            hookUpdater,
            address(0),
            address(0),
            0,
            0,
            lendingCore,
            false,
            address(sixDecimalsToken),
            ASSET_DECIMALS
        );
    }

    // collateralToken()

    function test_CollateralToken_ReturnsConfiguredToken() public view {
        assertEq(pool.collateralToken(), address(collateralToken));
    }

    // totalCollateral()

    function test_TotalCollateral_ReturnsZeroBeforeAnyDeposit() public view {
        assertEq(pool.totalCollateral(), 0);
    }

    function test_TotalCollateral_ReadsFromCollateralToken() public {
        vm.prank(lendingCore);
        pool.depositCollateral(caller, ASSETS, 0, receiver);

        assertEq(pool.totalCollateral(), ASSETS);
    }

    // collateralOf()

    function test_CollateralOf_ReadsEachAccountsBalanceFromCollateralToken() public {
        address otherReceiver = makeAddr("otherReceiver");
        vm.startPrank(lendingCore);
        pool.depositCollateral(caller, ASSETS, 0, receiver);
        pool.depositCollateral(caller, 250e18, 0, otherReceiver);
        vm.stopPrank();

        assertEq(pool.collateralOf(receiver), ASSETS);
        assertEq(pool.collateralOf(otherReceiver), 250e18);
    }

    // supportsInterface()

    function test_SupportsInterface_ReturnsTrueForCollateralisable() public view {
        assertTrue(pool.supportsInterface(type(ICollateralisable).interfaceId));
    }

    function test_SupportsInterface_ReturnsTrueForPool() public view {
        assertTrue(pool.supportsInterface(type(IPool).interfaceId));
    }

    function test_SupportsInterface_ReturnsTrueForERC3156FlashLender() public view {
        assertTrue(pool.supportsInterface(type(IERC3156FlashLender).interfaceId));
    }

    function test_SupportsInterface_ReturnsTrueForVersioned() public view {
        assertTrue(pool.supportsInterface(type(IVersioned).interfaceId));
    }

    function test_SupportsInterface_ReturnsTrueForERC165() public view {
        assertTrue(pool.supportsInterface(type(IERC165).interfaceId));
    }

    function test_SupportsInterface_ReturnsTrueForAccessControl() public view {
        assertTrue(pool.supportsInterface(type(IAccessControl).interfaceId));
    }

    function test_SupportsInterface_ReturnsTrueForAccessControlEnumerable() public view {
        assertTrue(pool.supportsInterface(type(IAccessControlEnumerable).interfaceId));
    }

    function test_SupportsInterface_ReturnsFalseForUnknownInterface() public view {
        assertFalse(pool.supportsInterface(bytes4(0xffffffff)));
    }

    // _validateCollateralToken()

    function test_ValidateCollateralToken_AcceptsTokenSupportingCollateralTokenInterface() public {
        CollateralTokenHarness token = new CollateralTokenHarness();

        pool.validateCollateralToken(address(token));
    }

    function test_ValidateCollateralToken_Revert_WhenTokenDoesNotSupportCollateralTokenInterface() public {
        address notCollateralToken = makeAddr("notCollateralToken");

        vm.expectRevert(abi.encodeWithSelector(Collateralisable.InvalidCollateralToken.selector, notCollateralToken));
        pool.validateCollateralToken(notCollateralToken);
    }

    function _deployPool(address collateralToken_, uint8 assetDecimals)
        internal
        returns (CollateralisableHarness pool_)
    {
        pool_ = CollateralisableHarness(Clones.clone(address(implementation)));
        pool_.initialize(
            defaultAdmin, hookUpdater, address(0), address(0), 0, 0, lendingCore, false, collateralToken_, assetDecimals
        );
    }
}
