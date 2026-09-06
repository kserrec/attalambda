#lang racket/base

(require rackunit
         (only-in racket/tcp tcp-connect)
         racket/promise
         "../core/errors.rkt"
         "../core/lists.rkt"
         "../core/logic.rkt"
         "../core/objects.rkt"
         "../core/pair.rkt"
         "../core/result.rkt"
         "../core/strings.rkt"
         "../core/tags.rkt"
         (only-in "../core/typed-logic.rkt" TRUE)
         "../effects/protocol.rkt"
         "../effects/tcp.rkt"
         "../readers/bool.rkt"
         "../readers/raw-boolean.rkt"
         "../readers/type-tag.rkt"
         "../runtime/codec.rkt"
         "../runtime/host.rkt"
         "helpers/lazy.rkt")

(define (typed-value? type value)
  (raw-boolean->boolean
   (apply2 raw-is-type type value)))

(define (error-kind-integer error)
  (type-tag->integer
   (lazy-apply raw-error-root-kind
               (lazy-apply raw-error-root error))))

(define (error-detail-strings error)
  (define details
    (lazy-apply
     raw-error-root-details
     (lazy-apply raw-error-root error)))
  (list
   (object-string->bytes
    (lazy-apply raw-first details))
   (object-string->bytes
    (lazy-apply raw-second details))))

(define (check-invalid-request value operation reason)
  (check-true (typed-value? error-type value))
  (check-equal? (error-kind-integer value) 7)
  (check-equal? (error-detail-strings value)
                (list operation reason)))

(define (check-host-failure value operation code)
  (check-true (typed-value? result-type value))
  (check-true (bool->boolean
               (lazy-apply is-err value)))
  (define error
    (lazy-apply unwrap-err value))
  (check-equal? (error-kind-integer error) 8)
  (check-equal? (error-detail-strings error)
                (list operation code)))

(define (check-ok-unit value)
  (check-true (typed-value? result-type value))
  (check-true (bool->boolean
               (lazy-apply is-ok value)))
  (check-equal?
   (type-tag->integer
    (lazy-apply raw-object-type
                (lazy-apply unwrap-ok value)))
   8))

(define (ok-nat value)
  (check-true (typed-value? result-type value))
  (check-true (bool->boolean
               (lazy-apply is-ok value)))
  (define payload
    (lazy-apply unwrap-ok value))
  (check-true (typed-value? rat-type payload))
  (object-rat->exact payload))

(define (ok-list value)
  (check-true (typed-value? result-type value))
  (check-true (bool->boolean
               (lazy-apply is-ok value)))
  (define payload
    (lazy-apply unwrap-ok value))
  (check-true (typed-value? list-type payload))
  (object-list->host-list payload))

;; Read results carry a List of Byte since the Step 37.4 switch.
(define (ok-bytes value)
  (check-true (typed-value? result-type value))
  (check-true (bool->boolean
               (lazy-apply is-ok value)))
  (object-byte-list->bytes
   (lazy-apply unwrap-ok value)))

(define (object-request parts)
  (host-list->object-list parts))

(define (host-call request)
  (lazy-apply host request))

