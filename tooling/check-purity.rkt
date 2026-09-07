#lang racket/base

;; Structural purity gate for production modules.
;;
;; The checker validates what Racket actually compiles: it reads each
;; production module with its source intact, expands it fully in a fresh
;; namespace exactly as `raco make` would, and then admits only these
;; fully-expanded shapes:
;;
;;   - a module in the trusted Lazy Racket shell;
;;   - project-only, phase-0 imports (same-directory modules, or a module
;;     one sibling directory away that still resolves inside the project
;;     root) and plain or renamed exports;
;;   - `define-values` of exactly one identifier;
;;   - Lazy Racket's expansion of a unary `lambda`;
;;   - Lazy Racket's expansion of a unary application;
;;   - variables bound by those lambdas, by this module, or by a project
;;     module that passes the same scan.
;;
;; Accepted module definitions must additionally form an acyclic dependency
;; graph. Recursion may arise from lexical self-application, never from a
;; cycle of phase-0 module bindings.
;;
;; The two Lazy Racket shapes are not modelled by hand. A reference term,
;; `(lambda (f) (lambda (x) (f x)))`, is expanded in the same shell, and every
;; production lambda and application must be alpha-equivalent to the
;; corresponding piece of that expansion. Any other expanded form — a host
;; conditional, a host datum, a multi-argument or zero-argument application, a
;; strict kernel lambda, a compile-time definition — is a violation. Because
;; the scan sees the same expansion the compiler produces, a macro cannot
;; hand the checker a different term than the compiler by inspecting its
;; input.
;;
;; Trust boundary. The checker trusts, by path, the two files under macros/
;; and the Racket installation. macros.rkt is judged only through what its
;; macros expand to; it is not scanned, so a macro module that inspects its
;; host process at expansion time (for example, the call stack) could still
;; behave differently under the checker. The gate exists to catch accidental
;; or convenient impurity in production code, not a contributor editing the
;; trusted files — who could equally edit this checker. Like `raco make`, the
;; scan runs read-time and compile-time code from the modules it examines; it
;; is not a sandbox.

(require racket/list
         racket/path
         racket/promise
         racket/runtime-path
         racket/string)

(provide (struct-out violation)
         file-violations
         files-violations
         production-files-under)

