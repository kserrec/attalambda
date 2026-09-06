#lang racket/base

(require racket/promise
         "../core/chars.rkt"
         "list.rkt"
         "raw-boolean.rkt")

(provide char-value->integer
         char-value->string)

(define (char-value->integer value)
  (for/fold ([total 0])
            ([bit (in-list
                   (list->host-list
                    ((force raw-char-value) value)
                    raw-boolean->boolean))])
    (+ (* total 2)
       (if bit 1 0))))

(define (supported-ascii-code? code)
  (or (memv code '(9 10 13))
      (<= 32 code 126)))

(define (char-value->string value)
  (define code
    (char-value->integer value))
  (if (supported-ascii-code? code)
      (string (integer->char code))
      (format "char:~a" code)))
