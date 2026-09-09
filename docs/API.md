# Public API

This reference describes the published 0.7.0 API. Older 0.6.0 binaries lack
the four small syntax sugars. See the [0.7.0 notes](releases/0.7.0.md) for syntax
and the [0.6.0 release notes](releases/0.6.0.md) for
printing examples and compatibility. Older 0.5.0 binaries include pure recursion
and the complete List library but lack the rendering functions below. The
[0.5.0 migration notes](releases/0.5.0.md) cover recursive `def` changes.
Programs written for 0.3.0 also need the new function spellings and Char literals.
All callable built-ins below are lowercase; their old uppercase aliases are
absent from the language.
Constants keep their names. All 25 specified List operations are implemented.
Verification is recorded in [PLAN.md](../PLAN.md) and the
[acceptance record](ACCEPTANCE.md).

Programs begin with `#lang attalambda`. Functions with multiple parameters
are curried: supplying one argument returns the function awaiting the next.
Every expanded lambda has one parameter. Wrong tagged arguments return
structured Error values with the public operation's name; an early Error absorbs the remaining
arguments.
Expected computational failures return Result Err. There is no implicit
printing or conversion from Error to a process exit status.

## Syntax and values

| Form | Meaning |
| --- | --- |
| `(lambda (value) body)` | Unary function. |
| `(lambda (first second ...) body)` | One or more identifier parameters, curried to nested unary lambdas. |
| `(def name = value)` | Named acyclic value. |
| `(def name first second = body)` | Named acyclic definition; arguments curry to unary lambdas. |
| `(rec name first second = body)` | Pure self-recursive definition; syntax over the lambda fixed-point combinator. |
| `(let name = value body)` | Unary-lambda application sugar. |
| `(let ((name value) ...) body)` | Sequential nested lets; later values can use earlier bindings. Empty bindings return the body. |
| `(list expression ...)` | Nested existing typed `cons` ending in `NIL`; `(list)` is `NIL`. |
| `(cond (condition result) ... (else result))` | Nested existing typed `if`; exactly one result per clause and a required final `else`. |
| `(function first second)` | Curried application, equivalent to `((function first) second)`. |
| `-7/3`, `0`, `42` | Canonical exact Rat literals; inexact and complex literals are rejected. |
| `"hello"` | String literal, one byte-sized Char per UTF-8 byte. |
| `#\a`, `#\A`, `#\0`, `#\(`, `#\)` | ASCII Char literals (0–127). |
| `#\space`, `#\tab`, `#\newline`, `#\return` | Whitespace Char literals. |

The recursion rules below are included in 0.5.0; older 0.4.0 binaries lack
`rec` and permit recursive `def`. In 0.5.0, `def` cannot depend on itself
directly or through other top-level definitions; acyclic forward references
remain valid.
Use `rec` for self recursion, with zero or more source arguments. It binds
the recursive name inside a unary lambda and applies the existing pure
fixed-point combinator. `rec` is syntax, not a runtime primitive, and
`raw-fix` remains private. Mutual cycles between top-level definitions are
rejected, including cycles involving `rec`. Local `lambda` parameters,
`def`/`rec` arguments, and `let` names shadow top-level names normally; a
`let` name is in scope only in its body, not its value expression. Resulting
computation remains untyped unary lambda calculus.

The four 0.7.0 sugars change presentation only. For example,
`(let ((x 2) (y (add x 3))) y)` is `(let x = 2 (let y = (add x 3) y))`.
Each binding is visible only to later bindings and the body; repeated names
shadow earlier names. Multi-parameter lambdas likewise nest in source order,
including repeated parameter names. Zero-parameter lambdas remain invalid.
`cond` reserves the spelling `else` in its final clause. It requires Bool
conditions, propagates Errors exactly like `if`, and never evaluates an
unselected result or later condition. It has no implicit default or extra
Scheme clause features. `list` preserves existing typed `cons` evaluation,
including the checks that can force elements or tails when the List is used.
Sugar-generated `cons`, `NIL`, `if`, and unary-lambda bindings are hygienic:
user bindings with those names do not replace the generated operations.

The constants are `TRUE`, `FALSE`, `NIL`, `UNIT`, `NONE`, `EMPTY-STRING`,
and the four HTTP status constants listed below. Individual named Chars are
no longer exported; ordinary names such as `a`, `x`, `n`, and `m` are free for
user definitions. Direct Char literals reject non-ASCII characters during
expansion; `make-char` still accepts the full byte range 0–255. String literals
retain their UTF-8 byte encoding.

