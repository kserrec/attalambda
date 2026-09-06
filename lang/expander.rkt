#lang lazy

(require (for-syntax racket/base)
         (only-in racket/base
                  [void language-discard])
         (only-in "../macros/macros.rkt"
                  def
                  [lambda-let language-let])
         (only-in "../core/byte.rkt"
                  MAKE-BYTE
                  BYTE-VALUE
                  BYTE-EQ
                  BYTE-LT
                  BYTE-LTE
                  BYTE-GT
                  BYTE-GTE
                  STRING-TO-BYTES
                  BYTES-TO-STRING)
         (only-in "../core/chars.rkt"
                  raw-make-char
                  MAKE-CHAR
                  CHAR-EQ
                  CHAR-LT
                  CHAR-LTE
                  CHAR-GT
                  CHAR-GTE
                  A B C D E F G H I J K L M
                  N O P Q R S T U V W X Y Z
                  a b c d e f g h i j k l m
                  n o p q r s t u v w x y z
                  DIGIT-0 DIGIT-1 DIGIT-2 DIGIT-3 DIGIT-4
                  DIGIT-5 DIGIT-6 DIGIT-7 DIGIT-8 DIGIT-9
                  SPACE TAB CR LF
                  DOT COMMA COLON SEMICOLON
                  SLASH BACKSLASH HYPHEN UNDERSCORE
                  QUESTION EQUAL AMPERSAND PERCENT HASH
                  LEFT-PAREN RIGHT-PAREN
                  LEFT-BRACKET RIGHT-BRACKET
                  LEFT-BRACE RIGHT-BRACE)
         (only-in "../core/int.rkt"
                  raw-make-int)
         (only-in "../core/list-nat.rkt"
                  [typed-len-rat LEN]
                  [typed-take-rat TAKE]
                  [typed-drop-rat DROP])
         (only-in "../core/lists.rkt"
                  NIL
                  raw-cons
                  [typed-cons language-cons]
                  [typed-head HEAD]
                  [typed-tail TAIL]
                  [typed-is-nil IS-NIL])
         (only-in "../core/logic.rkt"
                  raw-false
                  raw-true)
         (only-in "../core/objects.rkt"
                  raw-make-object)
         (only-in "../core/map.rkt"
                  MAKE-MAP
                  MAP-EMPTY?
                  MAP-SIZE
                  MAP-LOOKUP
                  MAP-CONTAINS?
                  MAP-SET
                  MAP-REMOVE)
         (only-in "../core/option.rkt"
                  NONE
                  SOME
                  IS-SOME
                  IS-NONE
                  OPTION-CASE)
         (only-in "../core/pair.rkt"
                  raw-pair)
         (only-in "../core/result.rkt"
                  make-ok
                  make-err
                  is-ok
                  is-err
                  unwrap-ok
                  unwrap-err)
         (only-in "../core/strings.rkt"
                  raw-make-string
                  EMPTY-STRING
                  MAKE-STRING
                  STRING-EMPTY?
                  STRING-LENGTH
                  STRING-EQ
                  STRING-APPEND
                  STRING-HEAD
                  STRING-TAIL
                  STRING-PREFIX?
                  STRING-CONTAINS?)
         (only-in "../core/typed-logic.rkt"
                  TRUE
                  FALSE
                  NOT
                  AND
                  OR
                  XOR
                  [typed-if language-if])
         (only-in "../core/tags.rkt"
                  rat-type)
         (only-in "../core/unit.rkt"
                  UNIT)
         (only-in "../core/typed-rat.rkt"
                  [typed-rat-succ SUCC]
                  [typed-rat-add ADD]
                  [typed-rat-sub SUB]
                  [typed-rat-mult MULT]
                  [typed-rat-div DIV]
                  [typed-rat-exp EXP]
                  [typed-rat-recip RECIP]
                  [typed-rat-negate NEG]
                  [typed-rat-abs ABS]
                  [typed-rat-floor FLOOR]
                  [typed-rat-equal EQ]
                  [typed-rat-less LT]
                  [typed-rat-less-equal LTE]
                  [typed-rat-greater GT]
                  [typed-rat-greater-equal GTE]
                  [typed-rat-is-zero IS-ZERO]
                  [typed-rat-is-whole IS-WHOLE]
                  [typed-rat-is-nonnegative-whole IS-NONNEGATIVE-WHOLE])
         (only-in "../effects/exit.rkt"
                  [make-exit language-make-exit])
         (only-in "../effects/files.rkt"
                  [make-read-file language-make-read-file]
                  [make-write-file language-make-write-file])
         (only-in "../effects/http.rkt"
                  parse-http-request)
         (only-in "../effects/http-response.rkt"
                  HTTP-STATUS-OK
                  HTTP-STATUS-BAD-REQUEST
                  HTTP-STATUS-NOT-FOUND
                  HTTP-STATUS-INTERNAL-SERVER-ERROR
                  render-http-response)
         (only-in "../effects/http-server.rkt"
                  make-http-path-handler
                  make-http-serve-one
                  make-http-server)
         (only-in "../effects/stdout.rkt"
                  [make-stdout language-make-stdout])
         (only-in "../effects/tcp.rkt"
                  [make-tcp-connect language-make-tcp-connect]
                  [make-tcp-listen language-make-tcp-listen]
                  [make-tcp-accept language-make-tcp-accept]
                  [make-tcp-read language-make-tcp-read]
                  [make-tcp-write language-make-tcp-write]
                  [make-tcp-close language-make-tcp-close])
         (only-in "../runtime/host.rkt"
                  [host language-host]))

