;; storynest-core
;; 
;; This contract serves as the central hub for the StoryNest platform, 
;; handling the creation, ownership, and transfer of animated story NFTs.
;; It maintains a registry of stories with their associated metadata and 
;; manages the marketplace where stories can be bought and sold.

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-STORY-NOT-FOUND (err u101))
(define-constant ERR-CREATOR-NOT-FOUND (err u102))
(define-constant ERR-INVALID-PARAMS (err u103))
(define-constant ERR-ALREADY-LISTED (err u104))
(define-constant ERR-NOT-LISTED (err u105))
(define-constant ERR-INSUFFICIENT-FUNDS (err u106))
(define-constant ERR-CANNOT-MINT (err u107))
(define-constant ERR-CREATOR-EXISTS (err u108))
(define-constant ERR-CANNOT-TRANSFER (err u109))
(define-constant ERR-CANNOT-BURN (err u110))

;; Platform configuration constants
(define-constant PLATFORM-ADMIN tx-sender)
(define-constant PLATFORM-FEE-PERCENT u50)  ;; 5% (represented as basis points, 1% = 10)
(define-constant MAX-ROYALTY-PERCENT u300)  ;; 30% max royalty (in basis points)
(define-constant BASIS-POINTS u1000)        ;; For percentage calculations

;; Data space definitions

;; Creator profiles
(define-map creators
  { creator: principal }
  {
    name: (string-utf8 100),
    bio: (string-utf8 500),
    profile-image: (string-utf8 256),
    reputation-score: uint,
    story-count: uint,
    total-sales: uint,
    creation-time: uint
  }
)

;; Story NFT data
(define-map stories
  { story-id: uint }
  {
    title: (string-utf8 100),
    description: (string-utf8 500),
    animation-url: (string-utf8 256),
    thumbnail-url: (string-utf8 256),
    creator: principal,
    royalty-percent: uint,
    likes: uint,
    shares: uint,
    creation-time: uint,
    category: (string-utf8 50)
  }
)

;; Story ownership tracking
(define-map story-ownership
  { story-id: uint }
  { owner: principal }
)

;; Marketplace listings
(define-map marketplace-listings
  { story-id: uint }
  {
    price: uint,
    seller: principal,
    listed-at: uint
  }
)

;; Counter for story IDs
(define-data-var next-story-id uint u1)

;; Private functions

;; Calculate platform fee from a given amount
(define-private (calculate-platform-fee (amount uint))
  (/ (* amount PLATFORM-FEE-PERCENT) BASIS-POINTS)
)

;; Calculate royalty fee for a creator
(define-private (calculate-royalty-fee (amount uint) (royalty-percent uint))
  (/ (* amount royalty-percent) BASIS-POINTS)
)

;; Get story data or fail
(define-private (get-story-or-fail (story-id uint))
  (match (map-get? stories { story-id: story-id })
    story story
    (begin
      (print (concat "Story not found: " (to-ascii (serialize story-id))))
      (asserts! false ERR-STORY-NOT-FOUND)
      ;; Return a placeholder to satisfy the type system
      {
        title: "", description: "", animation-url: "",
        thumbnail-url: "", creator: tx-sender, royalty-percent: u0,
        likes: u0, shares: u0, creation-time: u0, category: ""
      }
    )
  )
)

;; Get story owner or fail
(define-private (get-story-owner-or-fail (story-id uint))
  (match (map-get? story-ownership { story-id: story-id })
    ownership (get owner ownership)
    (begin
      (print (concat "Story ownership not found: " (to-ascii (serialize story-id))))
      (asserts! false ERR-STORY-NOT-FOUND)
      tx-sender  ;; Return placeholder
    )
  )
)

;; Check if caller is authorized for story operations
(define-private (is-story-owner (story-id uint) (caller principal))
  (match (map-get? story-ownership { story-id: story-id })
    ownership (is-eq (get owner ownership) caller)
    false
  )
)

;; Increment creator's reputation by the specified amount
(define-private (increment-creator-reputation (creator-principal principal) (amount uint))
  (match (map-get? creators { creator: creator-principal })
    creator-data
      (map-set creators
        { creator: creator-principal }
        (merge creator-data { reputation-score: (+ (get reputation-score creator-data) amount) })
      )
    false  ;; Creator not found, do nothing
  )
)

;; Public functions

;; Register a new creator profile
(define-public (register-creator 
                (name (string-utf8 100)) 
                (bio (string-utf8 500)) 
                (profile-image (string-utf8 256)))
  (let ((caller tx-sender))
    ;; Check if creator already exists
    (asserts! (is-none (map-get? creators { creator: caller })) ERR-CREATOR-EXISTS)
    
    ;; Create new creator profile
    (map-set creators
      { creator: caller }
      {
        name: name,
        bio: bio,
        profile-image: profile-image,
        reputation-score: u0,
        story-count: u0,
        total-sales: u0,
        creation-time: (unwrap-panic (get-block-info? time u0))
      }
    )
    (ok true)
  )
)

