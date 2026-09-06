#lang racket/base

(require rackunit
         racket/file
         racket/path
         racket/runtime-path
         racket/string
         "helpers/fresh-language.rkt")

(define-runtime-path project-root-path "..")

(define project-root
  (simplify-path project-root-path #f))

(define expected-help
  #"Usage:\n  attalambda FILE.attl\n  attalambda --help\n  attalambda --version\n")

(define (check-runner-failure result expected-status expected-stderr)
  (check-false (command-result-timed-out? result)
               (result-diagnostic result))
  (check-equal? (command-result-status result)
                expected-status
                (result-diagnostic result))
  (check-equal? (command-result-stdout result)
                #""
                (result-diagnostic result))
  (check-equal? (command-result-stderr result)
                expected-stderr
                (result-diagnostic result)))

(define (command-diagnostic reason)
  (string->bytes/utf-8
   (format "AttaLambda: ~a\n" reason)))

(define (source-diagnostic source reason
                           #:line [line #f]
                           #:column [column #f])
  (string->bytes/utf-8
   (if (and line column)
       (format "AttaLambda: ~s:~a:~a: ~a\n"
               source line column reason)
       (format "AttaLambda: ~s: ~a\n"
               source reason))))

(define (write-exact-bytes path content)
  (call-with-output-file path
    #:exists 'truncate
    #:mode 'binary
    (lambda (output)
      (write-bytes content output))))

(call-with-fresh-language-install
 project-root
 (lambda (installation)
   (define temporary-root
     (fresh-language-install-temporary-root installation))
   (define environment
     (fresh-language-install-environment installation))
   (define package-source
     (build-path temporary-root "package-source"))
   (define runner
     (build-path package-source "runner" "attalambda.rkt"))
   (define working-directory
     (build-path temporary-root "runner-work"))
   (make-directory working-directory)

   (define (run arguments
                #:current-directory [directory working-directory])
     (run-command environment
                  racket-executable
                  (cons (path->string runner) arguments)
                  20
                  #:current-directory directory))

   ;; The complete initial command surface is exact.
   (check-command-success (run '("--help")) expected-help)
   (check-command-success
    (run '("--version"))
    #"AttaLambda 0.3.0\n")

   (for ([arguments
          (in-list '(()
                     ("--help" "extra")
                     ("--version" "extra")
                     ("--unknown")
                     ("-example.attl")
                     ("run" "program.attl")
                     ("program.attl" "extra")))])
     (check-runner-failure
      (run arguments)
      64
      (command-diagnostic
       "expected attalambda FILE.attl, attalambda --help, or attalambda --version")))

   ;; The retired subcommand is treated as a supplied filename, not retained
   ;; as a compatibility alias.
   (check-runner-failure
    (run '("run"))
    65
    (source-diagnostic
     "run"
     "source file name must end in lowercase .attl"))

   ;; VERSION remains the sole CLI version source. Expansion embeds only an
   ;; approved state so the future native executable needs no runtime copy.
   (define product-version-file
     (build-path package-source "VERSION"))
   (write-exact-bytes product-version-file #"0.2.0-rc.1\n")
   (check-command-success
    (run '("--version"))
    #"AttaLambda 0.2.0-rc.1\n")
   (write-exact-bytes product-version-file #"0.2.0\n")
   (check-command-success
    (run '("--version"))
    #"AttaLambda 0.2.0\n")
   (write-exact-bytes product-version-file #"unsupported\n")
   (define invalid-version-build
     (run '("--version")))
   (check-false (command-result-timed-out? invalid-version-build)
                (result-diagnostic invalid-version-build))
   (check-not-equal? (command-result-status invalid-version-build)
                     0
                     (result-diagnostic invalid-version-build))
   (check-equal? (command-result-stdout invalid-version-build)
                 #""
                 (result-diagnostic invalid-version-build))
   (check-true
    (regexp-match? #rx"invalid product version metadata"
                   (bytes->string/utf-8
                    (command-result-stderr invalid-version-build)
                    #\?))
    (result-diagnostic invalid-version-build))
   (write-exact-bytes product-version-file #"0.3.0\n")

   ;; Validation precedence rejects names and metadata before source content.
   ;; None of the dotenv-spelled paths below is created or opened.
   (check-runner-failure
    (run '("program.env.rkt"))
    66
    (source-diagnostic
     "program.env.rkt"
     "refused source path because dotenv files are never read"))
   (check-runner-failure
    (run '(".ENV.local/program.attl"))
    66
    (source-diagnostic
     ".ENV.local/program.attl"
     "refused source path because dotenv files are never read"))
   (check-runner-failure
    (run '("missing.rkt"))
    65
    (source-diagnostic
     "missing.rkt"
     "source file name must end in lowercase .attl"))
   (check-runner-failure
    (run '("missing.atl"))
    65
    (source-diagnostic
     "missing.atl"
     "source file name must end in lowercase .attl"))
   (check-runner-failure
    (run '("missing.ATTL"))
    65
    (source-diagnostic
     "missing.ATTL"
     "source file name must end in lowercase .attl"))
   (check-runner-failure
    (run '("missing.attl"))
    66
    (source-diagnostic
     "missing.attl"
     "source file was not found"))

   (define directory-source
     (build-path working-directory "directory.attl"))
   (make-directory directory-source)
   (check-runner-failure
    (run (list (path->string directory-source)))
    66
    (source-diagnostic
     (path->string directory-source)
     "source path is not a regular file"))

   (define unreadable-source
     (build-path working-directory "unreadable.attl"))
   (write-source unreadable-source
                 "#lang attalambda\n(stdout \"no\")\n")
   (define unreadable-result
     (dynamic-wind
       (lambda ()
         (file-or-directory-permissions unreadable-source #o000))
       (lambda ()
         (run '("unreadable.attl")))
       (lambda ()
         (file-or-directory-permissions unreadable-source #o600))))
   (check-runner-failure
    unreadable-result
    66
    (source-diagnostic
     "unreadable.attl"
     "source file could not be read"))

   (define malformed-header
     (build-path working-directory "malformed.attl"))
   (write-source malformed-header
                 " #lang attalambda\n(stdout \"no\")\n")
   (check-runner-failure
    (run (list (path->string malformed-header)))
    65
    (source-diagnostic
     (path->string malformed-header)
     "line 1 must be exactly #lang attalambda"))

   (define retired-language-header
     (build-path working-directory "retired-language-header.attl"))
   (write-source retired-language-header
                 "#lang alone_the_lambdas\n(stdout \"no\")\n")
   (check-runner-failure
    (run (list (path->string retired-language-header)))
    65
    (source-diagnostic
     (path->string retired-language-header)
     "line 1 must be exactly #lang attalambda"))

   (define bare-carriage-return-header
     (build-path working-directory "bare-carriage-return.attl"))
   (write-exact-bytes
    bare-carriage-return-header
    #"#lang attalambda\r(stdout \"no\")\n")
   (check-runner-failure
    (run (list (path->string bare-carriage-return-header)))
    65
    (source-diagnostic
     (path->string bare-carriage-return-header)
     "line 1 must be exactly #lang attalambda"))

   (for ([malformed-case
          (in-list
           (list
            (cons "byte-order-mark.attl"
                  #"\357\273\277#lang attalambda\n")
            (cons "trailing-space.attl"
                  #"#lang attalambda \n")))])
     (define malformed-path
       (build-path working-directory (car malformed-case)))
     (write-exact-bytes malformed-path (cdr malformed-case))
     (check-runner-failure
      (run (list (path->string malformed-path)))
      65
      (source-diagnostic
       (path->string malformed-path)
       "line 1 must be exactly #lang attalambda")))

   (define linked-target
     (build-path working-directory "linked-target.attl"))
   (define linked-source
     (build-path working-directory "linked.attl"))
   (write-source linked-target
                 "#lang attalambda\n(stdout \"target ran\")\n")
   (make-file-or-directory-link linked-target linked-source)
   (check-runner-failure
    (run (list (path->string linked-source)))
    66
    (source-diagnostic
     (path->string linked-source)
     "refused symbolic-link source; choose a regular .attl file"))

   (define dotenv-parent
     (build-path working-directory "private.env.local"))
   (define ordinary-parent-link
     (build-path working-directory "ordinary-parent"))
   (make-directory dotenv-parent)
   (write-source
    (build-path dotenv-parent "program.attl")
    "#lang attalambda\n(stdout \"resolved target ran\")\n")
   (make-file-or-directory-link dotenv-parent ordinary-parent-link)
   (check-runner-failure
    (run (list (path->string
                (build-path ordinary-parent-link "program.attl"))))
    66
    (source-diagnostic
     (path->string
      (build-path ordinary-parent-link "program.attl"))
     "refused source path because dotenv files are never read"))

   (define allowed-parent-target
     (build-path working-directory "allowed-parent-target"))
   (define allowed-parent-link
     (build-path working-directory "allowed-parent"))
   (make-directory allowed-parent-target)
   (write-source
    (build-path allowed-parent-target "program.attl")
    "#lang attalambda\n(stdout \"parent link allowed\")\n")
   (make-file-or-directory-link allowed-parent-target allowed-parent-link)
   (check-command-success
    (run (list (path->string
                (build-path allowed-parent-link "program.attl"))))
    #"parent link allowed")

   ;; Paths containing spaces and non-ASCII characters retain the existing
   ;; reader/expander semantics, including CRLF declarations and UTF-8 String
   ;; lowering.
   (define unicode-directory
     (build-path working-directory "source space lambda-λ"))
   (make-directory unicode-directory)
   (define unicode-source
     (build-path unicode-directory "héllo λ.attl"))
   (write-source
    unicode-source
    (string-append
     "#lang attalambda\r\n"
     "(def choose first second = first)\r\n"
     "(stdout (choose \"héllo λ\\n\" \"ignored\"))\r\n"))
   (check-command-success
    (run (list (path->string unicode-source)))
    (string->bytes/utf-8 "héllo λ\n"))

   (define unicode-failure-name
     (path->string
      (build-path "source space lambda-λ" "unknown λ.attl")))
   (define unicode-failure-source
     (build-path working-directory unicode-failure-name))
   (write-source unicode-failure-source
                 "#lang attalambda\n(display \"escape\")\n")
   (check-runner-failure
    (run (list unicode-failure-name))
    65
    (source-diagnostic
     unicode-failure-name
     "unknown AttaLambda name: display"
     #:line 2
     #:column 1))

   (define relative-source
     (build-path working-directory "relative.attl"))
   (write-source relative-source
                 "#lang attalambda\n(stdout \"relative path\")\n")
   (check-command-success
    (run '("relative.attl"))
    #"relative path")

   (define dash-prefixed-source
     (build-path working-directory "-example.attl"))
   (write-source dash-prefixed-source
                 "#lang attalambda\n(stdout \"dash-prefixed path\")\n")
   (check-command-success
    (run '("./-example.attl"))
    #"dash-prefixed path")

   (define header-only-source
     (build-path working-directory "header-only.attl"))
   (write-exact-bytes header-only-source #"#lang attalambda")
   (check-command-success
    (run (list (path->string header-only-source)))
    #"")

   ;; This is the checked-in hello program, loaded outside the installed
   ;; collection by the runner's one dynamic-require call.
   (define hello-source
     (build-path package-source "examples" "hello.attl"))
   (check-command-success
    (run (list (path->string hello-source)))
    #"Hello from AttaLambda.\n")

   ;; Unsupported identifiers still fail in the existing AttaLambda expander. The
   ;; runner reports only the original spelling and source position, never the
   ;; resolved temporary/package path or Racket exception rendering.
   (define unbound-source
     (build-path working-directory "unbound.attl"))
   (write-source unbound-source
                 "#lang attalambda\n(display \"escape\")\n")
   (define unbound-result
     (run '("unbound.attl")))
   (check-runner-failure
    unbound-result
    65
    (source-diagnostic
     "unbound.attl"
     "unknown AttaLambda name: display"
     #:line 2
     #:column 1))
   (check-false
    (regexp-match?
     (regexp (regexp-quote (path->string temporary-root)))
     (bytes->string/utf-8 (command-result-stderr unbound-result)))
    (result-diagnostic unbound-result))

   (define wrong-public-name-source
     (build-path working-directory "wrong-public-name.attl"))
   (write-source
    wrong-public-name-source
    "#lang attalambda\n(_if TRUE \"yes\" \"no\")\n")
   (check-runner-failure
    (run '("wrong-public-name.attl"))
    65
    (source-diagnostic
     "wrong-public-name.attl"
     "unknown AttaLambda name: _if"
     #:line 2
     #:column 1))

   (define unsupported-datum-source
     (build-path working-directory "unsupported-datum.attl"))
   (write-source unsupported-datum-source
                 "#lang attalambda\n#t\n")
   (check-runner-failure
    (run '("unsupported-datum.attl"))
    65
    (source-diagnostic
     "unsupported-datum.attl"
     "unsupported literal; only exact Rat and String literals are supported"
     #:line 2
     #:column 0))

   (define invalid-syntax-source
     (build-path working-directory "invalid-syntax.attl"))
   (write-source invalid-syntax-source
                 "#lang attalambda\n(lambda (left right) left)\n")
   (check-runner-failure
    (run '("invalid-syntax.attl"))
    65
    (source-diagnostic
     "invalid-syntax.attl"
     "source has invalid syntax"
     #:line 2
     #:column 0))

   (define reader-failure-source
     (build-path working-directory "reader-failure.attl"))
   (write-source reader-failure-source
                 "#lang attalambda\n(stdout \"unterminated\"\n")
   (check-runner-failure
    (run '("reader-failure.attl"))
    65
    (source-diagnostic
     "reader-failure.attl"
     "source could not be read; check delimiters and UTF-8 encoding"
     #:line 2
     #:column 0))

   (define invalid-encoding-source
     (build-path working-directory "invalid-encoding.attl"))
   (write-exact-bytes
    invalid-encoding-source
    #"#lang attalambda\n\377\n")
   (check-runner-failure
    (run '("invalid-encoding.attl"))
    65
    (source-diagnostic
     "invalid-encoding.attl"
     "source is not valid UTF-8"))

   ;; A disposable copy replaces only the runner's one loader expression with
   ;; a host failure containing raw detail. The production catch path must
   ;; classify it as status 70 and discard every raw detail byte.
   (define runner-source
     (file->string runner))
   (define fault-runner
     (build-path package-source "runner" "attalambda-phase-23-fault.rkt"))
   (write-source
    fault-runner
    (string-replace
     runner-source
     "(dynamic-require source-path #f)"
     "(error 'phase-23-test \"raw host detail: ~s\" car)"))
   (define internal-failure-result
     (run-command environment
                  racket-executable
                  (list (path->string fault-runner)
                        "header-only.attl")
                  20
                  #:current-directory working-directory))
   (check-runner-failure
    internal-failure-result
    70
    (source-diagnostic
     "header-only.attl"
     "unexpected launcher failure; verify the AttaLambda installation"))
   (check-false
    (regexp-match? #rx"raw host detail|#<procedure|package-source"
                   (bytes->string/utf-8
                    (command-result-stderr internal-failure-result)))
    (result-diagnostic internal-failure-result))

   ;; Object-language Error, pure Result Err, and real-host Result Err values
   ;; are three distinct successful completions. The runner neither observes
   ;; nor reclassifies any of them.
   (define object-error-source
     (build-path working-directory "object-error.attl"))
   (write-source object-error-source
                 "#lang attalambda\n(stdout 0)\n")
   (check-command-success
    (run '("object-error.attl"))
    #"")

   (define pure-result-error-source
     (build-path working-directory "pure-result-error.attl"))
   (write-source pure-result-error-source
                 "#lang attalambda\n(DIV 1 0)\n")
   (check-command-success
    (run '("pure-result-error.attl"))
    #"")

   (define host-result-error-source
     (build-path working-directory "host-result-error.attl"))
   (write-source host-result-error-source
                 "#lang attalambda\n(read-file \"absent.txt\")\n")
   (check-command-success
    (run '("host-result-error.attl"))
    #"")

   ;; The program, not the runner, chooses fatal versus recoverable failure.
   ;; Every case is public-only source in the isolated working directory.
   (for ([case
          (in-list
           '(("exit-zero.attl" "(exit 0)\n" 0 #"")
             ("exit-one.attl" "(exit 1)\n" 1 #"")
             ("missing-file-fatal.attl"
              "(def outcome = (read-file \"missing-exit-input.txt\"))\n(if (is-err outcome) (exit 1) (exit 0))\n"
              1 #"")
             ("missing-file-recoverable.attl"
              "(def outcome = (read-file \"missing-exit-input.txt\"))\n(if (is-err outcome) (exit 0) (exit 1))\n"
              0 #"")
             ("exit-sequencing.attl"
              "(stdout \"before\")\n(exit 1)\n(stdout \"after\")\n"
              1 #"before")
             ("exit-unselected.attl"
              "(if FALSE (exit 1) (stdout \"continued\"))\n"
              0 #"continued")))])
     (define name (car case))
     (write-source (build-path working-directory name)
                   (string-append "#lang attalambda\n" (cadr case)))
     (define result (run (list name)))
     (check-false (command-result-timed-out? result) (result-diagnostic result))
     (check-equal? (command-result-status result) (caddr case) (result-diagnostic result))
     (check-equal? (command-result-stdout result) (cadddr case) (result-diagnostic result))
     (check-equal? (command-result-stderr result) #"" (result-diagnostic result)))))
