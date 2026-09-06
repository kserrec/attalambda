#lang s-exp "../macros/lazy-with-macros.rkt"

(require "../macros/macros.rkt"
         "../core/binary-nat.rkt"
         "../core/chars.rkt"
         (only-in "../core/errors.rkt"
                  NIL
                  raw-make-root-error)
         "../core/fix.rkt"
         (only-in "../core/list-nat.rkt" raw-list-take)
         (only-in "../core/lists.rkt"
                  raw-append
                  raw-cons
                  raw-list-head
                  raw-list-is-nil
                  raw-list-tail
                  raw-reverse)
         "../core/logic.rkt"
         "../core/objects.rkt"
         "../core/pair.rkt"
         "../core/result.rkt"
         "../core/strings.rkt"
         "../core/tags.rkt"
         "../core/typecheck.rkt"
         (only-in "protocol.rkt"
                  host-failure-kind))

(provide incomplete-http-request-kind
         malformed-http-request-kind
         unsupported-http-request-kind
         unsupported-http-status-kind
         raw-http-version-chars
         raw-space-chars
         raw-crlf-chars
         raw-scan-http-header-end
         parse-http-request)

;; Error kinds 0 through 8 are already assigned to core and host failures.
;; HTTP message outcomes extend only that tiny fixed metadata namespace.
(def incomplete-http-request-kind =
  (church-succ host-failure-kind))

(def malformed-http-request-kind =
  (church-succ incomplete-http-request-kind))

(def unsupported-http-request-kind =
  (church-succ malformed-http-request-kind))

(def unsupported-http-status-kind =
  (church-succ unsupported-http-request-kind))

(def incomplete-http-request-error =
  (raw-make-root-error incomplete-http-request-kind))

(def malformed-http-request-error =
  (raw-make-root-error malformed-http-request-kind))

(def unsupported-http-request-error =
  (raw-make-root-error unsupported-http-request-kind))

(def raw-name-char bits =
  ((raw-make-object char-type) bits))

(def raw-name-string chars =
  ((raw-make-object string-type) chars))

(define-function-name parse-http-request-function-name parse-http-request)

;; --------------------------------------------------------------------------
;; Fixed HTTP bytes

(def raw-get-chars =
  ((raw-cons G)
   ((raw-cons E)
    ((raw-cons T) NIL))))

(def raw-http-version-chars =
  ((raw-cons H)
   ((raw-cons T)
    ((raw-cons T)
     ((raw-cons P)
      ((raw-cons SLASH)
       ((raw-cons DIGIT-1)
        ((raw-cons DOT)
         ((raw-cons DIGIT-1) NIL)))))))))

(def raw-host-name-chars =
  ((raw-cons H)
   ((raw-cons o)
    ((raw-cons s)
     ((raw-cons t) NIL)))))

(def raw-content-length-name-chars =
  ((raw-cons C)
   ((raw-cons o)
    ((raw-cons n)
     ((raw-cons t)
      ((raw-cons e)
       ((raw-cons n)
        ((raw-cons t)
         ((raw-cons HYPHEN)
          ((raw-cons L)
           ((raw-cons e)
            ((raw-cons n)
             ((raw-cons g)
              ((raw-cons t)
               ((raw-cons h) NIL)))))))))))))))

(def raw-transfer-encoding-name-chars =
  ((raw-cons T)
   ((raw-cons r)
    ((raw-cons a)
     ((raw-cons n)
      ((raw-cons s)
       ((raw-cons f)
        ((raw-cons e)
         ((raw-cons r)
          ((raw-cons HYPHEN)
           ((raw-cons E)
            ((raw-cons n)
             ((raw-cons c)
              ((raw-cons o)
               ((raw-cons d)
                ((raw-cons i)
                 ((raw-cons n)
                  ((raw-cons g) NIL))))))))))))))))))

(def raw-space-chars =
  ((raw-cons SPACE) NIL))

(def raw-crlf-chars =
  ((raw-cons CR)
   ((raw-cons LF) NIL)))

(def raw-header-end-chars =
  ((raw-cons CR)
   ((raw-cons LF)
    ((raw-cons CR)
     ((raw-cons LF) NIL)))))

