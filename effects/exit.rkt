#lang s-exp "../macros/lazy-with-macros.rkt"

(require "../macros/macros.rkt"
         (only-in "../core/errors.rkt"
                  NIL
                  invalid-count-error
                  raw-add-result-frame)
         (only-in "../core/lists.rkt" raw-cons)
         "../core/logic.rkt"
         "../core/objects.rkt"
         (only-in "../core/rat.rkt"
                  raw-rat-equal
                  raw-rat-zero
                  raw-rat-one)
         "../core/tags.rkt"
         "../core/typecheck.rkt"
         "protocol.rkt")

(provide make-exit-request
         make-exit)

(def exit-rat-signature =
  ((raw-cons rat-type) NIL))

;; Status selection and validation are pure Rat computation. Only the injected
;; host performs termination; a returning fake host keeps its ordinary result.
(def raw-make-exit-request status-payload =
  (((raw-if
     ((raw-or
       ((raw-rat-equal status-payload) raw-rat-zero))
      ((raw-rat-equal status-payload) raw-rat-one)))
    ((raw-cons exit-operation)
     ((raw-cons
       ((raw-make-object rat-type) status-payload))
      NIL)))
   ((raw-add-result-frame invalid-count-error)
    exit-function-name)))

(def make-exit-request =
  ((((make-typed-function raw-make-exit-request)
     exit-function-name)
    exit-rat-signature)
   raw-keep-return))

(def raw-call-exit host status-payload =
  ((raw-dispatch-or-bubble host)
   (raw-make-exit-request status-payload)))

(def make-exit host =
  ((((make-typed-function (raw-call-exit host))
     exit-function-name)
    exit-rat-signature)
   raw-keep-return))
