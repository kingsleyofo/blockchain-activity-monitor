;; activity-monitor
;; 
;; This contract implements a comprehensive blockchain activity monitoring system
;; that enables users to create and manage custom monitoring profiles for tracking
;; on-chain activities. Users can define specific conditions and thresholds to monitor
;; transactions, contract calls, wallet activities, and receive notifications when
;; their conditions are met.

;; Error codes
(define-constant err-not-authorized (err u100))
(define-constant err-profile-not-found (err u101))
(define-constant err-profile-exists (err u102))
(define-constant err-invalid-parameters (err u103))
(define-constant err-profile-inactive (err u104))
(define-constant err-condition-not-found (err u105))

;; Activity types
(define-constant activity-type-tx u1)
(define-constant activity-type-contract-call u2)
(define-constant activity-type-token-transfer u3)
(define-constant activity-type-wallet-activity u4)

;; Data structures

;; Map to store monitoring profiles by profile ID
(define-map monitoring-profiles
  { profile-id: uint }
  {
    owner: principal,
    name: (string-ascii 50),
    description: (string-ascii 200),
    created-at: uint,
    active: bool,
    notification-endpoint: (optional (string-ascii 100))
  }
)

;; Map to store monitoring conditions for each profile
(define-map profile-conditions
  { profile-id: uint, condition-id: uint }
  {
    activity-type: uint,
    address: (optional principal),
    contract-name: (optional (string-ascii 128)),
    function-name: (optional (string-ascii 128)),
    min-amount: (optional uint),
    max-amount: (optional uint),
    token-id: (optional (string-ascii 50))
  }
)

;; Map to store activity matches (events that matched conditions)
(define-map activity-matches
  { profile-id: uint, match-id: uint }
  {
    condition-id: uint,
    tx-id: (string-ascii 64),
    matched-at: uint,
    notified: bool,
    details: (string-ascii 200)
  }
)

;; Counter for profile IDs
(define-data-var next-profile-id uint u1)

;; Counter for condition IDs (per profile)
(define-map next-condition-id { profile-id: uint } { id: uint })

;; Counter for match IDs (per profile)
(define-map next-match-id { profile-id: uint } { id: uint })

;; Private functions

;; Get the next available profile ID and increment the counter
(define-private (get-next-profile-id)
  (let ((current-id (var-get next-profile-id)))
    (var-set next-profile-id (+ current-id u1))
    current-id
  )
)

;; Get the next available condition ID for a profile and increment the counter
(define-private (get-next-condition-id (profile-id uint))
  (let ((current-id-map (default-to { id: u1 } (map-get? next-condition-id { profile-id: profile-id }))))
    (let ((current-id (get id current-id-map)))
      (map-set next-condition-id { profile-id: profile-id } { id: (+ current-id u1) })
      current-id
    )
  )
)

;; Get the next available match ID for a profile and increment the counter
(define-private (get-next-match-id (profile-id uint))
  (let ((current-id-map (default-to { id: u1 } (map-get? next-match-id { profile-id: profile-id }))))
    (let ((current-id (get id current-id-map)))
      (map-set next-match-id { profile-id: profile-id } { id: (+ current-id u1) })
      current-id
    )
  )
)

;; Check if the caller is the owner of a profile
(define-private (is-profile-owner (profile-id uint))
  (let ((profile (map-get? monitoring-profiles { profile-id: profile-id })))
    (if (is-some profile)
      (is-eq tx-sender (get owner (unwrap-panic profile)))
      false
    )
  )
)

;; Public functions

;; Create a new monitoring profile
(define-public (create-profile 
    (name (string-ascii 50)) 
    (description (string-ascii 200))
    (notification-endpoint (optional (string-ascii 100))))
  (let ((profile-id (get-next-profile-id)))
    (map-set monitoring-profiles 
      { profile-id: profile-id }
      {
        owner: tx-sender,
        name: name,
        description: description,
        created-at: block-height,
        active: true,
        notification-endpoint: notification-endpoint
      }
    )
    (map-set next-condition-id { profile-id: profile-id } { id: u1 })
    (map-set next-match-id { profile-id: profile-id } { id: u1 })
    (ok profile-id)
  )
)