;; The caller carries at most three prior characters. Scan only that suffix
;; plus the new chunk; retain at most three characters for the next read.
;; Once found, no suffix is needed. Semantic parsing remains separate.
(def raw-scan-http-header-end suffix chunk =
  (lambda-let candidate = ((raw-append suffix) chunk)
    (lambda-let found =
      ((raw-string-contains? candidate) raw-header-end-chars)
      ((raw-pair found)
       (((raw-if found)
         NIL)
        (raw-reverse
         ((raw-list-take (raw-nat-succ raw-two-bits))
          (raw-reverse candidate))))))))

(def raw-http-char-succ char =
  (raw-make-char
   (raw-nat-succ
    (raw-char-value char))))

(def raw-exclamation-char =
  (raw-http-char-succ SPACE))

(def raw-dollar-char =
  (raw-http-char-succ HASH))

(def raw-apostrophe-char =
  (raw-http-char-succ AMPERSAND))

(def raw-asterisk-char =
  (raw-http-char-succ RIGHT-PAREN))

(def raw-plus-char =
  (raw-http-char-succ raw-asterisk-char))

(def raw-at-char =
  (raw-http-char-succ QUESTION))

(def raw-caret-char =
  (raw-http-char-succ RIGHT-BRACKET))

(def raw-backtick-char =
  (raw-http-char-succ UNDERSCORE))

(def raw-pipe-char =
  (raw-http-char-succ LEFT-BRACE))

(def raw-tilde-char =
  (raw-http-char-succ RIGHT-BRACE))

(def raw-token-punctuation-chars =
  ((raw-cons raw-exclamation-char)
   ((raw-cons HASH)
    ((raw-cons raw-dollar-char)
     ((raw-cons PERCENT)
      ((raw-cons AMPERSAND)
       ((raw-cons raw-apostrophe-char)
        ((raw-cons raw-asterisk-char)
         ((raw-cons raw-plus-char)
          ((raw-cons HYPHEN)
           ((raw-cons DOT)
            ((raw-cons raw-caret-char)
             ((raw-cons UNDERSCORE)
              ((raw-cons raw-backtick-char)
               ((raw-cons raw-pipe-char)
                ((raw-cons raw-tilde-char) NIL))))))))))))))))

;; RFC 3986 pchar punctuation, plus slash and question mark for the
;; origin-form path and query. Percent is handled separately so malformed
;; escape triplets cannot pass as ordinary punctuation.
(def raw-origin-target-punctuation-chars =
  ((raw-cons raw-exclamation-char)
   ((raw-cons raw-dollar-char)
    ((raw-cons AMPERSAND)
     ((raw-cons raw-apostrophe-char)
      ((raw-cons LEFT-PAREN)
       ((raw-cons RIGHT-PAREN)
        ((raw-cons raw-asterisk-char)
         ((raw-cons raw-plus-char)
          ((raw-cons COMMA)
           ((raw-cons HYPHEN)
            ((raw-cons DOT)
             ((raw-cons SLASH)
              ((raw-cons COLON)
               ((raw-cons SEMICOLON)
                ((raw-cons EQUAL)
                 ((raw-cons QUESTION)
                  ((raw-cons raw-at-char)
                   ((raw-cons UNDERSCORE)
                    ((raw-cons raw-tilde-char) NIL))))))))))))))))))))

(def raw-high-byte-start-bits =
  ((raw-nat-mult
    (raw-char-value SPACE))
   raw-four-bits))

;; --------------------------------------------------------------------------
;; Request parsing

(def raw-make-split found before after =
  ((raw-pair found)
   ((raw-pair before) after)))

(def raw-split-found split =
  (raw-first split))

(def raw-split-before split =
  (raw-first
   (raw-second split)))

(def raw-split-after split =
  (raw-second
   (raw-second split)))

(def raw-invalid-split reversed =
  (((raw-make-split raw-false)
    (raw-reverse reversed))
   NIL))

(def raw-valid-split reversed after =
  (((raw-make-split raw-true)
    (raw-reverse reversed))
   after))

(def raw-http-char-equal left right =
  ((raw-nat-equal
    (raw-char-value left))
   (raw-char-value right)))

