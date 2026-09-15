#lang racket/base

(require rackunit racket/port racket/runtime-path racket/tcp racket/list '#%expobs
         "../runner/source-reader.rkt" "../runner/session.rkt")

(define-runtime-path host-path "../runtime/host.rkt")
(define (host-inspect current expression)
  (parameterize ([current-namespace (session-namespace current)])
    (parameterize ([current-namespace (module->namespace host-path)])
      (eval expression))))
(define (listeners current)
  (host-inspect current '(map listener-entry-listener (hash-values handle-registry))))
(define (listener-closed? listener)
  (with-handlers ([exn:fail? (lambda (_) #t)])
    (call-with-values (lambda () (tcp-addresses listener #t)) (lambda _ #f))))

(define (with-lifetime procedure)
  (define owner (make-custodian))
  (define-values (input feed) (make-pipe))
  (define errors (open-output-bytes))
  (define calls 0)
  (define active-signal #f)
  (define output
    (make-output-port
     'observed-program-output always-evt
     (lambda (buffer start end non-block? enable-break?)
       (define size (- end start))
       (unless (zero? size)
         (set! calls (add1 calls))
         (when (and active-signal (= calls 2)) (semaphore-post active-signal)))
       size)
     void))
  (define current (open-session #:input input #:output output #:error errors))
  (dynamic-wind
   void
   (lambda ()
     (parameterize ([current-custodian owner])
       (procedure current input feed output errors
                  (lambda ()
                    (set! calls 0)
                    (set! active-signal (make-semaphore))
                    active-signal))))
   (lambda ()
     (custodian-shutdown-all owner)
     (close-session current)
     (close-input-port input)
     (close-output-port feed)
     (close-output-port output)
     (close-output-port errors))))

(define (submit current text [echo? #t])
  (define shown '())
  (evaluate-entry current (parse-source-buffer 'repl:lifetime text)
                  (if echo?
                      (lambda (value)
                        (set! shown (cons (render-result current value) shown)))
                      void))
  (reverse shown))

;; Only tests need workers/deadlines. The production evaluator stays on its
;; caller's break-aware thread. Observe actual work before sending a break.
(define (cancel-observed operation ready)
  (define answer (box #f))
  (define worker
    (thread (lambda ()
              (set-box! answer
                        (with-handlers ([(lambda (_) #t) values])
                          (operation)
                          'completed)))))
  (check-not-false (sync/timeout 5 ready) "work did not reach the observed phase")
  (break-thread worker)
  (check-not-false (sync/timeout 5 (thread-dead-evt worker)) "cancelled work kept running")
  (check-true (exn:break? (unbox answer))))

(test-case "expansion can be cancelled before publication and the old binding survives"
  (with-lifetime
   (lambda (current input feed output errors observe-output)
     (submit current "(def old = 41) old")
     (define committed (session-bindings current))
     (define expanding (make-semaphore))
     (cancel-observed
      (lambda ()
        (parameterize ([current-expand-observe
                        (lambda (event detail)
                          (when (eq? event 'start-top)
                            (semaphore-post expanding)
                            (sync never-evt)))])
          (submit current "(def unpublished = 8) (stdout \"unreached\")")))
      expanding)
     (check-eq? (session-bindings current) committed)
     (check-equal? (submit current "old") '("41")))))

(test-case "language exit preserves status and unwinds entry resources before the caller observes it"
  (for ([status '(0 1)])
    (with-lifetime
     (lambda (current input feed output errors observe-output)
       (submit current "(def old = 41) (def kept = (tcp-listen \"127.0.0.1\" 0 1)) kept")
       (define retained (car (listeners current)))
       (define committed (session-bindings current))
       (define request
         (with-handlers ([session-exit? values])
           (submit current
                   (format "(def unpublished = 9) (tcp-listen \"127.0.0.1\" 0 1) (exit ~a)" status))))
       (check-true (session-exit? request))
       (check-equal? (session-exit-status request) status)
       (check-eq? (session-bindings current) committed)
       (check-equal? (length (listeners current)) 2)
       (for ([listener (in-list (listeners current))])
         (check-equal? (listener-closed? listener) (not (eq? listener retained))))
       (check-false (port-closed? input))
       (check-false (port-closed? output))
       (check-false (port-closed? errors))
       (close-session current)
       (check-true (listener-closed? retained))))))

(test-case "running recursion and automatic rendering are cancellable without replay"
  (for ([source '("(rec spin n = (if (is-ok (stdout \"tick\")) (spin n) n)) (spin UNIT)"
                   "(rec raw n = (if (is-ok (stdout \"tick\")) (raw n) n)) raw")])
    (with-lifetime
     (lambda (current input feed output errors observe-output)
       (submit current "(def old = 41) old")
       (submit current "(def kept = (tcp-listen \"127.0.0.1\" 0 1)) kept")
       (define retained (car (listeners current)))
       (define committed (session-bindings current))
       (cancel-observed (lambda () (submit current source)) (observe-output))
       (check-eq? (session-bindings current) committed)
       (check-equal? (submit current "old") '("41"))
       (check-false (listener-closed? retained))
       (check-false (port-closed? input))
       (check-false (port-closed? output))
       (check-false (port-closed? errors))))))

(test-case "cancelled shared input retains its failure and fresh input consumes the next line"
  (with-lifetime
   (lambda (current input feed output errors observe-output)
     (submit current "(def old = 41) (def saved = (read-line UNIT)) old")
     (define committed (session-bindings current))
     (define consumed (port-progress-evt input))
     (write-bytes #"cancelled-prefix" feed)
     (cancel-observed (lambda () (submit current "(def unpublished = 1) saved")) consumed)
     (check-eq? (session-bindings current) committed)
     (write-bytes #"next-line\n" feed)
     (check-exn exn:break? (lambda () (submit current "saved")))
     (check-equal? (submit current "(read-line UNIT) old")
                   '("OK(SOME(\"next-line\"))" "41"))
     (check-false (sync/timeout 0 input)))))

(test-case "failed work closes only new resources, including delayed allocations"
  (with-lifetime
   (lambda (current input feed output errors observe-output)
     (submit current "(def old = 41) (def kept = (tcp-listen \"127.0.0.1\" 0 1)) kept")
     (define retained (car (listeners current)))
     (check-false (listener-closed? retained))
     (for ([failure-kind '(render break)])
       (define before (listeners current))
       (define committed (session-bindings current))
       (define created #f)
       (check-exn
        (if (eq? failure-kind 'break) exn:break? #rx"injected rendering failure")
        (lambda ()
          (evaluate-entry
           current
           (parse-source-buffer 'repl:resources
                                "(def unpublished = (tcp-listen \"127.0.0.1\" 0 1)) unpublished")
           (lambda (_)
             (set! created (findf (lambda (value) (not (memq value before)))
                                  (listeners current)))
             (check-false (listener-closed? created))
             (if (eq? failure-kind 'break)
                 (break-thread (current-thread))
                 (error 'fixture "injected rendering failure"))))))
       (check-eq? (session-bindings current) committed)
       (check-true (listener-closed? created))
       (check-false (listener-closed? retained)))
     (define before (listeners current))
     (submit current "(def deferred = (tcp-listen \"127.0.0.1\" 0 1))")
     (check-equal? (listeners current) before)
     (define delayed #f)
     (check-exn
      #rx"failed demand"
      (lambda ()
        (evaluate-entry current (parse-source-buffer 'repl:resources "deferred")
                        (lambda (_)
                          (set! delayed
                                (findf (lambda (value) (not (memq value before)))
                                       (listeners current)))
                          (error 'fixture "failed demand")))))
     (check-true (listener-closed? delayed))
     (define count-after (length (listeners current)))
     (submit current "deferred" #f)
     (check-equal? (length (listeners current)) count-after "no replay of the closed handle")
     (check-false (listener-closed? retained))
     (check-equal? (submit current "old") '("41"))
     (check-false (port-closed? input))
     (check-false (port-closed? output))
     (check-false (port-closed? errors))
     (close-session current)
     (check-true (listener-closed? retained))
     (check-false (port-closed? input))
     (check-false (port-closed? output))
     (check-false (port-closed? errors)))))

(test-case "a break after successful publication retains the committed resource"
  (with-lifetime
   (lambda (current input feed output errors observe-output)
     (check-exn exn:break?
                (lambda ()
                  (submit current "(def committed = (tcp-listen \"127.0.0.1\" 0 1)) committed")
                  (break-thread (current-thread))))
     (check-equal? (session-names current) '(committed))
     (define retained (car (listeners current)))
     (check-false (listener-closed? retained))
     (close-session current)
     (check-true (listener-closed? retained)))))

(test-case "reset replaces namespace, names and host registry while preserving original ports"
  (with-lifetime
   (lambda (current input feed output errors observe-output)
     (submit current "(def old = 41) (def kept = (tcp-listen \"127.0.0.1\" 0 1)) kept")
     (define namespace (session-namespace current))
     (define owner (session-custodian current))
     (define retained (car (listeners current)))
     (define port (cadr (call-with-values (lambda () (tcp-addresses retained #t)) list)))
     (reset-session! current)
     (check-not-eq? (session-namespace current) namespace)
     (check-not-eq? (session-custodian current) owner)
     (check-equal? (session-names current) '())
     (check-equal? (host-inspect current '(hash-count handle-registry)) 0)
     (check-true (listener-closed? retained))
     (check-exn exn:fail:syntax? (lambda () (submit current "old")))
     (define rebound (tcp-listen port 1 #t "127.0.0.1"))
     (tcp-close rebound)
     (write-bytes #"after-reset\n" feed)
     (check-equal? (submit current "(read-line UNIT)") '("OK(SOME(\"after-reset\"))"))
     (submit current "(tcp-listen \"127.0.0.1\" 0 1)")
     (check-false (listener-closed? (car (listeners current))))
     (check-eq? (session-input current) input)
     (check-eq? (session-output current) output)
     (check-eq? (session-error current) errors)
     (check-false (port-closed? input))
     (check-false (port-closed? output))
     (check-false (port-closed? errors)))))

(test-case "cancelling replacement initialization keeps the original session usable"
  (with-lifetime
   (lambda (current input feed output errors observe-output)
     (submit current "(def old = 41) (def kept = (tcp-listen \"127.0.0.1\" 0 1)) kept")
     (define namespace (session-namespace current))
     (define retained (car (listeners current)))
     (define initializing (make-semaphore))
     (define original-resolver (current-module-name-resolver))
     (cancel-observed
      (lambda ()
        (parameterize ([current-module-name-resolver
                        (case-lambda
                          [(path relative syntax load?)
                           (when (equal? path '(quote #%kernel))
                             (semaphore-post initializing)
                             (sync never-evt))
                           (original-resolver path relative syntax load?)]
                          [(path namespace) (original-resolver path namespace)])])
          (reset-session! current)))
      initializing)
     (check-eq? (session-namespace current) namespace)
     (check-false (listener-closed? retained))
     (check-equal? (submit current "old") '("41")))))
