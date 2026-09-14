#lang racket/base

(require rackunit
         racket/list
         racket/runtime-path
         "../core/errors.rkt"
         "../core/objects.rkt"
         "../core/option.rkt"
         "../core/pair.rkt"
         "../core/result.rkt"
         "../core/tags.rkt"
         "../core/unit.rkt"
         (only-in "../core/typed-logic.rkt" TRUE FALSE typed-if)
         "../effects/protocol.rkt"
         "../effects/stdin.rkt"
         "../readers/bool.rkt"
         "../readers/error.rkt"
         "../readers/raw-boolean.rkt"
         "../readers/type-tag.rkt"
         "../runtime/codec.rkt"
         "../runtime/host.rkt"
         "helpers/lazy.rkt")

(define (typed-value? type value)
  (raw-boolean->boolean (apply2 raw-is-type type value)))

(define (check-host-error value kind reason)
  (check-true (typed-value? error-type value))
  (define root (lazy-apply raw-error-root value))
  (check-equal? (type-tag->integer (lazy-apply raw-error-root-kind root)) kind)
  (define details (lazy-apply raw-error-root-details root))
  (check-equal? (object-string->bytes (lazy-apply raw-first details)) #"read-line")
  (check-equal? (object-string->bytes (lazy-apply raw-second details)) reason))

(define request (lazy-apply make-read-line-request UNIT))
(define parts (object-list->host-list request))
(check-equal? (length parts) 1)
(check-equal? (object-string->bytes (car parts)) #"read-line")
(check-equal? (procedure-arity (lazy-force make-read-line-request)) 1)

;; The public unary call is checked before the injected host can run.
(define calls 0)
(define (fake-host value)
  (set! calls (add1 calls))
  (check-equal? (length (object-list->host-list value)) 1)
  (object-ok (object-some (bytes->object-string #"answer"))))
(define read-with-fake (lazy-apply make-read-line fake-host))
(check-equal? (procedure-arity (lazy-force make-read-line)) 1)
(check-equal? (procedure-arity (lazy-force read-with-fake)) 1)
(check-equal? calls 0)

(for ([function (in-list (list make-read-line-request read-with-fake))])
  (check-equal? (error-value->string (lazy-apply function TRUE))
                "read-line(arg1 expected UNIT got BOOL)")
  (check-equal? (error-value->string (lazy-apply function invalid-nat-error))
                "INVALID-NAT\n  -> read-line(arg1 expected UNIT)"))
(check-equal? calls 0)

(define pending (lazy-apply read-with-fake UNIT))
(check-equal? calls 0)
(check-true (bool->boolean (lazy-apply is-ok pending)))
(check-equal? calls 1)
(check-true (bool->boolean (lazy-apply is-ok pending)))
(check-equal? calls 1)
(check-true (bool->boolean (lazy-apply is-ok (lazy-apply read-with-fake UNIT))))
(check-equal? calls 2)

(define skipped (lazy-apply read-with-fake UNIT))
(check-true
 (bool->boolean
  (lazy-apply is-ok (apply3 typed-if FALSE skipped (object-ok UNIT)))))
(check-equal? calls 2)

;; Both absence and failures pass through without wrapper reinterpretation.
(for ([answer (in-list (list (object-ok object-none)
                             (object-err invalid-nat-error)))])
  (define wrapper (lazy-apply make-read-line (lambda (ignored) answer)))
  (check-eq? (lazy-force (lazy-apply wrapper UNIT)) (lazy-force answer)))

;; Zero-argument request schemas use the existing generalized walker.
(define dispatched 0)
(define bridge
  (lazy-apply make-host-bridge
              (lambda (value)
                (set! dispatched (add1 dispatched))
                (object-ok object-none))))
(check-true (bool->boolean (lazy-apply is-ok (lazy-apply bridge request))))
(check-equal? dispatched 1)
(for ([extra (in-list (list UNIT TRUE invalid-nat-error))])
  (define invalid
    (lazy-apply bridge (host-list->object-list (list read-line-operation extra))))
  (check-host-error invalid 7 #"wrong-arity"))
(check-equal? dispatched 1)

(define read-with-host (lazy-apply make-read-line host))
(define (read-result input)
  (parameterize ([current-input-port input])
    (lazy-force (lazy-apply read-with-host UNIT))))

(define (check-line result expected)
  (check-true (typed-value? result-type result))
  (check-true (bool->boolean (lazy-apply is-ok result)))
  (define option (lazy-apply unwrap-ok result))
  (check-true (typed-value? option-type option))
  (if expected
      (begin
        (check-true (bool->boolean (lazy-apply IS-SOME option)))
        (check-equal?
         (object-string->bytes
          (lazy-apply raw-option-value (lazy-apply raw-object-value option)))
         expected))
      (check-eq? (lazy-force option) (lazy-force NONE))))

;; Codec constructors retain canonical Option identity and payloads.
(check-eq? (lazy-force object-none) (lazy-force NONE))
(check-line (object-ok (object-some (bytes->object-string #""))) #"")

(for ([entry (in-list
             (list (list #"" (list #f))
                   (list #"\n" (list #"" #f))
                   (list #"a\r\nb\nc\rd" (list #"a" #"b" #"c" #"d" #f))
                   (list #"\r\n\r\n" (list #"" #"" #f))
                   (list #"a\r" (list #"a" #f))
                   (list #" \t a\0\377 \t\nlast" (list #" \t a\0\377 \t" #"last" #f))))])
  (define input (open-input-bytes (first entry)))
  (for ([expected (in-list (second entry))])
    (check-line (read-result input) expected))
  (check-line (read-result input) #f)
  (check-false (port-closed? input))
  (close-input-port input))

;; Every byte other than the two declared separators survives unchanged.
(define payload
  (list->bytes (filter (lambda (value) (not (member value '(10 13)))) (range 256))))
(check-line (read-result (open-input-bytes (bytes-append payload #"\n"))) payload)
(define long-line (make-bytes 4096 65))
(check-line (read-result (open-input-bytes long-line)) long-line)

;; Demand chooses the current port; no port or EOF flag is captured globally.
(define unused-input (open-input-bytes #"unused\n"))
(define delayed-read
  (parameterize ([current-input-port unused-input])
    (lazy-apply read-with-host UNIT)))
(define live-input (open-input-bytes #"first\nsecond\n"))
(check-equal? (peek-byte unused-input) 117)
(parameterize ([current-input-port live-input]) (check-line delayed-read #"first"))
(parameterize ([current-input-port live-input]) (check-line delayed-read #"first"))
(check-line (read-result live-input) #"second")
(check-line (read-result live-input) #f)
(check-line (read-result unused-input) #"unused")

;; Rejected direct requests must not consume even the first byte.
(define untouched (open-input-bytes #"still here\n"))
(define-runtime-path host-path "../runtime/host.rkt")
;; Test-only access proves defensive dispatch without the pure schema gate.
(define direct
  (parameterize ([current-namespace (module->namespace host-path)])
    (eval 'dispatch-request)))
(parameterize ([current-input-port untouched])
  (for* ([invoke (in-list (list host direct))]
         [invalid (in-list
                   (list (host-list->object-list (list read-line-operation UNIT))
                         (host-list->object-list (list read-line-operation TRUE))))])
    (check-host-error (lazy-apply invoke invalid) 7 #"wrong-arity")))
(check-line (read-result untouched) #"still here")
(parameterize ([current-input-port (open-input-bytes #"direct\n")])
  (check-line (direct request) #"direct"))

;; Native failures are stable Result Err values, never exception text.
(define closed-input (open-input-bytes #"secret"))
(close-input-port closed-input)
(define failed (read-result closed-input))
(check-true (bool->boolean (lazy-apply is-err failed)))
(check-host-error (lazy-apply unwrap-err failed) 8 #"io-failure")
(for ([entry (in-list
             (list (list (exn:fail "sensitive port details" (current-continuation-marks))
                         #"io-failure")
                   (list (exn:fail:out-of-memory "sensitive allocation details"
                                                (current-continuation-marks))
                         #"resource-exhausted")))])
  (define input
    (make-input-port 'private-input
                     (lambda (buffer) (raise (first entry))) #f void))
  (define result (read-result input))
  (check-true (bool->boolean (lazy-apply is-err result)))
  (check-host-error (lazy-apply unwrap-err result) 8 (second entry))
  (close-input-port input))
