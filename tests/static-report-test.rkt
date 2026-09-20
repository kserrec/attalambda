#lang racket/base
(require rackunit racket/list racket/string
         "../runner/static/frontend.rkt" "../runner/source-file.rkt"
         "../runner/static/analysis.rkt" "../runner/static/coverage.rkt"
         "../runner/static/report.rkt" "../runner/static/type-display.rkt" "../runner/static/types.rkt")
(define (report text [name "golden.attl"])
  (render-report
   (summarize-analysis
    (analyze-view (prepare-source (validated-source name text 2 0 17) #:analysis? #t))) name))

(test-case "complete and empty reports have exact stable counts and types"
  (define source "(def identity x = x)\n(def double x = (add x x))\n(double 3)")
  (define expected
    (string-append
     "Static type check: FULL PASS\nScope: golden.attl; all source definitions and expressions\n"
     "System: hm\n"
     "Definitions: 2/2 fully checked (100.0%)\nExpressions: 8/8 fully checked (100.0%)\n"
     "Unproved regions: 0\nType conflicts: 0\n\nInferred definitions:\n"
     "  identity : forall a. a -> a\n  double : Rat -> Rat\n"))
  (check-equal? (report source) expected)
  (check-regexp-match #rx"Static type check: FAIL" (report "(add 1 \"bad\")"))
  (check-equal? (report source) expected)
  (check-equal?
   (report "")
   (string-append
    "Static type check: FULL PASS\nScope: golden.attl; all source definitions and expressions\n"
    "System: hm\n"
    "Definitions: 0/0 fully checked (n/a)\nExpressions: 0/0 fully checked (n/a)\n"
    "Unproved regions: 0\nType conflicts: 0\n"
    "This source contains no definitions or expressions; the pass is vacuous.\n"))
  (check-equal? (types->strings (list (type-variable 7) (type-variable 9))) '("a" "b")))

(test-case "diagnostics preserve actual CRLF Unicode tab positions and enclosing lambdas"
  (define positioned (report "; café\r\n(def broken x =\r\n\t(add x \"bad\"))\r\n" "locations.attl"))
  (check-regexp-match #rx"locations.attl:4:15 \\[TYPE_CONFLICT\\] in broken" positioned)
  (check-regexp-match #rx"add argument 2 expects Rat; this expression has type String." positioned)
  (define nested (report "(def outer x = (lambda (y) (add y \"bad\")))" "nested.attl"))
  (check-regexp-match #rx"nested.attl:2:34 \\[TYPE_CONFLICT\\] in outer" nested)
  (check-regexp-match #rx"anonymous lambda at nested.attl:2:15 \\(source span 26 characters\\)" nested)
  (check-regexp-match #rx"Static type check: FULL PASS"
                      (report "(def add x y = x) (add 1 \"s\")"))
  (check-regexp-match #rx"Static type check: FULL PASS"
                      (report "(def λ x = x) (λ 1) (λ \"s\")")))

(test-case "source-controlled names and paths cannot emit terminal or invisible formatting controls"
  (define output
    (report "(def |name\u001b\u202e| x = (add x \"bad\"))" "path\u001b\u2028.attl"))
  (check-regexp-match #rx"name\\\\u\\{1b\\}\\\\u\\{202e\\}" output)
  (check-regexp-match #rx"path\\\\u\\{1b\\}\\\\u\\{2028\\}.attl" output)
  (for ([character (in-string output)])
    (unless (char=? character #\newline)
      (check-false (memq (char-general-category character) '(cc cf zl zp)))))
  ;; Names included in argument diagnostics receive the same escaping.
  (define call (report "(def |f\u001b| x = (add x 1)) (|f\u001b| \"bad\")"))
  (check-false (string-contains? call "\u001b"))
  (check-regexp-match #rx"TYPE_CONFLICT" call))

(test-case "partial declarations show reasons and bounded dependency paths, never success hints"
  (define output
    (report "(def gap = unwrap-ok) (def alias = gap) (def caller x = (alias x)) (caller (make-ok 1)) (def good = 1)"))
  (check-regexp-match #rx"Static type check: PARTIAL" output)
  (check-regexp-match #rx"Unproved regions: 1" output)
  (check-regexp-match #rx"  good : Rat" output)
  (check-false (regexp-match? #rx"(gap|alias|caller) :" output))
  (check-regexp-match #rx"caller -> alias -> gap: \\[UNREPRESENTED_ERROR_ALTERNATIVE\\]" output)
  (check-regexp-match #rx"Dependent top-level expressions:" output)
  (define self (report "(def self-apply x = (x x)) (def double x = (add x x))"))
  (check-regexp-match #rx"Definitions: 1/2 fully checked \\(50.0%\\)" self)
  (check-regexp-match #rx"RECURSIVE_TYPE_REQUIRED\\] in self-apply" self)
  (check-regexp-match #rx"ordinary AttaLambda is unchanged" self))

(test-case "shared aliases produce deterministic polynomial-size reports"
  (define source
    (string-append "(def gap = head)\n"
                   (string-join
                    (for/list ([i (in-range 1 36)])
                      (define previous (if (= i 1) "gap" (format "f~a" (sub1 i))))
                      (format "(def f~a = (if TRUE ~a ~a))" i previous previous)) "\n")))
  (define first (report source))
  (check-true (< (string-length first) 15000))
  (check-equal? (length (regexp-match* #rx"WrongResultVariant|An empty List returns Error" first)) 1)
  (check-equal? (report source) first))
