;; -----------------------------
;; Constants and Error Codes
;; -----------------------------

;; Platform error codes
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-INVALID-AMOUNT (err u101))
(define-constant ERR-INSUFFICIENT-BALANCE (err u102))
(define-constant ERR-INVALID-POSITION (err u103))
(define-constant ERR-INSUFFICIENT-COLLATERAL (err u104))
(define-constant ERR-MAX-LEVERAGE-EXCEEDED (err u105))
(define-constant ERR-POSITION-NOT-FOUND (err u106))
(define-constant ERR-INVALID-STATE-TRANSITION (err u107))
(define-constant ERR-POSITION-ALREADY-CLOSED (err u108))
(define-constant ERR-MAX-POSITION-SIZE (err u109))
(define-constant ERR-MIN-POSITION-SIZE (err u110))
(define-constant ERR-INVALID-LEVERAGE (err u111))
(define-constant ERR-MARKET-CLOSED (err u112))
(define-constant ERR-NETWORK-ERROR (err u113))

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
(define-constant MAX-LEVERAGE u20)          ;; 20x maximum leverage
(define-constant MIN-POSITION-SIZE u100)    ;; Minimum position size
(define-constant MAX-POSITION-SIZE u100000) ;; Maximum position size

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

;; Submit price update with enhanced validation
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
        
        ;; Enhanced validation checks
        (asserts! (not (var-get platform-paused)) ERR-MARKET-CLOSED)
        (asserts! (get is-active source) ERR-UNAUTHORIZED-SOURCE)
        (asserts! (> price u0) ERR-INVALID-PRICE)
        
        ;; Check heartbeat
        (asserts! (is-heartbeat-valid source current-time) ERR-STALE-PRICE)
        
        ;; Verify price deviation
        (asserts! (is-price-deviation-acceptable 
                   price 
                   (get current-price feed-data)) 
                 ERR-PRICE-DEVIATION)
        
        ;; Update price feed with network checks
        (try! (update-price-feed feed-id price current-time feed-data))
        
        ;; Update source state
        (try! (update-source-state tx-sender source current-time))
        
        (ok true)))

;; -----------------------------
;; Trading Functions
;; -----------------------------

;; Open position with enhanced validation
(define-public (open-position 
    (position-type uint)
    (size uint)
    (leverage uint))
    (let ((current-price (unwrap! (get-valid-price u1) ERR-INVALID-PRICE))
          (required-collateral (/ (* size current-price) leverage))
          (current-balance (get stx-balance (get-balance tx-sender)))
          (position-id (+ (var-get position-counter) u1)))
        
        ;; Enhanced validation checks
        (try! (validate-position-parameters position-type size leverage))
        (asserts! (not (var-get platform-paused)) ERR-MARKET-CLOSED)
        (asserts! (>= current-balance required-collateral) ERR-INSUFFICIENT-COLLATERAL)
        
        ;; Calculate liquidation price with validation
        (let ((liquidation-price 
               (try! (calculate-liquidation-price-safe current-price position-type leverage))))
            
            ;; Create position with validation
            (try! (create-position 
                   position-id 
                   position-type 
                   size 
                   current-price 
                   leverage 
                   required-collateral 
                   liquidation-price))
            
            ;; Update balance safely
            (try! (update-user-balance tx-sender (- current-balance required-collateral)))
            
            (var-set position-counter position-id)
            (ok position-id))))

;; -----------------------------
;; Helper Functions
;; -----------------------------

;; Validate position parameters
(define-private (validate-position-parameters 
    (position-type uint)
    (size uint)
    (leverage uint))
    (begin
        (asserts! (or (is-eq position-type TYPE-LONG) 
                     (is-eq position-type TYPE-SHORT)) 
                 ERR-INVALID-POSITION)
        (asserts! (>= size MIN-POSITION-SIZE) ERR-MIN-POSITION-SIZE)
        (asserts! (<= size MAX-POSITION-SIZE) ERR-MAX-POSITION-SIZE)
        (asserts! (> leverage u0) ERR-INVALID-LEVERAGE)
        (asserts! (<= leverage MAX-LEVERAGE) ERR-MAX-LEVERAGE-EXCEEDED)
        (ok true)))

