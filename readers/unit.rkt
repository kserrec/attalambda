#lang racket/base

(require racket/promise
         "../core/objects.rkt"
         "type-tag.rkt")

(provide unit->string)

(define (unit->string value)
  (type-tag->string
   ((force raw-object-type) value)))
