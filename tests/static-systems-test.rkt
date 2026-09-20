#lang racket/base
(require rackunit "../runner/static/systems.rkt")

(test-case "the two type systems are looked up by exact launcher token"
  (check-eq? (system-ref "hm") hm-system)
  (check-eq? (system-ref "simple") simple-system)
  (for ([name '("" "HM" "Simple" "fancy" "hm " #f 1)])
    (check-false (system-ref name) (format "~s" name))))

(test-case "the systems differ only in whether user bindings are generalized"
  (check-equal? (type-system-name hm-system) "hm")
  (check-equal? (type-system-name simple-system) "simple")
  (check-true (type-system-generalize? hm-system))
  (check-false (type-system-generalize? simple-system))
  (check-equal? (struct-copy type-system simple-system [generalize? #t])
                (struct-copy type-system hm-system [name "simple"])))
