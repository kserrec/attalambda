#lang s-exp "../macros/lazy-with-macros.rkt"

(require "../macros/macros.rkt"
         "../core/binary-nat.rkt"
         (only-in "../core/errors.rkt"
                  NIL
                  raw-make-error
                  raw-make-error-root)
         "../core/fix.rkt"
         (only-in "../core/lists.rkt"
                  raw-cons
                  raw-append
                  raw-list-head
                  raw-list-is-nil
                  raw-list-object
                  raw-list-tail)
         "../core/logic.rkt"
         "../core/objects.rkt"
         "../core/pair.rkt"
         "../core/strings.rkt"
         "../core/tags.rkt"
         "../core/typecheck.rkt")

(provide invalid-host-request-kind
         host-failure-kind
         host-function-name
         stdout-function-name
         read-file-function-name
         write-file-function-name
         tcp-connect-function-name
         tcp-listen-function-name
         tcp-accept-function-name
         tcp-read-function-name
         tcp-write-function-name
         tcp-close-function-name
         exit-function-name
         stdout-operation
         read-file-operation
         write-file-operation
         tcp-connect-operation
         tcp-listen-operation
         tcp-accept-operation
         tcp-read-operation
         tcp-write-operation
         tcp-close-operation
         exit-operation
         unknown-operation-reason
         wrong-arity-reason
         wrong-type-reason
         out-of-range-reason
         not-found-code
         permission-denied-code
         invalid-path-code
         invalid-text-code
         invalid-handle-code
         wrong-handle-kind-code
         address-in-use-code
         connection-refused-code
         connection-reset-code
         broken-pipe-code
         network-unreachable-code
         name-resolution-failed-code
         resource-exhausted-code
         timed-out-code
         io-failure-code
         make-invalid-host-request
         make-host-failure
         make-host-bridge
         raw-dispatch-or-bubble)

;; Error kinds 0 through 6 are owned by the completed core. Host protocol
;; failures extend only the approved tiny metadata namespace; they do not add
;; object-language types or ordinary numeric values.
(def invalid-host-request-kind =
  (church-succ church-six))

(def host-failure-kind =
  (church-succ invalid-host-request-kind))

(def raw-name-char bits =
  ((raw-make-object char-type) bits))

(def raw-name-string chars =
  ((raw-make-object string-type) chars))

(define-function-name host-function-name host)
(define-function-name stdout-function-name stdout)
(define-function-name read-file-function-name read-file)
(define-function-name write-file-function-name write-file)
(define-function-name tcp-connect-function-name tcp-connect)
(define-function-name tcp-listen-function-name tcp-listen)
(define-function-name tcp-accept-function-name tcp-accept)
(define-function-name tcp-read-function-name tcp-read)
(define-function-name tcp-write-function-name tcp-write)
(define-function-name tcp-close-function-name tcp-close)
(define-function-name exit-function-name exit)
(define-function-name stdout-operation stdout)
(define-function-name read-file-operation read-file)
(define-function-name write-file-operation write-file)
(define-function-name tcp-connect-operation tcp-connect)
(define-function-name tcp-listen-operation tcp-listen)
(define-function-name tcp-accept-operation tcp-accept)
(define-function-name tcp-read-operation tcp-read)
(define-function-name tcp-write-operation tcp-write)
(define-function-name tcp-close-operation tcp-close)
(define-function-name exit-operation exit)

(define-function-name unknown-operation-reason unknown-operation)
(define-function-name wrong-arity-reason wrong-arity)
(define-function-name wrong-type-reason wrong-type)
(define-function-name out-of-range-reason out-of-range)

(define-function-name not-found-code not-found)
(define-function-name permission-denied-code permission-denied)
(define-function-name invalid-path-code invalid-path)
(define-function-name invalid-text-code invalid-text)
(define-function-name invalid-handle-code invalid-handle)
(define-function-name wrong-handle-kind-code wrong-handle-kind)
(define-function-name address-in-use-code address-in-use)
(define-function-name connection-refused-code connection-refused)
(define-function-name connection-reset-code connection-reset)
(define-function-name broken-pipe-code broken-pipe)
(define-function-name network-unreachable-code network-unreachable)
(define-function-name name-resolution-failed-code name-resolution-failed)
(define-function-name resource-exhausted-code resource-exhausted)
(define-function-name timed-out-code timed-out)
(define-function-name io-failure-code io-failure)

(def raw-make-host-protocol-error kind operation detail =
  ((raw-make-error
    ((raw-make-error-root kind)
     ((raw-pair operation) detail)))
   NIL))

