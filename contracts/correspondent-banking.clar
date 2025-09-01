;; Cross-Border Correspondent Banking Smart Contract
;; A comprehensive platform for managing correspondent banking relationships,
;; processing cross-border transactions, and ensuring regulatory compliance

;; ===========================================
;; CONSTANTS
;; ===========================================

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-BANK-NOT-FOUND (err u101))
(define-constant ERR-RELATIONSHIP-EXISTS (err u102))
(define-constant ERR-INVALID-STATUS (err u103))
(define-constant ERR-INSUFFICIENT-FUNDS (err u104))
(define-constant ERR-TRANSACTION-NOT-FOUND (err u105))
(define-constant ERR-INVALID-AMOUNT (err u106))
(define-constant ERR-RISK-LIMIT-EXCEEDED (err u107))
(define-constant ERR-COMPLIANCE-VIOLATION (err u108))
(define-constant ERR-INVALID-CURRENCY (err u109))
(define-constant ERR-RELATIONSHIP-SUSPENDED (err u110))
(define-constant ERR-DUPLICATE-TRANSACTION (err u111))

;; Relationship statuses
(define-constant STATUS-PENDING u0)
(define-constant STATUS-ACTIVE u1)
(define-constant STATUS-SUSPENDED u2)
(define-constant STATUS-TERMINATED u3)

;; Transaction statuses
(define-constant TX-STATUS-PENDING u0)
(define-constant TX-STATUS-APPROVED u1)
(define-constant TX-STATUS-SETTLED u2)
(define-constant TX-STATUS-REJECTED u3)

;; Risk levels
(define-constant RISK-LOW u1)
(define-constant RISK-MEDIUM u2)
(define-constant RISK-HIGH u3)
(define-constant RISK-CRITICAL u4)

;; Fee basis points (1% = 100 basis points)
(define-constant BASE-FEE-BPS u50)
(define-constant RISK-MULTIPLIER u25)

;; Maximum limits
(define-constant MAX-TRANSACTION-AMOUNT u1000000000000) ;; 1M STX
(define-constant MAX-RISK-SCORE u100)
(define-constant MIN-RELATIONSHIP-DURATION u86400) ;; 1 day in seconds

;; ===========================================
;; DATA VARIABLES
;; ===========================================

;; Contract administrator
(define-data-var contract-owner principal tx-sender)

;; Global counters
(define-data-var next-bank-id uint u1)
(define-data-var next-transaction-id uint u1)
(define-data-var total-volume uint u0)
(define-data-var total-fees-collected uint u0)

;; Global platform settings
(define-data-var platform-active bool true)
(define-data-var minimum-risk-score uint u0)
(define-data-var maximum-daily-volume uint u100000000000) ;; 100K STX

;; ===========================================
;; DATA MAPS
;; ===========================================

;; Correspondent bank registry
(define-map correspondent-banks
  { bank-id: uint }
  {
    owner: principal,
    name: (string-ascii 64),
    country-code: (string-ascii 3),
    swift-code: (string-ascii 11),
    license-number: (string-ascii 32),
    status: uint,
    risk-score: uint,
    onboarded-at: uint,
    last-updated: uint,
    compliance-tier: uint,
    total-volume: uint,
    active-transactions: uint
  }
)

;; Bank authorization mapping
(define-map bank-principals
  { principal-addr: principal }
  { bank-id: uint }
)

;; KYC/Due diligence records
(define-map due-diligence-records
  { bank-id: uint }
  {
    kyc-status: uint,
    aml-check-date: uint,
    risk-assessment-date: uint,
    regulatory-approval: bool,
    sanctions-check: bool,
    financial-health-score: uint,
    audit-date: uint,
    compliance-officer: principal,
    next-review-date: uint
  }
)

;; Cross-border transactions
(define-map transactions
  { transaction-id: uint }
  {
    from-bank-id: uint,
    to-bank-id: uint,
    amount: uint,
    currency: (string-ascii 3),
    reference: (string-ascii 64),
    initiated-by: principal,
    initiated-at: uint,
    status: uint,
    approved-by: (optional principal),
    approved-at: (optional uint),
    settled-at: (optional uint),
    fee-amount: uint,
    risk-score: uint,
    compliance-checked: bool
  }
)

