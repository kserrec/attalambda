#lang racket/base
(require rackunit racket/list "helpers/static-acceptance.rkt"
         "../runner/static/frontend.rkt" "../runner/source-file.rkt"
         "../runner/static/analysis.rkt" "../runner/static/inference.rkt"
         "../runner/static/proof.rkt" "../runner/static/type-display.rkt")
(define (analyze text)
  (analyze-view (prepare-source (validated-source 'combined.attl text 2 0 17) #:analysis? #t)))
(define (state text) (proof-status (analysis-proof (analyze text))))

(test-case "every semantic counterexample retains its fixed expectation with the complete catalog"
  (for ([fixture (in-list semantic-fixtures)])
    (define result (analyze (list-ref fixture 3)))
    (define proof (analysis-proof result))
    (check-eq? (proof-status proof) (cadr fixture) (symbol->string (car fixture)))
    (for ([code (in-list (caddr fixture))])
      (check-not-false (memq code (map problem-code (proof-problems proof))) (symbol->string (car fixture))))))

(test-case "a partial output cannot acquire an arrow or manufacture a downstream conflict from its hint"
  (for ([text '("((if TRUE (head NIL) (lambda (x) (add x 1))) \"s\")"
                "(def choose = (if TRUE (head NIL))) (choose 1) (choose \"s\")"
                "(def apply f x = (f x)) (apply (head NIL) 1)"
                "(def pick = head) ((pick NIL) 1)"
                "(def wrap x = (lambda (ignored) (head x)))"
                "(map (lambda (x) (unwrap-err (div 1 0))) NIL)")])
    (check-eq? (state text) 'unproved text)))

(test-case "earlier gaps preserve independent known input conflicts through partial applications"
  (for ([text '("(write-file (head NIL) TRUE)" "(map (head NIL) TRUE)"
                "(if (head NIL) 1 \"s\")"
                "(let pending = (add (head NIL)) (pending \"bad\"))"
                "(def send = (write-file (head NIL))) (send \"bad\")"
                "(cons (head NIL) TRUE)")])
    (define proof (analysis-proof (analyze text)))
    (check-eq? (proof-status proof) 'conflict text)
    ;; Aliased gaps may be reached through dependency edges; the originating
    ;; definition remains in whole-file analysis-proof and retains its reason.
    (check-not-false (memq 'UNREPRESENTED_ERROR_ALTERNATIVE (map problem-code (proof-problems proof))))))

(test-case "ordinary user lambdas do not inherit library Error-absorbing continuation behavior"
  (for ([row '(("((lambda (e) 1) (unwrap-err (div 1 0)))" "Rat")
               ("(((lambda (e) (lambda (ignored) e)) (unwrap-err (div 1 0))) TRUE)" "Error")
               ("(option-case NONE (lambda (x) (unwrap-err (div 1 0))) (unwrap-err (make-ok 1)))" "Error"))])
    (define result (analyze (car row)))
    (check-eq? (proof-status (analysis-proof result)) 'established (car row))
    (check-equal? (type->string (judgment-type (car (analysis-expressions result)))) (cadr row)))
  (check-eq? (state "(add (unwrap-err (div 1 0)) 1)") 'conflict)
  (check-eq? (state "((lambda (e) (e 1)) (unwrap-err (div 1 0)))") 'conflict))
