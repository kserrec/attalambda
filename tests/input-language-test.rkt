#lang racket/base

(require rackunit
         racket/file
         racket/list
         racket/port
         racket/runtime-path
         "helpers/fresh-language.rkt")

(define-runtime-path project-root "..")
(define api-source (file->string (build-path project-root "docs" "API.md")))
(define example-match
  (regexp-match #px"(?s:<!-- terminal-input-example -->\n```racket\n(.*?)\n```\n<!-- /terminal-input-example -->)"
                api-source))
(unless example-match (error 'input-example "documented example was not found"))

;; All interaction is automated over pipes; deadlines and a custodian prevent
;; a broken read or prompt from leaving a child process behind.
(call-with-fresh-language-install
 project-root
 (lambda (installation)
   (define root (fresh-language-install-temporary-root installation))
   (define environment (fresh-language-install-environment installation))
   (define source (build-path root "input.attl"))
   (define runner (build-path root "package-source" "runner" "attalambda.rkt"))
   (define (run-input body input #:runner? [runner? #f] #:dialogue [dialogue '()])
     (write-source source body)
     (define owner (make-custodian))
     (dynamic-wind
       void
       (lambda ()
         (parameterize ([current-custodian owner]
                        [current-subprocess-custodian-mode 'kill]
                        [current-environment-variables environment])
           (define-values (process output to-child errors)
             (apply subprocess #f #f #f racket-executable
                    (if runner?
                        (list (path->string runner) (path->string source))
                        (list (path->string source)))))
           (define error-result (make-channel))
           (thread (lambda () (channel-put error-result (port->bytes errors))))
           (define prefix (open-output-bytes))
           (for ([round (in-list dialogue)])
             (define prompt (first round))
             (define observed
               (sync/timeout 20 (read-bytes-evt (bytes-length prompt) output)))
             (check-equal? observed prompt "prompt must arrive before input is sent")
             (unless (bytes? observed) (error 'input-dialogue "missing prompt"))
             (write-bytes observed prefix)
             (check-equal? (subprocess-status process) 'running)
             (write-bytes (second round) to-child)
             (flush-output to-child)
             ;; A partial line must not be returned before a separator/EOF.
             (check-false (sync/timeout 0.1 output) "read returned an incomplete line")
             (write-bytes #"\n" to-child)
             (flush-output to-child))
           (write-bytes input to-child)
           (close-output-port to-child)
           (define output-result (make-channel))
           (thread (lambda () (channel-put output-result (port->bytes output))))
           (define completed (sync/timeout 20 process))
           (unless completed (subprocess-kill process #t) (sync process))
           (define remaining (sync/timeout 5 output-result))
           (define diagnostics (sync/timeout 5 error-result))
           (command-result
            (and completed (subprocess-status process))
            (bytes-append (get-output-bytes prefix) (or remaining #""))
            (or diagnostics #"capture timed out")
            (not (and completed remaining diagnostics)))))
       (lambda () (custodian-shutdown-all owner))))

   (for ([runner? (in-list '(#f #t))])
     (check-command-success
      (run-input (second example-match) #"" #:runner? runner?
                 #:dialogue (list (list #"What is your name? " #"Ada")))
      #"What is your name? Hello, Ada.\n")
     (check-command-success
      (run-input (second example-match) #"\n" #:runner? runner?)
      #"What is your name? Hello, .\n")
     (check-command-success
      (run-input (second example-match) #"" #:runner? runner?)
      #"What is your name? \nNo input.\n"))

   (check-command-success
    (run-input
     "#lang attalambda\n(def answer = (read-line UNIT))\n(print answer)\n(print answer)\n(print (read-line UNIT))\n"
     #"first\nsecond\n")
    #"OK(SOME(\"first\"))OK(SOME(\"first\"))OK(SOME(\"second\"))")
   (check-command-success
    (run-input
     "#lang attalambda\n(def unused = (read-line UNIT))\n(if FALSE (read-line UNIT) UNIT)\n(print (read-line TRUE))\n(print (read-line (head NIL)))\n(print (read-line UNIT))\n"
     #"untouched\n")
    #"ERROR(read-line(arg1 expected UNIT got BOOL))ERROR(EMPTY-LIST\n  -> head(result)\n  -> read-line(arg1 expected UNIT))OK(SOME(\"untouched\"))")
   (check-command-success
    (run-input
     "#lang attalambda\n(def read = read-line)\n(let read-line = (lambda (ignored) UNIT) (print (read UNIT)))\n"
     #"aliased\n")
    #"OK(SOME(\"aliased\"))")

   ;; Each recursive invocation makes a fresh read; Result dependencies force
   ;; the prompt before input and the answer's output before the next prompt.
   (define loop-source
     (string-append
      "#lang attalambda\n"
      "(rec ask ignored =\n"
      "  (if (is-ok (stdout \"> \"))\n"
      "      (let answer = (read-line UNIT)\n"
      "        (if (is-ok answer)\n"
      "            (option-case (unwrap-ok answer)\n"
      "              (lambda (line)\n"
      "                (if (is-ok (stdout (string-append line \"\\n\")))\n"
      "                    (ask UNIT) (exit 1)))\n"
      "              UNIT)\n"
      "            (exit 1)))\n"
      "      (exit 1)))\n(ask UNIT)\n"))
   (check-command-success
    (run-input loop-source #"" #:runner? #t
               #:dialogue (list (list #"> " #"first")
                                (list #"first\n> " #"second")))
    #"> first\n> second\n> ")
   (check-command-success
    (run-input loop-source #" \t\0\377 \r\nlast" #:runner? #t)
    #">  \t\0\377 \n> last\n> ")

   (for ([name (in-list '("language-read-line" "language-make-read-line"
                         "make-read-line" "make-read-line-request"
                         "read-bytes-line" "current-input-port"))])
     (check-command-failure
      (run-input (format "#lang attalambda\n(~a UNIT)\n" name) #"")
      #rx"unbound identifier"))))
