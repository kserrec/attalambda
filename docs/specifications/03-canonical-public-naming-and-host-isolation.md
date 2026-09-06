# Addendum — Canonical Public Naming and Host-Language Isolation

This addendum supplements the **AttaLambda — Greenfield Core Language Specification** and the **Type Tags and Absolute Lambda Purity Addendum**.

Where this addendum affects naming decisions, it takes precedence over earlier examples.

## A. Do not expose Racket collision workarounds as language design

The original `all_the_lambdas` project sometimes used names such as:

```text
_if
_let
_cons
```

primarily to avoid collisions with bindings supplied by Racket.

Do **not** carry that convention into AttaLambda merely because Racket is the implementation host.

Once AttaLambda is surfaced as its own language, it controls what its identifiers mean.

Therefore canonical programming-language names should be used where they are the natural names:

```text
if
let
cons
```

The fact that Racket also has bindings with those names is an implementation detail and must not leak into the AttaLambda user experience.

---

# B. Separate internal names from public names

Use explicit semantic names internally.

Prefer names such as:

```text
raw-if
raw-cons
raw-head
raw-tail

typed-if
typed-cons
```

rather than:

```text
_if
_cons
```

An internal name should explain **what layer the operation belongs to**, not merely signal that Racket already had the obvious name.

This distinction is useful architecture:

```text
raw-if
    operates on the raw lambda Boolean selector

typed-if
    accepts a runtime-tagged BOOL object

raw-cons
    performs whatever raw structural construction the list representation needs

typed-cons
    validates the public LIST contract
```

---

# C. Public language names

When the standalone AttaLambda language is surfaced, expose the canonical names:

```text
lambda
def
let
if
cons
```

as appropriate.

The public programmer should not need to know or care that internally these may map to:

```text
typed-if
typed-cons
lambda-let-sugar
```

The language implementation may rename/export internal bindings under their canonical public names.

Conceptually:

```text
internal                    public

typed-if        ----------> if
typed-cons      ----------> cons
lambda-let      ----------> let
```

---

# D. Public `if` means the strict typed conditional

Do not expose the raw Boolean selector as the normal public `if`.

The public:

```text
if
```

must be the strict runtime-typed conditional described in the main specification.

It accepts a tagged BOOL value.

Conceptually:

```text
(if condition then-value else-value)
```

must behave according to:

```text
condition : BOOL
```

The implementation:

1. validates or bubbles the condition;
2. unwraps its raw Boolean payload;
3. performs lambda-based selection;
4. preserves laziness so the unselected branch is not evaluated.

The underlying raw operation remains available internally as:

```text
raw-if
```

or an equivalent clearly named internal binding.

---

# E. Public `cons` means the proper typed List constructor

The public:

```text
cons
```

must construct the canonical AttaLambda LIST representation.

It must not merely expose an arbitrary raw pair constructor.

Conceptually:

```text
(cons value tail)
```

must:

1. require `tail` to be a LIST;
2. create a valid non-empty LIST object;
3. return/bubble Error on invalid input as defined by the List/type system.

The raw structural constructor remains internal under a name such as:

```text
raw-cons
```

if one is needed.

Keep generic pair construction distinct from List construction.

---

# F. Public `let` remains pure sugar

`let` does not need a typed runtime implementation.

It is purely syntactic convenience.

For example:

```text
(let x = value
  body)
```

must mechanically lower to the equivalent unary-lambda application:

```text
((lambda (x)
   body)
 value)
```

No host binding semantics, mutation, environment object, or Racket `let` computation may determine the object-language result.

Its public name should simply be:

```text
let
```

not:

```text
_let
```

---

# G. `def` remains project-defined sugar

Retain:

```text
def
```

as the convenient definition syntax.

For example:

```text
(def add x y = body)
```

must expand to a host top-level binding whose value is ultimately:

```text
lambda x.
    lambda y.
        body
```

Every apparent argument remains curried into a separate unary lambda.

`def` is an AttaLambda language feature implemented as mechanical syntax sugar, not Racket's `define` exposed to users.

---

# H. Do not fight Racket bindings prematurely inside implementation modules

During the greenfield core phase, before the standalone custom language is implemented, foundational files are still ordinary Racket/Lazy Racket modules.

Do not create unnecessary complexity merely so those implementation files themselves can use public names like:

```text
if
let
cons
```

while importing Racket environments that already contain those bindings.

Instead:

```text
core implementation
    → raw-if / typed-if / raw-cons / typed-cons

eventual language surface
    → if / cons / let
```

This keeps the implementation clear now and gives users canonical names later.

The public naming requirement applies to the **AttaLambda language surface**, not necessarily to every internal Racket module identifier.

