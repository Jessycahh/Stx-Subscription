;; Subscription Service Smart Contract

;; Error codes
(define-constant ERROR-UNAUTHORIZED-ACCESS (err u100))
(define-constant ERROR-SUBSCRIPTION-EXISTS (err u101))
(define-constant ERROR-NO-ACTIVE-SUBSCRIPTION (err u102))
(define-constant ERROR-INSUFFICIENT-STX-BALANCE (err u103))
(define-constant ERROR-INVALID-SUBSCRIPTION-TYPE (err u104))
(define-constant ERROR-SUBSCRIPTION-EXPIRED (err u105))
(define-constant ERROR-INVALID-REFUND-AMOUNT (err u106))
(define-constant ERROR-IDENTICAL-PLAN-UPGRADE (err u107))
(define-constant ERROR-REFUND-PERIOD-EXPIRED (err u108))
(define-constant ERROR-INVALID-PLAN-CHANGE (err u109))
(define-constant ERROR-INVALID-INPUT-PARAMETERS (err u110))

;; Data vars
(define-data-var contract-administrator principal tx-sender)
(define-data-var minimum-subscription-cost uint u100)
(define-data-var standard-subscription-duration uint u2592000)
(define-data-var maximum-refund-window uint u259200)  ;; 3 days in seconds
(define-data-var subscription-plan-change-fee uint u1000000)     ;; 1 STX fee for changing plans

;; Data maps
(define-map SubscriberDetails
    principal
    {
        subscription-active: bool,
        subscription-start-timestamp: uint,
        subscription-end-timestamp: uint,
        current-subscription-plan: (string-ascii 20),
        last-payment-amount: uint,
        subscription-credit-balance: uint
    }
)

(define-map SubscriptionTierConfiguration
    (string-ascii 20)
    {
        plan-cost: uint,
        plan-duration: uint,
        plan-features: (list 10 (string-ascii 50)),
        plan-tier-level: uint,  ;; Higher number means higher tier
        refunds-enabled: bool
    }
)

(define-map CustomerRefundHistory
    { subscriber: principal, refund-timestamp: uint }
    {
        refund-amount: uint,
        refund-reason: (string-ascii 50)
    }
)

;; Read-only functions
(define-read-only (get-subscriber-details (subscriber-address principal))
    (map-get? SubscriberDetails subscriber-address)
)

(define-read-only (get-subscription-tier-details (subscription-tier-name (string-ascii 20)))
    (map-get? SubscriptionTierConfiguration subscription-tier-name)
)

(define-read-only (calculate-subscription-time-remaining (subscriber-address principal))
    (let (
        (subscriber-info (unwrap! (map-get? SubscriberDetails subscriber-address) u0))
    )
    (if (get subscription-active subscriber-info)
        (- (get subscription-end-timestamp subscriber-info) block-height)
        u0
    ))
)

(define-read-only (calculate-eligible-refund-amount (subscriber-address principal))
    (let (
        (subscriber-info (unwrap! (map-get? SubscriberDetails subscriber-address) u0))
        (elapsed-subscription-time (- block-height (get subscription-start-timestamp subscriber-info)))
        (total-subscription-period (- (get subscription-end-timestamp subscriber-info) (get subscription-start-timestamp subscriber-info)))
        (original-subscription-payment (get last-payment-amount subscriber-info))
    )
    (if (> elapsed-subscription-time (var-get maximum-refund-window))
        u0
        (/ (* original-subscription-payment (- total-subscription-period elapsed-subscription-time)) total-subscription-period)
    ))
)

;; Private functions
(define-private (verify-administrative-rights)
    (is-eq tx-sender (var-get contract-administrator))
)

(define-private (process-customer-refund (subscriber principal) (refund-amount uint) (refund-justification (string-ascii 50)))
    (begin
        (try! (stx-transfer? refund-amount (var-get contract-administrator) subscriber))
        (map-set CustomerRefundHistory
            { subscriber: subscriber, refund-timestamp: block-height }
            {
                refund-amount: refund-amount,
                refund-reason: refund-justification
            }
        )
        (ok true)
    )
)

(define-private (validate-plan-features (feature-list (list 10 (string-ascii 50))))
    (let ((total-features (len feature-list)))
        (and (> total-features u0) (<= total-features u10))
    )
)

