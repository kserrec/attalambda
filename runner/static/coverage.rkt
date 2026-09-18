#lang racket/base

;; Final source-accounting validation. Counts describe discharged source
;; obligations, never library implementation coverage or execution probability.
(require racket/list "../../lang/static-data.rkt" "analysis.rkt" "inference.rkt"
         "proof.rkt" "types.rkt" "contracts.rkt")
(provide (struct-out check-summary) summarize-analysis coverage-percentage)
(struct check-summary (analysis verdict definitions-checked definitions-total
                                expressions-checked expressions-total problems paths) #:transparent)
(define (established? state) (eq? (proof-status state) 'established))
(define (coverage-percentage checked total)
  (unless (and (exact-nonnegative-integer? checked) (exact-nonnegative-integer? total)
               (<= checked total))
    (error 'static-coverage "invalid coverage counts"))
  (if (zero? total) "n/a"
      (let ([tenths (quotient (+ (* checked 1000) (quotient total 2)) total)])
        (format "~a.~a%" (quotient tenths 10) (remainder tenths 10)))))

(define (summarize-analysis result)
  (define (check condition reason)
    (unless condition (error 'static-coverage "invalid final analysis: ~a" reason)))
  (check (analysis? result) "missing analysis")
  (validate-catalog catalog)
  (define view (analysis-view result))
  (check (source-view? view) "missing source view")
  (validate-source-view view (length (source-view-forms view)))
  (define definitions (analysis-definitions result))
  (define expressions (analysis-expressions result))
  (define nodes (analysis-nodes result))
  (check (and (list? definitions) (andmap definition-result? definitions)
               (list? expressions) (andmap judgment? expressions) (hash? nodes))
         "malformed final states")
  (check (equal? (map definition-result-binding definitions) (source-view-bindings view))
         "missing, reordered, or duplicate declaration state")
  (check (= (length expressions) (length (source-view-expressions view))) "missing top-level state")
  (define ids (map car (source-view-registry view)))
  (check (and (andmap exact-nonnegative-integer? (hash-keys nodes))
               (equal? (sort (hash-keys nodes) <) (sort ids <))) "missing or extra source classification")
  (define by-id
    (for/hasheqv ([item (in-list definitions)])
      (values (source-binding-id (definition-result-binding item)) item)))
  (define (validate-proof state)
    (check (proof? state) "missing proof state")
    (for ([issue (in-list (proof-problems state))])
      (check (and (source-location? (problem-location issue))
                   (or (not (problem-owner issue)) (hash-has-key? by-id (problem-owner issue)))
                   (or (not (problem-expected issue)) (monotype? (problem-expected issue)))
                   (or (not (problem-actual issue)) (monotype? (problem-actual issue))))
             "malformed diagnostic"))
    (for ([id (in-list (proof-dependencies state))])
      (check (and (hash-has-key? by-id id)
                   (not (established? (definition-result-proof (hash-ref by-id id)))))
             "unresolved or established gap dependency")))
  (define (validate-judgment item)
    (check (judgment? item) "missing source judgment")
    (validate-proof (judgment-proof item))
    (check (if (established? (judgment-proof item))
               (monotype? (judgment-type item)) (not (judgment-type item)))
           "unfinished or speculative source type"))
  (for ([item (in-list definitions)])
    (validate-proof (definition-result-proof item))
    (check (if (established? (definition-result-proof item))
               (scheme? (definition-result-signature item)) (not (definition-result-signature item)))
           "unfinished or speculative declaration signature"))
  (for ([id (in-list ids)]) (validate-judgment (hash-ref nodes id)))
  (for ([item (in-list expressions)]) (validate-judgment item))
  (define (walk node)
    (define children (map walk (source-node-children node)))
    (define children-complete? (andmap values children))
    (define id (source-node-id node))
    (define complete? (or (not id) (established? (judgment-proof (hash-ref nodes id)))))
    (when (and id complete?)
      (check children-complete? "established parent has incomplete source children")
      (when (and (eq? (source-node-kind node) 'reference)
                 (hash-has-key? by-id (source-node-data node)))
        (check (established? (definition-result-proof (hash-ref by-id (source-node-data node))))
               "established reference has incomplete declaration")))
    (and complete? children-complete?))
  (for ([item (in-list definitions)])
    (define complete? (walk (source-binding-value (definition-result-binding item))))
    (when (established? (definition-result-proof item))
      (check complete? "established declaration has incomplete body")))
  (for ([node (in-list (source-view-expressions view))] [item (in-list expressions)])
    (walk node)
    (check (equal? item (hash-ref nodes (source-node-id node))) "inconsistent top-level classification"))

  ;; One memoized explanation per binding, not an enumeration of paths through
  ;; a shared dependency graph. Visit even primary nodes' edges to reject cycles.
  (define paths (make-hasheqv))
  (define visiting (make-hasheqv))
  (define (explain id)
    (check (not (hash-ref visiting id #f)) "cyclic gap dependency")
    (hash-ref
     paths id
     (lambda ()
       (hash-set! visiting id #t)
       (define state (definition-result-proof (hash-ref by-id id)))
       (define dependencies (sort (remove-duplicates (proof-dependencies state)) <))
       (define tails (map explain dependencies))
       (define path
         (cond [(pair? (proof-problems state)) (list id)]
               [(pair? tails) (cons id (car tails))]
               [else (error 'static-coverage "incomplete declaration has no primary reason")]))
       (hash-remove! visiting id)
       (hash-set! paths id path)
       path)))
  (for ([item (in-list definitions)] #:unless (established? (definition-result-proof item)))
    (explain (source-binding-id (definition-result-binding item))))
  (define all-proof
    (apply proof-join (append (map definition-result-proof definitions)
                              (map judgment-proof expressions)
                              (map (lambda (id) (judgment-proof (hash-ref nodes id))) ids))))
  (define problems
    (sort (proof-problems all-proof) <
          #:key (lambda (item) (or (source-location-position (problem-location item)) 0))))
  (define dc (count (lambda (item) (established? (definition-result-proof item))) definitions))
  (define ec (count (lambda (id) (established? (judgment-proof (hash-ref nodes id)))) ids))
  (define verdict
    (cond [(ormap (lambda (item) (eq? (problem-code item) 'TYPE_CONFLICT)) problems) 'fail]
          [(and (= dc (length definitions)) (= ec (length ids))
                (established? all-proof)) 'full]
          [else 'partial]))
  (check-summary result verdict dc (length definitions) ec (length ids) problems
                 (for/hasheqv ([(id path) (in-hash paths)]) (values id path))))
