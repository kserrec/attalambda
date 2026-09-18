#lang racket/base

(require rackunit racket/async-channel racket/file racket/tcp
         "../runner/static/frontend.rkt" "../runner/source-file.rkt"
         "../lang/static-data.rkt" "../runner/static/analysis.rkt")

(define directory (make-temporary-file "attalambda-static-effects-~a" 'directory))
(define marker (build-path directory "marker.txt"))
(define data-file (build-path directory "program-data.txt"))
(define listener (tcp-listen 0 4 #t "127.0.0.1"))
(define-values (local port remote remote-port) (tcp-addresses listener #t))
(define file-attempts 0)
(define network-attempts 0)
(define exits 0)
(define guard
  (make-security-guard
   (current-security-guard)
   (lambda (who path modes)
     (when (and path (member (simplify-path (path->complete-path path) #f)
                             (list marker data-file))
                (or (memq 'read modes) (memq 'write modes)))
       (set! file-attempts (add1 file-attempts))
       (error 'test "program file access during analysis")))
   (lambda (who host port mode)
     (set! network-attempts (add1 network-attempts))
     (error 'test "program network access during analysis"))))

(define (bounded-prepare text)
  (define owner (make-custodian))
  (define channel (make-async-channel))
  (dynamic-wind
   void
   (lambda ()
     (parameterize ([current-custodian owner])
       (thread (lambda ()
                 (async-channel-put
                  channel
                  (with-handlers ([exn? values])
                    (define view (prepare-source (validated-source 'effects.attl text 2 0 17) #:analysis? #t))
                    (if (source-problem? view) view (analyze-view view)))))))
     (define result (sync/timeout 20 channel))
     (unless result (error 'test "source analysis exceeded its deadline"))
     (when (exn? result) (raise result))
     result)
   (lambda () (custodian-shutdown-all owner))))

(dynamic-wind
 (lambda () (call-with-output-file data-file (lambda (output) (display "private data" output))))
 (lambda ()
   (test-case "guard positive controls observe program file and network attempts"
     (parameterize ([current-security-guard guard])
       (check-exn #rx"program file access" (lambda () (file->string data-file)))
       (check-exn #rx"program network access" (lambda () (tcp-connect "127.0.0.1" port))))
     (check-equal? file-attempts 1)
     (check-equal? network-attempts 1)
     (set! file-attempts 0)
     (set! network-attempts 0))
   (test-case "demanded program effects and divergence are analyzed without execution"
     (define input (open-input-string "answer one\nanswer two\n"))
     (define output (open-output-string))
     (parameterize ([current-security-guard guard]
                    [current-input-port input] [current-output-port output]
                    [exit-handler (lambda (_) (set! exits (add1 exits))
                                    (error 'test "program exit during analysis"))])
       (for ([text (list "(stdout \"must-not-run\")" "(read-line UNIT)" "(exit 1)"
                         "(host (list \"stdout\" \"raw-must-not-run\"))"
                         (format "(read-file ~s)" (path->string data-file))
                         (format "(write-file ~s (string-to-bytes \"marker\"))" (path->string marker))
                         (format "(tcp-connect \"127.0.0.1\" ~a)" port)
                         "(rec loop x = (loop x)) (loop 0)"
                         "(rec loop = loop) loop")])
         (check-true (analysis? (bounded-prepare text)) text))
       (for ([text '("(stdout \"prefix\") missing" "(stdout \"prefix\") (")])
         (check-true (source-problem? (bounded-prepare text)) text)))
     (check-equal? (file-position input) 0)
     (check-equal? (get-output-string output) "")
     (check-equal? file-attempts 0)
     (check-equal? network-attempts 0)
     (check-equal? exits 0)
     (check-false (file-exists? marker))
     (check-equal? (file->string data-file) "private data")
     (check-false (tcp-accept-ready? listener))))
 (lambda () (tcp-close listener) (delete-directory/files directory)))
