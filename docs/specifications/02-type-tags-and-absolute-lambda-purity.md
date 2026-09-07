# Addendum — Type Tags and Absolute Lambda Purity

This addendum modifies and strengthens the architectural requirements of the **AttaLambda — Greenfield Core Language Specification**.

Where this addendum is more restrictive than the original specification, this addendum wins.

## A. Type-tag encoding decision

Canonical runtime type tags MUST use **Church numerals**.

For example:

```text
church-zero → ERROR-TYPE
church-one  → BOOL-TYPE
church-two  → LIST-TYPE
church-three → NAT-TYPE
...
```

Continue assigning successive Church numerals as additional types are introduced.

Do not replace these with Scott numerals merely for performance.

The project may eventually contain another five, ten, or more runtime types. This is still a sufficiently small numeric domain that the operational difference between Church and Scott numeral tags is not important enough to outweigh the simplicity and extensibility of Church tags.

Church numerals are therefore deliberately retained for:

```text
type tags
small discriminants
other tiny fixed metadata where appropriate
```

They are **not** the practical number representation.

Normal numeric values remain binary-digit-list-backed.

The architecture is explicitly:

```text
tiny identity/discriminant values
    → Church numerals

ordinary numeric computation
    → binary digit lists
```

If profiling much later demonstrates that tag comparison itself is a material bottleneck, optimization may be reconsidered then. Do not optimize it preemptively.

---

# B. Absolute object-language purity rule

This project MUST preserve the same purity discipline as `all_the_lambdas`.

This is one of the project's defining invariants, not a stylistic preference.

Before the future introduction of `host`, **every production object-language value and computation must ultimately consist only of pure untyped lambda-calculus terms.**

At the computational level, there are only:

```text
variables
one-argument lambda abstraction
function application
```

Nothing else may provide computational power.

---

# C. Every lambda takes exactly one argument

This requirement is absolute.

Production object-language code MUST NEVER use a Racket multi-argument lambda such as:

```racket
(lambda (x y) ...)
```

or:

```racket
(lambda (x y z) ...)
```

or any equivalent multi-argument host function definition.

All apparent multi-argument functions must ultimately be curried:

```racket
(lambda (x)
  (lambda (y)
    (lambda (z)
      ...)))
```

Therefore:

```text
f : A → B → C
```

really is represented as:

```text
λa.λb.result
```

not as a host-language function accepting two parameters simultaneously.

This applies everywhere in the production computational core, including:

- pair constructors;
- Boolean operators;
- list constructors;
- binary arithmetic;
- type checking;
- Error construction;
- Result operations;
- Char operations;
- String operations;
- recursive helpers;
- higher-order functions;
- the generalized arbitrary-arity typed-function machinery.

---

# D. `lambda` is the only function-construction primitive

The only primitive used to construct computational functions is:

```racket
lambda
```

and each such lambda takes exactly one parameter.

Do not use host alternatives such as:

```text
case-lambda
procedure-reduce-arity
match-lambda
lambda with multiple formals
optional arguments
keyword arguments
rest arguments
```

in production object-language computation.

Function application remains ordinary Lisp-shaped application:

```racket
(f x)
```

A call that conceptually takes several arguments is nested application:

```racket
((f x) y)
```

and not a host multi-argument call.

---

# E. `def` is sugar only

The project may provide the same style of `def` macro used by `all_the_lambdas`.

For example:

```racket
(def add x y = body)
```

is permitted only because it mechanically expands to the equivalent of:

```racket
(define add
  (lambda (x)
    (lambda (y)
      body)))
```

The apparent multi-argument syntax is therefore purely cosmetic.

`def` MUST never compile to:

```racket
(lambda (x y) body)
```

The macro's expansion should make the unary-currying invariant obvious and testable.

---

# F. Other sugar has the same restriction

Macros such as:

```text
_let
_if
_cons
```

may exist for readability.

They are not new computational primitives.

Every such form must mechanically expand into terms whose object-language computation consists only of:

```text
one-argument lambdas
application
already-pure lambda values
```

For example, `_let` is merely immediate lambda application.

