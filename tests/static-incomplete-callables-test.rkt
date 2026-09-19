#lang racket/base

;; Bounded regression driver adopted from the independent inference hunt.
;; These programs are expanded and checked only, including divergent recursion.
(require rackunit racket/list "../runner/static/frontend.rkt" "../runner/source-file.rkt"
         "../runner/static/analysis.rkt" "../runner/static/inference.rkt"
         "../runner/static/proof.rkt")
(define (analyze text)
  (analyze-view (prepare-source (validated-source 'incomplete.attl text 2 0 17) #:analysis? #t)))

(test-case "unproved callable results retain independent input contradictions"
  (for ([text '("(rec bad n = (if (is-zero n) (head NIL) (bad TRUE)))"
                "(rec bad n = (let ignored = (head NIL) (if (is-zero n) 0 (bad TRUE))))"
                "(rec bad n = (let ignored = (some (lambda (x) x)) (if (is-zero n) 0 (bad TRUE))))"
                "(rec bad = (lambda (n) (let ignored = (head NIL) (if (is-zero n) 0 (bad TRUE)))))"
                "(rec bad = (let ignored = (head NIL) (lambda (n) (if (is-zero n) 0 (bad TRUE)))))"
                "((lambda (x) (let ignored = (head NIL) (add x 1))) \"bad\")"
                "(filter (lambda (x) (let ignored = (head NIL) (string-empty? x))) (list 1))"
                "(map head (list 1))"
                "(def first = head) (map first (list TRUE))"
                "(def f x y = (let ignored = (head NIL) (add x y))) (f 1 \"bad\")"
                "(let f = (lambda (x) (let ignored = (head NIL) (add x 1))) (f TRUE))"
                "(def capture g = (let f = (lambda (x) (let gap = (head NIL) (g x))) (let a = (f 1) (f TRUE))))"
                "((lambda (f) (f 1)) head)"
                "((if (some (lambda (x) x)) 1) \"s\")"
                "(def bad f = (add (f (unwrap-ok (make-ok 1))) f))"
                "(def bad f = (add f (f (unwrap-ok (make-ok 1)))))"
                "((lambda (f) (f (unwrap-ok (make-ok 1)))) 7)"
                "(def invoke f = (f (unwrap-ok (make-ok 1)))) (def alias = invoke) (alias 7)"
                "(def bad_capture f = (let invoke = (lambda (u) (f (unwrap-ok (make-ok 1)))) (add (invoke UNIT) f)))"
                "(rec bad f = (add (f (unwrap-ok (make-ok 1))) (bad 1)))")])
    (define result (analyze text))
    (define evidence (analysis-proof result))
    (check-eq? (proof-status evidence) 'conflict text)
    (check-not-false (memq 'TYPE_CONFLICT (map problem-code (proof-problems evidence))) text)
    (check-not-false
     (ormap (lambda (problem) (memq (problem-code problem)
                                  '(UNREPRESENTED_ERROR_ALTERNATIVE UNSUPPORTED_DATA_DOMAIN)))
            (proof-problems evidence)) text)
    (for ([entry (in-list (analysis-definitions result))])
      (check-false (definition-result-signature entry) text))))

(test-case "complete and independently conflicting bodies keep their verdicts"
  (for ([text '("(rec bad n = (if (is-zero n) 0 (bad TRUE)))"
                "((lambda (x) (let ignored = 1 (add x 1))) \"bad\")"
                "(rec bad n = (if (is-zero n) (add 1 \"bad\") (bad TRUE)))")])
    (check-eq? (proof-status (analysis-proof (analyze text))) 'conflict text)))

(test-case "input evidence never establishes unknown results or fabricates result conflicts"
  (for ([text '("(filter (lambda (x) (unwrap-ok (div 1 1))) NIL)"
                "(filter head (list NIL))"
                "(error-to-string (unwrap-ok (div 1 0)))"
                "((if TRUE (head NIL) (lambda (x) (add x 1))) \"s\")"
                "(def choose = (if TRUE (head NIL))) (choose 1) (choose \"s\")"
                "(def f x = (head NIL)) ((f 1) TRUE)"
                "((lambda (x) (head NIL)) 1)"
                "(let f = (lambda (x) (head x)) (let a = (f (list 1)) (f (list TRUE))))"
                "(rec bad x = (some bad))"
                "((lambda (f) f) head)"
                "(((lambda (f) f) head) TRUE)"
                "((lambda (x) (let y = (some x) (x 1))) (lambda (x) x))"
                "(def invoke f = (f (unwrap-ok (make-ok 1))))"
                "((head NIL) 1)"
                "(add 1 (unwrap-ok (make-ok \"text\")))"
                "(def data_only f = (let held = (some f) (f (unwrap-ok (make-ok 1)))))")])
    (define result (analyze text))
    (check-eq? (proof-status (analysis-proof result)) 'unproved text)
    (for ([entry (in-list (analysis-definitions result))])
      (check-false (definition-result-signature entry) text))
    (for ([item (in-list (analysis-expressions result))])
      (check-false (judgment-type item) text)))
  ;; A data-restricted callable stays an unsupported-domain gap, never a conflict.
  (define restricted
    (analyze "(def data_only f = (let held = (some f) (f (unwrap-ok (make-ok 1)))))"))
  (check-not-false
   (memq 'UNSUPPORTED_DATA_DOMAIN (map problem-code (proof-problems (analysis-proof restricted))))))
