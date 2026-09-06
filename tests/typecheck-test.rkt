#lang racket/base

(require rackunit
         racket/list
         racket/promise
         "../core/binary-nat.rkt"
         "../core/errors.rkt"
         "../core/function-names.rkt"
         "../core/lists.rkt"
         "../core/logic.rkt"
         "../core/objects.rkt"
         "../core/tags.rkt"
         "../core/typecheck.rkt"
         "../core/rat.rkt"
         "../macros/macros.rkt"
         "../readers/list.rkt"
         "../readers/rat.rkt"
         "../readers/raw-boolean.rkt"
         "../readers/string.rkt"
         "../readers/type-tag.rkt"
         "helpers/lazy.rkt")

(def raw-identity value =
  value)

(def raw-first-of-two first second =
  first)

(def raw-first-of-three first second third =
  first)

(def raw-first-of-five first second third fourth fifth =
  first)

(def raw-return-two ignored =
  ((raw-make-object rat-type)
   (raw-whole-rat
    (raw-nat-succ raw-one-bits))))

(def raw-return-error ignored =
  invalid-nat-error)

(define (apply4 function first second third fourth)
  (lazy-apply
   (apply3 function first second third)
   fourth))

(define (apply-all function arguments)
  (for/fold ([result function])
            ([argument (in-list arguments)])
    (lazy-apply result argument)))

(define (signature-of . types)
  (foldr
   (lambda (type tail)
     (apply2 raw-cons type tail))
   NIL
   types))

(define (checked raw-function signature return-policy)
  (apply4 make-typed-function
          raw-function
          and-function-name
          signature
          return-policy))

(define (typed-value? type value)
  (raw-boolean->boolean
   (apply2 raw-is-type type value)))

(define (read-bool-object object)
  (raw-boolean->boolean
   (lazy-apply raw-object-value object)))

(define (error-kind=? error kind)
  (raw-boolean->boolean
   (apply2
    raw-error-kind-equal
    (lazy-apply
     raw-error-root-kind
     (lazy-apply raw-error-root error))
    kind)))

(define (mismatch-details error)
  (lazy-apply
   raw-error-root-details
   (lazy-apply raw-error-root error)))

(define (frame->host frame)
  (list
   (type-tag->integer
    (lazy-apply
     raw-error-frame-argument-position
     frame))
   (type-tag->integer
    (lazy-apply
     raw-error-frame-expected-type
     frame))))

(define (error-frames->host error)
  (list->host-list
   (lazy-apply raw-error-frames error)
   frame->host))

(define (error-frame-names->host error)
  (list->host-list
   (lazy-apply raw-error-frames error)
   (lambda (frame)
     (string-value->string
      (lazy-apply
       raw-error-frame-function-name
       frame)))))

(define true-object
  (apply2 raw-make-object bool-type raw-true))

(define false-object
  (apply2 raw-make-object bool-type raw-false))

(define wrap-bool
  (lazy-apply raw-wrap-return bool-type))

(define zero-signature
  NIL)

(define one-signature
  (signature-of bool-type))

(define two-signature
  (signature-of bool-type bool-type))

(define three-signature
  (signature-of bool-type bool-type bool-type))

(define five-signature
  (signature-of bool-type
                bool-type
                bool-type
                bool-type
                bool-type))

