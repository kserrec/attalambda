#lang racket/base

;; The purity gate scans what Racket compiles: every case below writes real
;; modules to a temporary tree that shares the trusted macro shell, then asks
;; the checker to expand and judge them exactly as `raco make` would.

(require rackunit
         racket/file
         racket/list
         racket/runtime-path
         "../tooling/check-purity.rkt")

(define-runtime-path trusted-macros-directory
  "../macros")

(define-runtime-path purity-checker-file
  "../tooling/check-purity.rkt")

(define-runtime-path core-directory
  "../core")

(define (write-datum path datum)
  (call-with-output-file path
    #:exists 'truncate
    (lambda (output)
      (write datum output))))

(define (temporary-tree prefix)
  (make-temporary-file (string-append "attalambda-" prefix "-~a")
                       'directory
                       (current-directory)))

;; Writes `datum` as core/production.rkt beside optional dependency modules,
;; with the real macros/ directory linked in, and returns the violation kinds.
(define (file-findings datum [dependencies '()])
  (define directory (temporary-tree "purity"))
  (define core (build-path directory "core"))
  (define path (build-path core "production.rkt"))
  (dynamic-wind
    (lambda ()
      (make-directory core)
      (make-file-or-directory-link trusted-macros-directory
                                   (build-path directory "macros"))
      (write-datum path datum)
      (for ([dependency (in-list dependencies)])
        (define dependency-path
          (build-path core (car dependency)))
        (define-values (base name directory?)
          (split-path dependency-path))
        (make-directory* base)
        (write-datum dependency-path (cadr dependency))))
    (lambda ()
      (file-violations path))
    (lambda ()
      (delete-directory/files directory))))

(define (file-kinds datum [dependencies '()])
  (map violation-kind (file-findings datum dependencies)))

;; Wraps one expression as the body of a curried definition so that the
;; free names the cases use are ordinary lambda-bound variables.
(define (expression-kinds expression)
  (file-kinds
   `(module production "../macros/lazy-with-macros.rkt"
      (#%module-begin
       (require "../macros/macros.rkt")
       (provide probe)
       (def probe value left right condition raw-operation =
         ,expression)))))

(define (untrusted-shell-file-kinds datum)
  (define directory (temporary-tree "shell"))
  (define core (build-path directory "core"))
  (define macros (build-path directory "macros"))
  (define path (build-path core "production.rkt"))
  (dynamic-wind
    (lambda ()
      (make-directory core)
      (make-directory macros)
      (write-datum (build-path macros "lazy-with-macros.rkt")
                   '(module lookalike racket/base
                      (#%module-begin)))
      (write-datum (build-path macros "macros.rkt")
                   '(module lookalike racket/base
                      (#%module-begin)))
      (write-datum path datum))
    (lambda ()
      (map violation-kind (file-violations path)))
    (lambda ()
      (delete-directory/files directory))))

(define (symlink-file-kinds datum)
  (define directory (temporary-tree "link"))
  (define target (build-path directory "target.rkt"))
  (define link (build-path directory "production.rkt"))
  (dynamic-wind
    (lambda ()
      (write-datum target datum)
      (make-file-or-directory-link target link))
    (lambda ()
      (map violation-kind (file-violations link)))
    (lambda ()
      (delete-directory/files directory))))

;; Copies the checker into an isolated tree with a substitute macros.rkt (and
;; optionally a substitute language shell), so the copied checker trusts the
;; substitutes exactly as the real checker trusts the real files.
(define (isolated-macro-file-kinds macro-datum
                                   production-datum
                                   [language-datum #f])
  (define directory (temporary-tree "macro-purity"))
  (define tooling (build-path directory "tooling"))
  (define macros (build-path directory "macros"))
  (define core (build-path directory "core"))
  (define checker (build-path tooling "check-purity.rkt"))
  (define production (build-path core "production.rkt"))
  (dynamic-wind
    (lambda ()
      (make-directory tooling)
      (make-directory macros)
      (make-directory core)
      (copy-file purity-checker-file checker)
      (define language-path
        (build-path macros "lazy-with-macros.rkt"))
      (if language-datum
          (write-datum language-path language-datum)
          (copy-file (build-path trusted-macros-directory
                                 "lazy-with-macros.rkt")
                     language-path))
      (write-datum (build-path macros "macros.rkt") macro-datum)
      (write-datum production production-datum))
    (lambda ()
      (define isolated-file-violations
        (dynamic-require checker 'file-violations))
      (define isolated-violation-kind
        (dynamic-require checker 'violation-kind))
      (map isolated-violation-kind
           (isolated-file-violations production)))
    (lambda ()
      (delete-directory/files directory))))

;; ---------------------------------------------------------------------------
;; Module names must not supply recursion, even when every RHS is locally pure.

(check-equal?
 (file-findings
  '(module production "../macros/lazy-with-macros.rkt"
     (#%module-begin
      (require "../macros/macros.rkt")
      (def entry = first)
      (def first value = (second value))
      (def second value = (first value)))))
 (list (violation 'recursive-module-binding "first -> second -> first")))

(for ([definitions
       (in-list
        '(((def loop value = (loop value)))
          ((def loop = loop))
          ((def first value = (second value))
           (def second value = (first value)))
          ((def first = second) (def second = third) (def third = first))
          ((def loop value = ((lambda (ignored) value) loop)))))])
  (check-equal?
   (file-kinds
    `(module production "../macros/lazy-with-macros.rkt"
       (#%module-begin
        (require "../macros/macros.rkt")
        ,@definitions)))
   '(recursive-module-binding)
   (format "~s" definitions)))

(for ([definitions
       (in-list
        '(((def fixed function =
             ((lambda (self) (function (self self)))
              (lambda (self) (function (self self))))))
          ((def first value = (second value)) (def second value = value))
          ((def loop loop = loop))
          ((def loop value = ((lambda (loop) loop) value)))
          ((def loop value = (lambda-let loop = value loop)))))])
  (check-equal?
   (file-kinds
    `(module production "../macros/lazy-with-macros.rkt"
       (#%module-begin
        (require "../macros/macros.rkt")
        ,@definitions)))
   '()
   (format "~s" definitions)))

;; ---------------------------------------------------------------------------
;; Expressions: only variables, unary lambda, and unary application survive

(check-equal? (expression-kinds '(lambda (value) value))
              '())
(check-equal? (expression-kinds '(lambda (value) (value value)))
              '())
(check-equal? (expression-kinds '((lambda (value) value) left))
              '())
(check-equal? (expression-kinds '((raw-operation left) right))
              '())
(check-equal? (expression-kinds '(lambda (value)
                                   (lambda-let inner = value
                                     inner)))
              '())

;; Local shadowing of a reserved or host name is ordinary lambda binding.
(check-equal? (expression-kinds '(lambda (lambda) (lambda lambda)))
              '())
(check-equal? (expression-kinds '(lambda (define) (define define)))
              '())
(check-equal? (expression-kinds '(lambda (lambda-let)
                                   (lambda-let lambda-let)))
              '())
(check-equal? (expression-kinds '(lambda (car) (car car)))
              '())

(check-equal? (expression-kinds '(lambda (left right) left))
              '(non-unary-lambda))
(check-equal? (expression-kinds '(lambda arguments arguments))
              '(non-unary-lambda))

;; Lazy Racket sequences a second body form with a host `begin`.
(check-equal? (expression-kinds '(lambda (value) value value))
              '(forbidden-host-form))

(check-equal? (expression-kinds '(raw-operation left right))
              '(non-unary-application))
(check-equal? (expression-kinds '(raw-operation))
              '(non-unary-application))
(check-equal? (expression-kinds '(lambda (value) (value left right)))
              '(non-unary-application))

(for ([form (in-list
             '((if condition left right)
               (cond [condition left] [else right])
               (begin left right)
               (let ([inner left]) inner)
               (letrec ([inner left]) inner)
               (case-lambda [(value) value])
               (set! left right)
               (when condition left)
               (and left right)))])
  (check-equal? (expression-kinds form)
                '(forbidden-host-form)
                (format "~s" form)))

(for ([datum (in-list '(0 1 "text" #\a #t #f #(1) ()))])
  (check-equal? (expression-kinds (if (null? datum) ''() datum))
                '(forbidden-host-datum)
                (format "~s" datum)))

(check-equal? (expression-kinds '(car value))
              '(forbidden-host-identifier))
(check-equal? (expression-kinds '(display value))
              '(forbidden-host-identifier))

;; Lazy Racket applies its own strict primitives directly, so that
;; application is not the lazy template; the bare reference is judged by
;; its binding.
(check-equal? (expression-kinds '(! value))
              '(forbidden-host-form))
(check-equal? (expression-kinds '(lambda (value) !))
              '(unapproved-production-identifier))
(check-equal? (expression-kinds '(lambda (value) car))
              '(forbidden-host-identifier))

;; An unbound name does not compile, so it cannot pass.
(check-equal? (expression-kinds 'missing)
              '(expansion-failure))

;; ---------------------------------------------------------------------------
;; Module scaffolding

(define pure-dependency-datum
  '(module dependency "../macros/lazy-with-macros.rkt"
     (#%module-begin
      (require "../macros/macros.rkt")
      (provide identity)
      (def identity value =
        value))))

(define nested-pure-dependency-datum
  '(module dependency "../../macros/lazy-with-macros.rkt"
     (#%module-begin
      (require "../../macros/macros.rkt")
      (provide identity)
      (def identity value =
        value))))

(define scaffolding-datum
  '(module example "../macros/lazy-with-macros.rkt"
     (#%module-begin
      (require "../macros/macros.rkt"
               "dependency.rkt")
      (provide apply-identity
               (rename-out [apply-identity APPLY-IDENTITY]))
      (def apply-identity value =
        (identity value)))))

(check-equal? (file-kinds scaffolding-datum
                          (list (list "dependency.rkt"
                                      pure-dependency-datum)))
              '())

;; A plain `define` of a lambda compiles to the same term as `def`.
(check-equal?
 (file-kinds '(module example "../macros/lazy-with-macros.rkt"
                (#%module-begin
                 (provide identity)
                 (define identity
                   (lambda (value)
                     value)))))
 '())

(check-equal?
 (file-kinds '(module example "../macros/lazy-with-macros.rkt"
                (#%module-begin
                 (provide (rename-out [identity renamed]))
                 (require (only-in "../macros/macros.rkt" def))
                 (def identity value = value))))
 '())

(check-equal? (file-kinds '(module example racket/base
                             (#%module-begin)))
              '(unexpected-production-language))

(check-equal?
 (untrusted-shell-file-kinds
  '(module example "../macros/lazy-with-macros.rkt"
     (#%module-begin)))
 '(unexpected-production-language))

(check-equal? (file-kinds '(not a module))
              '(invalid-production-module))

(check-equal?
 (symlink-file-kinds
  '(module example "../macros/lazy-with-macros.rkt"
     (#%module-begin)))
 '(disallowed-production-path))

;; Module-level forms other than definitions, imports, and exports
(for ([form (in-list
             '((identity identity)
               (define-syntax-rule (sugar value) value)
               (define-syntax (transformer stx) stx)
               (begin-for-syntax (define compile-time 0))
               (module+ test (define inner 0))
               (define-values (first second) (values identity identity))))])
  (check-equal?
   (file-kinds `(module example "../macros/lazy-with-macros.rkt"
                  (#%module-begin
                   (require "../macros/macros.rkt"
                            (for-syntax racket/base))
                   (def identity value = value)
                   ,form)))
   '(disallowed-production-import disallowed-module-form)
   (format "~s" form)))

