// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {OnlendFeeRegistry} from "src/onlend-managed/fees/OnlendFeeRegistry.sol";
import {FeeConstants} from "src/pool/lib/FeeConstants.sol";

contract OnlendFeeRegistryFuzzTest is Test {
    uint16 internal constant DEFAULT_FIXED_FEE_BPS = 500;
    uint16 internal constant DEFAULT_SPLIT_FEE_BPS = 2000;
    /// @dev The registry has no length-dependent logic, so this only bounds the cost of each fuzz run.
    uint256 internal constant MAX_BATCH_LENGTH = 20;

    address internal feeConfigurator;
    OnlendFeeRegistry internal registry;

    function setUp() public {
        feeConfigurator = makeAddr("feeConfigurator");

        registry = new OnlendFeeRegistry(
            makeAddr("defaultAdmin"),
            feeConfigurator,
            DEFAULT_FIXED_FEE_BPS,
            DEFAULT_SPLIT_FEE_BPS,
            makeAddr("feeRecipient")
        );
    }

    // setDefaultFeeConfig()

    function testFuzz_setDefaultFeeConfig_StoresFeesWithinMax(uint16 fixedFeeBps, uint16 splitFeeBps) public {
        fixedFeeBps = uint16(bound(fixedFeeBps, 0, FeeConstants.MAX_FEE_BPS));
        splitFeeBps = uint16(bound(splitFeeBps, 0, FeeConstants.MAX_FEE_BPS));

        vm.prank(feeConfigurator);
        registry.setDefaultFeeConfig(fixedFeeBps, splitFeeBps);

        (uint16 storedFixedFeeBps, uint16 storedSplitFeeBps) = registry.defaultFeeConfig();
        assertEq(storedFixedFeeBps, fixedFeeBps);
        assertEq(storedSplitFeeBps, splitFeeBps);
    }

    function testFuzz_setDefaultFeeConfig_RevertsWhenFixedFeeAboveMax(uint16 fixedFeeBps, uint16 splitFeeBps) public {
        fixedFeeBps = uint16(bound(fixedFeeBps, FeeConstants.MAX_FEE_BPS + 1, type(uint16).max));
        splitFeeBps = uint16(bound(splitFeeBps, 0, FeeConstants.MAX_FEE_BPS));

        vm.expectRevert(abi.encodeWithSelector(OnlendFeeRegistry.FixedFeeTooHigh.selector, fixedFeeBps));
        vm.prank(feeConfigurator);
        registry.setDefaultFeeConfig(fixedFeeBps, splitFeeBps);
    }

    function testFuzz_setDefaultFeeConfig_RevertsWhenSplitFeeAboveMax(uint16 fixedFeeBps, uint16 splitFeeBps) public {
        fixedFeeBps = uint16(bound(fixedFeeBps, 0, FeeConstants.MAX_FEE_BPS));
        splitFeeBps = uint16(bound(splitFeeBps, FeeConstants.MAX_FEE_BPS + 1, type(uint16).max));

        vm.expectRevert(abi.encodeWithSelector(OnlendFeeRegistry.SplitFeeTooHigh.selector, splitFeeBps));
        vm.prank(feeConfigurator);
        registry.setDefaultFeeConfig(fixedFeeBps, splitFeeBps);
    }

    // setPoolFeeConfigs()

    function testFuzz_setPoolFeeConfigs_StoresEachPoolFeeConfig(uint256 length, uint256 seed) public {
        length = bound(length, 0, MAX_BATCH_LENGTH);
        OnlendFeeRegistry.PoolFeeConfig[] memory configs = _poolFeeConfigs(length, seed);

        vm.prank(feeConfigurator);
        registry.setPoolFeeConfigs(configs);

        for (uint256 i; i < length; i++) {
            (uint16 fixedFeeBps, uint16 splitFeeBps) = registry.feeConfig(configs[i].pool);
            assertTrue(registry.hasPoolFeeConfig(configs[i].pool));
            assertEq(fixedFeeBps, configs[i].fixedFeeBps);
            assertEq(splitFeeBps, configs[i].splitFeeBps);
        }
    }

    function testFuzz_setPoolFeeConfigs_RevertsWhenAnyFixedFeeAboveMax(
        uint256 length,
        uint256 invalidIndex,
        uint16 invalidFeeBps,
        uint256 seed
    ) public {
        length = bound(length, 1, MAX_BATCH_LENGTH);
        invalidIndex = bound(invalidIndex, 0, length - 1);
        invalidFeeBps = uint16(bound(invalidFeeBps, FeeConstants.MAX_FEE_BPS + 1, type(uint16).max));
        OnlendFeeRegistry.PoolFeeConfig[] memory configs = _poolFeeConfigs(length, seed);
        configs[invalidIndex].fixedFeeBps = invalidFeeBps;

        vm.expectRevert(abi.encodeWithSelector(OnlendFeeRegistry.FixedFeeTooHigh.selector, invalidFeeBps));
        vm.prank(feeConfigurator);
        registry.setPoolFeeConfigs(configs);
    }

    function testFuzz_setPoolFeeConfigs_RevertsWhenAnySplitFeeAboveMax(
        uint256 length,
        uint256 invalidIndex,
        uint16 invalidFeeBps,
        uint256 seed
    ) public {
        length = bound(length, 1, MAX_BATCH_LENGTH);
        invalidIndex = bound(invalidIndex, 0, length - 1);
        invalidFeeBps = uint16(bound(invalidFeeBps, FeeConstants.MAX_FEE_BPS + 1, type(uint16).max));
        OnlendFeeRegistry.PoolFeeConfig[] memory configs = _poolFeeConfigs(length, seed);
        configs[invalidIndex].splitFeeBps = invalidFeeBps;

        vm.expectRevert(abi.encodeWithSelector(OnlendFeeRegistry.SplitFeeTooHigh.selector, invalidFeeBps));
        vm.prank(feeConfigurator);
        registry.setPoolFeeConfigs(configs);
    }

    // removePoolFeeConfigs()

    function testFuzz_removePoolFeeConfigs_RemovesOnlyListedPools(uint256 length, uint256 removeMask, uint256 seed)
        public
    {
        length = bound(length, 0, MAX_BATCH_LENGTH);
        OnlendFeeRegistry.PoolFeeConfig[] memory configs = _poolFeeConfigs(length, seed);
        vm.prank(feeConfigurator);
        registry.setPoolFeeConfigs(configs);
        address[] memory pools = _maskedPools(configs, removeMask);

        vm.prank(feeConfigurator);
        registry.removePoolFeeConfigs(pools);

        for (uint256 i; i < length; i++) {
            bool removed = (removeMask >> i) & 1 == 1;
            (uint16 fixedFeeBps, uint16 splitFeeBps) = registry.feeConfig(configs[i].pool);
            assertEq(registry.hasPoolFeeConfig(configs[i].pool), !removed);
            assertEq(fixedFeeBps, removed ? DEFAULT_FIXED_FEE_BPS : configs[i].fixedFeeBps);
            assertEq(splitFeeBps, removed ? DEFAULT_SPLIT_FEE_BPS : configs[i].splitFeeBps);
        }
    }

    function testFuzz_removePoolFeeConfigs_RevertsWhenAnyPoolHasNoOverride(
        uint256 length,
        uint256 missingIndex,
        uint256 seed
    ) public {
        length = bound(length, 1, MAX_BATCH_LENGTH);
        missingIndex = bound(missingIndex, 0, length - 1);
        OnlendFeeRegistry.PoolFeeConfig[] memory configs = _poolFeeConfigs(length, seed);
        address missingPool = _derivedPool(seed, length);
        vm.prank(feeConfigurator);
        registry.setPoolFeeConfigs(configs);
        address[] memory pools = _maskedPools(configs, type(uint256).max);
        pools[missingIndex] = missingPool;

        vm.expectRevert(abi.encodeWithSelector(OnlendFeeRegistry.PoolFeeConfigNotSet.selector, missingPool));
        vm.prank(feeConfigurator);
        registry.removePoolFeeConfigs(pools);
    }

    // setFeeRecipient()

    function testFuzz_setFeeRecipient_StoresNonZeroRecipient(address newFeeRecipient) public {
        vm.assume(newFeeRecipient != address(0));

        vm.prank(feeConfigurator);
        registry.setFeeRecipient(newFeeRecipient);

        assertEq(registry.feeRecipient(), newFeeRecipient);
    }

    // feeConfig()

    function testFuzz_feeConfig_ReturnsDefaultForPoolWithoutOverride(
        address pool,
        address otherPool,
        uint16 fixedFeeBps,
        uint16 splitFeeBps
    ) public {
        vm.assume(pool != otherPool);
        fixedFeeBps = uint16(bound(fixedFeeBps, 0, FeeConstants.MAX_FEE_BPS));
        splitFeeBps = uint16(bound(splitFeeBps, 0, FeeConstants.MAX_FEE_BPS));
        vm.prank(feeConfigurator);
        registry.setPoolFeeConfigs(_singlePoolFeeConfig(pool, fixedFeeBps, splitFeeBps));

        (uint16 otherFixedFeeBps, uint16 otherSplitFeeBps) = registry.feeConfig(otherPool);

        assertEq(otherFixedFeeBps, DEFAULT_FIXED_FEE_BPS);
        assertEq(otherSplitFeeBps, DEFAULT_SPLIT_FEE_BPS);
    }

    function _singlePoolFeeConfig(address pool, uint16 fixedFeeBps, uint16 splitFeeBps)
        internal
        pure
        returns (OnlendFeeRegistry.PoolFeeConfig[] memory configs)
    {
        configs = new OnlendFeeRegistry.PoolFeeConfig[](1);
        configs[0] = OnlendFeeRegistry.PoolFeeConfig({pool: pool, fixedFeeBps: fixedFeeBps, splitFeeBps: splitFeeBps});
    }

    /// @dev Builds `length` entries with fees within max, entry `i` for the pool `_derivedPool(seed, i)`. The pool
    ///      takes the low 160 bits of the entry's hash and the fees the bits above them.
    function _poolFeeConfigs(uint256 length, uint256 seed)
        internal
        pure
        returns (OnlendFeeRegistry.PoolFeeConfig[] memory configs)
    {
        configs = new OnlendFeeRegistry.PoolFeeConfig[](length);
        for (uint256 i; i < length; i++) {
            uint256 entrySeed = uint256(keccak256(abi.encode(seed, i)));
            configs[i] = OnlendFeeRegistry.PoolFeeConfig({
                pool: _derivedPool(seed, i),
                fixedFeeBps: uint16((entrySeed >> 160) % (FeeConstants.MAX_FEE_BPS + 1)),
                splitFeeBps: uint16((entrySeed >> 208) % (FeeConstants.MAX_FEE_BPS + 1))
            });
        }
    }

    /// @dev Distinct for each `index` under the same `seed`, so an index past a batch's length gives a pool outside it.
    function _derivedPool(uint256 seed, uint256 index) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encode(seed, index)))));
    }

    /// @dev Returns the pools of the entries whose bit is set in `mask`, in order.
    function _maskedPools(OnlendFeeRegistry.PoolFeeConfig[] memory configs, uint256 mask)
        internal
        pure
        returns (address[] memory pools)
    {
        pools = new address[](configs.length);
        uint256 count;
        for (uint256 i; i < configs.length; i++) {
            if ((mask >> i) & 1 == 1) pools[count++] = configs[i].pool;
        }

        // Shrink the array to the pools selected.
        assembly ("memory-safe") {
            mstore(pools, count)
        }
    }
}
