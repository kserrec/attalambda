#lang racket/base

(require rackunit
         racket/path
         racket/runtime-path
         "helpers/fresh-language.rkt")

(define-runtime-path project-root-path "..")
(define-runtime-path canonical-program
  "fixtures/language-canonical.rkt")

(define project-root
  (simplify-path project-root-path #f))

(define inherited-environment
  (environment-variables-copy
   (current-environment-variables)))
(define collection-path-separator
  (if (eq? (system-type 'os) 'windows)
      #";"
      #":"))
(environment-variables-set!
 inherited-environment
 #"PLTCOLLECTS"
 (bytes-append
  (path->bytes
   (build-path (find-system-path 'temp-dir)
               "attalambda-external-collections"))
  collection-path-separator))

(define (run-language-tests)
  (call-with-fresh-language-install
   project-root
   (lambda (installation)
    (define temporary-root
      (fresh-language-install-temporary-root installation))
    (define isolated-environment
      (fresh-language-install-environment installation))

    (check-false
     (environment-variables-ref isolated-environment #"PLTCOLLECTS"))

    (check-command-success
     (run-command isolated-environment
                  racket-executable
                  (list (path->string canonical-program))
                  20)
     (string->bytes/utf-8 "λ🙂"))

    (define retired-collection-program
      (build-path temporary-root "retired-collection.rkt"))
    (write-source
     retired-collection-program
     "#lang alone_the_lambdas\n")
    (check-command-failure
     (run-command isolated-environment
                  racket-executable
                  (list (path->string retired-collection-program))
                  20)
     #rx"collection not found|cannot open module file")

    (define currying-program
      (build-path temporary-root "currying.rkt"))
    (write-source
     currying-program
     #<<PROGRAM
#lang attalambda

(def add-two left right =
  (add left right))

(def add-two-to-two =
  (add-two 2))

(stdout
 (let identity = (lambda (value) value)
   (if (eq (add-two-to-two 2) 4)
       (identity "curried")
       "wrong")))
PROGRAM
     )
    (check-command-success
     (run-command isolated-environment
                  racket-executable
                  (list (path->string currying-program))
                  20)
     #"curried")

    ;; Exercise every renamed callable through the installed public language.
    ;; Each successful check prints one dot; an Error cannot silently pass
    ;; because its missing dot makes the exact output assertion fail.
    (define lowercase-program
      (build-path temporary-root "lowercase.rkt"))
    (write-source
     lowercase-program
     #<<PROGRAM
#lang attalambda

(def check condition = (stdout (if condition "." "!")))
(def values = (cons 1 (cons 2 NIL)))
(def byte-one = (make-byte 1))
(def byte-two = (make-byte 2))
(def table = (map-set (make-map eq) 1 10))

(check (eq (head values) 1))
(check (eq (head (tail values)) 2))
(check (is-nil NIL))
(check (eq (len values) 2))
(check (eq (len (take 1 values)) 1))
(check (eq (head (drop 1 values)) 2))
(check (not FALSE))
(check (and TRUE TRUE))
(check (or FALSE TRUE))
(check (xor FALSE TRUE))
(check (eq (succ 2) 3))
(check (eq (add -7/3 1/3) -2))
(check (eq (sub 5 2) 3))
(check (eq (mult 2 3) 6))
(check (eq (unwrap-ok (div 3 2)) 3/2))
(check (eq 1/2 2/4))
(check (lt 1 2))
(check (lte 2 2))
(check (gt 2 1))
(check (gte 2 2))
(check (is-zero 0))
(check (char-eq (make-char 65) #\A))
(check (char-eq #\A #\A))
(check (char-lt #\A #\B))
(check (char-lte #\A #\A))
(check (char-gt #\B #\A))
(check (char-gte #\A #\A))
(check (string-eq (make-string (cons #\A NIL)) "A"))
(check (string-empty? EMPTY-STRING))
(check (eq (string-length "ab") 2))
(check (string-eq "ab" "ab"))
(check (string-eq (string-append "a" "b") "ab"))
(check (char-eq (string-head "A") #\A))
(check (string-eq (string-tail "ab") "b"))
(check (string-prefix? "abc" "ab"))
(check (string-contains? "abc" "bc"))
(check (eq (unwrap-ok (exp 2 -2)) 1/4))
(check (eq (unwrap-ok (recip 2)) 1/2))
(check (eq (neg 2) -2))
(check (eq (abs -2) 2))
(check (eq (floor -3/2) -2))
(check (is-whole -2))
(check (is-nonnegative-whole 2))
(check (eq (byte-value (make-byte 255)) 255))
(check (eq (byte-value byte-one) 1))
(check (byte-eq byte-one byte-one))
(check (byte-lt byte-one byte-two))
(check (byte-lte byte-one byte-one))
(check (byte-gt byte-two byte-one))
(check (byte-gte byte-one byte-one))
(check (eq (byte-value (head (string-to-bytes "A"))) 65))
(check (string-eq (bytes-to-string (cons (make-byte 65) NIL)) "A"))
(check (option-case (some TRUE) (lambda (value) value) FALSE))
(check (is-some (some 1)))
(check (is-none NONE))
(check (option-case NONE (lambda (value) FALSE) TRUE))
(check (map-empty? (make-map eq)))
(check (not (map-empty? table)))
(check (eq (map-size table) 1))
(check (option-case (map-lookup table 1) (lambda (value) (eq value 10)) FALSE))
(check (map-contains? table 1))
(check (eq (map-size (map-set table 2 20)) 2))
(check (map-empty? (map-remove table 1)))
PROGRAM
     )
    (check-command-success
     (run-command isolated-environment
                  racket-executable
                  (list (path->string lowercase-program))
                  20)
     (make-bytes 63 46))

    ;; Expand a real language module for each retired name in one process.
    ;; Rejection must be an unbound identifier, not another expansion failure.
    (define retired-callables-probe
      (build-path temporary-root "retired-callables.rkt"))
    (write-source
     retired-callables-probe
     #<<PROBE
#lang racket/base

(parameterize ([current-namespace (make-base-namespace)])
  (for ([name (in-list
               '(HEAD TAIL IS-NIL LEN TAKE DROP NOT AND OR XOR
                 SUCC ADD SUB MULT DIV EQ LT LTE GT GTE IS-ZERO
                 MAKE-CHAR CHAR-EQ CHAR-LT CHAR-LTE CHAR-GT CHAR-GTE
                 MAKE-STRING STRING-EMPTY? STRING-LENGTH STRING-EQ
                 STRING-APPEND STRING-HEAD STRING-TAIL STRING-PREFIX?
                 STRING-CONTAINS? EXP RECIP NEG ABS FLOOR IS-WHOLE
                 IS-NONNEGATIVE-WHOLE MAKE-BYTE BYTE-VALUE BYTE-EQ BYTE-LT
                 BYTE-LTE BYTE-GT BYTE-GTE STRING-TO-BYTES BYTES-TO-STRING
                 SOME IS-SOME IS-NONE OPTION-CASE MAKE-MAP MAP-EMPTY?
                 MAP-SIZE MAP-LOOKUP MAP-CONTAINS? MAP-SET MAP-REMOVE
                 A B C D E F G H I J K L M N O P Q R S T U V W X Y Z
                 a b c d e f g h i j k l m n o p q r s t u v w x y z
                 DIGIT-0 DIGIT-1 DIGIT-2 DIGIT-3 DIGIT-4
                 DIGIT-5 DIGIT-6 DIGIT-7 DIGIT-8 DIGIT-9
                 SPACE TAB CR LF DOT COMMA COLON SEMICOLON
                 SLASH BACKSLASH HYPHEN UNDERSCORE QUESTION EQUAL AMPERSAND
                 PERCENT HASH LEFT-PAREN RIGHT-PAREN LEFT-BRACKET RIGHT-BRACKET
                 LEFT-BRACE RIGHT-BRACE))])
    (unless
        (with-handlers
            ([exn:fail:syntax?
              (lambda (failure)
                (regexp-match? #rx"unbound identifier" (exn-message failure)))])
          (expand `(module retired attalambda/lang/expander ,name))
          #f)
      (error 'retired-name "name did not fail as unbound: ~a" name)))
  (for ([name (in-list
               '(A B C D E F G H I J K L M N O P Q R S T U V W X Y Z
                 a b c d e f g h i j k l m n o p q r s t u v w x y z
                 DIGIT-0 DIGIT-1 DIGIT-2 DIGIT-3 DIGIT-4
                 DIGIT-5 DIGIT-6 DIGIT-7 DIGIT-8 DIGIT-9
                 SPACE TAB CR LF DOT COMMA COLON SEMICOLON
                 SLASH BACKSLASH HYPHEN UNDERSCORE QUESTION EQUAL AMPERSAND
                 PERCENT HASH LEFT-PAREN RIGHT-PAREN LEFT-BRACKET RIGHT-BRACKET
                 LEFT-BRACE RIGHT-BRACE))])
    (expand `(module available attalambda/lang/expander
               (def ,name = 1)
               (eq ,name 1)))))
PROBE
     )
    (check-command-success
     (run-command isolated-environment
                  racket-executable
                  (list (path->string retired-callables-probe))
                  20)
     #"")

    (define list-library-program
      (build-path temporary-root "list-library.rkt"))
    (write-source
     list-library-program
     #<<PROGRAM
#lang attalambda

(def check condition = (stdout (if condition "." "!")))
(def values = (cons 1 (cons 2 (cons 3 NIL))))
(def nested = (cons (cons 1 (cons (cons 2 NIL) NIL)) (cons (cons 3 NIL) NIL)))
(def loop value = (loop value))

(check (eq (len (append values (cons 4 NIL))) 4))
(check (eq (head (reverse values)) 3))
(check (eq (head (map succ values)) 2))
(check (eq (head (filter (lambda (value) (gt value 1)) values)) 2))
(check (is-nil (map loop NIL)))
(check (is-nil (filter loop NIL)))
(check (is-nil (reverse NIL)))
(check (is-nil (append NIL NIL)))
(check (eq (reduce sub 10 values) 4))
(check (any? (lambda (value) (gt value 1)) values))
(check (all? (lambda (value) (lt value 4)) values))
(check (option-case (find (eq 2) values) (lambda (value) (eq value 2)) FALSE))
(check (option-case (find-index (eq 2) values) (lambda (value) (eq value 1)) FALSE))
(check (contains? eq 2 values))
(check (any? (lambda (value) (if (eq value 1) TRUE (loop value))) values))
(check (not (all? (lambda (value) (if (eq value 1) FALSE (loop value))) values)))
(check (is-some (find (lambda (value) (if (eq value 1) TRUE (loop value))) values)))
(check (is-some (find-index (lambda (value) (if (eq value 1) TRUE (loop value))) values)))
(check (eq (reduce loop 5 NIL) 5))
(check (option-case (nth 1 values) (lambda (value) (eq value 2)) FALSE))
(check (is-none (nth 3 values)))
(check (eq (len (take-while (lambda (value) (lt value 3)) values)) 2))
(check (eq (head (drop-while (lambda (value) (lt value 2)) values)) 2))
(check (is-nil (take-while (lambda (value) (if (eq value 1) FALSE (loop value))) values)))
(check (eq (head (drop-while (lambda (value) (if (eq value 1) FALSE (loop value))) values)) 1))
(check (eq (head (tail (head (zip values (reverse values))))) 3))
(check (eq (len (concat nested)) 3))
(check (eq (head (head (tail (concat nested)))) 2))
(check (eq (reduce add 0 (flatten nested)) 6))
(check (is-nil (concat (cons NIL NIL))))
(check (is-nil (flatten (cons (cons NIL NIL) NIL))))
PROGRAM
     )
    (check-command-success
     (run-command isolated-environment
                  racket-executable
                  (list (path->string list-library-program))
                  20)
     (make-bytes 31 46))

    ;; Every ASCII literal must agree with make-char and a one-byte String.
    ;; Sending each through the existing String codec also validates its tag,
    ;; binary payload, and canonical List terminator.
    (define characters-program
      (build-path temporary-root "characters.rkt"))
    (write-source
     characters-program
     (string-append
      "#lang attalambda\n"
      "(def check-char character code text =\n"
      "  (stdout (if (and (char-eq character (make-char code))\n"
      "                   (char-eq character (string-head text)))\n"
      "              (make-string (cons character NIL)) \"FAIL\")))\n"
      (apply string-append
             (for/list ([code (in-range 128)])
               (define character (integer->char code))
               (format
                "(check-char ~s ~a ~s)\n"
                character code (string character))))
      "(def a = 1)\n(def x = 2)\n(def n = 3)\n(def m = 4)\n"
      "(stdout (if (eq (add (add a x) (add n m)) 10) \"names\" \"FAIL\"))\n"))
    (check-command-success
     (run-command isolated-environment
                  racket-executable
                  (list (path->string characters-program))
                  20)
     (bytes-append (list->bytes (build-list 128 values)) #"names"))

    (define lazy-branch-program
      (build-path temporary-root "lazy-branch.rkt"))
    (write-source
     lazy-branch-program
     #<<PROGRAM
#lang attalambda

(def loop value =
  (loop value))

(stdout
 (if FALSE
     (loop NIL)
     "lazy"))
PROGRAM
     )
    (check-command-success
     (run-command isolated-environment
                  racket-executable
                  (list (path->string lazy-branch-program))
                  20)
     #"lazy")

    ;; Public exit is an ordinary unary value, so a definition can alias it.
    ;; Invalid Rat statuses remain ordinary Errors and do not call native exit.
    (for ([case (in-list
                 '(("exit-alias.rkt"
                    "(def quit = exit)\n(quit 0)\n(stdout \"after\")\n"
                    #"")
                   ("invalid-exit.rkt"
                    "(exit 2)\n(stdout \"continued\")\n"
                    #"continued")))])
      (define program (build-path temporary-root (car case)))
      (write-source program (string-append "#lang attalambda\n" (cadr case)))
      (check-command-success
       (run-command isolated-environment
                    racket-executable
                    (list (path->string program))
                    20)
       (caddr case)))

    ;; Test tooling crosses the module boundary only to prove that expansion
    ;; produced canonical lambda values. None of this observation API is
    ;; exported by the object language.
    (define representation-program
      (build-path temporary-root "representations.rkt"))
    (write-source
     representation-program
     #<<PROGRAM
#lang attalambda

(def rat-zero = 0)
(def rat-one = 1)
(def rat-byte = 255)
(def rat-half = 1/2)
(def rat-negative = -7/3)
(def rat-large = 65536)
(def string-value = "λ🙂")
(def string-type-error = (string-append "hello" 3))
(def nested-type-error = (add (mult TRUE 1) 2))
(def map-callback-error = (map (lambda (value) (add TRUE value)) (cons 1 NIL)))
(def filter-callback-error = (filter (lambda (value) value) (cons 1 NIL)))
(def reduce-callback-error = (reduce sub TRUE (cons 1 NIL)))
(def any-callback-error = (any? (lambda (value) value) (cons 1 NIL)))
(def saved-host = host)
PROGRAM
     )

    (define representation-probe
      (build-path temporary-root "representation-probe.rkt"))
    (write-source
     representation-probe
     #<<PROBE
#lang racket/base

(require attalambda/runtime/codec)

;; Readers are test-side observers and intentionally absent from the package.
(define error-value->string
  (dynamic-require
   (string->path (vector-ref (current-command-line-arguments) 1))
   'error-value->string))

(define target
  (string->path
   (vector-ref (current-command-line-arguments) 0)))
(dynamic-require target #f)
(define target-namespace
  (module->namespace target))

(define (target-value name)
  (parameterize ([current-namespace target-namespace])
    (eval name)))

(write
 (map object-rat->exact
      (map target-value
           '(rat-zero rat-one rat-byte rat-half rat-negative rat-large))))
(newline)
(void
 (write-bytes
  (object-string->bytes
   (target-value 'string-value))))
(newline)
(displayln (error-value->string (target-value 'string-type-error)))
(displayln (error-value->string (target-value 'nested-type-error)))
(displayln (error-value->string (target-value 'map-callback-error)))
(displayln (error-value->string (target-value 'filter-callback-error)))
(displayln (error-value->string (target-value 'reduce-callback-error)))
(displayln (error-value->string (target-value 'any-callback-error)))
PROBE
     )
    (check-command-success
     (run-command isolated-environment
                  racket-executable
                  (list (path->string representation-probe)
                        (path->string representation-program)
                        (path->string (build-path project-root "readers" "error.rkt")))
                  20)
     (bytes-append
      #"(0 1 255 1/2 -7/3 65536)\n"
      (string->bytes/utf-8 "λ🙂\n")
      #"string-append(arg2 expected STRING got RAT)\n"
      #"mult(arg1 expected RAT got BOOL)\n  -> add(arg1 expected RAT)\n"
      #"add(arg1 expected RAT got BOOL)\n  -> map(result)\n"
      #"filter(arg1 expected BOOL got RAT)\n"
      #"sub(arg1 expected RAT got BOOL)\n  -> reduce(result)\n"
      #"any?(arg1 expected BOOL got RAT)\n"))

    (for ([case
           (in-list
            '(("#t" #rx"only exact Rat, String, and ASCII Char literals are supported")
              ("#f" #rx"only exact Rat, String, and ASCII Char literals are supported")
              ("1.0" #rx"only exact Rat, String, and ASCII Char literals are supported")
              ("1e3" #rx"only exact Rat, String, and ASCII Char literals are supported")
              ("+inf.0" #rx"only exact Rat, String, and ASCII Char literals are supported")
              ("+nan.0" #rx"only exact Rat, String, and ASCII Char literals are supported")
              ("1+2i" #rx"only exact Rat, String, and ASCII Char literals are supported")
              ("#\\é" #rx"Char literals must be ASCII")
              ("#\\u0080" #rx"Char literals must be ASCII")
              ("#\\λ" #rx"Char literals must be ASCII")
              ("#\\🙂" #rx"Char literals must be ASCII")
              ("#\"bytes\"" #rx"only exact Rat, String, and ASCII Char literals are supported")
              ("#:keyword" #rx"missing argument expression after keyword")
              ("#(1)" #rx"only exact Rat, String, and ASCII Char literals are supported")))]
          [index (in-naturals)])
      (define literal (car case))
      (define expected-message (cadr case))
      (define unsupported-program
        (build-path temporary-root
                    (format "unsupported-~a.rkt" index)))
      (write-source
       unsupported-program
       (string-append "#lang attalambda\n" literal "\n"))
      (check-command-failure
       (run-command isolated-environment
                    racket-executable
                    (list (path->string unsupported-program))
                    20)
       expected-message))

    (define multi-lambda-program
      (build-path temporary-root "multi-lambda.rkt"))
    (write-source
     multi-lambda-program
     "#lang attalambda\n(lambda (left right) left)\n")
    (check-command-failure
     (run-command isolated-environment
                  racket-executable
                  (list (path->string multi-lambda-program))
                  20)
     #rx"expected \\(lambda \\(argument\\) body\\)")

    (for ([source
           (in-list
            '("(define leaked 1)"
              "(require racket/base)"
              "(+ 1 2)"
              "(display \"leak\")"
              "(raw-cons 1 NIL)"
              "(typed-if TRUE \"yes\" \"no\")"
              "(_if TRUE \"yes\" \"no\")"
              "'quoted"))]
          [index (in-naturals)])
      (define isolated-program
        (build-path temporary-root
                    (format "isolated-~a.rkt" index)))
      (write-source
       isolated-program
       (string-append "#lang attalambda\n" source "\n"))
      (check-command-failure
       (run-command isolated-environment
                    racket-executable
                    (list (path->string isolated-program))
                    20)
       #rx"unbound identifier|not allowed in an expression")))
  ))

(parameterize ([current-environment-variables inherited-environment])
  (run-language-tests))
