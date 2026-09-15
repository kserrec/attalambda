#lang racket/base

;; Integration probe only: it accepts source text, not arbitrary evaluation.
;; Explicit hooks never execute the owner's Racket/Expeditor configuration.
(require expeditor
         racket/port
         racket/promise
         racket/string
         syntax-color/racket-lexer
         "../helpers/editor-descriptors.rkt"
         "../../runner/source-reader.rkt"
         (only-in "../../lang/expander.rkt" [read-line language-read-line]
                  UNIT value-to-string)
         "../../readers/string.rkt")

(parameterize ([current-expeditor-reader
                (lambda (input)
                  (define source (port->string input))
                  (if (equal? source "") eof source))]
               [current-expeditor-post-skipper (lambda (_) 0)]
               [current-expeditor-ready-checker
                (lambda (input) (source-ready? (port->string input)))]
               [current-expeditor-lexer racket-lexer]
               [current-expeditor-color-enabled #f])
  (define open-editor
    (if (equal? (current-command-line-arguments) '#("--fail-open"))
        (lambda (_) #f)
        expeditor-open))
  (define input-mode? (equal? (current-command-line-arguments) '#("--input")))
  (define editor (call-with-editor-output (lambda () (open-editor '()))))
  (if editor
      (dynamic-wind
       void
       (lambda ()
         (let loop ()
          (define continue?
           (with-handlers ([exn:break? (lambda (_)
                                        (eprintf "interrupted\n")
                                        #t)])
           (define source
             (call-with-editor-output
              (lambda () (expeditor-read editor #:prompt "atta>"))))
           (eprintf "accepted: ~s\n" source)
           (and input-mode? (string? source)
                (not (equal? (string-trim source) "quit"))
            (begin
             (when (equal? (string-trim source) "read")
               (eprintf "program ready\n")
               (flush-output (current-error-port))
               (define result ((force language-read-line) UNIT))
               (printf "program: ~a\n"
                       (string-value->string ((force value-to-string) result)))
               (flush-output))
             #t))))
          ;; Exception handlers run with breaks disabled. Leave the handler's
          ;; dynamic extent before starting the next cancellable operation.
          (when continue? (loop))))
       (lambda ()
         (eprintf "history: ~s\n" (expeditor-close editor))))
      (eprintf "editor unavailable\n")))

(displayln "stdout restored")
