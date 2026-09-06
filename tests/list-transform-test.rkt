#lang racket/base

(require rackunit
         racket/promise
         "../core/errors.rkt"
         "../core/lists.rkt"
         "../core/list-transform.rkt"
         "../core/result.rkt"
         (only-in "../core/typed-logic.rkt" TRUE FALSE)
         (only-in "../core/typed-rat.rkt" typed-rat-succ typed-rat-equal)
         "../readers/error.rkt"
         "../runtime/codec.rkt"
         "helpers/lazy.rkt"
         (only-in "helpers/values.rkt" object-tag))

(define (numbers values)
  (host-list->object-list (map exact->object-rat values)))
(define (read-numbers value)
  (map object-rat->exact (object-list->host-list value)))
(define sample (numbers '(1 2 3)))
(define one (exact->object-rat 1))
(define two (exact->object-rat 2))
(define heterogeneous
  (host-list->object-list (list TRUE one (bytes->object-string #"a"))))
(define unused (delay (error 'list-transform "forced unused argument")))

(check-equal? (read-numbers (apply2 typed-append sample (numbers '(4 5))))
              '(1 2 3 4 5))
(check-equal? (read-numbers (apply2 typed-append NIL sample)) '(1 2 3))
(check-equal? (read-numbers (apply2 typed-append sample NIL)) '(1 2 3))
(check-equal? (read-numbers (lazy-apply typed-reverse sample)) '(3 2 1))
(check-equal? (read-numbers (lazy-apply typed-reverse (numbers '(1)))) '(1))
(check-equal? (map object-tag (object-list->host-list
                              (lazy-apply typed-reverse heterogeneous)))
              '(6 7 1))
(check-equal? (map object-tag (object-list->host-list
                              (apply2 typed-append heterogeneous sample)))
              '(1 7 6 7 7 7))

;; Empty output must be the canonical terminator, including rebuilt inputs.
(for ([value (in-list (list (apply2 typed-append NIL NIL)
                            (lazy-apply typed-reverse NIL)
                            (apply2 typed-map unused NIL)
                            (apply2 typed-filter unused NIL)
                            (apply2 typed-filter (lambda (value) FALSE) sample)))])
  (check-eq? (lazy-force value) (lazy-force NIL))
  (check-equal? (object-list->host-list value) '()))

(check-equal? (error-value->string (apply2 typed-append TRUE unused))
              "append(arg1 expected LIST got BOOL)")
(check-equal? (error-value->string (apply2 typed-append invalid-count-error unused))
              "INVALID-COUNT\n  -> append(arg1 expected LIST)")
(check-equal? (error-value->string (apply2 typed-append sample TRUE))
              "append(arg2 expected LIST got BOOL)")
(check-equal? (error-value->string (apply2 typed-append sample invalid-count-error))
              "INVALID-COUNT\n  -> append(arg2 expected LIST)")
(check-equal? (error-value->string (lazy-apply typed-reverse TRUE))
              "reverse(arg1 expected LIST got BOOL)")
(check-equal? (error-value->string (lazy-apply typed-reverse invalid-count-error))
              "INVALID-COUNT\n  -> reverse(arg1 expected LIST)")

(check-equal? (read-numbers (apply2 typed-map typed-rat-succ sample)) '(2 3 4))
(check-equal? (read-numbers (apply2 typed-map typed-rat-succ (numbers '(1)))) '(2))
(check-equal? (map object-tag (object-list->host-list
                              (apply2 typed-map (lambda (value) value) heterogeneous)))
              '(1 7 6))
(check-equal? (read-numbers
               (apply2 typed-filter (lazy-apply typed-rat-equal two) sample))
              '(2))
(check-equal? (read-numbers (apply2 typed-filter (lambda (value) TRUE) sample))
              '(1 2 3))
(check-equal? (read-numbers
               (apply2 typed-filter (lambda (value) TRUE) (numbers '(1))))
              '(1))
(check-equal? (map object-tag (object-list->host-list
                              (apply2 typed-filter (lambda (value) TRUE) heterogeneous)))
              '(1 7 6))

;; A Result Err remains an ordinary value when mapped or retained.
(define result-err (lazy-apply make-err invalid-count-error))
(for ([value (in-list
              (list (apply2 typed-map (lambda (value) result-err) sample)
                    (apply2 typed-filter (lambda (value) TRUE)
                            (host-list->object-list (list result-err)))))])
  (for ([element (in-list (object-list->host-list value))])
    (check-equal? (object-tag element) 4)))

;; Invalid List arguments never evaluate the supplied callback.
(for ([function (in-list (list typed-map typed-filter))]
      [name (in-list '("map" "filter"))])
  (check-equal? (error-value->string (apply2 function unused TRUE))
                (format "~a(arg2 expected LIST got BOOL)" name))
  (check-equal? (error-value->string (apply2 function unused invalid-count-error))
                (format "INVALID-COUNT\n  -> ~a(arg2 expected LIST)" name))
  ;; First and later callback failures must be the whole answer, retain the
  ;; original root, and stop callback calls at that element.
  (for ([failure-at (in-list '(1 2))])
    (define calls '())
    (define result
      (apply2 function
              (lambda (value)
                (define number (object-rat->exact value))
                (set! calls (append calls (list number)))
                (cond [(= number failure-at) invalid-count-error]
                      [(> number failure-at) (error 'callback "continued after Error")]
                      [else TRUE]))
              sample))
    (check-equal? (object-tag result) 0)
    (check-equal? (error-value->string result)
                  (format "INVALID-COUNT\n  -> ~a(result)" name))
    (check-equal? calls (if (= failure-at 1) '(1) '(1 2)))))

;; Existing diagnostic frames remain in order beneath the outer operation.
(for ([function (in-list (list typed-map typed-filter))]
      [name (in-list '("map" "filter"))])
  (check-equal?
   (error-value->string
    (apply2 function (lambda (value) (lazy-apply typed-head NIL)) sample))
   (format "EMPTY-LIST\n  -> head(result)\n  -> ~a(result)" name)))

(for ([answer (in-list (list one (bytes->object-string #"bad") result-err))]
      [tag (in-list '("RAT" "STRING" "RESULT"))])
  (check-equal?
   (error-value->string (apply2 typed-filter (lambda (value) answer) sample))
   (format "filter(arg1 expected BOOL got ~a)" tag)))
(check-equal?
 (error-value->string
  (apply2 typed-filter
          (lambda (value)
            (if (= (object-rat->exact value) 1) TRUE one))
          sample))
 "filter(arg1 expected BOOL got RAT)")

(for ([function (in-list (list typed-append typed-reverse typed-map typed-filter))])
  (check-equal? (procedure-arity (lazy-force function)) 1))
(for ([partial (in-list (list (lazy-apply typed-append sample)
                              (lazy-apply typed-append invalid-count-error)
                              (lazy-apply typed-map typed-rat-succ)
                              (lazy-apply typed-filter (lambda (value) TRUE))))])
  (check-equal? (procedure-arity (lazy-force partial)) 1))
