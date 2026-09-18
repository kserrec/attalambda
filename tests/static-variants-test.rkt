#lang racket/base
(require rackunit racket/list "../runner/static/frontend.rkt" "../runner/source-file.rkt"
         "../runner/static/analysis.rkt" "../runner/static/inference.rkt"
         "../runner/static/proof.rkt" "../runner/static/type-display.rkt")
(define (analyze text)
  (analyze-view (prepare-source (validated-source 'variants.attl text 2 0 17) #:analysis? #t)))
(define (state text) (proof-status (analysis-proof (analyze text))))

(test-case "Option and Result keep their one data parameter and Error's fixed identity"
  (for ([row '(("(some 1)" "Option(Rat)") ("(make-ok \"s\")" "Result(String)")
               ("(is-some NONE)" "Bool") ("(is-none (some 1))" "Bool")
               ("(is-err (div 1 0))" "Bool")
               ("(unwrap-err (div 1 0))" "Error")
               ("(unwrap-err (make-ok 1))" "Error")
               ("(error-to-string (unwrap-err (make-ok 1)))" "String")
               ("(option-case (some 1) (lambda (x) (add x 1)) 0)" "Rat")
               ("((option-case NONE (lambda (x) (lambda (y) (add x y))) (add 1)) 2)" "Rat")
               ("((lambda (e) 1) (unwrap-err (div 1 0)))" "Rat"))])
    (define result (analyze (car row)))
    (check-eq? (proof-status (analysis-proof result)) 'established (car row))
    (check-equal? (type->string (judgment-type (car (analysis-expressions result)))) (cadr row)))
  (check-eq? (state "(make-err (unwrap-err (div 1 0)))") 'established)
  (check-eq? (state "(def failure = make-err) (is-err (failure (unwrap-err (div 1 0))))") 'established))

(test-case "Error is neither an arbitrary Result payload nor an implicit Rat or function"
  (for ([text '("(make-err 1)" "(def failure = make-err) (failure \"s\")"
                "(add (unwrap-err (div 1 0)) 1)" "((unwrap-err (div 1 0)) 1)"
                "(option-case (some 1) (lambda (x) x) \"s\")"
                "(option-case (some 1) 0 (lambda (x) x))")])
    (check-eq? (state text) 'conflict text))
  (for ([text '("(make-ok (unwrap-err (div 1 0)))" "(some (unwrap-err (div 1 0)))"
                "(make-ok (lambda (x) x))"
                "(def pack x = (some (list x))) (pack (lambda (y) y))")])
    (define result (analyze text))
    (check-eq? (proof-status (analysis-proof result)) 'unproved text)
    (check-not-false (memq 'UNSUPPORTED_DATA_DOMAIN (map problem-code (proof-problems (analysis-proof result)))))))

(test-case "variant predicates do not prove unwrap success, even through aliases and higher-order uses"
  (for ([text '("(unwrap-ok (make-ok 1))"
                "(let r = (div 1 0) (if (is-ok r) (unwrap-ok r) 0))"
                "(def extract = unwrap-ok) (map extract (list (make-ok 1)))"
                "(error-to-string (unwrap-ok (make-ok 1)))"
                "((unwrap-ok (make-ok 1)) 2)")])
    (check-eq? (state text) 'unproved text)))
