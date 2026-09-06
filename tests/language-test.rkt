#lang racket/base

(require rackunit
         racket/path
         racket/runtime-path
         "helpers/fresh-language.rkt")

(define-runtime-path project-root-path "..")
(define-runtime-path canonical-program
  "fixtures/language-canonical.rkt")

(define project-root
  (simplify-path project-root-path #f))

(define inherited-environment
  (environment-variables-copy
   (current-environment-variables)))
(define collection-path-separator
  (if (eq? (system-type 'os) 'windows)
      #";"
      #":"))
(environment-variables-set!
 inherited-environment
 #"PLTCOLLECTS"
 (bytes-append
  (path->bytes
   (build-path (find-system-path 'temp-dir)
               "attalambda-external-collections"))
  collection-path-separator))

(define (run-language-tests)
  (call-with-fresh-language-install
   project-root
   (lambda (installation)
    (define temporary-root
      (fresh-language-install-temporary-root installation))
    (define isolated-environment
      (fresh-language-install-environment installation))

    (check-false
     (environment-variables-ref isolated-environment #"PLTCOLLECTS"))

    (check-command-success
     (run-command isolated-environment
                  racket-executable
                  (list (path->string canonical-program))
                  20)
     (string->bytes/utf-8 "λ🙂"))

    (define retired-collection-program
      (build-path temporary-root "retired-collection.rkt"))
    (write-source
     retired-collection-program
     "#lang alone_the_lambdas\n")
    (check-command-failure
     (run-command isolated-environment
                  racket-executable
                  (list (path->string retired-collection-program))
                  20)
     #rx"collection not found|cannot open module file")

    (define currying-program
      (build-path temporary-root "currying.rkt"))
    (write-source
     currying-program
     #<<PROGRAM
#lang attalambda

(def add-two left right =
  (ADD left right))

(def add-two-to-two =
  (add-two 2))

(stdout
 (let identity = (lambda (value) value)
   (if (EQ (add-two-to-two 2) 4)
       (identity "curried")
       "wrong")))
PROGRAM
     )
    (check-command-success
     (run-command isolated-environment
                  racket-executable
                  (list (path->string currying-program))
                  20)
     #"curried")

    (define lazy-branch-program
      (build-path temporary-root "lazy-branch.rkt"))
    (write-source
     lazy-branch-program
     #<<PROGRAM
#lang attalambda

(def loop value =
  (loop value))

(stdout
 (if FALSE
     (loop NIL)
     "lazy"))
PROGRAM
     )
    (check-command-success
     (run-command isolated-environment
                  racket-executable
                  (list (path->string lazy-branch-program))
                  20)
     #"lazy")

    ;; Public exit is an ordinary unary value, so a definition can alias it.
    ;; Invalid Rat statuses remain ordinary Errors and do not call native exit.
    (for ([case (in-list
                 '(("exit-alias.rkt"
                    "(def quit = exit)\n(quit 0)\n(stdout \"after\")\n"
                    #"")
                   ("invalid-exit.rkt"
                    "(exit 2)\n(stdout \"continued\")\n"
                    #"continued")))])
      (define program (build-path temporary-root (car case)))
      (write-source program (string-append "#lang attalambda\n" (cadr case)))
      (check-command-success
       (run-command isolated-environment
                    racket-executable
                    (list (path->string program))
                    20)
       (caddr case)))

    ;; Test tooling crosses the module boundary only to prove that expansion
    ;; produced canonical lambda values. None of this observation API is
    ;; exported by the object language.
    (define representation-program
      (build-path temporary-root "representations.rkt"))
    (write-source
     representation-program
     #<<PROGRAM
#lang attalambda

(def rat-zero = 0)
(def rat-one = 1)
(def rat-byte = 255)
(def rat-half = 1/2)
(def rat-negative = -7/3)
(def rat-large = 65536)
(def string-value = "λ🙂")
(def saved-host = host)
PROGRAM
     )

    (define representation-probe
      (build-path temporary-root "representation-probe.rkt"))
    (write-source
     representation-probe
     #<<PROBE
#lang racket/base

(require attalambda/runtime/codec)

(define target
  (string->path
   (vector-ref (current-command-line-arguments) 0)))
(dynamic-require target #f)
(define target-namespace
  (module->namespace target))

(define (target-value name)
  (parameterize ([current-namespace target-namespace])
    (eval name)))

(write
 (map object-rat->exact
      (map target-value
           '(rat-zero rat-one rat-byte rat-half rat-negative rat-large))))
(newline)
(void
 (write-bytes
  (object-string->bytes
   (target-value 'string-value))))
PROBE
     )
    (check-command-success
     (run-command isolated-environment
                  racket-executable
                  (list (path->string representation-probe)
                        (path->string representation-program))
                  20)
     (bytes-append
      #"(0 1 255 1/2 -7/3 65536)\n"
      (string->bytes/utf-8 "λ🙂")))

    (for ([case
           (in-list
            '(("#t" #rx"only exact Rat and String literals are supported")
              ("#f" #rx"only exact Rat and String literals are supported")
              ("1.0" #rx"only exact Rat and String literals are supported")
              ("1e3" #rx"only exact Rat and String literals are supported")
              ("+inf.0" #rx"only exact Rat and String literals are supported")
              ("+nan.0" #rx"only exact Rat and String literals are supported")
              ("1+2i" #rx"only exact Rat and String literals are supported")
              ("#\\a" #rx"only exact Rat and String literals are supported")
              ("#\"bytes\"" #rx"only exact Rat and String literals are supported")
              ("#:keyword" #rx"missing argument expression after keyword")
              ("#(1)" #rx"only exact Rat and String literals are supported")))]
          [index (in-naturals)])
      (define literal (car case))
      (define expected-message (cadr case))
      (define unsupported-program
        (build-path temporary-root
                    (format "unsupported-~a.rkt" index)))
      (write-source
       unsupported-program
       (string-append "#lang attalambda\n" literal "\n"))
      (check-command-failure
       (run-command isolated-environment
                    racket-executable
                    (list (path->string unsupported-program))
                    20)
       expected-message))

    (define multi-lambda-program
      (build-path temporary-root "multi-lambda.rkt"))
    (write-source
     multi-lambda-program
     "#lang attalambda\n(lambda (left right) left)\n")
    (check-command-failure
     (run-command isolated-environment
                  racket-executable
                  (list (path->string multi-lambda-program))
                  20)
     #rx"expected \\(lambda \\(argument\\) body\\)")

    (for ([source
           (in-list
            '("(define leaked 1)"
              "(require racket/base)"
              "(+ 1 2)"
              "(display \"leak\")"
              "(raw-cons 1 NIL)"
              "(typed-if TRUE \"yes\" \"no\")"
              "(_if TRUE \"yes\" \"no\")"
              "'quoted"))]
          [index (in-naturals)])
      (define isolated-program
        (build-path temporary-root
                    (format "isolated-~a.rkt" index)))
      (write-source
       isolated-program
       (string-append "#lang attalambda\n" source "\n"))
      (check-command-failure
       (run-command isolated-environment
                    racket-executable
                    (list (path->string isolated-program))
                    20)
       #rx"unbound identifier|not allowed in an expression")))
  ))

(parameterize ([current-environment-variables inherited-environment])
  (run-language-tests))
