#lang racket/base

(require rackunit
         racket/promise
         "../core/errors.rkt"
         "../core/objects.rkt"
         (only-in "../core/pair.rkt" raw-first raw-second)
         "../core/result.rkt"
         "../core/strings.rkt"
         "../core/tags.rkt"
         (only-in "../core/typed-logic.rkt"
                  TRUE)
         "../effects/http.rkt"
         "../effects/http-response.rkt"
         "../readers/bool.rkt"
         "../readers/raw-boolean.rkt"
         "../readers/type-tag.rkt"
         "../runtime/codec.rkt"
         "helpers/lazy.rkt")

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

(define (parse bytes)
  (lazy-apply parse-http-request
              (bytes->object-string bytes)))

(define (check-parse-ok bytes expected-target)
  (define result (parse bytes))
  (check-true (typed-value? result-type result))
  (check-true (bool->boolean
               (lazy-apply is-ok result)))
  (define target
    (lazy-apply unwrap-ok result))
  (check-true (typed-value? string-type target))
  (check-equal? (object-string->bytes target)
                expected-target))

(define (check-parse-err bytes expected-kind)
  (define result (parse bytes))
  (check-true (typed-value? result-type result))
  (check-true (bool->boolean
               (lazy-apply is-err result)))
  (define error
    (lazy-apply unwrap-err result))
  (check-true (typed-value? error-type error))
  (check-equal? (error-kind-integer error)
                expected-kind
                (format "request bytes: ~s" bytes)))

(define (render status body-bytes)
  (apply2 render-http-response
          status
          (bytes->object-string body-bytes)))

(define (rendered-bytes status body-bytes)
  (define result (render status body-bytes))
  (check-true (typed-value? result-type result))
  (check-true (bool->boolean
               (lazy-apply is-ok result)))
  (object-string->bytes
   (lazy-apply unwrap-ok result)))