;; Fee structure per relationship
(define-map fee-structures
  { from-bank-id: uint, to-bank-id: uint }
  {
    base-fee-bps: uint,
    currency-fee-bps: uint,
    risk-adjustment-bps: uint,
    volume-discount-tier: uint,
    revenue-share-pct: uint,
    last-updated: uint
  }
)

;; Risk monitoring
(define-map risk-profiles
  { bank-id: uint }
  {
    credit-rating: uint,
    exposure-limit: uint,
    current-exposure: uint,
    default-probability: uint,
    concentration-risk: uint,
    country-risk: uint,
    operational-risk: uint,
    last-assessment: uint
  }
)

;; Compliance events log
(define-map compliance-events
  { event-id: uint }
  {
    bank-id: uint,
    event-type: (string-ascii 32),
    description: (string-ascii 128),
    severity: uint,
    reported-by: principal,
    reported-at: uint,
    resolved: bool,
    resolution-date: (optional uint)
  }
)

;; Daily volume tracking
(define-map daily-volumes
  { date: uint, bank-id: uint }
  { volume: uint, transaction-count: uint }
)

;; ===========================================
;; PRIVATE FUNCTIONS
;; ===========================================

;; Calculate fees based on amount, risk, and relationship
(define-private (calculate-transaction-fee (amount uint) (from-bank uint) (to-bank uint))
  (let (
    (base-fee (/ (* amount BASE-FEE-BPS) u10000))
    (risk-adjustment (default-to u0 (get risk-score (map-get? correspondent-banks { bank-id: to-bank }))))
    (additional-risk-fee (/ (* base-fee (* risk-adjustment RISK-MULTIPLIER)) u100))
  )
    (+ base-fee additional-risk-fee)
  )
)

;; Validate bank authorization
(define-private (is-authorized-bank (sender principal) (bank-id uint))
  (match (map-get? bank-principals { principal-addr: sender })
    bank-record (is-eq (get bank-id bank-record) bank-id)
    false
  )
)

;; Check if relationship is active
(define-private (is-relationship-active (bank-id uint))
  (match (map-get? correspondent-banks { bank-id: bank-id })
    bank-record (is-eq (get status bank-record) STATUS-ACTIVE)
    false
  )
)

;; Validate transaction limits
(define-private (check-transaction-limits (from-bank uint) (amount uint))
  (let (
    (bank-record (unwrap! (map-get? correspondent-banks { bank-id: from-bank }) false))
    (risk-record (map-get? risk-profiles { bank-id: from-bank }))
  )
    (and 
      (<= amount MAX-TRANSACTION-AMOUNT)
      (match risk-record
        profile (<= (+ (get current-exposure profile) amount) (get exposure-limit profile))
        true
      )
    )
  )
)

;; Update risk exposure
(define-private (update-risk-exposure (bank-id uint) (amount uint) (increase bool))
  (match (map-get? risk-profiles { bank-id: bank-id })
    current-profile
    (let (
      (new-exposure (if increase 
                      (+ (get current-exposure current-profile) amount)
                      (- (get current-exposure current-profile) amount)))
    )
      (map-set risk-profiles
        { bank-id: bank-id }
        (merge current-profile { current-exposure: new-exposure })
      )
      true
    )
    false
  )
)

;; ===========================================
;; READ-ONLY FUNCTIONS
;; ===========================================

;; Get bank details
(define-read-only (get-bank-details (bank-id uint))
  (map-get? correspondent-banks { bank-id: bank-id })
)

;; Get transaction details
(define-read-only (get-transaction-details (transaction-id uint))
  (map-get? transactions { transaction-id: transaction-id })
)

;; Get bank's risk profile
(define-read-only (get-risk-profile (bank-id uint))
  (map-get? risk-profiles { bank-id: bank-id })
)

