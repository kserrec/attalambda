#lang racket/base

(require rackunit
         racket/file
         racket/promise
         "../core/errors.rkt"
         "../core/lists.rkt"
         "../core/objects.rkt"
         "../core/pair.rkt"
         "../core/result.rkt"
         "../core/tags.rkt"
         "../effects/files.rkt"
         "../readers/bool.rkt"
         "../readers/raw-boolean.rkt"
         "../readers/type-tag.rkt"
         "../runtime/codec.rkt"
         "../runtime/host.rkt"
         "helpers/lazy.rkt")

(define (typed-value? type value)
  (raw-boolean->boolean
   (apply2 raw-is-type type value)))

(define (error-kind-integer error)
  (type-tag->integer
   (lazy-apply raw-error-root-kind
               (lazy-apply raw-error-root error))))

(define (error-detail-strings error)
  (define details
    (lazy-apply
     raw-error-root-details
     (lazy-apply raw-error-root error)))
  (list
   (object-string->bytes
    (lazy-apply raw-first details))
   (object-string->bytes
    (lazy-apply raw-second details))))

(define (text->object-string value)
  (bytes->object-string
   (string->bytes/utf-8 value)))

(define (path->object-string value)
  (text->object-string
   (path->string value)))

(define (check-ok-unit value)
  (check-true (typed-value? result-type value))
  (check-true (bool->boolean
               (lazy-apply is-ok value)))
  (check-equal?
   (type-tag->integer
    (lazy-apply raw-object-type
                (lazy-apply unwrap-ok value)))
   8))

;; Read results carry a List of Byte since the Step 37.3 switch.
(define (check-ok-bytes value expected)
  (check-true (typed-value? result-type value))
  (check-true (bool->boolean
               (lazy-apply is-ok value)))
  (check-equal?
   (object-byte-list->bytes
    (lazy-apply unwrap-ok value))
   expected))

(define (check-host-failure value operation code)
  (check-true (typed-value? result-type value))
  (check-true (bool->boolean
               (lazy-apply is-err value)))
  (define error
    (lazy-apply unwrap-err value))
  (check-equal? (error-kind-integer error) 8)
  (check-equal? (error-detail-strings error)
                (list operation code)))

(define (write-host-bytes path payload)
  (call-with-output-file path
    #:exists 'truncate
    (lambda (output)
      (write-bytes payload output))))

(define (errno-guard errno)
  (make-security-guard
   (current-security-guard)
   (lambda (who path permissions)
     (raise
      (make-exn:fail:filesystem:errno
       "synthetic filesystem failure"
       (current-continuation-marks)
       errno)))
   (lambda (who host-name port mode)
     (void))))

(define out-of-memory-guard
  (make-security-guard
   (current-security-guard)
   (lambda (who path permissions)
     (raise
      (make-exn:fail:out-of-memory
       "synthetic resource exhaustion"
       (current-continuation-marks))))
   (lambda (who host-name port mode)
     (void))))

