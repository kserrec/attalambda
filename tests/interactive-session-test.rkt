#lang racket/base

(require rackunit racket/promise
         "../runner/source-reader.rkt" "../runner/session.rkt"
         "../core/objects.rkt" "../readers/rat.rkt")

(define current (open-session))
(define output (open-output-bytes))
(define (prepare text) (prepare-entry current (parse-source-buffer 'repl:1 text)))

(dynamic-wind
 void
 (lambda ()
   (parameterize ([current-output-port output])
     (test-case "one checked entry preserves exact values and expression order"
       (define entry (prepare "(add 1/2 1/3) (mult 6 7)"))
       (define results '())
       (demand-entry current entry
                     (lambda (value)
                       (set! results
                             (cons (rat->number ((force raw-object-value) value))
                                   results))))
       (check-equal? (reverse results) '(5/6 42)))
     (test-case "expansion failure anywhere precedes every entry effect"
       (for ([bad '("unknown-name" "#t" "(def x = x)" "(require racket/base)"
                        "eval" "read-syntax" "current-input-port" "dynamic-require"
                        "language-discard" "(lambda (x) (eval x))"
                        "(#%top . eval)" "(#%top . dynamic-require)"
                        "(#%variable-reference)" "(quote 1)"
                        "(module native racket/base (display \"oops\"))"
                        "(def f = (lambda (x y) g)) (def g = (let ((x f)) x))"
                        "(def x = 1) (def x = 2)" "(def x = (let ((x x)) x))")])
         (get-output-bytes output #t)
         (check-exn exn:fail:syntax? (lambda () (prepare (string-append "(stdout \"no\") " bad))))
         (check-equal? (get-output-bytes output) #"" bad)))
     (test-case "ordinary effects are demanded once in source order"
       (define entry (prepare "(stdout \"A\") (stdout \"B\")"))
       (check-equal? (get-output-bytes output) #"")
       (demand-entry current entry)
       (check-equal? (get-output-bytes output) #"AB"))
     (test-case "automatic observation uses canonical rendering of computed results"
       (for ([example '(("(add 1/2 1/3)" "5/6")
                        ("(list 1 (some TRUE) (make-ok (list NONE UNIT)))"
                         "[1, SOME(TRUE), OK([NONE, UNIT])]")
                        ("(div 1 0)" "ERR(ERROR(DIVIDE-BY-ZERO))")
                        ("(head NIL)" "ERROR(EMPTY-LIST\n  -> head(result))")
                        ("(map-set (make-map string-eq) \"answer\" 42)"
                         "{\"answer\": 42}")
                        ("\"A\\x00\\xFF\"" "\"A\\x00\\xC3\\xBF\"")
                        ("#\\A" "#\\A")
                        ("(make-byte 255)" "BYTE(255)")
                        ("UNIT" "UNIT"))])
         (define actual '())
         (demand-entry current (prepare (car example))
                       (lambda (value)
                         (set! actual (cons (render-result current value) actual))))
         (check-equal? actual (list (cadr example)) (car example))))
     (test-case "rendering an effect result never repeats the expression"
       (get-output-bytes output #t)
       (define actual '())
       (demand-entry current (prepare "(stdout \"once\")")
                     (lambda (value)
                       (set! actual (list (render-result current value)
                                          (render-result current value)))))
       (check-equal? actual '("OK(UNIT)" "OK(UNIT)"))
       (check-equal? (get-output-bytes output) #"once"))
     (test-case "source bindings preserve hygiene without acquiring native privileges"
       (for ([example
              '(("(def eval = add) (eval 1 2)" "3")
                ("(def def x = x) (def 17)" "17")
                ("(def rec x = x) (rec 19)" "19")
                ("(def language-discard x = x) (language-discard 23)" "23")
                ("(def provide x = x) (provide 29)" "29")
                ("(def if x y z = 0) (cond (TRUE 31) (else 2))" "31")
                ("(def cons x y = 0) (def NIL = 0) (list 1 2)" "[1, 2]")
                ("(def x = (add y 1)) (def y = 36) x" "37")
                ("(rec count n = (if (eq n 0) 0 (count (sub n 1)))) (count 3)" "0"))])
         (define actual '())
         (demand-entry current (prepare (car example))
                       (lambda (value)
                         (set! actual (cons (render-result current value) actual))))
         (check-equal? actual (list (cadr example)) (car example))))
     (test-case "ordered demand shares an effect across results and subsequent demands"
       (get-output-bytes output #t)
       (define entry
         (prepare "(stdout \"A\") (def saved = (stdout \"X\")) saved saved (stdout \"B\")"))
       (check-equal? (get-output-bytes output) #"")
       (demand-entry current entry)
       (check-equal? (get-output-bytes output) #"AXB")
       (demand-entry current entry)
       (check-equal? (get-output-bytes output) #"AXB"))))
 (lambda () (close-session current) (close-output-port output)))
