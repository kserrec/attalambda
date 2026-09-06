# AttaLambda — Greenfield Core Language Specification

## 1. Project

Create a completely new repository and project:

```text
attalambda
```

Human-facing name:

**AttaLambda**

This is not a refactor or compatibility rewrite of `all_the_lambdas`.

Treat the old project only as:

- a source of ideas;
- a source of algorithms that may be reimplemented;
- evidence about what worked and what became awkward.

Do **not** preserve an old representation merely because old code depends on it.

The purpose of this project is to build the cleanest version we now know how to build.

---

# 2. Long-term objective

AttaLambda should eventually become a small but genuine general-purpose programming language whose computational world is built as faithfully as practical from **pure untyped lambda calculus**.

The intended eventual architecture is:

```text
AttaLambda program
          ↓
strong runtime-typed lambda values
          ↓
pure untyped lambda-calculus encodings
          ↓
one eventual host boundary
          ↓
operating system
```

The first version covered by this specification stops **before `host`**.

This specification builds the foundation necessary for `host` to be added cleanly afterward.

---

# 3. Core design decisions

These decisions are settled for this project.

## Numbers

Normal language numbers use:

> **binary digit lists**

Do not use Church numerals as the practical representation of ordinary numeric values.

Binary representation is chosen because representation size grows with bit width rather than numeric magnitude.

Canonical naturals must be normalized.

Example conceptually:

```text
0 = [0]
1 = [1]
2 = [1,0]
3 = [1,1]
4 = [1,0,0]
5 = [1,0,1]
```

Use one consistent digit order. Prefer most-significant bit first unless a concrete implementation reason strongly favors otherwise.

---

## Type tags

Runtime type tags use:

> **Church numerals**

Church numerals are excellent here because type tags are tiny fixed discriminants.

They are **not** the public numeric representation.

This distinction must remain explicit:

```text
Church numerals
    → small internal tags/discriminants

binary digit lists
    → actual numeric values
```

---

## Lists

Lists follow **Greg Michaelson's general typed-list approach** from *An Introduction to Functional Programming Through Lambda Calculus* rather than the old project's convention of:

```text
pair ... pair ... false
```

Do not make raw `false`, Church zero, and the empty list the same value.

A list is an explicitly list-tagged object.

The tail of every non-empty list must itself be a list object.

The empty list must be an explicit list object with a distinguished internal empty representation.

Use the Michaelson model as the reference architecture, while adapting details where necessary to fit this project's improved Error system.

---

## Runtime typing

The canonical programming layer is:

> **strict strong runtime typing implemented entirely with lambda encodings**

The underlying calculus remains untyped.

Values carry runtime tags.

Functions validate tags.

Invalid use returns lambda-encoded Error values.

No static type checker is required.

---

## Function type checking

Do **not** implement:

```text
type-check1
type-check2
type-check3
type-check4
...
```

Implement one arbitrary-arity type wrapper.

Its arity comes from a lambda list of expected argument types.

Arguments arrive naturally one at a time through currying.

---

## Errors

Errors are ordinary lambda-encoded values.

They:

- propagate automatically through typed function boundaries;
- preserve the original cause;
- accumulate structured context as they propagate;
- do not rely on Racket exceptions for language-level failures;
- do not flatten their history into a host string.

---

## Result

Use `Result` for expected computational failure.

Keep this semantic distinction:

```text
Error
    programmer/runtime-contract failure

Result Err
    legitimate computation that failed
```

Examples:

```text
ADD String Nat
    → Error

DIV Nat zero
    → Result Err(DIVIDE_BY_ZERO)
```

Later:

```text
READ-FILE valid-path-that-does-not-exist
    → Result Err(FILE_NOT_FOUND)
```

---

## Strings

Strings are genuine lambda-built values.

A String is built from:

```text
Char values
    ↓
Michaelson-style List
    ↓
String runtime tag
```

Characters use binary values from 0–255.

---

## Host

Do **not** implement `host` yet.

After this specification is complete, the next project phase will add exactly one privileged external boundary:

```text
(host request)
```

Everything in this specification should be designed so that adding that boundary later is straightforward.

---

# 4. Purity rule

Production object-language computation must use only lambda-calculus machinery.

Allowed computational primitives are fundamentally:

```text
variables
lambda abstraction
function application
```

Readable macros may mechanically lower into those constructs.

Racket may be used only for:

- module hosting;
- Lazy Racket evaluation;
- macro implementation;
- tests;
- human-facing readers;
- tooling.

A reader may inspect a completed lambda value and render it.

A reader may **never** determine an object-language result.

---

# 5. Suggested repository structure

Prefer a clear dependency-oriented structure such as:

```text
attalambda/
├── README.md
├── ARCHITECTURE.md
├── ROADMAP.md
├── macros/
│   ├── lazy-with-macros.rkt
│   └── macros.rkt
├── core/
│   ├── pair.rkt
│   ├── logic.rkt
│   ├── tags.rkt
│   ├── objects.rkt
│   ├── lists.rkt
│   ├── binary-nat.rkt
│   ├── errors.rkt
│   ├── typecheck.rkt
│   ├── typed-logic.rkt
│   ├── result.rkt
│   ├── chars.rkt
│   └── strings.rkt
├── readers/
├── tests/
└── run-all-tests.sh
```

Exact paths may change if a cleaner dependency graph emerges.

Do not create unnecessary abstraction layers.

---

# 6. Macro layer

Provide only mechanical sugar.

At minimum:

```text
def
_let
_if
```

`def` should convert:

```text
(def foo x y = body)
```

to nested unary lambdas.

Conceptually:

```text
define foo =
    λx.λy.body
```

`_let` should mechanically lower to immediate lambda application.

`_if` is the **raw Boolean** conditional and lowers to Boolean selection.

The eventual strict public conditional will be:

```text
IF
```

and is defined later in this specification.

Do not add language features through macros that change the computational model.

---

# 7. Phase 1 — raw foundational calculus

Implement:

```text
pair
first
second
true
false
_not
_and
_or
xor
```

All must be pure lambda terms.

Readers for testing may exist separately.

Do not introduce typed objects yet beyond what is needed to bootstrap the next phase.

Acceptance:

- Boolean truth tables pass.
- Pair selection works.
- No host conditional determines Boolean results.