`Rat`, `List`, `Bool`, and the other type names in the tables describe
contracts; they are not additional exported identifiers. Likewise, `value`
and `function` denote parameters, not an Any or Function runtime type.

## Bool and List

| Application | Result |
| --- | --- |
| `if condition then-value else-value` | Require Bool; return only the selected branch without evaluating the other. |
| `not boolean` | Bool negation. |
| `and left right`, `or left right`, `xor left right` | Two Bool arguments, Bool result. |
| `cons value tail` | Proper List; tail must be List. An Error value propagates. |
| `head list` | First value; Error on NIL. |
| `tail list` | Remaining List; Error on NIL. |
| `is-nil list` | Bool indicating emptiness. |
| `len list` | Length as a whole Rat. |
| `take count list`, `drop count list` | Keep or omit the first count elements; require a nonnegative whole Rat. Counts beyond length exhaust the input. |
| `nth index list` | Some element at the zero-based index, otherwise NONE. Require a nonnegative whole Rat; negative or fractional indices produce InvalidCount. |
| `take-while predicate list`, `drop-while predicate list` | Keep or omit the matching prefix; stop predicate calls at the first FALSE. Drop retains that element and its suffix. |
| `append left right` | List containing all left elements, then all right elements. |
| `reverse list` | List in reverse order. |
| `zip left right` | Corresponding elements as two-element Lists; stop at the shorter input. |
| `concat lists` | Remove exactly one nesting level. Every outer element must be List; otherwise TypeMismatch. |
| `flatten list` | Recursively flatten nested Lists in order; retain ordinary non-List leaves and propagate encountered Errors. Result Err stays a value. |
| `map function list` | Apply function to each element in order; a callback Error propagates as the whole result. |
| `filter predicate list` | Retain elements whose predicate returns TRUE, in their original order. |
| `reduce function initial list` | Accumulate left to right; function receives accumulator, then element. NIL returns initial; callback Error stops reduction. |
| `any? predicate list`, `all? predicate list` | Bool; stop at the first true or false answer respectively. NIL yields FALSE for any? and TRUE for all?. |
| `find predicate list` | First matching element in Option, otherwise NONE. |
| `find-index predicate list` | First matching zero-based whole Rat index in Option, otherwise NONE. |
| `contains? equality value list` | Bool membership; apply curried equality to value, then each element. Stop at the first match; NIL yields FALSE. |
| `range start end` | Whole Rats, including negatives. Include start, exclude end, increment by one; start >= end yields NIL. Fractional bounds produce InvalidCount. |
| `repeat count value` | Repeat value a nonnegative whole Rat count of times. Zero yields NIL without using value; negative or fractional counts produce InvalidCount. |

List callbacks are pure unary or curried functions. Predicates must return tagged Bool;
Error propagates with the List operation's frame, and another tagged answer
produces TypeMismatch expecting Bool. Neither map nor filter calls its callback
on NIL. Result Err remains an ordinary element. No Function or Any tag is added.
Searches stop as soon as their answer is known. Checking for later callback
Errors in map/filter can require traversing a finite result; those transforms
make no infinite-List productivity guarantee.

## Rat

| Application | Result |
| --- | --- |
| `succ number` | Rat plus one. |
| `add left right`, `sub left right`, `mult left right` | Exact Rat arithmetic. |
| `div numerator denominator` | Result containing the exact Rat quotient; division by zero returns Err. |
| `exp base exponent` | Result containing the exact Rat power for a whole exponent. Fractional exponents and zero to a negative power return Err; zero to zero returns Ok 1. |
| `recip number` | Result containing the reciprocal; zero returns Err. |
| `neg number`, `abs number` | Negated Rat or its absolute value. |
| `floor number` | Whole Rat rounded toward negative infinity. |
| `eq left right`, `lt left right`, `lte left right`, `gt left right`, `gte left right` | Rat comparisons returning Bool. |
| `is-zero number`, `is-whole number`, `is-nonnegative-whole number` | Rat predicates returning Bool. |

## Byte, Char, and String

