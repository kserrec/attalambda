#lang racket/base
(require rackunit racket/list "../runner/static/frontend.rkt" "../runner/source-file.rkt"
         "../runner/static/analysis.rkt" "../runner/static/inference.rkt"
         "../runner/static/proof.rkt" "../runner/static/type-display.rkt")
(define (analyze text)
  (analyze-view (prepare-source (validated-source 'lists.attl text 2 0 17) #:analysis? #t)))
(define (state text) (proof-status (analysis-proof (analyze text))))

(test-case "safe List operations preserve homogeneous element and nesting types"
  (for ([row '(("(cons 1 NIL)" "List(Rat)") ("(list (list 1) (list 2))" "List(List(Rat))")
               ("(append (list \"a\") (reverse (list \"b\")))" "List(String)")
               ("(concat (list (list 1) (list 2)))" "List(Rat)")
               ("(zip (list 1) (list 2 3))" "List(List(Rat))")
               ("(len (list 1 2))" "Rat") ("(is-nil NIL)" "Bool")
               ("(make-string (list #\\A #\\B))" "String")
               ("(bytes-to-string NIL)" "String"))])
    (define result (analyze (car row)))
    (check-eq? (proof-status (analysis-proof result)) 'established (car row))
    (check-equal? (type->string (judgment-type (car (analysis-expressions result)))) (cadr row))))

(test-case "constructors and aliases retain nominal, homogeneous, and recursive data restrictions"
  (for ([text '("(list 1 \"s\")" "(cons 1 (cons TRUE NIL))"
                "(def push = cons) (push 1 (push \"s\" NIL))"
                "(append (list 1) (list TRUE))" "(zip (list 1) (list \"s\"))"
                "(len \"abc\")" "(make-string (list 1))" "(cons 1 2)"
                "(concat (list 1))")])
    (check-eq? (state text) 'conflict text))
  (for ([text '("(cons (lambda (x) x) NIL)"
                "(def singleton x = (cons x NIL)) (singleton (lambda (x) x))"
                "(def nested xs = (cons xs NIL)) (nested (list (lambda (x) x)))"
                "(def empty = NIL) (cons (lambda (x) x) empty)")])
    (define result (analyze text))
    (check-eq? (proof-status (analysis-proof result)) 'unproved text)
    (check-not-false (memq 'UNSUPPORTED_DATA_DOMAIN (map problem-code (proof-problems (analysis-proof result))))))
  (define singleton (analyze "(def singleton x = (cons x NIL))"))
  (check-equal? (scheme->string (definition-result-signature (car (analysis-definitions singleton))))
                "forall a:data. a -> List(a)"))

(test-case "empty-list Error alternatives cannot become verified values or arrows"
  (for ([text '("(head NIL)" "(tail NIL)" "(head (list 1))" "head"
                "(def first = head) (first (list 1))"
                "((head NIL) 1)" "(error-to-string (head NIL))")])
    (check-eq? (state text) 'unproved text))
  (define both (analysis-proof (analyze "(add (head NIL) \"bad\")")))
  (check-eq? (proof-status both) 'conflict)
  (check-not-false (memq 'UNREPRESENTED_ERROR_ALTERNATIVE (map problem-code (proof-problems both))))
  (check-eq? (state "(head 1)") 'conflict))

(test-case "list-case has a complete contract while head and tail keep their empty-list gap"
  (define single (analyze "(list-case (list 1) (lambda (h t) h) 0)"))
  (check-eq? (proof-status (analysis-proof single)) 'established)
  (check-equal? (type->string (judgment-type (car (analysis-expressions single)))) "Rat")
  (define sum (analyze "(rec sum xs = (list-case xs (lambda (h t) (add h (sum t))) 0))\n(sum (list 1 2 3))"))
  (check-eq? (proof-status (analysis-proof sum)) 'established)
  (check-equal? (scheme->string (definition-result-signature (car (analysis-definitions sum))))
                "List(Rat) -> Rat")
  (for ([text '("(list-case NIL (lambda (h t) \"s\") 0)" "(list-case 1 (lambda (h t) h) 0)")])
    (check-eq? (state text) 'conflict text))
  (define raw (analyze "(list-case (list (lambda (x) x)) (lambda (h t) h) 0)"))
  (check-eq? (proof-status (analysis-proof raw)) 'unproved)
  (check-not-false (memq 'UNSUPPORTED_DATA_DOMAIN (map problem-code (proof-problems (analysis-proof raw)))))
  (define gap (analysis-proof (analyze "(rec sum xs = (if (is-nil xs) 0 (add (head xs) (sum (tail xs)))))")))
  (check-eq? (proof-status gap) 'unproved)
  (check-equal? (count (lambda (code) (eq? code 'UNREPRESENTED_ERROR_ALTERNATIVE))
                       (map problem-code (proof-problems gap))) 2))