;; Get due diligence status
(define-read-only (get-due-diligence-status (bank-id uint))
  (map-get? due-diligence-records { bank-id: bank-id })
)

;; Calculate fees for a potential transaction
(define-read-only (preview-transaction-fees (amount uint) (from-bank uint) (to-bank uint))
  (ok (calculate-transaction-fee amount from-bank to-bank))
)

;; Get bank's current exposure
(define-read-only (get-bank-exposure (bank-id uint))
  (match (map-get? risk-profiles { bank-id: bank-id })
    profile (ok {
      current: (get current-exposure profile),
      limit: (get exposure-limit profile),
      utilization: (/ (* (get current-exposure profile) u100) (get exposure-limit profile))
    })
    ERR-BANK-NOT-FOUND
  )
)

;; Check if banks can transact
(define-read-only (can-transact (from-bank uint) (to-bank uint) (amount uint))
  (and 
    (is-relationship-active from-bank)
    (is-relationship-active to-bank)
    (check-transaction-limits from-bank amount)
  )
)

;; ===========================================
;; ADMINISTRATIVE FUNCTIONS
;; ===========================================

;; Transfer contract ownership
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)
  )
)

;; Update platform settings
(define-public (update-platform-settings (active bool) (min-risk uint) (max-daily uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set platform-active active)
    (var-set minimum-risk-score min-risk)
    (var-set maximum-daily-volume max-daily)
    (ok true)
  )
)

;; ===========================================
;; RELATIONSHIP MANAGEMENT
;; ===========================================

;; Onboard new correspondent bank
(define-public (onboard-correspondent (name (string-ascii 64)) (country (string-ascii 3)) 
                                    (swift (string-ascii 11)) (license (string-ascii 32))
                                    (compliance-tier uint))
  (let (
    (bank-id (var-get next-bank-id))
    (current-time (unwrap! (get-block-info? time (- block-height u1)) (err u999)))
  )
    (asserts! (var-get platform-active) (err u112))
    (asserts! (is-none (map-get? bank-principals { principal-addr: tx-sender })) ERR-RELATIONSHIP-EXISTS)
    (asserts! (<= compliance-tier u5) ERR-INVALID-STATUS)
    
    ;; Create bank record
    (map-set correspondent-banks
      { bank-id: bank-id }
      {
        owner: tx-sender,
        name: name,
        country-code: country,
        swift-code: swift,
        license-number: license,
        status: STATUS-PENDING,
        risk-score: u50, ;; Default medium risk
        onboarded-at: current-time,
        last-updated: current-time,
        compliance-tier: compliance-tier,
        total-volume: u0,
        active-transactions: u0
      }
    )
    
    ;; Map principal to bank ID
    (map-set bank-principals
      { principal-addr: tx-sender }
      { bank-id: bank-id }
    )
    
    ;; Initialize risk profile
    (map-set risk-profiles
      { bank-id: bank-id }
      {
        credit-rating: u50,
        exposure-limit: u10000000000, ;; 10K STX default
        current-exposure: u0,
        default-probability: u5,
        concentration-risk: u10,
        country-risk: u20,
        operational-risk: u15,
        last-assessment: current-time
      }
    )
    
    ;; Initialize due diligence record
    (map-set due-diligence-records
      { bank-id: bank-id }
      {
        kyc-status: u0, ;; Pending
        aml-check-date: current-time,
        risk-assessment-date: current-time,
        regulatory-approval: false,
        sanctions-check: false,
        financial-health-score: u50,
        audit-date: u0,
        compliance-officer: tx-sender,
        next-review-date: (+ current-time u7776000) ;; 90 days
      }
    )
    
    ;; Increment bank counter
    (var-set next-bank-id (+ bank-id u1))
    
    (print {
      event: "bank-onboarded",
      bank-id: bank-id,
      name: name,
      swift: swift,
      onboarded-by: tx-sender
    })
    
    (ok bank-id)
  )
)

