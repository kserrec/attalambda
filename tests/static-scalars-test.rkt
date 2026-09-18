#lang racket/base
(require rackunit racket/list "../runner/static/frontend.rkt" "../runner/source-file.rkt"
         "../runner/static/analysis.rkt" "../runner/static/inference.rkt"
         "../runner/static/proof.rkt" "../runner/static/contracts.rkt"
         "../runner/static/type-display.rkt")
(define (analyze text)
  (analyze-view (prepare-source (validated-source 'scalars.attl text 2 0 17) #:analysis? #t)))
(define (state text) (proof-status (analysis-proof (analyze text))))

(test-case "scalar contracts have independently specified nominal and Result shapes"
  (for ([row '((exp "Rat -> Rat -> Result(Rat)") (recip "Rat -> Result(Rat)")
               (neg "Rat -> Rat") (floor "Rat -> Rat") (abs "Rat -> Rat")
               (is-whole "Rat -> Bool") (is-nonnegative-whole "Rat -> Bool")
               (char-lte "Char -> Char -> Bool") (byte-lt "Byte -> Byte -> Bool")
               (byte-value "Byte -> Rat") (UNIT "Unit") (EMPTY-STRING "String")
               (make-string "List(Char) -> String") (string-to-bytes "String -> List(Byte)")
               (bytes-to-string "List(Byte) -> String") (string-length "String -> Rat"))])
    (define entry (contract-ref (car row)))
    (check-eq? (library-contract-status entry) 'complete)
    (check-equal? (scheme->string (library-contract-signature entry)) (cadr row))))

(test-case "supported scalar uses establish types even when represented Results can be Err"
  (for ([row '(("(exp 0 -1)" "Result(Rat)") ("(recip 0)" "Result(Rat)")
               ("(div 1 0)" "Result(Rat)") ("(floor -3/2)" "Rat")
               ("(is-nonnegative-whole -1/2)" "Bool") ("(char-eq #\\A #\\B)" "Bool")
               ("(string-contains? (string-append \"a\" \"b\") \"b\")" "Bool")
               ("(bytes-to-string (string-to-bytes \"abc\"))" "String")
               ("(lambda (b) (byte-value b))" "Byte -> Rat"))])
    (define result (analyze (car row)))
    (check-eq? (proof-status (analysis-proof result)) 'established (car row))
    (check-equal? (type->string (judgment-type (car (analysis-expressions result)))) (cadr row))))

(test-case "nominal mismatches identify the actual argument while range and empty cases stay unproved"
  (for ([row '(("(char-eq #\\A 1)" "char-eq argument 2")
               ("(exp 2 \"s\")" "exp argument 2")
               ("(byte-value #\\A)" "byte-value argument 1")
               ("(string-prefix? TRUE \"s\")" "string-prefix? argument 1"))])
    (define problems (proof-problems (analysis-proof (analyze (car row)))))
    (check-not-false (findf (lambda (item) (and (eq? (problem-code item) 'TYPE_CONFLICT)
                                               (equal? (problem-detail item) (cadr row)))) problems)))
  (for ([source '("make-byte" "(make-byte 0)" "(make-char 65)" "(make-char -1/2)"
                  "(string-head \"hello\")" "(string-tail EMPTY-STRING)"
                  "(def create = make-byte) (create 0)" "(def first = string-head)")])
    (check-eq? (state source) 'unproved source))
  (check-eq? (state "(make-byte \"bad\")") 'conflict)
  (check-eq? (state "(add (make-byte 0) \"bad\")") 'conflict))
