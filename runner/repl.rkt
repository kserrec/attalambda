#lang racket/base

;; Shell control flow stays outside each cancellable language entry.
(require "source-reader.rkt" "source-file.rkt" "session.rkt" "diagnostics.rkt" "output.rkt")
(provide run-repl)

(define help-text
  (string-append
   "Enter AttaLambda expressions, for example (add 1/2 1/3).\n"
   "Definitions stay lazy: (def double x = (mult x 2)), then (double 21).\n"
   ":help                 Show this help\n"
   ":names                List user definitions\n"
   ":load \"path.attl\"     Execute a standalone file and retain its definitions\n"
   ":echo on / :echo off   Enable or disable automatic result printing\n"
   ":reset                Discard definitions and close session resources\n"
   ":quit                 End the session\n"
   "Automatic printing supports finite tagged values. Untagged functions can\n"
   "run, fail, or loop when the printer tries to identify them. Use :echo off\n"
   "to enter raw function values without automatic printing.\n"))

(define (run-repl version interactive? #:history? [history? #t])
  (define input (current-input-port))
  (define output (current-output-port))
  (define error (current-error-port))
  (define owner (make-custodian))
  (define-values (program-output result-output prepare-ui)
    (parameterize ([current-custodian owner])
      (make-shell-output output error (and interactive? (terminal-port? output)))))
  (define current #f)
  (define failed? #f)
  (define echo? #t)
  (define (show problem source)
    (prepare-ui)
    (display (format-source-problem source problem) error)
    (flush-output error))
  (define (recover problem source)
    ;; Exception handlers disable breaks; custom-port writes can also queue a
    ;; break until an explicit check. Deliver it inside this protected
    ;; extent, including a second Ctrl+C while reporting the first interruption.
    (with-handlers ([exn:break? (lambda (_) (if interactive? 'continue 130))])
      (parameterize-break #t
        (show problem source)
        (break-enabled #t)
        'continue)))
  (define (finish) (if (and (not interactive?) failed?) 1 0))
  (define (fatal)
    ;; A broken diagnostic destination must not escape cleanup/status handling.
    (with-handlers ([exn:fail? void])
      (prepare-ui)
      (display "AttaLambda: unexpected launcher failure; verify the AttaLambda installation\n" error)
      (flush-output error))
    70)
  (with-handlers ([session-exit? session-exit-status]
                  [exn:break? (lambda (_) 130)]
                  [exn:fail? (lambda (_) (fatal))])
    (dynamic-wind
     void
     (lambda ()
       (parameterize ([current-custodian owner])
         (set! current (open-session #:input input #:output program-output #:error error))
         (when interactive?
           (fprintf error "AttaLambda ~a — :help for help\n" version)
           (flush-output error))
         (let loop ([number 1])
           (define source (string->symbol (format "repl:~a" number)))
           (define phase 'source)
           (define outcome
             (with-handlers
                 ([exn:break? (lambda (_)
                                (if interactive?
                                    (recover (source-problem 'interrupted "entry interrupted" #f #f) source)
                                    130))]
                  [source-problem? (lambda (problem)
                                     (set! failed? #t) (recover problem source))]
                  [exn:fail? (lambda (failure)
                               ;; A failed shell stream cannot support another entry.
                               ;; Parse problems and language exceptions have their
                               ;; own recoverable paths; do not retry unusable I/O.
                               (when (memq phase '(source output command reset)) (raise failure))
                               (set! failed? #t)
                               (recover (failure->source-problem failure phase source) source))])
               (when interactive? (prepare-ui) (display "atta> " error) (flush-output error))
               (define parsed
                 (read-source-entry
                  input source
                  #:continue (lambda ()
                               (when interactive? (display "...> " error) (flush-output error)))))
               (cond
                 [(eof-object? parsed) (finish)]
                 [(source-command? parsed)
                  (set! phase 'command)
                  (prepare-ui)
                  (case (source-command-name parsed)
                    [(help) (display help-text error) (flush-output error) 'continue]
                    [(names)
                     (define names (session-names current))
                     (if (null? names)
                         (display "No user definitions.\n" error)
                         (begin
                           (display "User definitions:\n" error)
                           (for ([name (in-list names)])
                             (fprintf error "  ~a\n" (format-user-name name)))))
                     (flush-output error)
                     'continue]
                    [(load)
                     (set! source (source-command-argument parsed))
                     (set! phase 'load)
                     (define result
                       (load-source-file current source #:on-phase (lambda (next) (set! phase next))))
                     (when (source-problem? result) (raise result))
                     (set! phase 'command)
                     (prepare-ui)
                     (display "Loaded source file.\n" error) (flush-output error)
                     'continue]
                    [(reset)
                     (set! phase 'reset)
                     (reset-session! current)
                     (display "Session reset.\n" error) (flush-output error)
                     'continue]
                    [(echo)
                     (set! echo? (source-command-argument parsed))
                     (fprintf error "Automatic echo: ~a\n" (if echo? "on" "off"))
                     (flush-output error)
                     'continue]
                    [(quit) (finish)]
                    [else (raise (source-problem 'invalid "unsupported command" #f #f))])]
                 [(eq? (source-buffer-status parsed) 'unfinished-eof)
                  (show (source-problem 'invalid (source-buffer-message parsed)
                                        (source-buffer-line parsed) (source-buffer-column parsed)) source)
                  65]
                 [(eq? (source-buffer-status parsed) 'error)
                  (raise (source-problem 'invalid (source-buffer-message parsed)
                                         (source-buffer-line parsed) (source-buffer-column parsed)))]
                 [(eq? (source-buffer-status parsed) 'empty) 'continue]
                 [else
                  (evaluate-entry
                   current parsed
                   (if echo?
                       (lambda (value)
                         (set! phase 'render)
                         (define rendered
                           (call-with-render-diagnostics (lambda () (render-result current value))))
                         (set! phase 'output)
                         (result-output rendered)
                         (set! phase 'evaluate))
                       void)
                   #:on-phase (lambda (next) (set! phase next)))
                  'continue])))
           ;; Recover outside the handler's break-disabled dynamic extent.
           (if (eq? outcome 'continue) (loop (add1 number)) outcome))))
     (lambda ()
       (dynamic-wind void
                     (lambda () (when current (close-session current)))
                     (lambda ()
                       (custodian-shutdown-all owner)
                       (close-output-port program-output)))))))
