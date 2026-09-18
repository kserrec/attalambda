#lang racket/base

;; Stable display names are unrelated to fresh solver identities.
(require racket/list racket/string "types.rkt" "substitution.rkt")
(provide type->string types->strings scheme->string)
(define (variable-name index)
  (string-append (string (integer->char (+ 97 (modulo index 26))))
                 (if (< index 26) "" (number->string (quotient index 26)))))
(define (names-for variables)
  (for/hasheqv ([id (in-list (remove-duplicates variables))] [index (in-naturals)])
    (values id (variable-name index))))
(define (arrow? type) (and (type-form? type) (eq? (type-form-name type) 'Arrow)))
(define (display-type type names)
  (cond
    [(type-variable? type) (hash-ref names (type-variable-id type))]
    [(arrow? type)
     (define domain (car (type-form-arguments type)))
     (define codomain (cadr (type-form-arguments type)))
     (define input (display-type domain names))
     (string-append (if (arrow? domain) (string-append "(" input ")") input)
                    " -> " (display-type codomain names))]
    [else
     (define arguments (type-form-arguments type))
     (string-append (symbol->string (type-form-name type))
                    (if (null? arguments) ""
                        (string-append "(" (string-join (map (lambda (arg) (display-type arg names)) arguments) ", ") ")")))]))
(define (type->string type) (display-type type (names-for (type-variables type))))
(define (types->strings types)
  (define names (names-for (append-map type-variables types)))
  (map (lambda (type) (display-type type names)) types))
(define (scheme->string value)
  (define variables (scheme-variables value))
  (define names (names-for (append variables (type-variables (scheme-type value)))))
  (string-append
   (if (null? variables) ""
       (string-append
        "forall "
        (string-join
         (map (lambda (id)
                (string-append (hash-ref names id) (if (memv id (scheme-restricted value)) ":data" "")))
              variables) " ")
        ". "))
   (display-type (scheme-type value) names)))