---

# 8. Phase 2 — Church numeral tags only

Implement enough Church numeral machinery to construct small tags:

```text
church-zero
church-succ
church-one
church-two
...
```

Do not build a large Church arithmetic library.

These numerals exist primarily for discriminants.

Create the initial canonical type-tag table:

```text
0  ERROR
1  BOOL
2  LIST
3  NAT
4  RESULT
5  CHAR
6  STRING
```

Names may be:

```text
error-type
bool-type
list-type
nat-type
result-type
char-type
string-type
```

Future types may continue upward.

Add pure Church equality sufficient for comparing tags.

---

# 9. Phase 3 — generic typed-object representation

Use the standard lambda object shape:

```text
object = {type-tag, value}
```

Implement pure:

```text
make-obj
type
val
is-type
```

`make-obj` constructs the lambda pair.

`type` retrieves its tag.

`val` retrieves its payload.

`is-type expected obj` compares Church tags.

Important architectural rule:

The strict typed layer is a **closed convention**.

Its functions assume arguments are canonical AttaLambda typed values or Error values.

Do not attempt to build a magical validator capable of safely classifying every arbitrary untyped lambda term.

Raw lambda values are internal implementation values.

---

# 10. Phase 4 — Michaelson-style lists

This is foundational and should be designed carefully before numeric code.

## Representation

A non-empty list is conceptually:

```text
{
    LIST-TYPE,
    {
        head,
        tail-list
    }
}
```

where `tail-list` must itself be a valid list object.

Do not terminate lists with raw `false`.

Do not identify NIL with Boolean false or any numeric zero.

---

## NIL

Create one canonical empty list object:

```text
NIL
```

Follow Michaelson's explicit typed-empty-list strategy.

Its payload should use distinguished Error/sentinel values so that it remains a genuine LIST object while still being recognizably empty.

The invariant must ensure that the representation used to identify NIL cannot occur as the tail of a legitimate non-empty cell.

A valid simple model is:

```text
NIL =
{
    LIST-TYPE,
    {
        LIST-EMPTY-SENTINEL,
        LIST-EMPTY-SENTINEL
    }
}
```

where `LIST-EMPTY-SENTINEL` is an Error-like value reserved for this structural role.

The exact internal encoding may follow Michaelson more literally if that proves cleaner.

---

## Core list operations

Implement:

```text
CONS
HEAD
TAIL
IS-NIL
```

Semantics:

### `CONS x xs`

- `xs` must be a LIST.
- valid tail → construct new LIST.
- invalid tail → Error.

### `HEAD xs`

- non-list → Error.
- NIL → empty-list Error.
- non-empty → return stored head.

### `TAIL xs`

- non-list → Error.
- NIL → empty-list Error.
- non-empty → return stored tail LIST.

### `IS-NIL xs`

- non-list → Error.
- NIL → typed TRUE eventually / raw Boolean during bootstrap.
- otherwise → FALSE.

`IS-NIL` must be O(1).

---

## Additional foundational list functions

Once the four primitives are correct, implement:

```text
LEN
APPEND
REVERSE
MAP
FILTER
FOLD
TAKE
DROP
```

Use Y/fixed-point recursion where needed.

Do not implement unnecessary algorithms yet.

---

# 11. Bootstrap allowance

Some early typed operations will necessarily perform their checks manually because the generalized typed-function wrapper does not exist yet.

This is allowed temporarily for:

- core List constructors;
- binary Nat bootstrap;
- Error bootstrap.

Once the generic checker exists, migrate ordinary public typed operations onto it where appropriate.

Do not preserve duplicated ad hoc checking merely because it was used during bootstrapping.

---

# 12. Phase 5 — binary natural numbers

Build the canonical practical numeric type.

## Representation

A typed natural is:

```text
{
    NAT-TYPE,
    binary-digit-list
}
```

The payload is a lambda-built list representation.

Digits should be the simplest pure lambda values practical for the implementation.

Prefer raw lambda Booleans as bits:

```text
false = 0
true  = 1
```

unless testing demonstrates that another raw 0/1 representation is materially cleaner.

Do not tag every individual bit unless that provides a concrete benefit.

The Nat wrapper supplies the runtime type.

---

## Canonical form

Require:

```text
zero = [0]
```

All non-zero values:

- begin with `1`;
- contain no unnecessary leading zeroes.

Never allow an empty bit-list to escape as a Nat.

---

## Required raw binary operations

Implement pure algorithms for:

```text
normalize
is-zero
succ
add
sub
mult
eq
lt
lte
gt
gte
```

`sub` may saturate at zero for naturals.

Add division/modulo later in this phase if straightforward; otherwise it may be Phase 6.

Do not optimize through host arithmetic.

Readers may convert the completed binary encoding into a Racket integer solely for tests/output.

---

## Initial constants

Define at least:

```text
ZERO
ONE
TWO
THREE
...
```

as typed binary Nat values.

A small useful range is sufficient.

Do not add numeric literal syntax.

---

# 13. Phase 6 — structured Error system

Replace the old project's string-oriented error idea with a structured lambda representation from the start.

## Error type

Every Error is:

```text
{
    ERROR-TYPE,
    error-payload
}
```

The payload must preserve:

1. the root failure;
2. propagation context.

Do not replace the root cause as an error moves upward.

---

## Error kinds

Use small Church numeral discriminants for error kinds.

At minimum:

```text
TYPE-MISMATCH
EMPTY-LIST
INVALID-NAT
DIVIDE-BY-ZERO
```

Add others only as required.

These are not public numbers.

They are tiny internal tags.

---

## Error frames

Represent propagation frames structurally as lambda data.

A frame should contain at least:

```text
argument-position
expected-type
```

For a root type mismatch also preserve:

```text
actual-type
```

Conceptually:

```text
Error {
    root:
        TypeMismatch {
            expected,
            actual,
            argument
        }

    frames:
        [
            { argument, expected },
            ...
        ]
}
```

The exact nested-pair representation is an implementation detail.

Use the project's List representation for the frame list.

---

## Bubbling rule

When an Error is supplied to another typed function:

- do not execute the underlying function;
- do not discard the existing Error;
- add a new frame describing the current function boundary;
- propagate the resulting Error.

Do not flatten the history into a string.

---

## Function names