;; ---------------------------------------------------------------------------
;; Imports

(for ([spec (in-list
             '(racket/base
               (rename-in racket/base [car raw-first])
               (only-in racket/list first)
               (prefix-in host: racket/base)
               (except-in racket/base car)
               (for-syntax "dependency.rkt")
               (for-meta 1 "dependency.rkt")
               "sub/dependency.rkt"
               ".env.rkt"
               ".ENV.rkt"))])
  (check-not-false
   (member 'disallowed-production-import
           (file-kinds `(module example "../macros/lazy-with-macros.rkt"
                          (#%module-begin
                           (require ,spec)))
                       (list (list "dependency.rkt" pure-dependency-datum)
                             (list "sub/dependency.rkt"
                                   nested-pure-dependency-datum)
                             (list ".env.rkt" pure-dependency-datum)
                             (list ".ENV.rkt" pure-dependency-datum))))
   (format "~s" spec)))

(check-equal?
 (file-kinds '(module example "../macros/lazy-with-macros.rkt"
                (#%module-begin
                 (require "../macros/macros.rkt"
                          (rename-in "dependency.rkt"
                                     [identity renamed-identity]))
                 (provide call)
                 (def call value =
                   (renamed-identity value))))
             (list (list "dependency.rkt" pure-dependency-datum)))
 '())

;; A one-level sibling-directory import is a project import only when the
;; resolved file sits inside the repository: the exact spelling the effects
;; layer uses is rejected from a tree outside the project root, a two-level
;; parent spelling is rejected everywhere, and a sibling spelling into the
;; trusted macros directory is never an ordinary project import.
(let ()
  (define directory
    (make-temporary-file "attalambda-outside-~a"
                         'directory
                         (find-system-path 'temp-dir)))
  (define (fixture-kinds base spec)
    (define core (build-path base "core"))
    (define production (build-path core "production.rkt"))
    (make-directory* core)
    (unless (link-exists? (build-path base "macros"))
      (make-file-or-directory-link trusted-macros-directory
                                   (build-path base "macros")))
    (make-directory* (build-path base "other"))
    (write-datum (build-path base "other" "dependency.rkt")
                 pure-dependency-datum)
    (write-datum production
                 `(module production "../macros/lazy-with-macros.rkt"
                    (#%module-begin
                     (require "../macros/macros.rkt"
                              ,spec))))
    (map violation-kind (file-violations production)))
  (dynamic-wind
    void
    (lambda ()
      (check-equal?
       (fixture-kinds directory "../other/dependency.rkt")
       '(disallowed-production-import))
      (check-equal?
       (fixture-kinds (build-path directory "deep")
                      "../../other/dependency.rkt")
       '(disallowed-production-import))
      (check-equal?
       (fixture-kinds (build-path directory "third")
                      "../macros/lazy-with-macros.rkt")
       '(disallowed-production-import)))
    (lambda ()
      (delete-directory/files directory))))

(check-equal?
 (file-kinds '(module example "../macros/lazy-with-macros.rkt"
                (#%module-begin
                 (require (rename-in "dependency.rkt"
                                     [identity require]))))
             (list (list "dependency.rkt" pure-dependency-datum)))
 '(reserved-production-binding))

(check-equal? (production-files-under (string->path ".env.rkt"))
              '())

;; A directly supplied source beneath a dotenv-named parent is rejected
;; before the checker attempts to open it. The forbidden parent is not created.
(let ()
  (define directory (temporary-tree "dotenv-parent"))
  (dynamic-wind
    void
    (lambda ()
      (define source
        (build-path directory "private.env.local" "production.rkt"))
      (check-equal? (map violation-kind (file-violations source))
                    '(disallowed-production-path)))
    (lambda ()
      (delete-directory/files directory))))

;; Directory spellings that end in a separator must scan the same files.
(check-equal? (length (production-files-under
                       (path->directory-path core-directory)))
              30)

;; A symlinked directory under a production tree is reported, not skipped.
(let ()
  (define directory (temporary-tree "linked-directory"))
  (define elsewhere (build-path directory "elsewhere"))
  (define core (build-path directory "core"))
  (dynamic-wind
    (lambda ()
      (make-directory elsewhere)
      (make-directory core)
      (write-datum (build-path elsewhere "hidden.rkt")
                   '(module hidden "../macros/lazy-with-macros.rkt"
                      (#%module-begin)))
      (make-file-or-directory-link elsewhere
                                   (build-path core "linked")))
    (lambda ()
      (define found (production-files-under core))
      (check-equal? (length found) 1)
      (check-equal? (map violation-kind (file-violations (car found)))
                    '(disallowed-production-path)))
    (lambda ()
      (delete-directory/files directory))))

;; Two identical violations are two findings.
(check-equal?
 (file-kinds '(module example "../macros/lazy-with-macros.rkt"
                (#%module-begin
                 (require "../macros/macros.rkt")
                 (def first-head value = (car value))
                 (def second-head value = (car value)))))
 '(forbidden-host-identifier forbidden-host-identifier))

;; ---------------------------------------------------------------------------
;; Names

(for ([name (in-list '(lambda define def lambda-let define-function-name
                       require provide))])
  (check-equal?
   (file-kinds `(module example "../macros/lazy-with-macros.rkt"
                  (#%module-begin
                   (require "../macros/macros.rkt")
                   (def ,name value = value))))
   '(reserved-production-binding)
   (symbol->string name)))

(check-equal?
 (file-kinds '(module example "../macros/lazy-with-macros.rkt"
                (#%module-begin
                 (require "../macros/macros.rkt")
                 (provide host)
                 (def host request = request))))
 '(forbidden-host-identifier forbidden-host-identifier))

(check-equal?
 (file-kinds '(module example "../macros/lazy-with-macros.rkt"
                (#%module-begin
                 (require "../macros/macros.rkt")
                 (provide (rename-out [identity host]))
                 (def identity value = value))))
 '(forbidden-host-identifier))

(check-equal?
 (file-kinds '(module example "../macros/lazy-with-macros.rkt"
                (#%module-begin
                 (require "../macros/macros.rkt")
                 (def type-check2 value = value))))
 '(arity-specific-checker))

(check-equal?
 (file-kinds '(module example "../macros/lazy-with-macros.rkt"
                (#%module-begin
                 (require "../macros/macros.rkt")
                 (provide (rename-out [identity make-typed-function-3]))
                 (def identity value = value))))
 '(arity-specific-checker))

(check-equal?
 (file-kinds '(module example "../macros/lazy-with-macros.rkt"
                (#%module-begin
                 (require (rename-in "dependency.rkt"
                                     [identity type-check4]))))
             (list (list "dependency.rkt" pure-dependency-datum)))
 '(arity-specific-checker))

;; A module-level definition may reuse a host name; references then resolve
;; to the module's own pure binding.
(check-equal?
 (file-kinds '(module example "../macros/lazy-with-macros.rkt"
                (#%module-begin
                 (require "../macros/macros.rkt")
                 (provide car use-car)
                 (def car value = value)
                 (def use-car value = (car value)))))
 '())

;; ---------------------------------------------------------------------------
;; Exports

(check-equal?
 (file-kinds '(module example "../macros/lazy-with-macros.rkt"
                (#%module-begin
                 (provide car))))
 '(unapproved-production-export))

(check-equal?
 (file-kinds '(module example "../macros/lazy-with-macros.rkt"
                (#%module-begin
                 (provide (rename-out [car raw-first])))))
 '(unapproved-production-export))


;; `provide` compiles these transformations into plain or renamed exports,
;; and each exported binding is judged on its own.
(for ([spec (in-list
             '((all-from-out "dependency.rkt")
               (all-defined-out)
               (prefix-out raw- identity)
               (except-out (all-from-out "dependency.rkt") identity)))])
  (check-equal?
   (file-kinds `(module example "../macros/lazy-with-macros.rkt"
                  (#%module-begin
                   (require "dependency.rkt")
                   (provide ,spec)))
               (list (list "dependency.rkt" pure-dependency-datum)))
   '()
   (format "~s" spec)))

;; Export forms that survive to the compiled module unchanged are rejected.
(check-equal?
 (file-kinds '(module example "../macros/lazy-with-macros.rkt"
                (#%module-begin
                 (require "../macros/macros.rkt")
                 (def identity value = value)
                 (provide (protect-out identity)))))
 '(disallowed-production-export))

;; ---------------------------------------------------------------------------
;; Transitive imports

(define impure-provider-datum
  '(module provider "../macros/lazy-with-macros.rkt"
     (#%module-begin
      (provide raw-head)
      (define raw-head car))))

(define forwarding-dependency-datum
  '(module dependency "../macros/lazy-with-macros.rkt"
     (#%module-begin
      (require "provider.rkt")
      (provide raw-head))))

(check-equal?
 (file-kinds '(module example "../macros/lazy-with-macros.rkt"
                (#%module-begin
                 (require "../macros/macros.rkt"
                          "dependency.rkt")
                 (provide use)
                 (def use value = (raw-head value))))
             (list (list "dependency.rkt" forwarding-dependency-datum)
                   (list "provider.rkt" impure-provider-datum)))
 '(impure-production-import))

;; ---------------------------------------------------------------------------
;; Macros are judged by what they compile to

(define single-def-production-datum
  '(module production "../macros/lazy-with-macros.rkt"
     (#%module-begin
      (require "../macros/macros.rkt")
      (provide identity)
      (def identity value =
        value))))

(define transparent-def-macro-datum
  '(module macros lazy
     (require (for-syntax racket/base))
     (provide def)
     (define-syntax (def stx)
       (syntax-case stx (=)
         [(_ name argument = body)
          #'(define name
              (lambda (argument)
                body))]))))

(check-equal?
 (isolated-macro-file-kinds transparent-def-macro-datum
                            single-def-production-datum)
 '())

;; A macro that inspects its input — here, whether the syntax carries source
;; information — cannot show the checker a pure term and the compiler a host
;; datum, because the checker expands the same source the compiler does. (The
;; macro module itself is trusted by path, not scanned; see the checker's
;; header for that boundary.)
(define source-sensitive-macro-datum
  '(module macros lazy
     (require (for-syntax racket/base))
     (provide def)
     (define-syntax (def stx)
       (syntax-case stx (=)
         [(_ name argument = body)
          (if (syntax-source stx)
              #'(define name 0)
              #'(define name
                  (lambda (argument)
                    body)))]))))

(check-equal?
 (isolated-macro-file-kinds source-sensitive-macro-datum
                            single-def-production-datum)
 '(forbidden-host-datum))

(define generated-binding-macro-datum
  '(module macros lazy
     (require (for-syntax racket/base))
     (provide def)
     (define-syntax (def stx)
       (syntax-case stx (=)
         [(_ name argument = body)
          #'(begin
              (define generated-host-data 0)
              (define name
                (lambda (argument)
                  body)))]))))

(check-equal?
 (isolated-macro-file-kinds generated-binding-macro-datum
                            single-def-production-datum)
 '(forbidden-host-datum))

(define generated-value-macro-datum
  '(module macros lazy
     (require (for-syntax racket/base))
     (provide def)
     (define-syntax (def stx)
       (syntax-case stx (=)
         [(_ name argument = body)
          #'(define name
              0)]))))

(check-equal?
 (isolated-macro-file-kinds generated-value-macro-datum
                            single-def-production-datum)
 '(forbidden-host-datum))

(define generated-nested-syntax-macro-datum
  '(module macros lazy
     (require (for-syntax racket/base))
     (provide def
              lambda-let
              define-function-name)
     (define-syntax (def stx)
       (syntax-case stx (=)
         [(_ name argument = body)
          #'(define name
              (lambda (argument)
                body))]))
     (define-syntax (lambda-let stx)
       (syntax-case stx (=)
         [(_ name = value body)
          #'(if #t
                ((lambda (name) body) value)
                value)]))
     (define-syntax (define-function-name stx)
       (syntax-case stx ()
         [(_ binding rendered-name)
          #'(define binding
              0)]))))