;; Update due diligence information
(define-public (update-due-diligence (bank-id uint) (kyc-status uint) (sanctions-clear bool) 
                                   (financial-score uint))
  (let (
    (current-time (unwrap! (get-block-info? time (- block-height u1)) (err u999)))
    (bank-record (unwrap! (map-get? correspondent-banks { bank-id: bank-id }) ERR-BANK-NOT-FOUND))
  )
    (asserts! (or (is-eq tx-sender (var-get contract-owner))
                 (is-authorized-bank tx-sender bank-id)) ERR-NOT-AUTHORIZED)
    (asserts! (<= kyc-status u3) ERR-INVALID-STATUS)
    (asserts! (<= financial-score u100) (err u113))
    
    ;; Update due diligence record
    (map-set due-diligence-records
      { bank-id: bank-id }
      (merge (unwrap! (map-get? due-diligence-records { bank-id: bank-id }) ERR-BANK-NOT-FOUND)
        {
          kyc-status: kyc-status,
          aml-check-date: current-time,
          sanctions-check: sanctions-clear,
          financial-health-score: financial-score,
          next-review-date: (+ current-time u7776000)
        }
      )
    )
    
    ;; Update bank's last updated timestamp
    (map-set correspondent-banks
      { bank-id: bank-id }
      (merge bank-record { last-updated: current-time })
    )
    
    (print {
      event: "due-diligence-updated",
      bank-id: bank-id,
      kyc-status: kyc-status,
      updated-by: tx-sender
    })
    
    (ok true)
  )
)

;; Approve bank relationship (admin only)
(define-public (approve-relationship (bank-id uint))
  (let (
    (bank-record (unwrap! (map-get? correspondent-banks { bank-id: bank-id }) ERR-BANK-NOT-FOUND))
    (current-time (unwrap! (get-block-info? time (- block-height u1)) (err u999)))
  )
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status bank-record) STATUS-PENDING) ERR-INVALID-STATUS)
    
    (map-set correspondent-banks
      { bank-id: bank-id }
      (merge bank-record { 
        status: STATUS-ACTIVE,
        last-updated: current-time 
      })
    )
    
    (print {
      event: "relationship-approved",
      bank-id: bank-id,
      approved-by: tx-sender
    })
    
    (ok true)
  )
)

;; Suspend bank relationship
(define-public (suspend-relationship (bank-id uint) (reason (string-ascii 128)))
  (let (
    (bank-record (unwrap! (map-get? correspondent-banks { bank-id: bank-id }) ERR-BANK-NOT-FOUND))
    (current-time (unwrap! (get-block-info? time (- block-height u1)) (err u999)))
  )
    (asserts! (or (is-eq tx-sender (var-get contract-owner))
                 (is-authorized-bank tx-sender bank-id)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status bank-record) STATUS-ACTIVE) ERR-INVALID-STATUS)
    
    (map-set correspondent-banks
      { bank-id: bank-id }
      (merge bank-record { 
        status: STATUS-SUSPENDED,
        last-updated: current-time 
      })
    )
    
    (print {
      event: "relationship-suspended",
      bank-id: bank-id,
      reason: reason,
      suspended-by: tx-sender
    })
    
    (ok true)
  )
)

;; ===========================================
;; TRANSACTION PROCESSING
;; ===========================================

