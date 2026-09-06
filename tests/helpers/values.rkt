#lang racket/base

;; Shared builders and decoders for lambda values used across the test
;; suite. Every helper is host-side test scaffolding: builders construct
;; canonical object-language values directly, decoders force and read them.

(require "../../core/int.rkt"
         "../../core/lists.rkt"
         "../../core/logic.rkt"
         "../../core/objects.rkt"
         "../../core/rat.rkt"
         "../../core/tags.rkt"
         "../../readers/rat.rkt"
         "../../readers/raw-boolean.rkt"
         "../../readers/type-tag.rkt"
         "lazy.rkt")

(provide apply2
         apply3
         typed-value?
         object-tag
         host-bits->raw
         integer->host-bits
         integer->raw-bits
         integer->int
         whole-rat-object
         exact->typed-rat
         rat-object->number)

(define (typed-value? type value)
  (raw-boolean->boolean
   (apply2 raw-is-type type value)))

(define (object-tag value)
  (type-tag->integer
   (lazy-apply raw-object-type value)))

(define (host-bits->raw bits)
  (foldr
   (lambda (bit tail)
     (apply2 raw-cons
             (if bit raw-true raw-false)
             tail))
   NIL
   bits))

(define (integer->host-bits integer)
  (for/list ([character
              (in-string
               (number->string integer 2))])
    (char=? character #\1)))

(define (integer->raw-bits integer)
  (host-bits->raw
   (integer->host-bits integer)))

(define (integer->int integer)
  (apply2 raw-make-int
          (if (negative? integer) raw-false raw-true)
          (integer->raw-bits (abs integer))))

(define (whole-rat-object integer)
  (apply2 raw-make-object
          rat-type
          (lazy-apply
           raw-whole-rat
           (integer->raw-bits integer))))

(define (exact->typed-rat exact)
  (apply2 raw-make-object
          rat-type
          (apply2 raw-make-rat
                  (integer->int (numerator exact))
                  (integer->raw-bits (denominator exact)))))

(define (rat-object->number value)
  (rat->number
   (lazy-apply raw-object-value value)))
