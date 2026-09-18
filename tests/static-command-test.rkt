#lang racket/base
(require rackunit racket/file racket/port racket/string
         "../runner/static/command.rkt" "../runner/static/frontend.rkt"
         "../runner/static/analysis.rkt" "../runner/static/contracts.rkt"
         "../runner/source-file.rkt" "../lang/static-data.rkt")
(define directory (make-temporary-file "attalambda-static-command-~a" 'directory))
(define source (build-path directory "input.attl"))
(define (write-source text)
  (call-with-output-file source #:exists 'truncate
    (lambda (out) (display text out))))
(define (run text)
  (write-source text)
  (define out (open-output-string))
  (define err (open-output-string))
  (define status
    (parameterize ([current-output-port out] [current-error-port err])
      (run-check (path->string source))))
  (list status (get-output-string out) (get-output-string err)))
(dynamic-wind
 void
 (lambda ()
   (test-case "one source snapshot yields exact verdicts without evaluating its contents"
     (for ([row '(("(def id x = x) (id 1)" 0 "FULL PASS")
                  ("(add 1 \"bad\")" 1 "FAIL")
                  ("(head NIL)" 2 "PARTIAL")
                  ("(stdout \"must-not-run\")" 0 "FULL PASS")
                  ("(rec loop = loop) loop" 0 "FULL PASS"))])
       (define result (run (string-append "#lang attalambda\n" (car row))))
       (check-equal? (car result) (cadr row))
       (check-true (string-prefix? (cadr result) (string-append "Static type check: " (caddr row))))
       (check-false (string-contains? (cadr result) "must-not-run"))
       (check-equal? (caddr result) ""))
     (parameterize ([current-check-prepare
                     (lambda (snapshot)
                       (write-source "invalid replacement")
                       (prepare-source snapshot #:analysis? #t))])
       (define result (run "#lang attalambda\n(def original = 1)"))
       (check-equal? (car result) 0)
       (check-regexp-match #rx"original : Rat" (cadr result))))

   (test-case "source failures and internal failures remain distinct and safe"
     (for ([text '("bad header" "#lang attalambda\n(stdout \"prefix\") missing"
                   "#lang attalambda\n(stdout \"prefix\") (" "#lang attalambda\n(def f x = (f x))")])
       (define result (run text))
       (check-equal? (car result) 65)
       (check-equal? (cadr result) "")
       (check-regexp-match #rx"AttaLambda:" (caddr result)))
     (for ([analyzer
            (list (lambda (view) (error 'private "secret internal details"))
                  (lambda (view) (raise (exn:fail:syntax "secret syntax details" (current-continuation-marks) '())))
                  (lambda (view) (raise (exn:fail:filesystem "secret filesystem details" (current-continuation-marks))))
                  (lambda (view)
                    (validate-catalog (cons (struct-copy library-contract (car catalog) [status 'pending]) (cdr catalog))))
                  (lambda (view)
                    (define result (analyze-view view))
                    (struct-copy analysis result [nodes (hasheqv)])))])
       (parameterize ([current-check-analyze analyzer])
         (define result (run "#lang attalambda\n1"))
         (check-equal? (car result) 70)
         (check-equal? (cadr result) "")
         (check-equal? (caddr result)
                       (format "AttaLambda: ~a: unexpected static checking or report-delivery failure\n" source))))
     (parameterize ([current-check-prepare (lambda (snapshot) #f)])
       (check-equal? (car (run "#lang attalambda\n1")) 70))
     ;; These dotenv-spelled paths are never created or inspected.
     (define err (open-output-string))
     (parameterize ([current-error-port err])
       (check-equal? (run-check (path->string (build-path directory "missing.attl"))) 66)
       (check-equal? (run-check (path->string (build-path directory "service.env.attl"))) 66)))

   (test-case "owned resources close after internal failure while caller ports remain usable"
     (define owned #f)
     (define input (open-input-string "answer\n"))
     (define output (open-output-string))
     (define error-port (open-output-string))
     (write-source "#lang attalambda\n1")
     (parameterize ([current-input-port input] [current-output-port output] [current-error-port error-port]
                    [current-check-analyze
                     (lambda (view)
                       (set! owned (thread (lambda () (sync never-evt))))
                       (error 'private "resource failure"))])
       (check-equal? (run-check (path->string source)) 70))
     (check-true (thread-dead? owned))
     (check-false (port-closed? input))
     (check-false (port-closed? output))
     (check-false (port-closed? error-port))
     (check-equal? (file-position input) 0))

   (test-case "report write and flush failures return 70 without replay or fabricated success"
     (for ([fail-flush? '(#f #t)])
       (write-source "#lang attalambda\n1")
       (define collected (open-output-bytes))
       (define failures 0)
       (define output
         (make-output-port
          'broken-report always-evt
          (lambda (buffer start end non-block? breakable?)
            (cond [(or (not fail-flush?) (= start end))
                   (set! failures (add1 failures)) (error 'private "secret sink failure")]
                  [else (write-bytes buffer collected start end) (- end start)])) void))
       (define err (open-output-string))
       (define status
         (parameterize ([current-output-port output] [current-error-port err])
           (run-check (path->string source))))
       (check-equal? status 70)
       (check-equal? failures 1)
       (check-false (port-closed? output))
       (check-equal? (length (regexp-match* #rx#"Static type check: FULL PASS" (get-output-bytes collected)))
                     (if fail-flush? 1 0))
       (check-false (string-contains? (get-output-string err) "secret")))))
 (lambda () (delete-directory/files directory)))