---

# I. No underscore prefix solely for collision avoidance

As a general naming rule:

> Do not prefix an AttaLambda identifier with `_` merely because the obvious name already exists in Racket.

If an underscore is ever used in the future, it must have an actual AttaLambda semantic meaning.

Host-language namespace management should be handled using the implementation/module system, not exposed through awkward language vocabulary.

---

# J. Canonical language vocabulary takes priority over host vocabulary

When choosing between:

```text
_if
_if_
lambda-if
alt-if
```

and:

```text
if
```

the public language should choose:

```text
if
```

when that is the canonical programming concept being represented.

The same principle applies to:

```text
let
cons
```

and similar future names.

AttaLambda should look like a language designed on its own terms, not a collection of functions trying not to collide with Racket.

---

# K. Internal raw/public strict distinction should remain visible to maintainers

Although users should see the canonical vocabulary, maintainers should be able to tell immediately which layer a definition belongs to.

Prefer an internal convention such as:

```text
raw-*
typed-*
```

where useful.

Example:

```text
raw-if
typed-if

raw-cons
typed-cons

raw-add
typed-add
```

Do not force this prefixing mechanically on every definition if a module already makes the distinction obvious, but use semantic prefixes whenever ambiguity would otherwise exist.

This naming is preferable to underscores because it carries architectural information.

---

# L. Do not automatically rename every public operation in this milestone

This addendum specifically settles the canonical names of foundational language constructs such as:

```text
lambda
def
let
if
cons
```

It does not require an immediate global naming redesign for every typed arithmetic or library operation described elsewhere in the specification.

Names such as:

```text
ADD
SUB
MULT
STRING-APPEND
IS-NIL
```

may remain as specified during the core milestone.

A broader public-library naming convention can be decided when the standalone language surface is built.

Do not delay foundational implementation for cosmetic global renaming.

---

# M. Future standalone language requirement

When AttaLambda eventually becomes its own language, a normal program should be able to look conceptually like:

```text
(def choose x condition =
  (if condition
      (cons x NIL)
      NIL))
```

It should **not** need to look like:

```text
(def choose x condition =
  (_if condition
      (_cons x NIL)
      NIL))
```

The latter exposes a historical Racket-hosting workaround.

The former expresses the language AttaLambda is intended to be.

---

# N. Guiding naming principle

Use this rule whenever naming questions arise:

> **Public AttaLambda names should describe the programming concept. Internal names should describe the implementation layer. Neither should be distorted merely because Racket happens to use the same identifier.**

Racket is the host.

It does not own the vocabulary of AttaLambda.

---

# Milestone 4 Amendment (2026-09-01) — Public names for rational and foundational types

Where this amendment conflicts with Sections A through N above, this
amendment wins. It accompanies the Milestone 4 amendments to the main
specification and the purity addendum.

## O. Retained public spellings with new Rat contracts

These existing public arithmetic and comparison names are kept, and after
the public switch they denote the Rat operations:

```text
SUCC  ADD  SUB  MULT  DIV  EQ  LT  LTE  GT  GTE  IS-ZERO
```

Same spelling, new contract. No `RAT-ADD` style prefix is introduced for the
sole public number type.

## P. New public names

The exact new public spellings are:

```text
Rat     EXP  RECIP  NEG  ABS  FLOOR  IS-WHOLE  IS-NONNEGATIVE-WHOLE
Unit    UNIT
Byte    MAKE-BYTE  BYTE-VALUE  BYTE-EQ  BYTE-LT  BYTE-LTE  BYTE-GT  BYTE-GTE
Bytes   STRING-TO-BYTES  BYTES-TO-STRING
Option  SOME  NONE  IS-SOME  IS-NONE  OPTION-CASE
Map     MAKE-MAP  MAP-EMPTY?  MAP-SIZE  MAP-LOOKUP  MAP-CONTAINS?
        MAP-SET  MAP-REMOVE
```

The `Bytes` row names List-of-Byte conversion operations, not a type.
`MAP-EMPTY?` and `MAP-CONTAINS?` follow the existing `STRING-EMPTY?` /
`STRING-CONTAINS?` question-mark convention for uppercase predicates. The
lowercase Result operations (`make-ok`, `is-ok`, …) and effect wrapper names
(`stdout`, `read-file`, …) are unchanged.

## Q. Retired public names

At the public switch these public spellings are removed and must fail rather
than silently aliasing:

```text
ZERO ONE TWO THREE FOUR FIVE SIX SEVEN EIGHT NINE TEN
```

