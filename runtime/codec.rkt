#lang racket/base

;; Trusted deterministic representation conversion. This module performs no
;; operating-system effect and is imported in production only by host.rkt.

(require racket/promise
         (only-in "../core/byte.rkt"
                  raw-make-byte
                  raw-byte-value)
         (only-in "../core/chars.rkt"
                  raw-char-value
                  raw-make-char)
         (only-in "../core/int.rkt"
                  raw-make-int
                  raw-int-sign
                  raw-int-magnitude)
         (only-in "../core/lists.rkt"
                  NIL
                  raw-cons
                  raw-list-head
                  raw-list-tail)
         (only-in "../core/logic.rkt"
                  raw-false
                  raw-true)
         (only-in "../core/objects.rkt"
                  raw-is-type
                  raw-make-object
                  raw-object-value)
         (only-in "../core/pair.rkt"
                  raw-pair)
         (only-in "../core/rat.rkt"
                  raw-rat-numerator
                  raw-rat-denominator)
         (only-in "../core/result.rkt"
                  raw-make-err
                  raw-make-ok)
         (only-in "../core/strings.rkt"
                  raw-make-string
                  raw-string-value)
         (only-in "../core/unit.rkt"
                  UNIT)
         (only-in "../core/tags.rkt"
                  byte-type
                  char-type
                  list-type
                  rat-type
                  string-type))

(provide (struct-out codec-failure)
         object-list->host-list
         host-list->object-list
         object-string->bytes
         bytes->object-string
         object-byte-list->bytes
         bytes->object-byte-list
         exact->object-rat
         object-rat->exact
         object-unit
         object-ok
         object-err)

