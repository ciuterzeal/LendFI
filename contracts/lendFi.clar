;; Title: LendFi - Multi-Collateral Lending Protocol
;; Description: A DeFi lending protocol supporting multiple collateral types with risk-based interest rates

;; Define the SIP-010 trait locally
(define-trait sip-010-trait
  (
    ;; Transfer tokens from one user to another
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))
    ;; Get token balance of user
    (get-balance (principal) (response uint uint))
    ;; Get total supply
    (get-total-supply () (response uint uint))
    ;; Get token name
    (get-name () (response (string-ascii 32) uint))
    ;; Get token symbol
    (get-symbol () (response (string-ascii 32) uint))
    ;; Get token decimals
    (get-decimals () (response uint uint))
    ;; Get token URI
    (get-token-uri () (response (optional (string-utf8 256)) uint))
  )
)

;; Constants and Errors
(define-constant ERR-UNAUTHORIZED u100)
(define-constant ERR-LOAN-NOT-FOUND u101)
(define-constant ERR-LOAN-ALREADY-REPAID u102)
(define-constant ERR-INSUFFICIENT-COLLATERAL u103)
(define-constant ERR-REPAYMENT-FAILED u104)
(define-constant ERR-PAUSED u900)
(define-constant ERR-INVALID-AMOUNT u888)
(define-constant ERR-TRANSFER-FAILED u999)
(define-constant ERR-TOKEN-NOT-SET u777)
(define-constant ERR-COLLATERAL-TYPE-NOT-FOUND u105)
(define-constant ERR-COLLATERAL-TYPE-DISABLED u106)
(define-constant ERR-LOAN-HEALTHY u107)
(define-constant ERR-LIQUIDATION-FAILED u108)
(define-constant ERR-INVALID-LIQUIDATION-AMOUNT u109)
(define-constant ERR-INVALID-PARAMETERS u110)
(define-constant ERR-INVALID-CONTRACT u111)

(define-constant CONTRACT-OWNER tx-sender)
(define-constant minimum-deposit u100000) ;; Minimum deposit to open a loan
(define-constant interest-rate u10) ;; 10% interest (annualized abstract)
(define-constant LIQUIDATION-THRESHOLD u120) ;; 120% - if health factor below this, liquidation allowed
(define-constant LIQUIDATION-PENALTY u10) ;; 10% penalty for liquidation
(define-constant HEALTH-FACTOR-PRECISION u100) ;; For health factor calculations

;; Validation constants
(define-constant MAX-LTV-RATIO u9500) ;; 95% max LTV
(define-constant MIN-LTV-RATIO u1000) ;; 10% min LTV
(define-constant MAX-LIQUIDATION-THRESHOLD u20000) ;; 200% max threshold
(define-constant MIN-LIQUIDATION-THRESHOLD u10100) ;; 101% min threshold
(define-constant MAX-RISK-TIER u5)
(define-constant MIN-RISK-TIER u1)
(define-constant MAX-INTEREST-MULTIPLIER u1000) ;; 10x max multiplier
(define-constant MIN-INTEREST-MULTIPLIER u50) ;; 0.5x min multiplier
(define-constant MAX-AMOUNT u340282366920938463463374607431768211455) ;; Max uint128

;; Input validation functions
(define-private (validate-amount (amount uint))
  (and (> amount u0) (<= amount MAX-AMOUNT))
)