(define generated-nested-syntax-production-datum
  '(module production "../macros/lazy-with-macros.rkt"
     (#%module-begin
      (require "../macros/macros.rkt")
      (provide identity
               rendered-name)
      (def identity value =
        (lambda-let local = value
          local))
      (define-function-name rendered-name identity))))

(check-equal?
 (isolated-macro-file-kinds generated-nested-syntax-macro-datum
                            generated-nested-syntax-production-datum)
 '(forbidden-host-form forbidden-host-datum))

;; A macro shell that rebinds `lambda` or `quote` for its own expansion is
;; judged by the term that results.
(define generated-shadowed-lambda-macro-datum
  '(module macros lazy
     (require (for-syntax racket/base))
     (provide def)
     (define-syntax lambda
       (syntax-rules ()
         [(_ (argument) body)
          (quote forbidden-host-value)]))
     (define-syntax (def stx)
       (syntax-case stx (=)
         [(_ name argument = body)
          #'(define name
              (lambda (argument)
                body))]))))

(check-equal?
 (isolated-macro-file-kinds generated-shadowed-lambda-macro-datum
                            single-def-production-datum)
 '(forbidden-host-datum))

(define generated-shadowed-host-form-macro-datum
  '(module macros lazy
     (require (for-syntax racket/base))
     (provide def)
     (define-syntax (def stx)
       (syntax-case stx (=)
         [(_ name argument = body)
          #'(define name
              (lambda (argument)
                (quote argument)))]))))

