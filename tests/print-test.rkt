#lang racket/base

(require rackunit racket/promise
         (only-in "../core/function-names.rkt"
                  print-function-name value-to-string-function-name)
         "../core/errors.rkt" "../core/lists.rkt" "../core/result.rkt"
         (only-in "../core/typed-logic.rkt" TRUE) "../core/unit.rkt"
         "../effects/print.rkt" "../effects/stdout.rkt"
         "../runtime/codec.rkt" "../readers/error.rkt"
         "helpers/lazy.rkt" "helpers/values.rkt")

(check-equal? (object-string->bytes print-function-name) #"print")
(check-equal? (object-string->bytes value-to-string-function-name) #"value-to-string")

(define calls '())
(define answer (object-ok UNIT))
(define (fake-stdout value)
  (set! calls (cons (object-string->bytes value) calls))
  answer)
(define printer (lazy-apply make-print fake-stdout))
(check-equal? (procedure-arity (lazy-force make-print)) 1)
(check-equal? (procedure-arity (lazy-force printer)) 1)
(check-equal? calls '())

(define pending (lazy-apply printer (exact->typed-rat 42)))
(check-equal? calls '())
(check-eq? (lazy-force pending) (lazy-force answer))
(check-equal? calls '(#"42"))
(void (lazy-force pending))
(check-equal? calls '(#"42"))

;; Composing stdout passes every success or failure through without wrapping
;; it or adding a print frame. No newline is supplied by the composition.
(for ([next-answer (in-list (list (object-ok UNIT)
                                  (lazy-apply raw-make-err invalid-nat-error)
                                  invalid-nat-error))])
  (set! answer next-answer)
  (check-eq? (lazy-force (lazy-apply printer TRUE)) (lazy-force answer))
  (check-equal? (car calls) #"TRUE"))
(void (lazy-force (lazy-apply printer (bytes->object-string #"hello"))))
(check-equal? (car calls) #"\"hello\"")
(void (lazy-force (lazy-apply printer divide-by-zero-error)))
(check-equal? (car calls) #"ERROR(DIVIDE-BY-ZERO)")
(void (lazy-force (lazy-apply printer (apply2 raw-cons (exact->typed-rat 1)
                                            (apply2 raw-cons TRUE NIL)))))
(check-equal? (car calls) #"[1, TRUE]")

;; Trace the real stdout wrapper's existing host protocol, not only a spy on
;; the composition argument. The output request contains exactly one String.
(define requests '())
(define (fake-host request)
  (define parts (object-list->host-list request))
  (set! requests
        (cons (map object-string->bytes parts) requests))
  (object-ok UNIT))
(define stdout (lazy-apply make-stdout fake-host))
(define composed (lazy-apply make-print stdout))
(void (lazy-force (lazy-apply composed (bytes->object-string #"A\0\377"))))
(check-equal? requests '((#"stdout" #"\"A\\x00\\xFF\"")))
(void (lazy-force (lazy-apply stdout (bytes->object-string #"A\0\377"))))
(check-equal? (car requests) '(#"stdout" #"A\0\377"))
(define before (length requests))
(check-equal? (error-value->string (lazy-apply stdout (exact->typed-rat 1)))
              "stdout(arg1 expected STRING got RAT)")
(check-equal? (length requests) before)
