#lang racket/base

;; Trusted fault ports test shell failures independently of language Err values.
(require rackunit racket/port racket/file '#%expobs "../runner/repl.rkt")

(define (bounded action)
  (define owner (make-custodian))
  (define ports '())
  (define (own port) (set! ports (cons port ports)) port)
  (dynamic-wind
   void
   (lambda ()
     (define result (make-channel))
     (parameterize ([current-custodian owner])
       (thread (lambda ()
                 (channel-put result (with-handlers ([exn? values]) (action own))))))
     (define value (sync/timeout 20 result))
     (unless value (error 'controller-test "controller failed to return"))
     (when (exn? value) (raise value))
     (void))
   (lambda ()
     (custodian-shutdown-all owner)
     (for ([port (in-list ports)] #:unless (port-closed? port))
       (if (input-port? port) (close-input-port port) (close-output-port port))))))

(define (owned-pipe own)
  (define-values (input output) (make-pipe))
  (values (own input) (own output)))

(test-case "transcript and no-history modes never access the history directory"
  (define target (path->string (build-path (find-system-path 'pref-dir) "attalambda")))
  (for ([interactive? '(#f #t)])
    (bounded
     (lambda (own)
       (define accesses '())
       (define guard
         (make-security-guard
          (current-security-guard)
          (lambda (who path permissions)
            (when (and path (regexp-match? (regexp (regexp-quote target)) (path->string path)))
              (set! accesses (cons (list who path permissions) accesses))
              (error 'test "history access forbidden")))
          (lambda args (void))))
       (define output (own (open-output-bytes)))
       (define status
         (parameterize ([current-security-guard guard]
                        [current-input-port (own (open-input-string "(add 2 3)\n:quit\n"))]
                        [current-output-port output]
                        [current-error-port (own (open-output-bytes))])
           (run-repl "test" interactive? #:history? (not interactive?))))
       (check-equal? status 0)
       (check-equal? (get-output-bytes output) #"=> 5\n")
       (check-equal? accesses '())
       status))))

(test-case "the history byte limit does not reject a larger executable source entry"
  (bounded
   (lambda (own)
     (define output (own (open-output-bytes)))
     (define source (string-append "#|" (make-string 1048577 #\x) "|# (add 20 1)\n:quit\n"))
     (define status
       (parameterize ([current-input-port (own (open-input-string source))]
                      [current-output-port output]
                      [current-error-port (own (open-output-bytes))])
         (run-repl "test" #t #:history? #f)))
     (check-equal? status 0)
     (check-equal? (get-output-bytes output) #"=> 21\n")
     status)))

(test-case "a permanent source-stream failure terminates after one read with sanitized status70"
  (bounded
   (lambda (own)
     (define reads 0)
     (define source
       (own (make-input-port 'failed-source
                        (lambda (_)
                          (set! reads (add1 reads))
                          (error 'private "/native/secret.rkt: injected source failure"))
                        #f void)))
     (define messages (own (open-output-bytes)))
     (define status
       (parameterize ([current-input-port source]
                      [current-output-port (own (open-output-bytes))]
                      [current-error-port messages])
         (run-repl "test" #f #:history? #f)))
     (check-equal? status 70)
     (check-equal? reads 1)
     (check-equal? (get-output-bytes messages)
                   #"AttaLambda: unexpected launcher failure; verify the AttaLambda installation\n")
     (check-false (port-closed? source))
     status)))

(test-case "broken shell output terminates without consuming later source or leaking native exceptions"
  (for ([scenario '((#f #"1\n2\n:quit\n" #t #f 2)
                     (#f #"missing\n:quit\n" #f #t 8)
                     (#t #":quit\n" #f #t 0)
                     (#f #":help\n1\n" #f #t 6))])
    (bounded
     (lambda (own)
       (define source (own (open-input-bytes (cadr scenario))))
       (define good-output (own (open-output-bytes)))
       (define good-error (own (open-output-bytes)))
       (define bad
         (own (make-output-port 'failed-output always-evt
                           (lambda (_ start end nonblocking? breakable?)
                             (error 'private "/native/secret.rkt: injected write failure")) void)))
       (define status
         (parameterize ([current-input-port source]
                        [current-output-port (if (caddr scenario) bad good-output)]
                        [current-error-port (if (cadddr scenario) bad good-error)])
           (run-repl "test" (car scenario) #:history? #f)))
       (check-equal? status 70)
       (check-equal? (file-position source) (list-ref scenario 4))
       (check-false (regexp-match? #rx#"private|native/|rendering" (get-output-bytes good-error)))
       (check-false (port-closed? source))
       (check-false (port-closed? bad))
       status))))

(test-case "host stdout write failure remains a normal language Err with echo off"
  (bounded
   (lambda (own)
     (define bad
       (own (make-output-port 'failed-program-output always-evt
                         (lambda (_ start end nonblocking? breakable?)
                           (error 'probe "program write failed")) void)))
     (define status
       (parameterize ([current-input-port (own (open-input-string ":echo off\n(stdout \"x\")\n:quit\n"))]
                      [current-output-port bad]
                      [current-error-port (own (open-output-bytes))])
         (run-repl "test" #f #:history? #f)))
     (check-equal? status 0)
     status)))

(test-case "the controller recovers from observed expansion failure and cancellation"
  (for ([mode '(fail break)])
    (bounded
     (lambda (own)
       (define-values (input feed) (owned-pipe own))
       (define-values (output result-output) (owned-pipe own))
       (define-values (messages error-output) (owned-pipe own))
       (define reached (make-semaphore))
       (define armed? #f)
       (define status #f)
       (define worker
         (thread
          (lambda ()
            (set! status
                  (parameterize
                      ([current-input-port input] [current-output-port result-output]
                       [current-error-port error-output]
                       [current-expand-observe
                        (lambda (event detail)
                          (when (and armed? (eq? event 'start-top))
                            (set! armed? #f)
                            (semaphore-post reached)
                            (if (eq? mode 'fail)
                                (error 'probe "/private/native.rkt: expansion failure")
                                (sync never-evt))))])
                    (run-repl "test" #t #:history? #f))))))
       (check-not-false (sync/timeout 5 (read-bytes-line-evt messages 'any)))
       (check-equal? (sync/timeout 5 (read-bytes-evt 6 messages)) #"atta> ")
       (write-bytes #"(def old = 41) old\n" feed)
       (check-equal? (sync/timeout 5 (read-bytes-line-evt output 'any)) #"=> 41")
       (check-equal? (sync/timeout 5 (read-bytes-evt 6 messages)) #"atta> ")
       (set! armed? #t)
       (write-bytes #"(def ghost = 99) (stdout \"never\")\n" feed)
       (check-not-false (sync/timeout 5 reached))
       (when (eq? mode 'break) (break-thread worker))
       (define diagnostic (sync/timeout 5 (read-bytes-line-evt messages 'any)))
       (check-regexp-match (if (eq? mode 'fail) #rx#"source expansion failed" #rx#"entry interrupted")
                           diagnostic)
       (check-false (regexp-match? #rx#"private|native.rkt" diagnostic))
       (check-equal? (sync/timeout 5 (read-bytes-evt 6 messages)) #"atta> ")
       (write-bytes #"old\n" feed)
       (check-equal? (sync/timeout 5 (read-bytes-line-evt output 'any)) #"=> 41")
       (check-equal? (sync/timeout 5 (read-bytes-evt 6 messages)) #"atta> ")
       (close-output-port feed)
       (check-not-false (sync/timeout 5 (thread-dead-evt worker)))
       (check-equal? status 0)))))

(test-case "cancelling any recoverable diagnostic preserves interactive recovery and transcript130"
  (define directory (make-temporary-directory "attalambda-diagnostic-~a"))
  (dynamic-wind
   void
   (lambda ()
      (for* ([interactive? '(#t #f)]
             [example (list (list "unknown-name\n" #rx#"source expansion failed")
                            (list ")\n" #rx#"source could not be read")
                            (list ":unknown\n" #rx#"unknown command")
                            (list (format ":load ~s\n"
                                          (path->string (build-path directory "missing.attl")))
                                  #rx#"source file was not found"))])
        (bounded
         (lambda (own)
           (define text (string-append (car example) "41\n:quit\n"))
           (define input (own (open-input-string text)))
           (define output (own (open-output-bytes)))
           (define captured (own (open-output-bytes)))
           (define fired? #f)
           (define errors
             (own
              (make-output-port
               'diagnostic-break always-evt
               (lambda (bytes start end nonblocking? breakable?)
                 (when (and (not fired?) (regexp-match? (cadr example) bytes start end))
                   (set! fired? #t)
                   ;; Custom-port callbacks run with breaks disabled. The shell
                   ;; must deliver this pending break before leaving recovery.
                   (break-thread (current-thread)))
                 (write-bytes bytes captured start end)) void)))
           (define status
             (parameterize ([current-input-port input] [current-output-port output]
                            [current-error-port errors])
               (run-repl "test" interactive? #:history? #f)))
           (check-true fired?)
           (check-equal? status (if interactive? 0 130))
           (check-equal? (get-output-bytes output) (if interactive? #"=> 41\n" #""))
           (check-equal? (file-position input)
                         (string-length (if interactive? text (car example))))))))
   (lambda () (delete-directory/files directory))))

(test-case "a second interrupt while reporting the first still returns to a usable prompt"
  (bounded
   (lambda (own)
     (define-values (input feed) (owned-pipe own))
     (define output (own (open-output-bytes)))
     (define captured (own (open-output-bytes)))
     (define prompted (make-semaphore))
     (define second? #f)
     (define errors
       (own
        (make-output-port
         'repeated-interrupt always-evt
         (lambda (bytes start end nonblocking? breakable?)
           (when (regexp-match? #rx#"atta> " bytes start end) (semaphore-post prompted))
           (when (and (not second?) (regexp-match? #rx#"entry interrupted" bytes start end))
             (set! second? #t)
             (break-thread (current-thread)))
           (write-bytes bytes captured start end)) void)))
     (define status #f)
     (define worker
       (thread
        (lambda ()
          (set! status
                (parameterize ([current-input-port input] [current-output-port output]
                               [current-error-port errors])
                  (run-repl "test" #t #:history? #f))))))
     (check-not-false (sync/timeout 5 prompted))
     (break-thread worker)
     (check-not-false (sync/timeout 5 prompted))
     (check-true second?)
     (write-bytes #"41\n:quit\n" feed)
     (check-not-false (sync/timeout 5 (thread-dead-evt worker)))
     (check-equal? status 0)
     (check-equal? (get-output-bytes output) #"=> 41\n"))))
