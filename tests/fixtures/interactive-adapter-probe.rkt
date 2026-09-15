#lang racket/base

(require expeditor
         "../../runner/editor.rkt"
         "../../runner/source-reader.rkt")
(define mode (vector-ref (current-command-line-arguments) 0))
(define result
  (read-editor-entry
   (current-input-port) (current-output-port) 'repl:probe '()
   #:open (if (equal? mode "fail-open") (lambda (_) #f) expeditor-open)))
(define summary
  (cond [(source-buffer? result)
         (list (source-buffer-status result)
               (map syntax->datum (source-buffer-forms result)))]
        [(source-command? result)
         (list 'command (source-command-name result) (source-command-argument result))]
        [(eof-object? result) 'eof]
        [else 'unavailable]))
(eprintf "accepted: ~s\n" summary)
(when (source-buffer? result)
  (eprintf "text: ~s\n" (source-buffer-text result)))
(displayln "stdout restored")