(def make-invalid-host-request operation reason =
  (((raw-make-host-protocol-error invalid-host-request-kind)
    operation)
   reason))

(def make-host-failure operation code =
  (((raw-make-host-protocol-error host-failure-kind)
    operation)
   code))

(def host-list-signature =
  ((raw-cons list-type) NIL))

(def raw-invalid-request operation reason =
  ((make-invalid-host-request operation) reason))

(def raw-four-true-bits =
  ((raw-cons raw-true)
   ((raw-cons raw-true)
    ((raw-cons raw-true)
     ((raw-cons raw-true) NIL)))))

(def raw-eight-true-bits =
  ((raw-append raw-four-true-bits)
   raw-four-true-bits))

(def raw-sixteen-true-bits =
  ((raw-append raw-eight-true-bits)
   raw-eight-true-bits))

(def raw-four-false-bits =
  ((raw-cons raw-false)
   ((raw-cons raw-false)
    ((raw-cons raw-false)
     ((raw-cons raw-false) NIL)))))

(def raw-eight-false-bits =
  ((raw-append raw-four-false-bits)
   raw-four-false-bits))

(def raw-sixteen-false-bits =
  ((raw-append raw-eight-false-bits)
   raw-eight-false-bits))

(def raw-port-maximum-bits =
  raw-sixteen-true-bits)

(def raw-read-maximum-bits =
  ((raw-cons raw-true)
   raw-sixteen-false-bits))

(def raw-unconstrained-argument value =
  raw-true)

(def raw-nonempty-string-argument value =
  (raw-not
   (raw-list-is-nil
    (raw-string-value value))))

(def raw-nonzero-count-argument value =
  (raw-not
   (raw-nat-is-zero
    (raw-rat-field-magnitude value))))

(def raw-port-argument value =
  ((raw-and
    (raw-nonzero-count-argument value))
   ((raw-nat-less-equal
     (raw-rat-field-magnitude value))
    raw-port-maximum-bits)))

(def raw-listen-port-argument value =
  ((raw-nat-less-equal
    (raw-rat-field-magnitude value))
   raw-port-maximum-bits))

(def raw-read-maximum-argument value =
  ((raw-and
    (raw-nonzero-count-argument value))
   ((raw-nat-less-equal
     (raw-rat-field-magnitude value))
    raw-read-maximum-bits)))

(def raw-exit-argument value =
  ((raw-nat-less-equal
    (raw-rat-field-magnitude value))
   raw-one-bits))

(def raw-bit-representation-valid bit =
  (lambda-let selected =
    ((bit list-type) char-type)
    ((raw-or
      ((raw-tag-equal list-type) selected))
     ((raw-tag-equal char-type) selected))))

(def raw-proper-bit-list-step recur value =
  (((raw-if
     ((raw-is-type list-type) value))
    (((raw-if
       (raw-list-is-nil value))
      raw-true)
     (((raw-if
        (raw-bit-representation-valid
         (raw-list-head value)))
       (recur
        (raw-list-tail value)))
      raw-false)))
   raw-false))

(def raw-proper-bit-list value =
  ((raw-fix raw-proper-bit-list-step) value))

(def raw-normalized-bit-list value =
  (((raw-if
     (raw-list-is-nil value))
    raw-false)
   (((raw-if
      (raw-list-is-nil
       (raw-list-tail value)))
     raw-true)
    (raw-list-head value))))

(def raw-char-representation-valid value =
  (((raw-if
     ((raw-is-type char-type) value))
    (lambda-let bits =
      (raw-object-value value)
      (((raw-if
         (raw-proper-bit-list bits))
        (((raw-if
           (raw-normalized-bit-list bits))
          ((raw-nat-less-equal bits)
           raw-eight-true-bits))
         raw-false))
       raw-false)))
   raw-false))

(def raw-proper-list-satisfying-step recur predicate value =
  (((raw-if
     ((raw-is-type list-type) value))
    (((raw-if
       (raw-list-is-nil value))
      raw-true)
     (((raw-if
        (predicate
         (raw-list-head value)))
       ((recur predicate)
        (raw-list-tail value)))
      raw-false)))
   raw-false))

(def raw-proper-list-satisfying predicate value =
  (((raw-fix raw-proper-list-satisfying-step)
    predicate)
   value))

(def raw-string-representation-valid value =
  ((raw-proper-list-satisfying
    raw-char-representation-valid)
   (raw-string-value value)))

