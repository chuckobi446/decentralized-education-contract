;; Skill Verification System Smart Contract
;; Decentralized skill assessment and verifiable credential issuance
;; Enables peer-reviewed skill validation with blockchain certificates

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u300))
(define-constant ERR_NOT_FOUND (err u301))
(define-constant ERR_ALREADY_EXISTS (err u302))
(define-constant ERR_INVALID_ASSESSMENT (err u303))
(define-constant ERR_INSUFFICIENT_REVIEWERS (err u304))
(define-constant ERR_ASSESSMENT_EXPIRED (err u305))
(define-constant ERR_INVALID_CREDENTIAL (err u306))
(define-constant ERR_ALREADY_REVIEWED (err u307))

;; Skill Levels
(define-constant SKILL_BEGINNER u1)
(define-constant SKILL_INTERMEDIATE u2)
(define-constant SKILL_ADVANCED u3)
(define-constant SKILL_EXPERT u4)

;; Assessment Status
(define-constant STATUS_PENDING u1)
(define-constant STATUS_IN_REVIEW u2)
(define-constant STATUS_PASSED u3)
(define-constant STATUS_FAILED u4)
(define-constant STATUS_EXPIRED u5)

;; Data Variables
(define-data-var next-learner-id uint u1)
(define-data-var next-skill-id uint u1)
(define-data-var next-assessment-id uint u1)
(define-data-var next-credential-id uint u1)
(define-data-var min-peer-reviewers uint u3)
(define-data-var assessment-duration uint u604800) ;; 7 days in seconds
(define-data-var platform-active bool true)

;; Learner Profiles
(define-map learners
  { learner-id: uint }
  {
    learner-address: principal,
    name: (string-ascii 100),
    profile-data: (string-ascii 500),
    joined-at: uint,
    reputation-score: uint,
    completed-assessments: uint,
    active: bool
  }
)

;; Learner Address Mapping
(define-map learner-address-to-id
  { learner-address: principal }
  { learner-id: uint }
)

;; Skills Registry
(define-map skills
  { skill-id: uint }
  {
    skill-name: (string-ascii 100),
    description: (string-ascii 500),
    category: (string-ascii 50),
    created-by: principal,
    created-at: uint,
    assessment-count: uint,
    active: bool
  }
)

;; Skill Assessments
(define-map assessments
  { assessment-id: uint }
  {
    skill-id: uint,
    learner-id: uint,
    assessment-data: (string-ascii 1000), ;; IPFS hash or encrypted content
    submitted-at: uint,
    expires-at: uint,
    status: uint,
    required-level: uint,
    peer-reviews: uint,
    average-score: uint,
    passing-threshold: uint
  }
)

;; Peer Reviews
(define-map peer-reviews
  { assessment-id: uint, reviewer-id: uint }
  {
    reviewer-address: principal,
    score: uint, ;; 0-100
    feedback: (string-ascii 500),
    reviewed-at: uint,
    verified: bool
  }
)

;; Assessment Reviews Index
(define-map assessment-reviews
  { assessment-id: uint }
  { reviewer-ids: (list 10 uint) }
)

;; Credentials (NFT-like certificates)
(define-map credentials
  { credential-id: uint }
  {
    learner-id: uint,
    skill-id: uint,
    skill-level: uint,
    assessment-id: uint,
    issued-at: uint,
    issued-by: principal,
    expires-at: (optional uint),
    metadata: (string-ascii 500),
    active: bool
  }
)

;; Learner Credentials Index
(define-map learner-credentials
  { learner-id: uint }
  { credential-ids: (list 50 uint) }
)

;; Skill Credentials Index
(define-map skill-credentials
  { skill-id: uint }
  { credential-ids: (list 1000 uint) }
)

;; Public Functions

;; Register new learner
(define-public (register-learner (name (string-ascii 100)) (profile-data (string-ascii 500)))
  (let
    (
      (learner-id (var-get next-learner-id))
      (current-time (unwrap! (get-block-info? time (- block-height u1)) ERR_NOT_FOUND))
    )
    (asserts! (var-get platform-active) ERR_UNAUTHORIZED)
    (asserts! (is-none (map-get? learner-address-to-id { learner-address: tx-sender })) ERR_ALREADY_EXISTS)
    
    ;; Create learner profile
    (map-set learners
      { learner-id: learner-id }
      {
        learner-address: tx-sender,
        name: name,
        profile-data: profile-data,
        joined-at: current-time,
        reputation-score: u100, ;; Starting reputation
        completed-assessments: u0,
        active: true
      }
    )
    
    ;; Create address mapping
    (map-set learner-address-to-id
      { learner-address: tx-sender }
      { learner-id: learner-id }
    )
    
    ;; Initialize empty credentials list
    (map-set learner-credentials
      { learner-id: learner-id }
      { credential-ids: (list) }
    )
    
    ;; Increment learner ID
    (var-set next-learner-id (+ learner-id u1))
    
    (ok learner-id)
  )
)

