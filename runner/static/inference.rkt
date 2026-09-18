#lang racket/base

;; Syntax-directed inference over the trusted source view. A conditional input
;; cursor can check remaining arguments, but is never an established value type.
(require racket/list "../../lang/static-data.rkt" "types.rkt" "proof.rkt"
         "substitution.rkt" "unification.rkt" "contracts.rkt")
(provide (struct-out judgment) (struct-out call-inputs) (struct-out binding-contract)
         infer-expression bind-judgment)
(struct judgment (type proof inputs) #:transparent)
(struct call-inputs (type remaining name position) #:transparent)
(struct binding-contract (signature proof inputs) #:transparent)
(struct input-template (signature remaining name position) #:transparent)
(define (established? state) (eq? (proof-status state) 'established))
(define (arrow? type) (and (type-form? type) (eq? (type-form-name type) 'Arrow)))
(define (arrow-count type)
  (if (arrow? type) (add1 (arrow-count (cadr (type-form-arguments type)))) 0))

(define (bind-judgment item state environment #:proof [proof (judgment-proof item)] #:name [name #f])
  (define signatures (filter values (map binding-contract-signature (hash-values environment))))
  (define inputs (judgment-inputs item))
  (cond
    [(established? (judgment-proof item))
     (define signature (generalize state signatures (judgment-type item)))
     (binding-contract signature proof
                       (or inputs (and (arrow? (scheme-type signature))
                                       (call-inputs (scheme-type signature) (arrow-count (scheme-type signature)) name 1))))]
    [else
     ;; Only the remaining audited INPUT obligations are reusable. This template
     ;; is never a value signature, and its success tail never proves an output.
     ;; Captured monomorphic variables stay tied to the substituted environment.
     (binding-contract
      #f proof
      (and inputs (input-template (generalize state signatures (call-inputs-type inputs))
                                  (call-inputs-remaining inputs) (call-inputs-name inputs)
                                  (call-inputs-position inputs))))]))

(define (infer-expression root [environment (hasheqv)]
                          #:fresh [fresh (make-fresh)] #:initial [initial empty-solution]
                          #:owner [owner #f])
  (define state initial)
  (define nodes (hasheqv))
  (define (finish type proof [inputs #f])
    (when (and (established? proof) (not (monotype? type)))
      (error 'static-inference "established obligation has no monotype"))
    (judgment (and (established? proof) type) proof inputs))
  (define (check-equation expected actual node detail)
    (define result (unify expected actual state))
    (cond [(solution? result) (set! state result) established-proof]
          [else
           (proof (map (lambda (item)
                         (problem (equation-problem-code item) (source-node-location node) owner detail
                                  (equation-problem-expected item) (equation-problem-actual item)))
                       (unsatisfied-problems result)) '())]))
  (define (instantiate-here signature)
    (define-values (type next) (instantiate signature fresh state))
    (set! state next)
    type)
  (define (solved type) (and type (apply-type state type)))
  (define (residual inputs type)
    (and inputs (> (call-inputs-remaining inputs) 1)
         (call-inputs type (sub1 (call-inputs-remaining inputs))
                      (call-inputs-name inputs) (add1 (call-inputs-position inputs)))))
  (define (call-detail inputs)
    (if (and inputs (call-inputs-name inputs))
        (format "~s argument ~a" (call-inputs-name inputs) (call-inputs-position inputs))
        "application argument"))
  (define (application node function argument environment)
    (define operator (walk function environment))
    (define operand (walk argument environment))
    (define function-type (solved (judgment-type operator)))
    (define argument-type (solved (judgment-type operand)))
    (define inherited (proof-join (judgment-proof operator) (judgment-proof operand)))
    (define inputs
      (or (judgment-inputs operator)
          (and function-type (call-inputs function-type (arrow-count function-type) #f 1))))
    (define shape (or function-type (and inputs (solved (call-inputs-type inputs)))))
    (cond
      [(arrow? shape)
       (define domain (car (type-form-arguments shape)))
       (define codomain (cadr (type-form-arguments shape)))
       (define local
         (if argument-type (check-equation domain argument-type argument (call-detail inputs)) established-proof))
       (define complete (proof-join inherited local))
       (define output (solved codomain))
       (define remaining (residual inputs output))
       (finish output complete
               (or remaining (and (established? complete) (arrow? output)
                                  (call-inputs output (arrow-count output) #f 1))))]
      [(and function-type (type-variable? function-type) argument-type)
       (define output (fresh))
       (define local (check-equation function-type (arrow-type argument-type output) node "function application"))
       (finish (solved output) (proof-join inherited local))]
      [(and function-type (not (type-variable? function-type)))
       (finish #f (proof-join inherited
                              (check-equation (arrow-type (fresh) (fresh)) function-type function "callable value")))]
      [else (finish #f inherited)]))
  (define (walk node environment)
    (define kind (source-node-kind node))
    (define data (source-node-data node))
    (define children (source-node-children node))
    (define result
      (case kind
        [(literal) (finish (base-type data) established-proof)]
        [(builtin)
         (define entry (contract-ref data))
         (define type (instantiate-here (library-contract-signature entry)))
         (define complete? (eq? (library-contract-status entry) 'complete))
         (define obligation
           (if complete? established-proof
               (proof (list (problem (library-contract-gap-code entry) (source-node-location node) owner
                                     (library-contract-reason entry) #f #f)) '())))
         (finish type obligation
                 (and (positive? (library-contract-arity entry))
                      (call-inputs type (library-contract-arity entry) data 1)))]
        [(reference)
         (define binding (hash-ref environment data (lambda () (error 'static-inference "unresolved binding token"))))
         (define signature (binding-contract-signature binding))
         (define type (and signature (instantiate-here signature)))
         (define inputs (binding-contract-inputs binding))
         (define current-inputs
           (cond [(input-template? inputs)
                  (call-inputs (instantiate-here (input-template-signature inputs))
                               (input-template-remaining inputs) (input-template-name inputs) (input-template-position inputs))]
                 [inputs (struct-copy call-inputs inputs [type type])]
                 [else #f]))
         (finish type (binding-contract-proof binding) current-inputs)]
        [(lambda)
         (define parameter (fresh))
         (define body (walk (car children)
                            (hash-set environment data (binding-contract (scheme '() parameter '()) established-proof #f))))
         (finish (and (judgment-type body) (arrow-type (solved parameter) (solved (judgment-type body))))
                 (judgment-proof body))]
        [(application) (application node (car children) (cadr children) environment)]
        [(let)
         (define initializer (walk (car children) environment))
         (define binding (bind-judgment initializer state environment))
         (define body (walk (cadr children) (hash-set environment data binding)))
         (finish (judgment-type body) (proof-join (judgment-proof initializer) (judgment-proof body))
                 (judgment-inputs body))]
        [(group) (walk (car children) environment)]
        [else (error 'static-inference "unsupported source node in elementary inference")]))
    (define id (source-node-id node))
    (when id
      (when (hash-has-key? nodes id) (error 'static-inference "duplicate expression classification"))
      (set! nodes (hash-set nodes id result)))
    result)
  (define result (walk root environment))
  (define (freeze item)
    (define inputs (judgment-inputs item))
    (judgment (solved (judgment-type item)) (judgment-proof item)
              (and inputs (struct-copy call-inputs inputs [type (solved (call-inputs-type inputs))]))))
  (values (freeze result)
          (for/hasheqv ([(id item) (in-hash nodes)]) (values id (freeze item))) state))
