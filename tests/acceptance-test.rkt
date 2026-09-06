#lang racket/base

(require rackunit
         racket/list
         racket/promise
         racket/runtime-path
         "../core/chars.rkt"
         "../core/errors.rkt"
         "../core/lists.rkt"
         "../core/objects.rkt"
         "../core/result.rkt"
         "../core/strings.rkt"
         "../core/tags.rkt"
         (only-in "../core/typed-logic.rkt"
                  FALSE
                  TRUE
                  typed-if)
         "../core/binary-nat.rkt"
         "../core/logic.rkt"
         "../core/rat.rkt"
         "../core/typed-rat.rkt"
         "../readers/bool.rkt"
         "../readers/char.rkt"
         "../readers/error.rkt"
         "../readers/list.rkt"
         "../readers/rat.rkt"
         "../readers/raw-boolean.rkt"
         "../readers/string.rkt"
         "../readers/type-tag.rkt"
         "../tooling/check-purity.rkt"
         "helpers/lazy.rkt"
         (only-in "helpers/values.rkt"
                  apply2
                  apply3
                  host-bits->raw
                  whole-rat-object
                  rat-object->number))

(define (object-type-name value)
  (type-tag->string
   (lazy-apply raw-object-type value)))

(define ZERO (whole-rat-object 0))
(define ONE (whole-rat-object 1))
(define TWO (whole-rat-object 2))
(define EIGHT (whole-rat-object 8))
(define TEN (whole-rat-object 10))

(define ADD typed-rat-add)
(define MULT typed-rat-mult)
(define DIV typed-rat-div)

(define hi
  (lazy-apply
   MAKE-STRING
   (apply2 typed-cons
           h
           (apply2 typed-cons i NIL))))

(define space-world
  (lazy-apply
   MAKE-STRING
   (apply2 typed-cons
           SPACE
           (apply2 typed-cons
                   w
                   (apply2 typed-cons
                           o
                           (apply2 typed-cons
                                   r
                                   (apply2 typed-cons
                                           l
                                           (apply2 typed-cons
                                                   d
                                                   NIL))))))))

(define greeting
  (apply3 typed-if
          TRUE
          (apply2 STRING-APPEND hi space-world)
          EMPTY-STRING))

(check-equal? (object-type-name TRUE) "BOOL")
(check-equal? (object-type-name FALSE) "BOOL")
(check-equal? (object-type-name ZERO) "RAT")
(check-equal? (object-type-name NIL) "LIST")
(check-equal? (object-type-name A) "CHAR")
(check-equal? (object-type-name greeting) "STRING")

(check-false (bool->boolean
              (lazy-apply typed-is-nil
                          (apply2 typed-cons TRUE NIL))))
(check-equal? (string-value->string greeting)
              "hi world")
(check-equal? (char-value->string
               (lazy-apply STRING-HEAD greeting))
              "h")
(check-equal? (rat-object->number
               (lazy-apply STRING-LENGTH greeting))
              8)

(define one-hundred
  (apply2 MULT TEN TEN))

(check-equal? (rat-object->number one-hundred)
              100)
(check-equal? (list->host-list
               (lazy-apply raw-rat-magnitude-bits
                           (lazy-apply raw-object-value one-hundred))
               raw-boolean->boolean)
              '(#t #t #f #f #t #f #f))

(define division-success
  (apply2 DIV EIGHT TWO))
(define division-failure
  (apply2 DIV EIGHT ZERO))

(check-equal? (object-type-name division-success)
              "RESULT")
(check-true (bool->boolean
             (lazy-apply is-ok division-success)))
(check-equal? (rat-object->number
               (lazy-apply unwrap-ok division-success))
              4)
(check-true (bool->boolean
             (lazy-apply is-err division-failure)))
(check-equal? (error-value->string
               (lazy-apply unwrap-err division-failure))
              "DIVIDE-BY-ZERO")

(define contract-failure
  (apply2 ADD TRUE ONE))

(check-equal? (object-type-name contract-failure)
              "ERROR")
(check-equal? (error-value->string contract-failure)
              "add(arg1 expected RAT got BOOL)")

(define-runtime-path core-directory
  "../core")

(define production-results
  (files-violations
   (production-files-under core-directory)))

(check-equal? (length production-results)
              23)
(check-equal? (append-map cdr production-results)
              '())
