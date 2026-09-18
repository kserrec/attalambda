# AttaLambda — Optional Static Inference and Checking

**Status:** Implementation specification; no AttaLambda implementation or runtime test execution is claimed by this document.  
**Prepared:** 2026-09-17.  
**Revision:** 3 — semantic consistency, implementation-order, and adversarial acceptance review.  
**Repository:** `kserrec/attalambda`.  
**Inspected branch/revision:** `main` at `f6938b286329532230be210de0eaaa398286d38a`.  
**Default delivery endpoint:** A verified, unmerged, unpublished implementation candidate.  
**Proposed repository location:** `docs/optional-static-checking-spec.md`.

This is the complete replacement for the earlier unimplemented specifications, not an addendum to apply alongside them. The feature and delivery boundary remain one optional standalone-file checker and one verified local candidate. Revision 3 clarifies source-level `let`/`rec`, partial-result handling, contract identity, complete source accounting, and output/cancellation behavior; splits oversized implementation steps; and adds concrete counterexamples at the gates where they matter. It contains 39 focused steps across six phases, 26 acceptance requirements, and 22 counterexample fixtures; those counts describe organization, not evidence of correctness.

**One deliberate verdict correction:** a finite type contradiction at a heterogeneous List or branch join is now **FAIL under V1's homogeneous/common-result rules**, not a special PARTIAL escape. The same constraints apply through `cons`, `if`, their aliases, and higher-order calls. This removes the earlier ambiguity between “ordinary application conflict” and “unsupported heterogeneous join”; it does not prohibit those programs in normal AttaLambda. PARTIAL remains reserved for the explicit unproved categories in Section 5.8.

The remote `main` head was rechecked during this revision and remains `f6938b286329532230be210de0eaaa398286d38a`. Targeted source was re-read for first-class conditionals, Option elimination, Map callbacks, session preparation, and file I/O failure paths. No AttaLambda implementation, local repository baseline, Racket probe, test suite, or standalone build was run in this review. The source-level design below still requires its early executable probes. The supplied skill's emphasis is independently verifiable execution and recovery, not first-attempt perfection.

## 1. Objective and fixed boundaries

Add an optional command that analyzes an existing AttaLambda source file, infers types without annotations, checks every source definition and expression it can cover, and explains precisely what remains unproved.

```sh
attalambda --check program.attl
```

Normal execution remains unchanged:

```sh
attalambda program.attl
```

The initial implementation must provide useful whole-file checking, including ordinary `rec` definitions, higher-order functions, inferred reusable function types, source-located diagnostics, and honest coverage reporting. It must not obtain a reassuring result by silently treating unknown code as safe.

There are **no new source forms, annotation syntax, runtime tags, casts, or runtime type-checking changes**. Object-language computation still lowers to the same untyped unary lambda terms. The checker is host-side tooling, not a new object-language primitive or a replacement evaluator.

This specification defines a supported typed subset, not a promise that most existing programs will receive a full pass immediately. In particular, the explicit Error/variant limits below can leave otherwise correct programs partial; the corpus audit measures actual coverage rather than guessing it.

This is a contained tooling subsystem, not a runtime redesign. Its inference kernel is relatively compact; the material work is integrating it with lexical binding, macro lowering, runtime contracts, diagnostics, and the packaged executable.

### 1.1 Decisions that reconcile the preceding design discussion

These are deliberate design decisions, not claims about existing behavior:

1. **Inference is not gated by annotations.** Check all source definitions, nested function bodies, and top-level expressions. A function needs no written type to be fully checked.
2. **Include basic rank-1 generalization in the initial implementation.** Earlier discussion deferred polymorphism. That would unnecessarily penalize ordinary identity functions and reusable helpers. Include ordinary `def`/`let` generalization and fresh instantiation now; do not include higher-rank inference, polymorphic recursion, recursive types, or System F syntax. This is a limited adjustment, not permission to build an advanced type system.
3. **Type source-level `rec`, not the expanded fixed-point term.** Recursive calls are monomorphic while checking their definition; the completed binding may subsequently be generalized.
4. **Do not conceal first-class Error values.** An operation that may return either a useful value or an Error cannot receive a success-only static result type and count as fully checked. Initially, operations needing unimplemented variant/range reasoning create explicit coverage gaps. Do not introduce a general union or effect system merely to increase coverage.
5. **Use one checking command.** Exit status `0` means a full pass. Partial analysis remains useful, but exits `2`. No separate `--full` flag is needed to prevent partial reports from silently permitting execution in a shell pipeline.
6. **Report definition and expression coverage, not annotation coverage.** A `def` can bind data rather than a function. The report must use that terminology accurately and name functions when discussing their bodies.

### 1.2 Scope of this implementation

Deliver standalone-file checking through the existing executable. Preserve the REPL, file execution, source notation, runtime representations, library algorithms, host capabilities, and existing platform commitments.

This milestone does not add a project/module system, user annotations, a REPL type command, automatic checking on normal execution, editor integration, persistent inference caches, JSON output, checked-code optimization, runtime-check removal, or a combined check-and-execute mode. These are delivery boundaries, not permanent prohibitions on later features.

The checker may reject or leave unproved a program that ordinary AttaLambda can run. That is an expected property of an optional type assignment system. It must explain the distinction rather than changing the program or weakening the runtime to accommodate its analysis.

### 1.3 Early usefulness check, without widening the type system

The main product risk is a correct but overly partial checker. Before completing the library inventory, exercise the real frontend and inference engine on a small representative set: reusable unannotated helpers, ordinary recursion, a definite mismatch, raw self-application, a correctly guarded Result unwrap, and a caller of an incomplete function. The supported examples must be established; documented limitations must remain visibly partial. Use the same implementation and tests that ship, not a throwaway second checker.

Inspect a few existing examples during preflight to identify these expectations; measure the complete corpus at final acceptance. Documented partial results are accepted V1 limitations, not instructions to add union types, predicate refinements, or an effect system. Unexpected failures on the required supported subset must be fixed before broadening the contract inventory. Report any remaining usefulness limitation explicitly at handoff rather than claiming that most existing programs fully pass.

## 2. Inspected baseline and execution prerequisites

### 2.1 Observed repository facts

The inspected head is a documentation commit following the 0.8.0 release. Its parent, `f309199baa170ba5b12ff6b18b60dc49c114a8a1`, is the recorded merged/build source for that release. Do not attribute the published archive to the later documentation head. The open-pull-request query returned no open PRs during planning. The future executor must recheck all of this before writing. [R1, R2]

The following are observed implementation facts, not proposed syntax:

| Responsibility | Existing implementation and consequence |
| --- | --- |
| Language authority | `AGENTS.md`, the three canonical specifications, and their scoped amendments govern the work. `PLAN.md` cannot override them. |
| Public source | Files use lowercase `.attl` and begin with `#lang attalambda`. Definitions use `def` and `rec`; arithmetic uses `add`, `mult`, etc. The public number type is `Rat`. |
| Expansion | `lang/expander.rkt` already implements currying, lexical dependency checks, acyclic forward references, `rec`, and the four small Lisp sugars. |
| Recursion | `rec` lowers through `language-fix` to the existing private `raw-fix`. Direct or mutually recursive module bindings remain forbidden. |
| Source input | `runner/source-file.rkt` validates a source path and reads its body once. `runner/source-reader.rkt` produces source-located syntax objects with reader extensions disabled. |
| Execution boundary | `runner/attalambda.rkt` executes files using `dynamic-require`. `runner/session.rkt`'s `prepare-entry` expands **and then evaluates/instantiates** a module. Neither is a check-only backend. |
| Runtime typing | The existing generalized curried checker, tagged data, Error propagation, and Error-absorbing continuations are language behavior and remain unchanged. |
| Arithmetic failure | `div`, `exp`, and `recip` return Result values. They do not simply return `Rat`. |
| Result failure | Err contains an Error. `unwrap-ok` can return an ordinary Error for the wrong variant; Error is not an exception or a bottom type. |
| External input | `read-file` returns a Result containing a List of Byte; `read-line` returns a Result containing an Option of String. |
| Rendering | Raw functions, including functions within data, have unspecified rendering behavior. A universal “every value is printable” signature would be false. |
| Structural enforcement | `tooling/check-boundaries.rkt` inventories source locations and pins important imports, exports, definitions, and vocabularies. New tooling and launcher changes need scoped gate updates. |
| Delivery | The existing builder embeds the runner and recursively stages Racket files beneath `runner/`. Linux x86-64 is the public binary commitment. Existing other-platform CI must not be regressed or advertised as a new release. |

These facts are grounded in the source paths in Section 11, particularly [R3–R13].

### 2.2 Inspection limits

Planning and revision review used remote source inspection and the supplied Markdown documents. Revision 3 also performed document-structure checks, which are not AttaLambda tests. No local checkout, supported Racket runtime, implementation probe, test run, build, or independent code review was performed. Local modifications and unpushed branches are therefore unknown.

The source paths inspected directly cover the governing rules and specification index, the absolute-purity addendum, active-plan opening, language expander, runner input/execution paths, representative type/Result/effect implementations, public API, expansion tests, structural boundary machinery, complete-suite script, CI configuration, and Linux builder. The entire standard library has **not** been audited for static signatures during planning. Auditing each signature against its actual implementation is explicit implementation work below.

Recorded historical test counts in the repository are not a fresh baseline. The executor must establish its own baseline and retain the exact revision, environment, commands, and results.

### 2.3 Required environment

Use the repository's supported full **Racket CS 9.3** environment and its existing reviewed dependency corrections. Read the preparation scripts before running them. Apply corrections only to an agent-owned installation or disposable container, never the owner's normal installation. Preserve the current dependency versions; this feature does not require a new package. [R10, R11]

The exact known full-suite command is:

```sh
./run-all-tests.sh
```

The existing script refreshes test bytecode with `raco make`, runs each `*-test.rkt`, and executes both structural gates. For a focused test, refresh it before execution:

```sh
raco make tests/static-types-test.rkt
raco test tests/static-types-test.rkt
```

`tests/static-types-test.rkt` is a proposed new test path, not an existing baseline file. Equivalent private test filenames may be chosen, but record the actual commands in the active plan.

The separately runnable structural gates are:

```sh
racket tooling/check-purity.rkt
racket tooling/check-boundaries.rkt
```

Before substantial implementation, confirm access to a Linux x86-64 clean-build and isolated consumer environment. The existing commands are:

```sh
./tooling/build-linux-distribution.sh "$CANDIDATE_DIR"
./tooling/test-linux-distribution.sh "$CANDIDATE_DIR"
```

`CANDIDATE_DIR` must be a newly allocated agent-owned directory outside the checkout. Read both scripts first. The builder requires the approved runtime and, for final evidence, a clean committed source tree. Do not use `--allow-dirty` for final-candidate evidence. The existing consumer must end with `consumer_acceptance=passed`; extend its acceptance surface for checking rather than substituting source-only tests. [R11, R12]

## 3. User-visible contract

### 3.1 Invocation and process results

Accept exactly the new argument form:

```sh
attalambda --check FILE.attl
```

Keep all existing invocation forms and their behavior. Do not require a terminal, access shell history, read program answers, or start a REPL for checking.

| Situation | Report/result | Exit status |
| --- | --- | ---: |
| Every required source obligation is established | `Static type check: FULL PASS` | 0 |
| At least one supported typing constraint conflicts | `Static type check: FAIL` | 1 |
| No such conflict, but at least one obligation remains unproved | `Static type check: PARTIAL` | 2 |
| Invalid command arguments | Existing-style usage diagnostic | 64 |
| Invalid source declaration, encoding, reader syntax, unknown name, or forbidden definition cycle | Existing-style source diagnostic | 65 |
| Source unavailable or rejected by the existing path policy | Existing-style source diagnostic | 66 |
| Unexpected analyzer/launcher failure | Safe internal-failure diagnostic; never a partial/full pass | 70 |
| User interrupts analysis before its result is finalized | Stop, clean up owned resources, no completed analysis report | 130 |

A static FAIL means that the program does not satisfy the supported static rules. It is **not** a claim that execution must crash: an offending expression might be lazy or unselected, and the runtime may return an Error instead of crashing.

If a file contains both a concrete type conflict and an unproved region, FAIL wins, but list the unproved regions too. Malformed source prevents a meaningful whole-file coverage claim; do not turn a parse/expansion failure into “0% checked.”

Construct and validate the complete analysis result before formatting or emitting its human-readable report to stdout. There is no provisional FULL PASS, streamed success status, or success fallback in an exception handler. Usage, invalid/unavailable-source, interruption, and internal-failure diagnostics use stderr. Checking never emits program stdout. Use deterministic ordering and safe escaped spellings for source-controlled names and paths; no unsolicited terminal controls.