;; Create skill definition
(define-public (create-skill (skill-name (string-ascii 100)) (description (string-ascii 500)) (category (string-ascii 50)))
  (let
    (
      (skill-id (var-get next-skill-id))
      (current-time (unwrap! (get-block-info? time (- block-height u1)) ERR_NOT_FOUND))
    )
    (asserts! (var-get platform-active) ERR_UNAUTHORIZED)
    
    ;; Create skill
    (map-set skills
      { skill-id: skill-id }
      {
        skill-name: skill-name,
        description: description,
        category: category,
        created-by: tx-sender,
        created-at: current-time,
        assessment-count: u0,
        active: true
      }
    )
    
    ;; Initialize empty credentials list for skill
    (map-set skill-credentials
      { skill-id: skill-id }
      { credential-ids: (list) }
    )
    
    ;; Increment skill ID
    (var-set next-skill-id (+ skill-id u1))
    
    (ok skill-id)
  )
)

;; Submit skill assessment
(define-public (submit-assessment 
  (skill-id uint)
  (assessment-data (string-ascii 1000))
  (required-level uint)
  (passing-threshold uint)
)
  (let
    (
      (learner-data (unwrap! (map-get? learner-address-to-id { learner-address: tx-sender }) ERR_NOT_FOUND))
      (learner-id (get learner-id learner-data))
      (assessment-id (var-get next-assessment-id))
      (current-time (unwrap! (get-block-info? time (- block-height u1)) ERR_NOT_FOUND))
      (expires-at (+ current-time (var-get assessment-duration)))
      (skill-info (unwrap! (map-get? skills { skill-id: skill-id }) ERR_NOT_FOUND))
    )
    (asserts! (var-get platform-active) ERR_UNAUTHORIZED)
    (asserts! (get active skill-info) ERR_NOT_FOUND)
    (asserts! (<= required-level SKILL_EXPERT) ERR_INVALID_ASSESSMENT)
    (asserts! (and (>= passing-threshold u50) (<= passing-threshold u100)) ERR_INVALID_ASSESSMENT)
    
    ;; Create assessment
    (map-set assessments
      { assessment-id: assessment-id }
      {
        skill-id: skill-id,
        learner-id: learner-id,
        assessment-data: assessment-data,
        submitted-at: current-time,
        expires-at: expires-at,
        status: STATUS_PENDING,
        required-level: required-level,
        peer-reviews: u0,
        average-score: u0,
        passing-threshold: passing-threshold
      }
    )
    
    ;; Initialize empty reviews list
    (map-set assessment-reviews
      { assessment-id: assessment-id }
      { reviewer-ids: (list) }
    )
    
    ;; Update skill assessment count
    (map-set skills
      { skill-id: skill-id }
      (merge skill-info { assessment-count: (+ (get assessment-count skill-info) u1) })
    )
    
    ;; Increment assessment ID
    (var-set next-assessment-id (+ assessment-id u1))
    
    (ok assessment-id)
  )
)

;; Peer review assessment
(define-public (peer-review-assessment 
  (assessment-id uint)
  (score uint)
  (feedback (string-ascii 500))
)
  (let
    (
      (reviewer-data (unwrap! (map-get? learner-address-to-id { learner-address: tx-sender }) ERR_NOT_FOUND))
      (reviewer-id (get learner-id reviewer-data))
      (assessment-info (unwrap! (map-get? assessments { assessment-id: assessment-id }) ERR_NOT_FOUND))
      (current-time (unwrap! (get-block-info? time (- block-height u1)) ERR_NOT_FOUND))
      (existing-reviews (default-to (list) (get reviewer-ids (map-get? assessment-reviews { assessment-id: assessment-id }))))
    )
    (asserts! (var-get platform-active) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status assessment-info) STATUS_PENDING) ERR_INVALID_ASSESSMENT)
    (asserts! (< current-time (get expires-at assessment-info)) ERR_ASSESSMENT_EXPIRED)
    (asserts! (not (is-eq (get learner-id assessment-info) reviewer-id)) ERR_UNAUTHORIZED)
    (asserts! (and (>= score u0) (<= score u100)) ERR_INVALID_ASSESSMENT)
    (asserts! (is-none (map-get? peer-reviews { assessment-id: assessment-id, reviewer-id: reviewer-id })) ERR_ALREADY_REVIEWED)
    
    ;; Add peer review
    (map-set peer-reviews
      { assessment-id: assessment-id, reviewer-id: reviewer-id }
      {
        reviewer-address: tx-sender,
        score: score,
        feedback: feedback,
        reviewed-at: current-time,
        verified: true
      }
    )
    
    ;; Update review index
    (map-set assessment-reviews
      { assessment-id: assessment-id }
      { reviewer-ids: (unwrap! (as-max-len? (append existing-reviews reviewer-id) u10) ERR_NOT_FOUND) }
    )
    
    ;; Update assessment with new review count
    (let ((new-review-count (+ (get peer-reviews assessment-info) u1)))
      (map-set assessments
        { assessment-id: assessment-id }
        (merge assessment-info { 
          peer-reviews: new-review-count,
          status: (if (>= new-review-count (var-get min-peer-reviewers)) STATUS_IN_REVIEW STATUS_PENDING)
        })
      )
    )
    
    ;; Check if ready for credential issuance
    (try! (process-assessment-completion assessment-id))
    
    (ok true)
  )
)

