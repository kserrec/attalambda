#lang racket/base

;; Probe the minimum adaptation required by CS 9.3's fd-0/fd-1 editor.
;; No terminal-mode or input implementation lives here.
(require ffi/unsafe)
(provide call-with-editor-output)

(define libc (ffi-lib #f))
(define duplicate (get-ffi-obj "dup" libc (_fun _int -> _int)))
(define duplicate-to (get-ffi-obj "dup2" libc (_fun _int _int -> _int)))
(define close-descriptor (get-ffi-obj "close" libc (_fun _int -> _int)))

(define (call-with-editor-output action)
  (define saved #f)
  (dynamic-wind
   (lambda ()
     (parameterize-break #f
       (flush-output (current-output-port))
       (set! saved (duplicate 1))
       (when (< saved 0) (error 'editor "cannot preserve stdout"))
       (when (< (duplicate-to 2 1) 0)
         (close-descriptor saved)
         (set! saved #f)
         (error 'editor "cannot select UI output"))))
   action
   (lambda ()
     (parameterize-break #f
       (flush-output (current-output-port))
       (define restored (duplicate-to saved 1))
       (close-descriptor saved)
       (set! saved #f)
       (when (< restored 0) (error 'editor "cannot restore stdout"))))))