(provide #%top
         def
         (rename-out [language-module-begin #%module-begin]
                     [language-application #%app]
                     [language-datum #%datum]
                     [language-lambda lambda]
                     [language-let let]
                     [language-if if]
                     [language-cons cons]
                     [language-host host]
                     [language-exit exit])
         TRUE FALSE NOT AND OR XOR
         NIL HEAD TAIL IS-NIL LEN TAKE DROP
         SUCC ADD SUB MULT DIV EXP RECIP NEG ABS FLOOR
         EQ LT LTE GT GTE IS-ZERO IS-WHOLE IS-NONNEGATIVE-WHOLE
         UNIT
         MAKE-BYTE BYTE-VALUE BYTE-EQ BYTE-LT BYTE-LTE BYTE-GT BYTE-GTE
         STRING-TO-BYTES BYTES-TO-STRING
         SOME NONE IS-SOME IS-NONE OPTION-CASE
         MAKE-MAP MAP-EMPTY? MAP-SIZE MAP-LOOKUP
         MAP-CONTAINS? MAP-SET MAP-REMOVE
         make-ok make-err is-ok is-err unwrap-ok unwrap-err
         MAKE-CHAR CHAR-EQ CHAR-LT CHAR-LTE CHAR-GT CHAR-GTE
         A B C D E F G H I J K L M
         N O P Q R S T U V W X Y Z
         a b c d e f g h i j k l m
         n o p q r s t u v w x y z
         DIGIT-0 DIGIT-1 DIGIT-2 DIGIT-3 DIGIT-4
         DIGIT-5 DIGIT-6 DIGIT-7 DIGIT-8 DIGIT-9
         SPACE TAB CR LF
         DOT COMMA COLON SEMICOLON
         SLASH BACKSLASH HYPHEN UNDERSCORE
         QUESTION EQUAL AMPERSAND PERCENT HASH
         LEFT-PAREN RIGHT-PAREN
         LEFT-BRACKET RIGHT-BRACKET
         LEFT-BRACE RIGHT-BRACE
         EMPTY-STRING MAKE-STRING
         STRING-EMPTY? STRING-LENGTH STRING-EQ STRING-APPEND
         STRING-HEAD STRING-TAIL STRING-PREFIX? STRING-CONTAINS?
         stdout read-file write-file
         tcp-connect tcp-listen tcp-accept tcp-read tcp-write tcp-close
         parse-http-request
         HTTP-STATUS-OK
         HTTP-STATUS-BAD-REQUEST
         HTTP-STATUS-NOT-FOUND
         HTTP-STATUS-INTERNAL-SERVER-ERROR
         render-http-response
         make-http-path-handler
         make-http-serve-one
         make-http-server)

;; Racket's ordinary module wrapper prints every top-level expression result.
;; A language program instead forces each expression for its effects and
;; discards the resulting lambda value. Definitions remain definitions.
(define-for-syntax (language-definition-form? form)
  (syntax-case form (def)
    [(def . remaining) #t]
    [_ #f]))

(define-syntax (language-module-begin stx)
  (syntax-case stx ()
    [(_ form ...)
     (with-syntax
         ([(prepared-form ...)
           (map (lambda (form)
                  (if (language-definition-form? form)
                      form
                      #`(language-discard #,form)))
                (syntax->list #'(form ...)))])
       #'(#%module-begin prepared-form ...))]))

;; More than one source argument is notation for nested unary application.
;; The generated base case explicitly uses Lazy Racket's original #%app.
(define-syntax (language-application stx)
  (syntax-case stx ()
    [(_ function argument)
     #'(#%app function argument)]
    [(_ function first second remaining ...)
     #'(language-application
        (language-application function first)
        second
        remaining ...)]
    [_
     (raise-syntax-error
      #f
      "expected a function and at least one argument"
      stx)]))

;; Lambda abstraction itself stays unary. `def` is the separate currying
;; sugar for convenient named functions with any source arity.
(define-syntax (language-lambda stx)
  (syntax-case stx ()
    [(_ (argument) body)
     (identifier? #'argument)
     #'(lambda (argument) body)]
    [_
     (raise-syntax-error
      #f
      "expected (lambda (argument) body)"
      stx)]))

(define-for-syntax (language-list-expression elements)
  (if (null? elements)
      #'NIL
      #`((raw-cons #,(car elements))
         #,(language-list-expression (cdr elements)))))

(define-for-syntax (language-bit-expressions value)
  (map (lambda (digit)
         (if (char=? digit #\1)
             #'raw-true
             #'raw-false))
       (string->list
        (number->string value 2))))

(define-for-syntax (language-magnitude-expression value)
  (language-list-expression
   (language-bit-expressions value)))

;; An exact literal is already reduced with a positive denominator, so the
;; emitted term is the canonical stored representation: a tagged pair of a
;; signed magnitude and denominator bits.
(define-for-syntax (language-rat-expression value)
  #`((raw-make-object rat-type)
     ((raw-pair
       ((raw-make-int #,(if (negative? value)
                            #'raw-false
                            #'raw-true))
        #,(language-magnitude-expression (abs (numerator value)))))
      #,(language-magnitude-expression (denominator value)))))

(define-for-syntax (language-char-expression byte)
  #`(raw-make-char
     #,(language-list-expression
        (language-bit-expressions byte))))

(define-for-syntax (language-string-expression value)
  #`(raw-make-string
     #,(language-list-expression
        (map language-char-expression
             (bytes->list
              (string->bytes/utf-8 value))))))

;; These are the only source datums. Expansion consumes every host number or
;; String and emits only references plus unary lambda applications that build
;; the already-specified canonical representations.
(define-syntax (language-datum stx)
  (syntax-case stx ()
    [(_ . value)
     (let ([datum (syntax-e #'value)])
       (cond
         [(and (rational? datum) (exact? datum))
          (language-rat-expression datum)]
         [(string? datum)
          (language-string-expression datum)]
         [else
          (raise-syntax-error
           #f
           "only exact Rat and String literals are supported"
           stx)]))]))

;; The facade performs only one-time dependency injection. These bindings are
;; ordinary lambda values; only language-host is privileged.
(def stdout =
  (language-make-stdout language-host))

(def read-file =
  (language-make-read-file language-host))

(def write-file =
  (language-make-write-file language-host))

(def tcp-connect =
  (language-make-tcp-connect language-host))

(def tcp-listen =
  (language-make-tcp-listen language-host))

(def tcp-accept =
  (language-make-tcp-accept language-host))

(def tcp-read =
  (language-make-tcp-read language-host))

(def tcp-write =
  (language-make-tcp-write language-host))

(def tcp-close =
  (language-make-tcp-close language-host))

(def language-exit =
  (language-make-exit language-host))
