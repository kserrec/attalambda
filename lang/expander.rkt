#lang lazy

(require (for-syntax racket/base)
         (only-in racket/base
                  [void language-discard])
         (only-in "../macros/macros.rkt"
                  def
                  [lambda-let language-let])
         (only-in "../core/fix.rkt"
                  [raw-fix language-fix])
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
                  CHAR-GTE)
         (only-in "../core/int.rkt"
                  raw-make-int)
         (only-in "../core/list-nat.rkt"
                  [typed-len-rat LEN]
                  [typed-take-rat TAKE]
                  [typed-drop-rat DROP]
                  typed-nth-rat typed-range-rat typed-repeat-rat)
         (only-in "../core/list-search.rkt"
                  typed-any? typed-all? typed-find typed-find-index typed-contains?
                  typed-take-while typed-drop-while)
         (only-in "../core/list-transform.rkt"
                  typed-append typed-reverse typed-map typed-filter typed-reduce
                  typed-zip typed-concat typed-flatten)
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
         (only-in "../core/to-string.rkt"
                  error-to-string bool-to-string list-to-string result-to-string char-to-string string-to-string rat-to-string unit-to-string byte-to-string option-to-string map-to-string value-to-string)
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
         (only-in "../effects/print.rkt"
                  [make-print language-make-print])
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
                     [language-rec rec]
                     [language-let let]
                     [language-if if]
                     [language-cons cons]
                     [language-host host]
                     [language-exit exit]
                     [language-print print]
                     [HEAD head]
                     [TAIL tail]
                     [IS-NIL is-nil]
                     [LEN len]
                     [TAKE take]
                     [DROP drop]
                     [typed-nth-rat nth]
                     [typed-take-while take-while]
                     [typed-drop-while drop-while]
                     [typed-append append]
                     [typed-reverse reverse]
                     [typed-zip zip]
                     [typed-concat concat]
                     [typed-flatten flatten]
                     [typed-map map]
                     [typed-filter filter]
                     [typed-reduce reduce]
                     [typed-any? any?]
                     [typed-all? all?]
                     [typed-find find]
                     [typed-find-index find-index]
                     [typed-contains? contains?]
                     [typed-range-rat range]
                     [typed-repeat-rat repeat]
                     [NOT not]
                     [AND and]
                     [OR or]
                     [XOR xor]
                     [SUCC succ]
                     [ADD add]
                     [SUB sub]
                     [MULT mult]
                     [DIV div]
                     [EQ eq]
                     [LT lt]
                     [LTE lte]
                     [GT gt]
                     [GTE gte]
                     [IS-ZERO is-zero]
                     [MAKE-CHAR make-char]
                     [CHAR-EQ char-eq]
                     [CHAR-LT char-lt]
                     [CHAR-LTE char-lte]
                     [CHAR-GT char-gt]
                     [CHAR-GTE char-gte]
                     [MAKE-STRING make-string]
                     [STRING-EMPTY? string-empty?]
                     [STRING-LENGTH string-length]
                     [STRING-EQ string-eq]
                     [STRING-APPEND string-append]
                     [STRING-HEAD string-head]
                     [STRING-TAIL string-tail]
                     [STRING-PREFIX? string-prefix?]
                     [STRING-CONTAINS? string-contains?]
                     [EXP exp]
                     [RECIP recip]
                     [NEG neg]
                     [ABS abs]
                     [FLOOR floor]
                     [IS-WHOLE is-whole]
                     [IS-NONNEGATIVE-WHOLE is-nonnegative-whole]
                     [MAKE-BYTE make-byte]
                     [BYTE-VALUE byte-value]
                     [BYTE-EQ byte-eq]
                     [BYTE-LT byte-lt]
                     [BYTE-LTE byte-lte]
                     [BYTE-GT byte-gt]
                     [BYTE-GTE byte-gte]
                     [STRING-TO-BYTES string-to-bytes]
                     [BYTES-TO-STRING bytes-to-string]
                     [SOME some]
                     [IS-SOME is-some]
                     [IS-NONE is-none]
                     [OPTION-CASE option-case]
                     [MAKE-MAP make-map]
                     [MAP-EMPTY? map-empty?]
                     [MAP-SIZE map-size]
                     [MAP-LOOKUP map-lookup]
                     [MAP-CONTAINS? map-contains?]
                     [MAP-SET map-set]
                     [MAP-REMOVE map-remove])
         TRUE FALSE
         NIL
         UNIT
         NONE
         error-to-string bool-to-string list-to-string result-to-string char-to-string string-to-string rat-to-string unit-to-string byte-to-string option-to-string map-to-string value-to-string
         make-ok make-err is-ok is-err unwrap-ok unwrap-err
         EMPTY-STRING
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
(define-for-syntax (language-definition-form? form bound)
  (syntax-case form ()
    [(head . remaining)
     (and (identifier? #'head)
          (not (language-bound-name #'head bound))
          (or (free-identifier=? #'head #'def)
              (free-identifier=? #'head #'language-rec)))]
    [_ #f]))

(define-for-syntax (language-curried-lambdas arguments body)
  (if (null? arguments)
      body
      #`(lambda (#,(car arguments))
          #,(language-curried-lambdas (cdr arguments) body))))

;; Before expansion, compare prospective binders with their source references.
;; Equal spellings with different scopes must not become dependency edges.
(define-for-syntax (language-bound-name name names)
  (ormap (lambda (candidate)
           (and (identifier? name)
                (bound-identifier=? name candidate)
                candidate))
         names))

(define-for-syntax (language-definition-parts form)
  (syntax-case form ()
    [(_ name argument ... equals body)
     (and (identifier? #'name)
          (eq? (syntax-e #'equals) '=)
          (andmap identifier? (syntax->list #'(argument ...))))
     (list #'name (syntax->list #'(argument ...)) #'body)]
    [_ (raise-syntax-error #f "expected (def or rec name argument ... = body)" form)]))

(define-for-syntax (language-dependencies expression names bound)
  (cond
    [(identifier? expression)
     (let ([name (language-bound-name expression names)])
       (if (and name (not (language-bound-name expression bound)))
           (list name)
           '()))]
    [else
     (syntax-case expression ()
       [(head (argument) body)
        (and (identifier? #'head)
             (free-identifier=? #'head #'language-lambda)
             (identifier? #'argument)
             (not (language-bound-name #'head (append bound names))))
        (language-dependencies #'body names (cons #'argument bound))]
       [(head name equals value body)
        (and (identifier? #'head)
             (free-identifier=? #'head #'language-let)
             (identifier? #'name)
             (eq? (syntax-e #'equals) '=)
             (not (language-bound-name #'head (append bound names))))
        (append (language-dependencies #'value names bound)
                (language-dependencies #'body names (cons #'name bound)))]
       [(part ...)
        (apply append
               (map (lambda (part) (language-dependencies part names bound))
                    (syntax->list #'(part ...))))]
       [_ '()])]))

(define-for-syntax (language-check-definitions forms)
  ;; Module declarations expand in source order. Once a name shadows def or
  ;; rec, later calls to that binding are expressions, not declarations.
  (define definitions
    (let collect ([remaining forms] [bound '()])
      (cond
        [(null? remaining) '()]
        [else
         (define form (car remaining))
         (if (language-definition-form? form bound)
             (cons form
                   (collect (cdr remaining)
                            (cons (car (language-definition-parts form)) bound)))
             (collect (cdr remaining) bound))])))
  (define parts (map language-definition-parts definitions))
  (define names (map car parts))
  (define graph
    (map (lambda (form definition)
           (define name (car definition))
           (define arguments (cadr definition))
           (define bound
             (syntax-case form (language-rec)
               [(language-rec . remaining) (cons name arguments)]
               [_ arguments]))
           (cons name (language-dependencies (caddr definition) names bound)))
         definitions parts))
  (define (visit name path finished)
    (when (memq name path)
      (define self? (eq? name (car path)))
      (raise-syntax-error
       #f
       (if self?
           "recursive def binding is not allowed; use rec for self recursion"
           "module-binding recursion is forbidden; rec supports only self recursion")
       (syntax-property name 'attalambda-recursion (if self? 'self 'cycle))))
    (if (memq name finished)
        finished
        (cons name
              (foldl (lambda (dependency finished)
                       (visit dependency (cons name path) finished))
                     finished
                     (cdr (assq name graph))))))
  (foldl (lambda (name finished) (visit name '() finished)) '() names)
  definitions)

(define-syntax (language-module-begin stx)
  (syntax-case stx ()
    [(_ form ...)
     (with-syntax
         ([(prepared-form ...)
           (let ([definitions (language-check-definitions (syntax->list #'(form ...)))])
             (map (lambda (form)
                    (if (memq form definitions)
                        form
                        #`(language-discard #,form)))
                  (syntax->list #'(form ...))))])
       #'(#%module-begin prepared-form ...))]))

(define-syntax (language-rec stx)
  (syntax-case stx ()
    [(_ name argument ... equals body)
     (and (identifier? #'name)
          (not (eq? (syntax-e #'name) '=))
          (eq? (syntax-e #'equals) '=)
          (andmap (lambda (argument)
                    (and (identifier? argument)
                         (not (eq? (syntax-e argument) '=))))
                  (syntax->list #'(argument ...))))
     #`(def name =
         (language-fix
          (lambda (name)
            #,(language-curried-lambdas (syntax->list #'(argument ...)) #'body))))]
    [_ (raise-syntax-error #f "expected (rec name argument ... = body)" stx)]))

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

;; Lambda abstraction itself stays unary. `def` and `rec` provide currying
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

;; These are the only source datums. Expansion consumes every host number,
;; String, or Char and emits references plus unary applications that build
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
         [(char? datum)
          (if (<= (char->integer datum) 127)
              (language-char-expression (char->integer datum))
              (raise-syntax-error #f "Char literals must be ASCII (0-127)" stx))]
         [else
          (raise-syntax-error
           #f
           "only exact Rat, String, and ASCII Char literals are supported"
           stx)]))]))

;; The facade performs only one-time dependency injection. These bindings are
;; ordinary lambda values; only language-host is privileged.
(def stdout =
  (language-make-stdout language-host))

(def language-print =
  (language-make-print stdout))

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
