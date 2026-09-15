#lang racket/base

;; Source collection only. The session engine continues to own evaluation.
(require expeditor racket/port racket/runtime-path racket/string
         syntax-color/racket-lexer "source-reader.rkt")
(provide read-editor-entry)
(define-runtime-module-path-index editor-output-index "editor-output.rkt")

(define (completion-namespace names)
  (define namespace (make-empty-namespace))
  (for ([name (in-list names)])
    (define spelling
      (if (equal? (symbol->string name) "")
          "||"
          (parameterize ([read-accept-bar-quote #f])
            (string-replace (format "~s" name) "|" "\\|"))))
    ;; At the start of an entry, a bare colon would select a shell command.
    (define source-name
      (if (string-prefix? spelling ":") (string-append "\\" spelling) spelling))
    (namespace-set-variable-value! (string->symbol source-name) #f #t namespace))
  namespace)

(define (read-editor-entry input output source history
                           #:names [names '()]
                           #:open [open-editor expeditor-open])
  ;; Internal portability/file-mode use must not resolve POSIX symbols on Windows.
  (and
   (eq? (system-type 'os) 'unix)
   (let ([call-with-editor-output
          (dynamic-require editor-output-index 'call-with-editor-output)])
     (define content
       (parameterize
           ([current-input-port input]
            [current-output-port output]
            ;; Only source spellings and inert placeholders enter this namespace.
            [current-namespace (completion-namespace names)]
            [current-expeditor-reader
             (lambda (input)
               (define text (port->string input))
               (if (equal? text "") eof text))]
            [current-expeditor-post-skipper (lambda (_) 0)]
            [current-expeditor-ready-checker
             (lambda (input) (source-ready? (port->string input)))]
            [current-expeditor-lexer racket-lexer]
            [current-expeditor-parentheses '((|(| |)|) (|[| |]|) (|{| |}|))]
            ;; Use the library's S-expression grouping and indentation fallback.
            [current-expeditor-grouper (lambda (editor start limit direction) #t)]
            [current-expeditor-indenter (lambda (editor start auto?) #f)]
            [current-expeditor-color-enabled #f])
         (call-with-editor-output
          (lambda ()
            (define editor (open-editor history))
            (and editor
                 (dynamic-wind
                  void
                  (lambda () (expeditor-read editor #:prompt "atta>"))
                  ;; Open afresh on the next prompt so shell history can retain
                  ;; the specified 1000 entries despite the library's limit.
                  (lambda () (void (expeditor-close editor)))))))))
     (cond
       [(or (not content) (eof-object? content)) content]
       [(string? content) (parse-source-entry source content)]
       [else (error 'editor "source editor did not return an entry")]))))
