#lang racket/base

(require rackunit racket/list racket/promise racket/runtime-path
         "../runner/source-reader.rkt")

(define-runtime-path facade "../lang/expander.rkt")
(define-runtime-path tests-directory ".")
(define-runtime-path purity-checker "../tooling/check-purity.rkt")
(dynamic-require purity-checker #f)
(define checker-namespace (module->namespace purity-checker))
(define (checker-binding name)
  (parameterize ([current-namespace checker-namespace]) (eval name)))
(define expression-violations (checker-binding 'expression-violations))
(define expand-reference-templates (checker-binding 'expand-reference-templates))
(define owner (make-custodian))
(define namespace (make-base-namespace))
(define input (open-input-bytes #"saved answer\nnext answer\n"))
(define output (open-output-bytes))

;; Test the private expander protocol directly, independently of shell execution.
(define (entry-syntax name text [imports '()] [language `(file ,(path->string facade))])
  (define parsed (parse-source-buffer 'repl:1 text))
  (define forms (source-buffer-forms parsed))
  (define body
    (syntax-property (datum->syntax #f (cons '#%module-begin forms))
                     'attalambda-interaction
                     (list imports (map (lambda (_) (gensym 'result)) forms))))
  (datum->syntax #f `(module ,name ,language ,body)))

(dynamic-wind
 void
 (lambda ()
   (parameterize ([current-custodian owner] [current-namespace namespace]
                  [current-input-port input] [current-output-port output])
     (dynamic-require facade #f)
     (test-case "actual private result, def, and rec bodies satisfy expanded purity"
       (define templates (expand-reference-templates namespace))
       (define (definitions expanded)
         (filter
          (lambda (form)
            (define parts (syntax->list form))
            (and parts (eq? (syntax-e (car parts)) 'define-values)))
          (cdr (syntax->list (fourth (syntax->list expanded))))))
       (for ([text '("-7/3 \"hello\" #\\A"
                     "(def x = 1) (add x 2)"
                     "(def y = x) (def x = 7) y"
                     "x (def x = 7)"
                     "(rec sum n = (if (eq n 0) 0 (add n (sum (sub n 1))))) (sum 3)"
                     "(list 1 (some TRUE)) (lambda (x y) (add x y))"
                     "(let ((x 1) (y (add x 1))) y) (cond (FALSE 1) (else 2))")])
         ;; The core checker's import policy expects relative project paths.
         ;; Only spell the trusted facade relatively here, as sugar-test does;
         ;; the actual private transformer still generates every checked body.
         (define bodies
           (parameterize ([current-load-relative-directory tests-directory])
             (definitions
               (expand (entry-syntax (gensym 'pure) text '() "../lang/expander.rkt")))))
         (check-equal? (length bodies)
                       (length (source-buffer-forms (parse-source-buffer 'test text))))
         (for ([definition (in-list bodies)])
           (check-equal?
            (expression-violations (third (syntax->list definition)) templates)
            '() text)))
       ;; The exact same gate and binding-aware templates reject native
       ;; computation; excluding module scaffolding must not exclude bodies.
       (define forbidden
         (definitions (expand '(module forbidden lazy (define answer (if #t 1 2))))))
       (check-equal? (length forbidden) 1)
       (check-not-equal?
        (expression-violations (third (syntax->list (car forbidden))) templates) '()))
     (test-case "private definition exports do not demand effects"
       (define name (gensym 'entry))
       (eval (entry-syntax name "(def saved = (read-line UNIT))\n(def emitted = (stdout \"once\"))"))
       (define path `(quote ,name))
       (define-values (exports syntax-exports) (module->exports path))
       (check-equal? (sort (map car (cdr (assoc 0 exports))) symbol<?) '(emitted saved))
       (check-equal? (file-position input) 0)
       (check-equal? (get-output-bytes output) #"")
       (define saved (dynamic-require path 'saved))
       (define emitted (dynamic-require path 'emitted))
       (check-equal? (file-position input) 0)
       (check-equal? (get-output-bytes output) #"")
       (force emitted)
       (check-equal? (get-output-bytes output) #"once")
       (force emitted)
       (check-equal? (get-output-bytes output) #"once"))
     (test-case "expression transport is lazy, ordered and shared"
       (get-output-bytes output #t)
       (define name (gensym 'entry))
       (define source
         (entry-syntax name
                       "(stdout \"A\") (def delayed = (stdout \"D\")) (stdout \"B\")"))
       (define identifiers
         (cadr (syntax-property (fourth (syntax->list source)) 'attalambda-interaction)))
       (define path `(quote ,name))
       (eval source)
       (dynamic-require path #f)
       (check-equal? (get-output-bytes output) #"")
       (define-values (exports syntax-exports) (module->exports path))
       (define names (map car (cdr (assoc 0 exports))))
       (define results (filter (lambda (name) (memq name names)) identifiers))
       (check-equal? (length results) 2)
       (check-not-false (memq 'delayed names))
       (define first-result (dynamic-require path (first results)))
       (define second-result (dynamic-require path (second results)))
       (check-equal? (get-output-bytes output) #"")
       (force first-result)
       (force first-result)
       (check-equal? (get-output-bytes output) #"A")
       (force second-result)
       (check-equal? (get-output-bytes output) #"AB"))
     (test-case "ordinary modules still force and discard expressions"
       (get-output-bytes output #t)
       (define name (gensym 'file))
       (eval `(module ,name (file ,(path->string facade))
                (def delayed = (stdout "unused"))
                (stdout "file")))
       (dynamic-require `(quote ,name) #f)
       (check-equal? (get-output-bytes output) #"file"))))
 (lambda ()
   (close-input-port input)
   (close-output-port output)
   (custodian-shutdown-all owner)))
