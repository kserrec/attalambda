#lang racket/base
(require rackunit racket/list "../runner/static/frontend.rkt" "../runner/source-file.rkt"
         "../runner/static/analysis.rkt" "../runner/static/inference.rkt"
         "../runner/static/proof.rkt" "../runner/static/type-display.rkt")
(define (analyze text)
  (analyze-view (prepare-source (validated-source 'rendering.attl text 2 0 17) #:analysis? #t)))
(define (state text) (proof-status (analysis-proof (analyze text))))

(test-case "specific and restricted generic renderers establish String for canonical shapes"
  (for ([text '("(rat-to-string 1/2)" "(bool-to-string TRUE)" "(unit-to-string UNIT)"
                "(char-to-string #\\A)" "(string-to-string \"s\")"
                "(list-to-string (string-to-bytes \"s\"))"
                "(option-to-string (some (list 1)))"
                "(result-to-string (make-err (unwrap-err (div 1 0))))"
                "(map-to-string (map-set (make-map eq) 1 TRUE))"
                "(value-to-string (list (some (make-ok 1))))"
                "(error-to-string (unwrap-err (div 1 0)))")])
    (define result (analyze text))
    (check-eq? (proof-status (analysis-proof result)) 'established text)
    (check-equal? (type->string (judgment-type (car (analysis-expressions result)))) "String"))
  (check-eq? (state "(map byte-to-string (string-to-bytes \"s\"))") 'established)
  (check-eq? (state "(rat-to-string TRUE)") 'conflict)
  (check-eq? (state "(list-to-string \"s\")") 'conflict))

(test-case "generic rendering cannot accept direct or hidden raw functions or unresolved overloads"
  ;; Check only: never execute unspecified raw-function rendering.
  (for ([text '("(value-to-string (lambda (x) x))"
                "(value-to-string (some (lambda (x) x)))"
                "(list-to-string (list (lambda (x) x)))"
                "(def render = value-to-string) (render (lambda (x) x))"
                "(value-to-string (unwrap-err (div 1 0)))"
                "(value-to-string (unwrap-ok (make-ok 1)))")])
    (check-eq? (state text) 'unproved text)))

(test-case "count and nesting operations preserve known inputs without claiming success-only returns"
  (for ([text '("(take 1 (list 1 2))" "(drop 0 NIL)" "(nth 0 (list 1))"
                "(repeat 2 TRUE)" "(range -1 2)" "(flatten (list (list 1)))"
                "(def flatten-alias = flatten) (flatten-alias NIL)"
                "(error-to-string (nth 0 NIL))")])
    (check-eq? (state text) 'unproved text))
  (for ([text '("(take \"s\" NIL)" "(drop 1 TRUE)" "(nth 0 \"s\")"
                "(range 1 \"s\")" "(flatten 1)" "(add (nth 0 NIL) \"bad\")")])
    (check-eq? (state text) 'conflict text)))
