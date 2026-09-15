#lang racket/base

;; Inert history framing. Bounds are checked before decoding or allocating from
;; stored lengths; history text is never passed to a Racket data reader.
(require racket/file racket/path)
(provide history-entry-limit history-byte-limit history->bytes bytes->history
         remember-history read-history write-history)
(define history-entry-limit 1000)
(define history-byte-limit 1048576)
(define history-header #"AttaLambda-history-v1\n")
(define history-prefix-size (+ (bytes-length history-header) 2))

;; Source ownership is decided by the shell. Retain at most 1000 submissions
;; independently of the editor's own shorter close-result history.
(define (remember-history entries text)
  (if (and (string? text) (positive? (string-length text)))
      (for/list ([entry (in-list (cons text entries))]
                 [index (in-range history-entry-limit)])
        entry)
      entries))

;; Entries arrive newest first. Skip entries that cannot fit while retaining
;; later small entries; a history-storage limit must never reject execution.
(define (history->bytes entries)
  (define-values (parts total count)
    (for/fold ([parts '()] [total history-prefix-size] [count 0])
              ([entry (in-list entries)] #:break (= count history-entry-limit))
      (unless (string? entry)
        (raise-argument-error 'history->bytes "list of strings" entries))
      (define available (- history-byte-limit total 4))
      (define size
        (and (<= (string-length entry) available) (string-utf-8-length entry)))
      (if (and size (<= size available))
          (values (cons (string->bytes/utf-8 entry)
                        (cons (integer->integer-bytes size 4 #f #t) parts))
                  (+ total 4 size) (add1 count))
          (values parts total count))))
  (apply bytes-append history-header
         (integer->integer-bytes count 2 #f #t) (reverse parts)))

(define (bytes->history content)
  (define size (bytes-length content))
  (and
   (<= history-prefix-size size history-byte-limit)
   (bytes=? (subbytes content 0 (bytes-length history-header)) history-header)
   (let ([count (integer-bytes->integer content #f #t
                                      (bytes-length history-header) history-prefix-size)])
     (and
      (<= count history-entry-limit)
      (with-handlers ([exn:fail:contract? (lambda (_) #f)])
        (let loop ([remaining count] [offset history-prefix-size] [entries '()])
          (cond
            [(zero? remaining) (and (= offset size) (reverse entries))]
            [(> (+ offset 4) size) #f]
            [else
             (define start (+ offset 4))
             (define length (integer-bytes->integer content #f #t offset start))
             (define end (+ start length))
             (and (<= end size)
                  (loop (sub1 remaining) end
                        (cons (bytes->string/utf-8 content #f start end) entries)))])))))))

(define (history-directory-stat-safe? stat private? root-owner)
  (define mode (hash-ref stat 'mode))
  (and
   (= (bitwise-and mode file-type-bits) directory-type-bits)
   (or (not (eq? (system-type 'os) 'unix))
       (zero? (bitwise-and mode (if private? #o077 #o022)))
       ;; Compare with the filesystem root's observed owner: user namespaces can
       ;; map its UID to a value other than zero. Other owners remain untrusted.
       (and (not private?) (= (hash-ref stat 'user-id) root-owner)
            (not (zero? (bitwise-and mode sticky-bit)))))))

(define (history-file-stat-safe? stat)
  (define mode (hash-ref stat 'mode))
  (and (= (bitwise-and mode file-type-bits) regular-file-type-bits)
       (= (hash-ref stat 'hardlink-count) 1)
       (<= (hash-ref stat 'size) history-byte-limit)
       (or (not (eq? (system-type 'os) 'unix))
           (zero? (bitwise-and mode #o077)))))

(define (checked-history-directory preference-directory #:create? [create? #f])
  (define directory
    (simplify-path
     (path->complete-path
      (build-path (or preference-directory (find-system-path 'pref-dir)) "attalambda"))
     #f))
  (define parts (explode-path directory))
  (and
   ;; Validate all names before the writer can create any missing directory.
   (for/and ([part (in-list parts)])
     (and (path? part)
          (not (regexp-match? #px"(^|\\.)env($|\\.)" (string-downcase (path->string part))))))
   (let loop ([parts parts] [parent #f] [root-owner #f])
     (cond
       [(null? parts) parent]
       [else
        (define path (if parent (build-path parent (car parts)) (car parts)))
        (when (and create? (not (file-or-directory-type path)))
          (make-directory path #o700))
        (and
         (eq? (file-or-directory-type path) 'directory)
         (let* ([stat (file-or-directory-stat path #t)]
                [owner (or root-owner (hash-ref stat 'user-id))])
           (and (history-directory-stat-safe? stat (null? (cdr parts)) owner)
                (loop (cdr parts) path owner))))]))))

(define (read-history enabled? #:preference-directory [preference-directory #f])
  ;; Disabled means no path discovery or metadata/content access of any kind.
  (if (not enabled?) '()
      (with-handlers ([exn:fail? (lambda (_) '())])
        (define directory (checked-history-directory preference-directory))
        (or
         (and
          directory
          (let ([path (build-path directory "history-v1")])
            (and
             (eq? (file-or-directory-type path) 'file)
             (let ([before (file-or-directory-stat path #t)])
               (and
                (history-file-stat-safe? before)
                (call-with-input-file
                 path
                 (lambda (input)
                   (define opened (port-file-stat input))
                   (and
                    (history-file-stat-safe? opened)
                    (= (hash-ref before 'device-id) (hash-ref opened 'device-id))
                    (= (hash-ref before 'inode) (hash-ref opened 'inode))
                    (let ([content (read-bytes (add1 history-byte-limit) input)])
                      (and (bytes? content) (bytes->history content)))))))))))
         '()))))

(define (history-replacement-safe? path)
  (define type (file-or-directory-type path))
  (or (not type)
      (and (eq? type 'file)
           (history-file-stat-safe? (file-or-directory-stat path #t)))))

(define (write-history enabled? entries #:preference-directory [preference-directory #f])
  (when enabled?
    (with-handlers ([exn:fail? void])
      (define content (history->bytes entries))
      (define directory (checked-history-directory preference-directory #:create? #t))
      (when directory
        (define path (build-path directory "history-v1"))
        (when (history-replacement-safe? path)
          (call-with-atomic-output-file
           path
           (lambda (output temporary)
             ;; The temporary starts inside a private directory. Restrict its
             ;; mode before writing any source, then recheck the replacement path.
             (file-or-directory-permissions temporary #o600)
             (write-bytes content output)
             (unless (and (checked-history-directory preference-directory)
                          (history-replacement-safe? path))
               (error 'history "history target changed during save")))
           #:rename-fail-handler (lambda (failure _) (raise failure))))))))
