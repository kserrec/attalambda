#lang racket/base

(require rackunit racket/file racket/list racket/runtime-path
         "../tooling/check-boundaries.rkt")

(define-runtime-path session-source "../runner/session.rkt")
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
(define (check datum)
  (call-with-output-file target #:exists 'truncate
    (lambda (output) (write datum output)))
  (file-boundary-violations target 'session directory))

(dynamic-wind
 void
 (lambda ()
   (test-case "session boundary permits only checked isolated language modules"
     (check-equal? (check original) '())
     (for ([mutation
            '(((expand module-source) module-source)
              ((datum->syntax #f (cons (quote #%module-begin) forms))
               (datum->syntax (quote-syntax here) (cons (quote #%module-begin) forms)))
              ((eval expanded) (eval forms))
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
       (check-not-equal? (check changed) '() (format "rejected capability: ~s" form)))))
 (lambda () (delete-directory/files directory)))
