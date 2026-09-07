#lang s-exp "../macros/lazy-with-macros.rkt"

;; Fixed display spellings use the existing mechanical identifier-to-byte
;; expansion. Its local String constructor is identity: these are Char Lists.
(require "../macros/macros.rkt" "errors.rkt" "logic.rkt"
         "objects.rkt" "tags.rkt")

(provide raw-text-true
         raw-text-false
         raw-text-unit
         raw-text-byte-open
         raw-text-char-open
         raw-text-close
         raw-text-slash
         raw-text-minus
         raw-text-quote
         raw-text-char-prefix
         raw-text-space-char
         raw-text-tab-char
         raw-text-newline-char
         raw-text-return-char
         raw-text-escape-quote
         raw-text-escape-backslash
         raw-text-escape-newline
         raw-text-escape-tab
         raw-text-escape-return
         raw-text-escape-hex)

(def raw-name-char bits = ((raw-make-object char-type) bits))
(def raw-name-string chars = chars)

(define-function-name raw-text-true |TRUE|)
(define-function-name raw-text-false |FALSE|)
(define-function-name raw-text-unit |UNIT|)
(define-function-name raw-text-byte-open |BYTE(|)
(define-function-name raw-text-char-open |CHAR(|)
(define-function-name raw-text-close |)|)
(define-function-name raw-text-slash |/|)
(define-function-name raw-text-minus |-|)
(define-function-name raw-text-quote |"|)
(define-function-name raw-text-char-prefix |#\|)
(define-function-name raw-text-space-char |#\space|)
(define-function-name raw-text-tab-char |#\tab|)
(define-function-name raw-text-newline-char |#\newline|)
(define-function-name raw-text-return-char |#\return|)
(define-function-name raw-text-escape-quote |\"|)
(define-function-name raw-text-escape-backslash |\\|)
(define-function-name raw-text-escape-newline |\n|)
(define-function-name raw-text-escape-tab |\t|)
(define-function-name raw-text-escape-return |\r|)
(define-function-name raw-text-escape-hex |\x|)
