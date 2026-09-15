#lang racket/base

(require rackunit racket/promise)

;; Observe the dependency's payload without setters or replacement forcing.
;; These regressions distinguish cached state from a temporarily equal result.
(define peek
  (parameterize ([current-namespace (module->namespace 'racket/private/promise)])
    (eval '(lambda (value) (pref value)))))
(define (caught action) (with-handlers ([(lambda (_) #t) values]) (action)))

(test-case "completed values, links and cached failures survive new demands"
  (define completed (lazy 41))
  (check-equal? (force completed) 41)
  (define known (peek completed))
  (for ([index (in-range 1000)]) (check-equal? (force (lazy completed)) 41))
  (check-eq? (peek completed) known)
  (define pending (lazy 43))
  (check-equal? (force (lazy pending)) 43)
  (define link (peek pending))
  (check-true (promise? link))
  (check-equal? (force (lazy pending)) 43)
  (check-eq? (peek pending) link)
  (define payload (gensym 'failure))
  (define failed (lazy (raise payload)))
  (check-eq? (caught (lambda () (force failed))) payload)
  (define failure-state (peek failed))
  (for ([promise (list failed (lazy failed) failed)])
    (check-eq? (caught (lambda () (force promise))) payload)
    (check-eq? (peek failed) failure-state)))

(test-case "a rejected concurrent demand preserves the original running computation"
  (for ([alias? '(#f #t)])
    (define entered (make-semaphore 0))
    (define finish (make-semaphore 0))
    (define result #f)
    (define original (lazy (semaphore-post entered) (semaphore-wait finish) 41))
    (define worker (thread (lambda () (set! result (force original)))))
    (dynamic-wind
     void
     (lambda ()
       (unless (sync/timeout 5 entered) (error 'test "worker did not enter thunk"))
       (define running-state (peek original))
       (check-true (promise-running? original))
       (check-exn #rx"reentrant"
                  (lambda () (force (if alias? (lazy original) original))))
       (check-true (promise-running? original))
       (check-eq? (peek original) running-state)
       (semaphore-post finish)
       (unless (sync/timeout 5 worker) (error 'test "worker did not finish"))
       (check-equal? result 41)
       (check-equal? (force original) 41))
     (lambda ()
       (unless (thread-dead? worker) (kill-thread worker))
       (unless (sync/timeout 5 worker) (error 'test "worker cleanup failed"))))))

(test-case "newly demanded effects retain the same cancellation without replay"
  (define entered (make-semaphore 0))
  (define hold (make-semaphore 0))
  (define demands 0)
  (define effect (lazy (set! demands (add1 demands))
                       (semaphore-post entered) (semaphore-wait hold) 47))
  (define root (lazy effect))
  (define failure #f)
  (define worker
    (thread (lambda () (set! failure (caught (lambda () (force root)))))))
  (dynamic-wind
   void
   (lambda ()
     (unless (sync/timeout 5 entered) (error 'test "effect was not entered"))
     (break-thread worker)
     (unless (sync/timeout 5 worker) (error 'test "cancelled worker did not exit"))
     (check-true (exn:break? failure))
     (check-eq? (caught (lambda () (force root))) failure)
     (check-eq? (caught (lambda () (force effect))) failure)
     (check-equal? demands 1))
   (lambda ()
     (unless (thread-dead? worker) (kill-thread worker))
     (unless (sync/timeout 5 worker) (error 'test "worker cleanup failed")))))

(test-case "ordinary sharing, multiple values and recursive failures retain semantics"
  (define demands 0)
  (define shared (lazy (set! demands (add1 demands)) 43))
  (define a (lazy shared))
  (define b (lazy a))
  (for ([promise (list a b shared a shared b)]) (check-equal? (force promise) 43))
  (check-equal? demands 1)
  (define (collect promise) (call-with-values (lambda () (force promise)) list))
  (check-equal? (collect (lazy (delay (values)))) '())
  (define generic (lazy (delay (values 1 2 3))))
  (check-equal? (collect generic) '(1 2 3))
  (define generic-link (peek generic))
  (check-equal? (collect (lazy generic)) '(1 2 3))
  (check-eq? (peek generic) generic-link)
  (for ([promise (list (letrec ([p (lazy p)]) p)
                       (letrec ([p (lazy q)] [q (lazy p)]) p))])
    (define failure (caught (lambda () (force promise))))
    (check-true (exn:fail? failure))
    (check-eq? (caught (lambda () (force promise))) failure)))

(test-case "tail forcing releases old promises during computation and after completion"
  (define samples '())
  (define peak-live 0)
  (define (chain left)
    (lazy
     (define next (if (zero? left) 53 (chain (sub1 left))))
     (when (and (promise? next) (zero? (modulo left 1000)))
       (set! samples (cons (make-weak-box next) samples)))
     (when (zero? (modulo left 10000))
       (collect-garbage)
       (define live (for/sum ([sample samples]) (if (weak-box-value sample) 1 0)))
       (set! peak-live (max peak-live live)))
     next))
  (define root (chain 100000))
  (check-equal? (force root) 53)
  (check-true (<= peak-live 1))
  (collect-garbage) (collect-garbage)
  (check-equal? (for/sum ([sample samples]) (if (weak-box-value sample) 1 0)) 0))