Successful process exit is the automation contract: return `0` only after a full analysis and successful report emission/flush. A report write/flush failure is operational failure (`70` when catchable), not a type conflict or partial analysis. Do not replay an emitted report in an exception handler. Distinguish source-read errors from checker/embedding errors instead of mapping every exception to “invalid source.” Tests inject internal failures through private test seams, never an environment variable or public CLI backdoor.

Cancellation during analysis returns `130`, performs owned-resource cleanup, and emits no completed analysis report. Cancellation or a broken pipe during report delivery may leave already-written report bytes; do not promise to retract output or make stdout and process exit atomic. Such an interrupted/failed delivery is not exit `0`. Do not disable breaks across an unbounded analysis or potentially blocking report write to manufacture atomicity. Abrupt uncatchable process termination is outside the cleanup guarantee.

### 3.2 A full-pass example

This is actual AttaLambda notation, with no proposed annotation forms:

```racket
#lang attalambda

(def double x = (add x x))

(rec factorial n =
  (if (is-zero n)
      1
      (mult n (factorial (sub n 1)))))

(stdout (rat-to-string (factorial (double 3))))
```

The report must contain the equivalent of these lines, with an additional expression-coverage line computed from the source:

```text
Static type check: FULL PASS
Scope: program.attl; all source definitions and expressions
Definitions: 2/2 fully checked (100.0%)
Unproved regions: 0
Type conflicts: 0

Inferred definitions:
  double    : Rat -> Rat
  factorial : Rat -> Rat

Trusted basis: built-in contracts, rec lowering, and host/codec contracts.
This does not prove termination or successful external operations.
```

Checking this file must not print `720`, write anything through the program's `stdout`, or execute factorial. Its type is inferred from the source constraints and contracts. A negative input could make factorial diverge; `Rat -> Rat` is not a proof of termination or of a nonnegative input.

### 3.3 A definite static mismatch

```racket
#lang attalambda
(def broken x = (add x "hello"))
```

The report identifies `broken`, the file, the offending argument's actual source line and column, and the relevant contract:

```text
Static type check: FAIL
program.attl:2:<column> [TYPE_CONFLICT] in broken
  add argument 2 expects Rat; this expression has type String.
```

The column above is explanatory, not a hard-coded expected diagnostic. Tests must assert the actual location produced from the fixture. Keep the current runner/Racket convention: one-based lines and zero-based columns; document that convention. Do not substitute the location of generated lambda code or the implementation of `add` for the user's argument.

### 3.4 Partial coverage is not a disguised pass

```racket
#lang attalambda
(def self-apply x = (x x))
(def double x = (add x x))
```

The checker still verifies `double`. It identifies the self-application in `self-apply` as outside the finite simple/rank-1 type representation supported here. Normal execution remains available.

```text
Static type check: PARTIAL
Definitions: 1/2 fully checked (50.0%)
Unproved regions: 1

program.attl:2:<column> [RECURSIVE_TYPE_REQUIRED] in self-apply
  The constraints require a type to contain itself.
  V1 does not support recursive types; ordinary AttaLambda is unchanged.
```

Every incomplete definition must have either a primary reason or a dependency path to one. A caller of `self-apply` is not fully checked merely because its own expected return type can be written down.

### 3.5 Exact meaning of FULL PASS

FULL PASS means:

> All definitions, function bodies, and top-level expressions in this input file satisfy the V1 static rules, with no unproved source obligations, relative to the explicitly listed trusted built-in, lowering, and boundary contracts.

It does not mean that the checker re-proved the implementation of the standard library, codec, host, Racket evaluator, or operating system. These are outside source-coverage denominators. It does not prove termination, resource availability, filesystem/network success, valid resource lifetimes, application correctness, or the absence of deliberately returned Error or Result Err values.

A function type describes permitted inputs and result shape **when a normal value is produced**, subject to the trusted contracts. It must not hide an additional normal return alternative such as Error. Suspension, divergence, native implementation failure, external effects, and successful process termination are not a theorem of totality or successful execution. In particular, a type-correct recursive term need not terminate.

A fully checked function's type is an input precondition, not a runtime guard added to its entry point. An unchecked future caller can still pass it another kind of value. Whole-file coverage concerns this source snapshot and its checked call sites, not every possible client, later REPL binding, or source edit.

The checker makes no claim that its implementation has been formally verified. Tests and reviews provide evidence; they do not justify claiming a machine-checked soundness theorem.

### 3.6 Coverage and type display

Use two exact counters:

- **Definitions:** fully checked `def`/`rec` bindings divided by all source `def`/`rec` bindings. Include data definitions and function aliases; do not misleadingly label every binding a function.
- **Expressions:** fully checked source expression nodes divided by all source expression nodes, as defined below. Include nested lambdas, unused functions, unselected branches, and top-level expressions.

A binding is fully checked only if its complete body and required user-defined dependencies are fully established. A derived type that still depends on a hole is a **conditional shape**, not a verified signature. Display it as conditional or omit it; never list it among fully inferred contracts.

Count source nodes before representation lowering: literals, identifier references, applications, explicit lambdas, `let`, `list`, and `cond` nodes plus their expression children. Count a multi-argument source application/lambda once at its root; generated unary applications/lambdas do not inflate the total. Declaration headers and binder occurrences are not expression references. `let` initializers and body count; `cond` conditions/results count, but its `else` marker does not. Generated `cons`, `NIL`, and `if` nodes do not count. The implicit lambdas of function-definition shorthand do not count as additional source expressions.

Pin these rules with tiny exact-count tests. For example, `(add 1 2)` contains four expression nodes: one application and three children. A source lambda adds its own node and its body nodes, not a node for a binding occurrence.

These percentages count discharged static obligations. They are not a probability that the program is correct, a percentage of executions that are safe, or test coverage.

Display counts and a percentage to one decimal place. For a zero denominator, show `n/a`, not a fabricated percentage. An empty valid module may pass vacuously but must explicitly say that it contains no definitions or expressions. Full-pass selection uses exact proof state and counts, never a rounded percentage.

List fully inferred named bindings in source order. Print arrow types right-associatively and parenthesize arrow parameters. Print generalized variables consistently, e.g.:

```text
identity : forall a. a -> a
apply    : forall a b. (a -> b) -> a -> b
```

A quantified type variable is not an unchecked hole. Annotation coverage is not displayed: this version has no annotation syntax.

**Source-accounting invariant:** register source expression IDs before desugaring. Every registered expression receives exactly one final classification, and every declaration receives a final state. A normalized node may map back to an existing source ID, but generated nodes cannot create additional denominator entries. A missing/duplicate ID, unresolved binding token, omitted source form, pending contract entry, or unsolved unification work item is an analyzer defect (`70`), not a coverage gap that may be ignored. A legitimate unused generalized variable is already solved parametrically; it is not a pending constraint.

For expression coverage, a node is established only when its local typing obligation, counted children, and referenced user dependencies are established. A conflict/gap at a parent need not invalidate independent literals or trusted references beneath it; never count a node using constraints discarded during failure recovery. Thus an isolated `(add 1 "bad")` has three established child nodes out of four expressions, while its application fails. Pin additional exact counts for complete `(list 1 2)`, complete `(let x = 1 x)`, a nested lambda, and declaration shorthand. Definition counts remain independent of the number of generated curried lambdas.

Reports must name each incomplete definition and its primary reason or one deterministic dependency path. This need not enumerate all possible dependency paths: retain a compact dependency graph, deduplicate primary diagnostics, and avoid exponential repeated explanations. For a nested anonymous function, display its source span and enclosing named definition when present. A human-readable source excerpt is optional; precise names/spans and reasons are required.

## 4. Recommended architecture

### 4.1 One source read, one non-evaluating analysis path

Use this pipeline:

```text
existing source-file validation and single read
  -> existing restricted source reader, retaining source offsets
  -> trusted expansion-only preparation and source analysis view
  -> binding-aware inference and contract checking
  -> structured report
  -> CLI rendering / exit status
```

Read the source through `inspect-source-file`, then parse the returned text with `parse-source-buffer` and its stored line/column/position offset. Preserve all existing declaration, UTF-8, regular-file, symlink, extension, and dotenv-path rules. Do not replace this with unrestricted `read`, `#reader`, or a second file read.

The preferred integration is a **private, opt-in source-analysis view produced by the trusted expander** before it erases source constructs into encodings. Preserve literal kinds, lexical binding identity, `rec` boundaries, source origins, and declaration dependencies. A private module syntax property may request and carry this inert analysis data. It must not become public language syntax or a runtime dependency.

Exercise ordinary expansion for syntax/binding validation, but do not instantiate or evaluate the user's module. In particular, do not call `run-source`, `prepare-entry`, `evaluate-entry`, `demand-entry`, or a language renderer to analyze source. `prepare-entry` is not an expansion-only API despite its name. [R5, R6]

The analysis request property and output property must have distinct keys, a single well-defined ownership point, and validated payload shape. A missing or malformed analysis payload is an internal failure, not an empty program that passes. Never obtain a report by trusting metadata supplied through arbitrary user code.

Keep type algorithms outside `lang/expander.rkt`. The expander may perform only the small mechanical source/binding translation needed to expose its existing semantics. If a shared helper is necessary, classify it explicitly as compile-time frontend machinery, keep it independent of inference, and preserve the existing production import directions.

Racket syntax properties and their merging rules require an early actual integration probe; do not assume arbitrary metadata survives every expansion or embedding boundary. Use inert, validated data that can be consumed across the relevant phase boundary, not a closure, live port, or an instance whose identity depends on a separate module instantiation. A small tagged record/prefab or list/vector payload is enough; do not add a general serialization system. Metadata is consumed during checking and need not be preserved on ordinary compiled user programs. [T1, T2]

Do not shortcut ordinary source validation when collecting this view: an invalid or unsupported literal in an unused definition is still invalid source. Preserve exact-rational versus inexact/complex literal distinctions and actual character-literal restrictions. Validate the entire file before treating a prefix as a checked program. A malformed final form must not allow earlier forms to execute or produce a full-prefix report.

The non-evaluation boundary is **user code**, not “Racket performs no work.” Invoking trusted macro transformers or loading the fixed trusted language declaration graph may be necessary. That does not authorize instantiating the user's module, demanding its values, importing a path named by arbitrary source, or reusing a live REPL namespace. Read the explicit source snapshot only; no recursive project scan, user program data-file reads, or REPL/session imports are part of analysis.

### 4.2 No parallel grammar or name-based impersonation

Reuse the existing expander's declaration recognition, binder rules, and sugar lowering. Do not build an independently maintained parser that merely matches strings such as `if`, `list`, or `rec`.

A user can shadow names. In addition, generated sugar uses hygienic references that must not accidentally resolve to those user bindings. Associate a trusted contract with a resolved built-in binding, not a spelling. Preserve the distinction through aliases and source transformations.

The analysis view needs only a small inert AST: literal, variable, lambda, unary application, **local let binding**, top-level binding, recursive binding, and origin metadata for source sugars/diagnostics. Preserve `let` and `rec` before they become ordinary lambda applications. Every variable reference resolves to an opaque local binder ID or a trusted built-in catalog ID; source spelling is only for display. Preserve the original source-node registry even where checking uses normalized nodes.

Ordinary binding identity, declaration recognition, and hygienic sugar expansion must come from the trusted frontend's semantics, not a second symbol-based approximation. The trusted frontend may assign catalog IDs after it has resolved the actual built-in binding. Those IDs are private inert metadata, not tokens a source file may choose to gain a type contract. Verify the runtime/bundled module reference mapping in the early embedding probe; do not assume developer-checkout filesystem names survive embedding.

Use the existing dependency graph to process acyclic forward definitions in dependency order. This is **analysis ordering only**; never rewrite or reorder runtime source expressions to perform inference.

### 4.3 Implementation placement and dependencies

Prefer a small set of focused modules under an explicitly classified `runner/static/` subtree: frontend integration, type representation/unification, inference, trusted contracts, and report construction/formatting. These are suggested responsibility boundaries, not a required file count. Keep the CLI adapter in the existing launcher small and lazily load the checking path as appropriate for the existing embedding mechanism.

Do not place inference in `core/`, `effects/`, `runtime/codec.rkt`, or `runtime/host.rkt`. Do not import arbitrary `tooling/` support into production computation. New source classes and exact launcher/frontend permissions belong in the boundary gate in the same phase as their use. Enumerate the admitted modules and dependency directions rather than giving every future file under a new directory unrestricted capabilities; unknown paths and forbidden imports must still fail closed.

The backend returns structured Racket data. It does not print, exit, read additional project files, open sockets, execute source, or mutate a REPL session. CLI formatting does not use AttaLambda's runtime `value-to-string`.

Use existing Racket facilities and project conventions. No solver package, compiler framework, plugin system, language server, or generalized AST framework is needed.

## 5. Type system and inference rules

### 5.1 Representation

Represent types structurally, not as display strings:

```text
Type variable
Nominal base: Rat | Bool | String | Char | Byte | Unit | Error
Arrow(domain, codomain)
List(element)
Option(element)
Result(success-element)        -- the Err payload is always Error
Map(key, value)
```

