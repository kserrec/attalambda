#lang racket/base

;; Explicit preparation of an isolated toolchain, never a production import.
;; Build/test callers check it in a fresh process after the opt-in --apply step.
(require file/sha1 racket/file racket/promise racket/runtime-path
         "prepare-expeditor-runtime.rkt")
(provide original-promise-sha256 patched-promise-sha256 patch-sha256
         corrected-promise-bytes verify-loaded-promises)

(define original-promise-sha256
  "ad9009b58587dc5e326270e02d21788264abbc5b033cbef716521ff02663b628")
(define patched-promise-sha256
  "bca5b526943be123c8f3fbad24d30556fe3ffea1dc60b6d9c28ec8875e27c7eb")
(define patch-sha256
  "179be1bbde34542758c87b364ae7717c7355cba58cb880875faf137c521ab1a9")
(define-runtime-path patch-path "patches/racket-9.3-completed-promises.patch")

(define (digest content) (bytes->hex-string (sha256-bytes content)))

;; Exact replacements keep preparation portable to Windows without an external
;; patch executable. Both input and final output must match the reviewed hashes;
;; the adjacent unified diff records the same change for review and provenance.
(define replacements
  (list
   (cons #"(define (force/composable root)\n  (let ([v (pref root)])\n    (cond\n      [(procedure? v)"
         #"(define (force/composable root)\n  (let ([v (pref root)])\n    (cond\n      [(and (procedure? v) (not (running? v)) (not (reraise? v)))")
   (cons #"                     (pset! v root) ; share with root\n                     (cond [(procedure? v*) (loop (v*))]"
         (bytes-append
          #"                     (cond [(procedure? v*)\n"
          #"                            ;; Only pending computation may share the running\n"
          #"                            ;; root. Completed values and existing links must\n"
          #"                            ;; not inherit a break raised by this new demand.\n"
          #"                            (unless (or (running? v*) (reraise? v*))\n"
          #"                              (pset! v root))\n"
          #"                            (loop (v*))]"))
   (cons #"      [(promise? v) (force v)] ; non composable promise is forced as usual\n"
         (bytes-append
          #"      [(promise? v) (force v)] ; non composable promise is forced as usual\n"
          #"      [(or (running? v) (reraise? v)) (v)]\n"))))

(define (corrected-promise-bytes content)
  (cond
    [(equal? (digest content) patched-promise-sha256) content]
    [(equal? (digest content) original-promise-sha256)
     (define corrected
       (for/fold ([current content]) ([replacement (in-list replacements)])
         (define pattern (byte-regexp (regexp-quote (car replacement))))
         (unless (= (length (regexp-match* pattern current)) 1)
           (error 'prepare-racket-runtime "reviewed replacement is not unique"))
         (regexp-replace pattern current (lambda (_) (cdr replacement)))))
     (unless (equal? (digest corrected) patched-promise-sha256)
       (error 'prepare-racket-runtime "corrected source differs from the reviewed patch"))
     corrected]
    [else (error 'prepare-racket-runtime "promise source is neither approved original nor patched Racket 9.3")]))

(define (verify-loaded-promises)
  ;; A read-only observation distinguishes loaded old bytecode from the corrected
  ;; implementation; source-file hashes alone cannot establish what was loaded.
  (define peek
    (parameterize ([current-namespace (module->namespace 'racket/private/promise)])
      (eval '(lambda (value) (pref value)))))
  (define completed (lazy 41))
  (force completed)
  (define known (peek completed))
  (unless (and (= (force (lazy completed)) 41)
               (eq? known (peek completed)))
    (error 'prepare-racket-runtime "loaded promise implementation is unpatched; prepare an isolated Racket 9.3 runtime first")))

(module+ main
  (define arguments (vector->list (current-command-line-arguments)))
  (unless (member arguments '(("--apply") ("--check")))
    (error 'prepare-racket-runtime "use --apply only in an isolated toolchain, or --check for read-only verification"))
  (unless (and (equal? (version) "9.3") (eq? (system-type 'vm) 'chez-scheme))
    (error 'prepare-racket-runtime "requires Racket CS 9.3"))
  (unless (equal? (digest (file->bytes patch-path)) patch-sha256)
    (error 'prepare-racket-runtime "reviewed patch checksum differs"))
  (define source (collection-file-path "promise.rkt" "racket" "private"))
  (when (link-exists? source)
    (error 'prepare-racket-runtime "refusing a symlink promise source"))
  (define original (file->bytes source))
  (cond
    [(equal? arguments '("--apply"))
     (define corrected (corrected-promise-bytes original))
     (unless (bytes=? original corrected)
       (define permissions (file-or-directory-permissions source 'bits))
       (call-with-atomic-output-file
        source
        (lambda (output temporary)
          (write-bytes corrected output)
          (file-or-directory-permissions temporary permissions))))
     (prepare-expeditor-runtime #t)
     (displayln "Isolated Racket 9.3 dependency corrections prepared; verify with --check in a fresh process.")]
    [else
     (unless (equal? (digest original) patched-promise-sha256)
       (error 'prepare-racket-runtime "requires the reviewed Racket 9.3 promise correction"))
     (verify-loaded-promises)
     (prepare-expeditor-runtime #f)
     (printf "Racket promise patch SHA-256: ~a\n" patch-sha256)
     (printf "Racket promise source SHA-256: ~a\n" patched-promise-sha256)]))