;; Issue credential after successful assessment
(define-public (issue-credential (assessment-id uint))
  (let
    (
      (assessment-info (unwrap! (map-get? assessments { assessment-id: assessment-id }) ERR_NOT_FOUND))
      (credential-id (var-get next-credential-id))
      (current-time (unwrap! (get-block-info? time (- block-height u1)) ERR_NOT_FOUND))
      (learner-id (get learner-id assessment-info))
      (skill-id (get skill-id assessment-info))
      (existing-credentials (default-to (list) (get credential-ids (map-get? learner-credentials { learner-id: learner-id }))))
      (skill-credentials-list (default-to (list) (get credential-ids (map-get? skill-credentials { skill-id: skill-id }))))
    )
    (asserts! (var-get platform-active) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status assessment-info) STATUS_PASSED) ERR_INVALID_CREDENTIAL)
    
    ;; Create credential
    (map-set credentials
      { credential-id: credential-id }
      {
        learner-id: learner-id,
        skill-id: skill-id,
        skill-level: (get required-level assessment-info),
        assessment-id: assessment-id,
        issued-at: current-time,
        issued-by: tx-sender,
        expires-at: none, ;; No expiration for now
        metadata: "Blockchain-verified skill credential",
        active: true
      }
    )
    
    ;; Update learner credentials index
    (map-set learner-credentials
      { learner-id: learner-id }
      { credential-ids: (unwrap! (as-max-len? (append existing-credentials credential-id) u50) ERR_NOT_FOUND) }
    )
    
    ;; Update skill credentials index
    (map-set skill-credentials
      { skill-id: skill-id }
      { credential-ids: (unwrap! (as-max-len? (append skill-credentials-list credential-id) u1000) ERR_NOT_FOUND) }
    )
    
    ;; Increment credential ID
    (var-set next-credential-id (+ credential-id u1))
    
    (ok credential-id)
  )
)

;; Read-Only Functions

;; Get learner profile
(define-read-only (get-learner-profile (learner-id uint))
  (map-get? learners { learner-id: learner-id })
)

;; Get skill information
(define-read-only (get-skill-info (skill-id uint))
  (map-get? skills { skill-id: skill-id })
)

;; Get assessment details
(define-read-only (get-assessment-details (assessment-id uint))
  (map-get? assessments { assessment-id: assessment-id })
)

;; Get learner credentials
(define-read-only (get-learner-credentials (learner-id uint))
  (map-get? learner-credentials { learner-id: learner-id })
)

;; Get credential details
(define-read-only (get-credential-details (credential-id uint))
  (map-get? credentials { credential-id: credential-id })
)

;; Verify credential
(define-read-only (verify-credential (credential-id uint))
  (let
    ((credential-info (map-get? credentials { credential-id: credential-id })))
    (if (is-some credential-info)
      (let ((cred (unwrap-panic credential-info)))
        (get active cred)
      )
      false
    )
  )
)

;; Get learner ID by address
(define-read-only (get-learner-id (learner-address principal))
  (map-get? learner-address-to-id { learner-address: learner-address })
)

;; Private Functions

;; Process assessment completion
(define-private (process-assessment-completion (assessment-id uint))
  (let
    (
      (assessment-info (unwrap! (map-get? assessments { assessment-id: assessment-id }) ERR_NOT_FOUND))
      (review-count (get peer-reviews assessment-info))
    )
    (if (>= review-count (var-get min-peer-reviewers))
      (let
        (
          (average-score (calculate-average-score assessment-id review-count))
          (passed (>= average-score (get passing-threshold assessment-info)))
        )
        ;; Update assessment with final status
        (map-set assessments
          { assessment-id: assessment-id }
          (merge assessment-info {
            status: (if passed STATUS_PASSED STATUS_FAILED),
            average-score: average-score
          })
        )
        (ok true)
      )
      (ok false)
    )
  )
)

;; Calculate average score from peer reviews
(define-private (calculate-average-score (assessment-id uint) (review-count uint))
  ;; Simplified calculation - in production, this would iterate through all reviews
  u75 ;; Placeholder average score
)

;; Admin Functions

;; Set minimum peer reviewers
(define-public (set-min-peer-reviewers (count uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (and (>= count u1) (<= count u10)) ERR_INVALID_ASSESSMENT)
    (var-set min-peer-reviewers count)
    (ok true)
  )
)

;; Toggle platform status
(define-public (toggle-platform)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set platform-active (not (var-get platform-active)))
    (ok (var-get platform-active))
  )
)

