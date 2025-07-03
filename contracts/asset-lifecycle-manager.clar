;; Asset Lifecycle Manager Contract
;; Manages verification and roles for asset lifecycle managers

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-ALREADY-EXISTS (err u101))
(define-constant ERR-NOT-FOUND (err u102))
(define-constant ERR-INVALID-STATUS (err u103))
(define-constant ERR-INVALID-ROLE (err u104))

;; Data Variables
(define-data-var next-manager-id uint u1)

;; Data Maps
(define-map managers
  { manager-id: uint }
  {
    principal: principal,
    role: (string-ascii 50),
    status: (string-ascii 20),
    verified-at: uint,
    verified-by: principal,
    capabilities: (list 10 (string-ascii 30))
  }
)

(define-map manager-principals
  { principal: principal }
  { manager-id: uint }
)

(define-map authorized-verifiers
  { principal: principal }
  { authorized: bool, role: (string-ascii 30) }
)

;; Initialize contract owner as first verifier
(map-set authorized-verifiers
  { principal: CONTRACT-OWNER }
  { authorized: true, role: "admin" }
)

;; Public Functions

;; Register a new asset lifecycle manager
(define-public (register-manager (manager-principal principal) (role (string-ascii 50)) (capabilities (list 10 (string-ascii 30))))
  (let
    (
      (caller tx-sender)
      (manager-id (var-get next-manager-id))
    )
    (asserts! (is-authorized-verifier caller) ERR-UNAUTHORIZED)
    (asserts! (is-none (map-get? manager-principals { principal: manager-principal })) ERR-ALREADY-EXISTS)
    (asserts! (is-valid-role role) ERR-INVALID-ROLE)

    (map-set managers
      { manager-id: manager-id }
      {
        principal: manager-principal,
        role: role,
        status: "pending",
        verified-at: block-height,
        verified-by: caller,
        capabilities: capabilities
      }
    )

    (map-set manager-principals
      { principal: manager-principal }
      { manager-id: manager-id }
    )

    (var-set next-manager-id (+ manager-id u1))
    (ok manager-id)
  )
)

;; Verify a manager
(define-public (verify-manager (manager-id uint))
  (let
    (
      (caller tx-sender)
      (manager-data (unwrap! (map-get? managers { manager-id: manager-id }) ERR-NOT-FOUND))
    )
    (asserts! (is-authorized-verifier caller) ERR-UNAUTHORIZED)
    (asserts! (is-eq (get status manager-data) "pending") ERR-INVALID-STATUS)

    (map-set managers
      { manager-id: manager-id }
      (merge manager-data { status: "verified", verified-at: block-height, verified-by: caller })
    )
    (ok true)
  )
)

;; Suspend a manager
(define-public (suspend-manager (manager-id uint))
  (let
    (
      (caller tx-sender)
      (manager-data (unwrap! (map-get? managers { manager-id: manager-id }) ERR-NOT-FOUND))
    )
    (asserts! (is-authorized-verifier caller) ERR-UNAUTHORIZED)

    (map-set managers
      { manager-id: manager-id }
      (merge manager-data { status: "suspended" })
    )
    (ok true)
  )
)

;; Add authorized verifier
(define-public (add-verifier (verifier-principal principal) (role (string-ascii 30)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (map-set authorized-verifiers
      { principal: verifier-principal }
      { authorized: true, role: role }
    )
    (ok true)
  )
)

;; Read-only Functions

;; Check if principal is authorized verifier
(define-read-only (is-authorized-verifier (principal principal))
  (default-to false (get authorized (map-get? authorized-verifiers { principal: principal })))
)

;; Check if principal is verified manager
(define-read-only (is-verified-manager (principal principal))
  (match (map-get? manager-principals { principal: principal })
    manager-info
      (match (map-get? managers { manager-id: (get manager-id manager-info) })
        manager-data (is-eq (get status manager-data) "verified")
        false
      )
    false
  )
)

;; Get manager details
(define-read-only (get-manager (manager-id uint))
  (map-get? managers { manager-id: manager-id })
)

;; Get manager by principal
(define-read-only (get-manager-by-principal (principal principal))
  (match (map-get? manager-principals { principal: principal })
    manager-info (map-get? managers { manager-id: (get manager-id manager-info) })
    none
  )
)

;; Check if role is valid
(define-read-only (is-valid-role (role (string-ascii 50)))
  (or
    (is-eq role "acquisition-manager")
    (is-eq role "utilization-manager")
    (is-eq role "maintenance-manager")
    (is-eq role "disposal-manager")
    (is-eq role "general-manager")
  )
)

;; Check if manager has specific capability
(define-read-only (has-capability (manager-principal principal) (capability (string-ascii 30)))
  (match (get-manager-by-principal manager-principal)
    manager-data
      (and
        (is-eq (get status manager-data) "verified")
        (is-some (index-of (get capabilities manager-data) capability))
      )
    false
  )
)