(define-private (validate-principal (addr principal))
  (not (is-eq addr 'SP000000000000000000002Q6VF78))
)

(define-private (validate-ltv-ratio (ltv uint))
  (and (>= ltv MIN-LTV-RATIO) (<= ltv MAX-LTV-RATIO))
)

(define-private (validate-liquidation-threshold (threshold uint))
  (and (>= threshold MIN-LIQUIDATION-THRESHOLD) (<= threshold MAX-LIQUIDATION-THRESHOLD))
)

(define-private (validate-risk-tier (tier uint))
  (and (>= tier MIN-RISK-TIER) (<= tier MAX-RISK-TIER))
)

(define-private (validate-interest-multiplier (multiplier uint))
  (and (>= multiplier MIN-INTEREST-MULTIPLIER) (<= multiplier MAX-INTEREST-MULTIPLIER))
)

(define-private (validate-collateral-params (ltv uint) (threshold uint) (tier uint) (multiplier uint))
  (and 
    (validate-ltv-ratio ltv)
    (validate-liquidation-threshold threshold)
    (validate-risk-tier tier)
    (validate-interest-multiplier multiplier)
    (< ltv threshold) ;; LTV must be less than liquidation threshold
  )
)

;; Enhanced loan structure with collateral type
(define-map loans
  { loan-id: uint }
  {
    owner: principal,
    collateral: uint,
    borrowed: uint,
    repaid: bool,
    start-height: uint,
    collateral-type: principal ;; New field for collateral token contract
  }
)

;; Multi-collateral support with risk tiers
(define-map collateral-types
  { token-contract: principal }
  {
    ltv-ratio: uint,           ;; Loan-to-value ratio (e.g., 80 = 80%)
    liquidation-threshold: uint, ;; Threshold for liquidation (e.g., 120 = 120%)
    risk-tier: uint,           ;; Risk tier (1-5, 1 being safest)
    enabled: bool,             ;; Whether this collateral type is enabled
    interest-multiplier: uint   ;; Interest rate multiplier based on risk (100 = 1x)
  }
)

;; Liquidation tracking
(define-map liquidations
  { liquidation-id: uint }
  {
    loan-id: uint,
    liquidator: principal,
    liquidated-amount: uint,
    collateral-seized: uint,
    timestamp: uint
  }
)

(define-data-var next-loan-id uint u1)
(define-data-var next-liquidation-id uint u1)
(define-data-var admin principal tx-sender)
(define-data-var paused bool false)

;; Token contract references (to be set by admin)
(define-data-var yield-token-contract (optional principal) none)
(define-data-var borrow-token-contract (optional principal) none)

;; Admin function to set token contracts with validation
(define-public (set-yield-token (token-contract principal))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err ERR-UNAUTHORIZED))
    (asserts! (validate-principal token-contract) (err ERR-INVALID-CONTRACT))
    (var-set yield-token-contract (some token-contract))
    (ok true)
  )
)

(define-public (set-borrow-token (token-contract principal))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err ERR-UNAUTHORIZED))
    (asserts! (validate-principal token-contract) (err ERR-INVALID-CONTRACT))
    (var-set borrow-token-contract (some token-contract))
    (ok true)
  )
)

;; Admin function to add/update collateral types with validation
(define-public (set-collateral-type 
  (token-contract principal)
  (ltv-ratio uint)
  (liquidation-threshold uint)
  (risk-tier uint)
  (enabled bool)
  (interest-multiplier uint))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err ERR-UNAUTHORIZED))
    (asserts! (validate-principal token-contract) (err ERR-INVALID-CONTRACT))
    (asserts! (validate-collateral-params ltv-ratio liquidation-threshold risk-tier interest-multiplier) (err ERR-INVALID-PARAMETERS))
    (map-set collateral-types
      { token-contract: token-contract }
      {
        ltv-ratio: ltv-ratio,
        liquidation-threshold: liquidation-threshold,
        risk-tier: risk-tier,
        enabled: enabled,
        interest-multiplier: interest-multiplier
      }
    )
    (ok true)
  )
)

;; Admin Controls
(define-public (pause)
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err ERR-UNAUTHORIZED))
    (var-set paused true)
    (ok true)
  )
)

(define-public (unpause)
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err ERR-UNAUTHORIZED))
    (var-set paused false)
    (ok true)
  )
)

