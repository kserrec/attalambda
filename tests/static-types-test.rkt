#lang racket/base
(require rackunit "../runner/static/types.rkt" "../runner/static/proof.rkt")

(test-case "finite nominal types and constructor arities are explicit"
  (check-not-equal? (base-type 'String) (list-type (base-type 'Char)))
  (check-not-equal? (base-type 'Rat) (base-type 'Byte))
  (check-not-equal? (base-type 'Error) (base-type 'Rat))
  (for ([name '(Nat Int Number IOError Pair Function Any)])
    (check-exn exn:fail:contract? (lambda () (base-type name))))
  (check-exn exn:fail:contract? (lambda () (type-form 'Arrow (list (base-type 'Rat)))))
  (check-exn exn:fail:contract?
             (lambda () (type-form 'Result (list (base-type 'Rat) (base-type 'Error)))))
  (check-exn exn:fail:contract? (lambda () (type-variable -1)))
  (check-true (monotype? (map-type (base-type 'String) (result-type (base-type 'Rat))))))

(test-case "quantification and unproved obligations cannot enter monotypes"
  (define a (type-variable 0))
  (define identity (scheme '(0) (arrow-type a a) '()))
  (define gap (problem 'UNSUPPORTED_CONTRACT #f #f "raw host" #f #f))
  (check-false (monotype? identity))
  (check-false (monotype? gap))
  (check-exn exn:fail:contract? (lambda () (arrow-type identity a)))
  (check-exn exn:fail:contract? (lambda () (list-type gap)))
  (check-exn exn:fail:contract? (lambda () (scheme '(0 0) a '())))
  (check-exn exn:fail:contract? (lambda () (scheme '() gap '()))))

(test-case "closed proof states preserve conflicts, gaps and dependencies separately"
  (define gap (problem 'RECURSIVE_TYPE_REQUIRED #f #f "self application" #f #f))
  (define clash (problem 'TYPE_CONFLICT #f #f "argument" (base-type 'Rat) (base-type 'String)))
  (check-eq? (proof-status established-proof) 'established)
  (check-eq? (proof-status (proof (list gap) '())) 'unproved)
  (check-eq? (proof-status (proof '() '(2))) 'unproved)
  (define both (proof-join (proof (list gap) '(2)) (proof (list clash gap) '(2 3))))
  (check-eq? (proof-status both) 'conflict)
  (check-equal? (proof-problems both) (list gap clash))
  (check-equal? (proof-dependencies both) '(2 3))
  (check-exn exn:fail:contract? (lambda () (problem 'PENDING #f #f "unfinished" #f #f))))
