#lang racket/base

(require rackunit racket/string
         "../runner/diagnostics.rkt" "../runner/source-file.rkt"
         "../runner/source-reader.rkt" "../runner/session.rkt")

(define (capture action)
  (with-handlers ([exn:fail? values]) (action)))

(test-case "real expansion diagnostics preserve only matching submitted source locations"
  (define current (open-session))
  (dynamic-wind
   void
   (lambda ()
     (for ([example '(("unknown-name" "unknown AttaLambda name: unknown-name" 0)
                      ("#t" "unsupported literal" 0)
                      ("(def loop x = (loop x))" "use rec for self recursion" 5)
                      ("(def first = second) (def second = first)" "only self recursion" 5)
                      ("(lambda () 1)" "source has invalid syntax" 0))])
       (define failure
         (capture (lambda ()
                    (prepare-entry current (parse-source-buffer 'repl:19 (car example)
                                                                 #:line 3 #:column 0)))))
       (check-true (exn:fail:syntax? failure))
       (define problem (failure->source-problem failure 'expand 'repl:19))
       (check-true (string-contains? (source-problem-reason problem) (cadr example)))
       (check-equal? (source-problem-line problem) 3)
       (check-equal? (source-problem-column problem) (caddr example))
       (check-true (string-prefix? (format-source-problem 'repl:19 problem)
                                   (format "AttaLambda: repl:19:3:~a: source expansion failed:" (caddr example))))
       (define unmatched (failure->source-problem failure 'expand 'repl:20))
       (check-equal? (source-problem-reason unmatched) "source expansion failed: source has invalid syntax")
       (check-false (source-problem-line unmatched))))
   (lambda () (close-session current))))

(test-case "read diagnostics use expected file locations and structured validation passes through"
  (define input (open-input-string "\n("))
  (port-count-lines! input)
  (define failure (capture (lambda () (read-syntax (string->path "./with spaces.attl") input))))
  (close-input-port input)
  (define problem (failure->source-problem failure 'read "./with spaces.attl"))
  (check-equal? (source-problem-line problem) 2)
  (check-equal? (source-problem-column problem) 0)
  (check-false (source-problem-line (failure->source-problem failure 'read "different.attl")))
  (define missing (source-problem 'unavailable "source file was not found" #f #f))
  (check-eq? (failure->source-problem missing 'evaluate) missing)
  (check-equal? (format-source-problem "missing.attl" missing)
                "AttaLambda: missing.attl: source file was not found\n"))

(test-case "operation phase outranks native exception subtype and raw internals never appear"
  (define raw "secret-looking /private/native-installation/runtime.rkt #<procedure:privileged>")
  (define native (exn:fail raw (current-continuation-marks)))
  (define syntax-failure
    (exn:fail:syntax raw (current-continuation-marks)
                     (list (datum->syntax #f 'native-name
                                         (list "/private/runtime.rkt" 999 99 1 1)))))
  (for ([failure (list native syntax-failure)]
        [ignored '(1 2)])
    (for ([phase '(evaluate render expand read)])
      (define shown (format-source-problem 'repl:2 (failure->source-problem failure phase 'repl:2)))
      (check-false (regexp-match? #rx"secret-looking|private|native-name|privileged|999|#<procedure" shown))))
  (check-equal? (source-problem-reason (failure->source-problem syntax-failure 'render))
                "automatic result rendering failed")
  (check-equal? (source-problem-reason (failure->source-problem native 'evaluate))
                "evaluation failed in the underlying runtime"))

(test-case "interactive diagnostics escape controls and bound dynamic names and paths"
  (define current (open-session))
  (dynamic-wind
   void
   (lambda ()
     (for ([name (list "line\n\u001b[31m\u0085\u202econtrol" (make-string 10000 #\x))])
       (define form (datum->syntax #f (string->symbol name) (list 'repl:3 1 0 1 1)))
       (define parsed (source-buffer 'complete name (list form) #f #f #f))
       (define failure (capture (lambda () (prepare-entry current parsed))))
       (define shown
         (format-source-problem (string-append name ".attl")
                                (failure->source-problem failure 'expand 'repl:3)))
       (check-true (< (string-length shown) 4000))
       (check-equal? (length (regexp-match* #rx"\n" shown)) 1)
       (check-false (regexp-match? #rx"[\u001b\u0085\u202e]" shown))))
   (lambda () (close-session current))))

(test-case "opt-in render diagnostics unwind publication after effects and preserve control flow"
  (define output (open-output-bytes))
  (define current (open-session #:output output))
  (dynamic-wind
   void
   (lambda ()
     (evaluate-entry current (parse-source-buffer 'repl:1 "(def old = 7)"))
     (define committed (session-bindings current))
     (define failure
       (with-handlers ([source-problem? values])
         (evaluate-entry
          current (parse-source-buffer 'repl:2 "(def old = 99) (def ghost = 1) (stdout \"once\")")
          (lambda (value)
            (call-with-render-diagnostics
             (lambda ()
               (check-equal? (render-result current value) "OK(UNIT)")
               (raise-syntax-error 'native "secret underlying detail")))))))
     (check-equal? (source-problem-reason failure) "automatic result rendering failed")
     (check-eq? (session-bindings current) committed)
     (check-equal? (get-output-bytes output) #"once")
     (define requested (session-exit 1))
     (check-eq? (with-handlers ([session-exit? values])
                  (call-with-render-diagnostics (lambda () (raise requested)))) requested)
     (check-exn exn:break?
                (lambda ()
                  (call-with-render-diagnostics
                   (lambda () (break-thread (current-thread)) (sleep 0))))))
   (lambda () (close-session current) (close-output-port output))))