;; Update an existing monitoring profile
(define-public (update-profile 
    (profile-id uint) 
    (name (string-ascii 50)) 
    (description (string-ascii 200))
    (notification-endpoint (optional (string-ascii 100))))
  (let ((profile (map-get? monitoring-profiles { profile-id: profile-id })))
    (if (is-none profile)
      err-profile-not-found
      (if (not (is-eq tx-sender (get owner (unwrap-panic profile))))
        err-not-authorized
        (begin
          (map-set monitoring-profiles 
            { profile-id: profile-id }
            {
              owner: tx-sender,
              name: name,
              description: description,
              created-at: (get created-at (unwrap-panic profile)),
              active: (get active (unwrap-panic profile)),
              notification-endpoint: notification-endpoint
            }
          )
          (ok true)
        )
      )
    )
  )
)

;; Activate or deactivate a monitoring profile
(define-public (set-profile-status (profile-id uint) (active bool))
  (let ((profile (map-get? monitoring-profiles { profile-id: profile-id })))
    (if (is-none profile)
      err-profile-not-found
      (if (not (is-eq tx-sender (get owner (unwrap-panic profile))))
        err-not-authorized
        (begin
          (map-set monitoring-profiles 
            { profile-id: profile-id }
            (merge (unwrap-panic profile) { active: active })
          )
          (ok true)
        )
      )
    )
  )
)

;; Add a new condition to a monitoring profile
(define-public (add-condition
    (profile-id uint)
    (activity-type uint)
    (address (optional principal))
    (contract-name (optional (string-ascii 128)))
    (function-name (optional (string-ascii 128)))
    (min-amount (optional uint))
    (max-amount (optional uint))
    (token-id (optional (string-ascii 50))))
  (let ((profile (map-get? monitoring-profiles { profile-id: profile-id })))
    (if (is-none profile)
      err-profile-not-found
      (if (not (is-eq tx-sender (get owner (unwrap-panic profile))))
        err-not-authorized
        (let ((condition-id (get-next-condition-id profile-id)))
          (map-set profile-conditions
            { profile-id: profile-id, condition-id: condition-id }
            {
              activity-type: activity-type,
              address: address,
              contract-name: contract-name,
              function-name: function-name,
              min-amount: min-amount,
              max-amount: max-amount,
              token-id: token-id
            }
          )
          (ok condition-id)
        )
      )
    )
  )
)

;; Update an existing condition
(define-public (update-condition
    (profile-id uint)
    (condition-id uint)
    (activity-type uint)
    (address (optional principal))
    (contract-name (optional (string-ascii 128)))
    (function-name (optional (string-ascii 128)))
    (min-amount (optional uint))
    (max-amount (optional uint))
    (token-id (optional (string-ascii 50))))
  (let ((profile (map-get? monitoring-profiles { profile-id: profile-id })))
    (if (is-none profile)
      err-profile-not-found
      (if (not (is-eq tx-sender (get owner (unwrap-panic profile))))
        err-not-authorized
        (let ((condition (map-get? profile-conditions { profile-id: profile-id, condition-id: condition-id })))
          (if (is-none condition)
            err-condition-not-found
            (begin
              (map-set profile-conditions
                { profile-id: profile-id, condition-id: condition-id }
                {
                  activity-type: activity-type,
                  address: address,
                  contract-name: contract-name,
                  function-name: function-name,
                  min-amount: min-amount,
                  max-amount: max-amount,
                  token-id: token-id
                }
              )
              (ok true)
            )
          )
        )
      )
    )
  )
)

