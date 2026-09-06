#lang racket/base

(require rackunit
         racket/promise
         "../core/binary-nat.rkt"
         "../core/errors.rkt"
         "../core/list-nat.rkt"
         "../core/lists.rkt"
         "../core/logic.rkt"
         "../core/objects.rkt"
         "../core/tags.rkt"
         "../core/rat.rkt"
         (only-in "../core/option.rkt" NONE typed-option-is-some raw-option-value)
         "../readers/error.rkt"
         (only-in "../runtime/codec.rkt" exact->object-rat object-rat->exact host-list->object-list)
         "../readers/bool.rkt"
         "../readers/list.rkt"
         "../readers/rat.rkt"
         "../readers/raw-boolean.rkt"
         "helpers/lazy.rkt"
         (only-in "helpers/values.rkt"
                  apply2
                  host-bits->raw
                  whole-rat-object
                  rat-object->number
                  object-tag))

(define (prepend value tail)
  (apply2 typed-cons value tail))

(define (read-bool-object object)
  (raw-boolean->boolean
   (lazy-apply raw-object-value object)))

(define (list-value? value)
  (raw-boolean->boolean
   (apply2 raw-is-type list-type value)))

(define (nat-value? value)
  (raw-boolean->boolean
   (apply2 raw-is-type rat-type value)))

(define (error-value? value)
  (raw-boolean->boolean
   (apply2 raw-is-type error-type value)))

(define (error-kind=? error kind)
  (raw-boolean->boolean
   (apply2
    raw-error-kind-equal
    (lazy-apply
     raw-error-root-kind
     (lazy-apply raw-error-root error))
    kind)))

(define (nil-value? value)
  (bool->boolean
   (lazy-apply typed-is-nil value)))

(define true-object
  (apply2 raw-make-object bool-type raw-true))

(define false-object
  (apply2 raw-make-object bool-type raw-false))

(define sample
  (prepend true-object
           (prepend false-object
                    (prepend true-object
                             (prepend false-object NIL)))))

(define (read-list list)
  (list->host-list list read-bool-object))

(define ZERO (whole-rat-object 0))
(define ONE (whole-rat-object 1))
(define TWO (whole-rat-object 2))
(define THREE (whole-rat-object 3))
(define FOUR (whole-rat-object 4))
(define TEN (whole-rat-object 10))

(define (raw-length->integer list)
  (for/fold ([total 0])
            ([bit (in-list
                   (list->host-list
                    (lazy-apply raw-list-length list)
                    raw-boolean->boolean))])
    (+ (* total 2)
       (if bit 1 0))))

(check-equal? (raw-length->integer NIL) 0)
(check-equal? (raw-length->integer sample) 4)

(define empty-length
  (lazy-apply typed-len-rat NIL))

(define sample-length
  (lazy-apply typed-len-rat sample))

