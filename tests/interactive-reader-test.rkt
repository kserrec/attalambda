#lang racket/base

(require rackunit racket/file racket/list racket/port racket/runtime-path
         "../runner/source-reader.rkt" "../tooling/check-boundaries.rkt")

(define-runtime-path project-root "..")
(define-runtime-path reader-source "../runner/source-reader.rkt")

(define (parsed text) (parse-source-buffer 'repl:1 text))
(define (status text) (source-buffer-status (parsed text)))

(test-case "located native datums, without a second grammar"
  (define result (parsed "1/2 \"hello\" #\\(\n(add 2 (mult 3 4)) #t #(1)"))
  (check-equal? (source-buffer-status result) 'complete)
  (define forms (source-buffer-forms result))
  (check-equal? (map syntax->datum forms)
                '(1/2 "hello" #\( (add 2 (mult 3 4)) #t #(1)))
  ;; Unsupported object datums remain for the existing expander to reject.
  (check-equal? (syntax-source (fourth forms)) 'repl:1)
  (check-equal? (syntax-line (fourth forms)) 2)
  (check-equal? (syntax-column (fourth forms)) 0)
  (define nested (third (syntax->list (fourth forms))))
  (check-equal? (syntax-column nested) 7)
  (define loaded (parse-source-buffer "sample.attl" "\t(add 1 2)"
                                      #:line 2 #:position 17))
  (check-equal? (syntax-line (car (source-buffer-forms loaded))) 2)
  (check-equal? (syntax-column (car (source-buffer-forms loaded))) 8))

(test-case "native completeness including comments and delimiters in literals"
  (for ([text '("" " \t\r\n" "; comment" "#| nested #| comment |# |#" "#;1")])
    (check-equal? (status text) 'empty text))
  (for ([text '("(" "1 (add 2" "\"unfinished" "#| comment" "#;"
                       "#; #;1" "|name" "'" "#\\" "#<<END\ntext\n")])
    (define result (parsed text))
    (check-equal? (source-buffer-status result) 'incomplete text)
    (check-true (exact-positive-integer? (source-buffer-line result)) text)
    (check-true (exact-nonnegative-integer? (source-buffer-column result)) text))
  (for ([text '("#\\)" "#\\;" "\"a\\\"b\"" "#;#;1 2 3" "|multi\nline|"
                       "#<<END\ntext\nEND\n" "1/" "#!/usr/bin/anything\n1")])
    (check-equal? (status text) 'complete text))
  (for ([text '("(1]" ")" "#e1/" "#reader \"missing.rkt\"" "#lang racket"
                     "#!racket/base" "#~" "#;#reader \"missing.rkt\""
                     "#;#lang racket" "#0=(1)")])
    (check-equal? (status text) 'error text)))

(test-case "trusted defaults defeat ambient reader settings"
  (define invoked? #f)
  (define hostile-readtable
    (make-readtable #f #\@ 'terminating-macro
                    (lambda arguments (set! invoked? #t) 99)))
  (parameterize ([current-readtable hostile-readtable]
                 [read-decimal-as-inexact #f]
                 [read-case-sensitive #f]
                 [read-accept-reader #t]
                 [read-accept-lang #t]
                 [read-accept-compiled #t]
                 [read-syntax-accept-graph #t])
    (check-equal? (map syntax->datum (source-buffer-forms (parsed "@ ABC 0.5")))
                  '(@ ABC 0.5))
    (check-false invoked?)
    (check-equal? (status "#0=(1)") 'error)
    (check-equal? (status "#reader \"missing.rkt\"") 'error)))

(test-case "UTF-8 is strict and nested locations survive"
  (check-equal? (status #"\377\n") 'error)
  (define result (parsed "\"é\"\r\n  (add 1 2)"))
  (check-equal? (syntax-line (second (source-buffer-forms result))) 2)
  (check-equal? (syntax-column (second (source-buffer-forms result))) 2))

(test-case "source bytes stop before a program answer while pipe stays open"
  (define owner (make-custodian))
  (define-values (input output) (make-pipe))
  (dynamic-wind
   void
   (lambda ()
     (define result #f)
     (define reader
       (parameterize ([current-custodian owner])
         (thread (lambda () (set! result (read-source-entry input 'repl:1))))))
     (write-bytes #"(read-line UNIT)\r\n\377\nnext\n" output)
     (flush-output output)
     (check-not-false (sync/timeout 2 reader) "source must finish with writer still open")
     (check-equal? (source-buffer-text result) "(read-line UNIT)\r\n")
     (check-equal? (read-bytes-line input) #"\377")
     (check-equal? (read-bytes-line input) #"next"))
   (lambda ()
     (custodian-shutdown-all owner)
     (close-input-port input)
     (close-output-port output))))

(test-case "multiline collection preserves bytes and reports actual unfinished EOF"
  (define continued 0)
  (define input (open-input-bytes #"1 (add\r\n2 3)\nanswer\n"))
  (define result (read-source-entry input 'repl:1
                                    #:continue (lambda () (set! continued (add1 continued)))))
  (check-equal? continued 1)
  (check-equal? (source-buffer-text result) "1 (add\r\n2 3)\n")
  (check-equal? (map syntax->datum (source-buffer-forms result)) '(1 (add 2 3)))
  (check-equal? (port->bytes input) #"answer\n")
  (check-equal? (source-buffer-status
                 (read-source-entry (open-input-bytes #"(add\n1") 'repl:2))
                'unfinished-eof)
  (check-equal? (source-buffer-text
                 (read-source-entry (open-input-bytes #"1") 'repl:3)) "1")
  (check-true (eof-object? (read-source-entry (open-input-bytes #"") 'repl:4))))

(test-case "six commands have exact inert arguments"
  (for ([space '(#\u00a0 #\u2003 #\u2028 #\u3000)])
    (check-equal? (source-command-name
                   (parse-source-entry 'repl (format "~a:quit~a" space space))) 'quit)
    (check-true (source-command-argument
                  (parse-source-entry 'repl (format "~a:echo~aon~a" space space space)))))
  (for ([name '(help names reset quit)])
    (define command (parse-source-entry 'repl (format "  :~a ; comment\n" name)))
    (check-equal? (source-command-name command) name)
    (check-false (source-command-argument command))
    (check-equal? (source-buffer-status
                   (parse-source-entry 'repl (format ":~a extra" name))) 'error))
  (check-true (source-command-argument (parse-source-entry 'repl ":echo on")))
  (check-false (source-command-argument (parse-source-entry 'repl ":echo off")))
  (check-equal? (source-command-argument
                 (parse-source-entry 'repl ":load \"~/$(literal) a.attl\""))
                "~/$(literal) a.attl")
  (for ([text '(":" ":unknown" ":echo" ":echo ON" ":echo 'on" ":echo on off"
                     ":load file.attl" ":load \"x\" \"y\"" ":load \"unfinished"
                     ":load #<<END\nx.attl\nEND\n" ":quit (stdout \"no\")"
                     ":load \"x.attl\" #reader \"missing.rkt\"")])
    (check-equal? (source-buffer-status (parse-source-entry 'repl text)) 'error text)))

(test-case "commands are recognized only at a fresh entry"
  (for ([text '("\":quit\"" "; :quit\n" "#| :quit |#" "#;:quit" "(list :quit)"
                        "; source prefix\n:quit")])
    (check-true (source-buffer? (parse-source-entry 'repl text)) text))
  (define pending (read-source-entry (open-input-bytes #"(list\n:quit)\n") 'repl))
  (check-equal? (map syntax->datum (source-buffer-forms pending)) '((list :quit)))
  ;; Invalid command arguments are local errors, not an invitation to read answers.
  (define input (open-input-bytes #":load \"unfinished\nnext\n"))
  (check-equal? (source-buffer-status (read-source-entry input 'repl)) 'error)
  (check-equal? (port->bytes input) #"next\n"))

(test-case "readiness accepts empty and invalid entries for safe outer handling"
  (for ([text '("" "; comment" "#;1" ":quit" ":load \"unfinished" "(1]"
                     "#reader \"missing.rkt\"")])
    (check-true (source-ready? text) text))
  (for ([text '("1 (add" "\"unfinished" "#;" "#| comment")])
    (check-false (source-ready? text) text)))

(test-case "reader extensions never execute during readiness or submission"
  (define directory (make-temporary-file "attalambda-reader-~a" 'directory))
  (define sentinel (build-path directory "executed"))
  (define reader (build-path directory "reader.rkt"))
  (dynamic-wind
   void
   (lambda ()
     (call-with-output-file reader
       (lambda (output)
         (fprintf output
                  "#lang racket/base\n(provide read read-syntax)\n(call-with-output-file ~s (lambda (out) (display \"executed\" out)))\n"
                  (path->string sentinel))))
     (define directive (format "#reader (file ~s) 1" (path->string reader)))
     (for ([source (list directive (string-append "#;" directive)
                        (string-append ":load \"safe.attl\" " directive))])
       (check-true (source-ready? source))
       (check-equal? (source-buffer-status (parse-source-entry 'repl source)) 'error)
       (check-false (file-exists? sentinel))))
   (lambda () (delete-directory/files directory))))

(test-case "source tooling boundary rejects unsafe readers and native capabilities"
  (define original
    (call-with-input-file reader-source
      (lambda (input) (parameterize ([read-accept-reader #t]) (read input)))))
  (define directory (make-temporary-file "attalambda-reader-boundary-~a" 'directory))
  (define target (build-path directory "source-reader.rkt"))
  (define (replace datum before after)
    (cond [(equal? datum before) after]
          [(pair? datum) (cons (replace (car datum) before after)
                              (replace (cdr datum) before after))]
          [else datum]))
  (define (check datum)
    (call-with-output-file target #:exists 'truncate
      (lambda (output) (write datum output)))
    (file-boundary-violations target 'source-reader directory))
  (define (hoist datum operation)
    (cond
      [(not (pair? datum)) datum]
      [(eq? (car datum) operation)
       (if (eq? operation 'call-with-default-reading-parameterization)
           `(begin (call-with-default-reading-parameterization void) (,(cadr datum)))
           `(begin (parameterize ,(cadr datum) (void)) ,@(cddr datum)))]
      [else (cons (hoist (car datum) operation) (hoist (cdr datum) operation))]))
  (define (escape-reader datum kind)
    (cond
      [(not (pair? datum)) datum]
      [(eq? (car datum) 'call-with-default-reading-parameterization)
       (define parameters (caddr (cadr datum)))
       (define body (cddr parameters))
       (define deferred
         (case kind
           [(define) `(let () (define (loop) ,@body) loop)]
           [(named-let) `(let loop ((pending #t))
                          (if pending loop (begin ,@body)))]
           [else `(lambda () ,@body)]))
       (define factory
         `(call-with-default-reading-parameterization
           (lambda () (parameterize ,(cadr parameters) ,deferred))))
       (if (eq? kind 'named-let) `(,factory #f) `(,factory))]
      [else (cons (escape-reader (car datum) kind)
                  (escape-reader (cdr datum) kind))]))
  (dynamic-wind
   void
   (lambda ()
     (check-equal? (check original) '())
     ;; Keeping controls as no-ops elsewhere must not authorize an unguarded read.
     (for ([operation '(call-with-default-reading-parameterization parameterize)])
       (check-not-equal? (check (hoist original operation)) '()
                         (format "configuration must enclose reading: ~s" operation)))
     (check-not-equal?
      (check (hoist (hoist original 'call-with-default-reading-parameterization)
                    'parameterize)) '())
     (for ([kind '(lambda define named-let)])
       (check-not-equal? (check (escape-reader original kind)) '()
                         "a reader function cannot escape its dynamic restrictions"))
     (for ([mutation '(((read-accept-reader #f) (read-accept-reader #t))
                       ((read-accept-lang #f) (read-accept-lang #t))
                       ((read-accept-compiled #f) (read-accept-compiled #t))
                       ((current-readtable #f) (current-readtable (make-readtable #f)))
                       ((read-syntax source input) (read-syntax source))
                       ((bytes->string/utf-8 content #f) (bytes->string/utf-8 content #\?))
                       ((quote load) load))])
       (check-not-equal? (check (replace original (car mutation) (cadr mutation))) '()
                         (format "rejected mutation: ~s" mutation)))
     (for ([form '((eval source) (require racket/system)
                   (require "../runtime/codec.rkt") (provide current-input-port))])
       (define changed (append (take original 3)
                               (list (append (fourth original) (list form)))))
       (check-not-equal? (check changed) '() (format "rejected capability: ~s" form))))
   (lambda () (delete-directory/files directory)))
  (define reader-class
    (findf (lambda (item) (equal? (source-classification-path item)
                                  (simplify-path reader-source)))
           (project-source-classifications project-root)))
  (check-equal? (source-classification-class reader-class) 'source-reader))
