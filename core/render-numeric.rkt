#lang s-exp "../macros/lazy-with-macros.rkt"

(require "../macros/macros.rkt"
         "binary-nat.rkt" "fix.rkt" "lists.rkt" "logic.rkt"
         "objects.rkt" "pair.rkt" "tags.rkt")

(provide raw-decimal-chars raw-hex-byte-chars raw-metadata-chars
         raw-ascii-space raw-ascii-quote raw-ascii-backslash
         raw-ascii-return raw-ascii-limit raw-ascii-printable?)

(def raw-ascii-space = ((raw-nat-add raw-sixteen-bits) raw-sixteen-bits))
(def raw-ascii-quote = ((raw-nat-add raw-ascii-space) raw-two-bits))
(def raw-ascii-zero = ((raw-nat-add raw-ascii-space) raw-sixteen-bits))
(def raw-ascii-A = (raw-nat-succ ((raw-nat-add raw-ascii-space) raw-ascii-space)))
(def raw-ascii-backslash =
  ((raw-nat-sub ((raw-nat-add raw-ascii-zero) raw-ascii-zero)) raw-four-bits))
(def raw-ascii-return = ((raw-nat-add raw-eight-bits) raw-five-bits))
(def raw-ascii-limit = (raw-nat-half raw-byte-max-bits))

(def raw-ascii-printable? bits =
  ((raw-and ((raw-nat-greater-equal bits) raw-ascii-space))
   ((raw-nat-less bits) raw-ascii-limit)))

(def raw-decimal-digit bits =
  ((raw-make-object char-type) ((raw-nat-add raw-ascii-zero) bits)))

;; Work stays binary. Prepending the least significant remainder to the
;; accumulated suffix produces decimal order without repeated append.
(def raw-decimal-step recur bits suffix =
  (((raw-if ((raw-nat-less bits) raw-ten-bits))
    ((raw-cons (raw-decimal-digit bits)) suffix))
   (lambda-let division = ((raw-nat-div-rem bits) raw-ten-bits)
     ((recur (raw-first division))
      ((raw-cons (raw-decimal-digit (raw-second division))) suffix)))))

(def raw-decimal-chars bits =
  (((raw-fix raw-decimal-step) bits) NIL))

;; Only tiny Church metadata enters here, never ordinary numeric values.
(def raw-metadata-chars metadata =
  (raw-decimal-chars ((metadata raw-nat-succ) raw-zero-bits)))

(def raw-hex-digit bits =
  ((raw-make-object char-type)
   (((raw-if ((raw-nat-less bits) raw-ten-bits))
     ((raw-nat-add raw-ascii-zero) bits))
    ((raw-nat-add raw-ascii-A) ((raw-nat-sub bits) raw-ten-bits)))))

(def raw-hex-byte-chars bits =
  (lambda-let division = ((raw-nat-div-rem bits) raw-sixteen-bits)
    ((raw-cons (raw-hex-digit (raw-first division)))
     ((raw-cons (raw-hex-digit (raw-second division))) NIL))))