(check-equal?
 (list->host-list five-signature
                  type-tag->integer)
 '(1 1 1 1 1))

(define zero-argument-result
  (checked raw-true
           zero-signature
           wrap-bool))

(check-true
 (typed-value? bool-type
               zero-argument-result))
(check-true
 (read-bool-object zero-argument-result))

(define checked-one
  (checked raw-identity
           one-signature
           wrap-bool))

(define checked-two
  (checked raw-first-of-two
           two-signature
           wrap-bool))

(define checked-three
  (checked raw-first-of-three
           three-signature
           wrap-bool))

(define checked-five
  (checked raw-first-of-five
           five-signature
           wrap-bool))

(check-false
 (read-bool-object
  (lazy-apply checked-one false-object)))
(check-true
 (read-bool-object
  (apply2 checked-two true-object false-object)))
(check-false
 (read-bool-object
  (apply3 checked-three
          false-object
          true-object
          true-object)))
(check-true
 (read-bool-object
  (apply-all checked-five
             (list true-object
                   false-object
                   false-object
                   false-object
                   false-object))))

(define after-one
  (lazy-apply checked-five true-object))

(define after-two
  (lazy-apply after-one false-object))

(define after-three
  (lazy-apply after-two false-object))

(define after-four
  (lazy-apply after-three false-object))

(for ([partial (in-list
                (list checked-five
                      after-one
                      after-two
                      after-three
                      after-four))])
  (check-equal?
   (procedure-arity
    (lazy-force partial))
   1))

(check-true
 (read-bool-object
  (lazy-apply after-four false-object)))

(define kept-two
  (lazy-apply
   (checked raw-return-two
            one-signature
            raw-keep-return)
   true-object))

(check-true
 (typed-value? rat-type kept-two))
(check-equal? (rat->number
               (lazy-apply raw-object-value kept-two))
              2)

(define kept-error
  (lazy-apply
   (checked raw-return-error
            one-signature
            raw-keep-return)
   true-object))

(check-true
 (error-kind=? kept-error
               invalid-nat-kind))
(check-equal? (error-frames->host kept-error)
              '())

(define rat-zero-object
  (apply2 raw-make-object rat-type raw-rat-zero))

(define valid-five
  (list true-object
        false-object
        true-object
        false-object
        true-object))

(for ([wrong-index (in-range 5)])
  (define failure
    (apply-all
     checked-five
     (list-set valid-five wrong-index rat-zero-object)))
  (define details
    (mismatch-details failure))
  (check-true
   (error-kind=? failure
                 type-mismatch-kind))
  (check-equal?
   (type-tag->integer
    (lazy-apply
     raw-type-mismatch-argument-position
     details))
   (add1 wrong-index))
  (check-equal?
   (type-tag->integer
    (lazy-apply
     raw-type-mismatch-expected-type
     details))
   1)
  (check-equal?
   (type-tag->integer
    (lazy-apply
     raw-type-mismatch-actual-type
     details))
   7)
  (check-equal? (error-frames->host failure)
                (list
                 (list (add1 wrong-index) 1)))
  (check-equal? (error-frame-names->host failure)
                '("AND")))

(define failure-after-first
  (lazy-apply checked-five rat-zero-object))

(define failure-with-three-remaining
  (lazy-apply
   failure-after-first
   (delay
     (error 'make-typed-function
            "forced ignored argument four applications early"))))

(define failure-with-two-remaining
  (lazy-apply
   failure-with-three-remaining
   (delay
     (error 'make-typed-function
            "forced ignored argument three applications early"))))

(define failure-with-one-remaining
  (lazy-apply
   failure-with-two-remaining
   (delay
     (error 'make-typed-function
            "forced ignored argument two applications early"))))

(for ([partial (in-list
                (list failure-after-first
                      failure-with-three-remaining
                      failure-with-two-remaining
                      failure-with-one-remaining))])
  (check-equal?
   (procedure-arity
    (lazy-force partial))
   1))

(define absorbed-first-failure
  (lazy-apply
   failure-with-one-remaining
   (delay
     (error 'make-typed-function
            "forced final ignored argument"))))

(check-true
 (error-kind=? absorbed-first-failure
               type-mismatch-kind))

(define failure-after-third
  (lazy-apply
   (lazy-apply
    (lazy-apply checked-five true-object)
    false-object)
   rat-zero-object))

(check-equal?
 (procedure-arity
  (lazy-force failure-after-third))
 1)

(define failure-after-one-ignored
  (lazy-apply
   failure-after-third
   (delay
     (error 'make-typed-function
            "forced first ignored argument after third-position failure"))))

(check-equal?
 (procedure-arity
  (lazy-force failure-after-one-ignored))
 1)

(define absorbed-third-failure
  (lazy-apply
   failure-after-one-ignored
   (delay
     (error 'make-typed-function
            "forced second ignored argument after third-position failure"))))

(check-true
 (error-kind=? absorbed-third-failure
               type-mismatch-kind))

(define bubbled-at-four
  (apply-all
   checked-five
   (list true-object
         false-object
         true-object
         invalid-nat-error
         (delay
           (error 'make-typed-function
                  "forced argument after incoming Error")))))

(check-true
 (error-kind=? bubbled-at-four
               invalid-nat-kind))
(check-equal? (error-frames->host bubbled-at-four)
              '((4 1)))
(check-equal? (error-frame-names->host bubbled-at-four)
              '("AND"))
(check-equal? (error-frames->host invalid-nat-error)
              '())

(check-equal?
 (procedure-arity
  (lazy-force make-typed-function))
 1)
(check-equal?
 (procedure-arity
  (lazy-force
   (lazy-apply make-typed-function
               raw-identity)))
 1)
(check-equal?
 (procedure-arity
  (lazy-force
   (apply2 make-typed-function
           raw-identity
           and-function-name)))
 1)
(check-equal?
 (procedure-arity
  (lazy-force
   (apply3 make-typed-function
           raw-identity
           and-function-name
           one-signature)))
 1)
(check-equal?
 (procedure-arity
  (lazy-force raw-wrap-return))
 1)
(check-equal?
 (procedure-arity
  (lazy-force wrap-bool))
 1)
(check-equal?
 (procedure-arity
  (lazy-force raw-keep-return))
 1)
