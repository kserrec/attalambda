# AttaLambda Generic Pure Value Rendering and Printing

## Goal

Give AttaLambda a natural way to print any of its public tagged data values while preserving the project's purity contract completely.

The architecture must remain:

```text
tagged AttaLambda value
        ↓
pure untyped unary lambda computation
        ↓
value-to-string
        ↓
AttaLambda String
        ↓
existing stdout
        ↓
host boundary
```

All inspection, recursive traversal, type dispatch, numeric conversion, formatting, escaping, and String construction must happen inside AttaLambda's existing pure lambda-calculus computation layer.

The host must receive only the final String through the existing `stdout` operation.

No new host capability is required.

---

# Core Design

AttaLambda currently has eleven public tagged data types:

```text
Error
Bool
List
Result
Char
String
Rat
Unit
Byte
Option
Map
```

Add pure rendering support for every one of them.

Then add one generic pure dispatcher:

```text
value-to-string
```

and one convenience effect:

```text
print
```

Conceptually:

```text
print value
    =
stdout (value-to-string value)
```

`stdout` remains String-only.

`print` does not replace `stdout`.

`stdout` remains appropriate when the programmer already has raw text they want emitted exactly.

`print` renders an AttaLambda data value into a human-readable representation first.

---

# Purity Requirement

This feature must not weaken AttaLambda's purity standard in any way.

Every production computation involved in rendering must reduce through the same existing pure basis:

```text
variables
unary lambda abstraction
function application
```

Existing macros may provide notation exactly as elsewhere in the language, but they must expand into the existing permitted lambda forms.

The implementation must not use Racket to perform:

- type dispatch
- numeric conversion
- String formatting
- recursive traversal
- escaping
- List formatting
- Map formatting
- Error formatting
- Option or Result inspection
- Byte formatting
- Char formatting

Do not use:

```text
format
number->string
string-append
Racket lists
Racket maps
Racket numbers
Racket type predicates
runtime codec conversion
host requests
reader helpers
```

for production rendering computation.

Existing trusted mechanical macro expansion and lazy evaluation remain allowed under the project's existing purity rules.

The structural purity suite must continue to pass unchanged or become stricter.

---

# No New Runtime Types

Do not add:

```text
Any
Function
Printable
Show
Display
```

or any equivalent new runtime tag.

Do not tag ordinary functions.

Do not change the representation of existing values.

The existing type tags already distinguish every public data type that this feature needs to render.

---

# Functions Are Not Printable

`value-to-string` and `print` operate on **tagged AttaLambda data values**.

They do not support arbitrary raw functions.

For example:

```text
(print 5)
```

is supported.

```text
(print TRUE)
```

is supported.

```text
(print (cons 1 (cons TRUE NIL)))
```

is supported.

But:

```text
(print (lambda (x) x))
```

is outside the public contract.

This is intentional.

AttaLambda functions are ordinary untagged lambda values. Do not introduce Function tagging, reflection, `Any`, host inspection, or other machinery merely to make functions printable.

Likewise, if a List, Map, Option, Result, or other container contains an untagged function, recursively printing that portion of the value is outside the printing contract.

---

# Public API

Add:

```text
error-to-string
bool-to-string
list-to-string
result-to-string
char-to-string
string-to-string
rat-to-string
unit-to-string
byte-to-string
option-to-string
map-to-string

value-to-string

print
```

All `*-to-string` functions and `value-to-string` are pure.

Only `print` performs an effect, and that effect must be implemented solely by composing `value-to-string` with the existing `stdout`.

---

# Generic Dispatch

`value-to-string` must inspect the existing type tag of a tagged AttaLambda value and dispatch to the corresponding pure renderer.

Conceptually:

```text
value-to-string value

ERROR  → error-to-string
BOOL   → bool-to-string
LIST   → list-to-string
RESULT → result-to-string
CHAR   → char-to-string
STRING → string-to-string
RAT    → rat-to-string
UNIT   → unit-to-string
BYTE   → byte-to-string
OPTION → option-to-string
MAP    → map-to-string
```

This dispatch itself must be implemented in pure AttaLambda computation using the existing tag machinery and lambda conditionals.

Do not perform this dispatch in Racket.

Do not perform it in the host.

---

# Recursive Containers

Container renderers do not receive user-supplied rendering functions.

Instead, they recurse through the generic `value-to-string`.

For example:

```text
list-to-string list
```

walks the List and, for every element:

```text
value-to-string element
```

This means heterogeneous Lists work naturally.

Example:

```text
[1, TRUE, "hello"]
```

