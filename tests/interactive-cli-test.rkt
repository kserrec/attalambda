#lang racket/base

(require rackunit racket/file racket/runtime-path "helpers/fresh-language.rkt")

(define-runtime-path runner "../runner/attalambda.rkt")
(define-runtime-path api-document "../docs/API.md")
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

(test-case "documented snapshot transcript executes verbatim"
  (define matched
    (regexp-match #px"(?s:<!-- interactive-snapshot-example -->\n```text\n(.*?)\n```\n<!-- /interactive-snapshot-example -->)"
                  (file->string api-document)))
  (check-not-false matched)
  (check-command-success
   (run '("--repl" "--no-history")
        (string->bytes/utf-8 (string-append (cadr matched) "\n")))
   #"=> 2\n=> 11\n"))

(test-case "plain commands list lazy metadata, load standalone definitions, reset and quit"
  (define directory (make-temporary-file "attalambda-cli-load-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (write-source (build-path directory "with spaces.attl")
                   "#lang attalambda\n(stdout \"load-marker\\n\")\n(def base = 6)\n(def loaded n = (add base n))\n(add 2 3)\n")
     (define result
       (run '("--repl" "--no-history")
            #":help\n(def z = (read-line UNIT)) (def a = 41)\n:names\n:load \"with spaces.attl\"\n(loaded 1)\n:load \"with spaces.attl\"\n:names\n:reset\n:names\n(add 2 3)\n:quit\n(stdout \"never\")\n"
            #:directory directory))
     (check-false (command-result-timed-out? result))
     (check-equal? (command-result-status result) 0 (result-diagnostic result))
     (check-equal? (command-result-stdout result) #"load-marker\n=> 7\nload-marker\n=> 5\n")
     (define stderr (command-result-stderr result))
     (check-regexp-match #rx#"Untagged functions" stderr)
     (check-regexp-match #rx#"User definitions:\n  a\n  z\nLoaded source file.\n" stderr)
     (check-equal? (length (regexp-match* #rx#"Loaded source file." stderr)) 2)
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

(test-case "real REPL entries retain partial applications, recursive functions and binding snapshots"
  (check-command-success
   (run '("--repl")
        #"(def x = 1)\n(def f ignored = x)\n(def shifted = (add x))\n(def x = 2)\n(f UNIT) x (shifted 4)\n(rec sum n = (if (eq n 0) 0 (add n (sum (sub n 1)))))\n(sum 3)\n:quit\n")
   #"=> 1\n=> 2\n=> 5\n=> 6\n"))

(test-case "saved input survives name listing and repeated demand while fresh reads remain distinct"
  (define saved
    (run '("--repl")
         #"(def answer = (read-line UNIT))\n:names\nanswer\nKyle\nanswer\n:quit\n"))
  (check-false (command-result-timed-out? saved))
  (check-equal? (command-result-status saved) 0 (result-diagnostic saved))
  (check-equal? (command-result-stdout saved)
                #"=> OK(SOME(\"Kyle\"))\n=> OK(SOME(\"Kyle\"))\n")
  (check-equal? (command-result-stderr saved) #"User definitions:\n  answer\n")
  (check-command-success
   (run '("--repl") #"(read-line UNIT)\nfirst\n(read-line UNIT)\nsecond\n:quit\n")
   #"=> OK(SOME(\"first\"))\n=> OK(SOME(\"second\"))\n"))

(test-case "recovery retains old names, reset removes them, and the transcript failure remains sticky"
  (for ([probe-reset? '(#f #t)])
    (define result
      (run '("--repl")
           (if probe-reset?
               #"(def keep = 7)\nmissing_name\nkeep\n:reset\nkeep\n(add 1 2)\n:quit\n"
               #"(def keep = 7)\nmissing_name\nkeep\n:reset\n(add 1 2)\n:quit\n")))
    (check-false (command-result-timed-out? result))
    (check-equal? (command-result-status result) 1 (result-diagnostic result))
    (check-equal? (command-result-stdout result) #"=> 7\n=> 3\n")
    (check-regexp-match #rx#"missing_name" (command-result-stderr result))
    (check-regexp-match #rx#"Session reset." (command-result-stderr result))
    (when probe-reset?
      (check-regexp-match #rx#"unknown AttaLambda name: keep" (command-result-stderr result)))))

(test-case "load expansion failure suppresses earlier file effects and publishes no names"
  (define directory (make-temporary-file "attalambda-cli-rejected-load-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (write-source (build-path directory "rejected.attl")
                   "#lang attalambda\n(stdout \"must-not-run\")\n(def partial = 9)\nmissing-in-file\n")
     (define result
       (run '("--repl") #":load \"rejected.attl\"\n:names\n(add 2 3)\n:quit\n"
            #:directory directory))
     (check-false (command-result-timed-out? result))
     (check-equal? (command-result-status result) 1 (result-diagnostic result))
     (check-equal? (command-result-stdout result) #"=> 5\n")
     (check-regexp-match #rx#"missing-in-file" (command-result-stderr result))
     (check-regexp-match #rx#"No user definitions." (command-result-stderr result)))
   (lambda () (delete-directory/files directory))))
