#lang racket/base
(require rackunit racket/list racket/string
         "../runner/static/frontend.rkt" "../runner/source-file.rkt"
         "../runner/static/analysis.rkt" "../runner/static/proof.rkt")
(define (analyze text)
  (analyze-view (prepare-source (validated-source 'bounded.attl text 2 0 17) #:analysis? #t)))

(test-case "bounded deep and broad source retains exact counts and fresh repeatable state"
  (define fixtures
    (list
     (list (for/fold ([body "1"]) ([i (in-range 60)]) (format "(lambda (x~a) ~a)" i body))
           'established 61 0)
     (list (for/fold ([body "1"]) ([i (in-range 120)]) (format "((lambda (x) x) ~a)" body))
           'established 361 0)
     (list (string-join (for/list ([i (in-range 80)]) (format "(def f~a x = (add x 1))" i)) "\n")
           'established 320 80)
     (list (string-append "(def gap = unwrap-ok)\n"
                          (string-join (for/list ([i (in-range 1 101)])
                                         (format "(def alias~a = ~a)" i
                                                 (if (= i 1) "gap" (format "alias~a" (sub1 i))))) "\n"))
           'unproved 101 101)))
  (for ([row (in-list fixtures)])
    (define first (analyze (car row)))
    (check-eq? (proof-status (analysis-proof first)) (cadr row))
    (check-equal? (hash-count (analysis-nodes first)) (caddr row))
    (check-equal? (length (analysis-definitions first)) (cadddr row))
    (check-eq? (proof-status (analysis-proof (analyze "(add 1 \"bad\")"))) 'conflict)
    (check-equal? (analyze (car row)) first)))
