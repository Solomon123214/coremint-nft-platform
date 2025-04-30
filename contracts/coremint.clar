;; coremint.clar
;; CoreMint NFT Platform
;;
;; This contract implements a comprehensive NFT platform compatible with SIP-009
;; while extending functionality to support creator royalties and collection management.
;; It enables creators to mint, manage, and transfer NFTs with automatic royalty
;; enforcement on secondary sales.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-TOKEN-ID-NOT-FOUND (err u101))
(define-constant ERR-NOT-OWNER (err u102))
(define-constant ERR-LISTING-NOT-FOUND (err u103))
(define-constant ERR-COLLECTION-NOT-FOUND (err u104))
(define-constant ERR-INVALID-ROYALTY (err u105))
(define-constant ERR-SALE-PRICE-ZERO (err u106))
(define-constant ERR-TRANSFER-FAILED (err u107))
(define-constant ERR-ROYALTY-PAYMENT-FAILED (err u108))
(define-constant ERR-ALREADY-LISTED (err u109))
(define-constant ERR-PRICE-TOO-LOW (err u110))
(define-constant ERR-COLLECTION-EXISTS (err u111))
(define-constant ERR-NO-TOKENS-MINTED (err u112))

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MAX-ROYALTY-PERCENTAGE u30) ;; Maximum royalty is 30%

;; Data structures

;; NFT token data
(define-non-fungible-token coremint-nft uint)

;; Token counter to generate unique IDs
(define-data-var token-id-counter uint u0)

;; Collections map: collection-id -> collection details
(define-map collections
  uint
  {
    name: (string-ascii 64),
    creator: principal,
    description: (string-utf8 256),
    royalty-percentage: uint,
    total-supply: uint,
    created-at: uint
  }
)

;; Collection counter to generate unique collection IDs
(define-data-var collection-id-counter uint u0)

;; Collection membership: token-id -> collection-id
(define-map token-collection
  uint
  uint
)

;; Token metadata
(define-map token-metadata
  uint
  {
    name: (string-ascii 64),
    description: (string-utf8 256),
    image-uri: (string-ascii 256),
    creator: principal,
    created-at: uint
  }
)

;; Token royalty information
(define-map token-royalties
  uint
  {
    recipient: principal,
    percentage: uint
  }
)

;; Market listings
(define-map token-listings
  uint
  {
    price: uint,
    seller: principal,
    listed-at: uint
  }
)

;; Private functions

;; Get the current token ID and increment the counter
(define-private (next-token-id)
  (let ((current-id (var-get token-id-counter)))
    (var-set token-id-counter (+ current-id u1))
    current-id
  )
)

;; Get the current collection ID and increment the counter
(define-private (next-collection-id)
  (let ((current-id (var-get collection-id-counter)))
    (var-set collection-id-counter (+ current-id u1))
    current-id
  )
)

;; Check if the provided percentage is valid for royalties
(define-private (is-valid-royalty (percentage uint))
  (<= percentage MAX-ROYALTY-PERCENTAGE)
)

;; Calculate royalty amount based on sale price and royalty percentage
(define-private (calculate-royalty (token-id uint) (sale-price uint))
  (match (map-get? token-royalties token-id)
    royalty-info
    (let ((royalty-amount (/ (* sale-price (get percentage royalty-info)) u100)))
      {
        recipient: (get recipient royalty-info),
        amount: royalty-amount
      }
    )
    ;; If no royalty info is found, return zero royalty
    {
      recipient: CONTRACT-OWNER,
      amount: u0
    }
  )
)

;; Transfer royalty to creator
(define-private (transfer-royalty (token-id uint) (sale-price uint))
  (let (
    (royalty-data (calculate-royalty token-id sale-price))
    (royalty-amount (get amount royalty-data))
    (royalty-recipient (get recipient royalty-data))
  )
    (if (> royalty-amount u0)
      (stx-transfer? royalty-amount tx-sender royalty-recipient)
      (ok true))
  )
)

;; Process token transfer with royalty handling
(define-private (process-transfer (token-id uint) (sender principal) (recipient principal) (sale-price uint))
  (begin
    ;; Check if token exists
    (asserts! (is-some (nft-get-owner? coremint-nft token-id)) ERR-TOKEN-ID-NOT-FOUND)
    ;; Check if sender is the owner
    (asserts! (is-eq sender (unwrap! (nft-get-owner? coremint-nft token-id) ERR-NOT-OWNER)) ERR-NOT-AUTHORIZED)
    
    ;; If there's a sale price > 0, handle royalty payment
    (if (> sale-price u0)
      (unwrap! (transfer-royalty token-id sale-price) ERR-ROYALTY-PAYMENT-FAILED)
      true)
      
    ;; Perform the NFT transfer
    (unwrap! (nft-transfer? coremint-nft token-id sender recipient) ERR-TRANSFER-FAILED)
    
    ;; If token was listed, remove the listing
    (map-delete token-listings token-id)
    
    (ok true)
  )
)

