;; Acquisition Planning Contract
;; Manages asset acquisition planning and approval workflows

;; Constants
(define-constant ERR-UNAUTHORIZED (err u200))
(define-constant ERR-NOT-FOUND (err u201))
(define-constant ERR-INVALID-STATUS (err u202))
(define-constant ERR-INSUFFICIENT-BUDGET (err u203))
(define-constant ERR-INVALID-PROPOSAL (err u204))

;; Data Variables
(define-data-var next-proposal-id uint u1)
(define-data-var total-budget uint u0)
(define-data-var allocated-budget uint u0)

;; Data Maps
(define-map acquisition-proposals
  { proposal-id: uint }
  {
    proposer: principal,
    asset-type: (string-ascii 50),
    description: (string-ascii 200),
    estimated-cost: uint,
    priority: (string-ascii 20),
    status: (string-ascii 20),
    created-at: uint,
    approved-by: (optional principal),
    approved-at: (optional uint),
    vendor: (optional (string-ascii 100)),
    justification: (string-ascii 300)
  }
)

(define-map budget-allocations
  { category: (string-ascii 50) }
  { allocated: uint, spent: uint, reserved: uint }
)

(define-map vendor-evaluations
  { vendor: (string-ascii 100) }
  {
    rating: uint,
    evaluations: uint,
    last-updated: uint,
    status: (string-ascii 20)
  }
)

;; Public Functions

;; Create acquisition proposal
(define-public (create-proposal
  (asset-type (string-ascii 50))
  (description (string-ascii 200))
  (estimated-cost uint)
  (priority (string-ascii 20))
  (justification (string-ascii 300))
)
  (let
    (
      (proposal-id (var-get next-proposal-id))
      (caller tx-sender)
    )
    (asserts! (> estimated-cost u0) ERR-INVALID-PROPOSAL)
    (asserts! (is-verified-acquisition-manager caller) ERR-UNAUTHORIZED)
    (asserts! (is-valid-priority priority) ERR-INVALID-PROPOSAL)

    (map-set acquisition-proposals
      { proposal-id: proposal-id }
      {
        proposer: caller,
        asset-type: asset-type,
        description: description,
        estimated-cost: estimated-cost,
        priority: priority,
        status: "pending",
        created-at: block-height,
        approved-by: none,
        approved-at: none,
        vendor: none,
        justification: justification
      }
    )

    (var-set next-proposal-id (+ proposal-id u1))
    (ok proposal-id)
  )
)

;; Approve acquisition proposal
(define-public (approve-proposal (proposal-id uint) (vendor (string-ascii 100)))
  (let
    (
      (caller tx-sender)
      (proposal (unwrap! (map-get? acquisition-proposals { proposal-id: proposal-id }) ERR-NOT-FOUND))
    )
    (asserts! (is-verified-acquisition-manager caller) ERR-UNAUTHORIZED)
    (asserts! (is-eq (get status proposal) "pending") ERR-INVALID-STATUS)
    (asserts! (>= (- (var-get total-budget) (var-get allocated-budget)) (get estimated-cost proposal)) ERR-INSUFFICIENT-BUDGET)

    (map-set acquisition-proposals
      { proposal-id: proposal-id }
      (merge proposal {
        status: "approved",
        approved-by: (some caller),
        approved-at: (some block-height),
        vendor: (some vendor)
      })
    )

    (var-set allocated-budget (+ (var-get allocated-budget) (get estimated-cost proposal)))
    (ok true)
  )
)

;; Execute approved acquisition
(define-public (execute-acquisition (proposal-id uint) (actual-cost uint))
  (let
    (
      (caller tx-sender)
      (proposal (unwrap! (map-get? acquisition-proposals { proposal-id: proposal-id }) ERR-NOT-FOUND))
    )
    (asserts! (is-verified-acquisition-manager caller) ERR-UNAUTHORIZED)
    (asserts! (is-eq (get status proposal) "approved") ERR-INVALID-STATUS)

    (map-set acquisition-proposals
      { proposal-id: proposal-id }
      (merge proposal { status: "executed" })
    )

    ;; Update budget allocation
    (var-set allocated-budget (- (var-get allocated-budget) (get estimated-cost proposal)))
    (ok true)
  )
)

;; Set budget allocation
(define-public (set-budget (amount uint))
  (begin
    (asserts! (is-verified-acquisition-manager tx-sender) ERR-UNAUTHORIZED)
    (var-set total-budget amount)
    (ok true)
  )
)

;; Evaluate vendor
(define-public (evaluate-vendor (vendor (string-ascii 100)) (rating uint))
  (let
    (
      (caller tx-sender)
      (current-eval (default-to
        { rating: u0, evaluations: u0, last-updated: u0, status: "active" }
        (map-get? vendor-evaluations { vendor: vendor })
      ))
    )
    (asserts! (is-verified-acquisition-manager caller) ERR-UNAUTHORIZED)
    (asserts! (<= rating u10) ERR-INVALID-PROPOSAL)

    (map-set vendor-evaluations
      { vendor: vendor }
      {
        rating: (/ (+ (* (get rating current-eval) (get evaluations current-eval)) rating) (+ (get evaluations current-eval) u1)),
        evaluations: (+ (get evaluations current-eval) u1),
        last-updated: block-height,
        status: "active"
      }
    )
    (ok true)
  )
)

;; Read-only Functions

;; Get proposal details
(define-read-only (get-proposal (proposal-id uint))
  (map-get? acquisition-proposals { proposal-id: proposal-id })
)

;; Get budget status
(define-read-only (get-budget-status)
  {
    total: (var-get total-budget),
    allocated: (var-get allocated-budget),
    available: (- (var-get total-budget) (var-get allocated-budget))
  }
)

;; Get vendor evaluation
(define-read-only (get-vendor-evaluation (vendor (string-ascii 100)))
  (map-get? vendor-evaluations { vendor: vendor })
)

;; Check if valid priority
(define-read-only (is-valid-priority (priority (string-ascii 20)))
  (or
    (is-eq priority "high")
    (is-eq priority "medium")
    (is-eq priority "low")
    (is-eq priority "critical")
  )
)

;; Check if verified acquisition manager
(define-read-only (is-verified-acquisition-manager (principal principal))
  ;; For now, allow any principal to act as acquisition manager
  ;; In production, this would check against a local authorization system
  true
)
