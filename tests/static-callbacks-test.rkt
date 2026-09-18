#lang racket/base
(require rackunit racket/list "../runner/static/frontend.rkt" "../runner/source-file.rkt"
         "../runner/static/analysis.rkt" "../runner/static/inference.rkt"
         "../runner/static/proof.rkt" "../runner/static/type-display.rkt")
(define (analyze text)
  (analyze-view (prepare-source (validated-source 'callbacks.attl text 2 0 17) #:analysis? #t)))
(define (state text) (proof-status (analysis-proof (analyze text))))

(test-case "List callbacks preserve elements, changed outputs and accumulator-first order"
  (for ([row '(("(map is-zero (list 0 1))" "List(Bool)")
               ("(filter is-zero (list 0 1))" "List(Rat)")
               ("(reduce (lambda (acc x) (cons x acc)) NIL (list 1 2))" "List(Rat)")
               ("(find is-zero (list 0 1))" "Option(Rat)")
               ("(find-index string-empty? (list \"a\"))" "Option(Rat)")
               ("(contains? char-eq #\\A (list #\\B))" "Bool")
               ("(take-while is-zero (list 0 1))" "List(Rat)")
               ("(drop-while string-empty? (list \"a\"))" "List(String)"))])
    (define result (analyze (car row)))
    (check-eq? (proof-status (analysis-proof result)) 'established (car row))
    (check-equal? (type->string (judgment-type (car (analysis-expressions result)))) (cadr row))))

(test-case "callbacks must satisfy their contracts even on empty containers"
  (for ([text '("(filter (lambda (x) 1) NIL)" "(def keep = filter) (keep (lambda (x) 1) NIL)"
                "(any? (lambda (x) 1) NIL)" "(all? (lambda (x) 1) NIL)"
                "(reduce (lambda (x acc) (string-append acc (if (is-zero x) \"a\" \"b\"))) \"\" (list 1))"
                "(map (add 1) (list TRUE))" "(map 1 NIL)"
                "(contains? eq TRUE NIL)" "(find (lambda (x) 1) NIL)")])
    (check-eq? (state text) 'conflict text))
  (for ([text '("(map (lambda (x) (lambda (y) y)) NIL)"
                "(filter (lambda (x) (unwrap-ok (div 1 1))) NIL)"
                "(reduce (lambda (acc x) (head NIL)) 0 NIL)")])
    (check-eq? (state text) 'unproved text)))

(test-case "Map schemes enforce comparator and key/value relationships"
  (for ([row '(("(map-lookup (map-set (make-map string-eq) \"a\" 1) \"b\")" "Option(Rat)")
               ("(map-size (make-map eq))" "Rat")
               ("(map-contains? (make-map eq) 1)" "Bool")
               ("(map-remove (map-set (make-map eq) 1 \"a\") 2)" "Map(Rat, String)"))])
    (define result (analyze (car row)))
    (check-eq? (proof-status (analysis-proof result)) 'established (car row))
    (check-equal? (type->string (judgment-type (car (analysis-expressions result)))) (cadr row)))
  (check-eq? (state "(def empty = (make-map eq)) (map-set empty 1 TRUE) (map-set empty 2 \"s\")") 'established)
  (for ([text '("(make-map (lambda (x y) 1))"
                "(make-map (lambda (x y) (if (is-zero x) (string-empty? y) TRUE)))"
                "(map-set (make-map eq) \"s\" 1)"
                "(def m = (map-set (make-map eq) 1 \"s\")) (map-set m 2 TRUE)")])
    (check-eq? (state text) 'conflict text))
  (for ([text '("(make-map (lambda (x y) (unwrap-ok (div 1 1))))"
                "(def empty = (make-map eq)) (map-set empty 1 (lambda (x) x))"
                "(def loose = (make-map (lambda (x y) TRUE))) (map-set loose (lambda (x) x) 1)"
                "(map-empty? (make-map (lambda (x y) (head NIL))))")])
    (check-eq? (state text) 'unproved text)))
