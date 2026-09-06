#lang racket/base

(require rackunit
         racket/list
         racket/promise
         "../core/byte.rkt"
         "../core/errors.rkt"
         "../core/int.rkt"
         "../core/lists.rkt"
         "../core/logic.rkt"
         "../core/objects.rkt"
         "../core/rat.rkt"
         "../core/tags.rkt"
         (only-in "../core/typed-logic.rkt" TRUE)
         (only-in "../core/typed-rat.rkt" typed-rat-add)
         "../readers/bool.rkt"
         "../readers/byte.rkt"
         "../readers/error.rkt"
         "../readers/rat.rkt"
         "../readers/raw-boolean.rkt"
         "../readers/type-tag.rkt"
         "helpers/lazy.rkt"
         (only-in "helpers/values.rkt"
                  apply2
                  host-bits->raw
                  exact->typed-rat
                  typed-value?
                  object-tag))

;; Every value 0 through 255 constructs, reads back, and converts to the
;; same whole Rat; no other value constructs.
(for ([code (in-list '(0 1 2 127 128 254 255))])
  (define byte-value
    (lazy-apply MAKE-BYTE (exact->typed-rat code)))
  (check-equal? (object-tag byte-value) 9)
  (check-equal? (byte-value->integer byte-value) code)
  (define back (lazy-apply BYTE-VALUE byte-value))
  (check-equal? (object-tag back) 7)
  (check-equal? (rat->number
                 (lazy-apply raw-object-value back))
                code))

;; Negative, fractional, and over-255 inputs are the InvalidByte Error.
(for ([bad (in-list '(-1 -255 1/2 255/2 256 65536))])
  (check-equal?
   (error-value->string
    (lazy-apply MAKE-BYTE (exact->typed-rat bad)))
   "INVALID-BYTE\n  -> make-byte(result)"))

;; Wrong argument types are ordinary strict mismatches.
(check-equal?
 (error-value->string
  (lazy-apply MAKE-BYTE TRUE))
 "make-byte(arg1 expected RAT got BOOL)")
(check-equal?
 (error-value->string
  (lazy-apply BYTE-VALUE TRUE))
 "byte-value(arg1 expected BYTE got BOOL)")

;; Ordinary Rat arithmetic rejects Byte: Byte is data, not a number.
(define byte-65
  (lazy-apply MAKE-BYTE (exact->typed-rat 65)))
(check-equal?
 (error-value->string
  (apply2 typed-rat-add byte-65 (exact->typed-rat 1)))
 "add(arg1 expected RAT got BYTE)")

;; Comparisons agree with host comparison across boundaries.
(for* ([left-code (in-list '(0 1 64 255))]
       [right-code (in-list '(0 1 64 255))])
  (define left (lazy-apply MAKE-BYTE (exact->typed-rat left-code)))
  (define right (lazy-apply MAKE-BYTE (exact->typed-rat right-code)))
  (for ([case (in-list
               (list (list BYTE-EQ =)
                     (list BYTE-LT <)
                     (list BYTE-LTE <=)
                     (list BYTE-GT >)
                     (list BYTE-GTE >=)))])
    (define result (apply2 (first case) left right))
    (check-equal? (object-tag result) 1)
    (check-equal? (bool->boolean result)
                  ((second case) left-code right-code))))

;; Byte comparisons reject Char even though both carry binary payloads.
(check-equal?
 (error-value->string
  (apply2 BYTE-EQ byte-65 TRUE))
 "byte-eq(arg2 expected BYTE got BOOL)")

;; Operations remain chains of unary lambdas.
(for ([function (in-list
                 (list MAKE-BYTE BYTE-VALUE))])
  (check-equal?
   (procedure-arity (lazy-force function))
   1))
(for ([function (in-list
                 (list BYTE-EQ BYTE-LT BYTE-LTE BYTE-GT BYTE-GTE))])
  (check-equal?
   (procedure-arity (lazy-force function))
   1)
  (check-equal?
   (procedure-arity
    (lazy-force (lazy-apply function byte-65)))
   1))

;; Step 37.2: pure String <-> List Byte conversion.

(require (only-in "../core/byte.rkt"
                  STRING-TO-BYTES
                  BYTES-TO-STRING)
         (only-in "../core/strings.rkt" MAKE-STRING EMPTY-STRING)
         (only-in "../core/chars.rkt" A B C)
         (only-in "../readers/string.rkt" string-value->string)
         (only-in "../readers/list.rkt" list->host-list))

(define (value-list values)
  (foldr
   (lambda (value tail)
     (apply2 raw-cons value tail))
   NIL
   values))

(define (byte-codes value)
  (list->host-list value byte-value->integer))

;; Ordinary text: one Byte per Char, byte-exact both ways.
(define abc
  (lazy-apply MAKE-STRING (value-list (list A B C))))
(define abc-bytes
  (lazy-apply STRING-TO-BYTES abc))
(check-equal? (object-tag abc-bytes) 2)
(check-equal? (byte-codes abc-bytes) '(65 66 67))
(define abc-back
  (lazy-apply BYTES-TO-STRING abc-bytes))
(check-equal? (object-tag abc-back) 6)
(check-equal? (string-value->string abc-back) "ABC")

;; Empty, boundary bytes, and an embedded zero round-trip exactly.
(check-equal? (byte-codes (lazy-apply STRING-TO-BYTES EMPTY-STRING)) '())
(check-equal?
 (string-value->string
  (lazy-apply BYTES-TO-STRING (value-list '())))
 "")

(define boundary-bytes
  (value-list
   (for/list ([code (in-list '(0 1 127 128 255))])
     (lazy-apply MAKE-BYTE (exact->typed-rat code)))))
(define boundary-string
  (lazy-apply BYTES-TO-STRING boundary-bytes))
(check-equal? (object-tag boundary-string) 6)
(check-equal?
 (byte-codes (lazy-apply STRING-TO-BYTES boundary-string))
 '(0 1 127 128 255))

;; A List whose element is not a Byte is rejected by validation, not
;; assumed to be a byte sequence.
(check-equal?
 (error-value->string
  (lazy-apply BYTES-TO-STRING
              (value-list (list byte-65 TRUE))))
 "INVALID-BYTE\n  -> bytes-to-string(result)")
(check-equal?
 (error-value->string
  (lazy-apply BYTES-TO-STRING
              (value-list (list A))))
 "INVALID-BYTE\n  -> bytes-to-string(result)")

;; Wrong argument types and incoming Errors behave like every strict
;; operation, and laziness holds: validation stops at the first bad
;; element without forcing the rest.
(check-equal?
 (error-value->string
  (lazy-apply STRING-TO-BYTES TRUE))
 "string-to-bytes(arg1 expected STRING got BOOL)")
(check-equal?
 (error-value->string
  (lazy-apply BYTES-TO-STRING invalid-nat-error))
 "INVALID-NAT\n  -> bytes-to-string(arg1 expected LIST)")

;; Validation fails on the first non-Byte element without examining any
;; later element: the second element's tag is a divergent computation.
(define fragile-element
  (apply2 raw-make-object
          (delay
            (error 'bytes "forced element after invalid element"))
          raw-true))
(check-equal?
 (error-value->string
  (lazy-apply BYTES-TO-STRING
              (value-list (list TRUE fragile-element))))
 "INVALID-BYTE\n  -> bytes-to-string(result)")

(for ([function (in-list (list STRING-TO-BYTES BYTES-TO-STRING))])
  (check-equal?
   (procedure-arity (lazy-force function))
   1))
