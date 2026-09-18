#lang racket/base
(require rackunit racket/list "../runner/static/frontend.rkt" "../runner/source-file.rkt"
         "../lang/static-data.rkt" "../runner/static/analysis.rkt" "../runner/static/inference.rkt"
         "../runner/static/proof.rkt" "../runner/static/type-display.rkt")
(define (view text) (prepare-source (validated-source 'sugar.attl text 2 0 17) #:analysis? #t))
(define (analyze text) (analyze-view (view text)))
(define (expression-type text)
  (define result (analyze text))
  (check-eq? (proof-status (analysis-proof result)) 'established text)
  (type->string (judgment-type (car (analysis-expressions result)))))

(test-case "currying and sequential let preserve the supported source abstraction rules"
  (for ([pair '(("(lambda (x y) (add x y))" "(lambda (x) (lambda (y) (add x y)))")
                ("(add 1 2)" "((add 1) 2)")
                ("(let ((id (lambda (x) x)) (one (id 1))) (if (id TRUE) one 0))"
                 "(let id = (lambda (x) x) (let one = (id 1) (if (id TRUE) one 0)))"))])
    (check-equal? (expression-type (car pair)) (expression-type (cadr pair)))))

(test-case "cond and first-class if use the same branch equations, including hygienic generated if"
  (check-equal? (expression-type "(cond (FALSE 1) (TRUE 2) (else 3))")
                (expression-type "(if FALSE 1 (if TRUE 2 3))"))
  (check-equal? (expression-type "(def if x = x) (cond (TRUE 1) (else 2))") "Rat")
  (for ([text '("(cond (TRUE 1) (else \"s\"))" "(if TRUE 1 \"s\")"
                "(def choose = if) (choose TRUE 1 \"s\")"
                "(if FALSE (add 1 \"unused\") 0)"
                "(cond (FALSE (add 1 \"unused\")) (else 0))"
                "(if TRUE (div 1 0) 1)")])
    (check-eq? (proof-status (analysis-proof (analyze text))) 'conflict text))
  (define both (analysis-proof (analyze "(cond (FALSE (unwrap-ok (div 1 0))) (else (add 1 \"bad\")))")))
  (check-eq? (proof-status both) 'conflict)
  (check-not-false (memq 'UNREPRESENTED_ERROR_ALTERNATIVE (map problem-code (proof-problems both)))))

(define (normalized node)
  (if (eq? (source-node-kind node) 'group)
      (normalized (car (source-node-children node)))
      (list (source-node-kind node) (source-node-data node) (map normalized (source-node-children node)))))
(test-case "list syntax and actual cons normalization have the same homogeneous rules"
  (define sugar (view "(list 1 2)"))
  (define explicit (view "(cons 1 (cons 2 NIL))"))
  (check-equal? (normalized (car (source-view-expressions sugar)))
                (normalized (car (source-view-expressions explicit))))
  (check-equal? (length (source-view-registry sugar)) 3)
  (for ([source (list sugar explicit)])
    (define result (analyze-view source))
    (check-eq? (proof-status (analysis-proof result)) 'established)
    (check-equal? (type->string (judgment-type (car (analysis-expressions result)))) "List(Rat)"))
  (for ([text '("(list 1 \"s\")" "(cons 1 (cons \"s\" NIL))"
                "(def push = cons) (push 1 (push \"s\" NIL))")])
    (check-eq? (proof-status (analysis-proof (analyze text))) 'conflict text)))
