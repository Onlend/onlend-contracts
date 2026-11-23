// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {LendingCore} from "src/lending-core/LendingCore.sol";
import {ILendingCore} from "src/lending-core/interfaces/ILendingCore.sol";
import {TargetHealthLiquidationEngine} from "src/liquidation/TargetHealthLiquidationEngine.sol";
import {FactorLoanEvaluator} from "src/loan/FactorLoanEvaluator.sol";
import {OnlendFeeRegistry} from "src/onlend-managed/fees/OnlendFeeRegistry.sol";
import {CollateralisableBorrowablePool} from "src/pool/CollateralisableBorrowablePool.sol";
import {CollateralisablePool} from "src/pool/CollateralisablePool.sol";
import {BorrowableCollateralToken} from "src/pool/collateral/BorrowableCollateralToken.sol";
import {ProtectedCollateralToken} from "src/pool/collateral/ProtectedCollateralToken.sol";
import {MultiInterestDebtToken} from "src/pool/debt/MultiInterestDebtToken.sol";
import {IPool} from "src/pool/interfaces/IPool.sol";
import {ComposedIRM} from "src/pool/irm/ComposedIRM.sol";

import {LoanHelpers} from "../helpers/LoanHelpers.sol";
import {MockOracle} from "../mocks/MockOracle.sol";
import {MockToken} from "../mocks/MockToken.sol";

