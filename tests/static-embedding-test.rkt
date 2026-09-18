#lang racket/base

(require rackunit racket/file racket/path racket/runtime-path
         "helpers/fresh-language.rkt")
(define-runtime-path project-root "..")
(define raco (find-executable-path "raco"))

(test-case "embedded frontend retains metadata outside its source checkout"
  (call-with-fresh-language-install
   project-root
   (lambda (installation)
     (define root (fresh-language-install-temporary-root installation))
     (define environment (fresh-language-install-environment installation))
     (define source (build-path root "package-source"))
     (define driver (build-path source "tests" "helpers" "static-driver.rkt"))
     (make-directory* (path-only driver))
     (copy-file (build-path project-root "tests" "helpers" "static-driver.rkt") driver)
     (define executable (build-path root (if (eq? (system-type) 'windows) "static-probe.exe" "static-probe")))
     (define built
       (run-command environment raco
                    (list "exe" "-o" (path->string executable) "++lang" "attalambda"
                          (path->string driver)) 180 #:current-directory root))
     (check-command-success built #"")
     (unless (equal? (command-result-status built) 0) (error 'test "embedding failed"))
     ;; Both staging and installed copies disappear; use embedded declarations.
     (define hidden-source (build-path root "source-not-available"))
     (rename-file-or-directory source hidden-source)
     (rename-file-or-directory
      (bytes->path (environment-variables-ref environment #"PLTUSERHOME"))
      (build-path root "installation-not-available"))
     (define sample (build-path root "sample.attl"))
     (write-source sample
                   "#lang attalambda\n(def identity x = x)\n(def plus = add)\n(plus (identity 1) 2)\n(stdout \"must-not-run\")\n")
     (check-command-success
      (run-command environment executable (list (path->string sample)) 30
                   #:current-directory root #:input #"unchanged input\n")
      #"((identity plus) 11 (add stdout))\n"))))
