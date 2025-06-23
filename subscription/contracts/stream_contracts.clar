;; SubscriptionNexus - Dynamic Service Payment Streams Contract v2.0
;; Enables flexible subscription payments with real-time billing adjustments

(define-constant SERVICE_ADMIN tx-sender)
(define-constant ERR_PERMISSION_DENIED (err u400))
(define-constant ERR_SUBSCRIPTION_NOT_FOUND (err u401))
(define-constant ERR_INSUFFICIENT_CREDIT (err u402))
(define-constant ERR_SUBSCRIPTION_EXISTS (err u403))
(define-constant ERR_INVALID_BILLING (err u404))
(define-constant ERR_SERVICE_TERMINATED (err u405))
(define-constant ERR_BILLING_SUSPENDED (err u406))

;; Subscription service data structure
(define-map service-subscriptions
  { subscription-id: uint }
  {
    provider: principal,
    subscriber: principal,
    billing-rate: uint,          ;; Cost per second of service usage
    service-activation: uint,    ;; When subscription became active
    billing-cycle-end: (optional uint), ;; Optional subscription end date
    total-prepaid: uint,         ;; Total amount prepaid for service
    charges-processed: uint,     ;; Amount already charged to subscriber
    service-active: bool,        ;; Service availability status
    billing-suspended: bool,     ;; Billing suspension status
    suspension-time: (optional uint) ;; When billing was suspended
  }
)

;; Track account credits for users
(define-map account-credits
  { account-holder: principal }
  { credit-balance: uint }
)

;; Track subscription counter
(define-data-var subscription-counter uint u0)

;; Track subscription statistics per user
(define-map user-subscription-metrics
  { user: principal }
  { provided-services: uint, active-subscriptions: uint }
)

;; Map users to their subscription IDs
(define-map provider-service-catalog
  { provider: principal, service-index: uint }
  { subscription-id: uint }
)

(define-map subscriber-service-list
  { subscriber: principal, subscription-index: uint }
  { subscription-id: uint }
)

;; Get current time reference
(define-read-only (get-time-reference)
  block-height
)

;; Get account credit balance
(define-read-only (get-credit-balance (account-holder principal))
  (default-to u0 (get credit-balance (map-get? account-credits { account-holder: account-holder })))
)

;; Get subscription information
(define-read-only (get-subscription-info (subscription-id uint))
  (map-get? service-subscriptions { subscription-id: subscription-id })
)

;; Calculate outstanding charges for billing
(define-read-only (calculate-outstanding-charges (subscription-id uint))
  (match (map-get? service-subscriptions { subscription-id: subscription-id })
    subscription-data
    (let (
      (current-time (get-time-reference))
      (activation-time (get service-activation subscription-data))
      (cycle-end (get billing-cycle-end subscription-data))
      (rate (get billing-rate subscription-data))
      (processed (get charges-processed subscription-data))
      (prepaid (get total-prepaid subscription-data))
      (active (get service-active subscription-data))
      (suspended (get billing-suspended subscription-data))
      (suspension-time (get suspension-time subscription-data))
    )
    (if (and active (not suspended))
      (let (
        (effective-end (match cycle-end
          some-end some-end
          current-time))
        (actual-end (if (> effective-end current-time) current-time effective-end))
        (usage-duration (if (>= actual-end activation-time) (- actual-end activation-time) u0))
        (total-charges (* usage-duration rate))
        (outstanding (if (> total-charges processed) (- total-charges processed) u0))
        (max-billable (if (> prepaid processed) (- prepaid processed) u0))
      )
      (if (< outstanding max-billable) outstanding max-billable))
      u0))
    u0)
)

;; Add credits to account
(define-public (add-credits (amount uint))
  (let (
    (current-credits (get-credit-balance tx-sender))
    (new-balance (+ current-credits amount))
  )
  (map-set account-credits
    { account-holder: tx-sender }
    { credit-balance: new-balance }
  )
  (ok new-balance))
)

;; Withdraw credits from account
(define-public (withdraw-credits (amount uint))
  (let (
    (current-credits (get-credit-balance tx-sender))
  )
  (if (>= current-credits amount)
    (begin
      (map-set account-credits
        { account-holder: tx-sender }
        { credit-balance: (- current-credits amount) }
      )
      (ok (- current-credits amount)))
    ERR_INSUFFICIENT_CREDIT))
)

