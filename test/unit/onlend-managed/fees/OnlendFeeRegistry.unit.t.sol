// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IAccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Test} from "forge-std/Test.sol";

import {IVersioned} from "src/interfaces/IVersioned.sol";
import {OnlendFeeRegistry} from "src/onlend-managed/fees/OnlendFeeRegistry.sol";
import {IOnlendFeeRegistry} from "src/pool/interfaces/IOnlendFeeRegistry.sol";
import {FeeConstants} from "src/pool/lib/FeeConstants.sol";

contract OnlendFeeRegistryUnitTest is Test {
    uint16 internal constant DEFAULT_FIXED_FEE_BPS = 500;
    uint16 internal constant DEFAULT_SPLIT_FEE_BPS = 2000;
    uint16 internal constant POOL_FIXED_FEE_BPS = 100;
    uint16 internal constant POOL_SPLIT_FEE_BPS = 5000;

    address internal defaultAdmin;
    address internal feeConfigurator;
    address internal nonFeeConfigurator;
    address internal feeRecipient;
    address internal pool;
    address internal otherPool;
    OnlendFeeRegistry internal registry;

    function setUp() public {
        defaultAdmin = makeAddr("defaultAdmin");
        feeConfigurator = makeAddr("feeConfigurator");
        nonFeeConfigurator = makeAddr("nonFeeConfigurator");
        feeRecipient = makeAddr("feeRecipient");
        pool = makeAddr("pool");
        otherPool = makeAddr("otherPool");

        registry = new OnlendFeeRegistry(
            defaultAdmin, feeConfigurator, DEFAULT_FIXED_FEE_BPS, DEFAULT_SPLIT_FEE_BPS, feeRecipient
        );
    }

    // constructor()

    function test_constructor_GrantsDefaultAdminRole() public view {
        assertTrue(registry.hasRole(registry.DEFAULT_ADMIN_ROLE(), defaultAdmin));
    }

    function test_constructor_GrantsFeeConfigRole() public view {
        assertTrue(registry.hasRole(registry.FEE_CONFIG_ROLE(), feeConfigurator));
    }

    function test_constructor_AllowsZeroAddressRoleMembers() public {
        OnlendFeeRegistry rolelessRegistry =
            new OnlendFeeRegistry(address(0), address(0), DEFAULT_FIXED_FEE_BPS, DEFAULT_SPLIT_FEE_BPS, feeRecipient);

        assertEq(rolelessRegistry.getRoleMemberCount(rolelessRegistry.DEFAULT_ADMIN_ROLE()), 0);
        assertEq(rolelessRegistry.getRoleMemberCount(rolelessRegistry.FEE_CONFIG_ROLE()), 0);
    }

    function test_constructor_SetsDefaultFeeConfig() public view {
        (uint16 fixedFeeBps, uint16 splitFeeBps) = registry.defaultFeeConfig();

        assertEq(fixedFeeBps, DEFAULT_FIXED_FEE_BPS);
        assertEq(splitFeeBps, DEFAULT_SPLIT_FEE_BPS);
    }

    function test_constructor_EmitsDefaultFeeConfigSet() public {
        vm.expectEmit();
        emit OnlendFeeRegistry.DefaultFeeConfigSet(DEFAULT_FIXED_FEE_BPS, DEFAULT_SPLIT_FEE_BPS);

        new OnlendFeeRegistry(defaultAdmin, feeConfigurator, DEFAULT_FIXED_FEE_BPS, DEFAULT_SPLIT_FEE_BPS, feeRecipient);
    }

    function test_constructor_SetsFeeRecipient() public view {
        assertEq(registry.feeRecipient(), feeRecipient);
    }

    function test_constructor_EmitsFeeRecipientSet() public {
        vm.expectEmit();
        emit OnlendFeeRegistry.FeeRecipientSet(feeRecipient);

        new OnlendFeeRegistry(defaultAdmin, feeConfigurator, DEFAULT_FIXED_FEE_BPS, DEFAULT_SPLIT_FEE_BPS, feeRecipient);
    }

    // setDefaultFeeConfig()

    function test_setDefaultFeeConfig_SetsDefaultFeeConfig() public {
        vm.prank(feeConfigurator);
        registry.setDefaultFeeConfig(POOL_FIXED_FEE_BPS, POOL_SPLIT_FEE_BPS);

        (uint16 fixedFeeBps, uint16 splitFeeBps) = registry.defaultFeeConfig();
        assertEq(fixedFeeBps, POOL_FIXED_FEE_BPS);
        assertEq(splitFeeBps, POOL_SPLIT_FEE_BPS);
    }

    function test_setDefaultFeeConfig_EmitsDefaultFeeConfigSet() public {
        vm.expectEmit(address(registry));
        emit OnlendFeeRegistry.DefaultFeeConfigSet(POOL_FIXED_FEE_BPS, POOL_SPLIT_FEE_BPS);

        vm.prank(feeConfigurator);
        registry.setDefaultFeeConfig(POOL_FIXED_FEE_BPS, POOL_SPLIT_FEE_BPS);
    }

    function test_setDefaultFeeConfig_AcceptsFixedFeeAtMax() public {
        vm.prank(feeConfigurator);
        registry.setDefaultFeeConfig(FeeConstants.MAX_FEE_BPS, DEFAULT_SPLIT_FEE_BPS);

        (uint16 fixedFeeBps,) = registry.defaultFeeConfig();
        assertEq(fixedFeeBps, FeeConstants.MAX_FEE_BPS);
    }

    function test_setDefaultFeeConfig_AcceptsSplitFeeAtMax() public {
        vm.prank(feeConfigurator);
        registry.setDefaultFeeConfig(DEFAULT_FIXED_FEE_BPS, FeeConstants.MAX_FEE_BPS);

        (, uint16 splitFeeBps) = registry.defaultFeeConfig();
        assertEq(splitFeeBps, FeeConstants.MAX_FEE_BPS);
    }

    function test_setDefaultFeeConfig_Revert_NotFeeConfigurator() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonFeeConfigurator, registry.FEE_CONFIG_ROLE()
            )
        );
        vm.prank(nonFeeConfigurator);
        registry.setDefaultFeeConfig(POOL_FIXED_FEE_BPS, POOL_SPLIT_FEE_BPS);
    }

    function test_setDefaultFeeConfig_Revert_FixedFeeAboveMax() public {
        vm.expectRevert(
            abi.encodeWithSelector(OnlendFeeRegistry.FixedFeeTooHigh.selector, FeeConstants.MAX_FEE_BPS + 1)
        );
        vm.prank(feeConfigurator);
        registry.setDefaultFeeConfig(FeeConstants.MAX_FEE_BPS + 1, DEFAULT_SPLIT_FEE_BPS);
    }

    function test_setDefaultFeeConfig_Revert_SplitFeeAboveMax() public {
        vm.expectRevert(
            abi.encodeWithSelector(OnlendFeeRegistry.SplitFeeTooHigh.selector, FeeConstants.MAX_FEE_BPS + 1)
        );
        vm.prank(feeConfigurator);
        registry.setDefaultFeeConfig(DEFAULT_FIXED_FEE_BPS, FeeConstants.MAX_FEE_BPS + 1);
    }

    // setPoolFeeConfigs()

    function test_setPoolFeeConfigs_SetsEachPoolFeeConfig() public {
        OnlendFeeRegistry.PoolFeeConfig[] memory configs = new OnlendFeeRegistry.PoolFeeConfig[](2);
        configs[0] = OnlendFeeRegistry.PoolFeeConfig({
            pool: pool, fixedFeeBps: POOL_FIXED_FEE_BPS, splitFeeBps: POOL_SPLIT_FEE_BPS
        });
        configs[1] =
            OnlendFeeRegistry.PoolFeeConfig({pool: otherPool, fixedFeeBps: FeeConstants.MAX_FEE_BPS, splitFeeBps: 0});

        vm.prank(feeConfigurator);
        registry.setPoolFeeConfigs(configs);

        (uint16 fixedFeeBps, uint16 splitFeeBps) = registry.feeConfig(pool);
        (uint16 otherFixedFeeBps, uint16 otherSplitFeeBps) = registry.feeConfig(otherPool);
        assertTrue(registry.hasPoolFeeConfig(pool));
        assertTrue(registry.hasPoolFeeConfig(otherPool));
        assertEq(fixedFeeBps, POOL_FIXED_FEE_BPS);
        assertEq(splitFeeBps, POOL_SPLIT_FEE_BPS);
        assertEq(otherFixedFeeBps, FeeConstants.MAX_FEE_BPS);
        assertEq(otherSplitFeeBps, 0);
    }

    function test_setPoolFeeConfigs_OverwritesExistingPoolFeeConfig() public {
        vm.prank(feeConfigurator);
        registry.setPoolFeeConfigs(_singlePoolFeeConfig(pool, POOL_FIXED_FEE_BPS, POOL_SPLIT_FEE_BPS));

        vm.prank(feeConfigurator);
        registry.setPoolFeeConfigs(_singlePoolFeeConfig(pool, FeeConstants.MAX_FEE_BPS, 0));

        (uint16 fixedFeeBps, uint16 splitFeeBps) = registry.feeConfig(pool);
        assertEq(fixedFeeBps, FeeConstants.MAX_FEE_BPS);
        assertEq(splitFeeBps, 0);
    }

    function test_setPoolFeeConfigs_UsesLastEntryForDuplicatePool() public {
        OnlendFeeRegistry.PoolFeeConfig[] memory configs = new OnlendFeeRegistry.PoolFeeConfig[](2);
        configs[0] = OnlendFeeRegistry.PoolFeeConfig({
            pool: pool, fixedFeeBps: POOL_FIXED_FEE_BPS, splitFeeBps: POOL_SPLIT_FEE_BPS
        });
        configs[1] =
            OnlendFeeRegistry.PoolFeeConfig({pool: pool, fixedFeeBps: FeeConstants.MAX_FEE_BPS, splitFeeBps: 0});

        vm.prank(feeConfigurator);
        registry.setPoolFeeConfigs(configs);

        (uint16 fixedFeeBps, uint16 splitFeeBps) = registry.feeConfig(pool);
        assertEq(fixedFeeBps, FeeConstants.MAX_FEE_BPS);
        assertEq(splitFeeBps, 0);
    }

    function test_setPoolFeeConfigs_EmitsPoolFeeConfigSetForEachPool() public {
        OnlendFeeRegistry.PoolFeeConfig[] memory configs = new OnlendFeeRegistry.PoolFeeConfig[](2);
        configs[0] = OnlendFeeRegistry.PoolFeeConfig({
            pool: pool, fixedFeeBps: POOL_FIXED_FEE_BPS, splitFeeBps: POOL_SPLIT_FEE_BPS
        });
        configs[1] =
            OnlendFeeRegistry.PoolFeeConfig({pool: otherPool, fixedFeeBps: FeeConstants.MAX_FEE_BPS, splitFeeBps: 0});

        vm.expectEmit(address(registry));
        emit OnlendFeeRegistry.PoolFeeConfigSet(pool, POOL_FIXED_FEE_BPS, POOL_SPLIT_FEE_BPS);
        vm.expectEmit(address(registry));
        emit OnlendFeeRegistry.PoolFeeConfigSet(otherPool, FeeConstants.MAX_FEE_BPS, 0);

        vm.prank(feeConfigurator);
        registry.setPoolFeeConfigs(configs);
    }

    function test_setPoolFeeConfigs_AcceptsFixedFeeAtMax() public {
        vm.prank(feeConfigurator);
        registry.setPoolFeeConfigs(_singlePoolFeeConfig(pool, FeeConstants.MAX_FEE_BPS, POOL_SPLIT_FEE_BPS));

        (uint16 fixedFeeBps,) = registry.feeConfig(pool);
        assertEq(fixedFeeBps, FeeConstants.MAX_FEE_BPS);
    }

    function test_setPoolFeeConfigs_AcceptsSplitFeeAtMax() public {
        vm.prank(feeConfigurator);
        registry.setPoolFeeConfigs(_singlePoolFeeConfig(pool, POOL_FIXED_FEE_BPS, FeeConstants.MAX_FEE_BPS));

        (, uint16 splitFeeBps) = registry.feeConfig(pool);
        assertEq(splitFeeBps, FeeConstants.MAX_FEE_BPS);
    }

    function test_setPoolFeeConfigs_Revert_NotFeeConfigurator() public {
        OnlendFeeRegistry.PoolFeeConfig[] memory configs =
            _singlePoolFeeConfig(pool, POOL_FIXED_FEE_BPS, POOL_SPLIT_FEE_BPS);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonFeeConfigurator, registry.FEE_CONFIG_ROLE()
            )
        );
        vm.prank(nonFeeConfigurator);
        registry.setPoolFeeConfigs(configs);
    }

    function test_setPoolFeeConfigs_Revert_FixedFeeAboveMax() public {
        OnlendFeeRegistry.PoolFeeConfig[] memory configs =
            _singlePoolFeeConfig(pool, FeeConstants.MAX_FEE_BPS + 1, POOL_SPLIT_FEE_BPS);

        vm.expectRevert(
            abi.encodeWithSelector(OnlendFeeRegistry.FixedFeeTooHigh.selector, FeeConstants.MAX_FEE_BPS + 1)
        );
        vm.prank(feeConfigurator);
        registry.setPoolFeeConfigs(configs);
    }

    function test_setPoolFeeConfigs_Revert_SplitFeeAboveMax() public {
        OnlendFeeRegistry.PoolFeeConfig[] memory configs =
            _singlePoolFeeConfig(pool, POOL_FIXED_FEE_BPS, FeeConstants.MAX_FEE_BPS + 1);

        vm.expectRevert(
            abi.encodeWithSelector(OnlendFeeRegistry.SplitFeeTooHigh.selector, FeeConstants.MAX_FEE_BPS + 1)
        );
        vm.prank(feeConfigurator);
        registry.setPoolFeeConfigs(configs);
    }

    // removePoolFeeConfigs()

    function test_removePoolFeeConfigs_RemovesEachPoolFeeConfig() public {
        vm.startPrank(feeConfigurator);
        registry.setPoolFeeConfigs(_singlePoolFeeConfig(pool, POOL_FIXED_FEE_BPS, POOL_SPLIT_FEE_BPS));
        registry.setPoolFeeConfigs(_singlePoolFeeConfig(otherPool, POOL_FIXED_FEE_BPS, POOL_SPLIT_FEE_BPS));
        vm.stopPrank();
        address[] memory pools = new address[](2);
        pools[0] = pool;
        pools[1] = otherPool;

        vm.prank(feeConfigurator);
        registry.removePoolFeeConfigs(pools);

        assertFalse(registry.hasPoolFeeConfig(pool));
        assertFalse(registry.hasPoolFeeConfig(otherPool));
    }

    function test_removePoolFeeConfigs_RestoresDefaultFeeConfig() public {
        vm.prank(feeConfigurator);
        registry.setPoolFeeConfigs(_singlePoolFeeConfig(pool, POOL_FIXED_FEE_BPS, POOL_SPLIT_FEE_BPS));
        address[] memory pools = new address[](1);
        pools[0] = pool;

        vm.prank(feeConfigurator);
        registry.removePoolFeeConfigs(pools);

        (uint16 fixedFeeBps, uint16 splitFeeBps) = registry.feeConfig(pool);
        assertEq(fixedFeeBps, DEFAULT_FIXED_FEE_BPS);
        assertEq(splitFeeBps, DEFAULT_SPLIT_FEE_BPS);
    }

    function test_removePoolFeeConfigs_EmitsPoolFeeConfigRemovedForEachPool() public {
        vm.startPrank(feeConfigurator);
        registry.setPoolFeeConfigs(_singlePoolFeeConfig(pool, POOL_FIXED_FEE_BPS, POOL_SPLIT_FEE_BPS));
        registry.setPoolFeeConfigs(_singlePoolFeeConfig(otherPool, POOL_FIXED_FEE_BPS, POOL_SPLIT_FEE_BPS));
        vm.stopPrank();
        address[] memory pools = new address[](2);
        pools[0] = pool;
        pools[1] = otherPool;

        vm.expectEmit(address(registry));
        emit OnlendFeeRegistry.PoolFeeConfigRemoved(pool);
        vm.expectEmit(address(registry));
        emit OnlendFeeRegistry.PoolFeeConfigRemoved(otherPool);

        vm.prank(feeConfigurator);
        registry.removePoolFeeConfigs(pools);
    }

    function test_removePoolFeeConfigs_Revert_NotFeeConfigurator() public {
        vm.prank(feeConfigurator);
        registry.setPoolFeeConfigs(_singlePoolFeeConfig(pool, POOL_FIXED_FEE_BPS, POOL_SPLIT_FEE_BPS));
        address[] memory pools = new address[](1);
        pools[0] = pool;

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonFeeConfigurator, registry.FEE_CONFIG_ROLE()
            )
        );
        vm.prank(nonFeeConfigurator);
        registry.removePoolFeeConfigs(pools);
    }

    function test_removePoolFeeConfigs_Revert_PoolFeeConfigNotSet() public {
        address[] memory pools = new address[](1);
        pools[0] = pool;

        vm.expectRevert(abi.encodeWithSelector(OnlendFeeRegistry.PoolFeeConfigNotSet.selector, pool));
        vm.prank(feeConfigurator);
        registry.removePoolFeeConfigs(pools);
    }

    function test_removePoolFeeConfigs_Revert_DuplicatePool() public {
        vm.prank(feeConfigurator);
        registry.setPoolFeeConfigs(_singlePoolFeeConfig(pool, POOL_FIXED_FEE_BPS, POOL_SPLIT_FEE_BPS));
        address[] memory pools = new address[](2);
        pools[0] = pool;
        pools[1] = pool;

        vm.expectRevert(abi.encodeWithSelector(OnlendFeeRegistry.PoolFeeConfigNotSet.selector, pool));
        vm.prank(feeConfigurator);
        registry.removePoolFeeConfigs(pools);
    }

    // setFeeRecipient()

    function test_setFeeRecipient_SetsFeeRecipient() public {
        address newFeeRecipient = makeAddr("newFeeRecipient");

        vm.prank(feeConfigurator);
        registry.setFeeRecipient(newFeeRecipient);

        assertEq(registry.feeRecipient(), newFeeRecipient);
    }

    function test_setFeeRecipient_EmitsFeeRecipientSet() public {
        address newFeeRecipient = makeAddr("newFeeRecipient");

        vm.expectEmit(address(registry));
        emit OnlendFeeRegistry.FeeRecipientSet(newFeeRecipient);

        vm.prank(feeConfigurator);
        registry.setFeeRecipient(newFeeRecipient);
    }

    function test_setFeeRecipient_Revert_NotFeeConfigurator() public {
        address newFeeRecipient = makeAddr("newFeeRecipient");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonFeeConfigurator, registry.FEE_CONFIG_ROLE()
            )
        );
        vm.prank(nonFeeConfigurator);
        registry.setFeeRecipient(newFeeRecipient);
    }

    function test_setFeeRecipient_Revert_ZeroFeeRecipient() public {
        vm.expectRevert(OnlendFeeRegistry.InvalidFeeRecipient.selector);
        vm.prank(feeConfigurator);
        registry.setFeeRecipient(address(0));
    }

    // feeConfig()

    function test_feeConfig_ReturnsDefaultForPoolWithoutOverride() public {
        vm.prank(feeConfigurator);
        registry.setPoolFeeConfigs(_singlePoolFeeConfig(pool, POOL_FIXED_FEE_BPS, POOL_SPLIT_FEE_BPS));

        (uint16 fixedFeeBps, uint16 splitFeeBps) = registry.feeConfig(otherPool);

        assertEq(fixedFeeBps, DEFAULT_FIXED_FEE_BPS);
        assertEq(splitFeeBps, DEFAULT_SPLIT_FEE_BPS);
    }

    function test_feeConfig_FollowsDefaultChangesForPoolWithoutOverride() public {
        vm.prank(feeConfigurator);
        registry.setDefaultFeeConfig(POOL_FIXED_FEE_BPS, POOL_SPLIT_FEE_BPS);

        (uint16 fixedFeeBps, uint16 splitFeeBps) = registry.feeConfig(pool);

        assertEq(fixedFeeBps, POOL_FIXED_FEE_BPS);
        assertEq(splitFeeBps, POOL_SPLIT_FEE_BPS);
    }

    // hasPoolFeeConfig()

    function test_hasPoolFeeConfig_ReturnsFalseForPoolNeverSet() public view {
        assertFalse(registry.hasPoolFeeConfig(pool));
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(registry.contractName(), "OnlendFeeRegistry");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(registry.contractVersion(), "1.0.0");
    }

    // supportsInterface()

    function test_supportsInterface_SupportsIOnlendFeeRegistry() public view {
        assertTrue(registry.supportsInterface(type(IOnlendFeeRegistry).interfaceId));
    }

    function test_supportsInterface_SupportsIVersioned() public view {
        assertTrue(registry.supportsInterface(type(IVersioned).interfaceId));
    }

    function test_supportsInterface_SupportsIAccessControl() public view {
        assertTrue(registry.supportsInterface(type(IAccessControl).interfaceId));
    }

    function test_supportsInterface_SupportsIAccessControlEnumerable() public view {
        assertTrue(registry.supportsInterface(type(IAccessControlEnumerable).interfaceId));
    }

    function test_supportsInterface_SupportsIERC165() public view {
        assertTrue(registry.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_ReturnsFalseForUnsupportedInterface() public view {
        assertFalse(registry.supportsInterface(0xffffffff));
    }

    function _singlePoolFeeConfig(address pool_, uint16 fixedFeeBps, uint16 splitFeeBps)
        internal
        pure
        returns (OnlendFeeRegistry.PoolFeeConfig[] memory configs)
    {
        configs = new OnlendFeeRegistry.PoolFeeConfig[](1);
        configs[0] = OnlendFeeRegistry.PoolFeeConfig({pool: pool_, fixedFeeBps: fixedFeeBps, splitFeeBps: splitFeeBps});
    }
}