(define loopback
  (bytes->object-string #"127.0.0.1"))
(define empty-string
  (bytes->object-string #""))

(define tcp-connect-with-host
  (lazy-apply make-tcp-connect host))
(define tcp-listen-with-host
  (lazy-apply make-tcp-listen host))
(define tcp-accept-with-host
  (lazy-apply make-tcp-accept host))
(define tcp-read-with-host
  (lazy-apply make-tcp-read host))
(define tcp-write-with-host
  (lazy-apply make-tcp-write host))
(define tcp-close-with-host
  (lazy-apply make-tcp-close host))

(define (connect remote port)
  (apply2 tcp-connect-with-host
          remote
          (exact->object-rat port)))

(define (listen local port backlog)
  (apply3 tcp-listen-with-host
          local
          (exact->object-rat port)
          (exact->object-rat backlog)))

(define (accept listener)
  (lazy-apply tcp-accept-with-host
              (exact->object-rat listener)))

(define (read-some connection maximum)
  (apply2 tcp-read-with-host
          (exact->object-rat connection)
          (exact->object-rat maximum)))

(define (write-all connection payload)
  (apply2 tcp-write-with-host
          (exact->object-rat connection)
          (bytes->object-byte-list payload)))

(define (close-handle connection)
  (lazy-apply tcp-close-with-host
              (exact->object-rat connection)))

(define (network-errno-guard errno)
  (make-security-guard
   (current-security-guard)
   (lambda (who path permissions)
     (void))
   (lambda (who host-name port mode)
     (raise
      (make-exn:fail:network:errno
       "synthetic network failure"
       (current-continuation-marks)
       errno)))))

(define out-of-memory-network-guard
  (make-security-guard
   (current-security-guard)
   (lambda (who path permissions)
     (void))
   (lambda (who host-name port mode)
     (raise
      (make-exn:fail:out-of-memory
       "synthetic resource exhaustion"
       (current-continuation-marks))))))

;; These deterministic failures occur before resource acquisition. Besides
;; proving the closed error vocabulary, the first real listener below proves
;; that none of them consumed a handle.
(for ([case (in-list
             (list
              (list (cons 13 'posix) #"permission-denied")
              (list (cons 111 'posix) #"connection-refused")
              (list (cons 104 'posix) #"connection-reset")
              (list (cons 32 'posix) #"broken-pipe")
              (list (cons 101 'posix) #"network-unreachable")
              (list (cons 24 'posix) #"resource-exhausted")
              (list (cons 110 'posix) #"timed-out")
              (list (cons -2 'gai) #"name-resolution-failed")))])
  (parameterize ([current-security-guard
                  (network-errno-guard (car case))])
    (check-host-failure
     (connect loopback 1)
     #"tcp-connect"
     (cadr case))))

(parameterize ([current-security-guard
                (network-errno-guard (cons 98 'posix))])
  (check-host-failure
   (listen loopback 0 1)
   #"tcp-listen"
   #"address-in-use"))

(parameterize ([current-security-guard out-of-memory-network-guard])
  (check-host-failure
   (connect loopback 1)
   #"tcp-connect"
   #"resource-exhausted"))

;; Pure schema failures are bare InvalidHostRequest Errors and cannot dispatch
;; a network effect.
(check-invalid-request
 (host-call
  (object-request (list tcp-connect-operation)))
 #"tcp-connect"
 #"wrong-arity")
(check-invalid-request
 (host-call
  (object-request
   (list tcp-connect-operation TRUE (exact->object-rat 80))))
 #"tcp-connect"
 #"wrong-type")
(check-invalid-request
 (apply2 tcp-connect-with-host
         empty-string
         (exact->object-rat 80))
 #"tcp-connect"
 #"out-of-range")
(check-invalid-request
 (connect loopback 0)
 #"tcp-connect"
 #"out-of-range")
(check-invalid-request
 (connect loopback 65536)
 #"tcp-connect"
 #"out-of-range")
(check-invalid-request
 (listen loopback 65536 1)
 #"tcp-listen"
 #"out-of-range")
(check-invalid-request
 (listen loopback 0 0)
 #"tcp-listen"
 #"out-of-range")
(check-invalid-request
 (listen loopback 0 65536)
 #"tcp-listen"
 #"out-of-range")
(check-invalid-request
 (accept 0)
 #"tcp-accept"
 #"out-of-range")
(check-invalid-request
 (read-some 1 0)
 #"tcp-read"
 #"out-of-range")
(check-invalid-request
 (read-some 1 65537)
 #"tcp-read"
 #"out-of-range")
(check-invalid-request
 (host-call
  (object-request
   (list tcp-close-operation
         (exact->object-rat 1)
         TRUE)))
 #"tcp-close"
 #"wrong-arity")

;; Forged noncanonical Rat fields are rejected by the pure representation
;; predicate before any operating-system call can dispatch.
(define (forged-rat-field numerator-bits denominator-bits)
  (apply2 raw-make-object
          rat-type
          (apply2 raw-pair
                  (apply2 raw-pair
                          raw-true
                          (host-list->object-list numerator-bits))
                  (host-list->object-list denominator-bits))))

(define leading-zero-nat
  (forged-rat-field (list raw-false raw-true)
                    (list raw-true)))
(check-invalid-request
 (host-call
  (object-request
   (list tcp-connect-operation loopback leading-zero-nat)))
 #"tcp-connect"
 #"wrong-type")

(define malformed-nat
  (apply2 raw-make-object rat-type TRUE))
(check-invalid-request
 (host-call
  (object-request
   (list tcp-connect-operation loopback malformed-nat)))
 #"tcp-connect"
 #"wrong-type")

(define malformed-bit-nat
  (forged-rat-field (list TRUE)
                    (list raw-true)))
(check-invalid-request
 (host-call
  (object-request
   (list tcp-connect-operation loopback malformed-bit-nat)))
 #"tcp-connect"
 #"wrong-type")

(define malformed-string
  (lazy-apply raw-make-string TRUE))
(check-invalid-request
 (host-call
  (object-request
   (list tcp-connect-operation
         malformed-string
         (exact->object-rat 80))))
 #"tcp-connect"
 #"wrong-type")
(check-invalid-request
 (host-call
  (object-request
   (list malformed-string
         loopback
         (exact->object-rat 80))))
 #""
 #"wrong-type")

;; Hostnames and interfaces alone use UTF-8 interpretation; wire data remains
;; arbitrary bytes.
(check-host-failure
 (connect (bytes->object-string #"\377") 80)
 #"tcp-connect"
 #"invalid-text")
(check-host-failure
 (listen (bytes->object-string #"\377") 0 1)
 #"tcp-listen"
 #"invalid-text")

(define open-handles '())
(define active-threads '())

(define (track! handle)
  (set! open-handles (cons handle open-handles))
  handle)

(define (untrack! handle)
  (set! open-handles (remove handle open-handles)))

(define (close-tracked! handle)
  (check-ok-unit (close-handle handle))
  (untrack! handle))

(define (start-worker thunk)
  (define result (box #f))
  (define started (make-channel))
  (define worker
    (thread
     (lambda ()
       (channel-put started 'started)
       (set-box! result (thunk)))))
  (set! active-threads (cons worker active-threads))
  (channel-get started)
  (values worker result))

(define (finish-worker worker result)
  (define completed
    (sync/timeout 10 worker))
  (check-not-false completed)
  (when completed
    (set! active-threads (remove worker active-threads)))
  (and completed (unbox result)))

(define (read-exactly connection amount maximum)
  (let loop ([received #""])
    (if (= (bytes-length received) amount)
        received
        (let ([chunk
               (ok-bytes (read-some connection maximum))])
          (check-true (positive? (bytes-length chunk)))
          (check-true (<= (bytes-length chunk) maximum))
          (check-true (<= (+ (bytes-length received)
                             (bytes-length chunk))
                          amount))
          (loop (bytes-append received chunk))))))

(dynamic-wind
  void
  (lambda ()
    ;; Ephemeral loopback listen returns [handle, actual-port]. The handle is
    ;; ONE because every prior rejected/synthetic request allocated nothing.
    (define listener-result
      (ok-list (listen loopback 0 8)))
    (check-equal? (length listener-result) 2)
    (define listener
      (track! (object-rat->exact (car listener-result))))
    (define bound-port
      (object-rat->exact (cadr listener-result)))
    (check-equal? listener 1)
    (check-true (and (exact-positive-integer? bound-port)
                     (<= bound-port 65535)))

    (check-host-failure
     (read-some listener 1)
     #"tcp-read"
     #"wrong-handle-kind")
    (check-host-failure
     (write-all listener #"")
     #"tcp-write"
     #"wrong-handle-kind")
    (check-host-failure
     (accept 999999)
     #"tcp-accept"
     #"invalid-handle")
    (check-host-failure
     (close-handle 999999)
     #"tcp-close"
     #"invalid-handle")

    (define client
      (track! (ok-nat (connect loopback bound-port))))
    (define server
      (track! (ok-nat (accept listener))))
    (check-equal? client 2)
    (check-equal? server 3)

    (check-host-failure
     (accept client)
     #"tcp-accept"
     #"wrong-handle-kind")

    ;; Only this thread ever forces lambda values: Lazy Racket promises are
    ;; not thread-safe, so test-side concurrency uses a raw Racket loopback
    ;; peer socket, mirroring the test-side external clients used by the
    ;; HTTP suites. The worker below performs plain port writes only.
    (define-values (peer-in peer-out)
      (tcp-connect "127.0.0.1" bound-port))
    (define raw-served
      (track! (ok-nat (accept listener))))
    (check-equal? raw-served 4)

    ;; A read remains blocked until a byte is written: the raw peer writes
    ;; only after a delay, and the blocking wrapper read returns exactly
    ;; those bytes no earlier than the write.
    (define write-instant (box #f))
    (define delayed-writer
      (thread
       (lambda ()
         (sleep 0.2)
         (set-box! write-instant (current-inexact-milliseconds))
         (write-bytes #"ab" peer-out)
         (flush-output peer-out))))
    (set! active-threads (cons delayed-writer active-threads))
    (check-equal? (ok-bytes (read-some raw-served 8)) #"ab")
    (define read-instant (current-inexact-milliseconds))
    (check-not-false (sync/timeout 5 delayed-writer))
    (set! active-threads (remove delayed-writer active-threads))
    (check-true (>= read-instant (unbox write-instant)))

    ;; The maximum is a hard per-call bound. Multiple writes and reads
    ;; preserve exact ordering without assuming TCP packet boundaries.
    (write-bytes #"cdefgh" peer-out)
    (flush-output peer-out)
    (check-equal? (read-exactly raw-served 6 2)
                  #"cdefgh")

    ;; A valid empty write emits no byte and does not unblock the peer.
    (check-ok-unit (write-all raw-served #""))
    (check-false (sync/timeout 0.05 peer-in))
    (check-ok-unit (write-all raw-served #"Z"))
    (check-equal? (read-bytes 1 peer-in) #"Z")

    ;; Complete-write acknowledgement means the peer can recover every
    ;; byte, including zero and values above ASCII, across many reads.
    (define complete-payload
      (apply bytes
             (for/list ([index (in-range 512)])
               (modulo (* index 73) 256))))
    (check-ok-unit (write-all raw-served complete-payload))
    (check-equal? (read-bytes (bytes-length complete-payload) peer-in)
                  complete-payload)

    ;; Host-handle pairs remain full duplex and byte-exact; loopback
    ;; buffering lets each direction complete sequentially on this thread.
    (check-ok-unit (write-all client #"ping\0\377"))
    (check-equal? (read-exactly server 6 3) #"ping\0\377")
    (define reverse-payload #"\0\377\200reply")
    (check-ok-unit (write-all server reverse-payload))
    (check-equal? (read-exactly client
                                (bytes-length reverse-payload)
                                3)
                  reverse-payload)

    ;; Orderly shutdown of the raw peer produces EOF for its host handle.
    (close-output-port peer-out)
    (check-equal? (ok-bytes (read-some raw-served 16)) #"")
    (close-input-port peer-in)
    (close-tracked! raw-served)

    ;; Closing one endpoint produces orderly EOF at its peer. Explicit close
    ;; removes a handle first, so every second close is deterministically stale.
    (close-tracked! client)
    (check-equal? (ok-bytes (read-some server 16)) #"")
    (check-host-failure
     (close-handle client)
     #"tcp-close"
     #"invalid-handle")
    (close-tracked! server)
    (check-host-failure
     (read-some server 1)
     #"tcp-read"
     #"invalid-handle")
    (close-tracked! listener)
    (check-host-failure
     (close-handle listener)
     #"tcp-close"
     #"invalid-handle")

    ;; Closed handles are never reused within the runtime instance.
    (define second-listener-result
      (ok-list (listen loopback 0 1)))
    (define second-listener
      (track! (object-rat->exact
               (car second-listener-result))))
    (check-equal? second-listener 5)
    (close-tracked! second-listener)

    ;; Racket custodians close their owned TCP resources at shutdown. A later
    ;; explicit close still removes the runtime handle, reports generic I/O
    ;; rather than a false name-resolution failure, and leaves it stale.
    (define socket-custodian (make-custodian))
    (define custodian-listener-result
      (parameterize ([current-custodian socket-custodian])
        (ok-list (listen loopback 0 1))))
    (define custodian-listener
      (track! (object-rat->exact
               (car custodian-listener-result))))
    (check-equal? custodian-listener 6)
    (custodian-shutdown-all socket-custodian)
    (check-host-failure
     (close-handle custodian-listener)
     #"tcp-close"
     #"io-failure")
    (untrack! custodian-listener)
    (check-host-failure
     (close-handle custodian-listener)
     #"tcp-close"
     #"invalid-handle"))
  (lambda ()
    (for ([worker (in-list active-threads)])
      (unless (thread-dead? worker)
        (kill-thread worker)))
    (for ([handle (in-list open-handles)])
      (with-handlers ([exn:fail? (lambda (failure) (void))])
        (lazy-force (close-handle handle))))))

(check-equal? open-handles '())
(check-equal? active-threads '())