(check-equal?
 (isolated-macro-file-kinds
  generated-shadowed-host-form-macro-datum
  '(module production "../macros/lazy-with-macros.rkt"
     (#%module-begin
      (require "../macros/macros.rkt")
      (provide identity)
      (def identity quote =
        quote))))
 '(forbidden-host-datum))

;; A macro cannot smuggle in a value defined by the macro module itself,
;; whether that value is pure or host-backed.
(define helper-reference-macro-datum
  '(module macros lazy
     (require (for-syntax racket/base))
     (provide def)
     (define helper car)
     (define-syntax (def stx)
       (syntax-case stx (=)
         [(_ name argument = body)
          #'(define name
              helper)]))))

(check-equal?
 (isolated-macro-file-kinds helper-reference-macro-datum
                            single-def-production-datum)
 '(unapproved-production-identifier))

;; A macro cannot substitute a strict kernel lambda for the lazy one.
(define strict-lambda-macro-datum
  '(module macros lazy
     (require (for-syntax racket/base)
              (only-in racket/base [lambda strict-lambda]))
     (provide def)
     (define-syntax (def stx)
       (syntax-case stx (=)
         [(_ name argument = body)
          #'(define name
              (strict-lambda (argument)
                body))]))))

(check-equal?
 (isolated-macro-file-kinds strict-lambda-macro-datum
                            single-def-production-datum)
 '(forbidden-host-form))

;; The language shell itself is pinned: a shell whose `#%module-begin`
;; injects host data is rejected before any module is judged.
(define generated-module-begin-language-datum
  '(module lazy-with-macros racket/base
     (#%module-begin
      (require lazy/lazy
               (for-syntax racket/base))
      (define-syntax (impure-module-begin stx)
        (syntax-case stx ()
          [(_ form ...)
           #'(#%module-begin
              (define generated-host-data 0)
              form ...)]))
      (provide
       (except-out (all-from-out lazy/lazy)
                   #%module-begin)
       (rename-out
        [impure-module-begin #%module-begin])))))

(check-equal?
 (isolated-macro-file-kinds transparent-def-macro-datum
                            single-def-production-datum
                            generated-module-begin-language-datum)
 '(invalid-production-language-shell))

;; ---------------------------------------------------------------------------
;; The real core

(define production-results
  (files-violations (production-files-under core-directory)))

(check-equal? (length production-results)
              30)
(for ([entry (in-list production-results)])
  (check-equal? (cdr entry)
                '()
                (format "~a" (car entry))))

;; ---------------------------------------------------------------------------
;; The real effects layer passes the same expanded scan

(define-runtime-path effects-directory
  "../effects")

(define effects-results
  (files-violations (production-files-under effects-directory)))

(check-equal? (length effects-results)
              9)
(for ([entry (in-list effects-results)])
  (check-equal? (cdr entry)
                '()
                (format "~a" (car entry))))
