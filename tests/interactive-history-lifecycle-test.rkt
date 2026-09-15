#lang racket/base

(require rackunit racket/file racket/runtime-path "helpers/fresh-language.rkt")
(define-runtime-path fixture "fixtures/interactive-history-lifecycle.rkt")

(test-case "history startup failures and untouched sessions preserve the existing file"
  (for ([kind '(startup-read-break startup-init-failure read-failure-eof empty-eof
                                  failed-save exit0 exit1 unfinished transcript disabled)])
    (define home (make-temporary-directory "attalambda-history-lifecycle-~a"))
    (dynamic-wind
     void
     (lambda ()
       (file-or-directory-permissions home #o700)
       (define environment (environment-variables-copy (current-environment-variables)))
       (environment-variables-set! environment #"HOME" (path->bytes home))
       (environment-variables-set! environment #"PLTUSERHOME" (path->bytes home))
       (environment-variables-set! environment #"TERM" #"dumb")
       (check-command-success
        (run-command environment racket-executable
                     (list (path->string fixture) (symbol->string kind) (path->string home)) 20)
        #"history lifecycle checked\n"))
     (lambda () (delete-directory/files home)))))
