#lang racket/base
(require rackunit racket/list "helpers/static-pilot.rkt"
         "../runner/static/frontend.rkt" "../runner/source-file.rkt" "../lang/static-data.rkt"
         "../runner/static/analysis.rkt" "../runner/static/inference.rkt"
         "../runner/static/proof.rkt" "../runner/static/type-display.rkt")
(define (analyze text)
  (analyze-view (prepare-source (validated-source 'pilot.attl text 2 0 17) #:analysis? #t)))
(define (status text) (proof-status (analysis-proof (analyze text))))

(test-case "fixed seed pilot expectations match the real frontend and kernel"
  (for ([fixture (in-list pilot-fixtures)])
    (define result (analyze (list-ref fixture 3)))
    (define state (analysis-proof result))
    (check-eq? (proof-status state) (cadr fixture) (symbol->string (car fixture)))
    (for ([code (in-list (caddr fixture))])
      (check-not-false (memq code (map problem-code (proof-problems state))) (symbol->string (car fixture))))))

(test-case "gaps follow aliases, nested closures, higher-order use and partial application"
  (for ([text '("(def extract = unwrap-ok) (def alias = extract) (def wrapped x = (alias x)) (def double x = (add x x))"
                "(def extract = unwrap-ok) (def captured x = (lambda (ignored) (extract (div x 1))))"
                "(def apply f x = (f x)) (apply unwrap-ok (div 1 0))"
                "((unwrap-ok (div 1 0)) 1)"
                "(let unused = (lambda (x) (x x)) 1)"
                "(def choose = (if TRUE (unwrap-ok (div 1 0)))) (if TRUE (choose 1) (choose \"s\"))")])
    (check-eq? (status text) 'unproved text))
  (define chain
    (analyze "(def extract = unwrap-ok) (def alias = extract) (def wrapped x = (alias x)) (def double x = (add x x))"))
  (define definitions (analysis-definitions chain))
  (check-equal? (map (lambda (entry) (proof-status (definition-result-proof entry))) definitions)
                '(unproved unproved unproved established))
  (check-equal? (proof-dependencies (definition-result-proof (cadr definitions))) '(0))
  (check-equal? (proof-dependencies (definition-result-proof (caddr definitions))) '(1))
  (check-equal? (scheme->string (definition-result-signature (list-ref definitions 3))) "Rat -> Rat")
  (check-eq? (status "(def pending = (add (unwrap-ok (div 1 0)))) (pending \"bad\")") 'conflict)
  ;; Known branch equations involving a captured parameter stay monomorphic,
  ;; even though the earlier condition is unproved.
  (check-eq? (status "(lambda (x) (let choose = (if (unwrap-ok (div 1 0)) x) (if TRUE (choose 1) (choose \"s\"))))") 'conflict))

(test-case "component isolation and repeated files leave established declarations immutable"
  (define identity-source (list-ref (car pilot-fixtures) 3))
  (define first (analyze identity-source))
  (check-eq? (status "(def choose = if) (choose TRUE 1 \"s\")") 'conflict)
  (check-equal? (analyze identity-source) first)
  (define mixed (analyze "(def broken x = (add x \"s\")) (def identity x = x) (identity 1) (identity \"s\")"))
  (check-equal? (scheme->string (definition-result-signature (cadr (analysis-definitions mixed)))) "forall a. a -> a")
  (check-true (andmap (lambda (item) (eq? (proof-status (judgment-proof item)) 'established))
                      (analysis-expressions mixed)))
  (define partial "(def gap x = (x x))")
  (check-eq? (status partial) 'unproved)
  (check-eq? (status (string-append partial " (add 1 \"bad\")")) 'conflict)
  (check-eq? (status "(def identity x = x) (def unused x = (x x)) (identity 1)") 'unproved))

(test-case "reordering independent definitions and renaming binders preserves verdict and counts"
  (define left (analyze "(def identity x = x) (def double y = (add y y)) (identity 1)"))
  (define right (analyze "(def double renamed = (add renamed renamed)) (def identity other = other) (identity 1)"))
  (check-eq? (proof-status (analysis-proof left)) (proof-status (analysis-proof right)))
  (check-equal? (hash-count (analysis-nodes left)) (hash-count (analysis-nodes right)))
  (check-equal? (length (analysis-definitions left)) (length (analysis-definitions right))))
