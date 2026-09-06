#lang racket/base

(require rackunit
         racket/promise
         "../core/errors.rkt"
         "../core/lists.rkt"
         "../core/logic.rkt"
         "../core/objects.rkt"
         "../core/tags.rkt"
         "../macros/macros.rkt"
         "../readers/bool.rkt"
         "../readers/list.rkt"
         "../readers/raw-boolean.rkt"
         "../readers/type-tag.rkt"
         "helpers/lazy.rkt")

(def test-not-object object =
  ((raw-make-object bool-type)
   (raw-not (raw-object-value object))))

(def test-bool-predicate object =
  (raw-object-value object))

(def test-object-and object accumulated =
  ((raw-and (raw-object-value object))
   accumulated))

(def test-object-or object accumulated =
  ((raw-or (raw-object-value object))
   accumulated))

(define (list-value? value)
  (raw-boolean->boolean
   (apply2 raw-is-type list-type value)))

(define (error-value? value)
  (raw-boolean->boolean
   (apply2 raw-is-type error-type value)))

(define (error-kind=? error kind)
  (raw-boolean->boolean
   (apply2
    raw-error-kind-equal
    (lazy-apply
     raw-error-root-kind
     (lazy-apply raw-error-root error))
    kind)))

(define (nil-value? value)
  (bool->boolean
   (lazy-apply typed-is-nil value)))

(define (prepend value tail)
  (apply2 typed-cons value tail))

(define (read-bool-object object)
  (raw-boolean->boolean
   (lazy-apply raw-object-value object)))

(define true-object
  (apply2 raw-make-object bool-type raw-true))

(define false-object
  (apply2 raw-make-object bool-type raw-false))

(define sample
  (prepend true-object
           (prepend false-object
                    (prepend false-object NIL))))

(check-true (list-value? NIL))
(check-true (nil-value? NIL))
(check-equal?
 (type-tag->integer
  (lazy-apply raw-object-type NIL))
 2)
(check-true
 (error-value?
  (raw-list-tail NIL)))
(check-false
 (raw-boolean->boolean raw-false))
(check-equal? (type-tag->integer church-zero)
              0)

(check-true (list-value? sample))
(check-false (nil-value? sample))
(check-equal?
 (list->host-list sample read-bool-object)
 '(#t #f #f))
(check-true
 (read-bool-object
  (lazy-apply typed-head sample)))
(check-equal?
 (list->host-list
  (lazy-apply typed-tail sample)
  read-bool-object)
 '(#f #f))

(define (every-tail-is-list? list)
  (and (list-value? list)
       (or (nil-value? list)
           (every-tail-is-list?
            (lazy-apply typed-tail list)))))

(check-true (every-tail-is-list? sample))

(define nested
  (prepend sample
           (prepend NIL NIL)))

(check-equal?
 (list->host-list
 nested
  (lambda (list)
    (list->host-list list read-bool-object)))
 '((#t #f #f) ()))

(check-true
 (error-value?
  (apply2 typed-cons true-object true-object)))
(check-true
 (error-value?
  (lazy-apply typed-head true-object)))
(check-true
 (error-value?
  (lazy-apply typed-tail true-object)))
(check-true
 (error-value?
  (lazy-apply typed-is-nil true-object)))
(check-true
 (error-value?
  (lazy-apply typed-head NIL)))
(check-true
 (error-value?
  (lazy-apply typed-tail NIL)))

(define incoming-error
  invalid-nat-error)

(define bubbled-values
  (list (apply2 typed-cons incoming-error NIL)
        (apply2 typed-cons false-object incoming-error)
        (lazy-apply typed-head incoming-error)
        (lazy-apply typed-tail incoming-error)
        (lazy-apply typed-is-nil incoming-error)))

(for ([bubbled (in-list bubbled-values)])
  (check-true (error-value? bubbled))
  (check-true
   (error-kind=? bubbled invalid-nat-kind)))

(define error-headed-list
  (apply2 raw-cons incoming-error NIL))

(check-false (nil-value? error-headed-list))
(check-true
 (error-value?
  (lazy-apply typed-head error-headed-list)))
(check-true
 (nil-value?
  (lazy-apply typed-tail error-headed-list)))

(define rejected-bool-object
  (apply2
   raw-make-object
   bool-type
   (delay
     (error 'typed-list-operation
            "forced non-list payload"))))

(define rejected-head-list
  (prepend rejected-bool-object NIL))

(check-false (nil-value? rejected-head-list))
(check-true
 (nil-value?
  (lazy-apply typed-tail rejected-head-list)))

(define bubbled-before-tail
  (apply2
   typed-cons
   incoming-error
   (delay
     (error 'typed-cons
            "forced tail after head Error"))))

(check-equal?
 (procedure-arity
  (lazy-force
   (lazy-apply typed-cons incoming-error)))
 1)
(check-true
 (error-kind=? bubbled-before-tail
               invalid-nat-kind))

(check-true
 (error-value?
  (apply2 typed-cons true-object rejected-bool-object)))
(check-true
 (error-value?
  (lazy-apply typed-head rejected-bool-object)))
(check-true
 (error-value?
  (lazy-apply typed-tail rejected-bool-object)))
(check-true
 (error-value?
  (lazy-apply typed-is-nil rejected-bool-object)))

(define one-true
  (prepend true-object NIL))

(check-equal?
 (list->host-list
  (apply2 raw-append sample one-true)
  read-bool-object)
 '(#t #f #f #t))
(check-equal?
 (list->host-list
  (apply2 raw-append NIL sample)
  read-bool-object)
 '(#t #f #f))
(check-equal?
 (list->host-list
  (apply2 raw-append sample NIL)
  read-bool-object)
 '(#t #f #f))
(check-equal?
 (list->host-list
  (lazy-apply raw-reverse sample)
  read-bool-object)
 '(#f #f #t))
(check-equal?
 (list->host-list
  (apply2 raw-map test-not-object sample)
  read-bool-object)
 '(#f #t #t))
(check-equal?
 (list->host-list
  (apply2 raw-filter test-bool-predicate sample)
  read-bool-object)
 '(#t))
(check-equal?
 (list->host-list
  (apply3 raw-fold raw-cons NIL sample)
  read-bool-object)
 '(#t #f #f))
(check-false
 (raw-boolean->boolean
  (apply3 raw-fold test-object-and raw-true sample)))
(check-true
 (raw-boolean->boolean
  (apply3 raw-fold test-object-or raw-false sample)))

(check-equal? (procedure-arity
               (lazy-force typed-cons))
              1)
(check-equal? (procedure-arity
               (lazy-force
                (lazy-apply typed-cons true-object)))
              1)
(check-equal? (procedure-arity
               (lazy-force typed-head))
              1)
(check-equal? (procedure-arity
               (lazy-force typed-tail))
              1)
(check-equal? (procedure-arity
               (lazy-force typed-is-nil))
              1)
(check-equal? (procedure-arity
               (lazy-force raw-fold))
              1)

;; HEAD decides emptiness from the tail's tag, which `cons` has already
;; validated for public Lists. A raw-built second cell has its tag read but
;; never its head or its own tail.
(define second-cell-with-unforced-contents
  (apply2 raw-cons
          (delay (error 'lists-test "second head was forced"))
          (delay (error 'lists-test "second tail was forced"))))

(define peekable-list
  (apply2 raw-cons
          true-object
          second-cell-with-unforced-contents))

(check-true
 (bool->boolean
  (lazy-apply typed-head peekable-list)))
(check-true
 (list-value?
  (lazy-apply typed-tail peekable-list)))
