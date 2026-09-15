#lang racket/base

;; Fresh-process fault injection: each caller must supply its isolated history
;; home so no personal preferences can be reached by this fixture.
(require racket/file racket/path racket/string racket/runtime-path rackunit
         "../../runner/repl.rkt" "../../runner/history.rkt")
(define kind (string->symbol (vector-ref (current-command-line-arguments) 0)))
(define root (path->directory-path (path->complete-path
                                  (vector-ref (current-command-line-arguments) 1))))
(define preference (find-system-path 'pref-dir))
(unless (string-prefix? (path->string preference) (path->string root))
  (error 'history-test "preference directory is outside the isolated test home"))
(write-history #t '("old saved submission"))
(define target (build-path preference "attalambda" "history-v1"))
(define prior (file->bytes target))
(define attempts 0)
(define-runtime-path language-directory "../../lang")
(define guard
  (make-security-guard
   (current-security-guard)
   (lambda (who path permissions)
     (when (and (zero? attempts) path
                (case kind
                  [(startup-read-break read-failure-eof)
                   (and (equal? path target) (memq 'read permissions))]
                  [(startup-init-failure)
                   (and (string-prefix? (path->string (simplify-path path #f))
                                        (path->string (path->directory-path
                                                       (simplify-path language-directory #f))))
                        (memq 'read permissions))]
                  [(failed-save)
                   (and (string-prefix? (path->string path) (path->string preference))
                        (eq? who 'rename-file-or-directory))]
                  [else #f]))
       (set! attempts (add1 attempts))
       (if (eq? kind 'startup-read-break)
           (begin (break-thread (current-thread)) (break-enabled #t))
           (error 'test "injected history lifecycle failure"))))
   (lambda args (void))))
(define source
  (case kind
    [(exit0) "(exit 0)\n"]
    [(exit1) "(exit 1)\n"]
    [(unfinished) "(add 1\n"]
    [(read-failure-eof empty-eof) ""]
    [else "(add 1 2)\n:quit\n"]))
(define input (open-input-string source))
(define output (open-output-bytes))
(define messages (open-output-bytes))
(dynamic-wind
 void
 (lambda ()
   (define status
     (parameterize ([current-security-guard guard]
                    [current-input-port input]
                    [current-output-port output]
                    [current-error-port messages])
       (run-repl "test" (not (eq? kind 'transcript))
                 #:history? (not (eq? kind 'disabled)))))
   (check-equal? status
                 (case kind [(startup-read-break) 130] [(startup-init-failure) 70]
                   [(unfinished) 65] [(exit1) 1] [else 0]))
   (check-equal? attempts
                 (if (memq kind '(startup-read-break startup-init-failure read-failure-eof failed-save)) 1 0))
   (when (memq kind '(startup-read-break startup-init-failure))
     (check-equal? (file-position input) 0))
   (if (memq kind '(exit0 exit1))
       (check-equal? (read-history #t) (list source "old saved submission"))
       (check-equal? (file->bytes target) prior))
   (displayln "history lifecycle checked"))
 (lambda ()
   (close-input-port input) (close-output-port output) (close-output-port messages)))
