# Project rules

These rules apply to every change in AttaLambda.

## Authority

1. The three documents in `docs/specifications/` define the language.
2. The type-tag and absolute-purity addendum overrides weaker purity examples
   in the base specification.
3. The canonical-naming addendum overrides earlier naming examples.
4. `PLAN.md` controls implementation order but cannot override a
   specification.

Stop and surface a conflict rather than silently choosing a new language
design.

## Absolute object-language purity

- Production object-language computation may contain only variables, unary
  `lambda`, and application after macro expansion.
- Every lambda takes exactly one argument. Multiple arguments are represented
  by nested unary lambdas.
- Do not use Racket numbers, Booleans, pairs, lists, strings, characters,
  structs, vectors, hashes, exceptions, or control flow as object-language
  values or computation.
- Do not use host conditionals, pattern matching, arithmetic, equality, loops,
  mutation, or data access to decide object-language results.
- In `core/`, Racket is allowed only for modules, `#lang lazy`, and mechanical
  macro expansion. `effects/` follows the same rule and may invoke only its
  injected unary host argument.
- `runtime/codec.rkt` is the separately classified deterministic conversion
  exception. It may inspect validated representations and construct canonical
  ones, but it may not perform effects, mutate state, own a registry, or enter
  the object-language dependency graph.
- `runtime/host.rkt` is the single privileged exception. It alone defines and
  exports `host`, alone imports the codec in production, and may perform only
  the operations approved for the current completed phases.
- Readers, tests, and tooling may use the host facilities needed for their
  stated roles, but production computation must never depend on them.
- Readers may observe and format values with host data and control flow, but
  may not perform external effects, mutate state, own registries, or import
  upward from effects, runtime, language, tests, or tooling. Production
  modules must never depend on readers.
- Tests and tooling may use ordinary host facilities, but every Racket source
  must remain in a classified repository location and neither class may enter
  a production dependency path.
- No other production module may define or import a privileged binding,
  codec, dispatcher, port, path, socket, exception, or host collection.

## Representation invariants

- Church numerals are limited to the closed type tags (tag 3, formerly Nat,
  is permanently retired) and tiny fixed metadata explicitly required by the
  specifications, including Error kinds and argument positions. Never use
  them for ordinary numeric values.
- The only public number type is Rat: a reduced Int numerator over a
  positive binary Nat denominator, with positive `0/1` as the only zero.
  Private binary Nat magnitudes remain normalized most-significant-bit-first
  digit Lists where `[0]` is the only zero, and private Int is a sign plus
  magnitude with one zero. Neither Nat nor Int may become public again.
- List follows the explicit Michaelson-style representation. `NIL` is a
  List, distinct from false and zero, and every tail is a List.
- One generalized arbitrary-arity curried checker owns strict runtime typing.
  Never add `type-check2`, `type-check3`, or any arity-specific equivalent.
- An early Error must absorb exactly the function's remaining arguments
  through unary lambdas.
- Use Error for contract or invariant failure. Use Result Err for expected
  computational failure.
- Char holds binary values 0 through 255. String is a List of Char.

## Names and layers

- Public language names are canonical: `lambda`, `def`, `let`, `if`,
  and `cons` where specified.
- Public `if` is the strict typed conditional. Public `cons` is the proper
  typed List constructor.
- Internal raw operations use descriptive `raw-*` names; strict typed
  operations use `typed-*` names.
- Never add an underscore prefix solely to avoid a Racket binding.
- Resolve host collisions with module boundaries, renaming, and selective
  exports.

## Implementation discipline

- Follow `PLAN.md` in dependency order. For the active non-core refactor,
  complete and record one bounded Step at a time while continuing serially
  under Kyle's approval; close each Phase as one verified commit.
- Keep files small, dependency-oriented, and logically nested. Avoid
  abstraction layers without a demonstrated need.
- Prefer the minimal implementation that satisfies the current phase and its
  tests.
- Study `all_the_lambdas` for proven patterns and reusable code, but verify
  every borrowed choice against all three AttaLambda specifications.
  Do not import compatibility constraints, underscore-based public names, or
  representations superseded by this project.
- Do not add a dependency for a convenience that is safer and clearer to write
  directly. Racket's lazy evaluator is the intended backbone.
- Keep raw algorithms raw. Add strict wrappers only at the typed layer.
- Never use Graphify in this repository or create or update `graphify-out/`.
  Inspect the repository directly for codebase, architecture, and project
  questions.
- Standalone examples must use only `#lang attalambda` and its public
  surface. Test real filesystem examples only in isolated temporary
  directories and real network examples only on ephemeral loopback ports.
- Do not build unapproved post-milestone features: a parser beyond approved
  Lisp syntax, optimizer, compiler, records, JSON, or unrelated standard-
  library breadth.

## Tests and verification

- Add focused tests with every production unit.
- Test behavior, representation invariants, error propagation, partial
  application, and laziness where applicable.
- Maintain structural purity checks for forbidden host forms and non-unary
  lambdas in production modules.
- Maintain the separate boundary check for pure effects, deterministic codec
  conversion, the sole host definition/export/import path, and each phase's
  exact host capability allowlist.
- Maintain the repository-wide source inventory and the distinct reader,
  application, test, and tooling rules; unknown Racket source locations and
  production imports of support code must fail closed.
- Run focused tests while working, then the complete suite before each commit.
- Documentation must distinguish observed implementation from planned design.

## Git

- Work directly on `main` for ordinary phases. A multi-phase milestone that
  changes the released language lands on one milestone branch (as Milestone 4
  did on `milestone-4-rationals`) and merges to `main` only with Kyle's
  explicit approval.
- The active non-core refactor stays on `refactor/non-core-simplification`.
  Push verified Phase commits only to that branch. At final completion, stop;
  do not create its pull request until Kyle reviews the branch and approves it.
- Commit and push after each meaningful, verified phase.
- Keep commits narrow and descriptive.
- Do not leave generated Racket artifacts in Git.
