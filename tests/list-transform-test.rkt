#lang racket/base

(require rackunit
         racket/promise
         "../core/errors.rkt"
         "../core/lists.rkt"
         "../core/list-transform.rkt"
         "../core/result.rkt"
         (only-in "../core/typed-logic.rkt" TRUE FALSE)
         (only-in "../core/typed-rat.rkt" typed-rat-succ typed-rat-equal typed-rat-sub)
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

;; Reduction is left-associated and passes accumulator before element.
(check-equal?
 (object-rat->exact (apply3 typed-reduce typed-rat-sub (exact->object-rat 10) sample))
 4)
(check-equal?
 (object-rat->exact (apply3 typed-reduce typed-rat-sub (exact->object-rat 10)
                           (numbers '(2))))
 8)
(for ([initial (in-list (list one TRUE NIL result-err))])
  (check-eq? (lazy-force (apply3 typed-reduce unused initial NIL))
             (lazy-force initial)))
(check-equal?
 (read-numbers
  (apply3 typed-reduce
          (lambda (accumulator) (lambda (value) (apply2 typed-cons value accumulator)))
          NIL sample))
 '(3 2 1))
(check-equal?
 (error-value->string (apply3 typed-reduce unused invalid-count-error unused))
 "INVALID-COUNT\n  -> reduce(result)")
(check-equal?
 (error-value->string (apply3 typed-reduce unused one TRUE))
 "reduce(arg3 expected LIST got BOOL)")
(check-equal?
 (error-value->string (apply3 typed-reduce unused one invalid-count-error))
 "INVALID-COUNT\n  -> reduce(arg3 expected LIST)")
(for ([failure-at (in-list '(1 2))])
  (define calls '())
  (define result
    (apply3 typed-reduce
            (lambda (accumulator)
              (lambda (value)
                (define number (object-rat->exact value))
                (set! calls (append calls (list number)))
                (cond [(= number failure-at) (lazy-apply typed-head NIL)]
                      [(> number failure-at) (error 'reduce "continued after Error")]
                      [else accumulator])))
            one sample))
  (check-equal? (error-value->string result)
                "EMPTY-LIST\n  -> head(result)\n  -> reduce(result)")
  (check-equal? calls (if (= failure-at 1) '(1) '(1 2))))
(for ([partial (in-list (list typed-reduce
                              (lazy-apply typed-reduce unused)
                              (apply2 typed-reduce unused one)
                              (apply2 typed-reduce unused invalid-count-error)))])
  (check-equal? (procedure-arity (lazy-force partial)) 1))

(check-eq?
 (lazy-force
  (apply3 typed-reduce (lambda (accumulator) (lambda (value) result-err)) NIL sample))
 (lazy-force result-err))
(check-eq?
 (lazy-force
  (apply3 typed-reduce (lambda (accumulator) (lambda (value) value)) NIL heterogeneous))
 (lazy-force (lazy-apply typed-head (lazy-apply typed-tail (lazy-apply typed-tail heterogeneous)))))

;; zip returns proper two-element Lists, stopping at the shorter side.
(define (read-pairs value)
  (map read-numbers (object-list->host-list value)))
(check-equal? (read-pairs (apply2 typed-zip sample (numbers '(4 5 6))))
              '((1 4) (2 5) (3 6)))
(check-equal? (read-pairs (apply2 typed-zip sample (numbers '(4 5))))
              '((1 4) (2 5)))
(check-equal? (read-pairs (apply2 typed-zip (numbers '(4 5)) sample))
              '((4 1) (5 2)))
(check-equal? (read-pairs (apply2 typed-zip (numbers '(1)) (numbers '(2))))
              '((1 2)))
(check-equal?
 (map (lambda (pair) (map object-tag (object-list->host-list pair)))
      (object-list->host-list (apply2 typed-zip heterogeneous sample)))
 '((1 7) (7 7) (6 7)))
(for ([value (in-list (list (apply2 typed-zip NIL NIL)
                            (apply2 typed-zip NIL sample)
                            (apply2 typed-zip sample NIL)
                            (apply2 typed-zip NIL (host-list->object-list (list unused)))))])
  (check-eq? (lazy-force value) (lazy-force NIL))
  (check-equal? (object-list->host-list value) '()))
(check-equal? (error-value->string (apply2 typed-zip TRUE unused))
              "zip(arg1 expected LIST got BOOL)")
(check-equal? (error-value->string (apply2 typed-zip invalid-count-error unused))
              "INVALID-COUNT\n  -> zip(arg1 expected LIST)")
(check-equal? (error-value->string (apply2 typed-zip NIL TRUE))
              "zip(arg2 expected LIST got BOOL)")
(check-equal? (error-value->string (apply2 typed-zip sample invalid-count-error))
              "INVALID-COUNT\n  -> zip(arg2 expected LIST)")
(for ([partial (in-list (list typed-zip
                              (lazy-apply typed-zip sample)
                              (lazy-apply typed-zip invalid-count-error)))])
  (check-equal? (procedure-arity (lazy-force partial)) 1))

;; concat removes exactly one level, retaining nested Lists and NIL elements.
(define nested
  (host-list->object-list
   (list (host-list->object-list (list one (numbers '(2)))) (numbers '(3)))))
(check-equal? (read-numbers
               (lazy-apply typed-concat
                           (host-list->object-list (list (numbers '(1 2)) NIL (numbers '(3))))))
              '(1 2 3))
(define concatenated (lazy-apply typed-concat nested))
(check-equal? (map object-tag (object-list->host-list concatenated)) '(7 2 7))
(check-equal? (read-numbers (lazy-apply typed-head (lazy-apply typed-tail concatenated))) '(2))
(check-equal? (object-tag
               (lazy-apply typed-head
                           (lazy-apply typed-concat
                                       (host-list->object-list
                                        (list (host-list->object-list (list NIL)))))))
              2)
(for ([value (in-list (list (lazy-apply typed-concat NIL)
                            (lazy-apply typed-concat (host-list->object-list (list NIL NIL)))))])
  (check-eq? (lazy-force value) (lazy-force NIL))
  (check-equal? (object-list->host-list value) '()))
(check-equal? (map object-tag
                   (object-list->host-list
                    (lazy-apply typed-concat (host-list->object-list (list heterogeneous)))))
              '(1 7 6))
(for ([source (in-list (list (host-list->object-list (list TRUE unused))
                             (host-list->object-list (list sample TRUE))))])
  (define result (lazy-apply typed-concat source))
  (check-equal? (object-tag result) 0)
  (check-equal? (error-value->string result) "concat(arg1 expected LIST got BOOL)"))
(check-equal? (error-value->string (lazy-apply typed-concat one))
              "concat(arg1 expected LIST got RAT)")
(check-equal? (error-value->string (lazy-apply typed-concat invalid-count-error))
              "INVALID-COUNT\n  -> concat(arg1 expected LIST)")
(check-equal? (error-value->string
               (lazy-apply typed-concat (host-list->object-list (list sample invalid-count-error))))
              "INVALID-COUNT\n  -> concat(arg1 expected LIST)")
(check-equal? (procedure-arity (lazy-force typed-concat)) 1)

;; flatten recursively traverses only Lists; other tagged values stay leaves.
(check-equal? (read-numbers (lazy-apply typed-flatten nested)) '(1 2 3))
(check-equal? (read-numbers (lazy-apply typed-flatten sample)) '(1 2 3))
(check-equal? (read-numbers (lazy-apply typed-flatten (numbers '(1)))) '(1))
(define deep-empty
  (host-list->object-list (list NIL (host-list->object-list (list NIL NIL)))))
(for ([source (in-list (list NIL deep-empty))])
  (define result (lazy-apply typed-flatten source))
  (check-eq? (lazy-force result) (lazy-force NIL))
  (check-equal? (object-list->host-list result) '()))
(define mixed-nesting
  (host-list->object-list
   (list TRUE (host-list->object-list (list one NIL))
         (host-list->object-list (list result-err heterogeneous)))))
(check-equal? (map object-tag (object-list->host-list (lazy-apply typed-flatten mixed-nesting)))
              '(1 7 4 1 7 6))
(for ([source (in-list
              (list (host-list->object-list (list invalid-count-error unused))
                    (host-list->object-list (list one invalid-count-error))
                    (host-list->object-list
                     (list (host-list->object-list (list one invalid-count-error)) unused))))])
  (define result (lazy-apply typed-flatten source))
  (check-equal? (object-tag result) 0)
  (check-equal? (error-value->string result) "INVALID-COUNT\n  -> flatten(result)"))
(check-equal?
 (error-value->string
  (lazy-apply typed-flatten
              (host-list->object-list (list (lazy-apply typed-head NIL)))))
 "EMPTY-LIST\n  -> head(result)\n  -> flatten(result)")
(check-equal? (error-value->string (lazy-apply typed-flatten TRUE))
              "flatten(arg1 expected LIST got BOOL)")
(check-equal? (error-value->string (lazy-apply typed-flatten invalid-count-error))
              "INVALID-COUNT\n  -> flatten(arg1 expected LIST)")
(check-equal? (procedure-arity (lazy-force typed-flatten)) 1)
