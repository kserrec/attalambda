#lang racket/base
(require rackunit racket/file racket/runtime-path "../tooling/check-boundaries.rkt")
(define-runtime-path checker "../runner/static")

(test-case "each exact kernel module rejects execution, I/O, and extra imports"
  (define directory (make-temporary-file "attalambda-static-kernel-boundary-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (for ([name '("types.rkt" "proof.rkt" "substitution.rkt" "unification.rkt" "type-display.rkt" "contracts.rkt" "inference.rkt" "analysis.rkt")]
           [class '(static-types static-proof static-substitution static-unification static-type-display static-contracts static-inference static-analysis)])
       (define original
         (call-with-input-file (build-path checker name)
           (lambda (input) (parameterize ([read-accept-reader #t]) (read input)))))
       (define target (build-path directory name))
       (define (check datum)
         (call-with-output-file target #:exists 'truncate (lambda (port) (write datum port)))
         (file-boundary-violations target class directory))
       (check-equal? (check original) '() name)
       (for ([injected '((eval '(lambda (x) x)) (display "source output") (exit 0)
                        (print "source output") (read-line)
                        (getenv "ATTALAMBDA_TEST") (require racket/tcp)
                        (require "../../runtime/host.rkt") (provide eval))])
         (define mutated (list (car original) (cadr original) (caddr original)
                               (append (cadddr original) (list injected))))
         (check-not-equal? (check mutated) '() (format "~a: ~s" name injected)))))
   (lambda () (delete-directory/files directory))))