A separate environment entry is `Scheme(quantified variables, monotype)`. Schemes are instantiated on lookup; they are not allowed inside arrow domains/codomains or container parameters. This is rank-1 inference, not higher-rank/System F inference.

There is no public `Nat`, `Int`, `Number`, `IOError`, native `Pair`, or interchangeable String/List type in this system. Type constructors are static metadata only, not new runtime tags. TCP handles remain Rats unless a later, separately justified refinement models them; do not invent runtime Listener/Connection types.

Keep **proof state** separate from the type representation:

```text
Established
Unproved(reason, source origin, dependencies)
Conflict(diagnostic)
```

An unproved expression is not a fresh type variable and not `Any`. Successful-output hints for partial contracts must never erase unproved state.

### 5.2 Restricting generic data safely

Ordinary functions are untagged lambdas. Several public constructors inspect their arguments' tags, including Error propagation. It is unsound to assume that a function value can be passed to every such constructor merely because the raw calculus represents both as lambdas. [R7, R8]

Use one small static restriction for constructor schemes: a **data-restricted type variable** ranges over canonical non-Error tagged data shapes, not arbitrary function types. Its admissible types are `Rat`, `Bool`, `String`, `Char`, `Byte`, `Unit`, and well-formed List/Option/Result/Map types over similarly admissible parameters. Result Err's fixed Error payload is part of the Result constructor contract. Error itself remains a separate first-class type.

Record this restriction on a variable and preserve it in generalization/instantiation; unification must propagate it. It is not a runtime `Data` tag and does not require a general type-class framework. A restricted scheme may display `forall a:data. ...` to avoid concealing its domain.

Container formation preserves these restrictions recursively: `List(a)`, `Option(a)`, and `Result(a)` require a data-restricted payload parameter, and `Map(k,v)` requires data-restricted keys/values. Unifying a data-restricted variable with a nested constructor constrains every contained parameter; it must not accept `List(a)` and later let `a` silently become a function. An unconstrained variable unified with a restricted variable retains the stricter domain. Failed restriction checks leave no committed partial mutation.

This is a static abstract-value invariant, not a host inspection of a runtime representation. `Map(k,v)` includes the separately checked invariant that its stored equality callback accepts two `k` values and returns Bool; that internal function is not a user data element. Canonical data may be lazy and may diverge when demanded; this restriction is not a finiteness or termination check.

Passing a function or another excluded value at such a boundary is an **unsupported-domain gap**, not permission to change runtime behavior or claim an unconditional success signature. For fixed Error-domain APIs such as `make-err` and `error-to-string`, provide the explicit Error-domain contract. Do not add a general overload resolver to cover every use of generic rendering: its supported data-restricted scheme may leave direct Error rendering partial even though the runtime supports it; `error-to-string` plus `stdout` is the existing explicitly typed alternative. Any broader overload not represented by the small scheme language remains a gap for that broader use. Do not silently assert that every runtime-supported value is in the checked subset.

### 5.3 Kernel operations

Implement fresh variables, structural substitution, free-type-variable computation, scheme instantiation, generalization, and unification with an occurs check. Enforce constructor arities, nominal distinctions, and data restrictions.

Unification must reject an equation such as `a = Arrow(a, b)` without looping or constructing an infinite type. Stable display names are separate from internal variable identities.

Generalize only variables not free in the **substituted current environment**, after applying the current solution to both the inferred type and environment. Apply the same solution to variable restrictions. In notation, quantify `FTV(S(type)) − FTV(S(environment))`, not variables free in a stale environment. Only completed obligations can be generalized; no success-only scheme is published from a partial body. Lambda parameters and a recursive binding inside its own body remain monomorphic. A completed recursive definition is generalized after removing its temporary self assumption, with the true outer environment retained. [T3]

Use one comprehensible solving strategy: syntax-directed rank-1 inference with a local substitution/constraint state, immutable or narrowly mutable as suits existing Racket conventions. A separate batch constraint framework, union-find optimization, solver plugin layer, or second production checker is not required. On a failed speculative equation, discard its tentative updates before independently checking siblings. Never share mutable quantified scheme variables between instantiations or between input files.

### 5.4 Expression rules

- Literals have their actual public nominal types: exact rational literal → Rat; string → String; accepted ASCII character literal → Char.
- A reference instantiates its established scheme. A reference to an incomplete binding retains dependency provenance and cannot make its caller fully checked.
- For a lambda, introduce a fresh monomorphic parameter type; infer its body and construct an arrow. Multi-parameter source lambdas use the existing unary interpretation.
- For application, infer function and argument, then constrain the function to an arrow from the argument type to the result. Preserve partial application rather than treating source argument lists as uncurried tuples.
- A `let` checks its initializer, generalizes eligible variables, then checks its body under the new binding. Sequential lets have the actual source scope and shadowing rules.
- A `def` is checked against its real dependencies; acyclic forward references remain supported. Do not infer by source order alone or by evaluating a definition.
- The actual first-class `if` binding has the supported scheme `forall a. Bool -> a -> a -> a`. Check all supplied arguments, including both branches regardless of a literal condition. `cond` uses the same contract through hygienic lowering; `if` is not a reserved syntax-only special case.
- List construction uses the supported homogeneous `cons` scheme and one element type. Incompatible established element types or branch types produce `TYPE_CONFLICT`, including when the runtime could choose one branch or store heterogeneous data. Visit every independent child so one conflict never hides another or an explicit unproved region. Normal execution remains unchanged.

A failed finite type-equation constraint between established types is a `TYPE_CONFLICT`, including a homogeneous-List/common-branch equation. Do not convert it into a gap merely because ordinary execution accepts the source. Use Section 5.8's closed classification; unsupported-contract hints cannot establish either a successful type or a spurious conflict.

### 5.4.1 Preserve source-level polymorphic binding

Source `let` is a generalization boundary even though normal execution lowers it to a lambda application. Do not run inference solely on that fully lowered application. These two snippets intentionally have different V1 static outcomes while retaining their existing runtime meanings:

```racket
;; FULL PASS: the let-bound identity is instantiated independently.
(let id = (lambda (x) x)
  (if (id TRUE) (id 1) 0))

;; FAIL: id is a monomorphic lambda parameter.
((lambda (id) (if (id TRUE) (id 1) 0))
 (lambda (x) x))
```

Similarly, `rec` has its source-level rule while an explicitly written self-applying fixed-point term may be outside the supported type language. Do not promise identical typing judgments for arbitrary beta-equivalent source rewrites. Require equivalence for the actual supported sugar mappings—currying, sequential-let nesting, List syntax and `cons`, and `cond` and its hygienic `if` chain—while preserving their source binding boundaries. This is an optional source checker, not a proof that every final raw lambda encoding is simply typable.

### 5.5 Ordinary recursion

For `(rec name arguments ... = body)`:

1. Introduce a fresh monomorphic type for `name` in its own scope.
2. Infer the curried definition body with that assumption available for recursive calls.
3. Unify the assumed type with the inferred definition type.
4. Preserve all body obligations; generalize eligible variables only after completion.

Apply this to zero-source-argument `rec` forms too. A recursive value that has consistent finite type constraints may be checked; failure to terminate is not a typing failure. An occurs-check failure remains an explicit unsupported recursive-type case.

The local self assumption is provisional typing context, **not an unproved external dependency**. Discharge it when its body and consistency equation succeed. Do not let generic transitive-gap propagation make every `rec` permanently partial or recurse infinitely through its own dependency edge. Genuine external gaps in the body still propagate. Ordinary recursive functions keep one monotype for all recursive calls; incompatible uses within that body are not rescued by separately freshening the recursive name.

Do not type-check literal `raw-fix` as though it had a derivable simple type. Trust the existing source-to-fixed-point lowering as a named compiler contract and test that it is unchanged. Do not expose `raw-fix`, accept new mutual recursion, add direct self-reference to `def`, or use host recursion to execute AttaLambda.

### 5.6 Error and incomplete contracts

**Error is not bottom, not a thrown exception, and not automatically assignable to every type.** Do not add implicit casts from Error or an unknown result to an expected type.

For an operation with a value-dependent Error alternative that V1 cannot represent/prove away, check whatever input contract is known and mark its result obligation unproved. A success-shape hint is useful in the explanation but is not a verified return type.

Required examples:

| Operation/use | Required V1 treatment |
| --- | --- |
| `div` on two established Rats | Result of Rat, not Rat. A possible Result Err is represented and does not alone create a gap. |
| `unwrap-ok` on a Result | Check the Result input; report unproved output because of the WrongResultVariant Error alternative. |
| `head` or `tail` on a List | Check the List input; report the possible empty-list Error as a gap. No implicit nonempty proof. |
| `make-byte` / `make-char` with a Rat | Input type is known; range/integrality-dependent Error remains unproved in V1. |
| `unwrap-err` on an established Result | Its normal output is Error even for the wrong variant; audit and record the actual contract, not a fictitious arbitrary error parameter. |
| A user lambda receiving an Error | Apply ordinary static rules. Do not assume the runtime's library Error-absorbing continuation semantics apply to arbitrary user functions. |
| A partial Error-producing call used as a function | Remains unproved; never infer away the possibility that the value does not satisfy the required arrow type. |

This conservative policy intentionally leaves some ordinary, correctly guarded programs partial. For example, V1 does not infer a variant refinement from `(is-ok r)` and therefore still reports the subsequent `(unwrap-ok r)` as unproved. Likewise it does not infer nonemptiness from `is-nil`. State this limitation in help documentation. Predicate refinements can be a later feature; they are not hidden implementation requirements.

Do not implement an ad hoc global rule that appends Error to every function result. Besides weakening the guarantee, it mishandles the runtime's arity-aware early-Error continuations. Keep those continuations unchanged and cover their interaction with the analyzer through conservative boundary tests.

### 5.7 Independent checking and gap propagation

Use per-binding/component inference state so a failed component does not corrupt unrelated inferred schemes. Do not retain half-applied substitutions from a failed check as authoritative environment information.

Propagate gaps through aliases, applications, return expressions, captured dependencies, and higher-order arguments. If a dependency has only a conditional shape, its users are conditional too. A type variable inferred from a known polymorphic scheme does not count as a gap.

Keep visiting independent child expressions and definitions after a gap or conflict where the source structure is valid. For example, an unknown result in argument one must not hide a concrete String/Rat mismatch in argument two. Deduplicate primary gap diagnostics while retaining dependent-definition references.

For a partial built-in, retain only its audited input requirements, curried positions, and gap reason as a conditional contract. The reference itself is unproved when its complete callable behavior is not represented; `(def extract = unwrap-ok)` cannot earn a verified `Result(a) -> a` just because no call occurs yet. That uncertainty follows an alias, a returned/captured function, an argument to `map`, and a partially applied value. Do not introduce latent effect types merely to make such bare references fully pass in V1.

Application handling must preserve known remaining argument obligations from an **established callee** even when an earlier argument is unproved. In `(add (head NIL) "bad")`, `head` supplies a gap but the independent second-argument Rat contract of `add` still yields a conflict. Any residual shape used for recovery is explicitly conditional and cannot be generalized, counted as established, or supplied as proof to a caller. A best-case output hint from an unproved producer is explanatory only; do not use it as established actual type to generate a downstream conflict. Check concrete conflicts inside that producer independently.

Keep completed schemes for upstream definitions immutable. A bad call site does not change a correctly inferred function declaration into an invalid definition. A failed function body, conversely, publishes no verified signature; dependent uses retain a path to that primary failure/gap. These rules apply equally to top-level values, function bodies, aliases, captured free variables, and nested anonymous functions.

### 5.8 Closed verdict rules and contract examples

The diagnostic class comes from the failing obligation, not how reassuring the final report would look.

| Obligation/outcome | Result | Example |
| --- | --- | --- |
| Supported finite nominal/arrow/container equation conflicts | `TYPE_CONFLICT`; file FAIL | Rat versus String, Result passed to `add`, incompatible homogeneous elements/branches |
| Occurs check requires an infinite type | `RECURSIVE_TYPE_REQUIRED`; unproved | `(lambda (x) (x x))` |
| Actual callable can return an unrepresented Error alternative | `UNREPRESENTED_ERROR_ALTERNATIVE`; unproved | `head`, `unwrap-ok`, a range-dependent constructor |
| Use is outside the catalog's explicitly supported data domain | `UNSUPPORTED_DATA_DOMAIN`; unproved | a function passed to `some` or nested inside a data-restricted construction |
| Raw host or another audited but unsupported value contract | `UNSUPPORTED_CONTRACT`; unproved | `host` and its aliases |
| Source binding depends on an unproved/failed source binding | dependency diagnostic; unproved | a wrapper around `unwrap-ok` |
| Invalid source syntax/binding/literal/module cycle | source diagnostic; status 65 | unknown identifier, recursive `def` |
| Missing analysis metadata, unfinished internal state, catalog drift, analyzer failure | operational diagnostic; status 70 | source nodes omitted by a broken frontend |

