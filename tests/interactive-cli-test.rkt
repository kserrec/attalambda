#lang racket/base

(require rackunit racket/file racket/runtime-path "helpers/fresh-language.rkt")

(define-runtime-path runner "../runner/attalambda.rkt")
(define environment (environment-variables-copy (current-environment-variables)))
(define (run arguments [input #""] #:directory [directory #f])
  (run-command environment racket-executable
               (cons (path->string runner) arguments) 30 #:input input
               #:current-directory directory))

(test-case "explicit REPL accepts both flag orders and empty transcript EOF"
  (for ([arguments '(("--repl") ("--repl" "--no-history") ("--no-history" "--repl"))])
    (check-command-success (run arguments) #"")))

(test-case "default nonterminal entry requires explicit transcript selection"
  (for ([arguments '(() ("--no-history"))])
    (define result (run arguments #"(stdout \"not selected\")\n"))
    (check-false (command-result-timed-out? result))
    (check-equal? (command-result-status result) 64)
    (check-equal? (command-result-stdout result) #"")
    (check-equal? (command-result-stderr result)
                  #"AttaLambda: a terminal is required; use attalambda --repl for redirected source\n")))

(test-case "unknown duplicates and mixed command/file options remain misuse"
  (for ([arguments '(("--repl" "--repl") ("--no-history" "--no-history")
                     ("--repl" "--no-history" "--no-history")
                     ("--unknown") ("--repl" "file.attl") ("file.attl" "--repl")
                     ("--no-history" "file.attl") ("--help" "--repl")
                     ("--version" "--no-history"))])
    (define result (run arguments))
    (check-false (command-result-timed-out? result))
    (check-equal? (command-result-status result) 64 (result-diagnostic result))
    (check-equal? (command-result-stdout result) #"")
    (check-regexp-match #rx#"expected attalambda" (command-result-stderr result))))

(test-case "transcript selection executes the plain checked source loop without terminal UI"
  (check-command-success (run '("--repl" "--no-history")
                               #"(add 1/2 1/3)\n(def double x = (mult x 2))\n(double 21)\n")
                          #"=> 5/6\n=> 42\n"))

(test-case "plain commands list lazy metadata, load standalone definitions, reset and quit"
  (define directory (make-temporary-file "attalambda-cli-load-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (write-source (build-path directory "with spaces.attl")
                   "#lang attalambda\n(stdout \"load-marker\\n\")\n(def base = 6)\n(def loaded n = (add base n))\n(add 2 3)\n")
     (define result
       (run '("--repl" "--no-history")
            #":help\n(def z = (read-line UNIT)) (def a = 41)\n:names\n:load \"with spaces.attl\"\n(loaded 1)\n:names\n:reset\n:names\n(add 2 3)\n:quit\n(stdout \"never\")\n"
            #:directory directory))
     (check-false (command-result-timed-out? result))
     (check-equal? (command-result-status result) 0 (result-diagnostic result))
     (check-equal? (command-result-stdout result) #"load-marker\n=> 7\n=> 5\n")
     (define stderr (command-result-stderr result))
     (check-regexp-match #rx#"Untagged functions" stderr)
     (check-regexp-match #rx#"User definitions:\n  a\n  z\nLoaded source file.\n" stderr)
     (check-regexp-match #rx#"User definitions:\n  a\n  base\n  loaded\n  z\nSession reset.\nNo user definitions.\n" stderr)
     (check-false (regexp-match? #rx#"atta>|UNSAFE|never" stderr)))
   (lambda () (delete-directory/files directory))))

(test-case "command and load failures recover without exposing partial definitions"
  (define result
    (run '("--repl")
         #":help extra\n:unknown\n:load 9\n:load \"absent-cli-fixture.attl\"\n:names\n(add 2 3)\n:quit\n"))
  (check-false (command-result-timed-out? result))
  (check-equal? (command-result-status result) 1)
  (check-equal? (command-result-stdout result) #"=> 5\n")
  (for ([message '(#rx#"this command takes no arguments" #rx#"unknown command; use :help"
                   #rx#"expected :load followed by exactly one quoted path string"
                   #rx#"absent-cli-fixture.attl: source file was not found"
                   #rx#"No user definitions.")])
    (check-regexp-match message (command-result-stderr result))))

(test-case "name listings preserve full names and escape terminal controls without forcing values"
  (define long-name (make-string 350 #\a))
  (define input
    (string->bytes/utf-8
     (format "(def ~a = (read-line UNIT)) (def |control\u001bname| = (read-line UNIT))\n:names\n:quit\n"
             long-name)))
  (define result (run '("--repl") input))
  (check-false (command-result-timed-out? result))
  (check-equal? (command-result-status result) 0)
  (check-equal? (command-result-stdout result) #"")
  (check-regexp-match (byte-regexp (string->bytes/utf-8 long-name)) (command-result-stderr result))
  (check-regexp-match #rx#"control\\\\u\\{1b\\}name" (command-result-stderr result))
  (check-false (regexp-match? #rx#"\33" (command-result-stderr result))))

(test-case "echo off never probes raw functions and survives reset while effects stay live"
  (define result
    (run '("--repl" "--no-history")
         #":echo off\n(def f ignored = (stdout \"called\\n\"))\nf\n(f UNIT)\n:reset\n(def g ignored = (stdout \"after-reset\\n\"))\ng\n(g UNIT)\n:echo on\n(add 1/2 1/3)\n(stdout \"last\\n\")\n:quit\n"))
  (check-false (command-result-timed-out? result))
  (check-equal? (command-result-status result) 0 (result-diagnostic result))
  (check-equal? (command-result-stdout result)
                #"called\nafter-reset\n=> 5/6\nlast\n=> OK(UNIT)\n")
  (check-equal? (command-result-stderr result)
                #"Automatic echo: off\nSession reset.\nAutomatic echo: on\n"))

(test-case "invalid echo commands preserve the prior setting"
  (define result
    (run '("--repl")
         #":echo off\n:echo yes\n:echo on extra\n:echo\n(def f ignored = (stdout \"unexpected\"))\nf\n:echo on\nTRUE\n:quit\n"))
  (check-false (command-result-timed-out? result))
  (check-equal? (command-result-status result) 1)
  (check-equal? (command-result-stdout result) #"=> TRUE\n")
  (check-equal? (length (regexp-match* #rx#"expected :echo on or :echo off"
                                      (command-result-stderr result))) 3))

(test-case "transcript program fragments stay immediate with legible automatic result boundaries"
  (define result
    (run '("--repl")
         #"(stdout \"abc\\r\") (add 1 2)\n(stdout \"line\\n\")\n:echo off\n(stdout \"fragment\")\n:help\n:echo on\nTRUE\nTRUE\n:echo off\n(stdout \"final\")\n:quit\n"))
  (check-false (command-result-timed-out? result))
  (check-equal? (command-result-status result) 0 (result-diagnostic result))
  (check-equal? (command-result-stdout result)
                #"abc\r\n=> OK(UNIT)\n=> 3\nline\n=> OK(UNIT)\nfragment\n=> TRUE\n=> TRUE\nfinal")
  (check-false (regexp-match? #rx#"atta>|\33" (command-result-stderr result))))

(test-case "transcript failures stay sticky across recovery and reset; explicit exit wins"
  (for ([example '((#"unknown-name\n(add 2 3)\n" 1)
                    (#")\n:reset\n(add 2 3)\n:quit\n" 1)
                    (#":load \"absent-status.attl\"\n(add 2 3)\n:quit\n" 1)
                    (#"unknown-name\n(exit 0)\n(stdout \"never\")\n" 0)
                    (#"unknown-name\n(exit 1)\n(stdout \"never\")\n" 1)
                    (#"(add 2\n" 65)
                    (#"unknown-name\n(add 2\n" 65))])
    (define result (run '("--repl") (car example)))
    (check-false (command-result-timed-out? result))
    (check-equal? (command-result-status result) (cadr example) (result-diagnostic result))
    (check-false (regexp-match? #rx#"never|atta>|\33" (command-result-stdout result)))
    (check-false (regexp-match? #rx#"/runtime/|/runner/|/lang/|#<procedure" (command-result-stderr result)))))

(test-case "ordinary Error and Err results leave the transcript successful"
  (define result (run '("--repl") #"(head NIL) (div 1 0)\n:reset\n:quit\n"))
  (check-false (command-result-timed-out? result))
  (check-equal? (command-result-status result) 0 (result-diagnostic result))
  (check-equal? (command-result-stdout result)
                #"=> ERROR(EMPTY-LIST\n  -> head(result))\n=> ERR(ERROR(DIVIDE-BY-ZERO))\n")
  (check-equal? (command-result-stderr result) #"Session reset.\n"))
