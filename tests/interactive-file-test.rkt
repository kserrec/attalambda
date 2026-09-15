#lang racket/base

(require rackunit racket/file racket/path racket/port
         "../runner/source-file.rkt" "../runner/source-reader.rkt" "../runner/session.rkt")

(define (with-files procedure)
  (define directory (make-temporary-file "attalambda-interactive-file-~a" 'directory))
  (dynamic-wind
   void
   (lambda () (parameterize ([current-directory directory]) (procedure directory)))
   (lambda () (delete-directory/files directory))))

(define (write-file name content)
  (call-with-output-file name #:exists 'truncate #:mode 'binary
    (lambda (output) (write-bytes content output))))

(test-case "validation returns the exact decoded body and counted source position"
  (with-files
   (lambda (directory)
     (for ([ending '(#"\n" #"\r\n")])
       (write-file "with spaces.attl"
                   (bytes-append #"#lang attalambda" ending
                                 (string->bytes/utf-8 "; λ comment\n(add 2 3)\n")))
       (define inspected (inspect-source-file "./with spaces.attl"))
       (check-true (validated-source? inspected))
       (check-equal? (validated-source-path inspected) (string->path "./with spaces.attl"))
       (check-equal? (validated-source-text inspected) "; λ comment\n(add 2 3)\n")
       (check-equal? (list (validated-source-line inspected) (validated-source-column inspected)
                           (validated-source-position inspected)) '(2 0 18)))
     (write-file "empty.attl" #"#lang attalambda")
     (define empty (inspect-source-file "empty.attl"))
     (check-equal? (validated-source-text empty) "")
     (check-equal? (list (validated-source-line empty) (validated-source-column empty)
                         (validated-source-position empty)) '(1 16 17)))))

(test-case "invalid declaration and whole-body encoding are structured failures"
  (with-files
   (lambda (directory)
     (for ([content '(#"#lang racket/base\n(display 1)\n" #"#lang attalambda\r"
                       #"#lang attalambda\n(stdout \"before\")\n\377")])
       (write-file "invalid.attl" content)
       (define inspected (inspect-source-file "invalid.attl"))
       (check-true (source-problem? inspected))
       (check-eq? (source-problem-kind inspected) 'invalid))
     (check-eq? (source-problem-kind (inspect-source-file "missing.attl")) 'unavailable)
     (check-eq? (source-problem-kind (inspect-source-file "missing.txt")) 'invalid))))

(test-case "dotenv spellings and final symlinks are rejected before content reads"
  (with-files
   (lambda (directory)
     (write-file "ordinary.attl" #"#lang attalambda\n42\n")
     (make-file-or-directory-link "ordinary.attl" "linked.attl")
     (define reads '())
     (define guard
       (make-security-guard
        (current-security-guard)
        (lambda (who path permissions)
          (when (memq 'read permissions) (set! reads (cons path reads))))
        (lambda (who host port mode) (void))))
     (parameterize ([current-security-guard guard])
       (for ([name '("secret.env.attl" "nested.env.local/value.attl" "linked.attl")])
         (check-eq? (source-problem-kind (inspect-source-file name)) 'unavailable)))
     (check-equal? reads '()))))

(define (with-file-session procedure)
  (with-files
   (lambda (directory)
     (define output (open-output-bytes))
     (define current (open-session #:input (open-input-bytes #"") #:output output))
     (dynamic-wind void (lambda () (procedure current output directory))
                   (lambda () (close-session current) (close-output-port output))))))

(define (enter current text)
  (define results '())
  (evaluate-entry current (parse-source-buffer 'repl:1 text)
                  (lambda (value) (set! results (cons (render-result current value) results))))
  (reverse results))

(test-case "loads use fresh checked modules, ordered file demand and no implicit observation"
  (with-file-session
   (lambda (current output directory)
     (enter current "(def ambient = 99)")
     (write-file "standalone.attl"
                 #"#lang attalambda\n(stdout \"A\")\n(def answer = 42)\n(lambda (x) (stdout \"unobserved\"))\n(stdout \"B\")\n")
     (check-true (void? (load-source-file current "standalone.attl")))
     (check-equal? (get-output-bytes output) #"AB")
     (check-equal? (enter current "answer") '("42"))
     (write-file "isolated.attl"
                 #"#lang attalambda\n(stdout \"never\")\n(def leaked = ambient)\n")
     (check-exn exn:fail:syntax? (lambda () (load-source-file current "isolated.attl")))
     (check-equal? (get-output-bytes output) #"AB")
     (check-equal? (session-names current) '(ambient answer)))))

(test-case "loads retain original file syntax locations and reject reader extensions before effects"
  (with-file-session
   (lambda (current output directory)
     (write-file "with spaces.attl" #"#lang attalambda\r\n(stdout \"never\")\r\n  unknown\r\n")
     (check-exn
      (lambda (failure)
        (and (exn:fail:syntax? failure)
             (let ([expression (syntax-failure-expression failure)])
               (check-equal? (syntax-source expression) (string->path "./with spaces.attl"))
               (check-equal? (syntax-line expression) 3)
               (check-equal? (syntax-column expression) 2)
               #t)))
      (lambda () (load-source-file current "./with spaces.attl")))
     (for ([form '(#"#reader \"untrusted.rkt\" 1" #"#lang racket/base" #"#~not-compiled")])
       (write-file "extension.attl" (bytes-append #"#lang attalambda\n(stdout \"never\")\n" form))
       (check-true (source-problem? (load-source-file current "extension.attl"))))
     (check-equal? (get-output-bytes output) #"")
     (check-equal? (enter current "(add 2 3)") '("5")))))

(test-case "reload reruns a fresh instance while old closures and delayed values keep snapshots"
  (with-file-session
   (lambda (current output directory)
     (define (version number)
       (write-file "reload.attl"
                   (string->bytes/utf-8
                    (format "#lang attalambda\n(stdout \"load\")\n(def x = ~a)\n(def plus-x n = (add x n))\n(def delayed = (add x 100))\n" number))))
     (version 1)
     (load-source-file current "reload.attl")
     (define first-module (cadr (hash-ref (session-bindings current) 'x)))
     (enter current "(def old-plus = plus-x) (def old-delayed = delayed)")
     (version 11)
     (load-source-file current "reload.attl")
     (define second-module (cadr (hash-ref (session-bindings current) 'x)))
     (check-not-eq? first-module second-module)
     (check-equal? (enter current "(old-plus 1) (plus-x 1) old-delayed delayed x")
                   '("2" "12" "101" "111" "11"))
     (load-source-file current "reload.attl")
     (check-not-eq? second-module (cadr (hash-ref (session-bindings current) 'x)))
     (check-equal? (get-output-bytes output) #"loadloadload")
     (check-equal? (enter current "(old-plus 1) x") '("2" "11")))))

(test-case "failed loads publish no names and successful Error or Err expressions still publish"
  (with-file-session
   (lambda (current output directory)
     (enter current "(def old = 7)")
     (define committed (session-bindings current))
     (for ([bad '("missing" "(def loop x = (loop x))" "(def first = second) (def second = first)")])
       (write-file "rejected.attl"
                   (string->bytes/utf-8
                    (string-append "#lang attalambda\n(stdout \"never\")\n(def old = 99)\n(def new = 1)\n" bad)))
       (check-exn exn:fail:syntax? (lambda () (load-source-file current "rejected.attl")))
       (check-eq? (session-bindings current) committed))
     (write-file "unfinished.attl" #"#lang attalambda\n(stdout \"never\")\n(def old = 99)\n(")
     (check-true (source-problem? (load-source-file current "unfinished.attl")))
     (check-eq? (session-bindings current) committed)
     (check-equal? (get-output-bytes output) #"")
     (write-file "accepted.attl" #"#lang attalambda\n(def old = 8)\n(def new = 2)\n(head NIL)\n(div 1 0)\n")
     (check-true (void? (load-source-file current "accepted.attl")))
     (check-equal? (enter current "old new") '("8" "2")))))

(test-case "cancelling a loaded file preserves old bindings but cannot undo its output"
  (with-files
   (lambda (directory)
     (define-values (input answer) (make-pipe))
     (define-values (observed output) (make-pipe))
     (define current (open-session #:input input #:output output))
     (define worker #f)
     (dynamic-wind
      void
      (lambda ()
        (enter current "(def old = 7)")
        (define committed (session-bindings current))
        (write-file "cancel.attl" #"#lang attalambda\n(def old = 99)\n(def new = 1)\n(stdout \"begun\")\n(read-line UNIT)\n(stdout \"never\")\n")
        (define finished (make-channel))
        (set! worker
              (thread (lambda ()
                        (channel-put finished
                                     (with-handlers ([exn:break? values] [exn:fail? values])
                                       (load-source-file current "cancel.attl"))))))
        (check-equal? (sync/timeout 15 (read-bytes-evt 5 observed)) #"begun")
        (break-thread worker)
        (check-true (exn:break? (sync/timeout 15 finished)))
        (check-not-false (sync/timeout 5 worker))
        (check-eq? (session-bindings current) committed)
        (check-equal? (enter current "old") '("7"))
        (check-false (byte-ready? observed)))
      (lambda ()
        (when (and worker (not (thread-dead? worker))) (kill-thread worker))
        (close-session current)
        (close-input-port input) (close-output-port answer)
        (close-input-port observed) (close-output-port output))))))

(test-case "literal load paths preserve the launch directory and program-relative I/O"
  (with-file-session
   (lambda (current output directory)
     (make-directory "sub dir")
     (write-file "sub dir/héllo λ.attl"
                 #"#lang attalambda\n(def loaded = 17)\n(write-file \"relative.txt\" (string-to-bytes \"launch directory\"))\n")
     (define before (current-directory))
     (define source-path (build-path directory "sub dir" "héllo λ.attl"))
     (define reads 0)
     (define guard
       (make-security-guard
        (current-security-guard)
        (lambda (who path permissions)
          (when (and (equal? path source-path) (memq 'read permissions))
            (set! reads (add1 reads))
            (when (> reads 1) (error 'test "validated source was reopened"))))
        (lambda (who host port mode) (void))))
     (parameterize ([current-security-guard guard])
       (check-true (void? (load-source-file current "sub dir/héllo λ.attl"))))
     (check-equal? reads 1)
     (check-equal? (current-directory) before)
     (check-equal? (file->bytes "relative.txt") #"launch directory")
     (check-false (file-exists? "sub dir/relative.txt"))
     (check-equal? (enter current "loaded") '("17"))
     (make-file-or-directory-link "sub dir" "allowed-parent")
     (check-true (void? (load-source-file current "allowed-parent/héllo λ.attl")))
     ;; These characters are literal path characters, never shell expansion.
     (write-file "$(literal).attl" #"#lang attalambda\n(def literal = 23)\n")
     (check-true (void? (load-source-file current "$(literal).attl")))
     (check-equal? (enter current "literal") '("23")))))

(test-case "load validation rejects content and unsafe paths while leaving the session usable"
  (with-file-session
   (lambda (current output directory)
     (enter current "(def retained = 29)")
     (define committed (session-bindings current))
     (for ([content '(#" #lang attalambda\n(stdout \"never\")"
                       #"#lang attalambda \n(stdout \"never\")"
                       #"\357\273\277#lang attalambda\n(stdout \"never\")"
                       #"#lang attalambda\r(stdout \"never\")"
                       #"#lang attalambda\n(stdout \"never\")\n\377")])
       (write-file "invalid.attl" content)
       (check-eq? (source-problem-kind (load-source-file current "invalid.attl")) 'invalid)
       (check-eq? (session-bindings current) committed))
     (make-directory "directory.attl")
     (for ([name '("missing.ATTL" "missing.txt" "missing.attl" "directory.attl")])
       (check-true (source-problem? (load-source-file current name))))
     (write-file "ordinary.attl" #"#lang attalambda\n(stdout \"never\")\n")
     (make-file-or-directory-link "ordinary.attl" "linked.attl")
     (make-directory "private.env.local")
     (make-file-or-directory-link "private.env.local" "ordinary-parent")
     (define reads '())
     (parameterize
         ([current-security-guard
           (make-security-guard
            (current-security-guard)
            (lambda (who path permissions)
              (when (memq 'read permissions) (set! reads (cons path reads))))
            (lambda (who host port mode) (void)))])
       ;; No dotenv-spelled file is created, opened or inspected.
       (for ([name '("secret.env.attl" ".ENV.local/value.attl" "ordinary-parent/value.attl"
                                      "linked.attl")])
         (check-eq? (source-problem-kind (load-source-file current name)) 'unavailable)))
     (check-equal? reads '())
     (check-eq? (session-bindings current) committed)
     (check-equal? (get-output-bytes output) #"")
     (check-equal? (enter current "retained") '("29")))))
