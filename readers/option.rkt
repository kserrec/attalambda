#lang racket/base

(require racket/promise
         "../core/objects.rkt"
         "../core/option.rkt"
         "raw-boolean.rkt")

(provide option->string)

(define (option->string value)
  (if (raw-boolean->boolean
       ((force raw-option-is-some)
        ((force raw-object-value) value)))
      "SOME"
      "NONE"))