(struct codec-failure (reason)
  #:transparent)

(define true-marker 'codec-true)
(define false-marker 'codec-false)

(define (lazy-apply function argument)
  ((force function) argument))

(define (lazy-apply2 function first second)
  (lazy-apply (lazy-apply function first) second))

(define (raw-boolean->boolean value)
  (define selected
    (force
     (lazy-apply2 value true-marker false-marker)))
  (cond
    [(eq? selected true-marker) #t]
    [(eq? selected false-marker) #f]
    [else (codec-failure 'wrong-type)]))

(define (object-has-type? expected value)
  (define decoded
    (raw-boolean->boolean
     (lazy-apply2 raw-is-type expected value)))
  (and (boolean? decoded) decoded))

(define (malformed-value-failure failure)
  (codec-failure 'wrong-type))

;; Floyd cycle detection: the tortoise trails the walk at half speed, so a
;; cyclic chain is caught in linear time with no per-node membership scan
;; and no mutable state. Every node is type-checked exactly once — the
;; head of the chain before the loop, every tail inside it.
(define (object-list->host-list value)
  (with-handlers ([exn:fail? malformed-value-failure])
    (if (not (object-has-type? list-type value))
        (codec-failure 'wrong-type)
        (let loop ([remaining (force value)]
                   [tortoise (force value)]
                   [advance-tortoise? #f]
                   [reversed '()])
          (cond
            [(eq? remaining (force NIL))
             (reverse reversed)]
            [else
             (define tail
               (force (lazy-apply raw-list-tail remaining)))
             (cond
               [(not (object-has-type? list-type tail))
                (codec-failure 'wrong-type)]
               [else
                (define next-tortoise
                  (if advance-tortoise?
                      (force (lazy-apply raw-list-tail tortoise))
                      tortoise))
                (if (eq? tail next-tortoise)
                    (codec-failure 'wrong-type)
                    (loop tail
                          next-tortoise
                          (not advance-tortoise?)
                          (cons (force
                                 (lazy-apply raw-list-head remaining))
                                reversed)))])])))))

(define (host-list->object-list values)
  (let loop ([remaining values])
    (if (null? remaining)
        NIL
        (lazy-apply2 raw-cons
                     (car remaining)
                     (loop (cdr remaining))))))

(define (raw-bit->boolean value)
  (with-handlers ([exn:fail? malformed-value-failure])
    (raw-boolean->boolean value)))

(define (raw-bits->integer bits-value)
  (define bits
    (object-list->host-list bits-value))
  (cond
    [(codec-failure? bits) bits]
    [(null? bits) (codec-failure 'out-of-range)]
    [else
     (define decoded
       (for/list ([bit (in-list bits)])
         (raw-bit->boolean bit)))
     (cond
       [(ormap codec-failure? decoded)
        (codec-failure 'wrong-type)]
       [(and (> (length decoded) 1)
             (not (car decoded)))
        (codec-failure 'out-of-range)]
       [else
        (for/fold ([total 0])
                  ([bit (in-list decoded)])
          (+ (* total 2)
             (if bit 1 0)))])]))

(define (raw-bits->byte bits-value)
  (define integer
    (raw-bits->integer bits-value))
  (cond
    [(codec-failure? integer) integer]
    [(<= integer 255) integer]
    [else (codec-failure 'out-of-range)]))

(define (object-char->byte value)
  (with-handlers ([exn:fail? malformed-value-failure])
    (if (object-has-type? char-type value)
        (raw-bits->byte
         (lazy-apply raw-char-value value))
        (codec-failure 'wrong-type))))

(define (object-list->immutable-bytes value element->integer)
  (define elements
    (object-list->host-list value))
  (if (codec-failure? elements)
      elements
      (let ([integers
             (for/list ([element (in-list elements)])
               (element->integer element))])
        (define failure
          (for/or ([integer (in-list integers)])
            (and (codec-failure? integer) integer)))
        (if failure
            failure
            (bytes->immutable-bytes
             (apply bytes integers))))))

(define (object-string->bytes value)
  (with-handlers ([exn:fail? malformed-value-failure])
    (if (not (object-has-type? string-type value))
        (codec-failure 'wrong-type)
        (object-list->immutable-bytes
         (lazy-apply raw-string-value value)
         object-char->byte))))

(define (object-byte->integer value)
  (with-handlers ([exn:fail? malformed-value-failure])
    (if (object-has-type? byte-type value)
        (raw-bits->byte
         (lazy-apply raw-byte-value value))
        (codec-failure 'wrong-type))))

(define (object-byte-list->bytes value)
  (with-handlers ([exn:fail? malformed-value-failure])
    (object-list->immutable-bytes value object-byte->integer)))

(define (integer->raw-bits integer)
  (define bits
    (if (zero? integer)
        (list #f)
        (let loop ([remaining integer]
                   [result '()])
          (if (zero? remaining)
              result
              (loop (quotient remaining 2)
                    (cons (odd? remaining) result))))))
  (host-list->object-list
   (map (lambda (bit)
          (if bit raw-true raw-false))
        bits)))

(define (build-object-char integer)
  (lazy-apply raw-make-char
              (integer->raw-bits integer)))

(define (build-object-byte integer)
  (lazy-apply raw-make-byte
              (integer->raw-bits integer)))

;; Only 256 Byte values and 256 Char values exist, and every object is
;; immutable, so inbound file/TCP decoding reuses one canonical object per
;; value instead of reconstructing it for every payload byte. The cycle
;; detection above tracks list cells, never element values, so sharing
;; elements across positions is sound.
(define canonical-object-chars
  (build-vector 256 build-object-char))

(define canonical-object-bytes
  (build-vector 256 build-object-byte))

(define (byte->object-char integer)
  (vector-ref canonical-object-chars integer))

(define (integer->object-byte integer)
  (vector-ref canonical-object-bytes integer))

(define (bytes->object-byte-list value)
  (unless (bytes? value)
    (raise-argument-error 'bytes->object-byte-list "bytes?" value))
  (host-list->object-list
   (for/list ([integer (in-bytes value)])
             (integer->object-byte integer))))

(define (bytes->object-string value)
  (unless (bytes? value)
    (raise-argument-error 'bytes->object-string "bytes?" value))
  (lazy-apply
   raw-make-string
   (host-list->object-list
    (for/list ([integer (in-bytes value)])
              (byte->object-char integer)))))

;; Racket exact rationals are canonical by construction — reduced, with a
;; positive denominator — so translation builds the stored representation
;; directly and never runs object-language arithmetic.
(define (exact->object-rat value)
  (unless (and (rational? value) (exact? value))
    (raise-argument-error 'exact->object-rat
                          "(and/c rational? exact?)"
                          value))
  (lazy-apply2
   raw-make-object
   rat-type
   (lazy-apply2
    raw-pair
    (lazy-apply2 raw-make-int
                 (if (negative? value) raw-false raw-true)
                 (integer->raw-bits (abs (numerator value))))
    (integer->raw-bits (denominator value)))))

(define (object-rat->exact value)
  (with-handlers ([exn:fail? malformed-value-failure])
    (cond
      [(not (object-has-type? rat-type value))
       (codec-failure 'wrong-type)]
      [else
       (define payload
         (lazy-apply raw-object-value value))
       (define sign
         (raw-bit->boolean
          (lazy-apply raw-int-sign
                      (lazy-apply raw-rat-numerator payload))))
       (define magnitude
         (raw-bits->integer
          (lazy-apply raw-int-magnitude
                      (lazy-apply raw-rat-numerator payload))))
       (define bottom
         (raw-bits->integer
          (lazy-apply raw-rat-denominator payload)))
       (cond
         [(codec-failure? sign) sign]
         [(not (boolean? sign)) (codec-failure 'wrong-type)]
         [(codec-failure? magnitude) magnitude]
         [(codec-failure? bottom) bottom]
         [(zero? bottom) (codec-failure 'out-of-range)]
         [(and (zero? magnitude)
               (or (not sign)
                   (not (= bottom 1))))
          (codec-failure 'out-of-range)]
         [(not (= (gcd magnitude bottom) 1))
          (codec-failure 'out-of-range)]
         [sign (/ magnitude bottom)]
         [else (- (/ magnitude bottom))])])))

(define object-unit UNIT)

(define (object-ok payload)
  (lazy-apply raw-make-ok payload))

(define (object-err error-value)
  (lazy-apply raw-make-err error-value))
