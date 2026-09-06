#lang racket/base

(require racket/promise
         "../core/int.rkt"
         "list.rkt"
         "raw-boolean.rkt")

(provide int->integer)

(define (int->integer value)
  (define total
    (for/fold ([total 0])
              ([bit (in-list
                     (list->host-list
                      ((force raw-int-magnitude) value)
                      raw-boolean->boolean))])
      (+ (* total 2)
         (if bit 1 0))))
  (if (raw-boolean->boolean
       ((force raw-int-sign) value))
      total
      (- total)))