Strings do not exist yet.

Therefore early error frames do not need textual function names.

They may initially contain:

```text
argument-position
expected-type
```

After String exists, extend frames to include:

```text
function-name : STRING
```

and update readers accordingly.

Do not introduce host strings into Error merely to solve this early.

---

# 14. Phase 7 — generalized arbitrary-arity typed functions

This replaces all arity-specific checking.

There must never be:

```text
type-check2
type-check3
type-check4
...
```

in the final architecture.

---

## Signature representation

Represent expected argument types as an AttaLambda LIST:

```text
[NAT-TYPE, NAT-TYPE]
```

or:

```text
[STRING-TYPE, NAT-TYPE, BOOL-TYPE, CHAR-TYPE]
```

The list itself defines the function's arity.

---

## Core mechanism

Create one generic constructor conceptually like:

```text
make-typed-function
    raw-function
    expected-types
    return-type
```

It processes arguments one at a time.

For each expected type, it returns one lambda awaiting one argument.

Example:

```text
expected = [Nat, Nat]

make-typed-function add expected Nat
```

behaves like:

```text
λarg1.
    check arg1
    λarg2.
        check arg2
        wrap result as Nat
```

No explicit arity number is needed.

---

# 15. Progressive application

When a valid argument arrives:

1. inspect expected type = HEAD(expected-types);
2. verify argument tag;
3. unwrap argument using `val`;
4. partially apply the raw function to that raw value;
5. recurse with:
   - partially applied raw function;
   - TAIL(expected-types);
   - next argument position.

Example:

```text
raw = add
types = [Nat, Nat]

receive TWO
    → validate
    → raw becomes (add two)
    → types becomes [Nat]

receive THREE
    → validate
    → raw becomes ((add two) three)
    → types becomes []

types empty
    → wrap raw result as Nat
```

---

# 16. Critical requirement — preserve remaining arity after an error

This is mandatory.

A naïve progressive checker has a serious problem.

Given:

```text
((ADD WRONG-VALUE) TWO)
```

if the first application immediately returns an Error object, the second application tries to invoke that Error as a function.

Do not do that.

When a failure occurs before all arguments have arrived:

1. create/bubble the Error immediately;
2. calculate how many expected arguments remain;
3. return one ignoring lambda for each remaining argument;
4. only after the final expected argument has been supplied return the Error.

Conceptually, for a two-argument function:

```text
ADD wrong
    → λignored. ERROR
```

therefore:

```text
((ADD wrong) TWO)
    → ERROR
```

For a five-argument function failing on argument two:

```text
((F a) bad)
    → λ_.λ_.λ_.ERROR
```

This preserves ordinary curried calling syntax and deterministic error behavior.

Implement this using the remaining expected-type list.

No host arity counting.

---

# 17. Error propagation during generic checking

At each argument:

### Argument is valid expected type

Continue partial application.

### Argument is another canonical typed value of the wrong type

Create a new root `TYPE-MISMATCH` Error.

Preserve:

```text
expected type
actual type
argument position
```

Then return an error-absorbing lambda chain for remaining arguments.

### Argument is already an Error

Do not replace it.

Append/prepend the current propagation frame.

Then return the same remaining-arity absorber chain.

---

# 18. Return handling

Support both categories of raw implementation:

## Raw-result function

Example:

```text
raw-add : bits -> bits -> bits
```

The generic typed wrapper should automatically package the final raw result:

```text
{NAT-TYPE, result}
```

## Already-typed-result function

Some operations may naturally return an already-tagged object such as:

```text
Result
Error
a polymorphic existing value
```

Do not create separate arity-specific systems for this.

Provide one small generic mechanism for selecting the finalization policy, such as:

```text
wrap-return
keep-return
```

or a finalizer function argument.

Keep this simple.

---

# 19. Phase 8 — canonical typed Boolean layer

Define:

```text
TRUE  = {BOOL-TYPE, true}
FALSE = {BOOL-TYPE, false}
```

Build strict typed operations:

```text
NOT
AND
OR
XOR
```

using the generalized function checker where possible.

Wrong types return/bubble Error.

---

# 20. Typed `IF`

Add a canonical strict conditional:

```text
IF
```

This is distinct from internal raw `_if`.

Contract conceptually:

```text
IF : BOOL -> A -> A -> A
```

Behavior:

1. condition Error → bubble Error;
2. condition not BOOL → type Error;
3. condition BOOL → unwrap raw Boolean selector;
4. select one branch;
5. do not evaluate the unselected branch.

Do not require the branches to have a hard-coded type.

Preserve laziness.

`IF` is allowed to use custom logic rather than the generic monomorphic function wrapper because its return is intentionally polymorphic.

The eventual public programming layer should prefer:

```text
IF
```

while internal raw code may use:

```text
_if
```

---

# 21. Phase 9 — migrate binary Nat operations to generic typing

Now replace bootstrap/manual typed wrappers for ordinary Nat operations.

Public Nat API should include at least:

```text
SUCC
ADD
SUB
MULT
EQ
LT
LTE
GT
GTE
IS-ZERO
```

All should:

- accept canonical typed Nat values;
- use the generalized checker;
- bubble Error correctly;
- return typed values.

Example:

```text
((ADD TWO) THREE)
    → typed Nat 5
```

Wrong type:

```text
((ADD TRUE) THREE)
    → structured Error
```

No arity-specific checking code.

---

# 22. Phase 10 — Result

Add:

```text
RESULT-TYPE
```

Representation:

```text
Result =
{
    RESULT-TYPE,
    {
        success-bool,
        payload
    }
}
```

where:

```text
success-bool = true
    → Ok

success-bool = false
    → Err
```

Implement:

```text
make-ok
make-err
is-ok
is-err
unwrap-ok
unwrap-err
```

`make-err` must accept an Error payload.

---

# 23. Error versus Result rule

Document this explicitly in code and architecture docs.

## Error

Use for:

- wrong runtime type;
- violated function contract;
- malformed internal value;
- using `HEAD` on NIL;
- similar programming/runtime contract errors.

These automatically propagate through typed function boundaries.

## Result Err

Use when failure is an expected part of a valid computation.

Examples:

```text
division by zero
future file not found
future socket bind failure
```

A function receiving valid argument types may return:

```text
Ok(value)
```

