#lang racket/base
(require rackunit racket/list "../runner/static/types.rkt"
         "../runner/static/substitution.rkt" "../runner/static/unification.rkt")
(define a (type-variable 0))
(define b (type-variable 1))
(define c (type-variable 2))
(define rat (base-type 'Rat))
(define string (base-type 'String))
(define bool (base-type 'Bool))
(define (codes result) (map equation-problem-code (unsatisfied-problems result)))

(test-case "nominal, arrow and container equations preserve exact structure"
  (define pairs
    (list (list a rat) (list a a) (list (arrow-type a b) (arrow-type rat string))
          (list (list-type a) (list-type bool))
          (list (map-type a b) (map-type string (result-type rat)))
          (list (option-type a) (option-type (list-type b)))))
  (for ([pair (in-list pairs)])
    (define result (unify (car pair) (cadr pair)))
    (check-true (solution? result))
    (check-equal? (apply-type result (car pair)) (apply-type result (cadr pair))))
  (for ([pair (in-list (list (list rat string) (list rat bool)
                             (list (base-type 'Error) rat)
                             (list string (list-type (base-type 'Char)))
                             (list (arrow-type a b) rat)
                             (list (result-type rat) rat)))])
    (check-equal? (codes (unify (car pair) (cadr pair))) '(TYPE_CONFLICT))))

(test-case "occurs checks terminate on direct and indirect infinite equations"
  (check-equal? (codes (unify a (arrow-type a b))) '(RECURSIVE_TYPE_REQUIRED))
  (define first (unify a (list-type b)))
  (check-equal? (codes (unify b (option-type a) first)) '(RECURSIVE_TYPE_REQUIRED))
  (check-equal? (apply-type first a) (list-type b))
  (check-equal? (codes (unify (arrow-type a rat) (arrow-type (arrow-type a b) string)))
                '(RECURSIVE_TYPE_REQUIRED TYPE_CONFLICT)))

(test-case "chains normalize; failures publish no partial substitutions"
  (define first (unify a b))
  (define second (unify b (list-type c) first))
  (define third (unify c rat second))
  (check-equal? (apply-type third a) (list-type rat))
  (check-equal? (apply-type third b) (list-type rat))
  (check-equal? (apply-type third (apply-type third a)) (apply-type third a))
  (define failed (unify (arrow-type a string) (arrow-type bool rat)))
  (check-equal? (codes failed) '(TYPE_CONFLICT))
  (check-equal? (apply-type empty-solution a) a)
  (check-equal? (apply-type (unify a rat) a) rat)
  (check-equal? (codes (unify (arrow-type rat string) (arrow-type bool rat)))
                '(TYPE_CONFLICT TYPE_CONFLICT)))

(test-case "bounded generated equations satisfy equality and stable substitution"
  (define atoms (list a b rat string bool))
  (define terms
    (append atoms (map list-type atoms) (map option-type atoms) (map result-type atoms)
            (for*/list ([left (in-list atoms)] [right (in-list atoms)])
              (arrow-type left right))))
  (for* ([left (in-list terms)] [right (in-list terms)])
    (define result (unify left right))
    (cond [(solution? result)
           (define solved (apply-type result left))
           (check-equal? solved (apply-type result right))
           (check-equal? (apply-type result solved) solved)
           (check-equal? (unify left right) result)]
          [else (check-true (unsatisfied? result))
                (check-not-equal? (unsatisfied-problems result) '())])))
