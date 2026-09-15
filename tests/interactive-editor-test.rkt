#lang racket/base

;; The supported Linux terminal gate runs with the ordinary source suite.
;; Every Python interaction has a bounded event wait and finally-based cleanup.
(require rackunit racket/runtime-path racket/system)

(define-runtime-path fixtures "fixtures")
(define-runtime-path harness "interactive_pty.py")
(define-runtime-path regressions "interactive_expeditor_regressions.py")

(unless (eq? (system-type 'os*) 'linux)
  (error 'interactive-editor-test "this terminal acceptance gate requires Linux"))
(define racket-path (find-executable-path "racket"))
(define raco-path (find-executable-path "raco"))
(define python-path (find-executable-path "python3"))
(unless (and racket-path raco-path python-path)
  (error 'interactive-editor-test "Racket, raco and Python 3 are required"))

(test-case "real editor and program input PTY acceptance"
  ;; Python launches these by path, so their imports are invisible to raco make
  ;; on this wrapper. Refresh every directly launched fixture for this runtime.
  (check-true
   (apply system* raco-path "make"
          (for/list ([name '("interactive-editor-probe.rkt"
                            "interactive-adapter-probe.rkt"
                            "interactive-descriptor-probe.rkt"
                            "interactive-expeditor-regression.rkt")])
            (build-path fixtures name))))
  (parameterize ([current-environment-variables
                  (environment-variables-copy (current-environment-variables))])
    (environment-variables-set! (current-environment-variables)
                               #"ATTALAMBDA_TEST_RACKET"
                               (path->bytes racket-path))
    (check-true (system* python-path harness "-v"))
    (check-true (system* python-path regressions "-v"))))