/// @notice Deploys one lending app from the real implementations, as an operator would, for proofs of concept.
/// @dev The app has two pools:
///      - `usdcPool`: a `CollateralisableBorrowablePool` of a 6-decimal stablecoin. Lenders supply to it, borrowers
///        borrow from it, and its shares can also back a loan.
///      - `wethPool`: a `CollateralisablePool` of an 18-decimal asset, holding protected collateral.
///
///      Prices come from `MockOracle` and can be moved with `_setPrice`. Every role, in every contract, is held by
///      `operator`. Bad debt socialisation is enabled and hooks are disabled; use the `operator` to change either.
///      `_deployCollateralisableBorrowablePool` and `_deployCollateralisablePool` add further pools, which must then be
///      configured in the evaluator, engine and oracle and listed with `lendingCore.addPool`.
abstract contract PoCBase is Test {
    // Oracle prices, per whole unit at 18dp.
    uint256 internal constant USDC_PRICE = 1e18;
    uint256 internal constant WETH_PRICE = 2000e18;

    // FactorLoanEvaluator.
    uint256 internal constant MIN_HEALTH_FACTOR = 1.05e18;
    uint16 internal constant USDC_COLLATERAL_FACTOR = 0.9e4;
    uint16 internal constant WETH_COLLATERAL_FACTOR = 0.8e4;
    uint32 internal constant BORROW_FACTOR = 1e4;

    // TargetHealthLiquidationEngine. Satisfies `collateralFactor * (1 + maxBonus) < 1` for both collaterals.
    uint256 internal constant TARGET_HEALTH_FACTOR = 1.02e18;
    uint256 internal constant BONUS_RAMP_START_HEALTH = 1e18;
    uint256 internal constant BONUS_RAMP_END_HEALTH = 0.9e18;
    uint256 internal constant MIN_LEFTOVER_VALUE = 10e18;
    uint256 internal constant CLOSE_OUT_THRESHOLD = 20e18;
    uint16 internal constant USDC_MIN_BONUS = 0.01e4;
    uint16 internal constant USDC_MAX_BONUS = 0.05e4;
    uint16 internal constant WETH_MIN_BONUS = 0.02e4;
    uint16 internal constant WETH_MAX_BONUS = 0.1e4;

    // ComposedIRM: piecewise linear borrow rate, fixed retention, applicable to every account.
    uint256 internal constant BASE_RATE = 0;
    uint256 internal constant OPTIMAL_UTILISATION = 0.8e18;
    uint256 internal constant SLOPE_1 = 0.04e18;
    uint256 internal constant SLOPE_2 = 0.6e18;
    uint256 internal constant RETENTION_RATE = 0.1e18;

    // OnlendFeeRegistry.
    uint16 internal constant ONLEND_FIXED_FEE_BPS = 100;
    uint16 internal constant ONLEND_SPLIT_FEE_BPS = 2000;

    address internal operator = makeAddr("operator");
    address internal onlend = makeAddr("onlend");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    MockToken internal usdc;
    MockToken internal weth;
    MockOracle internal oracle;
    OnlendFeeRegistry internal feeRegistry;

    LendingCore internal lendingCore;
    FactorLoanEvaluator internal loanEvaluator;
    TargetHealthLiquidationEngine internal liquidationEngine;
    CollateralisableBorrowablePool internal usdcPool;
    CollateralisablePool internal wethPool;

    LendingCore private _lendingCoreImpl;
    FactorLoanEvaluator private _loanEvaluatorImpl;
    TargetHealthLiquidationEngine private _liquidationEngineImpl;
    CollateralisableBorrowablePool private _collateralisableBorrowablePoolImpl;
    CollateralisablePool private _collateralisablePoolImpl;
    BorrowableCollateralToken private _borrowableCollateralTokenImpl;
    ProtectedCollateralToken private _protectedCollateralTokenImpl;
    MultiInterestDebtToken private _debtTokenImpl;
    ComposedIRM private _irmImpl;

    function setUp() public virtual {
        usdc = new MockToken("USD Coin", "USDC", 6);
        weth = new MockToken("Wrapped Ether", "WETH", 18);
        oracle = new MockOracle();
        feeRegistry = new OnlendFeeRegistry(onlend, onlend, ONLEND_FIXED_FEE_BPS, ONLEND_SPLIT_FEE_BPS, onlend);

        _lendingCoreImpl = new LendingCore();
        _loanEvaluatorImpl = new FactorLoanEvaluator();
        _liquidationEngineImpl = new TargetHealthLiquidationEngine();
        _collateralisableBorrowablePoolImpl = new CollateralisableBorrowablePool();
        _collateralisablePoolImpl = new CollateralisablePool();
        _borrowableCollateralTokenImpl = new BorrowableCollateralToken();
        _protectedCollateralTokenImpl = new ProtectedCollateralToken();
        _debtTokenImpl = new MultiInterestDebtToken();
        _irmImpl = new ComposedIRM();

        // Pools are bound to the LendingCore when initialised, so it is cloned first and initialised last.
        lendingCore = LendingCore(Clones.clone(address(_lendingCoreImpl)));
        usdcPool = _deployCollateralisableBorrowablePool(usdc);
        wethPool = _deployCollateralisablePool(weth);

        oracle.setPrice(usdcPool, USDC_PRICE, usdc.decimals());
        oracle.setPrice(wethPool, WETH_PRICE, weth.decimals());

        _deployLoanEvaluator();
        _deployLiquidationEngine();

        address[] memory pools = new address[](2);
        pools[0] = address(usdcPool);
        pools[1] = address(wethPool);
        lendingCore.initialize(
            address(loanEvaluator),
            address(liquidationEngine),
            operator,
            operator,
            address(0),
            0,
            0,
            operator,
            operator,
            operator,
            operator,
            operator,
            true,
            "{}",
            pools
        );

        usdc.mint(alice, 1_000_000e6);
        usdc.mint(carol, 1_000_000e6);
        weth.mint(bob, 1000e18);
    }

    // Deployment

    /// @dev Deploys a `CollateralisableBorrowablePool` with its debt token, collateral token and one `ComposedIRM`.
    function _deployCollateralisableBorrowablePool(MockToken asset)
        internal
        returns (CollateralisableBorrowablePool pool)
    {
        pool = CollateralisableBorrowablePool(Clones.clone(address(_collateralisableBorrowablePoolImpl)));
        MultiInterestDebtToken debtToken = MultiInterestDebtToken(Clones.clone(address(_debtTokenImpl)));
        BorrowableCollateralToken collateralToken =
            BorrowableCollateralToken(Clones.clone(address(_borrowableCollateralTokenImpl)));

        address[] memory irmIds = new address[](1);
        irmIds[0] = address(_deployIrm(address(debtToken)));

        string memory symbol = asset.symbol();
        debtToken.initialize(
            address(pool),
            string.concat("Debt ", symbol),
            string.concat("d", symbol),
            asset.decimals(),
            operator,
            operator,
            irmIds
        );
        collateralToken.initialize(
            address(pool), string.concat("Collateral ", symbol), string.concat("c", symbol), asset.decimals()
        );
        pool.initialize(
            operator,
            operator,
            operator,
            operator,
            address(0),
            0,
            0,
            address(lendingCore),
            true,
            IERC20Metadata(address(asset)),
            string.concat("Onlend ", symbol),
            string.concat("o", symbol),
            address(collateralToken),
            address(debtToken),
            address(feeRegistry),
            operator
        );
    }

    /// @dev Deploys a `CollateralisablePool` with its protected collateral token.
    function _deployCollateralisablePool(MockToken asset) internal returns (CollateralisablePool pool) {
        pool = CollateralisablePool(Clones.clone(address(_collateralisablePoolImpl)));
        ProtectedCollateralToken collateralToken =
            ProtectedCollateralToken(Clones.clone(address(_protectedCollateralTokenImpl)));

        string memory symbol = asset.symbol();
        collateralToken.initialize(
            address(pool), string.concat("Protected ", symbol), string.concat("p", symbol), asset.decimals()
        );
        pool.initialize(
            operator,
            operator,
            operator,
            address(0),
            0,
            0,
            address(lendingCore),
            true,
            IERC20Metadata(address(asset)),
            address(collateralToken)
        );
    }

    /// @dev Deploys a `ComposedIRM` whose `borrowRate` only `debtToken` can call.
    function _deployIrm(address debtToken) internal returns (ComposedIRM irm) {
        irm = ComposedIRM(Clones.clone(address(_irmImpl)));
        irm.initialize(
            debtToken,
            ComposedIRM.BorrowRateType.PIECEWISE_LINEAR,
            abi.encode(BASE_RATE, OPTIMAL_UTILISATION, SLOPE_1, SLOPE_2),
            ComposedIRM.RetentionRateType.FIXED,
            abi.encode(RETENTION_RATE),
            ComposedIRM.ConditionType.ALWAYS_APPLICABLE,
            "",
            operator,
            operator,
            operator,
            operator
        );
    }

    function _deployLoanEvaluator() private {
        FactorLoanEvaluator.PoolFactorConfig[] memory configs = new FactorLoanEvaluator.PoolFactorConfig[](2);
        configs[0] = FactorLoanEvaluator.PoolFactorConfig(usdcPool, USDC_COLLATERAL_FACTOR, BORROW_FACTOR);
        configs[1] = FactorLoanEvaluator.PoolFactorConfig(wethPool, WETH_COLLATERAL_FACTOR, BORROW_FACTOR);

        loanEvaluator = FactorLoanEvaluator(Clones.clone(address(_loanEvaluatorImpl)));
        loanEvaluator.initialize(operator, operator, operator, address(oracle), MIN_HEALTH_FACTOR, configs);
    }

    function _deployLiquidationEngine() private {
        TargetHealthLiquidationEngine.CollateralBonusConfig[] memory configs =
            new TargetHealthLiquidationEngine.CollateralBonusConfig[](2);
        configs[0] = TargetHealthLiquidationEngine.CollateralBonusConfig(usdcPool, USDC_MIN_BONUS, USDC_MAX_BONUS);
        configs[1] = TargetHealthLiquidationEngine.CollateralBonusConfig(wethPool, WETH_MIN_BONUS, WETH_MAX_BONUS);

        liquidationEngine = TargetHealthLiquidationEngine(Clones.clone(address(_liquidationEngineImpl)));
        liquidationEngine.initialize(
            operator,
            operator,
            operator,
            address(oracle),
            TARGET_HEALTH_FACTOR,
            BONUS_RAMP_START_HEALTH,
            BONUS_RAMP_END_HEALTH,
            MIN_LEFTOVER_VALUE,
            CLOSE_OUT_THRESHOLD,
            configs
        );
    }

    // User actions

    /// @dev Supplies `assets` to a borrowable pool through ERC-4626 `deposit`.
    function _supply(address user, CollateralisableBorrowablePool pool, uint256 assets)
        internal
        returns (uint256 shares)
    {
        vm.startPrank(user);
        IERC20Metadata(pool.asset()).approve(address(pool), assets);
        shares = pool.deposit(assets, user);
        vm.stopPrank();
    }

    /// @dev Deposits `assets` of collateral into `pool` for `user`'s loan.
    function _depositCollateral(address user, IPool pool, uint256 assets) internal {
        vm.startPrank(user);
        IERC20Metadata(pool.asset()).approve(address(pool), assets);
        lendingCore.depositCollateral(pool, assets, 0, user);
        vm.stopPrank();
    }

    /// @dev Withdraws `assets` of collateral from `pool` to `user`.
    function _withdrawCollateral(address user, IPool pool, uint256 assets) internal {
        vm.prank(user);
        lendingCore.withdrawCollateral(pool, assets, 0, user, user);
    }

    /// @dev Borrows `amount` from `pool` to `user`.
    function _borrow(address user, IPool pool, uint256 amount) internal {
        vm.prank(user);
        lendingCore.borrow(pool, amount, user, user);
    }

    /// @dev Repays up to `amount` of `user`'s debt in `pool` from `user`'s own funds.
    function _repay(address user, IPool pool, uint256 amount) internal returns (uint256 repayment) {
        vm.startPrank(user);
        IERC20Metadata(pool.asset()).approve(address(pool), amount);
        repayment = lendingCore.repay(pool, amount, user);
        vm.stopPrank();
    }

    /// @dev Liquidates `violator`, seizing `seizeAssets` from `colPool` and repaying up to `repayAmount` in `borPool`.
    function _liquidate(
        address liquidator,
        address violator,
        IPool colPool,
        uint256 seizeAssets,
        IPool borPool,
        uint256 repayAmount
    ) internal {
        vm.startPrank(liquidator);
        IERC20Metadata(borPool.asset()).approve(address(borPool), repayAmount);
        lendingCore.liquidate(
            violator, LoanHelpers.positions(colPool, seizeAssets), LoanHelpers.positions(borPool, repayAmount)
        );
        vm.stopPrank();
    }

    // Environment

    /// @dev Sets `pool`'s price per whole unit, at 18dp.
    function _setPrice(IPool pool, uint256 price) internal {
        oracle.setPrice(pool, price, IERC20Metadata(pool.asset()).decimals());
    }

    /// @dev Moves time forward by `elapsed` seconds.
    function _skip(uint256 elapsed) internal {
        vm.warp(vm.getBlockTimestamp() + elapsed);
    }

    // Views

    /// @dev `account`'s health as the loan evaluator reports it.
    function _health(address account) internal view returns (uint256) {
        return loanEvaluator.getLoanHealth(lendingCore.loanOf(account));
    }

    /// @dev Whether `account`'s loan is liquidatable.
    function _isLiquidatable(address account) internal view returns (bool liquidatable) {
        (liquidatable,) = loanEvaluator.isLoanLiquidatable(lendingCore.loanOf(account));
    }

    /// @dev `account`'s loan as `LendingCore` builds it.
    function _loan(address account) internal view returns (ILendingCore.Loan memory) {
        return lendingCore.loanOf(account);
    }
}
