#lang racket/base

(require rackunit racket/list racket/runtime-path
         "helpers/fresh-language.rkt"
         (prefix-in boundary: "../tooling/check-boundaries.rkt"))

(define-runtime-path project-root "..")
(define-runtime-path tests-directory ".")
(define-runtime-path purity-checker "../tooling/check-purity.rkt")

;; Judge the actual language-expanded expression with the existing purity
;; gate, retaining its binding checks and exact Lazy Racket unary templates.
;; Test-only observation avoids adding a new checker API or purity exception.
(dynamic-require purity-checker #f)
(define checker-namespace (module->namespace purity-checker))
(define (checker-binding name)
  (parameterize ([current-namespace checker-namespace]) (eval name)))
(define expression-violations (checker-binding 'expression-violations))
(define expand-reference-templates (checker-binding 'expand-reference-templates))
(define expansion-namespace (make-base-namespace))
(define templates (expand-reference-templates expansion-namespace))
(define (expanded-body language expression [definition-form '(def answer =)])
  (parameterize ([current-namespace expansion-namespace]
                 [current-load-relative-directory tests-directory])
    (define expanded
      (expand `(module probe ,language
                 (#%module-begin ,(append definition-form (list expression))))))
    (define definition
      (findf (lambda (form)
               (define parts (syntax->list form))
               (and parts (eq? (syntax-e (car parts)) 'define-values)))
             (cdr (syntax->list (cadddr (syntax->list expanded))))))
    (caddr (syntax->list definition))))

(for ([expression (in-list '((list) (list 1 (add 2 3) (list TRUE))
                            (lambda (x y z) (add x (add y z)))
                            (let ((x 2) (y (add x 3))) y)
                            (cond (FALSE 1) (TRUE 2) (else 3))))])
  (check-equal?
   (expression-violations (expanded-body "../lang/expander.rkt" expression) templates)
   '() (format "expanded purity: ~s" expression)))
;; A host conditional is rejected by the same expression gate and templates.
(check-not-equal?
 (expression-violations
  (expanded-body 'lazy '(if #t 1 2) '(define answer)) templates) '())

(check-equal?
 (boundary:file-boundary-violations
  (build-path project-root "lang" "expander.rkt") 'language-expander project-root)
 '())

(call-with-fresh-language-install
 project-root
 (lambda (installation)
   (define root (fresh-language-install-temporary-root installation))
   (define environment (fresh-language-install-environment installation))
   (define (run-source name body)
     (define path (build-path root name))
     (write-source path (string-append "#lang attalambda\n" body))
     (run-command environment racket-executable (list (path->string path)) 20))

   ;; Compare observable values to hand-written expansions, including computed
   ;; elements and propagated Errors; the renderer traverses every List tail.
   (define groups
     '((("(list)" "NIL")
        ("(list 1)" "(cons 1 NIL)")
        ("(list 1 2 3)" "(cons 1 (cons 2 (cons 3 NIL)))")
        ("(list (list 1 2) (list 3 4))" "(cons (cons 1 (cons 2 NIL)) (cons (cons 3 (cons 4 NIL)) NIL))")
        ("(list (add 1 2) (mult 2 3) \"hi\")" "(cons (add 1 2) (cons (mult 2 3) (cons \"hi\" NIL)))")
        ("(list 1 (head NIL))" "(cons 1 (cons (head NIL) NIL))"))
       (("((lambda (x) x) 4)" "4")
        ("((lambda (x y) (add x y)) 2 3)" "5")
        ("((lambda (x y z) (add x (add y z))) 1 2 3)" "6")
        ("(let f = ((lambda (x y) (add x y)) 2) (f 3))" "5")
        ("((lambda (x x) x) 1 2)" "((lambda (x) (lambda (x) x)) 1 2)"))
       (("(let ((x 2) (y 3)) (add x y))" "5")
        ("(let ((x 2) (y (add x 3))) y)" "(let x = 2 (let y = (add x 3) y))")
        ("(let x = 4 x)" "4")
        ("(let () 7)" "7")
        ("(let ((x 2) (x (add x 1))) x)" "3"))
       (("(cond (TRUE 1) (TRUE 2) (else 3))" "1")
        ("(cond (FALSE 1) (TRUE 2) (else 3))" "2")
        ("(cond (FALSE 1) (FALSE 2) (else 3))" "3")
        ("(cond (else 4))" "4")
        ("(cond (1 2) (else 3))" "(if 1 2 3)")
        ("(cond ((head NIL) 2) (else 3))" "(if (head NIL) 2 3)"))))
   (for ([group (in-list groups)] [index (in-naturals)])
     (check-command-success
      (run-source
       (format "sugar-values-~a.attl" index)
       (string-append
        "(def check condition = (stdout (if condition \".\" \"!\")))\n"
        (apply string-append
               (for/list ([entry (in-list group)])
                 (format "(check (string-eq (value-to-string ~a) (value-to-string ~a)))\n"
                         (first entry) (second entry))))))
      (make-bytes (length group) 46)))

   (check-command-success
    (run-source "sugar-lazy.attl"
                (string-append
                 "(rec loop x = (loop x))\n"
                 "(stdout ((lambda (x y) y) (loop NIL) \"a\"))\n"
                 "(stdout (let ((unused (loop NIL)) (answer \"b\")) answer))\n"
                 "(stdout (cond (FALSE (loop NIL)) (TRUE \"c\") ((loop NIL) (loop NIL)) (else (loop NIL))))\n"
                 "(stdout (if TRUE \"d\" (list (loop NIL))))\n"
                 "(print (head (list 1 (stdout \"tail\"))))\n"
                 "(print (head (cons 1 (cons (stdout \"tail\") NIL))))\n"))
    #"abcdtail1tail1")

   (check-command-success
    (run-source "sugar-scope.attl"
                (string-append
                 "(def f = (lambda (f y) (add f y)))\n"
                 "(def g = (let ((g 2) (y (add g 3))) y))\n"
                 "(def else = (cond (FALSE 0) (else 6)))\n"
                 "(def h = (let ((x 1) (h 2) (y (add x h))) y))\n"
                 "(rec sum = (lambda (n total) (cond ((eq n 0) total) (else (sum (sub n 1) (add total n))))))\n"
                 "(print (list (f 1 2) g else h (sum 3 0)))\n"
                 "(print (let ((list (lambda (x) x))) (list 7)))\n"
                 "(print (let ((cond (lambda (x) x))) (cond 8)))\n"
                 "(print (let ((let (lambda (x) x))) (let 9)))\n"))
    #"[3, 5, 6, 3, 6]789")
   ;; Generated constructors/conditionals retain their definition-site
   ;; bindings even when public names or private-looking spellings are shadowed.
   (check-command-success
    (run-source "sugar-hygiene.attl"
                "(def cons x y = 0)\n(def NIL = 0)\n(def if x y z = 0)\n(def language-cons = (list 2))\n(print (list 1))\n(print (cond (TRUE 3) (else 4)))\n(print language-cons)\n")
    #"[1]3[2]")

   ;; Expansion-only failures must never execute the preceding stdout.
   (define malformed
     '(("(lambda () 1)" "lambda")
       ("(lambda (x 1) x)" "lambda")
       ("(lambda x x)" "lambda")
       ("(lambda (x . y) x)" "lambda")
       ("(lambda (x) x x)" "lambda")
       ("(list 1 . 2)" "list")
       ("(let ((1 2)) 3)" "let")
       ("(let ((x)) x)" "let")
       ("(let ((x 1 2)) x)" "let")
       ("(let ((x 1) . tail) x)" "let")
       ("(let named ((x 1)) x)" "let")
       ("(let ((x 1)) x x)" "let")
       ("(cond)" "else must be last")
       ("(cond (TRUE 1))" "else must be last")
       ("(cond (else 1) (TRUE 2))" "else must be last")
       ("(cond (TRUE))" "else must be last")
       ("(cond (TRUE 1 2) (else 3))" "else must be last")
       ("(cond (TRUE => 1) (else 2))" "else must be last")
       ("(cond TRUE (else 1))" "else must be last")
       ("(cond (else 1) . tail)" "else must be last")))
   (define recursive
     '("(def f = (lambda (x y) f))"
       "(def f = (let ((f f)) f))"
       "(def f = (let ((x f) (f 1)) x))"
       "(def f = (list f))"
       "(def f = (cond (FALSE 1) (else f)))"
       "(def f = (lambda (x y) g))\n(def g = (let ((x f)) x))"
       "(def f let = (let ((f 1)) f))"
       "(def f lambda = (lambda (f x) x))"
       "(def f cond = (cond (else f)))"
       "(def f list = (list f))"))
   (for ([entry (in-list
                (append malformed
                        (map (lambda (source)
                               (list source "recursive def binding|module-binding recursion"))
                             recursive)))]
         [index (in-naturals)])
     (define result
       (run-source (format "invalid-sugar-~a.attl" index)
                   (string-append "(stdout \"must not run\")\n" (first entry) "\n")))
     (check-command-failure result (regexp (second entry)))
     (check-equal? (command-result-stdout result) #""))))
