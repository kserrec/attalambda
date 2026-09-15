#lang racket/base

;; A separate process allows the parent to inspect live fd1/fd2 destinations.
(require "../../runner/editor-output.rkt")
(define original (current-output-port))
(define mode (vector-ref (current-command-line-arguments) 0))
(define flushes 0)
(define outcome 'returned)
(define before (length (directory-list "/proc/self/fd")))
(define custom
  (make-output-port
   'controlled-flush always-evt
   (lambda (bytes start end nonblocking? breakable?)
     (cond
       [(= start end)
        (set! flushes (add1 flushes))
        (when (or (and (equal? mode "before") (= flushes 1))
                  (and (member mode '("after" "both" "break-after")) (= flushes 2)))
          (error 'probe "FLUSH-FAILURE"))
        0]
       [else (write-bytes bytes original start end)]))
   void))
(displayln "before" original)
(flush-output original)
(dynamic-wind
 void
 (lambda ()
   (with-handlers ([(lambda (_) #t)
                    (lambda (failure)
                      (set! outcome (if (exn? failure) (exn-message failure) failure)))])
     (parameterize ([current-output-port custom])
       (call-with-editor-output
        (lambda ()
          (displayln "editor-text" original)
          (flush-output original)
          (cond
            [(member mode '("action" "both")) (error 'probe "ACTION-FAILURE")]
            [(member mode '("break" "break-after"))
             (break-thread (current-thread))
             (break-enabled #t)])))))
   (displayln "after" original)
   (flush-output original)
   (eprintf "REPORT ~s\n"
            (list mode outcome flushes before (length (directory-list "/proc/self/fd")))))
 (lambda () (close-output-port custom)))
(flush-output (current-error-port))
(void (read-line))
