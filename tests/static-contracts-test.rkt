#lang racket/base
(require rackunit racket/list racket/runtime-path racket/string
         "../runner/static/contracts.rkt" "../runner/static/type-display.rkt"
         "../runner/static/frontend.rkt" "../runner/source-file.rkt" "../lang/static-data.rkt")
(define-runtime-path facade "../lang/expander.rkt")
(define-runtime-path project "..")

(test-case "inventory equals actual public values and each ID comes from its resolved binding"
  (define names
    (parameterize ([current-namespace (make-base-namespace)])
      (dynamic-require facade #f)
      (define-values (variables transformers) (module->exports facade))
      (sort (remove-duplicates
             (for*/list ([groups (in-list (list variables transformers))]
                         [group (in-list groups)] #:when (equal? (car group) 0)
                         [entry (in-list (cdr group))]
                         #:unless (memq (car entry) '(#%top #%app #%datum #%module-begin def lambda rec let list cond)))
               (car entry))) symbol<?)))
  (check-equal? (sort (map library-contract-id catalog) symbol<?) names)
  (define view
    (prepare-source (validated-source 'catalog.attl (string-join (map symbol->string names) " ") 2 0 17)
                    #:analysis? #t))
  (check-equal? (map source-node-kind (source-view-expressions view)) (make-list (length names) 'builtin))
  (check-equal? (map source-node-data (source-view-expressions view)) names))

(test-case "audited seeds have independently specified types and partial-result policy"
  (for ([row '((add "Rat -> Rat -> Rat") (sub "Rat -> Rat -> Rat") (mult "Rat -> Rat -> Rat")
               (div "Rat -> Rat -> Result(Rat)") (is-zero "Rat -> Bool")
               (TRUE "Bool") (FALSE "Bool") (not "Bool -> Bool")
               (if "forall a. Bool -> a -> a -> a")
               (is-ok "forall a:data. Result(a) -> Bool") (error-to-string "Error -> String"))])
    (define entry (contract-ref (car row)))
    (check-eq? (library-contract-status entry) 'complete)
    (check-equal? (scheme->string (library-contract-signature entry)) (cadr row)))
  (define unwrap (contract-ref 'unwrap-ok))
  (check-eq? (library-contract-status unwrap) 'partial)
  (check-eq? (library-contract-gap-code unwrap) 'UNREPRESENTED_ERROR_ALTERNATIVE)
  (check-equal? (library-contract-arity unwrap) 1)
  (check-not-false (member '("core/result.rkt" raw-result-unwrap-ok) (library-contract-implementations unwrap)))
  (check-equal? (validate-catalog catalog) catalog)
  (check-exn #rx"pending or malformed"
             (lambda () (validate-catalog (cons (struct-copy library-contract (car catalog) [status 'pending])
                                                (cdr catalog)))))
  (check-exn #rx"unregistered" (lambda () (contract-ref 'not-a-language-binding)))
  (check-exn #rx"invalid contract inventory" (lambda () (validate-catalog (cons (car catalog) catalog)))))

(test-case "every audited locator names a real implementation and a focused test"
  (for ([entry (in-list catalog)] #:unless (eq? (library-contract-status entry) 'pending))
    (for ([locator (in-list (library-contract-implementations entry))])
      (define module
        (call-with-input-file (build-path project (car locator))
          (lambda (input) (parameterize ([read-accept-reader #t]) (read input)))))
      (define definitions
        (for/list ([form (in-list (cdr (cadddr module)))]
                   #:when (and (pair? form) (memq (car form) '(def define))))
          (if (pair? (cadr form)) (caadr form) (cadr form))))
      (define name (cadr locator))
      (check-not-false (memq (if (string? name) (string->symbol name) name) definitions)
                       (format "~s" locator)))
    (for ([test (in-list (library-contract-tests entry))])
      (check-true (file-exists? (build-path project test)) test))))