| Application | Result |
| --- | --- |
| `make-byte number` | Byte from whole Rat 0–255; otherwise InvalidByte Error. |
| `byte-value byte` | Whole Rat 0–255. |
| `byte-eq left right`, `byte-lt left right`, `byte-lte left right`, `byte-gt left right`, `byte-gte left right` | Byte comparisons returning Bool. |
| `make-char number` | Char from whole Rat 0–255. Negative/fractional values produce InvalidCount; values above 255 produce InvalidChar. |
| `char-eq left right`, `char-lt left right`, `char-lte left right`, `char-gt left right`, `char-gte left right` | Char comparisons returning Bool. |
| `make-string chars` | String from a List whose elements must all be Char. |
| `string-empty? string` | Bool indicating emptiness. |
| `string-length string` | Whole Rat count of byte-sized Chars, not Unicode characters. |
| `string-eq left right` | Bool equality. |
| `string-append left right` | Concatenated String. |
| `string-head string`, `string-tail string` | First Char or remaining String; Error on empty input. |
| `string-prefix? string prefix`, `string-contains? string substring` | Bool; searched String first, candidate second. An empty candidate matches. |
| `string-to-bytes string` | List of Byte, one per Char. |
| `bytes-to-string bytes` | String from a List of Byte; every element is checked. |

## Option, Map, and Result

| Application | Result |
| --- | --- |
| `some value` | Option holding a non-Error value; incoming Error propagates. |
| `is-some option`, `is-none option` | Bool variant checks. |
| `option-case option some-function none-value` | Apply the function to a Some payload, or select none-value. The unselected branch remains unevaluated. |
| `make-map equality` | Empty persistent Map with caller-supplied curried equality returning Bool. |
| `map-empty? map`, `map-size map` | Bool emptiness or whole Rat entry count. |
| `map-lookup map key` | Option containing the found value, otherwise NONE. |
| `map-contains? map key` | Bool membership. |
| `map-set map key value` | New Map with the key inserted or replaced; original Map is unchanged. |
| `map-remove map key` | New Map without the key. Absence is allowed. |
| `make-ok value` | Successful Result; incoming Error propagates. |
| `make-err error` | Failed Result deliberately containing an Error. |
| `is-ok result`, `is-err result` | Bool variant checks. |
| `unwrap-ok result`, `unwrap-err result` | Selected payload; WrongResultVariant Error when the variant differs. |

Map keys and values are non-Error values. Equality is supplied as a pure
curried function; each comparison must return tagged Bool. Error propagates;
another tagged answer produces TypeMismatch attributed to the Map operation.

## Value Rendering and Printing

The eleven unary type-specific renderers return a language String. They
require the named tagged type and use ordinary TypeMismatch and incoming-Error
propagation, except that `error-to-string` deliberately consumes Error as data.
`(error-to-string 5)` therefore returns a TypeMismatch expecting ERROR.
The generic unary `value-to-string` also consumes Error as printable data.
All twelve functions are pure; calling them alone produces no output.

| Function | Display representation |
| --- | --- |
| `rat-to-string` | Exact decimal `0`, `42`, `-42`, `3/7`, or `-7/3`; no `/1` and no approximation. |
| `bool-to-string` | `TRUE` or `FALSE`. |
| `unit-to-string` | `UNIT`. |
| `byte-to-string` | `BYTE(n)`, where n is decimal 0–255. |
| `char-to-string` | Printable ASCII `#\A`; named `#\space`, `#\tab`, `#\newline`, `#\return`; otherwise decimal `CHAR(n)`. |
| `string-to-string` | Double-quoted, byte-escaped text, such as `"hello"`. |
| `list-to-string` | `[]` or comma-separated recursive values, such as `[1, TRUE, "hello"]`. |
| `option-to-string` | `NONE` or `SOME(value)`; NONE ignores its unused payload. |
| `result-to-string` | `OK(value)` or `ERR(ERROR(...))`. |
| `map-to-string` | `{}` or recursive keys and values, such as `{"answer": 42}`. |
| `error-to-string` | `ERROR(...)`, containing the existing diagnostic body and frames. |
| `value-to-string` | Dispatch by the existing tag to the corresponding representation above. |

Lists, Maps, Options, and Results recurse through one generic renderer;
callers do not supply rendering callbacks. For example, a Some containing an
Ok containing a heterogeneous List displays as `SOME(OK([1, TRUE, "hello"]))`.
Map entries retain their stored traversal order, without sorting or invoking
the Map's equality function. Equivalent Maps can display in different orders.
These forms are human-readable display, not a stable serialization protocol
or a promise that the parser accepts the output.