;; Function for creating subscription plans
(define-public (create-subscription-tier 
    (tier-name (string-ascii 20))
    (tier-cost uint)
    (tier-duration uint)
    (tier-features (list 10 (string-ascii 50)))
    (tier-level uint)
    (allows-refunds bool))
    (begin
        (asserts! (verify-administrative-rights) ERROR-UNAUTHORIZED-ACCESS)
        (asserts! (> tier-cost u0) ERROR-INVALID-INPUT-PARAMETERS)
        (asserts! (> tier-duration u0) ERROR-INVALID-INPUT-PARAMETERS)
        (asserts! (> tier-level u0) ERROR-INVALID-INPUT-PARAMETERS)
        (asserts! (validate-plan-features tier-features) ERROR-INVALID-INPUT-PARAMETERS)
        (asserts! (not (is-eq tier-name "")) ERROR-INVALID-INPUT-PARAMETERS)
        (ok (map-set SubscriptionTierConfiguration
            tier-name
            {
                plan-cost: tier-cost,
                plan-duration: tier-duration,
                plan-features: tier-features,
                plan-tier-level: tier-level,
                refunds-enabled: allows-refunds
            }
        ))
    )
)

;; Public functions for plan management
(define-public (subscribe-to-plan (selected-tier-name (string-ascii 20)))
    (let (
        (tier-details (unwrap! (map-get? SubscriptionTierConfiguration selected-tier-name) ERROR-INVALID-SUBSCRIPTION-TYPE))
        (subscription-start-time block-height)
        (tier-subscription-cost (get plan-cost tier-details))
        (existing-subscription (get-subscriber-details tx-sender))
    )
    (asserts! (is-none existing-subscription) ERROR-SUBSCRIPTION-EXISTS)
    (asserts! (not (is-eq selected-tier-name "")) ERROR-INVALID-INPUT-PARAMETERS)
    (asserts! (> tier-subscription-cost u0) ERROR-INVALID-INPUT-PARAMETERS)
    (try! (stx-transfer? tier-subscription-cost tx-sender (var-get contract-administrator)))
    
    (ok (map-set SubscriberDetails
        tx-sender
        {
            subscription-active: true,
            subscription-start-timestamp: subscription-start-time,
            subscription-end-timestamp: (+ subscription-start-time (get plan-duration tier-details)),
            current-subscription-plan: selected-tier-name,
            last-payment-amount: tier-subscription-cost,
            subscription-credit-balance: u0
        }
    ))
))

(define-public (request-subscription-refund (refund-justification (string-ascii 50)))
    (let (
        (subscriber-info (unwrap! (map-get? SubscriberDetails tx-sender) ERROR-NO-ACTIVE-SUBSCRIPTION))
        (tier-details (unwrap! (map-get? SubscriptionTierConfiguration (get current-subscription-plan subscriber-info)) ERROR-INVALID-SUBSCRIPTION-TYPE))
        (calculated-refund-amount (calculate-eligible-refund-amount tx-sender))
    )
    (asserts! (get subscription-active subscriber-info) ERROR-NO-ACTIVE-SUBSCRIPTION)
    (asserts! (get refunds-enabled tier-details) ERROR-INVALID-REFUND-AMOUNT)
    (asserts! (> calculated-refund-amount u0) ERROR-INVALID-REFUND-AMOUNT)
    (asserts! (not (is-eq refund-justification "")) ERROR-INVALID-INPUT-PARAMETERS)
    
    (try! (process-customer-refund tx-sender calculated-refund-amount refund-justification))
    
    (ok (map-set SubscriberDetails
        tx-sender
        {
            subscription-active: false,
            subscription-start-timestamp: (get subscription-start-timestamp subscriber-info),
            subscription-end-timestamp: block-height,
            current-subscription-plan: (get current-subscription-plan subscriber-info),
            last-payment-amount: u0,
            subscription-credit-balance: u0
        }
    ))
))

