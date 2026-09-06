# Architecture

AttaLambda keeps ordinary production computation inside pure untyped lambda
calculus. The three documents in
[`docs/specifications/`](docs/specifications/README.md) define the language;
this file explains how the current implementation is arranged.

Operation spellings below describe the public language unless an internal
`raw-*` or `typed-*` binding is named. The facade exposes lowercase callable
names through explicit export renaming; core implementation exports may retain
their earlier names. This changes neither the operations nor their imports.

## Computational boundary

After mechanical expansion, object-language computation contains only:

1. variables;
2. unary `lambda`;
3. application.

This rule covers `core/`, the request and HTTP computation in `effects/`, and
the terms emitted by the frontend. Multiple arguments are nested unary
lambdas, so partial application is ordinary application.

Racket provides modules, lazy evaluation, mechanical expansion, tests, and
tooling. Two runtime files have narrower roles:

- [`runtime/codec.rkt`](runtime/codec.rkt) converts between validated lambda
  representations and private Racket bytes, integers, lists, and exact
  rationals. It performs no external effect and owns no mutable state.
- [`runtime/host.rkt`](runtime/host.rkt) alone defines `host`. It may perform
  the approved standard-output, file, blocking TCP, and explicit process-exit
  operations and own the TCP handle registry.

Only `runtime/host.rkt` performs the approved native effects, only the language
facade imports that host, and only the host imports the codec. Readers can
observe completed values for people and tests, but production never depends
on them.

## Where to start

Read only the row for the work you are doing:

| Task | Start here | What follows |
| --- | --- | --- |
| Pure value or algorithm | the relevant file in [`core/`](core) | raw dependencies below it, then its strict wrapper |
| Effect request or HTTP behavior | the relevant file in [`effects/`](effects) | `protocol.rkt` for request/Error data; no runtime import |
| Native effect behavior | `dispatch-request` in [`runtime/host.rkt`](runtime/host.rkt) | one local decoder path and one `perform-*` function |
| Representation conversion | the matching exported function in [`runtime/codec.rkt`](runtime/codec.rkt) | raw constructors/accessors imported from `core/` |
| Source syntax or public exports | [`lang/expander.rkt`](lang/expander.rkt) | [`lang/reader.rkt`](lang/reader.rkt) and [`macros/`](macros) only as needed |
| Command-line launch | `main` in [`runner/attalambda.rkt`](runner/attalambda.rkt) | `validate-source`, then `run-source` |
| Human-readable observation | the matching file in [`readers/`](readers) | one-way conversion only |
| Structural enforcement | [`tooling/check-purity.rkt`](tooling/check-purity.rkt) and [`tooling/check-boundaries.rkt`](tooling/check-boundaries.rkt) | focused rejection fixtures in `tests/` |

Dependencies point toward the pure center:

```text
macros <- core
core <- effects <- lang
core <- runtime/codec <- runtime/host <- lang
effects/protocol <- runtime/host
```

The diagram shows module dependency, not authority. `effects/` receives the
host as an ordinary unary argument; it never imports `runtime/`. The language
facade is the single place that imports the real host and injects it into the
ten public effect wrappers.

## One host request

For a call such as `write-file`:

1. `lang/expander.rkt` exposes the wrapper already bound to the one real
   `host` value.
2. `effects/files.rkt` checks the String path and proper `List Byte` payload
   using lambda computation, then constructs a proper List request.
3. The `host` value built by `make-host-bridge` in `effects/protocol.rkt`
   applies its strict dispatcher only after pure request validation succeeds.
4. `dispatch-request` in `runtime/host.rkt` decodes the operation and arguments
   through `runtime/codec.rkt`, then calls `perform-write-file`.
5. The performer does the replacement write and returns `Ok(UNIT)` through the
   codec. Expected operating-system failure becomes `Result Err`; a malformed
   direct request becomes a bare contract `Error`.

The other eight returning operations use the same route. Explicit exit uses
the same request boundary but ends at `perform-exit`, without returning a
Result. `runtime/host.rkt` keeps decoding next to each route and keeps resource
acquisition, registration, cleanup, and failure mapping in the corresponding
`perform-*` helpers. The
exact request shapes, bounds, results, failure codes, byte rules, and lifecycle
contract live once in
[`docs/design/host-boundary.md`](docs/design/host-boundary.md).

