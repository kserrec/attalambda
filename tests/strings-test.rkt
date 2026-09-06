#lang racket/base

(require rackunit
         racket/list
         racket/promise
         "../core/binary-nat.rkt"
         "../core/chars.rkt"
         "../core/errors.rkt"
         "../core/lists.rkt"
         "../core/logic.rkt"
         "../core/objects.rkt"
         "../core/strings.rkt"
         "../core/tags.rkt"
         "../core/rat.rkt"
         (only-in "../core/typed-logic.rkt"
                  TRUE)
         "../readers/bool.rkt"
         "../readers/char.rkt"
         "../readers/list.rkt"
         "../readers/rat.rkt"
         "../readers/raw-boolean.rkt"
         "../readers/string.rkt"
         "../readers/type-tag.rkt"
         "helpers/lazy.rkt")

(define (values->list values)
  (foldr
   (lambda (value tail)
     (apply2 typed-cons value tail))
   NIL
   values))

(define (chars->string chars)
  (lazy-apply MAKE-STRING
              (values->list chars)))

(define (typed-value? type value)
  (raw-boolean->boolean
   (apply2 raw-is-type type value)))

(define (error-kind=? error kind)
  (raw-boolean->boolean
   (apply2
    raw-error-kind-equal
    (lazy-apply
     raw-error-root-kind
     (lazy-apply raw-error-root error))
    kind)))

(define (mismatch-details error)
  (lazy-apply
   raw-error-root-details
   (lazy-apply raw-error-root error)))

(define (frame->host frame)
  (list
   (type-tag->integer
    (lazy-apply
     raw-error-frame-argument-position
     frame))
   (type-tag->integer
    (lazy-apply
     raw-error-frame-expected-type
     frame))))

(define (error-frames->host error)
  (list->host-list
   (lazy-apply raw-error-frames error)
   frame->host))

(define (check-string expected value)
  (check-true
   (typed-value? string-type value))
  (check-equal? (string-value->string value)
                expected))

(define (check-char expected value)
  (check-true
   (typed-value? char-type value))
  (check-equal? (char-value->string value)
                expected))

(define (check-bool expected value)
  (check-true
   (typed-value? bool-type value))
  (check-equal? (bool->boolean value)
                expected))

(define rat-zero-object
  (apply2 raw-make-object rat-type raw-rat-zero))

(define (check-whole-rat expected value)
  (check-true
   (typed-value? rat-type value))
  (check-equal? (rat->number
                 (lazy-apply raw-object-value value))
                expected))

(define (check-mismatch error position expected actual)
  (define details
    (mismatch-details error))
  (check-true
   (typed-value? error-type error))
  (check-true
   (error-kind=? error
                 type-mismatch-kind))
  (check-equal?
   (type-tag->integer
    (lazy-apply
     raw-type-mismatch-argument-position
     details))
   position)
  (check-equal?
   (type-tag->integer
    (lazy-apply
     raw-type-mismatch-expected-type
     details))
   expected)
  (check-equal?
   (type-tag->integer
    (lazy-apply
     raw-type-mismatch-actual-type
     details))
   actual)
  (check-equal? (error-frames->host error)
                (list
                 (list position expected))))

(define (check-bubbled error position expected)
  (check-true
   (typed-value? error-type error))
  (check-true
   (error-kind=? error
                 invalid-nat-kind))
  (check-equal? (error-frames->host error)
                (list
                 (list position expected))))

