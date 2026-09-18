#lang racket/base
(require rackunit racket/file racket/list "../runner/static/frontend.rkt" "../runner/source-file.rkt"
         "../runner/static/analysis.rkt" "../runner/static/inference.rkt"
         "../runner/static/proof.rkt" "../runner/static/contracts.rkt"
         "../runner/static/type-display.rkt")
(define (analyze text)
  (analyze-view (prepare-source (validated-source 'io.attl text 2 0 17) #:analysis? #t)))
(define (state text) (proof-status (analysis-proof (analyze text))))

(test-case "the four public wrappers and print retain audited Result shapes"
  (for ([row '((stdout "String -> Result(Unit)") (read-line "Unit -> Result(Option(String))")
               (read-file "String -> Result(List(Byte))") (write-file "String -> List(Byte) -> Result(Unit)")
               (print "forall a:data. a -> Result(Unit)"))])
    (define entry (contract-ref (car row)))
    (check-eq? (library-contract-status entry) 'complete)
    (check-equal? (scheme->string (library-contract-signature entry)) (cadr row)))
  (for ([text '("(stdout 1)" "(read-line TRUE)" "(read-file NIL)"
                "(write-file \"path\" \"contents\")" "(write-file \"path\" (list 1))"
                "(stdout (read-file \"path\"))")])
    (check-eq? (state text) 'conflict text))
  (for ([text '("(print (lambda (x) x))" "(print (list (lambda (x) x)))"
                "(print (unwrap-ok (read-file \"path\")))")])
    (check-eq? (state text) 'unproved text)))

(test-case "actual wrapper analysis never reads program data, consumes input, writes, or prints factorial"
  (define directory (make-temporary-file "attalambda-static-io-~a" 'directory))
  (define data (build-path directory "data.txt"))
  (define marker (build-path directory "marker.txt"))
  (define attempts 0)
  (define guard
    (make-security-guard
     (current-security-guard)
     (lambda (who path modes)
       (when (and path (member (simplify-path (path->complete-path path) #f) (list data marker))
                  (or (memq 'read modes) (memq 'write modes)))
         (set! attempts (add1 attempts))
         (error 'observation "program data access")))
     (lambda args (error 'observation "unexpected network access"))))
  (dynamic-wind
   (lambda () (call-with-output-file data (lambda (out) (display "untouched" out))))
   (lambda ()
     (parameterize ([current-security-guard guard])
       (check-exn #rx"program data access" (lambda () (file->string data))))
     (check-equal? attempts 1)
     (set! attempts 0)
     (define input (open-input-string "answer\n"))
     (define output (open-output-string))
     (parameterize ([current-security-guard guard] [current-input-port input] [current-output-port output])
       (for ([text (list "(stdout \"marker\")" "(read-line UNIT)" "(print (some (list 1)))"
                         (format "(read-file ~s)" (path->string data))
                         (format "(write-file ~s (string-to-bytes \"marker\"))" (path->string marker))
                         "(def double x = (add x x))
                          (rec factorial n = (if (is-zero n) 1 (mult n (factorial (sub n 1)))))
                          (stdout (rat-to-string (factorial (double 3))))")])
         (check-eq? (state text) 'established text)))
     (check-equal? attempts 0)
     (check-equal? (file-position input) 0)
     (check-equal? (get-output-string output) "")
     (check-false (file-exists? marker))
     (check-equal? (file->string data) "untouched"))
   (lambda () (delete-directory/files directory))))
