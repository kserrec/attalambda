#lang racket/base

(require rackunit racket/list racket/runtime-path
         "../runner/static/frontend.rkt" "../runner/source-file.rkt"
         "../runner/source-reader.rkt" "../lang/static-data.rkt")
(define-runtime-path facade "../lang/expander.rkt")
(define (view text)
  (prepare-source (validated-source 'metadata.attl text 2 0 17) #:analysis? #t))
(define (nodes node)
  (cons node (append-map nodes (source-node-children node))))
(define (view-nodes result)
  (append-map nodes (append (map source-binding-value (source-view-bindings result))
                            (source-view-expressions result))))

(test-case "actual expansion transports source kinds and precise denominators"
  (check-not-eq? analysis-request-key analysis-result-key)
  (for ([text '("" "1 \"text\" #\\A" "(add 1 2)" "(list 1 2)"
                "(let x = 1 x)" "(lambda (x y) (add x y))"
                "(def f x y = (add x y))" "(cond (TRUE 1) (else 2))")]
        [count '(0 3 4 3 3 5 4 4)])
    (define result (view text))
    (check-true (source-view? result) text)
    (check-equal? (length (source-view-registry result)) count text)
    (check-equal? (length (filter source-node-id (view-nodes result))) count text)
    (for ([node (in-list (view-nodes result))])
      (check-equal? (source-location-source (source-node-location node)) "metadata.attl" text)))
  (check-equal? (map source-node-data (source-view-expressions (view "1 \"s\" #\\A")))
                '(Rat String Char)))

(test-case "explicit application and datum retain original source accounting"
  (for ([text '("(#%app add 1 2)" "(#%app . (add 1 2))"
                "(#%app (#%app add 1) 2)"
                "(#%datum . 1)" "(#%datum . \"s\")" "(#%datum . #\\A)")]
        [count '(4 4 5 1 1 1)])
    (define result (view text))
    (check-true (source-view? result) text)
    (check-equal? (length (source-view-registry result)) count text)
    (check-equal? (length (filter source-node-id (view-nodes result))) count text)
    (define location (source-node-location (car (source-view-expressions result))))
    (check-equal? (source-location-source location) "metadata.attl")
    (check-equal? (source-location-line location) 2)
    (check-equal? (source-location-column location) 0)
    (check-equal? (source-location-span location) (string-length text))))

(test-case "lexical identities, aliases, dependencies and recursion survive lowering"
  (define result
    (view "(def later x = (early x)) (def early x = x) (def plus = add) (rec loop x = (loop x))"))
  (define bindings (source-view-bindings result))
  (check-equal? (map source-binding-name bindings) '(later early plus loop))
  (check-equal? (source-binding-dependencies (car bindings))
                (list (source-binding-id (cadr bindings))))
  (check-equal? (source-node-data (source-binding-value (caddr bindings))) 'add)
  (check-true (source-binding-recursive? (list-ref bindings 3)))
  (check-equal? (source-binding-dependencies (list-ref bindings 3)) '())
  (define identity (source-binding-value (cadr bindings)))
  (check-equal? (source-node-data identity) (source-node-data (car (source-node-children identity)))))

(test-case "missing or corrupted accounting is an internal failure"
  (define result (view "(def identity x = x) (identity 1) 2"))
  (define expression (car (source-view-expressions result)))
  (define id (source-node-id expression))
  (define (invalid candidate)
    (check-exn #rx"invalid analysis metadata" (lambda () (validate-source-view candidate 3))))
  (invalid #f)
  (invalid (cons result result))
  (invalid (struct-copy source-view result [registry (cdr (source-view-registry result))]))
  (invalid (struct-copy source-view result [registry (cons (car (source-view-registry result))
                                                        (source-view-registry result))]))
  (invalid (struct-copy source-view result [expressions (list expression)]))
  (invalid (struct-copy source-view result [forms (cdr (source-view-forms result))]))
  (invalid (struct-copy source-view result
             [expressions (cons (source-node id 'reference (source-node-location expression) 999 '())
                                (cdr (source-view-expressions result)))]))
  (invalid (struct-copy source-view result [bindings (append (source-view-bindings result)
                                                            (source-view-bindings result))])))

;; Compare expanded terms, ignoring syntax properties and consistently renaming
;; generated uninterned binders. Binding-aware source fixtures are separate.
(define (alpha-datum syntax)
  (define names (make-hasheq))
  (define (walk datum)
    (cond [(and (symbol? datum) (not (symbol-interned? datum)))
           (hash-ref! names datum (lambda () (list 'fresh (hash-count names))))]
          [(pair? datum) (cons (walk (car datum)) (walk (cdr datum)))]
          [(vector? datum) (list->vector (map walk (vector->list datum)))]
          [else datum]))
  (walk (syntax->datum syntax)))
(define (expand-for-view text requested?)
  (define parsed (parse-source-buffer 'same.attl text))
  (define body (datum->syntax #f (cons '#%module-begin (source-buffer-forms parsed))))
  (define decorated (if requested? (syntax-property body analysis-request-key analysis-request) body))
  (parameterize ([current-namespace (make-base-namespace)])
    (expand (datum->syntax #f `(module same (file ,(path->string facade)) ,decorated)))))
(test-case "opt-in source metadata does not change expanded computation"
  (for ([text '("1 \"s\" #\\A" "(def f x = (add x 1)) (f 2)"
                "(let ((id (lambda (x) x)) (n (id 1))) n)"
                "(rec factorial n = (if (is-zero n) 1 (mult n (factorial (sub n 1)))))"
                "(list 1 2) (cond (FALSE 1) (else 2))"
                "(#%app add (#%datum . 1) 2)"
                "(#%app . (add 1 2)) (#%datum . \"s\") (#%datum . #\\A)"
                "(def plus = add) (#%app (#%app plus 1) 2)")])
    (define ordinary (expand-for-view text #f))
    (define analyzed (expand-for-view text #t))
    (check-false (syntax-property (cadddr (syntax->list ordinary)) analysis-result-key))
    (check-true (source-view? (syntax-property (cadddr (syntax->list analyzed)) analysis-result-key)))
    (check-equal? (alpha-datum ordinary) (alpha-datum analyzed) text)))
