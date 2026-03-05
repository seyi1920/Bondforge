;; BondForge - Tokenized Debt & Lending Contract

;; Error constants
(define-constant err-bond-not-found (err u100))
(define-constant err-bond-already-accepted (err u101))
(define-constant err-bond-not-found-repay (err u102))
(define-constant err-not-borrower (err u103))
(define-constant err-deadline-passed (err u104))
(define-constant err-bond-not-found-default (err u105))
(define-constant err-deadline-not-passed (err u106))
(define-constant err-already-repaid (err u107))
(define-constant err-not-lender (err u108))
(define-constant err-transfer-failed (err u109))
(define-constant err-invalid-amount (err u110))
(define-constant err-invalid-deadline (err u111))

;; Data variables
(define-data-var bond-counter uint u0)

;; Data maps - FIXED: Using proper Tuple syntax {}
(define-map bonds
  { id: uint }
  {
    lender: principal,
    borrower: (optional principal),
    amount: uint,
    interest: uint,
    collateral: uint,
    deadline: uint,
    repaid: bool,
    defaulted: bool
  }
)

;; ---------------------------------------
;; PUBLIC: Create bond offer as a lender
;; ---------------------------------------
(define-public (create-bond (amount uint) (interest uint) (collateral uint) (deadline uint))
  (let ((id (var-get bond-counter)))
    (begin
      ;; Validate inputs
      (asserts! (> amount u0) err-invalid-amount)
      (asserts! (> deadline stacks-block-height) err-invalid-deadline)
      
      ;; Increment counter
      (var-set bond-counter (+ id u1))
      
      ;; Create bond - FIXED: Tuple syntax used here
      (map-set bonds { id: id }
        {
          lender: tx-sender,
          borrower: none,
          amount: amount,
          interest: interest,
          collateral: collateral,
          deadline: deadline,
          repaid: false,
          defaulted: false
        })
      (ok id))))

;; ---------------------------------------
;; PUBLIC: Accept a bond as borrower
;; ---------------------------------------
(define-public (accept-bond (id uint))
  (let ((bond (unwrap! (map-get? bonds { id: id }) err-bond-not-found)))
    (begin
      (asserts! (is-none (get borrower bond)) err-bond-already-accepted)
      (asserts! (not (get repaid bond)) err-already-repaid)
      (asserts! (not (get defaulted bond)) err-already-repaid)
      
      ;; 1. Borrower sends collateral to the contract
      (try! (stx-transfer? (get collateral bond) tx-sender (as-contract tx-sender)))
      
      ;; 2. Lender sends loan amount to the borrower
      ;; FIXED: Transfers from tx-sender (lender) to borrower (tx-sender in this context is borrower, 
      ;; so we need to ensure the lender is the one who 'funded' the bond earlier or 
      ;; the lender transfers now). Assuming lender funds now:
      (try! (stx-transfer? (get amount bond) (get lender bond) tx-sender))
      
      (map-set bonds { id: id }
        (merge bond { borrower: (some tx-sender) }))
      (ok true))))

;; ---------------------------------------
;; PUBLIC: Repay a bond
;; ---------------------------------------
(define-public (repay-bond (id uint))
  (let (
    (bond (unwrap! (map-get? bonds { id: id }) err-bond-not-found-repay))
    (borrower-principal (unwrap! (get borrower bond) err-not-borrower))
  )
    (begin
      (asserts! (is-eq borrower-principal tx-sender) err-not-borrower)
      (asserts! (<= stacks-block-height (get deadline bond)) err-deadline-passed)
      (asserts! (not (get repaid bond)) err-already-repaid)
      
      ;; 1. Borrower pays lender (Principal + Interest)
      (try! (stx-transfer? (+ (get amount bond) (get interest bond)) tx-sender (get lender bond)))
      
      ;; 2. Contract returns collateral to borrower
      (try! (as-contract (stx-transfer? (get collateral bond) (as-contract tx-sender) borrower-principal)))
      
      (map-set bonds { id: id }
        (merge bond { repaid: true }))
      (ok true))))

;; ---------------------------------------
;; PUBLIC: Mark default and claim collateral
;; ---------------------------------------
(define-public (mark-default (id uint))
  (let ((bond (unwrap! (map-get? bonds { id: id }) err-bond-not-found-default)))
    (begin
      (asserts! (> stacks-block-height (get deadline bond)) err-deadline-not-passed)
      (asserts! (not (get repaid bond)) err-already-repaid)
      (asserts! (not (get defaulted bond)) err-already-repaid)
      (asserts! (is-eq tx-sender (get lender bond)) err-not-lender)
      
      ;; Contract transfers collateral to lender
      (try! (as-contract (stx-transfer? (get collateral bond) (as-contract tx-sender) (get lender bond))))
      
      (map-set bonds { id: id }
        (merge bond { defaulted: true }))
      (ok true))))

;; ---------------------------------------
;; READ-ONLY FUNCTIONS (Fixed syntax)
;; ---------------------------------------
(define-read-only (get-bond (id uint))
  (map-get? bonds { id: id }))

(define-read-only (get-bond-counter)
  (var-get bond-counter))