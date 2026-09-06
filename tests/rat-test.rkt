#lang racket/base

(require rackunit
         racket/list
         racket/promise
         "../core/binary-nat.rkt"
         "../core/errors.rkt"
         "../core/int.rkt"
         "../core/lists.rkt"
         "../core/logic.rkt"
         "../core/objects.rkt"
         "../core/rat.rkt"
         "../core/result.rkt"
         "../readers/int.rkt"
         "../readers/list.rkt"
         "../readers/rat.rkt"
         "../readers/raw-boolean.rkt"
         "../readers/type-tag.rkt"
         "helpers/lazy.rkt"
         (only-in "helpers/values.rkt"
                  apply2
                  host-bits->raw
                  integer->raw-bits
                  integer->int))

(define (make-rat numerator denominator)
  (apply2 raw-make-rat
          (integer->int numerator)
          (integer->raw-bits denominator)))

(define (stored-numerator value)
  (int->integer (lazy-apply raw-rat-numerator value)))

(define (stored-denominator value)
  (for/fold ([total 0])
            ([bit (in-list
                   (list->host-list
                    (lazy-apply raw-rat-denominator value)
                    raw-boolean->boolean))])
    (+ (* total 2)
       (if bit 1 0))))

;; Construction reduces to lowest terms with a positive denominator, and
;; the reader observes the exact host rational.
(for* ([top (in-list '(-24 -7 -6 -5 -1 0 1 2 5 6 7 24 123456))]
       [bottom (in-list '(1 2 3 4 6 7 24 25 654321))])
  (define value (make-rat top bottom))
  (define expected (/ top bottom))
  (check-equal? (rat->number value) expected)
  (check-equal? (stored-numerator value) (numerator expected))
  (check-equal? (stored-denominator value) (denominator expected)))

;; Every zero is positive 0/1, including negative and non-normalized
;; spellings.
(for ([value (in-list
              (list (make-rat 0 1)
                    (make-rat 0 7)
                    (apply2 raw-make-rat
                            (apply2 raw-make-int
                                    raw-false
                                    (integer->raw-bits 0))
                            (integer->raw-bits 5))
                    (apply2 raw-make-rat
                            (integer->int 0)
                            (host-bits->raw '(#f #f #t #f)))))])
  (check-equal? (rat->number value) 0)
  (check-equal? (stored-numerator value) 0)
  (check-equal? (stored-denominator value) 1)
  (check-true
   (raw-boolean->boolean
    (lazy-apply raw-int-sign
                (lazy-apply raw-rat-numerator value)))))

;; A non-normalized denominator is normalized and reduced.
(let ([value (apply2 raw-make-rat
                     (integer->int 2)
                     (host-bits->raw '(#f #f #t #f #f)))])
  (check-equal? (rat->number value) 1/2)
  (check-equal? (stored-numerator value) 1)
  (check-equal? (stored-denominator value) 2))

;; Constants.
(check-equal? (rat->number raw-rat-zero) 0)
(check-equal? (stored-denominator raw-rat-zero) 1)
(check-equal? (rat->number raw-rat-one) 1)
(check-equal? (stored-denominator raw-rat-one) 1)

;; Constructor and selectors are chains of unary lambdas.
(check-equal?
 (procedure-arity (lazy-force raw-make-rat))
 1)
(check-equal?
 (procedure-arity
  (lazy-force
   (lazy-apply raw-make-rat (integer->int 3))))
 1)
(for ([function (in-list
                 (list raw-rat-numerator
                       raw-rat-denominator))])
  (check-equal?
   (procedure-arity (lazy-force function))
   1))

;; Step 34.2: ordinary rational operations, verified against Racket's
;; exact rational arithmetic through the one-way reader.

(define (exact->rat exact)
  (make-rat (numerator exact) (denominator exact)))

(define rational-operands
  '(-24 -7/3 -2 -3/2 -1 -1/2 -2/5 0 2/5 1/2 1 3/2 2 7/3 24 123456/7))

(for* ([left-exact (in-list rational-operands)]
       [right-exact (in-list rational-operands)])
  (define left (exact->rat left-exact))
  (define right (exact->rat right-exact))
  (define (binary-rat function)
    (apply2 function left right))
  (define (binary-boolean function)
    (raw-boolean->boolean (binary-rat function)))
  (check-equal? (rat->number (binary-rat raw-rat-add))
                (+ left-exact right-exact))
  (check-equal? (rat->number (binary-rat raw-rat-sub))
                (- left-exact right-exact))
  (check-equal? (rat->number (binary-rat raw-rat-mult))
                (* left-exact right-exact))
  (check-equal? (binary-boolean raw-rat-equal)
                (= left-exact right-exact))
  (check-equal? (binary-boolean raw-rat-less)
                (< left-exact right-exact))
  (check-equal? (binary-boolean raw-rat-less-equal)
                (<= left-exact right-exact))
  (check-equal? (binary-boolean raw-rat-greater)
                (> left-exact right-exact))
  (check-equal? (binary-boolean raw-rat-greater-equal)
                (>= left-exact right-exact)))

;; Unary operations, checks, and floor across signs and wholeness.
(for ([exact (in-list rational-operands)])
  (define value (exact->rat exact))
  (check-equal? (rat->number (lazy-apply raw-rat-negate value))
                (- exact))
  (check-equal? (rat->number (lazy-apply raw-rat-abs value))
                (abs exact))
  (check-equal? (rat->number (lazy-apply raw-rat-floor value))
                (floor exact))
  (check-equal? (stored-denominator
                 (lazy-apply raw-rat-floor value))
                1)
  (check-equal?
   (raw-boolean->boolean (lazy-apply raw-rat-is-zero value))
   (zero? exact))
  (check-equal?
   (raw-boolean->boolean (lazy-apply raw-rat-is-whole value))
   (integer? exact))
  (check-equal?
   (raw-boolean->boolean
    (lazy-apply raw-rat-is-nonnegative-whole value))
   (and (integer? exact) (>= exact 0))))

;; Zero-valued results are canonical positive 0/1.
(for ([value (in-list
              (list (apply2 raw-rat-add
                            (exact->rat 3/2)
                            (exact->rat -3/2))
                    (apply2 raw-rat-sub
                            (exact->rat 7/3)
                            (exact->rat 7/3))
                    (apply2 raw-rat-mult
                            (exact->rat -5/2)
                            (exact->rat 0))
                    (lazy-apply raw-rat-negate (exact->rat 0))))])
  (check-equal? (rat->number value) 0)
  (check-equal? (stored-denominator value) 1)
  (check-true
   (raw-boolean->boolean
    (lazy-apply raw-int-sign
                (lazy-apply raw-rat-numerator value)))))

;; Results are reduced: stored parts match Racket's canonical parts.
(for ([case (in-list '((1/6 1/3) (5/12 7/12) (-5/6 1/3) (3/4 -1/4)))])
  (define sum (apply2 raw-rat-add
                      (exact->rat (first case))
                      (exact->rat (second case))))
  (define expected (+ (first case) (second case)))
  (check-equal? (stored-numerator sum) (numerator expected))
  (check-equal? (stored-denominator sum) (denominator expected)))

;; Operations remain chains of unary lambdas.
(for ([function (in-list
                 (list raw-rat-add
                       raw-rat-sub
                       raw-rat-mult
                       raw-rat-equal
                       raw-rat-less
                       raw-rat-less-equal
                       raw-rat-greater
                       raw-rat-greater-equal))])
  (check-equal?
   (procedure-arity (lazy-force function))
   1)
  (check-equal?
   (procedure-arity
    (lazy-force
     (lazy-apply function (exact->rat 1/2))))
   1))

(for ([function (in-list
                 (list raw-rat-negate
                       raw-rat-abs
                       raw-rat-floor
                       raw-rat-is-zero
                       raw-rat-is-whole
                       raw-rat-is-nonnegative-whole))])
  (check-equal?
   (procedure-arity (lazy-force function))
   1))

;; Step 34.3: reciprocal, exact division, and whole-exponent powers with
;; explicit expected failures.

(define (result-payload result)
  (lazy-apply raw-object-value result))

(define (result-ok? result)
  (raw-boolean->boolean
   (lazy-apply raw-result-is-ok
               (result-payload result))))

(define (result-value result)
  (lazy-apply raw-result-value
              (result-payload result)))

(define (error-kind-number error-value)
  (type-tag->integer
   (lazy-apply raw-error-root-kind
               (lazy-apply raw-error-root error-value))))

(define (check-ok-rat result expected)
  (check-true (result-ok? result))
  (check-equal? (rat->number (result-value result)) expected))

(define (check-err-kind result expected-kind)
  (check-false (result-ok? result))
  (check-equal? (error-kind-number (result-value result))
                expected-kind))

;; Division agrees with Racket for nonzero divisors; zero divisors are
;; the expected DIVIDE-BY-ZERO failure, kind 3.
(for* ([left-exact (in-list rational-operands)]
       [right-exact (in-list rational-operands)])
  (define result
    (apply2 raw-rat-div
            (exact->rat left-exact)
            (exact->rat right-exact)))
  (if (zero? right-exact)
      (check-err-kind result 3)
      (check-ok-rat result (/ left-exact right-exact))))

;; Reciprocal.
(for ([exact (in-list rational-operands)])
  (define result
    (lazy-apply raw-rat-recip (exact->rat exact)))
  (if (zero? exact)
      (check-err-kind result 3)
      (check-ok-rat result (/ 1 exact))))

;; Whole exponents across positive, negative, zero, fractional, and large
;; cases, against Racket's exact exponentiation.
(for ([case (in-list
             '((0 0 1)
               (0 5 0)
               (5 0 1)
               (-7/3 0 1)
               (2 10 1024)
               (-2 10 1024)
               (-2 11 -2048)
               (3/2 5 243/32)
               (-3/2 5 -243/32)
               (-3/2 4 81/16)
               (2 -3 1/8)
               (-2 -3 -1/8)
               (2/5 -2 25/4)
               (-2/5 -3 -125/8)
               (3/2 64 3433683820292512484657849089281/18446744073709551616)
               (2 200 1606938044258990275541962092341162602522202993782792835301376)
               (-2 101 -2535301200456458802993406410752)))])
  (check-ok-rat
   (apply2 raw-rat-exp
           (exact->rat (first case))
           (exact->rat (second case)))
   (expt (first case) (second case))))

;; Every fractional exponent is the expected NON-WHOLE-EXPONENT failure,
;; kind 14 — including powers that would happen to be rational.
(for ([case (in-list '((4/9 1/2) (8/27 1/3) (2 1/2) (-3/2 7/3)
                       (1 1/2) (0 1/2)))])
  (check-err-kind
   (apply2 raw-rat-exp
           (exact->rat (first case))
           (exact->rat (second case)))
   14))

;; Zero raised to a negative whole exponent divides by zero.
(for ([exponent (in-list '(-1 -2 -5))])
  (check-err-kind
   (apply2 raw-rat-exp
           (exact->rat 0)
           (exact->rat exponent))
   3))

;; Powers of zero and negative results stay canonical.
(let ([result (apply2 raw-rat-exp (exact->rat 0) (exact->rat 5))])
  (check-true (result-ok? result))
  (check-equal? (stored-denominator (result-value result)) 1)
  (check-true
   (raw-boolean->boolean
    (lazy-apply raw-int-sign
                (lazy-apply raw-rat-numerator
                            (result-value result))))))

;; Division and powers remain chains of unary lambdas.
(for ([function (in-list (list raw-rat-div raw-rat-exp))])
  (check-equal?
   (procedure-arity (lazy-force function))
   1)
  (check-equal?
   (procedure-arity
    (lazy-force
     (lazy-apply function (exact->rat 1/2))))
   1))
(check-equal?
 (procedure-arity (lazy-force raw-rat-recip))
 1)

;; Step 35.3: prepared Rat-based List, String, and Char operations. The
;; public Nat surface stays active; these strict variants are verified
;; ahead of the single public switch.

(require (only-in "../core/list-nat.rkt"
                  typed-len-rat
                  typed-take-rat
                  typed-drop-rat)
         (only-in "../core/chars.rkt"
                  typed-make-char-rat
                  raw-char-value
                  A)
         (only-in "../core/strings.rkt"
                  typed-string-length-rat
                  MAKE-STRING)
         (only-in "../core/tags.rkt"
                  rat-type
                  list-type
                  char-type)
         (only-in "../readers/error.rkt"
                  error-value->string)
         (only-in "../readers/type-tag.rkt"
                  type-tag->integer)
         (only-in "../readers/list.rkt"
                  list->host-list))

(define (object-tag value)
  (type-tag->integer
   (lazy-apply raw-object-type value)))

(define (typed-whole-rat exact)
  (apply2 raw-make-object
          rat-type
          (apply2 raw-make-rat
                  (integer->int (numerator exact))
                  (integer->raw-bits (denominator exact)))))

(define (typed-rat-object->number value)
  (rat->number (lazy-apply raw-object-value value)))

(define (char-list length-integer)
  (apply2 raw-make-object
          list-type
          (let loop ([count length-integer])
            (if (zero? count)
                (lazy-apply raw-object-value (force NIL))
                (lazy-apply raw-object-value
                            (apply2 raw-cons
                                    A
                                    (apply2 raw-make-object
                                            list-type
                                            (loop (sub1 count)))))))))

;; Simpler: build lists with typed cons-like raw-cons directly.
(define (value-list values)
  (foldr
   (lambda (value tail)
     (apply2 raw-cons value tail))
   NIL
   values))

(define five-chars
  (value-list (list A A A A A)))

;; LEN returns a whole-valued Rat.
(let ([length-rat (lazy-apply typed-len-rat five-chars)])
  (check-equal? (object-tag length-rat) 7)
  (check-equal? (typed-rat-object->number length-rat) 5))

(let ([length-rat (lazy-apply typed-len-rat NIL)])
  (check-equal? (typed-rat-object->number length-rat) 0))

;; TAKE and DROP accept nonnegative whole Rat counts.
(define (list-length-of value)
  (length (list->host-list value (lambda (element) element))))

(for ([case (in-list '((0 0 5) (2 2 3) (5 5 0) (7 5 0)))])
  (define taken
    (apply2 typed-take-rat
            (typed-whole-rat (first case))
            five-chars))
  (define dropped
    (apply2 typed-drop-rat
            (typed-whole-rat (first case))
            five-chars))
  (check-equal? (object-tag taken) 2)
  (check-equal? (list-length-of taken) (second case))
  (check-equal? (list-length-of dropped) (third case)))

;; Negative and fractional counts are INVALID-COUNT Errors carrying the
;; operation's frame.
(check-equal?
 (error-value->string
  (apply2 typed-take-rat (typed-whole-rat -1) five-chars))
 "INVALID-COUNT\n  -> take(result)")

(check-equal?
 (error-value->string
  (apply2 typed-drop-rat (typed-whole-rat 1/2) five-chars))
 "INVALID-COUNT\n  -> drop(result)")

;; Wrong argument types remain ordinary type mismatches.
(check-equal?
 (error-value->string
  (apply2 typed-take-rat A five-chars))
 "take(arg1 expected RAT got CHAR)")

;; STRING-LENGTH returns a whole-valued Rat.
(let ([hello (lazy-apply MAKE-STRING five-chars)])
  (define length-rat
    (lazy-apply typed-string-length-rat hello))
  (check-equal? (object-tag length-rat) 7)
  (check-equal? (typed-rat-object->number length-rat) 5))

;; MAKE-CHAR accepts nonnegative whole Rat codes 0..255 only.
(for ([code (in-list '(0 65 255))])
  (define char-value
    (lazy-apply typed-make-char-rat (typed-whole-rat code)))
  (check-equal? (object-tag char-value) 5))

(check-equal?
 (error-value->string
  (lazy-apply typed-make-char-rat (typed-whole-rat 256)))
 "INVALID-CHAR\n  -> make-char(result)")

(check-equal?
 (error-value->string
  (lazy-apply typed-make-char-rat (typed-whole-rat -1)))
 "INVALID-COUNT\n  -> make-char(result)")

(check-equal?
 (error-value->string
  (lazy-apply typed-make-char-rat (typed-whole-rat 3/2)))
 "INVALID-COUNT\n  -> make-char(result)")
