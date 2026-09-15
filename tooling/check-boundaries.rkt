#lang racket/base

;; Structural gate for the deliberately nonuniform language tree.
;; `check-purity.rkt` remains the expanded zero-exception proof for core/. This
;; checker inventories every Racket or `.attl` source and adds the approved
;; classes without weakening that proof:
;;
;;   core/                separately scanned pure unary-lambda computation
;;   effects/             pure source forms, including the HTTP server, and
;;                        also covered by check-purity's expanded scan
;;   macros/              the two exact mechanical expansion modules
;;   runtime/codec.rkt    deterministic conversion, no effect capabilities
;;   runtime/host.rkt     sole host export and the unchanged effect allowlist
;;   lang/reader.rkt      exact effect-free S-expression reader
;;   lang/expander.rkt    exact imports/exports and mechanical expansion only
;;   readers/             host observation only; no effects or upward imports
;;   tests/, tooling/     host-enabled support code, never production imports
;;   runner/attalambda.rkt       closed command/path/module-loading scaffolding
;;   examples/*.attl       exact standalone applications, tested end to end
;;   info.rkt             exact single-collection package metadata

(require racket/file
         racket/list
         racket/path
         racket/runtime-path)

(provide (struct-out boundary-violation)
         (struct-out source-classification)
         file-boundary-violations
         project-source-classifications
         project-boundary-violations)

(struct boundary-violation (path kind detail)
  #:transparent)

(struct module-info (language forms)
  #:transparent)

(struct source-classification (path class)
  #:transparent)

(define-runtime-path default-project-root "..")

(define effect-language "../macros/lazy-with-macros.rkt")
(define effect-macro-import "../macros/macros.rkt")

(define forbidden-codec-capabilities
  '(current-input-port current-output-port current-error-port
    read read-byte read-bytes read-line read-bytes-line write write-byte write-bytes
    display print printf eprintf flush-output
    open-input-file open-output-file call-with-input-file
    call-with-output-file file->bytes file->string
    directory-list make-directory make-directory* delete-directory
    delete-directory/files delete-file rename-file-or-directory copy-file
    tcp-connect tcp-listen tcp-accept tcp-close udp-open-socket
    exit system system* process process* subprocess shell-execute
    eval dynamic-require namespace-require make-base-namespace
    ffi-lib get-ffi-obj getenv putenv current-environment-variables
    thread thread/suspend-to-kill future place
    set! set-box! vector-set! hash-set! hash-set*! bytes-set! string-set!
    make-hash make-hasheq make-weak-hash register registry))

(define forbidden-host-capabilities
  '(read read-byte read-bytes read-line write write-byte display print printf
    open-input-file open-output-file call-with-input-file
    file->string
    directory-list make-directory make-directory* delete-directory
    delete-directory/files delete-file rename-file-or-directory copy-file
    udp-open-socket
    system system* process process* subprocess shell-execute
    eval dynamic-require namespace-require make-base-namespace
    ffi-lib get-ffi-obj getenv putenv current-environment-variables
    thread thread/suspend-to-kill future place))

;; These spellings denote pure wrappers at the language boundary. Exact
;; imports/definitions and export-only occurrence checks retain native bans.
(define forbidden-language-capabilities
  (remove* '(tcp-connect tcp-listen tcp-accept tcp-close exit print read-line)
           forbidden-codec-capabilities))

;; The runner is trusted only to decide whether and how the host process loads
;; the one explicitly supplied source. Its exact import and source vocabulary
;; leave dynamic module loading unavailable everywhere else.
(define forbidden-runner-capabilities
  '(current-environment-variables getenv putenv
    read read-char read-line read-string read-syntax
    open-input-file open-output-file call-with-output-file
    write write-byte write-bytes print printf
    file->bytes file->string
    directory-list make-directory make-directory* delete-directory
    delete-directory/files delete-file rename-file-or-directory copy-file
    tcp-connect tcp-listen tcp-accept tcp-close udp-open-socket
    system system* process process* subprocess shell-execute
    eval eval-syntax load namespace-require make-base-namespace
    ffi-lib get-ffi-obj
    thread thread/suspend-to-kill future place
    set! set-box! vector-set! hash-set! hash-set*! bytes-set! string-set!
    make-hash make-hasheq make-weak-hash register registry))

(define runner-vocabulary
  '(#%module-begin = _ and arguments binary build-path bytes->string/utf-8 bytes-length
    bytes? cadr call-with-input-file car column command-misuse-status cond content
    current-command-line-arguments datum->syntax define define-syntax display dynamic-require
    else embedded-product-version eprintf eq? equal? exit
    exn:fail:filesystem:missing-module-path exn:fail:filesystem:missing-module?
    exn:fail:filesystem? exn:fail:read-srclocs exn:fail:read? exn:fail:syntax? exn:fail?
    expression failure for-syntax help-text if input inspect-source-file inspected invalid
    invalid-source-status lambda length line location locations main matched missing-path
    newline not only-in pair? path->complete-path path-only path? product-version quote
    racket/base racket/path raise-syntax-error read-bytes reason regexp-match regexp-match?
    requested-source-missing? require run-source simplify-path source source-name source-path
    source-problem-column source-problem-kind source-problem-line source-problem-reason
    source-problem? srcloc-column srcloc-line status stop string-append stx syntax-column
    syntax-failure-expression syntax-failure-reason syntax-line syntax-source
    unavailable-source-status unexpected-failure-status unless up validate-source
    validated-source-path vector->list when with-handlers
    current-input-port current-error-port define-runtime-module-path-index interactive? member or
    racket/runtime-path repl-index run-repl terminal-port?))

(define expected-runner-requires
  '((require "source-file.rkt" racket/runtime-path
             (for-syntax racket/base (only-in racket/path path-only)))))

(define expected-runner-definitions
  '(command-misuse-status invalid-source-status unavailable-source-status
    unexpected-failure-status repl-index help-text embedded-product-version stop validate-source
    requested-source-missing? run-source main))

(define expected-runner-status-definitions
  '((define command-misuse-status 64)
    (define invalid-source-status 65)
    (define unavailable-source-status 66)
    (define unexpected-failure-status 70)))

(define expected-runner-input-targets
  '((build-path (path-only source) (quote up) "VERSION")))

;; Readers may turn completed values into host values for tests and people,
;; but they are not another effects layer. Host control flow and data are
;; allowed there; external I/O, mutation, registries, process/eval/FFI access,
;; and upward production dependencies are not.
(define reader-host-imports
  '(racket/list racket/promise racket/string))

;; This is the complete source vocabulary observed across the eight approved
;; one-way reader modules. Together with the narrow import direction, it turns
;; the reader rule into a closed allowlist instead of relying on an inevitably
;; incomplete catalog of Racket/base effects.
(define reader-vocabulary
  '(#%module-begin * + - / <= = actual-type add1 apply argument bit bool
    bool->boolean car case cdr char char-value->integer char-value->string code
    cons define details else error error-frames->oldest-first
    error-kind->string error-value->string for/fold force format frame
    frame->string frames function function-name if in-list int->integer
    integer->char kind
    kind-number lambda lazy-apply let let* list list->host-list loop map memv
    module null? or position provide quote racket/base
    racket/list racket/promise racket/string raw-boolean raw-boolean->boolean
    byte-value->integer
    rat->number raw-byte-value raw-char-value
    raw-error-frame-argument-position raw-error-diagnostic-string
    raw-object-type
    raw-int-magnitude raw-int-sign
    raw-rat-denominator raw-rat-numerator
    raw-error-frame-expected-type raw-error-frame-function-name
    raw-error-frames raw-error-root raw-error-root-details raw-error-root-kind
    raw-object-value raw-string-value
    raw-type-mismatch-actual-type raw-type-mismatch-argument-position
    raw-type-mismatch-expected-type read-value remaining require reverse root
    string string-append string-join string-value->string tag-number
    supported-ascii-code? total type-mismatch-root->string type-tag
    type-tag->integer type-tag->string typed-head typed-is-nil typed-tail
    length map->string option->string raw-map-entries raw-option-is-some
    entry
    unit->string value
    values))

(define privileged-host-only-identifiers
  '(current-output-port flush-output
    file->bytes call-with-output-file
    read-bytes-avail! write-bytes write-bytes-avail
    tcp-addresses
    close-input-port close-output-port
    make-hash hash-ref hash-set! hash-remove! set!))

;; Exact source vocabularies make the implicit racket/base import explicit.
;; Adding even an otherwise unknown identifier to either trusted runtime file
;; requires a deliberate update here in the same phase that approves it.
(define phase16-codec-vocabulary
  '(#%module-begin * + - / <= = > NIL NONE abs and apply argument bit bits
    object-none object-some raw-make-some
    bits-value bottom
    advance-tortoise? boolean? build-object-byte build-object-char
    build-vector byte->object-char bytes bytes->immutable-bytes
    bytes->object-string bytes? canonical-object-bytes
    canonical-object-chars car cdr char char-type chars codec
    codec-failure codec-failure? codec-false codec-true cond cons decoded
    define denominator else eq? error-value exact->object-rat exact?
    exn:fail? expected
    failure false-marker first
    for/fold for/list for/or force function gcd
    host-list->object-list if in-bytes in-list integer
    integer->raw-bits integers
    lambda lazy-apply lazy-apply2 length let list list-type loop magnitude
    malformed-value-failure map
    module negative? nil? not null? numerator object-char->byte
    object-err
    object-has-type? object-list->host-list object-list->immutable-bytes object-ok
    object-rat->exact object-unit object-byte->integer
    object-byte-list->bytes bytes->object-byte-list integer->object-byte
    element element->integer elements byte-type raw-make-byte raw-byte-value
    object-string->bytes odd? only-in or ormap
    out-of-range payload provide quote quotient racket/base racket/promise
    raise-argument-error rat-type rational? raw-bit->boolean raw-bits->byte
    raw-bits->integer
    raw-boolean->boolean raw-char-value raw-cons raw-false raw-int-magnitude
    raw-int-sign raw-is-type
    raw-list-head raw-list-is-nil raw-list-tail raw-make-char raw-make-err
    raw-make-int raw-make-object raw-make-ok raw-make-string
    raw-object-value raw-pair raw-rat-denominator
    raw-rat-numerator raw-string-value
    raw-true reason remaining require result reverse reversed second
    selected sign string-type struct struct-out tail
    next-tortoise tortoise total true-marker UNIT
    unless vector-ref
    value
    values with-handlers wrong-type zero?))

(define phase16-host-vocabulary
  '(#%module-begin + < <= = > EMPTY-STRING add1 address-in-use-code amount
    any current-input-port read-bytes-line read-line-operation perform-read-line
    object-none object-some
    and argument argument-count arguments attempt-close backlog begin bound-port broken-pipe-code buffer
    bytes-length bytes->object-string bytes->string/utf-8 bytes=? cadr caddr
    cadddr call-with-output-file car case cdr cleanup-new-connection
    cleanup-new-listener close-entry close-input-port close-output-port
    close-procedure code codec-failure-reason codec-failure? cond connection
    connection-entry connection-entry-input connection-entry-output
    connection-entry? connection-handle connection-refused-code
    connection-reset-code contract-code current-output-port decode-bounded-count
    decode-utf8
    decoded decoded-request define define-values discard-entry!
    dispatch-one-string dispatch-request else end eof-object? entry
    eq? errno errno-in? exact-nonnegative-integer? exact-positive-integer?
    exit exit-operation
    exn:fail:contract? exn:fail:filesystem:errno-errno
    exn:fail:filesystem:errno? exn:fail:network:errno-errno
    exn:fail:network:errno? exn:fail? exn:fail:out-of-memory? expected? failure
    file->bytes file-failure filesystem-failure-code first flush-output force
    function gai handle handle-registry hash-ref hash-remove! hash-set! host
    host-failure host-list->object-list if input exact->object-rat
    invalid-codec-request invalid-handle-code invalid-path-code invalid-request
    invalid-text-code io-failure-code lambda lazy-apply lazy-apply2 length let
    let-values list listener listener-entry listener-entry-listener
    listener-entry? local local-address local-payload lookup-entry loop
    make-bytes make-hash make-host-bridge make-host-failure
    make-invalid-host-request maximum memv minimum module
    name-resolution-failed-code network-failure network-failure-code
    network-unreachable-code next-handle not not-found-code null?
    object-err object-list->host-list object-rat->exact object-ok
    object-unit object-byte-list->bytes bytes->object-byte-list
    object-string->bytes only-in operation operation-bytes operation-value or
    out-of-range out-of-range-reason output output-failure pair? path
    path-payload payload perform-exit perform-read-file perform-stdout perform-tcp-accept
    perform-tcp-close perform-tcp-connect perform-tcp-listen perform-tcp-read
    perform-tcp-write perform-write-file performer permission-denied-code port
    posix posix-numbers prior-failure provide quote racket/base racket/file racket/promise
    racket/tcp read-bytes-avail! read-file-operation reason reason->object
    register-entry! remote remote-address remote-payload remote-port request
    require resource-exhausted-code second set! start status stdout-operation string=?
    string? struct subbytes tcp-accept tcp-accept-operation tcp-addresses
    tcp-close tcp-close-operation tcp-connect tcp-connect-operation tcp-listen
    tcp-listen-operation tcp-read-operation tcp-write-operation timed-out-code
    truncate unknown-operation-reason value void when windows windows-numbers with-handlers
    write-all-bytes write-bytes write-bytes-avail write-file-operation written
    wrong-arity wrong-arity-reason wrong-handle-kind-code wrong-type-reason zero?))

(define macro-vocabulary
  '(... = NIL _ and andmap argument arguments binding bit-expressions body
    byte bytes->list car cdr char=? character-expressions context
    curried-lambdas datum->syntax def define define-for-syntax
    define-function-name define-syntax digit elements eq? equals for-syntax
    function-name-expression identifier? if lambda lambda-let map name
    name-byte-expression name-list-expression null? number->string provide
    quasisyntax quote racket/base raw-cons raw-false raw-name-char
    raw-name-string raw-true rendered-name require string->bytes/utf-8
    string->list stx symbol->string syntax syntax->list syntax-case syntax-e
    unsyntax use-site-identifier value))

(define expected-macro-shell-language 'racket/base)

(define expected-macro-shell-forms
  '((require lazy/lazy)
    (provide (all-from-out lazy/lazy)
             #%module-begin
             #%app
             #%datum
             #%top)))

(define expected-macro-language 'lazy)

(define expected-macro-requires
  '((require (for-syntax racket/base))))

(define expected-macro-provide
  '(provide def
            lambda-let
            define-function-name))

(define expected-codec-provide
  '(provide (struct-out codec-failure)
            object-list->host-list
            host-list->object-list
            object-string->bytes
            bytes->object-string
            object-byte-list->bytes
            bytes->object-byte-list
            exact->object-rat
            object-rat->exact
            object-unit
            object-none
            object-some
            object-ok
            object-err))

(define expected-host-provide '(provide host))

(define string-imported-bindings
  '(EMPTY-STRING MAKE-STRING STRING-EMPTY? STRING-LENGTH STRING-EQ
    STRING-APPEND STRING-HEAD STRING-TAIL STRING-PREFIX? STRING-CONTAINS?))

(define language-direct-public-bindings
  '(TRUE FALSE NIL UNIT NONE
     error-to-string bool-to-string list-to-string result-to-string char-to-string string-to-string rat-to-string unit-to-string byte-to-string option-to-string map-to-string value-to-string
     make-ok make-err is-ok is-err unwrap-ok unwrap-err
     EMPTY-STRING stdout read-file write-file
     tcp-connect tcp-listen tcp-accept tcp-read tcp-write tcp-close
     parse-http-request
     HTTP-STATUS-OK
     HTTP-STATUS-BAD-REQUEST
     HTTP-STATUS-NOT-FOUND
     HTTP-STATUS-INTERNAL-SERVER-ERROR
     render-http-response
     make-http-path-handler
     make-http-serve-one
     make-http-server))

(define expected-language-expander-requires
  `((require
     (for-syntax racket/base)
     (only-in racket/base (void language-discard))
     (only-in "../macros/macros.rkt" def (lambda-let language-unary-let))
     (only-in "../core/fix.rkt" (raw-fix language-fix))
     (only-in "../core/byte.rkt"
              MAKE-BYTE BYTE-VALUE BYTE-EQ BYTE-LT BYTE-LTE BYTE-GT BYTE-GTE
              STRING-TO-BYTES BYTES-TO-STRING)
     (only-in "../core/chars.rkt"
              raw-make-char
              MAKE-CHAR CHAR-EQ CHAR-LT CHAR-LTE CHAR-GT CHAR-GTE)
     (only-in "../core/int.rkt"
              raw-make-int)
     (only-in "../core/list-nat.rkt"
              (typed-len-rat LEN)
              (typed-take-rat TAKE)
              (typed-drop-rat DROP)
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
              (typed-cons language-cons)
              (typed-head HEAD)
              (typed-tail TAIL)
              (typed-is-nil IS-NIL))
     (only-in "../core/logic.rkt" raw-false raw-true)
     (only-in "../core/objects.rkt" raw-make-object)
     (only-in "../core/map.rkt"
              MAKE-MAP MAP-EMPTY? MAP-SIZE MAP-LOOKUP
              MAP-CONTAINS? MAP-SET MAP-REMOVE)
     (only-in "../core/option.rkt" NONE SOME IS-SOME IS-NONE OPTION-CASE)
     (only-in "../core/pair.rkt" raw-pair)
     (only-in "../core/result.rkt"
              make-ok make-err is-ok is-err unwrap-ok unwrap-err)
     (only-in "../core/strings.rkt"
              raw-make-string
              ,@string-imported-bindings)
     (only-in "../core/to-string.rkt"
              error-to-string bool-to-string list-to-string result-to-string char-to-string string-to-string rat-to-string unit-to-string byte-to-string option-to-string map-to-string value-to-string)
     (only-in "../core/typed-logic.rkt"
              TRUE FALSE NOT AND OR XOR
              (typed-if language-if))
     (only-in "../core/tags.rkt" rat-type)
     (only-in "../core/unit.rkt" UNIT)
     (only-in "../core/typed-rat.rkt"
              (typed-rat-succ SUCC)
              (typed-rat-add ADD)
              (typed-rat-sub SUB)
              (typed-rat-mult MULT)
              (typed-rat-div DIV)
              (typed-rat-exp EXP)
              (typed-rat-recip RECIP)
              (typed-rat-negate NEG)
              (typed-rat-abs ABS)
              (typed-rat-floor FLOOR)
              (typed-rat-equal EQ)
              (typed-rat-less LT)
              (typed-rat-less-equal LTE)
              (typed-rat-greater GT)
              (typed-rat-greater-equal GTE)
              (typed-rat-is-zero IS-ZERO)
              (typed-rat-is-whole IS-WHOLE)
              (typed-rat-is-nonnegative-whole IS-NONNEGATIVE-WHOLE))
     (only-in "../effects/exit.rkt"
              (make-exit language-make-exit))
     (only-in "../effects/files.rkt"
              (make-read-file language-make-read-file)
              (make-write-file language-make-write-file))
     (only-in "../effects/http.rkt" parse-http-request)
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
     (only-in "../effects/print.rkt" (make-print language-make-print))
     (only-in "../effects/stdout.rkt"
              (make-stdout language-make-stdout))
     (only-in "../effects/stdin.rkt"
              (make-read-line language-make-read-line))
     (only-in "../effects/tcp.rkt"
              (make-tcp-connect language-make-tcp-connect)
              (make-tcp-listen language-make-tcp-listen)
              (make-tcp-accept language-make-tcp-accept)
              (make-tcp-read language-make-tcp-read)
              (make-tcp-write language-make-tcp-write)
              (make-tcp-close language-make-tcp-close))
     (only-in "../runtime/host.rkt" (host language-host)))))

(define expected-language-expander-provide
  `(provide
    #%top
    def
    (rename-out
     (language-module-begin #%module-begin)
     (language-application #%app)
     (language-datum #%datum)
     (language-lambda lambda)
     (language-rec rec)
     (language-let let)
     (language-list list)
     (language-cond cond)
     (language-if if)
     (language-cons cons)
     (language-host host)
     (language-exit exit)
     (language-print print)
     (language-read-line read-line)
     (HEAD head)
     (TAIL tail)
     (IS-NIL is-nil)
     (LEN len)
     (TAKE take)
     (DROP drop)
     (typed-nth-rat nth)
     (typed-take-while take-while)
     (typed-drop-while drop-while)
     (typed-append append)
     (typed-reverse reverse)
     (typed-zip zip)
     (typed-concat concat)
     (typed-flatten flatten)
     (typed-map map)
     (typed-filter filter)
     (typed-reduce reduce)
     (typed-any? any?)
     (typed-all? all?)
     (typed-find find)
     (typed-find-index find-index)
     (typed-contains? contains?)
     (typed-range-rat range)
     (typed-repeat-rat repeat)
     (NOT not)
     (AND and)
     (OR or)
     (XOR xor)
     (SUCC succ)
     (ADD add)
     (SUB sub)
     (MULT mult)
     (DIV div)
     (EQ eq)
     (LT lt)
     (LTE lte)
     (GT gt)
     (GTE gte)
     (IS-ZERO is-zero)
     (MAKE-CHAR make-char)
     (CHAR-EQ char-eq)
     (CHAR-LT char-lt)
     (CHAR-LTE char-lte)
     (CHAR-GT char-gt)
     (CHAR-GTE char-gte)
     (MAKE-STRING make-string)
     (STRING-EMPTY? string-empty?)
     (STRING-LENGTH string-length)
     (STRING-EQ string-eq)
     (STRING-APPEND string-append)
     (STRING-HEAD string-head)
     (STRING-TAIL string-tail)
     (STRING-PREFIX? string-prefix?)
     (STRING-CONTAINS? string-contains?)
     (EXP exp)
     (RECIP recip)
     (NEG neg)
     (ABS abs)
     (FLOOR floor)
     (IS-WHOLE is-whole)
     (IS-NONNEGATIVE-WHOLE is-nonnegative-whole)
     (MAKE-BYTE make-byte)
     (BYTE-VALUE byte-value)
     (BYTE-EQ byte-eq)
     (BYTE-LT byte-lt)
     (BYTE-LTE byte-lte)
     (BYTE-GT byte-gt)
     (BYTE-GTE byte-gte)
     (STRING-TO-BYTES string-to-bytes)
     (BYTES-TO-STRING bytes-to-string)
     (SOME some)
     (IS-SOME is-some)
     (IS-NONE is-none)
     (OPTION-CASE option-case)
     (MAKE-MAP make-map)
     (MAP-EMPTY? map-empty?)
     (MAP-SIZE map-size)
     (MAP-LOOKUP map-lookup)
     (MAP-CONTAINS? map-contains?)
     (MAP-SET map-set)
     (MAP-REMOVE map-remove))
    ,@language-direct-public-bindings))

(define expected-language-runtime-definitions
  '((def stdout = (language-make-stdout language-host))
    (def language-read-line = (language-make-read-line language-host))
    (def language-print = (language-make-print stdout))
    (def read-file = (language-make-read-file language-host))
    (def write-file = (language-make-write-file language-host))
    (def tcp-connect = (language-make-tcp-connect language-host))
    (def tcp-listen = (language-make-tcp-listen language-host))
    (def tcp-accept = (language-make-tcp-accept language-host))
    (def tcp-read = (language-make-tcp-read language-host))
    (def tcp-write = (language-make-tcp-write language-host))
    (def tcp-close = (language-make-tcp-close language-host))
    (def language-exit = (language-make-exit language-host))))

(define expected-language-transformers
  '(language-module-begin
    language-rec
    language-application
    language-lambda
    language-let
    language-list
    language-cond
    language-datum))

(define expected-language-for-syntax-definitions
  '(language-definition-form?
    language-curried-lambdas
    language-bound-name
    language-definition-parts
    language-dependencies
    language-check-definitions
    language-sugar-expression
    language-list-expression
    language-bit-expressions
    language-magnitude-expression
    language-rat-expression
    language-char-expression
    language-string-expression))

(define language-expander-vocabulary
  (remove-duplicates
   (append
    language-direct-public-bindings
    '(HEAD TAIL IS-NIL LEN TAKE DROP
      NOT AND OR XOR SUCC ADD
      SUB MULT DIV EQ LT LTE
      GT GTE IS-ZERO MAKE-CHAR CHAR-EQ CHAR-LT
      CHAR-LTE CHAR-GT CHAR-GTE MAKE-STRING STRING-EMPTY? STRING-LENGTH
      STRING-EQ STRING-APPEND STRING-HEAD STRING-TAIL STRING-PREFIX? STRING-CONTAINS?
      EXP RECIP NEG ABS FLOOR IS-WHOLE
      IS-NONNEGATIVE-WHOLE MAKE-BYTE BYTE-VALUE BYTE-EQ BYTE-LT BYTE-LTE
      BYTE-GT BYTE-GTE STRING-TO-BYTES BYTES-TO-STRING SOME IS-SOME
      IS-NONE OPTION-CASE MAKE-MAP MAP-EMPTY? MAP-SIZE MAP-LOOKUP
      MAP-CONTAINS? MAP-SET MAP-REMOVE
      head tail is-nil len take drop nth typed-nth-rat
      take-while drop-while typed-take-while typed-drop-while
      append reverse map filter typed-append typed-reverse typed-map typed-filter
      reduce typed-reduce
      range repeat typed-range-rat typed-repeat-rat
      zip concat flatten typed-zip typed-concat typed-flatten
      any? all? find find-index contains?
      typed-any? typed-all? typed-find typed-find-index typed-contains?
      not and or xor succ add
      sub mult div eq lt lte
      gt gte is-zero make-char char-eq char-lt
      char-lte char-gt char-gte make-string string-empty? string-length
      string-eq string-append string-head string-tail string-prefix? string-contains?
      exp recip neg abs floor is-whole
      is-nonnegative-whole make-byte byte-value byte-eq byte-lt byte-lte
      byte-gt byte-gte string-to-bytes bytes-to-string some is-some
      is-none option-case make-map map-empty? map-size map-lookup
      map-contains? map-set map-remove
      #%app #%datum #%module-begin #%top ... = _ and argument body byte
      language-rec rec raw-fix language-fix
      language-curried-lambdas language-bound-name language-definition-parts
      language-dependencies language-check-definitions imported retained
      interaction attalambda-interaction imports binding datum->syntax let*
      import-form export-form unsyntax-splicing results result result-names values
      language-sugar-expression language-unary-let language-list language-cond
      condition
      arguments name names candidate bound bound-identifier=? free-identifier=? ormap
      list quote andmap eq? equals expression part apply
      define definitions parts collect cadr caddr graph definition forms
      finished visit path when memq self? syntax-property attalambda-recursion
      self cycle foldl dependency assq
      bytes->list car cdr char=? char? char->integer <= cond datum def define-for-syntax
      define-syntax digit elements else exact? denominator numerator
      negative? rational? abs
      cons first for-syntax form function held host identifier? if lambda
      lambda-let language-application language-bit-expressions
      language-char-expression language-cons language-datum
      language-definition-form? language-discard language-host
      language-if language-lambda language-let language-list-expression
      language-exit language-make-exit make-exit exit
      language-make-read-file language-make-stdout
      language-read-line language-make-read-line make-read-line read-line
      language-print language-make-print make-print print
      language-make-tcp-accept language-make-tcp-close
      language-make-tcp-connect language-make-tcp-listen
      language-make-tcp-read language-make-tcp-write
      language-make-write-file language-module-begin
      language-magnitude-expression language-rat-expression
      language-string-expression let map null?
      number->string only-in prepared-form provide quasisyntax
      racket/base raise-syntax-error rat-type raw-cons raw-false
      raw-make-char raw-make-int raw-make-object raw-make-string raw-pair
      raw-true remaining rename-out require
      second string->bytes/utf-8 string->list string? stx syntax
      syntax->list syntax-case syntax-e typed-cons typed-drop-rat
      typed-head typed-if typed-is-nil typed-len-rat typed-rat-abs
      typed-rat-add typed-rat-div typed-rat-equal typed-rat-exp
      typed-rat-floor typed-rat-greater typed-rat-greater-equal
      typed-rat-is-nonnegative-whole typed-rat-is-whole typed-rat-is-zero
      typed-rat-less typed-rat-less-equal typed-rat-mult typed-rat-negate
      typed-rat-recip typed-rat-sub typed-rat-succ typed-tail
      typed-take-rat unsyntax
      value void with-syntax
      make-read-file make-stdout make-tcp-accept make-tcp-close
      make-tcp-connect make-tcp-listen make-tcp-read make-tcp-write
      make-write-file))))

(define expected-language-reader-forms
  '(attalambda/lang/expander))

(define product-version-projections
  '((#"0.2.0-dev\n" . "0.1.900")
    (#"0.2.0-rc.1\n" . "0.1.901")
    (#"0.2.0\n" . "0.2")
    (#"0.3.0-dev\n" . "0.2.900")
    (#"0.3.0\n" . "0.3")
    (#"0.4.0\n" . "0.4")
    (#"0.5.0\n" . "0.5")
    (#"0.6.0\n" . "0.6")
    (#"0.7.0\n" . "0.7")
    (#"0.8.0\n" . "0.8")))

(define runner-forbidden-version-literals
  (append-map
   (lambda (entry)
     (define with-newline (car entry))
     (define without-newline
       (subbytes with-newline
                 0
                 (sub1 (bytes-length with-newline))))
     (list with-newline
           without-newline
           (bytes->string/utf-8 without-newline)))
   product-version-projections))

(define (expected-package-info-forms package-version)
  `((define collection "attalambda")
    (define deps (quote ("base" "lazy" "expeditor-lib" "syntax-color-lib")))
    (define build-deps (quote ("rackunit-lib" "net-lib")))
    (define license (quote Apache-2.0))
    (define pkg-desc
      "A pure unary-lambda language with one explicit host boundary")
    (define version ,package-version)))

(define (normalized path)
  (simplify-path (path->complete-path path) #f))

(define (dotenv-name? path)
  (define name (file-name-from-path path))
  (and name
       (regexp-match?
        #px"(^|\\.)env($|\\.)"
        (string-downcase (path->string name)))))

(define (dotenv-path? path)
  (for/or ([part (in-list (explode-path (normalized path)))])
    (and (path? part)
         (dotenv-name? part))))

(define (path-within? parent child)
  (define parent-parts (explode-path (normalized parent)))
  (define child-parts (explode-path (normalized child)))
  (and (<= (length parent-parts) (length child-parts))
       (equal? parent-parts
               (take child-parts (length parent-parts)))))

(define (safe-absolute-components? path)
  (let loop ([parts (explode-path (normalized path))]
             [current #f])
    (cond
      [(null? parts) #t]
      [(not (path? (car parts))) #f]
      [else
       (define next
         (if current
             (build-path current (car parts))
             (car parts)))
       (and (not (dotenv-name? next))
            (not (link-exists? next))
            (loop (cdr parts) next))])))

(define (safe-components-under? project-root path)
  (define root (normalized project-root))
  (define source (normalized path))
  (and
   (safe-absolute-components? root)
   (path-within? root source)
   (let loop ([current root]
              [parts
               (explode-path (find-relative-path root source))])
     (cond
       [(null? parts) #t]
       [(not (path? (car parts))) #f]
       [else
        (define next (build-path current (car parts)))
        (and (not (dotenv-name? next))
             (not (link-exists? next))
             (loop next (cdr parts)))]))))

(define (safe-source-path? path [project-root #f])
  (and (not (dotenv-path? path))
       (if project-root
           (safe-components-under? project-root path)
           (safe-absolute-components? path))))

(define (resolve-relative source-path module-path)
  (normalized
   (build-path (or (path-only source-path) (current-directory))
               module-path)))

(define (read-module-info/unchecked path [project-root #f])
  (define collection-parent
    (and project-root
         (normalized
          (build-path (normalized project-root) 'up))))
  (define project-collection-link
    (and project-root
         (hash 'attalambda
               (list (normalized project-root)))))
  (define datum
    (call-with-input-file path
      (lambda (input)
        (parameterize ([read-accept-reader #t]
                       [current-load-relative-directory (path-only path)]
                       [current-library-collection-links
                        (if project-collection-link
                            (cons project-collection-link
                                  (current-library-collection-links))
                            (current-library-collection-links))]
                       [current-library-collection-paths
                        (if collection-parent
                            (cons collection-parent
                                  (current-library-collection-paths))
                            (current-library-collection-paths))])
          (read input)))))
  (and (list? datum)
       (= (length datum) 4)
       (eq? (car datum) 'module)
       (let ([body (list-ref datum 3)])
         (and (list? body)
              (pair? body)
              (eq? (car body) '#%module-begin)
              (module-info (list-ref datum 2)
                           (cdr body))))))

(define (violation path kind detail)
  (boundary-violation path kind (format "~s" detail)))

(define (regular-file-path? path)
  (with-handlers ([exn:fail? (lambda (failure) #f)])
    (= (bitwise-and
        (hash-ref (file-or-directory-stat path) 'mode)
        file-type-bits)
       regular-file-type-bits)))

(define (version-path project-root)
  (normalized (build-path project-root "VERSION")))

(define (version-projection project-root)
  (define path (version-path project-root))
  (and (safe-source-path? path project-root)
       (regular-file-path? path)
       (with-handlers ([exn:fail? (lambda (failure) #f)])
         (define entry
           (assoc (file->bytes path)
                  product-version-projections
                  bytes=?))
         (and entry (cdr entry)))))

(define (version-file-violations project-root)
  (define path (version-path project-root))
  (cond
    [(not (safe-source-path? path project-root))
     (list (violation path 'disallowed-version-path path))]
    [(not (file-exists? path))
     (list (violation path 'missing-version-file path))]
    [(not (regular-file-path? path))
     (list (violation path 'invalid-version-file-type path))]
    [else
     (with-handlers
         ([exn:fail?
           (lambda (failure)
             (list (violation path
                              'version-read-failure
                              (exn-message failure))))])
       (define content (file->bytes path))
       (if (assoc content product-version-projections bytes=?)
           '()
           (list (violation path
                            'invalid-product-version
                            content))))]))

(define (require-form? form)
  (and (pair? form) (eq? (car form) 'require)))

(define (provide-form? form)
  (and (pair? form) (eq? (car form) 'provide)))

(define (combined-require-bases specs)
  (define groups
    (map require-spec-bases specs))
  (and (andmap list? groups)
       (append* groups)))

(define (require-spec-bases spec)
  (cond
    [(or (string? spec) (symbol? spec)) (list spec)]
    [(and (list? spec)
          (pair? spec)
          (memq (car spec) '(only-in except-in rename-in))
          (>= (length spec) 2))
     (require-spec-bases (cadr spec))]
    [(and (list? spec)
          (pair? spec)
          (eq? (car spec) 'prefix-in)
          (>= (length spec) 3))
     (require-spec-bases (caddr spec))]
    [(and (list? spec)
          (pair? spec)
          (memq (car spec) '(combine-in for-syntax for-template for-label)))
     (combined-require-bases (cdr spec))]
    [(and (list? spec)
          (pair? spec)
          (memq (car spec) '(for-meta only-meta-in for-space))
          (>= (length spec) 3))
     (combined-require-bases (cddr spec))]
    [else #f]))

(define (require-spec-base spec)
  (define bases
    (require-spec-bases spec))
  (and bases
       (= (length bases) 1)
       (car bases)))

(define (only-in-spec? spec)
  (and (list? spec)
       (pair? spec)
       (eq? (car spec) 'only-in)))

(define (module-require-specs info)
  (append-map cdr
              (filter require-form?
                      (module-info-forms info))))

(define (provided-identifiers info)
  (append-map
   (lambda (form)
     (append-map
      (lambda (spec)
        (cond
          [(symbol? spec) (list spec)]
          [(and (list? spec)
                (pair? spec)
                (eq? (car spec) 'rename-out))
           (filter-map
            (lambda (rename)
              (and (list? rename)
                   (= (length rename) 2)
                   (symbol? (cadr rename))
                   (cadr rename)))
            (cdr spec))]
          [else '()]))
      (cdr form)))
   (filter provide-form? (module-info-forms info))))

(define (only-in-identifiers spec)
  (filter-map
   (lambda (selection)
     (cond
       [(symbol? selection) selection]
       [(and (list? selection)
             (= (length selection) 2)
             (symbol? (cadr selection)))
        (cadr selection)]
       [else #f]))
   (cddr spec)))

(define (imported-identifiers spec source-path project-root)
  (define base (require-spec-base spec))
  (cond
    [(only-in-spec? spec)
     (only-in-identifiers spec)]
    [(string? base)
     (define target (resolve-relative source-path base))
     (define info (read-module-info target project-root))
     (if info (provided-identifiers info) '())]
    [else '()]))

(define (effect-top-level-identifiers info)
  (filter-map
   (lambda (form)
     (cond
       [(and (list? form)
             (>= (length form) 4)
             (eq? (car form) 'def)
             (symbol? (cadr form)))
        (cadr form)]
       [(and (list? form)
             (= (length form) 3)
             (eq? (car form) 'define-function-name)
             (symbol? (cadr form)))
        (cadr form)]
       [else #f]))
   (module-info-forms info)))

(define (effect-allowed-identifiers info source-path project-root)
  (remove-duplicates
   (append
    (effect-top-level-identifiers info)
    (append-map (lambda (spec)
                  (if (effect-import-allowed? spec
                                              source-path
                                              project-root)
                      (imported-identifiers spec
                                            source-path
                                            project-root)
                      '()))
                (module-require-specs info)))))

(define (source-file? path project-root)
  (and (safe-source-path? path project-root)
       (regular-file-path? path)
       (member (path-get-extension path)
               '(#".rkt" #".attl")
               equal?)))

;; All opportunistic project-wide reads go through this guard. The one caller
;; that has already rejected unsafe/missing paths uses the unchecked reader so
;; it can preserve a concrete read-failure diagnostic for a regular source.
(define (read-module-info path project-root)
  (with-handlers ([exn:fail? (lambda (failure) #f)])
    (and (source-file? path project-root)
         (read-module-info/unchecked path project-root))))

(define (effect-import-allowed? spec source-path project-root)
  (define base (require-spec-base spec))
  (and (string? base)
       (let ([target (resolve-relative source-path base)])
         (or (and (equal? base effect-macro-import)
                  (equal? target
                          (normalized
                           (build-path project-root "macros" "macros.rkt")))
                  (source-file? target project-root))
             (and (or (path-within? (build-path project-root "core") target)
                      (path-within? (build-path project-root "effects")
                                    target))
                  (source-file? target project-root))))))

(define (reader-import-allowed? spec source-path project-root)
  (define base (require-spec-base spec))
  (cond
    [(symbol? base)
     (and (eq? spec base)
          (memq base reader-host-imports))]
    [(string? base)
     (define target (resolve-relative source-path base))
     (and (or (path-within? (build-path project-root "core") target)
              (path-within? (build-path project-root "readers") target))
          (source-file? target project-root))]
    [else #f]))

(define (codec-import-allowed? spec source-path project-root)
  (define base (require-spec-base spec))
  (cond
    [(eq? base 'racket/promise) (eq? spec 'racket/promise)]
    [(string? base)
     (define target (resolve-relative source-path base))
     (and (only-in-spec? spec)
          (path-within? (build-path project-root "core") target)
          (source-file? target project-root))]
    [else #f]))

(define (host-import-allowed? spec source-path project-root)
  (define base (require-spec-base spec))
  (cond
    [(eq? base 'racket/promise) (eq? spec 'racket/promise)]
    [(eq? base 'racket/file)
     (and (only-in-spec? spec)
          (equal? (only-in-identifiers spec) '(file->bytes)))]
    [(eq? base 'racket/tcp)
     (and (only-in-spec? spec)
          (equal? (only-in-identifiers spec)
                  '(tcp-accept
                    tcp-addresses
                    tcp-close
                    tcp-connect
                    tcp-listen)))]
    [(string? base)
     (define target (resolve-relative source-path base))
     (define allowed
       (map (lambda (parts)
              (normalized (apply build-path project-root parts)))
            '(("core" "errors.rkt")
              ("core" "strings.rkt")
              ("effects" "protocol.rkt")
              ("runtime" "codec.rkt"))))
     (and (only-in-spec? spec)
          (member target allowed equal?)
          (source-file? target project-root))]
    [else #f]))

(define (datum-symbols datum)
  (cond
    [(symbol? datum) (list datum)]
    [(pair? datum)
     (append (datum-symbols (car datum))
             (datum-symbols (cdr datum)))]
    [(vector? datum)
     (append-map datum-symbols (vector->list datum))]
    [(box? datum) (datum-symbols (unbox datum))]
    [(hash? datum)
     (append-map (lambda (entry)
                   (append (datum-symbols (car entry))
                           (datum-symbols (cdr entry))))
                 (hash->list datum))]
    [(prefab-struct-key datum)
     (datum-symbols (struct->vector datum))]
    [else '()]))

(define (module-symbols info)
  (datum-symbols (module-info-forms info)))

(define (datum-occurrence-count target datum)
  (cond
    [(equal? target datum) 1]
    [(pair? datum)
     (+ (datum-occurrence-count target (car datum))
        (datum-occurrence-count target (cdr datum)))]
    [(vector? datum)
     (for/sum ([element (in-vector datum)])
       (datum-occurrence-count target element))]
    [(box? datum) (datum-occurrence-count target (unbox datum))]
    [(hash? datum)
     (for/sum ([(key value) (in-hash datum)])
       (+ (datum-occurrence-count target key)
          (datum-occurrence-count target value)))]
    [(prefab-struct-key datum)
     (datum-occurrence-count target (struct->vector datum))]
    [else 0]))

(define (call-first-arguments name datum)
  (cond
    [(pair? datum)
     (append
      (if (and (eq? (car datum) name)
               (pair? (cdr datum)))
          (list (cadr datum))
          '())
      (call-first-arguments name (car datum))
      (call-first-arguments name (cdr datum)))]
    [(vector? datum)
     (append-map (lambda (element)
                   (call-first-arguments name element))
                 (vector->list datum))]
    [else '()]))

(define (symbol-violations path symbols forbidden kind)
  (for/list ([name (in-list (remove-duplicates symbols))]
             #:when (memq name forbidden))
    (violation path kind name)))

(define (capability-pattern-violations path symbols kind)
  (for/list ([name (in-list (remove-duplicates symbols))]
             #:when
             (let ([text (symbol->string name)])
               (or (regexp-match? #px"^set-.+!$" text)
                   (regexp-match? #px"registry" text))))
    (violation path kind name)))

(define (strict-vocabulary-violations path project-root allowed kind)
  (define info (read-module-info path project-root))
  (if info
      (for/list ([name (in-list
                        (remove-duplicates
                         (module-symbols info)))]
                 #:unless (memq name allowed))
        (violation path kind name))
      '()))

(define (pure-expression-violations expression bound allowed path)
  (cond
    [(symbol? expression)
     (if (or (memq expression bound)
             (memq expression allowed))
         '()
         (list (violation path 'unapproved-effect-identifier expression)))]
    [(not (pair? expression))
     (list (violation path 'forbidden-effect-datum expression))]
    [(eq? (car expression) 'lambda)
     (if (and (= (length expression) 3)
              (list? (cadr expression))
              (= (length (cadr expression)) 1)
              (symbol? (caadr expression)))
         (pure-expression-violations
          (caddr expression)
          (cons (caadr expression) bound)
          allowed
          path)
         (list (violation path 'non-unary-effect-lambda expression)))]
    [(eq? (car expression) 'lambda-let)
     (if (and (= (length expression) 5)
              (symbol? (cadr expression))
              (eq? (caddr expression) '=))
         (append
          (pure-expression-violations (cadddr expression)
                                      bound
                                      allowed
                                      path)
          (pure-expression-violations
           (list-ref expression 4)
           (cons (cadr expression) bound)
           allowed
           path))
         (list (violation path 'invalid-effect-macro-form expression)))]
    [(= (length expression) 2)
     (append (pure-expression-violations (car expression)
                                         bound
                                         allowed
                                         path)
             (pure-expression-violations (cadr expression)
                                         bound
                                         allowed
                                         path))]
    [else
     (list (violation path 'non-unary-effect-application expression))]))

(define (effect-definition-violations form allowed path)
  (define equals
    (indexes-of form '=))
  (cond
    [(or (not (eq? (car form) 'def))
         (not (= (length equals) 1))
         (< (car equals) 2)
         (not (= (car equals) (- (length form) 2)))
         (not (symbol? (cadr form)))
         (not (andmap symbol? (take (cddr form) (- (car equals) 2)))))
     (list (violation path 'invalid-effect-definition form))]
    [(eq? (cadr form) 'host)
     (list (violation path 'forbidden-host-definition 'host))]
    [else
     (define arguments
       (take (cddr form) (- (car equals) 2)))
     (pure-expression-violations (last form)
                                 arguments
                                 allowed
                                 path)]))

(define (effect-provide-violations form definitions path)
  (append-map
   (lambda (spec)
     (cond
       [(eq? spec 'host)
        (list (violation path 'forbidden-host-export spec))]
       [(and (symbol? spec) (memq spec definitions))
        '()]
       [else
        (list (violation path 'unapproved-effect-export spec))]))
   (cdr form)))

(define (effect-form-violations form definitions allowed path project-root)
  (cond
    [(require-form? form)
     (for/list ([spec (in-list (cdr form))]
                #:unless (effect-import-allowed? spec path project-root))
       (violation path 'disallowed-effect-import spec))]
    [(provide-form? form)
     (effect-provide-violations form definitions path)]
    [(and (pair? form) (eq? (car form) 'def))
     (effect-definition-violations form allowed path)]
    [(and (list? form)
          (= (length form) 3)
          (eq? (car form) 'define-function-name)
          (symbol? (cadr form))
          (symbol? (caddr form)))
     (if (eq? (cadr form) 'host)
         (list (violation path 'forbidden-host-definition form))
         '())]
    [else
     (list (violation path 'disallowed-effect-module-form form))]))

(define (effect-violations path info project-root)
  (define definitions
    (effect-top-level-identifiers info))
  (define allowed
    (effect-allowed-identifiers info path project-root))
  (append
   (if (equal? (module-info-language info) effect-language)
       '()
       (list (violation path 'unexpected-effect-language
                        (module-info-language info))))
   (append-map (lambda (form)
                 (effect-form-violations form
                                         definitions
                                         allowed
                                         path
                                         project-root))
               (module-info-forms info))))

(define (strict-import-violations path info project-root allowed? kind)
  (for/list ([spec (in-list (module-require-specs info))]
             #:unless (allowed? spec path project-root))
    (violation path kind spec)))

(define (exact-language-violations path info expected kind)
  (if (eq? (module-info-language info) expected)
      '()
      (list (violation path kind (module-info-language info)))))

(define (exact-require-violations path info expected kind)
  (define requires
    (filter require-form? (module-info-forms info)))
  (if (equal? requires expected)
      '()
      (list (violation path kind requires))))

(define (exact-provide-violations path info expected kind)
  (define provides
    (filter provide-form? (module-info-forms info)))
  (if (equal? provides (list expected))
      '()
      (list (violation path kind provides))))

(define (macro-shell-violations path info)
  (append
   (exact-language-violations path
                              info
                              expected-macro-shell-language
                              'unexpected-macro-shell-language)
   (if (equal? (module-info-forms info) expected-macro-shell-forms)
       '()
       (list (violation path
                        'invalid-macro-shell-forms
                        (module-info-forms info))))))

(define (macro-violations path info)
  (define symbols
    (module-symbols info))
  (append
   (exact-language-violations path
                              info
                              expected-macro-language
                              'unexpected-macro-language)
   (exact-require-violations path
                             info
                             expected-macro-requires
                             'invalid-macro-imports)
   (exact-provide-violations path
                             info
                             expected-macro-provide
                             'invalid-macro-export)
   (symbol-violations path
                      symbols
                      forbidden-codec-capabilities
                      'forbidden-macro-capability)
   (capability-pattern-violations path
                                  symbols
                                  'forbidden-macro-capability)))

(define (definition-form-name form keyword)
  (and (list? form)
       (>= (length form) 3)
       (eq? (car form) keyword)
       (let ([binding (cadr form)])
         (and (pair? binding)
              (symbol? (car binding))
              (car binding)))))

(define (language-expander-form-violations path info)
  (append-map
   (lambda (form)
     (cond
       [(or (require-form? form)
            (provide-form? form))
        '()]
       [(eq? (and (pair? form) (car form)) 'define-syntax)
        (if (memq (definition-form-name form 'define-syntax)
                  expected-language-transformers)
            '()
            (list (violation path
                             'unapproved-language-transformer
                             form)))]
       [(eq? (and (pair? form) (car form)) 'define-for-syntax)
        (if (memq (definition-form-name form 'define-for-syntax)
                  expected-language-for-syntax-definitions)
            '()
            (list (violation path
                             'unapproved-language-syntax-helper
                             form)))]
       [(eq? (and (pair? form) (car form)) 'def)
        (if (member form expected-language-runtime-definitions equal?)
            '()
            (list (violation path
                             'unapproved-language-runtime-definition
                             form)))]
       [else
        (list (violation path 'disallowed-language-module-form form))]))
   (module-info-forms info)))

(define (language-expander-violations path info project-root)
  (define transformer-names
    (filter-map
     (lambda (form)
       (definition-form-name form 'define-syntax))
     (module-info-forms info)))
  (define syntax-helper-names
    (filter-map
     (lambda (form)
       (definition-form-name form 'define-for-syntax))
     (module-info-forms info)))
  (define runtime-definitions
    (filter (lambda (form)
              (and (pair? form)
                   (eq? (car form) 'def)))
            (module-info-forms info)))
  (define symbols
    (module-symbols info))
  (append
   (exact-language-violations path
                              info
                              'lazy
                              'unexpected-language-expander-language)
   (exact-require-violations path
                             info
                             expected-language-expander-requires
                             'invalid-language-expander-imports)
   (exact-provide-violations path
                             info
                             expected-language-expander-provide
                             'invalid-language-expander-export)
   (if (equal? transformer-names expected-language-transformers)
       '()
       (list (violation path
                        'invalid-language-transformer-set
                        transformer-names)))
   (if (equal? syntax-helper-names
               expected-language-for-syntax-definitions)
       '()
       (list (violation path
                        'invalid-language-syntax-helper-set
                        syntax-helper-names)))
   (if (equal? runtime-definitions
               expected-language-runtime-definitions)
       '()
       (list (violation path
                        'invalid-language-runtime-definitions
                        runtime-definitions)))
   (language-expander-form-violations path info)
   ;; The exact provide form accounts for the sole public spelling `exit`.
   ;; Any additional occurrence can name native Racket exit in a syntax
   ;; helper or transformer, outside the approved host boundary.
   (if (= (datum-occurrence-count 'exit (module-info-forms info)) 1)
       '()
       (list (violation path 'forbidden-language-capability 'exit)))
   ;; `print` is allowed solely as the exported spelling of language-print.
   ;; Any extra use could select Racket's native printer and is forbidden.
   (if (= (datum-occurrence-count 'print (module-info-forms info)) 1)
       '()
       (list (violation path 'forbidden-language-capability 'print)))
   ;; Public read-line is only an export alias; native reads remain forbidden
   ;; in transformers and generated expressions as well as runtime helpers.
   (if (= (datum-occurrence-count 'read-line (module-info-forms info)) 1)
       '()
       (list (violation path 'forbidden-language-capability 'read-line)))
   (symbol-violations path
                      symbols
                      forbidden-language-capabilities
                      'forbidden-language-capability)
   (capability-pattern-violations path
                                  symbols
                                  'forbidden-language-capability)
   (strict-vocabulary-violations path
                                 project-root
                                 language-expander-vocabulary
                                 'unapproved-language-identifier)))

(define (language-reader-violations path info)
  (append
   (exact-language-violations path
                              info
                              'syntax/module-reader
                              'unexpected-language-reader-language)
   (if (equal? (module-info-forms info)
               expected-language-reader-forms)
       '()
       (list (violation path
                        'invalid-language-reader-forms
                        (module-info-forms info))))))

(define (reader-violations path info project-root)
  (define symbols
    (module-symbols info))
  (append
   ;; The Error observer must delegate all diagnostic policy to pure terms.
   ;; Pin this tiny conversion bridge so a second host formatter cannot return.
   (if (equal? (normalized path)
               (normalized (build-path project-root "readers" "error.rkt")))
       (if (equal? (module-info-forms info)
                   '((require racket/promise "../core/render-error.rkt" "string.rkt")
                     (provide error-value->string)
                     (define (error-value->string error)
                       (string-value->string
                        ((force raw-error-diagnostic-string) error)))))
           '()
           (list (violation path 'independent-error-formatting-policy
                            (module-info-forms info))))
       '())
   (exact-language-violations path
                              info
                              'racket/base
                              'unexpected-reader-language)
   (strict-import-violations path
                             info
                             project-root
                             reader-import-allowed?
                             'disallowed-reader-import)
   (symbol-violations path
                      symbols
                      forbidden-codec-capabilities
                      'forbidden-reader-capability)
   (capability-pattern-violations path
                                  symbols
                                  'forbidden-reader-capability)
   (strict-vocabulary-violations path
                                 project-root
                                 reader-vocabulary
                                 'unapproved-reader-identifier)))

(define (application-violations path info)
  (append
   (if (equal? (path-get-extension path) #".attl")
       '()
       (list (violation path
                        'invalid-application-extension
                        (path-get-extension path))))
   (exact-language-violations path
                              info
                              'attalambda/lang/expander
                              'unexpected-application-language)))

;; Tests and tooling deliberately have normal Racket authority. Their
;; structural rule is classification plus exclusion from every production
;; dependency path; successfully reading the module is enough here.
(define (host-support-violations path info class)
  '())

(define (package-info-violations path info project-root)
  (define package-version
    (version-projection project-root))
  (append
   (exact-language-violations path
                              info
                              'setup/infotab
                              'unexpected-package-info-language)
   (if (and package-version
            (equal? (module-info-forms info)
                    (expected-package-info-forms package-version)))
       '()
       (list (violation path
                        'invalid-package-info-forms
                        (module-info-forms info))))))

(define (codec-violations path info project-root)
  (define symbols
    (module-symbols info))
  (append
   (exact-language-violations path
                              info
                              'racket/base
                              'unexpected-codec-language)
   (strict-import-violations path info project-root
                             codec-import-allowed?
                             'disallowed-codec-import)
   (exact-provide-violations path info expected-codec-provide
                             'invalid-codec-export)
   (symbol-violations path
                      symbols
                      forbidden-codec-capabilities
                      'forbidden-codec-capability)
   (capability-pattern-violations path
                                  symbols
                                  'forbidden-codec-capability)))

(define (top-level-binding-name form)
  (and (list? form)
       (>= (length form) 3)
       (case (car form)
         [(define)
          (let ([binding (cadr form)])
            (if (pair? binding) (car binding) binding))]
         [(def) (cadr form)]
         [(define-values)
          (and (list? (cadr form))
               (= (length (cadr form)) 1)
               (caadr form))]
         [(define-runtime-path define-runtime-module-path-index)
          (and (symbol? (cadr form))
               (cadr form))]
         [(define-syntax)
          (let ([binding (cadr form)])
            (if (pair? binding) (car binding) binding))]
         [else #f])))

(define (runner-violations path info project-root)
  (define symbols
    (module-symbols info))
  (define definitions
    (filter-map top-level-binding-name
                (module-info-forms info)))
  (define status-definitions
    (filter (lambda (form)
              (memq (top-level-binding-name form)
                    '(command-misuse-status
                      invalid-source-status
                      unavailable-source-status
                      unexpected-failure-status)))
            (module-info-forms info)))
  (append
   (exact-language-violations path
                              info
                              'racket/base
                              'unexpected-runner-language)
   (exact-require-violations path
                             info
                             expected-runner-requires
                             'invalid-runner-imports)
   (if (null? (filter provide-form? (module-info-forms info)))
       '()
       (list (violation path
                        'invalid-runner-export
                        (filter provide-form?
                                (module-info-forms info)))))
   (if (equal? definitions expected-runner-definitions)
       '()
       (list (violation path
                        'invalid-runner-definition-set
                        definitions)))
   (if (equal? status-definitions expected-runner-status-definitions)
       '()
       (list (violation path
                        'invalid-runner-status-definitions
                        status-definitions)))
   (if (equal? (call-first-arguments 'call-with-input-file (module-info-forms info))
               expected-runner-input-targets)
       '()
       (list (violation path
                        'invalid-runner-input-targets
                        (call-first-arguments
                         'call-with-input-file
                         (module-info-forms info)))))
   (for/list ([literal (in-list runner-forbidden-version-literals)]
              #:when (positive?
                      (datum-occurrence-count
                       literal
                       (module-info-forms info))))
     (violation path
                'duplicated-runner-version-literal
                literal))
   (if (and (pair? (module-info-forms info))
            (equal? (last (module-info-forms info)) '(main))
            (= (count (lambda (name)
                        (eq? name 'dynamic-require))
                      symbols)
               2)
            (= (datum-occurrence-count
                '(dynamic-require source-path #f)
                (module-info-forms info))
               1)
            (= (datum-occurrence-count '(dynamic-require repl-index 'run-repl)
                                        (module-info-forms info)) 1)
            (= (datum-occurrence-count '(define-runtime-module-path-index repl-index "repl.rkt")
                                        (module-info-forms info)) 1)
            (= (count (lambda (name) (eq? name 'current-input-port)) symbols) 1)
            (= (datum-occurrence-count '(terminal-port? (current-input-port))
                                        (module-info-forms info)) 1)
            (= (count (lambda (name)
                        (eq? name 'call-with-input-file))
                      symbols)
               1))
       '()
       (list (violation path
                        'invalid-runner-entry-or-loader
                        'main/dynamic-require)))
   (symbol-violations path
                      symbols
                      forbidden-runner-capabilities
                      'forbidden-runner-capability)
   (capability-pattern-violations path
                                  symbols
                                  'forbidden-runner-capability)
   (strict-vocabulary-violations path
                                 project-root
                                 runner-vocabulary
                                 'unapproved-runner-identifier)))

;; File inspection is a separate closed class; it cannot execute source or
;; perform program I/O. Its sole content read remains behind the path preflight.
(define expected-source-file-preflight
  '(define (source-preflight-result source)
  (call-with-input-file source
    (lambda (input)
      (port-count-lines! input)
      (define declaration
        (read-bytes (bytes-length language-declaration) input))
      (define terminator (read-byte input))
      (if (and (equal? declaration language-declaration)
               (or (eof-object? terminator)
                   (= terminator 10)
                   (and (= terminator 13)
                        (equal? (read-byte input) 10))))
          (with-handlers ([exn:fail:contract? (lambda (_) 'invalid-encoding)])
            (define-values (line column position) (port-next-location input))
            (define text (bytes->string/utf-8 (port->bytes input) #f))
            (validated-source source text line column position))
          'invalid-declaration))
    #:mode 'binary)))

(define expected-source-file-inspection
  '(define (inspect-source-file source-name)
  (with-handlers ([source-problem? values]
                  [exn:fail? (lambda (_)
                               (source-problem 'unavailable
                                               "source path could not be inspected" #f #f))])
    (define (reject kind reason) (raise (source-problem kind reason #f #f)))
    (define supplied-path (string->path source-name))
    (when (dotenv-path? supplied-path)
      (reject 'unavailable "refused source path because dotenv files are never read"))
    (unless (equal? (path-get-extension supplied-path) #".attl")
      (reject 'invalid "source file name must end in lowercase .attl"))
    (define complete-path (path->complete-path supplied-path))
    (when (link-exists? complete-path)
      (reject 'unavailable "refused symbolic-link source; choose a regular .attl file"))
    (define-values (parent name directory?) (split-path complete-path))
    (define resolved-parent (resolve-parent-path parent))
    (unless resolved-parent
      (reject 'unavailable "source path could not be inspected"))
    (when (dotenv-path? resolved-parent)
      (reject 'unavailable "refused source path because dotenv files are never read"))
    (define resolved-source (build-path resolved-parent name))
    (unless (or (file-exists? resolved-source) (directory-exists? resolved-source))
      (reject 'unavailable "source file was not found"))
    (unless (regular-file? resolved-source)
      (reject 'unavailable "source path is not a regular file"))
    (define preflight-result
      (with-handlers ([exn:fail? (lambda (_)
                                  (reject 'unavailable "source file could not be read"))])
        (source-preflight-result resolved-source)))
    (cond
      [(eq? preflight-result 'invalid-declaration)
       (reject 'invalid "line 1 must be exactly #lang attalambda")]
      [(eq? preflight-result 'invalid-encoding)
       (reject 'invalid "source is not valid UTF-8")])
    (struct-copy validated-source preflight-result [path supplied-path]))))

(define source-file-vocabulary
  '(#%datum #%module-begin = _ and append attalambda-recursion binary bitwise-and
    build-path bytes->string/utf-8 bytes-length call-with-input-file car cdr column
    complete-path cond cons cycle datum-failure-expression? declaration define
    define-values directory-exists? directory? dotenv-component? dotenv-path? else
    eof-object? eq? equal? exn:fail:contract? exn:fail:syntax-exprs exn:fail? explode-path
    expression expressions failure file-exists? file-or-directory-stat file-type-bits
    for/or format hash-ref identifier? if in-list input inspect-source-file invalid
    invalid-declaration invalid-encoding kind lambda language-declaration let line
    link-exists? loop member mode name next not null? only-in or pair? parent part path
    path->complete-path path->string path-get-extension path-only path? port->bytes
    port-count-lines! port-next-location position preflight-result provide quote
    racket/file racket/path racket/port raise read-byte read-bytes reason regexp-match?
    regular-file-type-bits regular-file? reject remaining require resolve-parent-path
    resolve-path resolved resolved-parent resolved-source seen self simplify-path source
    source-name source-preflight-result source-problem source-problem? split-path
    string->path string-downcase struct struct-copy struct-out supplied-path syntax-e
    syntax-failure-expression syntax-failure-reason syntax-property syntax? terminator
    text unavailable unless validated-source value values when with-handlers))

(define (source-file-violations path info project-root)
  (define forms (module-info-forms info))
  (define symbols (module-symbols info))
  (append
   (exact-language-violations path info 'racket/base 'unexpected-source-file-language)
   (exact-require-violations
    path info '((require (only-in racket/file file-type-bits regular-file-type-bits)
                         (only-in racket/path path-get-extension path-only)
                         (only-in racket/port port->bytes)))
    'invalid-source-file-imports)
   (exact-provide-violations
    path info '(provide (struct-out validated-source) (struct-out source-problem)
                         inspect-source-file syntax-failure-expression syntax-failure-reason)
    'invalid-source-file-exports)
   (if (and (equal? (filter-map top-level-binding-name forms)
                    '(language-declaration dotenv-component? dotenv-path? resolve-parent-path
                      source-preflight-result regular-file? inspect-source-file
                      syntax-failure-expression datum-failure-expression? syntax-failure-reason))
            (equal? (filter (lambda (form) (and (pair? form) (eq? (car form) 'struct))) forms)
                    '((struct validated-source (path text line column position) #:transparent)
                      (struct source-problem (kind reason line column) #:transparent))))
       '() (list (violation path 'invalid-source-file-scaffolding 'module)))
   (if (and (equal? (call-first-arguments 'call-with-input-file forms) '(source))
            (= (datum-occurrence-count '(source-preflight-result resolved-source) forms) 1)
            (= (datum-occurrence-count '(bytes->string/utf-8 (port->bytes input) #f) forms) 1)
            (= (datum-occurrence-count expected-source-file-preflight forms) 1)
            (= (datum-occurrence-count expected-source-file-inspection forms) 1))
       '() (list (violation path 'invalid-source-file-input-targets 'preflight)))
   (for/list ([operation '(call-with-input-file read-byte read-bytes port->bytes source-preflight-result)]
              ;; port->bytes occurs once in the exact import and once in its call.
              [expected '(1 2 1 2 2)]
              #:unless (= (count (lambda (name) (eq? name operation)) symbols) expected))
     (violation path 'invalid-source-file-operation operation))
   (strict-vocabulary-violations path project-root source-file-vocabulary
                                 'unapproved-source-file-identifier)))

(define diagnostics-vocabulary
  '(< action actual and apply call-with-render-diagnostics car cc cf char->integer
    char-general-category character column cond define diagnostic-fragment else eq?
    equal? exn:fail:read-srclocs exn:fail:read? exn:fail:syntax? exn:fail? expand
    expected expected-source expression failure failure->source-problem for/list
    format format-source-problem format-user-name if in-string invalid lambda limit line location
    locations matched memq min native number->string only-in pair? path->string path?
    name phase problem provide quote raise read reason render rendering require same-source?
    size source source-name source-problem source-problem-column source-problem-line
    source-problem-reason source-problem? srcloc-column srcloc-line srcloc-source string
    string-append string-length string? symbol->string symbol? syntax-column
    syntax-failure-expression syntax-failure-reason syntax-line syntax-source text
    with-handlers zl zp))

(define (diagnostics-violations path info project-root)
  (define forms (module-info-forms info))
  (define symbols (module-symbols info))
  (append
   (exact-language-violations path info 'racket/base 'unexpected-diagnostics-language)
   (exact-require-violations
    path info '((require (only-in "source-file.rkt" source-problem source-problem? source-problem-reason
                                 source-problem-line source-problem-column
                                 syntax-failure-expression syntax-failure-reason)))
    'invalid-diagnostics-imports)
   (exact-provide-violations
    path info '(provide failure->source-problem format-source-problem format-user-name call-with-render-diagnostics)
    'invalid-diagnostics-exports)
   (if (and (equal? (filter-map top-level-binding-name forms)
                    '(same-source? failure->source-problem diagnostic-fragment format-user-name
                                   format-source-problem call-with-render-diagnostics))
            (= (datum-occurrence-count
                '(define (call-with-render-diagnostics action)
                   (with-handlers ([exn:fail? (lambda (failure)
                                              (raise (failure->source-problem failure 'render)))])
                     (action))) forms) 1))
       '() (list (violation path 'invalid-diagnostics-scaffolding 'module)))
   ;; These labels also name native capabilities. They are data only here.
   (for/list ([label '(read expand)]
              #:unless (and (= (count (lambda (name) (eq? name label)) symbols) 1)
                            (= (datum-occurrence-count (list 'quote label) forms) 1)))
     (violation path 'invalid-diagnostics-phase-token label))
   (strict-vocabulary-violations path project-root diagnostics-vocabulary
                                 'unapproved-diagnostics-identifier)))

;; Exact private source tooling: native reading of collected source buffers and
;; incremental reads from its injected source port. No evaluator or file access.
(define source-reader-vocabulary
  '(= _ add1 and argument arguments begin byte bytes->string/utf-8 bytes-append
    bytes-length bytes? call-with-default-reading-parameterization car char-whitespace?
    close-input-port column complete cond cons content continue current-readtable define
    define-values dynamic-wind echo else empty end end-column end-line end-position eof
    eof-object? eq? error exn:fail:contract? exn:fail:read-srclocs exn:fail:read:eof?
    exn:fail:read? failure failure-result for/first form forms get-output-bytes help
    identifier? if in-range incomplete index input invalid lambda length let line load
    location locations loop memq message name names next not null? off on only-in
    open-input-string open-output-bytes or output pair? parameterize parse-source-buffer
    parse-source-entry parsed pending port-count-lines! port-next-location position
    provide quit quote racket/string read-accept-compiled read-accept-lang
    read-accept-reader read-byte read-source-entry read-source-line read-syntax reason
    repl require reset result reverse separator set-port-next-location! size source
    source-buffer source-buffer-forms source-buffer-status source-buffer-text
    source-buffer? source-command source-ready? srcloc-column srcloc-line start status
    string->symbol string-length string-prefix? string-ref string? struct struct-copy
    struct-out sub1 substring syntax-e tail text trim-command-space trimmed
    unfinished-eof void with-handlers write-byte zero?))

;; Pin the executed reader block rather than infer dynamic scope from arbitrary
;; syntax nesting. A returned lambda, local function or named-let procedure must
;; not move the read outside its parameterization while retaining the controls.
(define expected-source-reader-block
  '(call-with-default-reading-parameterization
    (lambda ()
      (parameterize ((current-readtable #f)
                     (read-accept-reader #f)
                     (read-accept-lang #f)
                     (read-accept-compiled #f))
        (with-handlers ((exn:fail:read:eof?
                         (lambda (failure) (failure-result failure 'incomplete)))
                        (exn:fail:read?
                         (lambda (failure) (failure-result failure 'error))))
          (let loop ((forms '()))
            (define form (read-syntax source input))
            (if (eof-object? form)
                (source-buffer (if (null? forms) 'empty 'complete)
                               text (reverse forms) #f #f #f)
                (loop (cons form forms)))))))))

(define (source-reader-violations path info project-root)
  (define forms (module-info-forms info))
  (define symbols (module-symbols info))
  (append
   (exact-language-violations path info 'racket/base 'unexpected-source-reader-language)
   (exact-require-violations
    path info '((require (only-in racket/string string-prefix?)))
    'invalid-source-reader-imports)
   (exact-provide-violations
    path info
    '(provide (struct-out source-buffer) (struct-out source-command)
              parse-source-buffer parse-source-entry read-source-entry source-ready?)
    'invalid-source-reader-exports)
   (if (equal? (filter-map top-level-binding-name forms)
               '(parse-source-buffer trim-command-space parse-source-entry source-ready?
                 read-source-line read-source-entry))
       '() (list (violation path 'invalid-source-reader-definitions 'definitions)))
   (for/list ([control '(current-readtable read-accept-reader read-accept-lang
                        read-accept-compiled)]
              #:unless (and (= (count (lambda (name) (eq? name control)) symbols) 1)
                            (= (datum-occurrence-count (list control #f) forms) 1)))
     (violation path 'unsafe-source-reader-control control))
   (for/list ([call '((read-syntax source input) (read-byte input)
                     (write-byte byte output) (open-input-string text)
                     (bytes->string/utf-8 content #f))]
              #:unless (and (= (count (lambda (name) (eq? name (car call))) symbols) 1)
                            (= (datum-occurrence-count call forms) 1)))
     (violation path 'invalid-source-reader-operation call))
   ;; `load` is command data only; never admit the native loader as a value.
   (if (and (= (count (lambda (name) (eq? name 'load)) symbols) 1)
            (= (datum-occurrence-count '(quote load) forms) 1)
            (= (count (lambda (name)
                        (eq? name 'call-with-default-reading-parameterization)) symbols) 1)
            (= (datum-occurrence-count expected-source-reader-block forms) 1))
       '() (list (violation path 'unsafe-source-reader-configuration 'reader)))
   (strict-vocabulary-violations path project-root source-reader-vocabulary
                                 'unapproved-source-reader-identifier)))

;; Private session tooling has a closed import graph and native loader targets.
;; Pin module construction/expansion as a whole: symbols alone cannot establish
;; that user syntax lost native lexical context or was checked before execution.
(define session-vocabulary
  '(#%module-begin _ and assoc attalambda-interaction body car cdr checked-entry
    checked-entry-module-name checked-entry-result-names close-session complete cons
    consume current current-custodian current-namespace custodian custodian-shutdown-all
    datum->syntax define define-runtime-module-path-index define-values definitions demand-entry
    dynamic-require empty entry eval exn? expand expanded exports failure file filter for
    force forms gensym if imports in-list lambda language-index language-name language-origin language-reference list make-base-namespace
    make-custodian map memq module module->exports module-name module-source name names
    namespace not open-session owner parameterize parsed path path->string phase-zero
    prepare-entry provide quasiquote quote racket/promise racket/runtime-path raise
    raise-argument-error render-result renderer repl require result result-names session
    session-custodian session-namespace source-buffer-forms source-buffer-status
    source-buffer? string-value->string struct struct-out syntax-exports syntax-property
    unless unquote value-to-string void with-handlers
    bindings candidate checked-entry-definitions evaluate-entry for/fold hash-set
    hash-values hasheq parameterize-break session-bindings set-session-bindings!
    hash-keys session-names session-completion-names sort symbol<?
    for*/fold visible group item let #%app #%datum #%top
    input output error current-input-port current-output-port current-error-port
    session-input session-output session-error child successful? set! dynamic-wind
    initialize-session reset-session! previous installed? set-session-namespace!
    set-session-custodian! session-exit status exit-handler
    load-source-file source-name inspected inspect-source-file source-problem? cond else on-phase evaluate
    parse-source-buffer validated-source-path validated-source-text validated-source-line
    validated-source-column validated-source-position source-problem invalid
    source-buffer-message source-buffer-line source-buffer-column
    #%variable-reference variable-reference->namespace resolved-module-path-name
    module-path-index-resolve path? symbol? when namespace-attach-module-declaration
    racket/runtime-config))

