# Public API

This reference describes the source API and implemented interactive shell,
including unreleased `read-line`. Full current-source and candidate verification
remain unfinished. The published 0.7.0 binary includes neither shell nor line input.
Older 0.6.0 binaries lack
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

Standalone programs begin with `#lang attalambda`; shell entries omit that line.
Functions with multiple parameters
are curried: supplying one argument returns the function awaiting the next.
Every expanded lambda has one parameter. Wrong tagged arguments return
structured Error values with the public operation's name; an early Error absorbs the remaining
arguments.
Expected computational failures return Result Err. There is no implicit
printing in file mode or conversion from Error to a process exit status.
The shell's optional automatic echo observes expression values.

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
| `read-line UNIT` | Read one line from standard input; Ok(Some(String)) or Ok(NONE) at end of input. Unreleased. |
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

### Terminal line input (unreleased)

`read-line` follows Racket's native byte-line reader in `any` mode. LF, CRLF,
and CR are separators and are removed; other bytes are preserved, including
leading/trailing spaces and tabs. A blank line produces Some of the empty
String. A final line without a separator is returned before the next read
reports NONE. Reading writes no prompt and works with redirected files and
pipes as well as a terminal. Strings remain byte-based: input performs no
Unicode decoding, trimming, or parsing.

After CR, reading waits for another byte or end of input to determine
whether LF follows. A following LF completes the same separator; any other
byte belongs to the next line. A sender that keeps its stream open and waits
for a reply should end its line with LF or a complete CRLF, rather than CR
alone. No custom line reader or extra input state is used.

The exact example below is exercised by the input integration suite through
both the source language and the command-line runner:

<!-- terminal-input-example -->
```racket
#lang attalambda

(stdout "What is your name? ")
(def response = (read-line UNIT))
(if (is-ok response)
    (option-case (unwrap-ok response)
      (lambda (name)
        (stdout (string-append "Hello, " (string-append name ".\n"))))
      (stdout "\nNo input.\n"))
    (exit 1))
```
<!-- /terminal-input-example -->

The Unit argument preserves unary application. A wrong type or incoming
Error is rejected before reading. Expected failures return
Err(HostFailure(read-line, io-failure)); allocation failures use
resource-exhausted. No native exception message or port name is exposed.
Like whole-file input, there is no fixed line-length limit.

Reads follow the existing lazy effect rules. A saved result reads at most
once when demanded; an unused result reads nothing. Put a fresh call inside
the body of a function to read again on its next invocation. Top-level
expressions run in source order, so stdout displays and flushes the example's
prompt first. Inside a function, check an output Result with `if (is-ok ...)`
before entering the branch that reads or recurs. A lazy let binding by itself
does not force an effect or establish order between independent effects.

The interactive shell uses this unchanged operation while a program runs.
Source collection and program input share the original input port. The
[full input contract](terminal-input-spec.md) records the public and internal
request boundaries.

HTTP status constants are `HTTP-STATUS-OK` (200),
`HTTP-STATUS-BAD-REQUEST` (400), `HTTP-STATUS-NOT-FOUND` (404), and
`HTTP-STATUS-INTERNAL-SERVER-ERROR` (500). HTTP constructors retain the
existing diagnostic names `http-path-handler`, `http-serve-one`, and
`http-server` for the functions they construct; these names are lowercase.
The existing HTTP grammar, request-size cap, and cleanup rules are unchanged.

## Interactive shell (unreleased)

These behaviors are implemented and source-tested on `interactive-attalambda`.
The full current-source and standalone release-candidate gates remain unfinished;
see [PLAN.md](../PLAN.md). The published 0.7.0 executable has no shell.

Tab completion includes public language names and successfully committed user
definitions, including loaded names. Redefinition updates the visible bindings;
reset removes user names. Completion does not force lazy values. Control characters
in names receive safe display spellings while their original source is preserved.

With terminal stdin and stderr, `attalambda` or `attalambda --no-history` starts
`atta> `. `attalambda --repl` explicitly allows redirected input/output;
`--repl` and `--no-history` may appear in either order. Duplicates and combinations
with file mode are rejected. A pipe without `--repl` receives a usage diagnostic.
Interactive UI uses stderr; automatic results and program output use stdout.
Redirected transcripts have no unsolicited prompts, banner, terminal controls,
or persistent-history access.

