#lang racket/base

(require rackunit
         racket/promise
         "../core/lists.rkt"
         "../core/logic.rkt"
         "../core/objects.rkt"
         "../core/result.rkt"
         "../core/tags.rkt"
         "../core/unit.rkt"
         "../readers/bool.rkt"
         "../readers/raw-boolean.rkt"
         "../readers/type-tag.rkt"
         "../readers/unit.rkt"
         "../runtime/codec.rkt"
         "helpers/lazy.rkt")

(define (typed-value? type value)
  (raw-boolean->boolean
   (apply2 raw-is-type type value)))

;; UNIT is the single Unit value: tag 8, distinct from every other public
;; type, and never confusable with NIL, false, or zero.
(check-true (typed-value? unit-type UNIT))
(check-equal?
 (type-tag->integer
  (lazy-apply raw-object-type UNIT))
 8)
(check-false (typed-value? unit-type NIL))
(check-false (typed-value? list-type UNIT))
(check-false (typed-value? bool-type UNIT))
(check-false (typed-value? rat-type UNIT))

;; The one-way reader renders the value's type name.
(check-equal? (unit->string UNIT) "UNIT")

;; The codec exposes the same canonical value to the host, and successful
;; no-value acknowledgements are Ok(UNIT).
(check-true (typed-value? unit-type object-unit))
(define acknowledgement (object-ok object-unit))
(check-true (typed-value? result-type acknowledgement))
(check-true
 (bool->boolean (lazy-apply is-ok acknowledgement)))
(check-true
 (typed-value? unit-type
               (lazy-apply unwrap-ok acknowledgement)))

;; NIL still means only an actual empty List.
(check-true (typed-value? list-type NIL))
(check-true
 (bool->boolean (lazy-apply typed-is-nil NIL)))

;; Unit participates lazily like every tagged value: an unselected branch
;; holding a divergent payload is never forced.
(define fragile-unit
  (apply2 raw-make-object
          unit-type
          (delay
            (error 'unit "forced unselected Unit payload"))))
(check-true (typed-value? unit-type fragile-unit))