For `(exit status)`, the pure wrapper in `effects/exit.rkt` uses the generalized
checker and raw Rat equality to accept only 0 or 1. Wrong types return
TypeMismatch, other Rats return InvalidCount, and an incoming Error bubbles;
none calls the host. The public `exit` name is a renamed private
`language-exit` binding, with the real host injected once. The host defensively
decodes a canonical whole Rat in range 0..1 and terminates with that exact
status, without printing or returning `Ok UNIT`. Fake hosts may return normal
values for tests. Pure code decides whether an Error or Result Err is fatal;
neither the host nor runner derives a status from an arbitrary final value.
Without explicit exit, normal completion remains status 0. Unselected exit
branches stay lazy; performed exit prevents later effects.

## Incremental HTTP request reading

`effects/http-server.rkt` keeps reversed accumulated characters, a running
private binary Nat count, and at most three preceding characters. Each read
converts, counts, and reverses only the new chunk, then places its reverse
before the old accumulation without walking the old prefix. The running count
enforces the unchanged 8192-byte cap before parsing.

`raw-scan-http-header-end` in `effects/http.rkt` looks for `CR LF CR LF` in only
that suffix plus the new chunk. Incomplete nonempty reads do not invoke the
full parser. At completion or EOF, the server reconstructs once and invokes
the existing semantic parser once; every byte of the completing chunk remains
present, preserving trailing-data rejection. All of this is pure lambda
computation. Grammar, errors, cleanup, and blocking reads are unchanged. The
server still serves one connection at a time, with no timeout or nonblocking
guarantee.

## Frontend, runner, and observation

[`lang/reader.rkt`](lang/reader.rkt) delegates Lisp reading to
`syntax/module-reader`. [`lang/expander.rkt`](lang/expander.rkt) owns the public
surface. Its application transformer curries source calls, its `lambda`
transformer permits one parameter, and its datum transformer turns only exact
Rat and String literals into canonical lambda terms. The two files in
[`macros/`](macros) provide the smaller expansion machinery used by production
modules. Their different lexical contexts are deliberate.

[`runner/attalambda.rkt`](runner/attalambda.rkt) is process scaffolding. It
implements `attalambda FILE.attl`, `--help`, and `--version`; validates the
source name, path policy, regular-file status, exact first line, and UTF-8; and
loads the source once. It exports nothing, imports no project module, does not
inspect a completed lambda value, and reports only fixed sanitized
diagnostics. Its native exit calls remain limited to launcher, source-loading,
and scaffolding failures; program-requested exit belongs only to the host.

Each file in [`readers/`](readers) turns one completed representation into a
Racket value or display string. Readers may force and inspect values, but they
perform no external effect, own no registry, and never enter a production
dependency path.

## Representation contracts

### Tiny discriminants

The runtime type tags use Church numerals:

| Tag | Type |
| ---: | --- |
| 0 | Error |
| 1 | Bool |
| 2 | List |
| 3 | retired (was Nat; never reassigned) |
| 4 | Result |
| 5 | Char |
| 6 | String |
| 7 | Rat |
| 8 | Unit |
| 9 | Byte |
| 10 | Option |
| 11 | Map |

Tags are closed discriminants, not public arithmetic values. Structured Error
kinds and argument positions also reuse tiny Church values as explicitly
permitted metadata. Ordinary numeric computation always uses Rat, backed by
private binary Nat machinery.

### Objects

A runtime-typed object carries a tag and payload using lambda-encoded
structure. The representation must remain entirely inside the calculus.

### Booleans and conditional

`TRUE` and `FALSE` are Bool-tagged objects containing `raw-true` and
`raw-false`. `typed-not`, `typed-and`, `typed-or`, and `typed-xor` use the
generalized checker with List signatures, unwrap their Bool inputs, run the
existing raw operations, and wrap the raw result as Bool. The language facade
exports them as `not`, `and`, `or`, and `xor`; the core module retains its
implementation exports.

`typed-if` validates only its tagged Bool condition because both branches are
intentionally polymorphic. A valid condition unwraps to the raw selector and
chooses without forcing the other branch. A wrong condition or incoming Error
returns two unary ignoring continuations before exposing the failure, so the
conditional retains its full curried application shape. The generalized
monomorphic checker remains unchanged, as the specification allows.

### Lists

