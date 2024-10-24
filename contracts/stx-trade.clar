;; -----------------------------
;; Constants and Error Codes
;; -----------------------------

;; Platform error codes
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-INVALID-AMOUNT (err u101))
(define-constant ERR-INSUFFICIENT-BALANCE (err u102))
(define-constant ERR-INVALID-POSITION (err u103))
(define-constant ERR-INSUFFICIENT-COLLATERAL (err u104))

;; Oracle error codes
(define-constant ERR-INVALID-PRICE (err u201))
(define-constant ERR-STALE-PRICE (err u202))
(define-constant ERR-INSUFFICIENT-SOURCES (err u203))
(define-constant ERR-PRICE-DEVIATION (err u204))
(define-constant ERR-UNAUTHORIZED-SOURCE (err u205))

;; Trading constants
(define-constant MIN-COLLATERAL-RATIO u150)  ;; 150%
(define-constant TYPE-LONG u1)
(define-constant TYPE-SHORT u2)

;; -----------------------------
;; Data Variables
;; -----------------------------

;; Platform state
(define-data-var contract-owner principal tx-sender)
(define-data-var platform-paused bool false)
(define-data-var position-counter uint u0)

;; Oracle configuration
(define-data-var min-oracle-sources uint u3)
(define-data-var price-validity-period uint u300)  ;; 5 minutes
(define-data-var max-price-deviation uint u1000)   ;; 10%
(define-data-var heartbeat-interval uint u300)     ;; 5 minutes

;; -----------------------------
;; Data Maps
;; -----------------------------

;; User balances
(define-map balances 
    principal 
    { stx-balance: uint })

;; Trading positions
(define-map positions 
    uint 
    { owner: principal,
      position-type: uint,
      size: uint,
      entry-price: uint,
      leverage: uint,
      collateral: uint,
      liquidation-price: uint })

;; Oracle sources
(define-map price-sources
    principal
    { is-active: bool,
      last-update: uint,
      weight: uint })

;; Price data
(define-map price-feeds
    uint  ;; feed-id
    { current-price: uint,
      last-update: uint,
      source-count: uint,
      prices: (list 10 uint),     ;; Price history
      timestamps: (list 10 uint)  ;; Timestamp history
    })

;; -----------------------------
;; Oracle Management Functions
;; -----------------------------

;; Register price source
(define-public (register-price-source (source principal) (weight uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-UNAUTHORIZED)
        (map-set price-sources
            source
            { is-active: true,
              last-update: u0,
              weight: weight })
        (ok true)))

;; Submit price update
(define-public (submit-price-update (feed-id uint) (price uint))
    (let ((source (unwrap! (map-get? price-sources tx-sender) ERR-UNAUTHORIZED-SOURCE))
          (current-time (get-block-info? time (- block-height u1)))
          (feed-data (default-to 
                      { current-price: u0, 
                        last-update: u0, 
                        source-count: u0,
                        prices: (list u0),
                        timestamps: (list u0) }
                      (map-get? price-feeds feed-id))))
        
        ;; Verify source is active
        (asserts! (get is-active source) ERR-UNAUTHORIZED-SOURCE)
        
        ;; Check heartbeat
        (asserts! (is-heartbeat-valid source current-time) ERR-STALE-PRICE)
        
        ;; Verify price deviation
        (asserts! (is-price-deviation-acceptable 
                   price 
                   (get current-price feed-data)) 
                 ERR-PRICE-DEVIATION)
        
        ;; Update price feed
        (map-set price-feeds feed-id
            { current-price: price,
              last-update: (unwrap! current-time ERR-INVALID-PRICE),
              source-count: (+ (get source-count feed-data) u1),
              prices: (unwrap! (as-max-len? 
                               (concat (list price) 
                                      (get prices feed-data)) u10)
                             ERR-INVALID-PRICE),
              timestamps: (unwrap! (as-max-len? 
                                   (concat (list (unwrap! current-time (err u255))) 
                                          (get timestamps feed-data)) u10)
                                 ERR-INVALID-PRICE) })
        
        ;; Update source
        (map-set price-sources tx-sender
            (merge source
                  { last-update: (unwrap! current-time (err u256)) }))
        
        (ok true)))

