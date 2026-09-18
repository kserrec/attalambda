#lang racket/base

(require rackunit racket/file racket/runtime-path
         "../runner/static/frontend.rkt" "../runner/source-file.rkt")

(define directory (make-temporary-file "attalambda-static-frontend-~a" 'directory))
(define source-path (build-path directory "input.attl"))
(define (snapshot text)
  (call-with-output-file source-path #:exists 'truncate
    (lambda (output) (display text output)))
  (inspect-source-file (path->string source-path)))
(define (prepare text)
  (prepare-source (snapshot (string-append "#lang attalambda\n" text))))

(dynamic-wind
 void
 (lambda ()
   (test-case "validated source is expanded without evaluation or demand"
     (define input (open-input-string "answer\n"))
     (define output (open-output-string))
     (define original-eval (current-eval))
     (define evaluated-module-names '())
     (define user-module-names '())
     (parameterize ([current-input-port input] [current-output-port output]
                    [exit-handler (lambda (_) (error 'test "user exit during expansion"))]
                    [current-eval
                     (lambda (form)
                       (define datum (if (syntax? form) (syntax->datum form) form))
                       (when (and (pair? datum) (eq? (car datum) 'module))
                         (set! evaluated-module-names (cons (cadr datum) evaluated-module-names)))
                       (original-eval form))])
       ;; Positive control proves that the observer sees module evaluation.
       ;; Compare actual generated user identities, not a helper's name prefix.
       (parameterize ([current-namespace (make-base-namespace)])
         (eval '(module observer-positive-control racket/base)))
       (check-not-false (memq 'observer-positive-control evaluated-module-names))
       (for ([text '("" "(add 1 2)" "(def twice x = (add x x))"
                     "(stdout \"must-not-run\") (read-line UNIT) (exit 1)"
                     "(rec loop = loop) loop")])
         (define expanded (prepare text))
         (check-true (syntax? expanded) text)
         (set! user-module-names
               (cons (syntax-e (cadr (syntax->list expanded))) user-module-names))))
     (for ([name (in-list user-module-names)])
       (check-false (memq name evaluated-module-names)))
     (check-equal? (file-position input) 0)
     (check-equal? (get-output-string output) ""))
   (test-case "complete restricted syntax validation precedes any user effect"
     (for ([text '("missing" "(def unused = #t)" "(def unused = 1.5)"
                   "(def unused = 1+2i)" "(def unused = #\\λ)"
                   "#reader racket/base" "#lang racket"
                   "(def x = x)" "(def x = y) (def y = x)"
                   "(stdout \"prefix\") (" "(stdout \"prefix\") missing")])
       (define result (prepare text))
       (check-true (source-problem? result) text)
       (check-equal? (source-problem-kind result) 'invalid text)))
   (test-case "each snapshot has a fresh namespace and is never reread"
     (check-true (syntax? (prepare "(def isolated = 1) isolated")))
     (check-true (source-problem? (prepare "isolated")))
     (define saved (snapshot "#lang attalambda\n(def retained = 1) retained"))
     (delete-file source-path)
     (check-true (syntax? (prepare-source saved))))
   (test-case "file validation and source offsets remain the existing contract"
     (for ([text '("#lang racket\n1" " #lang attalambda\n1")])
       (check-true (source-problem? (snapshot text))))
     (define result (prepare "\n(add 1 unknown)"))
     (check-equal? (source-problem-line result) 3)
     (check-equal? (source-problem-column result) 7)
     (check-exn exn:fail:contract? (lambda () (prepare-source "unvalidated")))))
 (lambda () (delete-directory/files directory)))