(def raw-split-at-char-step recur delimiter remaining reversed =
  (((raw-if
     (raw-list-is-nil remaining))
    (raw-invalid-split reversed))
   (((raw-if
      ((raw-http-char-equal
        (raw-list-head remaining))
       delimiter))
     ((raw-valid-split reversed)
      (raw-list-tail remaining)))
    (((recur delimiter)
      (raw-list-tail remaining))
     ((raw-cons
       (raw-list-head remaining))
      reversed)))))

(def raw-split-at-char delimiter chars =
  ((((raw-fix raw-split-at-char-step)
     delimiter)
    chars)
   NIL))

(def raw-split-crlf-step recur remaining reversed =
  (((raw-if
     (raw-list-is-nil remaining))
    (raw-invalid-split reversed))
   (lambda-let current =
     (raw-list-head remaining)
     (lambda-let tail =
       (raw-list-tail remaining)
       (((raw-if
          ((raw-http-char-equal current) LF))
         (raw-invalid-split reversed))
        (((raw-if
           ((raw-http-char-equal current) CR))
          (((raw-if
             (raw-list-is-nil tail))
            (raw-invalid-split reversed))
           (((raw-if
              ((raw-http-char-equal
                (raw-list-head tail))
               LF))
             ((raw-valid-split reversed)
              (raw-list-tail tail)))
            (raw-invalid-split reversed))))
         ((recur tail)
          ((raw-cons current) reversed))))))))

(def raw-split-crlf chars =
  (((raw-fix raw-split-crlf-step)
    chars)
   NIL))

(def raw-ascii-uppercase? char =
  ((raw-and
    ((raw-nat-greater-equal
      (raw-char-value char))
     (raw-char-value A)))
   ((raw-nat-less-equal
     (raw-char-value char))
    (raw-char-value Z))))

(def raw-ascii-folded-value char =
  (((raw-if
     (raw-ascii-uppercase? char))
    ((raw-nat-add
      (raw-char-value char))
     (raw-char-value SPACE)))
   (raw-char-value char)))

(def raw-char-ci-equal left right =
  ((raw-nat-equal
    (raw-ascii-folded-value left))
   (raw-ascii-folded-value right)))

(def raw-http-char-between? char lower upper =
  ((raw-and
    ((raw-nat-greater-equal
      (raw-char-value char))
     (raw-char-value lower)))
   ((raw-nat-less-equal
     (raw-char-value char))
    (raw-char-value upper))))

(def raw-http-char-member-step recur char choices =
  (((raw-if
     (raw-list-is-nil choices))
    raw-false)
   (((raw-if
      ((raw-http-char-equal char)
       (raw-list-head choices)))
     raw-true)
    ((recur char)
     (raw-list-tail choices)))))

(def raw-http-char-member? char choices =
  (((raw-fix raw-http-char-member-step)
    char)
   choices))

(def raw-ascii-hex-digit? char =
  ((raw-or
    (((raw-http-char-between? char)
      DIGIT-0)
     DIGIT-9))
   ((raw-or
     (((raw-http-char-between? char) A) F))
    (((raw-http-char-between? char) a) f))))

(def raw-origin-target-unescaped-char? char =
  ((raw-or
    ((raw-or
      ((raw-or
        (((raw-http-char-between? char) A) Z))
       (((raw-http-char-between? char) a) z)))
     (((raw-http-char-between? char)
       DIGIT-0)
      DIGIT-9)))
   ((raw-http-char-member? char)
    raw-origin-target-punctuation-chars)))

(def raw-char-list-all-step recur predicate chars =
  (((raw-if
     (raw-list-is-nil chars))
    raw-true)
   ((raw-and
     (predicate
      (raw-list-head chars)))
    ((recur predicate)
     (raw-list-tail chars)))))

(def raw-char-list-all? predicate chars =
  (((raw-fix raw-char-list-all-step)
    predicate)
   chars))

(def raw-header-token-char? char =
  ((raw-or
    ((raw-or
      ((raw-or
        (((raw-http-char-between? char) A) Z))
       (((raw-http-char-between? char) a) z)))
     (((raw-http-char-between? char)
       DIGIT-0)
      DIGIT-9)))
   ((raw-http-char-member? char)
    raw-token-punctuation-chars)))

