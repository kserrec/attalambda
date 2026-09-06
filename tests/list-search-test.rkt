#lang racket/base

(require rackunit
         racket/promise
         "../core/errors.rkt"
         "../core/list-search.rkt"
         "../core/lists.rkt"
         "../core/objects.rkt"
         "../core/option.rkt"
         "../core/result.rkt"
         (only-in "../core/strings.rkt" STRING-EQ)
         (only-in "../core/typed-logic.rkt" TRUE FALSE)
         (only-in "../core/typed-rat.rkt" typed-rat-equal typed-rat-less)
         "../readers/bool.rkt"
         "../readers/error.rkt"
         "../runtime/codec.rkt"
         "helpers/lazy.rkt"
         (only-in "helpers/values.rkt" object-tag))

(define (numbers values)
  (host-list->object-list (map exact->object-rat values)))
(define (found value)
  (check-equal? (object-tag value) 10)
  (if (bool->boolean (lazy-apply typed-option-is-some value))
      (lazy-apply raw-option-value (lazy-apply raw-object-value value))
      'none))
(define (found-number value)
  (define payload (found value))
  (if (eq? payload 'none) 'none (object-rat->exact payload)))
(define sample (numbers '(1 2 3)))
(define one (exact->object-rat 1))
(define two (exact->object-rat 2))
(define unused (delay (error 'list-search "forced unused argument")))
(define matches-two (lazy-apply typed-rat-equal two))
(define (always value) TRUE)
(define (never value) FALSE)

(check-false (bool->boolean (apply2 typed-any? unused NIL)))
(check-true (bool->boolean (apply2 typed-all? unused NIL)))
(check-eq? (lazy-force (apply2 typed-find unused NIL)) (lazy-force NONE))
(check-eq? (lazy-force (apply2 typed-find-index unused NIL)) (lazy-force NONE))
(check-false (bool->boolean (apply3 typed-contains? unused one NIL)))

(check-true (bool->boolean (apply2 typed-any? matches-two sample)))
(check-false (bool->boolean (apply2 typed-any? never sample)))
(check-true (bool->boolean (apply2 typed-all? always sample)))
(check-false (bool->boolean (apply2 typed-all? matches-two sample)))
(check-equal? (found-number (apply2 typed-find matches-two (numbers '(1 2 2)))) 2)
(check-equal? (found-number (apply2 typed-find never sample)) 'none)
(check-equal? (found-number (apply2 typed-find-index matches-two sample)) 1)
(check-equal? (found-number (apply2 typed-find-index always sample)) 0)
(check-equal? (found-number
               (apply2 typed-find-index (lazy-apply typed-rat-equal (exact->object-rat 3))
                       sample))
              2)
(check-equal? (found-number (apply2 typed-find-index never sample)) 'none)
(check-true (bool->boolean (apply2 typed-any? always (numbers '(1)))))
(check-true (bool->boolean (apply2 typed-all? always (numbers '(1)))))
(check-equal? (found-number (apply2 typed-find always (numbers '(1)))) 1)
(check-equal? (found-number (apply2 typed-find-index always (numbers '(1)))) 0)
(check-true (bool->boolean (apply3 typed-contains? typed-rat-equal one (numbers '(1)))))
(check-false (bool->boolean (apply3 typed-contains? typed-rat-equal two (numbers '(1)))))

;; Values remain polymorphic; finding a Result Err does not propagate it.
(define text (bytes->object-string #"a"))
(define result-err (lazy-apply make-err invalid-count-error))
(define heterogeneous (host-list->object-list (list TRUE text result-err)))
(check-equal? (object-tag (found (apply2 typed-find always heterogeneous))) 1)
(check-equal?
 (object-string->bytes
  (found (apply2 typed-find (lambda (value) (if (= (object-tag value) 6) TRUE FALSE))
                 heterogeneous)))
 #"a")
(check-equal?
 (object-tag (found (apply2 typed-find always
                           (host-list->object-list (list result-err)))))
 4)
(check-true
 (bool->boolean
  (apply3 typed-contains? STRING-EQ text
          (host-list->object-list (list (bytes->object-string #"b") text)))))

;; Each search stops at the first decisive result, including a first-element
;; answer. A later callback throws if the stopping rule is lost.
(for ([function (in-list (list typed-any? typed-all? typed-find typed-find-index))]
      [name (in-list '("any?" "all?" "find" "find-index"))])
  (check-equal? (error-value->string (apply2 function unused TRUE))
                (format "~a(arg2 expected LIST got BOOL)" name))
  (check-equal? (error-value->string (apply2 function unused invalid-count-error))
                (format "INVALID-COUNT\n  -> ~a(arg2 expected LIST)" name))
  (check-equal? (procedure-arity (lazy-force function)) 1)
  (check-equal? (procedure-arity (lazy-force (lazy-apply function unused))) 1)
  (for ([stop-at (in-list '(1 2))])
    (define calls '())
    (define result
      (apply2 function
              (lambda (value)
                (define number (object-rat->exact value))
                (set! calls (append calls (list number)))
                (when (> number stop-at) (error 'search "continued after answer"))
                (if (equal? name "all?")
                    (if (= number stop-at) FALSE TRUE)
                    (if (= number stop-at) TRUE FALSE)))
              sample))
    (cond [(equal? name "any?")
           (check-equal? (object-tag result) 1)
           (check-true (bool->boolean result))]
          [(equal? name "all?")
           (check-equal? (object-tag result) 1)
           (check-false (bool->boolean result))]
          [(equal? name "find") (check-equal? (found-number result) stop-at)]
          [else (check-equal? (found-number result) (sub1 stop-at))])
    (check-equal? calls (if (= stop-at 1) '(1) '(1 2))))
  (for ([failure-at (in-list '(1 2))])
    (define calls '())
    (define result
      (apply2 function
              (lambda (value)
                (define number (object-rat->exact value))
                (set! calls (append calls (list number)))
                (cond [(= number failure-at) (lazy-apply typed-head NIL)]
                      [(> number failure-at) (error 'search "continued after Error")]
                      [(equal? name "all?") TRUE]
                      [else FALSE]))
              sample))
    (check-equal? (error-value->string result)
                  (format "EMPTY-LIST\n  -> head(result)\n  -> ~a(result)" name))
    (check-equal? calls (if (= failure-at 1) '(1) '(1 2))))
  (for ([answer (in-list (list one result-err))]
        [tag (in-list '("RAT" "RESULT"))])
    (check-equal?
     (error-value->string (apply2 function (lambda (value) answer) sample))
     (format "~a(arg1 expected BOOL got ~a)" name tag)))
  (check-equal?
   (error-value->string
    (apply2 function
            (lambda (value)
              (if (= (object-rat->exact value) 1)
                  (if (equal? name "all?") TRUE FALSE)
                  one))
            sample))
   (format "~a(arg1 expected BOOL got RAT)" name)))

;; Asymmetric equality proves argument order without universal equality.
(check-false (bool->boolean (apply3 typed-contains? typed-rat-less two (numbers '(1)))))
(check-true (bool->boolean (apply3 typed-contains? typed-rat-less two (numbers '(3)))))
(for ([match-at (in-list '(1 2))])
  (define comparisons '())
  (define contains-result
    (apply3 typed-contains?
            (lambda (sought)
              (lambda (element)
                (define left (object-rat->exact sought))
                (define right (object-rat->exact element))
                (set! comparisons (append comparisons (list (list left right))))
                (when (> right match-at) (error 'contains "continued after match"))
                (if (= left right) TRUE FALSE)))
            (exact->object-rat match-at) sample))
  (check-true (bool->boolean contains-result))
  (check-equal? comparisons (if (= match-at 1) '((1 1)) '((2 1) (2 2)))))
(for ([failure-at (in-list '(1 2))])
  (define comparisons '())
  (define result
    (apply3 typed-contains?
            (lambda (sought)
              (lambda (element)
                (define number (object-rat->exact element))
                (set! comparisons (append comparisons (list number)))
                (cond [(= number failure-at) invalid-count-error]
                      [(> number failure-at) (error 'contains "continued after Error")]
                      [else FALSE])))
            one sample))
  (check-equal? (error-value->string result)
                "INVALID-COUNT\n  -> contains?(result)")
  (check-equal? comparisons (if (= failure-at 1) '(1) '(1 2))))
(check-equal?
 (error-value->string (apply3 typed-contains? unused invalid-count-error unused))
 "INVALID-COUNT\n  -> contains?(result)")
(check-equal? (error-value->string (apply3 typed-contains? unused one TRUE))
              "contains?(arg3 expected LIST got BOOL)")
(check-equal? (error-value->string (apply3 typed-contains? unused one invalid-count-error))
              "INVALID-COUNT\n  -> contains?(arg3 expected LIST)")
(check-equal?
 (error-value->string
  (apply3 typed-contains? (lambda (left) (lambda (right) one)) one sample))
 "contains?(arg1 expected BOOL got RAT)")
(check-equal?
 (error-value->string
  (apply3 typed-contains? (lambda (left) (lambda (right) invalid-count-error)) one sample))
 "INVALID-COUNT\n  -> contains?(result)")
(for ([partial (in-list (list typed-contains?
                              (lazy-apply typed-contains? unused)
                              (apply2 typed-contains? unused one)
                              (apply2 typed-contains? unused invalid-count-error)))])
  (check-equal? (procedure-arity (lazy-force partial)) 1))

;; Predicate prefixes preserve order and stop before any later callback.
(define (read-numbers value)
  (map object-rat->exact (object-list->host-list value)))
(for ([function (in-list (list typed-take-while typed-drop-while))]
      [name (in-list '("take-while" "drop-while"))])
  (check-eq? (lazy-force (apply2 function unused NIL)) (lazy-force NIL))
  (check-equal? (object-list->host-list (apply2 function unused NIL)) '())
  (check-equal? (procedure-arity (lazy-force function)) 1)
  (check-equal? (procedure-arity (lazy-force (lazy-apply function unused))) 1)
  (check-equal? (error-value->string (apply2 function unused TRUE))
                (format "~a(arg2 expected LIST got BOOL)" name))
  (check-equal? (error-value->string (apply2 function unused invalid-count-error))
                (format "INVALID-COUNT\n  -> ~a(arg2 expected LIST)" name))
  (for ([stop-at (in-list '(1 2))])
    (define calls '())
    (define result
      (apply2 function
              (lambda (value)
                (define number (object-rat->exact value))
                (set! calls (append calls (list number)))
                (when (> number stop-at) (error 'prefix "continued after false"))
                (if (= number stop-at) FALSE TRUE))
              sample))
    (check-equal? (read-numbers result)
                  (if (equal? name "take-while")
                      (if (= stop-at 1) '() '(1))
                      (if (= stop-at 1) '(1 2 3) '(2 3))))
    (check-equal? calls (if (= stop-at 1) '(1) '(1 2))))
  (for ([failure-at (in-list '(1 2))])
    (define calls '())
    (define result
      (apply2 function
              (lambda (value)
                (define number (object-rat->exact value))
                (set! calls (append calls (list number)))
                (cond [(= number failure-at) (lazy-apply typed-head NIL)]
                      [(> number failure-at) (error 'prefix "continued after Error")]
                      [else TRUE]))
              sample))
    (check-equal? (error-value->string result)
                  (format "EMPTY-LIST\n  -> head(result)\n  -> ~a(result)" name))
    (check-equal? calls (if (= failure-at 1) '(1) '(1 2))))
  (for ([answer-at (in-list '(1 2))])
    (check-equal?
     (error-value->string
      (apply2 function
              (lambda (value) (if (= (object-rat->exact value) answer-at) one TRUE))
              sample))
     (format "~a(arg1 expected BOOL got RAT)" name))))
(check-equal? (read-numbers (apply2 typed-take-while always sample)) '(1 2 3))
(check-eq? (lazy-force (apply2 typed-drop-while always sample)) (lazy-force NIL))
(check-eq? (lazy-force (apply2 typed-take-while never sample)) (lazy-force NIL))
(check-eq? (lazy-force (apply2 typed-drop-while never sample)) (lazy-force sample))
(check-equal? (read-numbers (apply2 typed-take-while always (numbers '(1)))) '(1))
(check-eq? (lazy-force (apply2 typed-drop-while always (numbers '(1)))) (lazy-force NIL))
(check-equal? (map object-tag (object-list->host-list
                              (apply2 typed-take-while always heterogeneous)))
              '(1 6 4))
(check-equal? (map object-tag (object-list->host-list
                              (apply2 typed-drop-while never heterogeneous)))
              '(1 6 4))
