# AttaLambda — Preserve Callable Constraints Through Unknown Arguments

**Verification-first implementation specification**  
**Prepared:** September 18, 2026  
**Repository:** `kserrec/attalambda`  
**Inspected `main`:** `135263fe0774cf1233fe7e7e36e9e034fe94ec2f`  
**Release context:** 0.9.0; its recorded build/merge source is `0960a79ae797007da850a6d6f1c449482d333614`, not the later publication-record commit above.  
**Endpoint:** A verified source patch, or an evidence-backed finding that no production fix is needed. Publication is not included.  
**Status:** Specification only. The suspected defect has been traced in source, not reproduced by running AttaLambda during preparation. All implementation steps below remain unchecked.

## 1. Objective, baseline, and scope

Verify whether the optional static checker drops an independently knowable **callable-shape constraint** when a function parameter is applied to an argument whose type is unproved. If confirmed, repair that mechanism with the smallest coherent change, preserve the existing uncertainty rules, and retain regression tests that exercise the real checking command.

This is one diagnostic-correctness patch, not another typing milestone. A strong foundation here means a clear contract, a reproduced defect, a small repair, and evidence against nearby regressions—not a promise that the entire type system has been proved sound.

The inspected implementation already separates established value types from incomplete input obligations, performs rank-1 generalization and monomorphic self-recursion, and reports `FULL PASS`, `FAIL`, or `PARTIAL`. The previous independent review fixed related incomplete-callable cases. Reuse that machinery rather than introducing a second inference path. [R2–R5]

The relevant source was inspected through GitHub; the remote head was rechecked while preparing this document. Local changes, unpushed work, and the executor's toolchain are unknown. Reconcile them before writing. Historical passing CI is useful context, not evidence that this particular hypothesis is confirmed or fixed. [R1]

### Fixed change boundary

The expected production change is in the `application` logic of `runner/static/inference.rkt`. Reuse existing tests, especially `tests/static-incomplete-callables-test.rkt` and the existing CLI harness. A small neighboring change is acceptable only when a reproduction demonstrates it is necessary for the same defect.

Preserve source syntax, runtime tags, ordinary execution, laziness, runtime type checks, library contracts, host permissions, frontend binding identities, and the existing verdict/exit-code contract. Do not add ADTs, refinements, literal metadata, effect checking, a plugin interface, new flags, optimizations, or broad refactoring. Those earlier discussion topics are not part of this patch. [R2, R3, R6]

Do not bump `VERSION`, alter published release notes to imply a new binary exists, retag, replace assets, or publish 0.9.1 under this assignment. A subsequent expressly authorized release can package the verified fix using the existing release workflow.

## 2. The hypothesis to verify

Create these as **separate** temporary `.attl` files. Do not execute their programs; use `--check` only.

### C01 — Function use before numeric use

```racket
#lang attalambda

(def bad f =
  (add (f (unwrap-ok (make-ok 1))) f))
```

### C02 — Numeric use before function use

```racket
#lang attalambda

(def bad f =
  (add f (f (unwrap-ok (make-ok 1)))))
```

**Source-trace prediction, not an observed result:** C01 produces `PARTIAL`/2 without a `TYPE_CONFLICT`, while C02 produces `FAIL`/1 with a conflict. In C01, `unwrap-ok` has no established output type, and the inference branch that constrains a fresh function variable currently also requires an available argument type. That can leave `f` unconstrained until its numeric use. [R4]

The independent constraints in both examples are:

```text
f is used as an operator:             type(f) = Arrow(alpha, beta)
f is used as an argument to add:      type(f) = Rat
```

The missing type of the first call's argument does not make `Rat` and `Arrow(...)` compatible. This is a claim about V1's static rules, not a prediction that a lazy program must crash. The existing specification says that a supported conflict wins over incompleteness, while the gap remains visible. [R3]

### Required behavior if the hypothesis is confirmed

Both programs must produce `Static type check: FAIL`, exit status 1, and source-attributed `TYPE_CONFLICT` evidence. They must still report the `UNREPRESENTED_ERROR_ALTERNATIVE` associated with `unwrap-ok`. The affected `bad` definition must not acquire an established signature. No submitted program effect may run.

Do not require identical diagnostic order, wording, or coverage between different source arrangements. Require the same conflict-versus-partial classification for these independently contradictory constraints. This patch does not promise general order-independent diagnostics for arbitrary programs.

### Verification decision

Before implementation, record actual stdout, stderr, exit status, source revision, and the inference path for C01 and C02.

