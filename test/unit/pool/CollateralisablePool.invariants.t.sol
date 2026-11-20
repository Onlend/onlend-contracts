// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

import {CollateralToken} from "src/pool/collateral/abstract/CollateralToken.sol";
import {ProtectedCollateralToken} from "src/pool/collateral/ProtectedCollateralToken.sol";
import {CollateralisablePool} from "src/pool/CollateralisablePool.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockFlashBorrower} from "./mocks/MockFlashBorrower.sol";

/// @notice Stateful handler — exercises protected collateral deposits and withdrawals across a fixed set of actors.
/// @dev Every action is bounded or guarded so the handler never reverts. Direct asset transfers and withdrawals to
///      the pool itself are intentionally excluded because the invariant covers flows between the pool and external
///      accounts.
// forge-lint: disable-next-line(multi-contract-file)
contract CollateralisablePoolHandler is Test {
    CollateralisablePool public pool;
    MockERC20 public asset;
    CollateralToken public collateralToken;
    address public lendingCore;

    address[] public actors;

    /// @dev The pool's balance and collateral just before the flash loan in flight went out, and the amount it lent.
    uint256 private _balanceBeforeLoan;
    uint256 private _collateralBeforeLoan;
    uint256 private _loanAmount;

    constructor(CollateralisablePool _pool, MockERC20 _asset, address _lendingCore) {
        pool = _pool;
        asset = _asset;
        collateralToken = CollateralToken(_pool.collateralToken());
        lendingCore = _lendingCore;

        actors.push(makeAddr("actor0"));
        actors.push(makeAddr("actor1"));
        actors.push(makeAddr("actor2"));
    }

    function depositCollateral(uint256 callerSeed, uint256 receiverSeed, uint256 assets) external {
        address caller = actors[callerSeed % actors.length];
        address receiver = actors[receiverSeed % actors.length];
        assets = bound(assets, 1, type(uint128).max);
        asset.mint(caller, assets);
        vm.prank(caller);
        asset.approve(address(pool), assets);

        vm.prank(lendingCore);
        pool.depositCollateral(caller, assets, 0, receiver);
    }

    function withdrawCollateral(uint256 callerSeed, uint256 receiverSeed, uint256 assets) external {
        address caller = actors[callerSeed % actors.length];
        uint256 availableAssets = collateralToken.balanceOf(caller);
        if (availableAssets == 0) return;
        address receiver = actors[receiverSeed % actors.length];
        assets = bound(assets, 1, availableAssets);

        vm.prank(lendingCore);
        pool.withdrawCollateral(caller, assets, 0, receiver);
    }

    function seizeCollateral(uint256 violatorSeed, uint256 receiverSeed, uint256 assets) external {
        address violator = actors[violatorSeed % actors.length];
        uint256 availableAssets = collateralToken.balanceOf(violator);
        if (availableAssets == 0) return;
        address receiver = actors[receiverSeed % actors.length];
        assets = bound(assets, 1, availableAssets);

        vm.prank(lendingCore);
        pool.seizeCollateral(violator, assets, receiver);
    }

    /// @dev Runs one of the other actions from within a flash loan's callback.
    function flashLoan(uint256 actionSeed, uint256 seedA, uint256 seedB, uint256 rawValue, uint256 rawAmount) external {
        (bytes4 action, uint256 maxPayout) = _flashLoanAction(actionSeed, seedA);
        uint256 maxAmount = asset.balanceOf(address(pool)) - maxPayout;
        if (maxAmount == 0) return;

        uint256 amount = bound(rawAmount, 1, maxAmount);
        MockFlashBorrower receiver = new MockFlashBorrower();
        receiver.addCallbackCall(address(this), abi.encodeCall(this.assertLoanMovedOnlyBalance, ()));
        receiver.addCallbackCall(address(this), abi.encodeWithSelector(action, seedA, seedB, rawValue));
        _balanceBeforeLoan = asset.balanceOf(address(pool));
        _collateralBeforeLoan = pool.totalCollateral();
        _loanAmount = amount;

        pool.flashLoan(receiver, address(asset), amount, "");
    }

    /// @dev Called from within a flash loan's callback ahead of its inner action.
    function assertLoanMovedOnlyBalance() external view {
        assertEq(asset.balanceOf(address(pool)), _balanceBeforeLoan - _loanAmount, "pool not short exactly the loan");
        assertEq(pool.totalCollateral(), _collateralBeforeLoan, "loan moved collateral");
    }

    /// @dev Picks the action a flash loan runs from within its callback.
    function _flashLoanAction(uint256 actionSeed, uint256 ownerSeed)
        private
        view
        returns (bytes4 action, uint256 maxPayout)
    {
        uint256 choice = actionSeed % 3;
        if (choice == 0) return (this.depositCollateral.selector, 0);

        uint256 collateral = collateralToken.balanceOf(actors[ownerSeed % actors.length]);
        if (choice == 1) return (this.withdrawCollateral.selector, collateral);
        return (this.seizeCollateral.selector, collateral);
    }
}

// forge-lint: disable-next-line(multi-contract-file)
contract CollateralisablePoolInvariantsTest is Test {
    CollateralisablePool internal pool;
    MockERC20 internal asset;
    CollateralToken internal collateralToken;
    CollateralisablePoolHandler internal handler;

    function setUp() public {
        asset = new MockERC20();
        CollateralisablePool poolImplementation = new CollateralisablePool();
        pool = CollateralisablePool(Clones.clone(address(poolImplementation)));

        ProtectedCollateralToken collateralImplementation = new ProtectedCollateralToken();
        ProtectedCollateralToken collateralClone =
            ProtectedCollateralToken(Clones.clone(address(collateralImplementation)));
        collateralClone.initialize(address(pool), "Protected USD Coin", "pUSDC", asset.decimals());

        pool.initialize(
            makeAddr("defaultAdmin"),
            makeAddr("hookUpdater"),
            makeAddr("flashLoanConfigurator"),
            address(0),
            0,
            0,
            makeAddr("lendingCore"),
            true,
            asset,
            address(collateralClone)
        );
        collateralToken = CollateralToken(pool.collateralToken());
        handler = new CollateralisablePoolHandler(pool, asset, makeAddr("lendingCore"));

        targetContract(address(handler));
        bytes4[] memory withinLoanOnly = new bytes4[](1);
        withinLoanOnly[0] = handler.assertLoanMovedOnlyBalance.selector;
        excludeSelector(FuzzSelector({addr: address(handler), selectors: withinLoanOnly}));
    }

    /// @dev Deposits and withdrawals between the pool and external accounts must preserve one-to-one accounting.
    function invariant_CollateralTokenSupplyEqualsPoolAssetBalance() public view {
        assertEq(collateralToken.totalSupply(), asset.balanceOf(address(pool)));
    }

    /// @dev Every asset accounted for by a protected pool is collateral and cannot be borrowed.
    function invariant_TotalAssetsEqualsTotalCollateral() public view {
        assertEq(pool.totalAssets(), pool.totalCollateral());
    }

    /// @dev Protected pools never issue debt.
    function invariant_TotalDebtIsAlwaysZero() public view {
        assertEq(pool.totalDebt(), 0);
    }
}
