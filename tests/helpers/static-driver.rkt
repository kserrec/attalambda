#lang racket/base

;; A minimal embedding regression around the actual frontend; no second parser.
(require racket/list "../../runner/static/frontend.rkt"
         "../../runner/source-file.rkt" "../../lang/static-data.rkt")
(define (nodes node) (cons node (append-map nodes (source-node-children node))))
(module+ main
  (define inspected (inspect-source-file (vector-ref (current-command-line-arguments) 0)))
  (when (source-problem? inspected) (error 'probe "source validation failed"))
  (define view (prepare-source inspected #:analysis? #t))
  (when (source-problem? view) (error 'probe "source expansion failed"))
  (define terms
    (append-map nodes (append (map source-binding-value (source-view-bindings view))
                              (source-view-expressions view))))
  (write (list (map source-binding-name (source-view-bindings view))
               (length (source-view-registry view))
               (map source-node-data
                    (filter (lambda (node) (eq? (source-node-kind node) 'builtin)) terms))))
  (newline))