Raw `_if` is merely application of a lambda-encoded Boolean selector.

Sugar must never smuggle a Racket conditional, arithmetic operation, list operation, mutation, or other host computation into the object language.

---

# G. Generalized typed functions must themselves obey unary currying

The arbitrary-arity typed-function mechanism is especially important here.

It must NOT solve arbitrary arity by constructing a host function that accepts a Racket list or multiple Racket arguments.

Instead, it must generate/return **one unary lambda at a time**.

Given expected types:

```text
[NAT-TYPE, STRING-TYPE, BOOL-TYPE]
```

the resulting typed function behaves structurally like:

```text
λarg1.
    check arg1
    λarg2.
        check arg2
        λarg3.
            check arg3
            final-result
```

The expected-type LIST tells the mechanism whether another unary lambda must be returned.

Arguments are never accumulated into a Racket array, Racket list, vector, or variadic argument structure.

Each argument arrives naturally through one lambda application.

The partially applied raw lambda function carries the computation forward.

---

# H. Error-absorbing continuations must also be unary lambdas

When type checking fails before all arguments have arrived, the mechanism described in the main specification must preserve remaining arity entirely with pure unary lambdas.

For example, failure on the first argument of a three-argument function produces the equivalent of:

```text
λignored.
    λignored.
        ERROR
```

not a host variadic function and not a Racket data structure holding pending arguments.

---

# I. No host data structures inside object-language representations

Production object-language values may not secretly contain:

```text
Racket lists
Racket vectors
Racket hashes
Racket structs
Racket strings
Racket numbers
Racket booleans
mutable cells
host exceptions
```

as computational representations.

If the AttaLambda language contains a List, Nat, Bool, Error, Result, Char, or String, that value must genuinely be represented by the lambda encodings defined by the project.

Host values may appear only at the explicit observation/tooling boundaries described below.

---

# J. Exactly allowed pre-`host` exceptions

Before `host` is introduced, deviation from the pure object-language rule is allowed only for these categories.

## 1. Tests

Test infrastructure may use ordinary Racket freely to:

- execute terms;
- compare observed outputs;
- enforce deadlines;
- create fixtures;
- report results.

Test machinery must never become part of production object-language computation.

## 2. Readers and human-facing output

Readers may use Racket to inspect completed lambda encodings and produce convenient human-readable output.

Examples:

```text
binary Nat → host number/string
Char → host character
String → host string
Error → formatted diagnostic text
```

This is a strictly one-way observation boundary.

A reader's host-level result MUST NOT be fed back into object-language logic to determine a computational result.

## 3. Macros / syntactic sugar

Macros may use Racket's syntax facilities to mechanically translate convenient notation into the permitted pure terms.

This includes tools such as:

```text
define-syntax
syntax-case
syntax-rules
```

when used solely for translation.

Macros must not perform object-language computation on behalf of programs.

---

# K. Module/tooling scaffolding is not object-language computation

Racket is also permitted to provide ordinary repository/module infrastructure such as:

```text
#lang
require
provide
top-level module bindings
CI/test discovery
```

This is implementation scaffolding, not computational machinery available to AttaLambda programs.

Top-level bindings generated by `def` may ultimately use host `define` to give a lambda term a repository-visible name.

The value bound by that name must still satisfy the pure unary-lambda invariant.

---

# L. Forbidden production shortcuts

The following must not be used to determine production object-language results:

```text
Racket if/cond/case
Racket arithmetic
Racket equality
Racket list operations
Racket strings
Racket regex
Racket loops
Racket mutation
Racket exceptions
Racket structs
Racket collections
Racket pattern matching
host recursion
```

If a feature can be built from the lambda universe, build it there.

This applies even when using the Racket operation would be dramatically easier or faster.

Performance does not justify breaking the experiment's defining rule.

---

# M. Raw algorithms remain raw

The preferred architecture is:

```text
strict typed public operation
        ↓
validate tagged arguments
        ↓
unwrap raw lambda values
        ↓
call raw lambda algorithm
        ↓
wrap resulting lambda value
```

Do not implement one typed operation by repeatedly invoking other typed public operations when the same computation can use their raw counterparts internally.

