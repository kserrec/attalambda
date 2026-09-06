#lang racket/base

(require rackunit
         net/http-client
         racket/port
         racket/promise
         "../core/errors.rkt"
         "../core/lists.rkt"
         "../core/objects.rkt"
         "../core/result.rkt"
         "../core/strings.rkt"
         "../core/tags.rkt"
         "../core/unit.rkt"
         (only-in "../core/typed-logic.rkt"
                  TRUE)
         "../effects/http-response.rkt"
         "../effects/http-server.rkt"
         "../effects/tcp.rkt"
         "../readers/bool.rkt"
         "../readers/raw-boolean.rkt"
         "../readers/type-tag.rkt"
         "../runtime/codec.rkt"
         "../runtime/host.rkt"
         "helpers/lazy.rkt")

(define (apply-arguments function arguments)
  (if (null? arguments)
      function
      (apply-arguments
       (lazy-apply function (car arguments))
       (cdr arguments))))

(define (typed-value? type value)
  (raw-boolean->boolean
   (apply2 raw-is-type type value)))

(define (error-kind-integer error)
  (type-tag->integer
   (lazy-apply raw-error-root-kind
               (lazy-apply raw-error-root error))))

(define (first-error-frame error)
  (car
   (object-list->host-list
    (lazy-apply raw-error-frames error))))

(define (check-contract-error value expected-name position expected-type)
  (check-true (typed-value? error-type value))
  (check-equal? (error-kind-integer value) 0)
  (define frame (first-error-frame value))
  (check-equal?
   (object-string->bytes
    (lazy-apply raw-error-frame-function-name frame))
   expected-name)
  (check-equal?
   (type-tag->integer
    (lazy-apply raw-error-frame-argument-position frame))
   position)
  (check-equal?
   (type-tag->integer
    (lazy-apply raw-error-frame-expected-type frame))
   expected-type))

(define (check-ok-unit value)
  (check-true (typed-value? result-type value))
  (check-true (bool->boolean
               (lazy-apply is-ok value)))
  (check-equal?
   (type-tag->integer
    (lazy-apply raw-object-type
                (lazy-apply unwrap-ok value)))
   8))

(define (check-result-err-kind value expected-kind)
  (check-true (typed-value? result-type value))
  (check-true (bool->boolean
               (lazy-apply is-err value)))
  (define failure
    (lazy-apply unwrap-err value))
  (check-true (typed-value? error-type failure))
  (check-equal? (error-kind-integer failure)
                expected-kind))

(define (check-response-bytes value expected)
  (check-true (typed-value? result-type value))
  (check-true (bool->boolean
               (lazy-apply is-ok value)))
  (check-equal?
   (object-string->bytes
    (lazy-apply unwrap-ok value))
   expected))

