#lang racket/base

;; Proof state never pretends that an unchecked result is a type variable.
;; One region may contain conflicts and gaps together. Dependencies point only
;; to incomplete source bindings, not a recursion rule's local assumption.
(require racket/list)
(provide (struct-out problem) (struct-out proof) established-proof
         proof-status proof-join)

(define problem-codes
  '(TYPE_CONFLICT RECURSIVE_TYPE_REQUIRED UNREPRESENTED_ERROR_ALTERNATIVE
    UNSUPPORTED_DATA_DOMAIN UNSUPPORTED_CONTRACT))
(struct problem (code location owner detail expected actual) #:transparent
  #:guard
  (lambda (code location owner detail expected actual who)
    (unless (and (memq code problem-codes) (string? detail))
      (raise-arguments-error who "invalid proof problem" "code" code "detail" detail))
    (values code location owner detail expected actual)))
(struct proof (problems dependencies) #:transparent
  #:guard
  (lambda (problems dependencies who)
    (unless (and (list? problems) (andmap problem? problems)
                 (list? dependencies) (andmap exact-nonnegative-integer? dependencies))
      (raise-arguments-error who "invalid proof state"
                             "problems" problems "dependencies" dependencies))
    (values problems dependencies)))
(define established-proof (proof '() '()))
(define (proof-status state)
  (cond [(ormap (lambda (item) (eq? (problem-code item) 'TYPE_CONFLICT))
                (proof-problems state)) 'conflict]
        [(and (null? (proof-problems state)) (null? (proof-dependencies state))) 'established]
        [else 'unproved]))
(define (proof-join . states)
  (proof (remove-duplicates (append-map proof-problems states))
         (remove-duplicates (append-map proof-dependencies states))))
