#lang racket/base

;; Which type system the checker applies. Both systems share the audited
;; catalog; they differ only in whether user bindings are generalized.
(provide (struct-out type-system) hm-system simple-system system-ref)
(struct type-system (name generalize?) #:transparent)
(define hm-system (type-system "hm" #t))
(define simple-system (type-system "simple" #f))
(define (system-ref name)
  (cond [(equal? name "hm") hm-system]
        [(equal? name "simple") simple-system]
        [else #f]))
