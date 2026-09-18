#lang racket/base

(require rackunit racket/list racket/runtime-path racket/string
         "../runner/static/frontend.rkt" "../runner/source-file.rkt"
         "../lang/static-data.rkt")
(define-runtime-path facade "../lang/expander.rkt")
(define (view text)
  (prepare-source (validated-source 'bindings.attl text 2 0 17) #:analysis? #t))
(define (nodes node) (cons node (append-map nodes (source-node-children node))))
(define (all-nodes result)
  (append-map nodes (append (map source-binding-value (source-view-bindings result))
                            (source-view-expressions result))))
(define (kind-nodes result kind)
  (filter (lambda (node) (eq? (source-node-kind node) kind)) (all-nodes result)))
(define (builtins result) (map source-node-data (kind-nodes result 'builtin)))

(test-case "actual public binding identity supplies every catalog label"
  (define names
    (parameterize ([current-namespace (make-base-namespace)])
      (dynamic-require facade #f)
      (define-values (variables transformers) (module->exports facade))
      (sort (remove-duplicates
             (for*/list ([groups (in-list (list variables transformers))]
                         [group (in-list groups)] #:when (equal? (car group) 0)
                         [entry (in-list (cdr group))]
                         #:unless (memq (car entry) '(#%top #%app #%datum #%module-begin def lambda rec let list cond)))
               (car entry))) symbol<?)))
  (define text (string-join (map symbol->string names) " "))
  (check-equal? (builtins (view text)) names))

(test-case "local names and aliases cannot impersonate builtins"
  (for ([text '("(def add x = x) (add \"s\")"
                "(lambda (if) (if 1))"
                "(let cons = (lambda (x) x) (cons 1))"
                "(let ((add (lambda (x) x)) (alias add)) (alias 1))")])
    (check-equal? (builtins (view text)) '() text))
  (check-equal? (builtins (view "(def plus = add) (plus 1 2)")) '(add))
  (check-equal? (builtins (view "(def choose = if) (choose TRUE 1 2)")) '(if TRUE))
  ;; Reader-equivalent identifier spellings retain ordinary binding identity.
  (check-equal? (builtins (view "(|add| 1 2) (a\\dd 3 4)")) '(add add)))

(test-case "generated list and cond operations retain hygienic builtin bindings"
  (define result
    (view "(def cons x = x) (def NIL = 7) (def if x = x) (list 1 2) (cond (TRUE 1) (else 2))"))
  (check-equal? (builtins result) '(cons cons NIL if TRUE))
  (check-equal? (length (source-view-bindings result)) 3)
  (check-equal? (length (source-view-registry result)) 10))

(test-case "sequential and repeated lexical binders resolve to the nearest identity"
  (define result (view "(let ((x 1) (y x) (x y)) x)"))
  (define lets (kind-nodes result 'let))
  (define references (kind-nodes result 'reference))
  (check-equal? (map source-node-data references) (map source-node-data lets))
  (define repeated (view "(lambda (x x) x)"))
  (check-equal? (source-node-data (car (kind-nodes repeated 'reference)))
                (source-node-data (cadr (kind-nodes repeated 'lambda))))
  (define empty-let (view "(let () 1)"))
  (check-equal? (length (source-view-registry empty-let)) 2)
  (check-equal? (kind-nodes empty-let 'let) '()))

(test-case "declaration recognition and forward dependency order use source semantics"
  (define result (view "(def def x y z = z) (def 1 2 3)"))
  (check-equal? (map source-binding-name (source-view-bindings result)) '(def))
  (check-equal? (length (source-view-expressions result)) 1)
  (define forward (view "(def later x = (early x)) (def early x = x)"))
  (check-equal? (source-binding-dependencies (car (source-view-bindings forward))) '(1))
  (for ([text '("(def x = x)" "(def x = y) (def y = x)"
                "(def unused = #t)" "(stdout \"prefix\") missing")])
    (check-true (source-problem? (view text)) text)))

(test-case "rec boundaries include zero-argument values and monomorphic self identity"
  (for ([text '("(rec loop = loop)" "(rec loop x = (loop x))"
                "(rec sum n = (if (is-zero n) 0 (add n (sum (sub n 1)))))")])
    (define result (view text))
    (define binding (car (source-view-bindings result)))
    (check-true (source-binding-recursive? binding))
    (check-equal? (source-binding-dependencies binding) '())
    (check-not-false (member (source-binding-id binding)
                             (map source-node-data (kind-nodes result 'reference))))))
