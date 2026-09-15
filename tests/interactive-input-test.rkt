#lang racket/base

(require rackunit racket/port
         "../runner/source-reader.rkt" "../runner/session.rkt")

;; Pipes and the controller belong to the test, never to an entry. Close both
;; pipe endpoints explicitly even when an assertion or worker fails.
(define (with-input procedure)
  (define owner (make-custodian))
  (define-values (input feed) (make-pipe))
  (define output (open-output-bytes))
  (define errors (open-output-bytes))
  (define current (open-session #:input input #:output output #:error errors))
  (dynamic-wind
   void
   (lambda ()
     (parameterize ([current-custodian owner])
       (procedure current input feed output errors)))
   (lambda ()
     (custodian-shutdown-all owner)
     (close-session current)
     (close-input-port input)
     (close-output-port feed)
     (close-output-port output)
     (close-output-port errors))))

(define (submit current source)
  (define shown '())
  (evaluate-entry current (parse-source-buffer 'repl:input source)
                  (lambda (value)
                    (set! shown (cons (render-result current value) shown))))
  (reverse shown))

(define (start-work thunk)
  (define answer (make-channel))
  (define worker
    (thread (lambda ()
              (channel-put answer (with-handlers ([exn? values]) (thunk))))))
  (values worker answer))

(define (await-work worker answer)
  (define result (sync/timeout 5 answer))
  (check-not-false result "entry did not finish within the test deadline")
  (check-not-false (sync/timeout 5 (thread-dead-evt worker)))
  (when (exn? result) (raise result))
  result)

(define (bounded-work thunk)
  (define-values (worker answer) (start-work thunk))
  (await-work worker answer))

(test-case "entry execution uses the captured process ports, never a parsing port"
  (with-input
   (lambda (current input feed output errors)
     (write-bytes #"actual-answer\n" feed)
     (define temporary (open-input-string "source-buffer-is-not-an-answer"))
     (define wrong-output (open-output-bytes))
     (dynamic-wind
      void
      (lambda ()
        (parameterize ([current-input-port temporary]
                       [current-output-port wrong-output]
                       [current-error-port wrong-output])
          (check-equal? (submit current "(read-line UNIT) (stdout \"actual-output\")")
                        '("OK(SOME(\"actual-answer\"))" "OK(UNIT)"))
          (evaluate-entry current (parse-source-buffer 'repl:ports "UNIT")
                          (lambda (_)
                            (check-eq? (current-input-port) input)
                            (check-eq? (current-output-port) output)
                            (check-eq? (current-error-port) errors))))
        (check-equal? (file-position temporary) 0)
        (check-equal? (get-output-bytes output) #"actual-output")
        (check-equal? (get-output-bytes wrong-output) #""))
      (lambda () (close-input-port temporary) (close-output-port wrong-output))))))

(test-case "source, partial live answer and following source share one incremental stream"
  (for ([ending '(#"\n" #"\r\n")])
    (with-input
     (lambda (current input feed output errors)
       (define accepted (make-semaphore))
       (write-bytes (bytes-append #"(read-line UNIT)" ending) feed)
       (define-values (worker answer)
         (start-work
          (lambda ()
            (define parsed (read-source-entry input 'repl:1))
            (semaphore-post accepted)
            (define shown '())
            (evaluate-entry current parsed
                            (lambda (value)
                              (set! shown (cons (render-result current value) shown))))
            (define following (read-source-entry input 'repl:2))
            (list shown (source-buffer-text following)))))
       (check-not-false (sync/timeout 5 accepted))
       (define consumed (port-progress-evt input))
       (write-bytes #"partial" feed)
       (check-not-false (sync/timeout 5 consumed))
       (check-false (sync/timeout 0.1 answer) "partial answer must stay pending")
       (write-bytes #"-answer\n(add 2 3)\n" feed)
       (check-equal? (await-work worker answer)
                     '(("OK(SOME(\"partial-answer\"))") "(add 2 3)\n"))
       (check-false (port-closed? feed))
       (check-false (sync/timeout 0 input))))))

(test-case "saved input is lazy and shared, while function calls read fresh answers"
  (with-input
   (lambda (current input feed output errors)
     (check-equal?
      (bounded-work
       (lambda ()
         (submit current "(def saved = (read-line UNIT)) (def ask u = (read-line u))")
         (session-names current)))
      '(ask saved))
     (check-equal? (bounded-work (lambda () (submit current "(if TRUE 7 saved)"))) '("7"))
     (write-bytes #"first\nsecond\nthird\n" feed)
     (check-equal? (bounded-work (lambda () (submit current "saved saved")))
                   '("OK(SOME(\"first\"))" "OK(SOME(\"first\"))"))
     (check-equal? (bounded-work (lambda () (submit current "(ask UNIT) (ask UNIT) saved")))
                   '("OK(SOME(\"second\"))" "OK(SOME(\"third\"))" "OK(SOME(\"first\"))"))
     (check-false (sync/timeout 0 input))
     (check-equal? (get-output-bytes output) #""))))
