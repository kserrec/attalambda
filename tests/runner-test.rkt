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
  #"Usage:\n  attalambda [--no-history]\n  attalambda --repl [--no-history]\n  attalambda FILE.attl\n  attalambda --check FILE.attl\n  attalambda --check=SYSTEM FILE.attl\n  attalambda --help\n  attalambda --version\n")

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

   ;; File/help/version retain their contracts alongside interactive selection.
   (check-command-success (run '("--help")) expected-help)
   (check-command-success
    (run '("--version"))
    #"AttaLambda 0.9.0\n")

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
       (if (null? arguments)
           "a terminal is required; use attalambda --repl for redirected source"
           "expected attalambda [--repl] [--no-history], attalambda FILE.attl, attalambda --check FILE.attl, attalambda --help, or attalambda --version"))))

   ;; The retired subcommand is treated as a supplied filename, not retained
   ;; as a compatibility alias.
   (check-runner-failure
    (run '("run"))
    65
    (source-diagnostic
     "run"
     "source file name must end in lowercase .attl"))

   ;; VERSION remains the sole CLI version source. Expansion validates its
   ;; format and embeds it so the native executable needs no runtime copy.
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
   (for ([version-case
          (in-list '((#"0.6.1\n" #"AttaLambda 0.6.1\n")
                     (#"1.2.3-dev\n" #"AttaLambda 1.2.3-dev\n")
                     (#"12.34.56-rc.2\n" #"AttaLambda 12.34.56-rc.2\n")))])
     (write-exact-bytes product-version-file (car version-case))
     (check-command-success
      (run '("--version"))
      (cadr version-case)))
   ;; The unchanged 64-byte read must reach EOF before accepting a version.
   (define long-version (bytes-append #"1.2." (make-bytes 58 49)))
   (write-exact-bytes product-version-file (bytes-append long-version #"\n"))
   (check-command-success
    (run '("--version"))
    (bytes-append #"AttaLambda " long-version #"\n"))
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
   (for ([invalid-version
          (in-list (list #"0.6\n"
                         #"0.6.1.2\n"
                         #"00.6.1\n"
                         #"0.6.1-rc.01\n"
                         #"0.6.1-preview\n"
                         #"0.6.1"
                         #"0.6.1\n\n"
                         (bytes-append long-version #"1\n")
                         (bytes-append long-version #"1\ntrailing-junk\n")))])
     (write-exact-bytes product-version-file invalid-version)
     (check-command-failure
      (run '("--version"))
      #rx"invalid product version metadata"))
   (write-exact-bytes product-version-file #"0.9.0\n")

   ;; Validation precedence rejects names and metadata before source content.
   ;; None of the dotenv-spelled paths below is created or opened.
   (check-runner-failure
    (run '(".env.rkt"))
    66
    (source-diagnostic
     ".env.rkt"
     "refused source path because dotenv files are never loaded as source"))
   (check-runner-failure
    (run '(".ENV.local/program.attl"))
    66
    (source-diagnostic
     ".ENV.local/program.attl"
     "refused source path because dotenv files are never loaded as source"))
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
     (build-path working-directory ".env.private"))
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
     "refused source path because dotenv files are never loaded as source"))

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

   ;; Returning through a completed link target is not a symbolic-link loop.
   (check-command-success
    (run (list (path->string
                (build-path allowed-parent-link 'up "allowed-parent"
                            "program.attl")))
         #:current-directory temporary-root)
    #"parent link allowed")

   ;; Normalize only after walking each component: a symlink followed by
   ;; ".." refers to the target's parent, not the link's lexical parent.
   (define nested-target (build-path allowed-parent-target "nested"))
   (make-directory nested-target)
   (make-file-or-directory-link
    nested-target (build-path working-directory "nested-link"))
   (make-file-or-directory-link
    "nested-link/.." (build-path working-directory "target-parent"))
   (check-command-success
    (run (list (path->string
                (build-path working-directory "target-parent" "program.attl")))
         #:current-directory temporary-root)
    #"parent link allowed")

   ;; Relative loop targets must not grow distinct spellings indefinitely.
   (for ([loop-case (in-list '(("dot-loop" "./dot-loop")
                              ("up-loop" "allowed-parent-target/../up-loop")
                              ("suffix-loop" "./suffix-loop/nested")))])
     (define loop-source
       (build-path working-directory (car loop-case) "program.attl"))
     (make-file-or-directory-link
      (cadr loop-case) (build-path working-directory (car loop-case)))
     (check-runner-failure
      (run (list (path->string loop-source)))
      66
      (source-diagnostic (path->string loop-source)
                         "source path could not be inspected")))

   ;; A relative directory-link target belongs to the link's directory,
   ;; independent of the launcher's working directory.
   (define relative-parent-link
     (build-path working-directory "relative-parent"))
   (make-file-or-directory-link "allowed-parent-target" relative-parent-link)
   (check-command-success
    (run (list (path->string
                (build-path relative-parent-link "program.attl")))
         #:current-directory temporary-root)
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

   ;; Only dotenv spellings are refused; a name merely containing env is a
   ;; program like any other.
   (write-source (build-path working-directory "env.attl")
                 "#lang attalambda\n(stdout \"env program\")\n")
   (check-command-success (run '("env.attl")) #"env program")

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
     "unsupported literal; only exact Rat, String, and ASCII Char literals are supported"
     #:line 2
     #:column 0))

   (define invalid-syntax-source
     (build-path working-directory "invalid-syntax.attl"))
   (write-source invalid-syntax-source
                 "#lang attalambda\n(lambda () 1)\n")
   (check-runner-failure
    (run '("invalid-syntax.attl"))
    65
    (source-diagnostic
     "invalid-syntax.attl"
     "source has invalid syntax"
     #:line 2
     #:column 0))

   ;; Recursion errors keep actionable, fixed text and the user's location;
   ;; they must not expose host exception text or execute preceding effects.
   (for ([case (in-list
                '(("recursive-def.attl" "(def loop x = (loop x))"
                   "recursive def binding is not allowed; use rec for self recursion")
                  ("recursive-alias.attl" "(def loop = loop)"
                   "recursive def binding is not allowed; use rec for self recursion")
                  ("recursive-cycle.attl"
                   "(def first x = (second x))\n(def second x = (first x))"
                   "module-binding recursion is forbidden; rec supports only self recursion")
                  ("recursive-mixed.attl"
                   "(rec first x = (second x))\n(def second x = (first x))"
                   "module-binding recursion is forbidden; rec supports only self recursion")))])
     (define filename (car case))
     (write-source (build-path working-directory filename)
                   (string-append "#lang attalambda\n(stdout \"must not run\")\n"
                                  (cadr case) "\n"))
     (check-runner-failure
      (run (list filename)) 65
      (source-diagnostic filename (caddr case) #:line 3 #:column 5)))

   ;; A repeated name blames its later definition; blame generated inside the
   ;; language reports the user's location, never an expander position; and
   ;; control characters in a user name are escaped rather than written raw.
   (for ([case (in-list
                '(("duplicate-def.attl" "(def x = 1)\n(def x = 2)"
                   "duplicate definition: x" 4 5)
                  ("nested-def.attl" "(stdout (def y = 1))"
                   "source has invalid syntax" 3 9)
                  ("control-name.attl" "(stdout na\u001bme)"
                   "unknown AttaLambda name: na\\u{1b}me" 3 8)))])
     (define filename (car case))
     (write-source (build-path working-directory filename)
                   (string-append "#lang attalambda\n(stdout \"must not run\")\n"
                                  (cadr case) "\n"))
     (check-runner-failure
      (run (list filename)) 65
      (source-diagnostic filename (caddr case)
                         #:line (cadddr case) #:column (car (cddddr case)))))

   ;; A body reader extension is refused before any of its host code runs, and
   ;; bytecode planted beside a source file never replaces the source itself.
   (write-source (build-path working-directory "planted-reader.rkt")
                 (string-append
                  "#lang racket/base\n(provide read read-syntax)\n"
                  "(define (read input) (with-output-to-file \"planted-sentinel\" void) 1)\n"
                  "(define (read-syntax source input) (datum->syntax #f (read input)))\n"))
   (write-source (build-path working-directory "reader-extension.attl")
                 "#lang attalambda\n(stdout #reader \"planted-reader.rkt\" 1)\n")
   (check-runner-failure
    (run '("reader-extension.attl")) 65
    (source-diagnostic "reader-extension.attl"
                       "source could not be read; check delimiters and UTF-8 encoding"
                       #:line 2 #:column 8))
   (check-false (file-exists? (build-path working-directory "planted-sentinel")))

   (write-source (build-path working-directory "planted.attl")
                 "#lang attalambda\n(stdout \"planted\")\n")
   (write-source (build-path working-directory "victim.attl")
                 "#lang attalambda\n(stdout \"source\")\n")
   (check-command-success
    (run-command environment racket-executable '("-l-" "raco" "make" "planted.attl") 60
                 #:current-directory working-directory)
    #"")
   (copy-file (build-path working-directory "compiled" "planted_attl.zo")
              (build-path working-directory "compiled" "victim_attl.zo"))
   (check-command-success (run '("victim.attl")) #"source")

   (unless (eq? (system-type) 'windows)
     ;; A closed stderr never changes the exit status, and an interrupt ends
     ;; the run with one fixed line and status 130.
     (define shell (find-executable-path "sh"))
     (define closed-stderr-result
       (run-command environment shell
                    (list "-c" "exec \"$0\" \"$@\" 2>&-"
                          (path->string racket-executable) (path->string runner) "missing.attl")
                    20 #:current-directory working-directory))
     (check-equal? (command-result-status closed-stderr-result) 66
                   (result-diagnostic closed-stderr-result))

     (write-source (build-path working-directory "interrupted.attl")
                   (string-append "#lang attalambda\n"
                                  "(write-file \"started\" (string-to-bytes \"x\"))\n"
                                  "(print (len (range 0 100000000)))\n"))
     (define interrupted-result
       (run-command environment shell
                    (list "-c"
                          (string-append
                           "\"$0\" \"$@\" & pid=$!; tries=0; "
                           "until [ -e started ] || [ \"$tries\" -ge 300 ]; do sleep 0.1; tries=$((tries + 1)); done; "
                           "kill -INT \"$pid\"; wait \"$pid\"")
                          (path->string racket-executable) (path->string runner) "interrupted.attl")
                    60 #:current-directory working-directory))
     (check-runner-failure interrupted-result 130
                           (source-diagnostic "interrupted.attl" "interrupted")))

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
                 "#lang attalambda\n(div 1 0)\n")
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