(define (check-empty-list-error error)
  (check-true
   (typed-value? error-type error))
  (check-true
   (error-kind=? error
                 empty-list-kind))
  (check-equal? (error-frames->host error)
                '((0 0))))

(define empty-from-list
  (chars->string '()))
(define h-string
  (chars->string (list h)))
(define hi
  (chars->string (list h i)))
(define hi-copy
  (chars->string (list h i)))
(define hip
  (chars->string (list h i p)))
(define hell
  (chars->string (list h e l l)))
(define hello
  (chars->string (list h e l l o)))
(define ell
  (chars->string (list e l l)))
(define lo
  (chars->string (list l o)))
(define o-string
  (chars->string (list o)))
(define world
  (chars->string (list w o r l d)))
(define banana
  (chars->string (list b a n a n a)))
(define ana
  (chars->string (list a n a)))
(define uppercase-hi
  (chars->string (list H i)))

(check-string "" EMPTY-STRING)
(check-string "" empty-from-list)
(check-string "h" h-string)
(check-string "hi" hi)
(check-string "hello" hello)
(check-string "\t\n" (chars->string (list TAB LF)))
(check-string "{a_b}" (chars->string
                        (list LEFT-BRACE a UNDERSCORE b RIGHT-BRACE)))

(check-equal?
 (type-tag->integer
  (lazy-apply raw-object-type hi))
 6)

(define hi-chars
  (lazy-apply raw-string-value hi))

(check-true
 (typed-value? list-type hi-chars))
(check-equal?
 (list->host-list hi-chars
                  char-value->string)
 '("h" "i"))
(check-char "h"
            (lazy-apply typed-head hi-chars))
(check-true
 (typed-value?
  list-type
  (lazy-apply typed-tail hi-chars)))
(check-mismatch
 (lazy-apply typed-head hi)
 1
 2
 6)

(check-equal?
 (list->host-list
  (lazy-apply raw-string-length hi-chars)
  raw-boolean->boolean)
 '(#t #f))
(check-true
 (raw-boolean->boolean
  (apply2 raw-string-equal
          hi-chars
          (lazy-apply raw-string-value hi-copy))))
(check-equal?
 (list->host-list
  (apply2 raw-string-append
          hi-chars
          (lazy-apply raw-string-value world))
  char-value->string)
 '("h" "i" "w" "o" "r" "l" "d"))
(check-true
 (raw-boolean->boolean
  (apply2 raw-string-prefix?
          (lazy-apply raw-string-value hello)
          (lazy-apply raw-string-value hell))))
(check-true
 (raw-boolean->boolean
  (apply2 raw-string-contains?
          (lazy-apply raw-string-value hello)
          (lazy-apply raw-string-value ell))))

(for ([invalid-chars
       (in-list
        (list
         (list rat-zero-object h)
         (list h rat-zero-object i)
         (list h i TRUE)))])
  (define failure
    (lazy-apply MAKE-STRING
                (values->list invalid-chars)))
  (check-true
   (typed-value? error-type failure))
  (check-true
   (error-kind=? failure
                 invalid-string-kind))
  (check-equal? (error-frames->host failure)
                '((0 0))))

(define lazy-wrong-element
  (apply2
   raw-make-object
   bool-type
   (delay
     (error 'string
            "forced rejected element payload"))))

(define lazy-invalid-string
  (lazy-apply
   MAKE-STRING
   (values->list
    (list h lazy-wrong-element))))

(check-true
 (error-kind=? lazy-invalid-string
               invalid-string-kind))

(define lazy-char
  (apply2
   raw-make-object
   char-type
   (delay
     (error 'string
            "forced valid Char payload during construction"))))

(define lazy-valid-string
  (lazy-apply
   MAKE-STRING
   (values->list (list lazy-char))))

(check-true
 (typed-value? string-type
               lazy-valid-string))
(check-bool #f
            (lazy-apply STRING-EMPTY?
                        lazy-valid-string))

(check-mismatch
 (lazy-apply MAKE-STRING TRUE)
 1
 2
 1)
(check-bubbled
 (lazy-apply MAKE-STRING
             invalid-nat-error)
 1
 2)

(check-bool #t
            (lazy-apply STRING-EMPTY?
                        EMPTY-STRING))
(check-bool #f
            (lazy-apply STRING-EMPTY?
                        hi))

(for ([case (in-list
             (list
              (list EMPTY-STRING 0 '(#f))
              (list h-string 1 '(#t))
              (list hi 2 '(#t #f))
              (list hello 5 '(#t #f #t))
              (list banana 6 '(#t #t #f))))])
  (define length-value
    (lazy-apply STRING-LENGTH
                (first case)))
  (check-whole-rat (second case)
                   length-value)
  (check-equal? (list->host-list
                 (lazy-apply raw-rat-magnitude-bits
                             (lazy-apply raw-object-value length-value))
                 raw-boolean->boolean)
                (third case)))

(for ([case (in-list
             (list
              (list EMPTY-STRING EMPTY-STRING #t)
              (list hi hi-copy #t)
              (list hi h-string #f)
              (list h-string hi #f)
              (list hi hip #f)
              (list hi uppercase-hi #f)
              (list hello world #f)))])
  (check-bool (third case)
              (apply2 STRING-EQ
                      (first case)
                      (second case))))

(for ([case (in-list
             (list
              (list EMPTY-STRING EMPTY-STRING "")
              (list EMPTY-STRING hi "hi")
              (list hi EMPTY-STRING "hi")
              (list hi world "hiworld")
              (list hell o-string "hello")))])
  (check-string (third case)
                (apply2 STRING-APPEND
                        (first case)
                        (second case))))

(check-char "h"
            (lazy-apply STRING-HEAD hi))
(check-char "b"
            (lazy-apply STRING-HEAD banana))
(check-empty-list-error
 (lazy-apply STRING-HEAD EMPTY-STRING))

(check-string ""
              (lazy-apply STRING-TAIL h-string))
(check-string "i"
              (lazy-apply STRING-TAIL hi))
(check-string "ello"
              (lazy-apply STRING-TAIL hello))
(check-empty-list-error
 (lazy-apply STRING-TAIL EMPTY-STRING))

;; Both binary predicates take the searched String first and the candidate
;; prefix or substring second.
(for ([case (in-list
             (list
              (list EMPTY-STRING EMPTY-STRING #t)
              (list hello EMPTY-STRING #t)
              (list EMPTY-STRING h-string #f)
              (list hi h-string #t)
              (list hi hi-copy #t)
              (list hi hip #f)
              (list hello hell #t)
              (list hello ell #f)
              (list hi uppercase-hi #f)))])
  (check-bool (third case)
              (apply2 STRING-PREFIX?
                      (first case)
                      (second case))))

(for ([case (in-list
             (list
              (list EMPTY-STRING EMPTY-STRING #t)
              (list hello EMPTY-STRING #t)
              (list EMPTY-STRING h-string #f)
              (list hello hell #t)
              (list hello ell #t)
              (list hello lo #t)
              (list hello hello #t)
              (list hello world #f)
              (list banana ana #t)
              (list hi hip #f)
              (list hi uppercase-hi #f)))])
  (check-bool (third case)
              (apply2 STRING-CONTAINS?
                      (first case)
                      (second case))))

(define unary-string-operations
  (list typed-string-empty?
        typed-string-length-rat
        typed-string-head
        typed-string-tail
        STRING-EMPTY?
        STRING-LENGTH
        STRING-HEAD
        STRING-TAIL))

(for ([operation (in-list unary-string-operations)])
  (check-mismatch
   (lazy-apply operation TRUE)
   1
   6
   1)
  (check-bubbled
   (lazy-apply operation
               invalid-nat-error)
   1
   6))

(define binary-string-operations
  (list typed-string-equal
        typed-string-append
        typed-string-prefix?
        typed-string-contains?
        STRING-EQ
        STRING-APPEND
        STRING-PREFIX?
        STRING-CONTAINS?))

(for ([operation (in-list binary-string-operations)])
  (define wrong-first-partial
    (lazy-apply operation TRUE))
  (check-equal?
   (procedure-arity
    (lazy-force wrong-first-partial))
   1)
  (check-mismatch
   (lazy-apply
    wrong-first-partial
    (delay
      (error 'string
             "forced argument after first String mismatch")))
   1
   6
   1)
  (check-mismatch
   (apply2 operation hi TRUE)
   2
   6
   1)

  (define bubbled-first-partial
    (lazy-apply operation
                invalid-nat-error))
  (check-equal?
   (procedure-arity
    (lazy-force bubbled-first-partial))
   1)
  (check-bubbled
   (lazy-apply
    bubbled-first-partial
    (delay
      (error 'string
             "forced argument after first String Error")))
   1
   6)
  (check-bubbled
   (apply2 operation hi invalid-nat-error)
   2
   6))

(define propagated-invalid-string
  (lazy-apply STRING-LENGTH
              lazy-invalid-string))

(check-true
 (error-kind=? propagated-invalid-string
               invalid-string-kind))
(check-equal? (error-frames->host
               propagated-invalid-string)
              '((1 6) (0 0)))

(define unreadable-string
  (apply2
   raw-make-object
   string-type
   (delay
     (error 'string
            "forced searched String for empty candidate"))))

(check-bool #t
            (apply2 STRING-PREFIX?
                    unreadable-string
                    EMPTY-STRING))
(check-bool #t
            (apply2 STRING-CONTAINS?
                    unreadable-string
                    EMPTY-STRING))

(for ([function
       (in-list
        (list raw-make-string
              raw-string-value
              raw-string-empty?
              raw-string-length
              raw-string-head
              raw-string-tail
              typed-make-string
              typed-string-empty?
              typed-string-length-rat
              typed-string-head
              typed-string-tail
              MAKE-STRING
              STRING-EMPTY?
              STRING-LENGTH
              STRING-HEAD
              STRING-TAIL))])
  (check-equal?
   (procedure-arity
    (lazy-force function))
   1))

(define raw-binary-string-operations
  (list raw-string-equal
        raw-string-append
        raw-string-prefix?
        raw-string-contains?))

(for ([function (in-list raw-binary-string-operations)])
  (check-equal?
   (procedure-arity
    (lazy-force function))
   1)
  (check-equal?
   (procedure-arity
    (lazy-force
     (lazy-apply
     function
      (lazy-apply raw-string-value hi))))
   1))

(for ([function (in-list binary-string-operations)])
  (check-equal?
   (procedure-arity
    (lazy-force function))
   1)
  (check-equal?
   (procedure-arity
    (lazy-force
     (lazy-apply function hi)))
   1))
