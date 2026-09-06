#lang racket/base

(require rackunit
         racket/promise
         "../core/byte.rkt"
         "../core/chars.rkt"
         "../core/errors.rkt"
         "../core/int.rkt"
         "../core/lists.rkt"
         "../core/logic.rkt"
         "../core/map.rkt"
         "../core/objects.rkt"
         "../core/pair.rkt"
         "../core/option.rkt"
         "../core/rat.rkt"
         (only-in "../core/strings.rkt" MAKE-STRING STRING-EQ)
         "../core/tags.rkt"
         (only-in "../core/typed-logic.rkt" TRUE FALSE)
         (only-in "../core/typed-rat.rkt" typed-rat-equal)
         "../readers/bool.rkt"
         "../readers/error.rkt"
         "../readers/map.rkt"
         "../readers/option.rkt"
         "../readers/rat.rkt"
         "../readers/raw-boolean.rkt"
         "../readers/type-tag.rkt"
         "helpers/lazy.rkt"
         (only-in "helpers/values.rkt"
                  apply2
                  typed-value?
                  object-tag
                  host-bits->raw
                  whole-rat-object
                  rat-object->number))

(define (lookup-number map-value key)
  (define result (apply2 MAP-LOOKUP map-value key))
  (check-equal? (object-tag result) 10)
  (if (bool->boolean (lazy-apply IS-SOME result))
      (rat-object->number
       (lazy-apply raw-option-value
                   (lazy-apply raw-object-value result)))
      'none))

;; An empty Map under Rat equality: lookup is expected absence, size zero.
(define rat-map (lazy-apply MAKE-MAP typed-rat-equal))
(check-equal? (object-tag rat-map) 11)
(check-true (bool->boolean (lazy-apply MAP-EMPTY? rat-map)))
(check-equal? (rat-object->number (lazy-apply MAP-SIZE rat-map)) 0)
(check-equal? (map->string rat-map) "MAP:0")
(check-equal? (lookup-number rat-map (whole-rat-object 1)) 'none)


;; Wrong Map arguments and incoming Errors carry the operation's frame.
(check-equal?
 (error-value->string (apply2 MAP-LOOKUP TRUE (whole-rat-object 1)))
 "map-lookup(arg1 expected MAP got BOOL)")
(check-equal?
 (error-value->string
  (apply2 MAP-LOOKUP invalid-nat-error (whole-rat-object 1)))
 "INVALID-NAT\n  -> map-lookup(arg1 expected MAP)")
(check-equal?
 (error-value->string
  (apply2 MAP-LOOKUP rat-map invalid-nat-error))
 "INVALID-NAT\n  -> map-lookup(result)")
(check-equal?
 (error-value->string (lazy-apply MAP-EMPTY? TRUE))
 "map-empty?(arg1 expected MAP got BOOL)")
(check-equal?
 (error-value->string (lazy-apply MAP-SIZE TRUE))
 "map-size(arg1 expected MAP got BOOL)")

;; An equality function that answers with a non-Bool is a structured
;; Error; one that answers with an Error bubbles. Both need one entry so
;; a comparison actually runs — built through the raw layer here, ahead
;; of the Step 39.2 public MAP-SET.
(define (raw-map-with-one-entry equality key value)
  (apply2 raw-make-object
          map-type
          (apply2 raw-pair
                  equality
                  (apply2 raw-cons
                          (apply2 raw-pair key value)
                          NIL))))

(define wrong-answer-map
  (raw-map-with-one-entry
   (lambda (left) (lambda (right) (whole-rat-object 1)))
   (whole-rat-object 1)
   (whole-rat-object 2)))
(check-equal?
 (error-value->string
  (apply2 MAP-LOOKUP wrong-answer-map (whole-rat-object 1)))
 "map-lookup(arg1 expected BOOL got RAT)")

(define error-answer-map
  (raw-map-with-one-entry
   (lambda (left) (lambda (right) invalid-nat-error))
   (whole-rat-object 1)
   (whole-rat-object 2)))
(check-equal?
 (error-value->string
  (apply2 MAP-LOOKUP error-answer-map (whole-rat-object 1)))
 "INVALID-NAT\n  -> map-lookup(result)")

;; A found entry returns SOME of its stored value under the Map's own
;; equality function.
(define populated
  (raw-map-with-one-entry typed-rat-equal
                          (whole-rat-object 4)
                          (whole-rat-object 44)))
(check-equal? (lookup-number populated (whole-rat-object 4)) 44)
(check-equal? (lookup-number populated (whole-rat-object 5)) 'none)
(check-false (bool->boolean (lazy-apply MAP-EMPTY? populated)))
(check-equal? (rat-object->number (lazy-apply MAP-SIZE populated)) 1)
(check-equal? (map->string populated) "MAP:1")

;; Operations remain chains of unary lambdas.
(for ([function (in-list (list MAKE-MAP MAP-EMPTY? MAP-SIZE MAP-LOOKUP))])
  (check-equal? (procedure-arity (lazy-force function)) 1))
(check-equal?
 (procedure-arity (lazy-force (lazy-apply MAP-LOOKUP rat-map)))
 1)

;; Step 39.2: persistent updates and queries.

(define (typed-bool value)
  (apply2 raw-make-object bool-type value))

(define (set3 map-value key value)
  (lazy-apply
   (apply2 MAP-SET map-value key)
   value))

;; Build 1->11, 2->22, 3->33; replace 2; remove 1; older maps unchanged.
(define map-zero (lazy-apply MAKE-MAP typed-rat-equal))
(define map-one
  (set3 map-zero (whole-rat-object 1) (whole-rat-object 11)))
(define map-two
  (set3 map-one (whole-rat-object 2) (whole-rat-object 22)))
(define map-three
  (set3 map-two (whole-rat-object 3) (whole-rat-object 33)))
(define map-replaced
  (set3 map-three (whole-rat-object 2) (whole-rat-object 220)))
(define map-removed
  (apply2 MAP-REMOVE map-replaced (whole-rat-object 1)))

(check-equal? (rat-object->number (lazy-apply MAP-SIZE map-three)) 3)
(check-equal? (lookup-number map-three (whole-rat-object 2)) 22)

;; Replacement keeps exactly one entry for the key.
(check-equal? (rat-object->number (lazy-apply MAP-SIZE map-replaced)) 3)
(check-equal? (lookup-number map-replaced (whole-rat-object 2)) 220)

;; Removal drops one entry; removing an absent key is an equivalent Map.
(check-equal? (rat-object->number (lazy-apply MAP-SIZE map-removed)) 2)
(check-equal? (lookup-number map-removed (whole-rat-object 1)) 'none)
(check-equal? (lookup-number map-removed (whole-rat-object 3)) 33)
(define map-removed-absent
  (apply2 MAP-REMOVE map-removed (whole-rat-object 9)))
(check-equal? (rat-object->number (lazy-apply MAP-SIZE map-removed-absent)) 2)
(check-equal? (lookup-number map-removed-absent (whole-rat-object 3)) 33)

;; Persistence: every older Map still returns its older answers.
(check-true (bool->boolean (lazy-apply MAP-EMPTY? map-zero)))
(check-equal? (lookup-number map-one (whole-rat-object 1)) 11)
(check-equal? (lookup-number map-one (whole-rat-object 2)) 'none)
(check-equal? (lookup-number map-three (whole-rat-object 2)) 22)
(check-equal? (lookup-number map-replaced (whole-rat-object 1)) 11)

;; MAP-CONTAINS? is the strict Bool query.
(for ([case (in-list '((1 #f) (2 #t) (3 #t) (9 #f)))])
  (check-equal?
   (bool->boolean
    (apply2 MAP-CONTAINS? map-removed (whole-rat-object (car case))))
   (cadr case)))
(check-equal?
 (error-value->string (apply2 MAP-CONTAINS? TRUE (whole-rat-object 1)))
 "map-contains?(arg1 expected MAP got BOOL)")

;; String, Char, and Byte equality functions drive the same Map machinery,
;; and a custom coarse equality produces deliberate collisions.
(define (chars->string-object chars)
  (lazy-apply
   MAKE-STRING
   (foldr (lambda (value tail) (apply2 typed-cons value tail))
          NIL
          chars)))
(define hello (chars->string-object (list h e l l o)))
(define hi (chars->string-object (list h i)))
(define string-map
  (set3 (lazy-apply MAKE-MAP STRING-EQ)
        hello
        (whole-rat-object 5)))
(check-equal? (lookup-number string-map
                             (chars->string-object (list h e l l o)))
              5)
(check-equal? (lookup-number string-map hi) 'none)

(define char-map
  (set3 (lazy-apply MAKE-MAP CHAR-EQ) A (whole-rat-object 65)))
(check-equal? (lookup-number char-map A) 65)
(check-equal? (lookup-number char-map B) 'none)

(define byte-map
  (set3 (lazy-apply MAKE-MAP BYTE-EQ)
        (lazy-apply MAKE-BYTE (whole-rat-object 7))
        (whole-rat-object 77)))
(check-equal? (lookup-number byte-map
                             (lazy-apply MAKE-BYTE (whole-rat-object 7)))
              77)

;; A coarse equality that treats every key as equal collides by design:
;; set replaces the single entry, and lookup finds it under any key.
(define coarse-equality
  (lambda (left)
    (lambda (right)
      TRUE)))
(define coarse-map
  (set3 (set3 (lazy-apply MAKE-MAP coarse-equality)
              (whole-rat-object 1)
              (whole-rat-object 10))
        (whole-rat-object 2)
        (whole-rat-object 20)))
(check-equal? (rat-object->number (lazy-apply MAP-SIZE coarse-map)) 1)
(check-equal? (lookup-number coarse-map (whole-rat-object 9)) 20)

;; Error keys and values bubble with the operation's frame; wrong Maps
;; are ordinary mismatches; partial applications stay unary.
(check-equal?
 (error-value->string
  (set3 map-zero invalid-nat-error (whole-rat-object 1)))
 "INVALID-NAT\n  -> map-set(result)")
(check-equal?
 (error-value->string
  (set3 map-zero (whole-rat-object 1) invalid-nat-error))
 "INVALID-NAT\n  -> map-set(result)")
(check-equal?
 (error-value->string
  (apply2 MAP-REMOVE invalid-nat-error (whole-rat-object 1)))
 "INVALID-NAT\n  -> map-remove(arg1 expected MAP)")
(check-equal?
 (error-value->string
  (set3 TRUE (whole-rat-object 1) (whole-rat-object 2)))
 "map-set(arg1 expected MAP got BOOL)")

;; A failing comparison mid-walk is the whole answer, not a mangled Map.
(check-equal?
 (error-value->string
  (set3 error-answer-map (whole-rat-object 1) (whole-rat-object 2)))
 "INVALID-NAT\n  -> map-set(result)")

;; Laziness: a pending update runs no comparison until the new Map is
;; demanded — binding it and taking further partial applications forces
;; nothing.
(define fragile-map
  (raw-map-with-one-entry
   (lambda (left)
     (lambda (right)
       (delay (error 'map "forced comparison during construction"))))
   (whole-rat-object 1)
   (whole-rat-object 2)))
(define untouched-partial
  (apply2 MAP-SET fragile-map (whole-rat-object 3)))
(check-equal?
 (procedure-arity (lazy-force untouched-partial))
 1)

(for ([function (in-list (list MAP-CONTAINS? MAP-SET MAP-REMOVE))])
  (check-equal? (procedure-arity (lazy-force function)) 1))
(check-equal?
 (procedure-arity
  (lazy-force (apply2 MAP-SET map-zero (whole-rat-object 1))))
 1)
