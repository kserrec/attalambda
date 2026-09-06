#lang racket/base

(require rackunit
         (only-in racket/list drop take)
         racket/promise
         "../core/errors.rkt"
         "../core/lists.rkt"
         "../core/objects.rkt"
         "../core/result.rkt"
         "../core/tags.rkt"
         "../core/unit.rkt"
         (only-in "../core/typed-logic.rkt"
                  FALSE
                  typed-if)
         "../effects/tcp.rkt"
         "../readers/bool.rkt"
         "../readers/raw-boolean.rkt"
         "../readers/type-tag.rkt"
         "../runtime/codec.rkt"
         "helpers/lazy.rkt")

(define (apply-arguments function arguments)
  (if (null? arguments)
      function
      (apply-arguments
       (lazy-apply function (car arguments))
       (cdr arguments))))

(define (typed-value? type value)
  (raw-boolean->boolean
   (apply2 raw-is-type type value)))

(define (error-kind-integer error)
  (type-tag->integer
   (lazy-apply raw-error-root-kind
               (lazy-apply raw-error-root error))))

(define (first-error-frame error)
  (car
   (object-list->host-list
    (lazy-apply raw-error-frames error))))

(define (check-contract-frame error expected-name expected-position
                              expected-type)
  (check-true (typed-value? error-type error))
  (check-equal? (error-kind-integer error) 0)
  (define frame (first-error-frame error))
  (check-equal?
   (object-string->bytes
    (lazy-apply raw-error-frame-function-name frame))
   expected-name)
  (check-equal?
   (type-tag->integer
    (lazy-apply raw-error-frame-argument-position frame))
   expected-position)
  (check-equal?
   (type-tag->integer
    (lazy-apply raw-error-frame-expected-type frame))
   expected-type))

(define (check-ok-unit value)
  (check-true (typed-value? result-type value))
  (check-true (bool->boolean
               (lazy-apply is-ok value)))
  (check-equal?
   (type-tag->integer
    (lazy-apply raw-object-type
                (lazy-apply unwrap-ok value)))
   8))

