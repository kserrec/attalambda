#lang s-exp "../macros/lazy-with-macros.rkt"

(require "../macros/macros.rkt"
         "errors.rkt"
         "fix.rkt"
         "function-names.rkt"
         "logic.rkt"
         "objects.rkt"
         "pair.rkt"
         "tags.rkt"
         "typecheck.rkt")

(provide NIL
         raw-cons
         list-unary-signature
         raw-list-head
         raw-list-tail
         raw-list-is-nil
         raw-list-object
         raw-rebuild-list
         typed-cons
         typed-head
         typed-tail
         typed-is-nil
         typed-list-case
         raw-fold
         raw-append
         raw-reverse
         raw-map
         raw-filter)

(def raw-list-head list =
  (raw-first (raw-object-value list)))

(def raw-list-tail list =
  (raw-second (raw-object-value list)))

(def raw-list-is-nil list =
  ((raw-is-type error-type)
   (raw-list-tail list)))

(def raw-list-object payload =
  ((raw-make-object list-type) payload))

;; Rebuilding a List object from a checker-unwrapped payload must restore
;; the one canonical NIL for the empty case: the codec deliberately
;; rejects any other terminator as forged.
(def raw-rebuild-list payload =
  (lambda-let rebuilt = (raw-list-object payload)
    (((raw-if
       (raw-list-is-nil rebuilt))
      NIL)
     rebuilt)))

(def list-unary-signature =
  ((raw-cons list-type) NIL))

(def raw-list-payload-head payload =
  (raw-first payload))

(def raw-list-payload-tail payload =
  (raw-second payload))

(def raw-list-payload-is-nil payload =
  ((raw-is-type error-type)
   (raw-list-payload-tail payload)))

(def raw-checked-list-head payload =
  (((raw-if
     (raw-list-payload-is-nil payload))
    ((raw-add-result-frame empty-list-error)
     head-function-name))
   (raw-list-payload-head payload)))

(def raw-checked-list-tail payload =
  (((raw-if
     (raw-list-payload-is-nil payload))
    ((raw-add-result-frame empty-list-error)
     tail-function-name))
   (raw-list-payload-tail payload)))

(def typed-cons value tail =
  (((raw-if
     ((raw-is-type error-type) value))
    value)
   ((((((raw-check-argument cons-function-name)
        argument-position-two)
       list-type)
      raw-keep-return)
     (raw-cons value))
    tail)))

(def typed-head =
  ((((make-typed-function raw-checked-list-head)
     head-function-name)
    list-unary-signature)
   raw-keep-return))

(def typed-tail =
  ((((make-typed-function raw-checked-list-tail)
     tail-function-name)
    list-unary-signature)
   raw-keep-return))

(def typed-is-nil =
  ((((make-typed-function raw-list-payload-is-nil)
     is-nil-function-name)
    list-unary-signature)
   (raw-wrap-return bool-type)))

;; LIST-CASE list cons-function nil-value: strict on the List, lazy on
;; both branches. A populated List applies the curried callback to the
;; head and then the tail; NIL selects the caller-supplied value.
(def typed-list-case list cons-function nil-value =
  (((raw-if
     ((raw-is-type error-type) list))
    ((((raw-bubble-error list)
       list-case-function-name)
      argument-position-one)
     list-type))
   (((raw-if
      ((raw-is-type list-type) list))
     (((raw-if
        (raw-list-is-nil list))
       nil-value)
      ((cons-function (raw-list-head list))
       (raw-list-tail list))))
    ((((raw-bubble-error
        (((raw-make-type-mismatch-error
           argument-position-one)
          list-type)
         (raw-object-type list)))
       list-case-function-name)
      argument-position-one)
     list-type))))

(def raw-fold-step recur function initial list =
  (((raw-if
     (raw-list-is-nil list))
    initial)
   ((function (raw-list-head list))
    (((recur function) initial)
     (raw-list-tail list)))))

(def raw-fold =
  (raw-fix raw-fold-step))

(def raw-append left right =
  (((raw-fold raw-cons) right) left))

(def raw-reverse-step recur remaining reversed =
  (((raw-if
     (raw-list-is-nil remaining))
    reversed)
   ((recur (raw-list-tail remaining))
    ((raw-cons (raw-list-head remaining))
     reversed))))

(def raw-reverse list =
  (((raw-fix raw-reverse-step) list) NIL))

(def raw-map-step function value mapped-tail =
  ((raw-cons (function value)) mapped-tail))

(def raw-map function list =
  (((raw-fold (raw-map-step function)) NIL)
   list))

(def raw-filter-step predicate value filtered-tail =
  (((raw-if
     (predicate value))
    ((raw-cons value) filtered-tail))
   filtered-tail))

(def raw-filter predicate list =
  (((raw-fold (raw-filter-step predicate)) NIL)
   list))
