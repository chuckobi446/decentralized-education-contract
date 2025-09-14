;; Knowledge Monetization Platform Smart Contract
;; Educator compensation and student incentive distribution for learning achievements
;; Enables direct monetization of educational content and instruction

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u400))
(define-constant ERR_NOT_FOUND (err u401))
(define-constant ERR_ALREADY_EXISTS (err u402))
(define-constant ERR_INSUFFICIENT_PAYMENT (err u403))
(define-constant ERR_INVALID_COURSE (err u404))
(define-constant ERR_NOT_ENROLLED (err u405))
(define-constant ERR_COURSE_INACTIVE (err u406))
(define-constant ERR_INVALID_PROGRESS (err u407))

;; Course Types
(define-constant COURSE_FREE u0)
(define-constant COURSE_PAID u1)
(define-constant COURSE_SUBSCRIPTION u2)

;; Enrollment Status
(define-constant ENROLLMENT_ACTIVE u1)
(define-constant ENROLLMENT_COMPLETED u2)
(define-constant ENROLLMENT_EXPIRED u3)
(define-constant ENROLLMENT_REFUNDED u4)

;; Data Variables
(define-data-var next-educator-id uint u1)
(define-data-var next-course-id uint u1)
(define-data-var next-enrollment-id uint u1)
(define-data-var platform-fee-percentage uint u500) ;; 5%
(define-data-var min-completion-rate uint u70) ;; 70% minimum for rewards
(define-data-var platform-active bool true)

;; Educator Profiles
(define-map educators
  { educator-id: uint }
  {
    educator-address: principal,
    name: (string-ascii 100),
    bio: (string-ascii 500),
    credentials: (string-ascii 300),
    specialties: (list 10 (string-ascii 50)),
    joined-at: uint,
    total-earnings: uint,
    course-count: uint,
    student-count: uint,
    rating-average: uint,
    active: bool
  }
)

;; Educator Address Mapping
(define-map educator-address-to-id
  { educator-address: principal }
  { educator-id: uint }
)

;; Course Catalog
(define-map courses
  { course-id: uint }
  {
    educator-id: uint,
    title: (string-ascii 100),
    description: (string-ascii 1000),
    category: (string-ascii 50),
    course-type: uint,
    price-microSTX: uint,
    duration-hours: uint,
    lesson-count: uint,
    created-at: uint,
    updated-at: uint,
    enrollment-count: uint,
    completion-count: uint,
    active: bool,
    content-hash: (string-ascii 64) ;; IPFS hash for course materials
  }
)

;; Student Enrollments
(define-map enrollments
  { enrollment-id: uint }
  {
    course-id: uint,
    student-address: principal,
    enrolled-at: uint,
    expires-at: (optional uint),
    payment-amount: uint,
    status: uint,
    progress-percentage: uint,
    lessons-completed: uint,
    last-activity: uint
  }
)

;; Course Enrollments Index
(define-map course-enrollments
  { course-id: uint }
  { enrollment-ids: (list 1000 uint) }
)

;; Student Enrollments Index
(define-map student-enrollments
  { student-address: principal }
  { enrollment-ids: (list 100 uint) }
)

;; Learning Progress Tracking
(define-map lesson-progress
  { enrollment-id: uint, lesson-id: uint }
  {
    completed-at: uint,
    time-spent: uint,
    score: (optional uint),
    notes: (optional (string-ascii 500))
  }
)

;; Educator Earnings
(define-map educator-earnings
  { educator-id: uint }
  {
    total-revenue: uint,
    platform-fees: uint,
    net-earnings: uint,
    pending-withdrawal: uint,
    last-payout: uint
  }
)

;; Course Reviews and Ratings
(define-map course-reviews
  { course-id: uint, student-address: principal }
  {
    rating: uint, ;; 1-5 stars
    review: (string-ascii 500),
    created-at: uint,
    helpful-votes: uint
  }
)

;; Platform Statistics
(define-map platform-stats
  { stat-key: (string-ascii 20) }
  { value: uint }
)

;; Public Functions

;; Register educator
(define-public (register-educator 
  (name (string-ascii 100))
  (bio (string-ascii 500))
  (credentials (string-ascii 300))
  (specialties (list 10 (string-ascii 50)))
)
  (let
    (
      (educator-id (var-get next-educator-id))
      (current-time (unwrap! (get-block-info? time (- block-height u1)) ERR_NOT_FOUND))
    )
    (asserts! (var-get platform-active) ERR_UNAUTHORIZED)
    (asserts! (is-none (map-get? educator-address-to-id { educator-address: tx-sender })) ERR_ALREADY_EXISTS)
    
    ;; Create educator profile
    (map-set educators
      { educator-id: educator-id }
      {
        educator-address: tx-sender,
        name: name,
        bio: bio,
        credentials: credentials,
        specialties: specialties,
        joined-at: current-time,
        total-earnings: u0,
        course-count: u0,
        student-count: u0,
        rating-average: u0,
        active: true
      }
    )
    
    ;; Create address mapping
    (map-set educator-address-to-id
      { educator-address: tx-sender }
      { educator-id: educator-id }
    )
    
    ;; Initialize earnings tracking
    (map-set educator-earnings
      { educator-id: educator-id }
      {
        total-revenue: u0,
        platform-fees: u0,
        net-earnings: u0,
        pending-withdrawal: u0,
        last-payout: u0
      }
    )
    
    ;; Increment educator ID
    (var-set next-educator-id (+ educator-id u1))
    
    (ok educator-id)
  )
)

