#lang s-exp "../macros/lazy-with-macros.rkt"

(require "../macros/macros.rkt"
         "errors.rkt" "fix.rkt" "lists.rkt" "logic.rkt" "objects.rkt"
         "tags.rkt" "render-numeric.rkt" "render-scalars.rkt" "render-text.rkt")

(provide raw-error-diagnostic-string raw-render-error)

(def raw-actual-type-chars details =
  ((raw-append raw-text-got)
   (raw-type-name-chars (raw-type-mismatch-actual-type details))))

(def raw-argument-chars position expected actual =
  (((raw-render-enclose raw-text-argument-open)
    ((raw-append (raw-metadata-chars position))
     ((raw-append raw-text-expected)
      ((raw-append (raw-type-name-chars expected)) actual))))
   raw-text-close))

(def raw-frame-chars frame actual =
  ((raw-append (raw-object-value (raw-error-frame-function-name frame)))
   (((raw-if ((raw-tag-equal (raw-error-frame-argument-position frame))
              result-position))
     raw-text-result-frame)
    (((raw-argument-chars (raw-error-frame-argument-position frame))
      (raw-error-frame-expected-type frame)) actual))))

(def raw-frame-tail-step recur frames =
  (((raw-if (raw-list-is-nil frames)) NIL)
   ((raw-append raw-text-arrow)
    ((raw-append ((raw-frame-chars (raw-list-head frames)) NIL))
     (recur (raw-list-tail frames))))))

(def raw-frame-tail-chars = (raw-fix raw-frame-tail-step))

(def raw-mismatch-diagnostic-chars details frames =
  (((raw-if (raw-list-is-nil frames))
    ((raw-append raw-text-type-mismatch)
     (((raw-argument-chars (raw-type-mismatch-argument-position details))
       (raw-type-mismatch-expected-type details))
      (raw-actual-type-chars details))))
   ;; Preserve the oldest boundary's actual type without a duplicate root.
   ((raw-append ((raw-frame-chars (raw-list-head frames))
                 (raw-actual-type-chars details)))
    (raw-frame-tail-chars (raw-list-tail frames)))))

(def raw-error-diagnostic-chars payload =
  (lambda-let root = (raw-error-payload-root payload)
    (lambda-let frames = (raw-reverse (raw-error-payload-frames payload))
      (((raw-if ((raw-error-kind-equal (raw-error-root-kind root))
                 type-mismatch-kind))
        ((raw-mismatch-diagnostic-chars (raw-error-root-details root)) frames))
       ((raw-append (raw-kind-name-chars (raw-error-root-kind root)))
        (raw-frame-tail-chars frames))))))

;; Return the historical diagnostic body as String, consuming Error as data.
(def raw-error-diagnostic-string error =
  ((raw-make-object string-type)
   (raw-error-diagnostic-chars (raw-object-value error))))

(def raw-render-error payload =
  (((raw-render-enclose raw-text-error-open)
    (raw-error-diagnostic-chars payload)) raw-text-close))

(def raw-type-name-chars tag =
  (((raw-if ((raw-tag-equal tag) error-type)) raw-text-type-error)
   (((raw-if ((raw-tag-equal tag) bool-type)) raw-text-type-bool)
   (((raw-if ((raw-tag-equal tag) list-type)) raw-text-type-list)
   (((raw-if ((raw-tag-equal tag) result-type)) raw-text-type-result)
   (((raw-if ((raw-tag-equal tag) char-type)) raw-text-type-char)
   (((raw-if ((raw-tag-equal tag) string-type)) raw-text-type-string)
   (((raw-if ((raw-tag-equal tag) rat-type)) raw-text-type-rat)
   (((raw-if ((raw-tag-equal tag) unit-type)) raw-text-unit)
   (((raw-if ((raw-tag-equal tag) byte-type)) raw-text-type-byte)
   (((raw-if ((raw-tag-equal tag) option-type)) raw-text-type-option)
   (((raw-if ((raw-tag-equal tag) map-type)) raw-text-type-map)
   ((raw-append raw-text-type-fallback) (raw-metadata-chars tag))))))))))))))

;; Host/protocol, HTTP and unassigned kinds retain the existing numeric fallback.
(def raw-kind-name-chars kind =
  (((raw-if ((raw-tag-equal kind) type-mismatch-kind)) raw-text-type-mismatch)
   (((raw-if ((raw-tag-equal kind) empty-list-kind)) raw-text-empty-list)
   (((raw-if ((raw-tag-equal kind) invalid-nat-kind)) raw-text-invalid-nat)
   (((raw-if ((raw-tag-equal kind) divide-by-zero-kind)) raw-text-divide-by-zero)
   (((raw-if ((raw-tag-equal kind) invalid-char-kind)) raw-text-invalid-char)
   (((raw-if ((raw-tag-equal kind) invalid-string-kind)) raw-text-invalid-string)
   (((raw-if ((raw-tag-equal kind) wrong-result-variant-kind)) raw-text-wrong-result-variant)
   (((raw-if ((raw-tag-equal kind) non-whole-exponent-kind)) raw-text-non-whole-exponent)
   (((raw-if ((raw-tag-equal kind) invalid-count-kind)) raw-text-invalid-count)
   (((raw-if ((raw-tag-equal kind) invalid-byte-kind)) raw-text-invalid-byte)
   ((raw-append raw-text-error-kind) (raw-metadata-chars kind)))))))))))))