This:

- avoids redundant runtime tag checks;
- keeps type-tag performance negligible;
- mirrors the distinction between representation and public contract;
- keeps raw algorithms reusable.

---

# N. Purity tests

Add automated checks specifically for these invariants.

At minimum, test/scan production computational modules for forbidden multi-argument lambda forms.

The repository must fail CI if production object-language code introduces something equivalent to:

```racket
(lambda (x y) ...)
```

Every production lambda must have exactly one formal parameter.

Also scan for forbidden host computational forms outside explicitly allowed directories/files.

The purity checker should treat at least these locations as separately classified:

```text
production object-language code
macros
readers
tests
tooling
```

Do not rely solely on code review to enforce this requirement.

---

# O. Documentation language

`ARCHITECTURE.md` should state this prominently:

> AttaLambda does not merely avoid using host libraries for major algorithms. Its production computational terms are built exclusively from unary lambda abstraction and application. Every multi-argument function is represented by nested one-argument lambdas. Racket is used only to host/evaluate the terms, provide mechanical syntactic sugar and module tooling, test them, and observe completed values for humans. Until `host` is deliberately introduced, no other computational escape hatch exists.

This should be treated as one of the project's primary claims.

---

# P. Future `host` exception

When `host` is eventually introduced, it becomes the **single deliberate new exception** to this boundary.

At that point the architecture becomes:

```text
pure unary-lambda computational universe
                 ↕
               host
                 ↕
             outside world
```

Do not loosen any other purity rule when `host` is added.

`host` is not permission to begin implementing ordinary language functionality in Racket.

It is solely the explicit effect boundary.

---

# Milestone 4 Amendment (2026-09-01) — Tags and purity for rational and foundational types

Where this amendment conflicts with Sections A through P above, this
amendment wins. It accompanies the Milestone 4 amendments to the main
specification and the naming addendum.

## Q. Canonical tag table after Milestone 4

Type tags remain Church numerals. The canonical table becomes:

```text
0  ERROR
1  BOOL
2  LIST
3  (retired — formerly NAT; permanently unassigned)
4  RESULT
5  CHAR
6  STRING
7  RAT
8  UNIT
9  BYTE
10 OPTION
11 MAP
```

The Nat tag is retired without renumbering any existing non-Nat tag.
Church-three is never reassigned to another type. Future types continue
upward from the highest assigned tag.

Small Church discriminants remain correct for error kinds, host-operation
codes, argument positions, and similar tiny fixed metadata. Every ordinary
numeric value is a Rat backed by private binary digit lists.

## R. Absolute purity extends verbatim to the new types

Every new object-language value and every computation involving private Nat,
private Int, public Rat, Unit, Byte, Option, or Map must consist, after macro
expansion, only of variables, one-argument lambda abstraction, and function
application. This governs representations, constructors, normalization,
arithmetic, comparison, powers, conversions between object-language types,
type and value checks, error decisions, Option selection, and every Map
operation.

Racket must not calculate or decide an AttaLambda program's result. In
particular:

- Rat and Int operations may not use Racket arithmetic.
- Map may not use a Racket hash table, association list, dictionary, or any
  other host collection, and may not use Racket equality.
- No new type may use Racket conditionals, pattern matching, equality,
  loops, mutation, exceptions, or data access for object-language
  computation.

## S. Existing seams keep their exact purpose

The classified seams do not widen:

- macros may mechanically expand source — including exact integer and
  fraction literals — into pure unary lambda terms;
- the deterministic codec may translate validated values across the
  Racket/AttaLambda boundary (extended only by the exact conversions the
  approved boundary work requires, such as exact numbers and external
  bytes), but may not perform object-language arithmetic or decide
  object-language results;
- the single host bridge performs only its explicitly approved external
  effects and conversions at its existing narrow boundary;
- readers, tests, and tooling may observe or verify values but may not
  enter a production computation path.

The purity checker and structural boundary gates must classify and scan
every new production module under these same rules, and the repository must
fail if a public or production typed Nat surface is reintroduced after the
public switch.

---

# Explicit Exit Amendment (2026-09-05)

