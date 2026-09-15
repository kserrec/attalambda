#lang racket/base

(require rackunit
         racket/file
         racket/path
         racket/port)

(provide (struct-out command-result)
         (struct-out fresh-language-install)
         racket-executable
         run-command
         result-diagnostic
         check-command-success
         check-command-failure
         write-source
         call-with-fresh-language-install)

(struct command-result (status stdout stderr timed-out?)
  #:transparent)

(struct fresh-language-install (temporary-root environment)
  #:transparent)

(define racket-executable
  (find-executable-path "racket"))

(define raco-executable
  (find-executable-path "raco"))

(define (run-command environment executable arguments timeout-seconds
                     #:current-directory [working-directory #f])
  (define-values (process child-output child-input child-error)
    (parameterize
        ([current-environment-variables environment]
         [current-directory
          (or working-directory (current-directory))])
      (apply subprocess
             #f
             #f
             #f
             executable
             arguments)))
  (close-output-port child-input)
  (define captured-output
    (box #f))
  (define captured-error
    (box #f))
  (define output-reader
    (thread
     (lambda ()
       (set-box! captured-output
                 (port->bytes child-output)))))
  (define error-reader
    (thread
     (lambda ()
       (set-box! captured-error
                 (port->bytes child-error)))))
  (define completed
    (sync/timeout timeout-seconds process))
  (unless completed
    (subprocess-kill process #t)
    (sync process))
  (sync output-reader)
  (sync error-reader)
  (command-result
   (and completed (subprocess-status process))
   (unbox captured-output)
   (unbox captured-error)
   (not completed)))

(define (result-diagnostic result)
  (format "status: ~s\nstdout: ~s\nstderr: ~a"
          (command-result-status result)
          (command-result-stdout result)
          (bytes->string/utf-8
           (command-result-stderr result)
           #\?)))

(define (check-command-success result expected-output)
  (check-false (command-result-timed-out? result)
               (result-diagnostic result))
  (check-equal? (command-result-status result)
                0
                (result-diagnostic result))
  (check-equal? (command-result-stdout result)
                expected-output
                (result-diagnostic result))
  (check-equal? (command-result-stderr result)
                #""
                (result-diagnostic result)))

(define (check-command-failure result expected-message)
  (check-false (command-result-timed-out? result)
               (result-diagnostic result))
  (check-not-equal? (command-result-status result)
                    0
                    (result-diagnostic result))
  (check-true
   (regexp-match? expected-message
                  (bytes->string/utf-8
                   (command-result-stderr result)
                   #\?))
   (result-diagnostic result)))

(define (write-source path source)
  (call-with-output-file path
    #:exists 'truncate
    (lambda (output)
      (display source output))))

(define (dotenv-name? path)
  (define name
    (file-name-from-path path))
  (and name
       (regexp-match?
        #px"(^|\\.)env($|\\.)"
        (string-downcase (path->string name)))))

(define (excluded-package-entry? path)
  (define name
    (file-name-from-path path))
  (or (dotenv-name? path)
      (and name
           (member (path->string name)
                   '(".git" "compiled")))))

(define (copy-package-source source target)
  (cond
    [(link-exists? source)
     (error 'fresh-language-install
            "package source contains a symlink: ~a"
            source)]
    [(directory-exists? source)
     (make-directory target)
     (for ([entry (in-list (directory-list source))]
           #:unless (excluded-package-entry? entry))
       (copy-package-source (build-path source entry)
                            (build-path target entry)))]
    [(regular-file-path? source)
     (copy-file source target)]
    [else
     (error 'fresh-language-install
            "package source entry disappeared: ~a"
            source)]))

(define canonical-application-names
  '("hello.attl"
    "stdout.attl"
    "file-round-trip.attl"
    "http-server.attl"
    "foundations.attl"))

(define (regular-file-path? path)
  (with-handlers ([exn:fail? (lambda (failure) #f)])
    (= (bitwise-and
        (hash-ref (file-or-directory-stat path) 'mode)
        file-type-bits)
       regular-file-type-bits)))

(define (copy-canonical-applications source target)
  (when (link-exists? source)
    (error 'fresh-language-install
           "application directory is a symlink: ~a"
           source))
  (unless (directory-exists? source)
    (error 'fresh-language-install
           "application directory is unavailable: ~a"
           source))
  (define actual-names
    (sort (map path->string (directory-list source)) string<?))
  (define expected-names
    (sort canonical-application-names string<?))
  (unless (equal? actual-names expected-names)
    (error 'fresh-language-install
           "application inventory differs from the canonical names"))
  (make-directory target)
  (for ([name (in-list canonical-application-names)])
    (define source-path (build-path source name))
    (when (link-exists? source-path)
      (error 'fresh-language-install
             "canonical application is a symlink: ~a"
             source-path))
    (unless (regular-file-path? source-path)
      (error 'fresh-language-install
             "canonical application is not a regular file: ~a"
             source-path))
    (copy-file source-path (build-path target name))))

(define (call-with-fresh-language-install project-root procedure)
  (define temporary-root
    (make-temporary-file
     "attalambda-language-~a"
     'directory
     (if (directory-exists? "/tmp")
         (string->path "/tmp")
         (find-system-path 'temp-dir))))
  (dynamic-wind
    void
    (lambda ()
      (define isolated-home
        (build-path temporary-root "racket-home"))
      (make-directory isolated-home)

      (define isolated-environment
        (environment-variables-copy
         (current-environment-variables)))
      (environment-variables-set!
       isolated-environment
       #"PLTCOLLECTS"
       #f)
      (environment-variables-set!
       isolated-environment
       #"PLTUSERHOME"
       (path->bytes isolated-home))
      (environment-variables-set!
       isolated-environment
       #"TMPDIR"
       (path->bytes temporary-root))

      (define package-source
        (build-path temporary-root "package-source"))
      (make-directory package-source)
      (copy-file (build-path project-root "info.rkt")
                 (build-path package-source "info.rkt"))
      (copy-file (build-path project-root "VERSION")
                 (build-path package-source "VERSION"))
      (for ([directory
             (in-list '("core" "effects" "lang" "macros"
                        "readers" "runner" "runtime"))])
        (copy-package-source
         (build-path project-root directory)
         (build-path package-source directory)))
      (copy-canonical-applications
       (build-path project-root "examples")
       (build-path package-source "examples"))

      ;; This copy install proves collection resolution from declared package
      ;; metadata rather than a source-tree link. The staging walk rejects
      ;; symlinks and excludes dotenv, VCS, and compiled entries before their
      ;; contents could be accessed.
      (define install-result
        (run-command
         isolated-environment
         raco-executable
         (list "pkg" "install"
               "--batch"
               "--scope" "user"
               "--copy"
               "--name" "attalambda"
               "--deps" "fail"
               "--no-docs"
               "--fail-fast"
               (path->string package-source))
         180))
      (check-false (command-result-timed-out? install-result)
                   (result-diagnostic install-result))
      (check-equal? (command-result-status install-result)
                    0
                    (result-diagnostic install-result))
      (unless (and (not (command-result-timed-out? install-result))
                   (equal? (command-result-status install-result) 0))
        (error 'fresh-language-install
               "fresh package installation failed\n~a"
               (result-diagnostic install-result)))

      (procedure
       (fresh-language-install temporary-root isolated-environment)))
    (lambda ()
      (delete-directory/files temporary-root))))
