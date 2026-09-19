#lang racket/base
(require rackunit racket/file racket/runtime-path racket/string
         "helpers/fresh-language.rkt" "helpers/static-acceptance.rkt")
(define-runtime-path launcher "../runner/attalambda.rkt")
(define-runtime-path driver "helpers/static-cli-driver.rkt")
(define environment (environment-variables-copy (current-environment-variables)))
(define directory (make-temporary-file "attalambda-static-cli-~a" 'directory))
(define source (build-path directory "source with spaces.attl"))
(define (write-bytes-source bytes)
  (call-with-output-file source #:exists 'truncate #:mode 'binary
    (lambda (out) (write-bytes bytes out))))
(define (run arguments [program launcher])
  (run-command environment racket-executable (cons (path->string program) arguments) 30
               #:current-directory directory))
(define (verify result status)
  (check-false (command-result-timed-out? result) (result-diagnostic result))
  (check-equal? (command-result-status result) status (result-diagnostic result)))
(dynamic-wind
 void
 (lambda ()
   (test-case "real --check command implements the fixed semantic status matrix"
     (for ([fixture (in-list semantic-fixtures)])
       (write-source source (string-append "#lang attalambda\n" (list-ref fixture 3) "\n"))
       (define result (run (list "--check" (path->string source))))
       (define expected (case (cadr fixture) [(established) 0] [(conflict) 1] [else 2]))
       (verify result expected)
       (check-regexp-match (case expected [(0) #rx#"^Static type check: FULL PASS\n"]
                            [(1) #rx#"^Static type check: FAIL\n"] [else #rx#"^Static type check: PARTIAL\n"])
                           (command-result-stdout result))
       (check-equal? (command-result-stderr result) #"")
       (for ([code (in-list (caddr fixture))])
         (check-true (regexp-match? (byte-regexp (string->bytes/utf-8 (symbol->string code)))
                                    (command-result-stdout result))))))

   (test-case "a callable requirement survives an unproved argument in either use order"
     (for ([row '(("(def bad f = (add (f (unwrap-ok (make-ok 1))) f))" 1 "FAIL")
                  ("(def bad f = (add f (f (unwrap-ok (make-ok 1)))))" 1 "FAIL")
                  ("(def invoke f = (f (unwrap-ok (make-ok 1))))" 2 "PARTIAL")
                  ("(def identity x = x) (identity 1) (identity TRUE)" 0 "FULL PASS"))])
       (write-source source (string-append "#lang attalambda\n" (car row) "\n"))
       (define result (run (list "--check" (path->string source))))
       (verify result (cadr row))
       (define report (command-result-stdout result))
       (check-regexp-match (byte-regexp (string->bytes/utf-8 (string-append "^Static type check: " (caddr row) "\n")))
                           report)
       (check-equal? (command-result-stderr result) #"")
       (check-regexp-match #rx#"UNREPRESENTED_ERROR_ALTERNATIVE|identity : forall a[.] a -> a" report)
       (when (= (cadr row) 1)
         (check-regexp-match #rx#"\\.attl:2:[0-9]+ \\[TYPE_CONFLICT\\] in bad\n" report))
       (check-false (regexp-match? #rx#"\n  (bad|invoke) :" report)))
     ;; Checking reports the conflict without running the file, and an
     ;; independent good definition beside the bad one keeps its signature.
     (write-source source (string-append "#lang attalambda\n(stdout \"CHECK-MUST-NOT-RUN\")\n"
                                         "(def good x = x)\n"
                                         "(def bad f = (add (f (unwrap-ok (make-ok 1))) f))\n"))
     (define result (run (list "--check" (path->string source))))
     (verify result 1)
     (define report (command-result-stdout result))
     (check-regexp-match #rx#"^Static type check: FAIL\n" report)
     (check-regexp-match #rx#"\n  good : forall a[.] a -> a\n" report)
     (check-false (regexp-match? #rx#"\n  bad :" report))
     (check-false (regexp-match? #rx#"CHECK-MUST-NOT-RUN" report))
     (check-equal? (command-result-stderr result) #""))

   (test-case "exact argument shape rejects missing extra duplicate and incompatible arguments"
     (for ([arguments '(("--check") ("--check" "one.attl" "two.attl")
                        ("--check" "--check") ("--check" "--help")
                        ("--check" "--version") ("--check" "--repl")
                        ("--check" "--no-history") ("--repl" "--check" "one.attl")
                        ("--check" "one.attl" "--no-history") ("one.attl" "--check")
                        ("--check" "-file.attl"))])
       (define result (run arguments))
       (verify result 64)
       (check-equal? (command-result-stdout result) #"")
       (check-regexp-match #rx#"expected attalambda" (command-result-stderr result)))
     (check-regexp-match #rx#"attalambda --check FILE.attl" (command-result-stdout (run '("--help")))))

   (test-case "invalid whole source and path policy failures do not produce coverage reports"
     (for ([body '(#"bad header" #"#lang attalambda\n(stdout \"must-not-run\") missing"
                   #"#lang attalambda\n(stdout \"must-not-run\") ("
                   #"#lang attalambda\n#reader \"arbitrary.rkt\" 1"
                   #"#lang attalambda\n(def f x = (f x))"
                   #"#lang attalambda\n(def f x = (g x)) (def g x = (f x))"
                   #"#lang attalambda\n1.2" #"#lang attalambda\n\377")])
       (write-bytes-source body)
       (define result (run (list "--check" (path->string source))))
       (verify result 65)
       (check-equal? (command-result-stdout result) #"")
       (check-false (regexp-match? #rx#"must-not-run|Static type check:" (command-result-stderr result))))
     (write-source source "#lang attalambda\n1")
     (define link (build-path directory "link.attl"))
     (make-file-or-directory-link source link)
     (define unreadable (build-path directory "unreadable.attl"))
     (write-source unreadable "#lang attalambda\n1")
     (file-or-directory-permissions unreadable #o000)
     ;; Dotenv spellings are only passed to preflight; no such file is created.
     (for ([path (list (path->string link) (path->string unreadable) "missing.attl" ".env.attl" ".ENV.local/source.attl")])
       (define result (run (list "--check" path)))
       (verify result 66)
       (check-equal? (command-result-stdout result) #"")))

   (test-case "private faults reach the actual launcher and never masquerade as source errors or success"
     (write-source source "#lang attalambda\n1")
     (for ([mode '("internal" "syntax" "filesystem" "pending-catalog" "missing-id" "missing-state" "write-failure" "flush-failure")])
       (define result (run (list mode (path->string source)) driver))
       (verify result 70)
       (check-false (regexp-match? #rx#"private|/runner/|/lang/|context:" (command-result-stderr result)))
       (check-regexp-match #rx#"unexpected static checking or report-delivery failure" (command-result-stderr result))
       (check-equal? (length (regexp-match* #rx#"Static type check:" (command-result-stdout result)))
                     (if (equal? mode "flush-failure") 1 0)))))
 (lambda () (delete-directory/files directory)))
