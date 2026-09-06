#lang racket/base

(require racket/promise
         "../core/strings.rkt"
         "char.rkt"
         "list.rkt")

(provide string-value->string)

(define (string-value->string value)
  (apply
   string-append
   (list->host-list
    ((force raw-string-value) value)
    char-value->string)))