or:

```text
Err(error)
```

Do not automatically unwrap or propagate the Error inside a Result.

`Result` is an ordinary valid typed value.

---

# 24. Add safe division

Once Result exists, add binary Nat division if not already implemented.

Expose a strict operation conceptually:

```text
DIV : NAT -> NAT -> RESULT
```

Behavior:

```text
valid x / valid nonzero y
    → Ok(Nat)

valid x / ZERO
    → Err(DIVIDE-BY-ZERO Error)

wrong input type
    → Error
```

This is the canonical test proving the Error/Result distinction.

---

# 25. Phase 11 — Char

Add:

```text
CHAR-TYPE
```

A Char is:

```text
{
    CHAR-TYPE,
    binary-digit-list
}
```

Its binary payload must represent an integer:

```text
0..255
```

Do not use Racket characters as the object-language representation.

---

# 26. Char construction

Provide a strict constructor:

```text
MAKE-CHAR
```

that accepts a typed Nat.

Behavior:

```text
Nat 0..255
    → Char

Nat >255
    → Error INVALID-CHAR

wrong type
    → Error
```

The stored Char payload may reuse the Nat's normalized raw binary representation rather than nesting a full Nat object.

---

# 27. Character constants

Start with a practical subset rather than all 256 names.

At minimum define:

```text
A-Z
a-z
0-9

SPACE
TAB
CR
LF

.
,
:
;
/
\
-
_
?
=
&
%
#
(
)
[
]
{
}
```

Add any additional printable ASCII characters needed naturally.

Each constant is a genuine lambda-built Char.

No host character literals determine language computation.

---

# 28. Char reader

A host-level reader may:

1. inspect Char's binary payload;
2. convert it to an integer;
3. look up the corresponding character in a fixed reader table;
4. render it for tests/humans.

This reader is outside the object language.

It may not feed the host character back into computation.

For unsupported values, render something deterministic such as:

```text
char:173
```

until a broader table is added.

---

# 29. Phase 12 — String

Add:

```text
STRING-TYPE
```

Representation:

```text
{
    STRING-TYPE,
    char-list
}
```

where `char-list` is the canonical Michaelson-style LIST and every element must be a CHAR.

The empty String is:

```text
{
    STRING-TYPE,
    NIL
}
```

---

# 30. String construction

Provide:

```text
MAKE-STRING
```

Input:

```text
LIST
```

Validate recursively that every element is `CHAR`.

Valid:

```text
[Char('h'), Char('i')]
    → String("hi")
```

Invalid element:

```text
[Char('h'), Nat(5)]
    → Error
```

Validation must use lambda computation.

---

# 31. Initial String operations

Implement at least:

```text
STRING-EMPTY?
STRING-LENGTH
STRING-EQ
STRING-APPEND
STRING-HEAD
STRING-TAIL
STRING-PREFIX?
STRING-CONTAINS?
```

Prefer:

```text
STRING-HEAD
```

and similar partial operations to use either:

- Error for invalid contract use; or
- Result/Option if expected absence is part of the operation.

Do not introduce Option unless it clearly improves the design. Result is sufficient for this initial project.

---

# 32. String length result

`STRING-LENGTH` must return the canonical binary-backed `NAT`.

Do not return a Church numeral merely because list traversal naturally counts with one.

If an internal algorithm uses a Church counter temporarily, convert to binary before exposing the result—or preferably accumulate directly using binary Nat operations.

---

# 33. Function names in Error frames

Once String exists, upgrade structured Error frames.

Add:

```text
function-name : STRING
```

to propagation context.

The generalized typed-function constructor should now accept a lambda String function name.

Conceptually:

```text
make-typed-function
    raw-function
    function-name
    expected-types
    return-policy
```

An error can now structurally represent:

```text
root:
    TYPE-MISMATCH
    expected STRING
    actual NAT
    argument 2

frames:
    [
        function "FOO",
        function "BAR"
    ]
```

Do not flatten this into one String internally.

---

# 34. Error reader

The host reader may render the structured lambda Error into something pleasant:

```text
FOO(arg2 expected STRING got NAT)
  -> BAR(arg1 expected BOOL)
```

The exact presentation is secondary.

The data itself must remain structured.

---

# 35. String reader

A host reader may recursively render Char values into a human-readable host String.

Again:

```text
lambda String
    → host String
```

is one-way observation only.

Do not use host String operations to implement `STRING-EQ`, `STRING-APPEND`, parsing, searching, etc.

---

# 36. Purity validation

Create a simple repository purity check.

Production object-language modules should be scanned for accidental use of forbidden host computation such as:

```text
if
cond
case
+
-
*
/
=
equal?
list
map
foldl
string-append
substring
regexp
vector
hash
set!
```

except in explicitly marked:

```text
readers/
tests/
macros/
tooling/
```

The exact checker may be conservative.

The objective is to make accidental impurity difficult.

---

# 37. Tests

Every major representation needs direct tests.

## Lists

Test:

- NIL is a LIST.
- `IS-NIL NIL`.
- `CONS`.
- `HEAD`.
- `TAIL`.
- `HEAD NIL` Error.
- `TAIL NIL` Error.
- invalid tail to `CONS` Error.
- nested lists.

## Nat

Test:

- normalization.
- 0, 1, 2, powers of two.
- addition.
- subtraction.
- multiplication.
- comparisons.
- larger values demonstrating binary scalability.

## Errors

Test:

- wrong type creates root Error.
- Error passed into another typed function preserves root.
- new frame is added.
- root metadata does not change.

## Generic checker

Test functions of:

```text
0 args if supported
1 arg
2 args
3 args
5 args
```

Prove no arity-specific code exists.

Critically test:

```text
failure on arg1 of a 5-arg function
failure on arg3 of a 5-arg function
```

and prove remaining arguments are safely absorbed before final Error appears.

## IF

Test:

- TRUE selects first branch.
- FALSE selects second.
- wrong condition type → Error.
- incoming Error bubbles.
- unselected divergent/error-producing branch is not forced.

## Result

Test:

- Ok.
- Err.
- divide by zero.
- wrong type remains Error rather than Result Err.

## Char/String

Test:

- valid chars.
- boundary 0.
- boundary 255.
- 256 rejected.
- String validation.
- append.
- equality.
- prefix.
- length.
- empty String.

