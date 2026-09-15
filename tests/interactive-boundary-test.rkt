#lang racket/base

(require rackunit racket/file racket/list racket/runtime-path
         "../tooling/check-boundaries.rkt")

(define-runtime-path session-source "../runner/session.rkt")
(define-runtime-path diagnostics-source "../runner/diagnostics.rkt")
(define-runtime-path source-file-source "../runner/source-file.rkt")
(define-runtime-path repl-source "../runner/repl.rkt")
(define-runtime-path output-source "../runner/output.rkt")
(define directory (make-temporary-file "attalambda-session-boundary-~a" 'directory))
(define target (build-path directory "session.rkt"))
(define original
  (call-with-input-file session-source
    (lambda (input) (parameterize ([read-accept-reader #t]) (read input)))))
(define (replace datum before after)
  (cond [(equal? datum before) after]
        [(pair? datum) (cons (replace (car datum) before after)
                            (replace (cdr datum) before after))]
        [else datum]))
(define (check datum [class 'session])
  (call-with-output-file target #:exists 'truncate
    (lambda (output) (write datum output)))
  (file-boundary-violations target class directory))

(dynamic-wind
 void
 (lambda ()
   (test-case "shell boundary keeps source and output on their fixed owned ports"
     (for ([example (list (list repl-source 'repl
                                '(((close-output-port program-output) (close-output-port input))
                                  ((session-names current) (load "native.rkt"))
                                  ((render-result current value) (read-source-entry input source))
                                  ((open-session #:input input #:output program-output #:error error)
                                   (open-session #:input input #:output output #:error error))))
                         (list output-source 'shell-output
                               '(((flush-output destination) (flush-output))
                                 ((newline output) (newline))
                                 ((values total last-byte) (read-byte))
                                 (void (lambda () (close-output-port destination))))))])
       (define original-shell
         (call-with-input-file (car example)
           (lambda (input) (parameterize ([read-accept-reader #t]) (read input)))))
       (check-equal? (check original-shell (cadr example)) '())
       (for ([mutation (in-list (caddr example))])
         (define changed (replace original-shell (car mutation) (cadr mutation)))
         (check-not-equal? changed original-shell)
         (check-not-equal? (check changed (cadr example)) '()))))
   (test-case "session boundary permits only checked isolated language modules"
     (check-equal? (check original) '())
     (for ([mutation
            '(((expand module-source) module-source)
              ((datum->syntax #f (cons (quote #%module-begin) forms))
               (datum->syntax (quote-syntax here) (cons (quote #%module-begin) forms)))
              ((eval expanded) (eval forms))
              ((evaluate-entry current parsed void #:imports (quote ()) #:on-phase on-phase)
               (evaluate-entry current parsed void #:on-phase on-phase))
              ((parameterize-break #f (set-session-bindings! current candidate) (set! successful? #t))
               (begin (set-session-bindings! current candidate) (set! successful? #t)))
              ((parameterize-break #f (set-session-bindings! current candidate) (set! successful? #t))
               (begin (parameterize-break #f (set-session-bindings! current candidate))
                      (set! successful? #t)))
              ((unless successful? (custodian-shutdown-all child)) (void))
              ((demand-entry current entry consume)
               (begin (set-session-bindings! current candidate)
                      (demand-entry current entry consume)))
              ((dynamic-require language-path (quote value-to-string))
               (dynamic-require "../runtime/codec.rkt" (quote value-to-string)))
              ((define-runtime-path language-path "../lang/expander.rkt")
               (define-runtime-path language-path "../runtime/host.rkt"))
              ((define namespace (make-base-namespace))
               (define namespace (current-namespace))))])
       (define changed (replace original (car mutation) (cadr mutation)))
       (check-not-equal? changed original "mutation must exercise the actual source")
       (check-not-equal? (check changed) '() (format "rejected: ~s" mutation)))
     (for ([form '((require "../runtime/codec.rkt") (provide eval)
                   (eval forms) (open-input-file "anywhere")
                   (dynamic-require "racket/base" (quote eval)))])
       (define changed
         (append (take original 3) (list (append (fourth original) (list form)))))
       (check-not-equal? (check changed) '() (format "rejected capability: ~s" form))))
   (test-case "diagnostic boundary excludes native details and preserves unwind control flow"
     (define original-diagnostics
       (call-with-input-file diagnostics-source
         (lambda (input) (parameterize ([read-accept-reader #t]) (read input)))))
     (check-equal? (check original-diagnostics 'diagnostics) '())
     (for ([mutation
            '(((raise (failure->source-problem failure (quote render)))
               (failure->source-problem failure (quote render)))
              (exn:fail? exn?)
              ((same-source? (syntax-source expression) expected-source)
               (same-source? (read) expected-source))
              ((same-source? (syntax-source expression) expected-source)
               (same-source? (expand expression) expected-source))
              ((syntax-failure-reason matched) (exn-message failure))
              ((require (only-in "source-file.rkt" source-problem source-problem? source-problem-reason
                                 source-problem-line source-problem-column
                                 syntax-failure-expression syntax-failure-reason))
               (require "../runtime/codec.rkt")))])
       (define changed (replace original-diagnostics (car mutation) (cadr mutation)))
       (check-not-equal? changed original-diagnostics)
       (check-not-equal? (check changed 'diagnostics) '())))
   (test-case "file validation readers stay on their explicit port behind the complete preflight"
     (define original-file
       (call-with-input-file source-file-source
         (lambda (input) (parameterize ([read-accept-reader #t]) (read input)))))
     (check-equal? (check original-file 'source-file) '())
     (for ([mutation
            '(((read-byte input) (read-byte))
              ((read-bytes (bytes-length language-declaration) input)
               (read-bytes (bytes-length language-declaration)))
              ((port->bytes input) (port->bytes))
              ((define supplied-path (string->path source-name))
               (define supplied-path
                 (let ([path (string->path source-name)])
                   (source-preflight-result path) path)))
              ((define declaration (read-bytes (bytes-length language-declaration) input))
               (define declaration
                 (let ([declaration (read-bytes (bytes-length language-declaration) input)])
                   (read-byte) declaration))))])
       (define changed (replace original-file (car mutation) (cadr mutation)))
       (check-not-equal? changed original-file)
       (check-not-equal? (check changed 'source-file) '()))))
 (lambda () (delete-directory/files directory)))
