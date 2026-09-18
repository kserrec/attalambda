#lang racket/base
;; CHECK-ONLY source fixtures. C05 deliberately diverges under ordinary execution.
(provide pilot-fixtures)
;; ID, expected proof verdict, primary reasons required, complete source body.
(define pilot-fixtures
  '((C01 established () "(def identity x = x) (identity 1) (identity \"s\")")
    (C02 established () "(let id = (lambda (x) x) (if (id TRUE) (id 1) 0))")
    (C03 conflict (TYPE_CONFLICT) "((lambda (id) (if (id TRUE) (id 1) 0)) (lambda (x) x))")
    (C04 conflict (TYPE_CONFLICT) "(def bad_capture g = (let f = (lambda (x) (g x)) (if (f 0) (f TRUE) FALSE)))")
    (C05-function established () "(rec loop x = (loop x))")
    (C05-value established () "(rec loop = loop)")
    (C06 conflict (TYPE_CONFLICT) "(rec bad n = (if (is-zero n) 0 (bad TRUE)))")
    (C07 conflict (TYPE_CONFLICT) "(def choose = if) (choose TRUE 1 \"s\")")
    (C09 established () "(def choose = if) ((choose TRUE (lambda (x) (add x 1)) (lambda (x) (sub x 1))) 2)")
    (C11 unproved (UNREPRESENTED_ERROR_ALTERNATIVE) "(error-to-string (unwrap-ok (div 1 0)))")
    (C13 unproved (UNREPRESENTED_ERROR_ALTERNATIVE) "(def extract = unwrap-ok)")
    (C14 unproved (UNREPRESENTED_ERROR_ALTERNATIVE) "(def wrapped x = (lambda (ignored) (unwrap-ok (div x 1))))")
    (C16 conflict (TYPE_CONFLICT) "(def double x = (add x x)) (double \"s\")")
    (usefulness established () "(def identity x = x) (def apply f x = (f x)) (def compose f g x = (f (g x))) (def plus-one = (add 1)) (identity identity) (apply (compose plus-one (mult 2)) 3)")
    (section-3.2-kernel established () "(def double x = (add x x)) (rec factorial n = (if (is-zero n) 1 (mult n (factorial (sub n 1))))) (factorial (double 3))")
    (guarded-unwrap unproved (UNREPRESENTED_ERROR_ALTERNATIVE) "(def safe-looking x = (let result = (div 10 x) (if (is-ok result) (unwrap-ok result) 0)))")
    (raw-self-application unproved (RECURSIVE_TYPE_REQUIRED) "(def self-apply x = (x x)) (def double x = (add x x))")
    (seed-C12 conflict (UNREPRESENTED_ERROR_ALTERNATIVE TYPE_CONFLICT) "(add (unwrap-ok (div 1 0)) \"bad\")")))
