#lang s-exp "../macros/lazy-with-macros.rkt"

(require "../macros/macros.rkt"
         "binary-nat.rkt"
         "fix.rkt"
         "function-names.rkt"
         "lists.rkt"
         "logic.rkt"
         "objects.rkt"
         (only-in "option.rkt" NONE raw-make-some)
         "tags.rkt"
         "typecheck.rkt"
         (only-in "errors.rkt"
                  raw-add-result-frame
                  invalid-count-error)
         (only-in "rat.rkt"
                  raw-rat-is-nonnegative-whole
                  raw-rat-magnitude-bits
                  raw-whole-rat))

(provide raw-list-length
         raw-list-take
         raw-list-drop
         typed-len-rat
         typed-take-rat
         typed-drop-rat
         typed-nth-rat)

(def raw-list-length-step recur list count =
  (((raw-if
     (raw-list-is-nil list))
    count)
   ((recur
     (raw-list-tail list))
    (raw-nat-succ count))))

(def raw-list-length list =
  (((raw-fix raw-list-length-step)
    list)
   raw-zero-bits))

(def raw-list-take-step recur count list =
  (((raw-if
     ((raw-or
       (raw-nat-is-zero count))
      (raw-list-is-nil list)))
    NIL)
   ((raw-cons
     (raw-list-head list))
    ((recur
      ((raw-nat-sub count)
       raw-one-bits))
     (raw-list-tail list)))))

(def raw-list-take count list =
  (((raw-fix raw-list-take-step)
    count)
   list))

(def raw-list-drop-step recur count list =
  (((raw-if
     ((raw-or
       (raw-nat-is-zero count))
      (raw-list-is-nil list)))
    list)
   ((recur
     ((raw-nat-sub count)
      raw-one-bits))
    (raw-list-tail list))))

(def raw-list-drop count list =
  (((raw-fix raw-list-drop-step)
    count)
   list))

;; The public counting surface is Rat-based since the Step 35.5 switch.
;; Counting and indexing stay on private binary Nat; the Rat layer only
;; validates and converts at the typed boundary.

(def rat-list-signature =
  ((raw-cons rat-type)
   ((raw-cons list-type) NIL)))

(def raw-list-length-rat-value list-value =
  (raw-whole-rat
   (raw-list-length
    (raw-list-object list-value))))

(def raw-list-take-rat-values count list-value =
  (((raw-if
     (raw-rat-is-nonnegative-whole count))
    ((raw-list-take
      (raw-rat-magnitude-bits count))
     (raw-list-object list-value)))
   ((raw-add-result-frame invalid-count-error)
    take-function-name)))

;; raw-rebuild-list, not raw-list-object: drop can return the rebuilt
;; object itself, so an empty rebuild must restore the one canonical NIL
;; the codec's forged-terminator hardening requires.
(def raw-list-drop-rat-values count list-value =
  (((raw-if
     (raw-rat-is-nonnegative-whole count))
    ((raw-list-drop
      (raw-rat-magnitude-bits count))
     (raw-rebuild-list list-value)))
   ((raw-add-result-frame invalid-count-error)
    drop-function-name)))

(def typed-len-rat =
  ((((make-typed-function raw-list-length-rat-value)
     len-function-name)
    list-unary-signature)
   (raw-wrap-return rat-type)))

(def typed-take-rat =
  ((((make-typed-function raw-list-take-rat-values)
     take-function-name)
    rat-list-signature)
   raw-keep-return))

(def typed-drop-rat =
  ((((make-typed-function raw-list-drop-rat-values)
     drop-function-name)
    rat-list-signature)
   raw-keep-return))

(def raw-list-nth-rat-values index list-value =
  (((raw-if (raw-rat-is-nonnegative-whole index))
    (lambda-let remaining =
      ((raw-list-drop (raw-rat-magnitude-bits index))
       (raw-rebuild-list list-value))
      (((raw-if (raw-list-is-nil remaining))
        NONE)
       (raw-make-some (raw-list-head remaining)))))
   ((raw-add-result-frame invalid-count-error) nth-function-name)))

(def typed-nth-rat =
  ((((make-typed-function raw-list-nth-rat-values)
     nth-function-name)
    rat-list-signature)
   raw-keep-return))
