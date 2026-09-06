#lang racket/base

(require (only-in racket/file file-type-bits regular-file-type-bits)
         (only-in racket/path path-get-extension)
         (only-in racket/port port->bytes)
         (for-syntax racket/base
                     (only-in racket/path path-only)))

(define command-misuse-status 64)
(define invalid-source-status 65)
(define unavailable-source-status 66)
(define unexpected-failure-status 70)

(define help-text
  (string-append
   "Usage:\n"
   "  attalambda FILE.attl\n"
   "  attalambda --help\n"
   "  attalambda --version\n"))

(define language-declaration
  #"#lang attalambda")

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
         (regexp-match #px#"^(0[.]3[.]0(?:-dev)?|0[.]2[.]0(?:-dev|-rc[.]1)?)\n$"
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

(define (dotenv-component? part)
  (and (path? part)
       (regexp-match?
        #px"(^|\\.)env($|\\.)"
        (string-downcase (path->string part)))))

(define (dotenv-path? path)
  (for/or ([part (in-list (explode-path path))])
    (dotenv-component? part)))

(define (resolve-parent-path path)
  (let loop ([remaining (explode-path (path->complete-path path))]
             [resolved #f]
             [seen '()])
    (cond
      [(null? remaining)
       (and resolved (simplify-path resolved #f))]
      [else
       (define next
         (if resolved
             (build-path resolved (car remaining))
             (car remaining)))
       (cond
         [(link-exists? next)
          (if (member next seen equal?)
              #f
              (loop
               (append
                (explode-path
                 (path->complete-path (resolve-path next)))
                (cdr remaining))
               #f
               (cons next seen)))]
         [else
          (loop (cdr remaining) next seen)])])))

(define (source-preflight-result source)
  (call-with-input-file source
    (lambda (input)
      (define declaration
        (read-bytes (bytes-length language-declaration) input))
      (define terminator
        (read-byte input))
      (if (and (equal? declaration language-declaration)
               (or (eof-object? terminator)
                   (= terminator 10)
                   (and (= terminator 13)
                        (equal? (read-byte input) 10))))
          (with-handlers
              ([exn:fail:contract?
                (lambda (failure) 'invalid-encoding)])
            (bytes->string/utf-8 (port->bytes input) #f)
            'valid)
          'invalid-declaration))
    #:mode 'binary))

(define (regular-file? path)
  (= (bitwise-and
      (hash-ref (file-or-directory-stat path) 'mode)
      file-type-bits)
     regular-file-type-bits))

(define (validate-source source-name)
  (with-handlers
      ([exn:fail?
        (lambda (failure)
          (stop unavailable-source-status source-name
                "source path could not be inspected"))])
    (define supplied-path (string->path source-name))
    (when (dotenv-path? supplied-path)
      (stop unavailable-source-status source-name
            "refused source path because dotenv files are never read"))
    (unless (equal? (path-get-extension supplied-path) #".attl")
      (stop invalid-source-status source-name
            "source file name must end in lowercase .attl"))
    (define complete-path (path->complete-path supplied-path))
    (when (link-exists? complete-path)
      (stop unavailable-source-status source-name
            "refused symbolic-link source; choose a regular .attl file"))
    (define-values (parent name directory?)
      (split-path complete-path))
    (define resolved-parent (resolve-parent-path parent))
    (unless resolved-parent
      (stop unavailable-source-status source-name
            "source path could not be inspected"))
    (when (dotenv-path? resolved-parent)
      (stop unavailable-source-status source-name
            "refused source path because dotenv files are never read"))
    (define resolved-source (build-path resolved-parent name))
    (unless (or (file-exists? resolved-source)
                (directory-exists? resolved-source))
      (stop unavailable-source-status source-name
            "source file was not found"))
    (unless (regular-file? resolved-source)
      (stop unavailable-source-status source-name
            "source path is not a regular file"))
    (define preflight-result
      (with-handlers
        ([exn:fail?
          (lambda (failure)
            (stop unavailable-source-status source-name
                  "source file could not be read"))])
        (source-preflight-result resolved-source)))
    (cond
      [(eq? preflight-result 'invalid-declaration)
       (stop invalid-source-status source-name
             "line 1 must be exactly #lang attalambda")]
      [(eq? preflight-result 'invalid-encoding)
       (stop invalid-source-status source-name
             "source is not valid UTF-8")])
    supplied-path))

(define (syntax-failure-expression failure)
  (define expressions
    (exn:fail:syntax-exprs failure))
  (and (pair? expressions)
       (car expressions)))

(define (datum-failure-expression? expression)
  (and expression
       (let ([value (syntax-e expression)])
         (and (pair? value)
              (syntax? (car value))
              (eq? (syntax-e (car value)) '#%datum)))))

(define (syntax-failure-reason expression)
  (cond
    [(and expression (identifier? expression))
     (format "unknown AttaLambda name: ~s" (syntax-e expression))]
    [(datum-failure-expression? expression)
     "unsupported literal; only exact Rat and String literals are supported"]
    [else
     "source has invalid syntax"]))

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
    [else
     (stop command-misuse-status #f
           "expected attalambda FILE.attl, attalambda --help, or attalambda --version")]))

(main)