;; Helper function to get yield token contract - returns response type
(define-private (get-yield-token-contract)
  (match (var-get yield-token-contract)
    token-contract (ok token-contract)
    (err ERR-TOKEN-NOT-SET)
  )
)

;; Helper function to get borrow token contract - returns response type
(define-private (get-borrow-token-contract)
  (match (var-get borrow-token-contract)
    token-contract (ok token-contract)
    (err ERR-TOKEN-NOT-SET)
  )
)

;; Helper function to get collateral type info
(define-private (get-collateral-type-info (token-contract principal))
  (match (map-get? collateral-types { token-contract: token-contract })
    collateral-info (ok collateral-info)
    (err ERR-COLLATERAL-TYPE-NOT-FOUND)
  )
)

;; Calculate health factor for a loan (collateral-value / borrowed-value * 100)
(define-read-only (calculate-health-factor (lid uint))
  (match (map-get? loans { loan-id: lid })
    loan
      (let (
        (collateral-type-info (unwrap! (get-collateral-type-info (get collateral-type loan)) (err ERR-COLLATERAL-TYPE-NOT-FOUND)))
        (collateral-value (get collateral loan))
        (borrowed-value (get borrowed loan))
      )
        (if (is-eq borrowed-value u0)
          (ok u999999) ;; Very high health factor if no debt
          (ok (/ (* collateral-value HEALTH-FACTOR-PRECISION) borrowed-value))
        )
      )
    (err ERR-LOAN-NOT-FOUND)
  )
)

;; Enhanced borrower deposits collateral and receives loan with multi-collateral support
(define-public (open-loan (collateral uint) (loan-amount uint) (collateral-token-trait <sip-010-trait>) (borrow-token-trait <sip-010-trait>))
  (let (
    (borrow-token (try! (get-borrow-token-contract)))
    (collateral-token-contract (contract-of collateral-token-trait))
    (collateral-info (try! (get-collateral-type-info collateral-token-contract)))
  )
    ;; Input validation
    (asserts! (validate-amount collateral) (err ERR-INVALID-AMOUNT))
    (asserts! (validate-amount loan-amount) (err ERR-INVALID-AMOUNT))
    (asserts! (validate-principal collateral-token-contract) (err ERR-INVALID-CONTRACT))
    (asserts! (validate-principal borrow-token) (err ERR-INVALID-CONTRACT))
    
    ;; Verify the provided borrow token trait matches the stored contract
    (asserts! (is-eq (contract-of borrow-token-trait) borrow-token) (err ERR-UNAUTHORIZED))
    ;; Check if collateral type is enabled
    (asserts! (get enabled collateral-info) (err ERR-COLLATERAL-TYPE-DISABLED))
    (asserts! (not (var-get paused)) (err ERR-PAUSED))
    (asserts! (>= collateral minimum-deposit) (err ERR-INSUFFICIENT-COLLATERAL))
    
    ;; Check LTV ratio
    (let (
      (max-loan (/ (* collateral (get ltv-ratio collateral-info)) u100))
    )
      (asserts! (<= loan-amount max-loan) (err ERR-INSUFFICIENT-COLLATERAL))
      
      ;; Transfer collateral into contract
      (try! (contract-call? collateral-token-trait transfer collateral tx-sender (as-contract tx-sender) none))
      
      ;; Transfer borrowed tokens to user
      (try! (as-contract (contract-call? borrow-token-trait transfer loan-amount (as-contract tx-sender) tx-sender none)))
      
      ;; Store loan with collateral type
      (let ((lid (var-get next-loan-id)))
        (map-set loans
          { loan-id: lid }
          {
            owner: tx-sender,
            collateral: collateral,
            borrowed: loan-amount,
            repaid: false,
            start-height: stacks-block-height,
            collateral-type: collateral-token-contract
          }
        )
        (var-set next-loan-id (+ lid u1))
        (ok lid)
      )
    )
  )
)