(define expected-session-bootstrap
  '(when (symbol? language-name)
     (parameterize ([current-namespace language-origin])
       (dynamic-require language-reference #f))))

(define expected-session-initialization
  '(define (initialize-session owner)
     (parameterize ([current-custodian owner])
       (define namespace (make-base-namespace))
       (parameterize ([current-namespace namespace])
         (when (symbol? language-name)
           (namespace-attach-module-declaration language-origin language-reference)
           (namespace-attach-module-declaration language-origin 'racket/runtime-config))
         (dynamic-require language-reference #f))
       namespace)))

(define expected-session-rendering
  '(define (render-result current result)
     (parameterize ([current-namespace (session-namespace current)])
       (define renderer (force (dynamic-require language-reference 'value-to-string)))
       (string-value->string (renderer result)))))

(define expected-session-completion
  '(define (session-completion-names current)
     (parameterize ([current-namespace (session-namespace current)])
       (define-values (exports syntax-exports) (module->exports language-reference))
       (define names
         (for*/fold ([visible (session-bindings current)])
                    ([group (in-list (list exports syntax-exports))]
                     [item (in-list (let ([phase-zero (assoc 0 group)])
                                      (if phase-zero (cdr phase-zero) '())))])
           (if (memq (car item) '(#%app #%datum #%module-begin #%top))
               visible
               (hash-set visible (car item) #t))))
       (sort (hash-keys names) symbol<?))))

(define expected-session-reset
  '(define (reset-session! current)
     (define previous (session-custodian current))
     (define owner (make-custodian))
     (define installed? #f)
     (dynamic-wind
      void
      (lambda ()
        (define namespace (initialize-session owner))
        (parameterize-break #f
          (set-session-namespace! current namespace)
          (set-session-custodian! current owner)
          (set-session-bindings! current (hasheq))
          (set! installed? #t)))
      (lambda () (custodian-shutdown-all (if installed? previous owner))))))

(define expected-session-preparation
  '(define (prepare-entry current parsed [imports (hash-values (session-bindings current))]
                          #:on-phase [on-phase void])
     (unless (and (source-buffer? parsed)
                  (memq (source-buffer-status parsed) '(empty complete)))
       (raise-argument-error 'prepare-entry "complete source buffer" parsed))
     (define forms (source-buffer-forms parsed))
     (define name (gensym 'repl))
     (define result-names (map (lambda (_) (gensym 'result)) forms))
     (define body
       (syntax-property (datum->syntax #f (cons '#%module-begin forms))
                        'attalambda-interaction (list imports result-names)))
     (define module-source
       (datum->syntax #f `(module ,name ,language-reference ,body)))
     (parameterize ([current-namespace (session-namespace current)])
       (on-phase 'expand)
       (define expanded (expand module-source))
       (on-phase 'evaluate)
       (eval expanded)
       (define path `(quote ,name))
       (define-values (exports syntax-exports) (module->exports path))
       (define phase-zero (assoc 0 exports))
       (define names (if phase-zero (map car (cdr phase-zero)) '()))
       (dynamic-require path #f)
       (checked-entry name
                      (filter (lambda (name) (not (memq name result-names))) names)
                      (filter (lambda (name) (memq name names)) result-names)))))

(define expected-session-publication
  '(define (evaluate-entry current parsed [consume void]
                           #:imports [imports (hash-values (session-bindings current))]
                           #:on-phase [on-phase void])
     (define successful? #f)
     (define child (make-custodian (session-custodian current)))
     (dynamic-wind
      void
      (lambda ()
        (parameterize ([current-custodian child]
                       [current-input-port (session-input current)]
                       [current-output-port (session-output current)]
                       [current-error-port (session-error current)]
                       [exit-handler (lambda (status) (raise (session-exit status)))])
          (define entry (prepare-entry current parsed imports #:on-phase on-phase))
          (define candidate
            (for/fold ([bindings (session-bindings current)])
                      ([name (in-list (checked-entry-definitions entry))])
              (hash-set bindings name (list name (checked-entry-module-name entry) name))))
          (demand-entry current entry consume)
          (parameterize-break #f
            (set-session-bindings! current candidate)
            (set! successful? #t))))
      (lambda () (unless successful? (custodian-shutdown-all child))))))

(define expected-session-load
  '(define (load-source-file current source-name #:on-phase [on-phase void])
     (define inspected (inspect-source-file source-name))
     (cond
       [(source-problem? inspected) inspected]
       [else
        (define parsed
          (parse-source-buffer (validated-source-path inspected)
                               (validated-source-text inspected)
                               #:line (validated-source-line inspected)
                               #:column (validated-source-column inspected)
                               #:position (validated-source-position inspected)))
        (if (memq (source-buffer-status parsed) '(empty complete))
            (evaluate-entry current parsed void #:imports '() #:on-phase on-phase)
            (source-problem 'invalid (source-buffer-message parsed)
                            (source-buffer-line parsed) (source-buffer-column parsed)))])))

(define (session-violations path info project-root)
  (define forms (module-info-forms info))
  (define symbols (module-symbols info))
  (append
   (exact-language-violations path info 'racket/base 'unexpected-session-language)
   (exact-require-violations
    path info '((require racket/promise racket/runtime-path "source-reader.rkt" "source-file.rkt"
                          "../readers/string.rkt"))
    'invalid-session-imports)
   (exact-provide-violations
    path info '(provide (struct-out session) (struct-out checked-entry) (struct-out session-exit)
                         open-session close-session prepare-entry demand-entry render-result evaluate-entry
                         session-names session-completion-names reset-session! load-source-file)
    'invalid-session-exports)
   (if (and (equal? (filter-map top-level-binding-name forms)
                    '(language-index language-origin language-name language-reference initialize-session open-session close-session reset-session! prepare-entry
                                    demand-entry render-result evaluate-entry session-names session-completion-names load-source-file))
            (= (datum-occurrence-count
                '(define-runtime-module-path-index language-index "../lang/expander.rkt") forms) 1)
            (= (datum-occurrence-count
                '(define language-origin (variable-reference->namespace (#%variable-reference))) forms) 1)
            (= (datum-occurrence-count
                '(define language-name
                   (resolved-module-path-name (module-path-index-resolve language-index))) forms) 1)
            (= (datum-occurrence-count
                '(define language-reference
                   (if (path? language-name)
                       `(file ,(path->string language-name))
                       `(quote ,language-name))) forms) 1)
            (equal? (filter (lambda (form) (and (pair? form) (eq? (car form) 'struct))) forms)
                     '((struct session ([namespace #:mutable] [custodian #:mutable] input output error
                                        [bindings #:mutable]) #:transparent)
                       (struct checked-entry (module-name definitions result-names) #:transparent)
                       (struct session-exit (status) #:transparent)))
            (member expected-session-bootstrap forms)
            (= (datum-occurrence-count expected-session-bootstrap forms) 1)
            (= (datum-occurrence-count expected-session-initialization forms) 1)
            (= (datum-occurrence-count expected-session-rendering forms) 1)
            (= (datum-occurrence-count expected-session-completion forms) 1)
            (= (datum-occurrence-count expected-session-preparation forms) 1)
            (= (datum-occurrence-count expected-session-publication forms) 1)
            (= (datum-occurrence-count expected-session-reset forms) 1)
            (= (datum-occurrence-count expected-session-load forms) 1))
       '() (list (violation path 'invalid-session-scaffolding 'module)))
   (for/list ([operation '(eval expand datum->syntax syntax-property module->exports
                               make-base-namespace make-custodian dynamic-require
                               set-session-bindings! parameterize-break hash-set
                               namespace-attach-module-declaration module-path-index-resolve
                               variable-reference->namespace resolved-module-path-name set!)]
              [expected '(1 2 2 1 2 1 3 5 3 3 2 2 1 1 1 2)]
              #:unless (= (count (lambda (name) (eq? name operation)) symbols) expected))
     (violation path 'invalid-session-operation operation))
   (for/list ([call '((dynamic-require language-reference #f)
                     (dynamic-require path #f)
                     (dynamic-require `(quote ,(checked-entry-module-name entry)) name)
                     (dynamic-require language-reference 'value-to-string))]
              [expected '(2 1 1 1)]
              #:unless (= (datum-occurrence-count call forms) expected))
     (violation path 'invalid-session-loader-target call))
   (strict-vocabulary-violations path project-root session-vocabulary
                                 'unapproved-session-identifier)))

(define expected-repl-commands
  '(case (source-command-name parsed)
                    [(help) (display help-text error) (flush-output error) 'continue]
                    [(names)
                     (define names (session-names current))
                     (if (null? names)
                         (display "No user definitions.\n" error)
                         (begin
                           (display "User definitions:\n" error)
                           (for ([name (in-list names)])
                             (fprintf error "  ~a\n" (format-user-name name)))))
                     (flush-output error)
                     'continue]
                    [(load)
                     (set! source (source-command-argument parsed))
                     (set! phase 'load)
                     (define result
                       (load-source-file current source #:on-phase (lambda (next) (set! phase next))))
                     (when (source-problem? result) (raise result))
                     (set! phase 'command)
                     (prepare-ui)
                     (display "Loaded source file.\n" error) (flush-output error)
                     'continue]
                    [(reset)
                     (set! phase 'reset)
                     (reset-session! current)
                     (display "Session reset.\n" error) (flush-output error)
                     'continue]
                    [(echo)
                     (set! echo? (source-command-argument parsed))
                     (fprintf error "Automatic echo: ~a\n" (if echo? "on" "off"))
                     (flush-output error)
                     'continue]
                    [(quit) (finish)]
                    [else (raise (source-problem 'invalid "unsupported command" #f #f))]))

(define repl-vocabulary
  '(_ add1 and begin call-with-render-diagnostics close-session cond continue current
    current-custodian current-error-port current-input-port current-output-port
    custodian-shutdown-all define display dynamic-wind else empty eof-object? eq?
    error evaluate evaluate-entry exn:break? exn:fail? failed? failure
    failure->source-problem finish flush-output format format-source-problem fprintf
    history? if input interactive? interrupted invalid lambda let loop make-custodian
    next not number on-phase open-session outcome output owner parameterize parsed
    phase problem provide quote raise read-source-entry render render-result rendered require
    run-repl session-exit-status session-exit? set! show source source-buffer-column
    source-buffer-line source-buffer-message source-buffer-status source-command?
    source-problem source-problem? string->symbol unfinished-eof value version void
    when with-handlers
    case echo echo? help help-text names name null? for in-list session-names load load-source-file
    source-command-name source-command-argument result reset reset-session! quit
    string-append format-user-name define-values program-output result-output prepare-ui
    make-shell-output terminal-port? fatal memq command close-output-port recover parameterize-break break-enabled
    racket/runtime-path define-runtime-module-path-index editor-index editor-read dynamic-require read-editor-entry
    read-entry read-plain byte-ready? persistent-history? history read-history write-history
    remember-history source-buffer? source-buffer-text source-command-text session-completion-names
    history-changed? updated unless = port-file-identity))

(define (repl-violations path info project-root)
  (define forms (module-info-forms info))
  (define symbols (module-symbols info))
  (append
   (exact-language-violations path info 'racket/base 'unexpected-repl-language)
   (exact-require-violations
    path info '((require racket/runtime-path "source-reader.rkt" "source-file.rkt" "session.rkt" "diagnostics.rkt" "output.rkt" "history.rkt"))
    'invalid-repl-imports)
   (exact-provide-violations path info '(provide run-repl) 'invalid-repl-exports)
   (if (equal? (filter-map top-level-binding-name forms) '(editor-index help-text run-repl))
       '() (list (violation path 'invalid-repl-definitions 'module)))
   ;; `load` is a command label only; pin its case context as well as its count.
   (if (and (= (datum-occurrence-count expected-repl-commands forms) 1)
            (= (count (lambda (name) (eq? name 'load)) symbols) 2))
       '() (list (violation path 'invalid-repl-command-dispatch 'load)))
   (for/list ([operation '(current-input-port current-output-port current-error-port
                                             read-source-entry open-session evaluate-entry render-result
                                             make-shell-output terminal-port? close-output-port break-enabled
                                             byte-ready? dynamic-require define-runtime-module-path-index
                                             read-history write-history remember-history session-completion-names)]
              #:unless (= (count (lambda (name) (eq? name operation)) symbols) 1))
     (violation path 'invalid-repl-operation operation))
   (if (= (count (lambda (name) (eq? name 'port-file-identity)) symbols) 2)
       '() (list (violation path 'invalid-repl-operation 'port-file-identity)))
   (for/list ([call '((define-runtime-module-path-index editor-index "editor.rkt")
                     (dynamic-require editor-index (quote read-editor-entry))
                     (editor-read input output source history #:names (session-completion-names current))
                     (define persistent-history? (and interactive? history?))
                     (read-history persistent-history?)
                     (define history-changed? #f)
                     (write-history (and persistent-history? history-changed?) history)
                     (when (and interactive? (not (eof-object? parsed))
                                (not (and (source-buffer? parsed)
                                          (eq? (source-buffer-status parsed) (quote unfinished-eof)))))
                       (define updated
                         (remember-history history
                                           (if (source-command? parsed)
                                               (source-command-text parsed)
                                               (source-buffer-text parsed))))
                       (unless (eq? updated history)
                         (parameterize-break #f
                           (set! history updated)
                           (set! history-changed? #t))))
                     (byte-ready? input)
                     (define input (current-input-port))
                     (define output (current-output-port))
                     (define error (current-error-port))
                     (make-shell-output output error
                                        (and interactive? (terminal-port? output)
                                             (= (port-file-identity output) (port-file-identity error))))
                     (close-output-port program-output)
                     (break-enabled #t)
                     (open-session #:input input #:output program-output #:error error)
                     (read-source-entry
                      input source
                      #:continue (lambda ()
                                   (when interactive? (display "...> " error) (flush-output error)))))]
              #:unless (= (datum-occurrence-count call forms) 1))
     (violation path 'invalid-repl-port-use call))
   (strict-vocabulary-violations path project-root repl-vocabulary
                                 'unapproved-repl-identifier)))

(define expected-output-definitions
  '((define (make-observed-output destination)
  (define total 0)
  (define last-byte #f)
  (define observed
    (make-output-port
     'program-stdout destination
     (lambda (bytes start end nonblocking? breakable?)
       (cond
         [(= start end)
          (parameterize-break breakable? (flush-output destination))
          0]
         [else
          (define written
            ((cond [nonblocking? write-bytes-avail*]
                   [breakable? write-bytes-avail/enable-break]
                   [else write-bytes-avail])
             bytes destination start end))
          (cond
            [(and written (positive? written))
             (set! total (+ total written))
             (set! last-byte (bytes-ref bytes (+ start written -1)))
             written]
            [else (wrap-evt destination (lambda (_) #f))])]))
     void))
  (values observed (lambda () (values total last-byte))))

(define (make-shell-output output ui shared-terminal?)
  (define-values (program-output metadata) (make-observed-output output))
  (define result-boundary 0)
  (define ui-boundary 0)
  (define (result-output rendered)
    (define-values (total last-byte) (metadata))
    (when (and (> total result-boundary) (not (equal? last-byte 10))
               (not (and shared-terminal? (>= ui-boundary total))))
      (newline output))
    (fprintf output "=> ~a\n" rendered)
    (flush-output output)
    (set! result-boundary total)
    (set! ui-boundary total))
  (define (prepare-ui)
    (define-values (total last-byte) (metadata))
    (when (and shared-terminal? (> total ui-boundary) (not (equal? last-byte 10)))
      (newline ui)
      (flush-output ui))
    ;; A UI newline does not separate redirected stdout from its next result.
    (set! ui-boundary total))
  (values program-output result-output prepare-ui))))

(define (output-violations path info project-root)
  (append
   (exact-language-violations path info 'racket/base 'unexpected-output-language)
   (exact-require-violations path info '() 'invalid-output-imports)
   (exact-provide-violations path info '(provide make-shell-output) 'invalid-output-exports)
   (if (equal? (cdr (module-info-forms info)) expected-output-definitions)
       '() (list (violation path 'invalid-output-forwarding 'module)))))

(define expected-history-forms
  '(
;; Inert history framing. Bounds are checked before decoding or allocating from
;; stored lengths; history text is never passed to a Racket data reader.
(require racket/file racket/path)
(provide history-entry-limit history-byte-limit history->bytes bytes->history
         remember-history read-history write-history)
(define history-entry-limit 1000)
(define history-byte-limit 1048576)
(define history-header #"AttaLambda-history-v1\n")
(define history-prefix-size (+ (bytes-length history-header) 2))

;; Source ownership is decided by the shell. Retain at most 1000 submissions
;; independently of the editor's own shorter close-result history.
(define (remember-history entries text)
  (if (and (string? text) (positive? (string-length text)))
      (for/list ([entry (in-list (cons text entries))]
                 [index (in-range history-entry-limit)])
        entry)
      entries))

;; Entries arrive newest first. Skip entries that cannot fit while retaining
;; later small entries; a history-storage limit must never reject execution.
(define (history->bytes entries)
  (define-values (parts total count)
    (for/fold ([parts '()] [total history-prefix-size] [count 0])
              ([entry (in-list entries)] #:break (= count history-entry-limit))
      (unless (string? entry)
        (raise-argument-error 'history->bytes "list of strings" entries))
      (define available (- history-byte-limit total 4))
      (define size
        (and (<= (string-length entry) available) (string-utf-8-length entry)))
      (if (and size (<= size available))
          (values (cons (string->bytes/utf-8 entry)
                        (cons (integer->integer-bytes size 4 #f #t) parts))
                  (+ total 4 size) (add1 count))
          (values parts total count))))
  (apply bytes-append history-header
         (integer->integer-bytes count 2 #f #t) (reverse parts)))

(define (bytes->history content)
  (define size (bytes-length content))
  (and
   (<= history-prefix-size size history-byte-limit)
   (bytes=? (subbytes content 0 (bytes-length history-header)) history-header)
   (let ([count (integer-bytes->integer content #f #t
                                      (bytes-length history-header) history-prefix-size)])
     (and
      (<= count history-entry-limit)
      (with-handlers ([exn:fail:contract? (lambda (_) #f)])
        (let loop ([remaining count] [offset history-prefix-size] [entries '()])
          (cond
            [(zero? remaining) (and (= offset size) (reverse entries))]
            [(> (+ offset 4) size) #f]
            [else
             (define start (+ offset 4))
             (define length (integer-bytes->integer content #f #t offset start))
             (define end (+ start length))
             (and (<= end size)
                  (loop (sub1 remaining) end
                        (cons (bytes->string/utf-8 content #f start end) entries)))])))))))

(define (history-directory-stat-safe? stat private? root-owner)
  (define mode (hash-ref stat 'mode))
  (and
   (= (bitwise-and mode file-type-bits) directory-type-bits)
   (or (not (eq? (system-type 'os) 'unix))
       (zero? (bitwise-and mode (if private? #o077 #o022)))
       ;; Compare with the filesystem root's observed owner: user namespaces can
       ;; map its UID to a value other than zero. Other owners remain untrusted.
       (and (not private?) (= (hash-ref stat 'user-id) root-owner)
            (not (zero? (bitwise-and mode sticky-bit)))))))

(define (history-file-stat-safe? stat)
  (define mode (hash-ref stat 'mode))
  (and (= (bitwise-and mode file-type-bits) regular-file-type-bits)
       (= (hash-ref stat 'hardlink-count) 1)
       (<= (hash-ref stat 'size) history-byte-limit)
       (or (not (eq? (system-type 'os) 'unix))
           (zero? (bitwise-and mode #o077)))))

(define (checked-history-directory preference-directory #:create? [create? #f])
  (define directory
    (simplify-path
     (path->complete-path
      (build-path (or preference-directory (find-system-path 'pref-dir)) "attalambda"))
     #f))
  (define parts (explode-path directory))
  (and
   ;; Validate all names before the writer can create any missing directory.
   (for/and ([part (in-list parts)])
     (and (path? part)
          (not (regexp-match? #px"(^|\\.)env($|\\.)" (string-downcase (path->string part))))))
   (let loop ([parts parts] [parent #f] [root-owner #f])
     (cond
       [(null? parts) parent]
       [else
        (define path (if parent (build-path parent (car parts)) (car parts)))
        (when (and create? (not (file-or-directory-type path)))
          (make-directory path #o700))
        (and
         (eq? (file-or-directory-type path) 'directory)
         (let* ([stat (file-or-directory-stat path #t)]
                [owner (or root-owner (hash-ref stat 'user-id))])
           (and (history-directory-stat-safe? stat (null? (cdr parts)) owner)
                (loop (cdr parts) path owner))))]))))

(define (read-history enabled? #:preference-directory [preference-directory #f])
  ;; Disabled means no path discovery or metadata/content access of any kind.
  (if (not enabled?) '()
      (with-handlers ([exn:fail? (lambda (_) '())])
        (define directory (checked-history-directory preference-directory))
        (or
         (and
          directory
          (let ([path (build-path directory "history-v1")])
            (and
             (eq? (file-or-directory-type path) 'file)
             (let ([before (file-or-directory-stat path #t)])
               (and
                (history-file-stat-safe? before)
                (call-with-input-file
                 path
                 (lambda (input)
                   (define opened (port-file-stat input))
                   (and
                    (history-file-stat-safe? opened)
                    (= (hash-ref before 'device-id) (hash-ref opened 'device-id))
                    (= (hash-ref before 'inode) (hash-ref opened 'inode))
                    (let ([content (read-bytes (add1 history-byte-limit) input)])
                      (and (bytes? content) (bytes->history content)))))))))))
         '()))))

(define (history-replacement-safe? path)
  (define type (file-or-directory-type path))
  (or (not type)
      (and (eq? type 'file)
           (history-file-stat-safe? (file-or-directory-stat path #t)))))

(define (write-history enabled? entries #:preference-directory [preference-directory #f])
  (when enabled?
    (with-handlers ([exn:fail? void])
      (define content (history->bytes entries))
      (define directory (checked-history-directory preference-directory #:create? #t))
      (when directory
        (define path (build-path directory "history-v1"))
        (when (history-replacement-safe? path)
          (call-with-atomic-output-file
           path
           (lambda (output temporary)
             ;; The temporary starts inside a private directory. Restrict its
             ;; mode before writing any source, then recheck the replacement path.
             (file-or-directory-permissions temporary #o600)
             (write-bytes content output)
             (unless (and (checked-history-directory preference-directory)
                          (history-replacement-safe? path))
               (error 'history "history target changed during save")))
           #:rename-fail-handler (lambda (failure _) (raise failure))))))))
))

(define (history-violations path info project-root)
  (append
   (exact-language-violations path info 'racket/base 'unexpected-history-language)
   (if (equal? (module-info-forms info) expected-history-forms)
       '() (list (violation path 'invalid-bounded-history 'module)))))

(define expected-editor-forms
  (quote (

;; Source collection only. The session engine continues to own evaluation.
(require expeditor racket/port racket/runtime-path racket/string
         syntax-color/racket-lexer "source-reader.rkt")
(provide read-editor-entry)
(define-runtime-module-path-index editor-output-index "editor-output.rkt")

(define (completion-namespace names)
  (define namespace (make-empty-namespace))
  (for ([name (in-list names)])
    (define spelling
      (if (equal? (symbol->string name) "")
          "||"
          (parameterize ([read-accept-bar-quote #f])
            (string-replace (format "~s" name) "|" "\\|"))))
    ;; At the start of an entry, a bare colon would select a shell command.
    (define source-name
      (if (string-prefix? spelling ":") (string-append "\\" spelling) spelling))
    (namespace-set-variable-value! (string->symbol source-name) #f #t namespace))
  namespace)

(define (read-editor-entry input output source history
                           #:names [names '()]
                           #:open [open-editor expeditor-open])
  ;; Internal portability/file-mode use must not resolve POSIX symbols on Windows.
  (and
   (eq? (system-type 'os) 'unix)
   (let ([call-with-editor-output
          (dynamic-require editor-output-index 'call-with-editor-output)])
     (define content
       (parameterize
           ([current-input-port input]
            [current-output-port output]
            ;; Only source spellings and inert placeholders enter this namespace.
            [current-namespace (completion-namespace names)]
            [current-expeditor-reader
             (lambda (input)
               (define text (port->string input))
               (if (equal? text "") eof text))]
            [current-expeditor-post-skipper (lambda (_) 0)]
            [current-expeditor-ready-checker
             (lambda (input) (source-ready? (port->string input)))]
            [current-expeditor-lexer racket-lexer]
            [current-expeditor-parentheses '((|(| |)|) (|[| |]|) (|{| |}|))]
            ;; Use the library's S-expression grouping and indentation fallback.
            [current-expeditor-grouper (lambda (editor start limit direction) #t)]
            [current-expeditor-indenter (lambda (editor start auto?) #f)]
            [current-expeditor-color-enabled #f])
         (call-with-editor-output
          (lambda ()
            (define editor (open-editor history))
            (and editor
                 (dynamic-wind
                  void
                  (lambda () (expeditor-read editor #:prompt "atta>"))
                  ;; Open afresh on the next prompt so shell history can retain
                  ;; the specified 1000 entries despite the library's limit.
                  (lambda () (void (expeditor-close editor)))))))))
     (cond
       [(or (not content) (eof-object? content)) content]
       [(string? content) (parse-source-entry source content)]
       [else (error 'editor "source editor did not return an entry")]))))
)))

(define (editor-violations path info project-root)
  (append
   (exact-language-violations path info 'racket/base 'unexpected-editor-language)
   (if (equal? (module-info-forms info) expected-editor-forms)
       '() (list (violation path 'invalid-editor-source-adapter 'module)))))

(define expected-editor-output-forms
  '(
;; CS 9.3's editor uses fd0/fd1. Select stderr only during source editing;
;; Expeditor owns terminal modes and input. Load this POSIX adapter lazily.
(require ffi/unsafe)
(provide call-with-editor-output)

(define libc (ffi-lib #f))
(define duplicate (get-ffi-obj "dup" libc (_fun _int -> _int)))
(define duplicate-to (get-ffi-obj "dup2" libc (_fun _int _int -> _int)))
(define close-descriptor (get-ffi-obj "close" libc (_fun _int -> _int)))

(define (call-with-editor-output action)
  (define saved #f)
  (define action-failed? #f)
  (dynamic-wind
   (lambda ()
     (parameterize-break #f
       (flush-output (current-output-port))
       (set! saved (duplicate 1))
       (when (< saved 0) (error 'editor "cannot preserve stdout"))
       (when (< (duplicate-to 2 1) 0)
         (close-descriptor saved)
         (set! saved #f)
         (error 'editor "cannot select UI output"))))
   (lambda ()
     (set! action-failed? #f)
     (with-handlers ([(lambda (_) #t)
                      (lambda (failure) (set! action-failed? #t) (raise failure))])
       (action)))
   (lambda ()
     (parameterize-break #f
       (with-handlers ([(lambda (_) #t)
                        (lambda (failure) (unless action-failed? (raise failure)))])
         ;; Even a failed final flush must restore stdout and close its copy.
         (dynamic-wind
          void
          (lambda () (flush-output (current-output-port)))
          (lambda ()
            (define restored (duplicate-to saved 1))
            (close-descriptor saved)
            (set! saved #f)
            (when (< restored 0) (error 'editor "cannot restore stdout")))))))))
))

(define (editor-output-violations path info project-root)
  (append
   (exact-language-violations path info 'racket/base 'unexpected-editor-output-language)
   (if (equal? (module-info-forms info) expected-editor-output-forms)
       '() (list (violation path 'invalid-editor-output-adapter 'module)))))

(define (host-violations path info project-root)
  (define host-definitions
    (filter (lambda (form)
              (eq? (top-level-binding-name form) 'host))
            (module-info-forms info)))
  (define imported-targets
    (filter-map
     (lambda (spec)
       (define base (require-spec-base spec))
       (and (string? base)
            (resolve-relative path base)))
     (module-require-specs info)))
  (define required-targets
    (list (normalized (build-path project-root "effects" "protocol.rkt"))
          (normalized (build-path project-root "runtime" "codec.rkt"))))
  (append
   (exact-language-violations path
                              info
                              'racket/base
                              'unexpected-host-language)
   (strict-import-violations path info project-root
                             host-import-allowed?
                             'disallowed-host-import)
   (exact-provide-violations path info expected-host-provide
                             'invalid-host-export)
   (if (= (length host-definitions) 1)
       '()
       (list (violation path 'invalid-host-definition-count
                        (length host-definitions))))
   (for/list ([required (in-list required-targets)]
              #:unless (= (count (lambda (target)
                                   (equal? target required))
                                 imported-targets)
                          1))
     (violation path 'missing-required-host-import required))
   (symbol-violations path
                      (module-symbols info)
                      forbidden-host-capabilities
                      'forbidden-host-capability)))

(define (file-boundary-violations path class
                                  [project-root default-project-root])
  (define source (normalized path))
  (define root (normalized project-root))
  (cond
    [(not (safe-source-path? source root))
     (list (violation source 'disallowed-boundary-path source))]
    [(not (file-exists? source))
     (list (violation source 'missing-boundary-file source))]
    [(not (regular-file-path? source))
     (list (violation source 'nonregular-boundary-file source))]
    [else
     (define info
       (with-handlers ([exn:fail? values])
         (read-module-info/unchecked source root)))
     (cond
       [(exn? info)
        (list (violation source 'boundary-read-failure
                         (exn-message info)))]
       [(not info)
        (list (violation source 'invalid-boundary-module source))]
       [else
        (case class
          [(effect) (effect-violations source info root)]
          [(macro-shell) (macro-shell-violations source info)]
          [(macro) (macro-violations source info)]
          [(language-expander)
           (language-expander-violations source info root)]
          [(language-reader) (language-reader-violations source info)]
          [(reader) (reader-violations source info root)]
          [(test tooling) (host-support-violations source info class)]
          [(application) (application-violations source info)]
          [(runner) (runner-violations source info root)]
          [(source-reader) (source-reader-violations source info root)]
          [(source-file) (source-file-violations source info root)]
          [(diagnostics) (diagnostics-violations source info root)]
          [(repl) (repl-violations source info root)]
          [(shell-output) (output-violations source info root)]
          [(editor-output) (editor-output-violations source info root)]
          [(editor) (editor-violations source info root)]
          [(history) (history-violations source info root)]
          [(session) (session-violations source info root)]
          [(package-info) (package-info-violations source info root)]
          [(codec) (codec-violations source info root)]
          [(host) (host-violations source info root)]
          [else
           (list (violation source 'unknown-boundary-class class))])])]))

(define (excluded-discovery-entry? path)
  (define name
    (file-name-from-path path))
  (or (dotenv-name? path)
      (and name
           (member (path->string name)
                   '(".git" "compiled")))))

(define (racket-files-under directory)
  (cond
    [(excluded-discovery-entry? directory) '()]
    [(link-exists? directory) (list directory)]
    [(directory-exists? directory)
     (append-map racket-files-under
                 (directory-list directory #:build? #t))]
    [(and (file-exists? directory)
          (member (path-get-extension directory)
                  '(#".rkt" #".attl")
                  equal?))
     (list (normalized directory))]
    [else '()]))

(define (source-class path project-root)
  (define root
    (normalized project-root))
  (define source
    (normalized path))
  (define relative-parts
    (explode-path (find-relative-path root source)))
  (define first-part
    (and (pair? relative-parts)
         (path? (car relative-parts))
         (path->string (car relative-parts))))
  (define extension
    (path-get-extension source))
  (cond
    [(equal? extension #".attl")
     (and (equal? first-part "examples") 'application)]
    [(not (equal? extension #".rkt")) #f]
    [(equal? source (normalized (build-path root "info.rkt")))
     'package-info]
    [(equal? first-part "core") 'pure-core]
    [(equal? first-part "effects") 'effect]
    [(equal? first-part "macros")
     (cond
       [(equal? source
                (normalized
                 (build-path root "macros" "lazy-with-macros.rkt")))
        'macro-shell]
       [(equal? source
                (normalized
                 (build-path root "macros" "macros.rkt")))
        'macro]
       [else 'macro])]
    [(equal? first-part "runtime")
     (cond
       [(equal? source
                (normalized (build-path root "runtime" "codec.rkt")))
        'codec]
       [(equal? source
                (normalized (build-path root "runtime" "host.rkt")))
        'host]
       [else 'runtime])]
    [(equal? first-part "lang")
     (cond
       [(equal? source
                (normalized (build-path root "lang" "reader.rkt")))
        'language-reader]
       [(equal? source
                (normalized (build-path root "lang" "expander.rkt")))
        'language-expander]
       [else 'language])]
    [(equal? first-part "readers") 'reader]
    [(equal? first-part "tests") 'test]
    [(equal? first-part "tooling") 'tooling]
    [(equal? first-part "examples") 'application]
    [(equal? source (normalized (build-path root "runner" "source-reader.rkt")))
     'source-reader]
    [(equal? source (normalized (build-path root "runner" "source-file.rkt")))
     'source-file]
    [(equal? source (normalized (build-path root "runner" "diagnostics.rkt")))
     'diagnostics]
    [(equal? source (normalized (build-path root "runner" "repl.rkt")))
     'repl]
    [(equal? source (normalized (build-path root "runner" "history.rkt")))
     'history]
    [(equal? source (normalized (build-path root "runner" "editor.rkt")))
     'editor]
    [(equal? source (normalized (build-path root "runner" "editor-output.rkt")))
     'editor-output]
    [(equal? source (normalized (build-path root "runner" "output.rkt")))
     'shell-output]
    [(equal? source (normalized (build-path root "runner" "session.rkt")))
     'session]
    [(equal? first-part "runner") 'runner]
    [else #f]))

(define (classify-sources paths project-root)
  (filter-map
   (lambda (path)
     (define class
       (source-class path project-root))
     (and class
          (source-classification path class)))
   paths))

(define (project-source-classifications
         [project-root default-project-root])
  (define root
    (normalized project-root))
  (if (and (safe-absolute-components? root)
           (directory-exists? root))
      (classify-sources (racket-files-under root) root)
      '()))

(define (files-in-class classifications class)
  (for/list ([classification (in-list classifications)]
             #:when
             (eq? (source-classification-class classification) class))
    (source-classification-path classification)))

(define expected-application-paths
  '("hello.attl"
    "stdout.attl"
    "file-round-trip.attl"
    "http-server.attl"
    "foundations.attl"))

(define (application-inventory-violations project-root)
  (define directory
    (normalized (build-path project-root "examples")))
  (define expected
    (map (lambda (name)
           (normalized (build-path directory name)))
         expected-application-paths))
  (cond
    [(link-exists? directory)
     (list (violation directory
                      'disallowed-application-directory
                      directory))]
    [(not (directory-exists? directory))
     (list (violation directory
                      'missing-application-directory
                      directory))]
    [else
     (define actual
       (map normalized
            (directory-list directory #:build? #t)))
     (append
      (for/list ([path (in-list expected)]
                 #:unless (member path actual equal?))
        (violation path 'missing-canonical-application path))
      (for/list ([path (in-list actual)]
                 #:unless (member path expected equal?))
        (violation path 'unknown-application-source path))
      (for/list ([path (in-list expected)]
                 #:when (member path actual equal?)
                 #:when
                 (or (link-exists? path)
                     (not (regular-file-path? path))))
        (violation path
                   'disallowed-canonical-application
                   path)))]))

(define (unsafe-repository-path-violations files project-root)
  (for/list ([path (in-list files)]
             #:unless (source-file? path project-root))
    (violation path 'disallowed-repository-source-path path)))

(define (unclassified-repository-source-violations files project-root)
  (for/list ([path (in-list files)]
             #:when
             (and (source-file? path project-root)
                  (not (source-class path project-root))))
    (violation path 'unclassified-repository-source path)))

(define (unsafe-production-path-violations files project-root)
  (for/list ([path (in-list files)]
             #:unless (source-file? path project-root))
    (violation path 'disallowed-boundary-path path)))

(define (unauthorized-codec-imports files project-root codec host)
  (append-map
   (lambda (source)
     (define info (read-module-info source project-root))
     (if info
         (for*/list ([spec (in-list (module-require-specs info))]
                     [base (in-list (or (require-spec-bases spec) '()))]
                     #:when
                     (and (string? base)
                          (equal? (resolve-relative source base) codec)
                          (not (equal? source host))))
           (violation source 'unauthorized-codec-import spec))
         '()))
   files))

(define (unauthorized-host-imports files project-root host
                                   language-expander)
  (append-map
   (lambda (source)
     (define info (read-module-info source project-root))
     (if (or (not info) (equal? source host))
         '()
         (for*/list ([spec (in-list (module-require-specs info))]
                     [base (in-list (or (require-spec-bases spec) '()))]
                     #:when
                     (and (string? base)
                          (equal? (resolve-relative source base) host)
                          (not (equal? source language-expander))))
           (violation source 'unauthorized-host-import spec))))
   files))

(define (unauthorized-host-capability-imports files project-root host)
  (append-map
   (lambda (source)
     (define info (read-module-info source project-root))
     (if (or (not info) (equal? source host))
         '()
         (for*/list ([spec (in-list (module-require-specs info))]
                     [base (in-list (or (require-spec-bases spec) '()))]
                     #:when (memq base '(racket/file racket/tcp)))
           (violation source
                      'unauthorized-host-capability-import
                      spec))))
   files))

(define (production-nonproduction-imports files project-root)
  (define nonproduction-directories
    (map (lambda (name)
           (normalized (build-path project-root name)))
         '("readers" "tests" "tooling" "examples" "runner")))
  (append-map
   (lambda (source)
     (define info (read-module-info source project-root))
     (if info
         (for*/list ([spec (in-list (module-require-specs info))]
                     [base (in-list (or (require-spec-bases spec) '()))]
                     #:when
                     (and (string? base)
                          (let ([target (resolve-relative source base)])
                            (ormap (lambda (directory)
                                     (path-within? directory target))
                                   nonproduction-directories))))
           (violation source
                      'production-imports-nonproduction
                      spec))
         '()))
   files))

(define (privileged-identifiers-outside-host files project-root host)
  (append-map
   (lambda (source)
     (define info (read-module-info source project-root))
     (if (or (not info) (equal? source host))
         '()
         (for/list
             ([name
               (in-list
                (remove-duplicates
                 (module-symbols info)))]
              #:when (memq name privileged-host-only-identifiers))
           (violation source
                      'privileged-identifier-outside-host
                      name))))
   files))

(define (unclassified-require-specs files project-root)
  (append-map
   (lambda (source)
     (define info (read-module-info source project-root))
     (if info
         (for/list ([spec (in-list (module-require-specs info))]
                    #:unless (require-spec-bases spec))
           (violation source 'unclassified-production-import spec))
         '()))
   files))

(define (unauthorized-host-surfaces files project-root host
                                    language-expander)
  (append-map
   (lambda (source)
     (define info (read-module-info source project-root))
     (if (or (not info) (equal? source host))
         '()
         (append
          (for/list ([form (in-list (module-info-forms info))]
                     #:when (eq? (top-level-binding-name form) 'host))
            (violation source 'unauthorized-host-definition form))
          (for/list ([form (in-list (module-info-forms info))]
                     #:when
                     (and (provide-form? form)
                          (member 'host (datum-symbols (cdr form)))
                          (not (equal? source language-expander))))
            (violation source 'unauthorized-host-export form)))))
   files))

;; The public Nat surface was removed by the Step 35.5 switch. Rat is the
;; only public number type; these retired spellings must never reappear in
;; any production source.
(define retired-nat-surface-identifiers
  '(nat-type raw-make-nat raw-nat-value
    typed-nat-succ typed-nat-add typed-nat-sub typed-nat-mult
    typed-nat-div typed-nat-equal typed-nat-less typed-nat-less-equal
    typed-nat-greater typed-nat-greater-equal typed-nat-is-zero
    object-nat->integer integer->object-nat decode-bounded-nat
    ZERO ONE TWO THREE FOUR FIVE SIX SEVEN EIGHT NINE TEN))

(define (reintroduced-nat-surface-violations production-files project-root)
  (append-map
   (lambda (path)
     (define source (normalized path))
     (define root (normalized project-root))
     (cond
       [(not (and (safe-source-path? source root)
                  (file-exists? source)
                  (regular-file-path? source)))
        '()]
       [else
        (define info
          (with-handlers ([exn:fail? (lambda (failure) #f)])
            (read-module-info/unchecked source root)))
        (if (not info)
            '()
            (for/list ([name
                        (in-list
                         (remove-duplicates (module-symbols info)))]
                       #:when (memq name retired-nat-surface-identifiers))
              (violation source 'reintroduced-nat-surface name)))]))
   production-files))

(define (project-boundary-violations
         [project-root default-project-root])
  (define root (normalized project-root))
  (cond
    [(not (safe-absolute-components? root))
     (list (violation root 'disallowed-boundary-root 'unsafe-root))]
    [(not (directory-exists? root))
     (list (violation root 'missing-boundary-root 'missing-root))]
    [else
     ;; No directory discovery or source read occurs until the complete
     ;; authorization anchor above has passed component-by-component checks.
     (define effects-directory (build-path root "effects"))
     (define macros-directory (build-path root "macros"))
     (define runtime-directory (build-path root "runtime"))
     (define language-directory (build-path root "lang"))
     (define runner-directory (build-path root "runner"))
     (define package-info
       (normalized (build-path root "info.rkt")))
     (define runner
       (normalized (build-path runner-directory "attalambda.rkt")))
     (define source-reader
       (normalized (build-path runner-directory "source-reader.rkt")))
     (define session
       (normalized (build-path runner-directory "session.rkt")))
     (define source-file
       (normalized (build-path runner-directory "source-file.rkt")))
     (define diagnostics
       (normalized (build-path runner-directory "diagnostics.rkt")))
     (define history
       (normalized (build-path runner-directory "history.rkt")))
     (define editor
       (normalized (build-path runner-directory "editor.rkt")))
     (define editor-output
       (normalized (build-path runner-directory "editor-output.rkt")))
     (define shell-output
       (normalized (build-path runner-directory "output.rkt")))
     (define repl
       (normalized (build-path runner-directory "repl.rkt")))
     (define macro-shell
       (normalized (build-path macros-directory "lazy-with-macros.rkt")))
     (define macro-definitions
       (normalized (build-path macros-directory "macros.rkt")))
     (define codec (normalized (build-path runtime-directory "codec.rkt")))
     (define host (normalized (build-path runtime-directory "host.rkt")))
     (define language-expander
       (normalized (build-path language-directory "expander.rkt")))
     (define language-reader
       (normalized (build-path language-directory "reader.rkt")))
     (define effect-files (racket-files-under effects-directory))
     (define macro-files (racket-files-under macros-directory))
     (define runtime-files (racket-files-under runtime-directory))
     (define language-files (racket-files-under language-directory))
     (define runner-files (racket-files-under runner-directory))
     (define repository-files (racket-files-under root))
     (define classifications
       (classify-sources repository-files root))
     (define reader-files (files-in-class classifications 'reader))
     (define test-files (files-in-class classifications 'test))
     (define tooling-files (files-in-class classifications 'tooling))
     (define application-files
       (files-in-class classifications 'application))
     (define production-files
       (append
        (racket-files-under package-info)
        (append-map
         racket-files-under
         (list (build-path root "core")
               effects-directory
               macros-directory
               runtime-directory
               language-directory))))
     (append
      (version-file-violations root)
      (unsafe-repository-path-violations repository-files root)
      (unclassified-repository-source-violations repository-files root)
      (unsafe-production-path-violations production-files root)
      (application-inventory-violations root)
      (append-map (lambda (path)
                    (file-boundary-violations path 'effect root))
                  effect-files)
      (file-boundary-violations macro-shell 'macro-shell root)
      (file-boundary-violations macro-definitions 'macro root)
      (file-boundary-violations codec 'codec root)
      (file-boundary-violations host 'host root)
      (file-boundary-violations language-expander
                                'language-expander
                                root)
      (file-boundary-violations language-reader
                                'language-reader
                                root)
      (file-boundary-violations runner 'runner root)
      (file-boundary-violations source-reader 'source-reader root)
      (file-boundary-violations session 'session root)
      (file-boundary-violations source-file 'source-file root)
      (file-boundary-violations diagnostics 'diagnostics root)
      (file-boundary-violations repl 'repl root)
      (file-boundary-violations shell-output 'shell-output root)
      (file-boundary-violations editor-output 'editor-output root)
      (file-boundary-violations editor 'editor root)
      (file-boundary-violations history 'history root)
      (file-boundary-violations package-info 'package-info root)
      (append-map (lambda (path)
                    (file-boundary-violations path 'reader root))
                  reader-files)
      (append-map (lambda (path)
                    (file-boundary-violations path 'test root))
                  test-files)
      (append-map (lambda (path)
                    (file-boundary-violations path 'tooling root))
                  tooling-files)
      (append-map (lambda (path)
                    (file-boundary-violations path 'application root))
                  application-files)
      (strict-vocabulary-violations codec
                                    root
                                    phase16-codec-vocabulary
                                    'unapproved-codec-identifier)
      (strict-vocabulary-violations host
                                    root
                                    phase16-host-vocabulary
                                    'unapproved-host-identifier)
      (strict-vocabulary-violations macro-definitions
                                    root
                                    macro-vocabulary
                                    'unapproved-macro-identifier)
      (for/list ([path (in-list macro-files)]
                 #:unless (member path
                                  (list macro-shell macro-definitions)
                                  equal?))
        (violation path 'unclassified-macro-module path))
      (for/list ([path (in-list runtime-files)]
                 #:unless (member path (list codec host) equal?))
        (violation path 'unclassified-runtime-module path))
      (for/list ([path (in-list language-files)]
                 #:unless (member path
                                  (list language-expander language-reader)
                                  equal?))
        (violation path 'unclassified-language-module path))
      (for/list ([path (in-list runner-files)]
                 #:unless (member path (list runner source-reader session source-file diagnostics repl shell-output editor-output editor history) equal?))
        (violation path 'unclassified-runner-module path))
      (unclassified-require-specs production-files root)
      (reintroduced-nat-surface-violations production-files root)
      (production-nonproduction-imports production-files root)
      (unauthorized-codec-imports production-files root codec host)
      (unauthorized-host-imports production-files
                                 root
                                 host
                                 language-expander)
      (unauthorized-host-capability-imports production-files root host)
      (privileged-identifiers-outside-host production-files root host)
      (unauthorized-host-surfaces production-files
                                  root
                                  host
                                  language-expander))]))

(module+ main
  (define findings
    (project-boundary-violations default-project-root))
  (cond
    [(null? findings)
     (printf
      "Boundary check passed: all sources inventoried; pure computation, sole host, and closed runner enforced.\n")]
    [else
     (for ([finding (in-list findings)])
       (eprintf "~a: ~a: ~a\n"
                (boundary-violation-path finding)
                (boundary-violation-kind finding)
                (boundary-violation-detail finding)))
     (exit 1)]))
