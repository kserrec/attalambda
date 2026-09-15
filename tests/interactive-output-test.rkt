#lang racket/base

(require rackunit racket/port "../runner/output.rkt")

(define (bounded-read count input)
  (define result (sync/timeout 5 (read-bytes-evt count input)))
  (unless result (error 'bounded-read "output did not arrive within five seconds"))
  result)

(define (with-pipe action)
  (define owner (make-custodian))
  (define-values (input target) (make-pipe 2))
  (define error (open-output-bytes))
  (define-values (output result ui) (make-shell-output target error #f))
  (dynamic-wind
   void
   (lambda ()
     (parameterize ([current-custodian owner])
       (action input target output result ui)))
   (lambda ()
     (custodian-shutdown-all owner)
     (close-input-port input)
     (for ([port (in-list (list output target error))])
       (unless (port-closed? port) (close-output-port port))))))

(define (with-output-ports action)
  (define ports '())
  (define (own port) (set! ports (cons port ports)) port)
  (dynamic-wind void (lambda () (action own))
                (lambda ()
                  (for ([port (in-list ports)] #:unless (port-closed? port))
                    (close-output-port port)))))

(test-case "program bytes forward exactly; each result gets only its necessary separator"
  (with-output-ports
   (lambda (own)
      (define target (own (open-output-bytes)))
      (define error (own (open-output-bytes)))
      (define-values (out result ui) (make-shell-output target error #f))
      (own out)
      (write-bytes #"ignoredabc\rignored" out 7 11)
      (check-equal? (get-output-bytes target) #"abc\r")
      (result "1")
      (result "2")
      (write-byte 195 out) (write-byte 169 out)
      (write-bytes #"\0\377\33[1G" out)
      (result "3")
      (write-bytes #"line\n" out)
      (result "4")
      (write-bytes #"" out) (flush-output out)
      (result "5")
      (check-equal? (get-output-bytes target)
                    #"abc\r\n=> 1\n=> 2\n\303\251\0\377\33[1G\n=> 3\nline\n=> 4\n=> 5\n")
      (check-equal? (get-output-bytes error) #"")
      (close-output-port out)
      (check-false (port-closed? target)))))

(test-case "UI separates a shared terminal but never contaminates redirected stdout"
  (with-output-ports
   (lambda (own)
      (for ([shared? '(#t #f)])
        (define target (own (open-output-bytes)))
        (define error (own (open-output-bytes)))
        (define-values (out result ui) (make-shell-output target error shared?))
      (own out)
        (write-bytes #"fragment" out)
        (ui) (ui)
        (check-equal? (get-output-bytes target) #"fragment")
        (check-equal? (get-output-bytes error) (if shared? #"\n" #""))
        (result "TRUE")
        (ui)
        (check-equal? (get-output-bytes target)
                      (if shared? #"fragment=> TRUE\n" #"fragment\n=> TRUE\n"))
        (write-bytes #"complete\n" out)
        (ui)
        (check-equal? (get-output-bytes error) (if shared? #"\n" #""))))))

(test-case "nonblocking partial writes preserve accepted bytes and readiness"
  (with-pipe
   (lambda (in target out result ui)
     (check-equal? (write-bytes-avail* #"ab\n" out) 2)
     (check-equal? (write-bytes-avail* #"\n" out) 0)
     (check-false (sync/timeout 0 out))
     (check-equal? (bounded-read 2 in) #"ab")
     (check-not-false (sync/timeout 0 out))
     (check-equal? (write-bytes-avail* #"\n" out) 1)
     (check-equal? (bounded-read 1 in) #"\n")
     (close-output-port out)
     (check-false (port-closed? target)))))

(test-case "blocking writes span partial capacity without duplication or loss"
  (with-pipe
   (lambda (in target out result ui)
     (define data #"a\r\n\303\251z\0\377")
     (define count #f)
     (define worker (thread (lambda () (set! count (write-bytes data out)))))
     (check-equal? (bounded-read (bytes-length data) in) data)
     (check-not-false (sync/timeout 5 (thread-dead-evt worker)))
     (check-equal? count (bytes-length data)))))

(test-case "cancelled blocked write preserves its committed prefix and remains usable"
  (with-pipe
   (lambda (in target out result ui)
     (define broken? #f)
     (define worker
       (thread (lambda ()
                 (with-handlers ([exn:break? (lambda (_) (set! broken? #t))])
                   (write-bytes #"ab\n" out)))))
     (check-not-false (sync/timeout 5 in))
     (break-thread worker)
     (check-not-false (sync/timeout 5 (thread-dead-evt worker)))
     (check-true broken?)
     (check-equal? (bounded-read 2 in) #"ab")
     ;; The cancelled LF was never accepted. A later result must supply it.
     (define printer (thread (lambda () (result "1"))))
     (check-equal? (bounded-read 6 in) #"\n=> 1\n")
     (check-not-false (sync/timeout 5 (thread-dead-evt printer))))))

(test-case "flushes reach the destination and write failures do not invent accepted bytes"
  (with-output-ports
   (lambda (own)
      (define target (own (open-output-bytes)))
      (define flushed 0)
      (define reject? #f)
      (define sink
        (own (make-output-port
         'flush-probe always-evt
         (lambda (b s e n? br?)
           (cond [(= s e) (set! flushed (add1 flushed)) 0]
                 [reject? (error 'probe "injected write failure")]
                 [else (write-bytes b target s e)])) void)))
      (define-values (out result ui) (make-shell-output sink (own (open-output-bytes)) #f))
      (own out)
      (write-bytes #"prefix" out)
      (flush-output out)
      (check-equal? flushed 1)
      (set! reject? #t)
      (check-exn exn:fail? (lambda () (write-bytes #"unwritten\n" out)))
      (set! reject? #f)
      (result "1")
      (check-equal? (get-output-bytes target) #"prefix\n=> 1\n"))))
