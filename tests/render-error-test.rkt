#lang racket/base

(require rackunit racket/list racket/promise
         "../core/errors.rkt" "../core/function-names.rkt"
         "../core/objects.rkt" "../core/render-error.rkt" "../core/tags.rkt"
         "../core/to-string.rkt" "../readers/error.rkt" "../readers/string.rkt"
         "helpers/lazy.rkt" "helpers/values.rkt")

(define (metadata n)
  (for/fold ([tag church-zero]) ([i (in-range n)])
    (lazy-apply church-succ tag)))
(define (check-diagnostic value expected)
  (define body (lazy-apply raw-error-diagnostic-string value))
  (define display (lazy-apply error-to-string value))
  (check-equal? (object-tag body) 6)
  (check-equal? (object-tag display) 6)
  (check-equal? (string-value->string body) expected)
  (check-equal? (string-value->string display) (string-append "ERROR(" expected ")"))
  (check-equal? (error-value->string value) expected))

(for ([entry (in-list
              '((1 "EMPTY-LIST") (2 "INVALID-NAT") (3 "DIVIDE-BY-ZERO")
                (4 "INVALID-CHAR") (5 "INVALID-STRING") (6 "WRONG-RESULT-VARIANT")
                (14 "NON-WHOLE-EXPONENT") (15 "INVALID-COUNT") (16 "INVALID-BYTE")))])
  (check-diagnostic (lazy-apply raw-make-root-error (metadata (first entry)))
                    (second entry)))
(for ([n (in-list '(7 8 9 10 11 12 13 17 42))])
  (check-diagnostic (lazy-apply raw-make-root-error (metadata n))
                    (format "ERROR-KIND:~a" n)))

(for ([entry (in-list '((0 "ERROR") (1 "BOOL") (2 "LIST") (3 "TYPE:3")
                       (4 "RESULT") (5 "CHAR") (6 "STRING") (7 "RAT")
                       (8 "UNIT") (9 "BYTE") (10 "OPTION") (11 "MAP")
                       (42 "TYPE:42")))])
  (check-diagnostic
   (apply3 raw-make-type-mismatch-error (metadata 12)
           (metadata (first entry)) (metadata 99))
   (format "TYPE-MISMATCH(arg12 expected ~a got TYPE:99)" (second entry))))

(define (frame value name position expected)
  (apply2 raw-add-error-frame value
          (apply3 raw-make-error-frame name position expected)))
(define mismatch
  (apply3 raw-make-type-mismatch-error argument-position-two rat-type bool-type))
(define first-frame (frame mismatch add-function-name argument-position-two rat-type))
(check-diagnostic first-frame "add(arg2 expected RAT got BOOL)")
(check-diagnostic
 (frame first-frame string-length-function-name argument-position-one string-type)
 "add(arg2 expected RAT got BOOL)\n  -> string-length(arg1 expected STRING)")
(check-diagnostic
 (frame (frame invalid-nat-error head-function-name result-position error-type)
        rat-to-string-function-name argument-position-one rat-type)
 "INVALID-NAT\n  -> head(result)\n  -> rat-to-string(arg1 expected RAT)")
(check-diagnostic
 (frame mismatch head-function-name result-position (delay (error 'unused-type)))
 "head(result)")
;; Non-mismatch kinds never inspect their unused root details.
(check-diagnostic
 (apply2 raw-make-error
         (apply2 raw-make-error-root (metadata 8) (delay (error 'unused-details))) NIL)
 "ERROR-KIND:8")

(define wrong (lazy-apply error-to-string (exact->typed-rat 5)))
(check-equal? (object-tag wrong) 0)
(check-diagnostic wrong "error-to-string(arg1 expected ERROR got RAT)")
