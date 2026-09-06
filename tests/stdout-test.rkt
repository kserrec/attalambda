#lang racket/base

(require rackunit
         (only-in "../readers/type-tag.rkt" type-tag->integer)
         (only-in "../core/unit.rkt" UNIT)
         racket/promise
         "../core/errors.rkt"
         "../core/lists.rkt"
         "../core/objects.rkt"
         "../core/result.rkt"
         "../core/tags.rkt"
         (only-in "../core/typed-logic.rkt" TRUE)
         "../effects/protocol.rkt"
         "../effects/stdout.rkt"
         "../readers/bool.rkt"
         "../readers/error.rkt"
         "../readers/raw-boolean.rkt"
         "../runtime/codec.rkt"
         "helpers/lazy.rkt")

(define (typed-value? type value)
  (raw-boolean->boolean
   (apply2 raw-is-type type value)))

(define request
  (lazy-apply make-stdout-request
              (bytes->object-string #"A\0\377")))
(define request-parts
  (object-list->host-list request))

(check-true (typed-value? list-type request))
(check-equal? (length request-parts) 2)
(check-equal? (object-string->bytes (car request-parts))
              #"stdout")
(check-equal? (object-string->bytes (cadr request-parts))
              #"A\0\377")

(define calls 0)
(define traces '())

(define (fake-host request-value)
  (set! calls (add1 calls))
  (set! traces (cons request-value traces))
  (object-ok UNIT))

(define stdout-with-fake
  (lazy-apply make-stdout fake-host))

(check-equal? (procedure-arity
               (lazy-force stdout-with-fake))
              1)

(define pending
  (lazy-apply stdout-with-fake
              (bytes->object-string #"hello")))

(check-equal? calls 0)
(check-equal? traces '())
(check-true (bool->boolean
             (lazy-apply is-ok pending)))
(check-equal? calls 1)
(check-equal?
 (type-tag->integer
  (lazy-apply raw-object-type
              (lazy-apply unwrap-ok pending)))
 8)
(check-equal? calls 1)

(define traced-request
  (object-list->host-list (car traces)))
(check-equal? (object-string->bytes (car traced-request))
              #"stdout")
(check-equal? (object-string->bytes (cadr traced-request))
              #"hello")

;; A contract Error is decided before the injected host is called.
(define wrong-type
  (lazy-apply stdout-with-fake TRUE))
(check-true (typed-value? error-type wrong-type))
(check-equal? (error-value->string wrong-type)
              "stdout(arg1 expected STRING got BOOL)")
(check-equal? calls 1)

(define incoming-error
  (lazy-apply stdout-with-fake invalid-nat-error))
(check-true (typed-value? error-type incoming-error))
(check-equal? (error-value->string incoming-error)
              "INVALID-NAT\n  -> stdout(arg1 expected STRING)")
(check-equal? calls 1)

;; Result values from an injected host cross the wrapper unchanged.
(define failure-calls 0)
(define (failing-fake request-value)
  (set! failure-calls (add1 failure-calls))
  (object-err invalid-nat-error))

(define stdout-with-failure
  (lazy-apply make-stdout failing-fake))
(define expected-failure
  (lazy-apply stdout-with-failure
              (bytes->object-string #"ignored")))

(check-equal? failure-calls 0)
(check-true (bool->boolean
             (lazy-apply is-err expected-failure)))
(check-equal? failure-calls 1)
(check-true (typed-value?
             error-type
             (lazy-apply unwrap-err expected-failure)))
(check-equal? failure-calls 1)
