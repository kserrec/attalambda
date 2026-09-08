#lang s-exp "../macros/lazy-with-macros.rkt"

(require "../macros/macros.rkt"
         (only-in "../core/to-string.rkt" value-to-string))

(provide make-print)

;; Receive the already injected stdout wrapper; never receive host itself.
(def make-print stdout value =
  (stdout (value-to-string value)))
