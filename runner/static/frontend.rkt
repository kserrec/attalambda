#lang racket/base

;; Private expansion of one already validated snapshot. Never declare, evaluate,
;; instantiate, or demand the resulting user module. No session is imported.
(require racket/runtime-path "../source-file.rkt" "../source-reader.rkt"
         "../../lang/static-data.rkt")
(provide prepare-source)

(define-runtime-module-path-index language-index "../../lang/expander.rkt")
(define language-origin (variable-reference->namespace (#%variable-reference)))
(define language-name
  (resolved-module-path-name (module-path-index-resolve language-index)))
(define language-reference
  (if (path? language-name)
      `(file ,(path->string language-name))
      `(quote ,language-name)))

;; Embedded declarations need their fixed cross-phase-persistent dependencies.
;; This bootstraps only the trusted language graph, never an input module.
(when (symbol? language-name)
  (parameterize ([current-namespace language-origin])
    (dynamic-require language-reference #f)))

(define (prepare-source source #:analysis? [analysis? #f])
  (unless (validated-source? source)
    (raise-argument-error 'prepare-source "validated-source?" source))
  (define parsed
    (parse-source-buffer (validated-source-path source)
                         (validated-source-text source)
                         #:line (validated-source-line source)
                         #:column (validated-source-column source)
                         #:position (validated-source-position source)))
  (cond
    [(not (memq (source-buffer-status parsed) '(empty complete)))
     (source-problem 'invalid (source-buffer-message parsed)
                     (source-buffer-line parsed) (source-buffer-column parsed))]
    [else
     (define owner (make-custodian))
     (dynamic-wind
      void
      (lambda ()
        (parameterize ([current-custodian owner])
          (define namespace (make-base-namespace))
          (parameterize ([current-namespace namespace])
            (when (symbol? language-name)
              (namespace-attach-module-declaration language-origin language-reference)
              (namespace-attach-module-declaration language-origin 'racket/runtime-config))
            (define body
              (let ([body (datum->syntax #f (cons '#%module-begin (source-buffer-forms parsed)))])
                (if analysis? (syntax-property body analysis-request-key analysis-request) body)))
            (define module-source
              (datum->syntax #f `(module ,(gensym 'static-source) ,language-reference ,body)))
            (with-handlers
                ([exn:fail:syntax?
                  (lambda (failure)
                    (define expression (syntax-failure-expression failure))
                    (source-problem 'invalid (syntax-failure-reason expression)
                                    (and expression (syntax-line expression))
                                    (and expression (syntax-column expression))))])
              (define expanded (expand module-source))
              (if analysis?
                  (validate-source-view
                   (syntax-property (cadddr (syntax->list expanded)) analysis-result-key)
                   (length (source-buffer-forms parsed)))
                  expanded)))))
      (lambda () (custodian-shutdown-all owner)))]))
