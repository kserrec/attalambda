#lang racket/base

(require racket/promise)

(provide lazy-apply
         apply2
         apply3
         lazy-force)

(define (lazy-apply function argument)
  ((force function) argument))

(define (apply2 function first second)
  (lazy-apply (lazy-apply function first) second))

(define (apply3 function first second third)
  (lazy-apply (apply2 function first second) third))

(define (lazy-force value)
  (force value))
