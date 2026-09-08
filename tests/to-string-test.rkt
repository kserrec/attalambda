#lang racket/base

(require rackunit racket/list racket/promise racket/format
         "../core/errors.rkt" "../core/lists.rkt" "../core/objects.rkt"
         "../core/option.rkt" "../core/result.rkt" "../core/map.rkt"
         "../core/pair.rkt" (only-in "../core/logic.rkt" raw-true raw-false)
         "../core/strings.rkt" "../core/tags.rkt" "../core/to-string.rkt"
         (only-in "../core/typed-logic.rkt" TRUE FALSE) "../core/unit.rkt"
         "../readers/error.rkt" "../readers/string.rkt"
         (only-in "../runtime/codec.rkt" object-string->bytes)
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
  (check-equal? (string-value->string result) expected)
  ;; The independent boundary decoder rejects malformed List tails, non-Char
  ;; elements and noncanonical/out-of-range binary payloads hidden by display.
  (check-equal? (object-string->bytes result) (string->bytes/utf-8 expected)))

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

(define one (exact->typed-rat 1))
(define two (exact->typed-rat 2))
(define hello (byte-string '(104 101 108 108 111)))
(define mixed (host-list (list one TRUE hello)))
(define empty-map
  (lazy-apply typed-make-map (lambda (key) (error 'unused-equality))))
(define entries
  (host-list (list (apply2 raw-pair hello one)
                   (apply2 raw-pair (host-list (list one two))
                           (lazy-apply raw-make-some TRUE)))))
(define mixed-map
  (apply2 raw-make-object map-type
          (apply2 raw-pair (delay (error 'unused-equality)) entries)))
(define failed (lazy-apply raw-make-err divide-by-zero-error))

(define generic-cases
  (list (list invalid-nat-error "ERROR(INVALID-NAT)")
        (list TRUE "TRUE") (list mixed "[1, TRUE, \"hello\"]")
        (list (lazy-apply raw-make-ok mixed) "OK([1, TRUE, \"hello\"])")
        (list (byte-object char-type 65) "#\\A")
        (list hello "\"hello\"") (list (exact->typed-rat -7/3) "-7/3")
        (list UNIT "UNIT") (list (byte-object byte-type 255) "BYTE(255)")
        (list (lazy-apply raw-make-some mixed) "SOME([1, TRUE, \"hello\"])")
        (list mixed-map "{\"hello\": 1, [1, 2]: SOME(TRUE)}")
        (list (lazy-apply raw-make-ok mixed-map)
              "OK({\"hello\": 1, [1, 2]: SOME(TRUE)})")
        (list (host-list (list mixed-map NONE))
              "[{\"hello\": 1, [1, 2]: SOME(TRUE)}, NONE]")
        (list NIL "[]") (list empty-map "{}") (list NONE "NONE")
        (list failed "ERR(ERROR(DIVIDE-BY-ZERO))")
        (list (host-list (list failed)) "[ERR(ERROR(DIVIDE-BY-ZERO))]")
        (list (host-list (list one (host-list (list two)) FALSE)) "[1, [2], FALSE]")))
(for ([entry (in-list generic-cases)])
  (check-render value-to-string (first entry) (second entry)))

(for ([entry (in-list
              (list (list list-to-string mixed "[1, TRUE, \"hello\"]" "list-to-string" "LIST")
                    (list map-to-string mixed-map "{\"hello\": 1, [1, 2]: SOME(TRUE)}" "map-to-string" "MAP")
                    (list option-to-string NONE "NONE" "option-to-string" "OPTION")
                    (list result-to-string failed "ERR(ERROR(DIVIDE-BY-ZERO))" "result-to-string" "RESULT")))])
  (check-render (first entry) (second entry) (third entry))
  (check-equal? (error-value->string (lazy-apply (first entry) TRUE))
                (format "~a(arg1 expected ~a got BOOL)" (fourth entry) (fifth entry)))
  (check-equal? (error-value->string (lazy-apply (first entry) invalid-nat-error))
                (format "INVALID-NAT\n  -> ~a(arg1 expected ~a)" (fourth entry) (fifth entry))))

;; NONE and unknown well-formed tags must not inspect their unused payloads.
(check-render value-to-string
              (apply2 raw-make-object option-type
                      (apply2 raw-pair raw-false (delay (error 'unused-none)))) "NONE")
(for ([n (in-list '(3 12 42))])
  (define tag (for/fold ([tag church-zero]) ([i (in-range n)])
                (lazy-apply church-succ tag)))
  (check-render value-to-string
                (apply2 raw-make-object tag (delay (error 'unused-unknown)))
                (format "<UNPRINTABLE-TYPE:~a>" n)))

;; Alternating containers exercise the same recursive engine at every level.
(define-values (deep expected-deep)
  (for/fold ([value one] [text "1"]) ([depth (in-range 24)])
    (values (lazy-apply raw-make-some
                        (lazy-apply raw-make-ok (host-list (list value))))
            (string-append "SOME(OK([" text "]))"))))
(check-render value-to-string deep expected-deep)

;; Map order is precisely its stored entry order; reversing the entries
;; changes the display without ever using the Map's equality function.
(check-render value-to-string
              (apply2 raw-make-object map-type
                      (apply2 raw-pair (delay (error 'unused-equality))
                              (lazy-apply raw-reverse entries)))
              "{[1, 2]: SOME(TRUE), \"hello\": 1}")
