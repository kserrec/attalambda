#lang racket/base

(require rackunit racket/list racket/promise racket/format
         "../core/errors.rkt" "../core/lists.rkt" "../core/objects.rkt"
         "../core/strings.rkt" "../core/tags.rkt" "../core/to-string.rkt"
         (only-in "../core/typed-logic.rkt" TRUE FALSE) "../core/unit.rkt"
         "../readers/error.rkt" "../readers/string.rkt"
         "helpers/lazy.rkt" "helpers/values.rkt")

(define (byte-object tag n)
  (apply2 raw-make-object tag (integer->raw-bits n)))
(define (host-list xs)
  (foldr (lambda (x tail) (apply2 raw-cons x tail)) NIL xs))
(define (byte-string xs)
  (lazy-apply raw-make-string
              (host-list (map (lambda (n) (byte-object char-type n)) xs))))
(define (check-render renderer input expected)
  (define result (lazy-apply renderer input))
  (check-equal? (object-tag result) 6)
  (check-equal? (string-value->string result) expected))

(for ([n (in-list (list 0 1 42 -42 3/7 -7/3 1200 -1200
                        123456789012345678901234567890
                        -123456789012345678901234567890/7))])
  (check-render rat-to-string (exact->typed-rat n) (number->string n)))
(check-render bool-to-string TRUE "TRUE")
(check-render bool-to-string FALSE "FALSE")
(check-render unit-to-string UNIT "UNIT")
(check-render unit-to-string
              (apply2 raw-make-object unit-type (delay (error 'unused)))
              "UNIT")

;; Every byte: independent host oracle pins the complete classification,
;; uppercase two-digit escapes and both hex nibbles, not selected examples.
(define (hex n) (string-upcase (~r n #:base 16 #:min-width 2 #:pad-string "0")))
(define (escaped-byte n)
  (case n
    [(34) "\\\""] [(92) "\\\\"] [(10) "\\n"] [(9) "\\t"] [(13) "\\r"]
    [else (if (<= 32 n 126) (string (integer->char n))
              (string-append "\\x" (hex n)))]))
(for ([n (in-range 256)])
  (check-render byte-to-string (byte-object byte-type n) (format "BYTE(~a)" n))
  (check-render char-to-string (byte-object char-type n)
                (case n
                  [(32) "#\\space"] [(9) "#\\tab"] [(10) "#\\newline"]
                  [(13) "#\\return"]
                  [else (if (<= 33 n 126)
                            (string-append "#\\" (string (integer->char n)))
                            (format "CHAR(~a)" n))]))
  (check-render string-to-string (byte-string (list n))
                (string-append "\"" (escaped-byte n) "\"")))
(check-render string-to-string EMPTY-STRING "\"\"")
(check-render string-to-string (byte-string '(104 101 108 108 111)) "\"hello\"")
(check-render string-to-string (byte-string '(195 169 240 159 152 128))
              "\"\\xC3\\xA9\\xF0\\x9F\\x98\\x80\"")
(check-render string-to-string (byte-string (range 256))
              (string-append "\"" (apply string-append (map escaped-byte (range 256))) "\""))

(define scalar-cases
  (list (list rat-to-string "rat-to-string" "RAT" TRUE "BOOL")
        (list bool-to-string "bool-to-string" "BOOL" UNIT "UNIT")
        (list unit-to-string "unit-to-string" "UNIT" TRUE "BOOL")
        (list byte-to-string "byte-to-string" "BYTE" TRUE "BOOL")
        (list char-to-string "char-to-string" "CHAR" TRUE "BOOL")
        (list string-to-string "string-to-string" "STRING" TRUE "BOOL")))
(for ([entry (in-list scalar-cases)])
  (define renderer (first entry))
  (check-equal? (error-value->string (lazy-apply renderer (fourth entry)))
                (format "~a(arg1 expected ~a got ~a)"
                        (second entry) (third entry) (fifth entry)))
  (check-equal? (error-value->string (lazy-apply renderer invalid-nat-error))
                (format "INVALID-NAT\n  -> ~a(arg1 expected ~a)"
                        (second entry) (third entry))))
