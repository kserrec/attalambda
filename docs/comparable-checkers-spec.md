# AttaLambda — `list-case` and a second, selectable static checker

**Implementation specification in phases**
**Prepared:** 2026-09-19
**Repository:** `kserrec/attalambda`, local checkout `~/Projects/attalambda`
**Inspected branch and revision:** `fix/diagnostics-robustness` at `bcee97e` (four commits ahead of `main` `ea889e5`; working tree clean at inspection). Published release: 0.9.0, build source `0960a79`.
**Endpoint:** A verified release candidate for 0.10.0 on one milestone branch, with the full test suite and both structural gates green and a cold review recorded. Merge to `main`, tag, archive build for publication, and GitHub release require Kyle's explicit approval and are not part of this specification.
**Status:** Specification only. No implementation step below has been executed. Every claim about the repository is from inspected source at the revision above; every claim about behavior after a change is a requirement, not an observation.

---

## 1. Objective, baseline, and endpoint

### 1.1 What this milestone delivers

Three additive features, chosen as the first visible step toward AttaLambda's stated direction: a pure unary untyped lambda core, a growing Lisp surface, and several optional static checkers that can score the same program under different type systems.

1. **`list-case`**, a public List eliminator with a complete static contract. It removes the most common reason real programs cannot reach `FULL PASS` today: every use of `head` or `tail` is a permanent unproved region because the empty-list Error is not represented in their types.
2. **Type-system selection inside the checker.** One value describing "which type system" is threaded from the launcher through analysis to the report, with the existing Hindley-Milner checker as the default and no behavior change for existing invocations.
3. **A second system, `simple`,** in which user `def`, `rec`, and `let` bindings are monomorphic while built-in contracts keep their audited polymorphic types. It is the existing inference engine with generalization switched off and one solution state shared across the whole file. Its purpose is comparison: the same file can pass under `hm` and fail under `simple`, and the report shows why.

Nothing in the runtime changes except the addition of one library function built from existing Church-encoded pieces. The object language remains variables, unary lambdas, and application. No function tag, host detection, annotation syntax, product type, or tagged-union facility is added; those are later milestones.

### 1.2 Baseline facts the design relies on

Inspected at `bcee97e`:

