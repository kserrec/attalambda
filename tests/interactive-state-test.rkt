#lang racket/base

(require rackunit racket/promise "../runner/source-reader.rkt" "../runner/session.rkt")

(define (with-state procedure)
  (define input (open-input-bytes #"one\ntwo\n"))
  (define output (open-output-bytes))
  (define current (open-session #:input input #:output output))
  (dynamic-wind
   void
   (lambda ()
     (parameterize ([current-input-port input] [current-output-port output])
       (procedure current input output)))
   (lambda () (close-session current) (close-input-port input) (close-output-port output))))

(define (submit current source [echo? #t])
  (define shown '())
  (evaluate-entry current (parse-source-buffer 'repl:state source)
                  (if echo?
                      (lambda (value)
                        (set! shown (cons (render-result current value) shown)))
                      void))
  (reverse shown))

(test-case "later entries import actual definitions and partial applications"
  (with-state
   (lambda (current input output)
     (check-equal? (submit current "(def double x = (mult x 2))") '())
     (check-equal? (submit current "(double 21)") '("42"))
     (check-equal? (submit current "(def add-ten = (add 10))") '())
     (check-equal? (submit current "(add-ten 5) (double (add-ten 1))") '("15" "22"))
     (check-equal? (get-output-bytes output) #""))))

(test-case "acyclic forward aliases and early expressions stay lazy"
  (with-state
   (lambda (current input output)
     (check-equal? (submit current "(def y = x) (def x = 7) y") '("7"))
     (check-equal? (submit current "x (def x = 11)") '("11"))
     (check-equal? (submit current "y x") '("7" "11"))
     (submit current "(def alias = later) (def later = (stdout \"once\"))")
     (submit current "(def answer = next) (def next = (read-line UNIT))")
     (check-equal? (get-output-bytes output) #"")
     (check-equal? (file-position input) 0)
     (check-equal? (submit current "alias later alias")
                   '("OK(UNIT)" "OK(UNIT)" "OK(UNIT)"))
     (check-equal? (get-output-bytes output) #"once")
     (check-equal? (submit current "answer next answer")
                   '("OK(SOME(\"one\"))" "OK(SOME(\"one\"))" "OK(SOME(\"one\"))"))
     (check-equal? (file-position input) 4))))

(test-case "retention cannot supply unknown future names or hide forbidden cycles"
  (with-state
   (lambda (current input output)
     (submit current "(def x = 1)")
     (define committed (session-bindings current))
     (for ([source '("(def f n = (unknown-later n))"
                      "(def x = (add x 1))"
                      "(def x = (let ((fresh x)) fresh))"
                      "(def x = (cond (FALSE 1) (else x)))"
                      "(def x = (list x))"
                      "(def x = y) (def y = x)"
                      "(def x = (lambda (n) y)) (def y = (let ((value x)) value))")])
       (check-exn exn:fail:syntax? (lambda () (submit current source)) source)
       (check-eq? (session-bindings current) committed))
     (check-equal? (submit current "(def forward = (add later 1)) (def later = 4) forward")
                   '("5"))
     (submit current "(rec sum n = (if (eq n 0) 0 (add n (sum (sub n 1)))))")
     (check-equal? (submit current "(sum 3)") '("6"))
     (check-equal? (get-output-bytes output) #""))))

(test-case "retained effects are silent until demanded and never replayed"
  (with-state
   (lambda (current input output)
     (submit current "(def saved = (read-line UNIT)) (def emitted = (stdout \"once\"))")
     (submit current "(def alias = saved)")
     (check-equal? (file-position input) 0)
     (check-equal? (get-output-bytes output) #"")
     (check-equal? (submit current "alias saved")
                   '("OK(SOME(\"one\"))" "OK(SOME(\"one\"))"))
     (check-equal? (submit current "saved") '("OK(SOME(\"one\"))"))
     (check-equal? (file-position input) 4)
     (check-equal? (submit current "emitted emitted") '("OK(UNIT)" "OK(UNIT)"))
     (check-equal? (submit current "emitted") '("OK(UNIT)"))
     (check-equal? (get-output-bytes output) #"once"))))

(test-case "redefinition replaces future imports while closures keep their snapshots"
  (with-state
   (lambda (current input output)
     (submit current "(def x = 1)")
     (submit current "(def plus-x n = (add x n)) (def delayed = (add x 100))")
     (submit current "(def x = 10) (def current-x = (add x 0))")
     (check-equal? (submit current "(plus-x 1) (add x 1) delayed current-x")
                   '("2" "11" "101" "10"))
     (submit current "(def x = 20)")
     (check-equal? (submit current "(plus-x 1) current-x (add x 1)")
                   '("2" "10" "21"))
     (define committed (session-bindings current))
     (check-exn exn:fail:syntax?
                (lambda () (submit current "(def x = 30) (def x = 40)")))
     (check-eq? (session-bindings current) committed)
     (check-equal? (submit current "x") '("20"))
     (check-equal? (get-output-bytes output) #""))))

(test-case "imported public syntax names are values and cannot capture private scaffolding"
  (for ([name '(def rec lambda let list cond require provide eval)])
    (with-state
     (lambda (current input output)
       (submit current (format "(def ~a n = n)" name))
       (check-equal? (submit current (format "(~a 17)" name)) '("17") (symbol->string name)))))
  (with-state
   (lambda (current input output)
     (submit current "(def held = 100) (def result = 200) (def lambda n = n)")
     (submit current "(def f n = (add n 1))")
     (submit current "(def alias = f)")
     (define (binding-value name)
       (define binding (hash-ref (session-bindings current) name))
       (parameterize ([current-namespace (session-namespace current)])
         (force (dynamic-require `(quote ,(cadr binding)) (caddr binding)))))
     (check-eq? (binding-value 'f) (binding-value 'alias))
     (check-equal? (submit current "(alias 20) (lambda 30) (add held result)")
                   '("21" "30" "300"))
     (submit current "(def cons x y = 0) (def NIL = 0) (def if x y z = 0)")
     (check-equal? (submit current "(list 1 2) (cond (TRUE 3) (else 4))")
                   '("[1, 2]" "3")))))

(test-case "shadowed syntax spellings do not hide dependency cycles"
  (for ([example '((list "(def f = (list f))")
                   (lambda "(def f = (lambda (f x) x))")
                   (let "(def f = (let ((f 1)) f))")
                   (cond "(def f = (cond (else f)))"))])
    (with-state
     (lambda (current input output)
       (submit current (format "(def ~a n = n)" (car example)))
       (define committed (session-bindings current))
       (check-exn exn:fail:syntax? (lambda () (submit current (cadr example))))
       (check-eq? (session-bindings current) committed)))))

(test-case "reader and expansion failures leave the entire committed map intact"
  (with-state
   (lambda (current input output)
     (submit current "(def old = 1)")
     (define committed (session-bindings current))
     (for ([source '("(def old = 2) (def added = 3) ("
                      "(stdout \"unreached\") (def old = 2) unknown-name")])
       (check-exn exn:fail? (lambda () (submit current source)))
       (check-eq? (session-bindings current) committed)
       (check-equal? (get-output-bytes output) #""))
     (check-equal? (submit current "old") '("1")))))

(test-case "native demand failure stops later expressions without publishing any new name"
  (with-state
   (lambda (current input output)
     (submit current "(def old = 1)")
     ;; Trusted test injection supplies a delayed native failure. User source
     ;; cannot create this fixture or import its Racket capabilities.
     (define fixture (gensym 'native-failure))
     (parameterize ([current-namespace (session-namespace current)])
       (eval `(module ,fixture lazy
                (provide bomb)
                (define bomb (error 'fixture "injected native failure")))))
     (set-session-bindings!
      current (hash-set (session-bindings current) 'bomb (list 'bomb fixture 'bomb)))
     (define committed (session-bindings current))
     (check-exn #rx"injected native failure"
                (lambda ()
                  (submit current
                          "(def old = 2) (def added = 3) (stdout \"A\") bomb (stdout \"B\")")))
     (check-equal? (get-output-bytes output) #"A")
     (check-eq? (session-bindings current) committed)
     (check-equal? (submit current "old") '("1")))))

(test-case "rendering failure and interruption occur before the single publication"
  (with-state
   (lambda (current input output)
     (submit current "(def old = 1)")
     (define committed (session-bindings current))
     (define parsed
       (parse-source-buffer 'repl:atomic "(def old = 2) (def a = 3) (def b = 4) (stdout \"A\")"))
     (check-exn #rx"injected rendering failure"
                (lambda ()
                  (evaluate-entry
                   current parsed
                   (lambda (value)
                     (check-true (break-enabled))
                     (check-equal? (render-result current value) "OK(UNIT)")
                     (error 'fixture "injected rendering failure")))))
     (check-equal? (get-output-bytes output) #"A")
     (check-eq? (session-bindings current) committed)
     (check-exn exn:break?
                (lambda ()
                  (evaluate-entry current parsed
                                  (lambda (value)
                                    (check-true (break-enabled))
                                    (break-thread (current-thread))))))
     (check-equal? (get-output-bytes output) #"AA")
     (check-eq? (session-bindings current) committed)
     (check-equal? (submit current "old") '("1")))))

(test-case "ordinary Error and Err results permit publication"
  (with-state
   (lambda (current input output)
     (submit current "(def old = 1)")
     (check-equal? (submit current "(def old = 2) (def added = 3) (head NIL) (div 1 0)")
                   '("ERROR(EMPTY-LIST\n  -> head(result))" "ERR(ERROR(DIVIDE-BY-ZERO))"))
     (check-equal? (submit current "old added") '("2" "3")))))

(test-case "a failed entry does not roll back already forced shared promises"
  (with-state
   (lambda (current input output)
     (submit current "(def old = 1) (def saved-output = (stdout \"once\")) (def saved-input = (read-line UNIT))")
     (define committed (session-bindings current))
     (for ([name '(saved-output saved-input)])
       (check-exn #rx"consumer failure"
                  (lambda ()
                    (evaluate-entry
                     current
                     (parse-source-buffer 'repl:shared
                                          (format "(def old = 2) (def added = 3) ~a" name))
                     (lambda (value) (error 'fixture "consumer failure")))))
       (check-eq? (session-bindings current) committed))
     (check-equal? (get-output-bytes output) #"once")
     (check-equal? (file-position input) 4)
     (check-equal? (submit current "saved-output saved-input old")
                   '("OK(UNIT)" "OK(SOME(\"one\"))" "1"))
     (check-equal? (get-output-bytes output) #"once")
     (check-equal? (file-position input) 4))))

(test-case "sorted committed names never inspect values or expose private results"
  (with-state
   (lambda (current input output)
     (check-equal? (session-names current) '())
     (submit current "(def z = (read-line UNIT)) (def a = (head NIL)) (def fn x = (stdout \"body\"))")
     (check-equal? (session-names current) '(a fn z))
     (submit current "17")
     (check-exn exn:fail:syntax? (lambda () (submit current "(def ghost = unknown)")))
     (check-equal? (session-names current) '(a fn z))
     (check-equal? (file-position input) 0)
     (check-equal? (get-output-bytes output) #""))))