(def raw-byte-representation-valid value =
  (((raw-if
     ((raw-is-type byte-type) value))
    (lambda-let bits =
      (raw-object-value value)
      (((raw-if
         (raw-proper-bit-list bits))
        (((raw-if
           (raw-normalized-bit-list bits))
          ((raw-nat-less-equal bits)
           raw-eight-true-bits))
         raw-false))
       raw-false)))
   raw-false))

(def raw-byte-list-representation-valid value =
  ((raw-proper-list-satisfying
    raw-byte-representation-valid)
   value))

(def raw-rat-field-magnitude value =
  (raw-second
   (raw-first
    (raw-object-value value))))

(def raw-rat-field-denominator value =
  (raw-second
   (raw-object-value value)))

;; A numeric request field is a canonical nonnegative whole Rat: positive
;; sign bit, proper normalized magnitude bits, and denominator exactly one.
(def raw-whole-rat-representation-valid value =
  (lambda-let sign =
    (raw-first
     (raw-first
      (raw-object-value value)))
    (((raw-if
       (raw-bit-representation-valid sign))
      (((raw-if sign)
        ((raw-and
          ((raw-and
            (raw-proper-bit-list
             (raw-rat-field-magnitude value)))
           (raw-normalized-bit-list
            (raw-rat-field-magnitude value))))
         ((raw-and
           ((raw-and
             (raw-proper-bit-list
              (raw-rat-field-denominator value)))
            (raw-list-is-nil
             (raw-list-tail
              (raw-rat-field-denominator value)))))
          (raw-list-head
           (raw-rat-field-denominator value)))))
       raw-false))
     raw-false)))

(def raw-make-argument-rule expected-type representation-valid constraint =
  ((raw-pair expected-type)
   ((raw-pair representation-valid) constraint)))

(def raw-string-rule =
  (((raw-make-argument-rule string-type)
    raw-string-representation-valid)
   raw-unconstrained-argument))

(def raw-nonempty-string-rule =
  (((raw-make-argument-rule string-type)
    raw-string-representation-valid)
   raw-nonempty-string-argument))

(def raw-handle-rule =
  (((raw-make-argument-rule rat-type)
    raw-whole-rat-representation-valid)
   raw-nonzero-count-argument))

(def raw-port-rule =
  (((raw-make-argument-rule rat-type)
    raw-whole-rat-representation-valid)
   raw-port-argument))

(def raw-listen-port-rule =
  (((raw-make-argument-rule rat-type)
    raw-whole-rat-representation-valid)
   raw-listen-port-argument))

(def raw-read-maximum-rule =
  (((raw-make-argument-rule rat-type)
    raw-whole-rat-representation-valid)
   raw-read-maximum-argument))

(def raw-exit-rule =
  (((raw-make-argument-rule rat-type)
    raw-whole-rat-representation-valid)
   raw-exit-argument))

(def raw-exit-schema =
  ((raw-cons raw-exit-rule) NIL))

(def raw-one-string-schema =
  ((raw-cons raw-string-rule) NIL))

(def raw-byte-list-rule =
  (((raw-make-argument-rule list-type)
    raw-byte-list-representation-valid)
   raw-unconstrained-argument))

(def raw-string-and-byte-list-schema =
  ((raw-cons raw-string-rule)
   ((raw-cons raw-byte-list-rule) NIL)))

(def raw-tcp-connect-schema =
  ((raw-cons raw-nonempty-string-rule)
   ((raw-cons raw-port-rule) NIL)))

(def raw-tcp-listen-schema =
  ((raw-cons raw-string-rule)
   ((raw-cons raw-listen-port-rule)
    ((raw-cons raw-port-rule) NIL))))

(def raw-tcp-handle-schema =
  ((raw-cons raw-handle-rule) NIL))

(def raw-tcp-read-schema =
  ((raw-cons raw-handle-rule)
   ((raw-cons raw-read-maximum-rule) NIL)))

(def raw-tcp-write-schema =
  ((raw-cons raw-handle-rule)
   ((raw-cons raw-byte-list-rule) NIL)))