;; Activate new service subscription
(define-public (activate-subscription 
  (subscriber principal) 
  (billing-rate uint) 
  (prepaid-amount uint)
  (cycle-duration (optional uint)))
  (let (
    (subscription-id (+ (var-get subscription-counter) u1))
    (provider-credits (get-credit-balance tx-sender))
    (current-time (get-time-reference))
    (cycle-end (match cycle-duration
      some-duration (some (+ current-time some-duration))
      none))
    (provider-metrics (default-to { provided-services: u0, active-subscriptions: u0 } 
                   (map-get? user-subscription-metrics { user: tx-sender })))
    (subscriber-metrics (default-to { provided-services: u0, active-subscriptions: u0 } 
                      (map-get? user-subscription-metrics { user: subscriber })))
  )
  (asserts! (> billing-rate u0) ERR_INVALID_BILLING)
  (asserts! (> prepaid-amount u0) ERR_INVALID_BILLING)
  (asserts! (>= provider-credits prepaid-amount) ERR_INSUFFICIENT_CREDIT)
  (asserts! (is-none (map-get? service-subscriptions { subscription-id: subscription-id })) ERR_SUBSCRIPTION_EXISTS)
  
  ;; Process prepayment from provider credits
  (map-set account-credits
    { account-holder: tx-sender }
    { credit-balance: (- provider-credits prepaid-amount) }
  )
  
  ;; Create subscription record
  (map-set service-subscriptions
    { subscription-id: subscription-id }
    {
      provider: tx-sender,
      subscriber: subscriber,
      billing-rate: billing-rate,
      service-activation: current-time,
      billing-cycle-end: cycle-end,
      total-prepaid: prepaid-amount,
      charges-processed: u0,
      service-active: true,
      billing-suspended: false,
      suspension-time: none
    }
  )
  
  ;; Update subscription counter
  (var-set subscription-counter subscription-id)
  
  ;; Update user subscription mappings
  (map-set provider-service-catalog
    { provider: tx-sender, service-index: (get provided-services provider-metrics) }
    { subscription-id: subscription-id }
  )
  
  (map-set subscriber-service-list
    { subscriber: subscriber, subscription-index: (get active-subscriptions subscriber-metrics) }
    { subscription-id: subscription-id }
  )
  
  ;; Update subscription metrics
  (map-set user-subscription-metrics
    { user: tx-sender }
    { provided-services: (+ (get provided-services provider-metrics) u1), 
      active-subscriptions: (get active-subscriptions provider-metrics) }
  )
  
  (map-set user-subscription-metrics
    { user: subscriber }
    { provided-services: (get provided-services subscriber-metrics), 
      active-subscriptions: (+ (get active-subscriptions subscriber-metrics) u1) }
  )
  
  (ok subscription-id)))

;; Process billing for service usage
(define-public (process-billing (subscription-id uint))
  (match (map-get? service-subscriptions { subscription-id: subscription-id })
    subscription-data
    (let (
      (provider (get provider subscription-data))
      (outstanding-amount (calculate-outstanding-charges subscription-id))
      (current-processed (get charges-processed subscription-data))
      (provider-credits (get-credit-balance provider))
    )
    (asserts! (is-eq tx-sender provider) ERR_PERMISSION_DENIED)
    (asserts! (get service-active subscription-data) ERR_SERVICE_TERMINATED)
    (asserts! (> outstanding-amount u0) ERR_INSUFFICIENT_CREDIT)
    
    ;; Update subscription processed charges
    (map-set service-subscriptions
      { subscription-id: subscription-id }
      (merge subscription-data { charges-processed: (+ current-processed outstanding-amount) })
    )
    
    ;; Add billing amount to provider credits
    (map-set account-credits
      { account-holder: provider }
      { credit-balance: (+ provider-credits outstanding-amount) }
    )
    
    (ok outstanding-amount))
    ERR_SUBSCRIPTION_NOT_FOUND)
)

;; Suspend billing (provider only)
(define-public (suspend-billing (subscription-id uint))
  (match (map-get? service-subscriptions { subscription-id: subscription-id })
    subscription-data
    (let (
      (provider (get provider subscription-data))
      (current-time (get-time-reference))
    )
    (asserts! (is-eq tx-sender provider) ERR_PERMISSION_DENIED)
    (asserts! (get service-active subscription-data) ERR_SERVICE_TERMINATED)
    (asserts! (not (get billing-suspended subscription-data)) ERR_BILLING_SUSPENDED)
    
    (map-set service-subscriptions
      { subscription-id: subscription-id }
      (merge subscription-data { 
        billing-suspended: true,
        suspension-time: (some current-time)
      })
    )
    
    (ok true))
    ERR_SUBSCRIPTION_NOT_FOUND)
)

;; Resume billing (provider only)
(define-public (resume-billing (subscription-id uint))
  (match (map-get? service-subscriptions { subscription-id: subscription-id })
    subscription-data
    (let (
      (provider (get provider subscription-data))
      (current-time (get-time-reference))
      (suspension-time (get suspension-time subscription-data))
    )
    (asserts! (is-eq tx-sender provider) ERR_PERMISSION_DENIED)
    (asserts! (get service-active subscription-data) ERR_SERVICE_TERMINATED)
    (asserts! (get billing-suspended subscription-data) ERR_BILLING_SUSPENDED)
    
    ;; Adjust activation time for suspended period
    (let (
      (suspended-duration (match suspension-time
        some-suspension-time (- current-time some-suspension-time)
        u0))
      (new-activation-time (+ (get service-activation subscription-data) suspended-duration))
      (new-cycle-end (match (get billing-cycle-end subscription-data)
        some-end (some (+ some-end suspended-duration))
        none))
    )
    
    (map-set service-subscriptions
      { subscription-id: subscription-id }
      (merge subscription-data { 
        billing-suspended: false,
        suspension-time: none,
        service-activation: new-activation-time,
        billing-cycle-end: new-cycle-end
      })
    )
    
    (ok true)))
    ERR_SUBSCRIPTION_NOT_FOUND)
)

