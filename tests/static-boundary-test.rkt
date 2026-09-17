#lang racket/base

(require rackunit racket/file racket/runtime-path "../tooling/check-boundaries.rkt")
(define-runtime-path frontend "../runner/static/frontend.rkt")
(define directory (make-temporary-file "attalambda-static-boundary-~a" 'directory))
(define target (build-path directory "frontend.rkt"))
(define original
  (call-with-input-file frontend
    (lambda (input) (parameterize ([read-accept-reader #t]) (read input)))))
(define (replace datum before after)
  (cond [(equal? datum before) after]
        [(pair? datum) (cons (replace (car datum) before after)
                            (replace (cdr datum) before after))]
        [else datum]))
(define (check datum)
  (call-with-output-file target #:exists 'truncate
    (lambda (output) (write datum output)))
  (file-boundary-violations target 'static-frontend directory))
(dynamic-wind
 void
 (lambda ()
   (check-equal? (check original) '())
   (for ([mutation
          '(((expand module-source) (eval module-source))
            ((expand module-source) (dynamic-require module-source #f))
            ((make-base-namespace) (current-namespace))
            ((dynamic-require language-reference #f) (dynamic-require source #f))
            ((namespace-attach-module-declaration language-origin language-reference)
             (namespace-attach-module language-origin language-reference))
            ((datum->syntax #f (cons '#%module-begin (source-buffer-forms parsed)))
             (datum->syntax (quote-syntax here) (cons '#%module-begin (source-buffer-forms parsed))))
            ((require racket/runtime-path "../source-file.rkt" "../source-reader.rkt" "../../lang/static-data.rkt")
             (require racket/runtime-path "../source-file.rkt" "../source-reader.rkt" "../../lang/static-data.rkt" "../session.rkt"))
            ((provide prepare-source) (provide prepare-source eval)))])
     (define mutated (replace original (car mutation) (cadr mutation)))
     (check-not-equal? mutated original)
     (check-not-equal? (check mutated) '())))
 (lambda () (delete-directory/files directory)))