Lists use an explicit Michaelson-style representation. A nonempty List is a
List-tagged object whose payload pairs a head with another List object. `NIL`
is itself List-tagged; its payload contains the canonical empty-List Error in
both positions, so it is neither false nor numeric zero. That Error's empty
frame List is the same `NIL`; `raw-fix` ties this finite lazy graph without a
host reference or module cycle. `typed-cons` is the only strict constructor
and accepts only a List tail; it validates that tail with the shared
`raw-check-argument` step described under Runtime typing. NIL recognition checks the tail's Error tag in
O(1), so an Error head does not make a nonempty List look empty.

`typed-head`, `typed-tail`, and `typed-is-nil` use the generalized checker with
a one-element List signature. Wrong concrete types create structured
TypeMismatch roots, while incoming Errors gain the current argument frame.
`typed-cons` is not built by the checker because its head is intentionally
polymorphic and therefore has no expected runtime tag for a signature entry.
Its polymorphic head preserves an incoming Error without inventing an expected
type; its List tail has ordinary framed propagation. `head` and `tail` on
`NIL` return the canonical EmptyList Error with a result frame naming the
operation. Deciding that requires reading the tail's tag, which `cons` has
already validated for every public List; a raw-built List pays one extra cell
step, and the second cell's contents are never forced.
`typed-is-nil` now wraps its O(1) raw predicate result as a tagged Bool. The raw
layer currently provides a right fold, append, reverse, map, and filter; the
fold callback receives the head followed by the folded tail.

`core/list-nat.rkt` adds raw length, take, and drop after binary Nat is
available. Length returns canonical raw Nat bits. Take and drop accept raw Nat
bits first and a List second; taking beyond the end returns the complete List,
while dropping beyond the end returns `NIL`. The strict wrappers now use the
generalized checker. `len` returns a tagged whole Rat; `take` and `drop` accept
a nonnegative whole Rat count and a List. They bubble incoming Errors and
preserve the one remaining application after a bad first argument.

`core/list-transform.rkt` adds public `append`, `reverse`, `map`, and
`filter` without changing the foundational raw algorithms. The structural
wrappers reconstruct canonical List inputs after checker unwrapping. Map
folds its lazy raw results to propagate an Error as the whole answer; filter
adapts its existing branch selector to validate Bool results and propagate
suffix Errors before retaining a node. A small pure predicate-result helper
uses the same checker and diagnostic convention as Map equality. There is no
new tag, callback registry, or host computation.

The transform module also implements `reduce` as a direct left accumulator
loop, receiving accumulator before element and stopping at callback Error.
`core/list-search.rkt` implements `any?`, `all?`, `find`, `find-index`, and
`contains?` through direct loops and the same predicate-result helper. Any and
contains share their identical Boolean traversal; supplied equality receives
the sought value before the element. Find returns Option; find-index counts
with private binary Nat and wraps a canonical whole Rat in Option. Each search
stops before another predicate call once its answer is determined.

`nth` extends the numeric List module by reusing drop after the same count
validation and returning Some or NONE. The search peer also supplies
`take-while` and `drop-while`: both stop predicate calls at the first false
answer, and drop returns the retained suffix directly. Take propagates a
later predicate Error before constructing an earlier output node.

### Natural numbers (private machinery)

Binary Nat values are private machinery since Milestone 4: no public Nat type
or tag exists, and the boundary gate scans against any reintroduced Nat
surface. Rat's numerator magnitude and denominator are normalized binary
digit lists in most-significant-bit first order. Zero has exactly one
representation, `[0]`; positive values have no leading zeroes. Each digit is
a raw lambda Boolean inside the same proper List structure used elsewhere.

`core/binary-nat.rkt` normalizes empty or all-zero internal inputs to `[0]` and
removes every unnecessary leading zero. It implements raw zero testing,
successor, addition, saturating subtraction, multiplication, equality, and all
four order comparisons directly on MSB-first digit Lists. Addition and
subtraction reverse their operands for carry and borrow propagation;
multiplication scans one operand with binary shift-and-add. Division performs
MSB-first binary long division: one traversal produces a raw pair holding
both quotient and remainder, `raw-nat-div` selects the quotient, and
`raw-nat-rem` selects the remainder. The greatest common divisor iterates
Euclid's algorithm on that remainder, and the least common multiple divides
the product by the greatest common divisor behind explicit zero guards, so
no zero divisor ever reaches the division loop. The raw division contract
still requires a nonzero divisor; the strict layer owns the zero policy.
Parity reads the final bit of the normalized value, halving drops it, and
exponentiation recurses on the halved exponent with one squaring per bit —
never one multiplication per exponent decrement.
None of these algorithms converts through Church numerals or host numbers.
Since Step 32.1 the module contains only normalized binary-list values and
raw operations: it requires exactly the macro layer, the fixed-point helper,
raw Lists, raw logic, and raw pairs, exports only `raw-` bindings, and
depends on no tag, object, typed function, effect, codec, or host machinery.

