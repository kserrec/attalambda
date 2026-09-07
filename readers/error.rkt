#lang racket/base

(require racket/promise
         "../core/render-error.rkt"
         "string.rkt")

(provide error-value->string)

;; The pure core owns formatting; this reader only observes its String.
(define (error-value->string error)
  (string-value->string ((force raw-error-diagnostic-string) error)))
