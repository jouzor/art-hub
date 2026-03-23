;; Digital Art Commission Hub Smart Contract

;; Error codes
(define-constant ERR-PERMISSION-DENIED (err u100))
(define-constant ERR-ARTIST-REGISTERED (err u101))
(define-constant ERR-ARTIST-UNKNOWN (err u102))
(define-constant ERR-SPECIFICATION-FAILED (err u103))
(define-constant ERR-GALLERY-EMPTY (err u104))
(define-constant ERR-PAYMENT-FAILED (err u105))
(define-constant ERR-SUBMISSION-FAILED (err u106))
(define-constant ERR-PROJECT-FAILED (err u107))

;; Data variables
(define-data-var gallery-curator principal tx-sender)
(define-data-var art-fund uint u0)
(define-data-var artist-community uint u0)

;; Data maps
(define-map digital-artists
    principal
    {
        creativity-score: uint,
        artworks-submitted: uint,
        mastery-rank: uint,
        last-submission-time: uint,
        commission-earnings: uint,
        open-projects: uint
    }
)

(define-map art-projects
    {artist: principal, project-ref: uint}
    {
        artwork-requirement: uint,
        pieces-delivered: uint,
        project-expiration: uint,
        project-concluded: bool,
        commission-value: uint,
        art-medium: (string-ascii 20)
    }
)

(define-map artist-accolades
    principal
    (list 10 (string-ascii 30))
)

;; Public functions

;; Artist onboarding
(define-public (register-digital-artist)
    (let
        ((artist tx-sender))
        (asserts! (is-none (map-get? digital-artists artist)) (err ERR-ARTIST-REGISTERED))
        (map-set digital-artists
            artist
            {
                creativity-score: u0,
                artworks-submitted: u0,
                mastery-rank: u1,
                last-submission-time: burn-block-height,
                commission-earnings: u0,
                open-projects: u0
            }
        )
        (var-set artist-community (+ (var-get artist-community) u1))
        (ok true)
    )
)

;; Commission project creation
(define-public (establish-art-project (piece-count uint) (completion-deadline uint) (medium-style (string-ascii 20)))
    (let
        ((artist tx-sender)
         (artist-record (unwrap! (map-get? digital-artists artist) ERR-ARTIST-UNKNOWN))
         (project-ref (+ (get open-projects artist-record) u1)))
        
        (asserts! (> piece-count u0) ERR-SPECIFICATION-FAILED)
        (asserts! (> completion-deadline burn-block-height) ERR-SPECIFICATION-FAILED)
        (asserts! (<= (len medium-style) u20) ERR-SPECIFICATION-FAILED)
        
        (map-set art-projects
            {artist: artist, project-ref: project-ref}
            {
                artwork-requirement: piece-count,
                pieces-delivered: u0,
                project-expiration: completion-deadline,
                project-concluded: false,
                commission-value: (estimate-commission-value piece-count),
                art-medium: medium-style
            }
        )
        
        (map-set digital-artists
            artist
            (merge artist-record {open-projects: project-ref})
        )
        (ok project-ref)
    )
)

