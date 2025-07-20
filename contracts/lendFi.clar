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

(define-constant CONTRACT-OWNER tx-sender)
(define-constant minimum-deposit u100000) ;; Minimum deposit to open a loan
(define-constant interest-rate u10) ;; 10% interest (annualized abstract)
(define-constant LIQUIDATION-THRESHOLD u120) ;; 120% - if health factor below this, liquidation allowed
(define-constant LIQUIDATION-PENALTY u10) ;; 10% penalty for liquidation
(define-constant HEALTH-FACTOR-PRECISION u100) ;; For health factor calculations

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

;; Admin function to set token contracts
(define-public (set-yield-token (token-contract principal))
  (if (is-eq tx-sender (var-get admin))
    (begin
      (var-set yield-token-contract (some token-contract))
      (ok true)
    )
    (err ERR-UNAUTHORIZED)
  )
)

(define-public (set-borrow-token (token-contract principal))
  (if (is-eq tx-sender (var-get admin))
    (begin
      (var-set borrow-token-contract (some token-contract))
      (ok true)
    )
    (err ERR-UNAUTHORIZED)
  )
)

;; Admin function to add/update collateral types
(define-public (set-collateral-type 
  (token-contract principal)
  (ltv-ratio uint)
  (liquidation-threshold uint)
  (risk-tier uint)
  (enabled bool)
  (interest-multiplier uint))
  (if (is-eq tx-sender (var-get admin))
    (begin
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
    (err ERR-UNAUTHORIZED)
  )
)

;; Admin Controls
(define-public (pause)
  (if (is-eq tx-sender (var-get admin))
    (begin
      (var-set paused true)
      (ok true)
    )
    (err ERR-UNAUTHORIZED)
  )
)

(define-public (unpause)
  (if (is-eq tx-sender (var-get admin))
    (begin
      (var-set paused false)
      (ok true)
    )
    (err ERR-UNAUTHORIZED)
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
    ;; Verify the provided borrow token trait matches the stored contract
    (if (not (is-eq (contract-of borrow-token-trait) borrow-token))
      (err ERR-UNAUTHORIZED)
      ;; Check if collateral type is enabled
      (if (not (get enabled collateral-info))
        (err ERR-COLLATERAL-TYPE-DISABLED)
        (if (var-get paused)
          (err ERR-PAUSED)
          (if (< collateral minimum-deposit)
            (err ERR-INSUFFICIENT-COLLATERAL)
            ;; Check LTV ratio
            (let (
              (max-loan (/ (* collateral (get ltv-ratio collateral-info)) u100))
            )
              (if (> loan-amount max-loan)
                (err ERR-INSUFFICIENT-COLLATERAL)
                (begin
                  ;; Transfer collateral into contract
                  (match (contract-call? collateral-token-trait transfer collateral tx-sender (as-contract tx-sender) none)
                    success (if success
                      (begin
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
                      (err ERR-TRANSFER-FAILED)
                    )
                    error (err error)
                  )
                )
              )
            )
          )
        )
      )
    )
  )
)

;; Liquidation function
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
    ;; Verify token contracts match
    (if (not (is-eq (contract-of collateral-token-trait) (get collateral-type loan)))
      (err ERR-UNAUTHORIZED)
      (if (not (is-eq (contract-of borrow-token-trait) (try! (get-borrow-token-contract))))
        (err ERR-UNAUTHORIZED)
        ;; Check if loan is unhealthy (below liquidation threshold)
        (if (>= health-factor liquidation-threshold)
          (err ERR-LOAN-HEALTHY)
          (if (get repaid loan)
            (err ERR-LOAN-ALREADY-REPAID)
            (if (> liquidation-amount (get borrowed loan))
              (err ERR-INVALID-LIQUIDATION-AMOUNT)
              (let (
                ;; Calculate collateral to seize (with penalty)
                (collateral-to-seize (/ (* liquidation-amount (+ u100 LIQUIDATION-PENALTY)) u100))
                (remaining-collateral (- (get collateral loan) collateral-to-seize))
                (remaining-borrowed (- (get borrowed loan) liquidation-amount))
                (liquidation-id (var-get next-liquidation-id))
              )
                (if (> collateral-to-seize (get collateral loan))
                  (err ERR-LIQUIDATION-FAILED)
                  (begin
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
            )
          )
        )
      )
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

;; Enhanced yield calculation with risk-based interest
(define-public (trigger-repayment (lid uint) (borrow-token-trait <sip-010-trait>))
  (let (
    (borrow-token (try! (get-borrow-token-contract)))
    (loan (try! (get-loan lid)))
    (collateral-info (try! (get-collateral-type-info (get collateral-type loan))))
  )
    ;; Verify the provided trait matches the stored contract
    (if (not (is-eq (contract-of borrow-token-trait) borrow-token))
      (err ERR-UNAUTHORIZED)
      (if (not (is-eq (get owner loan) tx-sender))
        (err ERR-UNAUTHORIZED)
        (if (get repaid loan)
          (err ERR-LOAN-ALREADY-REPAID)
          (begin
            ;; Calculate yield with risk-based interest multiplier
            (let (
              (blocks (- stacks-block-height (get start-height loan)))
              (risk-adjusted-rate (/ (* interest-rate (get interest-multiplier collateral-info)) u100))
              (yield (/ (* (get collateral loan) risk-adjusted-rate blocks) u52560)) ;; assume 1 year = 52560 blocks
            )
              (if (>= yield (get borrowed loan))
                (begin
                  ;; Mark as repaid
                  (map-set loans 
                    { loan-id: lid }
                    {
                      owner: (get owner loan),
                      collateral: (get collateral loan),
                      borrowed: (get borrowed loan),
                      repaid: true,
                      start-height: (get start-height loan),
                      collateral-type: (get collateral-type loan)
                    }
                  )
                  (ok true)
                )
                (err ERR-REPAYMENT-FAILED)
              )
            )
          )
        )
      )
    )
  )
)

;; Admin can withdraw excess yield (if any)
(define-public (withdraw-yield (amount uint) (yield-token-trait <sip-010-trait>))
  (let (
    (yield-token (try! (get-yield-token-contract)))
  )
    ;; Verify the provided trait matches the stored contract
    (if (not (is-eq (contract-of yield-token-trait) yield-token))
      (err ERR-UNAUTHORIZED)
      (if (is-eq tx-sender (var-get admin))
        (as-contract (contract-call? yield-token-trait transfer amount (as-contract tx-sender) tx-sender none))
        (err ERR-UNAUTHORIZED)
      )
    )
  )
)

;; Enhanced boost collateral function
(define-public (boost-collateral (lid uint) (extra uint) (collateral-token-trait <sip-010-trait>))
  (let (
    (loan (try! (get-loan lid)))
  )
    ;; Verify the provided trait matches the loan's collateral type
    (if (not (is-eq (contract-of collateral-token-trait) (get collateral-type loan)))
      (err ERR-UNAUTHORIZED)
      (if (<= extra u0)
        (err ERR-INVALID-AMOUNT)
        (if (var-get paused)
          (err ERR-PAUSED)
          (if (not (is-eq (get owner loan) tx-sender))
            (err ERR-UNAUTHORIZED)
            (if (get repaid loan)
              (err ERR-LOAN-ALREADY-REPAID)
              (match (contract-call? collateral-token-trait transfer extra tx-sender (as-contract tx-sender) none)
                success (if success
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
                  (err ERR-TRANSFER-FAILED)
                )
                error (err error)
              )
            )
          )
        )
      )
    )
  )
)

;; Enhanced view accrued yield with risk adjustment
(define-read-only (view-accrued-yield (lid uint))
  (match (map-get? loans { loan-id: lid })
    loan
      (match (get-collateral-type-info (get collateral-type loan))
        collateral-info
          (let (
            (blocks (- stacks-block-height (get start-height loan)))
            (risk-adjusted-rate (/ (* interest-rate (get interest-multiplier collateral-info)) u100))
            (yield (/ (* (get collateral loan) risk-adjusted-rate blocks) u52560))
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