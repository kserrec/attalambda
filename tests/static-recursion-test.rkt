#lang racket/base
(require rackunit racket/list "../runner/static/frontend.rkt" "../runner/source-file.rkt"
         "../lang/static-data.rkt" "../runner/static/analysis.rkt" "../runner/static/inference.rkt"
         "../runner/static/proof.rkt" "../runner/static/type-display.rkt")
(define (analyze text)
  (analyze-view (prepare-source (validated-source 'recursion.attl text 2 0 17) #:analysis? #t)))
(define (signature entry) (and (definition-result-signature entry) (scheme->string (definition-result-signature entry))))

(test-case "ordinary factorial and summation infer without executing fixed-point encodings"
  (define result
    (analyze "(def double x = (add x x))
              (rec factorial n = (if (is-zero n) 1 (mult n (factorial (sub n 1)))))
              (rec sum n = (if (is-zero n) 0 (add n (sum (sub n 1)))))
              (factorial (double 3)) (sum 10)"))
  (check-eq? (proof-status (analysis-proof result)) 'established)
  (check-equal? (map signature (analysis-definitions result)) '("Rat -> Rat" "Rat -> Rat" "Rat -> Rat"))
  (check-true (andmap (lambda (item) (eq? (proof-status (judgment-proof item)) 'established))
                      (hash-values (analysis-nodes result)))))

(test-case "finite constraints can establish diverging functions and recursive values"
  ;; Check-only fixtures: none is evaluated or demanded.
  (for ([row '(("(rec loop x = (loop x))" "forall a b. a -> b")
               ("(rec loop = loop)" "forall a. a")
               ("(rec number = (add 1 number))" "Rat"))])
    (define result (analyze (car row)))
    (check-eq? (proof-status (analysis-proof result)) 'established (car row))
    (check-equal? (signature (car (analysis-definitions result))) (cadr row))
    (check-true (andmap (lambda (item) (eq? (proof-status (judgment-proof item)) 'established))
                        (hash-values (analysis-nodes result))))))

(test-case "recursive assumptions stay monomorphic and failed assumptions are not counted"
  (define result
    (analyze "(rec bad n = (if (is-zero n) 0 (bad TRUE))) (def double x = (add x x))"))
  (check-eq? (proof-status (analysis-proof result)) 'conflict)
  (define bad (car (analysis-definitions result)))
  (check-false (signature bad))
  (check-equal? (signature (cadr (analysis-definitions result))) "Rat -> Rat")
  (check-not-false (memq 'TYPE_CONFLICT (map problem-code (proof-problems (definition-result-proof bad)))))
  (define id (source-binding-id (definition-result-binding bad)))
  (define (self-refs node)
    (append (if (and (eq? (source-node-kind node) 'reference) (= (source-node-data node) id))
                (list (source-node-id node)) '())
            (append-map self-refs (source-node-children node))))
  (for ([key (in-list (self-refs (source-binding-value (definition-result-binding bad))))])
    (check-eq? (proof-status (judgment-proof (hash-ref (analysis-nodes result) key))) 'unproved)))

(test-case "recursive types and external gaps remain distinct from successful self assumptions"
  (for ([text '("(rec grow = (lambda (x) grow))" "(def self-apply x = (x x))")])
    (define result (analyze text))
    (check-eq? (proof-status (analysis-proof result)) 'unproved text)
    (check-not-false (memq 'RECURSIVE_TYPE_REQUIRED (map problem-code (proof-problems (analysis-proof result)))))
    (check-false (signature (car (analysis-definitions result)))))
  (define external
    (analyze "(def extract = unwrap-ok) (rec recurse n = (if (is-zero n) (extract (div 1 0)) (recurse (sub n 1))))"))
  (check-eq? (proof-status (analysis-proof external)) 'unproved)
  (check-false (signature (cadr (analysis-definitions external))))
  (check-not-false (member 0 (proof-dependencies (definition-result-proof (cadr (analysis-definitions external)))))))