;; Submit artwork progress
(define-public (deliver-artwork-batch (project-ref uint) (piece-quantity uint))
    (let
        ((artist tx-sender)
         (artist-record (unwrap! (map-get? digital-artists artist) ERR-ARTIST-UNKNOWN)))
        
        (asserts! (> piece-quantity u0) ERR-SUBMISSION-FAILED)
        (asserts! (<= project-ref (get open-projects artist-record)) ERR-PROJECT-FAILED)
        
        (let
            ((project-record (unwrap! (map-get? art-projects {artist: artist, project-ref: project-ref}) ERR-PROJECT-FAILED))
             (delivery-moment burn-block-height))
            
            (asserts! (not (get project-concluded project-record)) ERR-SPECIFICATION-FAILED)
            (asserts! (<= delivery-moment (get project-expiration project-record)) ERR-SPECIFICATION-FAILED)
            
            (let
                ((total-delivered (+ (get pieces-delivered project-record) piece-quantity))
                 (requirement-fulfilled (>= total-delivered (get artwork-requirement project-record)))
                 (score-increment (estimate-creativity-score piece-quantity))
                 (enhanced-score (+ (get creativity-score artist-record) score-increment)))
                
                ;; Update project
                (map-set art-projects
                    {artist: artist, project-ref: project-ref}
                    (merge project-record {
                        pieces-delivered: total-delivered,
                        project-concluded: requirement-fulfilled
                    })
                )
                
                ;; Update artist
                (map-set digital-artists
                    artist
                    (merge artist-record {
                        creativity-score: enhanced-score,
                        artworks-submitted: (+ (get artworks-submitted artist-record) u1),
                        last-submission-time: delivery-moment,
                        mastery-rank: (estimate-mastery-rank enhanced-score)
                    })
                )
                
                ;; Grant accolade if requirement fulfilled
                (if requirement-fulfilled
                    (grant-artist-accolade artist (concat "Completed " (get art-medium project-record)))
                    true
                )
                
                (ok {
                    delivered: total-delivered,
                    concluded: requirement-fulfilled,
                    score: enhanced-score
                })
            )
        )
    )
)

;; Withdraw commission payment
(define-public (claim-commission-payment (project-ref uint))
    (let
        ((artist tx-sender)
         (artist-record (unwrap! (map-get? digital-artists artist) ERR-ARTIST-UNKNOWN)))
        
        (asserts! (<= project-ref (get open-projects artist-record)) ERR-PROJECT-FAILED)
        
        (let
            ((project-record (unwrap! (map-get? art-projects {artist: artist, project-ref: project-ref}) ERR-PROJECT-FAILED)))
            
            (asserts! (get project-concluded project-record) ERR-SPECIFICATION-FAILED)
            (asserts! (>= (var-get art-fund) (get commission-value project-record)) ERR-GALLERY-EMPTY)
            
            ;; Process payment
            (var-set art-fund (- (var-get art-fund) (get commission-value project-record)))
            (map-set digital-artists
                artist
                (merge artist-record {
                    commission-earnings: (+ (get commission-earnings artist-record) (get commission-value project-record))
                })
            )
            
            (ok (get commission-value project-record))
        )
    )
)

;; Private functions

(define-private (estimate-commission-value (piece-count uint))
    (let
        ((rate-per-piece u100))
        (* rate-per-piece (/ piece-count u100))
    )
)

(define-private (estimate-creativity-score (piece-quantity uint))
    (* piece-quantity u10)
)

(define-private (estimate-mastery-rank (enhanced-score uint))
    (+ u1 (/ enhanced-score u1000))
)

(define-private (grant-artist-accolade (artist principal) (accolade-description (string-ascii 30)))
    (let
        ((current-accolades (default-to (list) (map-get? artist-accolades artist))))
        (map-set artist-accolades
            artist
            (unwrap-panic (as-max-len? (append current-accolades accolade-description) u10))
        )
    )
)

;; Read-only functions

(define-read-only (query-artist-record (artist principal))
    (map-get? digital-artists artist)
)

(define-read-only (query-project-record (artist principal) (project-ref uint))
    (map-get? art-projects {artist: artist, project-ref: project-ref})
)

(define-read-only (query-artist-accolades (artist principal))
    (map-get? artist-accolades artist)
)

(define-read-only (query-hub-statistics)
    {
        community-size: (var-get artist-community),
        fund-balance: (var-get art-fund)
    }
)

;; Administrative functions

(define-public (allocate-art-fund (funding-amount uint))
    (begin
        (asserts! (is-eq tx-sender (var-get gallery-curator)) ERR-PERMISSION-DENIED)
        (asserts! (> funding-amount u0) ERR-PAYMENT-FAILED)
        (var-set art-fund (+ (var-get art-fund) funding-amount))
        (ok true)
    )
)

(define-public (delegate-curator-role (successor-curator principal))
    (begin
        (asserts! (is-eq tx-sender (var-get gallery-curator)) ERR-PERMISSION-DENIED)
        (asserts! (not (is-eq successor-curator (var-get gallery-curator))) ERR-PERMISSION-DENIED)
        (var-set gallery-curator successor-curator)
        (ok true)
    )
)