- **Confirmed:** The current implementation misses the independently derivable conflict. Retain a failing regression and proceed.
- **Already fixed:** Both cases behave correctly on newer source. Locate the responsible change, check the nearby cases below, and avoid a duplicate repair. Add missing regression coverage only when useful.
- **Hypothesis disproved:** Explain the governing rule or source-trace mistake. Do not force the predicted result through a code change. Close with evidence and useful tests, if any.
- **Verification blocked:** State the missing toolchain/access or contradictory contract. Complete safe independent inspection, but do not claim the issue or fix is verified.

An unexpected outcome permits a bounded probe of this application/unknown-argument path, not an open-ended hunt across the language. If a different defect appears, distinguish it from this hypothesis and explain whether it is the same repair surface before changing it.

## 3. Repair contract and recommended mechanism

**An unproved argument must not erase a known operator's callable requirement. It also must not become an established value merely because constraints were collected around it.**

Use the existing unifier, fresh-variable supply, diagnostic creation, and proof joining. When the operator has an established type variable but the operand has neither an established type nor usable input obligations, the recommended repair is to constrain that operator variable to an arrow with fresh domain/codomain variables.

Those variables describe a required function shape. They are not an inferred type for the unknown operand, an `Any` type, or a proof that the application returns successfully. If usable operand evidence already exists, preserve the current more precise path.

Do not apply this rule to an operator whose own value type is absent. An absent judgment is not interchangeable with an established fresh type variable. Preserve the existing input-obligation handling for incomplete callable operators.

The exact private implementation remains evidence-driven; changing a condition alone is not a sufficient acceptance criterion. Confirm the following invariants:

1. **No speculative success.** An application carrying an unproved child remains unproved; its `judgment-type` stays absent. An incomplete definition receives no established scheme. Existing coverage validation must continue rejecting established parents with incomplete children.
2. **Independent facts survive.** Record valid callable constraints on shared lexical variables so later uses, callers, and monomorphic recursive assumptions can expose real contradictions. A gap does not suppress an independently supported conflict.
3. **No invented payload facts.** Do not use `unwrap-ok`'s success hint as a verified return type, infer its variant, or guess the type of an unknown callee/result. Do not turn every partial application into a conflict.
4. **Existing inference rules remain intact.** Preserve captured-variable sharing, independent instantiation of generalized bindings, data-domain restrictions, the occurs check, and rollback of tentative substitutions after failed equations.
5. **Reports remain honest.** `TYPE_CONFLICT` makes the aggregate verdict `FAIL`; unsupported data domains and recursive-type requirements retain their existing partial classification unless a separate supported conflict exists. Independent valid definitions may still have signatures and checked coverage.

These constraints preserve the existing evidence model rather than broadening the type system. [R4–R7]

## 4. Focused regression contract

Use the existing inference/source-view test helpers and real CLI harness. The fragments below omit only `#lang attalambda`; each is a separate input unless multiple definitions appear in the same fragment. They are **specified targets**, not claimed measurements.

| ID | Program fragment | Required outcome after a confirmed repair |
|---|---|---|
| C01–C02 | The two complete examples above. | Both `FAIL`; conflict and unwrap gap remain visible; no `bad` signature. |
| C03 | `((lambda (f) (f (unwrap-ok (make-ok 1)))) 7)` | `FAIL`: the lambda's parameter is required to be callable, but receives `Rat`; preserve the gap. |
| C04 | `(def invoke f = (f (unwrap-ok (make-ok 1)))) (def alias = invoke) (alias 7)` | `FAIL` at the incompatible call; incomplete `invoke`/`alias` do not acquire established signatures. |
| C05 | `(def bad_capture f = (let invoke = (lambda (u) (f (unwrap-ok (make-ok 1)))) (add (invoke UNIT) f)))` | `FAIL` with gap: the captured `f` must not be generalized away from its numeric use. |
| C06 | `(rec bad f = (add (f (unwrap-ok (make-ok 1))) (bad 1)))` | `FAIL` with gap: compare the callable parameter requirement with the monomorphic self-call's Rat input; no recursive signature. |
| N01 | `(def invoke f = (f (unwrap-ok (make-ok 1))))` | `PARTIAL`, no conflict and no established definition signature. Callable evidence alone is not a completed proof. |
| N02 | `((head NIL) 1)` | `PARTIAL`, no invented conflict: the callee itself is unproved. |
| N03 | `(error-to-string (unwrap-ok (div 1 0)))` | `PARTIAL`, no fabricated Rat-versus-Error conflict from an unwrap success hint. |
| N04 | `(add 1 (unwrap-ok (make-ok "text")))` | `PARTIAL`, not a newly inferred payload conflict: V1 still does not establish the unwrap result. |
| N05 | `(def data_only f = (let held = (some f) (f (unwrap-ok (make-ok 1)))))` | `PARTIAL` with the unsupported data-domain obligation, not `FULL PASS`, internal failure, or a relabeled `TYPE_CONFLICT` absent another contradiction. |
| P01 | `(def identity x = x) (identity 1) (identity TRUE)` | `FULL PASS`; identity retains an equivalent of `forall a. a -> a`. |
| P02 | `(add TRUE 1)` | Existing ordinary `FAIL`, without needing a gap. |

