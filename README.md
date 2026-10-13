# opendefi — Loan Prediction Market

Collateralised peer-to-peer ETH loans, each with a built-in prediction market on whether the
borrower repays. The market's odds are a live, crowd-sourced price of the borrower's default risk.

Originally a 2021 OpenDeFi hackathon project (Truffle); rewritten for Foundry and
[Robinhood Chain](https://docs.robinhood.com/chain) (Arbitrum Orbit L2, ETH for gas).

## How it works

```
Funding ──(principal filled)──► Active ──(repaid by maturity)──► Repaid
   │                              │
   └─(deadline passes /           └─(maturity passes, anyone calls markDefault)──► Defaulted
      borrower cancels)──► Cancelled
```

1. **Request** – the borrower calls `LoanMarketFactory.createLoan(principal, interest, fundingDeadline, maturity)`
   sending collateral as `msg.value`. Each loan gets its own `LoanMarket` contract.
2. **Fund** – lenders call `lend()` until `principal` is filled; the loan becomes `Active`.
   If it isn't filled by `fundingDeadline`, anyone can `cancel()` and everyone is refunded.
3. **Draw** – the borrower calls `drawdown()` to receive the principal.
4. **Resolve** – no oracle needed:
   - `repay()` with exactly `principal + interest` on or before `maturity` → **Repaid**.
     Lenders split principal + interest pro rata; the borrower reclaims collateral.
   - otherwise, after `maturity` anyone calls `markDefault()` → **Defaulted**.
     Lenders split the collateral (plus any undrawn principal) pro rata.
5. **Predict** – while the loan is Funding/Active and before maturity, anyone can `bet(Side.Repay)`
   or `bet(Side.Default)`. It's parimutuel: winners split the whole pot in proportion to their stake.
   If the loan is cancelled, or nobody backed the winning side, bets are refunded.
   `impliedRepayBps()` gives the market's current repayment probability.

All payouts are pull-based (`claimLender`, `claimBet`, `withdrawCollateral`).

## Develop

Requires [Foundry](https://getfoundry.sh).

```sh
git submodule update --init --recursive
forge build
forge test
```

## Deploy to Robinhood Chain

| Network | Chain ID | RPC | Explorer |
|---|---|---|---|
| Testnet | 46630 | https://rpc.testnet.chain.robinhood.com | https://explorer.testnet.chain.robinhood.com |
| Mainnet | 4663  | https://rpc.mainnet.chain.robinhood.com | see docs.robinhood.com/chain |

Import a deployer key into an encrypted Foundry keystore (avoids plaintext keys in `.env`):

```sh
cast wallet import deployer --interactive
```

Testnet:

```sh
forge script script/Deploy.s.sol --rpc-url robinhood_testnet --account deployer --broadcast \
  --verify --verifier blockscout --verifier-url https://explorer.testnet.chain.robinhood.com/api/
```

Mainnet: same with `--rpc-url robinhood`, and the mainnet explorer's Blockscout API URL. The public
RPCs are rate-limited; use a dedicated provider (Alchemy, QuickNode, Chainstack) for production.

## Known limitations — read before using real money

**Not audited.** Get an audit before mainnet use with meaningful value.

- **Insider trading** – the borrower (or anyone they tip off) knows whether they will repay. A
  borrower can bet on `Default` from another address and walk away; collateral is their cost.
  Over-collateralise accordingly. Blocking the borrower's address would be trivially bypassed,
  so the contract doesn't pretend to.
- **Late information** – betting stays open until maturity, so late bettors have more information.
  A parimutuel pool with no time-weighting rewards waiting.
- **No partial repayment, no extensions, no liquidation** – collateral is only seized at maturity,
  and its value isn't checked against principal (fine for ETH-against-ETH; would need a price
  oracle for any other collateral).
- **Native ETH only.** Stablecoin loans would need an ERC-20 version (use SafeERC20; avoid
  fee-on-transfer tokens).
- Pro-rata payouts round down, leaving a few wei of dust in each resolved loan.