;; Liquidation function with validation
(define-public (liquidate-loan 
  (lid uint) 
  (liquidation-amount uint)
  (collateral-token-trait <sip-010-trait>)
  (borrow-token-trait <sip-010-trait>))
  (let (
    (loan (try! (get-loan lid)))
    (health-factor (try! (calculate-health-factor lid)))
    (collateral-info (try! (get-collateral-type-info (get collateral-type loan))))
    (liquidation-threshold (get liquidation-threshold collateral-info))
  )
    ;; Input validation
    (asserts! (validate-amount liquidation-amount) (err ERR-INVALID-AMOUNT))
    (asserts! (validate-principal (contract-of collateral-token-trait)) (err ERR-INVALID-CONTRACT))
    (asserts! (validate-principal (contract-of borrow-token-trait)) (err ERR-INVALID-CONTRACT))
    
    ;; Verify token contracts match
    (asserts! (is-eq (contract-of collateral-token-trait) (get collateral-type loan)) (err ERR-UNAUTHORIZED))
    (asserts! (is-eq (contract-of borrow-token-trait) (try! (get-borrow-token-contract))) (err ERR-UNAUTHORIZED))
    ;; Check if loan is unhealthy (below liquidation threshold)
    (asserts! (< health-factor liquidation-threshold) (err ERR-LOAN-HEALTHY))
    (asserts! (not (get repaid loan)) (err ERR-LOAN-ALREADY-REPAID))
    (asserts! (<= liquidation-amount (get borrowed loan)) (err ERR-INVALID-LIQUIDATION-AMOUNT))
    
    (let (
      ;; Calculate collateral to seize (with penalty)
      (collateral-to-seize (/ (* liquidation-amount (+ u100 LIQUIDATION-PENALTY)) u100))
      (remaining-collateral (- (get collateral loan) collateral-to-seize))
      (remaining-borrowed (- (get borrowed loan) liquidation-amount))
      (liquidation-id (var-get next-liquidation-id))
    )
      (asserts! (<= collateral-to-seize (get collateral loan)) (err ERR-LIQUIDATION-FAILED))
      
      ;; Liquidator must provide repayment tokens
      (try! (contract-call? borrow-token-trait transfer liquidation-amount tx-sender (as-contract tx-sender) none))
      
      ;; Transfer collateral to liquidator
      (try! (as-contract (contract-call? collateral-token-trait transfer collateral-to-seize (as-contract tx-sender) tx-sender none)))
      
      ;; Update loan
      (map-set loans
        { loan-id: lid }
        {
          owner: (get owner loan),
          collateral: remaining-collateral,
          borrowed: remaining-borrowed,
          repaid: (is-eq remaining-borrowed u0),
          start-height: (get start-height loan),
          collateral-type: (get collateral-type loan)
        }
      )
      
      ;; Record liquidation
      (map-set liquidations
        { liquidation-id: liquidation-id }
        {
          loan-id: lid,
          liquidator: tx-sender,
          liquidated-amount: liquidation-amount,
          collateral-seized: collateral-to-seize,
          timestamp: stacks-block-height
        }
      )
      
      (var-set next-liquidation-id (+ liquidation-id u1))
      (ok liquidation-id)
    )
  )
)

;; View loan info
(define-read-only (get-loan (lid uint))
  (match (map-get? loans { loan-id: lid })
    loan (ok loan)
    (err ERR-LOAN-NOT-FOUND)
  )
)

;; View collateral type info
(define-read-only (get-collateral-type (token-contract principal))
  (match (map-get? collateral-types { token-contract: token-contract })
    collateral-info (ok collateral-info)
    (err ERR-COLLATERAL-TYPE-NOT-FOUND)
  )
)

;; View liquidation info
(define-read-only (get-liquidation (liquidation-id uint))
  (map-get? liquidations { liquidation-id: liquidation-id })
)

