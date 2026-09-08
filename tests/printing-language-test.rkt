#lang racket/base

(require rackunit racket/list racket/runtime-path
         "helpers/fresh-language.rkt")

(define-runtime-path project-root "..")

;; These are standalone public-language programs, installed into an isolated
;; package home. No reader or private representation helper enters a program.
(define rendering-cases
  '(("error-to-string" "(head NIL)" "ERROR(EMPTY-LIST\n  -> head(result))" "ERROR")
    ("bool-to-string" "TRUE" "TRUE" "BOOL")
    ("list-to-string" "(cons 1 (cons TRUE (cons \"hello\" NIL)))" "[1, TRUE, \"hello\"]" "LIST")
    ("result-to-string" "(div 1 0)" "ERR(ERROR(DIVIDE-BY-ZERO))" "RESULT")
    ("char-to-string" "#\\A" "#\\A" "CHAR")
    ("string-to-string" "\"hello\"" "\"hello\"" "STRING")
    ("rat-to-string" "-7/3" "-7/3" "RAT")
    ("unit-to-string" "UNIT" "UNIT" "UNIT")
    ("byte-to-string" "(make-byte 255)" "BYTE(255)" "BYTE")
    ("option-to-string" "(some (cons 1 NIL))" "SOME([1])" "OPTION")
    ("map-to-string" "(map-set (make-map string-eq) \"answer\" 42)" "{\"answer\": 42}" "MAP")))

(call-with-fresh-language-install
 project-root
 (lambda (installation)
   (define root (fresh-language-install-temporary-root installation))
   (define environment (fresh-language-install-environment installation))
   (define (run-source name body)
     (define source (build-path root name))
     (write-source source (string-append "#lang attalambda\n" body))
     (run-command environment racket-executable (list (path->string source)) 20))

   (define pure-expressions
     (append-map
      (lambda (entry)
        (list (format "(~a ~a)\n" (first entry) (second entry))
              (format "(value-to-string ~a)\n" (second entry))))
      rendering-cases))
   (check-command-success
    (run-source "pure-rendering.attl" (apply string-append pure-expressions)) #"")

   (define checks
     (map
      (lambda (entry)
        (define name (first entry))
        (define input (second entry))
        (define expected (third entry))
        (define type (fourth entry))
        (define wrong (if (equal? name "bool-to-string") "UNIT" "TRUE"))
        (define actual (if (equal? name "bool-to-string") "UNIT" "BOOL"))
        (append
         (list (format "(check (string-eq (~a ~a) ~s))\n" name input expected)
               (format "(check (string-eq (value-to-string ~a) ~s))\n" input expected)
               (format "(check (string-eq (error-to-string (~a ~a)) ~s))\n"
                       name wrong
                       (format "ERROR(~a(arg1 expected ~a got ~a))" name type actual)))
         (if (equal? name "error-to-string") '()
             (list
              (format "(check (string-eq (error-to-string (~a (head NIL))) ~s))\n"
                      name (format "ERROR(EMPTY-LIST\n  -> head(result)\n  -> ~a(arg1 expected ~a))"
                                   name type))))))
      rendering-cases))
   ;; Keep the exact same contract checks in one small program per renderer;
   ;; compiling all diagnostic literals together exceeds the process deadline.
   (for ([group (in-list checks)] [entry (in-list rendering-cases)])
     (check-command-success
      (run-source (string-append (first entry) ".attl")
                  (string-append "(def check condition = (stdout (if condition \".\" \"!\")))\n"
                                 (apply string-append group)))
      (make-bytes (length group) 46)))

   (check-command-success
    (run-source "rendering-hygiene.attl"
                "(def raw-value-to-chars x = \"wrong\")\n(def render = rat-to-string)\n(stdout (string-append (render 42) (value-to-string TRUE)))\n")
    #"42TRUE")

   ;; print composes the pure representation with the existing stdout effect.
   (check-command-success
    (run-source "print-values.attl"
                (apply string-append
                       (for/list ([entry (in-list rendering-cases)])
                         (format "(print ~a)\n(stdout \"|\")\n" (second entry)))))
    (string->bytes/utf-8
     (apply string-append
            (map (lambda (entry) (string-append (third entry) "|")) rendering-cases))))
   (check-command-success
    (run-source "print-and-stdout.attl"
                "(stdout \"hello\")\n(print \"hello\")\n(print 5)\n(stdout 5)\n(print (cons 1 (cons TRUE NIL)))\n")
    #"hello\"hello\"5[1, TRUE]")
   (check-command-success
    (run-source "print-hygiene.attl"
                "(def stdout value = UNIT)\n(def value-to-string value = \"wrong\")\n(def show = print)\n(show 42)\n")
    #"42")
   (check-command-success
    (run-source "print-laziness.attl"
                "(if FALSE (print \"unused\") UNIT)\n(if (is-ok (print 42)) (stdout \"ok\") UNIT)\n")
    #"42ok")

   (for ([name (in-list '("raw-value-to-chars" "raw-error-diagnostic-string"
                         "typed-rat-to-string" "RAT-TO-STRING" "VALUE-TO-STRING"
                         "language-print" "language-make-print" "PRINT"))])
     (check-command-failure
      (run-source "private-renderer.attl" (format "(~a 1)\n" name))
      #rx"unbound identifier"))))