;; Create course
(define-public (create-course
  (title (string-ascii 100))
  (description (string-ascii 1000))
  (category (string-ascii 50))
  (course-type uint)
  (price-microSTX uint)
  (duration-hours uint)
  (lesson-count uint)
  (content-hash (string-ascii 64))
)
  (let
    (
      (educator-data (unwrap! (map-get? educator-address-to-id { educator-address: tx-sender }) ERR_NOT_FOUND))
      (educator-id (get educator-id educator-data))
      (course-id (var-get next-course-id))
      (current-time (unwrap! (get-block-info? time (- block-height u1)) ERR_NOT_FOUND))
      (educator-profile (unwrap! (map-get? educators { educator-id: educator-id }) ERR_NOT_FOUND))
    )
    (asserts! (var-get platform-active) ERR_UNAUTHORIZED)
    (asserts! (<= course-type COURSE_SUBSCRIPTION) ERR_INVALID_COURSE)
    (asserts! (> lesson-count u0) ERR_INVALID_COURSE)
    
    ;; Create course
    (map-set courses
      { course-id: course-id }
      {
        educator-id: educator-id,
        title: title,
        description: description,
        category: category,
        course-type: course-type,
        price-microSTX: price-microSTX,
        duration-hours: duration-hours,
        lesson-count: lesson-count,
        created-at: current-time,
        updated-at: current-time,
        enrollment-count: u0,
        completion-count: u0,
        active: true,
        content-hash: content-hash
      }
    )
    
    ;; Initialize course enrollments index
    (map-set course-enrollments
      { course-id: course-id }
      { enrollment-ids: (list) }
    )
    
    ;; Update educator course count
    (map-set educators
      { educator-id: educator-id }
      (merge educator-profile { course-count: (+ (get course-count educator-profile) u1) })
    )
    
    ;; Increment course ID
    (var-set next-course-id (+ course-id u1))
    
    (ok course-id)
  )
)

;; Enroll in course
(define-public (enroll-in-course (course-id uint) (payment-amount uint))
  (let
    (
      (course-info (unwrap! (map-get? courses { course-id: course-id }) ERR_NOT_FOUND))
      (enrollment-id (var-get next-enrollment-id))
      (current-time (unwrap! (get-block-info? time (- block-height u1)) ERR_NOT_FOUND))
      (course-enrollments-list (default-to (list) (get enrollment-ids (map-get? course-enrollments { course-id: course-id }))))
      (student-enrollments-list (default-to (list) (get enrollment-ids (map-get? student-enrollments { student-address: tx-sender }))))
    )
    (asserts! (var-get platform-active) ERR_UNAUTHORIZED)
    (asserts! (get active course-info) ERR_COURSE_INACTIVE)
    
    ;; Check payment for paid courses
    (asserts! (if (> (get price-microSTX course-info) u0)
      (>= payment-amount (get price-microSTX course-info))
      true
    ) ERR_INSUFFICIENT_PAYMENT)
    
    ;; Create enrollment
    (map-set enrollments
      { enrollment-id: enrollment-id }
      {
        course-id: course-id,
        student-address: tx-sender,
        enrolled-at: current-time,
        expires-at: none, ;; No expiration for now
        payment-amount: payment-amount,
        status: ENROLLMENT_ACTIVE,
        progress-percentage: u0,
        lessons-completed: u0,
        last-activity: current-time
      }
    )
    
    ;; Update course enrollments index
    (map-set course-enrollments
      { course-id: course-id }
      { enrollment-ids: (unwrap! (as-max-len? (append course-enrollments-list enrollment-id) u1000) ERR_NOT_FOUND) }
    )
    
    ;; Update student enrollments index
    (map-set student-enrollments
      { student-address: tx-sender }
      { enrollment-ids: (unwrap! (as-max-len? (append student-enrollments-list enrollment-id) u100) ERR_NOT_FOUND) }
    )
    
    ;; Update course enrollment count
    (map-set courses
      { course-id: course-id }
      (merge course-info { enrollment-count: (+ (get enrollment-count course-info) u1) })
    )
    
    ;; Note: Payment processing would be handled here
    
    ;; Increment enrollment ID
    (var-set next-enrollment-id (+ enrollment-id u1))
    
    (ok enrollment-id)
  )
)