;; Calculate total repayment amount (principal + interest)
(define-read-only (calculate-repayment-amount (lid uint))
  (match (map-get? loans { loan-id: lid })
    loan
      (match (get-collateral-type-info (get collateral-type loan))
        collateral-info
          (let (
            (blocks (- stacks-block-height (get start-height loan)))
            (risk-adjusted-rate (/ (* interest-rate (get interest-multiplier collateral-info)) u100))
            (interest (/ (* (get borrowed loan) risk-adjusted-rate blocks) u52560))
            (total-repayment (+ (get borrowed loan) interest))
          )
            (ok total-repayment)
          )
        error (err error)
      )
    (err ERR-LOAN-NOT-FOUND)
  )
)

;; Proper loan repayment function with full settlement requirement
(define-public (trigger-repayment (lid uint) (repayment-amount uint) (borrow-token-trait <sip-010-trait>) (collateral-token-trait <sip-010-trait>))
  (let (
    (borrow-token (try! (get-borrow-token-contract)))
    (loan (try! (get-loan lid)))
    (collateral-info (try! (get-collateral-type-info (get collateral-type loan))))
    (collateral-token-contract (contract-of collateral-token-trait))
  )
    ;; Input validation
    (asserts! (validate-amount repayment-amount) (err ERR-INVALID-AMOUNT))
    (asserts! (validate-principal (contract-of borrow-token-trait)) (err ERR-INVALID-CONTRACT))
    (asserts! (validate-principal collateral-token-contract) (err ERR-INVALID-CONTRACT))
    
    ;; Verify provided traits match stored contracts
    (asserts! (is-eq (contract-of borrow-token-trait) borrow-token) (err ERR-UNAUTHORIZED))
    (asserts! (is-eq (contract-of collateral-token-trait) (get collateral-type loan)) (err ERR-UNAUTHORIZED))
    
    ;; Only owner can repay
    (asserts! (is-eq (get owner loan) tx-sender) (err ERR-UNAUTHORIZED))
    (asserts! (not (get repaid loan)) (err ERR-LOAN-ALREADY-REPAID))
    
    ;; Pull repayment tokens from borrower into this contract.
    ;; Caller must pass a borrow-token trait bound to their principal so the transfer can be executed.
    (try! (contract-call? borrow-token-trait transfer repayment-amount tx-sender (as-contract tx-sender) none))
    
    ;; Calculate accrued interest - FIXED: now uses borrowed amount instead of collateral
    (let (
      (blocks (- stacks-block-height (get start-height loan)))
      (risk-adjusted-rate (/ (* interest-rate (get interest-multiplier collateral-info)) u100))
      (accrued (/ (* (get borrowed loan) risk-adjusted-rate blocks) u52560))  ;; FIXED: changed from collateral to borrowed
      (total-due (+ (get borrowed loan) accrued))
    )
      ;; Require full settlement for now
      (asserts! (>= repayment-amount total-due) (err ERR-REPAYMENT-FAILED))
      
      ;; Determine any overpayment (kept in contract as protocol funds); principal cleared
      (let (
        (remaining-coll (get collateral loan))
        (lid-owner (get owner loan))
      )
        ;; Mark loan repaid and clear borrowed/collateral
        (map-set loans
          { loan-id: lid }
          {
            owner: lid-owner,
            collateral: u0,
            borrowed: u0,
            repaid: true,
            start-height: (get start-height loan),
            collateral-type: (get collateral-type loan)
          }
        )
        
        ;; Return collateral to borrower
        ;; Transfer collateral tokens from contract back to borrower
        (try! (as-contract (contract-call? collateral-token-trait transfer remaining-coll (as-contract tx-sender) tx-sender none)))
        
        ;; success
        (ok true)
      )
    )
  )
)