;; The parser returns only the origin-form target needed by the Phase 18
;; router. Method, version, and header syntax are validated before that target
;; can enter the handler.
(for ([case
       (in-list
        (list
         (list #"GET / HTTP/1.1\r\nHost: example.test\r\n\r\n"
               #"/")
         (list #"GET /hello?name=lambda HTTP/1.1\r\nHost: localhost\r\n\r\n"
               #"/hello?name=lambda")
         (list #"GET /escaped%20path?next=%2Fok HTTP/1.1\r\nHost: localhost\r\n\r\n"
               #"/escaped%20path?next=%2Fok")
         (list #"GET /pchar!$&'()*+,-.:;=@_~?query/with?mark HTTP/1.1\r\nHost: localhost\r\n\r\n"
               #"/pchar!$&'()*+,-.:;=@_~?query/with?mark")
         (list #"GET /empty-body HTTP/1.1\r\nHost: localhost\r\nContent-Length:\t00 \r\n\r\n"
               #"/empty-body")
         (list #"GET /mixed HTTP/1.1\r\nhOsT: localhost\r\n\r\n"
               #"/mixed")
         (list #"GET /headers HTTP/1.1\r\nUser-Agent: test\r\nHOST: localhost\r\nAccept: */*\r\n\r\n"
               #"/headers")
         (list #"GET /tokens HTTP/1.1\r\nHost: localhost\r\nX_Test-1:\tvalue\r\n\r\n"
               #"/tokens")))])
  (check-parse-ok (car case) (cadr case)))

;; The parser still accepts complete or partial Strings independently of the
;; server's framing loop. Every prefix before the final LF is incomplete.
(define fragmented-one
  (bytes->object-string
   #"GET /fragmented HTTP/1.1\r\nHost: localhost"))
(define fragmented-two
  (apply2 STRING-APPEND
          fragmented-one
          (bytes->object-string #"\r")))
(define fragmented-three
  (apply2 STRING-APPEND
          fragmented-two
          (bytes->object-string #"\n\r")))
(define fragmented-complete
  (apply2 STRING-APPEND
          fragmented-three
          (bytes->object-string #"\n")))

(for ([partial
       (in-list (list fragmented-one
                      fragmented-two
                      fragmented-three))])
  (define result
    (lazy-apply parse-http-request partial))
  (check-true (bool->boolean
               (lazy-apply is-err result)))
  (check-equal?
   (error-kind-integer
    (lazy-apply unwrap-err result))
   9))

(define fragmented-result
  (lazy-apply parse-http-request fragmented-complete))
(check-true (bool->boolean
             (lazy-apply is-ok fragmented-result)))
(check-equal?
 (object-string->bytes
  (lazy-apply unwrap-ok fragmented-result))
 #"/fragmented")

;; Compare each incremental decision against an independent host-byte oracle.
;; Stop when framing completes, just as the server does; the helper need not
;; remember completion across later calls. Empty helper chunks are harmless
;; (an empty TCP read, in contrast, means EOF to the server).
(define (check-scans chunks)
  (let loop ([remaining chunks] [suffix NIL] [received #""])
    (unless (null? remaining)
      (define combined (bytes-append received (car remaining)))
      (define scan
        (apply2 raw-scan-http-header-end suffix
                (lazy-apply raw-string-value
                            (bytes->object-string (car remaining)))))
      (define found
        (raw-boolean->boolean (lazy-apply raw-first scan)))
      (define next-suffix (lazy-apply raw-second scan))
      (define label (format "chunks ~s, received ~s" chunks combined))
      (check-equal? found (regexp-match? #rx#"\r\n\r\n" combined) label)
      (if found
          (check-eq? (force next-suffix) (force NIL) label)
          (let ([suffix-bytes
                 (object-string->bytes (lazy-apply raw-make-string next-suffix))])
            (check-equal? suffix-bytes
                          (subbytes combined (max 0 (- (bytes-length combined) 3)))
                          label)
            (loop (cdr remaining) next-suffix combined))))))

(for ([chunks
       (in-list
        (list
         (list #"\r\n\r\n")
         (list #"\r" #"\n\r\n")
         (list #"\r\n" #"\r\n")
         (list #"\r\n\r" #"\n")
         (list #"\r" #"\n" #"\r" #"\n")
         (list #"\r\r" #"\n\r" #"\n")
         (list #"\r\nx" #"\r\r\n" #"\r" #"\n")
         (list #"" #"\r" #"" #"\n\r" #"" #"\n")
         (list #"plain" #"\r\nx" #"\r\r" #"")
         (list #"\r\n\r\ntrailing")))])
  (check-scans chunks))

(define framing-request #"GET /split HTTP/1.1\r\nHost: localhost\r\n\r\n")
(for ([split (in-range (add1 (bytes-length framing-request)))])
  (check-scans (list (subbytes framing-request 0 split)
                     (subbytes framing-request split))))
(check-scans (for/list ([byte (in-bytes framing-request)]) (bytes byte)))
(check-equal? (procedure-arity (lazy-force raw-scan-http-header-end)) 1)
(check-equal? (procedure-arity
               (lazy-force (lazy-apply raw-scan-http-header-end NIL)))
              1)

(for ([incomplete
       (in-list
        (list #""
              #"GET / HTTP/1.1"
              #"GET / HTTP/1.1\r"
              #"GET / HTTP/1.1\r\nHost: x\r\n\r"))])
  (check-parse-err incomplete 9))

;; Once the header terminator is present, broken request-line or header
;; structure is malformed rather than incomplete.
(for ([malformed
       (in-list
        (list #"GET / HTTP/1.1\nHost: x\r\n\r\n"
              #"GET / HTTP/1.1\r\n\r\n"
              #"GET / HTTP/1.1\r\nHost: one\r\nhost: two\r\n\r\n"
              #"GET / HTTP/1.1\r\nBroken\r\nHost: x\r\n\r\n"
              #"GET / HTTP/1.1\r\nHost : x\r\n\r\n"
              #"GET / HTTP/1.1\r\nHost: x\r\n\r\nbody"
              #"GET  HTTP/1.1\r\nHost: x\r\n\r\n"
              #"GET /HTTP/1.1\r\nHost: x\r\n\r\n"
              #"GET /\rX HTTP/1.1\r\nHost: x\r\n\r\n"
              #"GET / HTTP/1.1\r\nBad/Name: x\r\nHost: x\r\n\r\n"
              #"GET / HTTP/1.1\r\nBad\0Name: x\r\nHost: x\r\n\r\n"
              #"GET / HTTP/1.1\r\nHost: x\r\nX-Test: bad\0value\r\n\r\n"
              #"GET /bad\tpath HTTP/1.1\r\nHost: x\r\n\r\n"
              #"GET /bad#fragment HTTP/1.1\r\nHost: x\r\n\r\n"
              #"GET /bad% HTTP/1.1\r\nHost: x\r\n\r\n"
              #"GET /bad%0 HTTP/1.1\r\nHost: x\r\n\r\n"
              #"GET /bad%GG HTTP/1.1\r\nHost: x\r\n\r\n"
              #"GET /bad\\path HTTP/1.1\r\nHost: x\r\n\r\n"
              #"GET /bad[path] HTTP/1.1\r\nHost: x\r\n\r\n"
              #"GET /body HTTP/1.1\r\nHost: x\r\nContent-Length: 3\r\n\r\n"
              #"GET /missing-length HTTP/1.1\r\nHost: x\r\nContent-Length:\t \r\n\r\n"
              #"GET /split-zero HTTP/1.1\r\nHost: x\r\nContent-Length: 0 0\r\n\r\n"
              #"GET /chunked HTTP/1.1\r\nHost: x\r\ntransfer-encoding: chunked\r\n\r\n"))])
  (check-parse-err malformed 10))

(for ([unsupported
       (in-list
        (list #"POST / HTTP/1.1\r\nHost: x\r\n\r\n"
              #"GET / HTTP/1.0\r\nHost: x\r\n\r\n"
              #"GET http://example.test/ HTTP/1.1\r\nHost: example.test\r\n\r\n"))])
  (check-parse-err unsupported 11))

;; The renderer owns both status text and framing headers, so caller-provided
;; data cannot inject a status line or header. String length counts protocol
;; bytes because each String element is one byte-valued Char.
(check-equal? (object-rat->exact HTTP-STATUS-OK) 200)
(check-equal? (object-rat->exact HTTP-STATUS-BAD-REQUEST) 400)
(check-equal? (object-rat->exact HTTP-STATUS-NOT-FOUND) 404)
(check-equal? (object-rat->exact
               HTTP-STATUS-INTERNAL-SERVER-ERROR)
              500)

(check-equal?
 (rendered-bytes HTTP-STATUS-OK #"")
 #"HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")

(check-equal?
 (rendered-bytes HTTP-STATUS-OK #"hello")
 #"HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\nhello")

(check-equal?
 (rendered-bytes HTTP-STATUS-BAD-REQUEST #"bad")
 #"HTTP/1.1 400 Bad Request\r\nContent-Length: 3\r\nConnection: close\r\n\r\nbad")

(check-equal?
 (rendered-bytes HTTP-STATUS-NOT-FOUND #"missing")
 #"HTTP/1.1 404 Not Found\r\nContent-Length: 7\r\nConnection: close\r\n\r\nmissing")

(check-equal?
 (rendered-bytes HTTP-STATUS-INTERNAL-SERVER-ERROR #"failure")
 #"HTTP/1.1 500 Internal Server Error\r\nContent-Length: 7\r\nConnection: close\r\n\r\nfailure")

(define ten-byte-body
  #"0123456789")
(check-equal?
 (rendered-bytes HTTP-STATUS-OK ten-byte-body)
 (bytes-append
  #"HTTP/1.1 200 OK\r\nContent-Length: 10\r\nConnection: close\r\n\r\n"
  ten-byte-body))

(define binary-body
  #"\0\200\377")
(check-equal?
 (rendered-bytes HTTP-STATUS-OK binary-body)
 (bytes-append
  #"HTTP/1.1 200 OK\r\nContent-Length: 3\r\nConnection: close\r\n\r\n"
  binary-body))

(check-equal?
 (rendered-bytes HTTP-STATUS-NOT-FOUND #"same")
 (rendered-bytes HTTP-STATUS-NOT-FOUND #"same"))

(define unsupported-status-result
  (render (exact->object-rat 201) #"created"))
(check-true (bool->boolean
             (lazy-apply is-err unsupported-status-result)))
(check-equal?
 (error-kind-integer
  (lazy-apply unwrap-err unsupported-status-result))
 12)

;; A negative or fractional status Rat is the unsupported-status Err, never
;; its magnitude's supported rendering: the status guard's
;; nonnegative-whole conjunct is load-bearing because
;; raw-rat-magnitude-bits drops the sign and denominator.
(for ([status (in-list '(-200 -404 401/2 200/3 -1/2))])
  (define negative-status-result
    (render (exact->object-rat status) #"body"))
  (check-true (bool->boolean
               (lazy-apply is-err negative-status-result))
              (format "status ~s" status))
  (check-equal?
   (error-kind-integer
    (lazy-apply unwrap-err negative-status-result))
   12
   (format "status ~s" status)))

;; Wrong runtime types remain contract Errors, including the exact remaining
;; unary absorber after a bad first renderer argument.
(check-contract-error
 (lazy-apply parse-http-request TRUE)
 #"parse-http-request"
 1
 6)

(define wrong-status-partial
  (lazy-apply render-http-response TRUE))
(check-equal? (procedure-arity
               (lazy-force wrong-status-partial))
              1)
(check-contract-error
 (lazy-apply
  wrong-status-partial
  (delay
    (error 'http
           "forced body after first renderer mismatch")))
 #"render-http-response"
 1
 7)

(check-contract-error
 (apply2 render-http-response
         HTTP-STATUS-OK
         TRUE)
 #"render-http-response"
 2
 6)

(define bubbled-parse-error
  (lazy-apply parse-http-request invalid-nat-error))
(check-true (typed-value? error-type bubbled-parse-error))
(check-equal? (error-kind-integer bubbled-parse-error) 2)
(define bubbled-frame
  (first-error-frame bubbled-parse-error))
(check-equal?
 (object-string->bytes
  (lazy-apply raw-error-frame-function-name bubbled-frame))
 #"parse-http-request")
(check-equal?
 (type-tag->integer
  (lazy-apply raw-error-frame-argument-position bubbled-frame))
 1)
(check-equal?
 (type-tag->integer
  (lazy-apply raw-error-frame-expected-type bubbled-frame))
 6)

(check-equal? (procedure-arity
               (lazy-force parse-http-request))
              1)
(check-equal? (procedure-arity
               (lazy-force render-http-response))
              1)
(check-equal? (procedure-arity
               (lazy-force
                (lazy-apply render-http-response
                            HTTP-STATUS-OK)))
              1)
