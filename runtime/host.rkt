#lang racket/base

;; The one production bridge to the outside world. The closed dispatcher
;; contains exactly stdout, file, blocking TCP, and explicit exit operations
;; approved by the host design and the 2026-09-05 exit amendment.

(require (only-in racket/file file->bytes)
         racket/promise
         (only-in racket/tcp
                  tcp-accept
                  tcp-addresses
                  tcp-close
                  tcp-connect
                  tcp-listen)
         (only-in "../core/strings.rkt" EMPTY-STRING)
         (only-in "../effects/protocol.rkt"
                  exit-operation
                  invalid-path-code
                  invalid-text-code
                  invalid-handle-code
                  io-failure-code
                  make-host-bridge
                  make-host-failure
                  make-invalid-host-request
                  address-in-use-code
                  broken-pipe-code
                  connection-refused-code
                  connection-reset-code
                  name-resolution-failed-code
                  network-unreachable-code
                  not-found-code
                  out-of-range-reason
                  permission-denied-code
                  read-file-operation
                  resource-exhausted-code
                  stdout-operation
                  tcp-accept-operation
                  tcp-close-operation
                  tcp-connect-operation
                  tcp-listen-operation
                  tcp-read-operation
                  tcp-write-operation
                  timed-out-code
                  unknown-operation-reason
                  write-file-operation
                  wrong-handle-kind-code
                  wrong-arity-reason
                  wrong-type-reason)
         (only-in "codec.rkt"
                  bytes->object-string
                  codec-failure-reason
                  codec-failure?
                  object-err
                  object-unit
                  exact->object-rat
                  object-rat->exact
                  object-list->host-list
                  object-ok
                  object-string->bytes
                  object-byte-list->bytes
                  bytes->object-byte-list
                  host-list->object-list))

(provide host)

