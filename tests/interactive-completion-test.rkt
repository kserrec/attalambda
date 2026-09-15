#lang racket/base
(require rackunit racket/file racket/list racket/string racket/runtime-path
         "../runner/editor.rkt"
         "../runner/source-reader.rkt"
         "../runner/session.rkt")
(define-runtime-path editor-source "../runner/editor.rkt")
(define actual-helper
  (parameterize ([current-namespace
                  (module->namespace `(file ,(path->string editor-source)))])
    (eval 'completion-namespace)))
(define (check value label) (check-true value (format "~a" label)))
(define controls (append (range 0 32) (range 127 160)))
(define names
  (remove-duplicates
   (map string->symbol
        (append
         '("" "|" "a|b" "a\\|b" "\\" "\\|" "||" "|\\|" "a b" "a;b"
           "(" ")" "[" "]" "{" "}" "'" "`" "," ",@" "#;" "#|" "#lang"
           "#reader" "#:key" "#t" "#f" "#true" "#\\a" "#0=" "#0#"
           "0" "1" "-1" "+1" "1/2" "1.5" "1e3" "+inf.0" "+nan.0" "1+2i"
           "." ".." "..." ".5" "1." "1a" "1|2" "+" "-" "/" "="
           ":" ":help" ":load" ":quit" ":names" ":reset" ":echo" ":unknown" ":two words"
           "λ" "日本語" "é" "é" "🙂" "a b" "a b" "a b" "a​b")
         (for/list ([code (in-range 128)]) (string (integer->char code)))
         (for/list ([code controls]) (string-append "control" (number->string code)
                                                      (string (integer->char code)) "-name"))
         (for/list ([code controls]) (string (integer->char code)))
         (for*/list ([left '("a" "1" "\\" "|" ":" "#" ".")]
                     [middle '("|" "\\" " " "\n" ":" "#" "." "1")]
                     [right '("" "a" "|" "\\" "1")])
           (string-append left middle right))))))
(define (mapped-symbols namespace)
  (parameterize ([current-namespace namespace]) (namespace-mapped-symbols)))
(define (decoded-name spelling)
  (define parsed (parse-source-entry 'actual-helper-review spelling))
  (check (and (source-buffer? parsed)
              (eq? (source-buffer-status parsed) 'complete)
              (= (length (source-buffer-forms parsed)) 1)
              (identifier? (car (source-buffer-forms parsed))))
         (format "not exactly an identifier: ~s" spelling))
  (syntax-e (car (source-buffer-forms parsed))))
(define (check-namespace actual expected)
  (define mapped (mapped-symbols actual))
  (define recovered
    (for/list ([name mapped])
      (check (eq? (namespace-variable-value name #t (lambda () 'missing) actual) #f)
             'non-inert-or-missing-completion-value)
      (decoded-name (symbol->string name))))
  (check (equal? (sort recovered symbol<?) (sort (remove-duplicates expected) symbol<?))
         'namespace-inventory-not-exact)
  (length mapped))
(void (check-namespace (actual-helper '()) '()))
(for ([name names]) (check-namespace (actual-helper (list name)) (list name)))
(void (check-namespace (actual-helper names) names))
(void (check-namespace (actual-helper (append names names)) names))


(define input (open-input-bytes #"private answer\n"))
(define output (open-output-bytes))
(define current (open-session #:input input #:output output))
(define scratch (make-temporary-directory "attalambda-completion-wiring-~a"))
(dynamic-wind
 void
 (lambda ()
   (define initial (session-completion-names current))
   (define initial-count (check-namespace (actual-helper initial) initial))
   (for ([forbidden '(eval dynamic-require current-input-port completion-namespace)])
     (check (not (memq forbidden initial)) 'unexpected-native-initial-name))
   ;; These native-looking names are legitimate user identifiers too. They must
   ;; remain visible, but their namespace values must still be inert placeholders.
   (define committed
     (append (map string->symbol '("" ":help" ":quit" ":load" "a|b" "a\\|b" "1" "λ"
                                   "eval" "dynamic-require" "current-input-port" "completion-namespace"))
             (for/list ([code controls])
               (string->symbol (string-append "owned" (number->string code)
                                               (string (integer->char code)) "-name")))))
   (define source
     (string-join
      (for/list ([name committed])
        (define only-name (car (mapped-symbols (actual-helper (list name)))))
        (format "(def ~a = (read-line UNIT))" (symbol->string only-name))) "\n"))
   (evaluate-entry current (parse-source-buffer 'actual-helper-review source))
   (check (equal? (session-names current) (sort committed symbol<?)) 'committed-identifiers)
   (define expected (remove-duplicates (append initial committed)))
   (for ([index (in-range 10)])
     (check-namespace (actual-helper (session-completion-names current)) expected))
   (define before-failure (session-completion-names current))
   (define failure
     (with-handlers ([exn:fail:syntax? values])
       (evaluate-entry current (parse-source-buffer 'review "(def omitted = absent-value)"))))
   (check (exn:fail:syntax? failure) 'failed-entry-did-not-fail)
   (check (equal? (session-completion-names current) before-failure) 'failed-entry-published)
   (define loaded-file (build-path scratch "loaded.attl"))
   (call-with-output-file loaded-file
     (lambda (out) (display "#lang attalambda\n(def |loaded name| = (read-line UNIT))\n" out)))
   (load-source-file current (path->string loaded-file))
   (check-namespace (actual-helper (session-completion-names current))
                    (cons '|loaded name| expected))
   (check (zero? (file-position input)) 'program-input-demanded)
   (check (equal? (get-output-bytes output) #"") 'program-output-demanded)
   (reset-session! current)
   (check-namespace (actual-helper (session-completion-names current)) initial)
   (check (zero? (file-position input)) 'reset-demanded-input)
   (printf "actual session:~a public and~a unusual committed names;native-looking user names remain inert;failed entry/load/reset exact;input/output demand=0\n"
           initial-count (length committed))
)
 (lambda ()
   (close-session current) (close-input-port input) (close-output-port output)
   (delete-directory/files scratch)))