---

# 38. Documentation requirements

Create `ARCHITECTURE.md` early.

It should explain:

## Underlying truth

Everything computationally meaningful is ultimately untyped lambda calculus.

## Raw versus runtime-typed values

The calculus is untyped, but the language constructs tagged values and enforces runtime contracts.

## Why Church numerals still exist

Only for tiny tags/discriminants.

## Why public numbers are binary

Performance/scalability.

## Why lists follow Michaelson

Explicit list identity and clean NIL semantics.

## Why generic function checking is curried

Expected-type list determines arity and each application validates one argument.

## Error versus Result

Make the distinction explicit.

## Future host boundary

Explain that external effects will later enter through one primitive, but `host` is not part of this phase.

---

# 39. Things explicitly not to build yet

Do not implement:

- `host`;
- filesystem I/O;
- networking;
- HTTP;
- standalone `#lang`;
- CLI;
- numeric literal syntax;
- String literal syntax;
- static typing;
- coercive typing;
- mutation;
- threads;
- async;
- classes;
- records;
- JSON;
- parser beyond Lisp syntax;
- optimizer;
- compiler.

This phase exists to make the **computational universe correct first**.

---

# 40. Implementation sequence

Execute in these passes.

## Pass 1

Repository scaffold, macros, pair, raw Boolean logic.

## Pass 2

Church numeral tags and typed object representation.

## Pass 3

Michaelson-style LIST representation and core operations.

## Pass 4

Binary Nat raw representation and arithmetic.

## Pass 5

Structured Error representation and bubbling primitives.

## Pass 6

Generalized arbitrary-arity curried function type checker, including remaining-arity error absorption.

## Pass 7

Strict typed Bool operations and typed `IF`.

## Pass 8

Migrate Nat API to generalized typing.

## Pass 9

Result and safe binary division.

## Pass 10

Char representation, constants, and reader.

## Pass 11

String representation and basic String algorithms.

## Pass 12

Add String function names to structured error frames; documentation/purity hardening.

Every pass must have focused tests and leave the entire suite green.

---

# 41. Completion criteria for this specification

This first project milestone is complete when a programmer can work entirely with values such as:

```text
TRUE
FALSE

ZERO
ONE
TWO

NIL
CONS

Char
String

Result
Error
```

and write lambda-built computations using strict runtime-checked operations.

The following must all be true:

- lists are explicit Michaelson-style LIST objects;
- empty list is not raw false;
- numbers are scalable binary digit lists;
- Church numerals are used only for tiny tags/discriminants;
- arbitrary-arity functions use one generalized curried runtime checker;
- no `type-check2`, `type-check3`, etc. exist;
- early type failures preserve the remaining curried arity safely;
- Errors preserve root causes and accumulate structured frames;
- Result represents expected failure separately from Error;
- typed `IF` consumes tagged Bool values;
- Char values use 0–255 binary payloads;
- String values are typed lists of typed Char values;
- String operations are themselves lambda computations;
- all core computation remains pure untyped lambda calculus.

---

# 42. Next milestone after this one

Only after the above foundation is stable, begin the next project:

> **AttaLambda: effects and standalone language**

That milestone should add exactly one privileged outside-world primitive:

```text
host
```

Then build ordinary lambda wrappers for:

```text
stdout
read-file
write-file
TCP
```

followed by a minimal lambda-built HTTP server and finally surface the system as its own runnable language.

Do not begin that work until this core milestone is coherent and tested.

---

# 43. Guiding principle

When making a design decision, prefer the option that makes the following sentence most literally true:

> **AttaLambda builds recognizable programming-language behavior out of pure untyped lambda calculus, adding structure through lambda encodings rather than borrowing computation from the host.**

This is a toy language.

It should still be engineered as though its internal rules matter.

---

# Milestone 4 Amendment (2026-09-01) — Exact rational numbers and foundational values

This amendment extends this specification for the fourth milestone. Where it
conflicts with Sections 1 through 43 above, this amendment wins. The earlier
sections remain the literal historical contract under which the completed
milestones were built and are not retroactively rewritten.

The two addenda receive matching Milestone 4 amendments in the same change.
The purity addendum's amendment governs tags and purity; the naming addendum's
amendment governs public spellings.

## M4.1 Final public type set

After the Milestone 4 public switch, the complete public type set is exactly:

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

`Nat` and `Int` are not public types. There is no public Nat or Int type tag,
constructor, constant, literal, typed function, reader, or language export.
There is exactly one public number type: `Rat`.

No floating point, approximate decimal arithmetic, logarithm, trigonometric
function, irrational constant, numeric hierarchy, automatic promotion,
generic arithmetic dispatcher, Tuple type, Bytes type, or Set type is added.
Pair remains internal representation machinery; tuples remain nested Pairs. A
Set can later be represented as a Map whose values are Unit, without a new
type.

## M4.2 Private binary Nat

The normalized most-significant-bit-first binary digit list defined in
Section 3 remains the representation of every whole-number magnitude. It
becomes exclusively private machinery: raw, untagged values used for
magnitudes, counting, characters, bytes, ports, handles, and similar internal
whole-number work.

In addition to the raw operations of Section 12, private Nat provides pure
raw algorithms for:

```text
quotient-with-remainder   (one traversal produces both)
remainder
greatest common divisor
least common multiple
even
odd
halve
exponentiation by repeated squaring
```

Raw Nat division remains selection of the quotient from the combined
quotient-with-remainder result and keeps its current answers. Private Nat
exponentiation must use repeated squaring, not one multiplication per
exponent decrement.

## M4.3 Private Int

A private Int is a raw, untagged pair:

```text
{ sign-bool, magnitude }
```

where `sign-bool` is a raw lambda Boolean (true means nonnegative) and
`magnitude` is a normalized private binary Nat.

Invariants:

- Every construction routes through one canonical constructor.
- Int zero has exactly one representation: positive zero. The canonical
  constructor turns any attempted negative zero into positive zero.

Private Int provides at least: successor, predecessor, addition, subtraction,
multiplication, negation, absolute value, equality, ordering, sign, magnitude,
and parity. Every result routes through the canonical constructor.

Int is not public. It exists only as the numerator machinery for Rat and
related internal work.

## M4.4 Rat representation and canonical form