For C03–C06, confirm the incompatible requirements from the existing rules before encoding assertions. If a result contradicts a governing contract rather than revealing this defect, document the discrepancy and resolve it without silently expanding scope or weakening an expectation to match current behavior.

Also retain the existing incomplete-callable negative controls, including `(((lambda (f) f) head) TRUE)`, without rewriting them merely to accommodate the repair. Run the existing generalization/capture, recursion, data-domain, substitution, and unification tests instead of duplicating their entire matrices. [R5, R7]

### Actual command and reporting evidence

Exercise C01, C02, N01, and P01 through `runner/attalambda.rkt --check`, not just `infer-expression`. Assert verdict, process status, expected diagnostic codes, and empty stderr for normal completed reports. For C01/C02 verify the absent `bad` signature and valid source locations. Do not assert arbitrary fresh-variable names or made-up coverage totals.

Include a CLI fixture with a top-level `(stdout "CHECK-MUST-NOT-RUN")` before the contradictory definition. Checking must report the static conflict without emitting that marker. Retain the existing broader file/input/network/non-execution tests; do not add new external services for this patch. [R8]

Keep a passing independent definition beside one bad definition in a regression. Verify that the good definition retains its signature while the file fails. This catches accidental whole-file invalidation.

## 5. Execution rules

Use a supported, isolated **Racket CS 9.3** environment with the repository's reviewed dependency corrections. Read the preparation tooling before running it; modify only an agent-owned installation/container. Do not touch the owner's normal runtime or install new project dependencies for this patch. A missing authorized test environment is an early blocker, not grounds to claim source tracing is an executed test. [R3, R9]

Read current `AGENTS.md`, the active opening of `PLAN.md`, applicable canonical specification amendments, and the affected code/tests. Preserve newer or unrelated work. Do not reset, stash, clean, force-push, inspect dotenv/credential contents, use Graphify, or run the example scripts against the owner's files or services.

This document is a planning artifact, not permission to mutate the repository. Once assigned for implementation, follow that assignment and the repository's Git rules. The inspected rules use `main` for ordinary phases and require a full suite before each commit. This plan deliberately contains **one implementation phase**, so temporary probes, failing regressions, and intermediate checkpoints do not require separate commits. Commit/push only when authorized by the implementation assignment and governing rules; merge/publication authority is separate. [R2]

Choose routine private details independently. If a step grows beyond one focused change-and-check unit, split it into stable lettered substeps in `PLAN.md` before proceeding; retain the same contract. Stop dependent work on failure, reduce the counterexample, repair the responsible unit, and refresh affected checks. Do not remove checks or enlarge timeouts to get green results.

Record progress concisely using `PLAN.md`/`HANDOFF.md`: baseline, decision, completed IDs, meaningful deviations, exact checks/results, and next unfinished step. Preserve historical release records. On resumption, inspect the actual branch/diff and evidence before continuing; do not blindly repeat external actions. Keep temporary probes/logs outside the checkout and clean up only agent-owned resources.

## 6. Phase 1 — One verified diagnostic-correctness patch

**Purpose:** Establish the actual defect before repairing it, then close the narrow change with regressions, review, and final-source evidence.  
**Prerequisites:** Authorized implementation workspace and supported isolated toolchain; no new release permission is presumed.

- [ ] **1.1 — Establish a trustworthy working baseline.**  
  **Work:** Read governing instructions; record actual branch/HEAD and existing changes. Reconcile newer work with the inspected revision. Check the isolated runtime and run the existing focused baseline below. Capture all five public example reports with `--check` before editing, using consistent source paths for later comparison.  
  **Check:** Runtime preparation check and focused baseline pass, or any pre-existing failure is isolated and recorded before dependent work. No example is executed.

  ```bash
  racket tooling/prepare-racket-runtime.rkt --check

  baseline_tests=(
    tests/static-incomplete-callables-test.rkt
    tests/static-bindings-inference-test.rkt
    tests/static-recursion-test.rkt
    tests/static-unification-test.rkt
    tests/static-substitution-test.rkt
  )
  raco make "${baseline_tests[@]}"
  raco test "${baseline_tests[@]}"
  ```

