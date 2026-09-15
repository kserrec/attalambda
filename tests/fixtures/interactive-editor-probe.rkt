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
         "../../runner/session.rkt"
         (only-in "../../lang/expander.rkt" [read-line language-read-line]
                  UNIT value-to-string)
         "../../readers/string.rkt")

(define status 0)
(with-handlers ([session-exit? (lambda (request) (set! status (session-exit-status request)))]
                [exn:fail? (lambda (_) (eprintf "probe failure\n") (set! status 70))])
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
  (define native-failure? (equal? (current-command-line-arguments) '#("--session-native-failure")))
  (define session-mode? (or native-failure? (equal? (current-command-line-arguments) '#("--session"))))
  (define current #f)
  (define echo? #t)
  (define editor (call-with-editor-output (lambda () (open-editor '()))))
  (if editor
      (dynamic-wind
       void
       (lambda ()
         (when session-mode? (set! current (open-session)))
         (let loop ()
          (define phase 'source)
          (define continue?
           (with-handlers ([exn:break? (lambda (_)
                                        (eprintf "repl:probe: interrupted (~a)\n" phase)
                                        #t)])
           (define source
             (call-with-editor-output
              (lambda () (expeditor-read editor #:prompt "atta>"))))
           (eprintf "accepted: ~s\n" source)
           (and (or input-mode? session-mode?) (string? source)
                (not (equal? (string-trim source) "quit"))
            (begin
             (when (equal? (string-trim source) "read")
               (eprintf "program ready\n")
               (flush-output (current-error-port))
               (define result ((force language-read-line) UNIT))
               (printf "program: ~a\n"
                       (string-value->string ((force value-to-string) result)))
               (flush-output))
             (when session-mode?
               (set! phase 'entry)
               (eprintf "entry ready\n")
               (flush-output (current-error-port))
               (define parsed (parse-source-entry 'repl:probe source))
               (cond
                 [(source-command? parsed)
                  (case (source-command-name parsed)
                    [(reset) (reset-session! current) (eprintf "session reset\n")]
                    [(echo) (set! echo? (source-command-argument parsed))
                            (eprintf "echo: ~a\n" echo?)]
                    [else (error 'fixture "unsupported probe command")])]
                 [else
                  (evaluate-entry current parsed
                                  (if echo?
                                      (lambda (value)
                                        (set! phase 'rendering)
                                        (eprintf "=> ~a\n" (render-result current value))
                                        (set! phase 'entry))
                                      void))])
               (when native-failure? (error 'fixture "injected native failure")))
             #t))))
          ;; Exception handlers run with breaks disabled. Leave the handler's
          ;; dynamic extent before starting the next cancellable operation.
          (when continue? (loop))))
       (lambda ()
         (when current (close-session current) (eprintf "session closed\n"))
         (eprintf "history: ~s\n" (expeditor-close editor))))
      (eprintf "editor unavailable\n"))))

(displayln "stdout restored")
(exit status)