;; Read-only functions

;; Get token metadata
(define-read-only (get-token-metadata (token-id uint))
  (map-get? token-metadata token-id)
)

;; Get token royalty information
(define-read-only (get-token-royalty (token-id uint))
  (map-get? token-royalties token-id)
)

;; Get collection information
(define-read-only (get-collection (collection-id uint))
  (map-get? collections collection-id)
)

;; Get token's collection
(define-read-only (get-token-collection (token-id uint))
  (map-get? token-collection token-id)
)

;; Get token listing information
(define-read-only (get-listing (token-id uint))
  (map-get? token-listings token-id)
)

;; Get total number of tokens minted
(define-read-only (get-total-tokens)
  (var-get token-id-counter)
)

;; Get total number of collections created
(define-read-only (get-total-collections)
  (var-get collection-id-counter)
)

;; Get last token ID
(define-read-only (get-last-token-id)
  (- (var-get token-id-counter) u1)
)

;; Check if principal owns a token
(define-read-only (owns-token (owner principal) (token-id uint))
  (is-eq owner (unwrap! (nft-get-owner? coremint-nft token-id) false))
)

;; SIP-009 NFT standard compatibility functions

;; Get token URI - returns the image URI from metadata
(define-read-only (get-token-uri (token-id uint))
  (match (map-get? token-metadata token-id)
    metadata (ok (get image-uri metadata))
    (err none)
  )
)

;; Get token owner
(define-read-only (get-owner (token-id uint))
  (nft-get-owner? coremint-nft token-id)
)

;; Get last token ID (SIP-009 name)
(define-read-only (get-last-token-id-sip-009)
  (ok (get-last-token-id))
)

;; Public functions

;; Create a new collection
(define-public (create-collection (name (string-ascii 64)) (description (string-utf8 256)) (royalty-percentage uint))
  (let ((collection-id (next-collection-id)))
    ;; Validate royalty percentage
    (asserts! (is-valid-royalty royalty-percentage) ERR-INVALID-ROYALTY)
    
    ;; Store the collection information
    (map-set collections collection-id {
      name: name,
      creator: tx-sender,
      description: description,
      royalty-percentage: royalty-percentage,
      total-supply: u0,
      created-at: block-height
    })
    
    (ok collection-id)
  )
)

;; Mint a single NFT with no collection
(define-public (mint-token (name (string-ascii 64)) (description (string-utf8 256)) (image-uri (string-ascii 256)) (royalty-percentage uint))
  (let ((token-id (next-token-id)))
    ;; Validate royalty percentage
    (asserts! (is-valid-royalty royalty-percentage) ERR-INVALID-ROYALTY)
    
    ;; Mint the token to the sender
    (try! (nft-mint? coremint-nft token-id tx-sender))
    
    ;; Store token metadata
    (map-set token-metadata token-id {
      name: name,
      description: description,
      image-uri: image-uri,
      creator: tx-sender,
      created-at: block-height
    })
    
    ;; Store royalty information
    (map-set token-royalties token-id {
      recipient: tx-sender,
      percentage: royalty-percentage
    })
    
    (ok token-id)
  )
)

;; Mint a token in a collection
(define-public (mint-in-collection (collection-id uint) (name (string-ascii 64)) (description (string-utf8 256)) (image-uri (string-ascii 256)))
  (let (
    (token-id (next-token-id))
    (collection (unwrap! (map-get? collections collection-id) ERR-COLLECTION-NOT-FOUND))
  )
    ;; Check if sender is the collection creator
    (asserts! (is-eq tx-sender (get creator collection)) ERR-NOT-AUTHORIZED)
    
    ;; Mint the token to the sender
    (try! (nft-mint? coremint-nft token-id tx-sender))
    
    ;; Store token metadata
    (map-set token-metadata token-id {
      name: name,
      description: description,
      image-uri: image-uri,
      creator: tx-sender,
      created-at: block-height
    })
    
    ;; Store royalty information using collection settings
    (map-set token-royalties token-id {
      recipient: tx-sender,
      percentage: (get royalty-percentage collection)
    })
    
    ;; Associate token with collection
    (map-set token-collection token-id collection-id)
    
    ;; Update collection total supply
    (map-set collections collection-id 
      (merge collection {
        total-supply: (+ (get total-supply collection) u1)
      })
    )
    
    (ok token-id)
  )
)