`core/int.rkt` is the private signed layer above raw binary Nat: an Int is a
raw untagged pair of a raw Boolean sign (true means nonnegative) and a
normalized magnitude. Every supported construction routes through
`raw-make-int`, which turns any attempted negative zero into positive zero,
so Int zero has exactly one representation. Same-sign addition adds
magnitudes; mixed-sign addition subtracts the smaller magnitude from the
larger and keeps the larger operand's sign; subtraction adds the negation;
multiplication compares signs and multiplies magnitudes; ordering puts any
negative below any nonnegative and reverses the magnitude comparison between
two negatives; parity reads the magnitude. Every result routes through the
canonical constructor, so operations whose mathematical result is zero
produce positive zero. Int exists solely as Rat's
numerator machinery: it has no type tag, no typed layer, no literal, no
reader in any production path, and no language export. `readers/int.rkt`
observes a completed Int as a signed host integer for tests and humans only.

`core/rat.rkt` holds private exact rationals: a raw untagged pair of an Int
numerator and a positive normalized binary Nat denominator. `raw-make-rat`
reduces both parts by their greatest common divisor and forces every zero to
positive `0/1`, so equal rational values have one stored representation and
the sign lives only in the numerator. A zero denominator is an internal
invariant failure, never a value: as with raw division, the raw
constructor's contract requires a nonzero denominator, and every supported
entry path guards zero before construction. Addition cross-multiplies
against the opposite denominator, subtraction adds the negation,
multiplication multiplies parts, ordering cross-multiplies signed
numerators, equality compares canonical parts directly, wholeness is a
denominator-one check, and floor divides magnitude by denominator and
decrements for negative fractions with a nonzero remainder; every Rat
result routes back through the canonical constructor. Reciprocal and
division guard a zero operand and return raw Result values: the expected
failure is the canonical DivideByZero Error inside Err, never an exception
or a sentinel. Exponentiation accepts only whole Rat exponents — a
fractional exponent is the expected NonWholeExponent failure (error kind 14,
numbered after the host-protocol and HTTP kinds)
even when that power would happen to be rational — computes magnitudes with
the private squaring exponentiation, takes reciprocals for negative
exponents, keeps `0^0 = 1`, and turns zero raised to a negative exponent
into DivideByZero. `readers/rat.rkt`
observes a completed Rat as an exact host rational for tests and humans
only.

`core/typed-rat.rkt` is the strict tagged Rat layer (tag 7, church-seven)
over the private rationals, built entirely on the unchanged generalized
exact-tag checker: `succ`, `add`, `sub`, `mult`, `neg`, `abs`, and `floor`
wrap Rat returns; the comparisons and the zero/whole/nonnegative-whole
checks wrap Bool returns; `div`, `exp`, and `recip` keep their
already-typed Result, re-wrapping a successful raw payload as a tagged Rat.
Since the Step 35.5 public switch this is the language's entire number
surface: `core/typed-nat.rkt` is deleted, the Nat tag (3) is permanently
retired, the constants `ZERO` through `TEN` are replaced by exact literals,
and the boundary gate fails if any production source reintroduces a retired
Nat spelling. Unary operations use one Rat signature entry, and binary
operations use two, so partial application, wrong-type failures,
incoming-Error bubbling, and remaining-arity absorption all behave exactly
as with every other strict typed function; every boundary records its
canonical function-name String, argument position, and expected Rat type
when it creates or propagates an Error.

### Errors and results

Every Error is an Error-tagged object whose payload pairs one immutable root
with a proper List of propagation frames. Root kinds are the small Church
discriminants TypeMismatch, EmptyList, InvalidNat, DivideByZero, InvalidChar,
InvalidString for a List that violates the String element invariant,
WrongResultVariant for unwrapping the variant a Result does not hold,
NonWholeExponent for exp with a fractional exponent, InvalidCount for a
count-valued Rat that is not a nonnegative whole within bounds, and
InvalidByte for a Byte construction outside 0 through 255; the host protocol
and HTTP layers extend the same kind space with their own discriminants. A
TypeMismatch root additionally stores its argument position,
expected runtime type, and actual runtime type. The other current roots need
no extra details.

