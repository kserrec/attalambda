#lang racket/base

;; Explicit preparation of the existing editor in an isolated Racket toolchain.
(require file/sha1 racket/file racket/list racket/path racket/runtime-path)
(provide expeditor-patch-sha256 expeditor-source-pins
         corrected-expeditor-sources prepare-expeditor-directory
         verify-loaded-expeditor prepare-expeditor-runtime)
(define-runtime-path expeditor-patch-path "patches/expeditor-1.2-source-display.patch")
(define expeditor-patch-sha256 "954cdc83b8ee684512a5c3c131d4bc48dd30c40a6a6e8c5a884b3f46dc98b755")
(define expeditor-source-pins
  '(("main.rkt" "f826d759776f016052a9557c2659b360e9de2fa32d563984b85516a71689048c" "5bc2e1e1ac8b08b40f52d8b4ef259612330fc63799ee932a6b3947eda70188ff")
    ("private/ee.rkt" "362cedc5104ce708e0c9fd1115a08e875e5cb1f5e8e6406a1967e8e73c3be39d" "5e3f9f407745db422ad53e21d1de855b0ff619af9c1079802e94f80efe3449f6")
    ("private/screen.rkt" "7219e625a87f51b2285c1b7e2b1dc7307df0f2e0f32f2c93f1ab6f85145a770c" "58da8a119d445728f684d1eebb70e4d1196a8fa699925c62731870ba1bf6e262")
    ("private/terminal.rkt" "f973eaf00badbc58086f024dcee70c5cffe01b3b802b655470cf322c67950111" "657c809503ba85b590c21ceeb0260d1253dc0440527eeba2be72d47db3c52f3e")
    ("private/wstring.rkt" "2583daaf0f6300ae830ab76141c63060575dbb60096482921ca75d0b9b134f03" "26ff7df942f7acd4332a5a6b4fd9e74abd7d5b2b14cb9a2f54ce862c2ffb07c2")))