;; Delete a condition from a monitoring profile
(define-public (delete-condition (profile-id uint) (condition-id uint))
  (let ((profile (map-get? monitoring-profiles { profile-id: profile-id })))
    (if (is-none profile)
      err-profile-not-found
      (if (not (is-eq tx-sender (get owner (unwrap-panic profile))))
        err-not-authorized
        (let ((condition (map-get? profile-conditions { profile-id: profile-id, condition-id: condition-id })))
          (if (is-none condition)
            err-condition-not-found
            (begin
              (map-delete profile-conditions { profile-id: profile-id, condition-id: condition-id })
              (ok true)
            )
          )
        )
      )
    )
  )
)

;; Record an activity match (This would typically be called by an oracle or authorized entity)
(define-public (record-activity-match
    (profile-id uint)
    (condition-id uint)
    (tx-id (string-ascii 64))
    (details (string-ascii 200)))
  (let ((profile (map-get? monitoring-profiles { profile-id: profile-id })))
    (if (is-none profile)
      err-profile-not-found
      (if (not (get active (unwrap-panic profile)))
        err-profile-inactive
        (let ((condition (map-get? profile-conditions { profile-id: profile-id, condition-id: condition-id })))
          (if (is-none condition)
            err-condition-not-found
            (let ((match-id (get-next-match-id profile-id)))
              (map-set activity-matches
                { profile-id: profile-id, match-id: match-id }
                {
                  condition-id: condition-id,
                  tx-id: tx-id,
                  matched-at: block-height,
                  notified: false,
                  details: details
                }
              )
              (ok match-id)
            )
          )
        )
      )
    )
  )
)

;; Mark a match as notified
(define-public (mark-match-notified (profile-id uint) (match-id uint))
  (let ((profile (map-get? monitoring-profiles { profile-id: profile-id })))
    (if (is-none profile)
      err-profile-not-found
      (if (not (is-eq tx-sender (get owner (unwrap-panic profile))))
        err-not-authorized
        (let ((match (map-get? activity-matches { profile-id: profile-id, match-id: match-id })))
          (if (is-none match)
            (err u106) ;; Match not found
            (begin
              (map-set activity-matches
                { profile-id: profile-id, match-id: match-id }
                (merge (unwrap-panic match) { notified: true })
              )
              (ok true)
            )
          )
        )
      )
    )
  )
)

;; Read-only functions

;; Get profile details
(define-read-only (get-profile (profile-id uint))
  (map-get? monitoring-profiles { profile-id: profile-id })
)

;; Get condition details
(define-read-only (get-condition (profile-id uint) (condition-id uint))
  (map-get? profile-conditions { profile-id: profile-id, condition-id: condition-id })
)

;; Get match details
(define-read-only (get-match (profile-id uint) (match-id uint))
  (map-get? activity-matches { profile-id: profile-id, match-id: match-id })
)

;; Check if a profile exists
(define-read-only (profile-exists (profile-id uint))
  (is-some (map-get? monitoring-profiles { profile-id: profile-id }))
)

;; Check if the caller is the owner of a profile
(define-read-only (is-owner (profile-id uint))
  (is-profile-owner profile-id)
)

;; Get profile ID by profile name and owner
;; Note: This is an inefficient lookup since Clarity doesn't support indexing
;; In a production environment, consider alternative approaches
(define-read-only (get-profile-id-by-name (owner principal) (name (string-ascii 50)))
  (let ((profile-id (var-get next-profile-id)))
    (match-profile-by-name owner name u1 profile-id)
  )
)

;; Helper function to search for a profile by name and owner
(define-private (match-profile-by-name (owner principal) (name (string-ascii 50)) (current-id uint) (max-id uint))
  (if (> current-id max-id)
    none
    (let ((profile (map-get? monitoring-profiles { profile-id: current-id })))
      (if (and 
            (is-some profile) 
            (is-eq owner (get owner (unwrap-panic profile)))
            (is-eq name (get name (unwrap-panic profile))))
        (some current-id)
        (match-profile-by-name owner name (+ current-id u1) max-id)
      )
    )
  )
)