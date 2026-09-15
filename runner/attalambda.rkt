#lang racket/base

(require "source-file.rkt" racket/runtime-path
         (for-syntax racket/base
                     (only-in racket/path path-only)))

(define command-misuse-status 64)
(define invalid-source-status 65)
(define unavailable-source-status 66)
(define unexpected-failure-status 70)
(define-runtime-module-path-index repl-index "repl.rkt")

(define help-text
  (string-append
   "Usage:\n"
   "  attalambda [--no-history]\n"
   "  attalambda --repl [--no-history]\n"
   "  attalambda FILE.attl\n"
   "  attalambda --help\n"
   "  attalambda --version\n"))

(define-syntax (embedded-product-version stx)
  (define source (syntax-source stx))
  (unless (path? source)
    (raise-syntax-error #f "runner source path is unavailable" stx))
  (define content
    (call-with-input-file (build-path (path-only source) 'up "VERSION")
      (lambda (input)
        (read-bytes 64 input))
      #:mode 'binary))
  (define matched
    (and (bytes? content)
         ;; A full read does not establish EOF; never embed a truncated prefix.
         (not (= (bytes-length content) 64))
         (regexp-match #px#"^((?:0|[1-9][0-9]*)(?:[.](?:0|[1-9][0-9]*)){2}(?:-dev|-rc[.](?:0|[1-9][0-9]*))?)\n$"
                       content)))
  (unless matched
    (raise-syntax-error #f "invalid product version metadata" stx))
  (datum->syntax stx
                 (bytes->string/utf-8 (cadr matched))))

(define (stop status source reason [line #f] [column #f])
  (cond
    [(and source line column)
     (eprintf "AttaLambda: ~s:~a:~a: ~a\n"
              source line column reason)]
    [source
     (eprintf "AttaLambda: ~s: ~a\n" source reason)]
    [else
     (eprintf "AttaLambda: ~a\n" reason)])
  (exit status))

(define (validate-source source-name)
  (define inspected (inspect-source-file source-name))
  (when (source-problem? inspected)
    (stop (if (eq? (source-problem-kind inspected) 'invalid)
              invalid-source-status unavailable-source-status)
          source-name (source-problem-reason inspected)
          (source-problem-line inspected) (source-problem-column inspected)))
  (validated-source-path inspected))

(define (requested-source-missing? failure source-path)
  (define missing-path
    (exn:fail:filesystem:missing-module-path failure))
  (and (path? missing-path)
       (equal?
        (simplify-path (path->complete-path missing-path) #f)
        (simplify-path (path->complete-path source-path) #f))))

(define (run-source source-name)
  (define source-path (validate-source source-name))
  (with-handlers
      ([exn:fail:read?
        (lambda (failure)
          (define locations
            (exn:fail:read-srclocs failure))
          (define location
            (and (pair? locations) (car locations)))
          (stop invalid-source-status source-name
                "source could not be read; check delimiters and UTF-8 encoding"
                (and location (srcloc-line location))
                (and location (srcloc-column location))))]
       [exn:fail:syntax?
        (lambda (failure)
          (define expression
            (syntax-failure-expression failure))
          (stop invalid-source-status source-name
                (syntax-failure-reason expression)
                (and expression (syntax-line expression))
                (and expression (syntax-column expression))))]
       [exn:fail:filesystem:missing-module?
        (lambda (failure)
          (if (requested-source-missing? failure source-path)
              (stop unavailable-source-status source-name
                    "source file was not found")
              (stop unexpected-failure-status source-name
                    "unexpected launcher failure; verify the AttaLambda installation")))]
       [exn:fail:filesystem?
        (lambda (failure)
          (stop unavailable-source-status source-name
                "source file could not be read"))]
       [exn:fail?
        (lambda (failure)
          (stop unexpected-failure-status source-name
                "unexpected launcher failure; verify the AttaLambda installation"))])
    (dynamic-require source-path #f)))

(define (main)
  (define arguments
    (vector->list (current-command-line-arguments)))
  (cond
    [(equal? arguments '("--help"))
     (display help-text)]
    [(equal? arguments '("--version"))
     (define product-version (embedded-product-version))
     (display "AttaLambda ")
     (display product-version)
     (newline)]
    [(and (= (length arguments) 1)
          (not (regexp-match? #px"^-" (car arguments))))
     (run-source (car arguments))]
    [(member arguments '(() ("--no-history") ("--repl")
                            ("--repl" "--no-history") ("--no-history" "--repl")))
     (define interactive?
       (and (terminal-port? (current-input-port)) (terminal-port? (current-error-port))))
     (unless (or interactive? (member "--repl" arguments))
       (stop command-misuse-status #f
             "a terminal is required; use attalambda --repl for redirected source"))
     (with-handlers ([exn:fail? (lambda (_)
                                (stop unexpected-failure-status #f
                                      "unexpected launcher failure; verify the AttaLambda installation"))])
       (define run-repl (dynamic-require repl-index 'run-repl))
       (exit (run-repl (embedded-product-version) interactive?
                       #:history? (not (member "--no-history" arguments)))))]
    [else
     (stop command-misuse-status #f
           "expected attalambda [--repl] [--no-history], attalambda FILE.attl, attalambda --help, or attalambda --version")]))

(main)
