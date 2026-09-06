#lang racket/base

(require rackunit
         racket/list
         racket/promise
         "../core/binary-nat.rkt"
         "../core/chars.rkt"
         "../core/errors.rkt"
         "../core/function-names.rkt"
         "../core/list-nat.rkt"
         "../core/lists.rkt"
         "../core/logic.rkt"
         "../core/objects.rkt"
         "../core/result.rkt"
         "../core/strings.rkt"
         "../core/tags.rkt"
         (only-in "../core/typed-logic.rkt"
                  TRUE
                  typed-not
                  typed-and
                  typed-or
                  typed-xor
                  typed-if)
         "../core/rat.rkt"
         "../core/typed-rat.rkt"
         "../readers/error.rkt"
         "../readers/list.rkt"
         "../readers/raw-boolean.rkt"
         "../readers/string.rkt"
         "../readers/type-tag.rkt"
         "helpers/lazy.rkt"
         (only-in "helpers/values.rkt"
                  apply2
                  apply3
                  typed-value?
                  host-bits->raw
                  whole-rat-object))

(define ONE (whole-rat-object 1))
(define FOUR (whole-rat-object 4))
(define EIGHT (whole-rat-object 8))

(define function-name-cases
  (list
   (list cons-function-name "cons")
   (list head-function-name "head")
   (list tail-function-name "tail")
   (list is-nil-function-name "is-nil")
   (list len-function-name "len")
   (list take-function-name "take")
   (list drop-function-name "drop")
   (list nth-function-name "nth")
   (list take-while-function-name "take-while")
   (list drop-while-function-name "drop-while")
   (list append-function-name "append")
   (list reverse-function-name "reverse")
   (list zip-function-name "zip")
   (list concat-function-name "concat")
   (list flatten-function-name "flatten")
   (list map-function-name "map")
   (list filter-function-name "filter")
   (list reduce-function-name "reduce")
   (list any-function-name "any?")
   (list all-function-name "all?")
   (list find-function-name "find")
   (list find-index-function-name "find-index")
   (list contains-function-name "contains?")
   (list not-function-name "not")
   (list and-function-name "and")
   (list or-function-name "or")
   (list xor-function-name "xor")
   (list if-function-name "if")
   (list succ-function-name "succ")
   (list add-function-name "add")
   (list sub-function-name "sub")
   (list mult-function-name "mult")
   (list div-function-name "div")
   (list eq-function-name "eq")
   (list lt-function-name "lt")
   (list lte-function-name "lte")
   (list gt-function-name "gt")
   (list gte-function-name "gte")
   (list is-zero-function-name "is-zero")
   (list make-err-function-name "make-err")
   (list is-ok-function-name "is-ok")
   (list is-err-function-name "is-err")
   (list unwrap-ok-function-name "unwrap-ok")
   (list unwrap-err-function-name "unwrap-err")
   (list make-char-function-name "make-char")
   (list char-eq-function-name "char-eq")
   (list char-lt-function-name "char-lt")
   (list char-lte-function-name "char-lte")
   (list char-gt-function-name "char-gt")
   (list char-gte-function-name "char-gte")
   (list make-string-function-name "make-string")
   (list string-empty-function-name "string-empty?")
   (list string-length-function-name "string-length")
   (list string-eq-function-name "string-eq")
   (list string-append-function-name "string-append")
   (list string-head-function-name "string-head")
   (list string-tail-function-name "string-tail")
   (list string-prefix-function-name "string-prefix?")
   (list string-contains-function-name "string-contains?")
   (list exp-function-name "exp")
   (list recip-function-name "recip")
   (list neg-function-name "neg")
   (list abs-function-name "abs")
   (list floor-function-name "floor")
   (list is-whole-function-name "is-whole")
   (list is-nonnegative-whole-function-name "is-nonnegative-whole")
   (list make-byte-function-name "make-byte")
   (list byte-value-function-name "byte-value")
   (list byte-eq-function-name "byte-eq")
   (list byte-lt-function-name "byte-lt")
   (list byte-lte-function-name "byte-lte")
   (list byte-gt-function-name "byte-gt")
   (list byte-gte-function-name "byte-gte")
   (list string-to-bytes-function-name "string-to-bytes")
   (list bytes-to-string-function-name "bytes-to-string")
   (list some-function-name "some")
   (list is-some-function-name "is-some")
   (list is-none-function-name "is-none")
   (list option-case-function-name "option-case")
   (list make-map-function-name "make-map")
   (list map-empty-function-name "map-empty?")
   (list map-size-function-name "map-size")
   (list map-lookup-function-name "map-lookup")
   (list map-contains-function-name "map-contains?")
   (list map-set-function-name "map-set")
   (list map-remove-function-name "map-remove")))

