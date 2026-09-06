#lang s-exp "../macros/lazy-with-macros.rkt"

(require "../macros/macros.rkt"
         "errors.rkt"
         "function-names.rkt"
         "lists.rkt"
         "logic.rkt"
         "objects.rkt"
         "tags.rkt"
         "typecheck.rkt")

(provide typed-append
         typed-reverse
         typed-map
         typed-filter
         typed-predicate-result)

(def list-binary-signature =
  ((raw-cons list-type) list-unary-signature))

(def raw-append-values left right =
  ((raw-append (raw-rebuild-list left))
   (raw-rebuild-list right)))

(def raw-reverse-value list =
  (raw-reverse (raw-rebuild-list list)))

(def typed-append =
  ((((make-typed-function raw-append-values)
     append-function-name)
    list-binary-signature)
   raw-keep-return))

(def typed-reverse =
  ((((make-typed-function raw-reverse-value)
     reverse-function-name)
    list-unary-signature)
   raw-keep-return))

;; Callback results follow the existing Map convention: Bool is unwrapped,
;; Error gains the operation's result frame, and other tags fail as Bool.
(def typed-predicate-result answer operation-name continue =
  (((raw-if ((raw-is-type error-type) answer))
    ((raw-add-result-frame answer) operation-name))
   ((((((raw-check-argument operation-name)
        argument-position-one)
       bool-type)
      raw-keep-return)
     (lambda (validated)
       (continue (raw-object-value validated))))
    answer)))

;; raw-map intentionally stores results verbatim. This fold moves an Error
;; out of the result List, checking the head before the lazy mapped suffix.
(def typed-map-cons value rest =
  (((raw-if ((raw-is-type error-type) value))
    value)
   (((raw-if ((raw-is-type error-type) rest))
     rest)
    ((raw-cons value) rest))))

(def typed-map-list function list =
  (lambda-let result =
    (((raw-fold typed-map-cons) NIL)
     ((raw-map function) list))
    (((raw-if ((raw-is-type error-type) result))
      ((raw-add-result-frame result) map-function-name))
     result)))

(def typed-map function list =
  ((((((raw-check-argument map-function-name)
       argument-position-two)
      list-type)
     raw-keep-return)
    (typed-map-list function))
   list))

;; raw-filter supplies its keep/skip branches to this unary-lambda selector.
;; Validate the predicate before forcing the suffix, and propagate a suffix
;; Error before selecting the retained node so no improper tail is produced.
(def typed-filter-choice predicate value kept skipped =
  (((typed-predicate-result (predicate value)) filter-function-name)
   (lambda (matched)
     (((raw-if ((raw-is-type error-type) skipped))
       skipped)
      (((raw-if matched) kept) skipped)))))

(def typed-filter predicate list =
  ((((((raw-check-argument filter-function-name)
       argument-position-two)
      list-type)
     raw-keep-return)
    (raw-filter (typed-filter-choice predicate)))
   list))