(define route-target
  (bytes->object-string #"/lambda"))
(define matched-body
  (bytes->object-string #"lambda says hello"))
(define fallback-body
  (bytes->object-string #"missing"))
(define listener-handle
  (exact->object-rat 1))
(define connection-handle
  (exact->object-rat 2))
(define maximum
  (exact->object-rat 65536))

(define (make-path-handler matched-status fallback-status)
  (apply-arguments
   make-http-path-handler
   (list route-target
         matched-status
         matched-body
         fallback-status
         fallback-body)))

(define handler
  (make-path-handler HTTP-STATUS-OK
                     HTTP-STATUS-NOT-FOUND))

;; The first five applications construct a pure unary request handler. It
;; routes by the parsed target and renders only its selected status/body.
(check-equal? (procedure-arity (lazy-force handler)) 1)
(check-response-bytes
 (lazy-apply handler route-target)
 #"HTTP/1.1 200 OK\r\nContent-Length: 17\r\nConnection: close\r\n\r\nlambda says hello")
(check-response-bytes
 (lazy-apply handler
             (bytes->object-string #"/elsewhere"))
 #"HTTP/1.1 404 Not Found\r\nContent-Length: 7\r\nConnection: close\r\n\r\nmissing")

;; An unsupported unselected status is not rendered. Selecting it preserves
;; the renderer's expected Result Err instead of introducing a host failure.
(define lazy-branch-handler
  (make-path-handler HTTP-STATUS-OK
                     (exact->object-rat 201)))
(check-response-bytes
 (lazy-apply lazy-branch-handler route-target)
 #"HTTP/1.1 200 OK\r\nContent-Length: 17\r\nConnection: close\r\n\r\nlambda says hello")
(check-result-err-kind
 (lazy-apply lazy-branch-handler
             (bytes->object-string #"/other"))
 12)

;; The handler factory uses the generalized checker across all six curried
;; positions, including the final target accepted by the produced handler.
(define wrong-handler-first
  (lazy-apply make-http-path-handler TRUE))
(define absorbed-handler-first
  (apply-arguments
   wrong-handler-first
   (list HTTP-STATUS-OK
         matched-body
         HTTP-STATUS-NOT-FOUND
         fallback-body
         route-target)))
(check-contract-error absorbed-handler-first
                      #"http-path-handler"
                      1
                      6)

(check-contract-error
 (lazy-apply handler TRUE)
 #"http-path-handler"
 6
 6)

(define incoming-handler-error
  (apply-arguments
   (lazy-apply make-http-path-handler invalid-nat-error)
   (list HTTP-STATUS-OK
         matched-body
         HTTP-STATUS-NOT-FOUND
         fallback-body
         route-target)))
(check-true (typed-value? error-type incoming-handler-error))
(check-equal? (error-kind-integer incoming-handler-error) 2)

;; Fake hosts return a scripted response for each forced TCP request and retain
;; the exact object-language trace for later decoding.
(define (make-scripted-host responses)
  (define remaining responses)
  (define traces '())
  (define calls 0)
  (values
   (lambda (request)
     (set! calls (add1 calls))
     (set! traces (cons request traces))
     (when (null? remaining)
       (error 'scripted-host "unexpected request"))
     (define response (car remaining))
     (set! remaining (cdr remaining))
     response)
   (lambda () (reverse traces))
   (lambda () calls)
   (lambda () remaining)))

(define (decode-tcp-request request)
  (define parts
    (object-list->host-list request))
  (check-false (codec-failure? parts))
  (define operation
    (object-string->bytes (car parts)))
  (cond
    [(bytes=? operation #"tcp-accept")
     (list operation
           (object-rat->exact (cadr parts)))]
    [(bytes=? operation #"tcp-read")
     (list operation
           (object-rat->exact (cadr parts))
           (object-rat->exact (caddr parts)))]
    [(bytes=? operation #"tcp-write")
     (list operation
           (object-rat->exact (cadr parts))
           (object-byte-list->bytes (caddr parts)))]
    [(bytes=? operation #"tcp-close")
     (list operation
           (object-rat->exact (cadr parts)))]
    [else
     (error 'decode-tcp-request
            "unexpected operation: ~s"
            operation)]))

(define (decoded-traces get-traces)
  (map decode-tcp-request (get-traces)))

(define (configure-serve-one fake-host request-handler)
  (lazy-apply
   (lazy-apply make-http-serve-one fake-host)
   request-handler))

(define (configure-server fake-host request-handler)
  (lazy-apply
   (lazy-apply make-http-server fake-host)
   request-handler))

(define valid-request-one
  #"GET /lambda HTTP/1.1\r\nHo")
(define valid-request-two
  #"st: localhost\r\n\r\n")
(define expected-ok-response
  #"HTTP/1.1 200 OK\r\nContent-Length: 17\r\nConnection: close\r\n\r\nlambda says hello")
(define expected-not-found-response
  #"HTTP/1.1 404 Not Found\r\nContent-Length: 7\r\nConnection: close\r\n\r\nmissing")

;; A fragmented success performs only accept, bounded reads, one complete
;; write, and connection close. Construction is pure and forcing is cached.
(define-values (success-host success-traces success-calls success-remaining)
  (make-scripted-host
   (list (object-ok connection-handle)
         (object-ok (bytes->object-byte-list valid-request-one))
         (object-ok (bytes->object-byte-list valid-request-two))
         (object-ok UNIT)
         (object-ok UNIT))))
(define success-serve-one
  (configure-serve-one success-host handler))
(check-equal? (procedure-arity
               (lazy-force success-serve-one))
              1)
(define pending-success
  (apply2 success-serve-one
          listener-handle
          maximum))
(check-equal? (success-calls) 0)
(check-ok-unit pending-success)
(check-equal? (success-calls) 5)
(check-ok-unit pending-success)
(check-equal? (success-calls) 5)
(check-equal? (success-remaining) '())
(check-equal?
 (decoded-traces success-traces)
 (list (list #"tcp-accept" 1)
       (list #"tcp-read" 2 65536)
       (list #"tcp-read" 2 65536)
       (list #"tcp-write" 2 expected-ok-response)
       (list #"tcp-close" 2)))

;; Framing must not depend on TCP packet boundaries. The scripted host has
;; exactly the expected reads: an extra read, premature completion, reordered chunk,
;; duplicate effect, missing close, or changed target/response fails here.
(define (check-request-chunks chunks expected-kind)
  (define handler-calls 0)
  (define-values (fake-host get-traces get-calls get-remaining)
    (make-scripted-host
     (append
      (list (object-ok connection-handle))
      (for/list ([chunk (in-list chunks)])
        (object-ok (bytes->object-byte-list chunk)))
      (if expected-kind '() (list (object-ok UNIT)))
      (list (object-ok UNIT)))))
  (define pending
    (apply2
     (configure-serve-one
      fake-host
      (lambda (target)
        (set! handler-calls (add1 handler-calls))
        (check-equal? (object-string->bytes target) #"/lambda")
        (lazy-apply handler target)))
     listener-handle
     maximum))
  (check-equal? (get-calls) 0)
  (check-equal? handler-calls 0)
  (for ([forcing (in-range 2)])
    (if expected-kind
        (check-result-err-kind pending expected-kind)
        (check-ok-unit pending))
    (check-equal? handler-calls (if expected-kind 0 1))
    (check-equal? (get-calls)
                  (+ (length chunks) (if expected-kind 2 3))))
  (check-equal? (get-remaining) '())
  (check-equal?
   (decoded-traces get-traces)
   (append
    (list (list #"tcp-accept" 1))
    (for/list ([chunk (in-list chunks)]) (list #"tcp-read" 2 65536))
    (if expected-kind '() (list (list #"tcp-write" 2 expected-ok-response)))
    (list (list #"tcp-close" 2)))))

(define framing-request
  (bytes-append valid-request-one valid-request-two))
(check-request-chunks (list framing-request) #f)
(check-request-chunks
 (for/list ([byte (in-bytes framing-request)]) (bytes byte))
 #f)
;; Nonempty pieces only: an empty TCP read means EOF, not a fragment.
(for ([split (in-range 1 (bytes-length framing-request))])
  (with-check-info (['split split])
    (check-request-chunks
     (list (subbytes framing-request 0 split)
           (subbytes framing-request split))
     #f)))

(check-request-chunks (list #"") 9)
(check-request-chunks (list #"GET /lambda HTTP/1.1\r\n\r" #"") 9)
(check-request-chunks (list #"GET /lambda HTTP/1.1\nHost: x\r\n\r" #"\n") 10)
(check-request-chunks (list #"POST /lambda HTTP/1.1\r\n\r" #"\n") 11)
;; Trailing bytes must arrive in the completing chunk. The server does not
;; read further stream data after it has received a complete bodyless request.
(check-request-chunks (list (bytes-append framing-request #"body")) 10)
(check-request-chunks
 (list (subbytes framing-request 0 (sub1 (bytes-length framing-request)))
       #"\nbody")
 10)

(define (padded-request method size)
  (define prefix (bytes-append method #" /lambda HTTP/1.1\r\nHost: localhost\r\nX: "))
  (define suffix #"\r\n\r\n")
  (bytes-append prefix
                (make-bytes (- size (bytes-length prefix) (bytes-length suffix))
                            (char->integer #\a))
                suffix))
(define at-cap-request (padded-request #"GET" 8192))
(check-request-chunks (list at-cap-request) #f)
(check-request-chunks
 (list (subbytes at-cap-request 0 8190) (subbytes at-cap-request 8190))
 #f)
;; POST would be unsupported (11) if parsed; over-cap must win as malformed
;; (10), including when the last chunk completes both the count and delimiter.
(define over-cap-request (padded-request #"POST" 8193))
(check-request-chunks (list over-cap-request) 10)
(check-request-chunks
 (list (subbytes over-cap-request 0 8190) (subbytes over-cap-request 8190))
 10)

;; Complete parse failures and incomplete EOF both close the acquired
;; connection and perform no write.
(define-values (malformed-host malformed-traces malformed-calls
                               malformed-remaining)
  (make-scripted-host
   (list (object-ok connection-handle)
         (object-ok
          (bytes->object-byte-list
           #"GET / HTTP/1.1\nHost: x\r\n\r\n"))
         (object-ok UNIT))))
(define malformed-result
  (apply2 (configure-serve-one malformed-host handler)
          listener-handle
          maximum))
(check-result-err-kind malformed-result 10)
(check-equal?
 (decoded-traces malformed-traces)
 (list (list #"tcp-accept" 1)
       (list #"tcp-read" 2 65536)
       (list #"tcp-close" 2)))
(check-equal? (malformed-calls) 3)
(check-equal? (malformed-remaining) '())

(define-values (eof-host eof-traces eof-calls eof-remaining)
  (make-scripted-host
   (list (object-ok connection-handle)
         (object-ok
          (bytes->object-byte-list
           #"GET /lambda HTTP/1.1\r\nHost: x\r\n"))
         (object-ok (bytes->object-byte-list #""))
         (object-ok UNIT))))
(define eof-result
  (apply2 (configure-serve-one eof-host handler)
          listener-handle
          maximum))
(check-result-err-kind eof-result 9)
(check-equal?
 (decoded-traces eof-traces)
 (list (list #"tcp-accept" 1)
       (list #"tcp-read" 2 65536)
       (list #"tcp-read" 2 65536)
       (list #"tcp-close" 2)))
(check-equal? (eof-calls) 4)
(check-equal? (eof-remaining) '())

;; Expected read/write failures remain primary Results while cleanup is still
;; forced. A close failure becomes the result only after a successful write.
(define-values (read-failure-host read-failure-traces read-failure-calls
                                  read-failure-remaining)
  (make-scripted-host
   (list (object-ok connection-handle)
         (object-ok (bytes->object-byte-list valid-request-one))
         (object-err invalid-nat-error)
         (object-ok UNIT))))
(check-result-err-kind
 (apply2 (configure-serve-one read-failure-host handler)
         listener-handle
         maximum)
 2)
(check-equal?
 (decoded-traces read-failure-traces)
 (list (list #"tcp-accept" 1)
       (list #"tcp-read" 2 65536)
       (list #"tcp-read" 2 65536)
       (list #"tcp-close" 2)))
(check-equal? (read-failure-calls) 4)
(check-equal? (read-failure-remaining) '())

(define-values (double-failure-host double-failure-traces
                                    double-failure-calls
                                    double-failure-remaining)
  (make-scripted-host
   (list (object-ok connection-handle)
         (object-err invalid-nat-error)
         (object-err invalid-char-error))))
(check-result-err-kind
 (apply2 (configure-serve-one double-failure-host handler)
         listener-handle
         maximum)
 2)
(check-equal?
 (decoded-traces double-failure-traces)
 (list (list #"tcp-accept" 1)
       (list #"tcp-read" 2 65536)
       (list #"tcp-close" 2)))
(check-equal? (double-failure-calls) 3)
(check-equal? (double-failure-remaining) '())

(define complete-request
  (bytes->object-byte-list
   #"GET /lambda HTTP/1.1\r\nHost: localhost\r\n\r\n"))
(define-values (write-failure-host write-failure-traces write-failure-calls
                                   write-failure-remaining)
  (make-scripted-host
   (list (object-ok connection-handle)
         (object-ok complete-request)
         (object-err invalid-nat-error)
         (object-ok UNIT))))
(check-result-err-kind
 (apply2 (configure-serve-one write-failure-host handler)
         listener-handle
         maximum)
 2)
(check-equal?
 (decoded-traces write-failure-traces)
 (list (list #"tcp-accept" 1)
       (list #"tcp-read" 2 65536)
       (list #"tcp-write" 2 expected-ok-response)
       (list #"tcp-close" 2)))
(check-equal? (write-failure-calls) 4)
(check-equal? (write-failure-remaining) '())

(define-values (close-failure-host close-failure-traces close-failure-calls
                                   close-failure-remaining)
  (make-scripted-host
   (list (object-ok connection-handle)
         (object-ok complete-request)
         (object-ok UNIT)
         (object-err invalid-nat-error))))
(check-result-err-kind
 (apply2 (configure-serve-one close-failure-host handler)
         listener-handle
         maximum)
 2)
(check-equal?
 (decoded-traces close-failure-traces)
 (list (list #"tcp-accept" 1)
       (list #"tcp-read" 2 65536)
       (list #"tcp-write" 2 expected-ok-response)
       (list #"tcp-close" 2)))
(check-equal? (close-failure-calls) 4)
(check-equal? (close-failure-remaining) '())

;; Handler Results and contract Errors never reach tcp-write. A wrong tagged
;; handler return becomes the dedicated invariant Error after close.
(define unsupported-handler
  (make-path-handler (exact->object-rat 201)
                     HTTP-STATUS-NOT-FOUND))
(define-values (handler-err-host handler-err-traces handler-err-calls
                                 handler-err-remaining)
  (make-scripted-host
   (list (object-ok connection-handle)
         (object-ok complete-request)
         (object-ok UNIT))))
(check-result-err-kind
 (apply2 (configure-serve-one handler-err-host unsupported-handler)
         listener-handle
         maximum)
 12)
(check-equal?
 (decoded-traces handler-err-traces)
 (list (list #"tcp-accept" 1)
       (list #"tcp-read" 2 65536)
       (list #"tcp-close" 2)))
(check-equal? (handler-err-calls) 3)
(check-equal? (handler-err-remaining) '())

(define-values (handler-error-host handler-error-traces handler-error-calls
                                   handler-error-remaining)
  (make-scripted-host
   (list (object-ok connection-handle)
         (object-ok complete-request)
         (object-ok UNIT))))
(define handler-error-result
  (apply2
   (configure-serve-one
    handler-error-host
    (lambda (target) invalid-char-error))
   listener-handle
   maximum))
(check-true (typed-value? error-type handler-error-result))
(check-equal? (error-kind-integer handler-error-result) 4)
(check-equal?
 (decoded-traces handler-error-traces)
 (list (list #"tcp-accept" 1)
       (list #"tcp-read" 2 65536)
       (list #"tcp-close" 2)))
(check-equal? (handler-error-calls) 3)
(check-equal? (handler-error-remaining) '())

(define-values (invalid-handler-host invalid-handler-traces
                                     invalid-handler-calls
                                     invalid-handler-remaining)
  (make-scripted-host
   (list (object-ok connection-handle)
         (object-ok complete-request)
         (object-ok UNIT))))
(define invalid-handler-result
  (apply2
   (configure-serve-one
    invalid-handler-host
    (lambda (target) HTTP-STATUS-OK))
   listener-handle
   maximum))
(check-true (typed-value? error-type invalid-handler-result))
(check-equal? (error-kind-integer invalid-handler-result) 13)
(check-equal?
 (decoded-traces invalid-handler-traces)
 (list (list #"tcp-accept" 1)
       (list #"tcp-read" 2 65536)
       (list #"tcp-close" 2)))
(check-equal? (invalid-handler-calls) 3)
(check-equal? (invalid-handler-remaining) '())

;; Accept failure acquires no connection and therefore performs no close.
(define-values (accept-failure-host accept-failure-traces
                                    accept-failure-calls
                                    accept-failure-remaining)
  (make-scripted-host
   (list (object-err invalid-nat-error))))
(check-result-err-kind
 (apply2 (configure-serve-one accept-failure-host handler)
         listener-handle
         maximum)
 2)
(check-equal?
 (decoded-traces accept-failure-traces)
 (list (list #"tcp-accept" 1)))
(check-equal? (accept-failure-calls) 1)
(check-equal? (accept-failure-remaining) '())

;; The public serving boundaries are unary and strict in both Nat arguments.
;; Contract failures happen before any host request and preserve absorber depth.
(define-values (contract-host contract-traces contract-calls
                              contract-remaining)
  (make-scripted-host '()))
(define contract-serve-one
  (configure-serve-one contract-host handler))
(define wrong-listener-partial
  (lazy-apply contract-serve-one TRUE))
(check-equal? (procedure-arity
               (lazy-force wrong-listener-partial))
              1)
(check-contract-error
 (lazy-apply wrong-listener-partial maximum)
 #"http-serve-one"
 1
 7)
(check-contract-error
 (apply2 contract-serve-one listener-handle TRUE)
 #"http-serve-one"
 2
 7)
(define incoming-server-error
  (apply2 contract-serve-one invalid-nat-error maximum))
(check-true (typed-value? error-type incoming-server-error))
(check-equal? (error-kind-integer incoming-server-error) 2)
(check-equal? (contract-calls) 0)
(check-equal? (contract-traces) '())
(check-equal? (contract-remaining) '())

;; The long-running server handles completed connections serially. This fake
;; permits two successes, then ends the otherwise nonterminating loop with an
;; expected accept Err. Each new accept follows the prior connection close.
(define second-connection-handle
  (exact->object-rat 3))
(define second-request
  (bytes->object-byte-list
   #"GET /missing HTTP/1.1\r\nHost: localhost\r\n\r\n"))
(define-values (loop-host loop-traces loop-calls loop-remaining)
  (make-scripted-host
   (list (object-ok connection-handle)
         (object-ok complete-request)
         (object-ok UNIT)
         (object-ok UNIT)
         (object-ok second-connection-handle)
         (object-ok second-request)
         (object-ok UNIT)
         (object-ok UNIT)
         (object-err invalid-nat-error))))
(define configured-loop
  (configure-server loop-host handler))
(check-equal? (procedure-arity
               (lazy-force configured-loop))
              1)
(define pending-loop
  (apply2 configured-loop listener-handle maximum))
(check-equal? (loop-calls) 0)
(check-result-err-kind pending-loop 2)
(check-equal? (loop-calls) 9)
(check-equal?
 (decoded-traces loop-traces)
 (list (list #"tcp-accept" 1)
       (list #"tcp-read" 2 65536)
       (list #"tcp-write" 2 expected-ok-response)
       (list #"tcp-close" 2)
       (list #"tcp-accept" 1)
       (list #"tcp-read" 3 65536)
       (list #"tcp-write" 3 expected-not-found-response)
       (list #"tcp-close" 3)
       (list #"tcp-accept" 1)))
(check-equal? (loop-remaining) '())

;; Real acceptance uses Racket's external HTTP client only in the test layer.
;; The production server still sees solely the documented TCP host requests.
(define real-listen
  (lazy-apply make-tcp-listen host))
(define real-close
  (lazy-apply make-tcp-close host))
(define real-serve-one
  (configure-serve-one host handler))
(define listener-result
  (apply3 real-listen
          (bytes->object-string #"127.0.0.1")
          (exact->object-rat 0)
          (exact->object-rat 4)))
(check-true (bool->boolean
             (lazy-apply is-ok listener-result)))
(define listener-parts
  (object-list->host-list
   (lazy-apply unwrap-ok listener-result)))
(define real-listener
  (car listener-parts))
(define bound-port
  (object-rat->exact (cadr listener-parts)))
(check-true (and (exact-positive-integer? bound-port)
                 (<= bound-port 65535)))

(define test-custodian
  (make-custodian))
(define listener-closed? #f)

(define (start-worker thunk)
  (define result (box #f))
  (define worker
    (parameterize ([current-custodian test-custodian])
      (thread
       (lambda ()
         (with-handlers ([exn:fail?
                          (lambda (failure)
                            (set-box! result failure))])
           (set-box! result (thunk)))))))
  (values worker result))

(define (finish-worker worker result)
  (unless (sync/timeout 5 worker)
    (error 'http-server-test "worker timed out"))
  (define value (unbox result))
  (when (exn:fail? value)
    (raise value))
  value)

(dynamic-wind
  void
  (lambda ()
    (define-values (server-worker server-result)
      (start-worker
       (lambda ()
         (define result
           (apply2 real-serve-one
                   real-listener
                   maximum))
         ;; Demand the Result tag inside the worker so serving cannot remain a
         ;; suspended lazy computation after the thread exits.
         (unless (typed-value? result-type result)
           (error 'http-server-test "server returned a non-Result"))
         result)))
    (define-values (client-worker client-result)
      (start-worker
       (lambda ()
         (define-values (status headers body)
           (http-sendrecv #"127.0.0.1"
                          #"/lambda"
                          #:port bound-port
                          #:headers
                          (list #"User-Agent: AttaLambda-phase-18")
                          #:content-decode '()))
         (list status headers (port->bytes body)))))
    (define response
      (finish-worker client-worker client-result))
    (check-equal? (car response)
                  #"HTTP/1.1 200 OK")
    (check-not-false
     (member #"Content-Length: 17" (cadr response)))
    (check-not-false
     (member #"Connection: close" (cadr response)))
    (check-equal? (caddr response)
                  #"lambda says hello")
    (check-ok-unit
     (finish-worker server-worker server-result))
    (check-ok-unit
     (lazy-apply real-close real-listener))
    (set! listener-closed? #t))
  (lambda ()
    (custodian-shutdown-all test-custodian)
    (unless listener-closed?
      ;; Best-effort cleanup remains test infrastructure; the Result is forced
      ;; so the real host removes the listener even after an earlier assertion.
      (with-handlers ([exn:fail? (lambda (failure) (void))])
        (typed-value?
         result-type
         (lazy-apply real-close real-listener))))))

;; ---------------------------------------------------------------------------
;; Resource-exhaustion regression (security audit finding F1)
;;
;; A hostile peer can open one connection and stream bytes that never form a
;; complete request header (and never close). The server must not buffer such a
;; request without bound. It caps the accumulated request size and rejects an
;; over-limit request as a malformed-request Result (kind 10) BEFORE parsing
;; it, so no parse ever runs on an unbounded buffer and the read loop always
;; terminates. Before the fix this loop grew the buffer without limit and never
;; returned.

;; accept once, then answer every tcp-read with a fixed nonterminating chunk
;; (never a header terminator, never EOF). Raises if asked for more than
;; read-budget reads, so a regressed unbounded loop fails fast instead of
;; hanging forever.
(define (make-counting-host chunk-bytes read-budget)
  (define reads 0)
  (define traces '())
  (values
   (lambda (request)
     (set! traces (cons request traces))
     (define op
       (object-string->bytes (car (object-list->host-list request))))
     (cond
       [(bytes=? op #"tcp-accept") (object-ok connection-handle)]
       [(bytes=? op #"tcp-read")
        (set! reads (add1 reads))
        (when (> reads read-budget)
          (error 'counting-host
                 "request buffer was not bounded: ~a reads" reads))
        (object-ok (bytes->object-byte-list chunk-bytes))]
       [(bytes=? op #"tcp-close") (object-ok UNIT)]
       [else (error 'counting-host "unexpected op ~s" op)]))
   (lambda () (reverse traces))
   (lambda () reads)))

;; One oversized read (> the 8192-byte cap) is rejected before any parse.
(define-values (oversized-host oversized-traces oversized-reads)
  (make-counting-host (make-bytes 9000 (char->integer #\a)) 4))
(check-result-err-kind
 (apply2 (configure-serve-one oversized-host handler)
         listener-handle
         maximum)
 10)
(check-equal? (oversized-reads) 1)
(check-equal?
 (decoded-traces oversized-traces)
 (list (list #"tcp-accept" 1)
       (list #"tcp-read" 2 65536)
       (list #"tcp-close" 2)))

;; Sub-cap chunks that accumulate past the cap are bounded too: the loop
;; terminates after a small, fixed number of reads with the same malformed
;; Result rather than growing the buffer without limit.
(define-values (dribble-host dribble-traces dribble-reads)
  (make-counting-host (make-bytes 4500 (char->integer #\a)) 8))
(check-result-err-kind
 (apply2 (configure-serve-one dribble-host handler)
         listener-handle
         maximum)
 10)
(check-equal? (dribble-reads) 2)
(check-equal?
 (decoded-traces dribble-traces)
 (list (list #"tcp-accept" 1)
       (list #"tcp-read" 2 65536)
       (list #"tcp-read" 2 65536)
       (list #"tcp-close" 2)))

;; The whole-request server loop inherits the same bound: a nonterminating
;; connection ends with the malformed Result instead of looping forever.
(define-values (server-dos-host server-dos-traces server-dos-reads)
  (make-counting-host (make-bytes 9000 (char->integer #\a)) 4))
(check-result-err-kind
 (apply2 (configure-server server-dos-host handler)
         listener-handle
         maximum)
 10)
(check-equal? (server-dos-reads) 1)
