#lang racket/base

;; Checker metadata only. A scheme is an environment entry, never a monotype.
(require racket/list)
(provide (struct-out type-variable) (struct-out type-form) (struct-out scheme)
         monotype? base-type arrow-type list-type option-type result-type map-type)

(struct type-variable (id) #:transparent
  #:guard (lambda (id name)
            (unless (exact-nonnegative-integer? id)
              (raise-argument-error name "exact-nonnegative-integer?" id))
            id))

(define arities
  '((Rat . 0) (Bool . 0) (String . 0) (Char . 0) (Byte . 0) (Unit . 0)
    (Error . 0) (Arrow . 2) (List . 1) (Option . 1) (Result . 1) (Map . 2)))
(define (monotype? value) (or (type-variable? value) (type-form? value)))
(struct type-form (name arguments) #:transparent
  #:guard
  (lambda (name arguments who)
    (define entry (assq name arities))
    (unless (and entry (list? arguments) (= (length arguments) (cdr entry))
                 (andmap monotype? arguments))
      (raise-arguments-error who "invalid finite type constructor"
                             "name" name "arguments" arguments))
    (values name arguments)))

;; Restricted variable IDs are separate from identity. The solver preserves
;; their data domain through substitutions and quantified instantiation.
(struct scheme (variables type restricted) #:transparent
  #:guard
  (lambda (variables type restricted who)
    (unless (and (list? variables) (andmap exact-nonnegative-integer? variables)
                 (= (length variables) (length (remove-duplicates variables)))
                 (monotype? type) (list? restricted)
                 (andmap exact-nonnegative-integer? restricted)
                 (= (length restricted) (length (remove-duplicates restricted))))
      (raise-arguments-error who "invalid type scheme"
                             "variables" variables "type" type "restricted" restricted))
    (values variables type restricted)))

(define (base-type name) (type-form name '()))
(define (arrow-type domain codomain) (type-form 'Arrow (list domain codomain)))
(define (list-type element) (type-form 'List (list element)))
(define (option-type element) (type-form 'Option (list element)))
(define (result-type element) (type-form 'Result (list element)))
(define (map-type key value) (type-form 'Map (list key value)))
