#lang racket/base
(require rackunit racket/file racket/port racket/string racket/runtime-path
         "../runner/static/command.rkt" "../runner/static/frontend.rkt"
         "../runner/static/analysis.rkt" "../runner/static/contracts.rkt"
         "../runner/source-file.rkt" "../lang/static-data.rkt")
(define-runtime-path facade "../lang/expander.rkt")
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
   (test-case "trusted expansion syntax failures do not impersonate source diagnostics"
     (define resolver (current-module-name-resolver))
     (for ([foreign? '(#t #f)])
       (define tripped? #f)
       (define result
         (parameterize
             ([current-module-name-resolver
               (lambda arguments
                 (when (equal? (car arguments) `(file ,(path->string (simplify-path facade #f))))
                   (set! tripped? #t)
                   (if foreign?
                       (raise-syntax-error
                        #f "private dependency expansion detail"
                        (datum->syntax #f 'private-library-binding
                                       '("/trusted/runtime/implementation.rkt" 99 7 200 23)))
                       (raise (exn:fail:syntax "private raw details" (current-continuation-marks) '()))))
                 (apply resolver arguments))])
           (run "#lang attalambda\n1")))
       (check-true tripped?)
       (check-equal? (car result) 70)
       (check-equal? (cadr result) "")
       (check-equal? (caddr result)
                     (format "AttaLambda: ~a: unexpected static checking or report-delivery failure\n" source))))

   (test-case "generated syntax keeps real source errors and source locations"
     (for ([row '(("missing" 0) ("(lambda () 1)" 0) ("(def unused = #t)" 14)
                  ("(def x = (def y = 1))" 10) ("(lambda (x) (def y = 1))" 12))])
       (define result (run (string-append "#lang attalambda\n" (car row))))
       (check-equal? (car result) 65 (car row))
       (check-equal? (cadr result) "")
       (check-true (string-contains? (caddr result) (format ":2:~a:" (cadr row))) (caddr result))
       (check-false (regexp-match? #rx"/lang/|/pkgs/|unknown AttaLambda name: (y|def|define)" (caddr result))))
     (for ([text '("(def unused = 1.5)" "(def unused = 1+2i)" "(def unused = #\\λ)"
                   "(def x = x)" "(def x = y) (def y = x)"
                   "(add (def y = 1) 2)" "(list (def y = 1))"
                   "(def x = 1) (def x = 2)" "(#%app add)"
                   "(#%datum . #t)" "(#%datum . #\\λ)")])
       (define result (run (string-append "#lang attalambda\n" text)))
       (check-equal? (car result) 65 text)
       (check-equal? (cadr result) ""))
     (define duplicate (run "#lang attalambda\n(def x = 1)\n(def x = 2)"))
     (check-equal? (caddr duplicate) (format "AttaLambda: ~a:3:5: duplicate definition: x\n" source)))

   (test-case "ordinary explicit syntax has the same checking verdicts"
     (for ([row '(("(#%app add 1 2)" 0)
                  ("(#%app . (add 1 2))" 0)
                  ("(def plus = add) (#%app (#%app plus 1) 2)" 0)
                  ("(#%app add 1 \"bad\")" 1)
                  ("(#%datum . 1) (#%datum . \"s\") (#%datum . #\\A)" 0)
                  ("(#%app head NIL)" 2)
                  ("(#%app stdout \"must-not-run\")" 0)
                  ("(#%datum . #t)" 65)
                  ("(#%datum . #\\λ)" 65)
                  ("(#%app add)" 65))])
       (define result (run (string-append "#lang attalambda\n" (car row))))
       (check-equal? (car result) (cadr row) (car row))
       (check-false (string-contains? (cadr result) "must-not-run"))
       (when (= (cadr row) 65) (check-equal? (cadr result) ""))))
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
