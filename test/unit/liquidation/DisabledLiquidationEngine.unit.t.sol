// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {ILendingCore} from "src/lending-core/interfaces/ILendingCore.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {ILoanEvaluator} from "src/loan/interfaces/ILoanEvaluator.sol";
import {IPool} from "src/pool/interfaces/IPool.sol";
import {ILiquidationEngine} from "src/liquidation/interfaces/ILiquidationEngine.sol";
import {DisabledLiquidationEngine} from "src/liquidation/DisabledLiquidationEngine.sol";

import {LoanHelpers} from "../../helpers/LoanHelpers.sol";

contract DisabledLiquidationEngineUnitTest is Test {
    // The engine reverts before reading anything, so any health suffices.
    uint256 constant HEALTH = 0.5e18;

    DisabledLiquidationEngine implementation;
    DisabledLiquidationEngine engine;

    function setUp() public {
        implementation = new DisabledLiquidationEngine();
        engine = DisabledLiquidationEngine(Clones.clone(address(implementation)));
        engine.initialize();
    }

    // liquidate()

    function test_Liquidate_EmptyLoan_Reverts() public {
        vm.expectRevert(DisabledLiquidationEngine.LiquidationsDisabled.selector);
        engine.liquidate(
            LoanHelpers.emptyLoan(),
            HEALTH,
            LoanHelpers.noPositions(),
            LoanHelpers.noPositions(),
            ILoanEvaluator(address(0))
        );
    }

    function test_Liquidate_PopulatedLoan_Reverts() public {
        ILendingCore.Loan memory loan = LoanHelpers.loanWithSingleBorrow(address(0xACC0), IPool(address(0xB0)), 50e18);

        vm.expectRevert(DisabledLiquidationEngine.LiquidationsDisabled.selector);
        engine.liquidate(loan, HEALTH, LoanHelpers.noPositions(), LoanHelpers.noPositions(), ILoanEvaluator(address(0)));
    }

    function test_Liquidate_WithRequestedPositions_Reverts() public {
        ILendingCore.Loan memory loan = LoanHelpers.loanWithSingleBorrow(address(0xACC0), IPool(address(0xB0)), 50e18);

        ILendingCore.LoanPosition[] memory reqCols = LoanHelpers.noPositions();
        ILendingCore.LoanPosition[] memory reqBors = LoanHelpers.positions(loan.borrows[0].pool, 25e18);

        vm.expectRevert(DisabledLiquidationEngine.LiquidationsDisabled.selector);
        engine.liquidate(loan, HEALTH, reqCols, reqBors, ILoanEvaluator(address(0xE7A)));
    }

    // contractName()

    function test_contractName_ReturnsContractName() public view {
        assertEq(engine.contractName(), "DisabledLiquidationEngine");
    }

    // contractVersion()

    function test_contractVersion_ReturnsVersion() public view {
        assertEq(engine.contractVersion(), "1.0.0");
    }

    // supportsInterface()

    function test_SupportsInterface_LiquidationEngine_ReturnsTrue() public view {
        assertTrue(engine.supportsInterface(type(ILiquidationEngine).interfaceId));
    }

    function test_SupportsInterface_Versioned_ReturnsTrue() public view {
        assertTrue(engine.supportsInterface(type(IVersioned).interfaceId));
    }

    function test_SupportsInterface_ERC165_ReturnsTrue() public view {
        assertTrue(engine.supportsInterface(type(IERC165).interfaceId));
    }

    function test_SupportsInterface_Unknown_ReturnsFalse() public view {
        assertFalse(engine.supportsInterface(0xffffffff));
        assertFalse(engine.supportsInterface(0xdeadbeef));
    }
}
