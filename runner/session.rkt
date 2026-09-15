#lang racket/base

;; Private checked module execution. Source carries no runner lexical context.
(require racket/promise racket/runtime-path "source-reader.rkt" "source-file.rkt"
         "../readers/string.rkt")

(provide (struct-out session) (struct-out checked-entry) (struct-out session-exit)
         open-session close-session prepare-entry demand-entry render-result evaluate-entry
         session-names session-completion-names reset-session! load-source-file)

(define-runtime-module-path-index language-index "../lang/expander.rkt")
(define language-origin (variable-reference->namespace (#%variable-reference)))
(define language-name
  (resolved-module-path-name (module-path-index-resolve language-index)))
(define language-reference
  (if (path? language-name)
      `(file ,(path->string language-name))
      `(quote ,language-name)))
;; Declaration transfer needs instantiated cross-phase-persistent dependencies.
;; Initialize the fixed embedded graph once, outside all session custodians.
;; Its unused host registry opens no resources and is never attached to a session.
(when (symbol? language-name)
  (parameterize ([current-namespace language-origin])
    (dynamic-require language-reference #f)))
(struct session ([namespace #:mutable] [custodian #:mutable] input output error
                 [bindings #:mutable]) #:transparent)
(struct checked-entry (module-name definitions result-names) #:transparent)
;; Exit is an unwind request, not an exn:fail that the host could turn into Err.
;; The outer launcher honors its status after editor/session cleanup has run.
(struct session-exit (status) #:transparent)

(define (initialize-session owner)
  (parameterize ([current-custodian owner])
    (define namespace (make-base-namespace))
    (parameterize ([current-namespace namespace])
      ;; Transfer declarations, with Racket's shared persistent primitives;
      ;; every session still instantiates its own ordinary modules and host state.
      (when (symbol? language-name)
        (namespace-attach-module-declaration language-origin language-reference)
        ;; Racket's module-begin inserts this require while expanding each entry.
        ;; Transfer its embedded public-name mapping into this fresh registry too.
        (namespace-attach-module-declaration language-origin 'racket/runtime-config))
      ;; A new instance initializes the shared host before any entry work.
      (dynamic-require language-reference #f))
    namespace))

(define (open-session #:input [input (current-input-port)]
                      #:output [output (current-output-port)]
                      #:error [error (current-error-port)])
  (define owner (make-custodian))
  (with-handlers ([exn? (lambda (failure)
                         (custodian-shutdown-all owner)
                         (raise failure))])
    (session (initialize-session owner) owner input output error (hasheq))))

(define (close-session current)
  (custodian-shutdown-all (session-custodian current))
  (parameterize-break #f
    (set-session-namespace! current #f)
    (set-session-bindings! current (hasheq))))

;; Prepare replacement state before discarding the old session. The shell owns
;; the same ports throughout; a cancelled reset releases only its candidate.
(define (reset-session! current)
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
   (lambda () (custodian-shutdown-all (if installed? previous owner)))))

(define (prepare-entry current parsed [imports (hash-values (session-bindings current))]
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
    ;; Expand the whole entry before instantiation or any result demand.
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
                   (filter (lambda (name) (memq name names)) result-names))))

(define (demand-entry current entry [consume void])
  (parameterize ([current-namespace (session-namespace current)])
    (for ([name (in-list (checked-entry-result-names entry))])
      (define result
        (force (dynamic-require `(quote ,(checked-entry-module-name entry)) name)))
      (consume result))))

;; Observe the same computed value through the language's pure renderer. The
;; String reader is the existing observation boundary, never the runtime codec.
(define (render-result current result)
  (parameterize ([current-namespace (session-namespace current)])
    (define renderer (force (dynamic-require language-reference 'value-to-string)))
    (string-value->string (renderer result))))

;; Keep only visible binding identities. Each compiled module captures its own
;; imports; replacing this shell map cannot mutate an earlier language closure.
(define (evaluate-entry current parsed [consume void]
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
       ;; No break may separate publication from retaining the entry's resources.
       (parameterize-break #f
         (set-session-bindings! current candidate)
         (set! successful? #t))))
   (lambda () (unless successful? (custodian-shutdown-all child)))))

(define (session-names current)
  (sort (hash-keys (session-bindings current)) symbol<?))

;; Export metadata supplies names without demanding language or user values.
;; Only module scaffolding is excluded; every committed identifier is retained.
(define (session-completion-names current)
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
    (sort (hash-keys names) symbol<?)))

;; The validator supplies the body from its single read. Loads have fresh module
;; identities, only public imports, and ordinary file demand without observation.
;; Validation/read failures are data; execution failures unwind the shared entry.
(define (load-source-file current source-name #:on-phase [on-phase void])
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
                         (source-buffer-line parsed) (source-buffer-column parsed)))]))
