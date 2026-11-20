// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IAccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Test} from "forge-std/Test.sol";

import {IHookReceiver, Phase} from "src/hooks/interfaces/IHookReceiver.sol";
import {ActionLib} from "src/hooks/lib/ActionLib.sol";
import {CapsHookReceiver} from "src/hooks/modules/abstract/CapsHookReceiver.sol";
import {UsdCapsHookReceiver} from "src/hooks/modules/UsdCapsHookReceiver.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IOracle} from "src/oracle/interfaces/IOracle.sol";
import {IPool} from "src/pool/interfaces/IPool.sol";
import {MockOracle} from "../../../mocks/MockOracle.sol";
import {MockPool} from "../../pool/mocks/MockPool.sol";

contract UsdCapsHookReceiverUnitTest is Test {
    CapsHookReceiver.CapType internal constant SUPPLY_CAP = CapsHookReceiver.CapType.Supply;

    address internal defaultAdmin;
    address internal capsConfigurator;
    address internal oracleUpdater;
    MockOracle internal oracle;
    UsdCapsHookReceiver internal implementation;
    UsdCapsHookReceiver internal capsHookReceiver;

    function setUp() public {
        defaultAdmin = makeAddr("defaultAdmin");
        capsConfigurator = makeAddr("capsConfigurator");
        oracleUpdater = makeAddr("oracleUpdater");
        oracle = new MockOracle();
        implementation = new UsdCapsHookReceiver();

        capsHookReceiver = _clone();
        capsHookReceiver.initialize(
            defaultAdmin, capsConfigurator, oracleUpdater, address(oracle), new CapsHookReceiver.PoolCapConfig[](0)
        );
    }

    // initialize()

    function test_initialize_StoresOracle() public view {
        assertEq(address(capsHookReceiver.oracle()), address(oracle));
    }

    function test_initialize_GrantsDefaultAdminCapsConfiguratorAndOracleUpdaterRoles() public view {
        assertTrue(capsHookReceiver.hasRole(capsHookReceiver.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertTrue(capsHookReceiver.hasRole(capsHookReceiver.CAPS_CONFIG_ROLE(), capsConfigurator));
        assertTrue(capsHookReceiver.hasRole(capsHookReceiver.ORACLE_UPDATER_ROLE(), oracleUpdater));
    }

    function test_initialize_AllowsZeroDefaultAdmin() public {
        UsdCapsHookReceiver instance = _clone();

        instance.initialize(
            address(0), capsConfigurator, oracleUpdater, address(oracle), new CapsHookReceiver.PoolCapConfig[](0)
        );

        assertEq(instance.getRoleMemberCount(instance.DEFAULT_ADMIN_ROLE()), 0);
    }

    function test_initialize_UsesDefaultAdminAsOracleUpdaterRoleAdmin() public view {
        assertEq(
            capsHookReceiver.getRoleAdmin(capsHookReceiver.ORACLE_UPDATER_ROLE()), capsHookReceiver.DEFAULT_ADMIN_ROLE()
        );
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(capsHookReceiver.contractName(), "UsdCapsHookReceiver");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(capsHookReceiver.contractVersion(), "1.0.0");
    }

    // supportsInterface()

    function test_supportsInterface_HookReceiver_ReturnsTrue() public view {
        assertTrue(capsHookReceiver.supportsInterface(type(IHookReceiver).interfaceId));
    }

    function test_supportsInterface_Versioned_ReturnsTrue() public view {
        assertTrue(capsHookReceiver.supportsInterface(type(IVersioned).interfaceId));
    }

    function test_supportsInterface_ERC165_ReturnsTrue() public view {
        assertTrue(capsHookReceiver.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_AccessControl_ReturnsTrue() public view {
        assertTrue(capsHookReceiver.supportsInterface(type(IAccessControl).interfaceId));
    }

    function test_supportsInterface_AccessControlEnumerable_ReturnsTrue() public view {
        assertTrue(capsHookReceiver.supportsInterface(type(IAccessControlEnumerable).interfaceId));
    }

    function test_supportsInterface_Unknown_ReturnsFalse() public view {
        assertFalse(capsHookReceiver.supportsInterface(bytes4(0xffffffff)));
        assertFalse(capsHookReceiver.supportsInterface(bytes4(0xdeadbeef)));
    }

    // _value() through onHook()

    function test_onHook_AfterDepositAllowsTotalUsdSupplyEqualToCap() public {
        address pool = _deployPool(600);
        _mockPrice(pool, 2e18, 18);
        _addCap(pool, 1200);

        // 600 * 2e18 / 1e18 = 1,200, equal to the 1,200 cap.
        capsHookReceiver.onHook(pool, Phase.AFTER, ActionLib.POOL_DEPOSIT, "");
    }

    function test_onHook_AfterDepositAllowsZeroTotalAmount() public {
        address pool = _deployPool(0);
        _mockPrice(pool, 2e18, 18);
        _addCap(pool, 0);

        // 0 * 2e18 / 1e18 = 0, equal to the zero cap.
        capsHookReceiver.onHook(pool, Phase.AFTER, ActionLib.POOL_DEPOSIT, "");
    }

    function test_onHook_AfterDepositRequestsPriceForHookSource() public {
        address pool = _deployPool(1000);
        _mockPrice(pool, 1e18, 18);
        _addCap(pool, 1000);

        vm.expectCall(address(oracle), abi.encodeWithSelector(IOracle.getPrice.selector, IPool(pool)));

        capsHookReceiver.onHook(pool, Phase.AFTER, ActionLib.POOL_DEPOSIT, "");
    }

    function test_onHook_AfterDepositDoesNotOverflowWhenIntermediateProductExceedsUint256() public {
        address pool = _deployPool(type(uint256).max);
        _mockPrice(pool, 1e18, 18);
        _addCap(pool, type(uint256).max);

        // max * 1e18 overflows uint256 before the division, but max * 1e18 / 1e18 = max, equal to the max cap.
        capsHookReceiver.onHook(pool, Phase.AFTER, ActionLib.POOL_DEPOSIT, "");
    }

    function test_onHook_AfterDepositRevertsWhenTotalUsdSupplyExceedsCap() public {
        address pool = _deployPool(600);
        _mockPrice(pool, 2e18, 18);
        _addCap(pool, 1000);

        // 600 * 2e18 / 1e18 = 1,200, above the 1,000 cap.
        vm.expectRevert(
            abi.encodeWithSelector(
                CapsHookReceiver.CapExceeded.selector, pool, SUPPLY_CAP, uint256(1000), uint256(1200)
            )
        );
        capsHookReceiver.onHook(pool, Phase.AFTER, ActionLib.POOL_DEPOSIT, "");
    }

    function test_onHook_AfterDepositRoundsTotalUsdSupplyUp() public {
        address pool = _deployPool(1001);
        _mockPrice(pool, 1, 1);
        _addCap(pool, 100);

        // 1,001 * 1 / 10 = 100.1, rounded up to 101, above the 100 cap.
        vm.expectRevert(
            abi.encodeWithSelector(CapsHookReceiver.CapExceeded.selector, pool, SUPPLY_CAP, uint256(100), uint256(101))
        );
        capsHookReceiver.onHook(pool, Phase.AFTER, ActionLib.POOL_DEPOSIT, "");
    }

    function test_onHook_AfterDepositRoundsPositiveUsdValueBelowOneUpToOne() public {
        address pool = _deployPool(1);
        _mockPrice(pool, 1, 18);
        _addCap(pool, 0);

        // 1 * 1 / 1e18 = 1e-18, rounded up to 1, above the zero cap.
        vm.expectRevert(
            abi.encodeWithSelector(CapsHookReceiver.CapExceeded.selector, pool, SUPPLY_CAP, uint256(0), uint256(1))
        );
        capsHookReceiver.onHook(pool, Phase.AFTER, ActionLib.POOL_DEPOSIT, "");
    }

    function _addCap(address pool, uint256 limit) internal {
        vm.prank(capsConfigurator);
        capsHookReceiver.addCap(pool, SUPPLY_CAP, limit);
    }

    function _deployPool(uint256 totalAssets) internal returns (address) {
        MockPool pool = new MockPool();
        pool.setTotals(totalAssets, 0, 0);
        return address(pool);
    }

    function _mockPrice(address pool, uint256 price, uint8 decimals) internal {
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(IOracle.getPrice.selector, IPool(pool)),
            abi.encode(IOracle.PriceFeed({price: price, assetDecimals: decimals}))
        );
    }

    function _clone() internal returns (UsdCapsHookReceiver) {
        return UsdCapsHookReceiver(Clones.clone(address(implementation)));
    }
}