(define-public (upgrade-subscription-tier (new-tier-name (string-ascii 20)))
    (begin
        (let (
            (current-subscription (unwrap! (map-get? SubscriberDetails tx-sender) ERROR-NO-ACTIVE-SUBSCRIPTION))
            (current-tier (unwrap! (map-get? SubscriptionTierConfiguration (get current-subscription-plan current-subscription)) ERROR-INVALID-SUBSCRIPTION-TYPE))
            (new-tier (unwrap! (map-get? SubscriptionTierConfiguration new-tier-name) ERROR-INVALID-SUBSCRIPTION-TYPE))
            (remaining-subscription-time (calculate-subscription-time-remaining tx-sender))
            (current-tier-value-remaining (* (get last-payment-amount current-subscription) (/ remaining-subscription-time (get plan-duration current-tier))))
        )
        (asserts! (get subscription-active current-subscription) ERROR-NO-ACTIVE-SUBSCRIPTION)
        (asserts! (> (get plan-tier-level new-tier) (get plan-tier-level current-tier)) ERROR-INVALID-PLAN-CHANGE)
        (asserts! (not (is-eq new-tier-name (get current-subscription-plan current-subscription))) ERROR-IDENTICAL-PLAN-UPGRADE)
        
        (let (
            (tier-upgrade-cost (- (get plan-cost new-tier) current-tier-value-remaining))
        )
        (try! (stx-transfer? (+ tier-upgrade-cost (var-get subscription-plan-change-fee)) tx-sender (var-get contract-administrator)))
        
        (ok (map-set SubscriberDetails
            tx-sender
            {
                subscription-active: true,
                subscription-start-timestamp: block-height,
                subscription-end-timestamp: (+ block-height (get plan-duration new-tier)),
                current-subscription-plan: new-tier-name,
                last-payment-amount: (get plan-cost new-tier),
                subscription-credit-balance: u0
            }
        ))
    ))
))

(define-public (downgrade-subscription-tier (new-tier-name (string-ascii 20)))
    (begin
        (let (
            (current-subscription (unwrap! (map-get? SubscriberDetails tx-sender) ERROR-NO-ACTIVE-SUBSCRIPTION))
            (current-tier (unwrap! (map-get? SubscriptionTierConfiguration (get current-subscription-plan current-subscription)) ERROR-INVALID-SUBSCRIPTION-TYPE))
            (new-tier (unwrap! (map-get? SubscriptionTierConfiguration new-tier-name) ERROR-INVALID-SUBSCRIPTION-TYPE))
            (remaining-subscription-time (calculate-subscription-time-remaining tx-sender))
        )
        (asserts! (get subscription-active current-subscription) ERROR-NO-ACTIVE-SUBSCRIPTION)
        (asserts! (< (get plan-tier-level new-tier) (get plan-tier-level current-tier)) ERROR-INVALID-PLAN-CHANGE)
        
        (let (
            (current-tier-value-remaining (* (get last-payment-amount current-subscription) (/ remaining-subscription-time (get plan-duration current-tier))))
            (subscription-credit-amount (- current-tier-value-remaining (get plan-cost new-tier)))
        )
        (try! (stx-transfer? (var-get subscription-plan-change-fee) tx-sender (var-get contract-administrator)))
        
        (ok (map-set SubscriberDetails
            tx-sender
            {
                subscription-active: true,
                subscription-start-timestamp: block-height,
                subscription-end-timestamp: (+ block-height (get plan-duration new-tier)),
                current-subscription-plan: new-tier-name,
                last-payment-amount: (get plan-cost new-tier),
                subscription-credit-balance: subscription-credit-amount
            }
        ))
    ))
))

;; Admin functions
(define-public (update-refund-window (new-refund-window uint))
    (begin
        (asserts! (verify-administrative-rights) ERROR-UNAUTHORIZED-ACCESS)
        (asserts! (> new-refund-window u0) ERROR-INVALID-INPUT-PARAMETERS)
        (ok (var-set maximum-refund-window new-refund-window))
    )
)

(define-public (update-plan-change-fee (updated-fee uint))
    (begin
        (asserts! (verify-administrative-rights) ERROR-UNAUTHORIZED-ACCESS)
        (asserts! (>= updated-fee u0) ERROR-INVALID-INPUT-PARAMETERS)
        (ok (var-set subscription-plan-change-fee updated-fee))
    )
)

;; Initial contract setup
(begin
    ;; Add default subscription plans
    (try! (create-subscription-tier
        "basic-tier"  ;; Basic tier plan
        u50000000  ;; 50 STX
        u2592000   ;; 30 days
        (list 
            "Basic Platform Access"
            "Standard Customer Support"
            "Core Feature Set"
        )
        u1  ;; Tier 1
        true ;; Allows refunds
    ))
    
    (try! (create-subscription-tier
        "premium-tier"  ;; Premium tier plan
        u100000000  ;; 100 STX
        u2592000    ;; 30 days
        (list 
            "Premium Platform Access"
            "24/7 Priority Support"
            "Complete Feature Set"
            "Advanced Analytics Dashboard"
        )
        u2  ;; Tier 2
        true ;; Allows refunds
    ))
)