(def raw-validate-request-arguments-step recur dispatcher request operation arguments rules =
  (((raw-if
     ((raw-is-type list-type) arguments))
    (((raw-if
       (raw-list-is-nil rules))
      (((raw-if
         (raw-list-is-nil arguments))
        (dispatcher request))
       ((raw-invalid-request operation)
        wrong-arity-reason)))
     (((raw-if
        (raw-list-is-nil arguments))
       ((raw-invalid-request operation)
        wrong-arity-reason))
      (lambda-let argument =
        (raw-list-head arguments)
        (lambda-let rule =
          (raw-list-head rules)
          (((raw-if
             ((raw-is-type
               (raw-first rule))
              argument))
            (lambda-let predicates =
              (raw-second rule)
              (((raw-if
                 ((raw-first predicates) argument))
                (((raw-if
                   ((raw-second predicates) argument))
                  (((((recur dispatcher)
                      request)
                     operation)
                    (raw-list-tail arguments))
                   (raw-list-tail rules)))
                 ((raw-invalid-request operation)
                  out-of-range-reason)))
               ((raw-invalid-request operation)
                wrong-type-reason))))
           ((raw-invalid-request operation)
            wrong-type-reason)))))))
   ((raw-invalid-request operation)
    wrong-type-reason)))

(def raw-validate-request-arguments dispatcher request operation arguments rules =
  ((((((raw-fix raw-validate-request-arguments-step)
       dispatcher)
      request)
     operation)
    arguments)
   rules))

(def raw-make-operation-entry operation schema =
  ((raw-pair operation) schema))

(def raw-operation-table =
  ((raw-cons
    ((raw-make-operation-entry stdout-operation)
     raw-one-string-schema))
   ((raw-cons
     ((raw-make-operation-entry read-file-operation)
      raw-one-string-schema))
    ((raw-cons
      ((raw-make-operation-entry write-file-operation)
       raw-string-and-byte-list-schema))
     ((raw-cons
       ((raw-make-operation-entry tcp-connect-operation)
        raw-tcp-connect-schema))
      ((raw-cons
        ((raw-make-operation-entry tcp-listen-operation)
         raw-tcp-listen-schema))
       ((raw-cons
         ((raw-make-operation-entry tcp-accept-operation)
          raw-tcp-handle-schema))
        ((raw-cons
          ((raw-make-operation-entry tcp-read-operation)
           raw-tcp-read-schema))
         ((raw-cons
           ((raw-make-operation-entry tcp-write-operation)
            raw-tcp-write-schema))
          ((raw-cons
            ((raw-make-operation-entry tcp-close-operation)
             raw-tcp-handle-schema))
           ((raw-cons
             ((raw-make-operation-entry exit-operation)
              raw-exit-schema))
            NIL)))))))))))

(def raw-dispatch-known-operation-step recur dispatcher request operation arguments entries =
  (((raw-if
     (raw-list-is-nil entries))
    ((raw-invalid-request operation)
     unknown-operation-reason))
   (lambda-let entry =
     (raw-list-head entries)
     (((raw-if
        ((raw-string-equal
          (raw-string-value operation))
         (raw-string-value
          (raw-first entry))))
       (((((raw-validate-request-arguments dispatcher)
          request)
         operation)
        arguments)
       (raw-second entry)))
      (((((recur dispatcher)
          request)
         operation)
        arguments)
       (raw-list-tail entries))))))

(def raw-dispatch-known-operation dispatcher request operation arguments =
  ((((((raw-fix raw-dispatch-known-operation-step)
       dispatcher)
      request)
     operation)
    arguments)
   raw-operation-table))

(def raw-validate-host-request dispatcher request =
  (((raw-if
     (raw-list-is-nil request))
    ((raw-invalid-request EMPTY-STRING)
     wrong-arity-reason))
   (lambda-let operation =
     (raw-list-head request)
     (((raw-if
        ((raw-is-type string-type) operation))
       (((raw-if
          (raw-string-representation-valid operation))
         (lambda-let arguments =
           (raw-list-tail request)
           (((raw-if
              ((raw-is-type list-type) arguments))
             ((((raw-dispatch-known-operation dispatcher)
                request)
               operation)
              arguments))
            ((raw-invalid-request operation)
             wrong-type-reason))))
        ((raw-invalid-request EMPTY-STRING)
         wrong-type-reason)))
      ((raw-invalid-request EMPTY-STRING)
       wrong-type-reason)))))

(def raw-host-function dispatcher request-payload =
  ((raw-validate-host-request dispatcher)
   (raw-list-object request-payload)))

(def raw-dispatch-or-bubble host request =
  (((raw-if
     ((raw-is-type error-type) request))
    request)
   (host request)))

;; The resulting value is the sole unary object-language boundary. Validation
;; above is ordinary lambda computation; only a schema-valid request reaches
;; the injected strict dispatcher.
(def make-host-bridge dispatcher =
  ((((make-typed-function
      (raw-host-function dispatcher))
     host-function-name)
    host-list-signature)
   raw-keep-return))