;; Complete lesson
(define-public (complete-lesson (enrollment-id uint) (lesson-id uint) (time-spent uint) (score (optional uint)))
  (let
    (
      (enrollment-info (unwrap! (map-get? enrollments { enrollment-id: enrollment-id }) ERR_NOT_FOUND))
      (course-info (unwrap! (map-get? courses { course-id: (get course-id enrollment-info) }) ERR_NOT_FOUND))
      (current-time (unwrap! (get-block-info? time (- block-height u1)) ERR_NOT_FOUND))
    )
    (asserts! (var-get platform-active) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get student-address enrollment-info) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status enrollment-info) ENROLLMENT_ACTIVE) ERR_NOT_ENROLLED)
    (asserts! (<= lesson-id (get lesson-count course-info)) ERR_INVALID_COURSE)
    
    ;; Record lesson completion
    (map-set lesson-progress
      { enrollment-id: enrollment-id, lesson-id: lesson-id }
      {
        completed-at: current-time,
        time-spent: time-spent,
        score: score,
        notes: none
      }
    )
    
    ;; Update enrollment progress
    (let 
      (
        (new-lessons-completed (+ (get lessons-completed enrollment-info) u1))
        (new-progress (/ (* new-lessons-completed u100) (get lesson-count course-info)))
      )
      (map-set enrollments
        { enrollment-id: enrollment-id }
        (merge enrollment-info {
          progress-percentage: new-progress,
          lessons-completed: new-lessons-completed,
          last-activity: current-time,
          status: (if (is-eq new-lessons-completed (get lesson-count course-info)) ENROLLMENT_COMPLETED ENROLLMENT_ACTIVE)
        })
      )
      
      ;; Note: Course completion rewards would be processed here
    )
    
    (ok true)
  )
)

;; Submit course review
(define-public (submit-course-review (course-id uint) (rating uint) (review (string-ascii 500)))
  (let
    (
      (current-time (unwrap! (get-block-info? time (- block-height u1)) ERR_NOT_FOUND))
    )
    (asserts! (var-get platform-active) ERR_UNAUTHORIZED)
    (asserts! (and (>= rating u1) (<= rating u5)) ERR_INVALID_COURSE)
    
    ;; Create review
    (map-set course-reviews
      { course-id: course-id, student-address: tx-sender }
      {
        rating: rating,
        review: review,
        created-at: current-time,
        helpful-votes: u0
      }
    )
    
    (ok true)
  )
)

;; Read-Only Functions

;; Get educator profile
(define-read-only (get-educator-profile (educator-id uint))
  (map-get? educators { educator-id: educator-id })
)

;; Get course details
(define-read-only (get-course-details (course-id uint))
  (map-get? courses { course-id: course-id })
)

;; Get enrollment details
(define-read-only (get-enrollment-details (enrollment-id uint))
  (map-get? enrollments { enrollment-id: enrollment-id })
)

;; Get student enrollments
(define-read-only (get-student-enrollments (student-address principal))
  (map-get? student-enrollments { student-address: student-address })
)

;; Get educator earnings
(define-read-only (get-educator-earnings (educator-id uint))
  (map-get? educator-earnings { educator-id: educator-id })
)

;; Get course enrollments
(define-read-only (get-course-enrollments (course-id uint))
  (map-get? course-enrollments { course-id: course-id })
)

;; Get educator ID by address
(define-read-only (get-educator-id (educator-address principal))
  (map-get? educator-address-to-id { educator-address: educator-address })
)

;; Private Functions

;; Process course payment
(define-private (process-course-payment (educator-id uint) (payment-amount uint))
  (let
    (
      (platform-fee (/ (* payment-amount (var-get platform-fee-percentage)) u10000))
      (educator-amount (- payment-amount platform-fee))
      (current-earnings (unwrap! (map-get? educator-earnings { educator-id: educator-id }) ERR_NOT_FOUND))
    )
    ;; Update educator earnings
    (map-set educator-earnings
      { educator-id: educator-id }
      {
        total-revenue: (+ (get total-revenue current-earnings) payment-amount),
        platform-fees: (+ (get platform-fees current-earnings) platform-fee),
        net-earnings: (+ (get net-earnings current-earnings) educator-amount),
        pending-withdrawal: (+ (get pending-withdrawal current-earnings) educator-amount),
        last-payout: (get last-payout current-earnings)
      }
    )
    
    (ok educator-amount)
  )
)

;; Process completion rewards
(define-private (process-completion-rewards (enrollment-id uint))
  (let
    (
      (enrollment-info (unwrap! (map-get? enrollments { enrollment-id: enrollment-id }) ERR_NOT_FOUND))
      (course-info (unwrap! (map-get? courses { course-id: (get course-id enrollment-info) }) ERR_NOT_FOUND))
    )
    ;; Update course completion count
    (map-set courses
      { course-id: (get course-id enrollment-info) }
      (merge course-info { completion-count: (+ (get completion-count course-info) u1) })
    )
    
    ;; Additional completion rewards logic would go here
    (ok true)
  )
)

;; Admin Functions

;; Set platform fee
(define-public (set-platform-fee (fee-percentage uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (<= fee-percentage u2000) ERR_INVALID_COURSE) ;; Max 20%
    (var-set platform-fee-percentage fee-percentage)
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

