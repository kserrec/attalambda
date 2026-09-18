#lang racket/base
(require rackunit racket/list "../runner/static/types.rkt"
         "../runner/static/substitution.rkt" "../runner/static/unification.rkt")
(define a (type-variable 0))
(define b (type-variable 1))
(define rat (base-type 'Rat))
(define string (base-type 'String))
(define function (arrow-type rat rat))
(define (codes result) (map equation-problem-code (unsatisfied-problems result)))

(test-case "canonical data includes nested containers but excludes functions and Error"
  (for ([type (list rat (base-type 'Bool) (base-type 'Char) (base-type 'Byte)
                    string (base-type 'Unit) (list-type rat) (option-type (list-type string))
                    (result-type rat) (map-type string (result-type rat)))])
    (check-true (solution? (restrict-data type))))
  (for ([type (list function (base-type 'Error) (list-type function)
                    (option-type (list-type (base-type 'Error))))])
    (check-equal? (codes (restrict-data type)) '(UNSUPPORTED_DATA_DOMAIN)))
  (check-true (solution? (unify function function)))
  (check-true (solution? (unify (base-type 'Error) (base-type 'Error)))))

(test-case "restricted variable linking and container formation constrain every nested variable"
  (define restricted (restrict-data a))
  (define linked (unify a b restricted))
  (check-equal? (codes (unify b function linked)) '(UNSUPPORTED_DATA_DOMAIN))
  (check-true (solution? (unify b rat linked)))
  (define nested (unify a (option-type (list-type b)) restricted))
  (check-equal? (codes (unify b function nested)) '(UNSUPPORTED_DATA_DOMAIN))
  (check-equal? (codes (unify b (base-type 'Error) nested)) '(UNSUPPORTED_DATA_DOMAIN))
  (define formation (unify a (list-type b)))
  (check-equal? (codes (unify b function formation)) '(UNSUPPORTED_DATA_DOMAIN))
  (check-equal? (codes (unify (list-type function) (list-type function))) '(UNSUPPORTED_DATA_DOMAIN)))

(test-case "restrictions survive generalization and independent instantiation"
  (define state (unify a (list-type b)))
  (define value (generalize state '() (arrow-type b a)))
  (check-equal? (scheme-restricted value) '(1))
  (define-values (instance instantiated) (instantiate value (make-fresh 3)))
  (check-equal? (codes (unify instance (arrow-type function (list-type function)) instantiated))
                '(UNSUPPORTED_DATA_DOMAIN))
  (check-true (solution? (unify instance (arrow-type rat (list-type rat)) instantiated)))
  (check-equal? (apply-type instantiated instance) instance))

(test-case "failed restrictions are atomic and do not hide nominal conflicts"
  (define restricted (restrict-data a))
  (define failed (unify (arrow-type a rat) (arrow-type function string) restricted))
  (check-equal? (codes failed) '(UNSUPPORTED_DATA_DOMAIN TYPE_CONFLICT))
  (check-equal? (apply-type restricted a) a)
  (check-true (solution? (unify a string restricted)))
  (define payload (map-type b function))
  (check-equal? (codes (restrict-data payload)) '(UNSUPPORTED_DATA_DOMAIN))
  ;; Restricting b while inspecting a rejected Map cannot leak into another equation.
  (check-true (solution? (unify b function)))
  (check-equal? (codes (unify (list-type rat) (list-type string))) '(TYPE_CONFLICT)))
