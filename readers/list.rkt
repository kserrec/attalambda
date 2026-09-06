#lang racket/base

(require racket/promise
         "../core/lists.rkt"
         "bool.rkt")

(provide list->host-list)

(define (list->host-list value read-value)
  (let loop ([remaining value])
    (if (bool->boolean
         ((force typed-is-nil) remaining))
        '()
        (cons
         (read-value
          ((force typed-head) remaining))
         (loop
          ((force typed-tail) remaining))))))
