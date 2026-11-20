// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

import {ILendingCore} from "src/lending-core/interfaces/ILendingCore.sol";
import {FactorLoanEvaluator} from "src/loan/FactorLoanEvaluator.sol";
import {IPool} from "src/pool/interfaces/IPool.sol";
import {MockOracle} from "../../mocks/MockOracle.sol";

/// @notice Stateful handler — exposes every configuration action and tracks the pools it has added.
// forge-lint: disable-next-line(multi-contract-file)
contract FactorLoanEvaluatorHandler is Test {
    uint16 internal constant ONE_4_DP = 10_000;
    uint256 internal constant ONE_18_DP = 1e18;

    /// @dev Ceilings chosen so that a loan across every pool a run can add stays far from overflowing a health.
    uint32 internal constant MAX_BORROW_FACTOR = 1e8;
    uint256 internal constant MAX_PRICE = 1e20;
    uint256 internal constant MAX_MIN_HEALTH_FACTOR = 100e18;

    FactorLoanEvaluator public evaluator;
    MockOracle public oracle;
    address public factorConfigurator;

    IPool[] public addedPools;

    constructor(FactorLoanEvaluator _evaluator, MockOracle _oracle, address _factorConfigurator) {
        evaluator = _evaluator;
        oracle = _oracle;
        factorConfigurator = _factorConfigurator;
    }

    function addPool(uint16 collateralFactor, uint32 borrowFactor, uint256 price, uint8 assetDecimals) external {
        collateralFactor = uint16(bound(collateralFactor, 0, ONE_4_DP));
        borrowFactor = uint32(bound(borrowFactor, ONE_4_DP, MAX_BORROW_FACTOR));
        price = bound(price, 1, MAX_PRICE);
        assetDecimals = uint8(bound(assetDecimals, 0, 18));
        IPool pool = IPool(address(uint160(uint256(keccak256(abi.encode(addedPools.length))))));

        oracle.setPrice(pool, price, assetDecimals);
        vm.prank(factorConfigurator);
        evaluator.addPool(pool, collateralFactor, borrowFactor);
        addedPools.push(pool);
    }

    function updateCollateralFactor(uint256 poolSeed, uint16 collateralFactor) external {
        if (addedPools.length == 0) return;
        IPool pool = addedPools[bound(poolSeed, 0, addedPools.length - 1)];
        collateralFactor = uint16(bound(collateralFactor, 0, ONE_4_DP));

        vm.prank(factorConfigurator);
        evaluator.updateCollateralFactor(pool, collateralFactor);
    }

    function updateBorrowFactor(uint256 poolSeed, uint32 borrowFactor) external {
        if (addedPools.length == 0) return;
        IPool pool = addedPools[bound(poolSeed, 0, addedPools.length - 1)];
        borrowFactor = uint32(bound(borrowFactor, ONE_4_DP, MAX_BORROW_FACTOR));

        vm.prank(factorConfigurator);
        evaluator.updateBorrowFactor(pool, borrowFactor);
    }

    function updateMinHealthFactor(uint256 minHealthFactor) external {
        minHealthFactor = bound(minHealthFactor, ONE_18_DP, MAX_MIN_HEALTH_FACTOR);

        vm.prank(factorConfigurator);
        evaluator.updateMinHealthFactor(minHealthFactor);
    }

    function addedPoolsCount() external view returns (uint256) {
        return addedPools.length;
    }
}

// forge-lint: disable-next-line(multi-contract-file)
contract FactorLoanEvaluatorInvariantsTest is Test {
    uint16 internal constant ONE_4_DP = 10_000;
    uint256 internal constant ONE_18_DP = 1e18;
    uint256 internal constant POSITION_AMOUNT = 1e18;

    FactorLoanEvaluator internal implementation;
    FactorLoanEvaluator internal evaluator;
    MockOracle internal oracle;
    FactorLoanEvaluatorHandler internal handler;

    function setUp() public {
        address factorConfigurator = makeAddr("factorConfigurator");
        oracle = new MockOracle();

        implementation = new FactorLoanEvaluator();
        evaluator = FactorLoanEvaluator(Clones.clone(address(implementation)));
        evaluator.initialize(
            makeAddr("defaultAdmin"),
            address(0),
            factorConfigurator,
            address(oracle),
            ONE_18_DP,
            new FactorLoanEvaluator.PoolFactorConfig[](0)
        );
        handler = new FactorLoanEvaluatorHandler(evaluator, oracle, factorConfigurator);

        targetContract(address(handler));
    }

    /// A loan holding every pool ever added must stay evaluable.
    function invariant_AddedPoolsRemainEvaluable() public view {
        uint256 count = handler.addedPoolsCount();
        ILendingCore.LoanPosition[] memory positions = new ILendingCore.LoanPosition[](count);
        for (uint256 i; i < count; ++i) {
            positions[i] = ILendingCore.LoanPosition({pool: handler.addedPools(i), amount: POSITION_AMOUNT});
        }

        evaluator.getLoanHealth(ILendingCore.Loan({account: address(this), collaterals: positions, borrows: positions}));
    }

    /// Every pool ever added stays added, and keeps factors that discount collateral and inflate borrows.
    function invariant_AddedPoolsKeepValidFactors() public view {
        uint256 count = handler.addedPoolsCount();
        for (uint256 i; i < count; ++i) {
            IPool pool = handler.addedPools(i);
            FactorLoanEvaluator.PoolFactors memory factors = evaluator.getPoolFactors(pool);
            assertTrue(evaluator.isPoolAdded(pool));
            assertLe(factors.collateralFactor, ONE_4_DP);
            assertGe(factors.borrowFactor, ONE_4_DP);
        }
    }

    /// A healthy loan must never be one that is already liquidatable, which holds only while the minimum health
    /// factor stays at or above the solvency boundary.
    function invariant_MinHealthFactorStaysAboveSolvency() public view {
        assertGe(evaluator.minHealthFactor(), ONE_18_DP);
    }
}