contains three different tagged types.

Rendering proceeds conceptually as:

```text
List
 ↓
1
 ↓
value-to-string
 ↓
rat-to-string

TRUE
 ↓
value-to-string
 ↓
bool-to-string

"hello"
 ↓
value-to-string
 ↓
string-to-string
```

The final result is:

```text
[1, TRUE, "hello"]
```

Nested containers work the same way.

---

# Required Display Representations

These representations are intended for human-readable inspection.

They are not a general serialization format and are not required to round-trip through the parser.

The representation should nevertheless make the kind of value clear wherever practical.

---

## Rat

Examples:

```text
0
42
-42
3/7
-7/3
```

Rules:

- use exact decimal integers
- retain `/denominator` for non-whole Rats
- never print `/1`
- never use decimal approximation
- preserve sign
- use the existing canonical reduced Rat representation

Examples:

```text
(rat-to-string 42)
→ "42"

(rat-to-string -7/3)
→ "-7/3"
```

---

## Bool

Render:

```text
TRUE
FALSE
```

---

## Unit

Render:

```text
UNIT
```

---

## Byte

A Byte must remain visibly distinct from an ordinary Rat.

Render:

```text
BYTE(0)
BYTE(42)
BYTE(255)
```

The contained number is decimal.

---

## Char

Chars should be recognizable as Chars rather than Strings.

For ordinary printable ASCII characters, prefer familiar Char notation:

```text
#\A
#\a
#\7
#\(
```

Use named forms for:

```text
#\space
#\tab
#\newline
#\return
```

For byte-sized Chars that do not have a clean printable representation, use:

```text
CHAR(n)
```

where `n` is the decimal value from 0 through 255.

Example:

```text
CHAR(0)
CHAR(255)
```

Do not expose internal binary Nat representation.

---

## String

Strings must be visibly distinguishable from other values.

Render with surrounding double quotes:

```text
"hello"
"42"
"TRUE"
```

Therefore:

```text
(print "42")
```

prints:

```text
"42"
```

while:

```text
(print 42)
```

prints:

```text
42
```

### String escaping

Within the rendered representation:

```text
"    → \"
\    → \\
newline → \n
tab     → \t
return  → \r
```

Printable ordinary bytes may appear directly.

Other non-printable byte values should use a fixed byte escape such as:

```text
\x00
\xFF
```

The escaping implementation must itself be pure AttaLambda computation.

---

## List

Render Lists using square brackets:

```text
[]
[1]
[1, 2, 3]
[1, TRUE, "hello"]
```

Each element is recursively rendered using `value-to-string`.

Nested example:

```text
[1, [2, 3], SOME(TRUE)]
```

The brackets themselves identify the value as a List.

---

## Option

Render:

```text
NONE
SOME(value)
```

Examples:

```text
NONE
SOME(5)
SOME("hello")
SOME([1, 2])
```

`SOME` payloads recurse through `value-to-string`.

`NONE` must not attempt to inspect or render its unused internal payload.

---

## Result

Render:

```text
OK(value)
ERR(error)
```

Examples:

```text
OK(5)

OK([1, 2, 3])

ERR(ERROR(DIVIDE-BY-ZERO))
```

The Ok payload recurses through `value-to-string`.

The Err payload is an Error and uses `error-to-string`.

Do not evaluate the unselected variant.

---

## Map

Render:

```text
{}
{key: value}
{key1: value1, key2: value2}
```

Keys and values recurse independently through `value-to-string`.

Examples:

```text
{"name": "Ada", "age": 36}

{1: TRUE, 2: FALSE}

{[1, 2]: SOME("value")}
```

The braces and key/value separator identify the representation as a Map.

### Map ordering

Use the existing internal Map entry traversal order.

Do not introduce sorting.

Do not make rendering order part of Map semantics.

Do not document the textual Map representation as canonical serialization.

Two semantically equivalent Maps are not guaranteed to have identical rendered entry order unless their existing internal ordering already happens to match.

---

## Error

Errors must be clearly recognizable as Errors.

Render:

```text
ERROR(...)
```

Examples:

```text
ERROR(DIVIDE-BY-ZERO)

ERROR(INVALID-NAT)

ERROR(TYPE-MISMATCH(arg1 expected RAT got BOOL))
```

Existing Error frames must remain visible.

Conceptually:

```text
ERROR(
  INVALID-NAT
    -> foo(...)
    -> bar(...)
)
```

The exact interior diagnostic wording should preserve the existing Error diagnostic semantics:

