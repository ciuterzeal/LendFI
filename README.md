# LendFi - Multi-Collateral Lending Protocol

**LendFi** is a secure, decentralized finance (DeFi) lending protocol built in Clarity for the Stacks blockchain. It supports multiple collateral types, risk-based interest rates, comprehensive input validation, and secure loan management with enhanced security features.

---

## 🔒 Security Features

- **Comprehensive Input Validation:** All user inputs are validated against predefined bounds
- **Contract Address Verification:** Prevents malicious contract substitution attacks
- **Range Checking:** Protects against overflow/underflow vulnerabilities
- **Authorization Controls:** Multi-level access control with admin and emergency functions
- **Pause Mechanism:** Emergency stop functionality for critical situations
- **Token Contract Verification:** Ensures token traits match stored contract references

---

## ✨ Features

- **Multi-Collateral Support:** Deposit various SIP-010 tokens as collateral with individual risk profiles
- **Risk-Based Lending:** Each collateral type has its own LTV ratio, liquidation threshold, risk tier, and interest multiplier
- **Enhanced Loan Management:** Open, repay, boost, and liquidate loans with comprehensive validation
- **Robust Admin Controls:** Pause/unpause contract, set token contracts, configure collateral types with validation
- **Liquidation Tracking:** Records liquidation events for transparency and audit trails
- **Dynamic Yield Calculation:** Interest calculated based on collateral risk and time elapsed
- **Health Factor Monitoring:** Real-time loan health assessment and liquidation protection

---

## 🏗️ Smart Contract Overview

- **Language:** Clarity
- **Main Contract:** lendFi.clar
- **Traits Used:** SIP-010 fungible token trait (defined locally)
- **Security Level:** Enhanced with comprehensive input validation and bounds checking

---

## 📊 Key Data Structures

- `loans`: Stores loan details (owner, collateral, borrowed amount, status, collateral type, creation block)
- `collateral-types`: Stores parameters for each collateral token (LTV, risk tier, liquidation threshold, interest multiplier, enabled status)
- `liquidations`: Tracks liquidation events with detailed information

---

## 🔧 Main Functions

### Core Lending Functions

| Function                | Description                                                      | Security Features |
|-------------------------|------------------------------------------------------------------|-------------------|
| `open-loan`             | Deposit collateral and borrow tokens with validation            | Amount validation, contract verification, LTV checking |
| `liquidate-loan`        | Liquidate unhealthy loans and seize collateral                  | Health factor validation, partial liquidation support |
| `trigger-repayment`     | Repay loan when accrued yield meets borrowed amount             | Ownership verification, yield calculation validation |
| `boost-collateral`      | Add more collateral to an existing loan                         | Amount validation, contract matching verification |

### Admin Functions

| Function                | Description                                                      | Security Features |
|-------------------------|------------------------------------------------------------------|-------------------|
| `set-yield-token`       | Set the yield token contract                                     | Admin-only, contract address validation |
| `set-borrow-token`      | Set the borrow token contract                                    | Admin-only, contract address validation |
| `set-collateral-type`   | Configure collateral token parameters                            | Comprehensive parameter validation |
| `pause` / `unpause`     | Emergency pause/unpause contract operations                      | Admin-only access control |
| `withdraw-yield`        | Admin withdraws excess yield tokens                              | Amount validation, contract verification |

### View Functions

| Function                | Description                                                      |
|-------------------------|------------------------------------------------------------------|
| `get-loan`              | View loan details with error handling                            |
| `get-collateral-type`   | View collateral type parameters                                  |
| `get-liquidation`       | View liquidation event details                                   |
| `get-loan-health`       | View comprehensive health factor and liquidation status         |
| `view-accrued-yield`    | View accrued yield with risk-adjusted calculations              |
| `get-contract-info`     | View contract admin, status, and token references               |
| `calculate-health-factor`| Calculate loan health factor with precision                     |

---

## ⚠️ Error Codes

### Core Errors
- `ERR-UNAUTHORIZED` (u100): Unauthorized action
- `ERR-LOAN-NOT-FOUND` (u101): Loan not found
- `ERR-LOAN-ALREADY-REPAID` (u102): Loan already repaid
- `ERR-INSUFFICIENT-COLLATERAL` (u103): Not enough collateral
- `ERR-REPAYMENT-FAILED` (u104): Repayment failed

