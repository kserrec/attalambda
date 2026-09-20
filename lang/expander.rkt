#lang lazy

(require (for-syntax racket/base "static-data.rkt" "static-source.rkt")
         (only-in racket/base
                  [void language-discard])
         (only-in "../macros/macros.rkt"
                  def
                  [lambda-let language-unary-let])
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
                  [typed-is-nil IS-NIL]
                  [typed-list-case LIST-CASE])
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
         (only-in "../effects/stdin.rkt"
                  [make-read-line language-make-read-line])
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
                     [language-list list]
                     [language-cond cond]
                     [language-if if]
                     [language-cons cons]
                     [language-host host]
                     [language-exit exit]
                     [language-print print]
                     [language-read-line read-line]
                     [HEAD head]
                     [TAIL tail]
                     [IS-NIL is-nil]
                     [LIST-CASE list-case]
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

;; Catalog labels are inert metadata. A source reference acquires one only by
;; free-identifier equality with the actual trusted binding on the left.
(define-for-syntax
 (language-analysis-builtins)
 (list
  (cons #'language-if "if")
  (cons #'language-cons "cons")
  (cons #'language-host "host")
  (cons #'language-exit "exit")
  (cons #'language-print "print")
  (cons #'language-read-line "read-line")
  (cons #'HEAD "head")
  (cons #'TAIL "tail")
  (cons #'IS-NIL "is-nil")
  (cons #'LIST-CASE "list-case")
  (cons #'LEN "len")
  (cons #'TAKE "take")
  (cons #'DROP "drop")
  (cons #'typed-nth-rat "nth")
  (cons #'typed-take-while "take-while")
  (cons #'typed-drop-while "drop-while")
  (cons #'typed-append "append")
  (cons #'typed-reverse "reverse")
  (cons #'typed-zip "zip")
  (cons #'typed-concat "concat")
  (cons #'typed-flatten "flatten")
  (cons #'typed-map "map")
  (cons #'typed-filter "filter")
  (cons #'typed-reduce "reduce")
  (cons #'typed-any? "any?")
  (cons #'typed-all? "all?")
  (cons #'typed-find "find")
  (cons #'typed-find-index "find-index")
  (cons #'typed-contains? "contains?")
  (cons #'typed-range-rat "range")
  (cons #'typed-repeat-rat "repeat")
  (cons #'NOT "not")
  (cons #'AND "and")
  (cons #'OR "or")
  (cons #'XOR "xor")
  (cons #'SUCC "succ")
  (cons #'ADD "add")
  (cons #'SUB "sub")
  (cons #'MULT "mult")
  (cons #'DIV "div")
  (cons #'EQ "eq")
  (cons #'LT "lt")
  (cons #'LTE "lte")
  (cons #'GT "gt")
  (cons #'GTE "gte")
  (cons #'IS-ZERO "is-zero")
  (cons #'MAKE-CHAR "make-char")
  (cons #'CHAR-EQ "char-eq")
  (cons #'CHAR-LT "char-lt")
  (cons #'CHAR-LTE "char-lte")
  (cons #'CHAR-GT "char-gt")
  (cons #'CHAR-GTE "char-gte")
  (cons #'MAKE-STRING "make-string")
  (cons #'STRING-EMPTY? "string-empty?")
  (cons #'STRING-LENGTH "string-length")
  (cons #'STRING-EQ "string-eq")
  (cons #'STRING-APPEND "string-append")
  (cons #'STRING-HEAD "string-head")
  (cons #'STRING-TAIL "string-tail")
  (cons #'STRING-PREFIX? "string-prefix?")
  (cons #'STRING-CONTAINS? "string-contains?")
  (cons #'EXP "exp")
  (cons #'RECIP "recip")
  (cons #'NEG "neg")
  (cons #'ABS "abs")
  (cons #'FLOOR "floor")
  (cons #'IS-WHOLE "is-whole")
  (cons #'IS-NONNEGATIVE-WHOLE "is-nonnegative-whole")
  (cons #'MAKE-BYTE "make-byte")
  (cons #'BYTE-VALUE "byte-value")
  (cons #'BYTE-EQ "byte-eq")
  (cons #'BYTE-LT "byte-lt")
  (cons #'BYTE-LTE "byte-lte")
  (cons #'BYTE-GT "byte-gt")
  (cons #'BYTE-GTE "byte-gte")
  (cons #'STRING-TO-BYTES "string-to-bytes")
  (cons #'BYTES-TO-STRING "bytes-to-string")
  (cons #'SOME "some")
  (cons #'IS-SOME "is-some")
  (cons #'IS-NONE "is-none")
  (cons #'OPTION-CASE "option-case")
  (cons #'MAKE-MAP "make-map")
  (cons #'MAP-EMPTY? "map-empty?")
  (cons #'MAP-SIZE "map-size")
  (cons #'MAP-LOOKUP "map-lookup")
  (cons #'MAP-CONTAINS? "map-contains?")
  (cons #'MAP-SET "map-set")
  (cons #'MAP-REMOVE "map-remove")
  (cons #'TRUE "TRUE")
  (cons #'FALSE "FALSE")
  (cons #'NIL "NIL")
  (cons #'UNIT "UNIT")
  (cons #'NONE "NONE")
  (cons #'error-to-string "error-to-string")
  (cons #'bool-to-string "bool-to-string")
  (cons #'list-to-string "list-to-string")
  (cons #'result-to-string "result-to-string")
  (cons #'char-to-string "char-to-string")
  (cons #'string-to-string "string-to-string")
  (cons #'rat-to-string "rat-to-string")
  (cons #'unit-to-string "unit-to-string")
  (cons #'byte-to-string "byte-to-string")
  (cons #'option-to-string "option-to-string")
  (cons #'map-to-string "map-to-string")
  (cons #'value-to-string "value-to-string")
  (cons #'make-ok "make-ok")
  (cons #'make-err "make-err")
  (cons #'is-ok "is-ok")
  (cons #'is-err "is-err")
  (cons #'unwrap-ok "unwrap-ok")
  (cons #'unwrap-err "unwrap-err")
  (cons #'EMPTY-STRING "EMPTY-STRING")
  (cons #'stdout "stdout")
  (cons #'read-file "read-file")
  (cons #'write-file "write-file")
  (cons #'tcp-connect "tcp-connect")
  (cons #'tcp-listen "tcp-listen")
  (cons #'tcp-accept "tcp-accept")
  (cons #'tcp-read "tcp-read")
  (cons #'tcp-write "tcp-write")
  (cons #'tcp-close "tcp-close")
  (cons #'parse-http-request "parse-http-request")
  (cons #'HTTP-STATUS-OK "HTTP-STATUS-OK")
  (cons #'HTTP-STATUS-BAD-REQUEST "HTTP-STATUS-BAD-REQUEST")
  (cons #'HTTP-STATUS-NOT-FOUND "HTTP-STATUS-NOT-FOUND")
  (cons
   #'HTTP-STATUS-INTERNAL-SERVER-ERROR
   "HTTP-STATUS-INTERNAL-SERVER-ERROR")
  (cons #'render-http-response "render-http-response")
  (cons #'make-http-path-handler "make-http-path-handler")
  (cons #'make-http-serve-one "make-http-serve-one")
  (cons #'make-http-server "make-http-server")))

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
       [(head (argument ...) body)
        (and (identifier? #'head)
             (free-identifier=? #'head #'language-lambda)
             (andmap identifier? (syntax->list #'(argument ...)))
             (not (language-bound-name #'head (append bound names))))
        (language-dependencies #'body names
                               (append (syntax->list #'(argument ...)) bound))]
       [(head . remaining)
        (and (identifier? #'head)
             (ormap (lambda (candidate) (free-identifier=? #'head candidate))
                    (list #'language-let #'language-list #'language-cond))
             (not (language-bound-name #'head (append bound names))))
        (language-dependencies (language-sugar-expression expression) names bound)]
       [(head name equals value body)
        (and (identifier? #'head)
             (free-identifier=? #'head #'language-unary-let)
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

(define-for-syntax (language-check-definitions forms [imported '()])
  ;; Module declarations expand in source order. Once a name shadows def or
  ;; rec, later calls to that binding are expressions, not declarations.
  (define definitions
    (let collect ([remaining forms] [bound imported])
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
  (let loop ([remaining names])
    (unless (null? remaining)
      (let ([duplicate (language-bound-name (car remaining) (cdr remaining))])
        (when duplicate
          (raise-syntax-error
           #f
           "duplicate definition; each name is defined once per module"
           (syntax-property duplicate 'attalambda-duplicate #t))))
      (loop (cdr remaining))))
  ;; A new local binding supersedes the imported name throughout this module.
  ;; In particular, a previous x must not hide a new def x's self-reference.
  (define retained
    (filter (lambda (name) (not (language-bound-name name names))) imported))
  (define graph
    (map (lambda (form definition)
           (define name (car definition))
           (define arguments (cadr definition))
           (define bound
             (syntax-case form (language-rec)
               [(language-rec . remaining) (cons name arguments)]
               [_ arguments]))
           (cons name (language-dependencies (caddr definition) names
                                             (append retained bound))))
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
     (let* ([forms (syntax->list #'(form ...))]
            ;; Only trusted tooling constructs this property. Restricted source
            ;; reading cannot create syntax properties or native module forms.
            [interaction (syntax-property stx 'attalambda-interaction)]
            [analysis (syntax-property stx analysis-request-key)]
            [imports (if interaction (car interaction) '())]
            [imported (map (lambda (binding) (datum->syntax stx (car binding))) imports)]
            [definitions (language-check-definitions forms imported)]
            [names (map (lambda (form) (car (language-definition-parts form))) definitions)]
            [results (if interaction
                         (map (lambda (name) (datum->syntax stx name)) (cadr interaction))
                         (map (lambda (form) #f) forms))]
            [result-names (filter values
                                  (map (lambda (form result)
                                         (and (not (memq form definitions)) result))
                                       forms results))])
       (with-syntax
           ([(import-form ...)
             (map (lambda (binding)
                    #`(require (only-in (quote #,(cadr binding))
                                        [#,(caddr binding)
                                         #,(datum->syntax stx (car binding))])))
                  (filter (lambda (binding)
                            (not (language-bound-name
                                  (datum->syntax stx (car binding)) names)))
                          imports))]
            [(export-form ...)
             (if interaction (list #`(provide #,@names #,@result-names)) '())]
            [(prepared-form ...)
             (map (lambda (form result)
                    (cond [(memq form definitions)
                           (if interaction
                               ;; Lazy Racket leaves bare aliases eager during
                               ;; module initialization. Pure suspension permits
                               ;; checked forward references without forcing them.
                               (syntax-case form ()
                                 [(head name argument ... equals body)
                                  #'(head name argument ... equals
                                          ((lambda (held) held) body))])
                               form)]
                          [interaction #`(def #,result = ((lambda (held) held) #,form))]
                          [else #`(language-discard #,form)]))
                  forms results)])
         (let ([prepared #'(#%module-begin import-form ... export-form ... prepared-form ...)])
           (cond
             [analysis
              (unless (and (eq? analysis analysis-request) (not interaction))
                (error 'static-source "invalid analysis request"))
              ;; Validate the entire ordinary expansion first. Only then expose
              ;; source metadata; invalid source never becomes a partial view.
              (syntax-property
               (local-expand prepared 'module-begin '()) analysis-result-key
               (make-source-view
                forms definitions language-definition-parts language-bound-name
                language-dependencies language-sugar-expression
                (list (cons 'lambda #'language-lambda) (cons 'let #'language-let)
                      (cons 'application #'language-application) (cons 'datum #'language-datum)
                      (cons 'unary-let #'language-unary-let) (cons 'list #'language-list)
                      (cons 'cond #'language-cond) (cons 'rec #'language-rec)
                      (cons 'nil #'NIL) (cons 'cons #'language-cons) (cons 'if #'language-if))
                (language-analysis-builtins)))]
             [else prepared]))))]))

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

;; These source conveniences disappear before object-language computation.
;; Dependency analysis uses the same lowering for sequential binders and else.
(define-for-syntax (language-sugar-expression stx)
  (syntax-case stx (language-lambda language-let language-list language-cond)
    [(language-lambda (first remaining ...) body)
     (andmap identifier? (syntax->list #'(first remaining ...)))
     (language-curried-lambdas (syntax->list #'(first remaining ...)) #'body)]
    [(language-let name equals value body)
     (and (identifier? #'name) (eq? (syntax-e #'equals) '=))
     #'(language-unary-let name = value body)]
    [(language-let () body) #'body]
    [(language-let ((name value) remaining ...) body)
     (identifier? #'name)
     #`(language-unary-let name = value
         #,(language-sugar-expression #'(language-let (remaining ...) body)))]
    [(language-list) #'NIL]
    [(language-list first remaining ...)
     #`((language-cons first)
        #,(language-sugar-expression #'(language-list remaining ...)))]
    [(language-cond (condition body))
     (eq? (syntax-e #'condition) 'else)
     #'body]
    [(language-cond (condition body) first remaining ...)
     (not (eq? (syntax-e #'condition) 'else))
     #`(((language-if condition) body)
        #,(language-sugar-expression #'(language-cond first remaining ...)))]
    [(language-lambda . remaining)
     (raise-syntax-error #f "expected (lambda (argument ...) body) with at least one identifier" stx)]
    [(language-let . remaining)
     (raise-syntax-error #f "expected (let name = value body) or (let ((name value) ...) body)" stx)]
    [(language-list . remaining)
     (raise-syntax-error #f "expected (list expression ...)" stx)]
    [(language-cond . remaining)
     (raise-syntax-error #f "expected (cond (condition result) ... (else result)); else must be last" stx)]))

(define-syntax (language-lambda stx)
  (language-sugar-expression stx))
(define-syntax (language-let stx)
  (language-sugar-expression stx))
(define-syntax (language-list stx)
  (language-sugar-expression stx))
(define-syntax (language-cond stx)
  (language-sugar-expression stx))

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

(def language-read-line =
  (language-make-read-line language-host))

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
