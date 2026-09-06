#lang s-exp "../macros/lazy-with-macros.rkt"

(require "../macros/macros.rkt"
         (only-in "binary-nat.rkt" raw-zero-bits raw-nat-succ)
         "errors.rkt"
         "fix.rkt"
         "function-names.rkt"
         "lists.rkt"
         (only-in "list-transform.rkt" typed-predicate-result)
         "logic.rkt"
         "objects.rkt"
         (only-in "option.rkt" NONE raw-make-some)
         (only-in "rat.rkt" raw-whole-rat)
         "tags.rkt"
         "typecheck.rkt"
         (only-in "typed-logic.rkt" TRUE FALSE))

(provide typed-any?
         typed-all?
         typed-find
         typed-find-index
         typed-contains?
         typed-take-while
         typed-drop-while)

;; any? and contains? share this same Boolean search; the supplied name
;; keeps callback failures attributed to the public operation being called.
(def typed-any-step recur predicate operation-name list =
  (((raw-if (raw-list-is-nil list))
    FALSE)
   (((typed-predicate-result (predicate (raw-list-head list))) operation-name)
    (lambda (matched)
      (((raw-if matched)
        TRUE)
       (((recur predicate) operation-name) (raw-list-tail list)))))))

(def typed-any? predicate list =
  ((((((raw-check-argument any-function-name)
       argument-position-two)
      list-type)
     raw-keep-return)
    (((raw-fix typed-any-step) predicate) any-function-name))
   list))

(def typed-all-step recur predicate list =
  (((raw-if (raw-list-is-nil list))
    TRUE)
   (((typed-predicate-result (predicate (raw-list-head list))) all-function-name)
    (lambda (matched)
      (((raw-if matched)
        ((recur predicate) (raw-list-tail list)))
       FALSE)))))

(def typed-all? predicate list =
  ((((((raw-check-argument all-function-name)
       argument-position-two)
      list-type)
     raw-keep-return)
    ((raw-fix typed-all-step) predicate))
   list))

(def typed-find-step recur predicate list =
  (((raw-if (raw-list-is-nil list))
    NONE)
   (((typed-predicate-result (predicate (raw-list-head list))) find-function-name)
    (lambda (matched)
      (((raw-if matched)
        (raw-make-some (raw-list-head list)))
       ((recur predicate) (raw-list-tail list)))))))

(def typed-find predicate list =
  ((((((raw-check-argument find-function-name)
       argument-position-two)
      list-type)
     raw-keep-return)
    ((raw-fix typed-find-step) predicate))
   list))

(def typed-find-index-step recur predicate index list =
  (((raw-if (raw-list-is-nil list))
    NONE)
   (((typed-predicate-result (predicate (raw-list-head list))) find-index-function-name)
    (lambda (matched)
      (((raw-if matched)
        (raw-make-some
         ((raw-make-object rat-type) (raw-whole-rat index))))
       (((recur predicate) (raw-nat-succ index)) (raw-list-tail list)))))))

(def typed-find-index predicate list =
  ((((((raw-check-argument find-index-function-name)
       argument-position-two)
      list-type)
     raw-keep-return)
    (((raw-fix typed-find-index-step) predicate) raw-zero-bits))
   list))

(def typed-contains? equality value list =
  (((raw-if ((raw-is-type error-type) value))
    ((raw-add-result-frame value) contains-function-name))
   ((((((raw-check-argument contains-function-name)
        (church-succ argument-position-two))
       list-type)
      raw-keep-return)
     (((raw-fix typed-any-step) (equality value)) contains-function-name))
    list)))

(def typed-take-while-step recur predicate list =
  (((raw-if (raw-list-is-nil list))
    NIL)
   (((typed-predicate-result (predicate (raw-list-head list))) take-while-function-name)
    (lambda (matched)
      (((raw-if matched)
        (lambda-let rest = ((recur predicate) (raw-list-tail list))
          (((raw-if ((raw-is-type error-type) rest))
            rest)
           ((raw-cons (raw-list-head list)) rest))))
       NIL)))))

(def typed-take-while predicate list =
  ((((((raw-check-argument take-while-function-name)
       argument-position-two)
      list-type)
     raw-keep-return)
    ((raw-fix typed-take-while-step) predicate))
   list))

(def typed-drop-while-step recur predicate list =
  (((raw-if (raw-list-is-nil list))
    NIL)
   (((typed-predicate-result (predicate (raw-list-head list))) drop-while-function-name)
    (lambda (matched)
      (((raw-if matched)
        ((recur predicate) (raw-list-tail list)))
       list)))))

(def typed-drop-while predicate list =
  ((((((raw-check-argument drop-while-function-name)
       argument-position-two)
      list-type)
     raw-keep-return)
    ((raw-fix typed-drop-while-step) predicate))
   list))