(define no-delete-guard
  (make-security-guard
   (current-security-guard)
   (lambda (who path permissions)
     (when (memq 'delete permissions)
       (raise
        (make-exn:fail:filesystem:errno
         "delete authority denied"
         (current-continuation-marks)
         (cons 13 'posix)))))
   (lambda (who host-name port mode)
     (void))))

(define read-file-with-host
  (lazy-apply make-read-file host))

(define write-file-with-host
  (lazy-apply make-write-file host))

(define temporary-root
  (make-temporary-file "attalambda-files-~a"
                       'directory
                       (current-directory)))

(dynamic-wind
  void
  (lambda ()
    (define content-path
      (build-path temporary-root "content.bin"))
    (define content-path-value
      (path->object-string content-path))
    (define initial-bytes
      #"\0\1\177\200\377lambda-bytes")

    ;; A new write is lazy, writes every byte only when demanded, and forcing
    ;; the same application again does not repeat the replacement.
    (define pending-write
      (apply2 write-file-with-host
              content-path-value
              (bytes->object-byte-list initial-bytes)))
    (check-false (file-exists? content-path))
    (check-ok-unit pending-write)
    (check-equal? (file->bytes content-path) initial-bytes)

    (write-host-bytes content-path #"outside-change")
    (check-ok-unit pending-write)
    (check-equal? (file->bytes content-path) #"outside-change")

    ;; A fresh write truncates an existing longer file. Reads return complete,
    ;; byte-exact object Strings without a reader or text normalization.
    (define replacement #"short\0\377")
    (check-ok-unit
     (apply2 write-file-with-host
             content-path-value
             (bytes->object-byte-list replacement)))
    (check-equal? (file->bytes content-path) replacement)
    (check-ok-bytes
     (lazy-apply read-file-with-host content-path-value)
     replacement)

    ;; Empty files and relative UTF-8 paths use the same byte-exact contract.
    (define relative-name "relative-\u03bb.bin")
    (parameterize ([current-directory temporary-root])
      (check-ok-unit
       (apply2 write-file-with-host
               (text->object-string relative-name)
               (bytes->object-byte-list #"")))
      (check-ok-bytes
       (lazy-apply read-file-with-host
                   (text->object-string relative-name))
       #""))
    (check-equal? (file->bytes
                   (build-path temporary-root relative-name))
                  #"")

    ;; Truncation follows a symlink and needs write authority only. In
    ;; particular, write-file must never fall back to deleting the symlink and
    ;; creating a different regular file at its path.
    (define symlink-target
      (build-path temporary-root "symlink-target.bin"))
    (define symlink-path
      (build-path temporary-root "symlink.bin"))
    (write-host-bytes symlink-target #"target-before")
    (make-file-or-directory-link symlink-target symlink-path)
    (parameterize ([current-security-guard no-delete-guard])
      (check-ok-unit
       (apply2 write-file-with-host
               (path->object-string symlink-path)
               (bytes->object-byte-list #"target-after"))))
    (check-true (link-exists? symlink-path))
    (check-equal? (file->bytes symlink-target) #"target-after")
    (check-equal? (file->bytes symlink-path) #"target-after")

    ;; Missing paths and invalid path encodings are expected host failures.
    (check-host-failure
     (lazy-apply
      read-file-with-host
      (path->object-string
       (build-path temporary-root "missing.bin")))
     #"read-file"
     #"not-found")

    (check-host-failure
     (lazy-apply read-file-with-host
                 (bytes->object-string #"\377"))
     #"read-file"
     #"invalid-text")

    (check-host-failure
     (lazy-apply read-file-with-host
                 (bytes->object-string #"bad\0path"))
     #"read-file"
     #"invalid-path")

    (check-host-failure
     (apply2 write-file-with-host
             (bytes->object-string #"\377")
             (bytes->object-byte-list #"bytes"))
     #"write-file"
     #"invalid-text")

    (check-host-failure
     (apply2 write-file-with-host
             (bytes->object-string #"bad\0path")
             (bytes->object-byte-list #"bytes"))
     #"write-file"
     #"invalid-path")

    (check-host-failure
     (apply2
      write-file-with-host
      (path->object-string
       (build-path temporary-root "missing-parent" "file.bin"))
      (bytes->object-byte-list #"bytes"))
     #"write-file"
     #"not-found")

    ;; Reading a directory is a stable generic filesystem failure in Racket.
    (check-host-failure
     (lazy-apply read-file-with-host
                 (path->object-string temporary-root))
     #"read-file"
     #"io-failure")

    ;; Deterministic security guards prove the stable errno categories without
    ;; depending on this test process's account permissions or open-file limit.
    (parameterize ([current-security-guard
                    (errno-guard (cons 13 'posix))])
      (check-host-failure
       (lazy-apply read-file-with-host content-path-value)
       #"read-file"
       #"permission-denied")
      (check-host-failure
       (apply2 write-file-with-host
               content-path-value
               (bytes->object-byte-list #"denied"))
       #"write-file"
       #"permission-denied"))

    (parameterize ([current-security-guard
                    (errno-guard (cons 24 'posix))])
      (check-host-failure
       (lazy-apply read-file-with-host content-path-value)
       #"read-file"
       #"resource-exhausted"))

    (parameterize ([current-security-guard out-of-memory-guard])
      (check-host-failure
       (lazy-apply read-file-with-host content-path-value)
       #"read-file"
       #"resource-exhausted"))

    (parameterize ([current-security-guard
                    (errno-guard (cons 110 'posix))])
      (check-host-failure
       (lazy-apply read-file-with-host content-path-value)
       #"read-file"
       #"timed-out")))
  (lambda ()
    (delete-directory/files temporary-root)))

(check-false (directory-exists? temporary-root))
