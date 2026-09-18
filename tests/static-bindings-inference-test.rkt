#lang racket/base
(require rackunit racket/list "../runner/static/frontend.rkt" "../runner/source-file.rkt"
         "../lang/static-data.rkt" "../runner/static/analysis.rkt" "../runner/static/inference.rkt"
         "../runner/static/proof.rkt" "../runner/static/type-display.rkt")
(define (prepare text) (prepare-source (validated-source 'bindings.attl text 2 0 17) #:analysis? #t))
(define (analyze text) (analyze-view (prepare text)))
(define (status text) (proof-status (analysis-proof (analyze text))))

(test-case "definitions generalize and instantiate independently in real dependency order"
  (define result
    (analyze "(def later x = (identity x)) (def identity x = x) (later 1) (identity \"s\") (identity identity)"))
  (check-eq? (proof-status (analysis-proof result)) 'established)
  (check-equal? (map (lambda (entry) (source-binding-name (definition-result-binding entry)))
                    (analysis-definitions result)) '(later identity))
  (check-equal? (map (lambda (entry) (scheme->string (definition-result-signature entry)))
                    (analysis-definitions result)) '("forall a. a -> a" "forall a. a -> a"))
  (check-eq? (status "(def apply f x = (f x)) (def compose f g x = (f (g x))) (apply (compose (add 1) (sub 3)) 2)") 'established)
  (check-eq? (status "(def choose = if) (choose TRUE 1 \"s\")") 'conflict)
  (check-eq? (status "(def choose = if) ((choose TRUE (lambda (x) (add x 1)) (lambda (x) (sub x 1))) 2)") 'established))

(test-case "source let generalizes but lambda parameters and captured variables do not"
  (check-eq? (status "(let id = (lambda (x) x) (if (id TRUE) (id 1) 0))") 'established)
  (check-eq? (status "((lambda (id) (if (id TRUE) (id 1) 0)) (lambda (x) x))") 'conflict)
  (check-eq? (status "(def bad_capture g = (let f = (lambda (x) (g x)) (if (f 0) (f TRUE) FALSE)))") 'conflict)
  (check-eq? (status "(let ((x 1) (y x) (x \"s\")) x)") 'established)
  (check-eq? (status "(let () 1)") 'established)
  (check-eq? (status "((lambda (x x) x) 1 \"s\")") 'established)
  (check-eq? (status "(def add x = x) (add \"s\")") 'established))

(test-case "bad uses preserve upstream declarations; incomplete inputs publish no signature"
  (define result (analyze "(def double x = (add x x)) (double \"s\")"))
  (check-eq? (proof-status (analysis-proof result)) 'conflict)
  (define double (car (analysis-definitions result)))
  (check-eq? (proof-status (definition-result-proof double)) 'established)
  (check-equal? (scheme->string (definition-result-signature double)) "Rat -> Rat")
  (define partial (analyze "(def extract = unwrap-ok) (extract (div 1 0))"))
  (check-eq? (proof-status (analysis-proof partial)) 'unproved)
  (check-false (definition-result-signature (car (analysis-definitions partial))))
  (check-eq? (status "(let extract = unwrap-ok (error-to-string (extract (div 1 0))))") 'unproved))

(test-case "source and dependency metadata errors cannot become smaller successful analyses"
  (for ([text '("missing" "(def x = x)" "(def x = y) (def y = x)")])
    (check-true (source-problem? (prepare text))))
  (define view (prepare "(def later x = (early x)) (def early x = x)"))
  (define changed (struct-copy source-binding (car (source-view-bindings view)) [dependencies '()]))
  (check-exn #rx"incomplete source dependency metadata"
             (lambda () (analyze-view (struct-copy source-view view [bindings (cons changed (cdr (source-view-bindings view)))])))))