- [ ] **1.2 — Produce reproduction evidence and a go/no-go decision.**  
  **Work:** Write C01/C02 in an owned temporary directory. Run each through the real `--check` path; inspect the corresponding backend proof state using existing helpers. Trace why the callable constraint is retained or lost. Classify the outcome using Section 2 before changing production code.  
  **Check:** Recorded actual outputs/statuses and a rule-based explanation establish a missed constraint, an already-fixed issue, a disproved hypothesis, or a genuine blocker. An expected nonzero static verdict must not be confused with a failed test harness.

  The known invocation is:

  ```bash
  status=0
  racket runner/attalambda.rkt --check "$PROBE_DIR/call-first.attl" \
    >"$PROBE_DIR/call-first.stdout" 2>"$PROBE_DIR/call-first.stderr" || status=$?
  printf 'call-first status=%s\n' "$status"
  ```

  Allocate `PROBE_DIR` using the executor's existing temporary-directory practice. Repeat for the numeric-first input. Never omit `--check`.

  **Early gate — Hypothesis established or retired.** A confirmed missed diagnostic permits Step 1.3. An already-fixed/disproved issue permits only useful regression/evidence work, review, and closure; do not invent a production fix. Record repair-only steps as not applicable with evidence, not as executed. A material unsupported assumption must be resolved before dependent work.

- [ ] **1.3 — Repair the confirmed constraint loss with direct regressions.**  
  **Work:** Add the C01/C02 backend regressions to the existing focused test file and observe their failure on the unfixed baseline. Make the smallest implementation change satisfying Section 3. Keep fresh placeholders private and incomplete judgments incomplete.  
  **Check:** The new regression fails for the intended reason before the fix and passes afterward; C01/C02 both expose the conflict and retain the gap. Existing incomplete-callable tests, unification tests, and substitution tests pass after rebuilding their bytecode. No runtime, public API, or library-contract changes appear in the diff.

- [ ] **1.4 — Pin the nearby boundaries and real CLI behavior.**  
  **Work:** Add the remaining focused cases in Section 4 using existing helpers. Reuse the CLI fixture machinery for the specified end-to-end cases and marker check. Assert absence of speculative signatures, correct gap classification, and preservation of an independent good definition.  
  **Check:** Run all static test modules with refreshed dependencies. Every new expectation has a source-rule explanation; existing negative controls remain intact. All covered cases complete through the normal summary validator without internal status 70.

  ```bash
  static_tests=(tests/static-*-test.rkt)
  raco make "${static_tests[@]}"
  raco test "${static_tests[@]}"
  ```

  Reuse existing source files where practical. If a necessary private helper changes a pinned structural inventory, update only that exact authorized inventory and its tests—never weaken the gate globally.

- [ ] **1.5 — Resolve a fresh, focused review.**  
  **Work:** Obtain a read-only reviewer when one is available; otherwise perform and label a fresh self-review. Review the contract, actual diff, and tests, specifically challenging: callable evidence versus absent operator types; speculative return-type leakage; captured/generalized variables; monomorphic recursion; data restrictions and failed-substitution rollback. Ask for reproducible findings, not a required finding count.  
  **Check:** Each finding is reproduced and fixed or dismissed with evidence. A reviewer-requested correction reruns affected tests. Record the review scope and outcome accurately. Add a concise patch note to the current handoff explaining the verified behavior and limits; do not overwrite the historical 0.9.0 review with a new claim of formal soundness.

- [ ] **1.6 — Verify and close the actual final source.**  
  **Work:** Run `git diff --check` and the complete required suite on final implementation/test inputs. Recheck the five public example reports against Step 1.1; preserve their documented verdicts and established signatures, and investigate every other difference rather than chasing a coverage percentage. Complete the current plan/handoff record. Follow authorized commit/push policy for this one verified phase.  
  **Check:** The full script succeeds, including its dependency refresh and both structural gates. The final diff remains confined to the repair, focused regressions, and necessary records. If a push is authorized and performed, observe the actual resulting head's CI and record any unavailable/pending jobs honestly. Do not claim a distributed binary is patched just because source tests or a source commit passed.

  ```bash
  git diff --check
  ./run-all-tests.sh
  ```

  The complete script already runs `tooling/check-purity.rkt` and `tooling/check-boundaries.rkt`; do not duplicate expensive gates without a reason. Refresh affected evidence after any subsequent executable/test change. Identify record-only changes separately from the tested source snapshot.

