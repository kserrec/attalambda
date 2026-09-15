#lang racket/base

;; Interactive presentation only. Native exception text and paths are never
;; diagnostic input; callers supply the submitted entry or load path explicitly.
(require (only-in "source-file.rkt" source-problem source-problem? source-problem-reason
                  source-problem-line source-problem-column
                  syntax-failure-expression syntax-failure-reason))

(provide failure->source-problem format-source-problem call-with-render-diagnostics)

(define (same-source? actual expected)
  (and expected
       (equal? (if (path? actual) (path->string actual) actual)
               (if (path? expected) (path->string expected) expected))))

(define (failure->source-problem failure phase [expected-source #f])
  (cond
    [(source-problem? failure) failure]
    [(eq? phase 'render)
     (source-problem 'rendering "automatic result rendering failed" #f #f)]
    [(eq? phase 'expand)
     (define expression
       (and (exn:fail:syntax? failure) (syntax-failure-expression failure)))
     (define matched
       (and expression (same-source? (syntax-source expression) expected-source) expression))
     (source-problem
      'invalid
      (string-append "source expansion failed: "
                     (cond [matched (syntax-failure-reason matched)]
                           [(exn:fail:syntax? failure) "source has invalid syntax"]
                           [else "unexpected underlying runtime failure"]))
      (and matched (syntax-line matched)) (and matched (syntax-column matched)))]
    [(eq? phase 'read)
     (define locations (if (exn:fail:read? failure) (exn:fail:read-srclocs failure) '()))
     (define location (and (pair? locations) (car locations)))
     (define matched
       (and location (same-source? (srcloc-source location) expected-source) location))
     (source-problem 'invalid "source could not be read; check delimiters and reader syntax"
                     (and matched (srcloc-line matched)) (and matched (srcloc-column matched)))]
    [else (source-problem 'native "evaluation failed in the underlying runtime" #f #f)]))

;; Bound presentation, never source acceptance. Escape terminal controls and
;; invisible formatting characters explicitly: symbol ~s can contain them raw.
(define (diagnostic-fragment text limit)
  (define size (min (string-length text) limit))
  (string-append
   (apply string-append
          (for/list ([character (in-string text 0 size)])
            (if (memq (char-general-category character) '(cc cf zl zp))
                (string-append "\\u{" (number->string (char->integer character) 16) "}")
                (string character))))
   (if (< size (string-length text)) "..." "")))

(define (format-source-problem source-name problem)
  (define source
    (diagnostic-fragment
     (cond [(path? source-name) (path->string source-name)]
           [(symbol? source-name) (symbol->string source-name)]
           [(string? source-name) source-name]
           [else "source"]) 200))
  (define reason (diagnostic-fragment (source-problem-reason problem) 240))
  (define line (source-problem-line problem))
  (define column (source-problem-column problem))
  (if (and line column)
      (format "AttaLambda: ~a:~a:~a: ~a\n" source line column reason)
      (format "AttaLambda: ~a: ~a\n" source reason)))

;; A renderer failure must leave the transaction, not become a successful
;; consumer return. Breaks and explicit language exit bypass this handler.
(define (call-with-render-diagnostics action)
  (with-handlers ([exn:fail? (lambda (failure)
                             (raise (failure->source-problem failure 'render)))])
    (action)))
