#lang racket/base

(require rackunit
         racket/file
         racket/list
         racket/path
         racket/runtime-path
         "../tooling/check-boundaries.rkt")

(define-runtime-path project-root "..")

(define clean-macro-shell-datum
  '(module lazy-with-macros racket/base
     (#%module-begin
      (require lazy/lazy)
      (provide (all-from-out lazy/lazy)
               #%module-begin
               #%app
               #%datum
               #%top))))

(define clean-macro-datum
  '(module macros lazy
     (#%module-begin
      (require (for-syntax racket/base))
      (provide def lambda-let define-function-name))))

(define (write-datum path datum)
  (call-with-output-file path
    #:exists 'truncate
    (lambda (output)
      (write datum output))))

(define (write-exact-bytes path content)
  (call-with-output-file path
    #:exists 'truncate
    #:mode 'binary
    (lambda (output)
      (write-bytes content output))))

(define (read-datum path)
  (call-with-input-file path
    (lambda (input)
      (parameterize ([read-accept-reader #t]
                     [current-load-relative-directory (path-only path)])
        (read input)))))

(define (append-module-form datum form)
  (list 'module
        (cadr datum)
        (caddr datum)
        (append (cadddr datum) (list form))))

(define (replace-package-version datum package-version)
  (list 'module
        (cadr datum)
        (caddr datum)
        (cons
         '#%module-begin
         (map (lambda (form)
                (if (and (list? form)
                         (= (length form) 3)
                         (eq? (car form) 'define)
                         (eq? (cadr form) 'version))
                    (list 'define 'version package-version)
                    form))
              (cdr (cadddr datum))))))

(define (replace-datum target replacement datum)
  (cond
    [(equal? datum target) replacement]
    [(pair? datum)
     (cons (replace-datum target replacement (car datum))
           (replace-datum target replacement (cdr datum)))]
    [(vector? datum)
     (list->vector
      (map (lambda (element)
             (replace-datum target replacement element))
           (vector->list datum)))]
    [else datum]))

(define (kinds findings)
  (map boundary-violation-kind findings))

(define (normalized path)
  (simplify-path (path->complete-path path) #f))

(define (observe-source-operations watched relevant? procedure)
  (define normalized-watched
    (map normalized watched))
  (define operation-count 0)
  (define guard
    (make-security-guard
     (current-security-guard)
     (lambda (who path permissions)
       (when (and (relevant? permissions)
                  (member (normalized path)
                          normalized-watched
                          equal?))
         (set! operation-count (add1 operation-count))))
     (lambda (who host-name port mode)
       (void))))
  (define result
    (parameterize ([current-security-guard guard])
      (procedure)))
  (values result operation-count))

(define (observe-source-reads watched procedure)
  (observe-source-operations watched
                             (lambda (permissions)
                               (memq 'read permissions))
                             procedure))

(define (observe-source-accesses watched procedure)
  (observe-source-operations
   watched
   (lambda (permissions)
     (or (memq 'exists permissions)
         (memq 'read permissions)))
   procedure))

(define (check-rejected-root-without-traversal unsafe-root)
  (define-values (findings access-count)
    (observe-source-accesses
     (list (build-path unsafe-root "effects")
           (build-path unsafe-root "macros")
           (build-path unsafe-root "runtime")
           (build-path unsafe-root "core"))
     (lambda ()
       (project-boundary-violations unsafe-root))))
  (check-equal? (kinds findings) '(disallowed-boundary-root))
  (check-equal? access-count 0))

(define (temporary-project procedure)
  (define root
    (make-temporary-file "attalambda-boundary-~a"
                         'directory
                         (current-directory)))
  (dynamic-wind
    (lambda ()
      (for ([directory
             (in-list '("core" "effects" "macros" "runtime" "lang"
                        "readers" "tests" "tooling" "examples"
                        "runner"))])
        (make-directory (build-path root directory)))
      (copy-file (build-path project-root "lang" "expander.rkt")
                 (build-path root "lang" "expander.rkt"))
      (copy-file (build-path project-root "lang" "reader.rkt")
                 (build-path root "lang" "reader.rkt"))
      (copy-file (build-path project-root "info.rkt")
                 (build-path root "info.rkt"))
      (copy-file (build-path project-root "VERSION")
                 (build-path root "VERSION"))
      (copy-file (build-path project-root "runner" "attalambda.rkt")
                 (build-path root "runner" "attalambda.rkt"))
      (for ([name (in-list '("hello.attl"
                             "stdout.attl"
                             "file-round-trip.attl"
                             "http-server.attl"
                             "foundations.attl"))])
        (copy-file (build-path project-root "examples" name)
                   (build-path root "examples" name)))
      (write-datum
       (build-path root "macros" "lazy-with-macros.rkt")
       clean-macro-shell-datum)
      (write-datum
       (build-path root "macros" "macros.rkt")
       clean-macro-datum)
      (write-datum
       (build-path root "core" "dependency.rkt")
       '(module dependency racket/base
          (#%module-begin
           (provide identity))))
      (write-datum
       (build-path root "effects" "protocol.rkt")
       '(module protocol "../macros/lazy-with-macros.rkt"
          (#%module-begin
           (require "../macros/macros.rkt"
                    (only-in "../core/dependency.rkt" identity))
           (provide make-host-bridge)
           (def make-host-bridge value =
             (identity value)))))
      (write-datum
       (build-path root "runtime" "codec.rkt")
       '(module codec racket/base
          (#%module-begin
           (provide (struct-out codec-failure)
                    object-list->host-list
                    host-list->object-list
                    object-string->bytes
                    bytes->object-string
                    object-byte-list->bytes
                    bytes->object-byte-list
                    exact->object-rat
                    object-rat->exact
                    object-unit
                    object-ok
                    object-err))))
      (write-datum
       (build-path root "runtime" "host.rkt")
       '(module host racket/base
          (#%module-begin
           (require (only-in "../effects/protocol.rkt" make-host-bridge)
                    (only-in "codec.rkt" object-ok))
           (provide host)
           (define (host request) request)))))
    (lambda () (procedure root))
    (lambda () (delete-directory/files root))))

(check-equal? (project-boundary-violations project-root)
              '())

(define project-classifications
  (project-source-classifications project-root))

(check-equal?
 (sort (remove-duplicates
        (map source-classification-class project-classifications))
       symbol<?)
 '(application codec effect host language-expander language-reader macro
   macro-shell package-info pure-core reader runner test tooling))

(check-equal?
 (count (lambda (classification)
          (eq? (source-classification-class classification)
               'application))
        project-classifications)
 5)

(check-equal?
 (count (lambda (classification)
          (eq? (source-classification-class classification)
               'reader))
        project-classifications)
 13)

(temporary-project
 (lambda (root)
   (check-equal? (project-boundary-violations root) '())

   ;; Every Racket source is classified. Tests and tooling may use normal host
   ;; facilities, but production code may never depend on either support
   ;; class or on readers/applications.
   (define rogue-source (build-path root "rogue.rkt"))
   (write-datum
    rogue-source
    '(module rogue racket/base
       (#%module-begin
        (provide value)
        (define value 1))))
   (check-not-false
    (member 'unclassified-repository-source
            (kinds (project-boundary-violations root))))
   (delete-file rogue-source)

   (define support-test
     (build-path root "tests" "host-support.rkt"))
   (write-datum
    support-test
    '(module host-support racket/base
       (#%module-begin
        (require racket/file)
        (provide observe)
        (define observe file->bytes))))
   (check-equal? (project-boundary-violations root) '())
   (delete-file support-test)

   (define nonlanguage-application
     (build-path root "examples" "not-a-language-program.rkt"))
   (write-datum
    nonlanguage-application
    '(module not-a-language-program racket/base
       (#%module-begin
        (provide value)
        (define value 1))))
   (check-equal?
    (kinds
     (file-boundary-violations nonlanguage-application
                               'application
                               root))
    '(invalid-application-extension unexpected-application-language))
   (delete-file nonlanguage-application)

   ;; The official application inventory is exact and uses only `.attl`.
   (define unknown-application
     (build-path root "examples" "unknown.attl"))
   (write-exact-bytes
    unknown-application
    #"#lang attalambda\n\n(stdout \"unknown\")\n")
   (check-not-false
    (member 'unknown-application-source
            (kinds (project-boundary-violations root))))
   (delete-file unknown-application)

   (define unknown-application-input
     (build-path root "examples" "notes.txt"))
   (write-exact-bytes unknown-application-input #"not an AttaLambda source\n")
   (check-not-false
    (member 'unknown-application-source
            (kinds (project-boundary-violations root))))
   (delete-file unknown-application-input)

   ;; A canonical application symlink is rejected from link metadata without
   ;; reading the linked source target.
   (define canonical-application
     (build-path root "examples" "hello.attl"))
   (define saved-canonical-application
     (build-path root "examples" "hello.attl.backup"))
   (rename-file-or-directory canonical-application
                             saved-canonical-application)
   (make-directory canonical-application)
   (check-not-false
    (member 'disallowed-canonical-application
            (kinds (project-boundary-violations root))))
   (delete-directory canonical-application)
   (rename-file-or-directory saved-canonical-application
                             canonical-application)

   (define application-target
     (make-temporary-file "attalambda-application-target-~a.attl"
                          #f
                          (path-only root)))
   (write-exact-bytes
    application-target
    #"#lang attalambda\n\n(stdout \"target\")\n")
   (rename-file-or-directory canonical-application
                             saved-canonical-application)
   (make-file-or-directory-link application-target
                                canonical-application)
   (define-values (application-link-findings application-target-reads)
     (observe-source-reads
      (list application-target)
      (lambda ()
        (project-boundary-violations root))))
   (check-not-false
    (member 'disallowed-repository-source-path
            (kinds application-link-findings)))
   (check-equal? application-target-reads 0)
   (delete-file canonical-application)
   (rename-file-or-directory saved-canonical-application
                             canonical-application)
   (delete-file application-target)
   (check-equal? (project-boundary-violations root) '())

   (define reader-source
     (build-path root "readers" "observer.rkt"))
   (write-datum
    reader-source
    '(module observer racket/base
       (#%module-begin
        (require racket/promise
                 "../core/dependency.rkt")
        (provide bool->boolean)
        (define (bool->boolean value) (force value)))))
   (check-equal?
    (file-boundary-violations reader-source 'reader root)
    '())

   (write-datum
    reader-source
    '(module observer racket/base
       (#%module-begin
        (require "../runtime/host.rkt")
        (provide bool->boolean)
        (define bool->boolean host))))
   (check-not-false
    (member 'disallowed-reader-import
            (kinds
             (file-boundary-violations reader-source 'reader root))))

   (write-datum
    reader-source
    '(module observer racket/base
       (#%module-begin
        (provide bool->boolean)
        (define (bool->boolean value)
          (call-with-output-file value values)))))
   (check-not-false
    (member 'forbidden-reader-capability
            (kinds
             (file-boundary-violations reader-source 'reader root))))

   (write-datum
    reader-source
    '(module observer racket/base
       (#%module-begin
        (provide bool->boolean)
        (define (bool->boolean value) (exit value)))))
   (check-not-false
    (member 'forbidden-reader-capability
            (kinds
             (file-boundary-violations reader-source 'reader root))))

   (write-datum
    reader-source
    '(module observer racket/base
       (#%module-begin
        (require racket/promise)
        (provide bool->boolean)
        (define (bool->boolean value) (force value)))))
   (define dependency-source
     (build-path root "core" "dependency.rkt"))
   (define clean-dependency-datum
     (read-datum dependency-source))
   (for ([support-directory
          (in-list '("readers" "tests" "tooling" "examples" "runner"))])
     (write-datum
      dependency-source
      `(module dependency racket/base
         (#%module-begin
          (require ,(format "../~a/support.rkt" support-directory))
          (provide identity)
          (define (identity value) value))))
     (check-not-false
      (member 'production-imports-nonproduction
              (kinds (project-boundary-violations root)))))

   (write-datum
    dependency-source
    '(module dependency racket/base
       (#%module-begin
        (provide identity)
        (define (identity value)
          (current-output-port)))))
   (check-not-false
    (member 'privileged-identifier-outside-host
            (kinds (project-boundary-violations root))))
   (write-datum dependency-source clean-dependency-datum)
   (delete-file reader-source)
   (check-equal? (project-boundary-violations root) '())

   ;; The authorization anchor is checked before project discovery. Neither a
   ;; symlink supplied as the root nor one in an ancestor component can make
   ;; the checker traverse the linked project tree.
   (define root-link (build-path root "linked-project-root"))
   (make-file-or-directory-link root root-link)
   (check-rejected-root-without-traversal root-link)
   (delete-file root-link)

   (define parent-link (build-path root "linked-project-parent"))
   (make-file-or-directory-link (path-only root) parent-link)
   (check-rejected-root-without-traversal
    (build-path parent-link (file-name-from-path root)))
   (delete-file parent-link)

   (define effect (build-path root "effects" "example.rkt"))
   (define (check-effect datum expected)
     (write-datum effect datum)
     (check-equal? (kinds (file-boundary-violations effect 'effect root))
                   expected))

   (check-effect
    '(module example "../macros/lazy-with-macros.rkt"
       (#%module-begin
        (require "../macros/macros.rkt"
                 (only-in "../core/dependency.rkt" identity))
        (provide use)
        (def use value =
          (identity value))))
    '())

   ;; An unknown Lazy Racket binding cannot bypass the gate merely because it
   ;; was omitted from a blacklist.
   (check-effect
    '(module example "../macros/lazy-with-macros.rkt"
       (#%module-begin
        (require "../macros/macros.rkt")
        (provide use)
        (def use value =
          (current-seconds value))))
   '(unapproved-effect-identifier))

   ;; Phase 17 HTTP computation remains in the same closed pure class. Host
   ;; String, regex, arithmetic, and HTTP-library helpers are each rejected.
   (check-effect
    '(module example "../macros/lazy-with-macros.rkt"
       (#%module-begin
        (require "../macros/macros.rkt")
        (provide use)
        (def use value =
          (string-length value))))
    '(unapproved-effect-identifier))

   ;; Explicit exit grants no native exit authority to the pure wrapper.
   (check-effect
    '(module example "../macros/lazy-with-macros.rkt"
       (#%module-begin
        (require "../macros/macros.rkt")
        (provide use)
        (def use value = (exit value))))
    '(unapproved-effect-identifier))

   (check-effect
    '(module example "../macros/lazy-with-macros.rkt"
       (#%module-begin
        (require "../macros/macros.rkt")
        (provide use)
        (def use value =
          (regexp-match? value))))
    '(unapproved-effect-identifier))

   (check-effect
    '(module example "../macros/lazy-with-macros.rkt"
       (#%module-begin
        (require "../macros/macros.rkt")
        (provide use)
        (def use value =
          (+ value))))
    '(unapproved-effect-identifier))

   (check-effect
    '(module example "../macros/lazy-with-macros.rkt"
       (#%module-begin
        (require "../macros/macros.rkt"
                 net/http-client)
        (provide use)
        (def use value =
          (http-sendrecv value))))
    '(disallowed-effect-import
      unapproved-effect-identifier))

   (check-effect
    '(module example "../macros/lazy-with-macros.rkt"
       (#%module-begin
        (provide current-seconds)))
    '(unapproved-effect-export))

   (check-effect
    '(module example "../macros/lazy-with-macros.rkt"
       (#%module-begin
        (require "../macros/macros.rkt"
                 (only-in "../core/dependency.rkt" identity))
        (provide use)
        (def use value =
          (identity value value))))
    '(non-unary-effect-application))

   (check-effect
    '(module example "../macros/lazy-with-macros.rkt"
       (#%module-begin
        (require "../macros/macros.rkt")
        (provide use)
        (def use value =
          (lambda (left right) left))))
    '(non-unary-effect-lambda))

   (check-effect
    '(module example "../macros/lazy-with-macros.rkt"
       (#%module-begin
        (require "../macros/macros.rkt")
        (provide host)
        (def host request = request)))
    '(forbidden-host-export forbidden-host-definition))

   (check-effect
    '(module example "../macros/lazy-with-macros.rkt"
       (#%module-begin
        (require (only-in "../runtime/codec.rkt" object-ok))
        (provide use)
        (def use value =
          (object-ok value))))
    '(disallowed-effect-import
      unapproved-effect-identifier))

   ;; Filesystem access happens only after import authorization. A rejected
   ;; full import is reported without touching even an ordinary regular
   ;; target's metadata or content.
   (define unapproved-directory (build-path root "unapproved"))
   (define unapproved-target
     (build-path unapproved-directory "plain.rkt"))
   (make-directory unapproved-directory)
   (write-datum
    unapproved-target
    '(module plain racket/base
       (#%module-begin
        (provide external-value))))
   (write-datum
    effect
    '(module example "../macros/lazy-with-macros.rkt"
       (#%module-begin
        (require "../unapproved/plain.rkt")
        (provide use)
        (def use value =
          (external-value value)))))
   (define-values (disallowed-import-findings disallowed-target-accesses)
     (observe-source-accesses
      (list unapproved-target)
      (lambda ()
        (file-boundary-violations effect 'effect root))))
   (check-not-false
    (member 'disallowed-effect-import
            (kinds disallowed-import-findings)))
   (check-equal? disallowed-target-accesses 0)
   (delete-file unapproved-target)
   (delete-directory unapproved-directory)

   (define codec (build-path root "runtime" "candidate-codec.rkt"))
   (define (codec-datum extra)
     `(module codec racket/base
        (#%module-begin
         (provide (struct-out codec-failure)
                  object-list->host-list
                  host-list->object-list
                  object-string->bytes
                  bytes->object-string
                  object-byte-list->bytes
                  bytes->object-byte-list
                  exact->object-rat
                  object-rat->exact
                  object-unit
                  object-ok
                  object-err)
         ,extra)))

   (write-datum codec
                (codec-datum '(define leak (display "effect"))))
   (check-equal?
    (kinds (file-boundary-violations codec 'codec root))
    '(forbidden-codec-capability))

   ;; Deterministic conversion must never terminate the process.
   (write-datum codec
                (codec-datum '(define leak (exit 0))))
   (check-equal?
    (kinds (file-boundary-violations codec 'codec root))
    '(forbidden-codec-capability))

   ;; File conversion remains privileged even after the host gains the
   ;; approved read-file operation.
   (write-datum codec
                (codec-datum '(define leak (file->bytes "path"))))
   (check-equal?
    (kinds (file-boundary-violations codec 'codec root))
    '(forbidden-codec-capability))

   ;; Deterministic conversion never gains network authority.
   (write-datum codec
                (codec-datum '(define leak (tcp-connect "host" 80))))
   (check-equal?
    (kinds (file-boundary-violations codec 'codec root))
    '(forbidden-codec-capability))

   (write-datum codec
                (codec-datum
                 '(define (mutate value)
                    (set-car! value value))))
   (check-equal?
    (kinds (file-boundary-violations codec 'codec root))
    '(forbidden-codec-capability))

   (write-datum codec
                (codec-datum '(define handle-registry '())))
   (check-equal?
    (kinds (file-boundary-violations codec 'codec root))
    '(forbidden-codec-capability))

   (define host-file (build-path root "runtime" "candidate-host.rkt"))
   (define (host-datum provide-form body)
     `(module host racket/base
        (#%module-begin
         (require (only-in "../effects/protocol.rkt" make-host-bridge)
                  (only-in "codec.rkt" object-ok))
         ,provide-form
         (define (host request) ,body))))

   (write-datum host-file
                (host-datum '(provide host) 'request))
   (check-equal? (file-boundary-violations host-file 'host root)
                 '())

   (write-datum host-file
                (host-datum '(provide host) '(exit request)))
   (check-equal? (file-boundary-violations host-file 'host root)
                 '())

   ;; Phase 16 admits exactly the five TCP bindings used by the sole host.
   (write-datum
    host-file
    '(module host racket/base
       (#%module-begin
        (require (only-in racket/tcp
                          tcp-accept
                          tcp-addresses
                          tcp-close
                          tcp-connect
                          tcp-listen)
                 (only-in "../effects/protocol.rkt" make-host-bridge)
                 (only-in "codec.rkt" object-ok))
        (provide host)
        (define (host request) request))))
   (check-equal? (file-boundary-violations host-file 'host root)
                 '())

   (write-datum
    host-file
    '(module host racket/base
       (#%module-begin
        (require racket/tcp
                 (only-in "../effects/protocol.rkt" make-host-bridge)
                 (only-in "codec.rkt" object-ok))
        (provide host)
        (define (host request) request))))
   (check-equal?
    (kinds (file-boundary-violations host-file 'host root))
    '(disallowed-host-import))

   (write-datum host-file
                (host-datum '(provide host leak) 'request))
   (check-equal?
    (kinds (file-boundary-violations host-file 'host root))
    '(invalid-host-export))

   (write-datum host-file
                (host-datum '(provide host) '(eval request)))
   (check-equal?
    (kinds (file-boundary-violations host-file 'host root))
    '(forbidden-host-capability))

   ;; Deletion and broad racket/file imports remain outside the closed host
   ;; capability set.
   (write-datum host-file
                (host-datum '(provide host) '(delete-file request)))
   (check-equal?
    (kinds (file-boundary-violations host-file 'host root))
    '(forbidden-host-capability))

   (write-datum
    host-file
    '(module host racket/base
       (#%module-begin
        (require (only-in racket/file file->bytes directory-list)
                 (only-in "../effects/protocol.rkt" make-host-bridge)
                 (only-in "codec.rkt" object-ok))
        (provide host)
        (define (host request) request))))
   (define broad-file-findings
     (kinds (file-boundary-violations host-file 'host root)))
   (check-not-false (member 'disallowed-host-import broad-file-findings))
   (check-not-false (member 'forbidden-host-capability broad-file-findings))

   ;; The exact runtime vocabularies reject capabilities not covered by a
   ;; finite blacklist, including a clock from racket/base.
   (define production-host (build-path root "runtime" "host.rkt"))
   (write-datum production-host
                (host-datum '(provide host) '(current-seconds)))
   (check-not-false
    (member 'unapproved-host-identifier
            (kinds (project-boundary-violations root))))
   (write-datum
    production-host
    '(module host racket/base
       (#%module-begin
        (require (only-in "../effects/protocol.rkt" make-host-bridge)
                 (only-in "codec.rkt" object-ok))
        (provide host)
        (define (host request) request))))

   ;; Project-wide scanning catches a second production importer of the
   ;; internal codec even when its own module class also rejects that import.
   (write-datum
    effect
    '(module example "../macros/lazy-with-macros.rkt"
       (#%module-begin
        (require (only-in "../runtime/codec.rkt" object-ok))
        (provide use)
        (def use value =
          (object-ok value)))))
   (check-not-false
    (member 'unauthorized-codec-import
            (kinds (project-boundary-violations root))))

   (delete-file codec)
   (delete-file host-file)
   (write-datum
    effect
    '(module example "../macros/lazy-with-macros.rkt"
       (#%module-begin
        (require "../macros/macros.rkt"
                 (only-in "../core/dependency.rkt" identity))
        (provide use)
        (def use value =
          (identity value)))))
   (check-equal? (project-boundary-violations root) '())

   (define (project-kinds)
     (kinds (project-boundary-violations root)))

   (define (check-project-kind kind)
     (check-not-false (member kind (project-kinds))))

   ;; Require wrappers cannot hide either privileged runtime module from the
   ;; project-wide scan. These core fixtures isolate the global detector from
   ;; the stricter effect and macro module classes.
   (define core-bridge (build-path root "core" "bridge.rkt"))
   (write-datum
    core-bridge
    '(module bridge racket/base
       (#%module-begin
        (require (rename-in "../runtime/codec.rkt"
                            [object-ok bridge]))
        (provide bridge))))
   (check-project-kind 'unauthorized-codec-import)
   (delete-file core-bridge)

   (write-datum
    core-bridge
    '(module bridge racket/base
       (#%module-begin
        (require (combine-in "../runtime/codec.rkt"
                             "dependency.rkt")))))
   (check-project-kind 'unauthorized-codec-import)
   (delete-file core-bridge)

   ;; A require transformer that has not been explicitly classified fails
   ;; closed instead of becoming a new way to conceal a privileged path.
   (write-datum
    core-bridge
    '(module bridge racket/base
       (#%module-begin
        (require (relative-in "../runtime" "codec.rkt")))))
   (check-project-kind 'unclassified-production-import)
   (delete-file core-bridge)

   (write-datum
    core-bridge
    '(module bridge racket/base
       (#%module-begin
        (require (prefix-in codec: "../runtime/codec.rkt")))))
   (check-project-kind 'unauthorized-codec-import)
   (delete-file core-bridge)

   (write-datum
    core-bridge
    '(module bridge racket/base
       (#%module-begin
        (require (rename-in "../runtime/host.rkt" [host bridge]))
        (provide bridge))))
   (check-project-kind 'unauthorized-host-import)
   (delete-file core-bridge)

   ;; The sole-host rule is global: even a class not otherwise inspected by
   ;; this checker cannot become a second filesystem or TCP importer.
   (write-datum
    core-bridge
    '(module bridge racket/base
       (#%module-begin
        (require (only-in racket/tcp tcp-connect)))))
   (check-project-kind 'unauthorized-host-capability-import)
   (delete-file core-bridge)

   (write-datum
    core-bridge
    '(module bridge racket/base
       (#%module-begin
        (require (only-in racket/file file->bytes)))))
   (check-project-kind 'unauthorized-host-capability-import)
   (delete-file core-bridge)

   ;; A symlinked directory cannot disguise runtime code as an allowed core
   ;; dependency. The individual effect check rejects it without metadata or
   ;; content access beneath the link; the project gate never opens its target.
   (define core-alias (build-path root "core" "runtime-alias"))
   (define linked-codec (build-path core-alias "codec.rkt"))
   (define linked-effect (build-path root "effects" "linked-escape.rkt"))
   (make-file-or-directory-link (build-path root "runtime") core-alias)
   (write-datum
    linked-effect
    '(module linked-escape "../macros/lazy-with-macros.rkt"
       (#%module-begin
        (require "../macros/macros.rkt"
                 "../core/runtime-alias/codec.rkt")
        (provide use)
        (def use value =
          (object-ok value)))))
   (define-values (linked-effect-findings linked-effect-accesses)
     (observe-source-accesses
      (list linked-codec)
      (lambda ()
        (file-boundary-violations linked-effect 'effect root))))
   (check-not-false
    (member 'disallowed-effect-import
            (kinds linked-effect-findings)))
   (check-equal? linked-effect-accesses 0)
   (define-values (linked-project-kinds linked-project-reads)
     (observe-source-reads
      (list core-alias linked-codec)
      project-kinds))
   (check-not-false
    (member 'disallowed-boundary-path linked-project-kinds))
   (check-equal? linked-project-reads 0)
   (delete-file linked-effect)
   (delete-file core-alias)

   ;; The macro layer is trusted to translate syntax mechanically, not to gain
   ;; operating-system authority. Exact imports plus a closed source
   ;; vocabulary catch both explicit capabilities and unknown implicit ones.
   (define macro-file (build-path root "macros" "macros.rkt"))
   (write-datum
    macro-file
    '(module macros lazy
       (#%module-begin
        (require (for-syntax racket/base)
                 racket/system)
        (provide def lambda-let define-function-name)
        (define-for-syntax leak (system "true")))))
   (check-project-kind 'invalid-macro-imports)
   (check-project-kind 'forbidden-macro-capability)
   (write-datum macro-file clean-macro-datum)

   (write-datum
    macro-file
    '(module macros lazy
       (#%module-begin
        (require (for-syntax racket/base))
        (provide def lambda-let define-function-name)
        (define-for-syntax observed (current-seconds)))))
   (check-project-kind 'unapproved-macro-identifier)
   (write-datum macro-file clean-macro-datum)

   (write-datum
    macro-file
    '(module macros lazy
       (#%module-begin
        (require (for-syntax racket/base)
                 (rename-in "../runtime/codec.rkt"
                            [object-ok bridge]))
        (provide def lambda-let define-function-name))))
   (check-project-kind 'invalid-macro-imports)
   (check-project-kind 'unauthorized-codec-import)
   (write-datum macro-file clean-macro-datum)

   ;; Both trusted paths are pinned, and new macro or language modules remain
   ;; outside the approved production classifications.
   (define macro-shell
     (build-path root "macros" "lazy-with-macros.rkt"))
   (write-datum
    macro-shell
    '(module lazy-with-macros racket/base
       (#%module-begin
        (require lazy/lazy)
        (provide (all-from-out lazy/lazy)
                 #%module-begin
                 #%app
                 #%datum
                 #%top)
        (define leak 'host-value))))
   (check-project-kind 'invalid-macro-shell-forms)
   (write-datum macro-shell clean-macro-shell-datum)

   (define macro-target (build-path root "macro-target.rkt"))
   (write-datum macro-target clean-macro-datum)
   (delete-file macro-file)
   (make-file-or-directory-link macro-target macro-file)
   (define-values (macro-symlink-kinds unsafe-macro-reads)
     (observe-source-reads (list macro-file) project-kinds))
   (check-not-false
    (member 'disallowed-boundary-path macro-symlink-kinds))
   (check-equal? unsafe-macro-reads 0)
   (delete-file macro-file)
   (delete-file macro-target)
   (write-datum macro-file clean-macro-datum)

   ;; Phase 19 admits exactly one reader, one facade/expander, and the pinned
   ;; package metadata. The facade alone may import and re-export production
   ;; host; its other imports, public surface, runtime definitions, and source
   ;; vocabulary remain closed.
   (define language-expander
     (build-path root "lang" "expander.rkt"))
   (define language-reader
     (build-path root "lang" "reader.rkt"))
   (define package-info
     (build-path root "info.rkt"))
   (define clean-language-expander-datum
     (read-datum language-expander))
   (define clean-language-reader-datum
     (read-datum language-reader))
   (define clean-package-info-datum
     (read-datum package-info))

   ;; The fixed point is a single selected private import. Neither exposing
   ;; it nor replacing it with a native recursive form is part of rec.
   (for ([name (in-list '(raw-fix language-fix))])
     (write-datum language-expander
                  (append-module-form clean-language-expander-datum `(provide ,name)))
     (check-not-false
      (member 'invalid-language-expander-export
              (kinds (file-boundary-violations language-expander 'language-expander root)))))
   (write-datum language-expander
                (replace-datum '(only-in "../core/fix.rkt" (raw-fix language-fix))
                               "../core/fix.rkt"
                               clean-language-expander-datum))
   (check-not-false
    (member 'invalid-language-expander-imports
            (kinds (file-boundary-violations language-expander 'language-expander root))))
   (write-datum language-expander
                (append-module-form clean-language-expander-datum
                                    '(define-syntax (language-rec stx)
                                       (syntax (letrec ([loop loop]) loop)))))
   (check-not-false
    (member 'unapproved-language-identifier
            (kinds (file-boundary-violations language-expander 'language-expander root))))
   (write-datum language-expander clean-language-expander-datum)

   (check-equal?
    (file-boundary-violations language-expander
                              'language-expander
                              root)
    '())
   (check-equal?
    (file-boundary-violations language-reader
                              'language-reader
                              root)
    '())
   (check-equal?
    (file-boundary-violations package-info 'package-info root)
    '())

   (write-datum
    language-expander
    (append-module-form
     clean-language-expander-datum
     '(require (only-in racket/file file->bytes))))
   (define expanded-capability-kinds
     (kinds
      (file-boundary-violations language-expander
                                'language-expander
                                root)))
   (check-not-false
    (member 'invalid-language-expander-imports
            expanded-capability-kinds))
   (check-not-false
    (member 'forbidden-language-capability
            expanded-capability-kinds))
   (write-datum language-expander clean-language-expander-datum)

   ;; Public exit is an export spelling, never a native capability for the
   ;; expander. Reject both compile-time calls and generated native calls in
   ;; existing approved helpers, without relying on an unknown helper name.
   (for ([replacement
          (in-list
           '((define-for-syntax (language-definition-form? form bound) (exit 1))
             (define-syntax (language-lambda stx) (syntax (exit 1)))
             (define-syntax (language-lambda stx)
               (syntax-case (syntax #&exit) ()
                 [#&function (syntax (function 1))]))
             (define-syntax (language-lambda stx)
               (syntax-case (syntax #s(p exit)) ()
                 [#s(p function) (syntax (function 1))]))
             (define-syntax (language-lambda stx)
               (syntax-case (syntax #(exit)) ()
                 [#(function) (syntax (function 1))]))
             (define-syntax (language-lambda stx)
               (syntax #hash((function . exit))))
             (define-for-syntax (language-definition-form? form bound) (print 1))
             (define-syntax (language-lambda stx) (syntax (print 1)))
             (define-syntax (language-lambda stx)
               (syntax #hash((function . print))))))])
     (define original
       (for/first ([form (in-list (cdr (cadddr clean-language-expander-datum)))]
                   #:when (equal? (take form 2) (take replacement 2)))
         form))
     (unless original
       (error 'boundary-test "existing language helper was not found"))
     (write-datum language-expander
                  (replace-datum original replacement clean-language-expander-datum))
     (check-not-false
      (member 'forbidden-language-capability
              (kinds
               (file-boundary-violations language-expander 'language-expander root)))))
   (write-datum language-expander clean-language-expander-datum)

   ;; Even an existing approved host binding cannot be injected into print:
   ;; its argument must be the already-created String-only stdout function.
   (write-datum
    language-expander
    (replace-datum
     '(def language-print = (language-make-print stdout))
     '(def language-print = (language-make-print language-host))
     clean-language-expander-datum))
   (check-not-false
    (member 'invalid-language-runtime-definitions
            (kinds (file-boundary-violations language-expander
                                              'language-expander root))))
   (write-datum language-expander clean-language-expander-datum)

   (write-datum
    language-expander
    (append-module-form clean-language-expander-datum
                        '(provide raw-cons)))
   (check-not-false
    (member 'invalid-language-expander-export
            (kinds
             (file-boundary-violations language-expander
                                       'language-expander
                                       root))))
   (write-datum language-expander clean-language-expander-datum)

   (write-datum
    language-expander
    (append-module-form
     clean-language-expander-datum
     '(def escape =
        (language-make-stdout language-host))))
   (check-not-false
    (member 'invalid-language-runtime-definitions
            (kinds
             (file-boundary-violations language-expander
                                       'language-expander
                                       root))))
   (write-datum language-expander clean-language-expander-datum)

   (write-datum
    language-expander
    (append-module-form
     clean-language-expander-datum
     '(define-for-syntax (clock)
        (current-seconds))))
   (define expanded-vocabulary-kinds
     (kinds
      (file-boundary-violations language-expander
                                'language-expander
                                root)))
   (check-not-false
    (member 'unapproved-language-syntax-helper
            expanded-vocabulary-kinds))
   (check-not-false
    (member 'unapproved-language-identifier
            expanded-vocabulary-kinds))
   (write-datum language-expander clean-language-expander-datum)

   (write-datum
    language-reader
    (append-module-form clean-language-reader-datum
                        'racket/base))
   (check-equal?
    (kinds
     (file-boundary-violations language-reader
                               'language-reader
                               root))
    '(invalid-language-reader-forms))
   (write-datum language-reader clean-language-reader-datum)

   (write-datum
    package-info
    (append-module-form clean-package-info-datum
                        '(define leak "host")))
   (check-equal?
    (kinds
     (file-boundary-violations package-info 'package-info root))
    '(invalid-package-info-forms))
   (write-datum package-info clean-package-info-datum)

   (write-datum
    package-info
    (replace-datum 'Apache-2.0 'MIT clean-package-info-datum))
   (check-equal?
    (kinds
     (file-boundary-violations package-info 'package-info root))
    '(invalid-package-info-forms))
   (write-datum package-info clean-package-info-datum)

   ;; VERSION is the sole product-version source. Every approved state has
   ;; one mechanically checked Racket package projection.
   (define product-version-file
     (build-path root "VERSION"))
   (for ([version-pair
          (in-list '((#"0.2.0-dev\n" "0.1.900")
                     (#"0.2.0-rc.1\n" "0.1.901")
                     (#"0.2.0\n" "0.2")
                     (#"0.3.0-dev\n" "0.2.900")
                     (#"0.3.0\n" "0.3")
                     (#"0.4.0\n" "0.4")
                     (#"0.5.0\n" "0.5")
                     (#"0.6.0\n" "0.6")
                     (#"0.7.0\n" "0.7")))])
     (write-exact-bytes product-version-file (car version-pair))
     (write-datum
      package-info
      (replace-package-version clean-package-info-datum
                               (cadr version-pair)))
     (check-equal? (project-boundary-violations root) '()))
   (write-exact-bytes product-version-file #"0.7.0\n")
   (write-datum package-info clean-package-info-datum)

   (write-exact-bytes product-version-file #"0.7.0")
   (check-project-kind 'invalid-product-version)
   (write-exact-bytes product-version-file #"0.7.0\n")

   (define saved-version-file
     (build-path root "VERSION.backup"))
   (define version-target
     (make-temporary-file "attalambda-version-target-~a"
                          #f
                          (path-only root)))
   (write-exact-bytes version-target #"0.7.0\n")
   (rename-file-or-directory product-version-file saved-version-file)
   (make-file-or-directory-link version-target product-version-file)
   (define-values (version-link-findings version-target-reads)
     (observe-source-reads
      (list version-target)
      (lambda ()
        (project-boundary-violations root))))
   (check-not-false
    (member 'disallowed-version-path
            (kinds version-link-findings)))
   (check-equal? version-target-reads 0)
   (delete-file product-version-file)
   (rename-file-or-directory saved-version-file product-version-file)
   (delete-file version-target)

   ;; The runner is a closed non-exporting scaffolding class. Its one loader
   ;; call must use source-path; runner behavior covers how that path is
   ;; validated. Process, environment, and additional-module surfaces all fail
   ;; closed. Private implementation details may change without duplicating
   ;; their bodies in this checker.
   (define runner-file
     (build-path root "runner" "attalambda.rkt"))
   (define clean-runner-datum
     (read-datum runner-file))
   (check-equal?
    (file-boundary-violations runner-file 'runner root)
    '())

   (write-datum
    runner-file
    (replace-datum
     '(and source line column)
     '(and line source column)
     clean-runner-datum))
   (check-equal?
    (file-boundary-violations runner-file 'runner root)
    '())
   (write-datum runner-file clean-runner-datum)

   (write-datum
    runner-file
    (replace-datum
     '(bytes->string/utf-8 (port->bytes input) #f)
     '(bytes->string/utf-8 #"" #f)
     clean-runner-datum))
   (check-not-false
    (member 'invalid-runner-input-targets
            (kinds
             (file-boundary-violations runner-file 'runner root))))
   (write-datum runner-file clean-runner-datum)

   (write-datum
    runner-file
    (append-module-form clean-runner-datum
                        '(define copied-version "0.2.0-dev")))
   (check-not-false
    (member 'duplicated-runner-version-literal
            (kinds
             (file-boundary-violations runner-file 'runner root))))
   (write-datum runner-file clean-runner-datum)

   (write-datum
    runner-file
    (replace-datum "VERSION"
                   "secrets.txt"
                   clean-runner-datum))
   (check-not-false
    (member 'invalid-runner-input-targets
            (kinds
             (file-boundary-violations runner-file 'runner root))))
   (write-datum runner-file clean-runner-datum)

   (write-datum
    runner-file
    (replace-datum '(define unexpected-failure-status 70)
                   '(define unexpected-failure-status 69)
                   clean-runner-datum))
   (check-not-false
    (member 'invalid-runner-status-definitions
            (kinds
             (file-boundary-violations runner-file 'runner root))))
   (write-datum runner-file clean-runner-datum)

   (write-datum
    runner-file
    (append-module-form clean-runner-datum
                        '(provide run-source)))
   (check-not-false
    (member 'invalid-runner-export
            (kinds
             (file-boundary-violations runner-file 'runner root))))
   (write-datum runner-file clean-runner-datum)

   (write-datum
    runner-file
    (append-module-form
     clean-runner-datum
     '(require (only-in racket/system system))))
   (define process-runner-kinds
     (kinds (file-boundary-violations runner-file 'runner root)))
   (check-not-false
    (member 'invalid-runner-imports process-runner-kinds))
   (check-not-false
    (member 'forbidden-runner-capability process-runner-kinds))
   (write-datum runner-file clean-runner-datum)

   (write-datum
    runner-file
    (append-module-form
     clean-runner-datum
     '(define leaked-environment
        (current-environment-variables))))
   (define environment-runner-kinds
     (kinds (file-boundary-violations runner-file 'runner root)))
   (check-not-false
    (member 'invalid-runner-definition-set environment-runner-kinds))
   (check-not-false
    (member 'forbidden-runner-capability environment-runner-kinds))
   (write-datum runner-file clean-runner-datum)

   (write-datum
    runner-file
    (replace-datum '(dynamic-require source-path #f)
                   '(dynamic-require version-path #f)
                   clean-runner-datum))
   (check-not-false
    (member 'invalid-runner-entry-or-loader
            (kinds
             (file-boundary-violations runner-file 'runner root))))
   (write-datum runner-file clean-runner-datum)

   (define extra-runner
     (build-path root "runner" "alternate.rkt"))
   (write-datum
    extra-runner
    '(module alternate racket/base
       (#%module-begin)))
   (check-project-kind 'unclassified-runner-module)
   (delete-file extra-runner)
   (check-equal? (project-boundary-violations root) '())

   (define extra-macro (build-path root "macros" "extra.rkt"))
   (write-datum
    extra-macro
    '(module extra racket/base
       (#%module-begin)))
   (check-project-kind 'unclassified-macro-module)
   (delete-file extra-macro)

   (define language-file (build-path root "lang" "main.rkt"))
   (write-datum
    language-file
    '(module main racket/base
       (#%module-begin
        (require (only-in "../runtime/host.rkt" host))
        (provide host))))
   (check-project-kind 'unclassified-language-module)
   (check-project-kind 'unauthorized-host-import)
   (check-project-kind 'unauthorized-host-export)
   (delete-file language-file)

   (check-equal? (project-boundary-violations root) '())))

;; Generic printing makes Error formatting a pure-core responsibility.
;; An otherwise permitted host formatter in this observer must fail closed.
(temporary-project
 (lambda (root)
   (define reader (build-path root "readers" "error.rkt"))
   (define clean (read-datum (build-path project-root "readers" "error.rkt")))
   (write-datum (build-path root "core" "render-error.rkt")
                '(module render-error racket/base
                   (#%module-begin
                    (provide raw-error-diagnostic-string)
                    (define (raw-error-diagnostic-string value) value))))
   (write-datum (build-path root "readers" "string.rkt")
                '(module string racket/base
                   (#%module-begin
                    (provide string-value->string)
                    (define (string-value->string value) value))))
   (write-datum reader clean)
   (check-equal? (file-boundary-violations reader 'reader root) '())
   (write-datum reader
                (replace-datum
                 '(string-value->string ((force raw-error-diagnostic-string) error))
                 '(format "~a" (string-value->string
                                ((force raw-error-diagnostic-string) error)))
                 clean))
   (check-not-false
    (member 'independent-error-formatting-policy
            (kinds (file-boundary-violations reader 'reader root))))))