(for ([case (in-list function-name-cases)])
  (check-true
   (typed-value? string-type
                 (first case)))
  (check-equal?
   (string-value->string
    (first case))
   (second case)))

(define type-name-cases
  (list
   (list error-type "ERROR")
   (list bool-type "BOOL")
   (list list-type "LIST")
   (list rat-type "RAT")
   (list result-type "RESULT")
   (list char-type "CHAR")
   (list string-type "STRING")))

(for ([case (in-list type-name-cases)])
  (check-equal? (type-tag->string
                 (first case))
                (second case)))

(define mismatch-cases
  (list
   (list (apply2 typed-cons TRUE TRUE)
         "cons" 2 "LIST" "BOOL")
   (list (lazy-apply typed-head TRUE)
         "head" 1 "LIST" "BOOL")
   (list (lazy-apply typed-tail TRUE)
         "tail" 1 "LIST" "BOOL")
   (list (lazy-apply typed-is-nil TRUE)
         "is-nil" 1 "LIST" "BOOL")
   (list (lazy-apply typed-len-rat TRUE)
         "len" 1 "LIST" "BOOL")
   (list (apply2 typed-take-rat TRUE NIL)
         "take" 1 "RAT" "BOOL")
   (list (apply2 typed-drop-rat TRUE NIL)
         "drop" 1 "RAT" "BOOL")

   (list (lazy-apply typed-not ONE)
         "not" 1 "BOOL" "RAT")
   (list (apply2 typed-and ONE TRUE)
         "and" 1 "BOOL" "RAT")
   (list (apply2 typed-or ONE TRUE)
         "or" 1 "BOOL" "RAT")
   (list (apply2 typed-xor ONE TRUE)
         "xor" 1 "BOOL" "RAT")
   (list (apply3 typed-if ONE TRUE TRUE)
         "if" 1 "BOOL" "RAT")

   (list (lazy-apply typed-rat-succ TRUE)
         "succ" 1 "RAT" "BOOL")
   (list (apply2 typed-rat-add TRUE ONE)
         "add" 1 "RAT" "BOOL")
   (list (apply2 typed-rat-sub TRUE ONE)
         "sub" 1 "RAT" "BOOL")
   (list (apply2 typed-rat-mult TRUE ONE)
         "mult" 1 "RAT" "BOOL")
   (list (apply2 typed-rat-div TRUE ONE)
         "div" 1 "RAT" "BOOL")
   (list (apply2 typed-rat-exp TRUE ONE)
         "exp" 1 "RAT" "BOOL")
   (list (lazy-apply typed-rat-recip TRUE)
         "recip" 1 "RAT" "BOOL")
   (list (lazy-apply typed-rat-negate TRUE)
         "neg" 1 "RAT" "BOOL")
   (list (lazy-apply typed-rat-abs TRUE)
         "abs" 1 "RAT" "BOOL")
   (list (lazy-apply typed-rat-floor TRUE)
         "floor" 1 "RAT" "BOOL")
   (list (apply2 typed-rat-equal TRUE ONE)
         "eq" 1 "RAT" "BOOL")
   (list (apply2 typed-rat-less TRUE ONE)
         "lt" 1 "RAT" "BOOL")
   (list (apply2 typed-rat-less-equal TRUE ONE)
         "lte" 1 "RAT" "BOOL")
   (list (apply2 typed-rat-greater TRUE ONE)
         "gt" 1 "RAT" "BOOL")
   (list (apply2 typed-rat-greater-equal TRUE ONE)
         "gte" 1 "RAT" "BOOL")
   (list (lazy-apply typed-rat-is-zero TRUE)
         "is-zero" 1 "RAT" "BOOL")
   (list (lazy-apply typed-rat-is-whole TRUE)
         "is-whole" 1 "RAT" "BOOL")
   (list (lazy-apply typed-rat-is-nonnegative-whole TRUE)
         "is-nonnegative-whole" 1 "RAT" "BOOL")

   (list (lazy-apply typed-make-err TRUE)
         "make-err" 1 "ERROR" "BOOL")
   (list (lazy-apply typed-result-is-ok TRUE)
         "is-ok" 1 "RESULT" "BOOL")
   (list (lazy-apply typed-result-is-err TRUE)
         "is-err" 1 "RESULT" "BOOL")
   (list (lazy-apply typed-result-unwrap-ok TRUE)
         "unwrap-ok" 1 "RESULT" "BOOL")
   (list (lazy-apply typed-result-unwrap-err TRUE)
         "unwrap-err" 1 "RESULT" "BOOL")

   (list (lazy-apply typed-make-char-rat TRUE)
         "make-char" 1 "RAT" "BOOL")
   (list (apply2 typed-char-equal TRUE A)
         "char-eq" 1 "CHAR" "BOOL")
   (list (apply2 typed-char-less TRUE A)
         "char-lt" 1 "CHAR" "BOOL")
   (list (apply2 typed-char-less-equal TRUE A)
         "char-lte" 1 "CHAR" "BOOL")
   (list (apply2 typed-char-greater TRUE A)
         "char-gt" 1 "CHAR" "BOOL")
   (list (apply2 typed-char-greater-equal TRUE A)
         "char-gte" 1 "CHAR" "BOOL")

   (list (lazy-apply typed-make-string TRUE)
         "make-string" 1 "LIST" "BOOL")
   (list (lazy-apply typed-string-empty? TRUE)
         "string-empty?" 1 "STRING" "BOOL")
   (list (lazy-apply typed-string-length-rat TRUE)
         "string-length" 1 "STRING" "BOOL")
   (list (apply2 typed-string-equal TRUE EMPTY-STRING)
         "string-eq" 1 "STRING" "BOOL")
   (list (apply2 typed-string-append TRUE EMPTY-STRING)
         "string-append" 1 "STRING" "BOOL")
   (list (lazy-apply typed-string-head TRUE)
         "string-head" 1 "STRING" "BOOL")
   (list (lazy-apply typed-string-tail TRUE)
         "string-tail" 1 "STRING" "BOOL")
   (list (apply2 typed-string-prefix? TRUE EMPTY-STRING)
         "string-prefix?" 1 "STRING" "BOOL")
   (list (apply2 typed-string-contains? TRUE EMPTY-STRING)
         "string-contains?" 1 "STRING" "BOOL")))

