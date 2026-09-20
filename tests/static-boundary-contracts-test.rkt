#lang racket/base
(require rackunit racket/list "../runner/static/frontend.rkt" "../runner/source-file.rkt"
         "../runner/static/analysis.rkt" "../runner/static/inference.rkt"
         "../runner/static/proof.rkt" "../runner/static/contracts.rkt"
         "../runner/static/type-display.rkt")
(define (analyze text)
  (analyze-view (prepare-source (validated-source 'boundaries.attl text 2 0 17) #:analysis? #t)))
(define (state text) (proof-status (analysis-proof (analyze text))))

(test-case "every export is audited; HTTP parse/render failures remain represented Result Err"
  (check-equal? (length catalog) 130)
  (check-false (ormap (lambda (entry) (eq? (library-contract-status entry) 'pending)) catalog))
  (check-not-exn (lambda () (validate-catalog catalog)))
  (for ([text '("(parse-http-request \"bad request\")" "(render-http-response -1/2 \"body\")"
                "(make-http-path-handler \"/\" HTTP-STATUS-OK \"ok\" 999 \"missing\" \"/\")")])
    (define result (analyze text))
    (check-eq? (proof-status (analysis-proof result)) 'established text)
    (check-equal? (type->string (judgment-type (car (analysis-expressions result)))) "Result(String)"))
  (check-eq? (state "(add HTTP-STATUS-BAD-REQUEST HTTP-STATUS-NOT-FOUND)") 'established)
  (check-eq? (state "(parse-http-request 1)") 'conflict)
  (check-eq? (state "(render-http-response 200 TRUE)") 'conflict))

(test-case "TCP, exit and injected HTTP factories have known inputs but unproved outputs"
  (for ([text '("(tcp-connect \"127.0.0.1\" 80)" "(tcp-listen \"127.0.0.1\" 0 4)"
                "(tcp-accept 1)" "(tcp-read 1 1024)" "(tcp-write 1 (string-to-bytes \"s\"))"
                "(tcp-close 1)" "(exit 0)" "(exit 2)"
                "(make-http-serve-one (lambda (request) (make-ok UNIT)) (lambda (target) (make-ok \"reply\")) 1 1024)"
                "(make-http-server host (lambda (target) (make-ok \"reply\")) 1 1024)")])
    (check-eq? (state text) 'unproved text))
  (for ([row '((tcp-connect "String -> Rat -> Result(Rat)")
               (tcp-read "Rat -> Rat -> Result(List(Byte))")
               (tcp-write "Rat -> List(Byte) -> Result(Unit)")
               (tcp-close "Rat -> Result(Unit)"))])
    (define entry (contract-ref (car row)))
    (check-eq? (library-contract-status entry) 'partial)
    ;; Explanatory shapes only; never judgment-type or a published signature.
    (check-equal? (scheme->string (library-contract-signature entry)) (cadr row)))
  (for ([text '("(tcp-connect 1 80)" "(tcp-write 1 \"s\")" "(exit TRUE)"
                "(make-http-serve-one 1 (lambda (target) (make-ok \"s\")) 1 1)"
                "(make-http-serve-one host (lambda (target) 1) 1 1)"
                "(def send = tcp-write) (send 1 \"s\")")])
    (check-eq? (state text) 'conflict text)))

(test-case "raw host remains unproved through aliases, closures and higher-order use"
  (for ([text '("host" "(host (list \"read-line\"))"
                "(def h = host) (h (list \"stdout\" \"marker\"))"
                "(def apply f x = (f x)) (apply host (list \"read-line\"))"
                "(def h = host) (def a = h) (def captured ignored = (lambda (x) (a x)))"
                "(stdout (host (list \"read-line\")))"
                "((host (list \"read-line\")) 1)")])
    (check-eq? (state text) 'unproved text))
  (check-eq? (state "(host 1)") 'conflict))