(define (patches-by-file patch)
  (define result (make-hash))
  (define name #f)
  (define lines '())
  (define (save)
    (when name
      (when (hash-has-key? result name) (error 'runtime-patch "duplicate patch file"))
      (hash-set! result name (apply bytes-append (reverse lines)))))
  (for ([line (in-list (regexp-match* #px#"[^\n]*\n|[^\n]+$" patch))])
    (cond
      [(regexp-match #px#"^--- a/([^\n]+)\n$" line)
       => (lambda (match)
            (save)
            (set! name (bytes->string/utf-8 (cadr match)))
            (set! lines (list line)))]
      [else
       (unless name (error 'runtime-patch "missing patch file header"))
       (set! lines (cons line lines))]))
  (save)
  result)

;; Only exact, pinned source patches are accepted by the caller. This small
;; applicator has no fuzzy matching, shell execution, or path interpretation.
(define (apply-unified-diff original patch)
  (define source (list->vector (regexp-match* #px#"[^\n]*\n|[^\n]+$" original)))
  (define index 0)
  (define output '())
  (define in-hunk? #f)
  (define (emit bytes) (set! output (cons bytes output)))
  (define (copy-to target)
    (unless (<= index target (vector-length source))
      (error 'runtime-patch "invalid source position"))
    (let loop ()
      (when (< index target)
        (emit (vector-ref source index))
        (set! index (add1 index))
        (loop))))
  (for ([line (in-list (regexp-match* #px#"[^\n]*\n|[^\n]+$" patch))])
    (cond
      [(regexp-match #px#"^@@ -([0-9]+)(?:,[0-9]+)? [+][0-9]+(?:,[0-9]+)? @@" line)
       => (lambda (match)
            (copy-to (sub1 (string->number (bytes->string/utf-8 (cadr match)))))
            (set! in-hunk? #t))]
      [(not in-hunk?)
       (unless (regexp-match? #px#"^(--- |[+][+][+] )" line)
         (error 'runtime-patch "unexpected patch header"))]
      [else
       (define operation (bytes-ref line 0))
       (define payload (subbytes line 1))
       (unless (memv operation '(32 43 45))
         (error 'runtime-patch "unexpected patch operation"))
       (when (memv operation '(32 45))
         (unless (and (< index (vector-length source))
                      (bytes=? payload (vector-ref source index)))
           (error 'runtime-patch "patch context differs"))
         (set! index (add1 index)))
       (when (memv operation '(32 43)) (emit payload))]))
  (unless in-hunk? (error 'runtime-patch "patch has no hunks"))
  (copy-to (vector-length source))
  (apply bytes-append (reverse output)))

(define (digest content) (bytes->hex-string (sha256-bytes content)))

(define (corrected-expeditor-sources directory patch)
  (unless (equal? (digest patch) expeditor-patch-sha256)
    (error 'prepare-expeditor-runtime "reviewed editor patch checksum differs"))
  (define parts (patches-by-file patch))
  (unless (equal? (sort (hash-keys parts) string<?)
                  (sort (map car expeditor-source-pins) string<?))
    (error 'prepare-expeditor-runtime "editor patch file inventory differs"))
  ;; Validate every input/output before the first write. Interrupted preparation
  ;; can be retried because each file permits only original or corrected bytes.
  (for/list ([pin (in-list expeditor-source-pins)])
    (define source (build-path directory (car pin)))
    (when (link-exists? source)
      (error 'prepare-expeditor-runtime "refusing a symlink editor source"))
    (define original (file->bytes source))
    (define before (digest original))
    (define corrected
      (cond
        [(equal? before (caddr pin)) original]
        [(equal? before (cadr pin))
         (apply-unified-diff original (hash-ref parts (car pin)))]
        [else (error 'prepare-expeditor-runtime "unknown editor source: ~a" (car pin))]))
    (unless (equal? (digest corrected) (caddr pin))
      (error 'prepare-expeditor-runtime "corrected editor source differs: ~a" (car pin)))
    (list source original corrected)))

(define (prepare-expeditor-directory directory patch apply?)
  (define sources (corrected-expeditor-sources directory patch))
  (for ([source (in-list sources)])
    (unless (bytes=? (cadr source) (caddr source))
      (unless apply?
        (error 'prepare-expeditor-runtime "requires the reviewed Expeditor correction"))
      (define permissions (file-or-directory-permissions (car source) 'bits))
      (call-with-atomic-output-file
       (car source)
       (lambda (output temporary)
         (write-bytes (caddr source) output)
         (file-or-directory-permissions temporary permissions))))))

(define (verify-loaded-expeditor)
  ;; Source hashes alone cannot distinguish a loaded upstream compiled module.
  ;; This is tooling-only observation; the product uses public editor APIs.
  (define (binding module name)
    (dynamic-require module #f)
    (parameterize ([current-namespace (module->namespace module)]) (eval name)))
  (define spell (binding 'expeditor/private/terminal 'character-display-string))
  (define width (binding 'expeditor/private/terminal 'char-width))
  (define unicell? (binding 'expeditor/private/wstring 'string-unicell?))
  (unless (and (equal? (spell (integer->char 27)) "^[")
               (= (width (integer->char 27)) 2)
               (equal? (spell (integer->char 155)) "\\x9B")
               (= (width (integer->char 155)) 4)
               (procedure? (binding 'expeditor/private/screen 'ee-write-glyph))
               (procedure? (binding 'expeditor/private/ee 'display-prompt))
               (not (unicell? (string (integer->char 27))))
               (not (unicell? (string (integer->char 155))))
               (eq? (binding 'expeditor 'string-width)
                    (binding 'expeditor/private/wstring 'string-width))
               (eq? (binding 'expeditor 'string-fits-width)
                    (binding 'expeditor/private/wstring 'string-fits-width)))
    (error 'prepare-expeditor-runtime "loaded editor implementation is unpatched")))

(define (prepare-expeditor-runtime apply?)
  (define directory (path-only (collection-file-path "main.rkt" "expeditor")))
  (prepare-expeditor-directory directory (file->bytes expeditor-patch-path) apply?)
  (unless apply?
    (verify-loaded-expeditor)
    (printf "Expeditor patch SHA-256: ~a\n" expeditor-patch-sha256)
    (for ([pin (in-list expeditor-source-pins)])
      (printf "Expeditor ~a SHA-256: ~a\n" (car pin) (caddr pin)))))

(module+ main
  (define arguments (vector->list (current-command-line-arguments)))
  (unless (member arguments '(("--apply") ("--check")))
    (error 'prepare-expeditor-runtime "use --apply only in an isolated toolchain, or --check"))
  (unless (and (equal? (version) "9.3") (eq? (system-type 'vm) 'chez-scheme))
    (error 'prepare-expeditor-runtime "requires Racket CS 9.3"))
  (prepare-expeditor-runtime (equal? arguments '("--apply"))))
