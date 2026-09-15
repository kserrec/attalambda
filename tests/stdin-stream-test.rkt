#lang racket/base

(require rackunit
         racket/list
         racket/port
         "../core/objects.rkt"
         "../core/option.rkt"
         "../core/result.rkt"
         "../core/unit.rkt"
         "../effects/stdin.rkt"
         "../readers/bool.rkt"
         "../runtime/codec.rkt"
         "../runtime/host.rkt"
         "helpers/lazy.rkt")

(define read-with-host (lazy-apply make-read-line host))

(define (read-observation input)
  (define result
    (parameterize ([current-input-port input])
      (lazy-force (lazy-apply read-with-host UNIT))))
  (unless (bool->boolean (lazy-apply is-ok result))
    (error 'stdin-stream "expected a successful read"))
  (define option (lazy-force (lazy-apply unwrap-ok result)))
  (if (eq? option (lazy-force NONE))
      'eof
      (object-string->bytes
       (lazy-apply raw-option-value (lazy-apply raw-object-value option)))))

;; Every read has a deadline, including reads after the initial line. The
;; finalizer closes the pipe explicitly and uses a custodian to kill workers
;; even when an assertion fails; pipe ports are not managed by custodians.
(define (start-read input)
  (define answer (make-channel))
  (thread
   (lambda ()
     (channel-put answer
                  (with-handlers ([exn? values])
                    (read-observation input)))))
  answer)

(define (await-read answer)
  (define result (sync/timeout 5 answer))
  (unless result (error 'stdin-stream "read did not complete within 5 seconds"))
  (when (exn? result) (raise result))
  result)

(define (call-with-input-pipe procedure)
  (define owner (make-custodian))
  (define-values (input output) (make-pipe))
  (dynamic-wind
    void
    (lambda ()
      (parameterize ([current-custodian owner])
        (procedure input output)))
    (lambda ()
      (custodian-shutdown-all owner)
      (unless (port-closed? input) (close-input-port input))
      (unless (port-closed? output) (close-output-port output)))))

(define (check-stream initial suffix waits? first-line remaining-lines)
  (call-with-input-pipe
   (lambda (input output)
     (define consumed (port-progress-evt input))
     (write-bytes initial output)
     (flush-output output)
     (define answer (start-read input))
     ;; Observe real input consumption before testing the wait, so a
     ;; worker that has not started cannot satisfy the negative check.
     (check-not-false (sync/timeout 5 consumed) "reader did not consume input")
     (define (send-suffix)
       (if (eq? suffix 'eof)
           (close-output-port output)
           (begin
             (write-bytes suffix output)
             (flush-output output))))
     (cond
       [waits?
        (check-false (sync/timeout 0.1 answer)
                     "read completed before its delayed suffix arrived")
        (send-suffix)
        (check-equal? (await-read answer) first-line)]
       [else
        ;; LF and complete CRLF must finish while the writer stays open,
        ;; before any bytes from the next line have been supplied.
        (check-equal? (await-read answer) first-line)
        (send-suffix)])
     (unless (eq? suffix 'eof)
       (check-false (port-closed? output))
       (close-output-port output))
     (for ([expected (in-list (append remaining-lines '(eof eof)))])
       (check-equal? (await-read (start-read input)) expected))
     (check-false (port-closed? input)))))

;; Exercise the native newline rules for both empty and nonempty lines.
;; In particular, a delayed LF must not become an extra empty line, while a
;; second CR must remain a distinct separator and yield an empty next line.
(for* ([prefix (in-list (list #"" #"first"))]
       [entry (in-list
               (list (list "LF" #"\n" #"next\n" #f (list #"next"))
                     (list "complete CRLF" #"\r\n" #"next\n" #f (list #"next"))
                     (list "CR then LF" #"\r" #"\nnext\n" #t (list #"next"))
                     (list "CR then ordinary byte" #"\r" #"next\n" #t (list #"next"))
                     (list "CR then CR" #"\r" #"\rnext\n" #t (list #"" #"next"))
                     (list "CR then EOF" #"\r" 'eof #t '())))])
  (test-case (format "~a after ~s" (first entry) prefix)
    (check-stream (bytes-append prefix (second entry))
                  (third entry) (fourth entry) prefix (fifth entry))))

;; Partial lines stay pending too; EOF still returns a final unterminated
;; line once, without conflating it with absence on subsequent reads.
(for ([suffix (in-list (list #"\nnext\n" 'eof))])
  (test-case (format "partial line then ~s" suffix)
    (check-stream #"partial" suffix #t #"partial"
                  (if (eq? suffix 'eof) '() (list #"next")))))

;; Pin cleanup on the failure path itself, including a worker waiting for
;; input that will never arrive. Custodian shutdown alone leaves pipes open.
(test-case "failed case closes both pipe ports and stops its reader"
  (define captured-input #f)
  (define captured-output #f)
  (define reader #f)
  (define started (make-semaphore))
  (define failure (exn:fail "deliberate test interruption" (current-continuation-marks)))
  (check-exn
   (lambda (raised) (eq? raised failure))
   (lambda ()
     (call-with-input-pipe
      (lambda (input output)
        (set! captured-input input)
        (set! captured-output output)
        (set! reader
              (thread (lambda ()
                        (semaphore-post started)
                        (read-observation input))))
        (unless (sync/timeout 5 started)
          (error 'stdin-stream "cleanup probe reader did not start"))
        (raise failure)))))
  (check-true (thread-dead? reader))
  (check-true (port-closed? captured-input))
  (check-true (port-closed? captured-output)))
