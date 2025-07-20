# LendFi - Multi-Collateral Lending Protocol

**LendFi** is a decentralized finance (DeFi) lending protocol built in Clarity for the Stacks blockchain. It supports multiple collateral types, risk-based interest rates, and secure loan management.

---

## Features

- **Multi-Collateral Support:** Deposit various SIP-010 tokens as collateral.
- **Risk-Based Lending:** Each collateral type has its own LTV ratio, liquidation threshold, risk tier, and interest multiplier.
- **Loan Management:** Open, repay, boost, and liquidate loans.
- **Admin Controls:** Pause/unpause contract, set token contracts, configure collateral types.
- **Liquidation Tracking:** Records liquidation events for transparency.
- **Yield Calculation:** Interest is calculated based on collateral risk.

---

## Smart Contract Overview

- **Language:** Clarity
- **Main Contract:** lendFi.clar
- **Traits Used:** SIP-010 fungible token trait

---

## Key Data Structures

- `loans`: Stores loan details (owner, collateral, borrowed amount, status, collateral type).
- `collateral-types`: Stores parameters for each collateral token (LTV, risk, etc.).
- `liquidations`: Tracks liquidation events.

---

## Main Functions

| Function                | Description                                                      |
|-------------------------|------------------------------------------------------------------|
| `open-loan`             | Deposit collateral and borrow tokens.                            |
| `liquidate-loan`        | Liquidate unhealthy loans and seize collateral.                  |
| `trigger-repayment`     | Repay loan if accrued yield meets borrowed amount.               |
| `boost-collateral`      | Add more collateral to an existing loan.                         |
| `withdraw-yield`        | Admin withdraws excess yield tokens.                             |
| `set-collateral-type`   | Admin sets parameters for collateral tokens.                     |
| `pause` / `unpause`     | Admin pauses/unpauses contract operations.                       |
| `get-loan`              | View loan details.                                               |
| `get-collateral-type`   | View collateral type parameters.                                 |
| `get-liquidation`       | View liquidation event details.                                  |
| `get-loan-health`       | View health factor and liquidation status for a loan.            |
| `view-accrued-yield`    | View accrued yield for a loan.                                   |
| `get-contract-info`     | View contract admin, status, and token references.               |

---

## Error Codes

- `ERR-UNAUTHORIZED` (u100): Unauthorized action
- `ERR-LOAN-NOT-FOUND` (u101): Loan not found
- `ERR-LOAN-ALREADY-REPAID` (u102): Loan already repaid
- `ERR-INSUFFICIENT-COLLATERAL` (u103): Not enough collateral
- `ERR-REPAYMENT-FAILED` (u104): Repayment failed
- `ERR-PAUSED` (u900): Contract is paused
- `ERR-INVALID-AMOUNT` (u888): Invalid amount
- `ERR-TRANSFER-FAILED` (u999): Token transfer failed
- `ERR-TOKEN-NOT-SET` (u777): Token contract not set
- `ERR-COLLATERAL-TYPE-NOT-FOUND` (u105): Collateral type not found
- `ERR-COLLATERAL-TYPE-DISABLED` (u106): Collateral type disabled
- `ERR-LOAN-HEALTHY` (u107): Loan is healthy (not liquidatable)
- `ERR-LIQUIDATION-FAILED` (u108): Liquidation failed
- `ERR-INVALID-LIQUIDATION-AMOUNT` (u109): Invalid liquidation amount

---

## Usage

1. **Admin Setup:**
   - Set yield and borrow token contracts.
   - Configure collateral types and risk parameters.

2. **User Actions:**
   - Open a loan by depositing collateral.
   - Repay loan or boost collateral.
   - Monitor loan health and avoid liquidation.

3. **Liquidators:**
   - Liquidate unhealthy loans and receive collateral.

---

## Requirements

- Stacks blockchain
- SIP-010 compliant token contracts

---

## License

MIT License

---

## Disclaimer

This contract is for educational and experimental purposes. Use at your own risk. Always audit smart contracts before deploying to mainnet.