A Rat is:

```text
{
    RAT-TYPE,
    {
        int-numerator,
        nat-denominator
    }
}
```

where `int-numerator` is a private Int and `nat-denominator` is a private
binary Nat.

Canonical-form invariants, enforced by one canonical constructor through
which every supported Rat construction passes:

- The denominator is nonzero. A zero denominator is invalid and never means
  zero; it is an internal invariant failure, not a value.
- The numerator and denominator are reduced by their greatest common divisor.
- Rat zero has exactly one representation: positive `0/1`.
- The sign lives in the Int numerator; the denominator is always positive.

Equal rational values therefore have exactly one stored representation.

## M4.5 Public Rat operations

The exact public operations and contracts are:

```text
SUCC                  : Rat -> Rat            adds one
ADD                   : Rat -> Rat -> Rat
SUB                   : Rat -> Rat -> Rat
MULT                  : Rat -> Rat -> Rat
DIV                   : Rat -> Rat -> Result
EXP                   : Rat -> Rat -> Result
RECIP                 : Rat -> Result
NEG                   : Rat -> Rat
ABS                   : Rat -> Rat
FLOOR                 : Rat -> Rat
EQ                    : Rat -> Rat -> Bool
LT                    : Rat -> Rat -> Bool
LTE                   : Rat -> Rat -> Bool
GT                    : Rat -> Rat -> Bool
GTE                   : Rat -> Rat -> Bool
IS-ZERO               : Rat -> Bool
IS-WHOLE              : Rat -> Bool
IS-NONNEGATIVE-WHOLE  : Rat -> Bool
```

All use the existing generalized exact-tag checker unchanged. A wrong
argument type produces Error. An expected arithmetic failure produces
`Result Err`. Every successful numeric answer is a canonical Rat.

Specific semantics:

- `DIV x zero` → `Err(DIVIDE-BY-ZERO)`. Otherwise `Ok(x / y)` exactly.
- `RECIP zero` → `Err(DIVIDE-BY-ZERO)`. Otherwise `Ok(1 / x)`.
- `FLOOR` rounds toward negative infinity, including for negative fractions
  and negative whole values.
- `EXP base exponent` accepts only whole-number exponents:
  - exponent not whole → `Err(NON-WHOLE-EXPONENT)`, even when that particular
    fractional power would happen to have an exact rational answer. No
    perfect-root detection exists.
  - negative whole exponent → the reciprocal of the positive power; if the
    base is zero, `Err(DIVIDE-BY-ZERO)`.
  - `EXP 0 0` → `Ok(1)`, following `all_the_lambdas`.
  - Implementation must use the private repeated-squaring machinery.

## M4.6 Number literals

An exact integer datum (optionally signed) and an exact fraction datum are
the only accepted numeric literals. Each mechanically lowers to the canonical
Rat it denotes:

```text
3      → Rat  3/1
-3     → Rat -3/1
7/2    → Rat  7/2
-7/2   → Rat -7/2
0      → Rat  0/1
```

Every inexact numeric datum (such as `1.5` or `1e3`) and every non-real
numeric datum is rejected during expansion rather than converted into a
surprising fraction. No other numeric syntax exists.

## M4.7 Retirements and re-specified whole-number consumers

At the single public switch:

- The public Nat type tag, constants `ZERO` through `TEN`, typed Nat
  functions, Nat reader, and Nat language exports are removed. Literals
  replace the constants.
- `LEN` and `STRING-LENGTH` return whole-valued Rat objects.
- `TAKE`, `DROP`, and `MAKE-CHAR` accept a Rat and verify that it is an
  allowed nonnegative whole number. A negative or fractional count produces
  `Error(INVALID-COUNT)`. `MAKE-CHAR` keeps `Error(INVALID-CHAR)` for values
  above 255. Actual counting and indexing work remains on private binary Nat
  values.
- Public Nat and Rat are never both public number types, in any intermediate
  state a user can observe.

## M4.8 Unit

Unit is a public type with exactly one value:

```text
UNIT = { UNIT-TYPE, fixed-internal-payload }
```

The payload is one fixed internal lambda value; its exact encoding is an
implementation detail. No second Unit value can be constructed.

`UNIT` is the only public Unit operation. There is no Unit predicate: the
exact-tag checker validates Unit positionally, and no polymorphic `Any`
mechanism is added to support one.

Unit replaces `Ok(NIL)` wherever an operation succeeds with no useful answer
(successful stdout, file write, TCP write, TCP close, and related server
results become `Ok(UNIT)`). `NIL` thereafter means only an actual empty List.

## M4.9 Byte

A Byte is:

```text
{ BYTE-TYPE, binary-digit-list }
```

whose payload represents an integer 0 through 255, exactly 256 valid values.

Public operations:

```text
MAKE-BYTE   : Rat  -> Byte     nonnegative whole 0..255, else Error(INVALID-BYTE)
BYTE-VALUE  : Byte -> Rat      whole-valued Rat 0..255
BYTE-EQ     : Byte -> Byte -> Bool
BYTE-LT     : Byte -> Byte -> Bool
BYTE-LTE    : Byte -> Byte -> Bool
BYTE-GT     : Byte -> Byte -> Bool
BYTE-GTE    : Byte -> Byte -> Bool
```

Byte is data, not a second number type: every Rat arithmetic operation
rejects Byte with an ordinary type-mismatch Error.

A byte sequence is `List Byte`. No separate Bytes type or host-backed byte
collection exists. Pure conversions:

```text
STRING-TO-BYTES : String -> List      one Byte per Char
BYTES-TO-STRING : List   -> String    validates every element is a Byte;
                                      an invalid element produces Error
```

"BYTES" in these names means a List of Byte values, not a distinct type.
Both conversions traverse, validate, and convert entirely with
object-language lambdas.

## M4.10 Option

An Option is:

```text
{
    OPTION-TYPE,
    {
        some-bool,
        payload
    }
}
```

mirroring the Result shape: raw `true` means Some, raw `false` means None.

Public operations:

```text
SOME         : value  -> Option
NONE         : Option constant
IS-SOME      : Option -> Bool
IS-NONE      : Option -> Bool
OPTION-CASE  : Option -> some-function -> none-value -> result
```