(for ([case (in-list mismatch-cases)])
  (define error (first case))
  (define name (second case))
  (define position (third case))
  (define expected-type (fourth case))
  (define actual-type (fifth case))
  (check-true
   (typed-value? error-type error))
  (check-equal?
   (error-value->string error)
   (format "~a(arg~a expected ~a got ~a)"
           name
           position
           expected-type
           actual-type)))

(define add-error
  (apply2 typed-rat-add TRUE ONE))

(define nested-error
  (lazy-apply typed-string-length-rat
              add-error))

(check-equal?
 (error-value->string nested-error)
 "add(arg1 expected RAT got BOOL)\n  -> string-length(arg1 expected STRING)")

(check-equal?
 (error-value->string
  (lazy-apply typed-rat-succ
              invalid-nat-error))
 "INVALID-NAT\n  -> succ(arg1 expected RAT)")

(define raw-mismatch
  (apply3 raw-make-type-mismatch-error
          argument-position-two
          list-type
          bool-type))

(check-equal?
 (error-value->string raw-mismatch)
 "TYPE-MISMATCH(arg2 expected LIST got BOOL)")
(check-equal?
 (error-value->string invalid-nat-error)
 "INVALID-NAT")
(check-equal?
 (error-value->string divide-by-zero-error)
 "DIVIDE-BY-ZERO")
(check-equal?
 (error-value->string invalid-char-error)
 "INVALID-CHAR")
(check-equal?
 (error-value->string invalid-string-error)
 "INVALID-STRING")
(check-equal?
 (error-value->string wrong-result-variant-error)
 "WRONG-RESULT-VARIANT")

(define one-element-list
  (apply2 typed-cons ONE NIL))

(define result-frame-cases
  (list
   (list (lazy-apply typed-head NIL)
         "EMPTY-LIST" "head")
   (list (lazy-apply typed-tail NIL)
         "EMPTY-LIST" "tail")
   (list (lazy-apply typed-make-char-rat
                     (apply2 typed-rat-mult
                             (apply2 typed-rat-mult FOUR EIGHT)
                             EIGHT))
         "INVALID-CHAR" "make-char")
   (list (lazy-apply typed-make-string one-element-list)
         "INVALID-STRING" "make-string")
   (list (lazy-apply typed-string-head EMPTY-STRING)
         "EMPTY-LIST" "string-head")
   (list (lazy-apply typed-string-tail EMPTY-STRING)
         "EMPTY-LIST" "string-tail")
   (list (lazy-apply typed-result-unwrap-ok
                     (lazy-apply typed-make-err invalid-nat-error))
         "WRONG-RESULT-VARIANT" "unwrap-ok")
   (list (lazy-apply typed-result-unwrap-err
                     (lazy-apply typed-make-ok ONE))
         "WRONG-RESULT-VARIANT" "unwrap-err")))

(for ([case (in-list result-frame-cases)])
  (define error (first case))
  (define root (second case))
  (define name (third case))
  (check-true
   (typed-value? error-type error))
  (check-equal?
   (error-value->string error)
   (format "~a\n  -> ~a(result)" root name)))

(check-equal?
 (error-value->string
  (lazy-apply typed-rat-succ
              (lazy-apply typed-head NIL)))
 "EMPTY-LIST\n  -> head(result)\n  -> succ(arg1 expected RAT)")
