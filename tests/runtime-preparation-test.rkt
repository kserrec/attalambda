#lang racket/base
(require rackunit file/sha1 racket/file racket/list racket/path racket/runtime-path
         "../tooling/prepare-expeditor-runtime.rkt" "helpers/fresh-language.rkt")
(define-runtime-path helper "../tooling/prepare-expeditor-runtime.rkt")
(define-runtime-path patch-path "../tooling/patches/expeditor-1.2-source-display.patch")
(define-runtime-path copy-helper "helpers/fresh-language.rkt")
(define patch (file->bytes patch-path))
(define candidate-root (path-only (collection-file-path "main.rkt" "expeditor")))
;; Recover the exact approved upstream bytes without storing a second copy of the
;; dependency. Both sides are checked against independent pinned SHA-256 values.
(define-values (split-patch apply-diff)
  (parameterize ([current-namespace (module->namespace `(file ,(path->string helper)))])
    (values (eval 'patches-by-file) (eval 'apply-unified-diff))))
(define (reverse-diff content)
  (apply bytes-append
         (for/list ([line (regexp-match* #px#"[^\n]*\n|[^\n]+$" content)])
           (cond
             [(regexp-match #px#"^@@ -([0-9]+(?:,[0-9]+)?) [+]([0-9]+(?:,[0-9]+)?) @@(.*)$" line)
              => (lambda (parts)
                   (bytes-append #"@@ -" (caddr parts) #" +" (cadr parts) #" @@" (cadddr parts)))]
             [(regexp-match? #rx#"^--- " line) (bytes-append #"+++ " (subbytes line 4))]
             [(regexp-match? #rx#"^[+][+][+] " line) (bytes-append #"--- " (subbytes line 4))]
             [(= (bytes-ref line 0) 43) (bytes-append #"-" (subbytes line 1))]
             [(= (bytes-ref line 0) 45) (bytes-append #"+" (subbytes line 1))]
             [else line]))))
(define parts (split-patch patch))
(define originals
  (for/hash ([pin expeditor-source-pins])
    (define current (file->bytes (build-path candidate-root (car pin))))
    (check-equal? (bytes->hex-string (sha256-bytes current)) (caddr pin))
    (define original (apply-diff current (reverse-diff (hash-ref parts (car pin)))))
    (check-equal? (bytes->hex-string (sha256-bytes original)) (cadr pin))
    (values (car pin) original)))
(define (with-copy action)
  (define directory (make-temporary-file "attalambda-expeditor-preparation-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (for ([pin expeditor-source-pins])
       (define path (build-path directory (car pin)))
       (make-directory* (path-only path))
       (call-with-output-file path (lambda (out) (write-bytes (hash-ref originals (car pin)) out)))
       (file-or-directory-permissions path #o640))
     (action directory))
   (lambda () (delete-directory/files directory))))
(define (snapshot directory)
  (for/list ([pin expeditor-source-pins])
    (define path (build-path directory (car pin)))
    (list (file->bytes path) (file-or-directory-identity path)
          (file-or-directory-modify-seconds path) (file-or-directory-permissions path 'bits))))

(test-case "explicit preparation is exact, mode-preserving and idempotent"
  (with-copy
   (lambda (directory)
     (define before (snapshot directory))
     (check-exn #rx"requires the reviewed" (lambda () (prepare-expeditor-directory directory patch #f)))
     (check-equal? (snapshot directory) before)
     (prepare-expeditor-directory directory patch #t)
     (for ([pin expeditor-source-pins])
       (define path (build-path directory (car pin)))
       (check-equal? (file->bytes path) (file->bytes (build-path candidate-root (car pin))))
       (check-equal? (file-or-directory-permissions path 'bits) #o640))
     (define prepared (snapshot directory))
     (prepare-expeditor-directory directory patch #t)
     (prepare-expeditor-directory directory patch #f)
     (check-equal? (snapshot directory) prepared))))

(test-case "an unknown last file prevents every earlier write"
  (with-copy
   (lambda (directory)
     (define last-path (build-path directory (car (last expeditor-source-pins))))
     (call-with-output-file last-path #:exists 'append (lambda (out) (display "unknown\n" out)))
     (define before (snapshot directory))
     (check-exn #rx"unknown editor source" (lambda () (prepare-expeditor-directory directory patch #t)))
     (check-equal? (snapshot directory) before))))

(test-case "unapproved patch bytes and symlink sources are refused"
  (with-copy
   (lambda (directory)
     (define before (snapshot directory))
     (check-exn #rx"checksum differs"
                (lambda () (prepare-expeditor-directory directory (bytes-append patch #"x") #t)))
     (check-equal? (snapshot directory) before)
     (define first-path (build-path directory (caar expeditor-source-pins)))
     (define target (build-path directory "target"))
     (rename-file-or-directory first-path target)
     (make-file-or-directory-link target first-path)
     (check-exn #rx"symlink editor source" (lambda () (prepare-expeditor-directory directory patch #t)))
     (check-equal? (file->bytes target) (caar before)))))

(test-case "partial completed preparation can be safely resumed"
  (with-copy
   (lambda (directory)
     (define first (caar expeditor-source-pins))
     (copy-file (build-path candidate-root first) (build-path directory first) #t)
     (define first-identity (file-or-directory-identity (build-path directory first)))
     (prepare-expeditor-directory directory patch #t)
     (prepare-expeditor-directory directory patch #f)
     (check-equal? (file-or-directory-identity (build-path directory first)) first-identity))))

(test-case "matching source hashes cannot conceal a loaded upstream editor main"
  (define directory (make-temporary-directory "attalambda-stale-editor-~a"))
  (define editor-directory (build-path directory "expeditor"))
  (define copy-source
    (parameterize ([current-namespace (module->namespace `(file ,(path->string copy-helper)))])
      (eval 'copy-package-source)))
  (define environment (current-environment-variables))
  (define (check-runtime)
    (run-command environment racket-executable
                 (list "-S" (path->string directory) (path->string helper) "--check") 30))
  (dynamic-wind
   void
   (lambda ()
     ;; Reuse the existing dotenv-safe source copier, excluding compiled caches.
     (copy-source candidate-root editor-directory)
     (define control (check-runtime))
     (check-false (command-result-timed-out? control) (result-diagnostic control))
     (check-equal? (command-result-status control) 0 (result-diagnostic control))
     (define main (build-path editor-directory "main.rkt"))
     (define corrected (file->bytes main))
     (dynamic-wind
      void
      (lambda ()
        (call-with-output-file main #:exists 'truncate
          (lambda (out) (write-bytes (hash-ref originals "main.rkt") out)))
        (check-command-success
         (run-command environment (find-executable-path "raco")
                      (list "make" (path->string main)) 30) #""))
      (lambda ()
        (call-with-output-file main #:exists 'truncate
          (lambda (out) (write-bytes corrected out)))
        (file-or-directory-modify-seconds main 1)))
     (check-true (file-exists? (build-path editor-directory "compiled/main_rkt.zo")))
     ;; Sources are approved, while the fresh checker must reject stale behavior
     ;; before printing any provenance that a builder could record as verified.
     (prepare-expeditor-directory editor-directory patch #f)
     (define stale (check-runtime))
     (check-command-failure stale #rx"string-width|loaded editor implementation")
     (check-equal? (command-result-stdout stale) #""))
   (lambda () (delete-directory/files directory))))