;; Initiate cross-border transaction
(define-public (initiate-transaction (to-bank-id uint) (amount uint) (currency (string-ascii 3)) 
                                   (reference (string-ascii 64)))
  (let (
    (from-bank-record (unwrap! (map-get? bank-principals { principal-addr: tx-sender }) (err u114)))
    (from-bank-id (get bank-id from-bank-record))
    (transaction-id (var-get next-transaction-id))
    (current-time (unwrap! (get-block-info? time (- block-height u1)) (err u999)))
    (fee-amount (calculate-transaction-fee amount from-bank-id to-bank-id))
  )
    (asserts! (var-get platform-active) (err u112))
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (is-relationship-active from-bank-id) ERR-RELATIONSHIP-SUSPENDED)
    (asserts! (is-relationship-active to-bank-id) ERR-BANK-NOT-FOUND)
    (asserts! (check-transaction-limits from-bank-id amount) ERR-RISK-LIMIT-EXCEEDED)
    (asserts! (not (is-eq from-bank-id to-bank-id)) (err u115))
    
    ;; Create transaction record
    (map-set transactions
      { transaction-id: transaction-id }
      {
        from-bank-id: from-bank-id,
        to-bank-id: to-bank-id,
        amount: amount,
        currency: currency,
        reference: reference,
        initiated-by: tx-sender,
        initiated-at: current-time,
        status: TX-STATUS-PENDING,
        approved-by: none,
        approved-at: none,
        settled-at: none,
        fee-amount: fee-amount,
        risk-score: u0,
        compliance-checked: false
      }
    )
    
    ;; Update risk exposure
    (update-risk-exposure from-bank-id amount true)
    
    ;; Increment transaction counter
    (var-set next-transaction-id (+ transaction-id u1))
    
    (print {
      event: "transaction-initiated",
      transaction-id: transaction-id,
      from-bank-id: from-bank-id,
      to-bank-id: to-bank-id,
      amount: amount,
      currency: currency,
      fee: fee-amount
    })
    
    (ok transaction-id)
  )
)

;; Approve pending transaction
(define-public (approve-transaction (transaction-id uint))
  (let (
    (tx-record (unwrap! (map-get? transactions { transaction-id: transaction-id }) ERR-TRANSACTION-NOT-FOUND))
    (to-bank-record (unwrap! (map-get? bank-principals { principal-addr: tx-sender }) (err u114)))
    (current-time (unwrap! (get-block-info? time (- block-height u1)) (err u999)))
  )
    (asserts! (is-eq (get bank-id to-bank-record) (get to-bank-id tx-record)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status tx-record) TX-STATUS-PENDING) ERR-INVALID-STATUS)
    
    (map-set transactions
      { transaction-id: transaction-id }
      (merge tx-record {
        status: TX-STATUS-APPROVED,
        approved-by: (some tx-sender),
        approved-at: (some current-time)
      })
    )
    
    (print {
      event: "transaction-approved",
      transaction-id: transaction-id,
      approved-by: tx-sender
    })
    
    (ok true)
  )
)

;; Settle approved transaction
(define-public (settle-transaction (transaction-id uint))
  (let (
    (tx-record (unwrap! (map-get? transactions { transaction-id: transaction-id }) ERR-TRANSACTION-NOT-FOUND))
    (current-time (unwrap! (get-block-info? time (- block-height u1)) (err u999)))
  )
    (asserts! (or (is-eq tx-sender (var-get contract-owner))
                 (is-authorized-bank tx-sender (get from-bank-id tx-record))
                 (is-authorized-bank tx-sender (get to-bank-id tx-record))) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status tx-record) TX-STATUS-APPROVED) ERR-INVALID-STATUS)
    
    ;; Update transaction status
    (map-set transactions
      { transaction-id: transaction-id }
      (merge tx-record {
        status: TX-STATUS-SETTLED,
        settled-at: (some current-time)
      })
    )
    
    ;; Update bank statistics
    (let (
      (from-bank (unwrap! (map-get? correspondent-banks { bank-id: (get from-bank-id tx-record) }) ERR-BANK-NOT-FOUND))
      (to-bank (unwrap! (map-get? correspondent-banks { bank-id: (get to-bank-id tx-record) }) ERR-BANK-NOT-FOUND))
    )
      (map-set correspondent-banks
        { bank-id: (get from-bank-id tx-record) }
        (merge from-bank {
          total-volume: (+ (get total-volume from-bank) (get amount tx-record)),
          active-transactions: (- (get active-transactions from-bank) u1)
        })
      )
      
      (map-set correspondent-banks
        { bank-id: (get to-bank-id tx-record) }
        (merge to-bank {
          total-volume: (+ (get total-volume to-bank) (get amount tx-record))
        })
      )
    )
    
    ;; Update global statistics
    (var-set total-volume (+ (var-get total-volume) (get amount tx-record)))
    (var-set total-fees-collected (+ (var-get total-fees-collected) (get fee-amount tx-record)))
    
    ;; Reduce risk exposure
    (update-risk-exposure (get from-bank-id tx-record) (get amount tx-record) false)
    
    (print {
      event: "transaction-settled",
      transaction-id: transaction-id,
      amount: (get amount tx-record),
      currency: (get currency tx-record),
      settled-by: tx-sender
    })
    
    (ok true)
  )
)

