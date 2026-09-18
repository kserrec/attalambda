#lang racket/base
(require rackunit racket/list "../runner/static/types.rkt" "../runner/static/substitution.rkt")
(define a (type-variable 0))
(define b (type-variable 1))
(define c (type-variable 2))
(define rat (base-type 'Rat))
(define string (base-type 'String))

(test-case "substitution is structural, simultaneous, and idempotent when solved"
  (define s (compose-substitutions (hasheqv 1 rat) (hasheqv 0 b)))
  (define t (arrow-type (list-type a) (result-type b)))
  (define expected (arrow-type (list-type rat) (result-type rat)))
  (check-equal? (substitute-type s t) expected)
  (check-equal? (substitute-type s (substitute-type s t)) expected)
  (check-equal? (type-variables (arrow-type a (map-type b a))) '(0 1))
  (check-equal? (substitute-type (hasheqv 0 b 1 rat) a) b)
  (check-exn #rx"unsolved substitution" (lambda () (solution (hasheqv 0 b 1 a) '())))
  (check-exn #rx"unsolved substitution" (lambda () (solution (hasheqv 0 b 1 rat) '()))))

(test-case "composition applies the old substitution first"
  (define old (hasheqv 0 b 2 rat))
  (define new (hasheqv 1 string 2 string))
  (define combined (compose-substitutions new old))
  (for ([t (list a b c (arrow-type a c) (list-type b))])
    (check-equal? (substitute-type combined t) (substitute-type new (substitute-type old t))))
  ;; A variable introduced by new must not get substituted by old afterward.
  (check-equal? (substitute-type (compose-substitutions (hasheqv 1 a) (hasheqv 0 rat)) b) a)
  (define substitutions (list (hasheqv) (hasheqv 0 b) (hasheqv 1 a) (hasheqv 0 rat)
                              (hasheqv 1 string) (hasheqv 0 (arrow-type b c))))
  (for* ([older (in-list substitutions)] [newer (in-list substitutions)]
         [type (in-list (list a b c (arrow-type a b) (option-type c)))])
    (check-equal? (substitute-type (compose-substitutions newer older) type)
                  (substitute-type newer (substitute-type older type)))))

(test-case "scheme substitution does not capture quantified variables"
  (define value (scheme '(0) (arrow-type a b) '(0 1)))
  (check-equal? (scheme-variables-free value) '(1))
  (check-equal? (substitute-scheme (hasheqv 0 string 1 rat) value)
                (scheme '(0) (arrow-type a rat) '(0))))

(test-case "fresh instances share neither variables nor analysis counters"
  (define fresh (make-fresh 3))
  (define identity (scheme '(0) (arrow-type a a) '(0)))
  (define-values (first s1) (instantiate identity fresh))
  (define-values (second s2) (instantiate identity fresh s1))
  (check-equal? first (arrow-type (type-variable 3) (type-variable 3)))
  (check-equal? second (arrow-type (type-variable 4) (type-variable 4)))
  (check-equal? (solution-restricted s2) '(3 4))
  (check-equal? ((make-fresh)) a)
  ;; Catalog-local 0/1 renamed to fresh 1/2 must not rename 0 to 2 transitively.
  (define-values (overlap ignored)
    (instantiate (scheme '(0 1) (arrow-type a b) '()) (make-fresh 1)))
  (check-equal? overlap (arrow-type b c)))

(test-case "generalization uses the substituted environment and preserves restrictions"
  ;; Captured g:a has become b -> c. Generalizing b -> c against stale a would
  ;; wrongly quantify b/c and permit incompatible uses of the captured g.
  (define state (solution (hasheqv 0 (arrow-type b c)) '(1)))
  (define environment (list (scheme '() a '())))
  (check-equal? (generalize state environment (arrow-type b c))
                (scheme '() (arrow-type b c) '(1)))
  (define local (type-variable 3))
  (check-equal? (generalize state environment (arrow-type local b))
                (scheme '(3) (arrow-type local b) '(1)))
  (check-equal? (generalize (solution (hasheqv 0 b) '(0)) '() (list-type a))
                (scheme '(1) (list-type b) '(1))))