A region can contain both conflicts and gaps; collect both, with FAIL as the file verdict. In the same region, do not let an unsupported-domain encounter erase an independently established finite conflict. Diagnostic category selection must not rely on a broad `catch all exceptions => PARTIAL` path.

These are reference schemes for the supported subset, to audit and instantiate through the same catalog as every other built-in. Lowercase quantified letters are static variables, not new source names:

```text
if          : forall a. Bool -> a -> a -> a
cons        : forall a:data. a -> List(a) -> List(a)
NIL         : forall a:data. List(a)
NONE        : forall a:data. Option(a)
some        : forall a:data. a -> Option(a)
make-ok     : forall a:data. a -> Result(a)
make-err    : forall a:data. Error -> Result(a)
option-case : forall a:data b. Option(a) -> (a -> b) -> b -> b
map         : forall a:data b:data. (a -> b) -> List(a) -> List(b)
filter      : forall a:data. (a -> Bool) -> List(a) -> List(a)
reduce      : forall a:data b:data. (b -> a -> b) -> b -> List(a) -> b
make-map    : forall k:data v:data. (k -> k -> Bool) -> Map(k,v)
```

Do not infer general equality laws or mathematical purity from `make-map`'s callback type. The type checks argument/result relationships only. A callback's unproved body taints the resulting Map, even if the Map is initially empty. A known wrong callback type is checked even when runtime laziness would skip it on an empty container; this checker does not specialize by demand or collection length.

If an audited implementation invalidates a proposed complete scheme, first establish the exact counterexample and classify the affected contract honestly; never change runtime semantics or insert a new type system to save the scheme. A contradiction affecting a mandatory supported example blocks the relevant gate and is reported as such after independent safe work; it is not resolved by secretly removing the requirement.

## 6. Trusted library and host contracts

### 6.1 One auditable contract inventory

Begin the checker-side inventory with the audited seed contracts in Step 2.5a, then complete it in Phase 3. Use the same inventory throughout, keyed by actual public binding identity; do not create a separate prototype table. For each exported value binding, record:

- A supported scheme or an explicit partial/unsupported classification.
- Curried parameter order and input-domain restrictions.
- Whether the stated result is complete under those restrictions or only a success-shape hint.
- Relevant value-dependent failures and data/printing restrictions.
- Implementation path and binding, and the focused test exercising the contract.

This inventory is not a second runtime library. Do not evaluate functions to discover their signatures. Do not generate trusted static facts from their runtime tags alone: tags do not encode function arrows, List element types, or Result success payloads.

A drift test must compare the actual facade's exported public value bindings against the inventory and account separately for syntax and module scaffolding. Added, removed, or renamed exports must fail closed until classified. Include literals/sugars via the frontend contract, not as fictitious value exports. The test must not need to demand exported language values.

Also test that every catalog key is backed by the intended resolved binding; equality of spellings is insufficient. During implementation, unaudited exports may have an explicit internal pending classification so early phases can run without inventing a type. The early backend pilot establishes its source obligations using audited seeds only; it does not claim that the final public catalog or CLI is delivered. Completeness checks for the shipping catalog are enabled before the real CLI, without introducing a public development mode or configurable escape hatch. Before the public command is enabled, every pending entry must become supported or specifically unsupported. A pending entry in the final command is an internal defect, not a normal user-source gap. Do not maintain a second copied list of signatures in the expander or test expectations generated from the same table and call that independent evidence.

### 6.2 Minimum complete supported surface

The following are minimum targets, conditional on their actual valid-input contracts. They cannot all be demoted to unknown merely to finish the milestone:

- Rat literals, Bool/Unit/String constants, Rat arithmetic returning Rat, Rat comparisons, and Bool operations.
- Identity, application, composition, curried partial application, ordinary reusable helpers, and ordinary `rec` over those operations.
- Parameterized List/Option/Result/Map representations in the type algebra; established schemes for `NIL`, `NONE`, `cons`, `some`, `make-ok`, and `make-err` with their real Error/data restrictions.
- Safe List structure operations such as `len`, `append`, and `reverse`, and higher-order `map`, `filter`, and `reduce` when element/callback contracts are established and their ordinary valid-input paths have no unrepresented Error alternative.
- Result/Option predicates and the actual `option-case` argument order and branch relationship.
- String operations whose valid-input outputs have a fixed shape, scalar type-specific rendering, and the I/O wrappers in Section 6.3.

Audit other exported operations individually. An honest partial classification is required for operations not covered by the small type language: do not invent signatures for heterogeneous `flatten`, treat `zip` as returning a native pair, or erase invalid-count possibilities in range/indexing operations.

`Result(a)` means Ok of `a` or Err of Error. It is not a two-free-parameter `Result(a, e)`. `make-err` consumes Error; it does not accept any payload. String and `List(Char)` remain distinct nominal interfaces even where their representations are related.

Generic rendering/printing may receive a restricted supported contract for known canonical data shapes. A raw function, a container with unproved contents, or an unresolved broader overload must not pass under an unconditional `forall a. a -> String` / `forall a. a -> Result(Unit)` claim. Preserve the language's existing unspecified behavior outside the supported domain; do not add host function detection or a Function tag. Test both direct and nested function cases. [R7, R8]

### 6.3 Host boundary

The initial complete wrapper contracts must include:

```text
stdout     : String -> Result(Unit)
read-line  : Unit -> Result(Option(String))
read-file  : String -> Result(List(Byte))
write-file : String -> List(Byte) -> Result(Unit)
```

Verify each against its wrapper, host branch, codec conversion, and existing tests before marking it complete. Expected I/O failure is represented by Result Err. These types do not assert that a file exists, a path is permitted, a write succeeds, or network input satisfies an application schema.

Audit the remaining TCP, HTTP, and exit operations with the same discipline. Numeric arguments that require an integral range or other value invariant must not be given a complete success-only result if the pure wrapper can instead return Error. A correct partial classification is acceptable for those operations in V1. Do not invent nominal handle types or a new effect system.

The public raw `host` binding is an explicit **unproved boundary** in V1. Its operation-dispatched protocol does not become a universal typed function merely because a caller expects one result type. The same restriction follows aliases and higher-order uses. Do not infer a raw-host result by inspecting a few request strings or executing the request.

Typing known wrappers does not mean proving external bytes in advance. It means relying on the actual host/codec contract to return a value of the declared shape or its declared Result failure. Runtime validation stays in place. Source code using raw `host` or a partial wrapper prevents FULL PASS through the relevant dependency chain.

### 6.4 Trust and source coverage stay separate

User-source coverage excludes library implementation expressions and macro-generated lambda encodings. Every report states the trusted basis. The contract inventory is audited/tested, not recursively passed through this same simple type checker and called proven.

Do not advertise “the entire untyped lambda runtime is now statically verified.” The deliverable is a checker for the supported source subset relative to a documented, reviewable boundary.

## 7. Execution contract for the implementation agent

### 7.1 Authority and preservation

This document was requested as a plan. Its creation authorizes no implementation, commits, pushes, PRs, merges, tags, deployments, publication, or dependency installation in the owner's environment.

When the owner explicitly assigns implementation using the kickoff in Section 12, the intended local endpoint includes a dedicated milestone branch, scoped workspace changes, isolated tests/builds, and verified local phase commits. The kickoff deliberately stops before remote pushes, PR creation, merge, tagging, or publication. Follow any later explicit owner instruction and higher-priority environment rules; do not reuse permission granted to the completed 0.8.0 milestone.

The supplied kickoff explicitly overrides the repository's usual phase-push routine for this assignment: make verified **local** commits only; no remote push or PR. Missing remote write access is therefore not a blocker. Use one milestone branch, proposed name `optional-static-checking`, based on the actual appropriate working revision after checking ancestry and existing work. Reuse an existing matching branch rather than creating parallel implementations. Preserve unrelated changes. Do not reset, stash, clean, or rewrite someone else's work to obtain a clean build. A separate authorized worktree is preferable to disturbing an active checkout.

Never inspect dotenv contents or credentials, run Graphify, use production data, make unapproved purchases, or expand external access beyond the assignment. Read-only repository/toolchain access needed for the assigned work is distinct from remote Git mutations or publication. Inspect repository scripts before executing them. Use synthetic fixtures, agent-owned temporary directories, and ephemeral loopback resources. Clean up only resources the agent created.

Do not change `VERSION` or release projections merely to package this unreleased feature. The existing builder supports the current approved version; record the candidate by its source revision and archive digest, clearly mark it unpublished, and keep it in a unique private output directory. It must not replace or masquerade as the public 0.8.0 asset.

### 7.2 Ordinary decisions and deviations

Decide private module names, small helper boundaries, test organization, and equivalent Racket plumbing without routine owner questions. Prefer the architecture here and existing repository conventions.

For a necessary deviation, record the reason, preserved contract, chosen mechanism, and validating test. A metadata transport failure may justify a narrow frontend adaptation; it does not justify a second evaluator, weaker reader policy, string-based binding resolution, or changes to runtime semantics.

If a step is larger than one focused inspect/change/test/review cycle, subdivide it into stable lettered substeps in the active plan **before** implementing it. Preserve the original outcome and acceptance requirements.

### 7.3 Failure loop and checkpoints

Stop dependent work on a failing checkpoint. Reproduce the smallest counterexample, identify the responsible layer, make a narrow correction, rerun focused checks, and refresh downstream evidence whose inputs changed. Distinguish baseline failures from regressions.

Do not remove assertions, weaken purity/boundary gates, reinterpret Error as success, inflate deadlines, mark unsupported code complete, or broaden the feature to obtain green results. Correct a mistaken test only with evidence against the intended contract. Avoid identical repeated attempts with no new diagnosis.

At each phase checkpoint, run its specified affected checks, the full required suite, both structural gates, and a scoped review before a mandated phase commit. The existing full-suite script already runs both gates; separate gate runs are useful during iteration, not a requirement to duplicate their work mechanically. Refresh relevant bytecode before focused tests. Do not run the entire suite after every tiny edit unless current project rules require it. A record-only phase need not invent unrelated focused tests, but still follows required repository commit gates. Do not add a second full-suite run only because a checkpoint text repeats checks already covered by its successful suite command.

Discover relevant review/debugging skills available in the execution environment and read a selected skill before using it. No named skill is required for correctness. Prefer a read-only independent reviewer at the frontend, inference/contract, and final gates when available. Otherwise perform and label a fresh self-review using the concrete counterexamples below. A review request or a favorable summary is not a substitute for executed tests.

### 7.3.1 Proportional robustness and independent evidence

For changed frontend, substitution, inference, coverage, and reporting paths, use bounded synthetic tests of nested syntax, long application chains, repeated aliases, and many independent definitions. Include repeated analyses in one test process to expose stale namespaces, schemes, and source IDs. Compare measured behavior on fixed fixtures; do not add a performance framework, arbitrary coverage target, new user quota, or an optimizer. A recoverable resource limit/internal failure yields no full pass. A runaway test is killed by its harness and fails the checkpoint; a timeout is not a supported PARTIAL verdict.

Negative non-execution tests require an observation that would actually detect the forbidden effect. Use an isolated marker file for writes, input-position or separate-pipe evidence for reads, and a ready ephemeral loopback listener/deny observer for network attempts. Do not count a mock expectation on a function the real checking path never calls as proof. Do not run a deliberately nonterminating or unspecified raw-function operation in the ordinary evaluator just to test static rejection. Such fixtures are **check-only**. Separately execute only small controlled runtime-contract tests that terminate under their stated domain, with parent-enforced deadlines and cleanup.

Build confidence against independent expected behavior: hand-derived type fixtures, actual source scope/lowering, and selected runtime results. Add a few bounded negative tests that remove a required catalog entry, corrupt an analysis ID, or inject an analyzer failure and assert fail-closed behavior. Existing purity/boundary negative tests must still reject an unclassified module or forbidden import. Do not create a mutation-testing service or a second checker.

### 7.4 Durable progress and resumption

Reuse `PLAN.md` and `HANDOFF.md` conventions. Link this specification and retain completed historical milestone records; do not erase the old plan or accidentally carry forward its release authority.

Record completed step IDs, actual source revisions, meaningful decisions, exact test commands/results, evidence paths, unresolved findings, and the next unfinished step. Keep transient/sensitive logs out of published records. Do not introduce a new progress database or reporting framework.

After interruption, reread the handoff, inspect the actual branch/worktree and owned resources, reconcile completed actions with evidence, and resume the first safe unfinished step. Recheck stale test results when source or runtime inputs changed. Do not blindly repeat an external action because a checkbox is unchecked. These rules enable resumption; they do not keep a session alive or automatically restart an agent after a platform limit or interruption.

Escalate only missing essential access/toolchain/authority, contradictory governing contracts, an unsafe irreversible action, or a material scope decision. Complete independent safe work and report the smallest necessary owner action. Missing final consumer infrastructure is a delivery blocker, not permission to call a source-only result fully packaged.

