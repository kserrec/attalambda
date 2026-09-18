#lang racket/base
(require rackunit racket/list racket/string "helpers/static-acceptance.rkt"
         "../runner/static/frontend.rkt" "../runner/source-file.rkt" "../lang/static-data.rkt"
         "../runner/static/analysis.rkt" "../runner/static/inference.rkt"
         "../runner/static/proof.rkt" "../runner/static/types.rkt" "../runner/static/coverage.rkt")
(define (analyze text)
  (analyze-view (prepare-source (validated-source 'coverage.attl text 2 0 17) #:analysis? #t)))
(define (summary text) (summarize-analysis (analyze text)))

(test-case "coverage counts original source, including complete bodies and failed top-level calls"
  (for ([row '(("" full 0 0 0 0)
               ("1" full 0 0 1 1)
               ("(add 1 2)" full 0 0 4 4)
               ("(add 1 \"bad\")" fail 0 0 3 4)
               ("(list 1 2)" full 0 0 3 3)
               ("(let x = 1 x)" full 0 0 3 3)
               ("(lambda (x) x)" full 0 0 2 2)
               ("(lambda (x y) x)" full 0 0 2 2)
               ("(lambda (x) (lambda (y) x))" full 0 0 3 3)
               ("(def identity x = x)" full 1 1 1 1)
               ("(def data = 1) (def alias = data)" full 2 2 2 2)
               ("(def double x = (add x x)) (double \"s\")" fail 1 1 6 7)
               ("(def gap = head) (def alias = gap) (def caller x = (alias x))" partial 0 3 1 5))])
    (define result (summary (car row)))
    (check-equal?
     (list (check-summary-verdict result) (check-summary-definitions-checked result)
           (check-summary-definitions-total result) (check-summary-expressions-checked result)
           (check-summary-expressions-total result))
     (cdr row) (car row))))

(test-case "all semantic outcomes survive final accounting and exact precedence"
  (for ([fixture (in-list semantic-fixtures)])
    (define result (summary (list-ref fixture 3)))
    (check-eq? (check-summary-verdict result)
               (case (cadr fixture) [(established) 'full] [(conflict) 'fail] [else 'partial])
               (symbol->string (car fixture))))
  (define both (summary "(add (head NIL) \"bad\")"))
  (check-eq? (check-summary-verdict both) 'fail)
  (check-not-false (memq 'TYPE_CONFLICT (map problem-code (check-summary-problems both))))
  (check-not-false (memq 'UNREPRESENTED_ERROR_ALTERNATIVE (map problem-code (check-summary-problems both))))
  (check-eq? (check-summary-verdict (summary "(def unused x = (lambda (y) (y y))) 1")) 'partial)
  (check-eq? (check-summary-verdict (summary "(if TRUE 1 (add 2 \"bad\"))")) 'fail))

(test-case "rounding never selects a full verdict and zero denominators are explicit"
  (check-equal? (coverage-percentage 0 0) "n/a")
  (check-equal? (coverage-percentage 3 4) "75.0%")
  (check-equal? (coverage-percentage 1 3) "33.3%")
  (check-exn exn:fail? (lambda () (coverage-percentage 2 1)))
  (define result (summary (string-append (string-join (make-list 5000 "1") "\n") "\n(head NIL)")))
  (check-equal? (check-summary-expressions-checked result) 5001)
  (check-equal? (check-summary-expressions-total result) 5003)
  (check-equal? (coverage-percentage 5001 5003) "100.0%")
  (check-eq? (check-summary-verdict result) 'partial))

(test-case "lost source accounting and unresolved or speculative states are analyzer failures"
  (define good (analyze "(def identity x = x) (identity 1)"))
  (define nodes (analysis-nodes good))
  (define id (car (sort (hash-keys nodes) <)))
  (define item (hash-ref nodes id))
  (define (bad value) (check-exn exn:fail? (lambda () (summarize-analysis value))))
  (bad (struct-copy analysis good [nodes (hash-remove nodes id)]))
  (bad (struct-copy analysis good [nodes (hash-set nodes 9999 item)]))
  (bad (struct-copy analysis good [definitions '()]))
  (bad (struct-copy analysis good [expressions '()]))
  (bad (struct-copy analysis good [nodes (hash-set nodes id (struct-copy judgment item [type #f]))]))
  (bad (struct-copy analysis good
         [nodes (hash-set nodes id (judgment (base-type 'Rat) (proof '() '(9999)) #f))]))
  (define incomplete (analyze "(def gap = head)"))
  (define binding (car (analysis-definitions incomplete)))
  (bad (struct-copy analysis incomplete
         [definitions (list (struct-copy definition-result binding [proof (proof '() '())]))]))
  (bad (struct-copy analysis incomplete
         [definitions (list (struct-copy definition-result binding
                              [proof (proof '() (list (source-binding-id (definition-result-binding binding))))]))])))

(test-case "one dependency path retains the primary reason without exponential path expansion"
  (define result
    (summary (string-append "(def gap = head)\n"
                            (string-join
                             (for/list ([i (in-range 1 45)])
                               (define previous (if (= i 1) "gap" (format "f~a" (sub1 i))))
                               (format "(def f~a = (if TRUE ~a ~a))" i previous previous)) "\n"))))
  (check-eq? (check-summary-verdict result) 'partial)
  (check-equal? (length (check-summary-problems result)) 1)
  (check-equal? (hash-count (check-summary-paths result)) 45)
  (check-equal? (apply max (map length (hash-values (check-summary-paths result)))) 45))