- `SOME` accepts any non-Error object-language value without an `Any` tag or
  any change to the generalized checker. An Error argument bubbles rather
  than hiding inside Some.
- `OPTION-CASE option some-function none-value` applies `some-function` to
  the Some payload, or returns `none-value` for None. The unselected branch
  is not evaluated. Like `IF`, `OPTION-CASE` may use custom logic because its
  return is intentionally polymorphic; its `option` argument is still
  strictly validated and bubbles Error.

Semantic rule: `NONE` means expected absence; `Result Err` means a
computation failed. Option must not be confusable with failure, false, zero,
NIL, or Unit.

## M4.11 Map

A Map is persistent: setting or removing an entry returns a new Map and never
alters the old Map.

Representation:

```text
{
    MAP-TYPE,
    {
        key-equality-function,
        entry-list
    }
}
```

where `entry-list` is a private object-language List of Pairs (key, value) —
never a Racket list, association list, hash table, dictionary, struct, or
mutable value — and `key-equality-function` is the user-supplied pure
object-language function fixed at construction.

Public operations:

```text
MAKE-MAP      : key-equality-function -> Map      the empty Map
MAP-EMPTY?    : Map -> Bool
MAP-SIZE      : Map -> Rat                        whole-valued
MAP-LOOKUP    : Map -> key -> Option              SOME value or NONE
MAP-CONTAINS? : Map -> key -> Bool
MAP-SET       : Map -> key -> value -> Map
MAP-REMOVE    : Map -> key -> Map
```

- Keys and values may be any non-Error object-language values, without an
  `Any` tag or any change to the generalized checker.
- `MAP-SET` on an existing key replaces its value without creating a
  duplicate entry, under the Map's own equality function.
- `MAP-REMOVE` of an absent key returns an equivalent Map.
- Every search, comparison, and branch is pure unary lambda computation.

Key-equality-function contract:

- It is curried and pure: `key -> key -> Bool`, returning a typed Bool.
- If a comparison returns a non-Bool value, the Map operation returns a
  structured Error. If a comparison returns an Error, it bubbles.
- The caller is responsible for supplying an equivalence relation; the Map
  behaves deterministically according to the function as given.

The central type checker gains no special Map mechanism.

## M4.12 Effect wrapper signatures after Milestone 4

