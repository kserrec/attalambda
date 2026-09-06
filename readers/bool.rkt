#lang racket/base

(require racket/promise
         "../core/objects.rkt"
         "raw-boolean.rkt")

(provide bool->boolean)

(define (bool->boolean value)
  (raw-boolean->boolean
   ((force raw-object-value) value)))