;; Safe price feed update
(define-private (update-price-feed 
    (feed-id uint)
    (price uint)
    (current-time (optional uint))
    (feed-data { current-price: uint,
                last-update: uint,
                source-count: uint,
                prices: (list 10 uint),
                timestamps: (list 10 uint) }))
    (let ((time (unwrap! current-time ERR-NETWORK-ERROR)))
        (map-set price-feeds feed-id
            { current-price: price,
              last-update: time,
              source-count: (+ (get source-count feed-data) u1),
              prices: (unwrap! (as-max-len? 
                               (concat (list price) 
                                      (get prices feed-data)) u10)
                             ERR-INVALID-PRICE),
              timestamps: (unwrap! (as-max-len? 
                                   (concat (list time) 
                                          (get timestamps feed-data)) u10)
                                 ERR-INVALID-PRICE) })
        (ok true)))

;; Update source state
(define-private (update-source-state 
    (source principal)
    (source-data { is-active: bool, last-update: uint, weight: uint })
    (current-time (optional uint)))
    (let ((time (unwrap! current-time ERR-NETWORK-ERROR)))
        (map-set price-sources source
            (merge source-data
                  { last-update: time }))
        (ok true)))

;; Calculate liquidation price with validation
(define-private (calculate-liquidation-price-safe 
    (entry-price uint)
    (position-type uint)
    (leverage uint))
    (begin
        (asserts! (> entry-price u0) ERR-INVALID-PRICE)
        (asserts! (> leverage u0) ERR-INVALID-LEVERAGE)
        (ok (if (is-eq position-type TYPE-LONG)
               (/ (* entry-price (- u100 (/ u100 leverage))) u100)
               (/ (* entry-price (+ u100 (/ u100 leverage))) u100)))))

;; Create position safely
(define-private (create-position
    (position-id uint)
    (position-type uint)
    (size uint)
    (entry-price uint)
    (leverage uint)
    (collateral uint)
    (liquidation-price uint))
    (begin
        (asserts! (is-none (map-get? positions position-id)) ERR-INVALID-STATE-TRANSITION)
        (map-set positions position-id
            { owner: tx-sender,
              position-type: position-type,
              size: size,
              entry-price: entry-price,
              leverage: leverage,
              collateral: collateral,
              liquidation-price: liquidation-price })
        (ok true)))

;; Update user balance safely
(define-private (update-user-balance (user principal) (new-balance uint))
    (begin
        (asserts! (>= new-balance u0) ERR-INSUFFICIENT-BALANCE)
        (map-set balances user { stx-balance: new-balance })
        (ok true)))

;; Existing helper functions remain unchanged
(define-private (is-price-fresh (feed-data { current-price: uint,
                                           last-update: uint,
                                           source-count: uint,
                                           prices: (list 10 uint),
                                           timestamps: (list 10 uint) }))
    (let ((current-time (unwrap-panic (get-block-info? time (- block-height u1)))))
        (< (- current-time (get last-update feed-data)) 
           (var-get price-validity-period))))

(define-private (is-heartbeat-valid 
    (source { is-active: bool, last-update: uint, weight: uint }) 
    (current-time (optional uint)))
    (let ((time (unwrap-panic current-time)))
        (or (is-eq (get last-update source) u0)
            (< (- time (get last-update source)) 
               (var-get heartbeat-interval)))))

(define-private (is-price-deviation-acceptable (new-price uint) (old-price uint))
    (if (is-eq old-price u0)
        true
        (let ((deviation (calculate-deviation new-price old-price)))
            (<= deviation (var-get max-price-deviation)))))

(define-private (calculate-deviation (price-a uint) (price-b uint))
    (let ((diff (if (> price-a price-b)
                   (- price-a price-b)
                   (- price-b price-a))))
        (* (/ (* diff u10000) price-b) u1)))

;; Read-only functions
(define-read-only (get-valid-price (feed-id uint))
    (let ((feed-data (unwrap! (map-get? price-feeds feed-id) ERR-INVALID-PRICE)))
        (asserts! (is-price-fresh feed-data) ERR-STALE-PRICE)
        (asserts! (>= (get source-count feed-data) 
                     (var-get min-oracle-sources))
                 ERR-INSUFFICIENT-SOURCES)
        (ok (get current-price feed-data))))

(define-read-only (get-balance (user principal))
    (default-to 
        { stx-balance: u0 }
        (map-get? balances user)))

(define-read-only (get-position (position-id uint))
    (map-get? positions position-id))