The public effect wrappers reach these contracts (implemented across the
milestone's phases, switched without ever exposing two public number types):

```text
stdout      : String -> Result                     Ok(UNIT)
read-file   : String -> Result                     Ok(List Byte)
write-file  : String -> List Byte -> Result        Ok(UNIT)
tcp-read    →  Ok(List Byte)
tcp-write   →  accepts List Byte, Ok(UNIT)
tcp-close   →  Ok(UNIT)
```

Filesystem paths remain String. Ports, backlog sizes, read limits, handles,
and other ordinary numeric fields are Rat objects representing nonnegative
whole numbers, validated in pure object-language code before any request
reaches the host. Pure HTTP parsing and rendering remain text-oriented,
converting explicitly at the TCP boundary; binary HTTP bodies are preserved
without treating arbitrary bytes as text. The host's authority, the codec's
deterministic-translation-only role, and the single-bridge rule do not
broaden. Expected external failures remain `Result Err`; contract failures
remain Error.

## M4.13 New error kinds

New small internal discriminants, added without renumbering existing kinds:

```text
NON-WHOLE-EXPONENT   expected failure (Result Err) from EXP
INVALID-COUNT        contract Error for negative/fractional counts
INVALID-BYTE         contract Error from MAKE-BYTE outside 0..255
```

`DIVIDE-BY-ZERO` is reused for `DIV` by zero, `RECIP` of zero, and zero
raised to a negative exponent. A zero Rat denominator is an internal
invariant failure, not a public error value.

---

# Explicit Exit Amendment (2026-09-05)

This amendment adds explicit program completion to the existing effects
boundary. Where it conflicts with earlier sections of this document,
including the Milestone 4 Amendment, this amendment wins only for the exit
contract below. All other contracts remain in force.

The public unary effect is `(exit status)`. Its argument must be a Rat whose
value is exactly 0 or 1. The existing generalized type checker returns an
ordinary TypeMismatch Error for a non-Rat argument and bubbles an incoming
Error with the normal propagation frame. Any other Rat, including negative
values, 2, and 1/2, produces the existing InvalidCount Error. Neither failure
calls the host.

Pure AttaLambda validates the status and constructs the ordinary List request
containing the String `"exit"` and the Rat status. This adds a tenth operation
to the closed host protocol. The real host uses the existing deterministic
codec to decode a canonical whole Rat, defensively requires native integer
0 or 1, and performs process termination with that operating-system status.
Successful real exit does not return, does not return `Ok UNIT`, and prints
nothing automatically. An injected fake host may return normally for tests;
the wrapper preserves its result and ordinary lazy evaluation behavior.

Status 0 means successful completion; status 1 means unsuccessful completion.
Pure AttaLambda decides whether a condition is fatal. Error and Result Err
remain ordinary values: neither the host nor the runner inspects an arbitrary
final value or automatically maps an Error kind or Result to an exit status.
A program that never calls exit retains normal status-0 completion. An exit
in an unselected branch remains unforced; a performed exit prevents later
program effects.

The runner may continue using native exit for launcher, source-loading, and
scaffolding failures. Only `runtime/host.rkt` performs explicit
AttaLambda-program-requested process termination. This amendment introduces
no other exit codes, automatic Error output, stderr effect, process spawning,
signals, or exception-style object-language errors.

---

# Public API and List Library Amendment (2026-09-06)

This amendment defines the approved public API update. It overrides earlier
sections only for public callable spellings, Char literal syntax and public
Char constants, and the List contracts below. Existing representations,
numeric semantics, Error/Result distinction, and host authority remain in
force. The matching naming and purity amendments apply. `PLAN.md` records
which implementation Phases have actually completed; specification text is
not evidence that a future Phase has shipped.

## Public spelling and Char literals

Every public callable built-in uses lowercase words separated by hyphens,
preserving existing question marks. The naming amendment gives the complete
inventory. Existing operation behavior is unchanged by renaming; structured
Error frames use the same lowercase public spelling as the called operation.
Old uppercase callable exports are removed, without compatibility aliases.
Map remains Map, with `map-*` operations; `map` transforms a List.

Direct `#\` Char literals mechanically emit the existing canonical Char
representation. Accept ASCII values 0 through 127, including letters, digits,
punctuation, delimiters, and `#\space`, `#\tab`, `#\newline`, `#\return`.
For example `a` is an identifier, `#\a` is a Char, and `"a"` is a String.
Reject non-ASCII Char literals during expansion: their UTF-8 encoding uses
multiple bytes, whereas one Char holds one byte. `make-char` still accepts
the existing nonnegative whole Rat range 0 through 255, and String literals
retain their existing UTF-8 byte encoding. No host Char survives expansion
as an object-language value. After literal support lands, remove all named
public Chars, including letters, digit names, and punctuation/whitespace
names; internal constants may remain for existing implementation use.

## List contracts

All apparent multi-argument applications below are curried unary applications.
Every List result is a proper Michaelson List with canonical NIL termination.
Lists may be heterogeneous wherever an operation does not require a particular
element type. The words `value`, `function`, and `predicate` in this section
describe parameters; they introduce no new runtime type or tag.

| Application | Contract |
| --- | --- |
| `cons value tail` | Existing typed constructor; tail must be List, incoming Error propagates. |
| `head list` | First element; NIL yields the existing empty-List Error. |
| `tail list` | Remaining List; NIL yields the existing empty-List Error. |
| `is-nil list` | Bool indicating whether the List is empty. |
| `len list` | Length as a nonnegative whole Rat. |
| `take count list` | Existing nonnegative whole Rat count contract; preserve the first count elements, or the whole List if shorter. Zero returns NIL. |
| `drop count list` | Existing nonnegative whole Rat count contract; omit the first count elements. Exact/beyond-length counts return NIL. |
| `nth index list` | Zero-based indexing; Some element at the index, otherwise NONE. Index must be a nonnegative whole Rat. |
| `take-while predicate list` | Preserve the initial matching prefix, stopping at the first false predicate result. |
| `drop-while predicate list` | Omit the initial matching prefix; retain the first nonmatching element and its suffix. Stop predicate calls there. |
| `append left right` | Both arguments are Lists; all left elements followed by all right elements, preserving order. |
| `reverse list` | Reverse element order; NIL returns NIL. |
| `zip left right` | Pair corresponding elements as two-element Lists; stop when either input ends. No public Pair type is added. |
| `concat lists` | Remove exactly one nesting level, preserving order. Each outer element must be List; a non-List produces a structured TypeMismatch Error attributed to concat. |
| `flatten list` | Recursively visit nested Lists in order, using their type tags; ordinary non-List values are leaves. Empty nested Lists contribute no elements. |
| `map function list` | Apply the function to each element, preserving order. A callback Error propagates as the operation's Error, never an output element. |
| `filter predicate list` | Preserve exactly the elements whose predicate answers true, in original order. |
| `reduce function initial list` | Accumulate left to right. The curried function receives accumulator, then current element. NIL returns initial. Callback Errors propagate and stop subsequent callback calls. |
| `any? predicate list` | Bool; FALSE on NIL, stop at the first true result. |
| `all? predicate list` | Bool; TRUE on NIL, stop at the first false result. |
| `find predicate list` | First matching value in Option, otherwise NONE; stop at the match. |
| `find-index predicate list` | Zero-based whole Rat index of the first match in Option, otherwise NONE; stop at the match. |
| `contains? equality value list` | Apply the curried equality to value, then each current element. Return Bool, stopping at the first match; FALSE on NIL. Equality is caller-supplied, never universal. |
| `range start end` | Both arguments are whole Rats, including negatives. Start is inclusive, end exclusive, step is +1; start >= end returns NIL. Only this two-argument form exists. |
| `repeat count value` | Repeat value count times; count is a nonnegative whole Rat. Zero returns NIL without using value. |

Thus `reduce f initial [a b c]` means `f (f (f initial a) b) c`, not a
right fold. `zip [a b c] [1 2]` yields `[[a 1] [b 2]]`;
`concat [[1 2] [3]]` yields `[1 2 3]`, while nested Lists within those
elements remain nested; `flatten [1 [2 [3]] NIL]` yields `[1 2 3]`.
`range -2 2` yields `[-2 -1 0 1]`. Bracketed examples here describe values;
they add no List literal syntax.

## Checking, Errors, and evaluation

Typed List/number arguments use the existing exact-tag checking and Error
propagation rules. Negative/fractional counts or indices produce the existing
InvalidCount Error. Fractional range endpoints also produce InvalidCount;
negative whole endpoints are valid. Wrong tagged argument types produce
TypeMismatch. Out-of-range indexing and unsuccessful searches are expected
absence, represented by NONE rather than Error or Result Err.

The predicate rule is identical for `filter`, `any?`, `all?`, `find`,
`find-index`, `take-while`, `drop-while`, and the equality in `contains?`:
a tagged Bool is used normally; Error propagates preserving its root and
existing frames; another tagged result produces TypeMismatch expecting Bool
and attributed to the public List operation. Callbacks are supplied as pure
unary/curried functions, as with Map equality; do not inspect arbitrary
lambdas as tagged values or introduce a Function or Any tag. Check their
returned tagged values at the point the operation needs them.

Encountered Errors propagate through the typed operations instead of becoming
elements or improper tails in generated Lists. Result Err remains an ordinary
value, not an automatically propagated Error. An Error detected before the
last source argument must absorb exactly the remaining arguments through
unary lambdas. Retain ordinary lazy evaluation, and do not evaluate later
predicates after an answer is determined. In particular, `any?`, `all?`,
`find`, `find-index`, `contains?`, `take-while`, and `drop-while` must prove
their stopping rules. Whole-operation propagation of a later callback Error
can require traversing a finite produced List; this amendment introduces no
infinite-List productivity guarantee.

Tests must cover each public spelling and new operation, rejected retired
names, literal/identifier separation, normal/NIL/singleton/heterogeneous Lists,
wrong types, incoming and callback Errors, non-Bool predicates, partial
application, short-circuiting, zero/negative/fractional counts, boundary/past-end
indices, unequal zip lengths, one-level versus recursive flattening, nested
empty Lists, and signed/equal/reversed ranges. Both behavioral and structural
purity suites must pass after each major implementation part.
