#lang racket/base

;; Compare the catalog with actual facade results, using only ephemeral loopback.
;; The runtime observation is independent of the explanatory static signatures.
(require rackunit racket/list racket/promise racket/runtime-path
         "../runner/static/contracts.rkt" "../runner/static/types.rkt"
         "../runner/static/type-display.rkt"
         (prefix-in r: "../core/result.rkt") "../core/objects.rkt"
         "../readers/type-tag.rkt" "../readers/bool.rkt"
         "../runtime/codec.rkt" "helpers/lazy.rkt")
(define-runtime-path facade "../lang/expander.rkt")

(test-case "all six partial TCP success hints match real runtime payloads"
  (define handles '())
  (define owner (make-custodian))
  (define (actual-shape value)
    (case (type-tag->integer (lazy-apply raw-object-type value))
      [(7) (check-true (rational? (object-rat->exact value))) "Rat"]
      [(8) "Unit"]
      [(9) "Byte"]
      [(2)
       (define elements (object-list->host-list value))
       (check-true (pair? elements))
       (define shapes (remove-duplicates (map actual-shape elements)))
       (check-equal? (length shapes) 1)
       (format "List(~a)" (car shapes))]
      [else (error 'static-tcp-test "unexpected runtime payload tag")]))
  (define (remember value) (set! handles (cons value handles)) value)
  (define (invoke id . args)
    (define entry (contract-ref id))
    (check-eq? (library-contract-status entry) 'partial)
    (define output-type
      (for/fold ([type (scheme-type (library-contract-signature entry))])
                ([index (in-range (library-contract-arity entry))])
        (cadr (type-form-arguments type))))
    (define result
      (for/fold ([function (dynamic-require facade id)]) ([argument (in-list args)])
        (lazy-apply function argument)))
    (check-true (bool->boolean (lazy-apply r:is-ok result)))
    (define value (lazy-apply r:unwrap-ok result))
    ;; Track acquired handles before asserting the catalog, so a wrong hint
    ;; cannot skip cleanup. The custodian also covers earlier decoding failures.
    (case id
      [(tcp-listen) (remember (car (object-list->host-list value)))]
      [(tcp-connect tcp-accept) (remember value)])
    (check-equal? (format "Result(~a)" (actual-shape value))
                  (type->string output-type) (symbol->string id))
    value)
  (define (close value)
    (invoke 'tcp-close value)
    (set! handles (remq value handles)))
  (dynamic-wind
   void
   (lambda ()
     (parameterize ([current-custodian owner])
       (define fields
         (object-list->host-list
          (invoke 'tcp-listen (bytes->object-string #"127.0.0.1")
                  (exact->object-rat 0) (exact->object-rat 1))))
       (check-equal? (length fields) 2)
       (define listener (car fields))
       (define client (invoke 'tcp-connect (bytes->object-string #"127.0.0.1") (cadr fields)))
       (define server (invoke 'tcp-accept listener))
       (invoke 'tcp-write client (bytes->object-byte-list #"x"))
       (check-equal? (object-byte-list->bytes (invoke 'tcp-read server (exact->object-rat 1))) #"x")
       (close server)
       (close client)
       (close listener)
       (check-equal? handles '())))
   (lambda ()
     (for ([handle (in-list handles)])
       (force (lazy-apply (dynamic-require facade 'tcp-close) handle)))
     (custodian-shutdown-all owner))))
