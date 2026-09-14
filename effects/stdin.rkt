#lang s-exp "../macros/lazy-with-macros.rkt"

(require "../macros/macros.rkt"
         (only-in "../core/errors.rkt" NIL)
         (only-in "../core/lists.rkt" raw-cons)
         "../core/tags.rkt"
         "../core/typecheck.rkt"
         "protocol.rkt")

(provide make-read-line-request
         make-read-line)

(def read-line-unit-signature =
  ((raw-cons unit-type) NIL))

;; Unit triggers the unary public call; the native operation has no payload.
(def raw-make-read-line-request unit-payload =
  ((raw-cons read-line-operation) NIL))

(def make-read-line-request =
  ((((make-typed-function raw-make-read-line-request)
     read-line-function-name)
    read-line-unit-signature)
   raw-keep-return))

(def raw-call-read-line host unit-payload =
  (host (raw-make-read-line-request unit-payload)))

;; The call remains inside the unary function, so each demanded application
;; can read again. Reusing one lazy result reuses that answer.
(def make-read-line host =
  ((((make-typed-function (raw-call-read-line host))
     read-line-function-name)
    read-line-unit-signature)
   raw-keep-return))
