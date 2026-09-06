#lang racket/base

(require rackunit
         (only-in "../core/unit.rkt" UNIT)
         racket/promise
         racket/runtime-path
         "../core/errors.rkt"
         "../core/lists.rkt"
         "../core/objects.rkt"
         "../core/pair.rkt"
         "../core/result.rkt"
         "../core/strings.rkt"
         "../core/tags.rkt"
         (only-in "../core/typed-logic.rkt"
                  FALSE
                  TRUE
                  typed-if)
         "../effects/protocol.rkt"
         "../effects/stdout.rkt"
         "../readers/bool.rkt"
         "../readers/raw-boolean.rkt"
         "../readers/type-tag.rkt"
         "../runtime/codec.rkt"
         "../runtime/host.rkt"
         "helpers/fresh-language.rkt"
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

(define stdout-request
  (lazy-apply make-stdout-request
              (bytes->object-string #"A\0\377")))

(check-equal? (procedure-arity (lazy-force host)) 1)

;; Applying host is lazy. The effect happens once when the Result is forced,
;; and forcing that same promise again reuses the cached Result.
(define output (open-output-bytes))
(define pending
  (parameterize ([current-output-port output])
    (lazy-apply host stdout-request)))

(check-equal? (get-output-bytes output) #"")
(parameterize ([current-output-port output])
  (check-true (bool->boolean
               (lazy-apply is-ok pending))))
(check-equal? (get-output-bytes output)
              #"A\0\377")
(parameterize ([current-output-port output])
  (check-true (bool->boolean
               (lazy-apply is-ok pending))))
(check-equal? (get-output-bytes output)
              #"A\0\377")
(check-equal?
 (type-tag->integer
  (lazy-apply raw-object-type
              (lazy-apply unwrap-ok pending)))
 8)

;; A host application in an unselected object-language branch remains
;; unforced and performs no output.
(define skipped-output (open-output-bytes))
(define skipped-host-call
  (lazy-apply host stdout-request))
(define selected-fallback
  (apply3 typed-if
          FALSE
          skipped-host-call
          (object-ok UNIT)))
(parameterize ([current-output-port skipped-output])
  (check-true (bool->boolean
               (lazy-apply is-ok selected-fallback))))
(check-equal? (get-output-bytes skipped-output) #"")

;; Empty output is still a successful, flushed acknowledgement.
(define empty-output (open-output-bytes))
(define empty-result
  (parameterize ([current-output-port empty-output])
    (lazy-force
     (lazy-apply
      host
      (lazy-apply make-stdout-request
                  (bytes->object-string #""))))))
(check-true (bool->boolean
             (lazy-apply is-ok empty-result)))
(check-equal? (get-output-bytes empty-output) #"")

;; A valid request whose output port fails maps to Result Err HostFailure.
(define closed-output (open-output-bytes))
(close-output-port closed-output)
(define failed-output
  (parameterize ([current-output-port closed-output])
    (lazy-force
     (lazy-apply
      host
      (lazy-apply make-stdout-request
                  (bytes->object-string #"failure"))))))

(check-true (typed-value? result-type failed-output))
(check-true (bool->boolean
             (lazy-apply is-err failed-output)))
(define host-failure
  (lazy-apply unwrap-err failed-output))
(check-equal? (error-kind-integer host-failure) 8)
(check-equal? (error-detail-strings host-failure)
              (list #"stdout" #"io-failure"))

;; The outer strict List contract remains the generalized core contract.
(define non-list-output (open-output-bytes))
(define non-list-result
  (parameterize ([current-output-port non-list-output])
    (lazy-force (lazy-apply host TRUE))))
(check-true (typed-value? error-type non-list-result))
(check-equal? (error-kind-integer non-list-result) 0)
(check-equal? (get-output-bytes non-list-output) #"")

(define incoming-error-output (open-output-bytes))
(define incoming-error-result
  (parameterize ([current-output-port incoming-error-output])
    (lazy-force (lazy-apply host invalid-nat-error))))
(check-true (typed-value? error-type incoming-error-result))
(check-equal? (error-kind-integer incoming-error-result) 2)
(check-equal? (get-output-bytes incoming-error-output) #"")

(check-invalid-request
 (lazy-force (lazy-apply host NIL))
 #""
 #"wrong-arity")

(check-invalid-request
 (lazy-force
  (lazy-apply host
              (host-list->object-list
               (list TRUE
                     (bytes->object-string #"bytes")))))
 #""
 #"wrong-type")

(check-invalid-request
 (lazy-force
  (lazy-apply host
              (host-list->object-list
               (list (bytes->object-string #"unknown")
                     (bytes->object-string #"bytes")))))
 #"unknown"
 #"unknown-operation")

(check-invalid-request
 (lazy-force
  (lazy-apply host
              (host-list->object-list
               (list stdout-operation))))
 #"stdout"
 #"wrong-arity")

(check-invalid-request
 (lazy-force
  (lazy-apply host
              (host-list->object-list
               (list stdout-operation TRUE))))
 #"stdout"
 #"wrong-type")

(check-invalid-request
 (lazy-force
  (lazy-apply host
              (host-list->object-list
               (list stdout-operation
                     (bytes->object-string #"bytes")
                     TRUE))))
 #"stdout"
 #"wrong-arity")

(check-invalid-request
 (lazy-force
  (lazy-apply host
              (host-list->object-list
               (list read-file-operation))))
 #"read-file"
 #"wrong-arity")

(check-invalid-request
 (lazy-force
  (lazy-apply host
              (host-list->object-list
               (list read-file-operation TRUE))))
 #"read-file"
 #"wrong-type")

(check-invalid-request
 (lazy-force
  (lazy-apply host
              (host-list->object-list
               (list read-file-operation
                     (bytes->object-string #"path")
                     TRUE))))
 #"read-file"
 #"wrong-arity")

(check-invalid-request
 (lazy-force
  (lazy-apply host
              (host-list->object-list
               (list write-file-operation))))
 #"write-file"
 #"wrong-arity")

(check-invalid-request
 (lazy-force
  (lazy-apply host
              (host-list->object-list
               (list write-file-operation
                     (bytes->object-string #"path")))))
 #"write-file"
 #"wrong-arity")

(check-invalid-request
 (lazy-force
  (lazy-apply host
              (host-list->object-list
               (list write-file-operation
                     TRUE
                     (bytes->object-string #"bytes")))))
 #"write-file"
 #"wrong-type")

(check-invalid-request
 (lazy-force
  (lazy-apply host
              (host-list->object-list
               (list write-file-operation
                     (bytes->object-string #"path")
                     TRUE))))
 #"write-file"
 #"wrong-type")

(check-invalid-request
 (lazy-force
  (lazy-apply host
              (host-list->object-list
               (list write-file-operation
                     (bytes->object-string #"path")
                     (bytes->object-byte-list #"bytes")
                     TRUE))))
 #"write-file"
 #"wrong-arity")

;; The pure String representation check includes each Char's canonical bit
;; payload, so a forged Char cannot touch stdout.
(define malformed-char
  (apply2 raw-make-object char-type TRUE))
(define malformed-string
  (lazy-apply
   raw-make-string
   (host-list->object-list (list malformed-char))))
(define untouched-output (open-output-bytes))
(define malformed-result
  (parameterize ([current-output-port untouched-output])
    (lazy-force
     (lazy-apply host
                 (host-list->object-list
                  (list stdout-operation malformed-string))))))
(check-invalid-request malformed-result
                       #"stdout"
                       #"wrong-type")
(check-equal? (get-output-bytes untouched-output) #"")

;; Native exit calls belong only in child processes, including malformed
;; requests: a regression must not terminate this test runner. Reuse the
;; isolated compiled installation so the existing 20-second execution deadline
;; measures the child operation rather than uncompiled source loading.
(define-runtime-path project-root "..")
(define-runtime-path lazy-helper "helpers/lazy.rkt")
(define-runtime-path tag-reader "../readers/type-tag.rkt")

(call-with-fresh-language-install
 project-root
 (lambda (installation)
   (define environment (fresh-language-install-environment installation))
   (define imports
     `(require racket/promise
               attalambda/runtime/host
               attalambda/runtime/codec
               attalambda/effects/protocol
               attalambda/core/errors
               attalambda/core/objects
               attalambda/core/pair
               attalambda/core/lists
               attalambda/core/logic
               (only-in attalambda/core/binary-nat raw-one-bits)
               (only-in attalambda/core/tags rat-type)
               (only-in attalambda/core/typed-logic TRUE)
               (file ,(path->string lazy-helper))
               (only-in (file ,(path->string tag-reader)) type-tag->integer)))
   (define (run-host-child body)
     (run-command environment racket-executable
                  (list "-e" (format "~s" `(begin ,imports ,@body)))
                  20
                  #:current-directory
                  (fresh-language-install-temporary-root installation)))

   (for ([status (in-list '(0 1))])
     (define result
       (run-host-child
        `((force
           (lazy-apply host
                       (host-list->object-list
                        (list exit-operation (exact->object-rat ,status)))))
          (display "unexpected exit return"))))
     (check-false (command-result-timed-out? result) (result-diagnostic result))
     (check-equal? (command-result-status result) status (result-diagnostic result))
     (check-equal? (command-result-stdout result) #"" (result-diagnostic result))
     (check-equal? (command-result-stderr result) #"" (result-diagnostic result)))

   ;; Test both the public bridge and its private strict dispatcher. Access to
   ;; the latter is test-only: it proves the real host's defensive decoding
   ;; still rejects malformed statuses even without the pure protocol check.
   (define invalid-result
     (run-host-child
      '((define direct
          (parameterize ([current-namespace
                          (module->namespace 'attalambda/runtime/host)])
            (eval 'dispatch-request)))
        (define noncanonical-one
          (apply2 raw-make-object rat-type
                  (apply2 raw-pair
                          (apply2 raw-pair raw-true
                                  (apply2 raw-cons raw-false
                                          (apply2 raw-cons raw-true NIL)))
                          raw-one-bits)))
        (define cases
          (list
           (list '() #"wrong-arity" #"wrong-arity")
           (list (list (exact->object-rat 0) TRUE) #"wrong-arity" #"wrong-arity")
           (list (list TRUE) #"wrong-type" #"wrong-type")
           (list (list (exact->object-rat 2)) #"out-of-range" #"out-of-range")
           (list (list (exact->object-rat -1)) #"wrong-type" #"out-of-range")
           (list (list (exact->object-rat 1/2)) #"wrong-type" #"out-of-range")
           (list (list noncanonical-one) #"wrong-type" #"out-of-range")))
        (for ([case (in-list cases)])
          (for ([invoke (in-list (list host direct))]
                [reason (in-list (cdr case))])
            (define outcome
              (force
               (lazy-apply invoke
                           (host-list->object-list
                            (cons exit-operation (car case))))))
            (unless (= (type-tag->integer (lazy-apply raw-object-type outcome)) 0)
              (error 'exit-test "malformed request did not return Error"))
            (define root (lazy-apply raw-error-root outcome))
            (define details (lazy-apply raw-error-root-details root))
            (unless (and (= (type-tag->integer (lazy-apply raw-error-root-kind root)) 7)
                         (equal? (object-string->bytes (lazy-apply raw-first details))
                                 #"exit")
                         (equal? (object-string->bytes (lazy-apply raw-second details))
                                 reason))
              (error 'exit-test "wrong malformed-request details"))))
        (display "invalid exit requests returned Errors\n"))))
   (check-command-success invalid-result #"invalid exit requests returned Errors\n")))