## 8. Phases and small implementation steps

All checkboxes are intentionally unchecked. Run focused tests with each step. Phase checkpoints collect evidence and close verified local commits; they do not replace the focused kernel, frontend, and contract reviews named inside the phases. Subdivide an unexpectedly large step before implementing it rather than sacrificing its checks.

### Phase 0 — Confirm the workspace, constraints, and usable V1 scope

**Purpose:** establish the actual baseline, authority, environment, and expected limitations.  
**Prerequisites:** explicit implementation assignment and repository read access.

- [ ] **0.1 — Reconcile the checkout and choose the safe workspace.**  
  **Work:** Read current project instructions, all canonical contracts/amendments, active plan/handoff, affected source, relevant PRs, ancestry, and local changes. Compare with the pinned baseline. Choose or reuse one milestone branch/worktree without disturbing other work. Do not update project source/contracts before the baseline in 0.2.  
  **Check:** Record `git rev-parse HEAD`, `git branch --show-current`, `git status --short --branch`, relevant changes, and applicable authority. A clean, separate authorized worktree is preferable to resetting/stashing another person's work. Existing public refs/assets are unchanged; a local-only assignment does not require remote write access.

- [ ] **0.2 — Establish the isolated test and candidate environment.**  
  **Work:** Inspect preparation/build/consumer scripts. Provision or reuse an agent-owned supported runtime; confirm Linux build/consumer prerequisites and available review tools.  
  **Check:** Record `racket --version`, dependency-correction `--check`, and untouched `./run-all-tests.sh` results. Name unavailable essential infrastructure now. Do not modify the owner's runtime or claim a historical test count as the new baseline.

- [ ] **0.3a — Save the active plan and narrowly authorize checker scaffolding.**  
  **Work:** After the baseline, save/link this complete specification and record the active phase plan using repository conventions. Add only necessary canonical amendments for optional source analysis, its private classified scaffolding, and checker exit statuses. Preserve prior bytes and update specification hashes.  
  **Check:** Historical plans and canonical bytes are preserved, index hashes/links match, and the initial diff contains only intended planning/contract changes. No runtime primitive, tag, capability, typing extension, or release authority is introduced.

- [ ] **0.3b — Record realistic pilot expectations.**  
  **Work:** Inspect representative existing arithmetic/recursive, container, and boundary examples. Map the Section 9.2 counterexamples to required FULL PASS, FAIL, PARTIAL, or invalid-source expectations before implementation can bias the expected results.  
  **Check:** The active plan names the early pilot in Step 2.9, the guarded-unwrap/nonempty/range limitations, and the explicit heterogeneous-join verdict correction. No promised corpus percentage or undocumented feature is needed to meet those expectations.

**Checkpoint 0 — Baseline gate.** Review authority, baseline, and the actual supported-versus-partial expectations; run required repository gates before committing. Stop dependent work on a relevant unexplained baseline failure. Missing packaging infrastructure may permit independent kernel work but remains a final-delivery blocker.

### Phase 1 — Prove the non-evaluating frontend and embedding path

**Purpose:** resolve binding, source-location, and metadata transport risk before inference.  
**Prerequisites:** Checkpoint 0 and understanding of the current restricted reader and expander.

- [ ] **1.1a — Add the expansion-only preparation seam.**  
  **Work:** Use the existing validated source snapshot and restricted parser to prepare a fresh module for trusted expansion only. Reuse the fixed language-declaration/embedding machinery as appropriate; do not call the session's evaluating preparation routine. Classify the new private helper and its exact imports in the same change.  
  **Check:** Focused frontend tests accept valid source and reject bad headers/readers, unsupported literals, and unknown names. Instrument the user-module boundary to establish that no evaluation/instantiation/demand occurs. Fresh preparations cannot inherit REPL bindings or an earlier input's namespace state.

- [ ] **1.1b — Expose a complete inert source analysis view.**  
  **Work:** Add the smallest private opt-in expander seam retaining literal kinds, lexical identities, original source IDs, declaration dependencies, and explicit `let`/`rec` nodes before representation lowering. Validate the metadata's shape and source-accounting invariants. Keep type algorithms outside the expander.  
  **Check:** Recover literals, a curried function, an alias, a nested lambda, a local let, and a recursive definition. Missing/corrupted/duplicated IDs or a missing final form fail internally rather than passing an incomplete program. Without the request, existing expanded computation remains binding-equivalent to the original path; compare structural terms modulo fresh binder names and inert source properties, not incidental pretty-print bytes.

- [ ] **1.2 — Preserve binding, sugar, forward references, and source abstraction boundaries.**  
  **Work:** Reuse expander logic for sequential lets, repeated binders, `list`, `cond`, acyclic forward references, zero-argument `rec`, and shadowed declaration keywords. Retain let-generalization boundaries while normalizing currying/list/cond mechanically.  
  **Check:** Actual-expander fixtures distinguish a user `add`/`if`/`cons` from the built-in and preserve hygienic generated operations. Source-local references identify their real binders even when names repeat. Ordinary datum-equivalent reader notation must be handled like the existing parser; do not invent new restrictions for an otherwise valid quoted/escaped spelling of an identifier. Preserve `rec` instead of only its fixed-point encoding. Existing direct/mutual-cycle rejection, literal validation, and original source locations remain unchanged; no symbol-only mock is sufficient.

- [ ] **1.3 — Prove preparation does not perform program effects.**  
  **Work:** Add synthetic user modules containing demanded stdout, input, file writes, exit, raw-host/network calls, and divergence. Include an effectful first form followed by invalid syntax.  
  **Check:** Preparation finishes or reports source errors without program output, consumed input bytes, marker-file writes, program exit, or network attempts. Combine instrumentation with actual isolated file/input/loopback observations; use bounded harness cleanup. The checker never calls the program to discover its types.

- [ ] **1.4 — Exercise the same frontend through executable embedding.**  
  **Work:** Compile a minimal test-only driver around the actual analysis seam using the existing embedding approach. Do not create a second parser or temporary public flag.  
  **Check:** Outside the checkout, the embedded driver analyzes source and retains metadata without source-path assumptions. Request and result properties remain distinct and validated. Retain the useful regression, not a parallel implementation or permanent probe framework.

**Checkpoint 1 — Frontend feasibility gate.** Run frontend/effect/embedding probes, affected source-reader and `tests/interactive-expansion-test.rkt` tests, full suite, and structural gates. Review binding/hygiene and non-execution counterexamples. Adapt failed metadata transport narrowly before investing in inference. Trusted compile-time expansion is allowed; evaluating the user's program is not.

### Phase 2 — Build the small inference engine and run the usefulness pilot

**Purpose:** establish finite types, ordinary inferred polymorphism/recursion, and honest incomplete results.  
**Prerequisites:** Checkpoint 1. Seed contracts are created in Step 2.5a; the full library inventory is not a prerequisite.

- [ ] **2.1 — Implement structural types and separate proof state.**  
  **Work:** Add nominal types, arrows, containers, variables/schemes, and established/unproved/conflict results in classified checker modules. Keep display separate.  
  **Check:** Distinguish String from List(Char), Rat from Byte, a scheme variable from a hole, and Error from other types. Validate constructor arities. No solver, runtime dependency, or generalized type-system framework is introduced.

- [ ] **2.2a — Implement substitution, instantiation, and eligible generalization.**  
  **Work:** Add fresh variables, free-variable sets, substitutions/composition, and fresh scheme instantiation. Implement generalization over the substituted environment as specified in 5.3. Keep schemes separate from monotypes and state local to an analysis.  
  **Check:** Independent identity instances have fresh variables; captured environment variables do not. Substitution respects bound scheme variables and composition order. Quantifiers never enter an arrow/container. Unit tests expose the stale-environment generalization bug before source integration.

- [ ] **2.2b — Implement finite structural unification and failure isolation.**  
  **Work:** Unify nominal types, arrows, and containers with an occurs check using one small solver. Keep unsuccessful equation updates tentative or discardable.  
  **Check:** Hand-derived and bounded generated equations cover success, nominal conflicts, arrow/container mismatch, chains, and `a = a -> b`. Successful substitutions satisfy input equations and repeated substitution stabilizes. A failure cannot leak state into a separate problem, erase a sibling conflict, or allocate a cyclic/infinite type.

- [ ] **2.3 — Enforce the one data-variable restriction.**  
  **Work:** Preserve Section 5.2's restricted domain through unification, substitution, and schemes. Use a small admissibility rule, not a type-class or constraint-plugin framework.  
  **Check:** Rat/nested supported data are accepted; an arrow or Error is not silently admitted. Restriction survives instantiation/generalization. Unsupported data-domain use remains distinct from a concrete Rat/String conflict; no runtime Data/Function tag is added.

- [ ] **2.4 — Render types deterministically and close the kernel review.**  
  **Work:** Render stable variable names, quantified restrictions, containers, and correctly grouped arrows. Review the kernel before inference depends on it.  
  **Check:** Golden tests cover `a -> b -> c`, `(a -> b) -> a -> b`, Error, and restricted schemes. Recheck freshening, substitution, occurs-check, and hole separation with focused tests. Rendering never calls an object-language evaluator. This is a focused review, not an extra mandatory full-suite/commit phase.

- [ ] **2.5a — Create the real seed-contract inventory.**  
  **Work:** Inspect actual implementations/tests and audit Rat/Bool constants plus the arithmetic and first-class `if` schemes needed for double/factorial. Include Result-valued `div`, `is-ok`, a conditional `unwrap-ok` input contract, and the fixed `error-to-string : Error -> String` contract for the pilot. Associate catalog IDs only with their resolved built-in bindings.  
  **Check:** Record source locators and valid/invalid-domain evidence. `if` works as a value and alias, not only a syntactic head. `div` is Result-valued; `unwrap-ok` has no verified success-only signature. Other known exports may be explicitly pending audit, never unknown identifiers or fabricated safe signatures. This is the same inventory completed in Phase 3.

- [ ] **2.5b — Infer elementary source expressions.**  
  **Work:** Infer literals, references, lambdas, and curried applications through the actual frontend/kernel and seed inventory. Preserve complete input obligations when an earlier argument is incomplete; keep conditional hints out of established types.  
  **Check:** Infer double, identity, application, nested lambdas, and partial `add`; locate a String/Rat conflict. A shadowed function never inherits a catalog contract. Calls through a first-class `if` alias obey the same homogeneous-result equations as direct calls.

- [ ] **2.6 — Infer lexical bindings with source-level generalization.**  
  **Work:** Use actual acyclic dependency order and sequential-let scope. Generalize completed `def`/`let` bindings using the solved current environment; instantiate each use. Keep lambda parameters and captured environment variables monomorphic where required.  
  **Check:** Forward definitions and repeated/shadowed names work without runtime reordering. Identity works at Rat and String; `(identity identity)` checks. Section 5.4.1's let form passes and its lambda-parameter counterpart fails. The captured-function counterexample in 9.2 fails. Unknown names/forbidden cycles remain source errors, not gaps.

- [ ] **2.7 — Infer ordinary source `rec` and discharge its local assumption.**  
  **Work:** Use one monomorphic recursive assumption, unify with the inferred curried body, discharge the self edge, and generalize eligible variables afterward. Include zero-source-argument recursive values without evaluation.  
  **Check:** Factorial/summation infer `Rat -> Rat`; locate recursive conflicts. Self-dependencies do not make all recursion partial. Finite-typed nonterminating recursive fixtures are checked without being run. Raw self-application reports the occurs-check limitation. Direct/mutual module recursion and pure fixed-point lowering remain unchanged; no polymorphic recursion is introduced.

- [ ] **2.8 — Apply uniform constraints through source sugars and aliases.**  
  **Work:** Check source list/conditional normalization using original IDs and first-class built-in schemes. Treat finite homogeneous-element/common-result contradictions as TYPE_CONFLICT in every representation. Preserve explicit let/rec boundaries.  
  **Check:** Currying, sequential-let nesting, list/cons, and cond/if mappings agree under their supported rules. Heterogeneous direct/aliased `if` calls fail identically; homogeneous function-valued branches pass. Both branches and all independent children are visited. List typing tests may use explicitly pending constructor contracts until 3.2, but no production completeness is claimed for an unaudited contract.

- [ ] **2.9 — Close gap propagation and run the early backend pilot.**  
  **Work:** Finish component isolation, proof-state propagation, and the representative cases in 1.3 using the actual frontend/kernel/seed inventory. Treat incomplete built-in references as incomplete even before invocation. Preserve established upstream declarations after a bad call.  
  **Check:** Arithmetic/identity/recursion establish types; bad `add` and incompatible branch types conflict; raw self-application, guarded unwraps, and their dependent callers remain partial. A closure cannot hide a gap in an unused nested body. An earlier gap cannot hide a later independent argument mismatch: use `(add (unwrap-ok (div 1 0)) "bad")` while only seed contracts exist. Best-case unwrap output hints cannot invent a conflict in C11; its Error renderer is included in the seed audit. Reordering independent definitions or checking twice changes no result. Record pilot outcomes; fix required supported cases before the broader audit.

