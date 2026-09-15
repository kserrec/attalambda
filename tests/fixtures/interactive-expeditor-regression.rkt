#lang racket/base

;; Public Expeditor operations only; source is never evaluated.
(require expeditor (submod expeditor configure)
         racket/port racket/promise racket/string syntax-color/racket-lexer
         "../../runner/editor-output.rkt")

(define arguments (current-command-line-arguments))
(define source
  (list->string
   (map (lambda (number) (integer->char (string->number number)))
        (string-split (vector-ref arguments 0) ","))))
(define checkpoints (vector-ref arguments 1))
(define metadata (make-empty-namespace))
(define untouched (delay (error 'fixture "editor forced namespace metadata")))
(namespace-set-variable-value! 'saved-source untouched #t metadata)

(expeditor-bind-key! "\t" (make-ee-insert-string source))
(expeditor-bind-key! "\e[13~" ee-indent)
(expeditor-bind-key!
 "\e[24~"
 (lambda (_ entry _key)
   ;; An owned side channel avoids adding test markers to terminal output.
   (call-with-output-file checkpoints #:exists 'append
     (lambda (output) (displayln "ready" output)))
   entry))

;; The parent sets the PTY size before releasing this handshake.
(eprintf "READY\n")
(unless (equal? (read-line) "start") (error 'fixture "invalid handshake"))
(define accepted
  (call-with-editor-output
   (lambda ()
     (define editor (expeditor-open '()))
     (unless editor (error 'fixture "Expeditor unavailable"))
     (dynamic-wind
      void
      (lambda ()
        (parameterize ([current-namespace metadata]
                       [current-expeditor-reader port->string]
                       [current-expeditor-post-skipper (lambda (_) 0)]
                       [current-expeditor-ready-checker (lambda (_) #t)]
                       [current-expeditor-lexer racket-lexer]
                       [current-expeditor-indenter (lambda (_ start auto?) #f)]
                       [current-expeditor-color-enabled #f])
          (expeditor-read editor #:prompt "atta>")))
      (lambda () (void (expeditor-close editor)))))))
(eprintf "REPORT ~s ~s\n"
         (map char->integer (string->list accepted))
         (promise-forced? untouched))
(displayln "stdout restored")