;; Transfer token without sale (standard transfer)
(define-public (transfer (token-id uint) (recipient principal))
  (process-transfer token-id tx-sender recipient u0)
)

;; List token for sale
(define-public (list-token (token-id uint) (price uint))
  (begin
    ;; Make sure token exists and sender owns it
    (asserts! (is-some (nft-get-owner? coremint-nft token-id)) ERR-TOKEN-ID-NOT-FOUND)
    (asserts! (is-eq tx-sender (unwrap! (nft-get-owner? coremint-nft token-id) ERR-NOT-OWNER)) ERR-NOT-AUTHORIZED)
    
    ;; Make sure price is greater than zero
    (asserts! (> price u0) ERR-SALE-PRICE-ZERO)
    
    ;; Make sure token is not already listed
    (asserts! (is-none (map-get? token-listings token-id)) ERR-ALREADY-LISTED)
    
    ;; Add listing
    (map-set token-listings token-id {
      price: price,
      seller: tx-sender,
      listed-at: block-height
    })
    
    (ok true)
  )
)

;; Cancel listing
(define-public (cancel-listing (token-id uint))
  (begin
    ;; Check if token is listed
    (asserts! (is-some (map-get? token-listings token-id)) ERR-LISTING-NOT-FOUND)
    
    ;; Check if sender is the seller
    (let ((listing (unwrap-panic (map-get? token-listings token-id))))
      (asserts! (is-eq tx-sender (get seller listing)) ERR-NOT-AUTHORIZED)
      
      ;; Remove listing
      (map-delete token-listings token-id)
      
      (ok true)
    )
  )
)

;; Buy a listed token
(define-public (buy-token (token-id uint))
  (let (
    (listing (unwrap! (map-get? token-listings token-id) ERR-LISTING-NOT-FOUND))
    (price (get price listing))
    (seller (get seller listing))
  )
    ;; Make sure buyer is not the seller
    (asserts! (not (is-eq tx-sender seller)) ERR-NOT-AUTHORIZED)
    
    ;; Process royalties first
    (try! (transfer-royalty token-id price))
    
    ;; Calculate seller amount after royalty
    (let (
      (royalty-data (calculate-royalty token-id price))
      (royalty-amount (get amount royalty-data))
      (seller-amount (- price royalty-amount))
    )
      ;; Transfer payment to seller
      (try! (stx-transfer? seller-amount tx-sender seller))
      
      ;; Transfer NFT to buyer
      (try! (nft-transfer? coremint-nft token-id seller tx-sender))
      
      ;; Remove listing
      (map-delete token-listings token-id)
      
      (ok true)
    )
  )
)

;; Update token metadata (only creator can update)
(define-public (update-token-metadata (token-id uint) (name (string-ascii 64)) (description (string-utf8 256)) (image-uri (string-ascii 256)))
  (let ((metadata (unwrap! (map-get? token-metadata token-id) ERR-TOKEN-ID-NOT-FOUND)))
    ;; Check if sender is the creator
    (asserts! (is-eq tx-sender (get creator metadata)) ERR-NOT-AUTHORIZED)
    
    ;; Update metadata
    (map-set token-metadata token-id (merge metadata {
      name: name,
      description: description,
      image-uri: image-uri
    }))
    
    (ok true)
  )
)

;; Update collection information (only creator can update)
(define-public (update-collection (collection-id uint) (name (string-ascii 64)) (description (string-utf8 256)))
  (let ((collection (unwrap! (map-get? collections collection-id) ERR-COLLECTION-NOT-FOUND)))
    ;; Check if sender is the creator
    (asserts! (is-eq tx-sender (get creator collection)) ERR-NOT-AUTHORIZED)
    
    ;; Update collection
    (map-set collections collection-id (merge collection {
      name: name,
      description: description
    }))
    
    (ok true)
  )
)

;; SIP-009 NFT standard compatibility function
(define-public (transfer-sip-009 (token-id uint) (sender principal) (recipient principal))
  (begin
    ;; Check if caller is the sender
    (asserts! (is-eq tx-sender sender) ERR-NOT-AUTHORIZED)
    (process-transfer token-id sender recipient u0)
  )
)