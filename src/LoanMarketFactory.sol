// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {LoanMarket} from "./LoanMarket.sol";

/// @title LoanMarketFactory
/// @notice Deploys one isolated LoanMarket per loan, so a bug or exploit in one loan cannot
///         drain funds held by another.
contract LoanMarketFactory {
    LoanMarket[] public loans;

    event LoanCreated(
        LoanMarket indexed loan,
        address indexed borrower,
        uint256 principal,
        uint256 interest,
        uint256 collateral,
        uint256 fundingDeadline,
        uint256 maturity
    );

    /// @notice Request a loan. Send the collateral as `msg.value`.
    function createLoan(uint256 principal, uint256 interest, uint256 fundingDeadline, uint256 maturity)
        external
        payable
        returns (LoanMarket loan)
    {
        loan = new LoanMarket{value: msg.value}(msg.sender, principal, interest, fundingDeadline, maturity);
        loans.push(loan);
        emit LoanCreated(loan, msg.sender, principal, interest, msg.value, fundingDeadline, maturity);
    }

    function loanCount() external view returns (uint256) {
        return loans.length;
    }
}
