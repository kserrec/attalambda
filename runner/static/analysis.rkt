#lang racket/base

;; Dependency order is for analysis only. No runtime module is reordered or run.
(require racket/list "../../lang/static-data.rkt" "inference.rkt" "proof.rkt"
         "types.rkt" "substitution.rkt" "unification.rkt" "contracts.rkt")
(provide (struct-out definition-result) (struct-out analysis) analyze-view analysis-proof)
(struct definition-result (binding signature proof) #:transparent)
(struct analysis (view definitions expressions nodes) #:transparent)
(define (analysis-proof result)
  (apply proof-join
         (append (map definition-result-proof (analysis-definitions result))
                 (map judgment-proof (analysis-expressions result)))))

(define (analyze-view view)
  (validate-catalog catalog)
  (validate-source-view view (length (source-view-forms view)))
  (define bindings (source-view-bindings view))
  (define sources (for/hasheqv ([binding (in-list bindings)]) (values (source-binding-id binding) binding)))
  (define (global-references node)
    (append (if (and (eq? (source-node-kind node) 'reference) (hash-has-key? sources (source-node-data node)))
                (list (source-node-data node)) '())
            (append-map global-references (source-node-children node))))
  (for ([binding (in-list bindings)])
    (define actual
      (remove-duplicates
       (filter (lambda (id) (not (and (source-binding-recursive? binding) (= id (source-binding-id binding)))))
               (global-references (source-binding-value binding)))))
    (unless (equal? (sort actual <) (sort (source-binding-dependencies binding) <))
      (error 'static-analysis "incomplete source dependency metadata")))
  (define fresh (make-fresh))
  (define environment (hasheqv))
  (define results (hasheqv))
  (define nodes (hasheqv))
  (define (collect new)
    (for ([(id judgment) (in-hash new)])
      (when (hash-has-key? nodes id) (error 'static-analysis "duplicate source classification"))
      (set! nodes (hash-set nodes id judgment))))
  (define (infer-binding source)
    (define id (source-binding-id source))
    (define recursive? (source-binding-recursive? source))
    (define assumption (and recursive? (fresh)))
    (define context
      (if recursive?
          (hash-set environment id (binding-contract (scheme '() assumption '()) established-proof #f))
          environment))
    (define-values (body classified state)
      (infer-expression (source-binding-value source) context #:fresh fresh #:owner id))
    (define consistency
      (and recursive? (judgment-type body) (unify assumption (judgment-type body) state)))
    (define final-state (if (solution? consistency) consistency state))
    (define final-proof
      (if (unsatisfied? consistency)
          (proof-join
           (judgment-proof body)
           (proof (map (lambda (item)
                         (problem (equation-problem-code item) (source-binding-location source) id
                                  "recursive definition must match its monomorphic self assumption"
                                  (equation-problem-expected item) (equation-problem-actual item)))
                       (unsatisfied-problems consistency)) '()))
          (judgment-proof body)))
    (define complete? (eq? (proof-status final-proof) 'established))
    (define (normalize item)
      (define inputs (judgment-inputs item))
      (judgment (and (judgment-type item) (apply-type final-state (judgment-type item)))
                (judgment-proof item)
                (and inputs (struct-copy call-inputs inputs [type (apply-type final-state (call-inputs-type inputs))]))))
    (define final-nodes
      (for/hasheqv ([(key item) (in-hash classified)]) (values key (normalize item))))
    ;; The self assumption is local proof context. Success discharges it. On
    ;; failure, only nodes using that failed assumption lose their provisional
    ;; classification; independent literals and references keep their evidence.
    (when (and recursive? (not complete?))
      (define (invalidate-self node)
        (define children (map invalidate-self (source-node-children node)))
        (define depends?
          (or (and (eq? (source-node-kind node) 'reference) (= (source-node-data node) id))
              (ormap values children)))
        (define key (source-node-id node))
        (when (and depends? key)
          (define item (hash-ref final-nodes key))
          (set! final-nodes
                (hash-set final-nodes key
                          (judgment #f (proof-join (judgment-proof item) (proof '() (list id))) #f))))
        depends?)
      (invalidate-self (source-binding-value source)))
    (define item (normalize body))
    (values (judgment (and complete? (judgment-type item)) final-proof
                      (and (or (not recursive?) complete?) (judgment-inputs item)))
            final-nodes final-state))
  (define (visit id visiting)
    (when (memv id visiting) (error 'static-analysis "cyclic source dependency metadata"))
    (unless (hash-has-key? results id)
      (define source (hash-ref sources id (lambda () (error 'static-analysis "unknown source dependency"))))
      (for ([dependency (in-list (source-binding-dependencies source))])
        (visit dependency (cons id visiting)))
      (define-values (item classified state)
        (infer-binding source))
      (define entry
        (bind-judgment item state environment #:name (source-binding-name source)
                       #:proof (if (eq? (proof-status (judgment-proof item)) 'established)
                                   established-proof (proof '() (list id)))))
      (collect classified)
      (set! environment (hash-set environment id entry))
      (set! results (hash-set results id (definition-result source (binding-contract-signature entry) (judgment-proof item))))))
  (for ([source (in-list bindings)]) (visit (source-binding-id source) '()))
  (define expressions
    (for/list ([source (in-list (source-view-expressions view))])
      (define-values (item classified state) (infer-expression source environment #:fresh fresh))
      (collect classified)
      item))
  (unless (equal? (sort (hash-keys nodes) <) (sort (map car (source-view-registry view)) <))
    (error 'static-analysis "missing source classification"))
  (analysis view (map (lambda (source) (hash-ref results (source-binding-id source))) bindings) expressions nodes))
