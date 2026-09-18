#lang racket/base
;; CHECK ONLY. Includes divergent recursion and unspecified dynamic domains.
(require "static-pilot.rkt")
(provide semantic-fixtures)
(define semantic-fixtures
  (append
   pilot-fixtures
   '((C08 conflict (TYPE_CONFLICT) "(def put = cons) (put 1 (list \"s\"))")
     (C10 conflict (TYPE_CONFLICT) "(filter (lambda (x) 1) NIL)")
     (C12 conflict (UNREPRESENTED_ERROR_ALTERNATIVE TYPE_CONFLICT) "(add (head NIL) \"bad\")")
     (C15 unproved (UNSUPPORTED_DATA_DOMAIN) "(def pack x = (some (list x))) (pack (lambda (y) y))")
     (C17 unproved (UNREPRESENTED_ERROR_ALTERNATIVE) "(make-map (lambda (x y) (unwrap-ok (div 1 1))))")
     (C18 established () "(unwrap-err (div 1 0))")
     (section-3.2-complete established () "(def double x = (add x x)) (rec factorial n = (if (is-zero n) 1 (mult n (factorial (sub n 1))))) (stdout (rat-to-string (factorial (double 3))))"))))
