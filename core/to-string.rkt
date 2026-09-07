#lang s-exp "../macros/lazy-with-macros.rkt"

(require "../macros/macros.rkt"
         "function-names.rkt" "lists.rkt" "tags.rkt"
         "typecheck.rkt" "render-scalars.rkt" "render-error.rkt"
         "errors.rkt" "logic.rkt" "objects.rkt")

(provide typed-error-to-string
         typed-rat-to-string
         typed-bool-to-string
         typed-unit-to-string
         typed-byte-to-string
         typed-char-to-string
         typed-string-to-string
         (rename-out [typed-error-to-string error-to-string]
                     [typed-rat-to-string rat-to-string]
                     [typed-bool-to-string bool-to-string]
                     [typed-unit-to-string unit-to-string]
                     [typed-byte-to-string byte-to-string]
                     [typed-char-to-string char-to-string]
                     [typed-string-to-string string-to-string]))

(def typed-rat-to-string =
  ((((make-typed-function raw-render-rat) rat-to-string-function-name)
    ((raw-cons rat-type) NIL)) (raw-wrap-return string-type)))
(def typed-bool-to-string =
  ((((make-typed-function raw-render-bool) bool-to-string-function-name)
    ((raw-cons bool-type) NIL)) (raw-wrap-return string-type)))
(def typed-unit-to-string =
  ((((make-typed-function raw-render-unit) unit-to-string-function-name)
    ((raw-cons unit-type) NIL)) (raw-wrap-return string-type)))
(def typed-byte-to-string =
  ((((make-typed-function raw-render-byte) byte-to-string-function-name)
    ((raw-cons byte-type) NIL)) (raw-wrap-return string-type)))
(def typed-char-to-string =
  ((((make-typed-function raw-render-char) char-to-string-function-name)
    ((raw-cons char-type) NIL)) (raw-wrap-return string-type)))
(def typed-string-to-string =
  ((((make-typed-function raw-render-string) string-to-string-function-name)
    ((raw-cons string-type) NIL)) (raw-wrap-return string-type)))

;; Like make-err, consume Error as data instead of automatically bubbling it.
(def typed-error-to-string error =
  (((raw-if ((raw-is-type error-type) error))
    ((raw-make-object string-type) (raw-render-error (raw-object-value error))))
   ((((raw-bubble-error
       (((raw-make-type-mismatch-error argument-position-one) error-type)
        (raw-object-type error)))
      error-to-string-function-name)
     argument-position-one) error-type)))
