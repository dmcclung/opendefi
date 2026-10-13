// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {LoanMarket} from "../src/LoanMarket.sol";
import {LoanMarketFactory} from "../src/LoanMarketFactory.sol";

contract RevertingReceiver {
    receive() external payable {
        revert();
    }
}

contract LoanMarketTest is Test {
    LoanMarketFactory factory;
    LoanMarket loan;

    address borrower = makeAddr("borrower");
    address alice = makeAddr("alice"); // lender
    address bob = makeAddr("bob"); // lender
    address carol = makeAddr("carol"); // bettor
    address dave = makeAddr("dave"); // bettor

    uint256 constant PRINCIPAL = 10 ether;
    uint256 constant INTEREST = 1 ether;
    uint256 constant COLLATERAL = 15 ether;
    uint256 fundingDeadline;
    uint256 maturity;

    function setUp() public {
        factory = new LoanMarketFactory();
        fundingDeadline = block.timestamp + 7 days;
        maturity = block.timestamp + 37 days;
        for (uint256 i; i < 5; i++) {
            vm.deal([borrower, alice, bob, carol, dave][i], 100 ether);
        }
        vm.prank(borrower);
        loan = factory.createLoan{value: COLLATERAL}(PRINCIPAL, INTEREST, fundingDeadline, maturity);
    }

    function _fund() internal {
        vm.prank(alice);
        loan.lend{value: 6 ether}();
        vm.prank(bob);
        loan.lend{value: 4 ether}();
    }

    function _fundAndDraw() internal {
        _fund();
        vm.prank(borrower);
        loan.drawdown();
    }

    // ---------------------------------------------------------------- setup

    function test_factoryRecordsLoan() public view {
        assertEq(factory.loanCount(), 1);
        assertEq(address(factory.loans(0)), address(loan));
        assertEq(loan.borrower(), borrower);
        assertEq(loan.collateral(), COLLATERAL);
        assertEq(address(loan).balance, COLLATERAL);
        assertEq(uint256(loan.state()), uint256(LoanMarket.State.Funding));
    }

    function test_createLoan_rejectsBadParams() public {
        vm.startPrank(borrower);
        vm.expectRevert(LoanMarket.InvalidParams.selector);
        factory.createLoan{value: 0}(PRINCIPAL, INTEREST, fundingDeadline, maturity);
        vm.expectRevert(LoanMarket.InvalidParams.selector);
        factory.createLoan{value: 1 ether}(0, INTEREST, fundingDeadline, maturity);
        vm.expectRevert(LoanMarket.InvalidParams.selector);
        factory.createLoan{value: 1 ether}(PRINCIPAL, INTEREST, block.timestamp, maturity);
        vm.expectRevert(LoanMarket.InvalidParams.selector);
        factory.createLoan{value: 1 ether}(PRINCIPAL, INTEREST, fundingDeadline, fundingDeadline);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------- funding

    function test_lend_fillsPrincipalAndActivates() public {
        _fund();
        assertEq(loan.totalLent(), PRINCIPAL);
        assertEq(loan.lent(alice), 6 ether);
        assertEq(uint256(loan.state()), uint256(LoanMarket.State.Active));
    }

    function test_lend_cannotExceedPrincipal() public {
        vm.prank(alice);
        vm.expectRevert(LoanMarket.ExceedsPrincipal.selector);
        loan.lend{value: PRINCIPAL + 1}();
    }

    function test_lend_closedAfterDeadline() public {
        vm.warp(fundingDeadline + 1);
        vm.prank(alice);
        vm.expectRevert(LoanMarket.FundingClosed.selector);
        loan.lend{value: 1 ether}();
    }

    function test_lend_rejectedOnceActive() public {
        _fund();
        vm.prank(alice);
        vm.expectRevert(LoanMarket.WrongState.selector);
        loan.lend{value: 1 wei}();
    }

    // ---------------------------------------------------------------- cancel

    function test_cancel_onlyBorrowerBeforeDeadline() public {
        vm.prank(alice);
        vm.expectRevert(LoanMarket.FundingOpen.selector);
        loan.cancel();

        vm.prank(borrower);
        loan.cancel();
        assertEq(uint256(loan.state()), uint256(LoanMarket.State.Cancelled));
    }

    function test_cancel_refundsEveryone() public {
        vm.prank(alice);
        loan.lend{value: 3 ether}();
        vm.prank(carol);
        loan.bet{value: 2 ether}(LoanMarket.Side.Default);

        vm.warp(fundingDeadline + 1);
        vm.prank(dave);
        loan.cancel();

        vm.prank(alice);
        loan.claimLender();
        vm.prank(carol);
        loan.claimBet();
        vm.prank(borrower);
        loan.withdrawCollateral();

        assertEq(alice.balance, 100 ether);
        assertEq(carol.balance, 100 ether);
        assertEq(borrower.balance, 100 ether);
        assertEq(address(loan).balance, 0);
    }

    function test_cancel_notAllowedOnceActive() public {
        _fund();
        vm.prank(borrower);
        vm.expectRevert(LoanMarket.WrongState.selector);
        loan.cancel();
    }

    // ---------------------------------------------------------------- drawdown

    function test_drawdown_onlyBorrowerOnce() public {
        _fund();
        vm.prank(alice);
        vm.expectRevert(LoanMarket.NotBorrower.selector);
        loan.drawdown();

        vm.prank(borrower);
        loan.drawdown();
        assertEq(borrower.balance, 100 ether - COLLATERAL + PRINCIPAL);

        vm.prank(borrower);
        vm.expectRevert(LoanMarket.WrongState.selector);
        loan.drawdown();
    }

    // ---------------------------------------------------------------- repaid path

    function test_repaid_lendersEarnInterestBorrowerGetsCollateral() public {
        _fundAndDraw();
        vm.prank(borrower);
        loan.repay{value: PRINCIPAL + INTEREST}();
        assertEq(uint256(loan.state()), uint256(LoanMarket.State.Repaid));

        vm.prank(alice);
        loan.claimLender();
        vm.prank(bob);
        loan.claimLender();
        vm.prank(borrower);
        loan.withdrawCollateral();

        assertEq(alice.balance, 100 ether + 0.6 ether); // 60% of the interest
        assertEq(bob.balance, 100 ether + 0.4 ether);
        assertEq(borrower.balance, 100 ether - INTEREST);
        assertEq(address(loan).balance, 0);
    }

    function test_repay_requiresExactAmount() public {
        _fundAndDraw();
        vm.prank(borrower);
        vm.expectRevert(LoanMarket.WrongAmount.selector);
        loan.repay{value: PRINCIPAL}();
    }

    function test_repay_requiresDrawdown() public {
        _fund();
        vm.prank(borrower);
        vm.expectRevert(LoanMarket.NotDrawn.selector);
        loan.repay{value: PRINCIPAL + INTEREST}();
    }

    function test_repay_closedAfterMaturity() public {
        _fundAndDraw();
        vm.warp(maturity + 1);
        vm.prank(borrower);
        vm.expectRevert(LoanMarket.PastMaturity.selector);
        loan.repay{value: PRINCIPAL + INTEREST}();
    }

    function test_repay_byThirdParty() public {
        _fundAndDraw();
        vm.prank(dave);
        loan.repay{value: PRINCIPAL + INTEREST}();
        assertEq(uint256(loan.state()), uint256(LoanMarket.State.Repaid));
    }

    // ---------------------------------------------------------------- default path

    function test_default_lendersSplitCollateral() public {
        _fundAndDraw();

        vm.expectRevert(LoanMarket.NotMatured.selector);
        loan.markDefault();

        vm.warp(maturity + 1);
        loan.markDefault();

        vm.prank(alice);
        loan.claimLender();
        vm.prank(bob);
        loan.claimLender();
        assertEq(alice.balance, 100 ether - 6 ether + 9 ether); // 60% of 15 ETH collateral
        assertEq(bob.balance, 100 ether - 4 ether + 6 ether);

        vm.prank(borrower);
        vm.expectRevert(LoanMarket.WrongState.selector);
        loan.withdrawCollateral();
    }

    function test_default_withoutDrawdownReturnsPrincipalToo() public {
        _fund();
        vm.warp(maturity + 1);
        loan.markDefault();
        vm.prank(alice);
        loan.claimLender();
        vm.prank(bob);
        loan.claimLender();
        assertEq(address(loan).balance, 0);
        assertEq(alice.balance + bob.balance, 200 ether + COLLATERAL);
    }

    function test_claimLender_onlyOnce() public {
        _fundAndDraw();
        vm.warp(maturity + 1);
        loan.markDefault();
        vm.startPrank(alice);
        loan.claimLender();
        vm.expectRevert(LoanMarket.NothingToClaim.selector);
        loan.claimLender();
        vm.stopPrank();
    }

    function test_claimLender_notBeforeResolution() public {
        _fundAndDraw();
        vm.prank(alice);
        vm.expectRevert(LoanMarket.NothingToClaim.selector);
        loan.claimLender();
    }

    // ---------------------------------------------------------------- prediction market

    function test_bets_winnersSplitLosingPool() public {
        vm.prank(carol);
        loan.bet{value: 3 ether}(LoanMarket.Side.Repay);
        vm.prank(dave);
        loan.bet{value: 1 ether}(LoanMarket.Side.Default);
        assertEq(loan.impliedRepayBps(), 7_500);

        _fundAndDraw();
        vm.prank(borrower);
        loan.repay{value: PRINCIPAL + INTEREST}();

        assertEq(loan.betPayout(dave), 0);
        vm.prank(carol);
        loan.claimBet();
        assertEq(carol.balance, 101 ether);

        vm.prank(dave);
        vm.expectRevert(LoanMarket.NothingToClaim.selector);
        loan.claimBet();
    }

    function test_bets_defaultSideWins() public {
        _fundAndDraw();
        vm.prank(carol);
        loan.bet{value: 3 ether}(LoanMarket.Side.Repay);
        vm.prank(dave);
        loan.bet{value: 1 ether}(LoanMarket.Side.Default);

        vm.warp(maturity + 1);
        loan.markDefault();
        vm.prank(dave);
        loan.claimBet();
        assertEq(dave.balance, 103 ether);
    }

    function test_bets_refundedWhenWinningSideEmpty() public {
        _fundAndDraw();
        vm.prank(dave);
        loan.bet{value: 2 ether}(LoanMarket.Side.Default);
        vm.prank(borrower);
        loan.repay{value: PRINCIPAL + INTEREST}();
        vm.prank(dave);
        loan.claimBet();
        assertEq(dave.balance, 100 ether);
    }

    function test_bets_closedAfterResolutionAndMaturity() public {
        _fundAndDraw();
        vm.warp(maturity + 1);
        vm.prank(carol);
        vm.expectRevert(LoanMarket.PastMaturity.selector);
        loan.bet{value: 1 ether}(LoanMarket.Side.Default);

        loan.markDefault();
        vm.prank(carol);
        vm.expectRevert(LoanMarket.WrongState.selector);
        loan.bet{value: 1 ether}(LoanMarket.Side.Default);
    }

    function test_transferFailureReverts() public {
        RevertingReceiver r = new RevertingReceiver();
        vm.deal(address(r), 10 ether);
        vm.prank(address(r));
        loan.lend{value: 1 ether}();
        vm.prank(borrower);
        loan.cancel();
        vm.prank(address(r));
        vm.expectRevert(LoanMarket.TransferFailed.selector);
        loan.claimLender();
        assertEq(loan.lent(address(r)), 1 ether); // state rolled back, can retry later
    }

    // ---------------------------------------------------------------- fuzz

    /// Whatever the amounts and outcome, every party can claim and the contract never
    /// owes more than it holds; leftover is only rounding dust.
    function testFuzz_solvency(
        uint96 lendA,
        uint96 betRepay,
        uint96 betDefault,
        uint96 interest,
        uint96 collateral,
        uint8 outcome
    ) public {
        uint256 principal = uint256(lendA) + 1 ether;
        collateral = uint96(bound(collateral, 1, type(uint96).max));
        outcome = uint8(bound(outcome, 0, 3));

        vm.deal(borrower, type(uint128).max);
        vm.deal(alice, type(uint128).max);
        vm.deal(bob, type(uint128).max);
        vm.deal(carol, type(uint128).max);
        vm.deal(dave, type(uint128).max);

        vm.prank(borrower);
        LoanMarket l = factory.createLoan{value: collateral}(principal, interest, fundingDeadline, maturity);
        if (betRepay > 0) {
            vm.prank(carol);
            l.bet{value: betRepay}(LoanMarket.Side.Repay);
        }
        if (betDefault > 0) {
            vm.prank(dave);
            l.bet{value: betDefault}(LoanMarket.Side.Default);
        }
        if (lendA > 0) {
            vm.prank(alice);
            l.lend{value: lendA}();
        }

        if (outcome == 0) {
            vm.prank(borrower);
            l.cancel();
        } else {
            vm.prank(bob);
            l.lend{value: 1 ether}();
            if (outcome == 1) {
                vm.prank(borrower);
                l.drawdown();
                uint256 due = l.amountDue();
                vm.prank(borrower);
                l.repay{value: due}();
            } else {
                if (outcome == 2) {
                    vm.prank(borrower);
                    l.drawdown();
                }
                vm.warp(maturity + 1);
                l.markDefault();
            }
        }

        address[4] memory claimants = [alice, bob, carol, dave];
        for (uint256 i; i < 4; i++) {
            vm.startPrank(claimants[i]);
            if (l.lenderPayout(claimants[i]) > 0) l.claimLender();
            if (l.betPayout(claimants[i]) > 0) l.claimBet();
            vm.stopPrank();
        }
        if (outcome <= 1) {
            vm.prank(borrower);
            l.withdrawCollateral();
        }
        assertLe(address(l).balance, 4, "more than rounding dust left behind");
    }
}
