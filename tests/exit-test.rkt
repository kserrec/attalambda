#lang racket/base

(require rackunit
         racket/promise
         (only-in "../core/binary-nat.rkt" raw-one-bits)
         "../core/errors.rkt"
         "../core/lists.rkt"
         "../core/logic.rkt"
         "../core/objects.rkt"
         "../core/pair.rkt"
         "../core/tags.rkt"
         (only-in "../core/typed-logic.rkt" TRUE FALSE typed-if)
         (only-in "../core/unit.rkt" UNIT)
         "../effects/exit.rkt"
         "../effects/protocol.rkt"
         "../readers/raw-boolean.rkt"
         "../readers/type-tag.rkt"
         "../runtime/codec.rkt"
         "helpers/lazy.rkt")

(define (error-kind value)
  (check-true
   (raw-boolean->boolean (apply2 raw-is-type error-type value)))
  (type-tag->integer
   (lazy-apply raw-error-root-kind (lazy-apply raw-error-root value))))

(define (check-exit-frame value position expected-type)
  (define frames
    (object-list->host-list (lazy-apply raw-error-frames value)))
  (check-equal? (length frames) 1)
  (define frame (car frames))
  (check-equal? (object-string->bytes
                 (lazy-apply raw-error-frame-function-name frame))
                #"exit")
  (check-equal? (type-tag->integer
                 (lazy-apply raw-error-frame-argument-position frame))
                position)
  (check-equal? (type-tag->integer
                 (lazy-apply raw-error-frame-expected-type frame))
                expected-type))

(define (check-request request status)
  (define parts (object-list->host-list request))
  (check-false (codec-failure? parts))
  (check-equal? (length parts) 2)
  (check-equal? (object-string->bytes (car parts)) #"exit")
  (check-equal? (object-rat->exact (cadr parts)) status))

(check-equal? (procedure-arity (lazy-force make-exit)) 1)
(check-equal? (procedure-arity (lazy-force make-exit-request)) 1)
(for ([status (in-list '(0 1))])
  (define argument (exact->object-rat status))
  (check-request (lazy-apply make-exit-request argument) status)
  (define calls 0)
  (define returned (object-ok UNIT))
  (define wrapper
    (lazy-apply make-exit
                (lambda (request)
                  (set! calls (add1 calls))
                  (check-request request status)
                  returned)))
  (check-equal? (procedure-arity (lazy-force wrapper)) 1)
  (define pending (lazy-apply wrapper argument))
  (check-equal? calls 0)
  (check-eq? (lazy-force pending) (lazy-force returned))
  (check-equal? calls 1)
  (check-eq? (lazy-force pending) (lazy-force returned))
  (check-equal? calls 1))

(define invalid-calls 0)
(define rejecting-wrapper
  (lazy-apply make-exit
              (lambda (request)
                (set! invalid-calls (add1 invalid-calls))
                UNIT)))

;; Both the request constructor and injected wrapper share the generalized
;; Rat contract. A contract failure cannot reach even a permissive fake host.
(for ([function (in-list (list make-exit-request rejecting-wrapper))])
  (for ([wrong-type (in-list (list TRUE NIL UNIT (bytes->object-string #"0")))])
    (define failure (lazy-apply function wrong-type))
    (check-equal? (error-kind failure) 0)
    (check-exit-frame failure 1 7))
  (for ([status (in-list '(-1 2 1/2 -1/2 255))])
    (define failure (lazy-apply function (exact->object-rat status)))
    (check-equal? (error-kind failure) (type-tag->integer invalid-count-kind))
    (check-exit-frame failure 0 0))
  (define incoming (lazy-apply function invalid-nat-error))
  (check-equal? (error-kind incoming) 2)
  (check-eq? (lazy-force (lazy-apply raw-error-root incoming))
             (lazy-force (lazy-apply raw-error-root invalid-nat-error)))
  (check-exit-frame incoming 1 7))
(check-equal? invalid-calls 0)

;; An unselected exit remains unforced. Fake-host returns are not interpreted
;; as statuses or forced into Result: even Unit or Error crosses unchanged.
(define skipped
  (lazy-apply rejecting-wrapper (exact->object-rat 1)))
(check-eq? (lazy-force (apply3 typed-if FALSE skipped UNIT)) (lazy-force UNIT))
(check-equal? invalid-calls 0)
(for ([returned (in-list (list UNIT invalid-nat-error (object-err invalid-nat-error)))])
  (define calls 0)
  (define pending
    (lazy-apply
     (lazy-apply make-exit
                 (lambda (request) (set! calls (add1 calls)) returned))
     (exact->object-rat 0)))
  (check-equal? calls 0)
  (check-eq? (lazy-force pending) (lazy-force returned))
  (check-equal? calls 1)
  (check-eq? (lazy-force pending) (lazy-force returned))
  (check-equal? calls 1))

;; The closed protocol retains its separate InvalidHostRequest contract for
;; malformed direct requests. No real process-exit capability is used here.
(define dispatch-calls 0)
(define bridge
  (lazy-apply make-host-bridge
              (lambda (request)
                (set! dispatch-calls (add1 dispatch-calls))
                UNIT)))
(for ([status (in-list '(0 1))])
  (check-eq?
   (lazy-force
    (lazy-apply bridge
                (lazy-apply make-exit-request (exact->object-rat status))))
   (lazy-force UNIT)))
(check-equal? dispatch-calls 2)

(define noncanonical-one
  (apply2 raw-make-object rat-type
          (apply2 raw-pair
                  (apply2 raw-pair raw-true
                          (apply2 raw-cons raw-false
                                  (apply2 raw-cons raw-true NIL)))
                  raw-one-bits)))
(for ([case
       (in-list
        (list (list '() #"wrong-arity")
              (list (list (exact->object-rat 0) TRUE) #"wrong-arity")
              (list (list TRUE) #"wrong-type")
              (list (list (exact->object-rat 2)) #"out-of-range")
              (list (list (exact->object-rat -1)) #"wrong-type")
              (list (list (exact->object-rat 1/2)) #"wrong-type")
              (list (list noncanonical-one) #"wrong-type")))])
  (define failure
    (lazy-apply bridge
                (host-list->object-list (cons exit-operation (car case)))))
  (check-equal? (error-kind failure) 7)
  (define details
    (lazy-apply raw-error-root-details (lazy-apply raw-error-root failure)))
  (check-equal? (object-string->bytes (lazy-apply raw-first details)) #"exit")
  (check-equal? (object-string->bytes (lazy-apply raw-second details)) (cadr case)))
(check-equal? dispatch-calls 2)
