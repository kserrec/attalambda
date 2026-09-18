#lang racket/base

;; One private inventory, populated in dependency order. Partial schemes contain
;; audited input obligations and an explanatory success hint ONLY. Their arity
;; is the number of inputs before the unrepresented result; inference must never
;; publish the hint as a verified output. Pending entries are internal failures.
(require racket/list "types.rkt")
(provide (struct-out library-contract) catalog contract-ref validate-catalog)
(struct library-contract (id status signature arity gap-code reason implementations tests) #:transparent)
(define rat (base-type 'Rat))
(define bool (base-type 'Bool))
(define string (base-type 'String))
(define error-type (base-type 'Error))
(define a (type-variable 0))
(define (entry id parameters result implementations tests
               [variables '()] [restricted '()] [gap-code #f] [reason #f])
  (library-contract id (if gap-code 'partial 'complete)
                    (scheme variables (foldr arrow-type result parameters) restricted)
                    (length parameters) gap-code reason implementations tests))

(define catalog
  (append
   (for/list ([row '((succ typed-rat-succ) (add typed-rat-add) (sub typed-rat-sub)
                    (mult typed-rat-mult) (eq typed-rat-equal) (lt typed-rat-less)
                    (lte typed-rat-less-equal) (gt typed-rat-greater) (gte typed-rat-greater-equal)
                    (is-zero typed-rat-is-zero))])
     (define id (car row))
     (entry id (if (memq id '(succ is-zero)) (list rat) (list rat rat))
            (if (memq id '(eq lt lte gt gte is-zero)) bool rat)
            (list (list "core/typed-rat.rkt" (cadr row)) (list "core/rat.rkt" 'raw-make-rat))
            '("tests/typed-rat-test.rkt" "tests/rat-test.rkt")))
   (for/list ([row '((TRUE TRUE) (FALSE FALSE) (not typed-not) (and typed-and)
                    (or typed-or) (xor typed-xor))])
     (define id (car row))
     (entry id (cond [(memq id '(TRUE FALSE)) '()] [(eq? id 'not) (list bool)] [else (list bool bool)]) bool
            (list (list "core/typed-logic.rkt" (cadr row))) '("tests/typed-logic-test.rkt")))
   (list
    (entry 'if (list bool a a) a '(("core/typed-logic.rkt" typed-if))
           '("tests/typed-logic-test.rkt" "tests/language-test.rkt") '(0))
    (entry 'div (list rat rat) (result-type rat)
           '(("core/typed-rat.rkt" typed-rat-div) ("core/rat.rkt" raw-rat-div))
           '("tests/typed-rat-test.rkt" "tests/result-test.rkt"))
    (entry 'is-ok (list (result-type a)) bool '(("core/result.rkt" typed-result-is-ok))
           '("tests/result-test.rkt") '(0) '(0))
    (entry 'unwrap-ok (list (result-type a)) a
           '(("core/result.rkt" typed-result-unwrap-ok) ("core/result.rkt" raw-result-unwrap-ok))
           '("tests/result-test.rkt") '(0) '(0) 'UNREPRESENTED_ERROR_ALTERNATIVE
           "WrongResultVariant may return Error; V1 does not refine Result variants.")
    (entry 'error-to-string (list error-type) string '(("core/to-string.rkt" typed-error-to-string))
           '("tests/to-string-test.rkt" "tests/render-error-test.rkt")))
   ;; Inert intermediate labels, verified against actual resolved facade exports.
   ;; Phase 3 replaces every pending entry before the public command exists.
   (for/list ([id '("EMPTY-STRING" "HTTP-STATUS-BAD-REQUEST" "HTTP-STATUS-INTERNAL-SERVER-ERROR"
                   "HTTP-STATUS-NOT-FOUND" "HTTP-STATUS-OK" "NIL" "NONE" "UNIT" "abs" "all?" "any?" "append"
                   "bool-to-string" "byte-eq" "byte-gt" "byte-gte" "byte-lt" "byte-lte" "byte-to-string"
                   "byte-value" "bytes-to-string" "char-eq" "char-gt" "char-gte" "char-lt" "char-lte"
                   "char-to-string" "concat" "cons" "contains?" "drop" "drop-while" "exit" "exp" "filter" "find"
                   "find-index" "flatten" "floor" "head" "host" "is-err" "is-nil" "is-none" "is-nonnegative-whole"
                   "is-some" "is-whole" "len" "list-to-string" "make-byte" "make-char" "make-err"
                   "make-http-path-handler" "make-http-serve-one" "make-http-server" "make-map" "make-ok"
                   "make-string" "map" "map-contains?" "map-empty?" "map-lookup" "map-remove" "map-set" "map-size"
                   "map-to-string" "neg" "nth" "option-case" "option-to-string" "parse-http-request" "print" "range"
                   "rat-to-string" "read-file" "read-line" "recip" "reduce" "render-http-response" "repeat"
                   "result-to-string" "reverse" "some" "stdout" "string-append" "string-contains?" "string-empty?"
                   "string-eq" "string-head" "string-length" "string-prefix?" "string-tail" "string-to-bytes"
                   "string-to-string" "tail" "take" "take-while" "tcp-accept" "tcp-close" "tcp-connect" "tcp-listen"
                   "tcp-read" "tcp-write" "unit-to-string" "unwrap-err" "value-to-string" "write-file" "zip")])
     (library-contract (string->symbol id) 'pending #f 0 #f "Pending Phase 3 audit." '() '()))))

(define (contract-ref id)
  (define found (findf (lambda (entry) (eq? id (library-contract-id entry))) catalog))
  (unless found (error 'static-contracts "unregistered resolved builtin"))
  (when (eq? (library-contract-status found) 'pending)
    (error 'static-contracts "pending builtin audit"))
  found)

(define (validate-catalog entries)
  (unless (and (list? entries) (andmap library-contract? entries)
               (= (length entries) (length (remove-duplicates (map library-contract-id entries)))))
    (error 'static-contracts "invalid contract inventory"))
  (for ([entry (in-list entries)])
    (unless (and (symbol? (library-contract-id entry))
                 (memq (library-contract-status entry) '(complete partial))
                 (scheme? (library-contract-signature entry))
                 (exact-nonnegative-integer? (library-contract-arity entry))
                 (pair? (library-contract-implementations entry))
                 (pair? (library-contract-tests entry))
                 (if (eq? (library-contract-status entry) 'partial)
                     (and (memq (library-contract-gap-code entry)
                                '(UNREPRESENTED_ERROR_ALTERNATIVE UNSUPPORTED_CONTRACT))
                          (string? (library-contract-reason entry)))
                     (and (not (library-contract-gap-code entry)) (not (library-contract-reason entry)))))
      (error 'static-contracts "pending or malformed builtin contract")))
  entries)