(def raw-field-value-char? char =
  ((raw-or
    ((raw-or
      ((raw-http-char-equal char) TAB))
     (((raw-http-char-between? char)
       SPACE)
      raw-tilde-char)))
   ((raw-nat-greater-equal
     (raw-char-value char))
    raw-high-byte-start-bits)))

(def raw-string-ci-equal-step recur left right =
  (((raw-if
     (raw-list-is-nil left))
    (raw-list-is-nil right))
   (((raw-if
      (raw-list-is-nil right))
     raw-false)
    (((raw-if
       ((raw-char-ci-equal
         (raw-list-head left))
        (raw-list-head right)))
      ((recur
        (raw-list-tail left))
       (raw-list-tail right)))
     raw-false))))

(def raw-string-ci-equal =
  (raw-fix raw-string-ci-equal-step))

(def raw-http-ows-char? char =
  ((raw-or
    ((raw-http-char-equal char) SPACE))
   ((raw-http-char-equal char) TAB)))

(def raw-http-all-ows-step recur chars =
  (((raw-if
     (raw-list-is-nil chars))
    raw-true)
   ((raw-and
     (raw-http-ows-char?
      (raw-list-head chars)))
    (recur
     (raw-list-tail chars)))))

(def raw-http-all-ows? =
  (raw-fix raw-http-all-ows-step))

(def raw-zero-content-length-digits-step recur chars =
  (((raw-if
     (raw-list-is-nil chars))
    raw-true)
   (lambda-let current =
     (raw-list-head chars)
     (((raw-if
        ((raw-http-char-equal current)
         DIGIT-0))
       (recur
        (raw-list-tail chars)))
      (((raw-if
         (raw-http-ows-char? current))
        (raw-http-all-ows?
         (raw-list-tail chars)))
       raw-false)))))

(def raw-zero-content-length-digits? =
  (raw-fix raw-zero-content-length-digits-step))

(def raw-zero-content-length-value-step recur chars =
  (((raw-if
     (raw-list-is-nil chars))
    raw-false)
   (lambda-let current =
     (raw-list-head chars)
     (((raw-if
        (raw-http-ows-char? current))
       (recur
        (raw-list-tail chars)))
      (((raw-if
         ((raw-http-char-equal current)
          DIGIT-0))
        (raw-zero-content-length-digits?
         (raw-list-tail chars)))
       raw-false)))))

(def raw-zero-content-length-value? =
  (raw-fix raw-zero-content-length-value-step))

(def raw-header-name-valid? chars =
  ((raw-and
    (raw-not
     (raw-list-is-nil chars)))
   ((raw-char-list-all?
     raw-header-token-char?)
    chars)))

(def raw-header-value-valid? chars =
  ((raw-char-list-all?
    raw-field-value-char?)
   chars))

(def raw-http-headers-valid-step recur remaining host-seen =
  (lambda-let line-split =
    (raw-split-crlf remaining)
    (((raw-if
       (raw-split-found line-split))
      (lambda-let line =
        (raw-split-before line-split)
        (lambda-let after =
          (raw-split-after line-split)
          (((raw-if
             (raw-list-is-nil line))
            ((raw-and host-seen)
             (raw-list-is-nil after)))
           (lambda-let field-split =
             ((raw-split-at-char COLON) line)
             (((raw-if
                (raw-split-found field-split))
               (lambda-let name =
                 (raw-split-before field-split)
                 (((raw-if
                    ((raw-and
                      (raw-header-name-valid? name))
                     (raw-header-value-valid?
                      (raw-split-after field-split))))
                   (lambda-let is-host =
                     ((raw-string-ci-equal name)
                      raw-host-name-chars)
                     (((raw-if
                        ((raw-string-ci-equal name)
                         raw-transfer-encoding-name-chars))
                       raw-false)
                      (((raw-if
                         ((raw-and
                           ((raw-string-ci-equal name)
                            raw-content-length-name-chars))
                          (raw-not
                           (raw-zero-content-length-value?
                            (raw-split-after field-split)))))
                        raw-false)
                       (((raw-if
                          ((raw-and is-host) host-seen))
                         raw-false)
                        ((recur after)
                         ((raw-or host-seen) is-host)))))))
                  raw-false)))
              raw-false))))))
     raw-false)))

