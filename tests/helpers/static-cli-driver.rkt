#lang racket/base
;; Test-only fault injection around the REAL auto-running launcher. No fault
;; selector enters the product's CLI, environment, or dependency graph.
(require racket/runtime-path racket/path "../../runner/static/command.rkt"
         "../../runner/static/frontend.rkt" "../../runner/static/analysis.rkt"
         "../../runner/static/contracts.rkt" "../../lang/static-data.rkt")
(define-runtime-path launcher "../../runner/attalambda.rkt")
(define arguments (vector->list (current-command-line-arguments)))
(define mode (car arguments))
(define source (cadr arguments))
(define original-prepare (current-check-prepare))
(define original-analyze (current-check-analyze))
(define real-output (current-output-port))
(define native-exit (exit-handler))
(define owned #f)
(define observed-input (open-input-string "answer remains unread\n"))
(define data-path (build-path (path-only (string->path source)) "program-data.bin"))
(define data-accesses 0)
(define observed-guard
  (make-security-guard
   (current-security-guard)
   (lambda (who path modes)
     (when (and path (equal? (simplify-path (path->complete-path path) #f) data-path)
                (or (memq 'read modes) (memq 'write modes)))
       (set! data-accesses (add1 data-accesses))
       (error 'observation "program data access")))
   (lambda args (void))))
(when (equal? mode "observe-input-data")
  (parameterize ([current-security-guard observed-guard])
    (with-handlers ([exn:fail? void]) (call-with-input-file data-path void)))
  (unless (= data-accesses 1) (error 'test "data observer positive control failed"))
  (set! data-accesses 0))
(define adapter-output
  (if (member mode '("write-failure" "flush-failure" "interrupt-flush"))
      (make-output-port
       'report-fault always-evt
       (lambda (buffer start end non-block? breakable?)
         (cond [(equal? mode "write-failure") (error 'injected "private output detail")]
               [(= start end)
                (if (equal? mode "flush-failure") (error 'injected "private flush detail")
                    (begin (break-thread (current-thread)) 0))]
               [else (write-bytes buffer real-output start end) (- end start)])) void)
      real-output))
(parameterize
    ([current-command-line-arguments (vector "--check" source)]
     [current-output-port adapter-output]
     [current-input-port (if (equal? mode "observe-input-data") observed-input (current-input-port))]
     [current-security-guard (if (equal? mode "observe-input-data") observed-guard (current-security-guard))]
     [exit-handler (lambda (status)
                     (when (equal? mode "observe-input-data")
                       (unless (and (= (file-position observed-input) 0) (= data-accesses 0))
                         (error 'test "program input or data was accessed"))
                       (display "program-input-and-data-untouched\n" (current-error-port)))
                     (when owned
                       (unless (thread-dead? owned) (error 'test "owned resource survived"))
                       (display "owned-resource-closed\n" (current-error-port))
                       (flush-output (current-error-port)))
                     (native-exit status))]
     [current-check-prepare
      (lambda (snapshot)
        (define view (original-prepare snapshot))
        (if (equal? mode "missing-id") (struct-copy source-view view [registry '()]) view))]
     [current-check-analyze
      (lambda (view system)
        (cond
          [(equal? mode "internal") (error 'injected "private internal detail")]
          [(equal? mode "syntax") (raise (exn:fail:syntax "private syntax detail" (current-continuation-marks) '()))]
          [(equal? mode "filesystem") (raise (exn:fail:filesystem "private filesystem detail" (current-continuation-marks)))]
          [(equal? mode "pending-catalog")
           (validate-catalog (cons (struct-copy library-contract (car catalog) [status 'pending]) (cdr catalog)))]
          [(equal? mode "missing-state")
           (struct-copy analysis (original-analyze view system) [nodes (hasheqv)])]
          [(equal? mode "interrupt-analysis")
           (set! owned (thread (lambda () (sync never-evt))))
           (display "analysis-ready\n" (current-error-port))
           (flush-output (current-error-port))
           (sync never-evt)]
          [else (original-analyze view system)]))])
  (dynamic-require launcher #f))
