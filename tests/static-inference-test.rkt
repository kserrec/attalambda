#lang racket/base
(require rackunit racket/list "../runner/static/frontend.rkt" "../runner/source-file.rkt"
         "../lang/static-data.rkt" "../runner/static/inference.rkt" "../runner/static/proof.rkt"
         "../runner/static/type-display.rkt")
(define (infer text)
  (define view (prepare-source (validated-source 'infer.attl text 2 0 17) #:analysis? #t))
  (define root (if (pair? (source-view-bindings view))
                   (source-binding-value (car (source-view-bindings view)))
                   (car (source-view-expressions view))))
  (define-values (result nodes state) (infer-expression root))
  (values result nodes))
(define (codes result) (map problem-code (proof-problems (judgment-proof result))))

(test-case "real source literals, lambdas and curried applications infer elementary types"
  (for ([row '(("1" "Rat") ("\"s\"" "String") ("#\\A" "Char")
               ("(lambda (x) x)" "a -> a")
               ("(lambda (f x) (f x))" "(a -> b) -> a -> b")
               ("(lambda (f g x) (f (g x)))" "(a -> b) -> (c -> a) -> c -> b")
               ("(def double x = (add x x))" "Rat -> Rat")
               ("(add 1)" "Rat -> Rat") ("(add 1 2)" "Rat")
               ("(div 1 0)" "Result(Rat)")
               ("((if TRUE (lambda (x) (add x 1)) (lambda (x) (sub x 1))) 2)" "Rat")
               ("((lambda (choose) (choose TRUE 1 2)) if)" "Rat")
               ("((lambda (add) (add \"s\")) (lambda (x) x))" "String"))])
    (define-values (result nodes) (infer (car row)))
    (check-eq? (proof-status (judgment-proof result)) 'established (car row))
    (check-equal? (type->string (judgment-type result)) (cadr row) (car row))))

(test-case "known mismatches identify the actual argument, not generated code"
  (define-values (result nodes) (infer "(add 1 \"bad\")"))
  (check-equal? (codes result) '(TYPE_CONFLICT))
  (define item (car (proof-problems (judgment-proof result))))
  (check-equal? (problem-detail item) "add argument 2")
  (check-equal? (source-location-source (problem-location item)) "infer.attl")
  (check-equal? (source-location-line (problem-location item)) 2)
  (check-equal? (source-location-column (problem-location item)) 7)
  (check-equal? (type->string (problem-expected item)) "Rat")
  (check-equal? (type->string (problem-actual item)) "String")
  (check-equal? (hash-count nodes) 4)
  (check-equal? (count (lambda (item) (eq? (proof-status (judgment-proof item)) 'established))
                       (hash-values nodes)) 3)
  (for ([text '("(if TRUE 1 \"s\")" "((lambda (choose) (choose TRUE 1 \"s\")) if)"
                "(1 2)" "(add (div 1 2) 3)")])
    (define-values (bad ignored) (infer text))
    (check-not-false (memq 'TYPE_CONFLICT (codes bad)) text)))

(test-case "partial outputs never establish a value type or hide independent arguments"
  (for ([text '("unwrap-ok" "(error-to-string (unwrap-ok (div 1 0)))"
                "(lambda (x) (x x))" "(lambda (x) (lambda (ignored) (unwrap-ok (div x 1))))")])
    (define-values (result ignored) (infer text))
    (check-eq? (proof-status (judgment-proof result)) 'unproved text)
    (check-false (judgment-type result) text)
    (check-false (memq 'TYPE_CONFLICT (codes result)) text))
  (define-values (combined ignored) (infer "(add (unwrap-ok (div 1 0)) \"bad\")"))
  (check-eq? (proof-status (judgment-proof combined)) 'conflict)
  (check-not-false (memq 'TYPE_CONFLICT (codes combined)))
  (check-not-false (memq 'UNREPRESENTED_ERROR_ALTERNATIVE (codes combined)))
  ;; Exhausting if's inputs cannot turn a conditional result hint into a callable.
  (define-values (returned ignored-again)
    (infer "((if TRUE (unwrap-ok (div 1 0)) (lambda (x) (add x 1))) \"s\")"))
  (check-eq? (proof-status (judgment-proof returned)) 'unproved)
  (check-false (memq 'TYPE_CONFLICT (codes returned))))
