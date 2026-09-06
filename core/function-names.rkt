#lang s-exp "../macros/lazy-with-macros.rkt"

(require "../macros/macros.rkt"
         "errors.rkt"
         "logic.rkt"
         "objects.rkt"
         "tags.rkt")

(provide cons-function-name
         head-function-name
         tail-function-name
         is-nil-function-name
         len-function-name
         take-function-name
         drop-function-name
         nth-function-name
         take-while-function-name
         drop-while-function-name
         append-function-name
         reverse-function-name
         zip-function-name
         concat-function-name
         flatten-function-name
         map-function-name
         filter-function-name
         reduce-function-name
         any-function-name
         all-function-name
         find-function-name
         find-index-function-name
         contains-function-name
         range-function-name
         repeat-function-name
         not-function-name
         and-function-name
         or-function-name
         xor-function-name
         if-function-name
         succ-function-name
         add-function-name
         sub-function-name
         mult-function-name
         div-function-name
         eq-function-name
         lt-function-name
         lte-function-name
         gt-function-name
         gte-function-name
         is-zero-function-name
         make-err-function-name
         is-ok-function-name
         is-err-function-name
         unwrap-ok-function-name
         unwrap-err-function-name
         make-char-function-name
         char-eq-function-name
         char-lt-function-name
         char-lte-function-name
         char-gt-function-name
         char-gte-function-name
         make-string-function-name
         string-empty-function-name
         string-length-function-name
         string-eq-function-name
         string-append-function-name
         string-head-function-name
         string-tail-function-name
         string-prefix-function-name
         string-contains-function-name
         exp-function-name
         recip-function-name
         neg-function-name
         abs-function-name
         floor-function-name
         is-whole-function-name
         is-nonnegative-whole-function-name
         make-byte-function-name
         byte-value-function-name
         byte-eq-function-name
         byte-lt-function-name
         byte-lte-function-name
         byte-gt-function-name
         byte-gte-function-name
         string-to-bytes-function-name
         bytes-to-string-function-name
         some-function-name
         is-some-function-name
         is-none-function-name
         option-case-function-name
         make-map-function-name
         map-empty-function-name
         map-size-function-name
         map-lookup-function-name
         map-contains-function-name
         map-set-function-name
         map-remove-function-name)

(def raw-name-char bits =
  ((raw-make-object char-type) bits))

(def raw-name-string chars =
  ((raw-make-object string-type) chars))

(define-function-name cons-function-name cons)
(define-function-name head-function-name head)
(define-function-name tail-function-name tail)
(define-function-name is-nil-function-name is-nil)
(define-function-name len-function-name len)
(define-function-name take-function-name take)
(define-function-name drop-function-name drop)
(define-function-name nth-function-name nth)
(define-function-name take-while-function-name take-while)
(define-function-name drop-while-function-name drop-while)
(define-function-name append-function-name append)
(define-function-name reverse-function-name reverse)
(define-function-name zip-function-name zip)
(define-function-name concat-function-name concat)
(define-function-name flatten-function-name flatten)
(define-function-name map-function-name map)
(define-function-name filter-function-name filter)
(define-function-name reduce-function-name reduce)
(define-function-name any-function-name any?)
(define-function-name all-function-name all?)
(define-function-name find-function-name find)
(define-function-name find-index-function-name find-index)
(define-function-name contains-function-name contains?)
(define-function-name range-function-name range)
(define-function-name repeat-function-name repeat)

(define-function-name not-function-name not)
(define-function-name and-function-name and)
(define-function-name or-function-name or)
(define-function-name xor-function-name xor)
(define-function-name if-function-name if)

(define-function-name succ-function-name succ)
(define-function-name add-function-name add)
(define-function-name sub-function-name sub)
(define-function-name mult-function-name mult)
(define-function-name div-function-name div)
(define-function-name eq-function-name eq)
(define-function-name lt-function-name lt)
(define-function-name lte-function-name lte)
(define-function-name gt-function-name gt)
(define-function-name gte-function-name gte)
(define-function-name is-zero-function-name is-zero)

(define-function-name make-err-function-name make-err)
(define-function-name is-ok-function-name is-ok)
(define-function-name is-err-function-name is-err)
(define-function-name unwrap-ok-function-name unwrap-ok)
(define-function-name unwrap-err-function-name unwrap-err)

(define-function-name make-char-function-name make-char)
(define-function-name char-eq-function-name char-eq)
(define-function-name char-lt-function-name char-lt)
(define-function-name char-lte-function-name char-lte)
(define-function-name char-gt-function-name char-gt)
(define-function-name char-gte-function-name char-gte)

(define-function-name make-string-function-name make-string)
(define-function-name string-empty-function-name string-empty?)
(define-function-name string-length-function-name string-length)
(define-function-name string-eq-function-name string-eq)
(define-function-name string-append-function-name string-append)
(define-function-name string-head-function-name string-head)
(define-function-name string-tail-function-name string-tail)
(define-function-name string-prefix-function-name string-prefix?)
(define-function-name string-contains-function-name string-contains?)

(define-function-name exp-function-name exp)
(define-function-name recip-function-name recip)
(define-function-name neg-function-name neg)
(define-function-name abs-function-name abs)
(define-function-name floor-function-name floor)
(define-function-name is-whole-function-name is-whole)
(define-function-name is-nonnegative-whole-function-name is-nonnegative-whole)

(define-function-name make-byte-function-name make-byte)
(define-function-name byte-value-function-name byte-value)
(define-function-name byte-eq-function-name byte-eq)
(define-function-name byte-lt-function-name byte-lt)
(define-function-name byte-lte-function-name byte-lte)
(define-function-name byte-gt-function-name byte-gt)
(define-function-name byte-gte-function-name byte-gte)
(define-function-name string-to-bytes-function-name string-to-bytes)
(define-function-name bytes-to-string-function-name bytes-to-string)

(define-function-name some-function-name some)
(define-function-name is-some-function-name is-some)
(define-function-name is-none-function-name is-none)
(define-function-name option-case-function-name option-case)

(define-function-name make-map-function-name make-map)
(define-function-name map-empty-function-name map-empty?)
(define-function-name map-size-function-name map-size)
(define-function-name map-lookup-function-name map-lookup)
(define-function-name map-contains-function-name map-contains?)
(define-function-name map-set-function-name map-set)
(define-function-name map-remove-function-name map-remove)
