#lang racket/base

(require rackunit
         (only-in racket/list range)
         racket/promise
         "../core/chars.rkt"
         "../core/errors.rkt"
         "../core/lists.rkt"
         "../core/logic.rkt"
         "../core/objects.rkt"
         "../core/pair.rkt"
         "../core/result.rkt"
         "../core/strings.rkt"
         "../core/tags.rkt"
         (only-in "../core/typed-logic.rkt" TRUE)
         "../readers/bool.rkt"
         "../readers/raw-boolean.rkt"
         "../runtime/codec.rkt"
         "helpers/lazy.rkt")

(define (typed-value? type value)
  (raw-boolean->boolean
   (apply2 raw-is-type type value)))

(define (failure-reason value)
  (and (codec-failure? value)
       (codec-failure-reason value)))

(define every-byte
  (apply bytes (range 256)))

(define every-char
  (bytes->object-string every-byte))

(check-true (immutable? (object-string->bytes every-char)))
(check-equal? (object-string->bytes every-char)
              every-byte)

(for ([sample (in-list (list #""
                             #"\0"
                             #"A\0B"
                             #"\377\200\0\177"))])
  (define encoded (bytes->object-string sample))
  (check-true (typed-value? string-type encoded))
  (check-equal? (object-string->bytes encoded)
                sample))

;; Encoding copies host bytes into pure lambda values; later mutation of the
;; source byte string cannot alter the object-language String.
(define mutable-source (bytes 65 0 255))
(define copied-string (bytes->object-string mutable-source))
(bytes-set! mutable-source 0 66)
(check-equal? (object-string->bytes copied-string)
              #"A\0\377")

(define two-values
  (list A TRUE))
(define object-list
  (host-list->object-list two-values))
(define decoded-list
  (object-list->host-list object-list))

(check-true (typed-value? list-type object-list))
(check-equal? (length decoded-list) 2)
(check-true (typed-value? char-type (car decoded-list)))
(check-true (typed-value? bool-type (cadr decoded-list)))
(check-equal? (object-list->host-list NIL) '())

(check-equal? (failure-reason (object-list->host-list TRUE))
              'wrong-type)
(check-equal? (failure-reason (object-string->bytes TRUE))
              'wrong-type)

(define malformed-string-payload
  (lazy-apply raw-make-string TRUE))
(check-equal? (failure-reason
               (object-string->bytes malformed-string-payload))
              'wrong-type)

(define wrong-element-string
  (lazy-apply
   raw-make-string
   (host-list->object-list (list TRUE))))
(check-equal? (failure-reason
               (object-string->bytes wrong-element-string))
              'wrong-type)

(define improper-char-list
  (apply2 raw-make-object
          list-type
          (apply2 raw-pair A TRUE)))
(define improper-string
  (lazy-apply raw-make-string improper-char-list))
(check-equal? (failure-reason
               (object-string->bytes improper-string))
              'wrong-type)

(define malformed-tag
  (lambda (step)
    (lambda (seed)
      (lambda (ignored) ignored))))
(define malformed-tail
  (apply2 raw-make-object malformed-tag raw-false))
(define malformed-list-predicate
  (apply2 raw-make-object
          list-type
          (apply2 raw-pair A malformed-tail)))
(check-equal? (failure-reason
               (object-list->host-list malformed-list-predicate))
              'wrong-type)

;; Only the one canonical NIL object terminates a decoded List. A forged cell
;; with an ordinary value in its head and an unrelated Error in its tail is
;; malformed; it must not be mistaken for an empty List and silently truncate.
(define false-nil-list
  (apply2 raw-make-object
          list-type
          (apply2 raw-pair A invalid-nat-error)))
(check-equal? (failure-reason
               (object-list->host-list false-nil-list))
              'wrong-type)
(check-equal? (failure-reason
               (object-string->bytes
                (lazy-apply raw-make-string false-nil-list)))
              'wrong-type)

(define (bits->raw bits)
  (host-list->object-list
   (map (lambda (bit)
          (if bit raw-true raw-false))
        bits)))

(define leading-zero-char
  (apply2 raw-make-object
          char-type
          (bits->raw '(#f #t))))
(define leading-zero-string
  (lazy-apply
   raw-make-string
   (host-list->object-list (list leading-zero-char))))
(check-equal? (failure-reason
               (object-string->bytes leading-zero-string))
              'out-of-range)

(define char-256
  (lazy-apply raw-make-char
              (bits->raw '(#t #f #f #f #f #f #f #f #f))))
(define out-of-range-string
  (lazy-apply
   raw-make-string
   (host-list->object-list (list char-256))))
(check-equal? (failure-reason
               (object-string->bytes out-of-range-string))
              'out-of-range)

;; Whole-number boundary values ride the Rat conversions since the Step
;; 35.5 switch, including the protocol bounds and values larger than any
;; current host request needs.
(for ([sample (in-list (list 0
                             1
                             255
                             256
                             65535
                             65536
                             (expt 2 80)))])
  (define encoded (exact->object-rat sample))
  (check-true (typed-value? rat-type encoded))
  (check-equal? (object-rat->exact encoded)
                sample))

(define ok-nil (object-ok NIL))
(check-true (typed-value? result-type ok-nil))
(check-true (bool->boolean (lazy-apply is-ok ok-nil)))
(check-true (bool->boolean
             (lazy-apply typed-is-nil
                         (lazy-apply unwrap-ok ok-nil))))

(define err-invalid-nat (object-err invalid-nat-error))
(check-true (typed-value? result-type err-invalid-nat))
(check-true (bool->boolean
             (lazy-apply is-err err-invalid-nat)))
(check-true (typed-value?
             error-type
             (lazy-apply unwrap-err err-invalid-nat)))

(check-exn exn:fail:contract?
           (lambda ()
             (bytes->object-string "not bytes")))

;; Step 35.2: exact Racket numbers translate to canonical Rat values and
;; back; inexact and non-real numbers are rejected; forged noncanonical
;; representations never decode.

(require (only-in "../core/int.rkt" raw-make-int)
         (only-in "../core/rat.rkt" raw-make-rat)
         (only-in "../readers/rat.rkt" rat->number))

(define (object-rat-payload value)
  (lazy-apply raw-object-value value))

(for ([exact (in-list '(0 1 -1 2 -2 1/2 -1/2 7/3 -7/3 123456/7
                        -123456/7 255 65536 -654321
                        1606938044258990275541962092341162602522202993782792835301376))])
  (define value (exact->object-rat exact))
  (check-true (typed-value? rat-type value))
  (check-equal? (rat->number (object-rat-payload value)) exact)
  (check-equal? (object-rat->exact value) exact))

;; Inexact and non-rational numbers are rejected before construction.
(for ([bad (in-list (list 1.5 -0.0 1e3 +inf.0 +nan.0 2+3i))])
  (check-exn exn:fail:contract?
             (lambda ()
               (exact->object-rat bad))))

;; Wrong tags and forged noncanonical payloads are codec failures.
(check-pred codec-failure? (object-rat->exact TRUE))

(define (forged-rat numerator-int denominator-bits)
  (apply2 raw-make-object
          rat-type
          (apply2 raw-pair numerator-int denominator-bits)))

(define (host-integer->bits integer)
  (let loop ([remaining integer]
             [result NIL])
    (if (zero? remaining)
        result
        (loop (quotient remaining 2)
              (apply2 raw-cons
                      (if (odd? remaining) raw-true raw-false)
                      result)))))

(define (host-integer->int integer)
  (apply2 raw-make-int
          (if (negative? integer) raw-false raw-true)
          (host-integer->bits (abs integer))))

;; Unreduced 2/4.
(check-pred codec-failure?
            (object-rat->exact
             (forged-rat (host-integer->int 2)
                         (host-integer->bits 4))))

;; Negative zero numerator.
(check-pred codec-failure?
            (object-rat->exact
             (forged-rat (apply2 raw-make-int
                                 raw-true
                                 (host-integer->bits 0))
                         (host-integer->bits 5))))

;; Zero denominator.
(check-pred codec-failure?
            (object-rat->exact
             (forged-rat (host-integer->int 1)
                         (apply2 raw-cons raw-false NIL))))

;; Non-normalized denominator bits (leading zero).
(check-pred codec-failure?
            (object-rat->exact
             (forged-rat (host-integer->int 1)
                         (apply2 raw-cons
                                 raw-false
                                 (apply2 raw-cons raw-true NIL)))))

;; A genuinely canonical constructed value decodes.
(check-equal?
 (object-rat->exact
  (forged-rat (host-integer->int -3)
              (host-integer->bits 2)))
 -3/2)

;; ---------------------------------------------------------------------------
;; Every public operation that can return an empty List or String must
;; restore the one canonical NIL terminator: the codec deliberately rejects
;; any other empty as forged, so a checker-unwrapped payload rebuilt with a
;; fresh terminator would fail at the host boundary (the MAKE-STRING/DROP
;; release blocker found in the Milestone 4 branch review).

(require (only-in "../core/list-nat.rkt" typed-take-rat typed-drop-rat)
         (only-in "../core/byte.rkt" STRING-TO-BYTES BYTES-TO-STRING)
         (only-in "helpers/values.rkt" whole-rat-object))

(define two-element-list
  (apply2 typed-cons
          (whole-rat-object 1)
          (apply2 typed-cons (whole-rat-object 2) NIL)))

(for ([case
       (in-list
        (list
         (cons "NIL" NIL)
         (cons "TAIL singleton"
               (lazy-apply typed-tail
                           (apply2 typed-cons (whole-rat-object 1) NIL)))
         (cons "TAKE 0 nonempty"
               (apply2 typed-take-rat (whole-rat-object 0) two-element-list))
         (cons "DROP exact length"
               (apply2 typed-drop-rat (whole-rat-object 2) two-element-list))
         (cons "DROP beyond length"
               (apply2 typed-drop-rat (whole-rat-object 3) two-element-list))
         (cons "TAKE 0 after DROP"
               (apply2 typed-take-rat (whole-rat-object 0)
                       (apply2 typed-drop-rat (whole-rat-object 1) two-element-list)))
         (cons "DROP after TAKE"
               (apply2 typed-drop-rat (whole-rat-object 1)
                       (apply2 typed-take-rat (whole-rat-object 1) two-element-list)))
         (cons "DROP 0 NIL" (apply2 typed-drop-rat (whole-rat-object 0) NIL))
         (cons "DROP 3 NIL" (apply2 typed-drop-rat (whole-rat-object 3) NIL))
         (cons "TAKE 0 NIL" (apply2 typed-take-rat (whole-rat-object 0) NIL))))])
  (check-equal? (object-list->host-list (cdr case)) '() (car case))
  (check-eq? (force (cdr case)) (force NIL) (car case)))

(define two-byte-list (bytes->object-byte-list #"AB"))
(define singleton-string (bytes->object-string #"A"))
(define singleton-string-tail (lazy-apply STRING-TAIL singleton-string))

(for ([case
       (in-list
        (list
         (cons "Byte TAIL singleton"
               (lazy-apply typed-tail (bytes->object-byte-list #"A")))
         (cons "Byte TAKE 0"
               (apply2 typed-take-rat (whole-rat-object 0) two-byte-list))
         (cons "Byte DROP exact length"
               (apply2 typed-drop-rat (whole-rat-object 2) two-byte-list))
         (cons "Byte DROP beyond length"
               (apply2 typed-drop-rat (whole-rat-object 3) two-byte-list))
         (cons "STRING-TO-BYTES empty" (lazy-apply STRING-TO-BYTES EMPTY-STRING))
         (cons "STRING-TO-BYTES singleton tail"
               (lazy-apply STRING-TO-BYTES singleton-string-tail))
         (cons "String/Byte/DROP/String/Byte composition"
               (lazy-apply STRING-TO-BYTES
                           (lazy-apply BYTES-TO-STRING
                                       (apply2 typed-drop-rat (whole-rat-object 1)
                                               (lazy-apply STRING-TO-BYTES
                                                           singleton-string)))))))])
  (check-equal? (object-byte-list->bytes (cdr case)) #"" (car case))
  (check-eq? (force (cdr case)) (force NIL) (car case)))

(for ([case
       (in-list
        (list
         (cons "MAKE-STRING NIL" (lazy-apply MAKE-STRING NIL))
         (cons "STRING-TAIL singleton" singleton-string-tail)
         (cons "STRING-APPEND empty empty"
               (apply2 STRING-APPEND EMPTY-STRING EMPTY-STRING))
         (cons "BYTES-TO-STRING NIL" (lazy-apply BYTES-TO-STRING NIL))))])
  (check-equal? (object-string->bytes (cdr case)) #"" (car case))
  (check-eq? (force (lazy-apply raw-string-value (cdr case)))
             (force NIL)
             (car case)))

;; ---------------------------------------------------------------------------
;; Cyclic chains are rejected as forged, never walked forever. The walk uses
;; Floyd tortoise/hare detection (codec forbids mutable state), so cycles of
;; several lengths behind several proper prefixes pin the property.

(define (cycle-cells cycle-length)
  (letrec ([head-cell
            (let build ([i cycle-length])
              (if (= i 1)
                  (apply2 raw-cons TRUE (lazy head-cell))
                  (apply2 raw-cons TRUE (build (sub1 i)))))])
    head-cell))

(define (with-prefix prefix-length cyclic)
  (let build ([i prefix-length])
    (if (zero? i)
        cyclic
        (apply2 raw-cons TRUE (build (sub1 i))))))

(for* ([cycle-length (in-list '(1 2 3 5))]
       [prefix-length (in-list '(0 1 2 5))])
  (define walked
    (object-list->host-list
     (with-prefix prefix-length (cycle-cells cycle-length))))
  (check-true (codec-failure? walked)
              (format "cycle ~a prefix ~a" cycle-length prefix-length))
  (check-equal? (codec-failure-reason walked)
                'wrong-type
                (format "cycle ~a prefix ~a" cycle-length prefix-length)))