(struct listener-entry (listener)
  #:transparent)

(struct connection-entry (input output)
  #:transparent)

(define handle-registry
  (make-hash))

(define next-handle 1)

(define (lazy-apply function argument)
  ((force function) argument))

(define (lazy-apply2 function first second)
  (lazy-apply (lazy-apply function first) second))

(define (reason->object reason)
  (case reason
    [(out-of-range) out-of-range-reason]
    [else wrong-type-reason]))

(define (invalid-request operation reason)
  (lazy-apply2 make-invalid-host-request operation reason))

(define (invalid-codec-request operation failure)
  (invalid-request operation
                   (reason->object
                    (codec-failure-reason failure))))

(define (host-failure operation code)
  (object-err
   (lazy-apply2 make-host-failure
                operation
                code)))

(define (register-entry! entry)
  (define handle next-handle)
  (set! next-handle (add1 next-handle))
  (hash-set! handle-registry handle entry)
  handle)

(define (attempt-close close-procedure prior-failure)
  (with-handlers ([exn:fail?
                   (lambda (failure)
                     (or prior-failure failure))])
    (close-procedure)
    prior-failure))

(define (close-entry entry)
  (cond
    [(listener-entry? entry)
     (attempt-close
      (lambda ()
        (tcp-close
         (listener-entry-listener entry)))
      #f)]
    [else
     (define output-failure
       (attempt-close
        (lambda ()
          (close-output-port
           (connection-entry-output entry)))
        #f))
     (attempt-close
      (lambda ()
        (close-input-port
         (connection-entry-input entry)))
      output-failure)]))

(define (discard-entry! handle entry)
  (hash-remove! handle-registry handle)
  (close-entry entry)
  (void))

(define (lookup-entry operation handle expected?)
  (define entry
    (hash-ref handle-registry handle #f))
  (cond
    [(not entry)
     (host-failure operation invalid-handle-code)]
    [(not (expected? entry))
     (host-failure operation wrong-handle-kind-code)]
    [else entry]))

(define (errno-in? errno posix-numbers windows-numbers)
  (and (pair? errno)
       (case (cdr errno)
         [(posix) (memv (car errno) posix-numbers)]
         [(windows) (memv (car errno) windows-numbers)]
         [else #f])))

;; Racket exposes stable OS error data as (number . domain). Keep the mapping
;; closed and return only approved lambda String codes; exception text, errno,
;; and paths never enter an object-language Error.
(define (filesystem-failure-code failure)
  (cond
    [(exn:fail:out-of-memory? failure)
     resource-exhausted-code]
    [(exn:fail:contract? failure)
     invalid-path-code]
    [(not (exn:fail:filesystem:errno? failure))
     io-failure-code]
    [else
     (define errno
       (exn:fail:filesystem:errno-errno failure))
     (cond
       [(errno-in? errno '(2) '(2 3))
        not-found-code]
       [(errno-in? errno '(1 13 30) '(5))
        permission-denied-code]
       [(errno-in? errno '(20 21 22 36 40) '(123 206 267))
        invalid-path-code]
       [(errno-in? errno '(12 23 24 28 122) '(4 8 14 112))
        resource-exhausted-code]
       [(errno-in? errno '(110) '(121))
        timed-out-code]
       [else io-failure-code])]))

(define (file-failure operation failure)
  (host-failure operation
                (filesystem-failure-code failure)))

(define (network-failure-code contract-code failure)
  (cond
    [(exn:fail:out-of-memory? failure)
     resource-exhausted-code]
    [(exn:fail:contract? failure)
     contract-code]
    [(not (exn:fail:network:errno? failure))
     io-failure-code]
    [else
     (define errno
       (exn:fail:network:errno-errno failure))
     (cond
       [(and (pair? errno)
             (eq? (cdr errno) 'gai))
        name-resolution-failed-code]
       [(errno-in? errno '(1 13) '(10013))
        permission-denied-code]
       [(errno-in? errno '(48 98) '(10048))
        address-in-use-code]
       [(errno-in? errno '(61 111) '(10061))
        connection-refused-code]
       [(errno-in? errno '(54 104) '(10053 10054))
        connection-reset-code]
       [(errno-in? errno '(32 57 107 108) '(10057 10058))
        broken-pipe-code]
       [(errno-in? errno
                   '(50 51 64 65 100 101 112 113)
                   '(10050 10051 10064 10065))
        network-unreachable-code]
       [(errno-in? errno '(12 23 24 55 105) '(10055))
        resource-exhausted-code]
       [(errno-in? errno '(60 110) '(10060))
        timed-out-code]
       [(errno-in? errno '() '(11001 11002 11003 11004))
        name-resolution-failed-code]
       [else io-failure-code])]))

(define (network-failure operation contract-code failure)
  (host-failure operation
                (network-failure-code contract-code failure)))

(define (perform-stdout payload)
  (with-handlers ([exn:fail?
                   (lambda (failure)
                     (host-failure stdout-operation
                                   io-failure-code))])
    (define output (current-output-port))
    (write-bytes payload output)
    (flush-output output)
    (object-ok object-unit)))

;; The pure caller chose the status; defensive decoding has already accepted
;; only canonical whole Rat 0 or 1. Successful real exit does not return.
(define (perform-exit status)
  (exit status))

(define (decode-utf8 operation payload)
  (with-handlers ([exn:fail:out-of-memory?
                   (lambda (failure)
                     (host-failure operation
                                   resource-exhausted-code))]
                  [exn:fail:contract?
                   (lambda (failure)
                     (host-failure operation
                                   invalid-text-code))]
                  [exn:fail?
                   (lambda (failure)
                     (host-failure operation
                                   io-failure-code))])
    (bytes->string/utf-8 payload #f)))

(define (perform-read-file path-payload)
  (define path
    (decode-utf8 read-file-operation path-payload))
  (if (string? path)
      (with-handlers ([exn:fail?
                       (lambda (failure)
                         (file-failure read-file-operation failure))])
        (object-ok
         (bytes->object-byte-list
          (file->bytes path))))
      path))

(define (perform-write-file path-payload payload)
  (define path
    (decode-utf8 write-file-operation path-payload))
  (if (string? path)
      (with-handlers ([exn:fail?
                       (lambda (failure)
                         (file-failure write-file-operation failure))])
        (call-with-output-file path
          #:exists 'truncate
          (lambda (output)
            (write-bytes payload output)))
        (object-ok object-unit))
      path))

(define (cleanup-new-connection input output handle)
  (when handle
    (hash-remove! handle-registry handle))
  (when output
    (attempt-close
     (lambda () (close-output-port output))
     #f))
  (when input
    (attempt-close
     (lambda () (close-input-port input))
     #f))
  (void))

(define (perform-tcp-connect remote-payload port)
  (define remote
    (decode-utf8 tcp-connect-operation remote-payload))
  (if (not (string? remote))
      remote
      (with-handlers ([exn:fail?
                       (lambda (failure)
                         (network-failure tcp-connect-operation
                                          name-resolution-failed-code
                                          failure))])
        (define-values (input output)
          (tcp-connect remote port))
        (define handle #f)
        (with-handlers ([exn:fail?
                         (lambda (failure)
                           (cleanup-new-connection input output handle)
                           (network-failure tcp-connect-operation
                                            name-resolution-failed-code
                                            failure))])
          (set! handle
                (register-entry!
                 (connection-entry input output)))
          (object-ok
           (exact->object-rat handle))))))

(define (cleanup-new-listener listener handle)
  (when handle
    (hash-remove! handle-registry handle))
  (when listener
    (attempt-close
     (lambda () (tcp-close listener))
     #f))
  (void))

(define (perform-tcp-listen local-payload port backlog)
  (define local
    (decode-utf8 tcp-listen-operation local-payload))
  (if (not (string? local))
      local
      (let ([listener #f]
            [handle #f])
        (with-handlers ([exn:fail?
                         (lambda (failure)
                           (cleanup-new-listener listener handle)
                           (network-failure tcp-listen-operation
                                            name-resolution-failed-code
                                            failure))])
          (set! listener
                (tcp-listen port
                            backlog
                            #f
                            (if (string=? local "")
                                #f
                                local)))
          (let-values ([(local-address
                         bound-port
                         remote-address
                         remote-port)
                        (tcp-addresses listener #t)])
            (set! handle
                  (register-entry!
                   (listener-entry listener)))
            (object-ok
             (host-list->object-list
              (list (exact->object-rat handle)
                    (exact->object-rat bound-port)))))))))

(define (perform-tcp-accept handle)
  (define listener
    (lookup-entry tcp-accept-operation
                  handle
                  listener-entry?))
  (if (not (listener-entry? listener))
      listener
      (with-handlers ([exn:fail?
                       (lambda (failure)
                         (network-failure tcp-accept-operation
                                          io-failure-code
                                          failure))])
        (define-values (input output)
          (tcp-accept
           (listener-entry-listener listener)))
        (define connection-handle #f)
        (with-handlers ([exn:fail?
                         (lambda (failure)
                           (cleanup-new-connection input
                                                   output
                                                   connection-handle)
                           (network-failure tcp-accept-operation
                                            io-failure-code
                                            failure))])
          (set! connection-handle
                (register-entry!
                 (connection-entry input output)))
          (object-ok
           (exact->object-rat connection-handle))))))

(define (perform-tcp-read handle maximum)
  (define connection
    (lookup-entry tcp-read-operation
                  handle
                  connection-entry?))
  (if (not (connection-entry? connection))
      connection
      (with-handlers ([exn:fail?
                       (lambda (failure)
                         (discard-entry! handle connection)
                         (network-failure tcp-read-operation
                                          io-failure-code
                                          failure))])
        (define buffer
          (make-bytes maximum))
        (define amount
          (read-bytes-avail!
           buffer
           (connection-entry-input connection)))
        (cond
          [(eof-object? amount)
           (object-ok
            (bytes->object-byte-list #""))]
          [(and (exact-positive-integer? amount)
                (<= amount maximum))
           (object-ok
            (bytes->object-byte-list
             (subbytes buffer 0 amount)))]
          [else
           (discard-entry! handle connection)
           (host-failure tcp-read-operation
                         io-failure-code)]))))

(define (write-all-bytes output payload)
  (define end
    (bytes-length payload))
  (let loop ([start 0])
    (cond
      [(= start end)
       (flush-output output)
       #t]
      [else
       (define written
         (write-bytes-avail payload output start end))
       (and (exact-positive-integer? written)
            (loop (+ start written)))])))

(define (perform-tcp-write handle payload)
  (define connection
    (lookup-entry tcp-write-operation
                  handle
                  connection-entry?))
  (if (not (connection-entry? connection))
      connection
      (if (zero? (bytes-length payload))
          (object-ok object-unit)
          (with-handlers ([exn:fail?
                           (lambda (failure)
                             (discard-entry! handle connection)
                             (network-failure tcp-write-operation
                                              io-failure-code
                                              failure))])
            (if (write-all-bytes
                 (connection-entry-output connection)
                 payload)
                (object-ok object-unit)
                (begin
                  (discard-entry! handle connection)
                  (host-failure tcp-write-operation
                                io-failure-code)))))))

(define (perform-tcp-close handle)
  (define entry
    (hash-ref handle-registry handle #f))
  (if (not entry)
      (host-failure tcp-close-operation
                    invalid-handle-code)
      (begin
        ;; Removal happens before close. Even if a platform close reports a
        ;; failure, the handle is stale and every side was attempted once.
        (hash-remove! handle-registry handle)
        (let ([failure
               (close-entry entry)])
          (if failure
              (network-failure tcp-close-operation
                               io-failure-code
                               failure)
              (object-ok object-unit))))))

(define (wrong-arity operation)
  (invalid-request operation wrong-arity-reason))

(define (dispatch-one-string operation value performer)
  (define payload
    (object-string->bytes value))
  (if (codec-failure? payload)
      (invalid-codec-request operation payload)
      (performer payload)))

(define (decode-bounded-count operation value minimum maximum)
  (define decoded
    (object-rat->exact value))
  (cond
    [(codec-failure? decoded)
     (invalid-codec-request operation decoded)]
    [(not (exact-nonnegative-integer? decoded))
     (invalid-request operation out-of-range-reason)]
    [(or (< decoded minimum)
         (and maximum (> decoded maximum)))
     (invalid-request operation out-of-range-reason)]
    [else decoded]))

(define (dispatch-request request)
  (define decoded-request
    (object-list->host-list request))
  (cond
    [(codec-failure? decoded-request)
     (invalid-codec-request EMPTY-STRING decoded-request)]
    [(null? decoded-request)
     (invalid-request EMPTY-STRING wrong-arity-reason)]
    [else
     (define operation-value (car decoded-request))
     (define operation-bytes
       (object-string->bytes operation-value))
     (if (codec-failure? operation-bytes)
         (invalid-codec-request EMPTY-STRING operation-bytes)
         (let ([arguments (cdr decoded-request)])
           (define argument-count
             (length arguments))
           (cond
             [(bytes=? operation-bytes #"stdout")
              (if (= argument-count 1)
                  (dispatch-one-string stdout-operation
                                       (car arguments)
                                       perform-stdout)
                  (wrong-arity stdout-operation))]
             [(bytes=? operation-bytes #"read-file")
              (if (= argument-count 1)
                  (dispatch-one-string read-file-operation
                                       (car arguments)
                                       perform-read-file)
                  (wrong-arity read-file-operation))]
             [(bytes=? operation-bytes #"write-file")
              (if (= argument-count 2)
                  (let ([path
                         (object-string->bytes (car arguments))])
                    (if (codec-failure? path)
                        (invalid-codec-request write-file-operation path)
                        (let ([payload
                               (object-byte-list->bytes (cadr arguments))])
                          (if (codec-failure? payload)
                              (invalid-codec-request write-file-operation
                                                     payload)
                              (perform-write-file path payload)))))
                  (wrong-arity write-file-operation))]
             [(bytes=? operation-bytes #"tcp-connect")
              (if (= argument-count 2)
                  (let ([remote
                         (object-string->bytes (car arguments))])
                    (if (codec-failure? remote)
                        (invalid-codec-request tcp-connect-operation remote)
                        (let ([port
                               (decode-bounded-count tcp-connect-operation
                                                     (cadr arguments)
                                                     1
                                                     65535)])
                          (if (exact-nonnegative-integer? port)
                              (perform-tcp-connect remote port)
                              port))))
                  (wrong-arity tcp-connect-operation))]
             [(bytes=? operation-bytes #"tcp-listen")
              (if (= argument-count 3)
                  (let ([local
                         (object-string->bytes (car arguments))])
                    (if (codec-failure? local)
                        (invalid-codec-request tcp-listen-operation local)
                        (let ([port
                               (decode-bounded-count tcp-listen-operation
                                                     (cadr arguments)
                                                     0
                                                     65535)])
                          (if (not (exact-nonnegative-integer? port))
                              port
                              (let ([backlog
                                     (decode-bounded-count
                                      tcp-listen-operation
                                      (caddr arguments)
                                      1
                                      65535)])
                                (if (exact-nonnegative-integer? backlog)
                                    (perform-tcp-listen local port backlog)
                                    backlog))))))
                  (wrong-arity tcp-listen-operation))]
             [(bytes=? operation-bytes #"tcp-accept")
              (if (= argument-count 1)
                  (let ([handle
                         (decode-bounded-count tcp-accept-operation
                                               (car arguments)
                                               1
                                               #f)])
                    (if (exact-nonnegative-integer? handle)
                        (perform-tcp-accept handle)
                        handle))
                  (wrong-arity tcp-accept-operation))]
             [(bytes=? operation-bytes #"tcp-read")
              (if (= argument-count 2)
                  (let ([handle
                         (decode-bounded-count tcp-read-operation
                                               (car arguments)
                                               1
                                               #f)])
                    (if (not (exact-nonnegative-integer? handle))
                        handle
                        (let ([maximum
                               (decode-bounded-count tcp-read-operation
                                                     (cadr arguments)
                                                     1
                                                     65536)])
                          (if (exact-nonnegative-integer? maximum)
                              (perform-tcp-read handle maximum)
                              maximum))))
                  (wrong-arity tcp-read-operation))]
             [(bytes=? operation-bytes #"tcp-write")
              (if (= argument-count 2)
                  (let ([handle
                         (decode-bounded-count tcp-write-operation
                                               (car arguments)
                                               1
                                               #f)])
                    (if (not (exact-nonnegative-integer? handle))
                        handle
                        (let ([payload
                               (object-byte-list->bytes (cadr arguments))])
                          (if (codec-failure? payload)
                              (invalid-codec-request tcp-write-operation
                                                     payload)
                              (perform-tcp-write handle payload)))))
                  (wrong-arity tcp-write-operation))]
             [(bytes=? operation-bytes #"tcp-close")
              (if (= argument-count 1)
                  (let ([handle
                         (decode-bounded-count tcp-close-operation
                                               (car arguments)
                                               1
                                               #f)])
                    (if (exact-nonnegative-integer? handle)
                        (perform-tcp-close handle)
                        handle))
                  (wrong-arity tcp-close-operation))]
             [(bytes=? operation-bytes #"exit")
              (if (= argument-count 1)
                  (let ([status
                         (decode-bounded-count exit-operation
                                               (car arguments)
                                               0
                                               1)])
                    (if (exact-nonnegative-integer? status)
                        (perform-exit status)
                        status))
                  (wrong-arity exit-operation))]
             [else
              (invalid-request
               (bytes->object-string operation-bytes)
               unknown-operation-reason)])))]))

(define host
  (lazy-apply make-host-bridge dispatch-request))