**Checkpoint 2 — Inference and practical-scope gate.** Review scope, generalization, recursive assumptions, and unchecked-result propagation; prefer independent read-only review when available. Run kernel/frontend/inference tests, affected language/recursion tests, full suite, and gates. The two definitions in Section 3.2 and `(factorial (double 3))` must be established without execution. Rendering/stdout arrive in Phase 3. Documented partial pilot results are an accepted V1 limitation, not a reason to invent refinements or request routine owner decisions.

### Phase 3 — Complete the auditable library and host contracts

**Purpose:** broaden useful coverage while preserving every actual failure alternative.  
**Prerequisites:** Checkpoint 2; the pilot works and the seed inventory is reused.

- [ ] **3.1 — Complete export classification and scalar contracts.**  
  **Work:** Inventory every actual public value binding separately from syntax/scaffolding. Complete supported scalar contracts; retain explicit range-dependent gaps.  
  **Check:** Export drift fails closed; `div`/`exp`/`recip` are Result-valued. Wrong nominal inputs fail with correct argument order. No private Nat/Int, public alias, or success-only signature is invented. Previously audited seeds remain consistent.

- [ ] **3.2 — Add container construction and safe non-callback List contracts.**  
  **Work:** Add data-restricted schemes for constants/constructors, `len`, `append`, `reverse`, and other audited fixed-shape operations. Record empty/count/nesting failure limits and preserve restrictions through nested type parameters.  
  **Check:** Homogeneous Lists retain element types; String is not List(Char). Heterogeneous `(list ...)`, direct `cons`, and a `cons` alias produce the same finite conflict. Functions hidden beneath a generalized nested-data variable cannot bypass its restriction. `head NIL`/`tail NIL` remain partial; `zip` does not gain an invented Pair. No runtime-valid construct is disabled in ordinary execution.

- [ ] **3.3 — Add higher-order List and Map contracts.**  
  **Work:** Inspect actual callback order, element/result restrictions, and Map equality/key/value relationships. Model the stored Map comparator's typed invariant, not merely its data fields. Leave unrepresented failure paths partial.  
  **Check:** `map` changes element type; `filter` requires Bool; `reduce` takes accumulator then element. Bad callbacks are checked even on NIL. Map equality ties both key inputs and its uncertainty taints an initially empty Map. Raw functions are not assumed admissible data elements. Generalized key/value restrictions survive subsequent updates. Do not modify library algorithms.

- [ ] **3.4 — Complete Option, Result, and Error contracts.**  
  **Work:** Encode fixed Error payloads, constructors/predicates, `option-case`, and conservative unwrapping. Distinguish make-ok's propagation from make-err's intentional Error consumption.  
  **Check:** `make-err 1` fails; `unwrap-ok` is not a total `Result(a) -> a`; guarded unwraps stay partial; `unwrap-err` has its audited Error output. Error cannot be coerced to Rat or an arrow. Aliases retain these rules.

- [ ] **3.5 — Audit pure rendering and the remaining value operations.**  
  **Work:** Finish scalar/restricted generic rendering; classify remaining value operations, including flatten/count/index cases. Inventory effectful print, completing its contract in Step 3.6. Review the complete value-contract set for missing Error alternatives before adding host signatures.  
  **Check:** Supported rendering returns String; direct/nested raw-function cases never receive universal safe signatures. Every completed entry has source and valid/invalid-domain evidence; unsupported entries have precise reasons. No runtime function detection or tag changes. Repair invalid seed assumptions and refresh dependent inference tests.

- [ ] **3.6 — Establish the four required I/O wrappers and print.**  
  **Work:** Verify stdout/read-line/read-file/write-file against wrappers, host branches, codec, and existing tests. Complete print from its rendering and stdout dependencies without changing runtime implementations.  
  **Check:** Catch String versus List(Byte) misuse; represent expected I/O failure as Result Err. Analyzing read-file never reads the program's requested data file. Separately test actual wrappers with isolated runtime resources. The complete Section 3.2 example now establishes all obligations without program execution.

- [ ] **3.7 — Classify raw host, TCP, HTTP, and exit.**  
  **Work:** Keep raw host explicitly unproved; audit remaining operations for numeric/value-dependent failures. Close all pending inventory entries as supported or specifically partial.  
  **Check:** Raw-host aliases and higher-order uses remain gaps. No invented nominal handles, String-returning read-file, new host operation, or successful-exit assumption. Every actual public export is accounted for; unsupported is not the same as absent.

- [ ] **3.8 — Close the combined boundary counterexamples.**  
  **Work:** Exercise partial outputs, higher-order use, callbacks, partial application, and the library's Error-absorbing continuations together.  
  **Check:** Possible Error cannot acquire a verified arrow type; an earlier gap cannot swallow a later nominal mismatch; ordinary user lambdas do not inherit library absorption semantics. Existing runtime outputs remain unchanged. Independently audit source coverage versus trusted contracts rather than claiming to have inferred the library's internals.

**Checkpoint 3 — Contract and trusted-boundary gate.** Review complete signatures against both success and failure domains, including data restrictions, callback order, and source/effect separation. Run contract/non-execution regressions, affected library/host/codec tests, full suite, and gates. Ordinary supported I/O is not unknown merely because it is effectful; partial wrappers/raw host are not complete merely because a return shape is desired. No refinements, unions, or effect system are needed to close this gate.

### Phase 4 — Deliver exact reports and the real checking command

**Purpose:** expose the established backend without changing ordinary execution.  
**Prerequisites:** Checkpoint 3.

- [ ] **4.1a — Compute exact complete-source coverage and final status.**  
  **Work:** Finalize source-node and definition states from the established proof data, retaining all registered source obligations and the closed verdict precedence. Keep local self assumptions separate from external gaps.  
  **Check:** Exact-count fixtures cover literals/apps/list/let/lambdas, data definitions, nested/unused bodies, empty modules, and rounding traps. A bad call preserves its valid function's declaration count; an incomplete top-level expression prevents FULL PASS. A missing source ID, pending catalog entry, or unfinished solver item is operational failure, never silently excluded from the denominator.

- [ ] **4.1b — Render types, primary diagnostics, and bounded dependency explanations.**  
  **Work:** Render original file/line/column, enclosing binding/lambda, reason code, established expected/actual types, and one deterministic path per dependent definition. Separate conditional hints from verified signatures and output from computation.  
  **Check:** Golden reports are stable across repeated checks and preserve positions across CRLF/Unicode/tabs/comments/shadowing. Control characters in names/paths are escaped. Large alias graphs do not enumerate exponentially many paths. Reports never expose arbitrary internal exception text or imply that source coverage certifies the trusted library.

- [ ] **4.2 — Integrate `--check` with precise launcher and output failure handling.**  
  **Work:** Add the exact invocation, help text, embedded lazy-load reference if needed, exit mapping, and narrow boundary-vocabulary updates. Leave file/REPL dispatch unchanged. Finalize analysis before report emission and require successful emission/flush before exit 0.  
  **Check:** Real subprocesses via `racket runner/attalambda.rkt --check ...` verify 0/1/2 and 64/65/66/70. Missing/extra paths, duplicate/incompatible flags, and private injected source/frontend/internal faults map correctly. A broken report sink cannot return 0 or replay output. Do not add public failure-injection switches or import the auto-running launcher as the backend.

- [ ] **4.3 — Prove CLI non-execution, interruption, and repeated-run isolation.**  
  **Work:** Run the existing effect/divergence fixtures through the real CLI. Exercise a controlled interruption during analysis and a report-delivery failure separately. Reuse the backend twice in one test process to reveal stale state.  
  **Check:** No program output/input/file/network/history effect occurs, including invalid-late-form cases. Interrupted analysis returns 130, cleans owned resources, and emits no completed analysis report. Interrupted delivery is nonzero even if earlier report bytes exist. Do not demand impossible output retraction or disable cancellation around blocking writes. Inspect rendered diagnostics as well as structured results.

**Checkpoint 4 — User-facing gate.** Run report/CLI tests and affected existing interactive/file-mode tests, full suite, and gates. Existing `attalambda FILE.attl`, help/version, and REPL behavior remain intact. Review exact status/coverage semantics, escape handling, and untouched runtime behavior. The checker itself never executes the analyzed file.

### Phase 5 — Verify realistic use and the exact standalone candidate

**Purpose:** finish documentation, full corpus evidence, cold review, and a tested deliverable.  
**Prerequisites:** Checkpoint 4, authorized local commits, and the confirmed Linux consumer environment.

- [ ] **5.1 — Measure the complete existing example corpus.**  
  **Work:** Analyze every current public `.attl` example and the minimum acceptance fixtures. Record status and every gap/conflict reason, distinguishing intentional dynamic/error demonstrations from regressions.  
  **Check:** Every file is accounted for; supported fixtures fully pass and known limitations are accurately classified. Compare with the early pilot. Do not rewrite examples/signatures to improve percentages or silently skip files. No arbitrary coverage target is imposed.

- [ ] **5.2 — Document the feature and exact limitations.**  
  **Work:** Update relevant README/API/architecture/getting-started material with invocation, statuses, trust scope, inferred types, restricted data, and Error/variant limitations. Identify the capability as unreleased source/candidate work.  
  **Check:** Examples are exercised; links/commands exist. The public 0.8.0 binary is not claimed to contain the feature. No claim of termination, all-error freedom, erased runtime tags, or whole-runtime formal verification appears.

- [ ] **5.3 — Extend the real standalone consumer.**  
  **Work:** Add compact full/partial/fail/invalid/no-effect check-mode fixtures to the existing Linux consumer. Verify embedding of checker/frontend dependencies. Preserve other native builders/CI; change only acceptance inputs necessitated by the shared launcher.  
  **Check:** Static distribution tests cover new inputs. Consumer tests use the delivered executable and temporary source only: no Racket install, checkout, network fetch, or personal configuration. Dependencies/notices remain unchanged absent an evidenced necessity. Source-only tests cannot replace consumer acceptance.

- [ ] **5.4 — Review the final implementation afresh and freeze tested inputs.**  
  **Work:** Prefer independent read-only counterexample review; otherwise label self-review honestly. Inspect contract, diff, tests, scope, and unused abstractions. Correct evidenced findings narrowly.  
  **Check:** Address binding impersonation, gap laundering, Error alternatives, generalization/recursion, non-execution, and embedding. Each finding has a disposition; no minimum finding count. Run corrections' focused tests and the complete required suite on final inputs. Close a clean local source commit under project rules before building.

- [ ] **5.5a — Build the exact clean, local candidate.**  
  **Work:** Record the reviewed source SHA/runtime identity and build with the known builder into a fresh external directory, without `--allow-dirty`. Confirm that the checkout/ref was not changed by another process during preparation.  
  **Check:** Record archive SHA-256 and build evidence; every executable/embedded input belongs to the recorded source. Current-version metadata is explicitly labeled an unpublished feature candidate, not the public asset. Preserve unrelated work and existing candidate outputs rather than overwriting them.

- [ ] **5.5b — Verify the transferred standalone artifact.**  
  **Work:** Transfer that exact archive to the isolated consumer and run the extended new check-mode and existing file/REPL acceptance. Use only the delivered executable and synthetic source fixtures.  
  **Check:** Verify archive digest before/after transfer and record consumer environment plus `consumer_acceptance=passed`. Include complete, conflicting, partial, invalid-source, and no-effect fixtures. Any code/build-input or consumer-logic correction requires affected rebuild/retest evidence. Report unavailable native-platform checks separately; do not claim the current archive came from a later handoff-only commit.

- [ ] **5.6 — Close the handoff and clean owned resources.**  
  **Work:** Update the existing durable plan/handoff with Section 10's source, test, review, coverage, artifact, limitation, and authority records. Clean only owned probes/containers/transfers.  
  **Check:** Distinguish the tested build source from later record-only commits. Every acceptance item has evidence or an explicit blocker/next step. Preserve unrelated work and existing releases. No push, PR, merge, tag, asset replacement, or publication occurs under the default endpoint; follow project gate rules for any final record-only commit.

**Checkpoint 5 — Delivery gate.** Completion requires final-input tests, disposed review findings, full-corpus results, and the exact digest-identified standalone candidate's consumer evidence. Missing infrastructure/authority is reported as a blocked gate, never a passed check. Finish independent safe work, record the precise next step, and stop at the authorized local candidate.

## 9. Acceptance coverage

These are observable requirements, not a target assertion count. Each test group must run against the actual applicable layer; at least the command/status/non-execution groups also run against the delivered executable.

