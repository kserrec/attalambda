#lang racket/base
(require rackunit racket/list "../runner/static/frontend.rkt" "../runner/source-file.rkt"
         "../lang/static-data.rkt" "../runner/static/analysis.rkt" "../runner/static/inference.rkt"
         "../runner/static/proof.rkt" "../runner/static/coverage.rkt" "../runner/static/report.rkt"
         "../runner/static/type-display.rkt" "../runner/static/systems.rkt")
(define (analyze text system)
  (analyze-view (prepare-source (validated-source 'simple.attl text 2 0 17) #:analysis? #t) #:system system))
(define (status text system) (proof-status (analysis-proof (analyze text system))))
(define (codes result) (map problem-code (proof-problems (analysis-proof result))))
(define (lines result) (map (lambda (p) (source-location-line (problem-location p))) (proof-problems (analysis-proof result))))
(define (signature result index)
  (define item (list-ref (analysis-definitions result) index))
  (and (definition-result-signature item) (scheme->string (definition-result-signature item))))
(define (established-definition? result index)
  (eq? (proof-status (definition-result-proof (list-ref (analysis-definitions result) index))) 'established))
(define e3 "(def identity x = x)\n(identity 1)\n(identity \"text\")")

(test-case "monomorphic definitions share one solution across the file and conflict where a second use disagrees"
  (define simple (analyze e3 simple-system))
  (check-eq? (proof-status (analysis-proof simple)) 'conflict)
  (check-equal? (codes simple) '(TYPE_CONFLICT))
  (check-equal? (lines simple) '(4))
  (check-true (established-definition? simple 0))
  (check-equal? (signature simple 0) "Rat -> Rat")
  (define summary (summarize-analysis simple))
  (check-eq? (check-summary-verdict summary) 'fail)
  (check-equal? (check-summary-definitions-checked summary) 1)
  (check-equal? (check-summary-definitions-total summary) 1)
  (define report (render-report summary "simple.attl" simple-system))
  (check-regexp-match #rx"^Static type check: FAIL\nScope: simple.attl; all source definitions and expressions\nSystem: simple\n" report)
  (check-regexp-match #rx"\n  identity : Rat -> Rat\n" report)
  (check-regexp-match #rx"simple.attl:4:[0-9]+ \\[TYPE_CONFLICT\\]" report)
  ;; The same file under hm generalizes identity and passes.
  (define hm (analyze e3 hm-system))
  (check-eq? (proof-status (analysis-proof hm)) 'established)
  (check-equal? (signature hm 0) "forall a. a -> a")
  (check-regexp-match #rx"\nSystem: hm\n" (render-report (summarize-analysis hm) "simple.attl" hm-system)))

(test-case "signatures reflect the final state and unsolved variables stay letters without forall"
  (check-equal? (signature (analyze "(def identity x = x)" simple-system) 0) "a -> a")
  (check-equal? (signature (analyze "(def identity x = x) (identity 1)" simple-system) 0) "Rat -> Rat")
  (check-equal? (signature (analyze "(def identity x = x) (def use = (identity TRUE))" simple-system) 0) "Bool -> Bool")
  (check-equal? (signature (analyze "(def identity x = x) (def use = (identity TRUE))" simple-system) 1) "Bool")
  ;; A failed equation commits nothing: a later agreeing use is still established.
  (define recovered (analyze "(def identity x = x)\n(identity 1)\n(identity \"text\")\n(identity 2)" simple-system))
  (check-equal? (map (lambda (item) (proof-status (judgment-proof item))) (analysis-expressions recovered))
                '(established conflict established))
  (check-equal? (signature recovered 0) "Rat -> Rat"))

(test-case "definitions are solved before top-level expressions, so the later-checked use is the one flagged"
  (define ordered (analyze "(def a x = x)\n(a 1)\n(def b = (a \"s\"))" simple-system))
  (check-eq? (proof-status (analysis-proof ordered)) 'conflict)
  (check-equal? (codes ordered) '(TYPE_CONFLICT))
  (check-equal? (lines ordered) '(3))
  (check-equal? (signature ordered 0) "String -> String")
  (check-equal? (signature ordered 1) "String")
  (check-eq? (status "(def a x = x)\n(a 1)\n(def b = (a \"s\"))" hm-system) 'established))

(test-case "source let is monomorphic under simple while built-ins stay polymorphic under both systems"
  (define shared-let "(let id = (lambda (x) x) (add (id 1) (string-length (id \"s\"))))")
  (check-eq? (status shared-let simple-system) 'conflict)
  (check-eq? (status shared-let hm-system) 'established)
  (for ([text '("(def a = (cons 1 NIL)) (def b = (cons \"s\" NIL))"
                "(len (cons 1 NIL)) (len (cons \"s\" NIL))"
                "(def first = (if TRUE 1 2)) (def second = (if FALSE \"a\" \"b\"))")])
    (check-eq? (status text simple-system) 'established text)
    (check-eq? (status text hm-system) 'established text))
  (define lists (analyze "(def a = (cons 1 NIL)) (def b = (cons \"s\" NIL))" simple-system))
  (check-equal? (signature lists 0) "List(Rat)")
  (check-equal? (signature lists 1) "List(String)"))

(test-case "recursion, partial contracts, data restrictions, and independent definitions behave as under hm"
  (define e1 "(rec sum xs = (list-case xs (lambda (h t) (add h (sum t))) 0))\n(sum (list 1 2 3))")
  (for ([system (list simple-system hm-system)])
    (define sum (analyze e1 system))
    (check-eq? (proof-status (analysis-proof sum)) 'established)
    (check-equal? (signature sum 0) "List(Rat) -> Rat")
    (define gap (analyze "(rec sum xs = (if (is-nil xs) 0 (add (head xs) (sum (tail xs)))))" system))
    (check-eq? (proof-status (analysis-proof gap)) 'unproved)
    (check-equal? (remove-duplicates (codes gap)) '(UNREPRESENTED_ERROR_ALTERNATIVE))
    (check-false (signature gap 0))
    (define raw (analyze "(def singleton x = (cons x NIL)) (singleton (lambda (y) y))" system))
    (check-eq? (proof-status (analysis-proof raw)) 'unproved)
    (check-not-false (memq 'UNSUPPORTED_DATA_DOMAIN (codes raw))))
  (define mixed (analyze (string-append e3 "\n(def double x = (add x x))\n(double 3)") simple-system))
  (check-eq? (proof-status (analysis-proof mixed)) 'conflict)
  (check-true (established-definition? mixed 0))
  (check-true (established-definition? mixed 1))
  (check-equal? (signature mixed 1) "Rat -> Rat")
  (check-eq? (check-summary-verdict (summarize-analysis mixed)) 'fail))
