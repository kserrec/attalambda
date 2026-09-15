#lang racket/base

(provide make-shell-output)

;; Observe only accepted program bytes. The destination remains live; no payload
;; is retained, and closing this forwarding port never closes original stdout.
(define (make-observed-output destination)
  (define total 0)
  (define last-byte #f)
  (define observed
    (make-output-port
     'program-stdout destination
     (lambda (bytes start end nonblocking? breakable?)
       (cond
         [(= start end)
          (parameterize-break breakable? (flush-output destination))
          0]
         [else
          (define written
            ((cond [nonblocking? write-bytes-avail*]
                   [breakable? write-bytes-avail/enable-break]
                   [else write-bytes-avail])
             bytes destination start end))
          (cond
            [(and written (positive? written))
             (set! total (+ total written))
             (set! last-byte (bytes-ref bytes (+ start written -1)))
             written]
            [else (wrap-evt destination (lambda (_) #f))])]))
     void))
  (values observed (lambda () (values total last-byte))))

(define (make-shell-output output ui shared-terminal?)
  (define-values (program-output metadata) (make-observed-output output))
  (define result-boundary 0)
  (define ui-boundary 0)
  (define (result-output rendered)
    (define-values (total last-byte) (metadata))
    (when (and (> total result-boundary) (not (equal? last-byte 10))
               (not (and shared-terminal? (>= ui-boundary total))))
      (newline output))
    (fprintf output "=> ~a\n" rendered)
    (flush-output output)
    (set! result-boundary total)
    (set! ui-boundary total))
  (define (prepare-ui)
    (define-values (total last-byte) (metadata))
    (when (and shared-terminal? (> total ui-boundary) (not (equal? last-byte 10)))
      (newline ui)
      (flush-output ui))
    ;; A UI newline does not separate redirected stdout from its next result.
    (set! ui-boundary total))
  (values program-output result-output prepare-ui))
