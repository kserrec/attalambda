#lang racket/base

;; Persistent equation state; fresh IDs belong to one analysis, never a module.
(require racket/list "types.rkt")
(provide (struct-out solution) empty-solution make-fresh
         type-variables scheme-variables-free substitute-type substitute-scheme
         compose-substitutions apply-type apply-scheme instantiate generalize)

(struct solution (bindings restricted) #:transparent
  #:guard
  (lambda (bindings restricted who)
    (unless (and (hash? bindings) (immutable? bindings)
                 (andmap exact-nonnegative-integer? (hash-keys bindings))
                 (andmap monotype? (hash-values bindings))
                 (list? restricted) (andmap exact-nonnegative-integer? restricted)
                 (not (ormap (lambda (id) (member id (append-map type-variables (hash-values bindings))))
                             (hash-keys bindings))))
      (raise-arguments-error who "invalid or unsolved substitution"
                             "bindings" bindings "restricted" restricted))
    (values bindings restricted)))
(define empty-solution (solution (hasheqv) '()))
(define (make-fresh [start 0])
  (define next start)
  (lambda () (begin0 (type-variable next) (set! next (add1 next)))))

(define (type-variables type)
  (cond [(type-variable? type) (list (type-variable-id type))]
        [(type-form? type) (remove-duplicates (append-map type-variables (type-form-arguments type)))]
        [else (raise-argument-error 'type-variables "monotype?" type)]))
(define (without ids excluded) (filter (lambda (id) (not (memv id excluded))) ids))
(define (scheme-variables-free value)
  (without (type-variables (scheme-type value)) (scheme-variables value)))

(define (substitute-type bindings type)
  (define (walk type)
    (cond
      [(type-variable? type)
       (hash-ref bindings (type-variable-id type) type)]
      [(type-form? type)
       (type-form (type-form-name type) (map walk (type-form-arguments type)))]
      [else (raise-argument-error 'substitute-type "monotype?" type)]))
  (walk type))

(define (substituted-restrictions bindings ids)
  (remove-duplicates
   (append-map (lambda (id) (type-variables (substitute-type bindings (type-variable id)))) ids)))
(define (substitute-scheme bindings value)
  (define free-bindings
    (for/fold ([result bindings]) ([id (in-list (scheme-variables value))])
      (hash-remove result id)))
  (scheme (scheme-variables value)
          (substitute-type free-bindings (scheme-type value))
          (substituted-restrictions free-bindings (scheme-restricted value))))

;; Compose new after old: result(t) = new(old(t)). Existing old keys win.
(define (compose-substitutions new old)
  (for/fold ([result new]) ([(id type) (in-hash old)])
    (hash-set result id (substitute-type new type))))
(define (apply-type state type) (substitute-type (solution-bindings state) type))
(define (apply-scheme state value) (substitute-scheme (solution-bindings state) value))

(define (instantiate value fresh [state empty-solution])
  (define current (apply-scheme state value))
  (define replacements
    (for/hasheqv ([id (in-list (scheme-variables current))]) (values id (fresh))))
  ;; A catalog-local ID can equal a freshly allocated ID; substitution is
  ;; simultaneous, so a fresh replacement never gets renamed a second time.
  (define (rename type) (substitute-type replacements type))
  (values
   (rename (scheme-type current))
   (solution (solution-bindings state)
             (remove-duplicates
              (append (solution-restricted state)
                      (map (lambda (id) (type-variable-id (rename (type-variable id))))
                           (scheme-restricted current)))))))

(define (generalize state environment type)
  (define solved (apply-type state type))
  (define free (type-variables solved))
  (define environment-free
    (remove-duplicates
     (append-map (lambda (entry) (scheme-variables-free (apply-scheme state entry))) environment)))
  (define restricted (substituted-restrictions (solution-bindings state) (solution-restricted state)))
  (scheme (without free environment-free) solved
          (filter (lambda (id) (memv id restricted)) free)))