String rendering escapes quote as `\"`, backslash as `\\`, newline as `\n`,
tab as `\t`, and return as `\r`. Other bytes in ASCII 32–126 appear directly;
all remaining bytes use uppercase two-digit `\xNN`. UTF-8 is escaped one byte
at a time: the String containing é displays as `"\xC3\xA9"`.
Char rendering uses direct notation for ASCII 33–126, the four named whitespace
forms, and `CHAR(n)` for all other byte values.

Error text retains existing kind/type names, decimal unknown-kind/type
fallbacks, argument positions, function names, oldest-first frame order,
and result frames. A framed TypeMismatch starts with its oldest function
frame and actual type, without duplicating a root label; later frames retain
their expected types. The runner's existing diagnostics keep their wording.

`value-to-string` and `print` support valid tagged data with printable contents.
Ordinary functions are untagged lambdas. Passing one directly or recursively
inside data has **unspecified behavior**; no structured Error is guaranteed.
There is no function detection, Function/Any tag, or host-side safety check.
`<UNPRINTABLE-TYPE:n>` is reserved for a well-formed tagged object with an
unknown tag; it is not a fallback for arbitrary functions. Rendering a
complete display requires finite contents.

`print value` applies `stdout` to `(value-to-string value)`. It returns exactly
stdout's success or failure result and adds no newline. `stdout string`
continues to emit the supplied String bytes exactly and rejects other tagged
types. There is no new host operation and no automatic top-level printing.

This complete program supplies its own line separators:

```racket
#lang attalambda

(stdout "hello")
(stdout "\n")
(print "hello")
(stdout "\n")
(print 5)
(stdout "\n")
(print (cons 5 (cons TRUE (cons "hello" NIL))))
(stdout "\n")
(print (some (make-ok (cons 1 (cons TRUE NIL)))))
```

It writes these bytes, with no newline after the last line:

```text
hello
"hello"
5
[5, TRUE, "hello"]
SOME(OK([1, TRUE]))
```

## Effects and HTTP

| Application | Successful outcome |
| --- | --- |
| `stdout string` | Write and flush bytes; Ok UNIT. |
| `print value` | Render tagged data through pure `value-to-string`, then delegate to stdout; Ok UNIT. Added in 0.6.0. |
| `read-file path` | Ok containing the complete List of Byte. |
| `write-file path bytes` | Replace file contents from List of Byte; Ok UNIT. |
| `exit status` | Terminate with status 0 or 1; no return value or automatic output. |
| `tcp-connect hostname port` | Ok containing a Rat connection handle. |
| `tcp-listen interface port backlog` | Ok containing a two-element List: listener handle and bound port. |
| `tcp-accept listener` | Ok containing a connection handle. |
| `tcp-read connection maximum` | Ok containing List of Byte; NIL means end of input. |
| `tcp-write connection bytes` | Write List of Byte; Ok UNIT. |
| `tcp-close handle` | Close the listener or connection; Ok UNIT. |
| `parse-http-request string` | Result containing the target String from the supported GET/HTTP/1.1 request grammar. |
| `render-http-response status body` | Result containing a complete response String for a supported status. |
| `make-http-path-handler path matched-status matched-body fallback-status fallback-body` | Unary target handler returning Result String. |
| `make-http-serve-one host handler listener maximum` | Serve one connection and close it; Ok UNIT. |
| `make-http-server host handler listener maximum` | Serve sequentially until an Error or failed Result; successful serving continues. |
| `host request` | Sole privileged bridge for the closed request List protocol. |

Paths, hostnames, and interface names are Strings; handles, ports, backlog,
maximum read sizes, and exit statuses are Rats with the exact constraints in
the [host boundary contract](design/host-boundary.md#closed-operation-table).
Expected external failures return Result Err. `exit` accepts only Rat 0 or 1:
other Rats return InvalidCount, wrong types return TypeMismatch, and neither
failure calls the host. Without explicit exit, normal completion is status 0.

HTTP status constants are `HTTP-STATUS-OK` (200),
`HTTP-STATUS-BAD-REQUEST` (400), `HTTP-STATUS-NOT-FOUND` (404), and
`HTTP-STATUS-INTERNAL-SERVER-ERROR` (500). HTTP constructors retain the
existing diagnostic names `http-path-handler`, `http-serve-one`, and
`http-server` for the functions they construct; these names are lowercase.
The existing HTTP grammar, request-size cap, and cleanup rules are unchanged.
