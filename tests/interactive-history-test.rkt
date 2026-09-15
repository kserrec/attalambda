#lang racket/base

(require rackunit racket/file racket/list racket/system "../runner/history.rkt")

(define header #"AttaLambda-history-v1\n")
(define (framed count payload)
  (bytes-append header (integer->integer-bytes count 2 #f #t) payload))

(test-case "in-memory navigation keeps the latest1000 complete source strings without a source-size limit"
  (define entries
    (for/fold ([entries '()]) ([index (in-range 1002)])
      (remember-history entries (number->string index))))
  (check-equal? entries (for/list ([index (in-range 1001 1 -1)]) (number->string index)))
  (check-equal? (remember-history entries #f) entries)
  (check-equal? (remember-history entries "") entries)
  (define oversized (make-string (add1 history-byte-limit) #\x))
  (define remembered (remember-history entries oversized))
  (check-eq? (car remembered) oversized)
  (check-equal? (length remembered) 1000)
  (check-equal? (bytes->history (history->bytes remembered)) (take entries 999)))

(test-case "history framing preserves inert multiline Unicode source in newest-first order"
  (define entries '("(add 1\n  2)" ":echo off" "λ and 🙂" "#reader \"never-run.rkt\""))
  (check-equal? (bytes->history (history->bytes entries)) entries)
  (check-equal? (history->bytes '("a" "λ"))
                (bytes-append header #"\0\2\0\0\0\1a\0\0\0\2\316\273"))
  (check-equal? (bytes->history (history->bytes '())) '()))

(test-case "history count and total bytes are bounded; oversized entries remain skippable"
  (define entries (for/list ([index (in-range 1002)]) (number->string index)))
  (check-equal? (bytes->history (history->bytes entries)) (take entries 1000))
  (define oversized (make-string (add1 history-byte-limit) #\x))
  (check-equal? (bytes->history (history->bytes (list oversized "retained"))) '("retained"))
  (define wide (make-string (quotient history-byte-limit 2) #\λ))
  (check-equal? (bytes->history (history->bytes (list wide "small"))) '("small"))
  (define exact (make-string (- history-byte-limit (bytes-length header) 2 4) #\x))
  (define encoded (history->bytes (list exact "cannot-fit")))
  (check-equal? (bytes-length encoded) history-byte-limit)
  (check-equal? (bytes->history encoded) (list exact)))

(test-case "malformed history rejects invalid lengths, counts, UTF-8, versions and trailing data"
  (define valid (history->bytes '("hello" "world")))
  (for ([end (in-range (bytes-length valid))])
    (check-false (bytes->history (subbytes valid 0 end))))
  (for ([bad (list #"#reader \"never-run.rkt\""
                   (framed 1001 #"")
                   (framed 1 #"\377\377\377\377")
                   (framed 1 #"\0\0\0\1\377")
                   (framed 1 #"\0\0\0\2\303\0")
                   (framed 0 #"trailing")
                   (bytes-append valid #"trailing")
                   (make-bytes (add1 history-byte-limit) 0))])
    (check-false (bytes->history bad)))
  (define wrong-version (bytes-copy valid))
  (bytes-set! wrong-version (- (bytes-length header) 2) (char->integer #\2))
  (check-false (bytes->history wrong-version)))

(test-case "history decoding and encoding perform no filesystem or network effects"
  (define guard
    (make-security-guard (current-security-guard)
                         (lambda args (error 'history "unexpected filesystem access"))
                         (lambda args (error 'history "unexpected network access"))))
  (parameterize ([current-security-guard guard])
    (check-equal? (bytes->history (history->bytes '("#reader \"forbidden\"")))
                  '("#reader \"forbidden\""))))

(define (with-history-fixture action)
  (define root (make-temporary-directory "attalambda-history-~a"))
  (dynamic-wind
   void
   (lambda ()
     (file-or-directory-permissions root #o700)
     (define preference (build-path root "preferences"))
     (define private (build-path preference "attalambda"))
     (make-directory preference #o700)
     (make-directory private #o700)
     (action preference private (build-path private "history-v1") root))
   (lambda () (delete-directory/files root))))

(define (write-history-fixture path content)
  (call-with-output-file path #:exists 'truncate #:permissions #o600
    (lambda (output) (void (write-bytes content output)))))

(test-case "safe history reading uses only a validated regular private file"
  (with-history-fixture
   (lambda (preference private path root)
     (check-equal? (read-history #t #:preference-directory preference) '())
     (define entries '("(add 1\n  2)" ":names" "#reader \"never-execute\""))
     (write-history-fixture path (history->bytes entries))
     (check-equal? (read-history #t #:preference-directory preference) entries)
     (write-history-fixture path #"invalid history")
     (check-equal? (read-history #t #:preference-directory preference) '()))))

(test-case "disabled history does not discover, stat or open any path"
  (define accesses '())
  (define guard
    (make-security-guard
     (current-security-guard)
     (lambda arguments (set! accesses (cons arguments accesses)) (error 'test "forbidden"))
     (lambda arguments (set! accesses (cons arguments accesses)) (error 'test "forbidden"))))
  (parameterize ([current-security-guard guard])
    (check-equal? (read-history #f) '())
    (write-history #f '("must not persist")))
  ;; Observe calls outside the protected function, so its best-effort handler
  ;; cannot turn an unexpected filesystem attempt into a false passing test.
  (check-equal? accesses '()))

(test-case "unsafe targets are rejected before any content-read attempt"
  (for ([kind '(link ancestor-link directory shared-file shared-directory
                    shared-ancestor oversized fifo hardlink)])
    (with-history-fixture
     (lambda (preference private path root)
       (define expected '("valid"))
       (define safe (build-path root "safe-target"))
       (write-history-fixture safe (history->bytes expected))
       (case kind
         [(link) (make-file-or-directory-link safe path)]
         [(ancestor-link)
          (delete-directory private)
          (define actual (build-path root "actual"))
          (make-directory actual #o700)
          (write-history-fixture (build-path actual "history-v1") (history->bytes expected))
          (make-file-or-directory-link actual private)]
         [(directory) (make-directory path #o700)]
         [(fifo hardlink)
          (check-true
           (system* (find-executable-path "python3") "-c"
                    (if (eq? kind 'fifo)
                        "import os,sys; os.mkfifo(sys.argv[1], 0o600)"
                        "import os,sys; os.link(sys.argv[2], sys.argv[1])")
                    path safe))]
         [else
          (write-history-fixture path
                                 (if (eq? kind 'oversized)
                                     (make-bytes (add1 history-byte-limit) 0)
                                     (history->bytes expected)))
          (case kind
            [(shared-file) (file-or-directory-permissions path #o644)]
            [(shared-directory) (file-or-directory-permissions private #o755)]
            [(shared-ancestor) (file-or-directory-permissions preference #o777)])])
       (define content-reads '())
       (define guard
         (make-security-guard
          (current-security-guard)
          (lambda (who target permissions)
            (when (memq 'read permissions)
              (set! content-reads (cons target content-reads))
              (error 'test "unsafe content read")))
          (lambda args (error 'test "unexpected network"))))
       (parameterize ([current-security-guard guard])
         (check-equal? (read-history #t #:preference-directory preference) '() (format "~a" kind)))
       (check-equal? content-reads '() (format "~a" kind))))))

(test-case "history read failures stay best effort but interruption propagates"
  (with-history-fixture
   (lambda (preference private path root)
     (write-history-fixture path (history->bytes '("valid")))
     (define attempts 0)
     (define guard
       (make-security-guard
        (current-security-guard)
        (lambda (who target permissions)
          (when (memq 'read permissions)
            (set! attempts (add1 attempts))
            (error 'test "injected read failure")))
        (lambda args (void))))
     (parameterize ([current-security-guard guard])
       (check-equal? (read-history #t #:preference-directory preference) '()))
     (check-equal? attempts 1)
     (define break-guard
       (make-security-guard
        (current-security-guard)
        (lambda (who target permissions)
          (when (memq 'read permissions)
            (break-thread (current-thread))
            (break-enabled #t)))
        (lambda args (void))))
     (parameterize ([current-security-guard break-guard])
       (check-exn exn:break? (lambda () (read-history #t #:preference-directory preference)))))))

(test-case "history saves create private directories and atomically replace bounded data"
  (with-history-fixture
   (lambda (preference private path root)
     (define fresh (build-path root "missing" "preferences"))
     (define target (build-path fresh "attalambda" "history-v1"))
     (define entries '("(add 1\n  2)" "λ" ":names"))
     (write-history #t entries #:preference-directory fresh)
     (check-equal? (read-history #t #:preference-directory fresh) entries)
     (for ([directory (list (build-path root "missing") fresh (build-path fresh "attalambda"))])
       (check-equal? (bitwise-and (file-or-directory-permissions directory 'bits) #o777) #o700))
     (check-equal? (bitwise-and (file-or-directory-permissions target 'bits) #o777) #o600)
     (define many (for/list ([index (in-range 1002)]) (number->string index)))
     (write-history #t (cons (make-string (add1 history-byte-limit) #\x) many)
                    #:preference-directory fresh)
     (check-equal? (read-history #t #:preference-directory fresh) (take many 1000))
     (check-true (<= (file-size target) history-byte-limit))
     (check-equal? (directory-list (build-path fresh "attalambda"))
                   (list (string->path "history-v1"))))))

(test-case "unsafe existing history targets remain untouched and are not read during saves"
  (for ([kind '(link directory shared-file shared-directory shared-ancestor oversized fifo hardlink)])
    (with-history-fixture
     (lambda (preference private path root)
       (define safe (build-path root "safe-target"))
       (write-history-fixture safe (history->bytes '("old")))
       (case kind
         [(link) (make-file-or-directory-link safe path)]
         [(directory) (make-directory path #o700)]
         [(fifo hardlink)
          (check-true
           (system* (find-executable-path "python3") "-c"
                    (if (eq? kind 'fifo)
                        "import os,sys; os.mkfifo(sys.argv[1], 0o600)"
                        "import os,sys; os.link(sys.argv[2], sys.argv[1])") path safe))]
         [else
          (write-history-fixture path (if (eq? kind 'oversized)
                                          (make-bytes (add1 history-byte-limit) 0)
                                          (history->bytes '("old"))))
          (case kind
            [(shared-file) (file-or-directory-permissions path #o644)]
            [(shared-directory) (file-or-directory-permissions private #o755)]
            [(shared-ancestor) (file-or-directory-permissions preference #o777)])])
       (define before (file-or-directory-stat path #t))
       (define accesses '())
       (define guard
         (make-security-guard
          (current-security-guard)
          (lambda (who target permissions)
            (when (ormap (lambda (permission) (memq permission '(read write delete))) permissions)
              (set! accesses (cons (list who target permissions) accesses))
              (error 'test "unsafe content access")))
          (lambda args (error 'test "unexpected network"))))
       (parameterize ([current-security-guard guard])
         (write-history #t '("new") #:preference-directory preference))
       (check-equal? accesses '() (format "~a" kind))
       (check-equal? (file-or-directory-stat path #t) before (format "~a" kind))
       (check-equal? (file->bytes safe) (history->bytes '("old")))))))

(test-case "save failures and breaks preserve the prior file and remove the temporary"
  (for ([kind '(write rename break)])
    (with-history-fixture
     (lambda (preference private path root)
       (define original (history->bytes '("preserved")))
       (write-history-fixture path original)
       (define attempts 0)
       (define guard
         (make-security-guard
          (current-security-guard)
          (lambda (who target permissions)
            (when (and (zero? attempts)
                       (if (eq? kind 'write)
                           (and (eq? who 'open-output-file) (memq 'write permissions))
                           (eq? who 'rename-file-or-directory)))
              (set! attempts (add1 attempts))
              (if (eq? kind 'break)
                  (begin (break-thread (current-thread)) (break-enabled #t))
                  (error 'test "injected save failure"))))
          (lambda args (void))))
       (parameterize ([current-security-guard guard])
         (if (eq? kind 'break)
             (check-exn exn:break?
                        (lambda () (write-history #t '("replacement") #:preference-directory preference)))
             (write-history #t '("replacement") #:preference-directory preference)))
       (check-equal? attempts 1 (format "~a" kind))
       (check-equal? (file->bytes path) original (format "~a" kind))
       (check-equal? (directory-list private) (list (string->path "history-v1")))))))