- kind
- expected type
- actual type
- argument position
- function name
- frame ordering
- result frames
- unknown type fallback
- unknown Error-kind fallback

### Pure Error formatting

Move the authoritative construction of human-readable Error diagnostics into the pure AttaLambda layer.

The existing Racket Error reader may convert the resulting AttaLambda String into a host String for testing or diagnostics, but it must not remain an independent source of Error-formatting policy.

To avoid unnecessarily changing existing runner/test diagnostic output, use a private pure helper:

```text
raw-error-diagnostic-string
```

that produces the current diagnostic body:

```text
DIVIDE-BY-ZERO
```

or:

```text
TYPE-MISMATCH(arg1 expected RAT got BOOL)
```

Then:

```text
error-to-string error
```

produces:

```text
"ERROR("
+
raw-error-diagnostic-string(error)
+
")"
```

The existing reader can delegate directly to `raw-error-diagnostic-string`, preserving current external diagnostic formatting while moving the computation itself into the pure language layer.

---

# Shared Numeric Rendering

The main new primitive algorithm required is:

```text
binary Nat → decimal Char List
```

This must be implemented in pure lambda computation.

Do not convert binary Nats into Racket integers.

Do not convert large values through unary Church numerals.

Use the existing binary Nat operations.

A normal approach is repeated division and remainder by ten:

```text
if n < 10
    digit(n)
else
    decimal(n / 10) ++ digit(n % 10)
```

An implementation that accumulates digits in reverse and reverses once is also acceptable if simpler or more efficient.

Reuse this machinery for:

- Rat numerator magnitude
- Rat denominator
- Byte decimal values
- fallback numeric Error/type identifiers
- numeric Char fallback
- any other display-only decimal metadata

For String byte escaping, a small pure hexadecimal helper may similarly convert a Byte into two hexadecimal digit Chars.

---

# Avoid Mutual Top-Level Recursion

The implementation must respect AttaLambda's current recursion rules.

Do not create a cycle such as:

```text
value-to-string → list-to-string → value-to-string
```

using mutually recursive top-level definitions.

The language intentionally permits pure self recursion through `rec` while rejecting top-level mutual recursion.

Structure the implementation around one internal self-recursive renderer.

Conceptually:

```text
raw-render-value recur value =
    dispatch tag:
        LIST   → raw-render-list recur value
        MAP    → raw-render-map recur value
        OPTION → raw-render-option recur value
        RESULT → raw-render-result recur value
        ...
```

Then construct the recursive function once using the existing pure fixed-point machinery:

```text
raw-value-to-string =
    fix raw-render-value
```

Container helpers receive the recursive renderer explicitly:

```text
raw-render-list recur list
raw-render-map recur map
raw-render-option recur option
raw-render-result recur result
```

This avoids forbidden mutual module recursion while remaining entirely inside the pure lambda basis.

The public:

```text
list-to-string
map-to-string
option-to-string
result-to-string
```

may call the already-constructed internal recursive renderer when they need to render their contents.

Do not relax the recursion purity rules for this feature.

---

# Type-Specific Functions

Each type-specific function must validate its own tagged input using the existing strict type-checking conventions where those conventions apply.

Examples:

```text
rat-to-string
```

requires Rat.

```text
bool-to-string
```

requires Bool.

```text
list-to-string
```

requires List.

An ordinary incoming Error should continue to follow the existing Error propagation policy unless the function explicitly exists to consume Error as data.

---

# Special Error Handling

`error-to-string` is intentionally different.

Its purpose is to consume an Error and turn it into a String.

Therefore it must not use a wrapper that automatically bubbles an Error argument before the renderer sees it.

Follow the same conceptual exception already required by operations such as `make-err`, where Error is deliberately consumed as data.

Calling:

```text
(error-to-string some-error)
```

must produce String.

Calling:

```text
(error-to-string 5)
```

must produce the normal TypeMismatch Error expecting ERROR.

Do not weaken general Error propagation elsewhere.

---

# `value-to-string`

Add a pure public:

```text
value-to-string value
```

Its contract is:

> Render any public tagged AttaLambda data value as a human-readable String.

It must:

1. inspect the existing tag
2. select the appropriate renderer
3. recursively render nested tagged values
4. return a tagged String

It must not:

- call stdout
- call host
- call runtime codecs
- use Racket formatting
- mutate anything
- add new type tags
- inspect arbitrary raw lambdas as though they were tagged objects

For all eleven existing public tagged types, rendering must succeed for valid printable contents.

---

# Unknown Tagged Values

The public type set is currently closed.