| ID | Required acceptance behavior | Implemented in | Required evidence |
| --- | --- | --- | --- |
| A01 | Existing normal file/REPL behavior, pure terms, tags, Error propagation, and host authority stay unchanged | 0.3a, 0.3b, 1.1a, 1.1b, 1.2, 4.2 | Existing full suite; expanded purity; exact boundary checks; existing file/REPL subprocess and consumer tests |
| A02 | No annotations or source grammar additions; existing `.attl` syntax is accepted | 1.1a, 1.1b, 1.2, 2.5a, 2.5b, 2.6, 2.7, 2.8 | Frontend fixtures for every existing source sugar and declaration form |
| A03 | Check mode never evaluates user code or performs its effects | 1.3, 4.3, 5.5a, 5.5b | Actual input-position/output/marker-file/network observations; invalid-late-form and divergent fixtures; packaged executable |
| A04 | Binding-aware checking respects shadowing, hygiene, aliases, and forward dependencies | 1.2, 2.6, 2.9 | Real-expander fixtures, not a symbol-only mock AST |
| A05 | Type variables, schemes, and holes are different; unification is finite and isolated | 2.1, 2.2a, 2.2b, 2.3, 2.9 | Kernel equations, occurs-check, failed-component isolation, repeated independent runs |
| A06 | Unannotated identity/apply/compose and curried arithmetic infer usable types | 2.5a, 2.5b, 2.6 | Hand-derived expected schemes; independent uses of identity at different types |
| A07 | Ordinary `rec`, including finite-typed recursive values, checks without typing Y or executing recursion | 1.2, 2.7 | Factorial/sum fixtures; zero-source-argument rec; unchanged expanded lowering |
| A08 | Unsupported raw self-application is located; direct/mutual `def` recursion stays a source error | 2.7, 4.1a, 4.1b | PARTIAL versus invalid-source status fixtures with source locations |
| A09 | Concrete argument/return-shape conflicts produce FAIL, including in unused bodies | 2.5a, 2.5b, 2.8, 4.1a, 4.1b | Bad arithmetic, bad inferred-function call, Result-used-as-Rat, unselected bad branch |
| A10 | Every public binding has an audited supported or explicit partial contract | 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7 | Export inventory drift test; implementation locators; relevant valid/invalid-domain tests |
| A11 | List/Option/Result/Map parameters and callback relationships are preserved | 2.3, 3.2, 3.3, 3.4 | Element/callback/accumulator/key-value tests; no invented Pair or Error parameter |
| A12 | Error alternatives cannot be laundered into successful value or function types | 2.9, 3.4, 3.8 | unwrap/head/range-dependent cases; alias, higher-order and partial-application regressions |
| A13 | Raw functions and unknown contents do not become universally printable/tagged | 2.3, 3.5, 3.6 | Direct and nested raw-function cases; Error-consuming versus propagating operations |
| A14 | Four required I/O wrappers have exact shapes; raw host remains a gap | 3.6, 3.7 | Wrapper/host/codec source audit, isolated runtime contract tests, check-only fixtures |
| A15 | A gap taints dependent definitions and expressions, not independent checked code | 2.9, 4.1a, 4.1b | At least a three-binding dependency chain, a closure, an alias, and a higher-order case |
| A16 | Coverage includes all source bodies/expressions, excludes generated code/library implementations, and handles empty inputs | 4.1a, 4.1b | Exact-count tiny fixtures, data definitions, no-definition programs, empty file, rounded-percentage trap |
| A17 | Locations identify original file/line/column and enclosing function; output is stable and safely escaped | 1.1a, 1.1b, 1.2, 4.1a, 4.1b | Golden reports including CRLF, Unicode, comments, tabs, shadowing, and unusual identifiers |
| A18 | Exit codes and precedence match Section 3; partial is never exit 0 | 4.2, 4.3, 5.5a, 5.5b | Real CLI and standalone subprocess matrix, controlled internal error, interrupted analysis |
| A19 | Runtime/reader/path restrictions are not weakened; unknown new source locations still fail closed | 0.3a, 0.3b, 1.1a, 1.1b, 4.2 | Boundary negative tests, reader-extension and dotenv-path rejection, no new production import escape |
| A20 | Representative usefulness is checked early; the complete corpus receives an honest measured result, without a forced percentage | 0.3a, 0.3b, 2.5a, 2.5b, 2.9, 5.1 | Early supported/partial pilot, then per-file corpus report and gap reasons; no unreported skipped examples |
| A21 | Final standalone command works outside the checkout and without Racket installed | 1.4, 5.3, 5.5a, 5.5b | Clean-source archive, digest, transferred consumer receipt and new check-mode fixtures |
| A22 | Delivery can be resumed and ends at the authorized local state | 0.1, 5.6 | Updated handoff, exact next step or completion, source/artifact identities, cleanup and authority record |
| A23 | Source let generalizes without turning lambda parameters polymorphic; rec self assumptions discharge | 1.1b, 1.2, 2.6, 2.7 | Paired let/lambda fixture; captured-environment conflict; monomorphic recursive-call conflict; divergent rec check-only |
| A24 | First-class and aliased operations obey uniform static rules; success hints do not create false judgments | 2.5a, 2.5b, 2.8, 2.9, 3.2, 3.8 | if/cons aliases, homogeneous function-valued branches, heterogeneous conflicts, error-to-string of an unproved unwrap |
| A25 | No source obligations, catalog entries, or solver work silently disappear from completion | 1.1b, 3.7, 4.1a | Deliberately corrupt/missing ID and pending-contract tests; source accounting; no skipped top-level forms |
| A26 | Report delivery and cancellation preserve truthful process success without impossible atomicity | 4.2, 4.3, 5.3, 5.5b | Broken sink/flush, private fault injection, interrupted analysis, repeated-run state isolation; no success on interrupted delivery |

### 9.1 Minimum semantic fixture set

Add small separate fixtures rather than one large program whose first failure masks the others. Use source strings in trusted tests for intentionally malformed programs, following current test conventions.

**Established without annotations:** identity used at Rat and String; `(identity identity)`; `apply`; composition; `double`; a partially applied arithmetic function; a simple sequential let; a forward definition; factorial; a terminating recursive Rat sum; a finite-typed recursive value analyzed without evaluation; homogeneous List mapping with an established callback; Option case analysis; Result predicates; a function returning `div`'s Result; the four supported I/O wrapper types.

**FAIL under supported rules:** `add` with String, Bool used as Rat, a nominal data value used where an arrow type is required, a user function inferred to require Rat called with String, a filter predicate returning Rat, a Result passed directly to Rat arithmetic, heterogeneous List/common-branch contradictions, and a definite conflict in an unselected/unused source body. Confirm that `(div 1 0)` alone can be fully typed as Result(Rat): a represented Result Err is not a type conflict.

**PARTIAL rather than invented certainty:** raw `(lambda (x) (x x))`; an unrepresented empty-list or wrong-Result-variant outcome; raw-host use; a constructor use outside the checked data domain; unproved generic rendering; an indirect caller/alias/higher-order user of a gap. Include a correctly guarded unwrap and document why it remains partial in this first version. Heterogeneous List/branch contradictions instead belong in the FAIL fixtures, including their aliased forms.

**Invalid source rather than PARTIAL:** a missing identifier, malformed literal/form, bad header, unsupported reader directive, direct recursive `def`, and a forbidden mutual cycle.

**Counterexample combinations:** a concrete bad `add` inside a heterogeneous structure; an unproved first argument plus a known invalid second argument; a seemingly correct returned constant in a definition that contains an unchecked nested function; a function with an unproved captured dependency; a no-definition file with an invalid top-level application. These prevent a high coverage figure from masking unexamined code.

For full-pass terminating examples, separately run the ordinary evaluator in isolated runtime tests and check the observed values against the inferred contracts. Do not execute arbitrary user source as part of checking, or use these finite examples as proof of all possible executions.

### 9.2 Counterexample fixtures with fixed expectations

Use the seed-only rows in the early pilot; run List/Map, complete Error-library, and command/output rows at their corresponding Phase 3/4 gates and final acceptance. Earlier checkpoints must not invent a completed contract for a later-phase fixture.

Each row is a small fixture body beneath `#lang attalambda`, unless it deliberately tests invalid source. When a row contains multiple forms, keep them in one file. Do not combine unrelated rows into a file whose first failure masks later expectations. Assertions cover status, primary reason, and relevant names/locations, not incidental fresh variable spelling. These are proposed acceptance fixtures, not tests executed during this review.

| ID | Source body or exact test | Expected observation |
| --- | --- | --- |
| C01 | `(def identity x = x)` followed by `(identity 1)` and `(identity "s")` | FULL PASS; independently instantiated identity; no annotations |
| C02 | `(let id = (lambda (x) x) (if (id TRUE) (id 1) 0))` | FULL PASS; source let generalization retained |
| C03 | `((lambda (id) (if (id TRUE) (id 1) 0)) (lambda (x) x))` | FAIL; lambda parameter stays monomorphic; do not “fix” by rewriting source |
| C04 | `(def bad_capture g = (let f = (lambda (x) (g x)) (if (f 0) (f TRUE) FALSE)))` | FAIL; captured `g` variables are not generalized away through `f` |
| C05 | `(rec loop x = (loop x))` and separately `(rec loop = loop)` | FULL PASS of finite type constraints; check-only; never execute either fixture |
| C06 | `(rec bad n = (if (is-zero n) 0 (bad TRUE)))` | FAIL; recursive assumption is one monotype, not separately freshened at each self call |
| C07 | `(def choose = if)` followed by `(choose TRUE 1 "s")` | FAIL, like direct `(if TRUE 1 "s")`; not special PARTIAL |
| C08 | `(def put = cons)` followed by `(put 1 (list "s"))` | FAIL, like `(list 1 "s")`; same homogeneous-element equation |
| C09 | `(def choose = if)` followed by `((choose TRUE (lambda (x) (add x 1)) (lambda (x) (sub x 1))) 2)` | FULL PASS; choosing functions does not require a runtime Function tag |
| C10 | `(filter (lambda (x) 1) NIL)` | FAIL; a known wrong callback result is checked even though no element triggers it at runtime |
| C11 | `(error-to-string (unwrap-ok (div 1 0)))` | PARTIAL, not a String/Rat conflict derived from a speculative Rat success hint; runtime may return Error from unwrap |
| C12 | `(add (head NIL) "bad")` | FAIL plus an unrepresented-Error gap; known argument 2 is still checked |
| C13 | `(def extract = unwrap-ok)` | PARTIAL even unused; no invented verified success-only alias signature |
| C14 | `(def wrapped x = (lambda (ignored) (unwrap-ok (div x 1))))` | PARTIAL; a returned nested function cannot hide its unchecked body |
| C15 | `(def pack x = (some (list x)))` followed by `(pack (lambda (y) y))` | PARTIAL with unsupported data-domain reason; the nested variable restriction survives generalization |
| C16 | `(def double x = (add x x))` followed by `(double "s")` | FAIL while `double` itself retains its established Rat-to-Rat declaration |
| C17 | `(make-map (lambda (x y) (unwrap-ok (div 1 1))))` | PARTIAL; an initially empty Map cannot hide its unchecked stored comparator |
| C18 | `(unwrap-err (div 1 0))` | FULL PASS with Error result type, not a claim that FULL PASS prevents intentional Error values |
| C19 | `(stdout "must-not-run")` followed by an unbound name or malformed final form | Status 65; no emitted program text; the complete source must validate |
| C20 | A corrupted frontend payload omits a registered expression; separately a final catalog entry is pending | Status 70; never a misleading smaller denominator or successful empty analysis |
| C21 | Analyze C01, C07, then C01 again through the backend in one test process | The two C01 results agree exactly after stable display normalization; no stale substitutions/names/gaps |
| C22 | An ordinary full-pass fixture with a failing report output/flush; interrupt a separate analysis before result completion | Nonzero operational/interruption result; no provisional full-pass success, no report replay |

For C11, do not add variant/range refinements merely to make the example fully pass. For C17, do not use the incomplete callback's best-case Rat hint as an established result type; its output contract remains unproved. Once the referenced partial contracts can be modeled by a separately approved future feature, their expected outcomes may deliberately change with a documented reason.

**Accounting fixtures:** `(add 1 2)` has 4 source expression nodes; `(add 1 "bad")` has 3 independently established children out of 4 expressions; `(list 1 2)` has 3 nodes (one source sugar node, two literals); `(let x = 1 x)` has 3 (one let, its initializer, its body reference); `(lambda (x) x)` has 2 (lambda and body reference). `(def identity x = x)` contributes one definition and one expression (its body reference); the implicit lambda and binder header add no denominator entries. Empty valid source has zero denominators displayed as `n/a`. These counts are independent of generated unary applications and encoded literal size.

**Same-feature diagnostic invariants:** adding an independent bad top-level expression cannot turn an existing FAIL/PARTIAL file into FULL PASS; adding unused source with a gap cannot be silently excluded; reordering independent acyclic declarations preserves verdict and coverage; uniform binder renaming preserves typing except for displayed names/positions. Tests of these properties use small source fixtures and the existing checker, not a new equivalence-testing framework.

