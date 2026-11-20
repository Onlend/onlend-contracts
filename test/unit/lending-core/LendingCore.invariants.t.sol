// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {LendingCore} from "src/lending-core/LendingCore.sol";
import {MockLoanEvaluator} from "../loan/mocks/MockLoanEvaluator.sol";
import {MockLiquidationEngine} from "../liquidation/mocks/MockLiquidationEngine.sol";
import {MockPool} from "../pool/mocks/MockPool.sol";

/// @notice Stateful handler — drives the pool-listing state machine and evaluator/engine config, and
///         tracks every pool it has ever added so the test can assert listing monotonicity.
/// @dev Every action is guarded so the handler never reverts, keeping the run independent of the
///      `fail_on_revert` setting.
// forge-lint: disable-next-line(multi-contract-file)
contract LendingCoreHandler is Test {
    LendingCore public lendingCore;
    address public poolLister;
    address public loanUpdater;
    address public liquidationUpdater;

    MockPool[] public pools;
    MockPool[] public everAdded;

    constructor(LendingCore _lendingCore, address _poolLister, address _loanUpdater, address _liquidationUpdater) {
        lendingCore = _lendingCore;
        poolLister = _poolLister;
        loanUpdater = _loanUpdater;
        liquidationUpdater = _liquidationUpdater;

        // A fixed candidate set keeps addresses valid IPool targets and bounds the state space.
        for (uint256 i = 0; i < 5; i++) {
            pools.push(new MockPool());
        }
    }

    function addPool(uint256 seed) external {
        MockPool target = pools[seed % pools.length];
        if (lendingCore.isPoolAdded(address(target))) return;

        vm.prank(poolLister);
        lendingCore.addPool(address(target));
        everAdded.push(target);
    }

    function setDeprecatePool(uint256 seed, bool deprecated) external {
        MockPool target = pools[seed % pools.length];
        if (!lendingCore.isPoolAdded(address(target))) return;
        if ((lendingCore.poolStatus(address(target)) == LendingCore.PoolStatus.DEPRECATED) == deprecated) return;

        vm.prank(poolLister);
        lendingCore.setDeprecatePool(address(target), deprecated);
    }

    function everAddedCount() external view returns (uint256) {
        return everAdded.length;
    }
}

// forge-lint: disable-next-line(multi-contract-file)
contract LendingCoreInvariantsTest is Test {
    LendingCore internal lendingCore;
    LendingCoreHandler internal handler;

    function setUp() public {
        LendingCore implementation = new LendingCore();
        lendingCore = LendingCore(Clones.clone(address(implementation)));
        lendingCore.initialize(
            address(new MockLoanEvaluator()),
            address(new MockLiquidationEngine()),
            makeAddr("defaultAdmin"),
            makeAddr("hookUpdater"),
            address(0),
            0,
            0,
            makeAddr("poolLister"),
            makeAddr("loanUpdater"),
            makeAddr("liquidationUpdater"),
            makeAddr("badDebtConfigurator"),
            address(0),
            false,
            "",
            new address[](0)
        );
        handler = new LendingCoreHandler(
            lendingCore, makeAddr("poolLister"), makeAddr("loanUpdater"), makeAddr("liquidationUpdater")
        );

        targetContract(address(handler));
    }

    /// @dev There is no unlisting path, so any pool that was ever added stays added.
    function invariant_AddedPoolsRemainListed() public view {
        uint256 count = handler.everAddedCount();
        for (uint256 i = 0; i < count; i++) {
            address addedPool = address(handler.everAdded(i));
            assertTrue(lendingCore.isPoolAdded(addedPool));
        }
    }
}
