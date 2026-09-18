#lang racket/base

;; Mechanical source view owned by the trusted frontend. The expander supplies
;; its existing binding, declaration, dependency, and sugar operations. There
;; are no type algorithms or runtime values in this module.
(require racket/list "static-data.rkt")
(provide make-source-view)

(define (make-source-view forms definitions definition-parts bound-name
                          dependencies sugar-expression syntax-bindings builtins)
  (define next-binding 0)
  (define next-expression 0)
  (define registry '())
  (define (fresh-binding)
    (begin0 next-binding (set! next-binding (add1 next-binding))))
  (define (location stx)
    (define source (syntax-source stx))
    (source-location (cond [(path? source) (path->string source)]
                           [(symbol? source) (symbol->string source)]
                           [(string? source) source] [else #f])
                     (syntax-line stx) (syntax-column stx)
                     (syntax-position stx) (syntax-span stx)))
  (define (register stx kind)
    (define id next-expression)
    (set! next-expression (add1 next-expression))
    (set! registry (cons (list id kind (location stx)) registry))
    id)
  (define parts (map definition-parts definitions))
  (define names (map car parts))
  (define globals (map (lambda (name) (cons name (fresh-binding))) names))
  (define (binding name environment)
    (define found (bound-name name (map car environment)))
    (and found (assq found environment)))
  (define (special? head kind environment)
    (and (identifier? head) (not (binding head environment))
         (free-identifier=? head (cdr (assq kind syntax-bindings)))))
  (define (node id kind stx data children)
    (source-node id kind (location stx) data children))
  (define (builtin id reference [origin reference])
    (define found
      (findf (lambda (entry) (free-identifier=? reference (car entry))) builtins))
    (unless found (error 'static-source "resolved public binding has no catalog identity"))
    (node id 'builtin origin (string->symbol (cdr found)) '()))
  (define (applications id stx function arguments)
    (for/fold ([value function]) ([argument (in-list arguments)] [index (in-naturals)])
      (node (and (= index (sub1 (length arguments))) id)
            'application stx #f (list value argument))))
  (define (abstraction id stx arguments body environment)
    (define binders (map (lambda (argument) (cons argument (fresh-binding))) arguments))
    (define value (translate body (append (reverse binders) environment)))
    (for/fold ([value value]) ([entry (in-list (reverse binders))])
      (node (and (eq? entry (car binders)) id) 'lambda stx (cdr entry) (list value))))
  ;; Sequential let lowering is supplied by the language, retaining each binding
  ;; boundary instead of translating it further into lambda application.
  (define (lower-let stx environment origin)
    (define pieces (syntax->list stx))
    (if (and pieces (pair? pieces) (special? (car pieces) 'unary-let environment))
        (let* ([name (cadr pieces)] [id (fresh-binding)]
               [value (translate (cadddr pieces) environment)]
               [body (lower-let (list-ref pieces 4) (cons (cons name id) environment) origin)])
          (node #f 'let origin id (list value body)))
        (translate stx environment)))
  (define (literal-node stx datum)
    (node (register stx 'literal) 'literal stx
          (cond [(and (rational? datum) (exact? datum)) 'Rat]
                [(string? datum) 'String] [(char? datum) 'Char]
                [else (error 'static-source "invalid literal survived expansion")]) '()))
  (define (translate stx environment)
    (define pieces (syntax->list stx))
    (define datum (syntax-e stx))
    (cond
      [(identifier? stx)
       (define id (register stx 'reference))
       (define local (binding stx environment))
       (if local (node id 'reference stx (cdr local) '()) (builtin id stx))]
      [(and (pair? datum) (special? (car datum) 'datum environment))
       (literal-node stx (cdr (syntax->datum stx)))]
      [(not pieces) (literal-node stx datum)]
      [(and (pair? pieces) (special? (car pieces) 'lambda environment))
       (abstraction (register stx 'lambda) stx (syntax->list (cadr pieces))
                    (caddr pieces) environment)]
      [(and (pair? pieces) (special? (car pieces) 'let environment))
       (node (register stx 'let) 'group stx 'let
             (list (lower-let (sugar-expression stx) environment stx)))]
      [(and (pair? pieces) (special? (car pieces) 'list environment))
       (define id (register stx 'list))
       (sugar-expression stx)
       (define elements (map (lambda (element) (translate element environment)) (cdr pieces)))
       (define tail (builtin #f (cdr (assq 'nil syntax-bindings)) stx))
       (node id 'group stx 'list
             (list (foldr (lambda (element tail)
                            (applications #f stx (builtin #f (cdr (assq 'cons syntax-bindings)) stx)
                                          (list element tail))) tail elements)))]
      [(and (pair? pieces) (special? (car pieces) 'cond environment))
       (define id (register stx 'cond))
       (sugar-expression stx)
       (define (clauses remaining)
         (define clause (syntax->list (car remaining)))
         (if (null? (cdr remaining))
             (translate (cadr clause) environment)
             (applications #f stx (builtin #f (cdr (assq 'if syntax-bindings)) stx)
                           (list (translate (car clause) environment)
                                 (translate (cadr clause) environment)
                                 (clauses (cdr remaining))))))
       (node id 'group stx 'cond (list (clauses (cdr pieces))))]
      [else
       (define id (register stx 'application))
       (define application-pieces
         (if (special? (car pieces) 'application environment) (cdr pieces) pieces))
       (applications id stx (translate (car application-pieces) environment)
                     (map (lambda (argument) (translate argument environment)) (cdr application-pieces)))]))
  (define result-bindings '())
  (define result-expressions '())
  (define result-forms '())
  (for ([form (in-list forms)])
    (cond
      [(memq form definitions)
       (define definition (definition-parts form))
       (define name (car definition))
       (define arguments (cadr definition))
       (define recursive? (free-identifier=? (car (syntax->list form)) (cdr (assq 'rec syntax-bindings))))
       (define id (cdr (binding name globals)))
       (define body (abstraction #f form arguments (caddr definition) globals))
       (define edges
         (remove-duplicates
          (map (lambda (name) (cdr (binding name globals)))
               (dependencies (caddr definition) names (if recursive? (cons name arguments) arguments)))))
       (set! result-bindings
             (cons (source-binding id (syntax-e name) (location name) body recursive? edges) result-bindings))
       (set! result-forms (cons (list 'binding id) result-forms))]
      [else
       (define value (translate form globals))
       (set! result-expressions (cons value result-expressions))
       (set! result-forms (cons (list 'expression (source-node-id value)) result-forms))]))
  (source-view (reverse result-bindings) (reverse result-expressions)
               (reverse registry) (reverse result-forms)))