;; -----------------------------
;; Trading Functions
;; -----------------------------

;; Open position with oracle price
(define-public (open-position 
    (position-type uint)
    (size uint)
    (leverage uint))
    (let ((current-price (unwrap! (get-valid-price u1) ERR-INVALID-PRICE))
          (required-collateral (/ (* size current-price) leverage))
          (current-balance (get stx-balance (get-balance tx-sender)))
          (position-id (+ (var-get position-counter) u1)))
        
        ;; Verify platform state
        (asserts! (not (var-get platform-paused)) ERR-UNAUTHORIZED)
        
        ;; Verify position parameters
        (asserts! (or (is-eq position-type TYPE-LONG) 
                     (is-eq position-type TYPE-SHORT)) 
                 ERR-INVALID-POSITION)
        (asserts! (>= current-balance required-collateral) 
                 ERR-INSUFFICIENT-COLLATERAL)
        
        ;; Calculate liquidation price
        (let ((liquidation-price 
               (calculate-liquidation-price current-price position-type leverage)))
            
            ;; Create position
            (map-set positions position-id
                { owner: tx-sender,
                  position-type: position-type,
                  size: size,
                  entry-price: current-price,
                  leverage: leverage,
                  collateral: required-collateral,
                  liquidation-price: liquidation-price })
            
            ;; Update balance
            (map-set balances 
                tx-sender 
                { stx-balance: (- current-balance required-collateral) })
            
            ;; Update counter
            (var-set position-counter position-id)
            (ok position-id))))

;; -----------------------------
;; Helper Functions
;; -----------------------------

;; Get valid price
(define-read-only (get-valid-price (feed-id uint))
    (let ((feed-data (unwrap! (map-get? price-feeds feed-id) ERR-INVALID-PRICE)))
        ;; Verify price freshness
        (asserts! (is-price-fresh feed-data) ERR-STALE-PRICE)
        
        ;; Verify minimum sources
        (asserts! (>= (get source-count feed-data) 
                     (var-get min-oracle-sources)) 
                 ERR-INSUFFICIENT-SOURCES)
        
        (ok (get current-price feed-data))))

;; Check price freshness
(define-private (is-price-fresh 
    (feed-data { current-price: uint,
                last-update: uint,
                source-count: uint,
                prices: (list 10 uint),
                timestamps: (list 10 uint) }))
    (let ((current-time (unwrap! (get-block-info? time (- block-height u1)) u0)))
        (< (- current-time (get last-update feed-data)) 
           (var-get price-validity-period))))

;; Validate heartbeat
(define-private (is-heartbeat-valid 
    (source { is-active: bool, last-update: uint, weight: uint }) 
    (current-time (optional uint)))
    (let ((time (unwrap! current-time false)))
        (or (is-eq (get last-update source) u0)
            (< (- time (get last-update source)) 
               (var-get heartbeat-interval)))))

;; Check price deviation
(define-private (is-price-deviation-acceptable (new-price uint) (old-price uint))
    (if (is-eq old-price u0)
        true
        (let ((deviation (calculate-deviation new-price old-price)))
            (<= deviation (var-get max-price-deviation)))))

;; Calculate price deviation
(define-private (calculate-deviation (price-a uint) (price-b uint))
    (let ((diff (if (> price-a price-b)
                   (- price-a price-b)
                   (- price-b price-a))))
        (* (/ (* diff u10000) price-b) u1)))  ;; Convert to basis points

;; Calculate liquidation price
(define-private (calculate-liquidation-price 
    (entry-price uint) 
    (position-type uint) 
    (leverage uint))
    (if (is-eq position-type TYPE-LONG)
        (/ (* entry-price (- u100 (/ u100 leverage))) u100)
        (/ (* entry-price (+ u100 (/ u100 leverage))) u100)))

;; Get user balance
(define-read-only (get-balance (user principal))
    (default-to 
        { stx-balance: u0 }
        (map-get? balances user)))

;; Get position details
(define-read-only (get-position (position-id uint))
    (map-get? positions position-id))
