;; Title: STX-Derivatives Platform Core Contracts
;; Description: Implementation of core derivatives trading functionality

;; -----------------------------
;; Constants and Traits
;; -----------------------------

;; Define error codes
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-INVALID-AMOUNT (err u101))
(define-constant ERR-INSUFFICIENT-BALANCE (err u102))
(define-constant ERR-INVALID-POSITION (err u103))
(define-constant ERR-INSUFFICIENT-COLLATERAL (err u104))

;; Minimum collateral ratio (150%)
(define-constant MIN-COLLATERAL-RATIO u150)

;; Position types
(define-constant TYPE-LONG u1)
(define-constant TYPE-SHORT u2)

;; -----------------------------
;; Data Maps and Variables
;; -----------------------------

;; Track user balances
(define-map balances 
    principal 
    { stx-balance: uint })

;; Track positions
(define-map positions 
    uint 
    { owner: principal,
      position-type: uint,
      size: uint,
      entry-price: uint,
      leverage: uint,
      collateral: uint,
      liquidation-price: uint })

;; Position counter
(define-data-var position-counter uint u0)

;; Contract admin
(define-data-var contract-owner principal tx-sender)

;; Price oracle (simplified for testnet)
(define-data-var current-price uint u0)

;; -----------------------------
;; Read-Only Functions
;; -----------------------------

(define-read-only (get-balance (user principal))
    (default-to 
        { stx-balance: u0 }
        (map-get? balances user)))

(define-read-only (get-position (position-id uint))
    (map-get? positions position-id))

(define-read-only (get-current-price)
    (ok (var-get current-price)))

;; Calculate liquidation price
(define-read-only (calculate-liquidation-price 
    (entry-price uint) 
    (position-type uint) 
    (leverage uint))
    (if (is-eq position-type TYPE-LONG)
        ;; Long position liquidation price
        (ok (/ (* entry-price (- u100 (/ u100 leverage))) u100))
        ;; Short position liquidation price
        (ok (/ (* entry-price (+ u100 (/ u100 leverage))) u100))))

;; -----------------------------
;; Public Functions
;; -----------------------------

;; Deposit collateral
(define-public (deposit-collateral (amount uint))
    (let ((current-balance (get stx-balance (get-balance tx-sender))))
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (ok (map-set balances 
            tx-sender 
            { stx-balance: (+ current-balance amount) }))))

;; Withdraw collateral
(define-public (withdraw-collateral (amount uint))
    (let ((current-balance (get stx-balance (get-balance tx-sender))))
        (asserts! (>= current-balance amount) ERR-INSUFFICIENT-BALANCE)
        (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
        (ok (map-set balances 
            tx-sender 
            { stx-balance: (- current-balance amount) }))))

;; Open position
(define-public (open-position 
    (position-type uint)
    (size uint)
    (leverage uint))
    (let 
        ((required-collateral (/ (* size (var-get current-price)) leverage))
         (current-balance (get stx-balance (get-balance tx-sender)))
         (position-id (+ (var-get position-counter) u1))
         (entry-price (var-get current-price)))
        
        ;; Verify conditions
        (asserts! (or (is-eq position-type TYPE-LONG) 
                     (is-eq position-type TYPE-SHORT)) ERR-INVALID-POSITION)
        (asserts! (>= current-balance required-collateral) ERR-INSUFFICIENT-COLLATERAL)
        
        ;; Calculate liquidation price
        (let ((liquidation-price (unwrap! (calculate-liquidation-price 
                                         entry-price 
                                         position-type 
                                         leverage) ERR-INVALID-POSITION)))
            
            ;; Create position
            (map-set positions position-id
                { owner: tx-sender,
                  position-type: position-type,
                  size: size,
                  entry-price: entry-price,
                  leverage: leverage,
                  collateral: required-collateral,
                  liquidation-price: liquidation-price })
            
            ;; Update balance
            (map-set balances 
                tx-sender 
                { stx-balance: (- current-balance required-collateral) })
            
            ;; Increment position counter
            (var-set position-counter position-id)
            (ok position-id))))

;; Close position
(define-public (close-position (position-id uint))
    (let ((position (unwrap! (get-position position-id) ERR-INVALID-POSITION)))
        ;; Verify owner
        (asserts! (is-eq (get owner position) tx-sender) ERR-UNAUTHORIZED)
        
        ;; Calculate PnL
        (let ((pnl (calculate-pnl position)))
            ;; Return collateral + PnL
            (try! (as-contract 
                   (stx-transfer? 
                    (+ (get collateral position) pnl) 
                    tx-sender 
                    tx-sender)))
            
            ;; Delete position
            (map-delete positions position-id)
            (ok true))))

;; -----------------------------
;; Private Functions
;; -----------------------------

;; Calculate PnL (simplified)
(define-private (calculate-pnl (position {owner: principal, 
                                        position-type: uint,
                                        size: uint,
                                        entry-price: uint,
                                        leverage: uint,
                                        collateral: uint,
                                        liquidation-price: uint}))
    (let ((current-price-local (var-get current-price))
          (price-diff (if (is-eq (get position-type position) TYPE-LONG)
                         (- current-price-local (get entry-price position))
                         (- (get entry-price position) current-price-local))))
        (* price-diff (get size position))))

;; -----------------------------
;; Admin Functions
;; -----------------------------

;; Update price (would be replaced by oracle in production)
(define-public (update-price (new-price uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-UNAUTHORIZED)
        (var-set current-price new-price)
        (ok true)))

;; Update contract owner
(define-public (set-contract-owner (new-owner principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-UNAUTHORIZED)
        (var-set contract-owner new-owner)
        (ok true)))