;; Terminate subscription and settle accounts
(define-public (terminate-subscription (subscription-id uint))
  (match (map-get? service-subscriptions { subscription-id: subscription-id })
    subscription-data
    (let (
      (provider (get provider subscription-data))
      (outstanding-for-provider (calculate-outstanding-charges subscription-id))
      (total-prepaid (get total-prepaid subscription-data))
      (processed (get charges-processed subscription-data))
      (refund-amount (if (> (- total-prepaid processed) outstanding-for-provider)
                       (- (- total-prepaid processed) outstanding-for-provider)
                       u0))
      (provider-credits (get-credit-balance provider))
      (subscriber-credits (get-credit-balance (get subscriber subscription-data)))
    )
    (asserts! (is-eq tx-sender provider) ERR_PERMISSION_DENIED)
    (asserts! (get service-active subscription-data) ERR_SERVICE_TERMINATED)
    
    ;; Mark subscription as terminated
    (map-set service-subscriptions
      { subscription-id: subscription-id }
      (merge subscription-data { service-active: false })
    )
    
    ;; Refund unused prepayment to subscriber
    (if (> refund-amount u0)
      (map-set account-credits
        { account-holder: (get subscriber subscription-data) }
        { credit-balance: (+ subscriber-credits refund-amount) })
      true)
    
    ;; Give outstanding charges to provider
    (if (> outstanding-for-provider u0)
      (begin
        (map-set account-credits
          { account-holder: provider }
          { credit-balance: (+ provider-credits outstanding-for-provider) })
        (map-set service-subscriptions
          { subscription-id: subscription-id }
          (merge subscription-data { 
            charges-processed: (+ processed outstanding-for-provider),
            service-active: false 
          })))
      true)
    
    (ok { refunded: refund-amount, final-billing: outstanding-for-provider }))
    ERR_SUBSCRIPTION_NOT_FOUND)
)

;; Extend subscription with additional prepayment
(define-public (extend-subscription (subscription-id uint) (additional-prepayment uint))
  (match (map-get? service-subscriptions { subscription-id: subscription-id })
    subscription-data
    (let (
      (provider (get provider subscription-data))
      (provider-credits (get-credit-balance provider))
      (current-prepaid (get total-prepaid subscription-data))
    )
    (asserts! (is-eq tx-sender provider) ERR_PERMISSION_DENIED)
    (asserts! (get service-active subscription-data) ERR_SERVICE_TERMINATED)
    (asserts! (>= provider-credits additional-prepayment) ERR_INSUFFICIENT_CREDIT)
    (asserts! (> additional-prepayment u0) ERR_INVALID_BILLING)
    
    ;; Deduct from provider credits
    (map-set account-credits
      { account-holder: provider }
      { credit-balance: (- provider-credits additional-prepayment) }
    )
    
    ;; Update subscription prepayment
    (map-set service-subscriptions
      { subscription-id: subscription-id }
      (merge subscription-data { total-prepaid: (+ current-prepaid additional-prepayment) })
    )
    
    (ok (+ current-prepaid additional-prepayment)))
    ERR_SUBSCRIPTION_NOT_FOUND)
)

;; Get user subscription metrics
(define-read-only (get-user-metrics (user principal))
  (default-to { provided-services: u0, active-subscriptions: u0 }
    (map-get? user-subscription-metrics { user: user }))
)

;; Get subscription ID by provider and index
(define-read-only (get-provider-service (provider principal) (index uint))
  (map-get? provider-service-catalog { provider: provider, service-index: index })
)

;; Get subscription ID by subscriber and index
(define-read-only (get-subscriber-service (subscriber principal) (index uint))
  (map-get? subscriber-service-list { subscriber: subscriber, subscription-index: index })
)

;; Get total subscription count
(define-read-only (get-total-subscriptions)
  (var-get subscription-counter)
)

;; Check if subscription cycle has ended
(define-read-only (has-cycle-ended (subscription-id uint))
  (match (map-get? service-subscriptions { subscription-id: subscription-id })
    subscription-data
    (let (
      (current-time (get-time-reference))
      (cycle-end (get billing-cycle-end subscription-data))
    )
    (or 
      (not (get service-active subscription-data))
      (match cycle-end
        some-end (>= current-time some-end)
        false)
      (>= (get charges-processed subscription-data) (get total-prepaid subscription-data))))
    false)
)