;; Reject transaction
(define-public (reject-transaction (transaction-id uint) (reason (string-ascii 128)))
  (let (
    (tx-record (unwrap! (map-get? transactions { transaction-id: transaction-id }) ERR-TRANSACTION-NOT-FOUND))
    (current-time (unwrap! (get-block-info? time (- block-height u1)) (err u999)))
  )
    (asserts! (or (is-eq tx-sender (var-get contract-owner))
                 (is-authorized-bank tx-sender (get to-bank-id tx-record))) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status tx-record) TX-STATUS-PENDING) ERR-INVALID-STATUS)
    
    (map-set transactions
      { transaction-id: transaction-id }
      (merge tx-record { status: TX-STATUS-REJECTED })
    )
    
    ;; Reduce risk exposure
    (update-risk-exposure (get from-bank-id tx-record) (get amount tx-record) false)
    
    (print {
      event: "transaction-rejected",
      transaction-id: transaction-id,
      reason: reason,
      rejected-by: tx-sender
    })
    
    (ok true)
  )
)

;; ===========================================
;; RISK MANAGEMENT
;; ===========================================

;; Update bank risk score
(define-public (update-risk-score (bank-id uint) (new-score uint) (assessment-notes (string-ascii 128)))
  (let (
    (bank-record (unwrap! (map-get? correspondent-banks { bank-id: bank-id }) ERR-BANK-NOT-FOUND))
    (current-time (unwrap! (get-block-info? time (- block-height u1)) (err u999)))
  )
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (<= new-score MAX-RISK-SCORE) (err u116))
    
    (map-set correspondent-banks
      { bank-id: bank-id }
      (merge bank-record {
        risk-score: new-score,
        last-updated: current-time
      })
    )
    
    ;; Update risk profile
    (match (map-get? risk-profiles { bank-id: bank-id })
      current-profile
      (map-set risk-profiles
        { bank-id: bank-id }
        (merge current-profile { last-assessment: current-time })
      )
      false
    )
    
    (print {
      event: "risk-score-updated",
      bank-id: bank-id,
      old-score: (get risk-score bank-record),
      new-score: new-score,
      notes: assessment-notes,
      updated-by: tx-sender
    })
    
    (ok true)
  )
)

;; Flag suspicious activity
(define-public (flag-suspicious-activity (transaction-id uint) (reason (string-ascii 128)) (severity uint))
  (let (
    (tx-record (unwrap! (map-get? transactions { transaction-id: transaction-id }) ERR-TRANSACTION-NOT-FOUND))
    (current-time (unwrap! (get-block-info? time (- block-height u1)) (err u999)))
    (event-id (+ (var-get next-transaction-id) u1000000)) ;; Use high number for event IDs
  )
    (asserts! (or (is-eq tx-sender (var-get contract-owner))
                 (is-authorized-bank tx-sender (get from-bank-id tx-record))
                 (is-authorized-bank tx-sender (get to-bank-id tx-record))) ERR-NOT-AUTHORIZED)
    (asserts! (<= severity u5) ERR-INVALID-STATUS)
    
    ;; Log compliance event
    (map-set compliance-events
      { event-id: event-id }
      {
        bank-id: (get from-bank-id tx-record),
        event-type: "suspicious-activity",
        description: reason,
        severity: severity,
        reported-by: tx-sender,
        reported-at: current-time,
        resolved: false,
        resolution-date: none
      }
    )
    
    (print {
      event: "suspicious-activity-flagged",
      transaction-id: transaction-id,
      bank-id: (get from-bank-id tx-record),
      reason: reason,
      severity: severity,
      flagged-by: tx-sender
    })
    
    (ok event-id)
  )
)

