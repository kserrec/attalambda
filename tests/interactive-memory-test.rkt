#lang racket/base

(require rackunit racket/list
         "../runner/source-reader.rkt" "../runner/session.rkt")

(define (collect)
  (for ([iteration (in-range 3)]) (collect-garbage 'major)))

(define (descriptor-count)
  (and (eq? (system-type 'os*) 'linux)
       (length (directory-list "/proc/self/fd"))))

(define (owned-process-resources owner parent)
  (append-map
   (lambda (resource)
     (cond [(custodian? resource) (owned-process-resources resource parent)]
           [(or (thread? resource) (input-port? resource) (output-port? resource))
            (list resource)]
           [else '()]))
   (custodian-managed-list owner parent)))

(test-case "three 200-entry sessions release state on reset without worker or port growth"
  (define parent (make-custodian))
  (define input (open-input-bytes #""))
  (define output (open-output-bytes))
  (define errors (open-output-bytes))
  (define current
    (parameterize ([current-custodian parent])
      (open-session #:input input #:output output #:error errors)))
  (define (submit source)
    (evaluate-entry current (parse-source-buffer 'repl:measurement source)
                    (lambda (value) (render-result current value) (void))))
  (dynamic-wind
   void
   (lambda ()
     ;; Warm shared code before measuring the repeated workload. Results/source
     ;; strings are not retained by the test, and output is empty throughout.
     (submit "(def stable = 1) (add stable 1)")
     (collect)
     (define initial-descriptors (descriptor-count))
     (printf "interactive baseline: memory=~a bytes descriptors=~a\n"
             (current-memory-use) initial-descriptors)
     (for ([cycle (in-range 3)])
       (when (positive? cycle) (submit "(def stable = 1) (add stable 1)"))
       (collect)
       (define before (current-memory-use))
       (define started (current-inexact-monotonic-milliseconds))
       (for ([index (in-range 200)])
         (case (modulo index 3)
           [(0) (submit (format "(def value-~a = ~a)" index index))]
           [(1) (submit "(add stable 1)")]
           [(2) (check-exn exn:fail:syntax?
                           (lambda () (submit (format "(def rejected-~a = unknown)" index))))]))
       (define elapsed (- (current-inexact-monotonic-milliseconds) started))
       (collect)
       (define retained (current-memory-use))
       (check-equal? (length (session-names current)) 68)
       (check-equal? (owned-process-resources (session-custodian current) parent) '())
       (define old-namespace (make-weak-box (session-namespace current)))
       (define old-bindings (make-weak-box (session-bindings current)))
       (parameterize ([current-custodian parent]) (reset-session! current))
       (collect)
       (check-false (weak-box-value old-namespace) "old namespace is still retained after reset")
       (check-false (weak-box-value old-bindings) "old visible-name table is still retained after reset")
       (check-equal? (owned-process-resources (session-custodian current) parent) '())
       (check-equal? (descriptor-count) initial-descriptors)
       (printf "interactive cycle ~a: entries=200 elapsed-ms=~a before=~a retained=~a reset=~a descriptors=~a\n"
               (add1 cycle) elapsed before retained (current-memory-use) (descriptor-count)))
     (define last-namespace (make-weak-box (session-namespace current)))
     (close-session current)
     (collect)
     (check-false (weak-box-value last-namespace))
     (check-equal? (get-output-bytes output) #"")
     (check-false (port-closed? input))
     (check-false (port-closed? output))
     (check-false (port-closed? errors)))
   (lambda ()
     (close-session current)
     (custodian-shutdown-all parent)
     (close-input-port input)
     (close-output-port output)
     (close-output-port errors))))