- **Runtime library shape.** Public `cons`, `head`, `tail`, `is-nil` are `typed-cons`, `typed-head`, `typed-tail`, `typed-is-nil` in `core/lists.rkt`, exported through `lang/expander.rkt` under renamed bindings (`HEAD`, `TAIL`, `IS-NIL`, `language-cons`) and re-exported with public spellings. A List is a tagged object whose payload is a pair; `NIL` is the canonical terminator from `core/errors.rkt`, recognized by `raw-list-is-nil` because its tail slot carries the Error tag. `raw-if` is Church-boolean selection, lazy on the unselected branch.
- **The eliminator precedent.** `typed-option-case` in `core/option.rkt` is the model: bubble an incoming Error with a frame naming the operation, reject a wrong tag with a TypeMismatch Error, otherwise select one branch lazily. Its runtime tests are in `tests/option-test.rkt`, including the unselected-branch laziness check via `delay` and the exact Error text `option-case(arg1 expected OPTION got BOOL)`. Function-name metadata comes from `define-function-name` in `core/function-names.rkt`.
- **Static catalog.** `runner/static/contracts.rkt` holds one `catalog` of `library-contract` rows: id, status (`complete`/`partial`), signature scheme, arity, gap code, reason, implementation locators, test locators. `option-case` is `forall a:data b. Option(a) -> (a -> b) -> b -> b`, complete. `tests/static-contracts-test.rkt` asserts the catalog equals the facade's exported value names and that every locator names a real definition and an existing test file. `docs/static-checking-contracts.md` mirrors the table (129 bindings: 106 complete, 23 partial).
- **Source view.** `lang/expander.rkt` exposes `language-analysis-builtins`, a compile-time list pairing each trusted binding identifier with its catalog label string. `lang/static-source.rkt` classifies each source reference by free-identifier equality against that list. A public value missing from the list makes the frontend fail with "resolved public binding has no catalog identity".
- **Inference and generalization.** `runner/static/inference.rkt` `bind-judgment` calls `generalize` (from `substitution.rkt`) for every established `let`/`def` initializer, producing a rank-1 scheme; references `instantiate` fresh copies. `runner/static/analysis.rkt` `analyze-view` infers each binding in dependency order, keeps only the resulting environment entry, and infers each top-level expression with `infer-expression source environment #:fresh fresh` and the default `#:initial empty-solution`. Solved states are not carried between bindings or expressions; that is sound today only because generalized schemes are closed.
- **Command and report.** `runner/static/command.rkt` `run-check` inspects the file, prepares the source view, calls `analyze-view`, `summarize-analysis`, `render-report`, and maps verdicts to exit 0/1/2. `runner/static/report.rkt` prints `Static type check: VERDICT`, a `Scope:` line, counts, then optional sections. `runner/attalambda.rkt` accepts exactly `("--check" FILE)` where FILE does not begin with `-`; help text lists the six invocation forms; `tooling/test-linux-distribution.sh` asserts that exact help text.
- **Gates.** `tooling/check-purity.rkt` scans every production module's expansion. `tooling/check-boundaries.rkt` classifies every Racket file; `runner/static/*` modules are classified by `tooling/static-boundary-contracts.rkt`, which lists for each module its exact imports, exports, and every identifier permitted in its source. A new module under `runner/static/` requires a new rule there and a new class name in the dispatch `case` in `check-boundaries.rkt` (currently listing `static-data … static-command`). `runner/attalambda.rkt` is pinned to exactly one `dynamic-require check-index 'run-check` occurrence.
- **Test runner.** `run-all-tests.sh` runs every `tests/*-test.rkt` with `raco test`, then both gates. HANDOFF.md records the full 0.9.0 gate taking about 30 minutes.
- **Release plumbing.** `tooling/build-linux-distribution.sh` enumerates approved `VERSION` values and their `info.rkt` projections (`0.9.0` ↔ `"0.9"`); a new version must be added there. Release notes live in `docs/releases/<version>.md`.
- **Governance.** `AGENTS.md`: the three documents in `docs/specifications/` define the language; adding a public name or launcher syntax is done by appending a dated amendment to the relevant documents and updating their SHA-256 hashes in `docs/specifications/README.md`; a milestone that changes the released language lands on one milestone branch and merges to `main` only with Kyle's approval; commit after each verified phase; leave no generated artifacts in Git.

### 1.3 Adjacent work

- The four bug-fix commits on `fix/diagnostics-robustness` are part of the intended 0.10.0 release. This milestone branches from that head.
- `PLAN.md` also records a pending "callable constraints through unknown arguments" patch on `main` (spec: `docs/static-checking-callable-constraints-patch-spec.md`), not yet started. It changes `runner/static/inference.rkt` `application`. This milestone does not touch that function. If the patch lands on `main` first, rebase the milestone branch onto it before Phase 6; if not, it is a separate later assignment.
- Deferred runtime items D1–D3 in `PLAN.md` (a raw function inside `cons`) remain deferred by design. Kyle confirmed on 2026-09-19 that no Function tag will be added; the static checkers are the guard.

### 1.4 What "done" means

- All Phase 0–6 steps checked with recorded evidence in `PLAN.md`.
- On the milestone branch: `./run-all-tests.sh` passes on the final revision, including both gates.
- The acceptance examples in §2.5 produce exactly the stated verdicts and exit statuses from `racket runner/attalambda.rkt`.
- `tooling/build-linux-distribution.sh` builds and `tooling/test-linux-distribution.sh` passes against that build in an isolated directory.
- A cold review by a fresh reader is recorded with its disposition.
- `HANDOFF.md` names the candidate revision and states that merge, tag, and publication await Kyle.

---

## 2. Behavior and design

### 2.1 `list-case`

**Public form.** `(list-case list cons-function nil-value)`. Argument order follows `option-case`: the list, then the function for the populated case, then the value for the empty case.

**Runtime behavior.**

| Input | Result |
| --- | --- |
| `list` is an Error value | That Error, bubbled with the frame `list-case`, argument position 1, expected type List. |
| `list` is not List-tagged | TypeMismatch Error rendered as `ERROR(list-case(arg1 expected LIST got <TAG>))`, following the `cons` and `option-case` wording. |
| `list` is `NIL` | `nil-value`. `cons-function` is not applied. |
| `list` is `(cons h t)` | `((cons-function h) t)`, curried. `nil-value` is not evaluated. |

Strict on the List argument, lazy on both branches, exactly like `option-case`. The callback's result is returned untouched; no Bool coercion or tag check applies to it. `list-case` is a chain of unary lambdas and supports partial application like every other builtin.

**Implementation.** In `core/lists.rkt`, add `typed-list-case` beside `typed-head`, built only from `raw-if`, `raw-is-type`, `raw-list-is-nil`, `raw-list-head`, `raw-list-tail`, `raw-object-value`, `raw-bubble-error`, `raw-make-type-mismatch-error`, and a new `list-case-function-name` from `core/function-names.rkt`. Mirror `typed-option-case` line for line; the only structural differences are the tag tested (`list-type`) and the two-argument callback. Export it from `core/lists.rkt`; in `lang/expander.rkt` import it as `[typed-list-case LIST-CASE]`, add `[LIST-CASE list-case]` to the public `rename-out`, and add `(cons #'LIST-CASE "list-case")` to `language-analysis-builtins`.

**Static contract.** One complete catalog row:

```
list-case : forall a:data b. List(a) -> (a -> List(a) -> b) -> b -> b
```

with variables `'(0 1)`, restricted `'(0)`, arity 3, implementation locator `("core/lists.rkt" typed-list-case)`, test locator `"tests/lists-test.rkt"`. The row is honest for every input because the empty case returns a caller-supplied value; no Error alternative is unrepresented.

**Observable static consequences.**

- `(rec sum xs = (list-case xs (lambda (h t) (add h (sum t))) 0))` establishes `sum : List(Rat) -> Rat` and the file is `FULL PASS`.
- The `head`/`tail` formulation of the same function remains `PARTIAL` with `UNREPRESENTED_ERROR_ALTERNATIVE`. Both behaviors are required; the contrast is the point.
- `(list-case NIL (lambda (h t) "s") 0)` is a `TYPE_CONFLICT` (branch results String vs Rat).
- `(list-case 1 (lambda (h t) h) 0)` is a `TYPE_CONFLICT` (Rat vs List).
- `(list-case (list (lambda (x) x)) (lambda (h t) h) 0)` remains unproved with `UNSUPPORTED_DATA_DOMAIN`, because `a` is data-restricted. Unchanged rule.

**Documentation.** One row in the "Bool and List" table of `docs/API.md`; one row and updated counts (130 bindings, 107 complete) in `docs/static-checking-contracts.md`; a dated amendment appended to `docs/specifications/01-greenfield-core-language.md` (List eliminator contract) and `docs/specifications/03-canonical-public-naming-and-host-isolation.md` (exactly one new public spelling, `list-case`), with hashes updated in `docs/specifications/README.md`.

### 2.2 Type-system selection

**One record, one place.** New module `runner/static/systems.rkt`:

```racket
(struct type-system (name generalize?) #:transparent)
(define hm-system (type-system "hm" #t))
(define simple-system (type-system "simple" #f))
(define (system-ref name) ...)   ; "hm" | "simple" -> type-system, else #f
(provide (struct-out type-system) hm-system simple-system system-ref)
```

Two fields are enough for this milestone. A future system whose built-in signatures differ (refinements, for example) would add a catalog field here; that is deliberately not done now, because both systems in this milestone share the audited catalog unchanged. Do not split `contracts.rkt`.

**Threading.** `analyze-view` gains `#:system` defaulting to `hm-system`. It passes the system to `infer-expression` (`#:system`), which passes `(type-system-generalize? system)` to `bind-judgment` as `#:generalize?`. `run-check` gains a second parameter, the system, chosen by the launcher. `render-report` gains the system and prints one additional line directly after `Scope:`:

```
System: hm
```

or `System: simple`. No other report text changes. Every existing test that calls `analyze-view` or `run-check` with the old arity keeps working through the defaults.

**Launcher syntax.** Three accepted spellings, each exactly two arguments:

```
attalambda --check FILE.attl          # same as --check=hm
attalambda --check=hm FILE.attl
attalambda --check=simple FILE.attl
```

`--check=<anything else>` is command misuse, exit 64, stderr diagnostic, empty stdout, like every other bad shape today. FILE still may not begin with `-`. Help text gains one line, `  attalambda --check=SYSTEM FILE.attl`, placed after the existing `--check` line, and the exact expected help text in `tooling/test-linux-distribution.sh` is updated to match.

### 2.3 The `simple` system

**Rule.** User bindings are monomorphic. A `def`, `rec`, or source `let` initializer's type is bound as `(scheme '() solved-type '())`: no quantified variables, so every reference shares the same type variables and unification forces one type for the whole file. Built-in contracts are unchanged: they are still instantiated fresh at each reference, so `NIL` can still be a `List(Rat)` in one place and a `List(String)` in another. Lambda parameters and the `rec` self assumption were already monomorphic.

This is the simply typed lambda calculus over a library of polymorphic constants, which is the standard way a simply typed checker treats a built-in library. The report and docs describe it as "monomorphic definitions", not as System F or as "no polymorphism anywhere".

**One solution state per file.** Because monomorphic types stay open, the solver state must persist. `analyze-view` under `simple` threads one `solution` through every binding (in dependency order) and every top-level expression: each `infer-binding` starts from the state left by the previous one, and each top-level `infer-expression` receives `#:initial` set to the current state and returns the next. Under `hm` the existing behavior (fresh `empty-solution` per top-level expression, closed schemes) is preserved exactly; do not change the `hm` path to share state, since that would alter nothing observable but would widen the change surface.

**Signatures reflect the final state.** After the whole file is analyzed, apply the final state to every established definition's type before it is displayed. Unsolved variables display as letters without `forall`, for example `identity : a -> a` when `identity` is never applied. Once applied, `identity : Rat -> Rat`.

**Conflicts are attributed where they arise.** In

```racket
#lang attalambda
(def identity x = x)
(identity 1)
(identity "text")
```

the third form's argument unifies `Rat` with `String`; that is a `TYPE_CONFLICT` located at line 4, and the verdict is `FAIL`. `identity` itself stays established with `Rat -> Rat`, because a failed equation never commits its tentative bindings (existing `unify` behavior). Under `hm` the same file is `FULL PASS` with `identity : forall a. a -> a`.

**Verdicts, counts, exit statuses** are computed by the unchanged `coverage.rkt` and `command.rkt` logic.

### 2.4 Change surface

| Area | Files | Nature |
| --- | --- | --- |
| Runtime library | `core/function-names.rkt`, `core/lists.rkt`, `lang/expander.rkt` | Add `list-case-function-name`, `typed-list-case`, export and public rename, catalog label |
| Static contract | `runner/static/contracts.rkt` | One new complete row |
| Static engine | `runner/static/systems.rkt` (new), `inference.rkt`, `analysis.rkt`, `command.rkt`, `report.rkt` | System record; generalize flag; state threading for `simple`; `System:` line |
| Launcher | `runner/attalambda.rkt` | Parse `--check=NAME`; help text |
| Gates | `tooling/static-boundary-contracts.rkt`, `tooling/check-boundaries.rkt` | New `static-systems` rule and class; vocabulary/import/export allowlists for every touched static module; expander export allowlist if enumerated |
| Tests | `tests/lists-test.rkt`, `tests/static-lists-test.rkt`, `tests/static-contracts-test.rkt`, `tests/helpers/static-acceptance.rkt`, `tests/static-cli-test.rkt`, `tests/static-report-test.rkt`, new `tests/static-systems-test.rkt`, `tests/static-simple-system-test.rkt` | Focused coverage per step |
| Docs | `docs/API.md`, `README.md`, `ARCHITECTURE.md`, `docs/static-checking-contracts.md`, `docs/static-checking-corpus.md`, `docs/specifications/01…`, `03…`, `docs/specifications/README.md`, `docs/releases/0.10.0.md` (draft), `PLAN.md`, `HANDOFF.md` | Contracts first, then reference, then records |
| Release plumbing | `VERSION`, `info.rkt`, `tooling/build-linux-distribution.sh`, `tooling/test-linux-distribution.sh` | `0.10.0` ↔ `"0.10"`; help text |

Not changed: `core/` beyond the two files above, `effects/`, `runtime/`, `readers/`, `macros/`, the reader, the REPL, `runner/static/{types,proof,substitution,unification,type-display,coverage,frontend}.rkt` except where a new import or vocabulary entry is unavoidable, and `application` in `inference.rkt`.

### 2.5 Acceptance examples

Each is a separate temporary `.attl` file. `--check` forms never execute the program. Locations are one-based line, zero-based column.

**E1 — `list-case` sum.** Source:

```racket
#lang attalambda
(rec sum xs = (list-case xs (lambda (h t) (add h (sum t))) 0))
(sum (list 1 2 3))
```

`--check` and `--check=simple`: `Static type check: FULL PASS`, exit 0, `sum : List(Rat) -> Rat` under both (`hm` shows no `forall` because the type has no free variables). Running the file with `(print (sum (list 1 2 3)))` prints `6`.

**E2 — `head` sum.** Source:

```racket
#lang attalambda
(rec sum xs = (if (is-nil xs) 0 (add (head xs) (sum (tail xs)))))
```

Both systems: `PARTIAL`, exit 2, two `UNREPRESENTED_ERROR_ALTERNATIVE` diagnostics in `sum`, no conflict. Unchanged from 0.9.0 apart from the new `System:` line.

**E3 — polymorphic reuse.** Source: the `identity` file from §2.3. `--check`: `FULL PASS`, `identity : forall a. a -> a`. `--check=simple`: `FAIL`, exit 1, one `TYPE_CONFLICT` at `4:0` (or the argument's column as the existing attribution rule places it; require line 4 and code `TYPE_CONFLICT`), `identity : Rat -> Rat` listed under inferred definitions, `Definitions: 1/1`.

**E4 — existing corpus unchanged under `hm`.** All five `examples/*.attl` produce the same verdicts, counts, and diagnostics as recorded in `docs/static-checking-corpus.md`, plus the `System: hm` line.

**E5 — runtime `list-case`.** Source:

```racket
#lang attalambda
(print (list-case (list 1 2) (lambda (h t) h) 0))
(stdout "\n")
(print (list-case NIL (lambda (h t) h) 0))
(stdout "\n")
(print (list-case 5 (lambda (h t) h) 0))
(stdout "\n")
```

Output, exit 0:

```
1
0
ERROR(list-case(arg1 expected LIST got RAT))
```

**E6 — launcher shapes.** `--check=simple FILE` and `--check=hm FILE` behave as above; `--check=` , `--check=HM`, `--check=fancy`, `--check=simple` with no file, and `--check=simple a.attl b.attl` all exit 64 with empty stdout and a stderr line containing `expected attalambda`.

### 2.6 Early probes

Run before the dependent implementation, each with a recorded pass/fail and decision.

- **P1 — shared solver state across top-level forms.** In a scratch test, call `infer-expression` twice on `(identity 1)` then `(identity "text")` with a monomorphic `identity` in the environment, passing the first call's returned state as the second call's `#:initial`. Question: does the second call report `TYPE_CONFLICT` and does `freeze` produce a `judgment` that `summarize-analysis` accepts? Pass → proceed with Phase 4 as designed. Fail because `infer-expression` cannot accept an externally supplied non-empty state cleanly → make the narrow adaptation of exposing the state parameter, still inside `inference.rkt`; do not restructure `analysis.rkt` beyond threading.
- **P2 — boundary gate demands for a new static module.** Add an empty `runner/static/systems.rkt` with the intended `provide`, run `racket tooling/check-boundaries.rkt`, and record every violation it reports. Question: is registering a new class in `static-boundary-contracts.rkt` and the `case` in `check-boundaries.rkt` sufficient, or does file discovery also need a change? Pass → follow the reported list in Phase 3. Fail with a violation no allowlist can express → stop and report; this would be a genuine blocker for a separate module, and the fallback is to define the record inside `command.rkt` and `analysis.rkt` without a new file.
- **P3 — help-text coupling.** Confirm by grep that the only places asserting the exact help text are `runner/attalambda.rkt` and `tooling/test-linux-distribution.sh` line 269, and that `tests/static-cli-test.rkt` only requires the substring `attalambda --check FILE.attl`. Record the result; it fixes the edit list for Phase 5.

---

## 3. Execution contract

**Authority.** The executor may create the milestone branch, implement, run tests and gates, build and test the distribution archive in an isolated directory, and commit and push the milestone branch after each verified phase. It may not merge to `main`, bump anything on `main`, tag, replace or publish release assets, or edit published release notes. Bumping `VERSION` to `0.10.0` on the milestone branch is in scope (Phase 6); it does not make a release.

**Branch.** Create `milestone-10-comparable-checkers` from `fix/diagnostics-robustness` at `bcee97e` (or its later head if Kyle has added commits; record the actual base). Work only there.

**Ordinary decisions.** Private names, test file organization, exact allowlist edits, and report wording within the stated lines are the executor's. Record each meaningful deviation in `PLAN.md`: reason, preserved contract, mechanism, validating check.

**Failure loop.** A failing focused test or gate stops dependent work. Reproduce the smallest failure, name the responsible unit, make one narrow correction, rerun that check, then rerun the phase's affected tests. Never disable a gate, loosen an allowlist beyond the identifiers actually introduced, widen a step's scope, or edit an existing test's expectation without evidence that the old expectation contradicts this specification or the governing specs. Separate baseline defects (present at `bcee97e`) from introduced regressions; report the former, fix the latter.

**Safety.** Do not run programs under `--check`. Do not run acceptance `.attl` files outside a scratch directory. Do not touch `~/.attalambda` history or any real network port. Leave `compiled/` out of Git. Clean up scratch files the executor created.

**Real blockers.** Stop and report only for: a gate violation no allowlist can express (P2 fail), a contradiction between this document and `docs/specifications/`, or a required change to `application` in `inference.rkt`. Report evidence, completed safe work, and the smallest owner action.

**Durable progress.** Phase 0 records this plan as the active plan in `PLAN.md` using the repository's Phase/Step convention. After every step, tick the box and record the exact command, the revision it ran on, and its result. After every phase, commit with a narrow message and push the branch. `HANDOFF.md` is updated only in Phase 6.

**Resumption.** Read `PLAN.md`, inspect `git status` and `git log` on the milestone branch, reconcile against recorded evidence, rerun the last recorded check if the tree changed, and continue from the first unticked step.

**Completion.** Phase 6's full suite and gates must run on the final revision, and the distribution test must run against an archive built from that same revision. Report anything unavailable as unavailable.

---

## 4. Phases and steps

Commands are run from the repository root with the project's Racket toolchain (the same one `run-all-tests.sh` uses). "Focused" means `raco test tests/<file>.rkt`. "Gates" means `racket tooling/check-purity.rkt && racket tooling/check-boundaries.rkt`.

### Phase 0 — Contracts and plan

Purpose: the governing documents authorize the new public name and launcher syntax before any code changes, per `AGENTS.md`.
Prerequisites: clean tree on the new milestone branch.

- [ ] **0.1 — Branch and baseline.**
  Work: create `milestone-10-comparable-checkers` from the current `fix/diagnostics-robustness` head; record base commit. Run `./run-all-tests.sh` once on the base.
  Check: suite and gates pass; record the run's count of test files and wall time in `PLAN.md` as the baseline.

- [ ] **0.2 — Specification amendments.**
  Work: append a dated "List Eliminator and Comparable Checkers Amendment (2026-09-19)" to `docs/specifications/01-greenfield-core-language.md` (the `list-case` contract of §2.1, the monomorphic-definitions system of §2.3 as checker metadata only, and the statement that the runtime is unchanged) and to `03-canonical-public-naming-and-host-isolation.md` (exactly one new public spelling `list-case`; launcher spellings `--check=hm` and `--check=simple`; `hm` and `simple` are launcher tokens, not AttaLambda identifiers). Update the three hashes and add a "before" paragraph in `docs/specifications/README.md` following the existing pattern. Save this document as `docs/comparable-checkers-spec.md` if not already present.
  Check: `sha256sum docs/specifications/0*.md` matches the README table; `git diff` shows only appended bytes in the three canonical files.

- [ ] **0.3 — Active plan.**
  Work: replace the top of `PLAN.md` with this milestone's phases and steps (this section, condensed), keeping the pending callable-constraints plan and history below.
  Check: `PLAN.md` renders; every step ID here appears once.

**Checkpoint 0 — Contracts committed.**
Commit `Authorize list-case and selectable static checkers` on the milestone branch and push. No production code has changed.

### Phase 1 — `list-case` at runtime

Purpose: the library function exists, behaves per §2.1, and is public.

- [ ] **1.1 — Function name and eliminator.**
  Work: `define-function-name list-case-function-name list-case` in `core/function-names.rkt` (provide it). In `core/lists.rkt`, add and provide `typed-list-case` per §2.1, mirroring `typed-option-case`.
  Check: `racket tooling/check-purity.rkt` passes (unary lambdas and application only). A scratch `raco test` expression applying `typed-list-case` to a two-element list, a callback returning the head, and a default returns the head.

- [ ] **1.2 — Runtime tests.**
  Work: extend `tests/lists-test.rkt` with: NIL selects the default; a cons list applies the curried callback to head and tail; the unselected branch is never forced (use `delay` raising, as `tests/option-test.rkt` does); an incoming Error bubbles with kind preserved; a non-List argument yields Error text `list-case(arg1 expected LIST got BOOL)`; the function is a unary chain (`procedure-arity` 1 at each stage, as the option tests check).
  Check: focused `tests/lists-test.rkt` passes; each new assertion fails when `typed-list-case` is temporarily replaced by `typed-head` (spot-check two, then restore).

- [ ] **1.3 — Public export.**
  Work: in `lang/expander.rkt`, import `[typed-list-case LIST-CASE]` from `core/lists.rkt`, add `[LIST-CASE list-case]` to the public `rename-out`, and add `(cons #'LIST-CASE "list-case")` to `language-analysis-builtins`. Run the gates and update any expander export allowlist the boundary gate reports.
  Check: E5 program prints the three expected lines with exit 0 via `racket runner/attalambda.rkt`. Gates pass. `tests/static-contracts-test.rkt` fails on the inventory equality until 1.4 lands; 1.3 and 1.4 are one change-and-check unit for commit purposes.

- [ ] **1.4 — Catalog row.**
  Work: add the §2.1 row to `runner/static/contracts.rkt` next to `option-case`. Update `tooling/static-boundary-contracts.rkt` vocabulary for `static-contracts` with the new identifiers/strings the gate reports.
  Check: focused `tests/static-contracts-test.rkt` passes (inventory equality, locator validity). Gates pass.

- [ ] **1.5 — API row.**
  Work: add `list-case list cons-function nil-value` to the "Bool and List" table in `docs/API.md` with the §2.1 wording.
  Check: the row's example matches E5 behavior.

**Checkpoint 1 — Runtime `list-case` with its catalog identity.**
Focused `tests/lists-test.rkt`, `tests/language-test.rkt`, all `tests/static-*-test.rkt`, and the gates pass. Commit `Add list-case eliminator` and push.

### Phase 2 — `list-case` static behavior

Purpose: the E1/E2 contrast and the conflict cases are demonstrated and tested, and the inventory document matches the catalog.

- [ ] **2.1 — Static tests.**
  Work: extend `tests/static-lists-test.rkt`: `(list-case (list 1) (lambda (h t) h) 0)` established with type `Rat`; E1's `sum` established with signature `List(Rat) -> Rat`; `(list-case NIL (lambda (h t) "s") 0)` conflict; `(list-case 1 (lambda (h t) h) 0)` conflict; `(list-case (list (lambda (x) x)) (lambda (h t) h) 0)` unproved with `UNSUPPORTED_DATA_DOMAIN`; E2's `head` sum still unproved with `UNREPRESENTED_ERROR_ALTERNATIVE`.
  Check: focused test passes.

- [ ] **2.2 — CLI fixture.**
  Work: add to `tests/helpers/static-acceptance.rkt` one established fixture (E1's definition) and one conflict fixture (branch mismatch) with their codes.
  Check: focused `tests/static-cli-test.rkt` passes, exercising the real launcher.

- [ ] **2.3 — Contract inventory doc.**
  Work: add the row to `docs/static-checking-contracts.md`; update the counts sentence to 130 bindings, 107 complete, 23 partial.
  Check: the table row matches the catalog string exactly as `scheme->string` renders it (verify with a one-line `racket -e` against `contract-ref`).

**Checkpoint 2 — `list-case` fully checked.**
All `tests/static-*-test.rkt`, `tests/lists-test.rkt`, and gates pass. E1 and E2 produce the stated verdicts from the launcher. Commit `Give list-case a complete static contract` and push.

### Phase 3 — Type-system selection plumbing

Purpose: a system value flows launcher → report with `hm` as default and zero behavior change for existing invocations.

- [ ] **3.1 — Probe P2.**
  Work: create `runner/static/systems.rkt` per §2.2; run the boundary gate; record every violation.
  Check: after adding the `static-systems` rule to `tooling/static-boundary-contracts.rkt` and the class to the dispatch `case` in `tooling/check-boundaries.rkt`, gates pass. If they cannot, stop per §3 blockers.

- [ ] **3.2 — Systems tests.**
  Work: new `tests/static-systems-test.rkt`: `system-ref` returns `hm-system` for `"hm"`, `simple-system` for `"simple"`, `#f` otherwise; the two records differ only in `generalize?`.
  Check: focused test passes.

- [ ] **3.3 — Thread the system through analysis and inference.**
  Work: `analyze-view` gains `#:system` (default `hm-system`); `infer-expression` gains `#:system`; `bind-judgment` gains `#:generalize?` and, when false, binds `(scheme '() solved-type '())` for both the established and the input-template paths. No caller passes `simple` yet. Update allowlists for `static-analysis` and `static-inference` (imports of `systems.rkt`, new keyword names).
  Check: entire `tests/static-*-test.rkt` set passes unchanged; gates pass.

- [ ] **3.4 — Report line and command parameter.**
  Work: `render-report` takes the system and emits `System: <name>` after `Scope:`. `run-check` takes `(run-check source-name system)`; `command.rkt` passes the system to `analyze-view` and `render-report`. Update `tests/static-report-test.rkt` expectations to include the new line; update `runner/attalambda.rkt` to pass `hm-system` for the existing `--check` shape (leave parsing of `--check=NAME` to Phase 5). Update allowlists for `static-report`, `static-command`, and the runner rule if the `dynamic-require` pin changes shape (it should not; keep one `run-check` occurrence).
  Check: `tests/static-report-test.rkt`, `tests/static-command-test.rkt`, `tests/static-cli-test.rkt` pass. E4: all five examples give the same verdicts and counts as `docs/static-checking-corpus.md`, differing only by the `System: hm` line (diff the reports).

**Checkpoint 3 — No-behavior-change refactor.**
Full `tests/static-*` set, `tests/runner-test.rkt`, and gates pass. Commit `Thread a selectable type system through static checking` and push.

### Phase 4 — The `simple` system

Purpose: monomorphic definitions with one shared solution state, per §2.3.

- [ ] **4.1 — Probe P1.**
  Work: scratch test as described in §2.6.
  Check: recorded pass, or the narrow adaptation chosen and recorded.

- [ ] **4.2 — Shared state under `simple`.**
  Work: in `analyze-view`, when `(type-system-generalize? system)` is false, thread one solution through `infer-binding` calls (start each from the running state, keep its `final-state`) and through top-level `infer-expression` calls via `#:initial`, and keep the last state. Under `hm`, keep the existing behavior exactly.
  Check: new `tests/static-simple-system-test.rkt`: E3's file yields `conflict` with a `TYPE_CONFLICT` problem whose location line is 4; the `identity` definition remains established.

- [ ] **4.3 — Final-state signatures.**
  Work: after analysis under `simple`, apply the final state to each established definition's scheme type before building `definition-result` (or in a final pass over results). Ensure `coverage.rkt` validations still hold (an established definition has a `scheme`, which `(scheme '() type '())` satisfies).
  Check: in the test, `identity`'s signature renders `Rat -> Rat` after E3's second form, and `a -> a` when the file contains only the definition. `summarize-analysis` accepts the result.

- [ ] **4.4 — Semantics tests.**
  Work: extend `tests/static-simple-system-test.rkt`: monomorphic `let` (`(let id = (lambda (x) x) (add (id 1) (string-length (id "s"))))` conflicts under `simple`, establishes under `hm`); builtins stay polymorphic (`(def a = (cons 1 NIL)) (def b = (cons "s" NIL))` establishes under both); `rec` still works (E1 establishes under `simple`); partial contracts still partial (E2 unproved under `simple`); data-restriction still applies; a conflict in one expression does not de-establish an independent definition.
  Check: focused test passes; `hm` results for the same texts are asserted alongside to pin the contrast.

**Checkpoint 4 — Two systems, same engine.**
All static tests and gates pass. Commit `Add the simple monomorphic-definitions system` and push.

### Phase 5 — Launcher, help, and reference docs

Purpose: users can select the system and read what it means.

- [ ] **5.1 — Probe P3 and parse `--check=NAME`.**
  Work: record P3's grep result. In `runner/attalambda.rkt`, accept a first argument matching `^--check(=(hm|simple))?$` with exactly one following FILE not starting with `-`; resolve the system via `system-ref`; keep exactly one `dynamic-require check-index 'run-check` occurrence. Add the help line. Update the runner allowlist in `check-boundaries.rkt` if new identifiers are flagged.
  Check: `tests/static-cli-test.rkt` extended with E6's misuse shapes (exit 64, empty stdout, `expected attalambda` on stderr) and a `--check=simple` run of E3 (exit 1, first line `Static type check: FAIL`, `System: simple` on line 3) and of E1 (exit 0). Passes.

- [ ] **5.2 — Distribution help text.**
  Work: update the exact expected usage string in `tooling/test-linux-distribution.sh` (the `check_captured_output` for `--help`) to include the new line.
  Check: the string equals `help-text` in the runner byte for byte (compare with a here-doc diff).

- [ ] **5.3 — Reference documentation.**
  Work: `docs/API.md` "Optional static checking": the three spellings, the `System:` line, a short "Type systems" subsection defining `hm` (unchanged 0.9.0 rules) and `simple` (monomorphic definitions, polymorphic built-ins, one shared solution, signatures reflect final state, unsolved variables shown without `forall`), and the E3 example with both reports abridged. `README.md`: usage line and one sentence. `ARCHITECTURE.md`: `systems.rkt` in the static-checking paragraph and table row. `docs/static-checking-corpus.md`: add the five examples' verdicts under `--check=simple` as a second table measured from the milestone branch, keeping the 0.9.0 table as history.
  Check: every command shown in the docs is run once and its output matches what the doc claims (record the revision).

**Checkpoint 5 — User-facing surface complete.**
`tests/static-cli-test.rkt`, `tests/runner-test.rkt`, gates pass. Commit `Select the static type system from the launcher` and push.

### Phase 6 — Release candidate

Purpose: a candidate Kyle can approve for merge and publication.

- [ ] **6.1 — Version plumbing.**
  Work: `VERSION` → `0.10.0`; `info.rkt` version `"0.10"`; add `0.10.0) expected_package_version="0.10" ;;` to `tooling/build-linux-distribution.sh`. Rebase onto `main` first if the callable-constraints patch has landed there (record the decision either way).
  Check: `racket runner/attalambda.rkt --version` prints `AttaLambda 0.10.0`; `tests/runner-test.rkt` passes.

- [ ] **6.2 — Release notes draft.**
  Work: `docs/releases/0.10.0.md` with the three features, the E1/E2 and E3 contrasts, the bug fixes from the base branch (summarize from its four commit messages), compatibility (all changes additive; `head`/`tail` unchanged; existing `--check` output gains one line), and the statement that the runtime is unchanged. Mark the publication paragraph as pending Kyle's approval; do not invent a URL or timestamp.
  Check: every claim in the notes maps to a step with recorded evidence.

- [ ] **6.3 — Full suite and gates.**
  Work: `./run-all-tests.sh` on the final revision.
  Check: passes; record file count, wall time, and revision in `PLAN.md`.

- [ ] **6.4 — Cold review.**
  Work: a fresh reader (a separate agent or Kyle) reviews the branch diff against this document and `AGENTS.md`, looking for reproducible counterexamples, allowlist over-widening, and purity leaks. Fix confirmed findings via the failure loop and rerun affected tests.
  Check: review disposition recorded in `PLAN.md` ("no issue found" is acceptable).

- [ ] **6.5 — Distribution build and isolated consumer test.**
  Work: `tooling/build-linux-distribution.sh` into a scratch directory; `tooling/test-linux-distribution.sh` against that archive per the script's own header instructions.
  Check: passes, including the updated help text and a `--check=simple` invocation if the consumer script exercises checking; record archive SHA-256 and source revision.

- [ ] **6.6 — Handoff.**
  Work: `HANDOFF.md`: candidate revision, base, what is implemented/tested/reviewed/packaged, what awaits Kyle (merge to `main`, tag `v0.10.0`, archive publication, release-notes timestamp/URL), and the exact commands to reproduce 6.3 and 6.5.
  Check: a reader with only `HANDOFF.md` and the repo can rerun the checks.

**Checkpoint 6 — Verified candidate.**
Commit `Prepare comparable-checkers release candidate 0.10.0` and push. Stop. Everything after this is Kyle's.

---

## 5. Acceptance coverage

| Requirement | Steps | Evidence |
| --- | --- | --- |
| `list-case` runtime semantics (§2.1 table) | 1.1, 1.2, 1.3 | `tests/lists-test.rkt`; E5 via launcher |
| `list-case` is pure unary lambda | 1.1 | `check-purity.rkt` |
| `list-case` public name and catalog identity | 1.3, 1.4 | `tests/static-contracts-test.rkt` inventory equality; frontend classifies it as `builtin` |
| Complete static contract; E1 `FULL PASS` | 1.4, 2.1, 2.2 | `tests/static-lists-test.rkt`; CLI fixture |
| `head` sum still `PARTIAL` (E2) | 2.1, 4.4 | static tests under both systems |
| Branch/tag conflicts and data restriction for `list-case` | 2.1 | static tests |
| System record and lookup | 3.1, 3.2 | `tests/static-systems-test.rkt`; gates |
| No behavior change under `hm` | 3.3, 3.4 | unchanged static tests; E4 report diff |
| `System:` line | 3.4, 5.1 | `tests/static-report-test.rkt`; CLI test line 3 |
| Monomorphic definitions and shared state (E3 `FAIL`) | 4.1–4.4 | `tests/static-simple-system-test.rkt`; CLI run |
| Built-ins remain polymorphic under `simple` | 4.4 | static test |
| Final-state signatures | 4.3 | static test rendering `Rat -> Rat` |
| Launcher spellings and misuse (E6) | 5.1 | `tests/static-cli-test.rkt` |
| Help text consistency | 5.1, 5.2, 6.5 | byte comparison; distribution test |
| Documentation matches behavior | 1.5, 2.3, 5.3, 6.2 | commands rerun during 5.3 |
| Governing specs amended and hashed | 0.2 | `sha256sum` vs README |
| Whole-repository health | 6.3 | `run-all-tests.sh` on final revision |
| Independent review | 6.4 | recorded disposition |
| Deliverable exercised | 6.5 | isolated consumer test on built archive |

---

## 6. Delivery and handoff

**Authorized final state.** Milestone branch `milestone-10-comparable-checkers` pushed, at a revision where 6.3–6.5 passed, with `PLAN.md` and `HANDOFF.md` recording revision, commands, results, review disposition, and archive hash. `main` untouched. No tag, no release, no asset.

**Deviations** are recorded in `PLAN.md` under the step where they occurred, with reason, preserved contract, mechanism, and check.

**Known limits, to state in docs and notes.** `simple` treats built-ins as polymorphic constants; it is not System F and does not remove polymorphism from the library. `head`, `tail`, and count-based List operations remain partial under both systems by design. A raw function inside a container remains unspecified at runtime and is excluded statically under both systems. No annotation syntax exists, so `simple` cannot be given a signature to check against; that is a later milestone. The `System:` line is the only report change; tools parsing 0.9.0 reports by line number must account for it.

**Cleanup.** Scratch `.attl` files, scratch build directories, and any temporary test scaffolding not kept in `tests/` are removed before Checkpoint 6. No `compiled/` directories are committed.

---

## 7. Kickoff instruction and references

**Kickoff.** On `~/Projects/attalambda`, create `milestone-10-comparable-checkers` from the head of `fix/diagnostics-robustness`, record the base commit, and execute `docs/comparable-checkers-spec.md` Phase 0 through Checkpoint 6 in order, recording each step in `PLAN.md` and committing and pushing after each checkpoint. Authority: implement, test, build and test the archive in a scratch directory, commit and push the milestone branch. Not authorized: merging to `main`, tagging, publishing, or editing published release notes. Stop after Checkpoint 6 and report the candidate revision; stop earlier only for a §3 blocker.

**Inspected sources (revision `bcee97e`).**
`AGENTS.md`; `PLAN.md`; `HANDOFF.md`; `ARCHITECTURE.md` (optional static checking section); `core/lists.rkt`; `core/option.rkt`; `core/function-names.rkt`; `core/typecheck.rkt`; `core/objects.rkt`; `core/pair.rkt`; `lang/expander.rkt` (imports, `rename-out`, `language-analysis-builtins`, `language-module-begin`); `lang/static-source.rkt`; `lang/static-data.rkt`; `runner/attalambda.rkt`; `runner/static/{command,frontend,analysis,inference,unification,substitution,types,proof,contracts,coverage,report,type-display}.rkt`; `tooling/check-boundaries.rkt` (class dispatch, static helper handling, runner pin); `tooling/static-boundary-contracts.rkt`; `tooling/check-purity.rkt` (header); `tooling/build-linux-distribution.sh` (version table); `tooling/test-linux-distribution.sh` (help assertion); `run-all-tests.sh`; `tests/{lists,option,static-lists,static-callbacks,static-contracts,static-cli,static-data-domain}-test.rkt`; `tests/helpers/static-acceptance.rkt`; `docs/API.md`; `docs/static-checking-contracts.md`; `docs/static-checking-corpus.md`; `docs/optional-static-checking-spec.md`; `docs/static-checking-callable-constraints-patch-spec.md`; `docs/small-lisp-sugar-spec.md`; `docs/specifications/README.md`; `docs/specifications/03-…md` (amendment style); `docs/releases/0.9.0.md`.

**Primary technical references.** Damas and Milner, "Principal type-schemes for functional programs" (1982), for the rank-1 generalization rule that `hm` implements and `simple` omits. Barendregt, "Lambda calculi with types" (1992), for the simply typed calculus and the lambda cube positioning used in `docs/API.md`'s "Type systems" subsection. Racket reference for `syntax-property`, `local-expand`, and `define-runtime-module-path-index`, as already used by the frontend and launcher.