(def raw-http-headers-valid? chars =
  (((raw-fix raw-http-headers-valid-step)
    chars)
   raw-false))

(def raw-origin-target-prefix? chars =
  ((raw-and
    (raw-not
     (raw-list-is-nil chars)))
   ((raw-http-char-equal
     (raw-list-head chars))
    SLASH)))

(def raw-percent-encoded-tail-valid? recur chars =
  (((raw-if
     (raw-list-is-nil chars))
    raw-false)
   (lambda-let after-first =
     (raw-list-tail chars)
     (((raw-if
        (raw-list-is-nil after-first))
       raw-false)
      (((raw-if
         ((raw-and
           (raw-ascii-hex-digit?
            (raw-list-head chars)))
          (raw-ascii-hex-digit?
           (raw-list-head after-first))))
        (recur
         (raw-list-tail after-first)))
       raw-false)))))

(def raw-request-target-chars-valid-step recur chars =
  (((raw-if
     (raw-list-is-nil chars))
    raw-true)
   (lambda-let current =
     (raw-list-head chars)
     (((raw-if
        ((raw-http-char-equal current)
         PERCENT))
       ((raw-percent-encoded-tail-valid? recur)
        (raw-list-tail chars)))
      (((raw-if
         (raw-origin-target-unescaped-char? current))
        (recur
         (raw-list-tail chars)))
       raw-false)))))

(def raw-request-target-chars-valid? =
  (raw-fix raw-request-target-chars-valid-step))

(def raw-incomplete-http-request-result =
  (raw-make-err incomplete-http-request-error))

(def raw-malformed-http-request-result =
  (raw-make-err malformed-http-request-error))

(def raw-unsupported-http-request-result =
  (raw-make-err unsupported-http-request-error))

(def raw-parse-complete-http-request chars =
  (lambda-let line-split =
    (raw-split-crlf chars)
    (((raw-if
       (raw-split-found line-split))
      (lambda-let line =
        (raw-split-before line-split)
        (lambda-let headers =
          (raw-split-after line-split)
          (lambda-let method-split =
            ((raw-split-at-char SPACE) line)
            (((raw-if
               (raw-split-found method-split))
              (lambda-let method =
                (raw-split-before method-split)
                (((raw-if
                   (raw-list-is-nil method))
                  raw-malformed-http-request-result)
                 (((raw-if
                    ((raw-string-equal method)
                     raw-get-chars))
                   (lambda-let target-split =
                     ((raw-split-at-char SPACE)
                      (raw-split-after method-split))
                     (((raw-if
                        (raw-split-found target-split))
                       (lambda-let target =
                         (raw-split-before target-split)
                         (((raw-if
                            (raw-list-is-nil target))
                           raw-malformed-http-request-result)
                          (((raw-if
                             ((raw-string-equal
                               (raw-split-after target-split))
                              raw-http-version-chars))
                            (((raw-if
                               (raw-origin-target-prefix? target))
                              (((raw-if
                                 (raw-request-target-chars-valid?
                                  target))
                                (((raw-if
                                   (raw-http-headers-valid? headers))
                                  (raw-make-ok
                                   (raw-make-string target)))
                                 raw-malformed-http-request-result))
                               raw-malformed-http-request-result))
                             raw-unsupported-http-request-result))
                           raw-unsupported-http-request-result))))
                      raw-malformed-http-request-result)))
                  raw-unsupported-http-request-result))))
             raw-malformed-http-request-result)))))
     raw-malformed-http-request-result)))

(def raw-parse-http-request chars =
  (((raw-if
     ((raw-string-contains? chars)
      raw-header-end-chars))
    (raw-parse-complete-http-request chars))
   raw-incomplete-http-request-result))

(def http-request-signature =
  ((raw-cons string-type) NIL))

(def parse-http-request =
  ((((make-typed-function raw-parse-http-request)
     parse-http-request-function-name)
    http-request-signature)
   raw-keep-return))