Nevertheless, the dispatcher must contain an explicit final fallback rather than relying on accidental behavior.

If it encounters a tagged object whose tag is not one of the currently supported public types, render a pure diagnostic placeholder such as:

```text
<UNPRINTABLE-TYPE:n>
```

where `n` is the pure decimal representation of the tag.

This fallback is for defensive behavior and future evolution.

It does not add an `Any` type or promise support for arbitrary untagged functions.

---

# `print`

Add:

```text
print value
```

Conceptually:

```text
print value =
    stdout (value-to-string value)
```

There must be no new host operation named `print`.

There must be no new host protocol schema.

There must be no second output primitive.

The only privileged output remains the existing String-only `stdout`.

`print` returns the same successful/failure shape as `stdout` because it ultimately delegates to it.

Do not automatically append a newline.

A future `println` may be added separately if desired.

---

# `stdout` vs `print`

Document the distinction clearly.

Use:

```text
stdout
```

when emitting text exactly as supplied.

Example:

```text
(stdout "hello")
```

writes:

```text
hello
```

Use:

```text
print
```

when displaying the representation of an AttaLambda value.

Example:

```text
(print "hello")
```

writes:

```text
"hello"
```

Similarly:

```text
(print 5)
```

writes:

```text
5
```

and:

```text
(print
  (cons 5
    (cons TRUE
      (cons "hello" NIL))))
```

writes:

```text
[5, TRUE, "hello"]
```

---

# Suggested Implementation Location

Prefer a dedicated pure module:

```text
core/to-string.rkt
```

This module should contain:

- fixed display Strings / Char sequences
- decimal conversion
- hexadecimal byte conversion if required
- scalar renderers
- container rendering helpers
- Error diagnostic rendering
- generic tag dispatch
- the internal self-recursive renderer
- public pure `*-to-string`
- public pure `value-to-string`

It may depend only on permitted pure core modules.

It must not depend on:

```text
runtime/
readers/
effects/
runner/
runtime/host.rkt
```

or privileged Racket formatting/conversion helpers.

---

# `print` Location

Keep `print` outside the pure core because it performs the existing stdout effect.

Prefer a very small composition layer such as:

```text
effects/print.rkt
```

whose only meaningful computation is:

```text
value
  ↓
value-to-string
  ↓
existing stdout wrapper
```

Alternatively, the language facade may construct `print` directly from the already injected `stdout` function if that is simpler and more consistent with the current dependency direction.

Do not inject the host a second time.

Do not grant `print` direct access to `host`.

---

# Function Names and Exports

Add normal diagnostic function-name values for:

```text
error-to-string
bool-to-string
list-to-string
result-to-string
char-to-string
string-to-string
rat-to-string
unit-to-string
byte-to-string
option-to-string
map-to-string
value-to-string
print
```

Expose them through `#lang attalambda` using the current lowercase callable naming convention.

Do not add legacy uppercase aliases.

---

# Phase 1 — Pure Scalar Foundation

Implement pure rendering for:

```text
Rat
Bool
Unit
Byte
Char
String
```

Also implement:

```text
binary Nat → decimal
Byte → two-digit hexadecimal
String escaping
```

### Required tests

Cover:

```text
0
1
42
large whole Rat
positive fraction
negative fraction
TRUE
FALSE
UNIT
BYTE(0)
BYTE(255)
ordinary Char
space
tab
newline
Char 0
Char 255
empty String
ordinary String
quotes
backslashes
control bytes
UTF-8 byte sequences
wrong tagged arguments
incoming Error propagation
```

Run the complete test and purity suite.

Do not continue until it passes.

---

# Phase 2 — Pure Error Rendering

Implement:

```text
raw-error-diagnostic-string
error-to-string
```

Move Error formatting policy from the Racket reader into pure AttaLambda computation.

Update the existing reader to observe the pure result rather than duplicate its logic.

Preserve existing runner/test diagnostic behavior unless deliberately covered by this spec.

### Required tests

Cover all current Error kinds and representative frames:

```text
TypeMismatch
EmptyList
InvalidNat
DivideByZero
InvalidChar
InvalidString
WrongResultVariant
NonWholeExponent
InvalidCount
InvalidByte
host/protocol kind fallback
HTTP kind fallback
single frame
multiple frames
result frame
unknown kind fallback
unknown type fallback
```

Also prove:

```text
(error-to-string error)
```

consumes Error as data.

Run the complete test and purity suite.

---

# Phase 3 — Generic Recursive Renderer

Implement the single pure recursive rendering engine.

Support:

