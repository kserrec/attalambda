#lang racket/base

;; CS 9.3's editor uses fd0/fd1. Select stderr only during source editing;
;; Expeditor owns terminal modes and input. Load this POSIX adapter lazily.
(require ffi/unsafe)
(provide call-with-editor-output)

(define libc (ffi-lib #f))
(define duplicate (get-ffi-obj "dup" libc (_fun _int -> _int)))
(define duplicate-to (get-ffi-obj "dup2" libc (_fun _int _int -> _int)))
(define close-descriptor (get-ffi-obj "close" libc (_fun _int -> _int)))

(define (call-with-editor-output action)
  (define saved #f)
  (define action-failed? #f)
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
   (lambda ()
     (set! action-failed? #f)
     (with-handlers ([(lambda (_) #t)
                      (lambda (failure) (set! action-failed? #t) (raise failure))])
       (action)))
   (lambda ()
     (parameterize-break #f
       (with-handlers ([(lambda (_) #t)
                        (lambda (failure) (unless action-failed? (raise failure)))])
         ;; Even a failed final flush must restore stdout and close its copy.
         (dynamic-wind
          void
          (lambda () (flush-output (current-output-port)))
          (lambda ()
            (define restored (duplicate-to saved 1))
            (close-descriptor saved)
            (set! saved #f)
            (when (< restored 0) (error 'editor "cannot restore stdout")))))))))