| Command | Effect |
| --- | --- |
| `:help` | Show syntax, commands, and the automatic-printing limitation. |
| `:names` | List sorted committed user names without demanding their values. |
| `:load "path.attl"` | Validate and run a standalone file; publish its definitions after success. |
| `:echo on` / `:echo off` | Enable or disable automatic expression-result observation. |
| `:reset` | Discard definitions and close session resources; preserve echo and history preferences. |
| `:quit` | End the shell with its current status. |

Commands occupy a fresh entry. Command-looking text inside source strings,
comments, unfinished expressions, or program answers is ordinary content.
`:load` takes one literal quoted path, with no shell expansion. The file must
begin with `#lang attalambda`; it sees only the public language, never shell
names. Each load is fresh, emits only the file's requested output, and publishes
all definitions together after successful evaluation. Earlier closures keep
their captured bindings across reloads and redefinitions. A failed file may
already have performed effects; those cannot be rolled back.

A definition is silent and lazy. Redefinition affects subsequent entries;
existing closures and delayed values retain the earlier binding. Recursive
`def` stays forbidden, including `(def x = (add x 1))`. Use `rec` for self
recursion. Unknown names cannot be supplied by a future entry.

<!-- interactive-snapshot-example -->
```text
(def x = 1)
(def plus-x n = (add x n))
(def x = 10)
(plus-x 1)
(add x 1)
:quit
```
<!-- /interactive-snapshot-example -->

In transcript mode the exact stdout is:

```text
=> 2
=> 11
```

The complete entry is read and expanded before any expression runs. Multiple
forms in one accepted buffer are one entry. Incomplete source continues on the
next line; the plain fallback shows `...> `. Reader extensions such as `#reader`
and entry-level `#lang` are rejected. A reader or expansion failure runs none of
that entry. A native failure or interruption during evaluation stops later
expressions and leaves the previously committed names available.

Echo applies the existing pure `value-to-string` to the computed result, then
observes its String. It does not rerun the expression. Definitions and unselected
branches remain unforced. Raw functions, including functions inside containers,
have unspecified rendering behavior: use `:echo off` before demanding them.
Program stdout is immediate even with echo off, including a prompt awaiting input.

`(read-line UNIT)` reads only when demanded and returns `Ok(Some(String))`,
`Ok(NONE)` at end of input, or a Result Err for expected failure. An unused saved
read consumes nothing; demanding one saved result repeatedly consumes at most
one line. Put a fresh call inside a function to read again. The source entry's
terminating newline belongs to source; the next answer line belongs to the
program. Wait for the program prompt before pasting answers: text already
accepted by the editor as one buffer is source, and the shell cannot infer a
source/answer boundary inside that buffer. Answer bytes retain the input
operation's byte semantics and are never recorded in source history.

In interactive mode, Ctrl+C cancels the pending entry or running demand and
returns to a fresh prompt. Ctrl+D at a fresh prompt exits; during a program read
it supplies the input operation's EOF behavior. Terminal state is restored on
exit and cancellation. If the advanced editor cannot initialize, the shell uses
a plain interactive collector on the same input port.

History retains at most 1,000 submitted source entries per shell. On Linux,
persistence uses the Racket preference directory's `attalambda/history-v1` file
(normally `~/.config/racket/attalambda/history-v1`). Its inert, versioned format
is bounded to 1 MiB; oversized entries can execute but are omitted from the
file. Unsafe, damaged, missing, or unwritable history does not stop the shell.
Private directory/file permissions and atomic replacement protect persisted
source. `--no-history` prevents all persistent-history access while retaining
in-memory navigation. Cancelled unsubmitted source and program answers are not
saved. Neither shell nor editor runs personal Racket initialization files.

| Exit situation | Status |
| --- | ---: |
| Normal interactive EOF or `:quit`, including after recovered errors | 0 |
| Transcript EOF or `:quit` after any reader, expansion, command, or native entry failure | 1 |
| Transcript EOF with unfinished source | 65 |
| Transcript Ctrl+C | 130 |
| Explicit `(exit 0)` or `(exit 1)` | Exactly the chosen status, overriding earlier transcript failures |
| Unexpected shell/stream initialization or infrastructure failure | 70 |

Ordinary language Error and Result Err values do not count as native failures.
The shell is not a sandbox: entered source and loaded files have the same
program capabilities as file mode, including file writes, TCP, and process exit.
