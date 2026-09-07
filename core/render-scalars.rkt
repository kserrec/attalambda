#lang s-exp "../macros/lazy-with-macros.rkt"

(require "../macros/macros.rkt"
         "binary-nat.rkt" "fix.rkt" "int.rkt" "lists.rkt"
         "logic.rkt" "objects.rkt" "rat.rkt" "tags.rkt"
         "render-numeric.rkt" "render-text.rkt")

(provide raw-render-rat raw-render-bool raw-render-unit raw-render-byte
         raw-render-char raw-render-string raw-render-enclose)

;; Raw renderers take unwrapped payloads and return canonical Char Lists.
(def raw-render-enclose prefix contents suffix =
  ((raw-append prefix) ((raw-append contents) suffix)))

(def raw-render-bool payload =
  (((raw-if payload) raw-text-true) raw-text-false))

(def raw-render-unit ignored = raw-text-unit)

(def raw-render-rat payload =
  (lambda-let numerator = (raw-rat-numerator payload)
    ((raw-append
      (((raw-if (raw-int-sign numerator)) NIL) raw-text-minus))
     ((raw-append (raw-decimal-chars (raw-int-magnitude numerator)))
      (((raw-if (raw-rat-is-whole payload)) NIL)
       ((raw-append raw-text-slash)
        (raw-decimal-chars (raw-rat-denominator payload))))))))

(def raw-render-byte bits =
  (((raw-render-enclose raw-text-byte-open)
    (raw-decimal-chars bits)) raw-text-close))

(def raw-render-char bits =
  (((raw-if ((raw-nat-equal bits) raw-ascii-space)) raw-text-space-char)
   (((raw-if ((raw-nat-equal bits) raw-nine-bits)) raw-text-tab-char)
    (((raw-if ((raw-nat-equal bits) raw-ten-bits)) raw-text-newline-char)
     (((raw-if ((raw-nat-equal bits) raw-ascii-return)) raw-text-return-char)
      (((raw-if (raw-ascii-printable? bits))
        ((raw-append raw-text-char-prefix)
         ((raw-cons ((raw-make-object char-type) bits)) NIL)))
       (((raw-render-enclose raw-text-char-open)
         (raw-decimal-chars bits)) raw-text-close)))))))

(def raw-escape-char character =
  (lambda-let bits = (raw-object-value character)
    (((raw-if ((raw-nat-equal bits) raw-ascii-quote)) raw-text-escape-quote)
     (((raw-if ((raw-nat-equal bits) raw-ascii-backslash)) raw-text-escape-backslash)
      (((raw-if ((raw-nat-equal bits) raw-ten-bits)) raw-text-escape-newline)
       (((raw-if ((raw-nat-equal bits) raw-nine-bits)) raw-text-escape-tab)
        (((raw-if ((raw-nat-equal bits) raw-ascii-return)) raw-text-escape-return)
         (((raw-if (raw-ascii-printable? bits)) ((raw-cons character) NIL))
          ((raw-append raw-text-escape-hex) (raw-hex-byte-chars bits))))))))))

(def raw-escape-string-step recur chars =
  (((raw-if (raw-list-is-nil chars)) NIL)
   ((raw-append (raw-escape-char (raw-list-head chars)))
    (recur (raw-list-tail chars)))))

(def raw-render-string chars =
  (((raw-render-enclose raw-text-quote)
    ((raw-fix raw-escape-string-step) chars)) raw-text-quote))