A frame contains a canonical function-name String, argument position, and
expected runtime type for the current boundary. `raw-bubble-error` reuses the
exact root and prepends one frame, so the frame List is newest-first and root
metadata never changes. Fresh TypeMismatch roots receive the same named frame
as propagated Errors.

A strict operation whose valid arguments still make its algorithm fail —
`head` or `tail` on `NIL`, `make-char` above 255, `make-string` with a
non-Char element, `string-head` or `string-tail` on the empty String, and
`unwrap-ok` or `unwrap-err` on the wrong variant — returns the canonical root
with one *result frame*: the function name, argument position `church-zero`
(argument positions start at one, so zero unambiguously means "at the
result"), and the Error type of the value produced. `raw-add-result-frame`
builds it, and each failing raw algorithm attaches it explicitly, so an Error
that a strict operation merely yields as ordinary data — a stored List element
or a `Result` payload — is returned unchanged. The polymorphic `typed-cons`
head and `make-ok` likewise preserve an incoming Error without adding a frame
because neither position has an expected runtime type to record.

`readers/error.rkt` reverses the stored frame List for causal display, renders
the oldest mismatch frame with its actual type, prints a result frame as
`NAME(result)`, and then prints each later boundary as an arrow. Function names remain structured String values inside
the Error; only the reader flattens them to diagnostic text. Language-level
failures never use host exceptions or strings.

`core/result.rkt` represents Result as a Result-tagged object whose payload
pairs a raw Boolean discriminator with a payload. True identifies Ok; false
identifies Err. `make-ok` accepts a polymorphic value but preserves an incoming
Error instead of hiding it. `make-err` is the intentional exception to normal
Error bubbling: it requires an Error and stores that Error as data. A wrong
non-Error argument remains a TypeMismatch Error.

`is-ok`, `is-err`, `unwrap-ok`, and `unwrap-err` strictly require Result via
the generalized checker. The predicates return tagged Bool values. `unwrap-ok`
returns the payload of an Ok and `unwrap-err` the payload of an Err, each
without automatically propagating it; asking for the variant a Result does not
hold is a contract failure and returns the WrongResultVariant Error with a
result frame. This is the semantic boundary: a Result Err is an ordinary valid
Result until a caller explicitly unwraps and uses its Error payload.

### Characters and strings

`core/chars.rkt` represents Char as a Char-tagged object containing normalized
raw Nat bits rather than a nested Nat object. Its pure upper bound is computed
as `(16 × 16) − 1` with raw binary operations. `make-char` uses the generalized
checker for its Rat argument, requires a nonnegative whole value, returns Char
for values 0 through 255, and returns the canonical InvalidChar Error above
that range.

`char-eq`, `char-lt`, `char-lte`, `char-gt`, and `char-gte` use two-Char
signatures through the same checker. They reuse raw binary Nat comparisons on
unwrapped Char payloads and return tagged Bool values.

The module defines every required upper- and lowercase letter, decimal digit,
control constant, and named punctuation constant as a genuine lambda-built
Char. Constants are derived from binary Nat values and unary successor chains;
core computation contains no host numbers or character literals. These
constants remain internal. Public ASCII Char literals use the existing reader
and `language-char-expression` during mechanical expansion; the facade
rejects non-ASCII Char literals and exports no named Char constants.

`readers/char.rkt` converts a completed Char payload to a host integer or
display string. It renders TAB, LF, CR, and printable ASCII directly and uses
`char:<integer>` for unsupported values. This observation is one-way and never
feeds host characters back into production computation.

`core/strings.rkt` represents String as a String-tagged object whose payload is
the canonical List object containing typed Char elements. `EMPTY-STRING` uses
`NIL`. `make-string` strictly requires a List and recursively checks every
element's Char tag using lambda computation; a well-typed List containing any
non-Char element returns the canonical InvalidString Error.

`string-empty?`, `string-length`, `string-eq`, `string-append`,
`string-head`, `string-tail`, `string-prefix?`, and `string-contains?` all use
the generalized checker. The raw algorithms traverse List structure and
compare Char binary payloads directly. Length reuses the canonical raw binary
List counter and returns a whole Rat. Head returns Char; tail returns String; either
partial operation returns EmptyList Error on the empty String. Prefix and
contains take the searched String first and the candidate prefix or substring
second; an empty candidate succeeds.

`readers/string.rkt` traverses the completed Char List and joins the Char
reader's host output. No production module imports it, and no host string
operation participates in equality, append, prefix, or substring search.

## Runtime typing

`make-typed-function` accepts, in order, a raw curried function, a canonical
function-name String, an AttaLambda List of expected type tags, and one
unary return policy. It constructs strict typed functions of arbitrary arity
by:

- validating one argument per application;
- bubbling an existing Error with the current function name, expected type,
  and Church-encoded argument position;
- creating and framing a structured Error for a wrong runtime type;
- unwrapping a valid argument and partially applying the raw function;
- preserving remaining arity with one unary absorbing continuation per
  unconsumed signature entry after an early failure; and
- applying `raw-wrap-return` for a raw result or `raw-keep-return` for a result
  that is already typed.

The empty signature also supports a zero-argument raw value. No host arity
counting or arity-specific checker variant exists. The purity gate explicitly
rejects numbered checker names.

One-argument validation lives in a single shared step, `raw-check-argument`:
given a function name, argument position, expected type, a failure
continuation, and a success continuation, it bubbles an incoming Error,
frames a fresh TypeMismatch, or passes a valid argument on. The checker uses
it with the remaining-arity absorber as its failure continuation; `typed-if`
(the specified custom polymorphic conditional) uses it with a two-branch
absorber and the raw selector as its success continuation; `typed-cons` uses
it for its List tail. The polymorphic positions — the `typed-cons` head, `typed-make-ok`, and
`typed-make-err`, which intentionally accepts Error as data — have no expected
tag and therefore test for the Error tag directly rather than through this
step.

## Naming

Internal names state their semantic layer:

- `raw-*` for raw representations and algorithms;
- `typed-*` for strict runtime-typed operations.

Public exports use canonical language vocabulary. Underscore prefixes must not
exist solely to avoid Racket bindings. Host collisions are handled at module
boundaries through renaming and selective export.

## Repository layout

| Path | Responsibility |
| --- | --- |
| [`macros/`](macros) | Mechanical expansion used by production modules. |
| [`core/`](core) | Pure representations, raw algorithms, and strict typed operations. |
| [`effects/`](effects) | Pure requests, wrappers, HTTP messages, routing, and sequential serving. |
| [`runtime/`](runtime) | Deterministic conversion and the sole privileged host. |
| [`lang/`](lang) | The public `#lang attalambda` reader and expander. |
| [`runner/`](runner) | The non-exporting command-line loader. |
| [`readers/`](readers) | One-way observation outside production computation. |
| [`examples/`](examples) | Programs using only the public language. |
| [`tests/`](tests) | Behavioral and adversarial verification. |
| [`tooling/`](tooling) | Structural gates and distribution build/consumer scripts. |
| [`distribution/`](distribution) | Text and notices placed in standalone archives. |

`VERSION` is the single product-version source. `info.rkt` contains the Racket
package metadata. New source locations fail the boundary inventory until they
receive an explicit class.

## Verification boundary

`tooling/check-purity.rkt` expands every `core/` and `effects/` module and
accepts only the trusted shapes of unary lambda and unary application. It also
checks production imports, exports, names, and module forms. The macro shell is
the trusted expansion base.

`tooling/check-boundaries.rkt` inventories every Racket and `.attl` source and
enforces the roles described above: one host producer, one production codec
importer, closed frontend and runner surfaces, effect-free readers, no upward
production dependency, and no unknown source location. Its rules include
closed imports and vocabularies so renamed or implicit host capabilities do not
slip through a shorter blacklist.

Focused suites exercise representations, strict typing, errors, laziness,
request precedence, codec canonicality, native failure mapping, TCP cleanup,
frontend hygiene, runner diagnostics, and hostile boundary mutations. Real
file tests use temporary directories and real network tests use ephemeral
loopback ports. `./run-all-tests.sh` runs every behavioral suite followed by
both structural gates. [`docs/ACCEPTANCE.md`](docs/ACCEPTANCE.md) maps the
released promises to their evidence.
