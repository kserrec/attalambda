#lang racket/base

;; Pure string construction over a validated whole-file summary. Source text is
;; never evaluated or rendered by an object-language operation.
(require racket/list racket/string "../../lang/static-data.rkt" "analysis.rkt"
         "coverage.rkt" "inference.rkt" "proof.rkt" "type-display.rkt")
(provide render-report)
(define (safe text)
  (apply string-append
         (for/list ([character (in-string text)])
           (if (memq (char-general-category character) '(cc cf zl zp))
               (string-append "\\u{" (number->string (char->integer character) 16) "}")
               (string character)))))
(define (name-text name) (safe (format "~s" name)))
(define (location-text location)
  (format "~a:~a:~a" (safe (or (source-location-source location) "source"))
          (or (source-location-line location) "?") (or (source-location-column location) "?")))
(define (render-report summary source-name)
  (define result (check-summary-analysis summary))
  (define view (analysis-view result))
  (define definitions (analysis-definitions result))
  (define by-id
    (for/hasheqv ([item (in-list definitions)])
      (values (source-binding-id (definition-result-binding item)) item)))
  (define (binding-name id)
    (name-text (source-binding-name (definition-result-binding (hash-ref by-id id)))))
  (define (path-text path) (string-join (map binding-name path) " -> "))
  (define (problem-text issue)
    (define prefix (safe (problem-detail issue)))
    (case (problem-code issue)
      [(TYPE_CONFLICT)
       (define types (types->strings (list (problem-expected issue) (problem-actual issue))))
       (format "~a expects ~a; this expression has type ~a." prefix (car types) (cadr types))]
      [(RECURSIVE_TYPE_REQUIRED)
       "The constraints require a type to contain itself. V1 does not support recursive types; ordinary AttaLambda is unchanged."]
      [(UNSUPPORTED_DATA_DOMAIN)
       (string-append prefix ": this use is outside the supported canonical non-Error data domain.")]
      [else prefix]))
  (define lambdas (filter (lambda (entry) (eq? (cadr entry) 'lambda)) (source-view-registry view)))
  (define (enclosing-lambda location)
    (define position (source-location-position location))
    (define candidates
      (filter (lambda (entry)
                (define origin (caddr entry))
                (define start (source-location-position origin))
                (define span (source-location-span origin))
                (and position start span (<= start position) (< position (+ start span)))) lambdas))
    (and (pair? candidates)
         (caddr (argmin (lambda (entry) (source-location-span (caddr entry))) candidates))))
  (define (diagnostic issue)
    (define location (problem-location issue))
    (define nested (enclosing-lambda location))
    (string-append
     (format "~a [~a]~a\n" (location-text location) (problem-code issue)
             (if (problem-owner issue) (string-append " in " (binding-name (problem-owner issue))) ""))
     (if nested
         (format "  anonymous lambda at ~a (source span ~a characters)\n"
                 (location-text nested) (source-location-span nested)) "")
     "  " (problem-text issue) "\n"))
  (define (count-line label checked total)
    (format "~a: ~a/~a fully checked (~a)\n" label checked total (coverage-percentage checked total)))
  (define problems (check-summary-problems summary))
  (define incomplete
    (filter (lambda (item) (not (eq? (proof-status (definition-result-proof item)) 'established))) definitions))
  (define inferred (filter definition-result-signature definitions))
  (define (primary path)
    (car (proof-problems (definition-result-proof (hash-ref by-id (last path))))))
  (define (explanation path)
    (define issue (primary path))
    (format "~a: [~a] at ~a" (path-text path) (problem-code issue) (location-text (problem-location issue))))
  (define top-level-dependencies
    (for/list ([node (in-list (source-view-expressions view))]
               [item (in-list (analysis-expressions result))]
               #:when (pair? (proof-dependencies (judgment-proof item))))
      (define id (car (sort (proof-dependencies (judgment-proof item)) <)))
      (format "  ~a depends on ~a\n" (location-text (source-node-location node))
              (explanation (hash-ref (check-summary-paths summary) id)))))
  (string-append
   "Static type check: " (case (check-summary-verdict summary) [(full) "FULL PASS"] [(fail) "FAIL"] [(partial) "PARTIAL"]
                          [else (error 'static-report "invalid verdict")]) "\n"
   "Scope: " (safe source-name) "; all source definitions and expressions\n"
   (count-line "Definitions" (check-summary-definitions-checked summary) (check-summary-definitions-total summary))
   (count-line "Expressions" (check-summary-expressions-checked summary) (check-summary-expressions-total summary))
   (format "Unproved regions: ~a\nType conflicts: ~a\n"
           (count (lambda (item) (not (eq? (problem-code item) 'TYPE_CONFLICT))) problems)
           (count (lambda (item) (eq? (problem-code item) 'TYPE_CONFLICT)) problems))
   (if (and (zero? (check-summary-definitions-total summary)) (zero? (check-summary-expressions-total summary)))
       "This source contains no definitions or expressions; the pass is vacuous.\n" "")
   (if (null? inferred) ""
       (string-append "\nInferred definitions:\n"
                      (apply string-append
                             (map (lambda (item)
                                    (format "  ~a : ~a\n"
                                            (name-text (source-binding-name (definition-result-binding item)))
                                            (scheme->string (definition-result-signature item)))) inferred))))
   (if (null? problems) "" (string-append "\nDiagnostics (one-based lines, zero-based columns):\n"
                                          (apply string-append (map diagnostic problems))))
   (if (null? incomplete) ""
       (string-append "\nIncomplete definitions (one reason path each):\n"
                      (apply string-append
                             (map (lambda (item)
                                    (string-append "  "
                                                   (explanation (hash-ref (check-summary-paths summary)
                                                                          (source-binding-id (definition-result-binding item))))
                                                   "\n")) incomplete))))
   (if (null? top-level-dependencies) ""
       (string-append "\nDependent top-level expressions:\n" (apply string-append top-level-dependencies)))
   "\nTrusted basis: built-in contracts, rec lowering, and host/codec contracts.\n"
   "Coverage counts source obligations; it does not certify the trusted implementations.\n"
   "This does not prove termination or successful external operations, or exclude deliberate Error/Result Err values.\n"))