## 10. Delivery record and maintainability

### 10.1 Required final handoff

The implementation handoff must identify:

- Actual branch, base revision, final tested source revision, workspace state, and whether local commits were made.
- Exact environment, dependency preparation, test commands, exit results, and evidence locations; distinguish baseline, focused, full-suite, structural, and real consumer evidence.
- Scope of independent review versus self-review, findings, corrections, and unresolved issues.
- Contract-inventory completeness, the measured example-corpus results, and known V1 coverage limitations.
- Exact candidate artifact and SHA-256, build source, build runtime, consumer environment/result, and any unavailable platform checks.
- Meaningful deviations from this document and their supporting tests.
- Cleanup performed and the final authorization state: implemented/tested/reviewed/packaged are distinct from pushed/PR-created/merged/published.
- The first unfinished step and smallest required owner action if a real blocker remains.

Do not label a later documentation-only commit as the source of an earlier archive. Do not claim the current artifact is published or replace existing release evidence with this milestone's local candidate evidence.

Keep one final build identity and one delivery-record identity rather than chasing a self-referential “receipt commit contains its own hash” loop. After consumer success, a later handoff-only commit can cite the build SHA and artifact digest; record its own final Git identity in the external handoff response or existing local receipt convention. Preserve the artifact verified at the earlier SHA. Any change to executable code, embedded inputs, build scripts, or consumer acceptance logic requires the affected build/consumer checks again. A record-only change must not be presented as though the earlier archive contains those later bytes.

### 10.2 Extension seams to retain, without implementing later features

Keep the type algebra, source analysis view, inference result, and report independent of CLI formatting. Keep trusted contracts and their unsupported reasons in one auditable place. Preserve binding identity and original source spans throughout.

These boundaries should allow later annotations to add expected-type obligations, later variant/nonempty/range refinements to replace particular gaps, and later type forms to extend the algebra without changing the evaluator. Basic rank-1 schemes are already included; higher-rank polymorphism, polymorphic recursion, recursive types, and richer heterogeneous data remain separate features with their own feasibility and soundness work. Supporting `rec` now does not mean that recursive *types* or polymorphically recursive calls are supported; those are different features.

Do not promise those future extensions are trivial. Do not prebuild their syntax or a configurable general-purpose type-system framework now. A new mutable or differently typed host capability would require revisiting the inference assumptions, not merely adding a permissive signature.

### 10.3 Running after a check

Users may explicitly choose this ordinary two-command workflow:

```sh
attalambda --check program.attl && attalambda program.attl
```

The checker itself never launches the program. Because these are two invocations, normal execution reads the file again; the check applies to the snapshot analyzed, not to arbitrary edits made afterward. This is not an atomic checked-execution guarantee. Do not add a second read or evaluator call inside check mode to imitate one.

## 11. Inspected sources and primary references

Repository source references below are pinned to the planning revision. Revalidate changed inputs during Phase 0. References to tests, scripts, and historical records identify inspected source, **not execution performed during planning**.

**[R1] Inspected head and released-source distinction.**
- [Planning head commit](https://github.com/kserrec/attalambda/commit/f6938b286329532230be210de0eaaa398286d38a).
- [Recorded merged/build source](https://github.com/kserrec/attalambda/commit/f309199baa170ba5b12ff6b18b60dc49c114a8a1).

**[R2] Current milestone/release record, opening and evidence sections.**
- [PLAN.md](https://github.com/kserrec/attalambda/blob/f6938b286329532230be210de0eaaa398286d38a/PLAN.md).
- Open PRs were queried through the GitHub connector with `state=open` on 2026-09-17 and returned an empty list. This is a dated observation, not a permanent repository invariant.

**[R3] Governing instructions and canonical-contract precedence.**
- [AGENTS.md](https://github.com/kserrec/attalambda/blob/f6938b286329532230be210de0eaaa398286d38a/AGENTS.md).
- [Specification index](https://github.com/kserrec/attalambda/blob/f6938b286329532230be210de0eaaa398286d38a/docs/specifications/README.md).
- [Absolute lambda-purity addendum](https://github.com/kserrec/attalambda/blob/f6938b286329532230be210de0eaaa398286d38a/docs/specifications/02-type-tags-and-absolute-lambda-purity.md), including Error-absorbing continuation and amendment rules. Phase 0 also requires reading the other two canonical documents in full.

**[R4] Surface expansion, dependencies, literals, and recursion.**
- [lang/expander.rkt](https://github.com/kserrec/attalambda/blob/f6938b286329532230be210de0eaaa398286d38a/lang/expander.rkt): `language-module-begin`, definition/dependency helpers, `language-rec`, `language-sugar-expression`, and literal lowering.

**[R5] Restricted input and launcher.**
- [runner/source-file.rkt](https://github.com/kserrec/attalambda/blob/f6938b286329532230be210de0eaaa398286d38a/runner/source-file.rkt): `inspect-source-file`, `validated-source`, and source-error mapping.
- [runner/source-reader.rkt](https://github.com/kserrec/attalambda/blob/f6938b286329532230be210de0eaaa398286d38a/runner/source-reader.rkt): `parse-source-buffer` and reader parameterization.
- [runner/attalambda.rkt](https://github.com/kserrec/attalambda/blob/f6938b286329532230be210de0eaaa398286d38a/runner/attalambda.rkt): CLI dispatch, embedded version, source validation, and `run-source`.

**[R6] Existing module/session preparation includes evaluation.**
- [runner/session.rkt](https://github.com/kserrec/attalambda/blob/f6938b286329532230be210de0eaaa398286d38a/runner/session.rkt): `prepare-entry`, `evaluate-entry`, module declaration transfer, and source-file loading.

**[R7] Public API contracts and limitations.**
- [docs/API.md](https://github.com/kserrec/attalambda/blob/f6938b286329532230be210de0eaaa398286d38a/docs/API.md): syntax/values; List callbacks; Rat; Option/Map/Result; rendering; I/O and line input.

**[R8] Representative implementations supporting the static/runtime distinction.**
- [core/option.rkt](https://github.com/kserrec/attalambda/blob/f6938b286329532230be210de0eaaa398286d38a/core/option.rkt): re-read in revision 3 for first-class `option-case`, branch selection, and Error handling.
- [core/map.rkt](https://github.com/kserrec/attalambda/blob/f6938b286329532230be210de0eaaa398286d38a/core/map.rkt): re-read in revision 3 for the stored equality callback and persistent Map representation.
- [core/typed-rat.rkt](https://github.com/kserrec/attalambda/blob/f6938b286329532230be210de0eaaa398286d38a/core/typed-rat.rkt): Result-valued division/power/reciprocal versus ordinary Rat arithmetic.
- [core/result.rkt](https://github.com/kserrec/attalambda/blob/f6938b286329532230be210de0eaaa398286d38a/core/result.rkt): constructors, fixed Error payload, wrong-variant Error returns.
- [core/typed-logic.rkt](https://github.com/kserrec/attalambda/blob/f6938b286329532230be210de0eaaa398286d38a/core/typed-logic.rkt): Bool validation and lazy selected-branch return.

**[R9] File wrapper validation and host injection.**
- [runtime/host.rkt](https://github.com/kserrec/attalambda/blob/f6938b286329532230be210de0eaaa398286d38a/runtime/host.rkt), `decode-utf8`, `perform-read-file`, `perform-write-file`, and line-input return encoding: revision 3 re-read confirms that expected invalid-text/file failures in those paths are Result Err, not invented success-only outputs. This is targeted inspection, not an audit of every host/codec contract.
- [effects/files.rkt](https://github.com/kserrec/attalambda/blob/f6938b286329532230be210de0eaaa398286d38a/effects/files.rkt): pure byte-list validation and injected host use. Reinspect the corresponding host/codec branches and additional wrappers during implementation; targeted revision review does not make every wrapper signature fully audited.

**[R10] Test execution and neighboring actual-expansion tests.**
- [run-all-tests.sh](https://github.com/kserrec/attalambda/blob/f6938b286329532230be210de0eaaa398286d38a/run-all-tests.sh).
- [tests/interactive-expansion-test.rkt](https://github.com/kserrec/attalambda/blob/f6938b286329532230be210de0eaaa398286d38a/tests/interactive-expansion-test.rkt): private source preparation, actual expansion, pure body checks, and lazy transport observations.

**[R11] Supported runtime and existing CI delivery checks.**
- [.github/workflows/tests.yml](https://github.com/kserrec/attalambda/blob/f6938b286329532230be210de0eaaa398286d38a/.github/workflows/tests.yml): Racket CS 9.3, isolated dependency correction, full suite, and transferred native consumers.

**[R12] Actual Linux packaging entry point.**
- [tooling/build-linux-distribution.sh](https://github.com/kserrec/attalambda/blob/f6938b286329532230be210de0eaaa398286d38a/tooling/build-linux-distribution.sh): approved versions, clean-source requirement, source staging, embedding, and external output directory. The executor must read the consumer script before modifying or executing it.

**[R13] Closed source classification and architectural boundaries.**
- [tooling/check-boundaries.rkt](https://github.com/kserrec/attalambda/blob/f6938b286329532230be210de0eaaa398286d38a/tooling/check-boundaries.rkt): exact launcher/frontend roles, source classifications, and production import restrictions.

**[T1] Racket Reference — Syntax Object Properties.**
- [Official documentation](https://docs.racket-lang.org/reference/stxprops.html). Relevant to opt-in metadata, property merging, origin tracking, and preservation. Validate the chosen mechanism on the repository's actual supported Racket version rather than assuming a documentation description proves the integration.

**[T1a] Racket Reference — Syntax Transformers.**
- [Official documentation](https://docs.racket-lang.org/reference/stxtrans.html): revision 3 reference check for binding-aware transformer/alias handling and trusted expansion. Use the actual target-runtime probe; an unversioned manual is not proof of embedding behavior on the supported installation.

**[T2] Racket Reference — Syntax Object Content.**
- [Official documentation](https://docs.racket-lang.org/reference/stxops.html). Relevant to source/line/column/span information and binding-sensitive syntax handling. Preserve syntax objects until the analysis view has captured the information it needs; do not discard context with premature `syntax->datum` conversion.

**[T3] OCaml Manual 5.3 — Polymorphism and its limitations.**
- [Official language documentation](https://ocaml.org/manual/5.3/polymorphism.html). A concrete precedent for separating ordinary inferred polymorphism, monomorphic recursive assumptions, polymorphic recursion, and higher-rank limitations. Revisited during revision 3. OCaml is not a dependency or a specification of AttaLambda's runtime; its mutation-related value restriction is not copied as a new AttaLambda feature.

The planning format follows the supplied `spec-in-phases` skill. This document includes its own execution rules and acceptance criteria; the implementation agent does not need that attachment or the earlier conversation to understand the assignment.

### 11.1 Revision-review record and remaining evidence boundary

Revision 3 reviewed the supplied skill and complete prior spec; rechecked the unchanged remote head; re-read the cited targeted implementations; consulted the primary Racket/OCaml documentation above; and checked this document for step IDs, acceptance mappings, examples, references, and contradictory verdict instructions. These are **planning checks**, not executed language tests or an independent implementation review.

Material corrections are the uniform finite-conflict classification; explicit source-level let/rec preservation; solved-environment generalization; nested data restrictions and Map comparator invariants; partial-reference/hint rules; complete source accounting; implementable interruption/reporting semantics; smaller dependency-ordered steps; and concrete adversarial acceptance fixtures. No new type forms, syntax, runtime capabilities, project system, optimizer, or release operation was added.

The unresolved evidence requirements are intentional execution gates, not hidden product choices: the actual source-view/embedding probe, audited final catalog, implemented inference and counterexamples, unchanged full regression suite, and exact standalone consumer result. A source-contract contradiction found there must be surfaced honestly, never repaired by weakening the checker or enlarging the language without authorization.

## 12. Ready-to-use kickoff

Use this text only when actually assigning implementation:

> Implement revision 3 of `docs/optional-static-checking-spec.md` in AttaLambda. Use this complete revision instead of earlier drafts. Reconcile the actual checkout and read the governing project instructions first. Use one milestone branch and verified local phase commits, with isolated dependencies, tests, and builds. Resolve ordinary private implementation choices independently; follow the checkpoints, counterexamples, failure recovery, and resumption rules. Preserve all runtime semantics and existing work. Stop at the fully tested, reviewed, standalone-verified local candidate. This assignment is local-only even where the repository normally expects phase pushes: do not push, open a PR, merge, tag, replace release assets, or publish without separate authorization. If a genuine access, infrastructure, or contract blocker remains, finish independent safe work and report the exact blocked gate and next step; do not broaden the feature or manufacture a passing result.

If the file has not yet been placed in the repository, supply this Markdown file with that assignment and save it at the proposed docs path without overwriting a conflicting existing document. No implementation step is complete merely because it is described here.
