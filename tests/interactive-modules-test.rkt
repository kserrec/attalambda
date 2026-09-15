#lang racket/base

;; Tiny trusted module-plumbing proofs. The production interaction path will
;; use the checked expander; these modules deliberately expose only fixtures.
(require rackunit
         racket/promise
         racket/runtime-path)

(define-runtime-path facade "../lang/expander.rkt")
(define-runtime-path renderer "../core/to-string.rkt")
(define-runtime-path string-reader "../readers/string.rkt")
(define-runtime-path host-path "../runtime/host.rkt")

(define owner (make-custodian))
(define replacement-owner (make-custodian))
(define input (open-input-bytes #"saved-answer\nremaining\n"))

(dynamic-wind
 void
 (lambda ()
   (parameterize ([current-custodian owner]
                  [current-input-port input]
                  [current-namespace (make-base-namespace)])
     (define facade-path `(file ,(path->string facade)))
     (dynamic-require facade-path #f)
     (define render (dynamic-require renderer 'value-to-string))
     (define observe (dynamic-require string-reader 'string-value->string))
     (define (shown value) (observe ((force render) value)))
     (eval `(module retained lazy
              (require (prefix-in a: ,facade-path))
              (provide answer)
              (define answer (a:read-line a:UNIT))))
     (define answer (dynamic-require ''retained 'answer))
     (check-equal? (file-position input) 0 "export lookup must not demand input")
     (eval '(module imported lazy
              (require (only-in 'retained answer))
              (provide again)
              (define again answer)))
     (define again (dynamic-require ''imported 'again))
     (check-equal? (file-position input) 0 "module import must not demand input")
     (check-equal? (shown again) "OK(SOME(\"saved-answer\"))")
     (check-equal? (file-position input) 13)
     (check-equal? (shown answer) "OK(SOME(\"saved-answer\"))")
     (check-equal? (file-position input) 13 "reusing a binding must not reread")
     (check-equal? (read-bytes-line input) #"remaining")

     (eval `(module original lazy
              (require (prefix-in a: ,facade-path))
              (provide x plus-x)
              (define x (a:#%datum . 1))
              (define plus-x (lambda (n) ((a:add x) n)))))
     (eval `(module replacement lazy
              (require (prefix-in a: ,facade-path))
              (provide x)
              (define x (a:#%datum . 10))))
     (eval `(module snapshots lazy
              (require (prefix-in a: ,facade-path)
                       (only-in 'original plus-x)
                       (only-in 'replacement x))
              (provide old-result current-result)
              (define old-result (plus-x (a:#%datum . 1)))
              (define current-result ((a:add x) (a:#%datum . 1)))))
     (check-equal? (shown (dynamic-require ''snapshots 'old-result)) "2")
     (check-equal? (shown (dynamic-require ''snapshots 'current-result)) "11")

     (define original-host (dynamic-require host-path 'host))
     (define original-host-namespace (module->namespace host-path))
     (define (registry-count namespace)
       (parameterize ([current-namespace namespace])
         (eval '(hash-count handle-registry))))
     (check-equal? (registry-count original-host-namespace) 0)
     (eval `(module listener lazy
              (require (prefix-in a: ,facade-path))
              (provide pending)
              (define pending
                (((a:tcp-listen (a:#%datum . "127.0.0.1"))
                  (a:#%datum . 0))
                 (a:#%datum . 1)))))
     (force (dynamic-require ''listener 'pending))
     (check-equal? (registry-count original-host-namespace) 1)
     (parameterize ([current-custodian replacement-owner]
                    [current-namespace (make-base-namespace)])
       ;; Load anew; never attach an already-instantiated expander/runtime graph.
       (dynamic-require facade-path #f)
       (check-not-eq? (dynamic-require host-path 'host) original-host)
       (check-equal? (registry-count (module->namespace host-path)) 0)
       (check-equal? (registry-count original-host-namespace) 1))))
 (lambda ()
   (close-input-port input)
   (custodian-shutdown-all owner)
   (custodian-shutdown-all replacement-owner)))
