#lang racket/base

;; Shared source-file inspection. No evaluation, process termination, or program
;; I/O; successful validation returns the same bytes decoded once for :load.
(require (only-in racket/file file-type-bits regular-file-type-bits)
         (only-in racket/path path-get-extension path-only)
         (only-in racket/port port->bytes))

(provide (struct-out validated-source) (struct-out source-problem)
         inspect-source-file syntax-failure-expression source-syntax syntax-failure-reason)

(struct validated-source (path text line column position) #:transparent)
(struct source-problem (kind reason line column) #:transparent)
(define language-declaration #"#lang attalambda")

(define (dotenv-component? part)
  (and (path? part)
       (regexp-match?
        #px"^\\.env($|\\.)"
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
      [(not (car remaining))
       ;; The target is complete; a later visit to this link is not a cycle.
       (loop (cdr remaining) resolved (cdr seen))]
      [else
       (define next
         (simplify-path
          (if resolved
              (build-path resolved (car remaining))
              (car remaining))
          #f))
       (cond
         [(link-exists? next)
          (if (member next seen equal?)
              #f
              (loop
               (append
                (explode-path
                 (path->complete-path (resolve-path next) (path-only next)))
                (cons #f (cdr remaining)))
               #f
               (cons next seen)))]
         [else
          (loop (cdr remaining) next seen)])])))

(define (source-preflight-result source)
  (call-with-input-file source
    (lambda (input)
      (port-count-lines! input)
      (define declaration
        (read-bytes (bytes-length language-declaration) input))
      (define terminator (read-byte input))
      (if (and (equal? declaration language-declaration)
               (or (eof-object? terminator)
                   (= terminator 10)
                   (and (= terminator 13)
                        (equal? (read-byte input) 10))))
          (with-handlers ([exn:fail:contract? (lambda (_) 'invalid-encoding)])
            (define-values (line column position) (port-next-location input))
            (define text (bytes->string/utf-8 (port->bytes input) #f))
            (validated-source source text line column position))
          'invalid-declaration))
    #:mode 'binary))

(define (regular-file? path)
  (= (bitwise-and
      (hash-ref (file-or-directory-stat path) 'mode)
      file-type-bits)
     regular-file-type-bits))

(define (inspect-source-file source-name)
  (with-handlers ([source-problem? values]
                  [exn:fail? (lambda (_)
                               (source-problem 'unavailable
                                               "source path could not be inspected" #f #f))])
    (define (reject kind reason) (raise (source-problem kind reason #f #f)))
    (define supplied-path (string->path source-name))
    (when (dotenv-path? supplied-path)
      (reject 'unavailable "refused source path because dotenv files are never loaded as source"))
    (unless (equal? (path-get-extension supplied-path) #".attl")
      (reject 'invalid "source file name must end in lowercase .attl"))
    (define complete-path (path->complete-path supplied-path))
    (when (link-exists? complete-path)
      (reject 'unavailable "refused symbolic-link source; choose a regular .attl file"))
    (define-values (parent name directory?) (split-path complete-path))
    (define resolved-parent (resolve-parent-path parent))
    (unless resolved-parent
      (reject 'unavailable "source path could not be inspected"))
    (when (dotenv-path? resolved-parent)
      (reject 'unavailable "refused source path because dotenv files are never loaded as source"))
    (define resolved-source (build-path resolved-parent name))
    (unless (or (file-exists? resolved-source) (directory-exists? resolved-source))
      (reject 'unavailable "source file was not found"))
    (unless (regular-file? resolved-source)
      (reject 'unavailable "source path is not a regular file"))
    (define preflight-result
      (with-handlers ([exn:fail? (lambda (_)
                                  (reject 'unavailable "source file could not be read"))])
        (source-preflight-result resolved-source)))
    (cond
      [(eq? preflight-result 'invalid-declaration)
       (reject 'invalid "line 1 must be exactly #lang attalambda")]
      [(eq? preflight-result 'invalid-encoding)
       (reject 'invalid "source is not valid UTF-8")])
    (struct-copy validated-source preflight-result [path supplied-path])))

(define (syntax-failure-expression failure)
  (define expressions
    (exn:fail:syntax-exprs failure))
  (and (pair? expressions)
       (car expressions)))

;; Macro-generated blame can retain user provenance in origins or children.
(define (source-syntax value path)
  (cond [(syntax? value)
         (or (and (equal? (syntax-source value) path) value)
             (source-syntax (syntax-property value 'origin) path)
             (source-syntax (syntax-e value) path))]
        [(pair? value) (or (source-syntax (car value) path) (source-syntax (cdr value) path))]
        [else #f]))

(define (datum-failure-expression? expression)
  (and expression
       (let ([value (syntax-e expression)])
         (and (pair? value)
              (syntax? (car value))
              (eq? (syntax-e (car value)) '#%datum)))))

(define (syntax-failure-reason expression)
  (cond
    [(and expression (eq? (syntax-property expression 'attalambda-recursion) 'self))
     "recursive def binding is not allowed; use rec for self recursion"]
    [(and expression (eq? (syntax-property expression 'attalambda-recursion) 'cycle))
     "module-binding recursion is forbidden; rec supports only self recursion"]
    [(and expression (syntax-property expression 'attalambda-duplicate))
     (format "duplicate definition: ~s" (syntax-e expression))]
    [(and expression (identifier? expression))
     (format "unknown AttaLambda name: ~s" (syntax-e expression))]
    [(datum-failure-expression? expression)
     "unsupported literal; only exact Rat, String, and ASCII Char literals are supported"]
    [else
     "source has invalid syntax"]))