;; Update a creator profile
(define-public (update-creator-profile 
                (name (string-utf8 100)) 
                (bio (string-utf8 500)) 
                (profile-image (string-utf8 256)))
  (let ((caller tx-sender))
    ;; Get current creator data
    (match (map-get? creators { creator: caller })
      creator-data
        (begin
          ;; Update creator profile
          (map-set creators
            { creator: caller }
            (merge creator-data {
              name: name,
              bio: bio,
              profile-image: profile-image
            })
          )
          (ok true)
        )
      (err ERR-CREATOR-NOT-FOUND)
    )
  )
)

;; Mint a new story NFT
(define-public (mint-story 
                (title (string-utf8 100)) 
                (description (string-utf8 500))
                (animation-url (string-utf8 256))
                (thumbnail-url (string-utf8 256))
                (royalty-percent uint)
                (category (string-utf8 50)))
  (let (
    (caller tx-sender)
    (story-id (var-get next-story-id))
    (current-time (unwrap-panic (get-block-info? time u0)))
  )
    ;; Ensure creator exists
    (asserts! (is-some (map-get? creators { creator: caller })) ERR-CREATOR-NOT-FOUND)
    
    ;; Validate royalty percentage (max 30%)
    (asserts! (<= royalty-percent MAX-ROYALTY-PERCENT) ERR-INVALID-PARAMS)
    
    ;; Create new story NFT
    (map-set stories
      { story-id: story-id }
      {
        title: title,
        description: description,
        animation-url: animation-url,
        thumbnail-url: thumbnail-url,
        creator: caller,
        royalty-percent: royalty-percent,
        likes: u0,
        shares: u0,
        creation-time: current-time,
        category: category
      }
    )
    
    ;; Set initial ownership
    (map-set story-ownership
      { story-id: story-id }
      { owner: caller }
    )
    
    ;; Update creator's story count
    (match (map-get? creators { creator: caller })
      creator-data
        (map-set creators
          { creator: caller }
          (merge creator-data { story-count: (+ (get story-count creator-data) u1) })
        )
      (err ERR-CREATOR-NOT-FOUND)
    )
    
    ;; Increment the story ID counter
    (var-set next-story-id (+ story-id u1))
    
    (ok story-id)
  )
)

;; List a story for sale
(define-public (list-story-for-sale (story-id uint) (price uint))
  (let ((caller tx-sender))
    ;; Ensure story exists and caller is the owner
    (asserts! (is-story-owner story-id caller) ERR-NOT-AUTHORIZED)
    
    ;; Check that the price is greater than zero
    (asserts! (> price u0) ERR-INVALID-PARAMS)
    
    ;; Check that story is not already listed
    (asserts! (is-none (map-get? marketplace-listings { story-id: story-id })) ERR-ALREADY-LISTED)
    
    ;; List the story for sale
    (map-set marketplace-listings
      { story-id: story-id }
      {
        price: price,
        seller: caller,
        listed-at: (unwrap-panic (get-block-info? time u0))
      }
    )
    
    (ok true)
  )
)

;; Cancel a marketplace listing
(define-public (cancel-listing (story-id uint))
  (let ((caller tx-sender))
    ;; Ensure story exists and caller is the owner
    (asserts! (is-story-owner story-id caller) ERR-NOT-AUTHORIZED)
    
    ;; Check that story is listed
    (asserts! (is-some (map-get? marketplace-listings { story-id: story-id })) ERR-NOT-LISTED)
    
    ;; Remove the listing
    (map-delete marketplace-listings { story-id: story-id })
    
    (ok true)
  )
)

;; Buy a story from the marketplace
(define-public (buy-story (story-id uint))
  (let (
    (caller tx-sender)
    (listing (unwrap! (map-get? marketplace-listings { story-id: story-id }) ERR-NOT-LISTED))
    (price (get price listing))
    (seller (get seller listing))
    (story (get-story-or-fail story-id))
    (creator (get creator story))
    (royalty-percent (get royalty-percent story))
  )
    ;; Ensure buyer is not the seller
    (asserts! (not (is-eq caller seller)) ERR-INVALID-PARAMS)
    
    ;; Calculate fees
    (let (
      (platform-fee (calculate-platform-fee price))
      (royalty-fee (if (is-eq seller creator) 
                      u0  ;; No royalty on primary sales
                      (calculate-royalty-fee price royalty-percent)))
      (seller-amount (- price (+ platform-fee royalty-fee)))
    )
      ;; Transfer payment from buyer to seller, platform, and creator
      ;; First, transfer funds from buyer to this contract
      (try! (stx-transfer? price caller (as-contract tx-sender)))
      
      ;; Then distribute funds from the contract
      (try! (as-contract (stx-transfer? seller-amount tx-sender seller)))
      (try! (as-contract (stx-transfer? platform-fee tx-sender PLATFORM-ADMIN)))
      
      ;; Pay royalty to creator if this is a secondary sale
      (if (> royalty-fee u0)
        (try! (as-contract (stx-transfer? royalty-fee tx-sender creator)))
        true
      )
      
      ;; Transfer ownership
      (map-set story-ownership
        { story-id: story-id }
        { owner: caller }
      )
      
      ;; Remove listing
      (map-delete marketplace-listings { story-id: story-id })
      
      ;; Update creator stats if this is a primary sale
      (when (is-eq seller creator)
        (match (map-get? creators { creator: creator })
          creator-data
            (map-set creators
              { creator: creator }
              (merge creator-data { total-sales: (+ (get total-sales creator-data) u1) })
            )
          false
        )
      )
      
      ;; Boost creator reputation
      (increment-creator-reputation creator u1)
      
      (ok true)
    )
  )
)

