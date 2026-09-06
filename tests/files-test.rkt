#lang racket/base

(require rackunit
         (only-in "../core/unit.rkt" UNIT)
         racket/promise
         "../core/errors.rkt"
         "../core/lists.rkt"
         "../core/objects.rkt"
         "../core/result.rkt"
         "../core/tags.rkt"
         (only-in "../core/typed-logic.rkt" TRUE)
         "../effects/files.rkt"
         "../readers/bool.rkt"
         "../readers/raw-boolean.rkt"
         "../readers/type-tag.rkt"
         "../runtime/codec.rkt"
         "helpers/lazy.rkt")

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

(define path-value
  (bytes->object-string #"relative/\316\273.bin"))

;; File contents are a List of Byte since the Step 37.3 switch.
(define bytes-value
  (bytes->object-byte-list #"\0\200\377contents"))

(define read-request
  (lazy-apply make-read-file-request path-value))

(define read-parts
  (object-list->host-list read-request))

(check-true (typed-value? list-type read-request))
(check-equal? (length read-parts) 2)
(check-equal? (object-string->bytes (car read-parts))
              #"read-file")
(check-equal? (object-string->bytes (cadr read-parts))
              #"relative/\316\273.bin")

(define write-request
  (apply2 make-write-file-request path-value bytes-value))

(define write-parts
  (object-list->host-list write-request))

(check-true (typed-value? list-type write-request))
(check-equal? (length write-parts) 3)
(check-equal? (object-string->bytes (car write-parts))
              #"write-file")
(check-equal? (object-string->bytes (cadr write-parts))
              #"relative/\316\273.bin")
(check-equal? (object-byte-list->bytes (caddr write-parts))
              #"\0\200\377contents")

(define calls 0)
(define traces '())

(define (fake-host request-value)
  (set! calls (add1 calls))
  (set! traces (cons request-value traces))
  (object-ok UNIT))

(define read-with-fake
  (lazy-apply make-read-file fake-host))

(define write-with-fake
  (lazy-apply make-write-file fake-host))

(check-equal? (procedure-arity (lazy-force read-with-fake)) 1)
(check-equal? (procedure-arity (lazy-force write-with-fake)) 1)

;; Construction and partial application remain pure. The fake host runs only
;; when the final Result is demanded, and a cached force does not repeat it.
(define pending-read
  (lazy-apply read-with-fake path-value))

(check-equal? calls 0)
(check-true (bool->boolean
             (lazy-apply is-ok pending-read)))
(check-equal? calls 1)
(check-equal?
 (type-tag->integer
  (lazy-apply raw-object-type
              (lazy-apply unwrap-ok pending-read)))
 8)
(check-equal? calls 1)

(define pending-write-function
  (lazy-apply write-with-fake path-value))

(check-equal? calls 1)
(check-equal? (procedure-arity
               (lazy-force pending-write-function))
              1)

(define pending-write
  (lazy-apply pending-write-function bytes-value))

(check-equal? calls 1)
(check-true (bool->boolean
             (lazy-apply is-ok pending-write)))
(check-equal? calls 2)
(check-equal?
 (type-tag->integer
  (lazy-apply raw-object-type
              (lazy-apply unwrap-ok pending-write)))
 8)
(check-equal? calls 2)

(define traced-write
  (object-list->host-list (car traces)))
(define traced-read
  (object-list->host-list (cadr traces)))

(check-equal? (object-string->bytes (car traced-write))
              #"write-file")
(check-equal? (object-string->bytes (cadr traced-write))
              #"relative/\316\273.bin")
(check-equal? (object-byte-list->bytes (caddr traced-write))
              #"\0\200\377contents")
(check-equal? (map object-string->bytes traced-read)
              (list #"read-file"
                    #"relative/\316\273.bin"))

;; Contract failures are decided wholly in the pure wrapper. An early first-
;; argument failure absorbs exactly the remaining curried write argument.
(define wrong-read
  (lazy-apply read-with-fake TRUE))
(check-contract-frame wrong-read #"read-file" 1 6)
(check-equal? calls 2)

(define wrong-write-first
  (lazy-apply write-with-fake TRUE))
(check-equal? (procedure-arity (lazy-force wrong-write-first)) 1)
(define absorbed-write-error
  (lazy-apply wrong-write-first bytes-value))
(check-contract-frame absorbed-write-error #"write-file" 1 6)
(check-equal? calls 2)

(define wrong-write-second
  (lazy-apply
   (lazy-apply write-with-fake path-value)
   TRUE))
(check-contract-frame wrong-write-second #"write-file" 2 2)
(check-equal? calls 2)

;; A well-typed List whose element is not a Byte never reaches the host:
;; the constructor's raw-byte-list-valid? guard answers the documented
;; INVALID-BYTE contract Error (kind 16) before any request value exists.
(define non-byte-write
  (lazy-apply
   (lazy-apply write-with-fake path-value)
   (apply2 typed-cons TRUE NIL)))
(check-true (typed-value? error-type non-byte-write))
(check-equal? (error-kind-integer non-byte-write) 16)
(check-equal? calls 2)

(define incoming-read-error
  (lazy-apply read-with-fake invalid-nat-error))
(check-true (typed-value? error-type incoming-read-error))
(check-equal? (error-kind-integer incoming-read-error) 2)
(check-equal? calls 2)

(define incoming-write-first
  (lazy-apply write-with-fake invalid-nat-error))
(check-equal? (procedure-arity (lazy-force incoming-write-first)) 1)
(define absorbed-incoming-write
  (lazy-apply incoming-write-first bytes-value))
(check-true (typed-value? error-type absorbed-incoming-write))
(check-equal? (error-kind-integer absorbed-incoming-write) 2)
(check-equal? calls 2)

;; An injected host's expected failure crosses the wrapper unchanged.
(define failure-calls 0)
(define (failing-fake request-value)
  (set! failure-calls (add1 failure-calls))
  (object-err invalid-nat-error))

(define read-with-failure
  (lazy-apply make-read-file failing-fake))
(define expected-failure
  (lazy-apply read-with-failure path-value))

(check-equal? failure-calls 0)
(check-true (bool->boolean
             (lazy-apply is-err expected-failure)))
(check-equal? failure-calls 1)
(check-equal? (error-kind-integer
               (lazy-apply unwrap-err expected-failure))
              2)
(check-equal? failure-calls 1)
