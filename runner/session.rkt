#lang racket/base

;; Private checked module execution. Source carries no runner lexical context.
(require racket/promise racket/runtime-path "source-reader.rkt"
         "../readers/string.rkt")

(provide (struct-out session) (struct-out checked-entry)
         open-session close-session prepare-entry demand-entry render-result evaluate-entry
         session-names)

(define-runtime-path language-path "../lang/expander.rkt")
(struct session (namespace custodian [bindings #:mutable]) #:transparent)
(struct checked-entry (module-name definitions result-names) #:transparent)

(define (open-session)
  (define owner (make-custodian))
  (with-handlers ([exn? (lambda (failure)
                         (custodian-shutdown-all owner)
                         (raise failure))])
    (parameterize ([current-custodian owner])
      (define namespace (make-base-namespace))
      (parameterize ([current-namespace namespace])
        ;; A new instance initializes the shared host before any entry work.
        (dynamic-require language-path #f))
      (session namespace owner (hasheq)))))

(define (close-session current)
  (custodian-shutdown-all (session-custodian current)))

(define (prepare-entry current parsed [imports (hash-values (session-bindings current))])
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
    (datum->syntax #f `(module ,name (file ,(path->string language-path)) ,body)))
  (parameterize ([current-namespace (session-namespace current)]
                 [current-custodian (session-custodian current)])
    ;; Expand the whole entry before instantiation or any result demand.
    (define expanded (expand module-source))
    (eval expanded)
    (define path `(quote ,name))
    (define-values (exports syntax-exports) (module->exports path))
    (define phase-zero (assoc 0 exports))
    (define names (if phase-zero (map car (cdr phase-zero)) '()))
    (dynamic-require path #f)
    (checked-entry name
                   (filter (lambda (name) (not (memq name result-names))) names)
                   (filter (lambda (name) (memq name names)) result-names))))

(define (demand-entry current entry [consume void])
  (parameterize ([current-namespace (session-namespace current)]
                 [current-custodian (session-custodian current)])
    (for ([name (in-list (checked-entry-result-names entry))])
      (define result
        (force (dynamic-require `(quote ,(checked-entry-module-name entry)) name)))
      (consume result))))

;; Observe the same computed value through the language's pure renderer. The
;; String reader is the existing observation boundary, never the runtime codec.
(define (render-result current result)
  (parameterize ([current-namespace (session-namespace current)]
                 [current-custodian (session-custodian current)])
    (define renderer (force (dynamic-require language-path 'value-to-string)))
    (string-value->string (renderer result))))

;; Keep only visible binding identities. Each compiled module captures its own
;; imports; replacing this shell map cannot mutate an earlier language closure.
(define (evaluate-entry current parsed [consume void])
  (define entry (prepare-entry current parsed))
  (define candidate
    (for/fold ([bindings (session-bindings current)])
              ([name (in-list (checked-entry-definitions entry))])
      (hash-set bindings name (list name (checked-entry-module-name entry) name))))
  (demand-entry current entry consume)
  ;; The candidate and all fallible work are complete before this one swap.
  (parameterize-break #f (set-session-bindings! current candidate)))

(define (session-names current)
  (sort (hash-keys (session-bindings current)) symbol<?))