;; Transfer a story to another user (gift)
(define-public (transfer-story (story-id uint) (recipient principal))
  (let ((caller tx-sender))
    ;; Ensure story exists and caller is the owner
    (asserts! (is-story-owner story-id caller) ERR-NOT-AUTHORIZED)
    
    ;; Ensure the story is not currently listed
    (asserts! (is-none (map-get? marketplace-listings { story-id: story-id })) ERR-CANNOT-TRANSFER)
    
    ;; Ensure recipient is not the current owner
    (asserts! (not (is-eq recipient caller)) ERR-INVALID-PARAMS)
    
    ;; Transfer ownership
    (map-set story-ownership
      { story-id: story-id }
      { owner: recipient }
    )
    
    (ok true)
  )
)

;; Like a story
(define-public (like-story (story-id uint))
  (let (
    (story (get-story-or-fail story-id))
    (creator (get creator story))
  )
    ;; Update story likes
    (map-set stories
      { story-id: story-id }
      (merge story { likes: (+ (get likes story) u1) })
    )
    
    ;; Increase creator reputation
    (increment-creator-reputation creator u1)
    
    (ok true)
  )
)

;; Share a story
(define-public (share-story (story-id uint))
  (let (
    (story (get-story-or-fail story-id))
    (creator (get creator story))
  )
    ;; Update story shares
    (map-set stories
      { story-id: story-id }
      (merge story { shares: (+ (get shares story) u1) })
    )
    
    ;; Increase creator reputation
    (increment-creator-reputation creator u2)  ;; Shares worth more than likes
    
    (ok true)
  )
)

;; Tip a creator directly
(define-public (tip-creator (creator-principal principal) (amount uint))
  (let ((caller tx-sender))
    ;; Ensure creator exists
    (asserts! (is-some (map-get? creators { creator: creator-principal })) ERR-CREATOR-NOT-FOUND)
    
    ;; Ensure amount is greater than zero
    (asserts! (> amount u0) ERR-INVALID-PARAMS)
    
    ;; Calculate platform fee
    (let ((platform-fee (calculate-platform-fee amount))
          (creator-amount (- amount platform-fee)))
      
      ;; Transfer funds
      (try! (stx-transfer? amount caller (as-contract tx-sender)))
      (try! (as-contract (stx-transfer? creator-amount tx-sender creator-principal)))
      (try! (as-contract (stx-transfer? platform-fee tx-sender PLATFORM-ADMIN)))
      
      ;; Increase creator reputation
      (increment-creator-reputation creator-principal u5)
      
      (ok true)
    )
  )
)

;; Read-only functions

;; Get story info
(define-read-only (get-story-info (story-id uint))
  (match (map-get? stories { story-id: story-id })
    story (ok story)
    ERR-STORY-NOT-FOUND
  )
)

;; Get story owner
(define-read-only (get-story-owner (story-id uint))
  (match (map-get? story-ownership { story-id: story-id })
    ownership (ok (get owner ownership))
    ERR-STORY-NOT-FOUND
  )
)

;; Get creator profile
(define-read-only (get-creator-profile (creator-principal principal))
  (match (map-get? creators { creator: creator-principal })
    creator-data (ok creator-data)
    ERR-CREATOR-NOT-FOUND
  )
)

;; Get marketplace listing
(define-read-only (get-marketplace-listing (story-id uint))
  (match (map-get? marketplace-listings { story-id: story-id })
    listing (ok listing)
    ERR-NOT-LISTED
  )
)

;; Check if story is listed
(define-read-only (is-story-listed (story-id uint))
  (is-some (map-get? marketplace-listings { story-id: story-id }))
)

;; Get the next available story ID
(define-read-only (get-next-story-id)
  (var-get next-story-id)
)

;; Get the total number of stories
(define-read-only (get-total-stories)
  (- (var-get next-story-id) u1)
)