together with every other public Nat surface. Exact integer and fraction
literals replace the retired numeric constants. After the switch, no public
name contains `NAT` or `INT`, and no public or hidden alias exposes Nat or
Int as a language type.

## R. Internal layer naming

Internal machinery keeps describing its layer, per Sections B and K:
private binary Nat and private Int operations use internal semantic names
(for example `raw-nat-*`, `raw-int-*`, `raw-rat-*` where ambiguity would
otherwise exist) and are never exported by the language surface.

---

# Explicit Exit Amendment (2026-09-05)

This amendment supplements the matching main-specification and purity
amendments. It overrides earlier naming examples only for the new public
effect, whose exact spelling and application are:

```lisp
(exit status)
```

The argument contract is Rat 0 or 1, as defined in the main amendment.
Expose the pure wrapper under the public name `exit`; do not expose Racket's
native exit procedure or add public aliases or status constants. Resolve the
host-name collision through module imports and a private binding such as
`language-exit`, renamed on export. The language supplies the existing host
to the wrapper once, following stdout/files/TCP. `host` remains the sole
privileged binding; `exit` is an ordinary lambda wrapper around that boundary.

Internal pure names `exit-function-name` and `exit-operation` denote the
lambda-encoded String `"exit"`. A peer `effects/exit.rkt` owns pure request
construction and validation, while `runtime/host.rkt` owns the native effect.
Runner-native exit continues to describe launcher/source/scaffolding status;
host exit describes explicit AttaLambda-program-chosen status.

---

# Public API and List Library Amendment (2026-09-06)

This amendment overrides earlier public callable spellings, including the
Milestone 4 exact-name lists. Every public callable built-in uses lowercase
hyphenated names, retaining question marks where already specified. Existing
lowercase names keep their spelling. Old uppercase callable aliases are
removed from `#lang attalambda`, and user-facing Error metadata uses the new
public spelling. Internal raw/typed identifiers remain implementation names;
module renaming handles Racket collisions without new runtime wrappers.

The existing callable inventory becomes:

```text
if not and or xor
cons head tail is-nil len take drop
succ add sub mult div exp recip neg abs floor
eq lt lte gt gte is-zero is-whole is-nonnegative-whole
make-byte byte-value byte-eq byte-lt byte-lte byte-gt byte-gte
string-to-bytes bytes-to-string
some is-some is-none option-case
make-map map-empty? map-size map-lookup map-contains? map-set map-remove
make-ok make-err is-ok is-err unwrap-ok unwrap-err
make-char char-eq char-lt char-lte char-gt char-gte
make-string string-empty? string-length string-eq string-append
string-head string-tail string-prefix? string-contains?
stdout read-file write-file exit
tcp-connect tcp-listen tcp-accept tcp-read tcp-write tcp-close
parse-http-request render-http-response
make-http-path-handler make-http-serve-one make-http-server
host
```

The complete List inventory after the later List Phases is:

```text
cons head tail is-nil len
take drop nth take-while drop-while
append reverse zip concat flatten
map filter reduce
any? all? find find-index contains?
range repeat
```

Map stays Map: `map` transforms a List; `make-map` and `map-*` operate on Map.
The syntax names `lambda`, `def`, and `let` are unchanged. Constants retain
their exact names: `TRUE`, `FALSE`, `NIL`, `UNIT`, `NONE`, `EMPTY-STRING`,
`HTTP-STATUS-OK`, `HTTP-STATUS-BAD-REQUEST`, `HTTP-STATUS-NOT-FOUND`, and
`HTTP-STATUS-INTERNAL-SERVER-ERROR`. They are values, not callable API entries.

After the Char-literal Phase, remove all individual public Char identifiers:
`A` through `Z`, `a` through `z`, `DIGIT-0` through `DIGIT-9`, `SPACE`, `TAB`,
`CR`, `LF`, `DOT`, `COMMA`, `COLON`, `SEMICOLON`, `SLASH`, `BACKSLASH`,
`HYPHEN`, `UNDERSCORE`, `QUESTION`, `EQUAL`, `AMPERSAND`, `PERCENT`, `HASH`,
`LEFT-PAREN`, `RIGHT-PAREN`, `LEFT-BRACKET`, `RIGHT-BRACKET`, `LEFT-BRACE`,
and `RIGHT-BRACE`. Use the main amendment's ASCII `#\` literal contract.
Ordinary identifiers become user-defined names rather than implicitly bound
Chars; internal constants used by the implementation may remain.

Migrate live public examples, README, acceptance documentation, public API
reference, and shipped guide examples with each affected Phase. Retain
earlier specification sections and release evidence as explicitly historical;
this amendment supplies their current spelling interpretation. Document
implemented behavior separately from the later planned List and Char work.