(check-true (nat-value? empty-length))
(check-true (nat-value? sample-length))
(check-equal? (rat-object->number empty-length) 0)
(check-equal? (rat-object->number sample-length) 4)
(check-equal? (list->host-list
               (lazy-apply raw-rat-magnitude-bits
                           (lazy-apply raw-object-value sample-length))
               raw-boolean->boolean)
              '(#t #f #f))

(check-equal? (read-list
               (apply2 typed-take-rat ZERO sample))
              '())
(check-equal? (read-list
               (apply2 typed-take-rat ONE sample))
              '(#t))
(check-equal? (read-list
               (apply2 typed-take-rat TWO sample))
              '(#t #f))
(check-equal? (read-list
               (apply2 typed-take-rat FOUR sample))
              '(#t #f #t #f))
(check-equal? (read-list
               (apply2 typed-take-rat TEN sample))
              '(#t #f #t #f))

(check-equal? (read-list
               (apply2 typed-drop-rat ZERO sample))
              '(#t #f #t #f))
(check-equal? (read-list
               (apply2 typed-drop-rat ONE sample))
              '(#f #t #f))
(check-equal? (read-list
               (apply2 typed-drop-rat TWO sample))
              '(#t #f))
(check-true
 (nil-value?
  (apply2 typed-drop-rat FOUR sample)))
(check-true
 (nil-value?
  (apply2 typed-drop-rat TEN sample)))

(check-true
 (nil-value?
  (apply2 typed-take-rat TEN NIL)))
(check-true
 (nil-value?
  (apply2 typed-drop-rat TEN NIL)))

(define (every-tail-is-list? list)
  (and (list-value? list)
       (or (nil-value? list)
           (every-tail-is-list?
            (lazy-apply typed-tail list)))))

(check-true
 (every-tail-is-list?
  (apply2 typed-take-rat THREE sample)))
(check-true
 (every-tail-is-list?
  (apply2 typed-drop-rat ONE sample)))

(define incoming-error
  invalid-nat-error)

(define rejected-bool-object
  (apply2
   raw-make-object
   bool-type
   (delay
     (error 'list-nat-operation
            "forced rejected object payload"))))

(check-true
 (error-value?
  (lazy-apply typed-len-rat true-object)))
(check-true
 (error-value?
  (lazy-apply typed-len-rat rejected-bool-object)))

(define bubbled-length
  (lazy-apply typed-len-rat incoming-error))

(check-true (error-value? bubbled-length))
(check-true
 (error-kind=? bubbled-length
               invalid-nat-kind))

(for ([function (in-list (list typed-take-rat typed-drop-rat))])
  (define bubbled-count
    (apply2
     function
     incoming-error
     (delay
       (error 'list-nat-operation
              "forced list after count Error"))))
  (check-true (error-value? bubbled-count))
  (check-true
   (error-kind=? bubbled-count
                 invalid-nat-kind))

  (define rejected-count
    (apply2
     function
     true-object
     (delay
       (error 'list-nat-operation
              "forced list after wrong count type"))))
  (check-true (error-value? rejected-count))
  (check-true
   (error-kind=? rejected-count
                 type-mismatch-kind))

  (define bubbled-list
    (apply2 function TWO incoming-error))
  (check-true (error-value? bubbled-list))
  (check-true
   (error-kind=? bubbled-list
                 invalid-nat-kind))

  (check-true
   (error-value?
    (apply2 function TWO true-object))))



(check-true
 (nil-value?
  (apply2
   raw-list-take
   (lazy-apply raw-rat-magnitude-bits
               (lazy-apply raw-object-value ZERO))
   (delay
     (error 'raw-list-take
            "forced list while taking zero")))))

(define fragile-list
  (apply2
   raw-cons
   true-object
   (delay
     (error 'raw-list-drop
            "forced tail while dropping zero"))))

(check-true
 (read-bool-object
  (lazy-apply
   raw-list-head
   (apply2 raw-list-drop
           raw-zero-bits
           fragile-list))))

(check-equal?
 (procedure-arity
  (lazy-force typed-len-rat))
 1)

(for ([function (in-list (list typed-take-rat typed-drop-rat))])
  (check-equal?
   (procedure-arity
    (lazy-force function))
   1)
  (check-equal?
   (procedure-arity
    (lazy-force
     (lazy-apply function TWO)))
   1)
  (check-equal?
   (procedure-arity
    (lazy-force
     (lazy-apply function incoming-error)))
   1)
  (check-equal?
   (procedure-arity
    (lazy-force
     (lazy-apply function true-object)))
   1))

;; nth uses the existing nonnegative whole-Rat count contract and returns
;; Option for ordinary absence, including an index exactly at the length.
(define numbered (host-list->object-list (map exact->object-rat '(10 20 30))))
(for ([index (in-list '(0 1 2 3 10))]
      [expected (in-list '(10 20 30 none none))])
  (define result (apply2 typed-nth-rat (exact->object-rat index) numbered))
  (check-equal? (object-tag result) 10)
  (if (eq? expected 'none)
      (check-eq? (lazy-force result) (lazy-force NONE))
      (begin
        (check-true (bool->boolean (lazy-apply typed-option-is-some result)))
        (check-equal?
         (object-rat->exact
          (lazy-apply raw-option-value (lazy-apply raw-object-value result)))
         expected))))
(check-eq? (lazy-force (apply2 typed-nth-rat ZERO NIL)) (lazy-force NONE))
(check-eq? (lazy-force (apply2 typed-nth-rat TEN NIL)) (lazy-force NONE))
(check-eq?
 (lazy-force (lazy-apply raw-option-value
                         (lazy-apply raw-object-value (apply2 typed-nth-rat ZERO sample))))
 (lazy-force true-object))
(for ([index (in-list '(-1 -1/2 1/2))])
  (check-equal?
   (error-value->string (apply2 typed-nth-rat (exact->object-rat index) numbered))
   "INVALID-COUNT\n  -> nth(result)"))
(define unused-nth-list (delay (error 'nth "forced list after index Error")))
(check-equal? (error-value->string (apply2 typed-nth-rat true-object unused-nth-list))
              "nth(arg1 expected RAT got BOOL)")
(check-equal? (error-value->string (apply2 typed-nth-rat incoming-error unused-nth-list))
              "INVALID-NAT\n  -> nth(arg1 expected RAT)")
(check-equal? (error-value->string (apply2 typed-nth-rat ZERO true-object))
              "nth(arg2 expected LIST got BOOL)")
(check-equal? (error-value->string (apply2 typed-nth-rat ZERO incoming-error))
              "INVALID-NAT\n  -> nth(arg2 expected LIST)")
(for ([partial (in-list (list typed-nth-rat
                              (lazy-apply typed-nth-rat ZERO)
                              (lazy-apply typed-nth-rat true-object)
                              (lazy-apply typed-nth-rat incoming-error)))])
  (check-equal? (procedure-arity (lazy-force partial)) 1))