;; Admin can withdraw excess yield (if any)
(define-public (withdraw-yield (amount uint) (yield-token-trait <sip-010-trait>))
  (let (
    (yield-token (try! (get-yield-token-contract)))
  )
    ;; Input validation
    (asserts! (validate-amount amount) (err ERR-INVALID-AMOUNT))
    (asserts! (validate-principal (contract-of yield-token-trait)) (err ERR-INVALID-CONTRACT))
    
    ;; Verify the provided trait matches the stored contract
    (asserts! (is-eq (contract-of yield-token-trait) yield-token) (err ERR-UNAUTHORIZED))
    (asserts! (is-eq tx-sender (var-get admin)) (err ERR-UNAUTHORIZED))
    (as-contract (contract-call? yield-token-trait transfer amount (as-contract tx-sender) tx-sender none))
  )
)

;; Enhanced boost collateral function
(define-public (boost-collateral (lid uint) (extra uint) (collateral-token-trait <sip-010-trait>))
  (let (
    (loan (try! (get-loan lid)))
  )
    ;; Input validation
    (asserts! (validate-amount extra) (err ERR-INVALID-AMOUNT))
    (asserts! (validate-principal (contract-of collateral-token-trait)) (err ERR-INVALID-CONTRACT))
    
    ;; Verify the provided trait matches the loan's collateral type
    (asserts! (is-eq (contract-of collateral-token-trait) (get collateral-type loan)) (err ERR-UNAUTHORIZED))
    (asserts! (not (var-get paused)) (err ERR-PAUSED))
    (asserts! (is-eq (get owner loan) tx-sender) (err ERR-UNAUTHORIZED))
    (asserts! (not (get repaid loan)) (err ERR-LOAN-ALREADY-REPAID))
    
    (try! (contract-call? collateral-token-trait transfer extra tx-sender (as-contract tx-sender) none))
    (let ((new-col (+ (get collateral loan) extra)))
      (map-set loans 
        { loan-id: lid }
        {
          owner: (get owner loan),
          collateral: new-col,
          borrowed: (get borrowed loan),
          repaid: false,
          start-height: (get start-height loan),
          collateral-type: (get collateral-type loan)
        }
      )
      (ok new-col)
    )
  )
)

;; Enhanced view accrued yield with risk adjustment - FIXED: now uses borrowed amount
(define-read-only (view-accrued-yield (lid uint))
  (match (map-get? loans { loan-id: lid })
    loan
      (match (get-collateral-type-info (get collateral-type loan))
        collateral-info
          (let (
            (blocks (- stacks-block-height (get start-height loan)))
            (risk-adjusted-rate (/ (* interest-rate (get interest-multiplier collateral-info)) u100))
            (yield (/ (* (get borrowed loan) risk-adjusted-rate blocks) u52560))  ;; FIXED: changed from collateral to borrowed
          )
            (ok yield)
          )
        error (err error)
      )
    (err ERR-LOAN-NOT-FOUND)
  )
)

;; Get contract info
(define-read-only (get-contract-info)
  (ok {
    admin: (var-get admin),
    paused: (var-get paused),
    next-loan-id: (var-get next-loan-id),
    next-liquidation-id: (var-get next-liquidation-id),
    yield-token: (var-get yield-token-contract),
    borrow-token: (var-get borrow-token-contract)
  })
)

;; Get loan health status
(define-read-only (get-loan-health (lid uint))
  (match (calculate-health-factor lid)
    health-factor 
      (let (
        (loan (unwrap! (get-loan lid) (err ERR-LOAN-NOT-FOUND)))
        (collateral-info (unwrap! (get-collateral-type-info (get collateral-type loan)) (err ERR-COLLATERAL-TYPE-NOT-FOUND)))
      )
        (ok {
          health-factor: health-factor,
          liquidation-threshold: (get liquidation-threshold collateral-info),
          is-liquidatable: (< health-factor (get liquidation-threshold collateral-info)),
          collateral-type: (get collateral-type loan)
        })
      )
    error (err error)
  )
)