This amendment supplements the main specification's Explicit Exit Amendment.
It overrides earlier sections of this document only to permit explicit
process termination through the existing sole host boundary. No other purity
rule or classified module role is relaxed.

Exit argument typing, exact Rat 0/1 validation, Error construction and
propagation, request construction, and the decision to call exit are all
object-language computation. After macro expansion they must contain only
variables, unary lambda abstraction, and application. The pure wrapper may
apply only its injected unary host argument for the external effect.

Only `runtime/host.rkt` may carry out program-requested process exit. The
codec remains a deterministic conversion exception and may not terminate
processes or decide whether a program succeeded. Host defensive validation
only checks the decoded canonical status; it never chooses a status from an
Error, Result, or arbitrary final lambda value. Runner-native exit remains
limited to launcher/source/scaffolding failures. Native exit is forbidden
in pure effects, codec, readers, and other production modules.

HTTP delimiter detection, suffix tracking, counting, accumulation, reversal,
and parsing remain pure unary lambda computation under the existing rules.
Neither the HTTP change nor explicit exit permits native Racket arithmetic,
conditionals, strings, buffers, collections, or mutation in object-language
computation. Both architectural checkers must enforce these boundaries.

---

# Public API and List Library Amendment (2026-09-06)

This amendment applies the existing absolute-purity rules to the approved
public API and List update. It supersedes earlier syntax examples only to
permit mechanical Char literal expansion; no computational exception widens.

Every new List algorithm, callback application, predicate-result check,
Error construction/propagation, Option result, count/index calculation,
range/repetition, and flattening type-tag decision is object-language
computation. After expansion it consists only of variables, unary lambdas,
and application. Use existing tagged values, Michaelson Lists, fixed-point
recursion, and private binary arithmetic. No Racket collection algorithms,
arithmetic, conditionals, equality, mutation, or host values may determine
these results. The closed type-tag table and generalized checker stay intact.

Reuse `raw-append`, `raw-reverse`, `raw-map`, and `raw-filter` where their raw
contracts fit, with strict public adapters for the new contracts. Preserve
existing raw behavior and callers. New raw algorithms remain raw; strict
typing belongs at their typed boundary. Left-to-right reduce requires its
specified accumulator behavior, not renaming the existing right fold.

Public renaming consists of module export renaming and mechanical updates to
lambda-encoded diagnostic names. It adds no executable compatibility wrappers
or public aliases. Char literals use the existing reader and Char emitter:
host character inspection at expansion time may validate the ASCII literal
and mechanically emit its canonical binary representation. No host Char,
Unicode runtime representation, parser, or new runtime helper is introduced.

All existing boundary classifications remain: codec performs deterministic
conversion; the sole host owns its ten approved effects; readers only
observe; tests/tooling cannot enter production dependencies. Source inventory
and expanded-purity checks cover every new production module. Do not weaken
those gates. Host-side edits remain simple explicit export entries, literal
checks, and necessary test/checker updates. No new dependency, registry,
dispatcher, callback/type framework, or unrelated feature is authorized.

---

# Recursive Definitions Amendment (2026-09-07)

Top-level names are module scaffolding only. No cycle among object-language
top-level bindings may provide computational recursion. Public `def` gives
an acyclic module name to a lambda term; it cannot recursively depend on
itself directly or indirectly. Acyclic forward references remain permitted.

Public `(rec name argument ... = body)` is mechanical syntax over the
existing private `core/fix.rkt` fixed-point term. It creates an acyclic
top-level binding whose recursive name is lambda-bound inside that term;
every declared argument introduces another unary lambda. Zero arguments
are allowed. `raw-fix` remains private. `rec` supports self recursion only,
not mutual module-binding cycles. Lexical shadowing follows the existing
argument, `lambda`, and `let` rules.

The public language must reject cyclic module dependencies at expansion
time. The production purity checker must independently reject cycles among
expanded same-module phase-0 bindings using binding identity; lambda-bound
self-application and imported references must not be mistaken for such
cycles. This strengthens Sections E and K without changing representations,
typing, evaluation, host capabilities, or any other purity rule.