**Checkpoint 1 — Verified source-patch endpoint.** Close only with a confirmed-and-fixed defect or an evidence-backed no-fix disposition, the required regression results, a resolved review, and final checks on identified inputs. Any real failing gate remains open. Missing commit/push/CI authority or infrastructure is reported separately from implementation correctness. There is no release, tag, asset replacement, version bump, or second typing feature hidden in this checkpoint.

## 7. Acceptance coverage

| Requirement | Steps | Evidence |
|---|---|---|
| Verify before fixing; permit honest no-fix closure | 1.1–1.2 | Current revision, actual C01/C02 results, traced constraints, decision. |
| Recover independently supported callable conflicts | 1.3–1.4 | C01–C06; regression failure before repair and success afterward. |
| Keep unknown results and unsupported domains unproved | 1.3–1.4 | N01–N05, existing negative controls, no speculative schemes or internal failures. |
| Preserve polymorphism, captures, recursion, and substitution integrity | 1.4–1.5 | C04–C06, P01, existing binding/recursion/domain/unification/substitution suites. |
| Correct CLI status, diagnostics, coverage, and no execution | 1.4 | Actual launcher cases, marker check, existing CLI-effect tests, summary validation. |
| Preserve the current language and useful independent evidence | 1.4–1.6 | Good-sibling regression, unchanged example verdicts/signatures, full suite and structural gates. |
| Keep change small, reviewable, and within authority | 1.5–1.6 | Focused diff/review, source-identity record, accurate Git/CI/release disposition. |

## 8. Handoff and ready-to-use kickoff

The final implementation handoff should answer these questions briefly:

- Was the suspected issue confirmed, already fixed, or disproved? What did C01/C02 actually do before and after?
- What constraint was missing, what changed, and why does the repair not establish unknown return types?
- Which source revision/diff was tested, which exact checks passed, and what did the focused review cover?
- What remains incomplete or unavailable? What was committed/pushed, and was exact-head CI observed? State explicitly that no new public release was made.

Retain the small regression tests in the repository. Preserve useful sanitized evidence outside the checkout and remove owned scratch resources. No extra reporting framework or large permanent probe corpus is required.

### Kickoff text

> Implement this specification through its verified-source-patch endpoint. First reproduce or disprove the suspected callable-constraint hole; do not assume the earlier review was correct. If confirmed, make the smallest repair, preserve honest PARTIAL results, add the specified regressions, complete the focused review and final gates, and follow the repository's authorized Git workflow. Do not add typing features, bump versions, or publish a release. Continue without routine questions; stop only for a genuine unresolved contract, access, safety, or authority blocker.

## 9. Inspected references

Unless otherwise noted, every repository locator below refers to `kserrec/attalambda` at **`135263fe0774cf1233fe7e7e36e9e034fe94ec2f`**. These are stable source locators, not claims that new tests were executed. The executor must reconcile subsequent changes.

- **[R1] Baseline and release distinction:** current `main` commit readback; opening of `PLAN.md`; `README.md`. The recorded 0.9.0 build is `0960a79ae797007da850a6d6f1c449482d333614`.
- **[R2] Governing workflow and purity rules:** `AGENTS.md`; current-versus-historical sections of `PLAN.md`.
- **[R3] Existing checking contract:** `docs/optional-static-checking-spec.md`, especially Sections 1 and 3.1; `runner/static/report.rkt`.
- **[R4] Suspected path and inference evidence:** `runner/static/inference.rkt`, especially `application`, `finish`, `input-obligations`, and `bind-judgment`; `runner/static/analysis.rkt`.
- **[R5] Previous related repair and regressions:** `docs/static-checking-independent-review.md`, H1; `tests/static-incomplete-callables-test.rkt`; `tests/static-bindings-inference-test.rkt`; `tests/static-recursion-test.rkt`.
- **[R6] Partial contracts and reporting integrity:** `runner/static/contracts.rkt`; `runner/static/coverage.rkt`; `runner/static/report.rkt`; `docs/static-checking-corpus.md`.
- **[R7] Constraint machinery:** `runner/static/unification.rkt`; `runner/static/substitution.rkt`; the existing static binding and recursion tests.
- **[R8] Real command/non-execution boundary:** `runner/static/command.rkt`; `runner/static/frontend.rkt`; `tests/static-cli-test.rkt`; `tests/static-cli-effects-test.rkt`.
- **[R9] Verification commands/toolchain requirements:** `run-all-tests.sh`; `README.md`; environment and command descriptions in `docs/optional-static-checking-spec.md`.

Authoring convention: the user's retrieved `SKILL(4).md`, **Spec in Phases**. Its execution discipline is incorporated here; the implementing agent does not need that file or the earlier conversation to use this specification.