### Security & Validation Errors
- `ERR-INVALID-AMOUNT` (u888): Invalid amount (zero, negative, or overflow)
- `ERR-INVALID-PARAMETERS` (u110): Invalid function parameters
- `ERR-INVALID-CONTRACT` (u111): Invalid or malicious contract address
- `ERR-TRANSFER-FAILED` (u999): Token transfer failed

### System Errors
- `ERR-PAUSED` (u900): Contract is paused
- `ERR-TOKEN-NOT-SET` (u777): Token contract not set
- `ERR-COLLATERAL-TYPE-NOT-FOUND` (u105): Collateral type not found
- `ERR-COLLATERAL-TYPE-DISABLED` (u106): Collateral type disabled

### Liquidation Errors
- `ERR-LOAN-HEALTHY` (u107): Loan is healthy (not liquidatable)
- `ERR-LIQUIDATION-FAILED` (u108): Liquidation failed
- `ERR-INVALID-LIQUIDATION-AMOUNT` (u109): Invalid liquidation amount

---

## 🛡️ Security Parameters

### Validation Bounds
- **LTV Ratio:** 10% - 95% (MIN_LTV_RATIO to MAX_LTV_RATIO)
- **Liquidation Threshold:** 101% - 200% (MIN_LIQUIDATION_THRESHOLD to MAX_LIQUIDATION_THRESHOLD)
- **Risk Tier:** 1-5 (1 being safest)
- **Interest Multiplier:** 0.5x - 10x (MIN_INTEREST_MULTIPLIER to MAX_INTEREST_MULTIPLIER)
- **Amount Limits:** 1 - MAX_UINT128

### Risk Management
- **Liquidation Penalty:** 10% bonus for liquidators
- **Health Factor Precision:** 100 (for accurate calculations)
- **Minimum Deposit:** 100,000 units (prevents dust attacks)

---

## 🚀 Usage

### 1. Admin Setup
```clarity
;; Set token contracts (admin only)
(contract-call? .lendfi set-yield-token .yield-token)
(contract-call? .lendfi set-borrow-token .borrow-token)

;; Configure collateral types with validation
(contract-call? .lendfi set-collateral-type 
  .collateral-token  ;; token contract
  u8000             ;; 80% LTV ratio
  u12000            ;; 120% liquidation threshold
  u2                ;; risk tier 2
  true              ;; enabled
  u150)             ;; 1.5x interest multiplier
  2. User Actions
;; Open a loan with collateral
(contract-call? .lendfi open-loan 
  u1000000          ;; collateral amount
  u800000           ;; loan amount (respects LTV)
  .collateral-token ;; collateral token trait
  .borrow-token)    ;; borrow token trait

;; Boost collateral to improve health
(contract-call? .lendfi boost-collateral 
  u1               ;; loan ID
  u200000          ;; additional collateral
  .collateral-token)

;; Check loan health
(contract-call? .lendfi get-loan-health u1)

3. Liquidation
;; Liquidate unhealthy loans
(contract-call? .lendfi liquidate-loan 
  u1               ;; loan ID
  u100000          ;; liquidation amount
  .collateral-token
  .borrow-token)
  
🔍 Security Considerations
Input Validation
All user inputs are validated against predefined bounds
Contract addresses are verified to prevent malicious substitution
Amount limits prevent overflow/underflow attacks
Access Control
Admin functions are protected with authorization checks
Emergency pause functionality for critical situations
Token contract verification prevents unauthorized token swaps
Economic Security
LTV ratios must be less than liquidation thresholds
Risk-based interest rates align incentives
Liquidation penalties ensure protocol sustainability
📋 Requirements
Stacks blockchain
SIP-010 compliant token contracts
Proper admin setup and configuration
Adequate token balances for operations
🧪 Testing Recommendations
Input Validation Testing: Test boundary conditions and invalid inputs
Access Control Testing: Verify unauthorized access is prevented
Economic Testing: Test liquidation scenarios and edge cases
Integration Testing: Test with real SIP-010 token contracts
Security Auditing: Conduct thorough security review before mainnet deployment
📄 License
MIT License

⚠️ Disclaimer
This contract includes enhanced security features and comprehensive input validation. However, it is still for educational and experimental purposes. Always conduct thorough testing and security audits before deploying to mainnet. DeFi protocols carry inherent risks including smart contract vulnerabilities, economic attacks, and market volatility.
