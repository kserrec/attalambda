#lang racket/base

;; The only checking adapter that reads the requested source or emits output.
;; Private parameters support controlled tests, not CLI flags or environment
;; backdoors. Their defaults never evaluate or instantiate the user's module.
(require "../source-file.rkt" "../diagnostics.rkt" "frontend.rkt"
         "analysis.rkt" "coverage.rkt" "report.rkt")
(provide run-check current-check-prepare current-check-analyze)
(define current-check-prepare
  (make-parameter (lambda (source) (prepare-source source #:analysis? #t))))
(define current-check-analyze (make-parameter analyze-view))
(define (run-check source-name)
  (define (diagnose status issue)
    ;; A failed diagnostic sink must not change a failure into process success.
    (with-handlers ([(lambda (failure) #t) (lambda (failure) (void))])
      (display (format-source-problem source-name issue) (current-error-port))
      (flush-output (current-error-port)))
    status)
  (with-handlers
      ([exn:break? (lambda (failure)
                     (diagnose 130 (source-problem 'interrupted "static checking interrupted" #f #f)))]
       [(lambda (failure) #t)
        (lambda (failure)
          (diagnose 70 (source-problem 'internal "unexpected static checking or report-delivery failure" #f #f)))])
    (define owner (make-custodian))
    (dynamic-wind
     void
     (lambda ()
       (parameterize ([current-custodian owner])
         (define source (inspect-source-file source-name))
         (cond
           [(source-problem? source)
            (diagnose (if (eq? (source-problem-kind source) 'invalid) 65 66) source)]
           [else
            (define view ((current-check-prepare) source))
            (cond
              [(source-problem? view)
               (unless (eq? (source-problem-kind view) 'invalid)
                 (error 'static-command "unexpected frontend failure classification"))
               (diagnose 65 view)]
              [else
               (define summary (summarize-analysis ((current-check-analyze) view)))
               (define report (render-report summary source-name))
               (display report (current-output-port))
               (flush-output (current-output-port))
               ;; Custom output callbacks temporarily disable breaks. Deliver a
               ;; break queued during the final flush before returning success.
               (break-enabled #t)
               (case (check-summary-verdict summary) [(full) 0] [(fail) 1] [(partial) 2]
                 [else (error 'static-command "invalid completed verdict")])])])))
     (lambda () (custodian-shutdown-all owner)))))
