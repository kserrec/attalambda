#lang racket/base

;; Each equation returns an immutable solution or explicit failed obligations.
;; A failed structural equation never commits any of its tentative bindings.
(require racket/list "types.rkt" "substitution.rkt")
(provide (struct-out equation-problem) (struct-out unsatisfied) unify restrict-data)
(struct equation-problem (code expected actual) #:transparent)
(struct unsatisfied (problems) #:transparent)

(define (failure code expected actual)
  (unsatisfied (list (equation-problem code expected actual))))
(define (check-many check types initial)
  (define-values (state problems)
    (for/fold ([state initial] [problems '()]) ([type (in-list types)])
      (define result (check type state))
      (if (unsatisfied? result)
          (values state (append problems (unsatisfied-problems result)))
          (values result problems))))
  (if (null? problems) state (unsatisfied (remove-duplicates problems))))

;; Restrict every payload variable, recursively. The stored Map comparator is
;; an invariant of Map's audited constructor, not one of its data parameters.
(define (restrict-data type [initial empty-solution])
  (define current (apply-type initial type))
  (cond [(type-variable? current)
         (solution (solution-bindings initial)
                   (remove-duplicates (cons (type-variable-id current) (solution-restricted initial))))]
        [(memq (type-form-name current) '(Rat Bool String Char Byte Unit)) initial]
        [(memq (type-form-name current) '(List Option Result Map))
         (check-many restrict-data (type-form-arguments current) initial)]
        [else (failure 'UNSUPPORTED_DATA_DOMAIN #f current)]))

;; Even an unrestricted variable unified with List(a) must constrain a. Arrows
;; themselves are allowed; only their nested data containers impose a domain.
(define (container-domains type initial)
  (define current (apply-type initial type))
  (cond [(type-variable? current) initial]
        [(memq (type-form-name current) '(List Option Result Map))
         (check-many restrict-data (type-form-arguments current) initial)]
        [else (check-many container-domains (type-form-arguments current) initial)]))

(define (unify expected actual [initial empty-solution])
  (unless (and (monotype? expected) (monotype? actual) (solution? initial))
    (raise-arguments-error 'unify "expected monotypes and a solved substitution"
                           "expected" expected "actual" actual "solution" initial))
  (define (bind variable type state)
    (define id (type-variable-id variable))
    (if (memv id (type-variables type))
        (failure 'RECURSIVE_TYPE_REQUIRED variable type)
        (let ([candidate
               (solution (compose-substitutions (hasheqv id type) (solution-bindings state))
                         (solution-restricted state))])
          (if (memv id (solution-restricted state))
              (restrict-data type candidate)
              (container-domains type candidate)))))
  (define (equate expected actual state)
    (define left (apply-type state expected))
    (define right (apply-type state actual))
    (cond
      [(equal? left right) state]
      [(type-variable? left) (bind left right state)]
      [(type-variable? right) (bind right left state)]
      [(not (eq? (type-form-name left) (type-form-name right)))
       (failure 'TYPE_CONFLICT left right)]
      [else
       (define-values (solved problems)
         (for/fold ([current state] [problems '()])
                   ([domain (in-list (type-form-arguments left))]
                    [range (in-list (type-form-arguments right))])
           (define result (equate domain range current))
           (if (unsatisfied? result)
               (values current (append problems (unsatisfied-problems result)))
               (values result problems))))
       (if (null? problems) solved (unsatisfied problems))]))
  (define domains (check-many container-domains (list expected actual) initial))
  (define result (equate expected actual (if (unsatisfied? domains) initial domains)))
  (cond [(and (unsatisfied? domains) (unsatisfied? result))
         (unsatisfied (remove-duplicates (append (unsatisfied-problems domains)
                                                 (unsatisfied-problems result))))]
        [(unsatisfied? domains) domains]
        [else result]))