(define remote
  (bytes->object-string #"127.0.0.1"))
(define local
  (bytes->object-string #""))
(define payload
  (bytes->object-byte-list #"A\0\200\377"))
(define port
  (exact->object-rat 8080))
(define listen-port
  (exact->object-rat 0))
(define backlog
  (exact->object-rat 16))
(define listener-handle
  (exact->object-rat 1))
(define connection-handle
  (exact->object-rat 2))
(define maximum
  (exact->object-rat 65536))

(define (decode-request request decoders)
  (define parts
    (object-list->host-list request))
  (check-false (codec-failure? parts))
  (check-equal? (length parts) (length decoders))
  (map (lambda (decoder part)
         (decoder part))
       decoders
       parts))

(define string-decoder object-string->bytes)
(define rat-field-decoder object-rat->exact)
(define byte-list-decoder object-byte-list->bytes)

;; Each request is a proper typed List containing only canonical object values.
(define request-cases
  (list
   (list make-tcp-connect-request
         (list remote port)
         (list string-decoder string-decoder rat-field-decoder)
         (list #"tcp-connect" #"127.0.0.1" 8080))
   (list make-tcp-listen-request
         (list local listen-port backlog)
         (list string-decoder string-decoder rat-field-decoder rat-field-decoder)
         (list #"tcp-listen" #"" 0 16))
   (list make-tcp-accept-request
         (list listener-handle)
         (list string-decoder rat-field-decoder)
         (list #"tcp-accept" 1))
   (list make-tcp-read-request
         (list connection-handle maximum)
         (list string-decoder rat-field-decoder rat-field-decoder)
         (list #"tcp-read" 2 65536))
   (list make-tcp-write-request
         (list connection-handle payload)
         (list string-decoder rat-field-decoder byte-list-decoder)
         (list #"tcp-write" 2 #"A\0\200\377"))
   (list make-tcp-close-request
         (list connection-handle)
         (list string-decoder rat-field-decoder)
         (list #"tcp-close" 2))))

(for ([case (in-list request-cases)])
  (define request
    (apply-arguments (car case) (cadr case)))
  (check-true (typed-value? list-type request))
  (check-equal? (decode-request request (caddr case))
                (cadddr case)))

(define calls 0)
(define traces '())

(define (fake-host request)
  (set! calls (add1 calls))
  (set! traces (cons request traces))
  (object-ok UNIT))

;; Builder, function name, expected type-tag integers, normal arguments,
;; request decoders, and the exact decoded request.
(define wrapper-cases
  (list
   (list make-tcp-connect #"tcp-connect" '(6 7)
         (list remote port)
         (list string-decoder string-decoder rat-field-decoder)
         (list #"tcp-connect" #"127.0.0.1" 8080))
   (list make-tcp-listen #"tcp-listen" '(6 7 7)
         (list local listen-port backlog)
         (list string-decoder string-decoder rat-field-decoder rat-field-decoder)
         (list #"tcp-listen" #"" 0 16))
   (list make-tcp-accept #"tcp-accept" '(7)
         (list listener-handle)
         (list string-decoder rat-field-decoder)
         (list #"tcp-accept" 1))
   (list make-tcp-read #"tcp-read" '(7 7)
         (list connection-handle maximum)
         (list string-decoder rat-field-decoder rat-field-decoder)
         (list #"tcp-read" 2 65536))
   (list make-tcp-write #"tcp-write" '(7 2)
         (list connection-handle payload)
         (list string-decoder rat-field-decoder byte-list-decoder)
         (list #"tcp-write" 2 #"A\0\200\377"))
   (list make-tcp-close #"tcp-close" '(7)
         (list connection-handle)
         (list string-decoder rat-field-decoder)
         (list #"tcp-close" 2))))

(define pending-results
  (for/list ([case (in-list wrapper-cases)])
    (define wrapper
      (lazy-apply (car case) fake-host))
    (check-equal? (procedure-arity (lazy-force wrapper)) 1)
    (apply-arguments wrapper (list-ref case 3))))

;; Construction and every partial application are pure.
(check-equal? calls 0)

(for ([pending (in-list pending-results)]
      [expected-calls (in-naturals 1)])
  (check-ok-unit pending)
  (check-equal? calls expected-calls)
  ;; A promise performs its host call at most once.
  (check-ok-unit pending)
  (check-equal? calls expected-calls))

(for ([trace (in-list (reverse traces))]
      [case (in-list wrapper-cases)])
  (check-equal? (decode-request trace (list-ref case 4))
                (list-ref case 5)))

;; A host call in an unselected lambda branch remains unforced.
(define skipped-calls 0)
(define (skipped-host request)
  (set! skipped-calls (add1 skipped-calls))
  (object-ok UNIT))
(define skipped-connect
  (apply2 (lazy-apply make-tcp-connect skipped-host)
          remote
          port))
(define selected-fallback
  (apply3 typed-if FALSE skipped-connect (object-ok UNIT)))
(check-ok-unit selected-fallback)
(check-equal? skipped-calls 0)

;; Every argument position uses the generalized strict checker. An early Error
;; remains a unary absorber until exactly the remaining arguments are supplied.
(define contract-baseline calls)
(for ([case (in-list wrapper-cases)])
  (define wrapper
    (lazy-apply (car case) fake-host))
  (define name (cadr case))
  (define expected-types (caddr case))
  (define arguments (list-ref case 3))
  (for ([position (in-range (length arguments))])
    (define prefix (take arguments position))
    (define remaining (drop arguments (add1 position)))
    (define value
      (lazy-apply (apply-arguments wrapper prefix) FALSE))
    (for ([argument (in-list remaining)])
      (check-equal? (procedure-arity (lazy-force value)) 1)
      (set! value (lazy-apply value argument)))
    (check-contract-frame value
                          name
                          (add1 position)
                          (list-ref expected-types position)))

  (define incoming
    (lazy-apply wrapper invalid-nat-error))
  (for ([argument (in-list (cdr arguments))])
    (check-equal? (procedure-arity (lazy-force incoming)) 1)
    (set! incoming (lazy-apply incoming argument)))
  (check-true (typed-value? error-type incoming))
  (check-equal? (error-kind-integer incoming) 2))

(check-equal? calls contract-baseline)

;; Expected host failure Results cross each wrapper unchanged and remain lazy.
(define failure-calls 0)
(define (failing-host request)
  (set! failure-calls (add1 failure-calls))
  (object-err invalid-nat-error))

(for ([case (in-list wrapper-cases)]
      [expected-calls (in-naturals 1)])
  (define pending
    (apply-arguments
     (lazy-apply (car case) failing-host)
     (list-ref case 3)))
  (check-equal? failure-calls (sub1 expected-calls))
  (check-true (bool->boolean (lazy-apply is-err pending)))
  (check-equal? failure-calls expected-calls)
  (check-equal?
   (error-kind-integer (lazy-apply unwrap-err pending))
   2)
  (check-true (bool->boolean (lazy-apply is-err pending)))
  (check-equal? failure-calls expected-calls))

;; Step 35.4: prepared Rat-based request constructors and wrappers. Ports,
;; backlog sizes, read limits, and handles are Rat objects validated as
;; nonnegative whole numbers in pure computation before any host request
;; exists; numeric request fields carry tagged Rat values.

(define rat-decoder object-rat->exact)

(define rat-port port)
(define rat-listen-port listen-port)
(define rat-backlog backlog)
(define rat-listener-handle listener-handle)
(define rat-connection-handle connection-handle)
(define rat-maximum maximum)

(define rat-request-cases
  (list
   (list make-tcp-connect-request
         (list remote rat-port)
         (list string-decoder string-decoder rat-decoder)
         (list #"tcp-connect" #"127.0.0.1" 8080))
   (list make-tcp-listen-request
         (list local rat-listen-port rat-backlog)
         (list string-decoder string-decoder rat-decoder rat-decoder)
         (list #"tcp-listen" #"" 0 16))
   (list make-tcp-accept-request
         (list rat-listener-handle)
         (list string-decoder rat-decoder)
         (list #"tcp-accept" 1))
   (list make-tcp-read-request
         (list rat-connection-handle rat-maximum)
         (list string-decoder rat-decoder rat-decoder)
         (list #"tcp-read" 2 65536))
   (list make-tcp-write-request
         (list rat-connection-handle payload)
         (list string-decoder rat-decoder byte-list-decoder)
         (list #"tcp-write" 2 #"A\0\200\377"))
   (list make-tcp-close-request
         (list rat-connection-handle)
         (list string-decoder rat-decoder)
         (list #"tcp-close" 2))))

(for ([case (in-list rat-request-cases)])
  (define request
    (apply-arguments (car case) (cadr case)))
  (check-true (typed-value? list-type request))
  (check-equal? (decode-request request (caddr case))
                (cadddr case)))

;; Negative and fractional numeric fields are INVALID-COUNT Errors
;; (kind 15) from the request constructor itself.
(define negative-rat (exact->object-rat -1))
(define fractional-rat (exact->object-rat 3/2))

(for ([bad-request
       (in-list
        (list (apply-arguments make-tcp-connect-request
                               (list remote negative-rat))
              (apply-arguments make-tcp-listen-request
                               (list local rat-listen-port fractional-rat))
              (apply-arguments make-tcp-accept-request
                               (list negative-rat))
              (apply-arguments make-tcp-read-request
                               (list rat-connection-handle fractional-rat))
              (apply-arguments make-tcp-write-request
                               (list negative-rat payload))
              (apply-arguments make-tcp-close-request
                               (list fractional-rat))))])
  (check-true (typed-value? error-type bad-request))
  (check-equal? (error-kind-integer bad-request) 15))

;; A well-typed List payload whose element is not a Byte is the documented
;; INVALID-BYTE contract Error (kind 16) from the request constructor
;; itself, before any request value exists.
(define non-byte-tcp-write
  (apply-arguments make-tcp-write-request
                   (list connection-handle
                         (apply2 typed-cons FALSE NIL))))
(check-true (typed-value? error-type non-byte-tcp-write))
(check-equal? (error-kind-integer non-byte-tcp-write) 16)

;; Valid Rat wrappers dispatch exactly the documented requests; the host is
;; never applied for an invalid numeric field, and the Error bubbles.
(define rat-calls 0)
(define rat-traces '())

(define (rat-fake-host request)
  (set! rat-calls (add1 rat-calls))
  (set! rat-traces (cons request rat-traces))
  (object-ok UNIT))

(define rat-wrapper-cases
  (list
   (list make-tcp-connect
         (list remote rat-port)
         (list string-decoder string-decoder rat-decoder)
         (list #"tcp-connect" #"127.0.0.1" 8080))
   (list make-tcp-listen
         (list local rat-listen-port rat-backlog)
         (list string-decoder string-decoder rat-decoder rat-decoder)
         (list #"tcp-listen" #"" 0 16))
   (list make-tcp-accept
         (list rat-listener-handle)
         (list string-decoder rat-decoder)
         (list #"tcp-accept" 1))
   (list make-tcp-read
         (list rat-connection-handle rat-maximum)
         (list string-decoder rat-decoder rat-decoder)
         (list #"tcp-read" 2 65536))
   (list make-tcp-write
         (list rat-connection-handle payload)
         (list string-decoder rat-decoder byte-list-decoder)
         (list #"tcp-write" 2 #"A\0\200\377"))
   (list make-tcp-close
         (list rat-connection-handle)
         (list string-decoder rat-decoder)
         (list #"tcp-close" 2))))

(define rat-pending-results
  (for/list ([case (in-list rat-wrapper-cases)])
    (define wrapper
      (lazy-apply (car case) rat-fake-host))
    (check-equal? (procedure-arity (lazy-force wrapper)) 1)
    (apply-arguments wrapper (cadr case))))

(check-equal? rat-calls 0)

(for ([pending (in-list rat-pending-results)]
      [expected-calls (in-naturals 1)])
  (check-ok-unit pending)
  (check-equal? rat-calls expected-calls))

(for ([trace (in-list (reverse rat-traces))]
      [case (in-list rat-wrapper-cases)])
  (check-equal? (decode-request trace (caddr case))
                (cadddr case)))

;; An invalid numeric field bubbles from the wrapper without a host call.
(define invalid-field-calls rat-calls)
(for ([bad-value
       (in-list
        (list (apply2 (lazy-apply make-tcp-connect rat-fake-host)
                      remote
                      negative-rat)
              (apply2 (lazy-apply make-tcp-read rat-fake-host)
                      rat-connection-handle
                      fractional-rat)
              (lazy-apply (lazy-apply make-tcp-close rat-fake-host)
                          negative-rat)))])
  (check-true (typed-value? error-type bad-value))
  (check-equal? (error-kind-integer bad-value) 15))
(check-equal? rat-calls invalid-field-calls)

;; Wrong argument types remain ordinary strict mismatches expecting RAT.
(check-contract-frame
 (apply2 (lazy-apply make-tcp-connect rat-fake-host)
         remote
         FALSE)
 #"tcp-connect"
 2
 7)
(check-equal? rat-calls invalid-field-calls)