```text
Error
Bool
List
Result
Char
String
Rat
Unit
Byte
Option
Map
```

Container helpers must receive and reuse the recursive renderer rather than forming forbidden mutual top-level recursion.

### Required tests

Cover heterogeneous and deeply nested structures.

Examples:

```text
[1, TRUE, "hello"]

[1, [2, 3], FALSE]

SOME([1, TRUE])

OK({"answer": 42})

{1: TRUE, "x": [2, 3]}

ERR(ERROR(DIVIDE-BY-ZERO))
```

Also test empty forms:

```text
[]
{}
NONE
```

Run the complete test and purity suite.

---

# Phase 4 — Public Per-Type API

Expose all eleven `*-to-string` functions plus:

```text
value-to-string
```

Prove each public function:

- accepts its correct tagged type
- returns String
- rejects incorrect tagged inputs through existing Error conventions
- performs no effect
- produces the required representation

Prove `value-to-string` dispatches correctly for every public tagged type.

Run the complete test and purity suite.

---

# Phase 5 — Generic `print`

Add `print` strictly as composition over:

```text
value-to-string
stdout
```

Do not alter `stdout`.

Do not alter the host protocol.

Do not alter the runtime codec.

Add source-level acceptance tests such as:

```text
(print 5)
```

```text
(print TRUE)
```

```text
(print "hello")
```

```text
(print
  (cons 1
    (cons TRUE
      (cons "hello" NIL))))
```

Expected combined representations must match the public display contract.

Also prove that `stdout` retains its existing behavior.

Run the complete test and structural/boundary suite.

---

# Phase 6 — Purity Audit

Perform an explicit audit of every new production path.

Confirm:

```text
value-to-string
rat-to-string
bool-to-string
list-to-string
result-to-string
char-to-string
string-to-string
unit-to-string
byte-to-string
option-to-string
map-to-string
error-to-string
```

contain no host computation.

Confirm all recursive traversal and formatting is expressed through the existing pure lambda machinery.

Confirm:

- no privileged import was added
- no new approved Racket primitive was added
- no host request was added
- no runtime conversion was added
- no Function tag was added
- no Any tag was added
- no generalized reflection mechanism was added
- no purity exception was added
- no mutual-recursion exception was added

`print` itself must cross the boundary only through the already-approved `stdout`.

Run:

```text
./run-all-tests.sh
```

and all existing structural checks included by the project.

Do not weaken a test to make the feature pass.

---

# Phase 7 — Documentation

Update the public API documentation with a concise **Value Rendering and Printing** section.

Document:

```text
*-to-string
value-to-string
print
stdout
```

Explain:

> `value-to-string` renders any tagged AttaLambda data value. Functions are ordinary untagged lambdas and are intentionally outside the printing contract.

Explain the difference between:

```text
(stdout "hello")
```

and:

```text
(print "hello")
```

Document that nested Lists, Maps, Options, and Results render recursively.

Document that these representations are for human-readable display and are not a stable serialization protocol.

Update acceptance/release documentation only where required by the project's existing process.

Avoid unrelated documentation expansion.

---

# Explicit Non-Goals

Do not add:

```text
Any
Function tag
typeclass
protocol
interface
reflection
generic host formatting
overloaded stdout
automatic top-level expression printing
REPL
println
serialization
deserialization
Map sorting
new host operation
new codec authority
Racket value rendering
```

Do not attempt to print arbitrary functions.

Do not change the purity contract to accommodate this feature.

---

# Final Architecture

The finished system should look exactly like this:

```text
                   PURE ATTALAMBDA
        untyped unary lambda-calculus computation

                       value
                         │
                         ▼
                inspect existing tag
                         │
       ┌─────────────────┼──────────────────┐
       │                 │                  │
       ▼                 ▼                  ▼
  rat-to-string    list-to-string     map-to-string
       │                 │                  │
       │            recursively         recursively
       │          value-to-string     value-to-string
       │                 │                  │
       └─────────────────┴──────────────────┘
                         │
                         ▼
                       String
                         │
             ┌───────────┴───────────┐
             │                       │
             ▼                       ▼
        value-to-string            print
        returns String               │
                                     ▼
                                   stdout
                                     │
════════════════ EXISTING HOST BOUNDARY ════════════════
                                     │
                                     ▼
                              write String bytes
```

The boundary remains unchanged.

The host still understands only output bytes from an AttaLambda String.

All knowledge of what a Rat, List, Map, Option, Result, Error, Byte, Char, Bool, Unit, or String looks like belongs to AttaLambda itself.

That is the core requirement of this feature.