(struct violation (kind detail)
  #:transparent)

;; ---------------------------------------------------------------------------
;; Trusted shell

(define expected-production-language
  "../macros/lazy-with-macros.rkt")

(define expected-macro-import
  "../macros/macros.rkt")

(define-runtime-path trusted-production-language-file
  "../macros/lazy-with-macros.rkt")

(define-runtime-path trusted-macro-import-file
  "../macros/macros.rkt")

(define (settled-path file)
  (if (file-exists? file)
      (normalize-path file)
      (simplify-path (path->complete-path file))))

(define trusted-production-language-path
  (settled-path trusted-production-language-file))

(define trusted-macro-import-path
  (settled-path trusted-macro-import-file))

(define expected-production-language-module
  '(module lazy-with-macros racket/base
     (#%module-begin
      (require lazy/lazy)
      (provide (all-from-out lazy/lazy)
               #%module-begin
               #%app
               #%datum
               #%top))))

(define expected-configure-runtime-submodule
  '(module configure-runtime '#%kernel
     (#%module-begin
      (#%require racket/runtime-config)
      (#%app configure '#f))))

;; ---------------------------------------------------------------------------
;; Names

(define reserved-production-bindings
  '(lambda
    define
    def
    lambda-let
    define-function-name
    require
    provide))

(define forbidden-host-names
  '(if cond case when unless and or not let let* letrec let-values
    let*-values for for* for/list for*/list do match match-lambda
    case-lambda begin begin0 apply values call/cc dynamic-wind delay force
    host eval dynamic-require system process open-input-file
    open-output-file call-with-input-file call-with-output-file display
    printf + - * / = < > <= >= eq? eqv? equal? pair? list? null? number?
    boolean? string? procedure? list cons car cdr member memq assoc map
    filter foldl foldr append reverse length vector make-vector vector-ref
    hash make-hash hash-ref set box set! set-box! string make-string
    string-length string-ref string=? char=? string-append substring regexp
    raise error with-handlers struct quote quasiquote λ))

(define (arity-specific-checker-name? name)
  (and (symbol? name)
       (regexp-match?
        #px"^(type-check|make-typed-function)-?[0-9]+$"
        (symbol->string name))))

(define (binding-name-violations name)
  (cond
    [(memq name reserved-production-bindings)
     (list (violation 'reserved-production-binding
                      (symbol->string name)))]
    [(eq? name 'host)
     (list (violation 'forbidden-host-identifier
                      (symbol->string name)))]
    [(arity-specific-checker-name? name)
     (list (violation 'arity-specific-checker
                      (symbol->string name)))]
    [else
     '()]))

;; ---------------------------------------------------------------------------
;; Paths

(define (dotenv-name? path)
  (define name (file-name-from-path path))
  (and name
       (regexp-match?
        #px"(^|\\.)env($|\\.)"
        (string-downcase (path->string name)))))

(define (dotenv-path? path)
  (for/or ([part (in-list (explode-path (path->complete-path path)))])
    (and (path? part)
         (dotenv-name? part))))

(define (safe-production-path? path)
  (and (not (dotenv-path? path))
       (not (link-exists? path))))

(define (resolve-import source-path spec)
  (simplify-path
   (build-path
    (or (path-only source-path)
        (current-directory))
    spec)
   #f))

(define (trusted-relative-path? source-path spec trusted-path)
  (define candidate
    (resolve-import source-path spec))
  (and (file-exists? candidate)
       (equal? (normalize-path candidate)
               trusted-path)))

(define (same-directory-module-name? spec)
  (and (string? spec)
       (regexp-match? #px"^[^/\\\\]+\\.rkt$" spec)
       (not (dotenv-name? (string->path spec)))))

;; "../<directory>/<module>.rkt": one step up, one named directory down.
;; The import checker additionally requires the resolved file to sit inside
;; the project root, so this form cannot escape the repository.
(define (sibling-directory-module-name? spec)
  (and (string? spec)
       (regexp-match? #px"^\\.\\./[^/\\\\]+/[^/\\\\]+\\.rkt$" spec)
       (for/and ([part (in-list (cdr (string-split spec "/")))])
         (not (dotenv-name? (string->path part))))))

;; The macros directory holds the trusted, unscanned expansion pair, so a
;; sibling spelling into it never counts as an ordinary project module:
;; macros.rkt is admitted only through the exact trusted-import clause, and
;; no runtime binding may chain through the macros directory at all.
(define (macros-directory-module-name? spec)
  (and (string? spec)
       (regexp-match? #px"^\\.\\./macros/" spec)))

(define (project-module-name? spec)
  (or (same-directory-module-name? spec)
      (and (sibling-directory-module-name? spec)
           (not (macros-directory-module-name? spec)))))

(define-runtime-path project-root-directory "..")

(define project-root-path
  (settled-path project-root-directory))

(define (within-project-root? path)
  (define parts (explode-path (normalize-path path)))
  (define root (explode-path project-root-path))
  (and (>= (length parts) (length root))
       (equal? (take parts (length root)) root)))

(define (production-files-under path)
  (cond
    [(dotenv-path? path)
     '()]
    [(link-exists? path)
     ;; Reported, never followed: file-violations rejects the link itself.
     (list path)]
    [(directory-exists? path)
     (append-map production-files-under
                 (directory-list path #:build? #t))]
    [(and (file-exists? path)
          (equal? (path-get-extension path) #".rkt"))
     (list path)]
    [else
     '()]))

;; ---------------------------------------------------------------------------
;; Reading and expansion

(define (read-module-syntax path)
  (call-with-input-file path
    (lambda (input)
      (port-count-lines! input)
      (parameterize ([read-accept-reader #t]
                     [current-load-relative-directory (path-only path)])
        (read-syntax path input)))))

(define (read-module-datum path)
  (syntax->datum (read-module-syntax path)))

(define (expand-module-syntax stx path namespace)
  (parameterize ([current-namespace namespace]
                 [current-load-relative-directory (path-only path)])
    (expand stx)))

(define (render stx)
  (define text
    (format "~s" (if (syntax? stx) (syntax->datum stx) stx)))
  (if (> (string-length text) 160)
      (string-append (substring text 0 157) "...")
      text))

(define (form-head-name form)
  (define parts (syntax->list form))
  (and parts
       (pair? parts)
       (identifier? (car parts))
       (syntax-e (car parts))))

;; ---------------------------------------------------------------------------
;; Reference templates from the trusted shell

(struct templates
  (app-id            ; kernel #%app
   lazy-proc-id      ; Lazy Racket's procedure wrapper
   lazy-id           ; Lazy Racket's promise constructor
   kernel-lambda-id  ; kernel lambda
   operator-hole     ; identifier standing for the operator in app-template
   argument-hole     ; identifier standing for the argument in app-template
   app-template))    ; expansion of (f x) under the shell

(define (reference-module-syntax)
  (datum->syntax
   #f
   `(module reference (file ,(path->string trusted-production-language-path))
      (#%module-begin
       (define reference
         (lambda (f)
           (lambda (x)
             (f x))))))))

(define (expand-reference-templates namespace)
  (with-handlers
      ([exn:fail?
        (lambda (failure)
          (raise
           (exn:fail
            (format "reference expansion under ~a is not the expected shape: ~a"
                    trusted-production-language-path
                    (exn-message failure))
            (current-continuation-marks))))])
    (extract-reference-templates
     (parameterize ([current-namespace namespace])
       (expand (reference-module-syntax))))))

(define (extract-reference-templates expanded)
  (define body
    (syntax->list (cadddr (syntax->list expanded))))
  (define definition
    (findf (lambda (form)
             (eq? (form-head-name form) 'define-values))
           body))
  ;; (define-values (reference)
  ;;   (#%app lazy-proc (lambda (f) (#%app lazy-proc (lambda (x) APP)))))
  (define outer (caddr (syntax->list definition)))
  (define outer-parts (syntax->list outer))
  (define outer-lambda (syntax->list (caddr outer-parts)))
  (define inner-parts (syntax->list (caddr outer-lambda)))
  (define inner-lambda (syntax->list (caddr inner-parts)))
  (define app-template (caddr inner-lambda))
  (templates (car outer-parts)
             (cadr outer-parts)
             (cadr (syntax->list app-template))
             (car outer-lambda)
             (car (syntax->list (cadr outer-lambda)))
             (car (syntax->list (cadr inner-lambda)))
             app-template))

;; Alpha-equivalence match of `candidate` against `template`. Identifiers
;; bound inside the template must be bound at the same positions in the
;; candidate; free identifiers must be the same binding; hole identifiers
;; capture the corresponding candidate subterm. Returns an association list
;; of hole identifier to captured syntax, or #f.
(define (match-template template candidate hole-ids kernel-lambda-id)
  (let/ec escape
    (define captured '())
    (define (hole? identifier)
      (ormap (lambda (hole) (free-identifier=? hole identifier))
             hole-ids))
    (define (env-lookup identifier env)
      (findf (lambda (pair) (free-identifier=? (car pair) identifier))
             env))
    (define (walk template candidate env)
      (cond
        [(identifier? template)
         (define bound (env-lookup template env))
         (cond
           [bound
            (unless (and (identifier? candidate)
                         (free-identifier=? candidate (cdr bound)))
              (escape #f))]
           [(hole? template)
            (set! captured (cons (cons template candidate) captured))]
           [else
            (unless (and (identifier? candidate)
                         (free-identifier=? template candidate))
              (escape #f))])]
        [(syntax->list template)
         => (lambda (template-parts)
              (define candidate-parts (syntax->list candidate))
              (unless (and candidate-parts
                           (= (length candidate-parts)
                              (length template-parts)))
                (escape #f))
              (define head (car template-parts))
              (cond
                [(and (identifier? head)
                      (free-identifier=? head kernel-lambda-id)
                      (= (length template-parts) 3))
                 (unless (and (identifier? (car candidate-parts))
                              (free-identifier=? head (car candidate-parts)))
                   (escape #f))
                 (define template-formals
                   (syntax->list (cadr template-parts)))
                 (define candidate-formals
                   (syntax->list (cadr candidate-parts)))
                 (unless (and template-formals
                              candidate-formals
                              (= (length template-formals)
                                 (length candidate-formals))
                              (andmap identifier? template-formals)
                              (andmap identifier? candidate-formals))
                   (escape #f))
                 (walk (caddr template-parts)
                       (caddr candidate-parts)
                       (append (map cons template-formals candidate-formals)
                               env))]
                [else
                 (for-each (lambda (template-part candidate-part)
                             (walk template-part candidate-part env))
                           template-parts
                           candidate-parts)]))]
        [else
         (unless (and (not (syntax->list candidate))
                      (equal? (syntax-e template) (syntax-e candidate)))
           (escape #f))]))
    (walk template candidate '())
    captured))

;; ---------------------------------------------------------------------------
;; Bindings

;; Splits a module path index into its relative segments, ending with 'self
;; when the chain is rooted in the module being expanded, or with the root
;; module path otherwise.
(define (module-path-chain index)
  (let loop ([index index]
             [segments '()])
    (define-values (path base)
      (module-path-index-split index))
    (cond
      [base
       (loop base (cons path segments))]
      [(and path (module-path? path))
       (reverse (cons path segments))]
      [else
       (reverse (cons 'self segments))])))

(define (self-chain? chain)
  (equal? chain '(self)))

(define (project-chain? chain)
  (and (pair? chain)
       (eq? (last chain) 'self)
       (andmap project-module-name?
               (drop-right chain 1))))

(define (reference-violations identifier)
  (define name (syntax-e identifier))
  (define binding (identifier-binding identifier))
  (cond
    [(eq? binding 'lexical)
     '()]
    [(not (list? binding))
     (list (violation 'unapproved-production-identifier
                      (symbol->string name)))]
    [else
     (define chain (module-path-chain (car binding)))
     (cond
       [(or (self-chain? chain)
            (project-chain? chain))
        (binding-name-violations name)]
       [(memq name forbidden-host-names)
        (list (violation 'forbidden-host-identifier
                         (symbol->string name)))]
       [else
        (list (violation 'unapproved-production-identifier
                         (symbol->string name)))])]))

;; ---------------------------------------------------------------------------
;; Expressions

(define (lazy-lambda-parts parts tpl)
  ;; (#%app lazy-proc (lambda formals body)) -> (list formals body) or #f
  (and (= (length parts) 3)
       (identifier? (car parts))
       (free-identifier=? (car parts) (templates-app-id tpl))
       (identifier? (cadr parts))
       (free-identifier=? (cadr parts) (templates-lazy-proc-id tpl))
       (let ([lambda-parts (syntax->list (caddr parts))])
         (and lambda-parts
              (>= (length lambda-parts) 3)
              (identifier? (car lambda-parts))
              (free-identifier=? (car lambda-parts)
                                 (templates-kernel-lambda-id tpl))
              (cdr lambda-parts)))))

(define (lazy-application-shape? parts tpl)
  ;; (#%app lazy (lambda () (#%app (lambda formals ...) ...)))
  (and (= (length parts) 3)
       (identifier? (car parts))
       (free-identifier=? (car parts) (templates-app-id tpl))
       (identifier? (cadr parts))
       (free-identifier=? (cadr parts) (templates-lazy-id tpl))
       (let ([thunk (syntax->list (caddr parts))])
         (and thunk
              (= (length thunk) 3)
              (identifier? (car thunk))
              (free-identifier=? (car thunk)
                                 (templates-kernel-lambda-id tpl))
              (let ([call (syntax->list (caddr thunk))])
                (and call
                     (pair? call)
                     (identifier? (car call))
                     (free-identifier=? (car call)
                                        (templates-app-id tpl))
                     (pair? (cdr call))
                     (let ([receiver (syntax->list (cadr call))])
                       (and receiver
                            (pair? receiver)
                            (identifier? (car receiver))
                            (free-identifier=?
                             (car receiver)
                             (templates-kernel-lambda-id tpl))))))))))

(define (expression-violations expression tpl)
  (cond
    [(identifier? expression)
     (reference-violations expression)]
    [else
     (define parts (syntax->list expression))
     (cond
       [(not (and parts (pair? parts)))
        (list (violation 'forbidden-host-datum
                         (render expression)))]
       [(eq? (form-head-name expression) 'quote)
        (list (violation 'forbidden-host-datum
                         (render expression)))]
       [(lazy-lambda-parts parts tpl)
        => (lambda (lambda-parts)
             (define formals (syntax->list (car lambda-parts)))
             (if (and formals
                      (= (length formals) 1)
                      (identifier? (car formals))
                      (= (length lambda-parts) 2))
                 (expression-violations (cadr lambda-parts) tpl)
                 (list (violation 'non-unary-lambda
                                  (render (caddr parts))))))]
       [(match-template (templates-app-template tpl)
                        expression
                        (list (templates-operator-hole tpl)
                              (templates-argument-hole tpl))
                        (templates-kernel-lambda-id tpl))
        => (lambda (captured)
             (define operator
               (assf (lambda (hole)
                       (free-identifier=? hole
                                          (templates-operator-hole tpl)))
                     captured))
             (define argument
               (assf (lambda (hole)
                       (free-identifier=? hole
                                          (templates-argument-hole tpl)))
                     captured))
             (if (and operator argument (= (length captured) 2))
                 (append (expression-violations (cdr operator) tpl)
                         (expression-violations (cdr argument) tpl))
                 (list (violation 'forbidden-host-form
                                  (render expression)))))]
       [(lazy-application-shape? parts tpl)
        (list (violation 'non-unary-application
                         (render expression)))]
       [(lazy-thunk-body parts tpl)
        => (lambda (body)
             (list (violation 'forbidden-host-form
                              (form-description body))))]
       [else
        (list (violation 'forbidden-host-form
                         (form-description expression)))])]))

(define (form-description form)
  (define head (form-head-name form))
  (if head
      (symbol->string head)
      (render form)))

(define (lazy-thunk-body parts tpl)
  ;; (#%app lazy (lambda () body)) -> body, or #f
  (and (= (length parts) 3)
       (identifier? (car parts))
       (free-identifier=? (car parts) (templates-app-id tpl))
       (identifier? (cadr parts))
       (free-identifier=? (cadr parts) (templates-lazy-id tpl))
       (let ([thunk (syntax->list (caddr parts))])
         (and thunk
              (= (length thunk) 3)
              (identifier? (car thunk))
              (free-identifier=? (car thunk)
                                 (templates-kernel-lambda-id tpl))
              (null? (or (syntax->list (cadr thunk)) '(x)))
              (caddr thunk)))))

;; ---------------------------------------------------------------------------
;; Module-level forms

(define (import-module-path-violations module-path source-path spec)
  (cond
    [(and (equal? module-path expected-macro-import)
          (trusted-relative-path? source-path
                                  module-path
                                  trusted-macro-import-path))
     '()]
    [(and (same-directory-module-name? module-path)
          (safe-production-path?
           (resolve-import source-path module-path)))
     '()]
    [(and (sibling-directory-module-name? module-path)
          (not (macros-directory-module-name? module-path))
          (let ([resolved (resolve-import source-path module-path)])
            (and (safe-production-path? resolved)
                 (file-exists? resolved)
                 (within-project-root? resolved))))
     '()]
    [else
     (list (violation 'disallowed-production-import
                      (render spec)))]))

(define (require-spec-violations spec source-path)
  (define datum (syntax->datum spec))
  (define parts (syntax->list spec))
  (define (disallowed)
    (list (violation 'disallowed-production-import
                     (render spec))))
  (cond
    [(string? datum)
     (import-module-path-violations datum source-path spec)]
    [(and parts (pair? parts) (identifier? (car parts)))
     (case (syntax-e (car parts))
       [(just-meta)
        (if (equal? (syntax-e (cadr parts)) 0)
            (append-map (lambda (inner)
                          (require-spec-violations inner source-path))
                        (cddr parts))
            (disallowed))]
       [(just-space)
        (append-map (lambda (inner)
                      (require-spec-violations inner source-path))
                    (cddr parts))]
       [(rename)
        ;; (rename module-path local-id exported-id): a binding imported
        ;; under its own name is judged where it is defined; only a new
        ;; local name is subject to the name rules here.
        (append
         (import-module-path-violations (syntax->datum (cadr parts))
                                        source-path
                                        spec)
         (if (eq? (syntax-e (caddr parts))
                  (syntax-e (cadddr parts)))
             '()
             (binding-name-violations (syntax-e (caddr parts)))))]
       [(only)
        (import-module-path-violations (syntax->datum (cadr parts))
                                       source-path
                                       spec)]
       [(all-except)
        (import-module-path-violations (syntax->datum (cadr parts))
                                       source-path
                                       spec)]
       [(prefix prefix-all-except)
        (import-module-path-violations (syntax->datum (caddr parts))
                                       source-path
                                       spec)]
       [else
        (disallowed)])]
    [else
     (disallowed)]))

(define (require-spec-module-paths spec)
  (define datum (syntax->datum spec))
  (cond
    [(string? datum)
     (list datum)]
    [(pair? datum)
     (case (car datum)
       [(just-meta)
        (append-map require-spec-module-paths
                    (cddr (syntax->list spec)))]
       [(just-space)
        (append-map require-spec-module-paths
                    (cddr (syntax->list spec)))]
       [(rename only all-except)
        (list (cadr datum))]
       [(prefix prefix-all-except)
        (list (caddr datum))]
       [else
        '()])]
    [else
     '()]))

(define (project-import-paths forms source-path)
  (remove-duplicates
   (filter-map
    (lambda (module-path)
      (and (project-module-name? module-path)
           (not (trusted-relative-path? source-path
                                        module-path
                                        trusted-macro-import-path))
           (let ([resolved (resolve-import source-path module-path)])
             (and (safe-production-path? resolved)
                  (file-exists? resolved)
                  (simplify-path (path->complete-path resolved) #f)))))
    (append-map
     (lambda (form)
       (if (eq? (form-head-name form) '#%require)
           (append-map require-spec-module-paths
                       (cdr (syntax->list form)))
           '()))
     forms))
   equal?))

(define (export-binding-violations identifier)
  (define binding (identifier-binding identifier))
  (define chain
    (and (list? binding)
         (module-path-chain (car binding))))
  (if (and chain
           (or (self-chain? chain)
               (project-chain? chain)))
      '()
      (list (violation 'unapproved-production-export
                       (symbol->string (syntax-e identifier))))))

(define (provide-spec-violations spec)
  (define parts (syntax->list spec))
  (cond
    [(identifier? spec)
     (append (export-binding-violations spec)
             (binding-name-violations (syntax-e spec)))]
    [(and parts
          (= (length parts) 3)
          (identifier? (car parts))
          (eq? (syntax-e (car parts)) 'rename)
          (identifier? (cadr parts))
          (identifier? (caddr parts)))
     (append (export-binding-violations (cadr parts))
             (binding-name-violations (syntax-e (caddr parts))))]
    [else
     (list (violation 'disallowed-production-export
                      (render spec)))]))

(define (definition-violations form tpl)
  (define parts (syntax->list form))
  (define identifiers
    (and (= (length parts) 3)
         (syntax->list (cadr parts))))
  (if (and identifiers
           (= (length identifiers) 1)
           (identifier? (car identifiers)))
      (append (binding-name-violations (syntax-e (car identifiers)))
              (expression-violations (caddr parts) tpl))
      (list (violation 'disallowed-module-form
                       (render form)))))

(define (module-form-violations form source-path tpl)
  (case (form-head-name form)
    [(module module*)
     (if (equal? (syntax->datum form)
                 expected-configure-runtime-submodule)
         '()
         (list (violation 'disallowed-module-form
                          (render form))))]
    [(#%require)
     (append-map (lambda (spec)
                   (require-spec-violations spec source-path))
                 (cdr (syntax->list form)))]
    [(#%provide)
     (append-map provide-spec-violations
                 (cdr (syntax->list form)))]
    [(define-values)
     (definition-violations form tpl)]
    [else
     (list (violation 'disallowed-module-form
                      (render form)))]))

;; ---------------------------------------------------------------------------
;; Modules

(struct scan (namespace templates results))

(define (make-scan)
  (define namespace (make-base-namespace))
  (scan namespace
        (delay (expand-reference-templates namespace))
        (make-hash)))

(define (module-shape-violations datum source-path)
  (cond
    [(not (and (list? datum)
               (>= (length datum) 3)
               (eq? (car datum) 'module)
               (symbol? (cadr datum))))
     (list (violation 'invalid-production-module
                      (render datum)))]
    [(not (and (equal? (caddr datum) expected-production-language)
               (trusted-relative-path? source-path
                                       (caddr datum)
                                       trusted-production-language-path)))
     (list (violation 'unexpected-production-language
                      (render (caddr datum))))]
    [else
     '()]))

(define (module-violations source-path current)
  (hash-ref!
   (scan-results current)
   source-path
   (lambda ()
     (define stx
       (with-handlers ([exn:fail? values])
         (read-module-syntax source-path)))
     (cond
       [(exn? stx)
        (list (violation 'read-failure (exn-message stx)))]
       [(eof-object? stx)
        (list (violation 'invalid-production-module "empty file"))]
       [else
        (define shape-findings
          (module-shape-violations (syntax->datum stx) source-path))
        (if (pair? shape-findings)
            shape-findings
            (let ([expanded
                   (with-handlers ([exn:fail? values])
                     (expand-module-syntax stx
                                           source-path
                                           (scan-namespace current)))])
              (if (exn? expanded)
                  (list (violation 'expansion-failure
                                   (exn-message expanded)))
                  (expanded-module-violations expanded
                                              source-path
                                              current))))]))))

(define (expanded-module-violations expanded source-path current)
  (define tpl
    (with-handlers ([exn:fail? values])
      (force (scan-templates current))))
  (if (exn? tpl)
      (list (violation 'invalid-production-language-shell
                       (exn-message tpl)))
      (expanded-module-form-violations expanded source-path current tpl)))

(define (expanded-module-form-violations expanded source-path current tpl)
  (define forms
    (cdr (syntax->list (cadddr (syntax->list expanded)))))
  (define own-findings
    (append-map (lambda (form)
                  (module-form-violations form source-path tpl))
                forms))
  (define import-findings
    (filter-map
     (lambda (imported-path)
       (define findings
         (module-violations imported-path current))
       (and (pair? findings)
            (violation 'impure-production-import
                       (format "~a (~a)"
                               imported-path
                               (violation-kind (car findings))))))
     (project-import-paths forms source-path)))
  (append own-findings
          (if (null? own-findings)
              (module-binding-cycle-violations forms)
              '())
          import-findings))

;; Only accepted expanded trees reach this check. Binding identity at phase 0
;; excludes lambda parameters and imported names, including renamed imports.
;; Return the first cycle in source/dependency order, with its closing name.
(define (module-binding-cycle-violations forms)
  (define definitions
    (filter-map
     (lambda (form)
       (and (eq? (form-head-name form) 'define-values)
            (let ([parts (syntax->list form)])
              (cons (car (syntax->list (cadr parts))) (caddr parts)))))
     forms))
  (define names (map car definitions))
  (define (references expression)
    (cond
      [(identifier? expression)
       (define binding (identifier-binding expression 0))
       (define name
         (and (list? binding)
              (self-chain? (module-path-chain (car binding)))
              (findf (lambda (name) (free-identifier=? expression name 0)) names)))
       (if name (list name) '())]
      [else
       (append-map references (or (syntax->list expression) '()))]))
  (define graph
    (map (lambda (definition)
           (cons (car definition) (remove-duplicates (references (cdr definition)) eq?)))
         definitions))
  (define finished (make-hasheq))
  (define (visit name path)
    (cond
      [(memq name path)
       (append (cons name (reverse (takef path (lambda (prior) (not (eq? prior name))))))
               (list name))]
      [(hash-ref finished name #f) #f]
      [else
       (define cycle
         (ormap (lambda (dependency) (visit dependency (cons name path)))
                (cdr (assq name graph))))
       (hash-set! finished name #t)
       cycle]))
  (define cycle (ormap (lambda (name) (visit name '())) names))
  (if cycle
      (list (violation 'recursive-module-binding
                       (string-join (map (lambda (name) (symbol->string (syntax-e name))) cycle)
                                    " -> ")))
      '()))

(define (production-language-shell-violations)
  (with-handlers
      ([exn:fail?
        (lambda (failure)
          (list (violation 'invalid-production-language-shell
                           (exn-message failure))))])
    (if (and (safe-production-path? trusted-production-language-path)
             (equal? (read-module-datum trusted-production-language-path)
                     expected-production-language-module))
        '()
        (list (violation 'invalid-production-language-shell
                         (format "unexpected contents at ~a"
                                 trusted-production-language-path))))))

(define (file-violations path [current (make-scan)])
  (cond
    [(not (safe-production-path? path))
     (list (violation 'disallowed-production-path
                      (format "~a" path)))]
    [else
     (define normalized-path
       (simplify-path (path->complete-path path) #f))
     (if (safe-production-path? normalized-path)
         (let ([shell-findings (production-language-shell-violations)])
           (if (pair? shell-findings)
               shell-findings
               (module-violations normalized-path current)))
         (list (violation 'disallowed-production-path
                          (format "~a" normalized-path))))]))

;; Scans several files with one shared namespace and expansion cache, so a
;; module reachable from many roots is expanded once. Returns an association
;; list of path to findings.
(define (files-violations paths)
  (define current (make-scan))
  (for/list ([path (in-list paths)])
    (cons path (file-violations path current))))

;; ---------------------------------------------------------------------------
;; Command line

(define-runtime-path default-production-directory
  "../core")

(define-runtime-path default-effects-directory
  "../effects")

(module+ main
  (define arguments
    (vector->list (current-command-line-arguments)))
  (define targets
    (if (null? arguments)
        (list default-production-directory
              default-effects-directory)
        (map string->path arguments)))
  (define files
    (append-map production-files-under targets))
  (define findings
    (for*/list ([entry (in-list (files-violations files))]
                [finding (in-list (cdr entry))])
      (cons (car entry) finding)))
  (cond
    [(null? files)
     (eprintf "No production Racket files found.\n")
     (exit 2)]
    [(null? findings)
     (printf "Purity check passed: ~a production file(s).\n"
             (length files))]
    [else
     (for ([finding (in-list findings)])
       (eprintf "~a: ~a: ~a\n"
                (car finding)
                (violation-kind (cdr finding))
                (violation-detail (cdr finding))))
     (exit 1)]))
