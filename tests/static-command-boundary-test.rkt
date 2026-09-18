#lang racket/base
(require rackunit racket/file racket/runtime-path "../tooling/check-boundaries.rkt")
(define-runtime-path command "../runner/static/command.rkt")
(test-case "the check adapter admits report output but rejects execution and program input"
  (define directory (make-temporary-file "attalambda-static-command-boundary-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define original
       (call-with-input-file command
         (lambda (input) (parameterize ([read-accept-reader #t]) (read input)))))
     (define target (build-path directory "command.rkt"))
     (define (check datum)
       (call-with-output-file target #:exists 'truncate (lambda (port) (write datum port)))
       (file-boundary-violations target 'static-command directory))
     (check-equal? (check original) '())
     (for ([injected '((eval '(lambda (x) x)) (read-line) (exit 0)
                      (dynamic-require "program.attl" #f) (open-input-file "program-data")
                      (getenv "ATTALAMBDA_TEST") (require racket/tcp)
                      (require "../session.rkt") (require "../../runtime/host.rkt")
                      (provide eval))])
       (check-not-equal? (check (list (car original) (cadr original) (caddr original)
                                      (append (cadddr original) (list injected)))) '()
                         (format "~s" injected))))
   (lambda () (delete-directory/files directory))))
