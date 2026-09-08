#lang s-exp "../macros/lazy-with-macros.rkt"

(require "../macros/macros.rkt"
         "fix.rkt" "lists.rkt" "logic.rkt" "objects.rkt"
         "option.rkt" "pair.rkt" "result.rkt" "tags.rkt"
         "render-error.rkt" "render-numeric.rkt"
         "render-scalars.rkt" "render-text.rkt")

(provide raw-value-to-chars raw-render-list raw-render-map
         raw-render-option raw-render-result)

;; A single traversal joins either List elements or Map entries. The item
;; renderer is supplied explicitly; it never depends on the generic engine.
(def raw-render-items-step self render-item items =
  (((raw-if (raw-list-is-nil items)) NIL)
   (lambda-let tail = (raw-list-tail items)
     ((raw-append (render-item (raw-list-head items)))
      (((raw-if (raw-list-is-nil tail)) NIL)
       ((raw-append raw-text-comma) ((self render-item) tail)))))))

(def raw-render-items = (raw-fix raw-render-items-step))

(def raw-render-list recur payload =
  (((raw-render-enclose raw-text-list-open)
    ((raw-render-items recur) (raw-rebuild-list payload))) raw-text-list-close))

(def raw-render-entry recur entry =
  ((raw-append (recur (raw-first entry)))
   ((raw-append raw-text-colon) (recur (raw-second entry)))))

(def raw-render-map recur payload =
  ;; The first payload field is the equality function. Never inspect or call
  ;; it; entry order is the existing List order, with no sorting or comparison.
  (((raw-render-enclose raw-text-map-open)
    ((raw-render-items (raw-render-entry recur)) (raw-second payload)))
   raw-text-map-close))

(def raw-render-option recur payload =
  (((raw-if (raw-option-is-some payload))
    (((raw-render-enclose raw-text-some-open)
      (recur (raw-option-value payload))) raw-text-close))
   raw-text-none))

(def raw-render-result recur payload =
  (((raw-if (raw-result-is-ok payload))
    (((raw-render-enclose raw-text-ok-open)
      (recur (raw-result-value payload))) raw-text-close))
   (((raw-render-enclose raw-text-err-open)
     (raw-render-error (raw-object-value (raw-result-value payload))))
    raw-text-close)))

;; Only well-formed tagged objects enter this contract. Arbitrary untagged
;; functions, including function contents of containers, remain unspecified.
(def raw-render-value-step recur value =
  (lambda-let tag = (raw-object-type value)
    (lambda-let payload = (raw-object-value value)
      (((raw-if ((raw-tag-equal tag) error-type)) (raw-render-error payload))
       (((raw-if ((raw-tag-equal tag) bool-type)) (raw-render-bool payload))
        (((raw-if ((raw-tag-equal tag) list-type)) ((raw-render-list recur) payload))
         (((raw-if ((raw-tag-equal tag) result-type)) ((raw-render-result recur) payload))
          (((raw-if ((raw-tag-equal tag) char-type)) (raw-render-char payload))
           (((raw-if ((raw-tag-equal tag) string-type)) (raw-render-string payload))
            (((raw-if ((raw-tag-equal tag) rat-type)) (raw-render-rat payload))
             (((raw-if ((raw-tag-equal tag) unit-type)) (raw-render-unit payload))
              (((raw-if ((raw-tag-equal tag) byte-type)) (raw-render-byte payload))
               (((raw-if ((raw-tag-equal tag) option-type)) ((raw-render-option recur) payload))
                (((raw-if ((raw-tag-equal tag) map-type)) ((raw-render-map recur) payload))
                 (((raw-render-enclose raw-text-unprintable-open)
                   (raw-metadata-chars tag)) raw-text-unprintable-close)))))))))))))))

;; This is the sole recursive value engine. Helpers above receive its lexical
;; recursive argument, so no module binding depends cyclically on another.
(def raw-value-to-chars = (raw-fix raw-render-value-step))
