# Diagnostics and robustness fixes — active, branch `fix/diagnostics-robustness`

Kyle assigned the 0.9.0 diagnostics/robustness/safety specification (kept
outside the repository) on 2026-09-19: verify each reported issue on the
current revision, fix only the real ones with the smallest change, escalate
policy questions, no release. Work lands on `fix/diagnostics-robustness` off
main `ea889e5`; merge, tag and release need Kyle. The callable-constraints
patch below is a separate pending assignment.

## Phase 1 — verify, fix, gate

- [x] 1.1 Reproduce every item (Racket CS 9.3 in a disposable container over
  this checkout). Real: A1 a `#reader` body extension ran host code and a
  planted `compiled/<name>_attl.zo` replaced the source in file-run; A2 Ctrl+C
  printed a stack trace with status 1; A3 a nested `def` reported an
  expander-internal position; A4 control characters in a name reached stderr
  raw; A5 a duplicate `def` reported "unknown AttaLambda name"; A7 a closed
  stderr turned status 66 into 1; B2 a port could not be rebound right after
  shutdown. Not reproducing, dropped: C1 (`let`-bound `NIL` at two element
  types passed in twelve shapes: top level, inside `def` with and without
  parameters, inside lambda, nested `let`, with `len`, `cons`, `list`, `add`)
  and B3 (the inner fallback code applies only to contract exceptions).
- [x] 1.2 Fix A1: `lang/reader.rkt` reads the module body with the same
  locked reader as `--check` and `:load`; `run-source` compiles the source
  file itself from source, never from a compiled file beside it. A2: a break
  prints one line and exits 130. A3/A4: `run-source` shares the frontend's
  provenance walk (`source-syntax`, now in `runner/source-file.rkt`) and the
  diagnostics escaping. A5: the expander rejects a repeated definition at its
  later occurrence in every entry path. A7: the message write cannot change
  the exit status. Regression tests in `tests/runner-test.rkt` and
  `tests/static-command-test.rkt`; boundary allowlists updated.
- [x] 1.3 Full gate green on the final revision (104 test files, purity and
  boundary checks); committed and pushed on the branch.

Deferred, Kyle decides (unchanged in code):

- A6: `dotenv-path?` refuses any path component matching `(^|.)env($|.)`, so
  `env.attl` or an `env/` directory is refused as "dotenv files are never
  read", while `read-file`/`write-file` have no such rule. The refusal is
  pinned by existing launcher tests. Options: narrow it to real dotenv names
  and reword, or keep it as policy.
- B1: `write-file` truncates and then writes, so a failure mid-write leaves a
  truncated file. The proposed temp-then-rename conflicts with the tested
  contract in `tests/file-host-test.rkt`: a write through a symlink keeps the
  symlink and needs write authority on the file only, whereas rename needs
  directory write, replaces the symlink with a regular file, and resets the
  inode, owner and permissions. Needs a decision on which contract wins.
- B2: real on Linux (rebinding a port after the server closed a connection
  fails with errno 98 without address reuse and succeeds with it). The fix is
  the third `tcp-listen` argument in `runtime/host.rkt` becoming `#t`.
- D1/D3: real. `typed-cons` forces its payload through
  `(raw-is-type error-type)`, which applies an untagged lambda as if it were
  an object: `(cons (lambda (x) (add x 1)) NIL)` makes `map` and `is-nil`
  return ERROR(EMPTY-LIST) and the run hangs; `(map (add 1 "a") (cons 1 NIL))`
  exhausts memory. No contained fix exists without a function tag in
  `core/objects.rkt`, a representation change.
- D2: an Error element makes the whole `cons` an Error, so `len`/`is-nil`
  return that Error. This is the documented `cons` contract ("An Error value
  propagates") and a language-design decision.

---

# Trim boilerplate from the `--check` report — completed

Kyle asked on 2026-09-18 for a deletion-only change: the `--check` report no
longer prints the `(one-based lines, zero-based columns)` parenthetical after
`Diagnostics` or the three trailing sentences beginning `Trusted basis:`. What
the checker proves, its verdicts, counts, diagnostics, locations and exit
statuses are unchanged. The spec for this work lives outside the repository.
No release is authorized; further work precedes the next release.

## Phase 1 — remove the report text everywhere it is required or quoted

- [x] 1.1 Amend both specification documents first: drop the stated trusted
  basis from the report description in the canonical-naming specification and
  the trailer, the "document that convention" clause and "Every report states
  the trusted basis" from the static-checking specification.
- [x] 1.2 Delete the header parenthetical and the three trailing strings in
  `runner/static/report.rkt`; delete the expected footer in
  `tests/static-report-test.rkt` and the `Trusted basis:` assertion in
  `tooling/test-linux-distribution.sh`; delete the quoted lines from the
  corpus document and the termination/external-success clauses from
  `docs/API.md` and `README.md`. Release notes and HANDOFF.md are historical.
- [x] 1.3 Focused report test passes; passing and failing reports end at their
  last content section. Full suite result recorded in the commit message.

# Release 0.9.0 — published and public download verified (historical)

Kyle authorized the complete 0.9.0 release after the independent review. That
work superseded the historical local-only endpoint below. PR #8 is merged;
`v0.9.0` is published and latest. The actual public Linux download passes the
complete isolated consumer. No new feature, dependency or public binary target
was added during release preparation. Completed releases grant no authority for
another release.

Evidence root: `/tmp/attalambda-090-release-g5_0101v/`. The final publication
record changes documents only; the archive remains the exact clean merged
source `0960a79ae797007da850a6d6f1c449482d333614`.

## Phase 1 — release inputs and PR verification

- [x] 1.1 Set VERSION to 0.9.0 and its package projection to 0.9, extend exact
  approved-version tables and expectations, and prepare the guide/notes. Raise
  only the source CI outer deadline from 30 to 45 minutes after the preceding
  suite took 34m36s; individual deadlines and runtime/checker behavior are unchanged.
- [x] 1.2 Pass 661 focused assertions, then 104 Racket files / 26982 reported
  tests, 49 Python methods, 40-module purity and the boundary gate in 29m42s.
  Verify all 226 executable, packaging and workflow inputs against the snapshot.
  Commit/push `46c2849f779ce00ce115ce6283ad80a4bcbb2403`, open PR #8 and pass
  all ten exact-head CI jobs in run `35311618086`. No temporary CI artifacts remain.

## Phase 2 — exact merged-source artifact

- [x] 2.1 Merge with the expected-head guard. Verify both parents and tree
  `af74508c74cc7f3ca710cb0566914c67ab56c58a`; fast-forward local main. All ten
  merged-head jobs pass in run `35312808000`, with the same source counts/gates
  and no remaining temporary native artifacts.
- [x] 2.2 Build the exact clean merge in isolated corrected Racket CS 9.3 and
  verify the manifest and all tested input identities. The 19,873,515-byte archive
  has SHA-256 `1dc9493bf041463fa9ec7226af2fbe5f078a43e4d707f4f4e2d502f4dccf8186`.
  Its no-Racket consumer passes static/runtime/guide/relocation checks and all
  25 terminal methods at both paths in 64.910s and 59.393s.

## Phase 3 — publication and records

- [x] 3.1 Recheck version availability and preservation. Create/push unsigned
  annotated tag `v0.9.0`, object `ad7fa3a6b5e31a599e7f1ef5a4aaadf8a343d0ba`,
  at the build commit. Create one draft with the exact archive/checksum assets;
  authenticated draft downloads match both verified hashes.
- [x] 3.2 Publish release `391256649` at `2026-09-18T06:25:52Z` as latest.
  Fresh unauthenticated public downloads return HTTP 200 and match the verified
  files. The actual downloaded archive passes the complete consumer and all
  25 terminal methods at both paths in 48.968s and 48.750s.
- [x] 3.3 Prepare the final publication record: current download/API/architecture
  docs, acceptance evidence, release notes, ledger, project instructions and
  handoff. Remove the owned build container, both consumers and their transfer
  directories; retain evidence and all candidates. Earlier seven releases,
  fourteen assets and seven annotated tags are preserved.

The final delivery gate applies to the resulting documentation-only commit:
commit/push this record, verify every exact-head CI job and clean main, and
record the actual SHA, run and preservation readback in `final-result.json`
outside the worktree. This avoids changing the commit being verified merely to
record its own identity. The handoff and GitHub Actions retain that lookup.

---

# Completed optional static-checking independent review (historical)

Kyle approved one focused independent correctness review and a security review
of the new checker's source/command boundaries after the completed candidate.
Starting branch `optional-static-checking`, clean HEAD
`ab521b034bd7ff0ea06daf70046518d1995c0499`; milestone base
`f6938b286329532230be210de0eaaa398286d38a`. No general refactor or whole-repository
audit is authorized. Existing local-commit authority continues; no remote action,
merge or publication is authorized. The original candidate below is preserved.

Evidence: `/tmp/attalambda-static-review-5du21rkr/`. Three fresh read-only reviewers
cover inference, frontend/command security, and contracts; root covers changed
structural checks, packaging and integration. Per-file coverage and proved
scenarios are retained in the review reports. The isolated corrected Racket CS
9.3 container is `attalambda-static-review`; the owner's runtime is untouched.

- [x] Enumerate the milestone delta and interacting boundaries; close-read and
  independently probe candidate failures. Four correctness findings are proven:
  H1 loses known callable-input conflicts alongside gaps; H2 rejects valid explicit
  application/datum forms internally; H3 gives tcp-listen the wrong success hint;
  H4 maps trusted syntax faults to user-source status 65. No execution bypass is
  demonstrated. These are defects in the completed milestone, not planned work.
- [x] Fix each confirmed cause serially, pin siblings and preserve bounded hunters
  as tests. The verified sequence was H3, H2, H1, H4. Ordinary source grammar,
  runtime behavior, partial-result honesty and structural gates are preserved.
- [x] Have a fresh agent cold-review the complete fix batch; settle every finding.
  The cold review found no additional proved defect. Independent probes passed
  18 inference cases, 34 syntax comparisons and five provenance cases.
- [x] Run focused checks, full suite, purity/boundary checks and current corpus.
  `review-full.log` exits 0: 104 Racket files / 26981 reported tests, 49 Python
  methods, 40 pure production modules and the boundary gate. `review-result.json`
  verifies 225 executable/packaging inputs against the tested snapshot. All five
  example reports exactly match the original candidate. Freeze this reviewed,
  verified source as a clean local commit before building.
- [x] Build a new exact clean candidate and run its transferred no-Racket consumer.
  Tested/build source is `7d577444bca5b8c101125d7cbf10e638a6e26cd0`; new archive
  SHA-256 is `a39febf5db4c7e6b2871252e52d863d903c04d3e62ad01377252e9a7690b0828`,
  19,873,969 bytes. Both path checks pass, including all 25 terminal methods at
  each path and the new static regressions. Original/transferred/final digests
  match. The original archive is preserved. Owned build/test and consumer
  containers and transfer state are removed. HANDOFF.md records exact paths and
  receipts; the final local record changes documents only. No remote action was
  taken and no review finding or authorized delivery step remains open.

---

# Completed implementation milestone (before independent review)

Kyle assigned the [complete revision-3 specification](docs/optional-static-checking-spec.md)
on 2026-09-17 and explicitly authorized the isolated Docker test-image build
with Python 3 and Git on resumption. The authorized endpoint is a fully tested,
reviewed, standalone-verified local candidate. Use the existing milestone branch
`optional-static-checking` and verified local phase commits. No push, pull
request, merge, tag, release-asset replacement, or publication is authorized.
Completed historical plans below grant no further authority.

The supplied specification defines six phases and 39 focused steps. Execute
steps serially and retain each phase's checkpoint before its local commit.
Phases 1–5 need multiple passes. On 2026-09-17 Kyle explicitly directed autonomous
continuation: finish and verify each pass, then start the next without requiring
another `next`. Stop only for a genuine owner-dependent blocker or serious
unresolved doubt. This overrides the next skill's one-pass stopping rule, while
retaining every step's full Work/Check requirements. If a step proves too large,
subdivide it into stable lettered substeps before implementation, as the
specification requires. Phase 0 is committed as `8bde48d`; Phase 1 is committed
as `20b6241`. Phase 2 Steps 2.1–2.9 and Checkpoint 2 are complete: the full
87-file suite, both structural gates, bounded robustness probes, and self-review
passed. Phase 2 is committed as `de39c732bf7cf571689fdf3677b094b9d67bc1ba`.
Phase 3 Steps 3.1–3.8 have passed their focused checks. All 129 public contracts
are audited (106 complete, 23 partial); Checkpoint 3 passed its full suite,
structural gates, input-hash comparison, and self-review, then committed as
`76c2c8b`. Phase 4 Steps 4.1a–4.3 and Checkpoint 4 passed: full regression suite,
structural gates, 218 matching executable inputs, and self-review. Phase 5 Steps
5.1–5.4 passed their final source checks: 102 Racket files, 26973 reported tests,
49 Python methods, both structural gates, and 223 matching executable/packaging
inputs. Fresh self-review has no open finding. The clean tested/build source is
`576d8837797f254fb068d19fd839ea1174e28151`. Its exact Linux archive passed the
transferred no-Racket consumer, including static checks and all 25 terminal
methods at both paths. Steps 5.5a/b and 5.6 are complete. The authorized local
milestone is finished; no owner action or unfinished implementation step remains.
The later delivery-record commit changes only PLAN.md, HANDOFF.md and
docs/ACCEPTANCE.md; its identity and final clean status are recorded externally.
Nothing was pushed, opened as a PR, merged, tagged, or published.

## Verified starting state and change boundary

The untouched checkout, local main, and remote main were at
`f6938b286329532230be210de0eaaa398286d38a`. There was no matching milestone branch,
open PR, or pre-existing local modification. The current branch was created at
that revision. All three canonical specifications and their amendments were
read in full, together with the relevant frontend, input/session, runtime
contracts, examples, and preparation/build/consumer/CI machinery.

The temporary 0.8.0 release receipt is absent. Its recorded fallback was checked:
all ten current-main CI jobs passed, and its delta from the tagged/build source
`f309199baa170ba5b12ff6b18b60dc49c114a8a1` contains only publication documents.
The public tag, release ID 389458950, and both asset IDs/digests match the
historical handoff. These read-only checks do not repeat release actions or
attribute its archive to the later documentation revision.

Phase 0 creates only `docs/optional-static-checking-spec.md`, as an exact copy
of the supplied file, and changes PLAN.md, HANDOFF.md, and the four files in
`docs/specifications/`. Canonical amendments are appended; every preceding
canonical byte and every historical plan/handoff byte is retained. Executable
code, tests, structural gates, build scripts, dependencies, VERSION, info.rkt,
README/API, examples, and release records have no change in this phase.

Later phases may modify the existing expander, launcher, exact structural gate,
tests, Linux consumer, and relevant current documentation, and create explicitly
classified checker modules and focused tests. They must preserve ordinary
execution, interactive behavior, runtime type checks, representation, host
capabilities, source grammar, and version metadata. No checker command or static
contract inventory is implemented at the end of Phase 0.

## Pilot expectations fixed before implementation

Step 2.9 uses the real frontend/kernel and one audited seed inventory. The
required supported pilot is reusable identity/apply/compose, partial arithmetic,
the source-let versus monomorphic-lambda distinction, acyclic forward bindings,
and ordinary factorial/summation. The two definitions and arithmetic call from
specification Section 3.2 must be established at Checkpoint 2; its rendering and
stdout calls join at Phase 3. Existing actual recursion examples are in
`tests/language-test.rkt` and `tests/interactive-expansion-test.rkt`.

Guarded `unwrap-ok`, empty-list access, and range/integrality-dependent
constructors remain partial without variant, nonempty, or range refinements.
Raw self-application requires unsupported recursive types. Incomplete references
remain incomplete through aliases, nested bodies, returned functions, and
dependent callers. An explanatory success hint cannot establish a result or
manufacture a downstream conflict. A known later argument mismatch still fails
when an earlier argument has a gap. These are required expectations, not measured
checker outcomes. No percentage of the existing corpus is promised.

The revision-3 correction is explicit: finite contradictions in homogeneous
List elements or common-result branches produce FAIL, including through aliases
and higher-order calls. Ordinary runtime behavior stays unchanged.

| Supplied fixtures | Required outcome and gate |
| --- | --- |
| C01, C02, C05, C09 | FULL PASS at the Phase 2 inference gate; C05 is check-only and must never execute. |
| C03, C04, C06, C07, C16 | FAIL at Phase 2, with captured variables and recursive self-calls monomorphic; C16 preserves the established declaration of double. |
| C11, C13, C14 | PARTIAL at Phase 2; Error alternatives, bare unwrap alias, and nested bodies cannot be hidden. |
| C08, C10 | FAIL at Phase 3: cons aliases obey homogeneous List constraints and filter requires Bool even on NIL. |
| C12 | FAIL plus the head-NIL Error-alternative gap at Phase 3; the seed-only pilot uses unwrap-ok in its first argument. |
| C15, C17 | PARTIAL at Phase 3: nested data restrictions and an unchecked stored Map comparator cannot be hidden. |
| C18 | FULL PASS with Error result at Phase 3; deliberate Error values are allowed. |
| C19 | Invalid source, status 65, with no program output at the frontend and CLI gates. |
| C20 | Internal failure for missing source accounting at Phase 1 and pending final contracts at Phase 4; CLI status 70. |
| C21 | Stable repeated backend analyses at Phase 2 and subsequent report/CLI gates. |
| C22 | Nonzero report-delivery failure and interrupted analysis at Phase 4; no provisional full-pass success or replay. |

All five public example files were inspected. `hello.attl` and `stdout.attl`
use the required complete stdout contract. `foundations.attl` combines exact
arithmetic, Option/Map, and Result unwraps; `file-round-trip.attl` contains guarded
unwraps and result branches; `http-server.attl` includes unwrap/head access,
numeric boundary conditions, and raw host. Those operations require the stated
V1 gaps, and any independently established finite conflict must still be
reported. Phase 5 measures each whole-file verdict and reason; source inspection
here is not a substitute for that corpus run or the Phase 3 contract audit.

## Phase 0 environment and checkpoint evidence (historical)

The untouched baseline at `f6938b286329532230be210de0eaaa398286d38a` passed
`./run-all-tests.sh` with exit 0: 69 Racket test files and
26845 reported Racket tests. The Python terminal harness ran
49 methods in its two suites. The same full-suite command
passed the expanded purity check for 40 production modules and the complete
source inventory/boundary gate. No new production or test unit was added.
Because this phase changes only planning/contracts, these unchanged executable
inputs retain that baseline evidence; separate document checks verify the final
specification bytes, historical prefixes/suffixes, hashes, links, and scope.

Evidence directory: `/tmp/attalambda-static-phase0-q0w_ycsc/`.
`baseline-unprivileged.log` is the completed run; `baseline-result.json` records its
process result and counts. `baseline-input-hashes.json` proves all 205 tracked
snapshot files match the baseline. `environment.log` records Racket CS 9.3,
Python 3.13.5, Git 2.47.3, Linux x86-64, retained Racket packages, and available
builder utilities. `preflight.json` records read-only Git/GitHub reconciliation.

The prepared Docker image is
`sha256:5366fd60f701ca1cbf5172c17bfa1150ca8a5e7500c3a9d19f5bbca4236be59c`,
derived from the verified full Racket image
`sha256:f9c540abe281413dc9e25bfbe6e35276f1a5bca1fa40213c40ac7bac6bb69c62`.
It adds only isolated test/build tooling and its native dependencies; no Racket
package version or AttaLambda dependency changed. The existing reviewed promise
and Expeditor corrections were applied inside the disposable test container and
verified with `racket tooling/prepare-racket-runtime.rkt --check`. The image
itself remains unpatched: future containers must apply/check the same corrections.
Package installation and tests ran as isolated UID/GID 1000, after root-only
preparation of the agent-owned container. `runner-unprivileged.log` records the
focused launcher pass before the complete suite; `unprivileged-preparation.log`
and `runner-unprivileged.sh` retain the setup output and exact test sequence.
`prepare-unprivileged.sh` creates the container-only test user and assigns its
Racket installation to that user so corrected dependency bytecode can rebuild.
The run had no external network and a 30-minute outer deadline. The normal
installed Racket 8.10 was not modified.

Exact in-container preparation/test commands were `racket --version`,
`python3 --version`, `git --version`,
`racket tooling/prepare-racket-runtime.rkt --apply`,
`racket tooling/prepare-racket-runtime.rkt --check`,
`raco pkg install --batch --scope user --link --name attalambda --deps fail --no-docs --fail-fast /evidence/baseline-unprivileged`,
`raco make tests/runner-test.rkt`, `raco test tests/runner-test.rkt`,
and `./run-all-tests.sh`. The fresh snapshot excluded dotenv paths before copying.

The existing isolated consumer image
`sha256:dabaae31057cbc79baf7e2afa65b8c8cfd378b5013e4e8a95a520265fc794803`
passes its prerequisite probe: Python 3.12.3 and pseudo-terminal/standard-library
facilities work, with Racket/raco absent, no external network, a read-only root,
non-root user, and dropped capabilities. Log: `consumer-prerequisites.log`.
This is environment readiness only, not a build or artifact consumer pass.
There is no new archive, measured static example-corpus result, or audited static
contract inventory yet. macOS/Windows checks were not run for this local phase;
their existing source and CI configuration are unchanged.

Earlier unsuccessful preparation attempts remain recorded. `baseline.log`
stopped at private snapshot directory permissions; `baseline-run.log` stopped
at the package source `.` being rejected. `baseline-full.log` passed 21 checks
before deliberate interruption (137) after discovering missing Python/Git.
The elevated image-build requests were rejected by the execution layer.
Following Kyle's authorization, the build succeeded within sandbox permissions
using `docker --config /tmp/attalambda-static-phase0-q0w_ycsc/docker-client build`;
the recipe and output are `Dockerfile` and `toolchain-build-contained.log`.
No failed attempt is counted as a complete baseline and no assertion, test
deadline, or product source was changed to obtain success.

The first prepared-image run, `baseline-prepared.log`, exited 1 at three launcher
assertions for a single unreadable-file fixture. Root bypassed its mode-000
permissions and executed the file. A direct root/unprivileged probe established
that cause (`permissions-diagnosis.json`). A fresh, byte-verified snapshot and
unprivileged test user corrected the environment; the focused launcher test
passed before the final full-suite run. No product or test source was changed.
The first unprivileged setup stopped before tests because the root-owned Racket
installation rejected bytecode writes (`unprivileged-cache-denied.log`). Giving
the disposable installation to its test user resolved that prerequisite.

Checkpoint review is a fresh self-review of authority, amendments, baseline
evidence, static/runtime separation, and the fixed C01–C22 expectations; no
independent reviewer or implementation review is claimed. Document verification
uses `python3 /tmp/attalambda-static-phase0-q0w_ycsc/verify-phase0.py` and records
`documentation-verification.json`. The supplied specification is byte-for-byte
identical to the upload, including its intentional Markdown hard breaks. Other
changed files pass ordinary whitespace checks. Previous canonical bytes and
historical plan/handoff records are preserved. No open finding remains.

Phase 0 closes with one local documentation/contract commit; its exact hash is
recorded in the external `state.json` and final response after commit, not inside
a self-referential record. No push or other remote mutation occurs. Owned test
containers are removed; the recorded image, snapshot, and logs are retained for
later steps. **Next unfinished step: 1.1a, expansion-only preparation.**
No owner action is required to start that step.

## Active phases and steps



All six phases are complete. The checked steps below retain their focused Work/Check requirements and checkpoint evidence. Final source and artifact identities are separate from the later delivery-record commit, as required by Section 10 of the specification.

## Phase 0 — Confirm the workspace, constraints, and usable V1 scope

**Purpose:** establish the actual baseline, authority, environment, and expected limitations.
**Prerequisites:** explicit implementation assignment and repository read access.

- [x] **0.1 — Reconcile the checkout and choose the safe workspace.**
  **Work:** Read current project instructions, all canonical contracts/amendments, active plan/handoff, affected source, relevant PRs, ancestry, and local changes. Compare with the pinned baseline. Choose or reuse one milestone branch/worktree without disturbing other work. Do not update project source/contracts before the baseline in 0.2.
  **Check:** Record `git rev-parse HEAD`, `git branch --show-current`, `git status --short --branch`, relevant changes, and applicable authority. A clean, separate authorized worktree is preferable to resetting/stashing another person's work. Existing public refs/assets are unchanged; a local-only assignment does not require remote write access.

- [x] **0.2 — Establish the isolated test and candidate environment.**
  **Work:** Inspect preparation/build/consumer scripts. Provision or reuse an agent-owned supported runtime; confirm Linux build/consumer prerequisites and available review tools.
  **Check:** Record `racket --version`, dependency-correction `--check`, and untouched `./run-all-tests.sh` results. Name unavailable essential infrastructure now. Do not modify the owner's runtime or claim a historical test count as the new baseline.

- [x] **0.3a — Save the active plan and narrowly authorize checker scaffolding.**
  **Work:** After the baseline, save/link this complete specification and record the active phase plan using repository conventions. Add only necessary canonical amendments for optional source analysis, its private classified scaffolding, and checker exit statuses. Preserve prior bytes and update specification hashes.
  **Check:** Historical plans and canonical bytes are preserved, index hashes/links match, and the initial diff contains only intended planning/contract changes. No runtime primitive, tag, capability, typing extension, or release authority is introduced.

- [x] **0.3b — Record realistic pilot expectations.**
  **Work:** Inspect representative existing arithmetic/recursive, container, and boundary examples. Map the Section 9.2 counterexamples to required FULL PASS, FAIL, PARTIAL, or invalid-source expectations before implementation can bias the expected results.
  **Check:** The active plan names the early pilot in Step 2.9, the guarded-unwrap/nonempty/range limitations, and the explicit heterogeneous-join verdict correction. No promised corpus percentage or undocumented feature is needed to meet those expectations.

**Checkpoint 0 — Baseline gate.** Review authority, baseline, and the actual supported-versus-partial expectations; run required repository gates before committing. Stop dependent work on a relevant unexplained baseline failure. Missing packaging infrastructure may permit independent kernel work but remains a final-delivery blocker.

## Phase 1 — Prove the non-evaluating frontend and embedding path

**Purpose:** resolve binding, source-location, and metadata transport risk before inference.
**Prerequisites:** Checkpoint 0 and understanding of the current restricted reader and expander.

- [x] **1.1a — Add the expansion-only preparation seam.**
  **Work:** Use the existing validated source snapshot and restricted parser to prepare a fresh module for trusted expansion only. Reuse the fixed language-declaration/embedding machinery as appropriate; do not call the session's evaluating preparation routine. Classify the new private helper and its exact imports in the same change.
  **Check:** Focused frontend tests accept valid source and reject bad headers/readers, unsupported literals, and unknown names. Instrument the user-module boundary to establish that no evaluation/instantiation/demand occurs. Fresh preparations cannot inherit REPL bindings or an earlier input's namespace state.
  **Evidence:** `runner/static/frontend.rkt` uses a validated snapshot and fresh
  expansion namespace. Focused frontend, static-boundary mutation, and existing
  boundary tests passed (167 checks); the whole boundary gate passed. Log:
  `/tmp/attalambda-static-implementation-mmgdshl_/step-1.1a.log`. No user evaluation,
  demand, input consumption, or output occurred. Phase 1 continues with 1.1b.

- [x] **1.1b — Expose a complete inert source analysis view.**
  **Work:** Add the smallest private opt-in expander seam retaining literal kinds, lexical identities, original source IDs, declaration dependencies, and explicit `let`/`rec` nodes before representation lowering. Validate the metadata's shape and source-accounting invariants. Keep type algorithms outside the expander.
  **Check:** Recover literals, a curried function, an alias, a nested lambda, a local let, and a recursive definition. Missing/corrupted/duplicated IDs or a missing final form fail internally rather than passing an incomplete program. Without the request, existing expanded computation remains binding-equivalent to the original path; compare structural terms modulo fresh binder names and inert source properties, not incidental pretty-print bytes.
  **Evidence:** Actual expansion transports validated prefabs through distinct
  request/result properties, preserving source IDs and exact counts. View,
  mutation, existing boundary tests, and gate passed; ordinary expanded terms
  compare equal modulo generated binders/properties. A test observer initially
  confused the trusted static-source helper with user modules; an identity probe
  established the cause, and the corrected observer/positive control passed.
  Logs: `step-1.1b.log` and `step-1.1b-observer-final.log` in the current evidence
  directory. No inference exists yet; Step 1.2 follows.

- [x] **1.2 — Preserve binding, sugar, forward references, and source abstraction boundaries.**
  **Work:** Reuse expander logic for sequential lets, repeated binders, `list`, `cond`, acyclic forward references, zero-argument `rec`, and shadowed declaration keywords. Retain let-generalization boundaries while normalizing currying/list/cond mechanically.
  **Check:** Actual-expander fixtures distinguish a user `add`/`if`/`cons` from the built-in and preserve hygienic generated operations. Source-local references identify their real binders even when names repeat. Ordinary datum-equivalent reader notation must be handled like the existing parser; do not invent new restrictions for an otherwise valid quoted/escaped spelling of an identifier. Preserve `rec` instead of only its fixed-point encoding. Existing direct/mutual-cycle rejection, literal validation, and original source locations remain unchanged; no symbol-only mock is sufficient.
  **Evidence:** Six focused actual-expander tests passed, including every public
  value's resolved catalog identity, escaped identifier spellings, shadowed
  declarations, hygienic cons/if, repeated binders, forward edges, and zero-argument
  rec. Log: `step-1.2.log`. No new source notation or runtime behavior was added.

- [x] **1.3 — Prove preparation does not perform program effects.**
  **Work:** Add synthetic user modules containing demanded stdout, input, file writes, exit, raw-host/network calls, and divergence. Include an effectful first form followed by invalid syntax.
  **Check:** Preparation finishes or reports source errors without program output, consumed input bytes, marker-file writes, program exit, or network attempts. Combine instrumentation with actual isolated file/input/loopback observations; use bounded harness cleanup. The checker never calls the program to discover its types.
  **Evidence:** `static-effects-test.rkt` passed both cases: instrumented file and
  network guards have positive controls, then actual source analysis performs no
  reads/writes of program data, connections, stdout, input consumption, or exit.
  Demanded divergence and invalid final forms finish within the bounded harness.
  Temporary files and an ephemeral loopback listener are cleaned up. Log:
  `step-1.3.log`.

- [x] **1.4 — Exercise the same frontend through executable embedding.**
  **Work:** Compile a minimal test-only driver around the actual analysis seam using the existing embedding approach. Do not create a second parser or temporary public flag.
  **Check:** Outside the checkout, the embedded driver analyzes source and retains metadata without source-path assumptions. Request and result properties remain distinct and validated. Retain the useful regression, not a parallel implementation or permanent probe framework.
  **Evidence:** The actual frontend driver compiled and passed after both its
  staged sources and isolated package installation were hidden. It recovered
  the expected declarations, 11 source expressions, and resolved builtins;
  the source stdout form never ran. Log: `step-1.4.log` in the current evidence
  directory. The driver lives only under tests/helpers.

**Checkpoint 1 — Frontend feasibility gate.** Run frontend/effect/embedding probes, affected source-reader and `tests/interactive-expansion-test.rkt` tests, full suite, and structural gates. Review binding/hygiene and non-execution counterexamples. Adapt failed metadata transport narrowly before investing in inference. Trusted compile-time expansion is allowed; evaluating the user's program is not.

**Checkpoint 1 passed.** `./run-all-tests.sh` exited 0 in the isolated Racket
9.3 container: 75 Racket test files, 26879 reported Racket tests, 49 Python
terminal methods, purity for all 40 production modules, and the complete boundary
gate. This includes the existing source-reader/interactive-expansion regressions
and all six new static frontend test files. `phase1-full.log` and
`phase1-result.json` in `/tmp/attalambda-static-implementation-mmgdshl_/` retain
the run and byte hashes of all tested executable inputs; those inputs match the
checkout. The final documentation-only checkpoint record does not change them.

The checkpoint is a fresh self-review, not an independent review. It checked
binding identity, shadowing, generated-operation hygiene, source accounting,
source positions, recursive/declaration boundaries, fresh namespaces, cleanup,
ordinary expanded-term equivalence, and actual executable embedding. No finding
remains open. Executable changes add only inert frontend metadata and its private
expansion seam; tests add the focused probes; tooling classifies exact modules
and imports. PLAN/HANDOFF record results. Core, effects, runtime, public grammar,
launcher behavior, version metadata, dependencies, and release assets retain
their existing behavior. No inference or public check flag exists yet.

## Phase 2 — Build the small inference engine and run the usefulness pilot

**Purpose:** establish finite types, ordinary inferred polymorphism/recursion, and honest incomplete results.
**Prerequisites:** Checkpoint 1. Seed contracts are created in Step 2.5a; the full library inventory is not a prerequisite.

- [x] **2.1 — Implement structural types and separate proof state.**
  **Work:** Add nominal types, arrows, containers, variables/schemes, and established/unproved/conflict results in classified checker modules. Keep display separate.
  **Check:** Distinguish String from List(Char), Rat from Byte, a scheme variable from a hole, and Error from other types. Validate constructor arities. No solver, runtime dependency, or generalized type-system framework is introduced.
  **Evidence:** `types.rkt` and `proof.rkt` are exact classified checker modules.
  Constructor/nominal/hole tests plus the existing boundary tests passed (149
  reported checks), followed by the complete source boundary gate. Log:
  `step-2.1.log`. Proof state preserves concurrent gaps/conflicts and dependency
  IDs independently of monotypes. Next: substitution and generalization.

- [x] **2.2a — Implement substitution, instantiation, and eligible generalization.**
  **Work:** Add fresh variables, free-variable sets, substitutions/composition, and fresh scheme instantiation. Implement generalization over the substituted environment as specified in 5.3. Keep schemes separate from monotypes and state local to an analysis.
  **Check:** Independent identity instances have fresh variables; captured environment variables do not. Substitution respects bound scheme variables and composition order. Quantifiers never enter an arrow/container. Unit tests expose the stale-environment generalization bug before source integration.
  **Evidence:** Structural substitution, composition, freshening, restriction
  transport, and substituted-environment generalization passed focused tests.
  An additional composition probe exposed double substitution; simultaneous
  substitution corrected it, and bounded composition equations now cover the
  class. Solver states reject unresolved/cyclic mappings. The final type/kernel
  and existing boundary batch passed 154 checks and the gate; separate mutation
  tests reject evaluation, output, environment reads, and unapproved imports.
  Logs: `step-2.2a-composition.log`, `step-2.2a-final.log`, and
  `step-2.2a-boundary.log` in the current evidence directory.

- [x] **2.2b — Implement finite structural unification and failure isolation.**
  **Work:** Unify nominal types, arrows, and containers with an occurs check using one small solver. Keep unsuccessful equation updates tentative or discardable.
  **Check:** Hand-derived and bounded generated equations cover success, nominal conflicts, arrow/container mismatch, chains, and `a = a -> b`. Successful substitutions satisfy input equations and repeated substitution stabilizes. A failure cannot leak state into a separate problem, erase a sibling conflict, or allocate a cyclic/infinite type.
  **Evidence:** The focused kernel/mutation batch passed all 13 test cases,
  including 2025 bounded structural equation pairs and independent sibling
  failures. The complete boundary gate passed. `step-2.2b.log` records the run.
  Unification returns an immutable solution or explicit failed obligations;
  unsuccessful equations expose no partially updated state.

- [x] **2.3 — Enforce the one data-variable restriction.**
  **Work:** Preserve Section 5.2's restricted domain through unification, substitution, and schemes. Use a small admissibility rule, not a type-class or constraint-plugin framework.
  **Check:** Rat/nested supported data are accepted; an arrow or Error is not silently admitted. Restriction survives instantiation/generalization. Unsupported data-domain use remains distinct from a concrete Rat/String conflict; no runtime Data/Function tag is added.
  **Evidence:** All 16 focused kernel test cases passed, including nested
  payloads, variable linking, generalization/freshening, failure isolation, and
  simultaneous unsupported-domain/nominal failures. The separate mutation test
  and complete boundary gate passed. Logs: `step-2.3.log` and
  `step-2.3-boundary.log`. No runtime representation changed.

- [x] **2.4 — Render types deterministically and close the kernel review.**
  **Work:** Render stable variable names, quantified restrictions, containers, and correctly grouped arrows. Review the kernel before inference depends on it.
  **Check:** Golden tests cover `a -> b -> c`, `(a -> b) -> a -> b`, Error, and restricted schemes. Recheck freshening, substitution, occurs-check, and hole separation with focused tests. Rendering never calls an object-language evaluator. This is a focused review, not an extra mandatory full-suite/commit phase.
  **Evidence:** Golden display, all focused kernel/mutation tests, and the
  existing boundary suite passed (165 reported checks), followed by the complete
  boundary gate (`step-2.4.log`). Self-review checked simultaneous substitution,
  solved-state normalization, fresh variable ownership, substituted environments,
  occurs checks, atomic failures, recursive data restrictions, and proof/type
  separation. The evidenced composition finding from 2.2a is resolved. No open
  kernel finding or independent-review claim remains. Phase 2's full suite and
  commit remain after source inference and its pilot.

- [x] **2.5a — Create the real seed-contract inventory.**
  **Work:** Inspect actual implementations/tests and audit Rat/Bool constants plus the arithmetic and first-class `if` schemes needed for double/factorial. Include Result-valued `div`, `is-ok`, a conditional `unwrap-ok` input contract, and the fixed `error-to-string : Error -> String` contract for the pilot. Associate catalog IDs only with their resolved built-in bindings.
  **Check:** Record source locators and valid/invalid-domain evidence. `if` works as a value and alias, not only a syntactic head. `div` is Result-valued; `unwrap-ok` has no verified success-only signature. Other known exports may be explicitly pending audit, never unknown identifiers or fabricated safe signatures. This is the same inventory completed in Phase 3.
  **Evidence:** `contracts.rkt` contains the audited Rat/Bool/if seeds, Result
  division/predicate, partial unwrap input contract, and explicit Error renderer.
  Each records implementation symbols/paths and focused runtime tests. The exact
  facade export inventory and actual frontend binding identities match; all other
  exports are explicitly pending and fail internally if requested. Shipping
  catalog validation rejects pending entries. Focused catalog/boundary tests
  passed (4 cases), followed by the whole boundary gate and 3519 existing runtime
  checks for typed rationals, logic, Results, and rendering (`step-2.5a.log`).

  Audit observed `typed-if` selecting untagged branches after its Bool check;
  `raw-rat-div` represents zero division as Result Err, and the strict wrapper
  tags successful Rat payloads. `raw-result-unwrap-ok` returns WrongResultVariant
  Error on Err, so its output remains unproved; `typed-error-to-string` deliberately
  consumes Error. A negative gate probe caught native `exit` accidentally admitted
  by a quoted catalog label. Labels for pending operations are now inert strings,
  the excess vocabulary is removed, and the retained execution mutation test
  passes. No runtime implementation was changed.

- [x] **2.5b — Infer elementary source expressions.**
  **Work:** Infer literals, references, lambdas, and curried applications through the actual frontend/kernel and seed inventory. Preserve complete input obligations when an earlier argument is incomplete; keep conditional hints out of established types.
  **Check:** Infer double, identity, application, nested lambdas, and partial `add`; locate a String/Rat conflict. A shadowed function never inherits a catalog contract. Calls through a first-class `if` alias obey the same homogeneous-result equations as direct calls.
  **Evidence:** The actual frontend/kernel infers literals, identity/apply/compose,
  double, partial add, Result division, and function-valued branches. Tests verify
  shadowing, first-class if aliases, precise argument locations, and 3/4 independent
  expression obligations for bad add. Partial outputs have no verified value type;
  known remaining inputs still expose later conflicts. An exhausted conditional
  cursor cannot turn its speculative function result into proof. Focused inference
  and mutation tests plus the boundary gate passed (`step-2.5b.log`), followed by
  the additional alias fixtures (`step-2.5b-aliases.log`). Let/module/rec rules are
  the following steps, not implied by this elementary-expression result.

- [x] **2.6 — Infer lexical bindings with source-level generalization.**
  **Work:** Use actual acyclic dependency order and sequential-let scope. Generalize completed `def`/`let` bindings using the solved current environment; instantiate each use. Keep lambda parameters and captured environment variables monomorphic where required.
  **Check:** Forward definitions and repeated/shadowed names work without runtime reordering. Identity works at Rat and String; `(identity identity)` checks. Section 5.4.1's let form passes and its lambda-parameter counterpart fails. The captured-function counterexample in 9.2 fails. Unknown names/forbidden cycles remain source errors, not gaps.
  **Evidence:** Actual-source bindings, elementary inference, mutation tests, and
  the existing boundary suite passed 154 checks plus the whole gate (`step-2.6.log`).
  C01–C04, C07, C09, C13, and C16 have their required binding/type outcomes.
  Reported dependency edges are checked against resolved source references before
  topological analysis. Incomplete aliases retain only conditional input templates;
  they publish no verified value scheme. Recursion is the next rule.

- [x] **2.7 — Infer ordinary source `rec` and discharge its local assumption.**
  **Work:** Use one monomorphic recursive assumption, unify with the inferred curried body, discharge the self edge, and generalize eligible variables afterward. Include zero-source-argument recursive values without evaluation.
  **Check:** Factorial/summation infer `Rat -> Rat`; locate recursive conflicts. Self-dependencies do not make all recursion partial. Finite-typed nonterminating recursive fixtures are checked without being run. Raw self-application reports the occurs-check limitation. Direct/mutual module recursion and pure fixed-point lowering remain unchanged; no polymorphic recursion is introduced.
  **Evidence:** Twelve focused recursion/binding/inference/mutation cases and
  the boundary gate passed (`step-2.7.log`). Factorial and sum establish Rat-to-Rat;
  both divergent C05 forms and a zero-argument recursive Rat establish finite
  constraints without execution. C06 conflicts, and recursive infinite types or
  external gaps remain unproved. A failed self consistency check invalidates only
  source nodes that used its provisional assumption; successful rec has no false
  external self dependency. Runtime fixed-point lowering was not changed.

- [x] **2.8 — Apply uniform constraints through source sugars and aliases.**
  **Work:** Check source list/conditional normalization using original IDs and first-class built-in schemes. Treat finite homogeneous-element/common-result contradictions as TYPE_CONFLICT in every representation. Preserve explicit let/rec boundaries.
  **Check:** Currying, sequential-let nesting, list/cons, and cond/if mappings agree under their supported rules. Heterogeneous direct/aliased `if` calls fail identically; homogeneous function-valued branches pass. Both branches and all independent children are visited. List typing tests may use explicitly pending constructor contracts until 3.2, but no production completeness is claimed for an unaudited contract.
  **Evidence:** Three actual-source sugar cases passed (`step-2.8.log`), covering
  curried/nested lambda/application equivalence, sequential/nested let, cond/if,
  shadowed public if, unselected conflicts, and coexisting gaps/conflicts. List
  sugar has the exact cons normalization and original 3-node denominator; both
  forms explicitly fail on the pending cons audit in this intermediate catalog.
  List typing is deliberately not claimed before Step 3.2.

- [x] **2.9 — Close gap propagation and run the early backend pilot.**
  **Work:** Finish component isolation, proof-state propagation, and the representative cases in 1.3 using the actual frontend/kernel/seed inventory. Treat incomplete built-in references as incomplete even before invocation. Preserve established upstream declarations after a bad call.
  **Check:** Arithmetic/identity/recursion establish types; bad `add` and incompatible branch types conflict; raw self-application, guarded unwraps, and their dependent callers remain partial. A closure cannot hide a gap in an unused nested body. An earlier gap cannot hide a later independent argument mismatch: use `(add (unwrap-ok (div 1 0)) "bad")` while only seed contracts exist. Best-case unwrap output hints cannot invent a conflict in C11; its Error renderer is included in the seed audit. Reordering independent definitions or checking twice changes no result. Record pilot outcomes; fix required supported cases before the broader audit.
  **Evidence:** All 18 fixed seed fixtures matched their pre-recorded outcomes;
  four pilot test cases also establish alias/closure/higher-order gap propagation,
  three-binding dependency paths, conditional input-template isolation and captured
  monomorphism, independent components, and C01/C07/C01 equality. The measured
  [pilot record](docs/static-checking-pilot.md) reports every fixture and limitation.
  Logs: `step-2.9-final.log` and `pilot-results.json`. The earlier `step-2.9.log`
  stopped at one extra closing parenthesis in the new test; that syntax error was
  corrected before the successful run. No production inference correction was
  required by these pilot cases. The public catalog has 21 audited seed entries
  and 108 explicitly pending entries; no shipping/whole-corpus claim is made.

**Checkpoint 2 — Inference and practical-scope gate.** Review scope, generalization, recursive assumptions, and unchecked-result propagation; prefer independent read-only review when available. Run kernel/frontend/inference tests, affected language/recursion tests, full suite, and gates. The two definitions in Section 3.2 and `(factorial (double 3))` must be established without execution. Rendering/stdout arrive in Phase 3. Documented partial pilot results are an accepted V1 limitation, not a reason to invent refinements or request routine owner decisions.

Checkpoint 2 passed. `./run-all-tests.sh` exited 0 with 87 Racket test files,
26919 reported Racket tests, 49 Python terminal methods, purity over all 40
production modules, and the complete source/boundary gate. Evidence:
`phase2-full.log` and `phase2-result.json` in the implementation evidence directory;
191 executable input hashes match the tested snapshot. Additional bounded probes
cover 60 nested lambdas (61 expressions), 120 nested applications (361), 80
independent definitions (320), and 100 dependent aliases after a partial seed
(101 definitions/expressions). Each run repeats identically, preserves exact
counts, and has the independently expected established/unproved verdict.
`phase2-robustness.rkt` and `phase2-robustness.log` retain these check-only probes.

Fresh self-review covered simultaneous substitution, restricted generalization,
monomorphic captures/self assumptions, conditional input cursors, discarded
failed equations, complete source accounting, binding identity, and exact helper
permissions. No open finding remains; no independent review is claimed. The
composition and native-exit label findings were resolved before this full run.
Executable additions are eight private checker modules plus exact gate rules;
tests add twelve focused files and the fixed pilot fixtures. Documentation records
the measured intermediate pilot and this checkpoint. Core, effects, runtime,
language frontend, ordinary launcher, and version metadata have no Phase 2 diff.
No public check command or complete catalog is claimed yet. Close one local phase
commit and continue directly with Step 3.1; no remote action is authorized.

## Phase 3 — Complete the auditable library and host contracts

**Purpose:** broaden useful coverage while preserving every actual failure alternative.
**Prerequisites:** Checkpoint 2; the pilot works and the seed inventory is reused.

- [x] **3.1 — Complete export classification and scalar contracts.**
  **Work:** Inventory every actual public value binding separately from syntax/scaffolding. Complete supported scalar contracts; retain explicit range-dependent gaps.
  **Check:** Export drift fails closed; `div`/`exp`/`recip` are Result-valued. Wrong nominal inputs fail with correct argument order. No private Nat/Int, public alias, or success-only signature is invented. Previously audited seeds remain consistent.
  **Evidence:** `step-3.1.log` passed 2101 reported checks across scalar/catalog/
  mutation tests and existing Rat, Char, Byte, and String tests, plus the boundary
  gate. All 129 actual facade exports remain inventoried. Thirty-three additional
  scalar/text entries are audited; range-dependent Char/Byte and empty String
  access retain Error-alternative gaps. Native print/read-line mutation probes
  join the existing exit check. No runtime/library implementation changed.

- [x] **3.2 — Add container construction and safe non-callback List contracts.**
  **Work:** Add data-restricted schemes for constants/constructors, `len`, `append`, `reverse`, and other audited fixed-shape operations. Record empty/count/nesting failure limits and preserve restrictions through nested type parameters.
  **Check:** Homogeneous Lists retain element types; String is not List(Char). Heterogeneous `(list ...)`, direct `cons`, and a `cons` alias produce the same finite conflict. Functions hidden beneath a generalized nested-data variable cannot bypass its restriction. `head NIL`/`tail NIL` remain partial; `zip` does not gain an invented Pair. No runtime-valid construct is disabled in ordinary execution.
  **Evidence:** `step-3.2.log` passed 344 checks across List/sugar/catalog/mutation
  tests and existing List/transform/count runtime tests, plus the boundary gate.
  Ten contracts now establish constructors, length, append/reverse/concat, and
  homogeneous two-element-List zip; head/tail remain partial. Direct and aliased
  heterogeneous Lists conflict, nested generalized function payloads retain data
  restrictions, and C12 reports both the head gap and later Rat/String conflict.

- [x] **3.3 — Add higher-order List and Map contracts.**
  **Work:** Inspect actual callback order, element/result restrictions, and Map equality/key/value relationships. Model the stored Map comparator's typed invariant, not merely its data fields. Leave unrepresented failure paths partial.
  **Check:** `map` changes element type; `filter` requires Bool; `reduce` takes accumulator then element. Bad callbacks are checked even on NIL. Map equality ties both key inputs and its uncertainty taints an initially empty Map. Raw functions are not assumed admissible data elements. Generalized key/value restrictions survive subsequent updates. Do not modify library algorithms.
  **Evidence:** `step-3.3.log` passed 352 checks across callback/catalog/mutation
  cases and existing transform/search/Map runtime tests, plus the boundary gate.
  Seventeen entries cover callbacks/search and Map operations. C10 conflicts on
  NIL, C17 remains partial, accumulator-first order is verified with differing
  element/accumulator types, and comparator/key/value relationships survive
  aliases, generalization, and persistent updates. No algorithms changed.

- [x] **3.4 — Complete Option, Result, and Error contracts.**
  **Work:** Encode fixed Error payloads, constructors/predicates, `option-case`, and conservative unwrapping. Distinguish make-ok's propagation from make-err's intentional Error consumption.
  **Check:** `make-err 1` fails; `unwrap-ok` is not a total `Result(a) -> a`; guarded unwraps stay partial; `unwrap-err` has its audited Error output. Error cannot be coerced to Rat or an arrow. Aliases retain these rules.
  **Evidence:** `step-3.4.log` passed 256 checks across variant/catalog/mutation
  tests and existing Option/Result runtime tests, plus the boundary gate. Nine
  entries complete Option and fixed-Error Result handling; C15 retains its nested
  data-domain gap and C18 establishes Error. User lambdas can deliberately ignore
  an Error, but arithmetic/calls cannot coerce it. Guarded unwraps remain partial.

- [x] **3.5 — Audit pure rendering and the remaining value operations.**
  **Work:** Finish scalar/restricted generic rendering; classify remaining value operations, including flatten/count/index cases. Inventory effectful print, completing its contract in Step 3.6. Review the complete value-contract set for missing Error alternatives before adding host signatures.
  **Check:** Supported rendering returns String; direct/nested raw-function cases never receive universal safe signatures. Every completed entry has source and valid/invalid-domain evidence; unsupported entries have precise reasons. No runtime function detection or tag changes. Repair invalid seed assumptions and refresh dependent inference tests.
  **Evidence:** `step-3.5.log` passed 2870 checks across rendering/count/catalog/
  mutation tests and existing pure renderer/Error/count runtime tests, plus the
  boundary gate. Seventeen entries cover scalar/data rendering, count/index
  operations and flatten. Generic rendering uses the recursive data restriction;
  direct Error overloads remain outside that scheme (error-to-string is complete).
  Count/integrality alternatives and arbitrary flatten nesting stay specifically
  partial. No seed signature needed correction. Print remains pending Step 3.6.

- [x] **3.6 — Establish the four required I/O wrappers and print.**
  **Work:** Verify stdout/read-line/read-file/write-file against wrappers, host branches, codec, and existing tests. Complete print from its rendering and stdout dependencies without changing runtime implementations.
  **Check:** Catch String versus List(Byte) misuse; represent expected I/O failure as Result Err. Analyzing read-file never reads the program's requested data file. Separately test actual wrappers with isolated runtime resources. The complete Section 3.2 example now establishes all obligations without program execution.
  **Evidence:** `step-3.6.log` passed 673 checks across static I/O/catalog/mutation
  cases and existing stdout, stdin, files, real file-host, print, codec, and host
  tests, plus the boundary gate. Five entries record facade/wrapper/host/codec
  locators; read-file returns Result(List(Byte)), never String. A positive-control
  file guard observes real reads, then confirms backend analysis makes no program
  reads/writes, consumes no input, and prints nothing. Section 3.2 fully establishes
  all obligations, including stdout and rendering, without executing factorial.

- [x] **3.7 — Classify raw host, TCP, HTTP, and exit.**
  **Work:** Keep raw host explicitly unproved; audit remaining operations for numeric/value-dependent failures. Close all pending inventory entries as supported or specifically partial.
  **Check:** Raw-host aliases and higher-order uses remain gaps. No invented nominal handles, String-returning read-file, new host operation, or successful-exit assumption. Every actual public export is accounted for; unsupported is not the same as absent.
  **Evidence:** `step-3.7.log` passed 1856 checks across boundary/catalog/mutation/
  full-backend non-execution cases and existing TCP, HTTP, HTTP-server, and exit
  runtime tests, plus the boundary gate. All 129 actual exports are now audited:
  106 complete, 23 specifically partial, zero pending (`catalog-results.json`).
  Every analysis validates the catalog. TCP keeps Rat handles and pre-host count
  gaps; HTTP parse/render failures are represented Result Err; injected factories,
  raw host, and exit remain partial. Actual input/file/network/exit observers now
  surround the complete backend. [The inventory](docs/static-checking-contracts.md)
  records each signature/input hint, reason, implementation locator, and test.

- [x] **3.8 — Close the combined boundary counterexamples.**
  **Work:** Exercise partial outputs, higher-order use, callbacks, partial application, and the library's Error-absorbing continuations together.
  **Check:** Possible Error cannot acquire a verified arrow type; an earlier gap cannot swallow a later nominal mismatch; ordinary user lambdas do not inherit library absorption semantics. Existing runtime outputs remain unchanged. Independently audit source coverage versus trusted contracts rather than claiming to have inferred the library's internals.
  **Evidence:** `step-3.8.log` passed 13 combined/robustness/pilot/catalog/mutation
  cases and the boundary gate. The reusable acceptance set contains all semantic
  C01–C18 cases (C05 in both forms), retained pilot extras, and complete Section
  3.2. Partial outputs cannot gain arrows or manufacture conflicts from hints;
  later known inputs still conflict through aliases and partial application.
  Deliberate Error-returning user lambdas establish their actual types. The
  bounded Phase 2 probes are now retained regressions, including intervening
  failed analyses. Source coverage counts only original registered expressions;
  the audited library remains the explicitly trusted basis. No runtime edits.

**Checkpoint 3 — Contract and trusted-boundary gate.** Review complete signatures against both success and failure domains, including data restrictions, callback order, and source/effect separation. Run contract/non-execution regressions, affected library/host/codec tests, full suite, and gates. Ordinary supported I/O is not unknown merely because it is effectful; partial wrappers/raw host are not complete merely because a return shape is desired. No refinements, unions, or effect system are needed to close this gate.

**Checkpoint 3 passed.** The isolated Racket 9.3 full suite exited 0 with 96
Racket test files, 26944 reported Racket tests, 49 Python terminal methods, purity
over 40 production modules, and the complete boundary gate. `phase3-full.log`
and `phase3-result.json` retain the run and 201 matching executable-input hashes
in `/tmp/attalambda-static-implementation-mmgdshl_/`. Final record-only edits do
not alter those tested inputs. The fresh self-review (`phase3-review.md` there)
has no open finding; no independent review is claimed.

Review covered success/failure domains, recursive data restrictions, callback
order, Error alternatives, partial application, aliases/closures, actual
non-execution, and exact capability-rejection mutations. Executable changes
complete the catalog and validate it at analysis entry; tooling records exact
permissions. Tests add nine focused suites and a reusable acceptance fixture
helper, and update catalog/non-execution/sugar/boundary cases. Documentation
adds the full audited inventory and this evidence. Core/effects/runtime code,
ordinary source execution, grammar, launcher, version, dependencies, and release
assets are untouched in this phase. No public checking command exists yet.

## Phase 4 — Deliver exact reports and the real checking command

**Purpose:** expose the established backend without changing ordinary execution.
**Prerequisites:** Checkpoint 3.

- [x] **4.1a — Compute exact complete-source coverage and final status.**
  **Work:** Finalize source-node and definition states from the established proof data, retaining all registered source obligations and the closed verdict precedence. Keep local self assumptions separate from external gaps.
  **Check:** Exact-count fixtures cover literals/apps/list/let/lambdas, data definitions, nested/unused bodies, empty modules, and rounding traps. A bad call preserves its valid function's declaration count; an incomplete top-level expression prevents FULL PASS. A missing source ID, pending catalog entry, or unfinished solver item is operational failure, never silently excluded from the denominator.
  **Evidence:** `coverage.rkt` validates exact declaration/node identities, final
  monotypes versus incomplete proofs, child/dependency closure, and bounded
  primary-reason paths. `step-4.1a.log` passed 152 reported coverage/boundary checks
  and the complete boundary gate. All semantic fixtures survive final accounting;
  exact tiny counts match the specification. The 5001/5003 established-expression
  fixture displays 100.0% while remaining PARTIAL. Corrupt/missing/unfinished
  states fail internally; a 45-binding shared graph retains one path per binding.

- [x] **4.1b — Render types, primary diagnostics, and bounded dependency explanations.**
  **Work:** Render original file/line/column, enclosing binding/lambda, reason code, established expected/actual types, and one deterministic path per dependent definition. Separate conditional hints from verified signatures and output from computation.
  **Check:** Golden reports are stable across repeated checks and preserve positions across CRLF/Unicode/tabs/comments/shadowing. Control characters in names/paths are escaped. Large alias graphs do not enumerate exponentially many paths. Reports never expose arbitrary internal exception text or imply that source coverage certifies the trusted library.
  **Evidence:** `step-4.1b.log` passed 154 reported report/display/boundary checks
  and the complete boundary gate. Golden complete/empty reports, actual CRLF/tab/
  Unicode argument positions, anonymous lambda spans, control escaping, repeated
  checks, and a 36-binding shared graph pass. Incomplete signatures are omitted;
  primary reasons and one dependency path remain visible. Expected/actual types
  share a stable variable-name map. Rendering only constructs host strings.

- [x] **4.2 — Integrate `--check` with precise launcher and output failure handling.**
  **Work:** Add the exact invocation, help text, embedded lazy-load reference if needed, exit mapping, and narrow boundary-vocabulary updates. Leave file/REPL dispatch unchanged. Finalize analysis before report emission and require successful emission/flush before exit 0.
  **Check:** Real subprocesses via `racket runner/attalambda.rkt --check ...` verify 0/1/2 and 64/65/66/70. Missing/extra paths, duplicate/incompatible flags, and private injected source/frontend/internal faults map correctly. A broken report sink cannot return 0 or replay output. Do not add public failure-injection switches or import the auto-running launcher as the backend.
  Split before implementation to keep the command and launcher checks focused:
  **4.2a:** create the private command pipeline with one validated snapshot,
  structured completion, safe operational diagnostics, owned-resource cleanup,
  output/flush handling, and private test seams; verify directly with controlled
  faults. **4.2b:** integrate the real launcher and exact boundary permissions,
  update shared help expectations, and exercise the complete subprocess status
  matrix with those private seams. Both are required to close 4.2.
  **4.2a passed:** `step-4.2a.log` records 151 command/boundary checks and the
  complete gate. One captured snapshot is used even when the backing test file
  changes after inspection. Source faults remain 65/66; injected metadata,
  pending-catalog, syntax/filesystem analyzer faults, and broken report writes/
  flushes return 70 without leaking internal details or replaying output. Owned
  resources close and caller ports stay open. Next: real launcher integration.
  **4.2b passed:** `step-4.2b.log` records 150 CLI/boundary checks and the complete
  gate. The real launcher returns 0/1/2 for all fixed semantic fixtures, 64 for
  invalid flag combinations, 65 for whole-source faults, 66 for absent/unreadable/
  symlink/dotenv paths, and 70 for injected analyzer/metadata/catalog/output
  faults. Faults use only a test driver around the actual launcher. Linux/macOS/
  Windows consumer help expectations add the shared invocation; native consumer
  runs remain pending. File and REPL dispatch branches retain their behavior.

- [x] **4.3 — Prove CLI non-execution, interruption, and repeated-run isolation.**
  **Work:** Run the existing effect/divergence fixtures through the real CLI. Exercise a controlled interruption during analysis and a report-delivery failure separately. Reuse the backend twice in one test process to reveal stale state.
  **Check:** No program output/input/file/network/history effect occurs, including invalid-late-form cases. Interrupted analysis returns 130, cleans owned resources, and emits no completed analysis report. Interrupted delivery is nonzero even if earlier report bytes exist. Do not demand impossible output retraction or disable cancellation around blocking writes. Inspect rendered diagnostics as well as structured results.
  **Evidence:** `step-4.3.log` passes four real-CLI cases. Actual source effects,
  input position, guarded data reads with a positive control, marker-file state,
  a ready ephemeral loopback listener with a positive connection control, absent
  history state, exit, divergence, and invalid final forms are observed. A real
  subprocess interrupt after the private analyzer readiness signal returns 130,
  closes its owned thread, and emits no report. A break queued by the final
  custom-port flush returns 130 after one report, without replay. Repeated
  backend/report equality remains covered by 3.8, 4.1a, and 4.1b. No product fault
  flag or environment switch is introduced.

**Checkpoint 4 — User-facing gate.** Run report/CLI tests and affected existing interactive/file-mode tests, full suite, and gates. Existing `attalambda FILE.attl`, help/version, and REPL behavior remain intact. Review exact status/coverage semantics, escape handling, and untouched runtime behavior. The checker itself never executes the analyzed file.

**Checkpoint 4 passed.** `phase4-full.log` records one successful isolated
Racket 9.3 `./run-all-tests.sh` run: 102 Racket test files, 26967 reported Racket
tests, 49 Python terminal methods, 40 pure production modules, and the complete
boundary gate. It includes all new report/CLI suites and existing file-mode,
interactive, terminal, runtime, distribution-contract, and embedding regressions.
`phase4-result.json` verifies 218 executable inputs against the staged snapshot,
including native consumer scripts and public examples. Evidence remains under
`/tmp/attalambda-static-implementation-mmgdshl_/`.

Fresh self-review (`phase4-review.md` there) covered exact counts/statuses,
incomplete-dependency closure, safe deterministic diagnostics, one-snapshot
non-evaluation, output failure/cancellation, ownership, and scope. No open
finding remains; no independent review is claimed. Executable changes create
coverage/report/command helpers, extend private type display and exact launcher
dispatch, and update exact tooling permissions. Six focused suites plus a
private fault driver were added; existing runner/native-consumer help assertions
were updated. PLAN/HANDOFF record the evidence. Runtime implementations, grammar,
type tags, ordinary file/REPL branches, version, dependencies, and published
artifacts are unchanged by this phase. Final Linux candidate testing is next;
macOS/Windows consumer execution is not claimed.

## Phase 5 — Verify realistic use and the exact standalone candidate

**Purpose:** finish documentation, full corpus evidence, cold review, and a tested deliverable.
**Prerequisites:** Checkpoint 4, authorized local commits, and the confirmed Linux consumer environment.

- [x] **5.1 — Measure the complete existing example corpus.**
  **Work:** Analyze every current public `.attl` example and the minimum acceptance fixtures. Record status and every gap/conflict reason, distinguishing intentional dynamic/error demonstrations from regressions.
  **Check:** Every file is accounted for; supported fixtures fully pass and known limitations are accurately classified. Compare with the early pilot. Do not rewrite examples/signatures to improve percentages or silently skip files. No arbitrary coverage target is imposed.
  **Evidence:** At `61a87c2`, all five examples ran through actual `--check`
  without execution or source edits. hello/stdout fully pass (3/3 expressions
  each). foundations is partial (126/138), file-round-trip partial (24/32), and
  http-server partial (134/199); none has a conflict. All 13 primary gap regions,
  declaration counts, reasons, locations, dependencies and example hashes are
  retained in [the measured corpus](docs/static-checking-corpus.md). Logs and
  machine-readable results are `step-5.1.log` and `corpus-results.json` in the
  evidence directory. The 25 semantic fixtures already pass the same source
  revision's real CLI and backend checkpoints; the seed pilot remains historical.

- [x] **5.2 — Document the feature and exact limitations.**
  **Work:** Update relevant README/API/architecture/getting-started material with invocation, statuses, trust scope, inferred types, restricted data, and Error/variant limitations. Identify the capability as unreleased source/candidate work.
  **Check:** Examples are exercised; links/commands exist. The public 0.8.0 binary is not claimed to contain the feature. No claim of termination, all-error freedom, erased runtime tags, or whole-runtime formal verification appears.
  **Evidence:** README/API/architecture, the actual guide template, distribution
  contract and acceptance map now distinguish the unreleased local checker from
  public 0.8.0. The API's new example fully checks with its exact documented
  identity/apply/double signatures (3/3 definitions, 14/14 expressions). All 212
  local links across seven relevant documents resolve; existing distribution
  tests pass 217 checks. Log: `step-5.2-final.log`. The initial test command named
  a nonexistent `api-test.rkt`; that command-selection error was corrected to the
  actual distribution suite, with no implementation change. Guide commands are
  also exercised by the forthcoming real consumer.

- [x] **5.3 — Extend the real standalone consumer.**
  **Work:** Add compact full/partial/fail/invalid/no-effect check-mode fixtures to the existing Linux consumer. Verify embedding of checker/frontend dependencies. Preserve other native builders/CI; change only acceptance inputs necessitated by the shared launcher.
  **Check:** Static distribution tests cover new inputs. Consumer tests use the delivered executable and temporary source only: no Racket install, checkout, network fetch, or personal configuration. Dependencies/notices remain unchanged absent an evidenced necessity. Source-only tests cannot replace consumer acceptance.
  **Evidence:** The existing Linux consumer now calls one inline Python-stdlib
  acceptance block before and after relocation. It checks full/fail/partial/
  empty/invalid cases, misuse/path statuses, exact counts/signatures, no effects,
  actual input position, a blocking FIFO data-read probe, loopback positive and
  negative controls, absent history, real `/dev/full` status 70, and interrupted
  pipe delivery status 130 after an observed first report byte. Its assertions
  passed against the real source launcher in `step-5.3.log`; this is deliberately
  source-only preparation, not standalone evidence. An assertion initially ran
  before its existing helper definition; the evidenced test-ordering correction
  passes all 223 distribution checks and both gates (`step-5.3-final.log`).
  The final delivered-command runs and embedding proof remain Steps 5.5a/b.

- [x] **5.4 — Review the final implementation afresh and freeze tested inputs.**
  **Work:** Prefer independent read-only counterexample review; otherwise label self-review honestly. Inspect contract, diff, tests, scope, and unused abstractions. Correct evidenced findings narrowly.
  **Check:** Address binding impersonation, gap laundering, Error alternatives, generalization/recursion, non-execution, and embedding. Each finding has a disposition; no minimum finding count. Run corrections' focused tests and the complete required suite on final inputs. Close a clean local source commit under project rules before building.
  **Evidence:** Fresh self-review (`phase5-review.md`) revisited the frontend,
  kernel, all contracts, proof/coverage, command, consumer, documentation and
  A01–A26 mapping; no finding remains open and no independent review is claimed.
  The final `./run-all-tests.sh` exited 0: 102 Racket test files, 26973 reported
  tests, 49 Python terminal methods, purity over 40 modules, and complete source
  boundaries. `phase5-full.log` and `phase5-result.json` retain results and 223
  matching executable/packaging input hashes, including the guide and consumer.
  No executable input changed during the run. The local source commit closes
  this step; its exact identity is recorded in the external candidate receipt
  before the builder starts. Only delivery-record edits may follow that build
  without repeating affected executable/build/consumer checks.

- [x] **5.5a — Build the exact clean, local candidate.**
  **Work:** Record the reviewed source SHA/runtime identity and build with the known builder into a fresh external directory, without `--allow-dirty`. Confirm that the checkout/ref was not changed by another process during preparation.
  **Check:** Record archive SHA-256 and build evidence; every executable/embedded input belongs to the recorded source. Current-version metadata is explicitly labeled an unpublished feature candidate, not the public asset. Preserve unrelated work and existing candidate outputs rather than overwriting them.
  **Evidence:** Clean local commit `576d8837797f254fb068d19fd839ea1174e28151`
  was cloned without checking out dotenv paths. All 223 tested inputs matched;
  owner checkout and clone retained that HEAD and clean status before/after the
  normal builder, with no `--allow-dirty`. The corrected isolated Racket CS 9.3
  build exited 0 (`candidate-build.log`). The 19,870,393-byte archive is
  `/tmp/attalambda-static-implementation-mmgdshl_/candidate-g7g7_p8u/attalambda-0.8.0-linux-x86_64.tar.gz`;
  SHA-256: `80c08ff21090d3b725a5c6df50b56783c5f434b5129dd60fc423c2abe35a3816`.
  Its manifest names that clean source; its guide explicitly identifies an
  unpublished feature candidate with retained 0.8.0 metadata. An initial
  temporary receipt assertion omitted the guide's words `optional-static-checking`;
  direct archive/template inspection established the mismatch and the exact
  wording passed. No source, artifact, or consumer logic changed.

- [x] **5.5b — Verify the transferred standalone artifact.**
  **Work:** Transfer that exact archive to the isolated consumer and run the extended new check-mode and existing file/REPL acceptance. Use only the delivered executable and synthetic source fixtures.
  **Check:** Verify archive digest before/after transfer and record consumer environment plus `consumer_acceptance=passed`. Include complete, conflicting, partial, invalid-source, and no-effect fixtures. Any code/build-input or consumer-logic correction requires affected rebuild/retest evidence. Report unavailable native-platform checks separately; do not claim the current archive came from a later handoff-only commit.
  **Evidence:** The exact source clone's existing extended consumer exited 0
  (`candidate-consumer.log`): `static_checking_acceptance=passed-at-both-paths`
  and final `consumer_acceptance=passed`. The original, transferred and final
  archive digests match. Both 25-method CLI/transcript runs passed (64.927s and
  67.255s), alongside guide/public API, file/network/exit, check-mode statuses,
  no-effects, actual failed output and interrupted delivery, and relocation.
  The consumer had no Racket/raco or checkout; Ubuntu 24.04, Python 3.12.3,
  read-only root, UID/GID 65534, no external network. Its actual prepared image
  is `sha256:f79d9f4012586a4c571e94f0dbcf295cc85a55e9e0f1d79e9f71f9ef2c4c9644`.
  Native macOS/Windows checks were not run; Linux x86-64 remains the supported
  binary target. `candidate-source.json`, `candidate-result.json` and the copied
  build manifest retain exact provenance. The archive predates this record.

- [x] **5.6 — Close the handoff and clean owned resources.**
  **Work:** Update the existing durable plan/handoff with Section 10's source, test, review, coverage, artifact, limitation, and authority records. Clean only owned probes/containers/transfers.
  **Check:** Distinguish the tested build source from later record-only commits. Every acceptance item has evidence or an explicit blocker/next step. Preserve unrelated work and existing releases. No push, PR, merge, tag, asset replacement, or publication occurs under the default endpoint; follow project gate rules for any final record-only commit.
  **Evidence:** HANDOFF.md and docs/ACCEPTANCE.md now close the A01–A26 map,
  source/tests/self-review/corpus/contracts, exact artifact, limitations and
  authority. The owned implementation container was stopped and removed; the
  consumer container and transfer directory were verified absent. Images,
  snapshots, logs and the candidate are retained. Only these three record files
  change after the build; executable/packaging hashes, local links, whitespace,
  local main and final clean Git state are checked before closing the record.
  Its own commit identity is saved in the external `state.json`, avoiding a
  self-referential commit. No blocker, deferred implementation, or owner action
  remains within this local-only assignment.

**Checkpoint 5 — Delivery gate.** Completion requires final-input tests, disposed review findings, full-corpus results, and the exact digest-identified standalone candidate's consumer evidence. Missing infrastructure/authority is reported as a blocked gate, never a passed check. Finish independent safe work, record the precise next step, and stop at the authorized local candidate.


---

# Historical plan — Interactive AttaLambda, published 0.8.0

# Interactive AttaLambda — published 0.8.0

Kyle authorized phases 0–11 of the [supplied contract](docs/interactive-implementation-spec.md)
on 2026-09-14, including isolated dependencies, tests/builds, milestone commits/pushes,
and a pull request. That candidate checkpoint is complete. Kyle subsequently
authorized Phase 12 with “lets do it” after merge, rebuild/verification, tag,
publication and public-download verification were explicitly described. Phase 12
is authorized for 0.8.0 only; its public-download verification has passed.
Older releases and assets remain intact.
Execute steps serially, subdividing oversized steps before implementation. Each
phase closes only after focused checks, the full suite, both structural gates,
and its scoped review. Historical plans below grant no additional authority.

## Starting state and scope

Clean input branch `terminal-input`: `62d0f0cf7e042bd6478024697c460c9fc88b50f7`.
Local/remote main: `71232f7fb47f8daad61e6a7a6bcf4a5477532352`. Latest release:
[v0.7.0](https://github.com/kserrec/attalambda/releases/tag/v0.7.0), published
2026-09-09T10:54:27Z; tag object `4d69bcba41bc667cef53f6d260f213880f3e5e2d`.
No existing interactive PR or intervening source work was found. The milestone
branch is `interactive-attalambda`, starting at the complete input implementation.

Modify the existing expander, runner, exact boundary checks, package/distribution
inputs, tests, version metadata (in Phase 9), and current documentation. Create
restricted source/session/editor/history helpers only where a demonstrated boundary
needs them, focused regressions and PTY fixtures, and the saved contract. Core,
effects, runtime input, codec, representations, language computation, and old file
execution remain behaviorally unchanged. Existing input code is preserved. Generated
interaction exports stay private. Every new source has an exact classification.
Never inspect dotenv contents or add Graphify output; never overwrite unrelated work.

## Evidence and exact next step

**0.8.0 is published and its fresh public download is verified.** The remaining
publication-record commit/push, exact-head CI and final review are reconciled
after this file is committed in `/tmp/attalambda-080-release-state.json`.
Its `next_unfinished_step` and `status` govern resumption; `status=complete`
means no unfinished release step. This avoids attributing the archive to a
later documentation commit or recursively committing its own hash.
Release389458950 was published at2026-09-15T20:32:24Z and is latest:
https://github.com/kserrec/attalambda/releases/tag/v0.8.0 . Annotated tag object
8628ca652e7ebf9ff3932d332fc57b611e3fd023 points to the clean merged/build source
f309199baa170ba5b12ff6b18b60dc49c114a8a1. All ten merged CI jobs pass.
The local release consumer passes both25-method runs; independent artifact review
is closed. Both uploaded digests and authenticated draft downloads match the
verified local files. Fresh unauthenticated public files returned200 and match
both hashes. Their local0664 modes reflected host umask002; the consumer's exact
0644 precondition stopped before starting a container. Removing group-write on
these two owned files preserves all bytes and checks. The failed receipt is
retained. The unchanged public consumer passes all 25 methods once at both
paths in 52.529s and 59.059s. Independent public review is closed at
`/tmp/attalambda-080-public-review-1tngp_s6/review.md`. All six earlier releases,
twelve assets and six tags are preserved. Owned containers/transfers are removed.
Live effect receipt: `/tmp/attalambda-080-release-state.json`; do not repeat
publication or reuse an active consumer/output path. The old3ae3926 candidate
remains historical. No new product source or dependencies changed.

The Phase 9 complete run `/tmp/attalambda-interactive-phase9-full.log` finished 0:
69 Racket test files, 26,845 assertions, 43 shared terminal methods in 71.605s,
6 visual methods in 5.733s, 40 pure production modules and the full boundary gate.
Afterward, only two Linux CI setup blocks changed; their affected distribution
suite passes 217 checks in `/tmp/attalambda-phase9-ci-ownership-focused.log`.

The earlier CI run, 34994217012, passed all Windows/macOS builds,
consumers and artifact cleanup. Its Linux preparation failures are diagnosed:
the newly installed Racket directory was root-owned. The correction transfers
only `/usr/share/racket` to the disposable job's user, then performs ordinary
preparation and compilation. Independent original-image checks prove the actual
compiler and all 15 preparation regressions pass with default caches. The final
frozen-source CI also passes. Full diagnosis logs and review are in
`/tmp/attalambda-phase9-checkpoint-review-7jrtn7b_/`.

Completion, bounded history, source/program input, cancellation, standalone loads
and output separation are implemented. Independent current-source review is
closed at `/tmp/attalambda-phase10-independent-review.md`; its 18-file hash
manifest still matches. The reviewed dependency patches, exact runtime checks,
notices and all three builder contracts remain unchanged from Phase8. The Linux
consumer now supplies UTF-8 only to its two terminal-test invocations.
The corrected temporary candidate drivers have independent source review at
`/tmp/attalambda-interactive-candidate01-review.md`; both completed successfully
and their exact output is independently reviewed in Phase 11.

Reuse the prepared consumer image
`sha256:dabaae31057cbc79baf7e2afa65b8c8cfd378b5013e4e8a95a520265fc794803`.
Development08 predates final source and is not a candidate. The final clean
archive has its own passing evidence. Only the documentation record and its
post-commit current-head reconciliation remain before delivery.
No source suite or owned container is running. The independent CI setup probe
also passed actual package setup, executable embedding, distribution, version and
transcript smoke checks; its finalizer removed the container. HANDOFF.md records
exact next actions and artifact driver paths. No merge, tag or publication.


Patch-format whitespace check: the staged whole-diff check reports18 whitespace
lines, all validated as unchanged unified-diff context in the two SHA-pinned
dependency patches (blank context markers and existing upstream indentation).
No added patch source line is implicated. Source whitespace passes with patch
serialization paths excluded; exact patch application/source hashes remain checked.
No source rule or acceptance test was weakened.

Phase 0 records context/ref/environment checks and preserves canonical bytes.
Untouched source verification: `TMPDIR=/tmp ./run-all-tests.sh`, Racket CS 8.10,
log `/tmp/attalambda-interactive-baseline.log`: exit 0, all 49 suites, 17,611 reported tests,
40-module expanded purity, and complete source inventory/boundaries pass.
Approved release runtime: cached `racket/racket:9.3-full`, image
`sha256:f9c540abe281413dc9e25bfbe6e35276f1a5bca1fa40213c40ac7bac6bb69c62`.
Docker and Python PTY facilities are available. Its Expeditor 1.2 depends on base
>=8.15.0.10 and syntax-color-lib >=1.3; use CS 9.3 for integration and release.
Local isolated development runtime is under `/tmp/attalambda-racket93`.
No personal Racket configuration is changed. The relocated library cache and package
command index were mapped/copied from the same image; `raco make` and package discovery
now pass. A Python-controlled PTY running CS 9.3 proved input, normal exit, terminal
state preservation, and explicit descriptor cleanup. Build/consumer acceptance is pending.

Independent read-only Checkpoint 0 review (`baseline_review`) close-read the contract,
active records, runner, expander definition/dependency/sugar path and exact runner
boundary/source inventory. It found no scope conflict. It requires only the scoped
canonical tooling amendments below and fresh host instantiation for reset. Other
algorithms and packaging execution were outside its scope; no implementation was
presented as reviewed. Available bughunt instructions supply proof/coverage discipline;
terminal and release checkpoints use the contract's explicit evidence procedures.

Phase 0 output checks: `python3 /tmp/attalambda-check-interactive-docs.py` passes
all three prior-byte preservation/hash checks, exact saved-contract comparison and
active documentation links. The first link probe included an unavailable historical
Downloads link; its scope was corrected to active records, preserving history.
The independent reviewer checked the amendment text and preservation procedure.
Only documentation changes in this phase; production and test inputs match the
untouched passing baseline.

### Phase 0 — Establish a safe, reproducible starting point

**Purpose:** know the actual repository state and toolchain before changing it.

- [x] **0.1 — Read the governing project context.** Read `AGENTS.md`, the active plan, specification index, input contract, and current release ledger. Record applicable restrictions and the intended milestone workflow; do not treat completed historical plans as current instructions. **Check:** the short baseline record identifies the correct language authority and the input feature to preserve.
- [x] **0.2 — Resolve current source and release refs.** Inspect repository status, current branch, input branch, main, latest release/tag, and any relevant existing PR. Compare ancestry to the pinned baseline without inspecting dotenv contents. **Check:** record exact SHAs, relevant intervening changes, and whether work already exists; never create a duplicate milestone blindly.
- [x] **0.3 — Establish the execution environment.** Confirm source-test tooling, Racket version, the project's supported build runtime, and available container/PTY facilities. Discover relevant available skills. Use isolated temporary package/user homes for probes; do not modify the owner's normal Racket configuration. **Check:** run the untouched full suite and both gates, separating observed failures from historical evidence.
- [x] **0.4 — Establish the milestone workspace.** When implementation/Git actions are authorized, create or reuse one milestone branch containing the input work without rewriting it. Preserve unrelated working changes. **Check:** compare its base and initial diff to the recorded source; no release artifact, tag, or main-branch write has occurred.
- [x] **0.5 — Install the active plan and scoped amendments.** Save this contract in a suitable docs location, link the active phase list from `PLAN.md`, and add only necessary canonical tooling-boundary amendments using the repository's existing preservation/hash procedure. **Check:** old specification content is preserved, index hashes and local links match, and the new active plan grants no accidental publication authority.

**Checkpoint 0 — Baseline/authority review.** Use repository-onboarding or planning review if available; otherwise compare the baseline and proposed scope directly. Close this phase only with a reproducible environment and no unexplained baseline failures affecting the milestone. A missing final packaging environment may be recorded for later provisioning, but must not be disguised as a passed consumer test.

### Phase 1 — Prove the two risky integrations early

**Purpose:** validate library behavior before committing to substantial UI or session plumbing. Keep probes tiny and isolated; retain useful regressions, not a second implementation.

Execution subdivisions: 1.1a creates the bounded reusable Python PTY harness and
test-only editor fixture; 1.1b verifies startup, acceptance, controlled open failure,
terminal restoration and no initialization-file execution. 1.3a covers paste and
pending bytes; 1.3b covers interruption and intentional harness-failure cleanup.
1.4a establishes lazy transport; 1.4b verifies cached input across module imports.
Test-only editor dependencies are declared with the probe; Phase 8 moves actual
production dependencies into `deps`. All integration work uses CS 9.3.

1.1 evidence/deviation: the first PTY probe observed `expeditor-open` returning
false when `current-output-port` is stderr. Fresh-process controls in both the
relocated runtime and stock 9.3 container return true with stdout and false with
stderr. Racket v9.3 `racket/src/ChezScheme/c/expeditor.c:811–824` explicitly rejects
output descriptors other than 1 (and requires input descriptor 0). The documented
port API alone cannot implement the fixed stderr UI contract. Substep 1.1c therefore
proves a narrow dup/dup2/close adapter that routes native stdout to stderr only
during editing and restores it before execution, including failure/break paths.
It adds no terminal driver, new input channel, or program effect. Exact native
capabilities must be classified if promoted in Phase 8. The first probe failure
log is `/tmp/attalambda-interactive-1.1.log`; native source snapshots are in
`/tmp/attalambda-racket93-terminal.ss` and `/tmp/attalambda-racket93-expeditor.c`.

- [x] **1.1 — Open and close the real editor.** In the supported Racket build runtime, initialize Expeditor with explicit safe hooks and `atta>`; accept one entry and close it. Exercise initialization failure through a controlled test seam. **Check:** terminal state is restored and the editor does not load user initialization files.
1.1 complete: `ATTALAMBDA_TEST_RACKET=/tmp/attalambda-racket93/bin/racket python3
tests/interactive_pty.py -v` passes 3 cases (1.839 s), log
`/tmp/attalambda-interactive-1.1-final.log`. Real editing, controlled failure,
synthetic initialization non-execution, terminal state and redirected stdout
restoration pass. Changed test paths: `tests/interactive_pty.py`,
`tests/fixtures/interactive-editor-probe.rkt`, `tests/helpers/editor-descriptors.rkt`.
`info.rkt` and the exact package metadata boundary declare test dependencies.
Expeditor handles a deep terminal protocol; Python uses no external dependency.
Uncompiled source sizes in the approved image are 208 KiB (expeditor-lib) and
152 KiB (syntax-color-lib); base/syntax-color are its dependency closure. Final
bundled size/notices are still a Phase 9 check, not claimed here.

- [x] **1.2 — Prove editor-to-program input handoff.** Extend the probe with an entry handler that invokes the existing AttaLambda input path through a tiny fixture, then returns to editing. Do not build a general evaluator yet. **Check:** one answer reaches the program exactly once, is not added as source history, and the next expression can be edited.
1.2 complete: the actual public input wrapper, pure renderer and String reader
return `OK(SOME("unique-answer"))` once, restore editing and exclude the answer
from history. Focused case `EditorProbe.test_program_input_then_editing` passes,
log `/tmp/attalambda-interactive-1.2-final.log`. Startup failures were observed
8.10 `.zo`/9.3 runtime mismatches; `raco make tests/fixtures/interactive-editor-probe.rkt`
with CS 9.3 rebuilt ignored outputs and fixed loading. The later failure was only
the test expecting oldest-first history; observed Expeditor order is newest-first.
No input/renderer production code changed and no deadline increased.

- [x] **1.3 — Exercise type-ahead and cancellation in the probe.** Drive the probe through a PTY using ordinary typing, a multiline source paste, an answer sent after the accepted entry, and interruption during a blocked read. **Check:** distinguish already accepted source from pending program bytes; prove no dropped/duplicated bytes and no stuck terminal mode. Use event-based readiness and bounded cleanup, not sleeps as proof.
1.3 complete: two pending-byte/paste cases pass in 1.083 s
(`/tmp/attalambda-interactive-1.3a.log`); source/blocked-read cancellation passes
(`/tmp/attalambda-interactive-1.3b-final.log`). The intentional harness failure
case closes its waiting process, PTY endpoints, process-event descriptor and stdout
pipe. Initial cancellation assertions were corrected to actual native behavior:
parenthesis flashing inserts cursor controls; Ctrl+C clears a nonempty entry
in place rather than raising a break. Both source and program cancellation remain
covered without time-based readiness assumptions. No input buffering adaptation
was needed for the tested type-ahead/paste path.

- [x] **1.4 — Prove module-instance retention.** Build the smallest trusted test harness with two fresh Racket modules using existing lazy AttaLambda values. Retrieve a lazy binding without forcing it and reference it from another module. **Check:** a saved effect runs once on demand, not on export discovery or import, and later use shares the same answer.
1.4 complete: `PATH=/tmp/attalambda-racket93/bin:$PATH
PLTUSERHOME=/tmp/attalambda-racket93-user TMPDIR=/tmp raco test
tests/interactive-modules-test.rkt` passes 7 assertions, log
`/tmp/attalambda-interactive-1.4.log`. Two trusted lazy modules preserve one saved
read across export discovery, import, and repeated demand. Input position remains
zero until demand and advances by exactly one answer. This test fixture does not
replace or bypass the planned checked production expansion path.

- [x] **1.5 — Prove lexical rebinding and reset isolation.** Extend only that harness with an old closure, a replacement binding, and a fresh session namespace. **Check:** the snapshot example produces `2` and `11`, and a new session does not share the previous stateful host instance. This is a plumbing proof, not permission to bypass the production expander.
- [x] **1.6 — Record the proven implementation choices.** Select documented editor hooks, source/program-port handling, and module-instance strategy from the evidence. Identify any narrow compatibility adaptation actually needed. **Check:** there is one intended engine and one intended editor adapter; no custom interpreter, terminal driver, or language change has slipped in.

1.5 complete: the same module fixture passes 14 assertions, including the old
closure returning `2`, the replacement returning `11`, a real ephemeral listener
in the original host registry, and an empty distinct registry in a fresh namespace.
Log: `/tmp/attalambda-interactive-1.5.log`; both custodians close in cleanup.

1.6 choices: one checked module per entry, actual lazy exports and lexical imports,
one fresh namespace/runtime graph per session, and explicit Expeditor reader,
readiness, lexer and post-skipper hooks. Never call its initialization convenience
function. Native input handoff passed without a replay buffer. Only the proven
stdout-to-stderr descriptor adaptation is needed. These are integration proofs;
private checked expansion, persistent history and packaged behavior remain pending.

Checkpoint 1 review found a real fixture defect: recurrence inside an exception
handler inherited disabled breaks, so the second blocked read ignored Ctrl+C in
3/3 independent probes. The handler now returns before recurrence. The permanent
PTY cancellation case repeats cancellation twice; all eight cases pass in 6.117 s
(`/tmp/attalambda-interactive-1.3-review.log`). The ordinary-suite wrapper
`tests/interactive-editor-test.rkt` compiles for the selected runtime and runs those
bounded Linux checks; it passes (`/tmp/attalambda-interactive-editor-gate.log`).
Independent reviewer `editor_probe_review` verified the correction with twenty
consecutive cancellations and a fresh successful read; descriptor/thread counts
remain 7/1. It independently passed all fourteen module assertions and checked
custodian/input cleanup. No new findings in the scoped feasibility review.
The full phase suite is running on CS 9.3. Its initial attempt stopped before
assertions on ignored 8.10 compiled reader caches. Compiling the complete test/gate
set with CS 9.3 succeeded (`/tmp/attalambda-interactive-phase1-compile.log`);
this changes no tracked source. A later boundary test exposed the dynamically
loaded `lang/reader.rkt` cache, which was outside static test dependencies. After
`raco make lang/reader.rkt`, the focused boundary suite passes 145 assertions
(`/tmp/attalambda-interactive-phase1-boundary.log`). The full suite has restarted.
The preserved cache-failure log is `/tmp/attalambda-interactive-phase1-reader-cache-failure.log`.

**Checkpoint 1 — Integration feasibility review.** Use a focused architecture review and terminal-integration review. A cold reviewer should challenge stdin ownership, accidental forcing, captured bindings, and runtime sharing. Do not proceed with a handoff known to lose bytes or a reset known to share old host state. Resolve the minimal mechanism here rather than hiding the problem until packaging.

Checkpoint 1 complete: `PATH=/tmp/attalambda-racket93/bin:$PATH
PLTUSERHOME=/tmp/attalambda-racket93-user TMPDIR=/tmp ./run-all-tests.sh` exits 0:
all 51 suites, 17,626 reported Racket tests plus the eight Python PTY cases,
40-module expanded purity, and complete boundary inventory pass. Full log:
`/tmp/attalambda-interactive-phase1-full.log`. Independent correction/module
review has no remaining findings. `git diff --check` passes. Executable language,
effect, runtime, codec and launcher sources are untouched; this phase adds test
probes/harness and their declared build dependencies, exact metadata expectations,
Python-cache exclusion and evidence records. Phase 2 starts after this phase commit.

### Phase 2 — Implement one restricted source reader

**Purpose:** obtain well-defined entries without changing the language grammar.

Read-only design review (`reader_design_review`) verified native CS 9.3 behavior.
Use default reading parameterization plus explicit fixed readtable and extension
restrictions; parse fresh buffer ports, retaining original nested syntax locations.
Preserve source terminator bytes, strict-decode only collected bytes, and provide
buffer-end locations when native incomplete errors have no location. Expeditor's
reader hook must return inert data, not raise raw errors that it displays itself;
consume the whole buffer with post-skipper zero. Add hostile ambient parameters,
datum comments/here-strings/bar symbols, open-pipe invalid-UTF-8 answer preservation,
and quoted-spelling-only load argument tests. The launcher remains unchanged until
Phase 6; classify the exact reader helper now without broadening all runner files.

- [x] **2.1 — Parse a completed buffer with locations.** Add one helper that reads the entire supplied source buffer under the fixed safe reader configuration and returns located forms or a structured diagnostic. **Check:** exact Rats, strings, ASCII character literals, nested forms, and multiple forms parse without executing code; unsupported datums still fail at their existing stage.
- [x] **2.2 — Classify completeness and errors.** Distinguish empty/comment-only input, incomplete input, complete input, and genuine read failure using the native reader's behavior. **Check:** comments, escaped quotes, character literals containing delimiters, incomplete strings/block comments, and mismatched delimiters are classified correctly. Do not count parentheses manually.
- [x] **2.3 — Assemble plain source entries incrementally.** Collect source lines only until the current buffer is complete, preserving positions and consuming its own terminator. Decode only collected source bytes. **Check:** a following answer line remains available on the same input port, including when the pipe writer stays open.
- [x] **2.4 — Parse commands without evaluation.** Add fresh-entry recognition and exact argument validation for the six commands, reusing restricted string parsing for `:load`. **Check:** command-like text inside comments, strings, incomplete source, and program answers is not intercepted; trailing extra command arguments are rejected.
- [x] **2.5 — Connect editor readiness to this reader.** Use the same safe parser/completeness logic for Expeditor acceptance and the fallback. Prevent the editor's default reader or error path from bypassing extension restrictions or sanitized diagnostics. **Check:** a malicious reader directive is rejected during completeness checking as well as submission, and no fixture reader module executes.

Steps 2.1–2.5 implemented in `runner/source-reader.rkt`, with located native
syntax, strict UTF-8, default/fixed reader controls, native completeness, fresh
command recognition and incremental source bytes. Source physical lines end at
LF (preserving CRLF); a bare CR in a redirected source line is reader whitespace.
This source policy does not alter the existing program read's native CR handling.
The editor fixture now uses shared readiness; its reader hook still returns inert
whole-buffer text with post-skipper zero. No file-launch/runtime source changed.

Focused evidence: `raco test tests/interactive-reader-test.rkt` passes eleven
cases covering the parser matrix, source locations, hostile ambient settings,
open-pipe answer preservation, commands, extension non-execution and boundary
mutations (`/tmp/attalambda-interactive-2-reader.log`). The ordinary editor gate
passes nine PTY cases in 6.843 s (`/tmp/attalambda-interactive-2-editor.log`).
Exact source-reader imports/exports, reader controls/operations and vocabulary
are classified; unknown runner modules remain rejected. The existing boundary
fixture was updated to copy the new required helper and include its class after
its failures reported precisely those omissions. Its focused rerun passes all 145 assertions
(`/tmp/attalambda-interactive-2-boundary-suite.log`).

One new test initially missed its final closing parenthesis; the reader's line 87
error located it and the correction passed. A combined multi-file `raco test`
invocation failed before assertions in the relocated runtime's process mode;
individual invocations, matching the normal full-suite script, pass. No test
content or deadline was weakened to accommodate that environment failure.
Independent review and full phase verification are running before the phase commit;
full log `/tmp/attalambda-interactive-phase2-full.log`.

Independent Phase 2 review found two gaps, now closed. Native Unicode whitespace
was not recognized by command trimming/splitting; commands now use
`char-whitespace?`, verified independently across all 25 whitespace characters below
U+3100. The new gate initially counted reader controls without proving protected
execution. Independent copies moved controls into no-ops or returned a lambda,
local function or named-let function that read after restrictions ended, passing
the earlier checks and executing an ambient reader macro. The final gate pins the
exact approved defaults/parameterization/handlers/read-loop fragment alongside the
single-operation counts; no general dynamic-scope analyzer remains. All six
hoisting/function-escape mutations are permanent regressions.

Final independent recheck (`reader_design_review`) rejects the original named-let
bypass, accepts the actual safe helper, and passes all eleven reader cases. Both
findings are closed; no remaining finding in parser/commands/readiness/boundary scope.
Focused final logs: `/tmp/attalambda-interactive-2-review.log` (11 cases) and
`/tmp/attalambda-interactive-2-boundary-review.log` (145 assertions). The full phase
run completed successfully; the late gate refinement has focused reruns and passed
the full run's final structural gate. Earlier language/runtime
sources are unchanged.

**Checkpoint 2 — Reader correctness and extension-boundary review.** Run adversarial reader cases and affected existing reader/runner tests. Inspect all places that parse source, command arguments, and later history data; each must use an explicit restricted configuration. Confirm that terminal input remains in the host, while source input remains tooling.

Checkpoint 2 complete: the full CS 9.3 command recorded above exits 0 with
52 suites, 17,637 reported Racket tests plus nine Python PTY cases, 40-module purity
and complete boundaries (`/tmp/attalambda-interactive-phase2-full.log`). The final
exact-block gate refinement also passed focused 11-reader/145-boundary reruns and
independent original counterexamples. `git diff --check` passes. Changes create
one private source helper, its focused tests, shared fixture readiness and exact
boundary classification/fixture updates; object-language/host/codec/file-launch
behavior is unchanged. Phase 3 starts after this phase commit/push.

### Phase 3 — Add the smallest private interaction path

**Purpose:** evaluate a checked entry and retrieve results without duplicating language semantics.

Read-only Phase 3 design review (`interaction_design_review`) proved in isolated
CS 9.3 modules that fresh gensym module names, uninterned result-export discovery,
lazy dynamic retrieval, and shared ordinary user imports work. Static `only-in`
rejected uninterned result exports, so they remain runner-only; user exports retain
their ordinary source symbols. A private module-begin syntax property reaches the
transformer, and source-context identifiers match generated import binders. Native
quote/require/provide forms must come from transformer lexical templates, not user
context. Reuse the existing definition checker with retained-name context, excluding
superseded imports before graph analysis so a prior x cannot hide a new self-reference.
Use actual expanded define-values bodies for purity, including generated results.
The transformer prototype uses `#lang lazy`; comparisons show quote/require/
only-in/provide retain native bindings, so no extra native imports are needed.
Probe files: `/tmp/attalambda-phase3-name-probe.rkt`,
`/tmp/attalambda-phase3-user-import-probe.rkt`, and
`/tmp/attalambda-phase3-property-{lang,probe}.rkt`. No production interaction path yet.

- [x] **3.1 — Factor shared definition analysis only as needed.** Make the existing definition recognition/dependency checks reusable by the private interactive wrapper, preserving their lexical context. **Check:** existing file syntax, recursive-definition rejection, sugar, and shadowing suites remain unchanged in behavior.
3.1 complete: existing language suite passes 193 checks and sugar suite passes
157 (`/tmp/attalambda-interactive-3.1-{language,sugar}.log`). Definition recognition
and dependency checks accept retained-name context while preserving file defaults.

- [x] **3.2 — Expose lazy user bindings privately.** Add generated exports or equivalent trusted access for definitions from an interaction module. Keep the public language export surface unchanged. **Check:** discovering exports and retrieving a definition do not demand an input/output effect hidden in its body.
3.2 complete: direct private-module test passes; export discovery and dynamic
retrieval leave saved effects undemanded, and repeated demand emits once
(`/tmp/attalambda-interactive-3.2.log`). Exact public language exports remain pinned;
the targeted boundary gate passes. Native imports/provides come from transformer
scope; user forms retain their original syntax context.

- [x] **3.3 — Expose ordered expression results privately.** Generate result bindings that preserve the original lazy expressions and their source order. Keep native transport metadata outside object-language terms. **Check:** module instantiation alone does not prematurely force these results, while ordinary file modules still execute their normal force-and-discard path.
3.3 complete: three private-expansion cases pass (`/tmp/attalambda-interactive-3.3.log`).
Instantiation/export retrieval do not demand expression results, demand order is A/B,
repeated demand shares A, a delayed definition stays silent, and ordinary file modules
still force/discard their expressions. Result identities are private uninterned exports.

- [x] **3.4 — Evaluate one checked module in a session.** Add the minimal runner-side declaration/instantiation/result-demand path. Use fresh module names and the safe AttaLambda source context. **Check:** arithmetic produces the expected encoded value, expressions are demanded in order, and an expansion error anywhere in the entry prevents all its effects.
3.4 complete: three engine cases pass (`/tmp/attalambda-interactive-3.4.log`):
exact arithmetic, rejection before effects and ordered execution. The first numeric
test incorrectly observed a tagged object as a raw Rat; an isolated payload-accessor
probe returned 5/6 and 42, and correcting the test observer passed without engine changes.

- [x] **3.5 — Render supported results through the existing renderer.** Connect the pure `value-to-string` path and observation-side String reader, retaining the already computed result. **Check:** exact fractions, nested Lists/Options/Results, Maps, Errors, Strings, and Unit use canonical rendering, with no second evaluation and no codec import.
3.5 complete: five session cases pass (`/tmp/attalambda-interactive-3.5.log`),
including exact fractions, nested containers, Maps, Errors, byte-escaped Strings,
Char, Byte and Unit. Re-observing one stdout result prints once. Two test inputs
were corrected against the actual API/UTF-8 literal rules: make-ok is public;
source U+00FF becomes bytes C3 BF. No production formatter/representation changed.

- [x] **3.6 — Classify the new scaffolding precisely.** Extend boundary expectations for the new files/imports/exports and their narrowly required capabilities. **Check:** unknown source locations, unapproved production imports, and user attempts to access native `eval`, `require`, or port operations still fail closed.
3.6 complete: exact session imports/exports, native loader targets, source-context
construction and whole-entry expansion sequence are classified. The full boundary
gate passes, as do 145 existing boundary assertions and session mutation cases
(`/tmp/attalambda-interactive-3.6-{gate,boundary,mutations}.log`). Unknown runner
locations, native/codec imports, unexpanded eval and context attachment fail closed.

- [x] **3.7 — Check real generated terms for purity.** Feed actual interactive expansions through the existing purity-checking approach, isolating native module scaffolding as existing frontend tests do. **Check:** representative literal, sugar, `def`, and `rec` bodies contain only the allowed expanded computation; a deliberately forbidden computation fixture is rejected.

3.7 complete: four private expansion cases pass (`/tmp/attalambda-interactive-3.7.log`).
Every generated literal/sugar/def/rec/result body passes the unchanged expression
purity checker; native conditional computation fails its negative control. The
test spells the same trusted facade relatively, following sugar-test, because
the core gate deliberately rejects absolute `(file ...)` import chains. An isolated
probe established that only scaffolding path spelling differed; these are actual
private-transformer bodies under relative test plumbing, not the engine’s exact
absolute-path module syntax. The independent reviewer accepted that isolation.
No checker exception or object-language change was introduced.

**Checkpoint 3 — Language-equivalence and purity review.** Use a focused code/architecture review. Compare file and interactive expansion paths and their tests. Reject copied recursion logic, privileged scope accidentally attached to user source, eager transport conversions, and public export leakage. Close only after the full suite and both structural gates pass.

Independent Checkpoint 3 review (`interaction_design_review`) found no proven
issues after close-reading the complete session helper, expander delta/shared
analysis, exact session boundary and all three focused tests. Surrounding boundary
classes/source-reader were skimmed; retention/cancellation/UI/artifacts are outside
this phase. Its 28 additional scope/hygiene/shared-effect assertions are now
permanent regressions. Final independent reruns pass four expansion and seven
session cases; session boundary mutations also pass. The first full suite used
`/tmp/attalambda-interactive-phase3-full.log`; its corrected rerun is recorded below.

The initial full phase run stopped in host-test: the isolated package staging
list copied the new session helper but omitted readers/string.rkt. The exact
missing-module diagnostic proves the staging closure is incomplete. Added
`readers` to the fresh-install helper and all three matching distribution staging
lists; this narrow prerequisite moves forward from Phase 9, without any version
change or artifact claim. Focused host/distribution reruns precede the full rerun.
Initial failure log is retained at `/tmp/attalambda-interactive-phase3-full.log`.
Focused correction checks pass: host 81, distribution 209, and both shell-builder
syntax checks. Full rerun log: `/tmp/attalambda-interactive-phase3-final-full.log`.
Independent cold follow-up traced the String reader dependency closure, inspected
all four staging-list changes and searched their siblings. It found no remaining
omission or weakened dotenv/symlink/compiled-file exclusion. Version and release
capabilities are unchanged; final artifact/platform checks remain Phase 9–11 work.




Checkpoint 3 complete: the final full CS 9.3 rerun exits 0 with 55 suites,
17,649 reported Racket tests plus nine Python PTY cases, 40-module expanded
purity and all source boundaries (`/tmp/attalambda-interactive-phase3-final-full.log`).
Independent reviews and `git diff --check` pass. Executable changes add private
module expansion/session/result observation and the exact tooling class; package
staging now includes observation readers. New tests cover private expansion,
session execution and boundary mutations; existing staging fixtures are updated.
PLAN/HANDOFF record evidence and the upcoming forward-reference gap. Core, effects,
host, codec, public facade exports and old file-launch behavior are unchanged.
Phase 3 commit `fe70e6f` is pushed; continue 4.1 serially.

### Phase 4 — Retain definitions with precise session semantics

**Purpose:** grow from one entry to a persistent session without replay or mutable globals.

Read-only preparation while Checkpoint 3 runs: `reader_design_review` verified
explicit binding triples with the existing helper. Snapshots yield 2/11, saved
effects remain lazy across imports and run once, superseding self-reference is
rejected, and imported def/rec values become calls. Implement an immutable hasheq
of visible-name to module/export identity with one shell-owned mutable field;
construct candidate state before demand and protect only the final successful
field swap. Keep an explicit empty-import path for later standalone loads.
Names derive from committed keys without forcing. At that pre-implementation checkpoint,
the reviewer also compared direct forward aliases in real files/private
entries: `(def y = x) (def x = 7) y` fails identically during instantiation, whereas
`(def y = (add x 0)) ...` succeeds. Although inherited, the canonical purity amendment explicitly permits acyclic
forward references. Step 4.3 must therefore cover direct forward aliases and
expressions before a later definition; inheritance is not an acceptance exemption.
Investigate pure hygienic suspension in the private expansion path, retaining
existing dependency checks and the old file-launch behavior. No implementation
had occurred at that checkpoint; Step 4.3 below resolves the gap.
The isolated read-only probe `/tmp/attalambda-suspension-review.rkt` now proves
the minimal mechanism: after existing analysis, wrap each private declaration
body and generated result expression in a hygienic unary identity application.
Keep ordinary file forms unchanged. It resolves aliases/expression-before-def,
preserves identical function objects and one-time stdout/input effects, survives
lambda/held/def shadowing, and retains cycle rejection/rec. The three local lambda
bodies pass existing expanded purity; final in-repository literal/effect purity
is still required because the relocated facade is outside the gate’s path policy.


- [x] **4.1 — Retain and import committed binding identities.** Maintain the visible-name map and import references to existing module instances into the next entry. **Check:** definitions, functions, and retained partial applications remain usable across several entries without rerunning earlier expressions.
4.1 complete: runner/session.rkt now stores immutable visible binding identities;
prepare imports those actual modules, and evaluate-entry constructs/publishes one
candidate map after demand. Two focused state cases pass: retained definitions,
partial applications, lazy aliases and once-only input/stdout across entries.
The exact session boundary also passes (`/tmp/attalambda-interactive-4.1{,-boundary}.log`).
Atomic failure/interruption and metadata receive deeper tests in 4.5/4.6.

- [x] **4.2 — Implement snapshot redefinition.** New entries replace visible name mappings, not old language bindings. Resolve generated imports so local replacements do not conflict. **Check:** the `x`/`plus-x` example passes, old delayed expressions retain their environment, and duplicate definitions within one entry retain current rejection behavior.
4.2 complete: three state cases pass (`/tmp/attalambda-interactive-4.2.log`).
Old closures yield2, new x yields11, delayed old arithmetic yields101, and another
replacement preserves prior captured values. Duplicate declarations reject
without changing the committed map. Existing module-binding identities suffice.

- [x] **4.3 — Preserve name and recursion rules across entries.** Test unknown earlier names, permitted same-entry forward dependencies, recursive `def`, mutual cycles, and `rec`. **Check:** `(def x = (add x 1))` is rejected even with an earlier `x`; hidden dependencies in sugar do not bypass the checks.
4.3 complete: private declaration/result bodies now have hygienic pure unary
identity suspension after the unchanged dependency checker. Five state groups
pass, including direct forward aliases, early source expressions, shared lazy
stdout/input, unknown future names, sugar-hidden self/mutual cycles and rec.
Four actual expansion/purity groups and the exact boundary pass
(`/tmp/attalambda-interactive-4.3-{state,purity,boundary}.log`). Public/file paths
retain their original expansion branch; no host promise operation was added.

- [x] **4.4 — Preserve shadowing and hygiene.** Exercise shadowed public function/syntax names, including declaration-name shadowing where the current language permits it, across multiple entries. **Check:** recognition follows bindings rather than raw symbol spelling, and user names cannot capture generated result/import/export identifiers.
4.4 complete: seven state groups pass (`/tmp/attalambda-interactive-4.4.log`).
Imported def/rec/lambda/let/list/cond and native-looking names remain language
values; generated wrappers/imports/results resist capture. Function aliases are
the identical procedure, and shadowed syntax spellings cannot hide dependency cycles.

- [x] **4.5 — Commit new names as one small transition.** Prepare an entry's new map separately and publish it only after required execution/rendering succeeds; protect only the brief commit operation against partial interruption. **Check:** read/expansion/native/render failures expose none of the entry's new names, preserve previous names, and do not claim to roll back completed effects.
4.5 complete: eleven state groups and exact publication mutations pass
(`/tmp/attalambda-interactive-4.5-{state,boundary}.log`). Read/expansion rejection,
a trusted delayed native-failure injection, rendering failure after stdout and
a pending break all preserve the identical old map; later expressions stop and
completed output remains visible. Ordinary Error/Err values commit normally.
The candidate and consumer calls are outside break protection; only one final
setter is protected, and its entire approved function is structurally pinned.

- [x] **4.6 — Expose non-evaluating name metadata.** Provide the sorted committed name set for `:names` and completion, excluding private exports. **Check:** listing names never forces a saved read, lazy error, or function body, and failed-entry names never appear.

4.6 complete: twelve state groups and the full boundary gate pass
(`/tmp/attalambda-interactive-4.6-{state,boundary}.log`). session-names sorts
committed hash keys, exposes no private result exports or failed names, and
leaves saved input, lazy Error and function body untouched. An extra closing
parenthesis in the newly added test was identified by the native reader at line217
and corrected before this passing run. Independent `state_review` and the full
phase suite/gates are in progress; log `/tmp/attalambda-interactive-phase4-full.log`.

**Checkpoint 4 — State and laziness review.** Use a code review focused on instance reuse and binding publication. The strongest tests should deliberately include observable effects and failing entries, not just arithmetic. Verify the implementation neither concatenates history nor changes closures to read mutable top-level cells.

Independent `state_review` close-read the complete session helper, expansion and
dependency interactions, exact session boundary, and state/expansion/boundary tests.
Adjacent facade/boundary rules were skimmed; Phase 5 resources/CLI/artifacts were
not covered. No confirmed findings: independent 12-state/4-expansion/boundary
reruns and nine additional hunter groups pass. Its distinct shared-promise-after-
consumer-failure case is now permanent, extended to stdout and input; the final focused and independent reruns pass
13 groups (`/tmp/attalambda-interactive-4-review-regression.log`). Independent
close-read of the addition found no issue. The addition was made while fullsuite was still in the
earlier binary-Nat file, before its state-test invocation.

Checkpoint 4 complete: full CS 9.3 suite exits 0, all 56 suites, 17,662 reported
Racket tests plus nine Python PTY cases, 40-module purity and full boundaries.
Log: `/tmp/attalambda-interactive-phase4-full.log`. `git diff --check` passes.
Executable changes: immutable visible binding identities, single protected
publication, and pure private forward-reference suspension. Test changes: state,
actual private expansion and publication-boundary regressions. Documentation:
PLAN/HANDOFF evidence. No core/effect/host/codec or file-mode behavioral change.

### Phase 5 — Integrate input, cancellation, and session lifetime

**Purpose:** make interactive execution recoverable without changing existing input semantics.

Execution subdivisions: 5.2 first proves the live pipe, then adds a session mode
to the existing temporary editor fixture. 5.4 first verifies engine cancellation
using event-observed work, then prompt recovery through that fixture. 5.5 adds
child ownership and a success marker atomic with publication. Phase 7 replaces
the fixture loop with the production controller; no second engine is introduced.

- [x] **5.1 — Wire original process ports and session runtime ownership.** Initialize the shared runtime under session lifetime and parameterize actual entry execution with the correct process ports. **Check:** temporary parsing ports never become program stdin, and one session has one consistent host instance.
5.1 complete: session construction captures the caller's three standard ports;
entry execution explicitly uses them even under a temporary parsing port. The
focused captured-port test and exact boundary pass (`/tmp/attalambda-interactive-5.1-{input,boundary}.log`).
Runtime initialization remains once per fresh namespace under session lifetime.
Phase 4 commit `ba3d4c5` is pushed.

- [x] **5.2 — Integrate one live program read.** Connect the source engine to `(read-line UNIT)` through open pipes, then through the early editor adapter. **Check:** source terminators are consumed correctly, a partial answer blocks, one answer is returned exactly once, and the next source entry is readable.
5.2 complete: two input groups pass with event-observed partial reads and LF/CRLF
source termination; the writer remains open and following source is consumed only
after the answer. Logs `/tmp/attalambda-interactive-5.2-pipe.log` and
`/tmp/attalambda-interactive-5.2-pty.log`. The new session mode in the existing
editor fixture executes the checked engine; its real PTY test passes, returning
from one program read to a second source entry with correct history and restored
standard output/terminal mode. The fixture remains test-only until Phase 7's loop.

- [x] **5.3 — Prove lazy input reuse.** Retain a definition whose body reads input, inspect its name, demand it twice, and invoke a function containing a fresh read twice. **Check:** name inspection does not read; the retained answer is reused; fresh calls consume successive answers; an unselected branch performs no read. Reuse existing typing/byte/EOF/newline tests rather than rebuilding that operation.
5.3 complete: three live-input groups pass; definitions/name metadata and an
unselected branch finish with no supplied answer, a saved read reuses its first
answer, and two function calls consume the following two answers. Test-owned
workers have event deadlines and bounded cleanup. Log:
`/tmp/attalambda-interactive-5.3-input.log`. Existing byte/EOF/newline tests remain.

- [x] **5.4 — Add break-aware recovery.** Handle prompt cancellation and cancellation during expansion, infinite computation, rendering, and blocked input. **Check:** each returns to a usable interactive prompt and an unrelated earlier definition still works. Verify diagnostic context and terminal restoration; do not impose a universal computation timeout.
5.4 complete: three engine lifetime groups pass. A native test-only expansion
observer proves interruption inside expansion; two actual output calls prove
running recurrence and automatic raw-term rendering before interruption. A
consumed partial saved read retains its cached break without consuming the next
answer on retry; a fresh read and old=41 still work. No production worker/timeout
is introduced. The real checked-session PTY case passes four cancellations,
including two blocked reads, with old=41 after each, correct entry/rendering
context and terminal restoration. Logs `/tmp/attalambda-interactive-5.4-lifetime.log`
and `/tmp/attalambda-interactive-5.4-pty-context.log`. Final launcher diagnostics
and production prompt assembly remain the explicitly scheduled Phase 6/7 work.

- [x] **5.5 — Scope resources created by an entry.** Add the narrow custodian/worker ownership required by the proven design. **Check:** a failed entry's new listener closes, a previously committed unrelated listener survives, original standard ports remain open, and no cancelled worker continues reading or writing.
5.5 complete: every entry now owns a child custodian under its existing session;
shared runtime initialization stays outside. Prepare/demand/render no longer
override that child. The success marker and binding swap share one short protected
block, with exact structural mutations proving the seam is rejected. Five lifetime
groups and the full boundary pass (`/tmp/attalambda-interactive-5.5-{lifetime-final,gate}.log`);
mutation log `...-5.5-boundary.log`. Failed renderer/break cleanup closes only new
listeners; delayed allocations belong to demand scope, never replay; previously
committed listeners survive failed work and actual recursive/render cancellation.
The caller thread and original three ports survive. A break after successful
publication preserves its listener until explicit session shutdown.

- [x] **5.6 — Implement reset as genuine session replacement.** Shut down the old session and discard its namespace, visible-name map, runtime instance, and stored diagnostics. Retain shell preferences. **Check:** old names disappear, a listening port can be rebound, the new host registry is fresh, and input/history/echo ownership is still correct.
5.6 complete: reset prepares a fresh runtime/namespace under a candidate owner,
then swaps namespace/owner/empty bindings atomically. Its finalizer closes exactly
the displaced or abandoned owner. Seven lifetime groups pass: original names are
unknown, host registry starts empty, old listener closes/rebinds, new session can
create a live listener, input still works, and cancelled initialization preserves
old state. Real PTY reset preserves editor history and echo setting; logs
`/tmp/attalambda-interactive-5.6-{lifetime-final,pty,gate}.log`. The independent
`state_review` close-read found no issue and reran seven lifetime groups; its
`/tmp/attalambda-reset-design-review.rkt` additionally proves initialization failure
and deferred-break-at-swap with real resources. Caller invariant: reset runs in
the controlling shell outside the previous session custodian; no program can
invoke this tooling API. close-session also drops namespace and binding references.

- [x] **5.7 — Close cleanly on all exit paths.** Route ordinary quit/EOF, fatal failure, and valid language exit through the necessary cleanup, preserving language exit statuses. **Check:** terminal mode is restored and session resources close after normal success, `(exit 0)`, `(exit 1)`, and an injected native failure. Test processes must be isolated from the test runner.
5.7 complete: valid language exit raises a private non-exn:fail unwind request
inside the entry, allowing child/session/editor cleanup before the outer launcher
honors status0/1. Eight lifetime groups and the exact gate pass; the exit test
observes new listeners closed before catching the request while old ones survive
until session shutdown. Two PTY groups exercise exit0, exit1, injected native
failure70 and fresh EOF, with terminal and output restoration. Logs:
`/tmp/attalambda-interactive-5.7-{lifetime,gate,pty}.log`. The fixture outer loop
implements these integration exits; the actual CLI loop follows in Phase 7.

- [x] **5.8 — Measure repeated-use and reset behavior.** Run a modest reproducible workload, initially about 200 small entries mixing definitions, expressions, and rejected entries, across several reset cycles. **Check:** no worker/port accumulation, old session objects become reclaimable after references are dropped, and memory/latency observations show no unexplained severe growth. Record measurements without brittle universal timing/RSS thresholds; fix concrete retention bugs, not theoretical infinite-session limits.

5.8 complete: three cycles of 200 mixed definitions, rendered expressions and
rejected entries pass. Elapsed times9.147/9.135/9.210seconds; retained heap
131.157/131.386/131.452MB; after reset121.068/121.147/121.149MB versus initial
121.182MB. Process descriptors remain7. Old namespace and binding-table weak
references clear after every reset and final close; no session-owned thread/port
accumulation. These are observations, not universal timing/heap limits. Log:
`/tmp/attalambda-interactive-5.8-memory.log`. Permanent test preserves measurements,
weak-reference checks, resource checks and bounded owned-resource cleanup.

**Checkpoint 5 — Effects, interruption, and lifetime review.** Use systematic debugging for any failures, followed by a cold review of the port/custodian/namespace paths. Tests must include failure-path cleanup and actual PTY behavior. Explicitly check forced promises are not replayed after interruption and that cleanup does not accidentally close the shared session runtime initialized for earlier entries.

Checkpoint 5 cold `lifetime_cold_review` found no proven findings after close-reading
the complete session, exact gate, input/lifetime/memory tests, state delta and
editor fixture/PTY additions against contract§§3.6–4.3. Independent checks pass:
8 lifetime, 3 input and 1 boundary groups and all 5 new PTY cases. Memory test was reviewed,
not rerun alongside the local measurement. No extra hunter required retention.
The full suite completed as recorded below. Focused state/boundary and diff
whitespace checks pass.

Checkpoint 5 complete: full CS 9.3 verification exits 0 with all 59 suites,
17,674 reported Racket tests plus 14 Python PTY cases, 40 production purity
modules and full boundary/source inventory. Log:
`/tmp/attalambda-interactive-phase5-full.log`. Cold review and whitespace checks
pass. Executable changes: original port capture, entry-owned resources, atomic
publication/success marking, genuine reset and explicit-exit unwinding in private
session tooling; exact gate updated. Tests: input/lifetime/memory regressions,
state/boundary updates and five real-PTY integration cases in the existing fixture.
Documentation records measured evidence and remaining work. Object language,
effects, codec/host and existing file execution behavior remain unchanged from
the authorized input baseline. Phase 5 commit `4f29dd1` is pushed. Step 6.1 follows.

### Phase 6 — Load files and reuse diagnostics

**Purpose:** integrate standalone files without weakening the existing launcher.

Execution subdivisions: 6.1 first extracts the existing validation and small
syntax-diagnostic selectors, then verifies unchanged CLI behavior and the new
structured result/body coordinates. 6.2 adds an explicit empty-import evaluator
option and the single checked load route. No file is reopened after validation.
Step 6.1 verification passed; new source-file class is exact and runner filesystem
capabilities were reduced. Session composes validation and reading without gaining
native filesystem primitives; its load route is pinned by the boundary checker.

- [x] **6.1 — Extract only genuinely shared validation.** Refactor source validation so the file runner can retain its terminating behavior while the REPL receives structured failures. **Check:** existing file-mode path, encoding, declaration, status, and diagnostic tests still pass exactly where their contract is fixed.
6.1 complete: source-file.rkt returns the exact validated body and source position;
the original launcher retains its terminating policy and dynamic-require behavior.
Three new helper groups, 291 runner assertions, 145 boundary assertions and the
complete boundary gate pass (/tmp/attalambda-interactive-6.1-*.log). Source-file
has an exact class; the runner's old validation capabilities are removed.
- [x] **6.2 — Load a fresh standalone instance.** Read the validated file body with the fixed reader, preserve file locations, and use the private export path without ambient REPL imports. **Check:** file effects execute once in normal order, bare expressions are not auto-echoed, and undefined file names cannot be supplied implicitly by the session.
6.2 complete: load-source-file parses the validated body with its original path
and coordinates, then calls the same evaluator with empty imports and void consumer.
Five file groups and the exact session boundary mutations pass
(/tmp/attalambda-interactive-6.2-{file,boundary}.log): ordered effects, no raw-function
observation, no ambient-name resolution, whole-file expansion before effects,
CRLF locations and rejected reader/lang/compiled directives.
- [x] **6.3 — Publish loaded definitions on success.** Integrate the loaded module's definitions through the same snapshot/publication mechanism. **Check:** names are available afterward, failed files publish none, and loading the same path again deliberately reruns it while old closures retain old bindings.
6.3 complete: eight file groups pass (/tmp/attalambda-interactive-6.3-file.log).
Three same-path loads have distinct module identities and exactly three effects;
old closures/delayed values retain old snapshots. Read/expansion/recursion failures
and a real interrupted program read publish nothing; prior output survives the
interrupt and old bindings remain usable. Error/Err results permit publication.
- [x] **6.4 — Test file and working-directory boundaries.** Exercise quoted paths with spaces, relative paths, invalid extensions/declarations/UTF-8, rejected symlinks, and dotenv-path rejection without reading dotenv contents. **Check:** working directory and program-relative I/O semantics remain unchanged; rejected loads leave the session usable.
6.4 complete: ten file groups and the complete boundary gate pass
(/tmp/attalambda-interactive-6.4-{file,gate}-final.log). Guarded source reads prove
one read per load. Literal Unicode/space/shell-looking paths, allowed parent links,
relative program writes and unchanged working directory pass. Rejected dotenv/final
symlink loads perform zero content reads; all rejected loads preserve old names.
The initial focused run caught a missing parenthesis in the new test's for form;
the exact syntax correction precedes these passing reruns. No product fix was inferred.
- [x] **6.5 — Consolidate sanitized error presentation.** Share small classification/location helpers where beneficial; keep phase-specific diagnostics and the existing file launcher behavior. **Check:** malformed source, unknown names, recursion rejection, missing file, rendering failure, and unexpected native failure produce useful bounded diagnostics without leaking arbitrary native internals.
6.5 implementation: new pure diagnostics.rkt reuses source-problem and the existing
syntax selectors, bounds/escapes dynamic text, trusts only caller-matching locations,
and offers an opt-in rendering wrapper that raises through transaction cleanup.
Five diagnostic groups pass (/tmp/attalambda-interactive-6.5-diagnostics.log).
No default session exception or existing CLI message changed. Final controller
phase/context and presentation wiring remains Phase 7; native/render diagnostics
name the entry/file without inventing per-result coordinates. Two boundary mutation
groups, 145 existing boundary assertions and the complete gate pass in
/tmp/attalambda-interactive-6.5-{mutations,boundary,gate}.log.

**Checkpoint 6 — Compatibility and boundary review.** Use a focused regression/code review of validation and loading. Prefer proving the shared helper preserves existing behavior over broad runner cleanup. Re-run the existing file runner/integration suites plus the new load tests and both gates.

Checkpoint 6 complete: the full CS 9.3 run exits0 with61 suites,17,691 reported
Racket tests,14 Python PTY cases,40 production purity modules and complete source
boundaries (/tmp/attalambda-interactive-phase6-full.log). Independent review and
repair verification are complete; git diff --check passes. The phase is being
committed/pushed as542d47b; reconcile Git before starting7.1 after an interruption.

Executable changes: shared validation and sanitized diagnostics are new helpers;
the existing launcher delegates validation, and the session executes fresh isolated
loads through its existing publication transaction. Tests add ten file groups,
five diagnostic groups and stronger boundary mutations; tooling pins exact new
classes and sensitive operations. Documentation updates PLAN/HANDOFF and records
independent preparation. Core/effects/runtime/lang/readers, package metadata and
VERSION have no diff from Phase 5. File-launch compatibility remains291 assertions.

Cold review proved two structural-gate gaps, with no unmutated execution defect:
source-file allowed omitted read ports and an extra content preflight before path
validation; diagnostics allowed native calls using read/expand phase-label tokens.
The disposable hunter consumed one simulated stdin byte through the first mutation
and eleven through the diagnostic read mutation. Source-file now pins both complete
inspection/preflight blocks and exact native-operation counts; diagnostic labels are
quoted data only. Three permanent mutation groups and the full boundary gate pass
(/tmp/attalambda-interactive-phase6-review-{mutations,gate}-final.log).
An initial count omitted port->bytes's explicit import; observed import-plus-call
count is two and is now fixed. Independent repair review confirms both findings
closed, with no additional confirmed issue; all original hunter mutations, three
updated boundary groups and complete inventory gate pass independently
(/tmp/attalambda-phase6-review-{hunter,boundary,gate}-fixed.log). The already
running full suite had only reached unchanged acceptance/binary-nat tests before
these gate/test repairs; its later boundary checks test the repaired implementation.

### Phase 7 — Assemble the command loop and echo/status policy

**Purpose:** expose the working engine through the final CLI before full editing polish.

Phase 7 execution subdivisions: 7.1 adds argument/terminal policy and a working
plain source loop; 7.2 fills in commands, then7.3/7.4 complete echo and output
boundary behavior, followed by status and live-stream acceptance. Keep the new
controller behind a fixed lazy module load in the existing launcher, preserving
help/version/file behavior without initializing the interactive dependency tree.
No private editor, history, or terminal descriptor capabilities enter Phase 7.

Read-only preparation during Phase 6 verification: editor_probe_review proved that
stdout location counters cannot alone implement separator boundaries. Bare CR and
LF have identical reported locations, and Expeditor's fresh-line changes the stdout
counter while descriptor 1 is routed to stderr, even when stdout itself is a pipe.
terminal-port? also changes during dup2, so terminal status must be captured before
editing. A minimal immediate forwarding port tracking only the last accepted output
byte was proven before 7.4; the implementation and verification are recorded below.
The 28-line public make-output-port candidate is
/tmp/attalambda-phase7-forward-output-review.rkt. Five focused partial/nonblocking/
break/flush/byte tests and five engine/PTY scenarios pass in the adjacent
forward-output-test.rkt and forward-integration.{rkt,py} probes. It retains only
accepted-byte count/last byte, forwards immediately, and leaves original stdout
open. Keep stdout-result separation distinct from visual stderr-prompt separation.
The editor continues to use original ports; no line counting is needed.

- [x] **7.1 — Add CLI dispatch without altering file mode.** Implement only the supported command forms and terminal/transcript selection. **Check:** both flag orders work, invalid combinations return `64`, default nonterminal invocation does not consume source, and existing `--help`, `--version`, and file mode retain their contracts except the documented new help text.
7.1 complete: the fixed lazy controller load leaves help/version/file dependency
initialization separate. Supported flags, explicit transcripts and a basic checked
plain loop work. Four CLI groups,291 runner assertions,145 boundary assertions,
three mutation groups and three actual-CLI PTY cases pass; complete boundary gate
passes (/tmp/attalambda-interactive-7.1-*.log, final suffix where present).
PTYs cover all five terminal flag forms, stdout redirection, and terminal stdin
with redirected stderr requiring explicit --repl. The new controller has its own
closed class; optional on-phase callbacks identify actual expansion/evaluation for
diagnostics without changing default engine exceptions. The process-test helper
now feeds transcripts while draining output and closes all child pipe handles.
The first gate identified an omitted local problem identifier; its reviewed
allowlist entry is added. Commands, echo/separators and full status acceptance follow.
- [x] **7.2 — Connect the plain loop and commands.** Use the shared reader/session engine and implement `:help`, `:names`, `:load`, `:reset`, and `:quit`. **Check:** a full plain session exercises each command, command errors recover, and reset retains shell preferences while replacing evaluation state.
7.2 complete: seven CLI groups, five diagnostic groups and complete boundaries
pass (/tmp/attalambda-interactive-7.2-{cli,diagnostics,gate}.log). Real transcripts
exercise every added command, lazy name listing, loaded definitions/no file echo,
reset, early quit and recovered command/load failures. Explicit name listings
preserve long names and escape controls through a small shared formatting helper.
The exact command case and load-label count are pinned; no native loader is added
to the controller. Echo preference and its preservation follow in7.3.
- [x] **7.3 — Add explicit echo control.** Implement `:echo on/off` as one shell preference, default on. With echo off, use normal file-style demand and skip all renderer/type-probing paths. **Check:** supported values print canonically when on; the raw-function example in §3.5 does not invoke `f` until explicit application; explicit output remains immediate in either mode.
7.3 complete: nine CLI groups and complete boundaries pass in
/tmp/attalambda-interactive-7.3-{cli,gate}.log. Echo-off raw functions stay
unobserved until explicit application; echo survives reset; invalid commands
retain the prior setting. Explicit effects stay live.

- [x] **7.4 — Keep stdout and UI separate.** Add the small banner/prompt/result/diagnostic output helpers, including separator behavior after a program writes without a newline. **Check:** `atta>` is used consistently, stdout redirection contains no UI, prompts reach the terminal before blocking reads, and echo-off emits no synthetic result text.
7.4 complete: six output groups, ten CLI groups, five actual CLI PTY cases,
145 boundary checks and complete gate pass (7.4-{output,cli,pty,gate,
boundary-final}.log). Forwarding preserves immediate exact bytes, partial and
nonblocking writes, cancellation, flush and original-port ownership. UI and
redirected stdout have independent separator state. The first boundary test
failed only because its expected inventory omitted the new shell-output class;
that explicit expectation is updated and the rerun passes.

7.5 starting evidence: independent file_load_cold_review proved a permanent
source failure retries101times/100diagnostics; failed stderr escapes the fatal
handler; automatic-output failures are mislabeled rendering and consume later
source. Hunter/log: /tmp/attalambda-phase7-stream-review.{rkt,log}. Treat unusable
shell streams as fatal70, preserving recoverable entry failures and program Err.

- [x] **7.5 — Implement transcript status tracking.** Add the sticky recovered-failure flag and explicit EOF/interruption/exit precedence from §3.7. **Check:** a bad entry followed by a good one still ends with status `1`; reset does not clear the flag; language Error/Err values alone do not set it; unfinished EOF returns `65`; explicit language exit retains its own status.
7.5 complete:12CLIgroups,4controllergroups,2actualCLI cancellation/EOF
PTY cases,1transcript interruption case and complete gate pass in7.5logs
(cli-final/controller-final/pty/transcript/gate). Status precedence, reset
stickiness, language Error/Err, source/command/load recovery, explicit exit,
unfinished EOF65 and transcript SIGINT130 are verified. Actual expansion
observer tests prove controller recovery from native failure and interruption.
Permanent shell stream failures now return70 after one read/failed emission;
last-resort stderr failure cannot escape the controller. The initial new
Error/Err test expected empty stderr despite explicit reset; its assertion
now requires the documented reset acknowledgement. No product fix for that.

- [x] **7.6 — Test the complete incremental transcript path.** Feed source, program answers, blank answers, multiple source forms, a recoverable error, and fresh source through an open pipe without closing the writer prematurely. **Check:** exact answer/source boundaries and expected results/statuses hold with no prompts, escapes, or history access.

7.6 complete: three live transcript cases pass (7.6-transcript.log), including
open-writer source/program handoff, command-like and blank answers, multiple
forms, recoverable failure/fresh source, final running-read EOF then sticky
status1, echo-off immediate prompt and SIGINT130. No UI appears in transcripts.
Reviewer reran the original stream hunter; all three product findings close
(/tmp/attalambda-phase7-stream-review-fixed.log). Its follow-up proved Racket
custodians leave in-memory ports open. Controller test ports now close explicitly
in finalization; the shell closes its forwarding port explicitly while preserving
original stdout. Controller4/output6 groups and complete gate pass (7.6 final
logs); boundary mutants pass4groups.

Checkpoint7 review found Ctrl+C during recoverable diagnostic output escaped to
outer130, including read/command/load siblings and a second interrupt while
reporting the first. A nested parameterize-break-only attempt failed and was
reverted. Minimal probes establish queued custom-port breaks; final protected
recovery explicitly checks (break-enabled #t) after show. Six controller groups,
two targeted PTY cases and the complete boundary gate pass. Independent
command_loop_cold_review closes with no remaining confirmed Phase7 findings:
five original interruption siblings, eight cleanup paths and final six controller
groups pass. Its last test-only global missing-file assumption is eliminated with
a unique temporary directory and explicit cleanup.

Initial full attempt /tmp/attalambda-interactive-phase7-full.log ended1 at
distribution load: compiled tests retained old run-command9.1 imports after the
helper gained #:input. Prior six suites passed. Distribution209passes after raco
make. run-all-tests.sh now refreshes test dependencies with raco make before
execution; shell syntax and diff checks pass. The final complete suite passed:
64 test files, 17,716 reported Racket tests, 24 Python PTY tests, 40 production
purity modules and complete source boundaries. Command: PATH=/tmp/attalambda-racket93/bin:$PATH
PLTUSERHOME=/tmp/attalambda-racket93-user TMPDIR=/tmp ./run-all-tests.sh;
log /tmp/attalambda-interactive-phase7-full-final.log, exit 0. Exec49517 and
monitor cell448 are finished; do not repeat them. Dotenv-safe diff/whitespace
checks pass. This phase creates runner/repl.rkt and runner/output.rkt, modifies
launcher selection/diagnostics/session phase reporting, adds CLI/controller/output
and PTY regressions, and narrows the corresponding boundary rules. Plan/handoff
changes record evidence. Core/effects/runtime/lang/readers and version/package
metadata have no diff from Phase6. No archive or release claim is made.

Memory observations: three 200-entry cycles took 10.313/10.205/10.020 seconds;
retained heaps were 125204976/125477904/125469192 bytes and reset heaps
115107568/115168456/115222448 bytes versus 115299864 initial. Descriptors stayed7;
weak-reference/reset/close assertions passed. These are measurements, not universal
memory or latency bounds.

**Checkpoint 7 — End-to-end plain REPL review.** Use a behavioral code review against the fixed contract. At this point the feature works without advanced editing. Inspect especially echo-off for accidental tag probing and transcript handling for read-ahead or hidden process-status failures.

### Phase 8 — Complete terminal editing and bounded history

**Purpose:** polish one working engine, not add another execution path.

Step8.1 is subdivided before implementation. 8.1a promotes the proven POSIX
stdout-to-stderr descriptor adapter, repairs the evidenced flush-failure cleanup,
classifies exactly its three foreign calls and retains the subprocess regression.
8.1b adds the small Expeditor source-reader adapter with explicit safe hooks,
fixed lazy loading and exact dependencies/boundaries. 8.1c wires it into the real
CLI, retaining plain fallback and original-stdin pending-byte handoff, and verifies
equivalent entry semantics, no initialization-file execution and terminal cleanup.
Completion/history remain8.3–8.5; no second evaluator or terminal driver is added.

8.1a complete:runner/editor-output.rkt replaces tests/helpers/editor-descriptors.rkt;
the test editor imports the promoted adapter. Its proven final-flush cleanup now
always restores/closes fd1 while retaining a propagating action failure/break.
The new separate-process fixture verifies seven success/failure combinations,
live fd1/fd2 destinations, unchanged descriptor counts and original stdout bytes.
DescriptorProbe plus accept/close and redirected-stdout PTYs pass; five boundary
mutation groups,145 boundary checks and complete gate pass. Logs:
/tmp/attalambda-interactive-8.1a-{descriptor,redirect,mutants,boundary,gate}.log.
The descriptor log includes one command-selection error from naming a nonexistent
test_stdout_is_separate method; the actual test_redirected_stdout_is_restored
passed in the redirect log. No product repair or test waiver for that invocation.
Exact new class pins the complete small adapter, its foreign names/arguments and
single export. Full phase verification remains after8.7.

8.1b complete:runner/editor.rkt uses fixed lazy POSIX adapter loading and explicit
public Expeditor hooks, the existing restricted reader and an empty metadata-only
namespace. Real PTYs pass multi-form source, commands, reader-directive rejection,
fresh EOF and controlled open failure, with restored redirected stdout and no
synthetic initialization-file execution. Six boundary mutation groups,145 boundary
checks and the complete gate pass; logs /tmp/attalambda-interactive-8.1b-*.log.
The production CLI connection follows8.1c; completion remains8.3.

Dependency decision:promote expeditor-lib and syntax-color-lib from build-deps to
direct deps because the adapter imports the editor and maintained Racket lexer.
Expeditor is required by the contract and owns the terminal protocol; replacing
the lexer would create another parser. The approved CS9.3 packages add only
parser-tools-lib and option-contract-lib beyond base. Measured installed source
directories are166215/111875/255947/24750 bytes respectively; final archive delta
is unmeasured until packaging. Existing runtime versions are retained; no separate
advisory audit is claimed. No convenience dependency or user package-home change.

- [x] **8.1 — Integrate the proven editor adapter.** Promote the early editor probe into the real loop using the shared safe reader. Declare the actual direct package dependencies and corresponding narrow boundary changes. **Check:** advanced and fallback modes produce equivalent entry semantics and the library still does not execute Racket initialization files.

8.1c complete:repl.rkt loads the fixed editor module only for interactive mode,
uses original input/output and returns to the same plain collector when original
stdin already has buffered bytes. An unavailable editor selects plain interactive
fallback for that shell. Transcript collection is unchanged. Ten existing actual
CLI/transcript tests pass; three focused terminal cases additionally prove advanced
cursor correction, program/answer/source type-ahead, normal terminal mode during
program input, no synthetic init execution, and cancellation/recovery in both
advanced and fallback modes. Six controller and six boundary mutation groups plus
complete gate pass. Logs /tmp/attalambda-interactive-8.1c-*.log. Plain prompt tests
retain their exact continuation assertions under an unrecognized terminal; advanced
checks allow its native UI bytes between exact result bytes and the next prompt.
No executable failure or acceptance waiver occurred. Full phase review remains8.7.

- [x] **8.2 — Configure multiline editing and indentation.** Select appropriate documented lexer/indentation/parenthesis hooks without importing the entire Racket REPL. **Check:** nested expressions, comments, escaped strings, cursor movement, and multi-form paste work; no second parser or custom terminal escape engine is introduced.

8.2 complete:explicit public parentheses/grouping/indentation hooks select the
library's S-expression fallbacks with racket-lexer. Actual CLI nested let, block
and line comments, escaped multiline String, cursor editing and multi-form paste
pass in advanced and fallback modes. The adapter's submitted source contains the
expected two-space indentation after Tab. Initial test incorrectly expected
auto-indent during rapid paste; installed private/ee.rkt should-auto-indent?
suppresses it when keystrokes are within50ms. The corrected test explicitly asks
for indentation, with no sleep or production change. Logs8.2-editor.log (four
other passing methods and this initial test failure),8.2-indent.log (corrected
indentation pass),8.2-mutants.log (six groups),8.2-gate.log (pass).

Initialization fixture correction:the legacy .expeditor.rkt sentinel was not the
CS9.3 target under PLTUSERHOME. A read-only API probe gives
PLTUSERHOME/.config/racket/expeditor.rkt and racketrc.rktl. Tests now create both
actual files plus the legacy file in their isolated home. A positive control
calling expeditor-configure executes the synthetic sentinel and fails as expected;
the real adapter/CLI and existing editor probe succeed without executing it.
Earlier no-init assertions alone did not prove the actual path; exact boundary
checks already prohibited configuration loading. The updated tests supply that
missing behavioral evidence.

Independent8.1 adapter review reports no actionable current-configuration finding.
Its primed-entry/color-enabled initial lexer failure is outside production:
expeditor-open/ee-set-history! always start histnow empty, and color is disabled.
Six additional PTYs with0/1/1000 history entries confirm no initial lexer callback,
restored termios and clean stdout. Scratch /tmp/attalambda-phase8-fresh-history-review.*.
The asynchronous initial-display signal window remains unverified, not a proved bug.

- [x] **8.3 — Add non-evaluating completion.** Derive visible language names from actual public exports and combine them with committed user names through a supported editor mechanism. **Check:** newly defined/redefined/loaded names appear, reset removes user names, failed names never appear, and lazy definitions are not forced. Filter private scaffolding, not legitimate public language exports.

8.3a is metadata-only plumbing: `session-completion-names` combines actual value
and syntax exports with committed names, excluding only four module scaffolds.
The initial14 state groups,7 boundary groups and complete boundary gate pass in
`/tmp/attalambda-resumed-completion-{metadata,mutants,boundary}.log`.
Independent review finds no actionable issue: all135 actual public names,
all65 C0/DEL/C1 committed identifier cases, loaded lazy definitions, no demand,
failed-entry exclusion and reset pass; four metadata mutations fail after an
unchanged scratch baseline passes. Review evidence:
`/tmp/attalambda-completion-metadata-review{,-state}.log`.
The review's complete export-set and65-character hunters are now permanent focused
state tests. All15 groups pass in `/tmp/attalambda-resumed-completion-hunters.log`
(exec87774 finished0); no value is demanded by these metadata checks.
8.3b remains the editor connection and actual completion acceptance; it depends
on resolving the control-character contract question. No UI filtering is present.

A scoped existing-library correction is now being prepared to preserve every
name without needing that exception. Read-only analysis establishes stock Expeditor
emits source control characters literally; history additionally expands tabs and
drops CR, and its completion-list padding counts characters rather than displayed
width. The empty symbol is a legitimate committed identifier; source spelling must
use `||` instead of the empty result from the no-bar symbol printer.
Before implementation, subdivide8.3b:8.3b1 applies a pinned correction only in the
separate candidate Expeditor package, sharing safe control spelling with geometry,
retaining actual source/history characters and explicit UI newlines;8.3b2 proves
completion/recall/wrapping/cursor behavior with real PTYs, then promotes the patch
and read-only build verification;8.3b3 connects metadata through the public
namespace mechanism, with no value demand and source-spelling round trips;
8.3b4 runs actual CLI completion, full tests/gates and independent review.
No omission, new grammar, terminal driver or product private import is authorized
or needed by the proposed library repair. Do not call it working before PTY proof.

The isolated candidate now separates C0/DEL caret display and C1 ASCII hex display
from unchanged source characters, shares visible widths with cursor geometry,
preserves history tabs/CR, and wraps completion lists by visible width. Its first
all-control completion/recall PTY run is in progress; do not change that candidate
during the run. Before the next correction,8.3b1 additionally covers the proven
narrow-prompt failure: original widths1/3/5 crash before input and leave raw mode,
while fitting the same public prompt makes the same edit pass with full cleanup.
Retain the configured prompt and derive a display prompt only when it exceeds the
row, so widening restores it. Evidence:
`/tmp/attalambda-phase8-{narrow-prompt,fitting-prompt}-results.json`.
Widths smaller than one character's display use a one-cell placeholder while
retaining the exact source; resize refreshes both row and one-cell layout caches.
The initial130 public-API PTYs passed (65 completion and65 recalled source cases),
including identity, no demand, stdout restoration and terminal cleanup:
`/tmp/attalambda-expeditor-candidate-controls.{log,json}`. The subsequent fitting
prompt candidate compiles and is under independent geometry/resize/list review.
Independent spelling review found that leading `:` also needs a backslash so an
actual name such as `:help` bypasses shell-command dispatch. With that correction,
all549 unusual names round-trip through parse-source-entry;73 actual committed
lazy names remain undemanded. Probe/log:
`/tmp/attalambda-completion-spelling-review.{rkt,log}`.

8.3b2 visual review found two stock multicell redraw defects: deleting a character
that crosses a wrap mutates geometry before moving the physical cursor; inserting
can leave stale glyphs in newly vacated row-end cells when row count stays equal.
Untouched stock reproduces the same deletion bytes with ordinary `界`. Native
indentation also hangs after removing a leading space because its old column lies
beyond the new string before move-bol. Before editing, narrow the next correction
to these source/physical-coordinate transitions: move to the old logical line
start before modifying affected multicell lines, then reuse existing clear/redraw;
perform indentation's move-bol before its mutation. Preserve captured splice and
mark coordinates. Test same-line and multiline insertion/deletion, indentation,
completion cycling, exact visual cursor state, resizes and cleanup. `indent-all`
already anchors before modification and has no proved issue. Evidence:
`/tmp/attalambda-expeditor-multicell-transition-visual.json` and
`/tmp/attalambda-expeditor-indent-transition-review.py`.
The old-geometry repair passes all24 visual cursor/grid checkpoints and three
former indentation-hang siblings. A separate untouched-stock ASCII multiline
failure is now proved: display-rest-of-entry prints a phantom prompt but passes
physical column0 to the following line layout.8.3b2's next correction changes
that argument to the actual prompt width; no further terminal mechanism is added.
Evidence: `/tmp/attalambda-expeditor-multiline-ascii-results.json` and
`/tmp/attalambda-expeditor-correction-indent-results.json`.
That prompt-width argument fixes the ASCII/ordinary-width newline cases. Narrow
leading multicell characters reveal why logical BOL is not a stable physical
anchor: the first character can begin on the next row. The independent native
full-redisplay control renders these exact width3/7/8 cases correctly. Replace the
affected non-unicell incremental adaptation with existing clear-entry before
mutation and existing redisplay after setting the new point and fresh viewport.
Keep captured splice/mark coordinates, source/color data, configured prompt,
history and key behavior. Ordinary one-cell edits retain their original path;
the proved ASCII multiline prompt-width correction remains. This replaces the
incomplete adaptation, without adding a terminal driver. Reviewer source/viewport
assessment and proof: `/tmp/attalambda-expeditor-leading-wide-refresh-visual.json`.

The following exception discussion is historical; a dependency repair preserving
the contract is now in progress, so no exception is needed if its checks pass.
Independent command_loop_cold_review confirms that omitting control-containing
committed names changes the fixed3.9/8.3 promise. Public Expeditor insertion/display
emits literal control bytes, and Racket identifiers have no ASCII hex escape that
round-trips to ESC. Ordinary source-spelling adaptation works for spaces/bars/
backslashes/numeric-looking names; incomplete |tw is merely an unsupported prefix,
not an unavailable identifier. Kyle was asked whether completion alone may omit
names containing U+0000–001F or U+007F–009F, retaining their source behavior and safe
:names listing. No filtering is authorized or implemented yet. Do not infer an
answer from elapsed time. Independent safe history work8.4/8.5 may continue under
the explicit instruction to finish independent work when blocked;8.3 stays open.

- [x] **8.4 — Implement bounded inert history reading.** Choose one simple data format and safe application-data path; enforce the entry and byte bounds before unbounded parsing/allocation. **Check:** valid multiline entries round-trip, oversized/corrupt/unsafe files are ignored safely, reader directives cannot execute, and `--no-history` performs no persistent read.

Independent8.4 subdivisions before implementation:8.4a implements/tests a bounded
binary history format in runner/history.rkt (fixed version header, unsigned entry
count and UTF-8 byte lengths; no native data reader).8.4b adds best-effort reading
under the platform preference directory with no-follow path/type/permission checks,
a strict read cap, and an early disabled branch before filesystem discovery.
8.5a will add atomic persistence;8.5b will connect shell-owned1000-entry navigation
and source-only history. These helpers do not depend on the pending completion
decision. Do not declare8.3 or the phase complete while that decision is pending.

8.4a complete:runner/history.rkt and tests/interactive-history-test.rkt provide
the inert framed format, exact1000/1MiB limits, strict UTF-8 and rejection of
truncation/oversized count/declared length/version/trailing bytes. Encoding skips
oversized entries and preserves newest-first order. Four focused groups,seven
boundary mutation groups,145 boundary checks and complete gate pass in
/tmp/attalambda-interactive-8.4a-{history,mutants,boundary,gate}.log. Exact source
classification is added; no history filesystem access or shell integration yet.

8.4b complete:read-history uses pref-dir/attalambda/history-v1, rejects dotenv path
components and symlink/nondirectory ancestors, unsafe directory/file permissions,
nonregular files/FIFOs/hardlinks and oversized files before a content-read attempt.
Opened-file identity/type/permissions/size are rechecked before reading at most
1048577 bytes. Disabled history returns before path discovery. Errors are best
effort; interruption propagates. Eight focused groups,seven boundary mutation
groups and complete gate pass in8.4b-{history,mutants,gate}-fixed.log. No shell
history integration or persistence at that checkpoint. Independent read review
closed with no actionable findings: all8 groups pass independently, and four
open-time substitutions (inode, permissions, growth, FIFO) return empty history
promptly. Evidence:/tmp/attalambda-phase8-history-{review,race-review}.log.

Initial read tests rejected valid private files because this sandbox maps the
filesystem root and /tmp owner to65534. Read-only stat proved the cause; the sticky
ancestor exception now compares against the observed filesystem-root owner instead
of hardcoded UID0. Non-root-owner sticky ancestors remain untrusted. The diagnostic
probe initially omitted TMPDIR and tried read-only /var/tmp; an escalated retry was
declined and was not run. The cause was established with metadata-only inspection,
then ordinary sandboxed tests passed. No retry through another mutation path or
system permission change occurred.

- [x] **8.5 — Implement best-effort history persistence.** Save submitted source/commands with appropriate permissions and atomic replacement where supported. Skip oversized entries rather than rejecting their execution. **Check:** program answers are absent, an unwritable target does not break the session, a failed save does not corrupt an existing valid file, and `--no-history` performs no persistent write.

8.5a passes11 history groups,7 boundary mutation groups and complete gate in
/tmp/attalambda-interactive-8.5a-{history-fixed,mutants,gate}.log. New write-history
uses the standard library's atomic output helper inside a validated private
directory, sets temporary permissions before payload, rechecks the destination,
and retains the old file/cleans temporary files on write, rename and break
failures. Missing directories are created0700; existing unsafe targets remain
untouched without content reads. Disabled writes perform no filesystem access.
The initial test log contains a test-only extra closing parenthesis, corrected
before the passing run. Independent writer/shared-helper review closed with no
actionable findings; chmod failure/break and a destination permission change at
the final recheck preserve old data and clean the temporary. Evidence:
/tmp/attalambda-phase8-history-write-{review,hunters}.log.

8.5b focused checks now pass:12 history groups,8 controller groups,1 lifecycle
group covering10 fresh-process scenarios,7 boundary mutation groups, complete
gate, and actual CLI source-only persistence, no-history recall, unsafe target
recovery,1000-entry navigation, cancellation/exit and file load/reset cases.
Logs:/tmp/attalambda-interactive-8.5b-{history,controller,lifecycle-fixed,
mutants-fixed,gate-fixed,pty,pty-fixed}.log and8.6-pty.log. The initial pty.log
contains a fixture-permission failure:Python parents=True created intermediate
ancestors0775 under umask0002, correctly rejected by the reader. Explicit0700
creation fixes the fixture; three independent two-prompt1000-recall runs also
pass, without a production change (attalambda-history-safe-recall-review.py).

Independent integration review found one real startup-erasure bug: cleanup
saved the initial empty list when open-session failed or initial history reading
was interrupted, consuming no source but replacing prior history. Repair tracks
whether a nonempty source submission changed history and enables saving only
then. This also preserves the old file on read failure followed by EOF or an
untouched session. The promoted lifecycle regression fails before the repair
(8.5b-lifecycle-before.log) and all10 scenarios pass afterward. Fresh cold review
is closed:all10 scenarios and seven additional boundary probes pass, including
partial-source interruption, completed source followed by interruption, early
source/UI failure, submitted reader/expansion failure and emptyEOF with no prior
file. Evidence:/tmp/attalambda-history-record-boundary-review.{rkt,py}.
The lifecycle fixture now resolves the language directory from its own location,
so fault injection does not require a checkout named attalambda. The first
relocation-independent rerun (8.5b-lifecycle-final.log) exposed unsimplified '..'
segments in define-runtime-path:the fault hook did not fire. A read-only API
probe confirmed them; lexical normalization of both compared paths resolves the
test-only issue.8.5b-lifecycle-portable.log passes all10 scenarios. All production
findings in this scope are closed.

- [x] **8.6 — Finalize editor failure and fallback paths.** Handle unrecognized terminals, controlled initialization failure, EOF, interrupt, and process exit without exposing the editor's internal errors as language values. **Check:** no terminal-mode residue, no duplicate input reader, and the plain fallback retains multiline source support; advanced features are required on the supported normal Linux terminal, not silently waived.

Complete real terminal gate passes36 Python cases plus its Racket wrapper:
/tmp/attalambda-interactive-8.6-editor-all.log, exit0. Controlled open refusal,
unrecognized-TERM plain mode, explicit advanced-mode editing, multiline/paste,
source/evaluation/render/input/load cancellation, source-to-program handoff,
EOF/exit0/1, descriptor cleanup, original stdout separation,1000-entry history
and inert initialization are covered.8.3 completion remains open; this is the
implemented terminal gate, not evidence that completion or the candidate passed.

- [x] **8.7 — Run full PTY acceptance.** Drive the actual executable through editing, history recall, completion, multiline paste, program input, Ctrl+C, Ctrl+D, and explicit exit. **Check:** terminal state is restored on every termination path and the source/program handoff still passes after history/completion integration. Exercise source entered before and after blocked reads.

Independent9.1 coverage preparation identified four explicit §6.1 real-REPL
transcripts that existed only at the helper level. Added them to
tests/interactive-cli-test.rkt:binding snapshots/partial application/terminating
rec, saved+fresh reads, recovery/reset/sticky status, and load expansion rejection
before earlier effects. Initial8.7-transcripts.log passes15/16 groups; the failure
is an assertion using "unknown name keep" instead of the observed canonical
"unknown AttaLambda name: keep". Test-only correction is in
8.7-transcripts-fixed.log. The final success-load fixture now checks exactly two
markers/acknowledgments plus bare-expression silence across reload; all16 CLI
groups pass in8.7-transcripts-final.log. Full source regression passed with exit0:
66 test files,17,738 reported Racket tests,36 Python PTY cases,40 purity modules
and the complete boundary gate. Log:
/tmp/attalambda-interactive-phase8-independent-full.log. Three200-entry memory
cycles took8.951/8.966/9.491seconds; retained125224776/125465232/125471920bytes,
reset115127912/115220456/115228752 versus115308624initial. Descriptors stayed7.
These are observations, not performance guarantees.8.3 still waits; do not
close8.7 or Phase8 before completion integration and refreshed terminal evidence.

Current8.3b4 verification record (supersedes intermediate correction notes above):
actual completion is wired and the corrected lifecycle method passes in
`/tmp/attalambda-completion-actual-cli-state.log`; the72 unusual/control CLI cases
pass in`/tmp/attalambda-completion-actual-cli.log` (that original combined run
fails only the now-corrected source-cancel diagnostic assertion). The independently
reviewed actual helper corpus is permanent ininteractive-completion-test.rkt;
9075 checks pass in`/tmp/attalambda-permanent-completion.log`. Permanent dependency
preparation checks pass14 in`/tmp/attalambda-permanent-preparation.log`; its first
run rejected an extra newline in the test's reverse-diff fixture, now corrected.
The attempted multi-file raco invocation failed before loading any test because
this copied runtime could not resolve compiler/test's process submodule. Individual
raco invocations, as used by run-all-tests.sh, execute successfully; the failed
multi-file invocation is not product evidence. Distribution checks pass217 in
`/tmp/attalambda-final-dependency-distribution.log`.
A cold tooling review then proved corrected main.rkt source could coexist with
upstream compiled main.rkt while the old checker inspected only private modules.
The checker now loads main and compares its newly imported width bindings, and
checks Windows-sensitive string-unicell? behavior. Source/loaded --check passes
in`/tmp/attalambda-final-runtime-loaded-check.log`; permanent stale-main hunter
and applied-delta review follow before closure.

Checkpoint8 closure evidence: all69 source files/26845 Racket assertions and both
terminal suites (43+6 methods) pass with both structural gates in
`/tmp/attalambda-interactive-phase8-final-full-02.log`. Exact command is the
corrected isolated CS9.3 invocation in HANDOFF.md. Source diff whitespace and
independent reviewed-file hashes pass. Three200-entry memory cycles retain
125510688/125668432/125663616bytes and reset to115855184/115863840/115855568bytes
versus116030592initial; descriptors stay7. These are observations, not guarantees.
The repaired test wrapper compiles all four Python-launched fixtures before the
two harnesses; the independent inventory review found no omitted fixture.
The phase commit includes the proved runtime and packaging prerequisites needed
by the terminal feature, with Phase9's final reconciliation still separate.

**Checkpoint 8 — Terminal usability and history review.** Use terminal-integration review plus a narrow privacy/boundary review of history and startup behavior. The complete program, not just the probe, must pass real PTY tests. No general penetration-testing framework or new account/service integration is needed.

### Phase 9 — Reconcile documentation and distribution inputs

**Purpose:** make the implemented feature accurately documented and packageable.

9.5e — CI preparation correction, recorded before implementation. Current-head
run34994217012 failed both Linux jobs before tests/builds: setup-racket installs
the job-owned toolchain under `/usr`, then unprivileged --apply cannot atomically
write `/usr/share/racket/collects/racket/private/promise.rkt` (errno13). Logs:
`/tmp/attalambda-ci-phase8-{source,linux}.log`. Use `sudo -n /usr/bin/racket`
only for these two preparation steps; normal tests/builds remain unprivileged.
The install log proves `/usr/bin` and successful sudo; GitHub's hosted-runner
documentation confirms passwordless sudo. This is the authorized disposable CI
environment, not a local system mutation. Do not relocate the toolchain into a
temporary absolute prefix or weaken the archive path gate. Verify the focused
distribution checks, independent workflow review, full suite and new CI run.
The same run is now complete: all Windows/macOS build/consumer/cleanup jobs pass;
only the two Linux preparation jobs failed. The changed workflow passes217
distribution assertions. A disposable original-image probe reproduces the
unprivileged failure, passes root-only preparation and then passes nonroot
read-only verification; container cleanup passes. Evidence:
`/tmp/attalambda-ci-preparation-permissions-probe.{log,json}`. The Phase9 full suite
is running in exec17885, log`/tmp/attalambda-interactive-phase9-full.log`.
Independent review subsequently proves that read-only source loading does not
establish `raco make` permissions: its recursive compiler writes stale installed
dependency caches. A changed read-only scratch collection loads successfully but
compilation of its importer fails errno13. Evidence:
`/tmp/attalambda-phase9-checkpoint-review-7jrtn7b_/compilation-permission-results.json`.
The original-image actual import closure is under diagnosis before any further
workflow edit. Do not call the two --apply lines alone a sufficient CI repair.

9.5e2 — Replace that incomplete preparation-only privilege attempt with ownership
of the newly installed `/usr/share/racket`, then ordinary --apply. Before this
edit, an independent original-image probe transferred only that directory to the
job UID/GID: `/usr/bin/racket` and `/usr/lib/racket/compiled` remained root-owned.
Ordinary --apply, --check, actual launcher/editor/promise-test `raco make` and all
15 unchanged preparation regressions pass. Default cache roots are preserved.
Evidence:`/tmp/attalambda-phase9-checkpoint-review-7jrtn7b_/ownership02-*.log`.
This adds no custom cache policy or test change. Earlier global setup and cold
embedding/ownership diagnostic timeouts are retained, not counted as passes.
The transfer's Docker overlay I/O took73.995s; compilation took44.35s and the
preparation regression5.41s. Final native CI remains the complete workflow proof.
The full Phase9 source run17885 finished0:69 files/26845 assertions,43 terminal
methods71.605s,6 visual methods5.733s,40-module purity and full boundary inventory.
Only these CI setup lines change afterward; rerun their affected distribution
checks before committing, and verify the complete final configuration in CI.

Independent preparation while8.3 awaits the explicit contract decision:9.1
assertion mapping is below;9.5 package-path behavior is being checked with the
existing build script in an isolated, explicitly dirty development build at
/tmp/attalambda-interactive-development-probe-01. Log:
/tmp/attalambda-interactive-development-build-01.log. VERSION remains0.7.0;
this probe cannot satisfy the clean candidate requirement or justify publication.
That full source baseline has passed; packaging repair can now proceed.

Development build01 completed (exit0) but the exact extracted executable's
`--repl --no-history` smoke exits70 with no stdout. The archive contains12 files,
including only repl.rkt as a copied runtime source, without its required sibling
modules. Logs:development-build-01.log, development-smoke-01.log and
development-module-probe-01.log under /tmp/attalambda-interactive-*.
This is an observed9.5 packaging defect, not a verified standalone candidate.
Existing fixed dynamic module references use define-runtime-path (a runtime file
declaration); the documented define-runtime-module-path-index declares module
dependencies for embedding. Investigate/repair the complete fixed-module-path
class after the running source baseline finishes, with a focused packaged
regression and fresh independent review. Do not treat copying the whole source
checkout or embedding arbitrary runner paths as an acceptable repair.

Read-only embedding prototypes identify the fresh-namespace requirement:using
one module-path index directly caches a reference that does not load the module
into a second registry. Resolving to an ordinary file/symbol module reference
works in source mode, but an embedded symbolic declaration lives in the original
executable namespace and is absent from a fresh base namespace. The next bounded
prototype uses documented namespace-attach-module-declaration (declarations only,
never instances) to retain fresh host/input/resource state. That prototype now
passes both source mode and a relocated distribution with all sources hidden:
/tmp/attalambda-module-reference-review-soxj70_o/ and driver
/tmp/attalambda-module-reference-review-v5.py. It proves two fresh registries and
captured original inputs, shared identity across two generated entries per
session, owned-port cleanup and preserved original inputs. An embedded poisoned
helper remains uninstantiated on help/skip paths. No Windows execution claim.
Recommended mechanical repair:four module-path-index declarations; resolve the
session language to a normal file/quoted-symbol reference; attach declarations
only for the embedded-symbol case before instantiating in each fresh namespace.
The toy needed racket/runtime-config because of its racket/base module-begin;
this is not evidence that the actual AttaLambda language needs a new dependency.
The verified repair is now applied, pending focused source/packaged verification:
four fixed module dependencies use module-path indexes; the session resolves its
language once and attaches only embedded declarations before fresh instantiation.
Exact boundary checks pin resolution/attachment/initialization and reject instance
attachment or omission. Core/effects/runtime/lang/readers are behaviorally unchanged.

- [x] **9.1 — Run a contract-to-test audit.** Map every acceptance row in §6 to an existing test, new test, or explicit artifact check. **Check:** critical behaviors have executable evidence; observational memory measurements and unperformed platform checks are labeled honestly, not converted into claims of proof.

Independent read-only audit prepared while8.3 is blocked; this maps assertions,
not a new execution or final-artifact claim. command_loop_cold_review read all18
rows and their test assertions; its four §6.1 integration gaps and exact reload
marker gap are now covered by the16 passing CLI groups above. Completion and
the final source/artifact checkpoints remain open. All *-test.rkt files are
discovered by run-all-tests.sh; interactive-editor-test.rkt invokes the Python
PTY harness without skipping the required Linux gate.

| Acceptance | Executable evidence / remaining check |
|---|---|
| A01 selection/flags/file behavior | interactive-cli-test.rkt flag groups; CLIProbe default/redirected/fallback cases; runner-test.rkt file/help/version. Artifact rerun pending. |
| A02 entries/comments/literals | interactive-reader-test.rkt; interactive-session-test.rkt whole-entry expansion rejection; CLIProbe multiline/comments/String/paste. |
| A03 reader extension rejection | interactive-reader-test.rkt, interactive-file-test.rkt reader probes; interactive-history-test.rkt inert framing; interactive-boundary-test.rkt reader mutants. |
| A04 retained state/snapshots | interactive-state-test.rkt partial applications, retained effects, rebinding; actual CLI snapshot/partial/rec group. |
| A05 def/rec/hygiene | interactive-state-test.rkt cycles/shadowing/duplicates; interactive-session-test.rkt hygiene; interactive-expansion-test.rkt; actual CLI terminating rec. |
| A06 purity/capabilities | interactive-expansion-test.rkt actual generated terms and negative control; interactive-boundary-test.rkt; boundary-check-test.rkt unknown imports/classes. Exact completion namespace/wiring boundary and mutation checks pass. |
| A07 rendering/effect sharing | interactive-session-test.rkt computed-result rendering/no repeat; interactive-cli-test.rkt echo-off raw functions and exact effect output. |
| A08 saved/fresh input | interactive-input-test.rkt; stdin-test.rkt/stdin-stream-test.rkt/input-language-test.rkt byte/EOF/type/sharing cases; actual CLI saved/:names/repeated/fresh read group. |
| A09 one input stream | interactive-input-test.rkt original-port/open-pipe assertions; TranscriptProbe live source/answers; CLIProbe advanced typeahead/immediate prompt/EOF. Artifact rerun pending. |
| A10 cancellation | interactive-lifetime-test.rkt all stages; interactive-controller-test.rkt deterministic expansion/diagnostic interruption; CLIProbe advanced/plain cancellation and surviving binding. |
| A11 failed publication/recovery | interactive-state-test.rkt reader/expand/native/render failure and cached-promise behavior; actual CLI keep/reset/sticky1 and Error/Err0 groups. |
| A12 resource lifetime | interactive-lifetime-test.rkt failed-entry/reset/exit isolation; interactive-memory-test.rkt weak-reference/descriptor/worker checks; actual CLI reset/exit. |
| A13 loading | interactive-file-test.rkt standalone/path/reload/snapshot/failed publication/cancel; exact-output CLI two-load markers/bare-expression silence and failed-load expansion; CLIProbe real repeated load/reset. |
| A14 statuses | interactive-cli-test.rkt sticky1/incomplete65/explicit exit0,1/Error+Err0; TranscriptProbe interruption130. |
| A15 completion/history | Names:interactive-state-test.rkt; history:interactive-history-test.rkt/lifecycle fixture and CLI persistence/recall/1000/cancel/no-history. Completion:interactive-completion-test.rkt and actual CLI completion methods; full current terminal gate passes. |
| A16 terminal usability/restoration | CLIProbe advanced editing/paste/cancellation/EOF/exit; DescriptorProbe restoration including flush/break failures; full current terminal gate43+6 methods passes. Exact artifact rerun pending. |
| A17 measured repeated use | interactive-memory-test.rkt three200-entry sessions, observed elapsed/heap, weak old state reclamation and stable descriptors. Current three200-entry observations recorded above; no universal memory bound claimed. |
| A18 standalone artifact | distribution-test.rkt plus tooling/test-linux-distribution.sh existing no-Racket/layout/notices/examples/relocation checks.Interactive/runtime-input/PTY checks are wired; exact11.1–11.2 clean build/consumer gate pending. |

§6.2 cleanup regression remains EditorProbe.test_harness_failure_closes_waiting_reader_and_descriptors
and stdin-stream-test.rkt's failing-case teardown. These deliberately take the
failure path; no generic testing framework is added.9.1 closes only after final
completion assertions and packaging check locations are reconciled.
- [x] **9.2 — Update user documentation and executable examples.** Update README/API/help/release notes for runtime input, `atta>`, commands, snapshot redefinition, lazy effects, echo-off, load semantics, and transcript status behavior. **Check:** execute the documented examples, confirm uppercase canonical rendering, and remove obsolete references to `att>` or special literal-lambda printing.

README/API/archive guide and new unreleased0.8.0 notes now describe implemented
shell/input behavior, preserving the published0.7.0 links and explicitly leaving
completion/candidate checks open. The marked API snapshot transcript executes
verbatim:17CLI groups pass; the existing marked input example passes76 assertions.
Distribution assertions pass216. Logs9-docs-{interactive-cli,input-language,
distribution}.log. New consumer exact-input/snapshot checks and updated existing
macOS/Windows help expectations are prepared but actual platform runs are pending.
Independent documentation/consumer review closed after correcting current
distribution version/notice/test-image metadata and the exact forwarded stdout
description. Historical release-ledger bytes remain identical. The19 current
source CLIProbe/TranscriptProbe methods pass in9-source-terminal.log (44.330s).
The consumer's binary-input fixture passes source execution with exact expected
bytes in9-consumer-input-source-fixed.log. Its first standalone probe omitted
collection registration; a read-only collection-file-path probe proved the
missing attalambda/lang collection, then a temporary -S collection alias supplied
the ordinary source installation context. No production change was involved.
- [x] **9.3 — Reconcile architecture and specification records.** Document the narrow REPL-tooling exception, shared expansion path, unchanged host-input contract, source inventory, and dependency direction. Update canonical amendment/index evidence as required. **Check:** docs describe observed code separately from remaining release work and contain no blanket purity exception for arbitrary runner modules.

Architecture, host/distribution design, specification index and acceptance map
now distinguish exact tooling classes, shared checked expansion, fresh session
instances, pure rendering/reader observation, original-input handoff, and inert
history. No new canonical amendment was needed; existing canonical bytes/hashes
remain. Source baseline evidence is explicitly before packaging changes and is
not presented as current candidate evidence. Final review remains open.
Both current structural gates pass in9-final-{boundary,purity}.log (40pure
production modules). Scoped docs/capability review is closed; complete milestone
cold review and final source verification remain Phase10 work.
- [x] **9.4 — Prepare candidate version metadata.** After confirming `0.8.0` is still unused and appropriate, update `VERSION`, package projection `0.8`, and every exact version acceptance table/test that actually depends on them. **Check:** Linux and existing internal portability scripts agree; do not broaden version validators generically just to avoid listing the new supported state. If the version was taken by intervening work, do not reuse its tag or overwrite artifacts.

Fresh remote/tag/release preflight still shows no0.8.0, main71232f7 and milestone
9960d4b. VERSION0.8.0 and package0.8 are prepared; explicit Linux/macOS/Windows
tables and version fixtures retain all prior approved states plus this one.
Focused9.4 checks pass7interactive-boundary groups,146boundary assertions,
291runner assertions and216distribution assertions. Logs9.4-*.log. All processes
finished. No tag/publication.
- [x] **9.5 — Include the editor and new runner modules in distribution.** Adjust only the dependency/bundling inputs needed by the existing build machinery, including any modules reached through dynamic lookup. **Check:** declared package closure and bundled modules cover the real code path, with no dependence on a developer package home or unbundled source checkout.

9.5 is split into fixed-module declaration/namespace repair (a), focused source
and extracted-development validation (b), diagnosed embedded dependency
initialization and isolation regression (b1), generated entry runtime-config
dependency and standalone expansion regression (b2), then exact candidate confirmation
at11 (c). Repair(a) passes7boundary/16CLI/8lifetime/1history-lifecycle/291runner/145
boundary checks and the complete gate. Logs9.5-*.log. Cold review found the
checker accepted extra reassignment of language-reference and local shadowing
inside render-result. Both promoted mutations fail before the repair; pinning
the renderer body and the two permitted set! occurrences closes them. Seven
groups pass in9.5-reference-mutants-fixed.log. Independent cold recheck closes
both original hunters and nine nearby assignment/shadow/instance siblings:
/tmp/attalambda-reference-closure-review.rkt. No remaining finding in that class.

Development build02 exited2 at the existing forbidden-build-path gate; no archive
was produced. Independent bounded toy reproduction shows ten toolchain-root
strings in embedded Expeditor/lexer syntax-parse diagnostic metadata, introduced
by minimatch.rkt's quoted syntax-source. The fixed-index toy without these
libraries contains no retained source/toolchain root. No gate or production
reference change is justified by this separate toolchain-origin issue. The
approved cached official CS9.3 build image uses the already-permitted system
prefix. Its identical relocated toy passes with zero temporary prefixes and
runs in clean Ubuntu without Racket or source, proving these system-prefix
diagnostic strings are not source dependencies. Logs:
/tmp/attalambda-phase9-runtimepath-{container-toy,clean-consumer-toy}.log.
The cached build image lacks Git (read-only preflight exit127). Development
build03 therefore installs Git only inside its disposable application-build
container, using the original image, a read-only checkout mount and separate
output mount. This is independent of the stopped Python consumer-image build;
it makes no Docker buildx cache mutation. Build03 is running with --allow-dirty
at /tmp/attalambda-interactive-development-probe-03; log development-build-03.log.
Container a02522579a2f and exec58791 are owned by this run. Completion and
candidate verification remain open.

Build03 finished2 at the same path gate; its container is removed and no archive
exists. The bounded library toy therefore did not cover every path in the whole
program. No further production fix was guessed. Diagnostic build04 uses the
same unchanged source/runtime and a /tmp-only grep instrumentation wrapper that
preserves grep's result while recording the exact rejected needle/file and
copying only that generated artifact file before normal cleanup. Output:
/tmp/attalambda-interactive-development-probe-04; log development-build-04.log.
Container ID is recorded in /tmp/attalambda-interactive-build04-container-id,
with explicit timeout cleanup. This is diagnosis, not candidate verification.

Build04 finished2 and its container is removed. Exact diagnosis is now proven:
the generic mount name /source was the scanner needle; all28 matches in the
captured executable are safe abbreviated .../runner/source-file.rkt or
.../runner/source-reader.rkt filenames. There are zero /source/ directory,
actual staging-directory, host checkout or temporary toolchain prefix matches.
Evidence:/tmp/attalambda-interactive-build04-path-diagnosis.log and the captured
rejected-path-file.bin. This was an invocation-name collision, not remaining
source dependence. Build05 changes only the mount name to
/attalambda-project-workspace, preserving the source and every build gate.
It is running in exec13151,
with container ID in /tmp/attalambda-interactive-build05-container-id, output
/tmp/attalambda-interactive-development-probe-05 and development-build-05.log.
Independent read-only recheck confirms14matches for each abbreviated basename
and zero actual directory prefixes. Native grep positive controls with injected
new-root and staging-root bytes still reject, so the invocation-only correction
preserves the existing leakage acceptance criterion. No source/gate change.

Build05 completed0, all unchanged packaging/path gates passed. Archive:
/tmp/attalambda-interactive-development-probe-05/attalambda-0.8.0-linux-x86_64.tar.gz,
SHA2563550e93fe904a8153d3015d0328a301af687d01eabb663a1b43cb9178c2c1165,
19573173compressed/68824799unpacked bytes,11files/2runtime files. Manifest records
HEAD9960d4b plus explicitly dirty source; this is not a candidate.
Extraction:/tmp/attalambda-interactive-development-extract-05/attalambda-0.8.0-linux-x86_64.
Actual extracted REPL startup still exits70 with sanitized launcher failure,
both on host and in clean pinned Ubuntu without Racket/source. Version succeeds.
Logs:development-05-clean-smoke.log and development-05-terminal.log; packaged
terminal acceptance fails. Subsequent bounded diagnosis corrects the earlier
module-load inference: loading actual embedded repl succeeds, then actual
open-session fails at namespace-attach-module-declaration because embedded
racket/tcp is not instantiated in language-origin. Racket9.3 attach.rkt lines91–101
requires a source instance for cross-phase-persistent modules even for declaration
transfer. The verified dependency edge is expander -> host -> racket/tcp;
source sessions skip the embedded-only branch. Native evidence:
/tmp/attalambda-real-repl-diagnostic-05.log and
/tmp/attalambda-real-repl-diagnostic-azpjd_ko/embedded-open-session.stderr.
9.5b1 now initializes the fixed embedded language in its origin once at module
startup, outside session/entry custodians. Independent ownership review confirms
no program I/O, ports, listeners or workers are created or captured by this
initialization; ordinary session host instances remain separate. The cost is one
retained unused origin graph. Exact bootstrap/loader count pins remain closed.
New actual CLI listener/reset regression fails on build05 at known startup70 and
passes source in4.200s; eight lifetime and seven boundary groups pass. Logs:
9.5b1-{regression-before,regression-source,lifetime,boundary}.log. Development
build06 is running with the same approved /usr runtime and distinctive mount,
output /tmp/attalambda-interactive-development-probe-06 and build-06.log.
Independent applied-delta review is closed with no findings: exact bootstrap,
fixed loader permissions and mutations, handle reuse/reset, listener lifetime and
bounded test cleanup were inspected. The complete current source suite is running
in /tmp/attalambda-interactive-9.5b1-full-source.log; full boundary gate already
passes in9.5b1-gate.log. Draft PR7 is open for committed phases0–7 only:
https://github.com/kserrec/attalambda/pull/7 . Workflow34941424282 runs on9960d4b,
not these uncommitted inputs; no current candidate claim follows. The earlier toy omitted this
dependency; do not treat
its success as actual language-closure verification. One real packaged startup
smoke must pass before repeating broader terminal acceptance.
Build06 finished0 with all packaging/path gates preserved. ArchiveSHA256
3b357e38e9e7205467ef77f7060b365e12e81f67de2091fd53de5182e441512b,
19573938compressed bytes,11files/2runtime files, dirty inputs atop9960d4b.
Its container is removed. Empty and :quit transcripts pass0, proving the prior
session-initialization failure is repaired. Literal41 now fails1 during source
expansion with sanitized invalid-syntax text. The new actual registry regression
also fails waiting for an expression result; bounded cleanup completes.
Logs:development-06-{smoke,startup-scope}.log and9.5b1-regression-artifact.log.
No full terminal/consumer rerun. The actual-module diagnostic establishes the new
native error: collection not found for racket/runtime-config, generated by
Racket9.3 pre-base.rkt:198–202 while expanding a fresh module. Source preparation
passes; embedded load/open-session/empty pass; prepare-entry fails before eval.
Evidence:/tmp/attalambda-real-repl-expansion-diagnostic.log and
/tmp/attalambda-real-repl-expansion-k4ivvn5p/embedded-prepare-entry.stderr.
The old toy explicitly required this library and therefore did not establish
the real language closure. Before any product edit, one /tmp diagnostic embedding
with only ++lib racket/runtime-config added left the identical failure. Direct
binary inspection proves this module and its initial-namespace mapping were
already present, correcting the earlier absent-code inference. The exact defect
is the fresh registry's declaration/resolver visibility: compiler/embed.rkt
maintains mappings per registry and copies only attached modules' mappings.
The actual-session probe proves that attaching only runtime-config declarations
after the existing language transfer makes parse/expand/evaluate/demand/render
produce41. Its unchanged control still fails. Evidence:
/tmp/attalambda-real-repl-expansion-attach-config.log and diagnostic root
/tmp/attalambda-real-repl-expansion-gippplgh. No builder flag or new import is
needed; the product attachment repair is pending.

The current bootstrap source run finished1 at the terminal wrapper:
9.5b1-full-source.log.36 of37 Python cases pass; plain fallback cancellation sees
an extra interrupt on the next old entry after cancelling an entry containing
read-line. The output marker does not establish that the read had started.
No root cause yet. The unchanged exact case passes10/10 fresh-process repeats
with stable hashes, logs /tmp/attalambda-plain-cancel-review-01.log through -10.log.
editor_probe_review is investigating with handler-only /tmp instrumentation;
no cancellation repair is applied. Remaining full suites/gates did not run.
After characterization finished, the proven embedded runtime-config declaration
transfer was applied after language attachment; no build flags/imports changed.
Exact boundary pins and omission/wrong-target/instance mutations pass7 groups in
9.5b2-boundary.log. Build07 runs in exec22886 via
/tmp/attalambda-interactive-development-build07.py; applied-delta cold review
closed with no findings, and the complete boundary gate passes in9.5b2-gate.log.
Build07 finished0; unchanged packaging gates pass. Its archiveSHA256 is
13d2ea303f01d213c86ee16fcefb1a9a7db904a336010ccb89037561acd6552b,
19573804compressed/68825514unpacked bytes,11files/2runtime files, dirty inputs
atop9960d4b. Literal41 transcript passes0; actual listener/reset regression passes
in2.384s; all20 actual CLIProbe/TranscriptProbe artifact tests pass in34.942s.
The binary's snapshot/saved-input/fresh-input/reset transcript also passes in
the pinned Ubuntu base without Racket/source, at original and space-containing
mount paths. Logs:development-07-{smoke,terminal,clean-smoke}.log and
9.5b2-regression-artifact.log. All owned build/smoke containers are removed.
This is development evidence, not the denied full isolated Python terminal
consumer or clean candidate gate.

Cancellation review's handler instrumentation reproduces a raw-render sibling:
run20 reuses the identical break object and original marks in the next old entry.
Logs:/tmp/attalambda-plain-cancel-instrumented-v4-20{,-breaks}.log. This20-run batch
is not an unchanged-source rate estimate; the embedded-only configuration
attachment changed during it after the earlier10 unchanged runs finished.
Exact reader/promise cause remains unresolved after read-only investigation. No speculative
cancellation repair. Keep it separate from the proven packaging fixes.

Independent remaining source verification completed only the suites after the
failed interactive-editor wrapper, through both final gates, in exec40286 via
/tmp/attalambda-interactive-remaining-source.py. Ledger/log:
/tmp/attalambda-interactive-9.{json,log} (the temporary script's with_suffix
replaced the dotted suffix; these are its actual files). All44 remaining files,
10114 reported Racket tests,40-module purity and the full boundary gate pass.
The ledger has no current test; the process finished0. Do not restart it.
This cannot erase the earlier
terminal failure or count as a complete passing full-suite run.

The read-only cancellation report is
/tmp/attalambda-cancellation-diagnosis-review.md. Additional20 instrumented runs
and40 shortened runs did not reproduce the cached break, so their planned
post-failure observations did not execute. A100-trial tiny composable-promise
control also did not reproduce corruption. None establishes a root cause or
justifies a production patch. command_loop_cold_review completed one bounded
20-process diagnostic preserving the original full priming sequence and handler
timing; only a repeated exception would trigger reader/session promise scans,
followed by echo-off/fresh-value/reset observations before cleanup. That batch
finished20/20 exact full-method executions,100 nonrepeated exceptions, unchanged
source/harness/instrumentation hashes, normal terminal restoration and complete
process/descriptor/home cleanup. Neither the metadata scan nor post-failure
sequence executed. This supplies no new cause and cannot close the failure.
Evidence:/tmp/attalambda-cancel-repeat-metadata-69px5izf/review.md,
results.json, driver.log and run-NN.{json,pty.log,breaks.log}; exec13053 finished.
The initial scratch scanner parenthesis error was corrected before behavioral
runs and recorded separately in setup-check.log. No product edit resulted.

The independent partial-byte readiness prototype passes8 source/build07 scenarios:
/tmp/attalambda-blocked-read-readiness-results.json and its review.md report.
Two actual CLI tests are promoted into tests/interactive_pty.py. They stop the
owned child, enqueue a non-newline byte, observe FIONREAD1, resume and observe0
before cancellation. This establishes an active incomplete host read, not that
the OS thread is necessarily already asleep. Two cancellations preserve old=41;
a third read completes to OK(SOME("p")). A no-read computation retains the byte
across10 fresh markers, rejecting output-only readiness. Both methods pass source
in5.093s and build07 in5.081s: input-readiness-{source,artifact}.log.

Cold review found a test-harness cleanup escape: resume() raising before the
termination block skipped child reaping while closing parent descriptors. A real
stopped child ignoring SIGHUP proves the leak; the promoted KeyboardInterrupt and
OSError regression both fail before repair in
/tmp/attalambda-terminal-resume-regression-before.log. A nested finally now always
reaches bounded termination after resume. The three focused methods pass source
in9.100s and build07 in9.102s:
/tmp/attalambda-terminal-readiness-regression-{source,artifact}.log. Applied-delta
cold review closes with four real-child failures before/after SIGCONT, checking
exception identity, reaping, all descriptors EBADF and idempotent close. Adjacent
write-failure and undrained-queue cleanup probes also pass. Evidence:
/tmp/attalambda-terminal-resume-cleanup-fixed-review.py and
/tmp/attalambda-terminal-readiness-failures-review.py. All owned children ended.
The harness now has40 Python methods, including22 actual CLI/transcript methods;
no40-method all-passing run is claimed. This changes tests only; no cancellation
behavior in production is changed.

Draft PR7 remains open againstmain at pushed9960d4b. Its body now distinguishes
that revision's source pass/overall CI failure from local development evidence,
and records the completion, cancellation and isolated-consumer blockers. The
installed gh pr edit command failed its legacy projectCards GraphQL query before
updating; the explicit REST pull-request body update succeeded. No branch push,
merge, tag or publication occurred in this continuation. Canonical byte/hash,
saved-contract and active-document link checks pass in
/tmp/attalambda-interactive-handoff-integrity.log; dotenv-safe diff --check passes.

- [x] **9.6 — Preserve notices and packaging integrity.** Add any required notices for newly bundled dependencies through the existing notice/hash process without deleting prior notices or weakening checks. **Check:** version, notices, archive layout, and source-selection validations all remain explicit and reproducible.

Read-only source-closure/notice preparation by command_loop_cold_review identifies
four required package attributions; final archive closure remains unverified.
Installed9.3 package metadata and concrete imports (editor→expeditor/racket-lexer;
lexer→parser-tools/lex; lexer-contract→racket/contract/option) establish the scope.

| Package | Version | Source revision (not the package checksum) |
|---|---|---|
| expeditor-lib |1.2|65e20a410bdc5f09c0682a1bb57cac2b68d73506|
| syntax-color-lib |1.7|e1c5ac5115ed3e6c52430390e6bf9b39c8c7e3df|
| parser-tools-lib |9.0|2f3638fa66c83d0c53f8aec7cc6cfd3775daf8a5|
| option-contract-lib |1.0|50d72f706ef944689e21b65a6c94b3c819989c59|

Each pinned info.rkt declares Apache-2.0 OR MIT. Preserve all15 existing inventory
rows and license blocks. Expeditor's Boyer notice equals the already preserved
notice verbatim; extend its attribution. Also preserve parser-tools' packaged
legacy LGPL notice with a factual provenance note alongside the later pinned
dual-license declaration:upstream commit4afd434f2fcd719132e7a5b2c263faf544f916ca
added that declaration in2021; the legacy LICENSE.txt dates to2014. Sources:
https://github.com/racket/parser-tools/commit/4afd434f2fcd719132e7a5b2c263faf544f916ca
and the info.rkt/LICENSE.txt at the pinned parser-tools revision above. Existing
full Apache/MIT/GPL/LGPL texts remain. data/integer-set resolves within Racket
core, so no unobserved data-lib or test-only rackunit inventory row is warranted.
After template edits, refresh all13 existing digest pins across the three
builders, three consumers and distribution-test.rkt; preserve validation and add
specific new-revision/retained-notice assertions. Template and13pins are now
updated; new SHA256ab740853401a2d0b6c29153c6a10f65e28ad364adf45800b3495205553cb6216.
All earlier license blocks remain, and7new revision/notice assertions are added.
Focused distribution checks pass216. Independent file_load_cold_review verifies
all15 prior inventory rows and22 verbatim blocks remain byte-identical; allfour
package revisions/licenses/source URLs and the later2021dual-license provenance
match installed and pinned upstream sources. Evidence:
/tmp/attalambda-notice-review.{py,log}. Exact archive verification remains open.
- [x] **9.7 — Extend the existing Linux consumer tests.** Add REPL and runtime-input cases to the current consumer workflow, using external test-only PTY tooling when needed. **Check:** the consumer still proves there is no system Racket/raco and covers default/explicit REPL, fallback/transcript, editing, input, cancellation, load/reset, and the old examples. Preserve existing internal portability evidence without claiming new public platforms.

Subdivide before implementation:9.7a prepares the existing pinned Ubuntu consumer
with only test-side Python3 standard library;9.7b transfers the existing Python
harness and invokes only CLIProbe/TranscriptProbe against the absolute extracted
executable;9.7c adds exact runtime-input/documented-transcript checks and repeats
terminal acceptance after relocation. Keep acceptance offline/read-only/non-root
with no Racket, and record actual preparation image ID/package versions. The
networked image preparation is separate from artifact execution. Independent
inspection confirms Ubuntu already includes xterm-256color terminfo; no extra
terminal dependency is needed. The19 current selected methods create all their
fixtures in temporary directories and require no checkout or Racket fixtures.

9.7a/b implementation:tooling/linux-consumer.Dockerfile adds only
Ubuntu Python3 using an empty Docker build context. The consumer transfers only
interactive_pty.py, runs CLIProbe/TranscriptProbe at both extraction paths using
Python isolated mode, and records harness hash/classes/image/package evidence.
Existing locked-down acceptance flags remain. Initial image preparation failed because
Docker tried to write /home/serrecchia/.docker/buildx/activity outside the writable
workspace; the exact escalated retry was rejected by the user (functions620).
That first attempt built no image. Historical log:
/tmp/attalambda-interactive-consumer-image-build.log.
Kyle's later "keep the python testing and finish" instruction renewed preparation;
the escalated retry was accepted and completed0 in exec24797. Image ID is recorded
at the top of this plan and in `/tmp/attalambda-interactive-consumer-image-id-resume`.
It installs14 Ubuntu packages,7.274MB download/27.9MB installed space, no pip tree.
The existing build07 archive then ran in the prepared no-Racket consumer:
21 of22 terminal methods passed in70.504seconds, with advanced cancellation failing
before a second signal was sent. Relocated terminal acceptance did not run.
Exec95739 finished1; owned container/transfer directory were removed.
`/tmp/attalambda-resumed-development-consumer.{json,log}` preserves exact provenance.
No full consumer pass or clean candidate is claimed.

Independent cancellation diagnosis now proves shared completed-promise redirection
can cache a later break in both actual reader and session NIL graphs. Public
lazy/force constructs the completed chains; a read-only observer interrupts only
after the vulnerable state appears. Reader isolation fails the session variant;
automatic reset would discard committed definitions. Current upstream promise.rkt
is byte-identical to installed9.3. No runtime or product cancellation edit was made.
The earlier intermittent failure's exact promise remains unidentified. Evidence:
`/tmp/attalambda-promise-observed-redirect/review.md`, manifest, scripts and logs.
Next independent step is assessing a compliant repair, not repeating old batches.

The bounded remedy review is complete: no supported runner-only mechanism was
found. A killed worker also leaves the shared completed value with a reentrant
promise failure. A narrow correction to the existing Racket9.3 promise invariant
is a scoped dependency repair under2.2, not another evaluator or promise rollback.
`/tmp/attalambda-promise-observed-redirect/runner-remedy-review.md` records the
limits and obligations. Before editing, subdivide the repair:
9.5c1 creates a separate isolated9.3 candidate correcting only redirection of
already completed promises, with pinned original/patch hashes and independent
read-only review. It must retain pending-thunk failure caching and tail-space
behavior. 9.5c2 promotes class regressions and proves actual session/reader
cancellation, lazy effects and focused terminal behavior. 9.5c3 makes the same
reviewed patch reproducible in source/build environments and records patched9.3
provenance, then runs required full source/upstream checks before any checkpoint.
9.5c1/c2 isolated candidate now passes: original promise.rkt SHA256
ad9009b58587dc5e326270e02d21788264abbc5b033cbef716521ff02663b628;
corrected SHA256 bca5b526943be123c8f3fbad24d30556fe3ffea1dc60b6d9c28ec8875e27c7eb;
patch SHA256179be1bbde34542758c87b364ae7717c7355cba58cb880875faf137c521ab1a9.
`/tmp/attalambda-racket93-promise-candidate` is a separate runtime; original9.3
remains unchanged. Upstream lazy promise tests pass261. Independent read-only
review passes marker/cache/link preservation, pending-break caching without replay,
and100000 tail steps with at most one sampled live current link and no historical
links after completion. The first inner-only candidate exposed a root-marker
overwrite through the reviewer's direct-force probe; the corrected candidate
guards both sites. `/tmp/attalambda-promise-independent-review.md` records closure.
Actual reader/session regressions fail before and pass after; old/fresh values,
explicit output and cleanup survive. The real CLI advanced/plain cancellation
method passes in3.212s. Logs are under `/tmp/attalambda-promise-` and enumerated in
HANDOFF. Full40-method source terminal acceptance is running against this runtime.
9.5c3 integration is present: exact patch plus explicit isolated preparation,
read-only source/loaded-runtime check, source-suite preflight, CI preparation,
and all builder/consumer provenance fields. Permanent dependency tests pass5
groups on corrected9.3 and fail3 on original. All40 terminal methods pass92.721s.
Distribution216 and full boundary gate pass. Actual preparation from original
source bytes, fresh-process check, transformation/idempotence/unknown-byte refusal
are verified; the initial rejection probe's broad catch was corrected before
claiming that evidence. Current notices add only correction provenance:
103062bytes, SHA256d0a5ba77357474e66701d1aab00d8546aa0e5ff9c4d265b5a1d5061d173b9131;
13 pins updated. Full current source verification remains open. Corrected
development build08 finished and its exact isolated consumer passed22 terminal
methods at both extraction paths plus existing examples, relocation, runtime-input
transcript and provenance checks. Exact artifact/log evidence is in HANDOFF.
This evidence is not a candidate checkpoint.

Phase9 cold review found two concrete remaining issues. Subdivide their correction
as9.7d before edits: the Windows consumer's exact archive-name pattern still rejects
0.8.0 although its builder accepts/creates that version; extract and exercise the
actual consumer pattern against VERSION and invalid versions/targets before repair.
The standalone design's exact help, missing-argument and misuse descriptions also
disagree with observed launcher output; refresh those descriptions without changing
launcher behavior. Evidence:
`/tmp/attalambda-phase9-packaging-review-_n1ep3qp/results.json`.
9.7d complete: actual extracted-pattern regression fails before1/217 and passes
after217; logs `/tmp/attalambda-windows-version-hunter-{before,after}.log`.
Independent applied-delta review checks the actual regex and exact help/reasons
against captured launcher output, with unchanged launcher hash; no remaining
proven finding. Report and closure:
`/tmp/attalambda-phase9-packaging-review-_n1ep3qp/{review.md,repair-verification.json}`.
This is static/cross-regex Windows evidence, not native Windows execution.
The separate old macOS Intel path-gate failure cannot be causally diagnosed from
its generic log: no matched bytes were recorded and no artifact survives. Old and
current scan rules are identical. Before another native build,9.5d adds a bounded
first-match diagnostic only inside the existing failing branch (needle/file in
hex, file hash/size, byte offset and64 bytes of surrounding context). Preserve
the original search, exclusions, exit2 and cleanup. This is diagnostic preparation,
not a claim that the unobserved native failure is repaired. Review:
`/tmp/attalambda-macos-intel-job104290767080-review.md`.
9.5d diagnostic preparation complete: positive branch emits binary-safe first
match evidence while retaining the exact gate failure. Shell syntax passes;
an extracted-function probe checks literal metacharacters, NUL-containing artifact
bytes, file/needle/hash/size/offset and153bytes of bounded context, preserving
positive exit2 and negative exit0. Log:
`/tmp/attalambda-macos-path-diagnostic-probe.log`. Native outcome remains pending.

Phase9 final reconciliation: current README/API/architecture/acceptance/release
notes describe observed completion and source behavior; no stale contract-choice
or unfinished-completion claim remains in active user docs. Published0.7.0 links
and all three canonical documents are preserved. Current full source evidence is
69 files/26845 assertions/43+6 terminal methods; current-head CI and final artifact
remain explicitly pending. All18 acceptance rows name actual assertions or final
artifact gates. The final docs/provenance review is closed without findings in
`/tmp/attalambda-expeditor-preparation-review-ihudogrm/review.md`.
Next9-checkpoint action: full source/gates with these documentation inputs before
its separate phase commit; inspect new-head CI in parallel and diagnose any failure.

Checkpoint 9 evidence is complete: the full source run and both gates pass;
217 distribution assertions pass again on the final workflow. Canonical prior
bytes/index hashes, exact saved contract, active links and source-review hashes
pass. Remote preflight at 2026-09-15T16:42:52Z still finds no v0.8.0 tag/release;
main remains71232f7. All18 acceptance rows identify executable checks or the
explicit Phase11 artifact gate. Actual docs examples are included in the passing
source suite. No executable product, tests, dependency pins or build/consumer
script changed after the Phase8 commit; this phase changes docs and CI setup.
Current-head CI and clean artifact evidence remain Phase10–11 work.
The final independent ownership/compilation/packaging control completed and
cleaned successfully; no confirmed review finding remains. Evidence:
`/tmp/attalambda-phase9-checkpoint-review-7jrtn7b_/ownership02-cache-results.json`
and `review.md`. This control is not the final clean archive/consumer acceptance.

**Checkpoint 9 — Documentation and packaging review.** Use release-readiness review. Check executable docs and static packaging coverage before the final clean build. The full suite and existing CI configuration must include the new tests or invoke them explicitly; a successful old test count alone is not evidence of the new feature.

### Phase 10 — Review and freeze the candidate source

**Purpose:** close implementation review and establish the clean source revision used by the artifact phase.

10.2b — Diagnose the current CI terminal consumer before editing. Run35008188837
built the Linux archive successfully, then its25-method consumer failed only the
unusual-name case when typing prefix `z日`: native Expeditor reported invalid or
incomplete multibyte input and the process exited. All65 control-name prefixes
and other terminal methods passed. Log:`/tmp/attalambda-phase10-linux-ci.log`.
The consumer explicitly exports `LC_ALL=C`; its Python child inherits that
ASCII-only native locale. Compare the unchanged actual CLI case under C and
C.UTF-8 and review the fixed contract before deciding whether only the terminal
test invocation needs an explicit UTF-8 environment. Preserve the Unicode case,
the deterministic shell checks, all deadlines and the exact artifact gate.
At diagnosis, no executable change had been made and source CI was still running.
Diagnosis is confirmed before repair: the unchanged72-name actual CLI test fails
only at `z日` under C (9.753s, native exit70) and passes in C.UTF-8 (9.798s).
Native Expeditor creates its console locale from the environment, then decodes
bytes with mbrtowc; C declares ASCII, so UTF-8 input fails before completion.
Independent review identifies fixture setup, not a language/completion defect.
10.2b1 will set C.UTF-8 only on the two existing Python terminal invocations and
record that terminal locale in consumer evidence. Keep global C for sorting and
byte checks, preserve every Unicode assertion and deadline, and document the
actual consumer environment. Logs:`/tmp/attalambda-phase10-locale-{C,UTF8}-source.log`.
This does not claim Unicode editing under a deliberately non-UTF-8 native locale.
10.2b1 is applied: two command-scoped locale assignments, one consumer evidence
line and the distribution design explanation. No product/test-body/deadline
change. The affected distribution suite passes217 assertions in
`/tmp/attalambda-phase10-locale-distribution.log`; all18 current source-review
hashes still match. Final independent locale review is closed at
`/tmp/attalambda-phase10-locale-review.md`; its direct no-Tab Unicode sibling
proves native decoding and cleanup under both locales. The full source CI has
now passed; its exact results are recorded in10.3. The new-head Linux consumer
and the exact Phase11 candidate must rerun the unchanged25 methods at both paths.

- [x] **10.1 — Perform a cold implementation review.** Review the current complete milestone diff, this contract, and tests using a separate read-only reviewer when available. Focus on purity, effects/laziness, imports/shadowing, cancellation, stdin, loading, history, and scope. **Check:** each finding has evidence and a severity/rationale; do not manufacture changes when no defect is found.
- [x] **10.2 — Resolve confirmed findings in small units.** For each actual finding, add a regression or reproducible check, patch only the responsible code, and rerun focused checks. Split independent fixes into separate numbered substeps. **Check:** no unresolved correctness or security-boundary blocker remains; rejected suggestions have an evidence-based explanation.
10.2a (before repair): independent current-source review proves stdout and stderr
can be different terminals. The current shared-terminal flag checks only whether
stdout is a terminal; a UI separator on stderr then suppresses the needed stdout
separator. Actual two-PTY shell output is`prefix=> 41\r\n` instead of
`prefix\r\n=> 41\r\n`. Proof:`/tmp/attalambda-phase10-separated-terminals.py`
and`.log`. Add a permanent two-terminal CLI test (recognized/unrecognized terminal settings), then compare
Racket's documented port-file-identity for the two open output ports before
allowing one terminal's UI newline to satisfy the other's result boundary.
Update the exact boundary pins; existing same-terminal and pipe tests must pass.

- [x] **10.3 — Run final source verification.** Run the entire suite, expanded purity, boundary inventory, and PTY cases on the final candidate inputs. Review dotenv-safe diff/whitespace checks and generated-file exclusions. **Check:** record the runtime, commands, logs, actual results, and any outstanding artifact-only checks.

10.3 evidence: CI35008188837 source job104513162394 completed successfully on
Racket CS9.3 after explicit isolated preparation. `./run-all-tests.sh` passes69
Racket files/26,845 assertions;43 shared terminal methods47.226s and6 visual
methods3.528s; expanded purity40 modules and complete boundary/source inventory.
The PR merge commit60450c1ca36cf0604e4b8f312d87803167aded68 and reviewed head549460f
have the same tree `ed17a5a251d1368809d4eb636034eea69ce5e47b`. Source review18-file
hashes match. Subsequent changes are the reviewed consumer fixture locale and
its receipt/docs only; affected distribution suite passes217. Full CI log and
parsed receipt are `/tmp/attalambda-phase9-ci-complete.log` and
`/tmp/attalambda-phase9-ci-summary.json`. Canonical attachment/index/link integrity,
dotenv-safe source scope/generated inventory and whitespace checks pass. Exact
standalone artifact and new-head CI remain Phase11 gates, not inferred passes.

**Checkpoint 10 — Source freeze.** Use a final scope and code review; close the verified phase with its commit/push when authorized. Record the resulting exact candidate commit without claiming the archive is already verified. Do not amend executable inputs during artifact testing without returning to the responsible implementation step and refreshing affected evidence.

### Phase 11 — Build and verify the exact release candidate

**Purpose:** test the artifact from the frozen source, then record artifact-only evidence separately.

11.1a/11.2a — Before execution, harden only the temporary invocation drivers.
Independent review confirms the existing consumer selects25 real CLI/transcript
methods at both paths, but the wrapper's early expected-HEAD check must also be
checked around the build and against the exact output manifest/clean-tree state.
Its cleanup must retain transfer removal and JSON evidence even if container
removal raises or times out. Add these guards to the `/tmp` drivers, check their
syntax and obtain a read-only re-review. Product/build/consumer scripts and
acceptance criteria remained unchanged. At that preparation step the drivers had
not run a candidate; both subsequent verified executions are recorded below.

- [x] **11.1 — Build from the clean candidate revision.** Use the repository's approved Racket CS build runtime and existing Linux build script, with a fresh output directory outside the checkout. Do not use `--allow-dirty` for the candidate artifact. **Check:** record the clean source revision, product/package versions, build command, artifact names, and checksums.
11.1 evidence: `python3 /tmp/attalambda-interactive-candidate-build01.py
3ae392629ecfb380d3dd31451c33fd5617d53f51` finished0 (exec32901). It invokes the
existing Linux builder without --allow-dirty, source read-only, with the pinned
CS9.3 image and isolated runtime corrections. Source commit/tree stayed clean
before/inside/after. Product0.8.0/package0.8;11 files,2 runtime files,
68,881,441 unpacked regular-file bytes. Archive19,602,521 bytes at
`/tmp/attalambda-interactive-candidate-01/attalambda-0.8.0-linux-x86_64.tar.gz`,
SHA256 `1b4b4a338028b11fafe22a4b52c7862c77f9c57e0241e4e037c6b022f6761785`.
Manifest SHA256 `e0597d0506f08ad0661c0dc9d1dab2ac1257afb8d799d3aca3cbb2725a44a95b`;
SHA256SUMS SHA256 `a5382b07aa7190196f114536cf47e86d029a8017b43cc4cd934a88db25fc11ba`.
Log:`/tmp/attalambda-interactive-candidate-build-01.log`; receipt:
`/tmp/attalambda-interactive-candidate-01/build-report.json`. Builder removed.
The following exact consumer result closes11.2 independently of build success.

- [x] **11.2 — Consume the exact artifact without development dependencies.** Run the existing isolated Linux consumer on the output directory, including real terminal tests and relocation to a path with spaces. **Check:** the extracted executable supports both new feature themes without external Racket, source checkout, personal packages, or user initialization files. Artifact failures require a fix, refreshed source verification as affected, and a new clean build.
11.2 evidence: `python3 /tmp/attalambda-interactive-candidate-consumer01.py
3ae392629ecfb380d3dd31451c33fd5617d53f51` finished0 (exec63273). The transferred
archive/hash and frozen consumer/harness bytes match11.1. Same25 actual CLI and
transcript methods pass at both extraction paths in67.185s and78.388s. The
consumer confirms no external racket/raco, no source checkout, guide workflow,
runtime input/snapshot transcript, and relocation pass. Terminal localeC.UTF-8;
Python3.12.3 is consumer test tooling only, absent from the11-file product.
The immutable prepared Ubuntu24.04 image ran offline/read-only/nonroot65534,
capabilities dropped, no-new-privileges, bounded processes/memory and tmpfs.
Consumer container and transfer directory are removed. First startup714ms and
relocated630ms are observations, not performance guarantees. Log/report:
`/tmp/attalambda-interactive-candidate01-consumer.log` and`.json`; combined parsed
receipt:`/tmp/attalambda-interactive-candidate01-summary.json`. The following11.3
record closes new-head CI and independent artifact review; no publication is authorized.

- [x] **11.3 — Reconcile delivery state and handoff.** Verify that the reviewed source, tested source, clean build revision, and recorded artifact actually correspond. Open or update the milestone PR when authorized, verify current-head checks/review, and record any pending external checks without calling them passed. **Check:** provide the concise handoff in §7; stop at the candidate unless explicit merge/publication authority is present.

11.3 evidence: CI35010700799 completes successfully with all ten jobs at the
exact build head. Its PR merge commit2dcc67ef7f8fb17e8b2c7f88ce8d16a21c0c6761 has
the identical build tree. Source results:69 files/26,845 assertions;43 terminal
methods51.387s and6 visual methods3.902s;40 pure modules and complete boundaries.
Full log:`/tmp/attalambda-phase10-ci-complete.log`; summary:
`/tmp/attalambda-phase10-ci-summary.json`. Remote temporary artifacts are absent.
The exact-artifact independent review closes with no actionable findings:
`/tmp/attalambda-final-artifact-review-t48v0bdw/review.md`; adjacent observations
verify all11 files, all25 method identities at both paths, source/patch/notices
hashes, consumer isolation and actual cleanup. Current source review hashes match.

The Phase11 record reconciles README/API, acceptance, candidate notes, distribution
design, PLAN and HANDOFF only. The archive remains built from3ae3926 regardless
of later record SHA. The final record-head CI/review and exact Git/PR state must
be saved after commit in `/tmp/attalambda-interactive-final-state.json`; its absence
or pending status means final delivery reconciliation is not finished. No extra
commit is required merely to insert a commit's own SHA into itself. No merge,
tag or publication is authorized; the exact candidate is retained locally.

**Checkpoint 11 — Final release-candidate gate.** Use release verification and a final scope review. Close this phase with a documentation-only evidence commit when authorized; preserve the exact earlier build SHA rather than relabeling the archive as built from the later record commit. No executable-input change may rely solely on stale evidence. If only publication-record documentation changes afterward, state why prior artifact evidence still applies. Leave no owned test workers, listeners, containers, or temporary source modifications running or staged accidentally.


## Phase 12 — Publish AttaLambda 0.8.0 (authorized)

Kyle authorized this phase with “lets do it” after the release procedure was
explicitly described: merge PR #7, verify merged source, build/consume it, tag,
publish and verify public downloads. This supersedes the earlier candidate-only
stop; the saved specification remains unchanged. No new product scope or
platform is added. Historical release assets must remain intact.

Live effect receipt: `/tmp/attalambda-080-release-state.json`. During the clean
merged-source build, the existing handoff's post-commit receipt points to this
continuation. Repository publication records are applied after that build so
the clean merge is the exact archive source; no dirty build or altered source
identity is permitted.

- [x] 12.1 — Current PR head fd8bafa and main baseline71232f7 verified; all ten
  exact-head CI jobs pass; completed independent reviews have no findings;
  v0.8.0 tag/release absent; older releases/assets snapshotted.
- [x] 12.2 — Merge exact reviewed PR head using an expected-SHA guard. Verify
  actual merge tree and all merged-head checks before proceeding.
- [x] 12.3 — Fresh clean merged-source build and existing isolated Linux
  consumer, including all25 CLI/transcript methods at both extraction paths.
- [x] 12.4 — Create unsigned annotated tag at exact build commit, push that
  tag only, create draft with --verify-tag, upload exact archive/checksum once,
  and compare authenticated draft downloads to the verified local bytes.
- [x] 12.5 — Publish only that verified draft, mark latest, download fresh
  public files without authentication, compare both hashes and run the same
  consumer on the actual downloaded copy. Preserve all earlier releases/assets.
- 12.6 — Record IDs, dates, source/tag/archive identities, public-copy tests,
  cleanup and release-ledger/README/API state. Independently review and verify,
  then commit/push documents only on main. The post-commit receipt
  `/tmp/attalambda-080-release-state.json` closes this step only after final
  record-head CI, exact-head review and clean Git state pass. Do not relabel
  the archive or create a self-referential evidence commit.

12.2a completed: PR #7 merge f309199baa170ba5b12ff6b18b60dc49c114a8a1 has tree
0ed67ac08a6f0fc2696741791e272b407d30f5c6, exactly equal to reviewed fd8bafa.
Local main fast-forwarded cleanly. Merged CI35017215218 passes all ten jobs:
69 Racket files/26,845 assertions;43 shared terminal methods48.887s;6 visual
methods3.627s;40 pure modules and complete boundaries. Full log/summary at
`/tmp/attalambda-080-merged-ci-complete.log` and
`/tmp/attalambda-080-merged-ci-summary.json`.
Release drivers are literal path-only variants of the independently verified
candidate drivers. Output `/tmp/attalambda-0.8.0-release` is fresh; image pins,
420s build/900s consumer bounds, expected-SHA and clean-tree checks, exact
manifest/checksum/script identities and cleanup are preserved. A separate public
consumer reads `/tmp/attalambda-0.8.0-public-download` and compares against the
original release build receipt; it cannot silently retest the original archive.

12.3a completed: release build driver finished0 with clean f309199 source.
Archive19,602,535 bytes; SHA256
`f1b8b49ba659485e089ffcf38d1d5999016131de65e21177bb922fa86013d3fc`;
manifest SHA256 `359b53bfca5c0cd11ed42f5528c3e8ea2bb60093b895d962cb45c689eeb3afc9`;
SHA256SUMS SHA256 `9129165ef63481b39a35a47035ab7bff72e194427e7811ef179481639a8d4fde`.
Log:`/tmp/attalambda-080-release-build01.log`; receipt:
`/tmp/attalambda-0.8.0-release/build-report.json`. Exact consumer passes all25 methods at both paths in99.417s and57.933s;
container and transfer are removed. Log/report:
`/tmp/attalambda-080-release-consumer01.log` and`.json`; parsed summary:
`/tmp/attalambda-080-local-consumer-summary.json`. Independent review is closed.
Repository edits after the clean build are publication records only.

12.3b completed: independent release-artifact review closes without findings at
`/tmp/attalambda-080-release-artifact-review-c3bw_6tv/review.md`, with exact
provenance, method identities at both paths and observed cleanup.
12.4 completed: unsigned annotated tag8628ca652e7ebf9ff3932d332fc57b611e3fd023
peels to clean buildf309199. Draft389458950 assets566456157 (archive) and566456156
(SHA256SUMS) match expected sizes/hashes. Authenticated draft downloads match
byte for byte: `/tmp/attalambda-080-draft-verification.json`. Initial lookup by
tag returned404 for this draft; authenticated release listing located exactly
one matching draft by tag/target/body, then immutable-ID reads verified it.
No duplicate draft was created and no asset was overwritten.
12.5 completed: published verified draft at2026-09-15T20:32:24Z, latest0.8.0.
Public GETs are unauthenticated, with curl-q disabling personal configuration,
and return200 for19,602,535 archive bytes and103 checksum bytes. Both hashes
match the local release. Local umask002 produced0664 mode; the wrapper's unchanged
0644 precondition stopped before container execution. Only those two public-file
modes were corrected; first failed receipt is preserved at
`/tmp/attalambda-080-public-consumer01-precondition-failure.json`. Unchanged
public-copy consumer passed all 25 methods once at each path in 52.529s and
59.059s, with no skips. Runtime input, snapshot transcripts, guide/API/file/TCP,
exit and relocation gates passed. Its container and transfer were removed.
`/tmp/attalambda-080-public-final-verification.json` binds the public log/receipt,
tag/latest readbacks and preservation of six earlier releases, twelve assets
and six tags. Public review:
`/tmp/attalambda-080-public-review-1tngp_s6/review.md`, no actionable findings.

12.6 publication records describe observed 0.8.0 delivery in README/API,
architecture/host-boundary status, release notes, acceptance, current project
instructions, distribution ledger and this plan/handoff. Older release-ledger
sections retain their bytes. Canonical documents, the saved interactive
contract, both marked executable API examples and all product/test/build inputs
are preserved. Final checks/review and the resulting record commit are bound
in the post-commit receipt rather than relabeling the earlier archive.

---

# Historical plan — terminal input

# Terminal line input

Status: implemented and verified on `terminal-input`, starting from clean `main` at
`71232f7`. Kyle authorized implementation on 2026-09-14 after agreeing that
program input should provide a reusable foundation for a later REPL.
Contract: [terminal input](docs/terminal-input-spec.md). No merge or release
is authorized by this plan; published 0.7.0 remains unchanged.

## Verified starting state and scope

`effects/protocol.rkt` and `runtime/host.rkt` support ten operations: stdout,
files, blocking TCP, and exit. There is no standard-input operation or wrapper.
`lang/expander.rkt` injects the sole host and forces top-level expressions in
order. Existing tests prove that a forced effect result is cached. The codec
constructs Result and String values but has no Option constructors. The
existing Option type already distinguishes SOME from NONE. The related
`all_the_lambdas` repository has no production stdin/line-input implementation
to reuse; its input references are subprocess test plumbing.

Modify the protocol, host, codec, language facade, exact boundary enforcement,
focused tests, API/architecture/host docs, and canonical specification addenda.
Create `effects/stdin.rkt`, focused input suites, and the contract below;
put the runnable example in the API documentation and test that exact example.
Core, representations, evaluator, macros, runner, dependencies, existing
operations, VERSION, and published artifacts remain behaviorally unchanged.

## Phase 1 — Implement and verify line input

- [x] Step 1.1 — Save the contract and append scoped canonical amendments,
  preserving all earlier specification bytes and updating their hashes.
- [x] Step 1.2 — Add the pure unary Unit wrapper and zero-argument request
  schema; add deterministic Option construction and native byte-line input.
- [x] Step 1.3 — Expose only public `read-line`, inject the host once, and
  extend exact boundary checks without granting native input elsewhere.
- [x] Step 1.4 — Test typing, propagation, laziness, fresh/cached reads,
  line endings, byte preservation, EOF, failures, request rejection, and
  source/runner interaction using automated pipes and isolated package homes.
- [x] Step 1.5 — Document the unreleased API and runnable example, including
  effect ordering and the future REPL boundary. Review the completed diff.
- [x] Step 1.6 — Run focused suites, the complete suite, expanded purity,
  and boundary inventory; record evidence, commit, and push this branch.

Focused result: all 444 assertions in stdin, input-language, and boundary
suites pass (`/tmp/attalambda-input-focused-final.log`). The source and runner
tests prove prompt-before-input ordering, waiting on partial lines, recursive
fresh reads, saved-answer reuse, EOF and blank-line distinction, unselected
branches, byte preservation, and private binding isolation. Unit tests also
exercise direct defensive dispatch and synthetic I/O/allocation failures.
Expanded purity passes all 40 production modules
(`/tmp/attalambda-input-purity.log`). All earlier canonical specification bytes
are preserved and their updated index hashes match; local document links resolve.

Test development corrected only harness assumptions: the native custodian
parameter's exact name, structured host-error checks instead of unsupported
formatted spellings, and local rather than module-wide shadowing for an alias
test. No production correction was needed. The multi-file raco runner needed
approved sandbox escalation for its `/var/tmp` scratch files; the final run
passed without changing implementation to address that environment limit.

Final result: all 48 source suites pass 17,596 assertions, followed by the
expanded purity proof for all 40 production modules and the complete boundary
inventory. Logs: `/tmp/attalambda-input-full.log` (31 completed suites) and
`/tmp/attalambda-input-full-resumed.log` (the remaining 17 suites and both
gates). The first run reached an existing purity fixture using read-only
`/var/tmp`. Escalation for the remaining script was denied; inspecting the
fixture confirmed it needs only a directory outside the repository. Setting
`TMPDIR=/tmp` preserved that condition and allowed verification inside the
sandbox. The resumed purity suite also exposed its old expected count of nine
effect modules; updating that single assertion to ten retained every expanded
purity check. No other test or production code changed during the full run,
so the earlier 31 passing suites remain applicable.

Final diff review: executable changes add only the Unit-triggered input
wrapper, protocol entry, native line read, deterministic Option constructors,
public binding, and exact boundary vocabulary/enforcement. Tests add the two
input suites, native-input rejection cases, and the effect inventory count.
Documentation adds the contract, scoped specification amendments, tested API
example, and current architecture/host/source availability notes. Core,
macros, runner, VERSION, and package metadata have empty diffs. Dependencies
and existing operations retain their behavior; the shared host and codec
files are modified as described above. No merge, release, or binary publication is part
of this phase. The focused review and authorized documentation/test follow-up
are recorded below.

## Focused bughunt — 2026-09-14

Kyle authorized a focused correctness review of `71232f7..fff9956` and its
direct interactions. Close-read coverage includes the new input wrapper,
protocol, codec, facade, host input/shared validation and dispatch paths,
generalized checker, Option/Result, both input suites, the contract and
canonical amendments. The review also traced the changed boundary/purity
checks and tests, runner source execution, and related documentation changes.
Unrelated native operation bodies were skimmed. The remaining language
algorithms, unrelated suites, and binary packaging were outside this pass.
An independent reviewer reproduced the behavior below. The initial review
made no executable or test changes.

**Observed behavior: native CR lookahead; accepted, not a runtime defect.**
`runtime/host.rkt:256` uses `read-bytes-line` in `any` mode. Send `first\r`
through an open pipe and wait for a response without sending another byte:
the read remains pending. Sending a subsequent LF, ordinary byte, CR, or EOF
allows it to return `first`; subsequent line contents are correct. Control
probes with LF and complete CRLF return while the writer remains open.
This can stall a CR-delimited request/response exchange over pipes. The
original review called it a confirmed defect and a specification conflict;
that classification was too strong. It interpreted reading "until a line
separator" as promising immediate completion after CR, even though the
contract expressly selects Racket's `any` mode. The waiting is proven; a
need to replace Racket's reader was not established.

Kyle authorized retaining the existing reader, clarifying the contract/API
wording, and adding delayed-input regression tests. The accepted behavior
is Racket's `read-bytes-line` in `any` mode, including looking ahead after CR
to recognize CRLF. This resolution adds no production code, state, host
capabilities, or purity exceptions. No contract decision remains pending.

Reproduction drivers are `/tmp/attalambda-input-delayed-cr-probe.rkt` and
`/tmp/attalambda-input-recovery-probe.rkt`. Each uses an open pipe, a reader
thread, a 250 ms observation window, then supplies the remaining input and
checks the resulting line. The recovery probe also confirms fresh reads
recover after transient EOF and I/O failure on the same still-open port.
Phase 2 turns the delayed-input driver into bounded regression tests covering
CR followed later by LF, another byte, CR, and EOF, with LF/complete-CRLF
controls. The recovery probe found no defect and does not require a fix.

Fresh verification: `TMPDIR=/tmp raco test tests/stdin-test.rkt` passes
223 assertions and `TMPDIR=/tmp raco test tests/input-language-test.rkt`
passes 76 assertions. `TMPDIR=/tmp racket tooling/check-purity.rkt` passes
all 40 production modules, and `TMPDIR=/tmp racket tooling/check-boundaries.rkt`
passes the full source inventory and host/language boundaries. The earlier
complete-suite result above remains the baseline; it was not rerun for this
review. No other confirmed or unresolved likely defects were found within
the stated coverage. All initial review-owned processes exited.

## Phase 2 — Clarify and test the accepted native behavior

Modify this plan record, `docs/terminal-input-spec.md`, and `docs/API.md`;
create `tests/stdin-stream-test.rkt`. Runtime behavior, canonical specification
files, dependencies, purity enforcement, and release artifacts stay unchanged.

- [x] Step 2.1 — Correct the review classification and explicitly document
  native line-reading behavior, including the wait after a bare CR.
- [x] Step 2.2 — Convert the delayed-input probe into bounded tests of the
  actual wrapper and host, including line contents after each delayed suffix.
- [x] Step 2.3 — Run focused and complete verification, obtain a fresh cold
  review, record results, and commit/push this phase on `terminal-input`.

Focused verification: all 15 cases in `tests/stdin-stream-test.rkt` pass
(`/tmp/attalambda-stdin-stream-focused.log`). The suite covers empty/nonempty
lines, LF/complete-CRLF controls, delayed CR suffixes, partial lines, following
line contents, repeated EOF, and leaving input open. It waits for observed
pipe consumption before asserting that a read is pending and gives every
read a deadline. Cleanup explicitly closes both pipe ports and uses a
custodian to stop reader threads, including on assertion failure. The cold
review proved that the first test draft incorrectly relied on custodian
shutdown to close pipe ports; that assumption was corrected in the harness.
A permanent failure-path case deliberately interrupts a waiting reader, then
verifies that both ports are closed and the reader thread is dead.

The fresh cold review found no remaining issues after that correction. In an
isolated copy, alternate native newline modes fail 10 of the 14 stream cases,
and readers that never consume input fail all 14 consumption guards.
Removing either explicit pipe close independently fails the permanent
cleanup regression. Instrumented success and forced-failure runs verify all
captured ports close and reader workers stop. The reviewed test file's SHA-256
is `2ce21fa9baceda16504e07e625bd7d4d60574af0cccf06693fbb26dd215dd2b5`;
probe copies are under `/tmp/attalambda-input-cold-review-h4vubzhm`.

Final verification: `TMPDIR=/tmp ./run-all-tests.sh` passes all 49 suites
(17,611 reported tests, including the 15 new compound test cases), followed
by the expanded purity check for all 40 production modules and the complete
source inventory/boundary gate. Log: `/tmp/attalambda-input-native-full.log`.
All eight local document links resolve and `git diff --check` passes.
The complete run includes the final, cold-reviewed test file; the cleanup
correction was made before that run reached the new suite.

Final scope: three documentation files and one new test suite. Production
modules, the three canonical specification files and their index, purity
enforcement, dependencies, VERSION, and release metadata have empty diffs
against `fff9956`. This follow-up preserves native input behavior and closes
the focused review without a remaining runtime finding or design decision.
The verified phase is recorded on `terminal-input`; no merge or release is
part of this work.

---

# Completed small Lisp sugar and release 0.7.0 (historical)

Status: complete. PR #6 is merged, and AttaLambda 0.7.0 is published and verified.
Kyle authorized the supplied sugar contract,
a pull request merged to main, and another release on 2026-09-09. This request
supersedes the completed cleanup plan's stop-after-merge limit.
Contract: [supplied sugar specification](docs/small-lisp-sugar-spec.md).

## Verified starting state and scope

Clean main starts at `d523bbb` (merged cleanup PR #5). VERSION is 0.6.0 and
GitHub's latest stable release is v0.6.0. The existing expander permits unary
lambda and single-name let, has a currying helper for rec, and checks source
binding dependencies before expansion. List and cond syntax do not exist.

Modify `lang/expander.rkt`, exact boundary vocabulary, focused tests, syntax
and release docs, version projections, and the existing Linux consumer.
Create this saved contract, sugar tests, and 0.7.0 notes. Core, effects,
runtime, host, representations, dependencies, and purity enforcement remain
behaviorally unchanged. Multi-binding let is sequential; empty let returns its
body. Cond requires a final else. Keep production changes around 80 lines.
The release retains Linux x86-64 as the only supported public binary.

## Phase 1 — Implement and verify the four sugars

- [x] Step 1.1 — Save the contract and implement mechanical syntax lowering,
  including the existing recursion analysis's binding scopes.
- [x] Step 1.2 — Test behavior, malformed syntax, partial application,
  laziness, shadowing, recursion rejection, and actual expanded purity.
- [x] Step 1.3 — Update the syntax contract and release inputs to 0.7.0;
  exercise all four sugars in the packaged Linux consumer.
- [x] Step 1.4 — Review the diff, run the full suite and both gates, record
  evidence, commit and push the verified feature branch, and open the PR.

Focused result: all 157 sugar assertions pass, including actual expanded
expressions accepted by the unchanged purity expression checker and the
expander's exact boundary gate. The expander diff is 56 added and 16 removed
lines. Test development corrected two test-only issues: an omitted reader
module wrapper and an assumption that typed cons never forces tail elements.
The final test compares its demand with hand-written cons; no production fix
was needed. Evidence: `/tmp/attalambda-sugar-focused-final.log`.

Integration result: existing language, runner, boundary, and distribution
suites pass all 832 assertions (`/tmp/attalambda-sugar-integration.log`). The
Linux preview built with full Racket CS 9.3 and passed the isolated Ubuntu
consumer, including packaged sugars, existing API/printing, guide, files,
TCP/HTTP, exit statuses, and relocation. Racket/raco were absent and external
networking disabled. It is an internal uncommitted preview, not publishable.
Archive: `/tmp/attalambda-070-sugar-preview/attalambda-0.7.0-linux-x86_64.tar.gz`,
14,164,528 bytes, SHA-256
`b13ce46cdce0d9a24d17ac127dc2e72713a39c594ab6799c5ad34d18cfaf977a`.
Logs: `/tmp/attalambda-070-preview-build-final.log` and
`/tmp/attalambda-070-preview-consumer.log`. The first container mount `/src`
collided with embedded `syntax/srcloc`; using `/attalambda-sugar-070-source`
passed the unchanged build-path gate. No build-script or legal-byte fix was
needed. The stock image also needed its existing prerequisite git installed
inside the disposable container. No host installation changed.

Final local result: all 46 source suites pass 17,290 assertions, followed
by the expanded purity proof for 39 production modules and the complete
boundary inventory (`/tmp/attalambda-sugar-full.log`). The completed diff was
reviewed against the supplied spec and direct binding/expansion interactions;
no production correction was needed after the initial implementation. Core,
effects, runtime, macros, and runner have empty diffs, and legal bytes are
unchanged. Phase 1 was committed as `8e18f04`, pushed, and opened as PR #6.
Kyle explicitly allowed Git writes after the initial permission rejection;
`small-lisp-sugar` was created from the fetched, unchanged main revision.
The remote main revision was independently verified as the same `d523bbb` via
GitHub's API. All session-owned containers have exited. No process is left
running after local checks finish.

## Phase 2 — Merge and publish the verified release

- [x] Step 2.1 — Address actionable PR review feedback and require all CI
  checks to pass; merge the reviewed PR to main.
- [x] Step 2.2 — Build the clean merged revision with full Racket CS 9.3;
  verify the exact archive with the isolated no-Racket Linux consumer.
- [x] Step 2.3 — Tag the exact build revision, stage the two verified assets,
  compare draft downloads, publish 0.7.0, and verify public downloads.
- [x] Step 2.4 — Persist release provenance and completion in the existing
  docs and handoff, commit/push those records, and leave main clean.

Git access: Kyle explicitly allowed Git writes on 2026-09-09 after the first
escalation was rejected. Fetch and branch creation succeeded on retry. The
original request already authorizes the PR, merge to main, and 0.7.0 release.

Phase 2 result: PR #6 passed all ten checks and automated review, then merged
as `ab8c9b28bf544fe368695b40a33b1a254d1cf8dc`. Its tree equals the tree of the
reviewed and CI-tested PR head. The clean merged build and isolated consumer
passed. Tag `v0.7.0` points to that build commit; release `385434426`
was published at `2026-09-09T10:54:27Z` after exact draft-download verification.
Fresh unauthenticated public downloads match both original hashes and pass
the complete isolated consumer. The release is latest, contains exactly the
Linux archive and SHA256SUMS, and preserves every older release and asset.
Archive SHA-256: `af3e14784f7e6c885db38a055ab2d9faeaf7bf5a4e3a475d21e53055aa184f28`.
Checksum-manifest SHA-256: `49a79635332eb7144c82f7fd43413294a17b7f0c6fa8e5bffcf1753cc6fdd389`.
Exact asset IDs, sizes, tag object, and provenance are in the release ledger.

Evidence: `/tmp/attalambda-070-build.log`, `/tmp/attalambda-070-consumer.log`,
`/tmp/attalambda-070-public-consumer.log`, `/tmp/attalambda-070-pr-ci.log`,
and `/tmp/attalambda-070-release-state.json`.
Publication records change only documentation outside archive inputs; prior
source/CI/consumer evidence applies to identical executable and test inputs.
All local links and specification/legal hashes were checked before committing
these records. No implementation, review, merge, or publication work remains.
Future work needs a new instruction.

---

# Completed minimal cleanup (historical)

# Minimal cleanup

Status: cleanup work complete, including all three PR review corrections.
Phases 1 and 2 are implemented; Phase 3 was
assessed and skipped under the spec's size limit. Branch `minimal-cleanup`
starts from clean, synced main `9708ab7`.
Contract: [supplied cleanup spec](docs/minimal-cleanup-spec.md).
Keep the three changes independent and small; this is not a general refactor.

## Verified starting state and scope

`runner/attalambda.rkt` completes symlink targets against the working directory
and validates VERSION against an explicit historical list. Existing runner
tests cover absolute parent symlinks, source symlink rejection, and dotenv
paths, but have no relative parent-symlink regression. The boundary checker's
`strict-vocabulary-violations` checks all source symbols, including local names.

Modify only the runner, focused tests, and the necessary boundary checks.
Create the saved cleanup spec and update this plan. Language semantics, public
APIs, runtime/effects/core behavior, purity checks, host capabilities, VERSION,
package-version projection, dependencies, and release behavior stay unchanged.
Kyle subsequently authorized completing this spec without further `next`
prompts, pushing it, opening the PR, addressing every review comment requiring
code changes, and merging to main after the PR checks pass. Stop immediately
after that merge; no release or further project work is authorized.
Delivery: [PR #5](https://github.com/kserrec/attalambda/pull/5).

## Phase 1 — Fix relative symlink resolution

- [x] Step 1.1 — Add one regression with a relative directory symlink, a valid
  program beneath its target, and a different process working directory;
  observe the existing failure before changing production code.
- [x] Step 1.2 — Resolve relative targets against the symlink's directory.
  Preserve the resolver's loop detection and all source security checks;
  adjust the exact import check only if the fix needs it.
- [x] Step 1.3 — Run runner tests, then the full suite including purity and
  boundary checks. Record the result, commit, and push this phase.
- [x] Step 1.4 — Correct the relative-loop regression found during PR review:
  normalize each already-walked component before loop detection, retaining
  physical parent traversal through symlinks. Add focused regressions, run
  runner tests and the full suite, and push the verified correction.
- [x] Step 1.5 — Permit repeated visits after a symlink target has finished
  resolving, while retaining cycle detection during target expansion. Test a
  valid revisit and a cycle with a growing suffix, then verify and push.

Phase 1 result: the new relative-parent-symlink regression failed with status
66 before the fix. The resolver now supplies the symlink's containing directory
to `path->complete-path`; only the required runtime import and its exact
boundary expectation changed alongside it. Existing security tests are unchanged.
Focused runner and boundary tests passed 228 and 138 assertions, respectively.
The complete suite passed all 45 files and 17,069 assertions, plus expanded
purity for 39 production modules and the complete boundary check. The initial
full run was interrupted during `milestone-two-acceptance-test.rkt`; with code
unchanged, verification resumed at that file and completed the remaining tests
and both scans. Logs: `/tmp/attalambda-cleanup-phase1-full.log` and
`/tmp/attalambda-cleanup-phase1-resumed.log`.

## Phase 2 — Validate version format

- [x] Step 2.1 — Replace only the runner's historical alternation with
  MAJOR.MINOR.PATCH validation, retaining the project's -dev and -rc.N forms.
  Keep VERSION reading/embedding, output, and package projection unchanged.
- [x] Step 2.2 — Add a hypothetical future-version case; retain current
  version tests and malformed-version rejection.
- [x] Step 2.3 — Run runner tests, then the full suite and both structural
  checks. Record the result, commit, and push this phase.
- [x] Step 2.4 — Reject full-sized VERSION reads so a valid 64-byte prefix
  cannot hide trailing data. Keep the read itself unchanged, test the size
  boundary, and verify/push together with the PR's loop correction.

Phase 2 result: one runner regular expression now validates three numeric
version components without leading zeros, with optional `-dev` or `-rc.N`.
An isolated `0.6.1` probe failed before the change and succeeds afterward.
Existing version tests are retained; added cases cover future stable,
development, and release-candidate versions plus malformed formats. All 261
runner assertions passed. The complete suite passed all 45 files and 17,102
assertions, plus 39-module purity and complete boundaries. VERSION reading,
embedding, and CLI output keep their existing implementation; release metadata
and package projection are unchanged. Only the validation expression, runner tests/comment, and
this plan changed. Logs: `/tmp/attalambda-cleanup-phase2-focused.log` and
`/tmp/attalambda-cleanup-phase2-full.log`.

## Phase 3 — Remove unnecessary local-name policing, if small (skipped)

- [x] Step 3.1 — Determine whether local binding names can be excluded from
  vocabulary checks with a small change. Skip this phase with a concrete
  reason if it would require a redesign; do not broaden the scope.
- [x] Step 3.2 — If feasible, make that narrow change and add one harmless
  local-rename fixture. Preserve languages, imports, exports, privileged names,
  forbidden capabilities, mutation rules, runtime/codec/host separation,
  runner loading, effects, classification, and security-sensitive structure.
- [x] Step 3.3 — Run boundary tests including existing prohibited-capability
  and import fixtures, then the full suite and both structural checks.
  Record the result or skip reason, commit, and push this phase.

Phase 3 assessment: intentionally skipped; Step 3.2's conditional implementation
and new regression do not apply. An isolated copy of `readers/bool.rkt` passes
its boundary check, but changing only the `value` parameter and its reference
to `previously-unseen-local` produces `unapproved-reader-identifier`.
`strict-vocabulary-violations` consumes `module-symbols`, which recursively
flattens all symbols without binding scope. A general exemption would need new
scope analysis for local definitions, lambda/let forms, loop bindings, and
macro syntax. Merely adding all bound spellings to the vocabulary would also
exempt out-of-scope references to those spellings. That security-sensitive
analysis exceeds this minimal cleanup; the spec explicitly says to preserve
the checker instead. No vocabulary, capability, import, structural, or purity
restriction was removed, and no source or test file changed in this phase.
All 138 boundary assertions passed again
(`/tmp/attalambda-cleanup-phase3-boundary.log`). Phase 2's complete 45-file,
17,102-assertion suite and both structural checks apply to identical executable
and test inputs; the PR runs the complete checks again before merge.

## PR review corrections

The first two actionable findings on PR #5 were reproduced and corrected. Relative
loop targets containing `.` or `..` produced ever-growing lexical paths;
normalizing each already-walked component makes loop keys stable while
preserving physical parent traversal through symlinks. The widened version
format also admitted a valid-looking 64-byte prefix followed by unseen junk;
rejecting a filled buffer establishes EOF without changing the original read.
Tests cover both loop spellings, physical parent traversal, an accepted
63-byte VERSION, and rejected 64-byte reads with and without trailing data.

That correction's focused runner suite passes 283 assertions. The complete suite passes
all 45 files and 17,124 assertions, plus purity for 39 production modules and
the complete boundary checker. Logs:
`/tmp/attalambda-cleanup-pr-focused-final.log` and
`/tmp/attalambda-cleanup-pr-full-final.log`.
The earlier partial run was stopped when the second review finding arrived;
these final results cover both corrections together. No checker restriction,
release metadata, package projection, core/effect/runtime code, or public API
changed in this follow-up. PR checks and a fresh review of the corrected
commit are required before the authorized merge, after which work stops.

The fresh review found a valid repeated symlink visit rejected as a loop.
An isolated `link/../../link/program.attl` probe returned status 66 while the
direct target ran successfully. The resolver retained completed links in its
loop history. Step 1.5 limits that history to active target expansions, with a
completion marker before each original path suffix. The valid revisit now runs;
a cycle whose remaining suffix grows still returns status 66. All 291 focused
runner assertions pass. The final complete suite passes all 45 files and
17,132 assertions, plus purity for 39 production modules and the complete
boundary check. Logs: `/tmp/attalambda-cleanup-revisit-focused.log` and
`/tmp/attalambda-cleanup-revisit-full.log`. This correction changes only the
resolver, its focused regression coverage, and this plan. A fresh PR review and
all checks must pass before merging; stop after the merge.

---

# Completed release 0.6.0 (historical)

# Release 0.6.0 — Generic pure printing

Status: complete. AttaLambda 0.6.0 is published and its public Linux download is
verified. Kyle explicitly requested publication
on 2026-09-08 after confirming that the printing implementation was merged but
not yet released. That request authorized both release phases without another
approval pause, covering version 0.6.0, its verified Linux x86-64
archive and SHA256SUMS, annotated tag v0.6.0 at the clean build commit, GitHub
Release publication, public-download verification, and current release records.
The completed implementation plan below remains historical evidence.

## Verified starting state and scope

Clean main is `0f85683d3b8747078b532d88bc0ccecfb7ac610b`. PR #4 is merged and
all ten jobs in CI run 34188023243 passed (45 source files, 17,064 assertions,
39 pure modules, and complete boundaries). VERSION contains 0.5.0; info.rkt
projects it to 0.5. GitHub's latest public release is v0.5.0. No 0.6.0 release
notes exist. The existing Linux consumer checks 31 public-API cases but does
not yet exercise the printing API in the packaged executable.

Modify the closed version allowlists, version metadata, runner/version tests,
Linux consumer, bundled guide, and release/status documentation. Create
`docs/releases/0.6.0.md`. The pure core, effects, runtime/codec, host protocol,
representations, macros, public API, specification texts, dependency set, legal
bytes, and purity enforcement remain behaviorally unchanged. Only Linux x86-64
is published; macOS and Windows remain internal CI portability checks. Preserve
all older releases, tags, and assets. Use the existing cached full Racket CS 9.3
image and the existing isolated Ubuntu consumer; no new release framework.

## Phase 1 — Prepare and verify the release inputs

- [x] Step 1.1 — Add exactly 0.6.0 / package 0.6 to all closed version paths;
  update current runner expectations while retaining historical accepted states
  and rejection tests. Record the new state in the distribution contract.
- [x] Step 1.2 — Write accurate release notes and bundled printing guidance.
  Add a public-only Linux consumer program exercising all thirteen printing
  callables, recursive data, Error text, byte escaping, effect results, and
  exact output without an implicit newline. Keep published download links at
  0.5.0 until the new release exists.
- [x] Step 1.3 — Run focused version/distribution/boundary tests, exercise the
  documented program, then run the full source and structural gates. Commit
  and push one verified preparation phase on main; inspect its CI. Capture the
  exact clean build commit before proceeding.

Phase 1 result: version 0.6.0 / package 0.6 is accepted only in the existing
closed version paths, with historical states preserved. The new Linux consumer
uses all thirteen printing callables and checks recursive data, Error text,
UTF-8 byte escaping, lazy output, returned Result, and exact bytes without an
implicit newline. Its source and the release-note example passed in an isolated
installation. The focused version/boundary/distribution/example run passed
581 assertions (`/tmp/attalambda-060-focused.log`). The complete source gate
passed all 45 files and 17,065 assertions in one run, with 39-module expanded
purity and complete boundaries (`/tmp/attalambda-060-full-suite.log`).
Use `env TMPDIR=/tmp` for local checks: the initial request for tests outside
the sandbox was rejected, and selecting the permitted temporary directory let
all tests pass inside the sandbox without changing test behavior or deadlines.
All 32 local links in the four changed Markdown documents resolve. Canonical
specification and legal hashes match the starting revision. The pure core,
effects, runtime, facade, macros, and specification text have no diff. This
verified preparation commit is the clean input for Phase 2; CI must pass before
publication, alongside the exact archive's independent consumer result.

## Phase 2 — Build, publish, and verify 0.6.0

- [x] Step 2.1 — Build the final archive and SHA256SUMS from the clean prepared
  commit with the existing Racket CS 9.3 builder. Run the isolated no-Racket,
  no-checkout Linux consumer, including printing, guide, file/TCP/HTTP, process
  statuses, and relocation. Require all preparation CI jobs to pass. Record
  exact provenance, archive inventory, sizes, and both hashes.
- [x] Step 2.2 — Create the annotated v0.6.0 tag at that build commit, stage a
  GitHub Release with exactly the verified two assets, and compare downloaded
  draft bytes with the originals. Publish as the latest stable release, then
  fetch both public URLs without authentication and verify hashes, manifest,
  version, and packaged printing. No repeated permission request is needed:
  publication is the explicit task Kyle authorized above.
- [x] Step 2.3 — Update README downloads, API/specification status, release
  notes, acceptance evidence, release ledger, AGENTS.md, and handoff to the
  observed published result. Mark the phases complete, validate local links
  and release metadata, and confirm the publication-record diff changes no
  archive input. Commit/push the records and leave main clean and synced.
  Prior verified source checks apply to identical executable/test inputs;
  inspect the resulting CI without repeating unchanged local suites.

Phase 2 result: preparation commit `dfa5d52a1c9f4a5841bacbba88e06b8eae90e824` was
committed/pushed cleanly and all ten jobs in
[CI run 34233310627](https://github.com/kserrec/attalambda/actions/runs/34233310627)
passed. The downloaded source-job log independently confirms 45 files and
17,065 assertions, 39-module purity, and complete boundaries
(`/tmp/attalambda-060-ci-tests.log`).

The existing full Racket CS 9.3 builder produced the final clean archive in
`/tmp/attalambda-0.6.0-dfa5d52-release/`. Its digest is
`c3d9ea5263f7ab09e5f9b8d3260b8ead1335d8f1a052c7aba11edd4bf020bb4f`; size is 14,159,078 bytes. The
103-byte SHA256SUMS digest is
`5380ea26bf9bb906d70ac8f1b52301b763dfeb93a3ed737810cfe13f6093f3f6`. The original archive and a fresh
unauthenticated public copy each passed the complete isolated Linux consumer,
including 31 existing API checks and 13 printing checks, guide, file/TCP/HTTP,
process statuses, and relocation. Logs: `/tmp/attalambda-060-build.log`,
`/tmp/attalambda-060-consumer.log`, and `/tmp/attalambda-060-public-consumer.log`.
The public-download preflight initially observed local mode 0664; setting those
two session-owned files to the consumer's required 0644 allowed verification
without changing downloaded bytes or the consumer.

Annotated tag `v0.6.0` (object `af80443d34027d3c9c414c0506213da23f57c2a1`)
peels to the exact build commit. Release `384776276` contains only
the archive (asset `550607281`) and checksum manifest (asset `550607275`).
GitHub's digests and draft downloads matched both originals before publication.
It was published at `2026-09-08T13:59:26Z` as the latest stable release:
<https://github.com/kserrec/attalambda/releases/tag/v0.6.0>.
Fresh public downloads matched both hashes, passed the downloaded checksum
manifest, and passed the independent consumer. All four older releases and
their asset identities, descriptions, sizes, hashes, and URLs were preserved.

README, release notes, API/specification status, acceptance, release ledger,
project instructions, and handoff now describe observed publication. These
publication records change Markdown only, outside the tagged archive inputs.
The verified source and CI gates above apply to identical executable/test
inputs. All 159 local links in the nine changed Markdown files resolve; the
publication diff is limited to those nine documents, and remote release/asset
metadata matches the recorded values. The publication-record commit leaves
main clean and synced, with its workflow providing final CI verification.
No implementation, merge, or release action remains pending. Future work
requires a new instruction.

---

# Completed printing implementation (historical)

# Milestone 6 — Generic pure value rendering and printing

Status: all seven implementation phases complete and merged into main through
[PR #4](https://github.com/kserrec/attalambda/pull/4), with Kyle's explicit
merge approval. Merge commit: `e088e1fc22463c1118127badcdc066c4f8b6cef6`.
The milestone began from clean main `e8572ee`. Publication remains outside
this plan's authorization.
Kyle authorized planning and executing every pass autonomously on 2026-09-07.
The user instruction overrides the next skill's normal stop-after-one-pass rule.
Contracts: [printing specification](docs/generic-pure-printing-spec.md) and
[raw-function addendum](docs/raw-function-printing-contract.md), with the latter
controlling raw functions and unknown-tag fallback. Existing specifications,
representation invariants, closed capabilities, and recursive purity remain binding.

## Verified starting state and scope

At starting revision `e8572ee`, no `core/to-string.rkt`, `effects/print.rkt`,
or public value renderer existed. `readers/error.rkt` owned diagnostic
formatting in Racket. Its TypeMismatch
with frames prints the oldest frame with actual type, followed by newer
frames without actual type; it omits the root label in that case. Preserve
these exact diagnostics through a new pure helper. Binary division/remainder,
Char Lists, raw append/reverse, the generalized checker, and raw-fix already
exist and will be reused. `stdout` is String-only and injected once in the
language facade. The expanded purity checker rejects module-binding cycles.
The predecessor repository has no reusable pure decimal/rendering implementation.

Create pure rendering modules as `core/render-*.rkt`, facade `core/to-string.rkt`,
`effects/print.rkt`, focused tests, and the saved contracts. Modify diagnostic
name exports, the Error reader, language exports/injection, exact boundary
allowlists, API/architecture/acceptance documents, and this plan. All existing
representations, raw algorithms, general typing, runtime/codec, host protocol,
stdout, parser, recursion rules, and dependencies remain behaviorally unchanged.
No new runtime tag, reflection, raw-function guard, newline, sorting, or
serialization promise. Printable ASCII is 32–126; other String bytes use
uppercase two-digit hexadecimal escapes, including each UTF-8 byte separately.

Each Step below is independently executable in one pass. Complete Steps
serially and continue automatically. Every Phase ends with the complete suite
and both architectural gates, then one narrow commit and push to verified
origin `git@github.com:kserrec/attalambda.git`. Never continue beyond a failing
Phase gate. Diagnose failures from evidence before repairs; do not weaken tests.
Keep this milestone on its branch. This request authorizes the implementation
and a reviewable PR; AGENTS.md requires explicit approval to merge a milestone.
No version bump, tag, publication, or download-link change belongs to this plan.

## Phase 1 — Pure scalar foundation

- [x] Step 1.1 — Save contracts and this plan. Add fixed Char sequences using
  existing mechanical macro expansion; add pure binary decimal conversion by
  division/remainder ten and two-digit hex conversion. Share these algorithms
  across all renderers; Church-to-binary conversion is only for metadata.
- [x] Step 1.2 — Add raw Rat, Bool, Unit, Byte, Char and quoted/escaped String
  renderers, strict unary wrappers using make-typed-function, and diagnostic
  names. Keep scalar helpers dependency-oriented and acyclic. No facade exports yet.
- [x] Step 1.3 — Test zero, signs, exact fractions, large Rats, every Char/Byte,
  quote/backslash/control/UTF-8 escaping, wrong types, Error propagation, String
  representation, and irrelevant-payload laziness. Run the full gate; commit/push.

Phase 1 work: four new pure modules reuse the existing fixed-text macro,
binary division/remainder, and generalized checker. Scalar tests pass 1,584
assertions, covering every byte independently. The expanded purity scan
passes all 36 production modules. The three exact core inventory assertions
now require 28 instead of 24 modules; their rejection rules are unchanged.
Focused acceptance/purity verification passed 173 assertions. Initial checks
caught and corrected one missing parenthesis and a test-only broad import
that shadowed Racket `if`; neither required a change to an existing algorithm.
Full gate: all 42 files passed 15798 assertions, expanded purity passed 36
modules, and the complete boundary inventory passed. Evidence combines
`/tmp/attalambda-printing-phase-1.log` (16 passing files) with
`/tmp/attalambda-printing-phase-1-resumed.log` (26 passing files). The initial
language suite hit the existing ASCII fixture's unchanged 20-second deadline.
Three isolated runs of that exact probe then passed in 17.8, 16.5 and 14.8
seconds without any code/deadline change; the complete language suite passed
on resumption. This is recorded timing variability, not a claimed code fix.
The scalar unit's imports, algorithms and wrapper aliases pass the final gate.
No runtime, effects, codec, macro or language-facade implementation changed.

Saved contract SHA-256 values: printing
`125120685fc1d2df8161f53fd152ac9f43c2bd9fd5784400bb42dcdbd4bc9291`;
raw-function addendum
`2f89c6672905c06dd53344008bac9a101990a88f44ced4f56907de30db1597cf`.

## Phase 2 — Pure Error diagnostics

- [x] Step 2.1 — Implement raw-error-diagnostic-string and error-to-string.
  Preserve all existing kind/type names, numeric fallbacks, argument positions,
  oldest-first frame order, result frames and the framed TypeMismatch policy.
  Explicitly consume Error as data; other tagged types produce TypeMismatch.
- [x] Step 2.2 — Make readers/error.rkt only decode the pure diagnostic String.
  Tighten its boundary to forbid an independent formatting policy. Test all core
  kinds, host/HTTP and unknown fallback kinds, unknown types, root-only/single/
  multiple/result frames, wrong input, and unused-details laziness. Run the full
  gate including existing runner diagnostics; commit/push.

Phase 2 focused evidence: 186 new Error-rendering assertions and all 308
existing Error-reader assertions passed. They cover every assigned core kind,
all host/HTTP fallback kinds, unknown kind/type identifiers, multi-digit
metadata, root-only and ordered frames, result-frame laziness, deliberate
Error consumption and wrong-type diagnostics. The narrowed observer bridge
admits no independent formatting policy; all 133 boundary tests pass,
including a mutation introducing native formatting into that bridge.
The core inventory now requires 29 modules. Phase 1 was committed and pushed
as `7758f83`. Phase 2 full gate passed all 43 files and 15987 assertions, 37-module
expanded purity, and the complete boundary inventory. Logs are
`/tmp/attalambda-printing-phase-2.log` and the ten-file continuation
`/tmp/attalambda-printing-phase-2-resumed.log`. The first run reached stdout
before encountering stale compiled dependency metadata from the old reader.
The identical stdout tests passed with compiled loading disabled and then
passed all 24 assertions normally after `raco make`; no source repair or
weakened assertion was needed. Remaining artifacts were refreshed before
resuming. Refresh classified test artifacts before subsequent full gates
when changing the dependency graph; never commit generated Racket files.
Executable changes are pure Error formatting, its strict consuming wrapper,
the one-way reader bridge, and the stricter reader boundary. Tests add Error
cases and a native-formatter rejection mutation, and update the exact source
inventory. Architecture and plan text describe the verified implementation.

## Phase 3 — One recursive renderer

- [x] Step 3.1 — Add List, Option, Result and Map helpers taking the recursive
  renderer explicitly. Build one raw-fix engine for all eleven tags. Preserve
  Map traversal order, ignore Map equality and NONE payload, render Err through
  Error formatting, and add decimal unknown-tag fallback without inspecting payload.
- [x] Step 3.2 — Add strict per-container wrappers and complete core/to-string.rkt.
  Test all eleven generic cases, heterogeneous and deeply nested containers,
  empty forms, Errors as nested data, wrong types, propagated Errors, and lazy
  unused payloads. Never probe arbitrary raw functions as supported values.
  Run the full gate; commit/push.

Phase 3 implementation uses one `core/render-value.rkt` module with explicit
recursive arguments for container helpers and one fixed-point value engine.
Lists and Maps share only the ordinary comma-joining traversal. NONE never
reads its payload; Map rendering never touches equality; unknown well-formed
tags never read their payload. The expanded purity checker passes 38 modules,
including the new acyclic engine. Error Phase 2 was committed/pushed as
`9849156`. Phase 3 focused rendering passes 1,650 assertions, including all eleven
tags, nested Maps, heterogeneous Lists, 72 alternating container levels,
wrong-type and propagated Errors, empty forms, stored Map order, and poisoned
unused payload/equality fields. Full verification passed all 43 files and
16054 assertions in one run, plus 38-module expanded purity and the complete
boundary inventory. Log: `/tmp/attalambda-printing-phase-3.log`.
The sole new module is the recursive value engine; existing scalar/Error
algorithms and all runtime/effect/frontend behavior remain unchanged. Tests
extend the rendering matrix and exact core inventory; this plan records scope.

## Phase 4 — Public pure API

- [x] Step 4.1 — Export exactly the eleven lowercase per-type renderers and
  value-to-string through the language facade. Pin corresponding exact boundary
  imports/exports; preserve private raw helpers and the current public surface.
- [x] Step 4.2 — Execute source-language acceptance for every renderer, String
  result typing, recursive dispatch, wrong inputs and no effects. Check aliases,
  hygiene, private helper isolation and existing language behavior. Run the full
  gate; commit/push.

Phase 4 exports exactly twelve canonical pure renderers through selected
facade imports and the pinned public surface. No runtime binding, injection,
syntax rule or core algorithm changes. The new installed-language tests
exercise all eleven per-type renderers, generic dispatch, exact String return
contracts, incoming/wrong Errors, lack of effects, aliasing, lexical hygiene,
and rejected private/uppercase names. The first combined 43-check fixture
exceeded 20 seconds; an isolated probe measured 33.0 seconds compiling and
2.0 seconds executing, with all 43 checks passing. Those identical checks
are now grouped into one program per renderer under the unchanged deadline;
no production repair or assertion removal is involved. The boundary checker
passes the precise new imports/exports. Phase 3 was pushed as `7fb056f`.
Phase 4 focused verification passes all 69 harness assertions and all 43
embedded language contract checks under the unchanged deadlines. Full verification passed all 44 files with 16123 assertions in one run,
38-module expanded purity and the complete boundary inventory. Evidence:
`/tmp/attalambda-printing-phase-4.log`. Executable changes are only selected
pure imports/public exports and the exact facade allowlists; the new test
file covers installed source programs. This plan records the verification.

## Phase 5 — Print through existing stdout

- [x] Step 5.1 — Add a unary composition factory taking the already-created
  stdout function, never host. Inject print from stdout in the facade and pin
  that exact wiring. Add print's normal diagnostic name without wrapping Error
  inputs in general propagation before rendering.
- [x] Step 5.2 — Test one String-only stdout delegation, identical success/
  failure returns, no implicit newline, no call before application, and real
  source output for scalars, nested containers, and Errors. Verify stdout remains
  byte-exact and String-only. Run the full structural/test gate; commit/push.

Phase 5 adds only a unary composition factory receiving the already-injected
stdout. The facade's private `language-print` binding captures that stdout and
is renamed only on export. Native Racket print remains forbidden in every
other class; in the facade the exact export is its sole permitted occurrence,
with native calls and generated/native syntax-data uses rejected by mutation
checks. The exact import and injection definitions remain pinned. No host,
codec, protocol or stdout source changes. Composition tests cover String-only
requests, no newline, no premature call/repeated effect, and identity-preserved
success/Err/Error results. The effect inventory increases from eight to nine.
Phase 4 was pushed as `34097b4`. Phase 5 focused verification passed 94 installed-language assertions, 22
composition/protocol assertions and all 136 boundary assertions. Full gate:
all 45 test files, 16174 assertions, 39-module expanded purity and complete
boundary inventory passed in one run. Log: `/tmp/attalambda-printing-phase-5.log`.
Executable changes are the pure composition and exact facade wiring/export
checks. Tests add print behavior and native-printer rejection, and update the
explicit effects inventory. No runtime, codec, host protocol, stdout source,
new runtime tag, macro primitive or recursive-purity exception was added.

## Phase 6 — Explicit purity and contract audit

- [x] Step 6.1 — Trace every new production path through expanded unary lambda
  terms. Verify no runtime/readers/effects import enters rendering, no new host
  capability or primitive, no module recursion cycle, and no tag/codec change.
  Add meaningful isolated mutation coverage for printing boundaries and Error
  reader policy. Review all implemented contract cases and repair proven issues.
- [x] Step 6.2 — Run the complete suite and architectural gates, record exact
  counts and limits, compare the milestone diff with scope, commit/push.

Phase 6 review found no production defect. All six rendering modules depend
only on permitted pure modules and existing mechanical macros. One fixed-point
value engine supplies recursive arguments to container helpers. The unchanged
expanded checker passes all 39 production modules, including cycle detection;
the complete boundary inventory passes. A baseline diff confirms no changes to
tags, representations, generalized typing, numeric algorithms, runtime/codec,
host/protocol, stdout, or macro implementation. Existing boundary mutations
reject native print and an independent Error-reader formatting policy; a new
mutation also rejects injecting the host into print instead of stdout.
Independent codec validation now checks canonical String results throughout
the scalar/container/Error matrix, used only from tests. All 2,862 focused
rendering/Error/boundary assertions pass. Raw functions remain outside the
contract, and no safety guarantee or probe for them was introduced.
Phase 6 full gate passed all 45 files and 17,064 assertions, 39-module
expanded purity, and the complete boundary inventory. The run was interrupted
by continuation turns, each recorded as a user break rather than an assertion
failure. The unchanged source was resumed at the interrupted file; completed
files were not rerun. Evidence is `/tmp/attalambda-printing-phase-6.log` and
its `-resumed`, `-resumed-2`, and `-resumed-3` logs (12 + 12 + 5 + 16 files).
The phase changes tests and this record only; no executable production or
checker implementation changed. Phase 5 was committed/pushed as `d905f61`.

## Phase 7 — Documentation and reviewable completion

- [x] Step 7.1 — Document each renderer, recursive containers, raw-function
  unspecified behavior, unknown well-formed tags, exact escapes, diagnostic
  compatibility, stdout versus print, no newline, and display-only Map ordering.
  Update architecture, specification index and acceptance only for this feature;
  append scoped amendments incorporating the supplied contracts into the three
  canonical specifications and update their hashes. Refresh current README and
  handoff pointers without changing historical release evidence;
  distinguish branch implementation from published 0.5.0.
- [x] Step 7.2 — Execute documented examples, verify local links and all tests/
  boundaries, record executable/test/doc changes separately, commit/push, and
  create a reviewable PR with the final scope and verification. Inspect its CI;
  resolve concrete in-scope findings and leave the branch clean. End with all
  authorized implementation passes complete; merge/publication require later
  explicit approval and are not unfinished implementation Steps.

Phase 7 documentation now covers all thirteen new public callables, exact
display/byte rules, recursive containers, consuming Error behavior, existing
diagnostic compatibility, unsupported raw functions, and the stdout distinction.
Architecture describes the verified dependency and injection path. Three scoped
canonical amendments incorporate the supplied contracts without changing any
preceding byte; the index records all new and previous hashes. README and
handoff distinguish this branch from published 0.5.0. The API's complete
public-only example was extracted verbatim and passed six isolated-install
assertions with exact bytes and no trailing newline. All 185 local links in
the ten modified Markdown files and all five contract hashes passed validation.
Phase 6 was committed/pushed as `eb9a6d7`. This phase changes documentation
only; executable production, checker and test sources remain unchanged.
The final Phase 7 local gate passed all 45 test files and 17,064 assertions
in one run, 39-module expanded purity, and the complete boundary inventory.
Evidence: `/tmp/attalambda-printing-phase-7.log`. The documented program's
six checks also passed independently. All local implementation and documentation
work is verified. Documentation was committed/pushed as `a9ae2f6`, and
[PR #4](https://github.com/kserrec/attalambda/pull/4) was opened against main.
[CI run 34181311603](https://github.com/kserrec/attalambda/actions/runs/34181311603)
passed all ten jobs for `a9ae2f6032377f97d91773b449e0618b60773707`: source tests,
Linux distribution, both macOS architectures and Windows build/consumer checks,
and temporary-artifact cleanup. Its Racket CS 9.3 source job passed the same
45 files, 17,064 assertions, 39-module purity, and complete boundary inventory.
Evidence: `/tmp/attalambda-printing-ci-a9ae2f6.log`. Final review/comment
inspection found no posted findings. This closure record changes documentation
only; no executable or test file differs from that verified head. All authorized
implementation passes are complete. The PR is the review and live CI entry point;
merge required Kyle's separate explicit approval under AGENTS.md, recorded below.

## Approved merge

Kyle explicitly approved merging PR #4 on 2026-09-07. GitHub merged the
verified head `c3d61fd7a3baf75ba1e44f9fb27457ef67bc1ca6` into main at
`2026-09-08T03:33:50Z`, creating `e088e1fc22463c1118127badcdc066c4f8b6cef6`.
The merge tree exactly equals the approved PR tree (`34f5e863bb7c4b4b17579b42a7743b5b0230fb94`).
All ten jobs in [the final PR CI run](https://github.com/kserrec/attalambda/actions/runs/34182567747)
passed at that head, including 45 source suites, 17,064 assertions, 39-module
expanded purity, and the complete boundary inventory. No review findings were
posted when the merge was approved. Local main was fast-forwarded to the merge.
The follow-up commit updates only merge/status documentation; executable,
test, and checker code remains the verified PR tree. Main's workflow supplies
post-merge verification. No version, tag, download metadata, or release changed.

### Post-merge CI job allowance

All ten jobs passed for merge commit `e088e1f` in
[run 34183948133](https://github.com/kserrec/attalambda/actions/runs/34183948133).
The source job took 18 minutes 22 seconds. The documentation-only follow-up
`b59f8f5` passed all 45 test files and 17,064 assertions in
[run 34184114154](https://github.com/kserrec/attalambda/actions/runs/34184114154),
then GitHub cancelled the job during its final structural checks. Its annotation
explicitly reports exceeding the 20-minute maximum; the log contains no test
failure. The other nine jobs passed. This proves an overall job-budget limit,
with the identical executable/test tree already passing on the merge commit.
The follow-up raises only `jobs.test.timeout-minutes` from 20 to 30 and refreshes
its explanatory comment. Parsed YAML comparison proves this is the only
workflow setting changed. Individual test deadlines, assertions, purity/boundary
checks, and all other job limits remain unchanged.

The pre-commit local gate passed 16 files and 7,503 assertions, then its
representation fixture exceeded the existing 20-second deadline before output.
Three exact isolated repetitions also timed out. Loading the repository Error
reader alone took 28,272 ms. Rebuilding that reader did not refresh its core
dependencies and did not reduce loading time. A loader trace proved that five
core modules were being loaded from source because their generated artifacts
predated the merge; function names and fixed rendering text dominated the delay.
Explicitly rebuilding those five existing modules reduced reader loading to
64 ms. The unchanged fixture then passed all three isolated repetitions
(2,611, 2,676 and 2,664 ms; 18 assertions). No tracked source or test change was
made for this local build-artifact issue. Evidence is in
`/tmp/attalambda-reader-load-trace.log` and
`/tmp/attalambda-representation-deadline-probe-after-dependencies.log`.
The resumed language suite passed all 193 assertions. The purity suite needed
its existing `/var/tmp` fixture permission outside the sandbox and then passed
all 155 assertions. The complete gate passed 45 files and 17,064 assertions,
39-module expanded purity, and the full boundary inventory. Logs are
`/tmp/attalambda-merge-ci-allowance.log` (16 completed files), its `-resumed`
log (14 completed files before the sandbox exception),
`/tmp/attalambda-merge-purity-test.log` (1 file), and the allowance `-final`
log (14 files and both structural checks). Failed partial attempts are retained
as diagnostic evidence and excluded from the passing totals. The resulting
main workflow supplies final CI verification for this workflow-only adjustment;
no executable production, test, checker, or dependency file changed.

---

# Completed plans (historical; no further authority)

# Milestone 5 — Pure recursive definitions (target 0.5.0)

Status: complete on main. PR #3 merged and 0.5.0 is published and verified.
Kyle authorized starting this work on 2026-09-07 after choosing 0.5.0 for
the new public syntax and the migration away from recursive `def`.
Kyle's subsequent "keep going" followed the explicit merge/build/verify/
publish steps and authorized completing this release on 2026-09-07.
Starting revision: clean `0987c8a` on main, following the published 0.4.0.
Source: [supplied recursion specification](docs/recursive-purity-spec.md),
SHA-256 `108e4b13b73350d1cfb959752fc29f55f0fbe7951e268d276585a818856278f5`.

## Scope and verified starting state at `0987c8a`

`macros/macros.rkt` expands `def` into host `define` and unary lambdas.
`lang/expander.rkt` recognizes only `def` as a definition and performs no
dependency-cycle validation. `tooling/check-purity.rkt` accepts same-module
references but does not check their dependency graph. `core/fix.rkt` already
contains the canonical lambda-only fixed-point term. Public `rec` is absent.
Two language fixtures and `examples/http-server.attl` use recursive `def`.
The runner currently replaces general syntax exceptions with a generic
diagnostic; recursion failures need a narrowly selected safe explanation.

Modify the expander, purity and boundary checks, focused tests, runner syntax
diagnostics, the HTTP example's definition keyword, API and purity docs.
Create the saved source specification and this active plan. Preserve core
algorithms (including `raw-fix`), the macro layer, representations, typing,
laziness, all ten host capabilities, and Linux-only binary support. Do not
add dependencies or public fixed-point functions. No mutual-recursion sugar.

The supplied specification's six stages are retained in order as Steps in
one implementation Phase: they cannot independently satisfy its requirement
that every completed Phase pass all tests. In particular the new syntax,
pinned boundary rules, and existing recursive fixtures must land together.
Each Phase below is one complete implementation/verification pass.

## Phase 1 — Implement and verify pure recursion

- [x] Step 1.1 — Add rejection tests for direct/indirect recursive `def`
  and expanded module bindings. Observe the failures before enforcement.
- [x] Step 1.2 — Privately reuse `raw-fix`, implement public `rec` with
  unary currying, and recognize it as a top-level definition. Test execution,
  zero/multiple arguments, partial application, and laziness.
- [x] Step 1.3 — Reject top-level dependency cycles at expansion, treating
  `rec` self references and `def`/`rec` arguments, `lambda`, and `let` names
  as lexical. Preserve acyclic forward references and actual shadowing.
  Cover `rec`/`def` cycles and non-call references. Give direct and indirect
  cycles clear diagnostics, including through the public runner.
- [x] Step 1.4 — Check expanded same-module phase-0 dependencies by binding
  identity. Reject deterministic cycles while retaining lexical recursion,
  imported references, and acyclic definitions. Scan real core/effects.
- [x] Step 1.5 — Pin only the exact new expander import/export/helpers and
  vocabulary; test private-name isolation and retained prohibitions. Convert
  the two divergent fixtures and only the HTTP formatter's `def` keyword.
  Update API docs and add the absolute-purity amendment.
- [x] Step 1.6 — Run focused tests, then the complete suite and both
  architectural checks. Obtain the fresh-agent cold review required for
  fixes, address proven findings, record results, commit and push this Phase.

Steps 1.1–1.5 evidence: before enforcement, all six new public recursive-def
fixtures expanded successfully, and all five checker-level recursive
fixtures returned no violations (5/147 assertions failed as expected).
The baseline language run additionally hit the existing representation
probe's 20-second deadline while other work was running; no deadline or
production algorithm was changed. Its subsequent isolated run passed.

Focused verification after implementation passed 148 purity assertions,
130 boundary assertions, and 401 language/runner assertions. A fresh-agent
cold review found one additional acyclic-source regression: calls to user
bindings named `def` or `rec` were being parsed as declarations. Declaration
collection now follows source order, and the wrapper uses that same result.
Four execution cases protect this class, including private macro hygiene.
The reviewer confirmed the final correction with isolated probes and found
no remaining concrete issue. Full-suite verification below includes these
four additional cases. Logs are `/tmp/attalambda-recursion-purity.log`,
`/tmp/attalambda-recursion-boundary-tests.log`, and
`/tmp/attalambda-recursion-public-tests.log`.

Full-suite attempt: acceptance passed 21 assertions and binary Nat passed
2,168, then a boundary mutation fixture could not locate the helper because
it still expected the old one-argument signature. Updated that exact fixture
to `(language-definition-form? form bound)`; focused boundary verification
again passed all 130 assertions. The cold reviewer confirmed its native-exit
prohibition remains intact. No production code changed after those first two
full-suite files passed. The initial log is
`/tmp/attalambda-recursion-full-tests.log`.

Step 1.6 completion: Kyle explicitly approved continuing verification,
commit, and push after correcting an execution-tool rejection that did not
come from him. The remaining 39 files passed, including all 193 public
language assertions, launcher diagnostics, and the real HTTP example on an
ephemeral loopback port. Together with the unchanged first two files, all
41 test files passed 14,209 assertions. The passing-file inventory exactly
matches repository discovery. Final expanded purity passed all 32 production
modules; the complete structural boundary/source inventory check passed.
Continuation log: `/tmp/attalambda-recursion-remaining-tests.log`.
Per-file counts: `/tmp/attalambda-recursion-verification.json`.

Executable changes are confined to the language expander, runner syntax
diagnostics, purity/boundary checkers, and the HTTP example's definition
keyword. Four test files add regression coverage and update the existing
boundary mutation fixture. Documentation updates cover the API, purity
amendment, saved verbatim specification, plan, and handoff. Core, effects,
runtime, and macro files have no diff. No dependency or host capability was
added. Version metadata and release downloads still identify 0.4.0; Phase 2
owns preparation of the chosen 0.5.0 release. Final whitespace checks pass.

## Phase 2 — Prepare 0.5.0 for release review

- [x] Step 2.1 — Add exactly the 0.5.0 product / 0.5 package version state
  to metadata, exact runner/boundary/build/consumer validation and tests.
- [x] Step 2.2 — Prepare migration/release notes distinguishing the purity
  repair from the new `rec` syntax and breaking recursive-`def` rule.
  Run focused and full verification; commit and push the preparation.
- [x] Step 2.3 — Prepare the reviewable PR and report its verified revision.
  Merge to main requires Kyle's explicit approval under AGENTS.md. Release build and
  publication follow the existing Linux release process after approval of
  the concrete reviewed release; do not reuse the historical 0.4.0 authority.

Step 2.1 result: VERSION is 0.5.0 and info.rkt projects it to 0.5. The runner,
boundary checker, all three builders, and the macOS/Windows consumers accept
exactly that additional state while preserving their historical states. The
Linux consumer derives its version from VERSION. Current-version fixtures
were updated; the boundary suite additionally exercises the new projection.

Release preparation also found an embedded recursive `def` in the Linux
consumer's public-API fixture. Running the exact extracted program failed at
expansion with status 65 and the expected recursive-def diagnostic. Changed
that declaration to `rec` and added an executed two-argument recursive
countdown, partially applied, to the consumer's existing output assertions.
The resulting program passes all 31 checks through the source launcher.

Migration notes are in `docs/releases/0.5.0.md` and the packaged getting-started
guide. The specification index now describes the recursion amendment and
records its actual hash; no normative specification changed in this Phase.
README download links still refer to the published 0.4.0 archive.

Focused verification: `TMPDIR=/tmp raco test tests/boundary-check-test.rkt
tests/distribution-test.rkt tests/runner-test.rkt` passed 564 assertions.
The extracted Linux consumer program and complete release-note factorial
example both produced exact expected output; the CLI prints exactly
`AttaLambda 0.5.0` with one LF. Logs are `/tmp/attalambda-050-focused.log`
and `/tmp/attalambda-050-probes.json`. Complete verification with
`TMPDIR=/tmp ./run-all-tests.sh` passed all 41 test files, 14,210 assertions,
32-module expanded purity, and complete structural boundaries/source
inventory. The passing-file list exactly matches repository test discovery.
Evidence: `/tmp/attalambda-050-full.log` and per-file counts in
`/tmp/attalambda-050-verification.json`. All 129 local links in the changed
reference documents resolve; final whitespace checks pass.

Phase 2 executable changes are only the exact version metadata/allowlists.
Test changes update current-version assertions, exercise the new package
projection, and migrate/extend the Linux consumer's recursion fixture.
Documentation adds migration/release notes and synchronizes source versus
published-release descriptions, the specification index, plan, and handoff.
Core, effects, runtime, macros, expander, and canonical examples have no
additional diff from the verified Phase 1 commit `c7c729f`.

The reviewable PR uses `milestone-5-recursive-purity` as head and `main` as
base; its description covers both Phases and the above verification. Use
`gh pr view milestone-5-recursive-purity` for its URL, exact head, and live CI
status. The Phase 2 commit closes the prepared source changes; CI and review
results are recorded by GitHub rather than inferred from local tests.
Next action: evaluate the PR's CI/reviews, then obtain explicit approval
before merging and following the existing Linux release process. This Phase
does not create a release tag or publish downloadable assets.

## Phase 3 — Review, merge, publish, and verify 0.5.0

- [x] Step 3.1 — Evaluate the completed automated review and wait for all
  checks on the final PR revision. Record concrete evidence for accepting or
  rejecting each finding; make no speculative code change.
- [x] Step 3.2 — Merge the authorized PR with a merge commit, fast-forward
  local main, verify equality with the reviewed tree, and check post-merge CI.
- [x] Step 3.3 — Build from clean merged main with the existing Racket CS 9.3
  Linux builder; run the isolated consumer. Stage the exact archive and
  checksum, create the annotated tag, publish, and verify fresh public bytes.
- [x] Step 3.4 — Update current download links, API/release status, acceptance,
  ledger, project instructions, and handoff. Verify the documentation and
  unchanged build inputs, commit/push this publication record, and leave main
  clean. This completed milestone does not authorize another release.

Review result: all ten jobs passed on PR head
`39fa142800c7bfc33e407fb93718960f91fe90d9` in
https://github.com/kserrec/attalambda/actions/runs/34156900771.
The one automated P2 suggestion claimed that later module definitions named
`lambda` or `let` must not affect earlier definition bodies. Exact probes
disproved that premise on source Racket 8.10 and packaged Racket CS 9.3:
the forms succeed without the later shadow; with it, even renaming the outer
function to remove the alleged self edge still fails during ordinary
expansion. A valid forward-call control with `(def identity = (let value =
1 value))`, later `(def let a b c d = a)`, `(def = = 0)`, and `(def value = 7)`
evaluates identity to 7 through the later ordinary function. Lexical `let`
would produce 1. Declaration recognition is source-ordered; definition-body
bindings are module-wide. The existing scanner reflects that distinction.
No production fix or regression-test change was justified. The assessment is
in the PR description; review thread `PRRT_kwDOUC8y9s6gBBBI` is resolved.
Evidence: `/tmp/attalambda-050-shadow-before.json`,
`/tmp/attalambda-050-shadow-scope.json`, and
`/tmp/attalambda-050-native-shadow.json`.

PR #3 merged at `2026-09-07T20:04:33Z` as
`d770b8335a06a8ec6e5925030c4a92cde88e85d8`. Local main was fast-forwarded;
its tree `28f5161e211c4cb2c32816c8fe28b640098b22ef` equals the reviewed head's
tree. All ten post-merge jobs passed in
https://github.com/kserrec/attalambda/actions/runs/34158001491.
The downloaded source-job log independently confirms all 41 files and 14,210
assertions, 32-module purity, and complete boundaries:
`/tmp/attalambda-0.5.0-merged-ci-tests.log`.

The exact merged commit built cleanly with the cached Racket CS 9.3 image.
The local container requires a read-only `/usr/bin/git` mount and runs as
UID/GID 1000:1000 to write its user-owned output directory with capabilities
dropped. Those environment requirements were diagnosed without code edits.
The final archive and 103-byte checksum manifest are in
`/tmp/attalambda-0.5.0-release/`. The archive is 14,027,976 bytes with SHA-256
`9d87027d3fcad80c58668ce2d1d31365bba507131bc67889118e3d2ae7af36c4`.
The isolated consumer passed all 31 public-API checks, including `rec` and
partial application, plus guide, file/TCP/HTTP, process-status, and relocation
checks. Logs: `/tmp/attalambda-0.5.0-build.log` and
`/tmp/attalambda-0.5.0-consumer.log`. The earlier reviewed-head archive in
`/tmp/attalambda-050-review-39fa142/` remains an unpublished probe artifact.

Unsigned annotated tag `v0.5.0` (object
`718078c3b8f7c68e165ddab0e157f0765234d5ff`) points to the merged build commit.
Release `384296811` was staged with exactly the archive (asset `549317035`)
and checksum manifest (asset `549317036`). GitHub's digests and authenticated
draft downloads matched both local files. Published at
`2026-09-07T20:21:07Z` as the latest stable release:
https://github.com/kserrec/attalambda/releases/tag/v0.5.0.
Fresh unauthenticated downloads in `/tmp/attalambda-0.5.0-public-download/`
matched both local hashes and passed `sha256sum -c SHA256SUMS`. Older release
assets were preserved. Exact asset hashes, sizes, and provenance are in
`docs/design/standalone-distribution.md`.

The publication-record diff changes documentation only. No executable,
test, version, bundled-guide, legal, or other archive input changed after the
verified build. Its source/architecture verification is the completed local
and post-merge full suite above; documentation links, published metadata,
asset preservation, and final whitespace/source-diff checks were also verified.

---

# Release 0.4.0 (complete; historical)

Status: complete on main. PR #2 merged and 0.4.0 published and verified.
Kyle explicitly authorized the PR, evaluation of useful actionable review
comments, merge, and release on 2026-09-06. This authorization supersedes the
completed implementation plan's stop conditions below. Preparation started at
clean `65b875cfef5bdc12adc236af158c563a7004cb82`; the public release at that point
was 0.3.0 with only its Linux x86-64 archive and checksum manifest.

Release scope: 0.4.0 packages the completed public API/List changes and the
already merged HTTP/exit/refactor work since 0.3.0. Add exactly the approved
`0.4.0` → `0.4` version projection to the existing runner, boundary, native
build, and consumer checks. Preserve historical version states. Modify only
version metadata, corresponding tests/tables, release documentation, and any
review finding verified against the specification. No new language feature,
dependency, host capability, publishing framework, or binary support target.

## Phase 1 — PR and release preparation

### Step 1.1 — Open the verified implementation for review

- [x] Open the PR from the completed feature branch to main with scope and
  actual verification evidence. PR: https://github.com/kserrec/attalambda/pull/2.
  Automated code review and existing CI started on `65b875c`.

### Step 1.2 — Prepare the explicit version state

- [x] Set VERSION to `0.4.0` and the Racket package projection to `0.4`;
  extend the existing exact validation tables and native consumer filename
  checks. Update the version contract and affected tests without widening
  accepted future versions. Keep current publication claims factual until
  publication, and prepare migration/release notes. Run focused checks and
  the full suite, then commit and push the preparation to the same PR.

Step 1.2 result: added only the explicit 0.4.0 state to existing version
tables/regular expressions across runner, boundary, builders, and native
consumers. Historical states remain accepted; no future/pre-release version
was added. Updated the existing version-projection test and runner fixture
expectations. Focused tests passed 543 assertions; the full suite passed all
41 files, 14,100 assertions, 32-module expanded purity, and complete boundaries.
Shell syntax and the full relevant diff/whitespace checks passed. Draft release
notes are at `/tmp/attalambda-0.4.0-release-notes.md`; the full log is
`/tmp/attalambda-0.4.0-preparation-tests.log`. No object-language computation,
dependency, representation, effect, or publication-support claim changed.

## Phase 2 — Evaluate review and merge

### Step 2.1 — Resolve useful findings and verify the PR

- [x] Read completed reviews and inline/discussion comments. Accept only
  findings supported by the code, behavior, and canonical specification;
  diagnose before fixing and test any repair. Wait for the final PR revision's
  existing CI jobs to pass. Record the review result and actual tested revision.

Review observed (2026-09-06): the repository's automated Codex review of
`65b875c` completed at 17:12:36 UTC with a thumbs-up. Both paginated review
comment/submission endpoints and the unresolved-thread inventory contained
no findings. No repair is justified by that review. The later version-only
delta was reviewed locally and passed its own full suite. Final PR revision
`d6f50eec467062a0d33ce0697229f0b691735a06` passed all ten jobs in
https://github.com/kserrec/attalambda/actions/runs/34048807658. A final check of
comments and submitted reviews still found no actionable issue.

### Step 2.2 — Merge the verified revision

- [x] Merge with a merge commit, preserving the separate implementation
  phases. Update local main without overwriting local work and verify the
  resulting commit/checks. Kyle's instruction already authorizes this merge.

Step 2.2 result: PR #2 merged at 17:45:00 UTC as
`bd1dd56925765f8d8359609a49e333ba570bcfc6`. Local main was fast-forwarded and
verified clean. Its tree `ae8eddd8d437a1bd88f2581b583612b99a106241` exactly
matches the final CI-verified PR tree. Post-merge CI is tracked separately in
https://github.com/kserrec/attalambda/actions/runs/34049568221; all ten jobs
passed before publication.

## Phase 3 — Publish and verify 0.4.0

### Step 3.1 — Build and test the exact release inputs

- [x] From clean merged main, use the existing Racket CS 9.3 Linux builder
  and isolated Ubuntu consumer. Record source commit, archive/checksum names,
  exact SHA-256 and sizes, and passing consumer evidence. Stage release notes
  describing the breaking spellings/Char migration, complete List library,
  HTTP/exit changes, and unchanged Linux-only support.

Step 3.1 result: the exact merged commit built cleanly with cached full
Racket CS 9.3. The isolated Ubuntu consumer passed all 30 public-API markers,
guide, file/TCP/HTTP, exit-status, and relocation checks. Archive
`/tmp/attalambda-0.4.0-release/attalambda-0.4.0-linux-x86_64.tar.gz` is
14,016,817 bytes, SHA-256
`29728792d17843c7c09faf5f9be0cb4b215e13a43113a7b65d83d909dd37ac8b`.
Sibling `SHA256SUMS` is 103 bytes, SHA-256
`4bf58df3b8ea6e5c9fc36b1227d7065283925aedcc744fe6cf40f7269bfc19dd`.
The build/consumer logs are `/tmp/attalambda-0.4.0-build.log` and
`/tmp/attalambda-0.4.0-consumer.log`.

### Step 3.2 — Publish the authorized release and verify public bytes

- [x] Create annotated tag `v0.4.0` at the tested clean build commit. Publish
  a GitHub release with only `attalambda-0.4.0-linux-x86_64.tar.gz` and
  `SHA256SUMS`, after checking the staged assets. Preserve older releases.
  Download the public assets afresh, compare hashes, and verify release/tag
  metadata. Update current download links, acceptance/release ledger, and
  handoff to the observed published state; commit/push the documentation and
  leave main clean. No additional publication approval is needed for this
  explicitly requested release within the established support boundary.

Staging result: annotated tag `v0.4.0` (tag object
`baba89b99fafbc5109af1b5dc23f5f1df90ed591`) points to the exact merged/build
commit. GitHub draft release ID `383668323` contains only the archive (asset
`547488679`) and checksum manifest (asset `547488678`). GitHub's asset digests
and fresh authenticated draft downloads match both local hashes exactly.
Published at 18:00:46 UTC as the latest stable release:
https://github.com/kserrec/attalambda/releases/tag/v0.4.0. Fresh unauthenticated
downloads in `/tmp/attalambda-0.4.0-public-download/` matched both exact local
hashes, and `sha256sum -c SHA256SUMS` passed. The older releases and assets
were preserved. README/API links and status, the acceptance/release ledger,
project instructions, and handoff now describe the observed published state.

Completion changes after the tagged build are documentation only; all
production, version, builder, consumer, and shipped-example inputs remain
identical to `bd1dd56`. The final publication-record full suite passed all 41
files and 14,100 assertions, including the distribution suite's 209 checks;
32-module expanded purity and complete boundaries passed again. Its log is
`/tmp/attalambda-0.4.0-publication-record-tests.log`. Diff and whitespace checks
passed. No further release or feature work is authorized by this completed
plan.

---

# Completed Public API and List library update

Status: Phases 1–8 complete; the separately authorized release plan above
controls the subsequent PR, review, merge, and publication.
Branch: `feature/public-api-and-list-library`.
Verified starting revision: `097deb5e397617c08f736bb00e47fddb33f40e68`
on clean `main`, after merge of `refactor/non-core-simplification`.
Source: [Kyle's Public API and List Library Update](</home/serrecchia/Downloads/AttaLambda Public API and List Library Update.md>),
SHA-256 `1991b4942f6df8f2eccd94170bd1920a23abd2dbe8a15633e67ce1b2671f3428`.
Kyle's 2026-09-06 clarification controls implementation: preserve absolute
purity; make naming and Char changes mechanical; keep host-side code extremely
simple; add only the code needed for the specified behavior.

## Scope and verified starting state

This is a public spelling/literal migration plus 18 List operations. The
algorithms are small. The eight Phases follow the supplied order; each Phase
is one implementation pass with logical Steps and a complete verification
gate. They do not authorize additional language or infrastructure work.

- `lang/expander.rkt` explicitly exports the uppercase operations and named
  Chars. It already owns `language-char-expression`, which emits canonical
  lambda-built Chars for String literals. `language-datum` currently accepts
  only exact Rat and String literals; the language suite rejects `#\a`.
- String literals encode one Char per UTF-8 byte. Direct ASCII Char literals
  can reuse that emitter without changing Char, String, readers, or codec.
- `core/lists.rkt` contains `raw-append`, `raw-reverse`, `raw-map`, and
  `raw-filter`. Its `raw-fold` is a right fold. `raw-map` stores callback
  results directly; `raw-filter` expects an untagged Boolean selector.
  These are existing raw contracts, not bugs to repair.
- `core/list-nat.rkt` already implements Rat-based `len`, `take`, and `drop`
  internally. `core/typecheck.rkt`, `core/errors.rkt`, `core/option.rkt`, and
  private numeric primitives provide checking, Error frames, Option, and
  counting. `core/map.rkt` provides a small example of checking callback Bool
  results without inventing a Function or Any type.
- `core/function-names.rkt` owns the encoded diagnostic names. The boundary
  checker pins facade imports/exports; the purity checker expands production
  code. Both must continue to enforce their existing restrictions.
- No public expanded List library, direct Char-literal support, or standalone
  public API reference exists yet. Creating those is new work. This planning
  inspection is source evidence; no fresh behavioral-suite pass is claimed.

## Change boundary and simplicity requirements

Modify the existing facade, encoded function names, necessary List modules,
exact boundary allowlists, directly affected tests, official examples, current
documentation, and the three normative specifications with their hash index.
Use existing internal `typed-*` exports and ordinary `rename-out` entries for
public spelling changes. Internal raw/typed names need no global redesign.

Create only the small List modules and focused suites needed to keep higher
dependencies out of the foundational List module, plus `docs/API.md`, the
requested public reference. The intended layout is two peers,
`core/list-transform.rkt` and `core/list-search.rkt`, with matching test files;
numeric List additions extend `core/list-nat.rkt` and its existing suite.
Do not create empty modules in advance or add a forwarding facade. Respect
dependency direction: foundations must not import the new library modules.
Use the existing language-test installation/helper for public-language cases.

The following are acceptance requirements, not optional cleanup goals:

1. All object-language computation, including new validation, Error choices,
   iteration, indexing, and type-tag inspection, expands to variables, unary
   lambdas, and application. Counts use private binary Nat; public numbers
   remain canonical Rat. No host arithmetic, branching, lists, or other
   Racket values may compute or represent an object-language result.
2. Keep the generalized checker and closed tag table intact. Reuse its
   existing argument-check helper for mixed callback/value signatures, as
   current polymorphic operations do. No Function/Any tag, callback registry,
   alternate checker, dispatcher, intermediate representation, or collection
   framework. Early Errors still absorb the remaining source arguments.
3. Preserve existing raw contracts and their callers. Reuse the four named
   raw List functions where their behavior fits; add only the pure adapters
   needed for the public contracts. Keep new raw algorithms raw, and keep
   strict checks in the typed layer. Shared helpers must remove actual
   repetition among these operations, with no speculative extension points.
4. Phase 1 executable changes affect spellings and diagnostic text only. No
   operation's computation changes. It adds no runtime
   wrappers, compatibility aliases, name registry, generator, migration
   command, or export framework. Remove uppercase callable exports from
   `#lang attalambda`; implementation-only names are a separate surface.
5. Phase 2 adds a Char case to the existing datum expander and removes named
   Char exports. Use the existing reader and Char emitter. No parser,
   readtable, new runtime helper, Unicode conversion layer, or representation
   change. Host Char inspection is permitted only during mechanical expansion.
6. Non-core code stays direct: explicit imports/exports, a small literal
   check, ordinary test cases, and exact updates to existing checker tables.
   No new test runner, checker architecture, dependency, configuration,
   performance framework, or unrelated refactor. Never weaken a gate to make
   an implementation pass.

Behaviorally unchanged: existing operation results, evaluation rules, type
representations, raw algorithms, codec validation, and all ten host effects.
Only the specified public spellings/diagnostic names, new Char syntax, removed
named Char bindings, and new List functions change language behavior. Map
stays Map. Constants `TRUE`, `FALSE`, `NIL`, `UNIT`, `NONE`, `EMPTY-STRING`, and
the `HTTP-STATUS-*` values keep their names. Existing lowercase functions,
including `exit` (omitted from the proposal's example inventory), remain.
Version, published artifacts, runtime/host capabilities, and release work are
outside this change.

## Contract details to record before implementation

The specifications currently require older public spellings. Step 1.1 must
explicitly amend their precedence before any executable change; the plan
cannot override them. Record all contracts in the supplied proposal, including
these details that affect implementation and tests:

- Direct Char literals accept ASCII values 0–127, including the supplied
  letter, digit, punctuation, delimiter, space, tab, newline, and return
  examples. Reject non-ASCII literals during expansion: a Unicode character
  that occupies multiple UTF-8 bytes cannot denote one existing Char
  consistently with String literals. `make-char` retains its full 0–255
  contract, and UTF-8 String literals retain their existing behavior.
- Callbacks are supplied as pure unary/curried functions, following the
  existing Map convention. Do not inspect an arbitrary lambda as a tagged
  value or introduce a host callable test. Validate tagged callback results.
  `map` and `reduce` propagate callback Errors; predicate/equality results
  must be Bool or Error. Other tagged answers produce TypeMismatch expecting
  Bool, attributed to the public List operation. Preserve Error roots and
  frames; retain Result Err as an ordinary computational value.
- `contains?` applies the supplied equality to the sought value and current
  element in that order. Its public argument order is equality, value, List.
  `reduce` applies its curried callback to accumulator, then element.
- `nth` returns Option; `find-index` returns Option of a whole Rat. Counts
  and indices are nonnegative whole Rats. `range` accepts signed whole Rats,
  includes start, excludes end, increments by one, and returns NIL when
  start >= end. Fractional endpoints use the existing InvalidCount Error;
  a non-Rat uses TypeMismatch. No new Error kind or range overload.
- Predicate-driven operations stop exactly where specified. Never evaluate
  the suffix merely to validate callbacks that the answer does not need.
  List-producing operations must return proper Lists ending in canonical
  NIL or propagate an Error, never hide callback Errors inside an output
  List or an improper tail. Checking a later produced element can require
  traversing the finite result; make no new infinite-List productivity claim.

## Execution and verification

Read the current instructions, relevant normative sections, named modules,
and their tests before each Phase. The previous completed plans below are
history, not instructions to return to their branches or repeat their work.
Study `/home/serrecchia/Projects/all_the_lambdas/lists.rkt` and relevant typed
List code only for useful existing patterns; current AttaLambda contracts
and representations govern every choice.

Complete and record the Steps in order. Run focused behavioral tests during
work, plus both architectural checks after production edits. At every Phase
boundary run `./run-all-tests.sh` (which includes both architectural gates),
inspect the full relevant diff and `git diff --check`, and commit/push that
verified Phase to this branch. Do not repeat successful checks without a
subsequent change or unresolved failure. State executable, test/tooling, and
documentation changes separately in completion records.

For new operations, test public-language behavior as well as the pure unit
contracts. Cover normal, NIL, singleton, and heterogeneous inputs where valid;
wrong tagged arguments and incoming Errors at each applicable position;
partial application and remaining-arity absorption; canonical output tags and
NIL; exact diagnostic names and preserved Error roots; and the phase-specific
cases below. Use delayed failures/call observations and existing finite
subprocess deadlines to prove short-circuiting. Keep tests local and direct;
do not build a matrix framework or run each small case in a fresh installation.

Diagnose actual failures before changing code. Do not stack unproven fixes;
two failed hypotheses require stopping with the evidence. Surface a genuine
normative conflict instead of inventing a language decision. Routine work
inside this requested scope requires no repeated permission. Final completion
stops for Kyle's branch review; no pull request, merge, tag, or publication.
Every recursive search/listing/bulk read or diff must explicitly exclude
`.env`, `*.env`, `.env.*`, and `*.env.*`. Never inspect dotenv contents or use
Graphify. Filesystem examples use temporary directories; network examples use
ephemeral loopback ports.

## Phase 1 — Mechanical public lowercase migration

### Step 1.1 — Establish the canonical contract

- [x] Append dated amendments to all three language specifications and update
  precedence/provenance and SHA-256 values in their index. Preserve previous
  text as explicitly historical. Specify the lowercase public inventory,
  retained constants, Char rule, and all 25 final List contracts from the
  proposal, including the details above. Distinguish normative future scope
  from current implementation. No executable changes in this Step.

Step 1.1 result (2026-09-06): appended the three normative amendments and
updated their precedence/provenance index. All previous specification bytes
remain exact prefixes; recorded hashes match the amended files. This Step
changed documentation only.

### Step 1.2 — Change exports and diagnostic spellings

- [x] Mechanically map each existing uppercase callable to its lowercase
  hyphenated spelling in `lang/expander.rkt`; retain existing lowercase
  functions and constants. Update `core/function-names.rkt` so Errors report
  the same canonical public names. Update the existing boundary tables
  exactly. Resolve Racket name collisions through export renaming, without
  adding wrapper functions or changing compile-time uses of Racket bindings.

Step 1.2 result (2026-09-06): changed 63 explicit public export pairs and
63 encoded diagnostic-name literals; imports, literal expansion, module
execution, and host injection are byte-for-byte unchanged. Updated the
existing exact checker tables; corrected an introduced EMPTY-STRING ordering
mismatch. Expanded purity passed all 30 production modules and the complete
boundary/inventory gate passed. No runtime wrapper or algorithm was added.

### Step 1.3 — Migrate public examples and prove the surface

- [x] Migrate all live public-language examples, fixtures, embedded runner
  and distribution programs, guide text, and current documentation. Preserve
  historical release evidence and internal implementation names as such.
  Create `docs/API.md` with the implemented public inventory and signatures;
  link it from README and extend it as later Phases land. Public-language
  tests exercise every renamed binding and reject every retired uppercase
  callable name. Update diagnostic expectations without weakening behavioral
  assertions. Run focused language, runner, boundary, diagnostic, and affected
  unit suites, then the Phase completion gate.

Step 1.3 result (2026-09-06): migrated live public examples, embedded runner
and Linux consumer programs, and diagnostic expectations. Added installed
language cases executing all 63 renamed callables and rejecting all 63 old
names, public Error-frame observations, and 27 additional encoded-name cases
in the existing reader suite. The observation probe initially tried to import
a reader from the deliberately production-only package; corrected the test to
load the repository reader as an external observer. No packaging or production
change was needed. The corrected focused language run passed 98 assertions.

The complete `./run-all-tests.sh` run passed all 39 suites, 13,669 assertions,
expanded purity for 30 production modules, and the complete source/boundary
inventory. An earlier run stopped when the filesystem sandbox denied an
existing purity fixture's `/var/tmp` directory; the unchanged suite passed
with that filesystem permission. Future full runs need access to the system
temporary directory. Shell syntax, specification hashes and preserved
prefixes, the complete relevant diff, and whitespace checks passed.

Phase 1 executable changes: 63 export renames, 63 encoded diagnostic-name
literals, and corresponding spelling changes in official programs. Existing
algorithms, facade imports/expansion/execution, effects, runtime, macros, and
readers are unchanged. Tests/tooling: direct public API checks, diagnostic
expectations, and exact existing boundary tables; no new test framework.
Documentation: normative amendments/provenance, new `docs/API.md`, current
README/architecture/acceptance updates, and the plan/branch instructions.
No new production module, runtime wrapper, dependency, or host capability.
Phase 1 is complete; the next bounded chunk is Phase 2, Char literals.

## Phase 2 — Mechanical Char-literal migration

### Step 2.1 — Expand literals through the existing emitter

- [x] Add the small Char datum branch in `lang/expander.rkt`, with the ASCII
  check and a clear syntax error for unsupported characters. Emit through
  `language-char-expression`. Keep `lang/reader.rkt`, String expansion, and
  runtime representation intact. Update only the relevant checker vocabulary
  and language diagnostics; retain rejection of other unsupported datums.

Step 2.1 result (2026-09-06): the existing datum expander now accepts ASCII
Chars through its existing emitter. Updated the exact facade checker vocabulary
and literal diagnostics; no reader, String emitter, or runtime change.
Expanded purity passed all 30 production modules; boundary checks passed.

### Step 2.2 — Remove named public Chars and verify isolation

- [x] Remove individual Char imports/exports from the language facade and
  its exact allowlist; keep internal constants used by existing core/effects
  code. Migrate public examples/tests to literals. Test lowercase/uppercase
  letters, digits, punctuation, parentheses, all four named whitespace forms,
  ASCII boundaries, and rejected non-ASCII values. Prove literal equivalence
  to `make-char`, correct tags/canonical representation, and byte consistency
  with a one-character ASCII String. Prove `a`, `x`, `n`, `m`, and all removed
  names are unbound until defined, while ordinary user definitions work.
  Update current docs/reference; run language, runner, Char, String, codec,
  and boundary tests, then the Phase completion gate.

Step 2.2 result (2026-09-06): removed all named Char imports/exports from
only the public facade and its exact checker inventory; migrated the HTTP
example and public callable tests to literals. The installed-language suite
checks every ASCII value against make-char and one-byte Strings through the
canonical codec, rejects all removed names and non-ASCII literals, and proves
user definitions. Its first generated all-ASCII program exceeded the existing
20-second deadline: a separate timing probe measured 43.6 seconds in expansion.
Factoring its repeated check into one ordinary source function preserved all
128 cases; the unchanged deadline then passed. No production change was needed.
Focused language tests passed 111 assertions; runner, Char, String, codec, and
boundary suites passed 1,670 assertions. The full suite passed all 39 suites,
13,682 assertions, expanded purity for 30 modules, and complete boundaries.
The complete relevant diff and whitespace check passed. Racket's ordinary
ignored compilation cache was populated; no generated artifact is tracked.

Phase 2 executable changes: one ASCII datum branch, named Char export removal,
the matching runner diagnostic, and mechanical example literal substitutions.
Tests/tooling: literal/name coverage and exact facade tables. Documentation:
current API, architecture, README, acceptance, launcher contract, and this plan.
Reader, String expansion, core constants, representations, codec, and effects
are unchanged. No new production module, runtime helper, dependency, or host
capability. Phase 2 is complete; Phase 3 follows under the continuous approval.

## Phase 3 — Append, reverse, map, and filter

### Step 3.1 — Expose the existing structural algorithms

- [x] Add small typed `append` and `reverse` wrappers in
  `core/list-transform.rkt`, reusing `raw-append`/`raw-reverse` and canonical
  reconstruction after checker unwrapping. Add their explicit exports and
  diagnostic names. Cover order, empty sides, singleton/heterogeneous Lists,
  argument Errors/types, partial application, and canonical empty output.

Step 3.1 result (2026-09-06): added the two structural wrappers in the new
transform peer, canonical reconstruction, explicit public exports, diagnostic
names, and focused behavior/contract coverage. Eight new test assertions had
Rat and Result tag numbers reversed; verified the existing closed table and
corrected only those expectations. Structural behavior and the unchanged
raw algorithms passed; expanded purity includes the new module (31 total),
and the exact boundary inventory passes.

### Step 3.2 — Enforce the callback contracts

- [x] Add public `map` and `filter`, reusing the existing raw operations with
  the necessary pure typed adapters. Enforce whole-operation Error propagation
  and Bool predicate validation without altering the raw helpers or their
  existing callers. Use one small local predicate-result helper where it
  actually serves the later predicate operations. Test first and later
  callback Errors, non-Bool predicates, preserved ordering, no callback on
  NIL, and all common contracts. Add the matching transform suite, public
  cases, and reference entries; run the Phase completion gate.

Step 3.2 result (2026-09-06): map reuses raw-map and a small pure result
fold; filter supplies a checked keep/skip selector to raw-filter. Both propagate
callback Errors as the whole answer, preserve frames, stop subsequent callbacks
after Error, and avoid callbacks on NIL. The shared predicate helper checks Bool
through raw-check-argument. Focused transform tests passed 64 assertions,
encoded-name tests passed 280, and installed-language tests passed 115.
The first full gate exposed the old core-module count in acceptance; the
focused rerun also exposed its separate directory-path count assertion. Updated
all three exact assertions from 22 to 23, without changing violation checks.
Acceptance and purity regressions then passed (21 and 136 assertions).
The final full run passed all 40 suites, 13,759 assertions, expanded purity for
31 production modules, and the complete boundary gate. Relevant diff and
whitespace checks passed.

Phase 3 executable changes: one pure transform module, four public exports,
and four encoded names. Existing raw List algorithms, generalized checker,
representations, and runtime are unchanged. Tests/tooling: one focused suite,
public and diagnostic cases, exact facade tables, and three inventory counts.
Documentation: current API, README, architecture, acceptance, and plan. No new
dependency, host capability, callback registry, or intermediate representation.
Phase 3 is complete; Phase 4 follows under the continuous approval.

## Phase 4 — Reduce and predicate searches

### Step 4.1 — Implement left reduction

- [x] Add the small accumulator recursion and typed `reduce` wrapper to the
  transform module. `reduce f initial NIL` returns initial. Test a
  noncommutative combining function to distinguish argument order and left
  association from the existing right fold. Prove callback Error propagation
  stops further callback evaluation and preserves remaining-arity behavior.

Step 4.1 result (2026-09-06): implemented direct left reduction in the
transform module with accumulator-first callback application and immediate
callback Error propagation. The first test load exposed a reference to a
nonexistent third-position alias; used the checker's existing church-succ on
argument-position-two instead, adding no metadata binding. Focused tests cover
noncommutative reduction, NIL identity, mixed accumulation, early Errors,
callback stopping, preserved frames, and curried arity.

### Step 4.2 — Implement the five searches

- [x] Add `any?`, `all?`, `find`, `find-index`, and `contains?` in
  `core/list-search.rkt`, using the same predicate-result rule. Keep loops
  direct; do not create a general search engine. Empty answers are FALSE,
  TRUE, NONE, NONE, and FALSE respectively. Return the first matching value
  or zero-based whole Rat index in Option. Use private binary counting.
  Test equality argument order, type/Error cases, no-match cases, and later
  callbacks that would fail if short-circuiting were lost. Add the matching
  search suite, exports, diagnostics, public cases, and docs; run the Phase
  completion gate.

Step 4.2 result (2026-09-06): added the small search peer with direct loops,
sharing only the identical any/contains traversal and the existing predicate
result helper. Option results and whole Rat indices use existing constructors
and private binary counting. Tests prove first/later stopping, equality order,
NIL/singleton/heterogeneous cases, non-Bool answers, incoming/callback Errors,
preserved frames, and curried arity. The final focused transform/search run
passed 192 assertions (84 and 108); encoded-name tests passed 292 and installed
language tests passed 115, including all six new public functions and stopping
programs. The full run passed all 41 suites, 13,900 assertions, expanded purity
for 32 modules, and complete boundaries. Updated all three exact core counts
to 24 before the gate. The relevant diff and whitespace checks passed.

Phase 4 executable changes: direct reduction in the transform peer, one pure
search peer, and six exports/encoded names. Tests/tooling: search suite,
reduction/public/diagnostic coverage, and exact facade/inventory tables.
Documentation: current reference, README, architecture, acceptance, and plan.
Existing raw algorithms, tag table, generalized checker, runtime, and host
capabilities remain unchanged. Phase 4 is complete; Phase 5 follows under the
continuous approval.

## Phase 5 — Indexing and predicate prefixes

### Step 5.1 — Add nth

- [x] Extend `core/list-nat.rkt` and its suite with zero-based `nth` using
  existing count validation and Option construction. Test zero, last valid,
  exact-length, past-length, negative, fractional, wrong-type, and incoming
  Error indices, NIL, and partial application. Expected absence returns NONE;
  invalid counts return the existing attributed InvalidCount Error.

Step 5.1 result (2026-09-06): nth reuses raw-list-drop after the existing
Rat count validation, returns existing Option values, and reconstructs canonical
NIL before traversal. Focused numeric List tests passed 77 assertions, covering
valid/boundary/past-end indices, NIL, heterogeneous elements, negative/fractional
counts, type and incoming Errors, and remaining-arity absorption.

### Step 5.2 — Add take-while and drop-while

- [x] Extend the search module with direct prefix traversal and the shared
  predicate-result rule. Stop predicate calls at the first false result;
  `drop-while` retains that element and its suffix. Test immediate stop,
  all-match, NIL, predicate Error/non-Bool answers, canonical empty results,
  and unevaluated later callbacks. Add exports, names, public cases, and docs;
  run the Phase completion gate.

Step 5.2 result (2026-09-06): added direct predicate-prefix loops using the
existing Bool-result rule. Drop retains the first false element and suffix;
take checks the recursive result before building a prefix cell. Focused tests
passed 148 search, 77 numeric List, 298 diagnostic, and 115 installed-language
assertions, including first/later stopping and failures, full matches, NIL,
singletons, heterogeneous values, and canonical empty output. The full run
passed all 41 suites, 13,973 assertions, expanded purity for 32 modules, and
the complete boundary gate. Relevant diff and whitespace checks passed.

Phase 5 executable changes: three pure functions in the existing numeric and
search peers, with their exports and encoded names. Tests/tooling: focused and
public cases and exact facade tables. Documentation: current reference,
README, architecture, acceptance, and plan. No module, dependency, runtime
helper, checker mechanism, or host capability was added. Phase 5 is complete;
Phase 6 follows under the continuous approval.

## Phase 6 — Zip, concat, and flatten

### Step 6.1 — Add zip and one-level concat

- [x] Extend the transform module with `zip`, producing proper two-element
  Lists and stopping at the shorter input, and `concat`, removing exactly
  one nesting level. Validate each visited outer element of concat as List;
  a wrong type is an attributed structured Error. Test both unequal-length
  directions, empty sides, empty inner Lists, nesting retained by concat,
  and invalid first/later inner elements.

Step 6.1 result (2026-09-06): zip constructs two-element Lists with canonical
NIL and stops at the shorter side; concat checks each outer element as List
and propagates recursive Errors before appending. Corrected three extra closing
parentheses in newly written tests before execution. Focused transform tests
then passed 121 assertions, including both unequal-length directions, retained
nesting, empty inputs, wrong types, incoming Errors, and canonical output.
The exact facade boundary gate passed.

### Step 6.2 — Add recursive flatten

- [x] Add the direct recursive List-tag case: visit nested Lists in order;
  retain ordinary non-List values as leaves. Do not inspect host data or add
  universal equality, another representation, or a traversal framework.
  Test mixed nesting, empty nested Lists, heterogeneous leaves, fully empty
  output, Error propagation when encountered, proper tails, and preserved
  order. Add all three public surfaces, diagnostics, reference entries, and
  behavioral cases; run the Phase completion gate.

Step 6.2 result (2026-09-06): flatten uses direct List-tag recursion with a
remaining-output suffix, preserving leaf order and propagating encountered
Errors once while retaining Result Err. Focused transform tests passed 139
assertions, encoded-name tests passed 304, and installed-language tests passed
115. Coverage includes nesting retained by concat, recursive flattening,
canonical empty results, heterogeneous leaves, existing Error frames, and
unevaluated later leaves after failure. The full run passed all 41 suites,
14,034 assertions, expanded purity for 32 modules, and complete boundaries.
The relevant diff and whitespace checks passed.

Phase 6 executable changes: three functions in the existing transform module,
explicit exports, and encoded names. Tests/tooling: focused/public cases and
exact facade tables. Documentation: current API, README, architecture,
acceptance, and plan. No new module, representation, traversal framework,
dependency, runtime code, or host capability. Phase 6 is complete; the two
specified generators are next under the continuous approval.

## Phase 7 — Range and repeat

### Step 7.1 — Add the two generators

- [x] Extend the numeric List module using existing raw Rat comparison,
  whole-number validation, increment, and private binary count operations.
  Implement only `range start end` and `repeat count value`. Test negative
  starts, crossing zero, adjacent/equal/reversed endpoints, fractional
  endpoints, zero/one/multiple repetitions, negative/fractional counts,
  wrong tagged arguments, incoming Errors, partial application, and
  heterogeneous repeated values. Zero repetitions return canonical NIL
  without using the value. Add exports, names, unit/public tests, and docs;
  run the Phase completion gate.

Step 7.1 result (2026-09-06): range validates signed whole Rat bounds and
uses existing comparison/successor operations; repeat validates its count and
uses private binary countdown. Zero repeat returns canonical NIL before
examining its value. Focused numeric tests passed 138 assertions, encoded-name
tests passed 308, and installed-language tests passed 115. Coverage includes
signed/cross-zero/equal/reversed ranges, fractional rejection, canonical
Rat/List output, mixed repeated values, Error propagation, remaining unary
arity, and lazy zero. The full run passed all 41 suites, 14,099 assertions,
expanded purity for 32 modules, and complete boundaries. The relevant diff
and whitespace checks passed.

Phase 7 executable changes: the two generators in the existing numeric List
module, explicit exports, and encoded names. Tests/tooling: focused/public
cases and exact facade tables. Documentation: the complete API, README,
architecture, acceptance, and plan. No new module, checker, representation,
dependency, runtime code, or host capability. All 25 specified List functions
are implemented; final branch and packaged verification follows in Phase 8.

## Phase 8 — Complete surface and simplicity verification

### Step 8.1 — Check the delivered API against the proposal

- [x] Compare the exact facade export set against every existing renamed
  callable, retained constant/effect, and these 25 List operations:

  `cons head tail is-nil len take drop nth take-while drop-while append
  reverse zip concat flatten map filter reduce any? all? find find-index
  contains? range repeat`.

  Confirm old callable aliases and named public Chars are absent; Char
  literals work; Map and its `map-*` operations remain distinct from List
  `map`; all public diagnostics/examples use the new names. Synchronize
  README, API reference, architecture/acceptance docs, and specification
  status without claiming unrun or unpublished acceptance.

Step 8.1 result (2026-09-06): a read-only comparison of the baseline facade,
current explicit exports, normative inventory, and API reference agreed
exactly: 105 callables, 10 retained constants, and seven syntax/module
bindings. The delta is exactly 63 lowercase callable renames, 85 removed
named Chars, and 18 additions completing the 25 List functions. Existing
installed-language tests execute every renamed/new operation, reject all old
callables and named Chars, validate all 128 ASCII literals, and permit ordinary
Char-name definitions. Map remains distinct from List map. Current examples
and documentation use the new names; older acceptance/specification text is
explicitly historical. The three normative file hashes and proposal hash
still match their recorded values. Documentation now describes the complete
source API and continues to distinguish the published archive.

### Step 8.2 — Verify purity, minimality, and completion

- [x] Review the complete branch diff for unrelated changes and unnecessary
  helpers, wrappers, intermediate structures, or host-side complexity. Every
  addition must have a direct role in a requested contract or its proof.
  Check the new modules enter the existing production inventory and purity
  scan; preserve fail-closed rejection and all privileged-boundary limits.
  Run the final full suite. Update existing Linux consumer examples as
  necessary and validate a clean recorded implementation commit with the
  existing Linux build/consumer harness; keep the artifact unpublished.
  Record actual tested revisions and results, commit/push verified work,
  and stop for Kyle's branch review.

Step 8.2 result (2026-09-06): reviewed the complete branch delta from
`097deb5`, including the new pure modules, existing numeric List additions,
mechanical facade/diagnostic changes, tests/checker tables, and current docs.
Every addition serves the specified surface or its verification. The four
existing raw List algorithms, generalized checker, closed tags, macros,
readers, effects, codec, and host remain unchanged. There is no new dependency,
representation, callback framework, runtime wrapper, or host capability. All
70 existing encoded diagnostic names have the required lowercase spellings;
exactly 18 specified names were added. Both new modules enter the existing
inventory and expanded-purity scan; fail-closed enforcement is retained.

The unchanged builder produced a clean Linux artifact from implementation
commit `17641cc41f53d00e96308846500f8ed65e633203` using cached Racket CS 9.3.
The existing Ubuntu consumer, without Racket/checkout/external network,
passed its complete workflow and one additional public-only program with 30
success markers covering all 25 List functions, Char literals, ordinary
identifiers, Map, and laziness. Archive SHA-256 is
`38329c11591b5d724ced243bc3327576dbe2bc3d06b428ae65fbad6b84af3acf`;
the unpublished artifact and full provenance/results are recorded in
[docs/ACCEPTANCE.md](docs/ACCEPTANCE.md). Final production sources and shipped
examples are identical to that build commit; Phase 8 changes only consumer
test code and documentation.

The final full source run passed all 41 suites, 14,099 assertions, expanded
purity for 32 modules, and the complete source/boundary inventory. The affected
distribution suite separately passed 209 assertions; shell syntax and final
diff/whitespace checks passed. Full Phase logs remain under
`/tmp/attalambda-public-api-phase*-tests.log`; final build/consumer logs are
`/tmp/attalambda-public-api-phase8-build.log` and
`/tmp/attalambda-public-api-phase8-consumer.log`.

Phase 8 executable language changes: none. Tests/tooling: one direct program
in the existing Linux consumer, with no new harness. Documentation: completed
plan, API/reference status, README links, and exact acceptance evidence; the
three normative specification files retain their recorded hashes. Phases 1–8
are complete as separately verified feature-branch commits. Stop for Kyle's
branch review; no pull request, merge, version change, tag, or publication.

---

# Completed plans — historical record

The material below completed before merge `097deb5`. Its branch directions,
starting-state observations, approvals, and stop conditions describe that
completed work only. The Public API and List library plan above is active.

# HTTP, empty-List consistency, and explicit exit plan

Status: all five Phases complete on 2026-09-05; verified for Kyle's review.
Branch: `refactor/non-core-simplification`; no new branch.
Verified baseline: `6663ad6c55a71791df1db768652089cabcce6496`, with a clean
working tree before this planning edit.
Source: [Kyle's HTTP/List/exit specification](/home/serrecchia/Downloads/ATTALAMBDA_HTTP_LIST_EXIT_SPEC.md),
SHA-256 `b57cfc8a694ac9af02b60d50cec950ea66706641b60922c6181aed9912903e1f`.
The three [language specifications](docs/specifications/README.md) remain
normative; Phase 0 explicitly amends them before adding the new effect.

## Size and verified starting state

Three bounded changes, with five Phases and thirteen single-pass Steps as
the supplied specification requires. This is smaller in implementation scope
than the completed non-core refactor, but not three tiny passes. Empty-List
consistency is expected to require tests only; HTTP changes two existing
production modules; exit adds one small effect across existing layers.
Specification, checker, subprocess, and packaged acceptance work account for
the remaining Steps. The prior baseline full suite took about 23 minutes;
five required Phase runs plus the Linux build/consumer make verification a
material part of the work. That is prior timing, not a new runtime estimate.

- **HTTP exists:** `effects/http-server.rkt:161` implements
  `raw-read-http-request-step` with `raw-string-append`, whole-List length,
  and `parse-http-request` after each read. `effects/http.rkt:663` first
  scans for `CR LF CR LF` and returns incomplete until it is present. The
  existing parser can therefore remain the sole semantic parser.
- **Canonical reconstruction exists:** `raw-rebuild-list` in
  `core/lists.rkt` is already used by `MAKE-STRING` and public `DROP`.
  `runtime/codec.rkt:105` accepts only the canonical `NIL` terminator.
  A read-only planning probe passed all 18 requested empty-producing cases,
  checking both codec conversion and canonical List/String termination.
  The existing `tests/codec-test.rkt` suite passed 144 tests. The expanded
  persistent regression matrix has not yet been written.
- **Public exit is new:** no `effects/exit.rkt`, `tests/exit-test.rkt`,
  public exit binding, protocol entry, or host performer exists. The protocol
  and real dispatcher each contain nine operations. Native exit currently
  appears in the runner's launcher-failure path. Existing bounded Rat
  decoding and language host injection can be reused.

## Change boundary and execution

The planning turn changed only `PLAN.md`; the completed plan below is retained
as history. Kyle approved all five Phases on 2026-09-05 after discussing purity
and the exit boundary. Execute them serially without routine reconfirmation.
This named work is separate from the previous plan's final stop.

The approved scope modifies the two HTTP modules, protocol, real host, language
expander, directly affected tests/checkers, normative specifications, current
documentation, and existing Linux consumer harness named below. Create only
`effects/exit.rkt` and `tests/exit-test.rkt` as new production/test modules.
List producers change only if the persistent matrix proves a specific failure;
the planning probe gives no present reason to modify one.

Behaviorally unchanged: List representation and codec acceptance; existing
HTTP grammar, 8192-byte cap, trailing-data rejection, error propagation,
cleanup, and laziness; all nine existing host operations; launcher failure
statuses; normal status-0 completion without explicit exit. Intended changes
are incremental HTTP work and the new explicit program-chosen exit effect.
No dependencies, new runtime layer, generic streaming parser, HTTP bodies,
concurrency, timeout, TLS, stderr effect, process spawning/signals, exit codes
2..255, automatic Error printing, or final-value/status inference.

Before each Step, read `AGENTS.md`, all three normative specifications, the
named production files, and directly relevant tests. Execute and record one
Step at a time in source order; each numbered Step is one pass. Run focused
tests while working and both architectural checkers after production edits:
`racket tooling/check-purity.rkt` and `racket tooling/check-boundaries.rkt`.
After every Step, inspect `git diff --check` and the complete relevant diff,
explicitly excluding `.env`, `*.env`, `.env.*`, and `*.env.*` from every
recursive listing/search/bulk read or diff. Never inspect dotenv contents.

At each Phase boundary, run `./run-all-tests.sh`, then obtain a fresh agent
review focused only on that Phase's diff and direct interactions. Prove causes
before repairs; fix serially, at most ten findings per batch, obtain fresh
review of repairs, and repeat invalidated checks before continuing. Record
executable, test/tooling, and comment/doc changes separately. Commit and push
each verified Phase only to this branch. Use isolated temporary filesystem
fixtures, ephemeral loopback ports, and existing finite test deadlines.
Stop on a normative conflict, a broad List representation problem, or two
failed diagnostic hypotheses. No unrelated cleanup or weakened checks.

## Phase 0 — Specify exit (one Step)

### Step 0.1 — Amend the normative contract

- [x] Append dated amendments to the three normative specification files;
  update precedence/provenance and hashes in `docs/specifications/README.md`.
  Specify public `(exit status)`: Rat 0/1 only; wrong type yields ordinary
  TypeMismatch Error, other Rats yield existing InvalidCount Error, and
  incoming Error bubbles. Pure code validates/chooses; only the real host
  terminates with the requested OS status and does not return. Fake hosts
  may return. Runner-native exit remains launcher/source scaffolding;
  Error/Err values never automatically determine process status. Programs
  without exit retain normal status 0. No production changes in this Step.
  Run the full suite, diff checks, and Phase review before committing.

Step 0.1 result (2026-09-05): appended all three amendments, updated the
index's precedence and SHA-256 provenance, and verified that every original
byte remains an exact prefix. Executable/test changes: none. Documentation:
the approved plan and four specification documents. `./run-all-tests.sh`
passed all 38 suites; expanded purity passed 29 production modules and the
repository-wide boundary gate passed. Exact-file diff checks passed. Fresh
Phase 0 review found zero confirmed issues. No repairs were needed.

## Phase 1 — Prove empty-List consistency (two Steps)

### Step 1.1 — Persist the codec consistency matrix

- [x] Extend the canonical-empty section of `tests/codec-test.rkt`. Generic
  Lists: `NIL`, singleton `TAIL`, nonempty `TAKE 0`, exact/beyond-length
  `DROP`, `TAKE 0` after another List operation, and empty `DROP` after
  `TAKE`. List Byte: singleton `TAIL`, `TAKE 0`, exact/beyond-length `DROP`.
  Strings: `MAKE-STRING NIL`, singleton `STRING-TAIL`, append two empty
  Strings, and `BYTES-TO-STRING NIL`. Also convert empty String and singleton
  String tail to bytes; compose `"A" -> STRING-TO-BYTES -> DROP 1 ->
  BYTES-TO-STRING -> STRING-TO-BYTES -> codec`. Assert empty host List/bytes
  and canonical `NIL` where required, retaining forged-terminator rejection.

Step 1.1 result (2026-09-05): persisted 21 labeled cases, each checking codec
acceptance and canonical NIL identity, retaining prior empty-input and forged
terminator/cycle coverage. Test-only change; List producers and codec are
untouched. Corrected one extra parenthesis in the new table after its reader
diagnostic. The complete relevant diff and whitespace check passed.

### Step 1.2 — Verify; repair only a proven producer

- [x] Run codec, List, and String suites, plus List-count/Byte suites if
  their producers change. If all cases pass, retain only the regression
  tests. Otherwise name the failing producer and repair its smallest pure
  reconstruction path using canonical `NIL`/existing `raw-rebuild-list`.
  No codec loosening or List redesign; stop if the cause is broader. Run
  applicable checkers, full suite, and Phase review before committing.

Step 1.2 result (2026-09-05): all matrix cases passed; no producer failed,
so no production repair was justified or made. Focused codec/List/String
suites passed 665 assertions (178/57/430). The full run passed all 38 suites,
12,335 assertions, expanded purity for 29 production modules, and the source
inventory/boundary gate. Fresh Phase 1 review found zero confirmed issues;
its independent codec run passed 178 assertions. Relevant diff checks passed.
Executable changes: none. Tests: codec consistency matrix only. Documentation:
this plan's completion record. Core, codec, and forged/cyclic rejection are
untouched.

## Phase 2 — Incremental HTTP framing and accumulation (three Steps)

### Step 2.1 — Add the pure delimiter scanner

- [x] Add `raw-scan-http-header-end` in `effects/http.rkt`, returning a raw
  Pair of found flag and next suffix. Inspect only the new chunk plus at
  most three preceding characters, using existing pure List/String tools;
  retain at most the last three characters when incomplete. Extend
  `tests/http-test.rkt` for a whole delimiter, all three internal delimiter
  splits, byte-at-a-time input, overlapping CRs, near matches, empty chunks,
  trailing characters, and every two-chunk split of a complete valid request.

Step 2.1 result (2026-09-05): added the pure suffix/chunk scanner without
changing semantic parsing. The HTTP suite passed 510 assertions, including
all delimiter/request splits and suffix bounds. Expanded purity passed all
29 production modules; the source inventory/boundary gate and complete
relevant diff/whitespace checks passed.

### Step 2.2 — Replace the server's repeated prefix work

- [x] Change `effects/http-server.rkt` loop state to reversed accumulated
  characters, running private binary Nat count, and at-most-three-character
  suffix. Convert/count/reverse only the new chunk; prepend its reverse
  without walking the old prefix. Check the running count against 8192
  before parsing. Scan suffix plus chunk; incomplete nonempty reads recur
  without full parsing. At completion or EOF, reconstruct once and call the
  existing parser once. Include all bytes from the completing chunk so
  trailing-data rejection stays intact. Update the loop's obsolete comments;
  preserve callers, cleanup, EOF and failure behavior. Run both HTTP suites.

Step 2.2 result (2026-09-05): replaced repeated prefix append, recount, and
parsing with reversed accumulation, a private binary count, and suffix-only
framing. Parser and cleanup implementations are untouched. Both HTTP suites
passed 668 assertions; expanded purity (29 modules), boundary/inventory,
complete relevant diff review, and whitespace checks passed.

### Step 2.3 — Verify server behavior across chunk boundaries

- [x] Extend existing fake-host tests in `tests/http-server-test.rkt` for
  one chunk, one byte per chunk, every nonempty two-chunk split, and each
  delimiter split. An empty TCP read remains EOF, not an interior fragment.
  Pin premature EOF, exactly 8192 and over-cap requests, malformed and
  unsupported requests, trailing data, read failures, cleanup, read order,
  and repeated-forcing laziness. Review source to prove no full parse on
  incomplete chunks, no repeated old-prefix append traversal, and no whole
  request recount. Run both HTTP suites, checkers, full suite, and review.

Step 2.3 result (2026-09-05): split, byte-at-a-time, EOF, exact/over-cap,
malformed/unsupported, trailing-data, partial-read failure, cleanup, and
repeated-forcing regressions passed. Corrected the new padded valid fixture
to include the parser's required Host header; no production repair was
needed. Focused HTTP suites passed 1,412 assertions (510/902). The full run
passed 38 suites, 13,381 assertions, expanded purity for 29 production modules,
and the inventory/boundary gate. Fresh Phase 2 review found zero confirmed
issues or material regression gaps; its independent HTTP run also passed
1,412 assertions. Source review confirms one guarded full parse and no old
prefix append/recount; tests observe results and effects, not parser calls.
Complete relevant diff and whitespace checks passed. Executable changes:
pure scanner and server accumulation only. Tests: two HTTP suites. Comments
and documentation: accurate buffering/test descriptions and this plan.
Semantic parser, cleanup implementation, host, codec, and core are untouched.

## Phase 3 — Add public exit 0/1 (four Steps)

### Step 3.1 — Construct and validate the pure exit request

- [x] Create peer `effects/exit.rkt` and `tests/exit-test.rkt`; extend
  `effects/protocol.rkt` with `exit-function-name`, `exit-operation` and
  the closed operation-table entry. Request: List `["exit", Rat(status)]`.
  Reuse the generalized checker, existing raw Rat primitives, and request
  dispatch/bubbling pattern. Validate 0/1 before calling the injected host.
  Test both encodings, unary shape, no call before forcing, exactly one call
  per valid status, TypeMismatch, InvalidCount for `-1`, `2`, and `1/2`,
  incoming Error, and fake-host return propagation. Verify direct malformed
  protocol requests retain InvalidHostRequest behavior. Change checker
  inventories only as required.

Step 3.1 result (2026-09-05): created the pure exit peer and its tests, and
added the tenth pure protocol entry. Exit/stdout/TCP suites passed 459
assertions (167/24/268), including malformed direct requests, exact statuses,
Error frames, fake returns, and laziness. Both architectural checks passed;
expanded purity now covers 30 production modules without checker changes.
Complete relevant diffs and whitespace checks passed. Real host termination
and the public language binding are still pending the following Steps.

### Step 3.2 — Perform explicit process termination in the real host

- [x] Extend `runtime/host.rkt` with the tenth dispatch case and
  `perform-exit`; reuse `decode-bounded-count` with bounds 0 and 1 for
  defensive canonical whole-Rat decoding. No automatic output, final-value
  inspection, Error mapping, or returning `Ok UNIT` after successful real
  exit. Update `tooling/check-boundaries.rkt`, host tests, and
  `docs/design/host-boundary.md` for this exact capability. Successful real
  calls run only in child processes; malformed requests must not terminate
  tests. Native exit remains forbidden in pure effects, codec, and readers.

Step 3.2 result (2026-09-05): added the real host's bounded exit performer
and exact checker capability. Host tests passed 81 assertions, including
isolated children terminating silently with statuses 0 and 1 and surviving
14 malformed requests across the pure bridge and strict dispatcher. Boundary
tests passed 119 assertions, including native-exit rejection in effects,
codec, and readers. Both architectural gates passed (30 pure modules).
Existing compiled fresh-language setup keeps subprocess checks within their
unchanged deadlines. Updated the host design contract, distinguishing wrapper,
bridge, and defensive host validation and documenting existing non-List
TypeMismatch behavior accurately. Complete relevant diffs and whitespace
checks passed. Codec, core, runner, and the nine existing performers are
untouched; public injection follows in Step 3.3.

### Step 3.3 — Expose the canonical public binding

- [x] In `lang/expander.rkt`, inject `language-host` once into `make-exit`,
  bind internally as `language-exit`, and rename/export as `exit` without
  colliding with native Racket exit. Update language tests and exact
  import/export/injection checks; run boundary/purity suites as applicable.
  Add no other public alias or constant; runner production behavior stays.

Step 3.3 result (2026-09-05): added the single host injection and canonical
rename from private `language-exit` to public `exit`, with exact checker
import/export/definition expectations. Language and boundary suites passed
209 assertions (90/119); both architectural gates passed (30 pure modules).
Public programs proved ordinary function aliasing and non-terminating invalid
status behavior. Updated the host design's implementation status and wrapper
count. Complete relevant diffs and whitespace checks passed. No additional
public alias, status constant, or runner production change was introduced.

### Step 3.4 — Prove operating-system statuses and sequencing

- [x] Extend existing runner/subprocess tests with temporary public-only
  `#lang attalambda` programs: exit 0/1 gives exact status and empty output;
  no exit, including `(DIV 1 0)` and ordinary Error, remains status 0;
  missing-file Err chosen fatal/recoverable gives 1/0; stdout before exit
  appears, stdout afterward does not; an unselected exit branch stays lazy.
  Run exit, host, language, runner suites, both checkers, full suite, and
  Phase review. Pure AttaLambda makes every fatal/recoverable decision.

Step 3.4 verification (2026-09-05): runner tests passed 208 assertions,
including exact silent 0/1 exits, unchanged no-exit Error/Err completion,
pure fatal/recoverable missing-file choices, before/after output ordering,
and an unselected exit. The first full run found the old exact seven-effect
inventory expectation in `tests/purity-test.rkt`; source inventory proved
eight with the new exit peer. Updated only that expectation, retained every
per-module purity assertion, and passed its focused 135 assertions. The
subsequent full run passed all 39 suites, 13,599 assertions, expanded purity
for 30 production modules, and the repository boundary/inventory gate.
Complete relevant diffs and whitespace checks passed. Fresh Phase 3 review
found one enforcement gap: admitting the public `exit` spelling also admitted
native exit in an existing language syntax helper or transformer. Both new
regressions reproduced the bypass. The checker now pins the sole occurrence
of `exit` to the already-exact public export contract; boundary tests passed
121 assertions and the repository boundary gate passed. The next full run
passed all 39 suites (13,601 assertions), expanded purity for 30 modules, and
the boundary gate. Repair review then proved that the existing datum walkers
missed boxed and prefab-contained identifiers. Additional regressions also
reproduced a hash-contained miss; the vector control already passed. Extended
both existing walkers to inspect boxes, hash keys/values, and prefab fields.
The invalidated boundary suite and gate were rerun successfully: 125 focused
assertions passed, including all six language-exit regressions. A fresh
container-repair review found zero confirmed issues or material gaps, passed
125 assertions independently, and checked nested-container siblings. The
125-assertion repair suite supersedes the 121-assertion boundary suite in that
full run; Phase 4 will run the complete suite again on the final source.
Complete relevant diffs and whitespace checks passed. Executable changes:
pure exit wrapper/protocol, sole-host performer/dispatch, and one public
injection. Tests/tooling: exit, host, language, runner, inventory, and boundary
regressions/checks. Documentation: host contract and this completion record.
No core, codec, reader, or runner production change was needed or made.

## Phase 4 — Documentation, packaged behavior, acceptance (three Steps)

### Step 4.1 — Synchronize current documentation

- [x] Update `README.md`, `ARCHITECTURE.md`, `docs/design/host-boundary.md`,
  and `docs/ACCEPTANCE.md` for ten operations, public exit 0/1, unchanged
  no-exit completion and launcher statuses, and incremental HTTP work.
  Also update the shipped `distribution/GETTING_STARTED.md.in` status table,
  which currently has no explicit program-exit entries. Remove the
  deferred quadratic HTTP finding only after both parsing and prefix
  accumulation/count repetition are eliminated. Preserve the blocking,
  single-connection limitation; no new timeout/nonblocking claims or old
  milestone narration. Record observed implementation separately from plans.

Step 4.1 result (2026-09-05): synchronized the five existing documents with
the implemented ten-operation boundary, pure exit choices/validation, exact
0/1/default completion, unchanged launcher statuses, and incremental HTTP
work. Removed the resolved repeated-prefix/reparse finding while retaining
blocking single-connection/no-timeout limits. README explicitly distinguishes
this branch from the published 0.3.0 archive. Corrected the shipped guide's
observably stale four-example/first-release wording without changing version,
artifact policy, or legal bytes. Documentation-only changes; the distribution
suite passed 207 assertions, and complete relevant diff/whitespace checks
passed. Final packaged observations remain pending.

### Step 4.2 — Extend existing Linux consumer checks

- [x] Extend `tooling/test-linux-distribution.sh` and directly relevant
  `tests/distribution-test.rkt` checks to prove packaged exit 0, exit 1,
  and unchanged no-exit status 0, including captured stdout/stderr. Reuse
  existing temporary programs, status capture, and consumer isolation;
  no new distribution framework, artifact policy, version, or release.

Step 4.2 result (2026-09-05): extended the existing isolated Linux consumer
with five public-only temporary programs for exact 0/1/default statuses and
fatal/recoverable missing-file Err decisions. Each uses the existing captured
output checks and a finite 20-second child deadline; expected status 1 is
captured without weakening shell failure handling. Status evidence is printed
only after exact status and empty stdout/stderr checks pass. Added the guide's
status-1 entry to its existing document assertions. Shell syntax checks and
208 distribution assertions passed; complete relevant diff/whitespace checks
passed. Test/tooling changes only; actual packaged behavior is still pending
the clean build and consumer in Step 4.3.

### Step 4.3 — Final acceptance and fresh review

- [x] Run the full suite and both checkers; review only this milestone's
  changes with a fresh agent. In isolated temporary fixtures, prove checker
  rejection of native computation in pure HTTP framing and native exit in
  effects, codec, and a reader; retain no mutations. Resolve proven findings
  and rerun invalidated checks. Build a recorded clean implementation commit
  with the existing Racket CS 9.3 Linux harness and run the independent
  no-Racket consumer. Record revision, checksum, packaged 0/1/default
  statuses, and pure program decisions making a missing-file Err fatal or
  recoverable. Keep acceptance artifacts unpublished. Commit/push verified
  results on this branch and stop: no pull request, merge, tag, or release
  without Kyle's explicit approval. Any later evidence-only commit must be
  distinguished from the implementation revision actually tested.

Step 4.3 result (2026-09-05): isolated copies of the actual
HTTP framing, exit wrapper, codec, and reader passed before mutation. Native
`+` in the framing helper was rejected as forbidden-host-identifier by
expanded purity and unapproved-effect-identifier by the boundary gate. Native
exit in the pure peer was rejected as unapproved-production-identifier and
unapproved-effect-identifier; codec and reader native exit were rejected as
forbidden-codec-capability and forbidden-reader-capability. All four copied
bodies were restored, SHA-256 matched their working-tree originals, and both
applicable checks returned no findings again. Working production sources were
never mutated. Also corrected the acceptance map after source inspection:
fixed launcher-failure cases belong to the runner suite, not the Linux
consumer. The final complete run passed all 39 suites with 13,606 assertions,
expanded purity for 30 production modules, and the boundary/inventory gate.
Fresh milestone review covered all 28 changed files and direct interactions:
zero confirmed findings or material test gaps; its independent focused run
passed 980 assertions. Shell syntax, specification hashes, and complete
relevant diff/whitespace checks passed.

The unchanged CS 9.3 builder produced an archive from clean implementation
commit `31138222bd5299d6554ad036c4f44e9c74fe0d4c`, verified in its manifest.
The cached builder image lacked Git; its prerequisite check stopped before
building. A read-only mount of the existing Git executable passed the complete
prerequisite probe and enabled the build without package installation or
source changes. The independent digest-pinned Ubuntu 24.04 consumer had no
Racket, raco, or checkout. All guide, file/TCP/HTTP, relocation, and completion
checks passed. Packaged exit 0/1, no-exit completion, and fatal/recoverable
missing-file Err choices produced statuses 0/1/0/1/0 with empty stdout/stderr.

Local unpublished archive:
`/tmp/attalambda-http-exit-build-X0sRsh/attalambda-0.3.0-linux-x86_64.tar.gz`;
SHA-256 `cb2eab3a0041b8733467f4839869e9a726b129b362dce9a8e2632218c4c5b981`;
13,948,353 compressed bytes, 59,765,547 unpacked regular-file bytes, 11 files
(two runtime files). Complete acceptance/provenance is in
[`docs/ACCEPTANCE.md`](docs/ACCEPTANCE.md). This final record and that evidence
are a later documentation-only commit, not the implementation revision built
above; no production, test, or shipped-guide bytes changed after acceptance.

Phase 4 executable changes: none. Tests/tooling: five packaged completion
cases and the shipped-guide assertion. Documentation: synchronized existing
docs and recorded observed acceptance. Across the milestone, core, codec,
readers, runner production code, version, legal bytes, and build script are
untouched. All five Phases are complete. Stop for Kyle's branch review; no
pull request, merge, tag, or release has been created.

## Final branch bug hunt — 2026-09-05

Kyle separately approved this branch-wide correctness pass after milestone
completion. Scope: all 57 changed paths from `main` at `578f1ac` through
`96652c0`, plus their direct interactions. No further refactor is authorized.

Coverage: 40 current files received a close read. The other 17 received a
close read of the delta with selected direct interactions or a surrounding
skim: `effects/http.rkt`, `tooling/check-boundaries.rkt`, and the boundary,
distribution, errors, files, HTTP, language, Lists, purity, runner, stdout,
Strings, TCP-host, TCP, typecheck, and Unit test suites. No in-scope delta was
left unexamined. Unchanged core algorithms and unrelated platform machinery
did not receive a fresh full audit; the complete source suite still exercises
them. Normative amendments, previous review repairs, codec canonicality,
dispatch/error precedence, resource cleanup, reader/helper substitutions,
incremental HTTP, exit injection, and architectural enforcement were traced.

No production correctness defect was confirmed. A deterministic seed-9052026
scratch probe passed 2,770 assertions over 180 scanner inputs and 45 multi-chunk
server scenarios, comparing framing with a host-byte oracle and server results
with the existing semantic parser. It also checked cleanup, unforced effects,
and repeated forcing. It found no bug; it is not counted as retained regression
coverage or a replacement for the existing HTTP tests.

Three documentation discrepancies in completed work were confirmed and
corrected serially:

1. The distribution contract conflated normal completion with explicit program
   termination. Existing runner cases show missing-file Err can deliberately
   lead to status 1, while no exit and recoverable choices remain 0. The contract
   now distinguishes these paths and marks exit as unpublished source behavior.
2. Consumer evidence had been copied from source-suite evidence. The Linux
   harness inventories foundations but never executes it and does not exercise
   fixed launcher failures. Corrected both the current distribution contract
   and the earlier non-core acceptance paragraph;
   the earlier acceptance-document correction had missed these sibling claims.
   `tests/runner-test.rkt` and `tests/milestone-two-acceptance-test.rkt` own
   those executable checks; the consumer's actual checks remain unchanged.
3. The shipped guide assumed the manifest records an operating-system version.
   The actual clean-`3113822` archive manifest and builder record target,
   toolchain, and native-library assumptions, not that version. Corrected the
   guide without introducing a compatibility promise; one assertion in the
   existing guide-contract test pins the corrected claim. It checks the guide's
   wording, not runtime compatibility. Packaged acceptance must be repeated
   because the guide is a shipped input.

Production-code changes: none. Tests: one guide-contract assertion; the first two
prose corrections are verified against existing behavioral tests and the exact
consumer commands, not new source-string behavior tests. Documentation:
existing distribution contract, guide, and this plan only. No new module,
dependency, language behavior, purity exception, release, or permission change.
Focused exit verification passed 167 assertions. The full run passed all 39
suites with 13,606 assertions, expanded purity for 30 production modules, and
the complete boundary/inventory gate. That run reached the distribution suite
before its edit (208 assertions); the post-edit focused run passed all 209,
including the added guide assertion. The new assertion rejects the previous
guide wording. Fresh cold review of all four repair files and direct evidence
found zero confirmed issues, including in the shared guide's macOS and Windows
manifest claims. No findings are deferred.

The unchanged Linux builder then produced a fresh archive from clean reviewed
commit `441ef63622e63584fe9e70e56c2cc154c45485ec`, verified in the manifest,
using the same cached Racket CS 9.3 image and read-only Git mount as Phase 4.
The corrected guide is present in the archive. Local unpublished artifact:
`/tmp/attalambda-bughunt-build-zp2iZ4/attalambda-0.3.0-linux-x86_64.tar.gz`;
SHA-256 `997e8bfe1113da9a28547b03427969ea07bcd8b6f49468a69b4bf246bf148946`;
13,947,823 compressed bytes, 59,765,570 unpacked regular-file bytes, 11 files
(two runtime files).

The same digest-pinned Ubuntu 24.04 consumer passed without Racket, raco, a
checkout, or external networking. Checksum, guide workflow, stdout,
file/TCP/HTTP behavior, and relocation passed. Explicit exit 0/1, default
completion, and fatal/recoverable missing-file decisions produced statuses
0/1/0/1/0, each with empty stdout/stderr. First and relocated version startups
were 369 ms and 374 ms; these are observations, not guarantees. The final
marker was `consumer_acceptance=passed`. Version and legal bytes are unchanged.

Review and verification are complete. The later evidence-only commit changes
only this plan, not a shipped input or the built revision above. Commit/push
that final record on the existing branch, then stop for Kyle's branch review.
No further refactor, pull request, merge, tag, or release is part of this pass.

---

# Completed non-core simplification plan

Status: complete on 2026-09-05; pushed for Kyle's review. The permanent stop
at the end of Step 4.2 now applies.
Branch: `refactor/non-core-simplification`.
Starting commit: `578f1acc00566c17c18786a393cfa0b496c531ba`.

**The result must contain less code, less indirection, and less maintenance.**
The [refactor specification](docs/design/non-core-refactor.md) defines the
preserved contracts. The [language specifications](docs/specifications/README.md)
remain normative. This replaces the rejected 63-step proposal; it is not
that proposal compressed into fewer headings.

## Scope and execution

Thirteen Steps in four Phases. Each Step is one bounded change or verification;
prerequisites are completion of the previous Step and its required checks.
Execute Steps serially without routine permission requests under Kyle's
approval. Keep each Step bounded and record its result before continuing.

Work in existing modules. No new runtime layer, request types, codec importer,
prelude, literal module, generic checker, dependency, or review framework.
Pure lambda computation is protected wherever it occurs, including effects
and terms generated by macros. No List/sentinel, pathname-policy, process-exit,
public-language, resource-lifecycle, or distribution-policy redesign.
The only planned diagnostic correction replaces obsolete Nat wording with Rat.

Before each edit, name the existing code to remove, why the complete result
will be easier to follow, and the behavior checks. Revise or drop a candidate
that cannot meet those conditions; keep necessary working code. Do not create
extra work to make a Step end with a patch. Supporting edits are limited to
the affected tests, comments/docs, this plan, and the minimum existing checker
rules needed for the exact change. They cannot weaken authority.

Record concise results under the Step: files changed, removed logic, source
line difference, checks, and any no-change decision. Count helpers and callers
together. No whitespace compression, comment stripping, moved-code accounting,
or deleted safeguards to manufacture a reduction. Test additions need a
specific regression they catch. Compare implementation, tests/tooling, and
documentation separately, as well as maintained code overall.

Use focused suites first and both architectural checkers for production edits.
Run the full suite before each Phase commit; a current unchanged passing run
also satisfies the pre-commit check. Review each completed diff. At the runtime
and application Phase boundaries, check the changed paths together for real
bugs. Prove a cause before fixing it, fix serially, check siblings, and obtain
fresh review of bug/test repairs before commit under the repository rules.
At most ten fixes belong in a review batch. Zero findings is a valid result;
revisit only an actual finding or an evidence-invalidating change.

Never inspect dotenv contents, even synthetic fixtures. Every recursive
listing/search/bulk read and Git diff excludes `.env`, `*.env`, `.env.*`,
and `*.env.*`; do not follow links to them. Use isolated temporary fixtures,
ephemeral loopback ports, and finite test-harness deadlines. No Graphify.

A failed required check, normative conflict, excluded repair, or unavailable
mandatory environment is a blocker. Diagnose without speculative code edits;
after two failed hypotheses stop and report. Do not weaken tests, increase
timeouts to hide failures, or add unplanned rewrites. Adding a new workstream
requires Kyle's decision; this plan must not grow back into the rejected one.

## Phase 1 — Simplify the existing runtime

### Step 1.1 — Establish the baseline and removal targets

- [x] **Scope:** this plan and the execution/Git paragraphs of `AGENTS.md`.
  Record the approved branch, serial execution, and final stop; preserve all
  language and authority rules.
- **Work:** record source/public-export inventories, source line totals,
  current tools, and full-suite/checker results. Verify the pinned Racket CS
  9.3 Linux build/consumer path is available before production edits. Inspect
  the named candidates below and record concrete removals; no speculative
  module split. Use this plan for evidence, not another planning document.
- **Check:** `./run-all-tests.sh` passes, mandatory tools are usable without
  paid usage or privileged system changes, and no unexplained edits exist.
  Historical release runs and preliminary 8.10 probes are not this baseline.
- **Result (2026-09-05):** the unchanged starting commit passed all 38 test
  files and 12,298 assertions; purity passed for 29 production files and the
  repository-wide boundary inventory passed. The run used local Racket CS
  8.10 and took about 23 minutes. Docker already contains the exact full
  `racket/racket:9.3-full` builder image and digest-pinned Ubuntu consumer;
  direct probes confirmed Racket CS 9.3 and `main-distribution`, so final
  acceptance needs no paid or privileged setup.
- **Inventory:** 29 pure/effect production modules, 7 non-pure production
  modules, 13 readers, 42 test/support sources (38 suites), 8 tooling sources,
  and the CI workflow are inventoried. Baseline line totals are 5,510 pure,
  2,057 non-pure implementation, 13,478 tests/support, and 6,731 tooling/CI:
  27,776 maintained code lines overall and 22,266 in the refactor comparison
  surface. The exact public-surface gate passed; in the edited runtime it locks
  `host` as the sole host export and the existing codec struct/conversion/Result
  exports. No public export is scheduled to change.
- **Concrete removals:** replace the two repeated eager List-to-immutable-bytes
  pipelines and `first-codec-failure` walk with one local concrete operation;
  replace dispatch length/position plumbing with direct argument cases while
  retaining each named operation and performer; collapse paired POSIX/Windows
  membership calls into one closed helper. Later candidates remain conditional:
  the copied runner diagnostic bodies in the boundary gate have direct behavior
  coverage, while macro/reader/helper sharing must reduce its complete call
  path or remain unchanged. All current edits are the approved planning files.

### Step 1.2 — Remove duplicated codec conversion plumbing

- [x] **Scope:** `runtime/codec.rkt`.
- **Change:** simplify the repeated List decoding, first-failure selection,
  and immutable-byte construction in `object-string->bytes` and
  `object-byte-list->bytes`. Share only that concrete repeated operation
  locally if it shortens both callers. Keep the two-way API and all existing
  representation, evaluation-order, range, copy, and cycle checks.
- **Check:** `tests/codec-test.rkt`, then host/file/TCP callers. The complete
  codec is shorter and easier to trace, or the existing direct code is retained.
  No new representation acceptance or universal conversion mechanism.
- **Result (2026-09-05):** `object-list->immutable-bytes` now owns the two
  identical eager decode/failure/freeze pipelines; `first-codec-failure` and
  both duplicate blocks are gone. The public codec is unchanged and is 12
  lines shorter; the vocabulary edit only records the replacement names.
  Codec tests passed 144 assertions, direct host/file/TCP tests passed 353,
  and both purity and boundary gates passed.

### Step 1.3 — Shorten native request dispatch

- [x] **Scope:** `dispatch-request`, `dispatch-*`, and
  `decode-bounded-count` in `runtime/host.rkt`.
- **Change:** consolidate repeated arity and argument-selection branches into
  straightforward cases in this module. Keep concrete argument decoding and
  the existing performers; remove superseded dispatch plumbing. No request
  structs, schema, generated dispatch, callback framework, or second route.
- **Check:** `tests/host-test.rkt`, `tests/file-host-test.rkt`, and
  `tests/tcp-host-test.rkt` preserve all nine operations, left-to-right
  rejection precedence, malformed requests, ranges, and actual effects.
- **Result (2026-09-05):** `dispatch-request` now strips and counts arguments
  once and keeps each operation's arity/decode path beside its route. Seven
  intermediate dispatch functions are gone; one two-line `wrong-arity` helper
  serves all routes, and the two genuinely identical one-String operations
  retain their small shared helper. `host.rkt` is 18 lines shorter. The 353
  direct host/file/TCP assertions and both architecture gates passed.

### Step 1.4 — Remove repeated host error plumbing

- [x] **Scope:** `errno-in?`, the two native failure mappings, and trivial
  error wrappers in `runtime/host.rkt`.
- **Change:** simplify repeated POSIX/Windows membership tests and equivalent
  error forwarding. Keep every existing code/category and OS mapping, UTF-8
  handling, and meaningful cleanup helper. Do not redesign handles, write
  loops, close ordering, or resource registration.
- **Check:** host/file/TCP suites, including failure cleanup and partial writes.
  Review the changed host/codec path together for correctness and reading
  effort; retain only improvements. Run Phase checks, commit, and push.
- **Result (2026-09-05):** `errno-in?` now selects the existing POSIX or
  Windows number list itself, removing 13 paired/custom membership branches
  without moving any number or category. The file/network wrappers remain
  because they separate mapping from Error construction for multiple callers.
  This Step removes 11 more host lines; Phase 1 removes 41 runtime lines total.
  A scoped bughunt close-read both runtime modules and every changed branch,
  traced all nine pure request shapes, checked the prior codec cycle/canonical
  fix, and compared every OS mapping. Direct tests and checkers were skimmed
  for their interactions; unrelated code was outside scope. There were zero
  confirmed, likely, or latent findings. The full suite passed all 38 files
  and 12,298 assertions, followed by the 29-file purity proof and complete
  boundary inventory.

## Phase 2 — Simplify application glue where it earns its place

### Step 2.1 — Simplify runner validation and diagnostics

- [x] **Scope:** `runner/attalambda.rkt`.
- **Change:** remove repeated preflight or exception plumbing only where
  existing behavior is demonstrably preserved. Replace custom path work with
  an ordinary Racket operation only if it preserves the current path policy
  and diagnostics. Correct the unsupported-literal message from Nat to Rat.
  Keep current symlink/dotenv restrictions, source loading, and exit behavior.
- **Check:** `tests/runner-test.rkt` and `tests/language-test.rkt`: paths,
  links/cycles, unavailable/nonregular inputs, UTF-8/header/syntax, sanitized
  failures, version/help, and unchanged Error/Err completion. A resolver change
  that needs a new policy is omitted rather than turned into another project.
- **Result (2026-09-05):** `stop` now defaults its line and column, removing
  the repeated `#f #f` plumbing from every locationless caller without adding
  a helper; the runner remains 251 lines and is 92 bytes shorter. Its stale
  unsupported-literal diagnostic now says exact Rat and String. A filesystem
  probe showed that Racket's ordinary path simplifiers do not resolve an
  intermediate parent link, so the tested custom resolver remains. All 181
  runner and 82 language assertions passed, as did both architecture gates.

### Step 2.2 — Reduce repeated compile-time emission

- [x] **Scope:** `macros/macros.rkt` and `lang/expander.rkt`.
- **Change:** share existing bit/List emission only if a small helper in an
  existing module reduces total code while keeping use-site and definition-site
  bindings explicit. Otherwise keep the small direct implementations. Preserve
  the public prelude, one-time host injection, and generated pure terms.
- **Check:** macro/language/purity suites, public-export comparison, hygiene,
  shadowing, literal encodings, laziness, and exactly-once effects. No new
  literal/prelude module, renaming layer, or native object-language computation.
- **Result (2026-09-05, no code change):** the similar emitters require
  opposite binding contexts: function-name expansion deliberately creates
  caller-context identifiers, while language literals capture the expander's
  imports against user shadowing. Sharing them would require a cross-phase
  generic context API and increase the complete call path. The existing direct
  code stays. Macro/language tests passed 94 assertions; the preceding boundary
  and purity gates preserve exact exports, hygiene, and generated pure terms.

### Step 2.3 — Trim only useful reader and test-helper duplication

- [x] **Scope:** existing `readers/` modules and
  `tests/helpers/lazy.rkt`, `tests/helpers/values.rkt`, and
  `tests/helpers/fresh-language.rkt`, with affected callers.
- **Change:** remove concrete unused or repeated support code only when the
  whole call path becomes smaller. Keep short local helpers when sharing
  them would increase reading effort. Preserve reader output, subprocess
  isolation, staging exclusions, deadlines, cleanup, and real installed tests.
- **Check:** affected reader tests plus language/runner/distribution suites.
  Review this Phase's changed paths for hygiene, laziness, unintended effects,
  and diagnostics. No rendering, mocking, or process framework. Run Phase
  checks, commit, and push; a justified no-change result needs no extra sweep.
- **Result (2026-09-05):** ten small readers now show their one to three
  `force` applications directly, removing ten copied `lazy-apply` definitions
  and 30 reader lines; the two readers where the helper prevents difficult
  nesting retain it. `apply2` and `apply3` now live once in the already-imported
  lazy test helper, replacing 21 identical local definitions across 14 tests
  and removing 87 test/support lines net. No assertion or import edge changed;
  broader `typed-value?` sharing was rejected because it would couple unrelated
  suites to the object-value helper. Focused reader tests passed 6,263
  assertions. A Phase bughunt close-read every executable/helper change and
  mechanical removal and skimmed surrounding callers; unrelated test bodies
  were outside scope. It found zero confirmed, likely, or latent bugs. The
  Phase full suite passed all 38 files and 12,298 assertions, purity passed 29
  files, and the complete boundary inventory passed.

## Phase 3 — Reduce maintenance in checks, tests, and documentation

### Step 3.1 — Remove only demonstrably redundant boundary locks — complete

- [x] **Scope:** `tooling/check-boundaries.rkt` and its focused tests.
- **Change:** start with the copied runner diagnostic bodies and their
  duplicate checks. For each removal, name the promise, remaining enforcement,
  and behavioral test. Keep any rule still needed to restrict capability.
  No new binding-analysis mechanism or replacement of all class rules.
- **Check:** boundary/runner suites; isolated violations still fail for the
  intended reason, and an equivalent private change passes each removed lock.
  Preserve closed imports, implicit/renamed capability restrictions, sole host
  authority, exact public surfaces, and rejection of unknown source locations.
  Keep the expanded purity checker; change only mechanical references required
  by an earlier Step. A smaller blacklist is not equivalent enforcement.

**Result:** Removed the checker's copied `stop` and
`syntax-failure-reason` bodies and the exact-body comparison, deleting 40
checker lines. Those copies protected diagnostic behavior, which
`tests/runner-test.rkt` already verifies through the real command surface.
The checker still requires the exact runner definition set, imports, exports,
status definitions, input targets, entry/load shape, closed vocabulary,
capability restrictions, and repository inventory. An isolated fixture
reordered the side-effect-free operands of `stop`'s private location condition
and passed the remaining boundary rules; the old exact-body lock would have
rejected it. The boundary and runner suites passed 296 assertions, and the
complete boundary inventory passed.

### Step 3.2 — Remove superseded test machinery without losing protection — complete

- [x] **Scope:** only tests and fixtures affected by Steps 1.2–3.1.
- **Change:** remove source-copy/private-name assertions superseded by proven
  behavior or capability checks, and their unused fixtures. Reuse existing
  coverage. Approval of this plan permits those evidenced replacements;
  necessary regression tests and sole coverage stay.
- **Check:** run affected suites and a targeted isolated mutation for each
  replacement's named promise. A test that fails only from malformed syntax
  proves nothing about the intended rule. Review repaired tests freshly;
  no coverage quota, new test tier, or repeated whole-suite audit.

**Result:** Audited the affected host, codec, runner, boundary, reader, and
shared-helper tests under the project rule that tests need a named failure and
must preserve behavior, invariants, error propagation, partial application,
and laziness where applicable. The only redundant machinery was a seven-line
runner assertion that counted the private loader expression before replacing
it in a fault-injection fixture. The boundary checker independently enforces
exactly one `(dynamic-require source-path #f)` call. An isolated duplicate-call
mutation failed with `invalid-runner-entry-or-loader`, so the private count was
removed. The fault-injection fixture remains: changing the generic failure
handler to expose `exn-message` produced exactly two failures in that fixture,
proving it still catches raw-detail leakage. No other assertion was removed;
the same-layer candidates protect distinct argument precedence, conversion,
resource-lifecycle, or representation cases. The restored runner suite passed
all 180 assertions. A fresh reviewer close-read the affected checker/test diff
and rules, independently confirmed that the equivalent private `stop` change
passes while a duplicate loader call fails, and confirmed the diagnostic
fixture catches raw-detail leakage. It found no blocking defect. The reviewer
also caught an overbroad test comment: source validation is proven by runner
behavior, while the structural rule proves that the one loader call uses
`source-path`; the comment now states that exact division.

### Step 3.3 — Make the current system quick to understand — complete

- [x] **Scope:** the non-pure architecture passages in `ARCHITECTURE.md`,
  `README.md`'s repository guide, and `docs/design/host-boundary.md`.
- **Change:** give each role a short explanation and real entry points:
  host performs effects; codec converts; frontend emits/injects; runner loads;
  readers observe; checkers enforce. Remove duplicated current descriptions
  and stale phase narration. Keep pure representation reference material,
  canonical specifications, and the exact current host contracts.
- **Check:** trace claims to code. A maintainer can explain a host request and
  conversion from host/codec alone, following only relevant named functions.
  Other roles have equally direct entry points. No new documentation framework.

**Result:** Replaced the architecture's milestone-by-milestone narration and
test catalog with a task-based reading map, the five-step host path, concise
frontend/runner/reader roles, the current dependency directions, and the two
actual structural gates. Rewrote the host-boundary document around the current
Rat, Unit, and `List Byte` contract instead of retaining an obsolete contract
under a later amendment; all nine operations, bounds, results, failure codes,
byte/path rules, lifecycle guarantees, authority, and approval remain stated.
The README repository table now points directly to host, codec, expander, and
runner entry files. The three documents fell from 1,743 to 903 lines. The pure
representation/runtime-typing reference remained unchanged in this Step.
Final review later corrected three pre-existing public Nat sentences to the
implemented Rat boundary while leaving the private Nat descriptions intact.
Every local link resolves. Claims were traced to
`dispatch-request`/`perform-*`, the codec exports, pure request constructors,
the expander bindings, runner flow, reader exports, and both checker entry
points.

### Step 3.4 — Remove obsolete process narration

- [x] **Scope:** `HANDOFF.md`, `docs/ACCEPTANCE.md`,
  `docs/design/standalone-distribution.md`, and the two existing plan archives.
- **Change:** remove duplicated session instructions and stale active plans;
  retain unique release evidence, legal text, current platform constraints,
  and the deferred HTTP-parser finding in a clearly marked existing home.
  Do not archive the rejected refactor proposals into more repository docs.
- **Check:** retained facts and local links remain intact; historical records
  cannot authorize new work. No distribution script, CI workflow, release,
  support policy, or legal-byte change. Run Phase checks, commit, and push.

**Result:** Replaced repeated phase narratives with one 107-line current
acceptance map, one 297-line distribution contract/release ledger, one 132-line
completed-milestone ledger, and a 32-line active handoff. Deleted the second
plan archive after moving its unique Milestone 4 outcomes, correction record,
0.3.0 evidence, and deferred HTTP-parser finding into those existing homes.
These five files fell from 4,043 to 568 lines, removing 3,475 documentation
lines. Exact 0.2.0/0.3.0 commits, tags, artifact names, sizes, IDs and hashes;
the desktop withdrawal record; legal hashes; Racket CS 9.3 build/consumer
contract; Linux-only support; publication authority; and the bounded O(cap²)
finding remain explicit. All local links resolve, the legal bytes retain their
approved hashes, and no distribution script, workflow, release, support
policy, or legal file changed. Phase-focused boundary, runner, and distribution
tests passed 502 assertions; the full gate passed all 38 suites and 12,297
assertions, the 29-file purity proof, and the complete boundary inventory.

## Phase 4 — Verify the benefit and stop

### Step 4.1 — Fresh review of the completed changes

- [x] **Scope:** the completed non-pure diff and its direct interactions.
- **Work:** a fresh agent that did not author the changes reviews correctness,
  authority, unnecessary abstractions, and reading effort. Require evidence
  for bugs and a concrete benefit for suggested cleanup. Record close-read,
  skimmed, and unexamined scope. Zero findings is a valid result.
- **Check:** repair proven in-scope defects serially in their owning Step,
  check siblings, and obtain fresh review of repairs. Revisit only affected
  evidence; do not launch another skill chain or find work to justify a pass.

**Result:** A fresh agent close-read the complete production diff, every
changed reader/helper caller, runner/boundary changes, all rewritten non-core
documents, and the approved plan/specification; it skimmed unchanged adjacent
performers/tests and did not re-audit unrelated pure algorithms or complete
desktop harnesses. Six focused suites passed 792 assertions, the boundary
inventory passed, and purity passed all 29 production files. It found no
production correctness, purity, authority, or API regression, and confirmed
the code reduction lowers reading effort.

The review proved four bounded omissions: the runner's generic syntax fallback
lacked behavioral coverage after its body lock was removed; three retained
Architecture sentences still called public Rat boundaries Nat; the handoff
predated the Phase 3 commit; and the Linux transfer description omitted the
consumer harness itself. One invalid two-argument-lambda case now pins status
65, source location, exact fallback text, empty stdout, and sanitized stderr;
the runner suite passes 184 assertions. The three public contracts now say Rat,
the handoff names all pushed phase commits, and the transfer names archive,
checksum, and harness. A second independent close-read traced each repair to
the runner, List/Char/String implementations, and Linux transfer commands. It
found no excess scope or remaining repair finding; `git diff --check` and local
links pass. Zero confirmed findings remain.

### Step 4.2 — Final acceptance, comparison, and completion

- [x] **Scope:** verification and concise final evidence in this plan.
- **Work:** run the complete suite and both checkers; build and consume a
  clean, recorded implementation commit using the existing Racket CS 9.3
  Linux scripts and an independent consumer without Racket. Record revision,
  checksum, help/version, stdout, file/TCP/HTTP, relocation, and exit behavior.
  Preserve isolation, cleanup, notices, and artifact policy; publish nothing.
- **Check:** compare against the baseline: less non-pure implementation code,
  less maintained code overall including tests/tooling, fewer unnecessary
  functions/branches, and easier reading paths. Documentation savings cannot
  substitute for code reduction. Count new helpers and explain actual removed
  logic; do not credit formatting or relocation. Required checks pass and no
  confirmed finding remains. If those conditions fail, report the unmet goal;
  do not manufacture more changes or declare completion.
- **Close:** commit/push only the verified refactor branch and leave it clean.
  Identify any later documentation-only commit separately from the tested
  implementation commit; if it changes shipped/build inputs, repeat acceptance.
  Keep a concise completed plan and useful evidence. **Stop here.** No PR until
  Kyle reviews the completed branch and explicitly approves it. No merge,
  release, new milestone, or further cleanup, even after a generic `next`
  or skill invocation. Separate future work needs a separately named request.

**Result:** Exact implementation/test revision
`f772e8d1f87cf1df7d171476046f9986426192af` passed all 38 suites and 12,301
assertions, the expanded purity proof over all 29 production files, and the
complete boundary inventory. This includes the final review repair and the
real filesystem, TCP, HTTP, runner, language, distribution-contract, and
mutation suites. No confirmed review finding remains.

The clean revision then built with full Racket CS 9.3 from pinned image
`racket/racket:9.3-full` (image ID
`f9c540abe281413dc9e25bfbe6e35276f1a5bca1fa40213c40ac7bac6bb69c62`).
The resulting `attalambda-0.3.0-linux-x86_64.tar.gz` is 13,936,532 bytes with
SHA-256
`355cced2e6c7d8954e80404aaa53d2969329319c52446b083f6446b56141ce5c`;
it contains 11 regular files totaling 59,741,483 bytes, including two runtime
files. This is an unpublished acceptance artifact in `/tmp`, not a release.

The existing consumer passed in read-only digest-pinned
`ubuntu:24.04@sha256:561618e2c15bf2397621dd04f96926663a3b5616c189cf7e38db7e82f5c538ea`
with Racket and `raco` absent, no checkout, all capabilities dropped, and
external networking disabled. Checksum, exact inventory, permissions, legal
bytes, guide workflow, help/version, stdout, byte-exact file-example round-trip,
TCP/HTTP loopback, and relocation all passed. Launcher-failure statuses and
sanitized diagnostics were checked by the source runner suite; foundations
execution was checked by the source milestone-two acceptance suite, not this
consumer. First startup was 470 ms and relocated startup was 369 ms.

| Maintained code | Baseline | Final | Change |
| --- | ---: | ---: | ---: |
| Pure `core/` + `effects/` | 5,510 | 5,510 | 0 |
| Non-pure implementation | 2,057 | 1,986 | -71 |
| Tests/support | 13,478 | 13,398 | -80 |
| Tooling/CI | 6,731 | 6,689 | -42 |
| **All maintained code** | **27,776** | **27,583** | **-193** |
| Refactor surface excluding the pure center | 22,266 | 22,073 | -193 |

The production reduction comes from one codec conversion path replacing two
pipelines, direct host dispatch replacing seven route helpers, and ten reader
`lazy-apply` wrappers becoming direct applications. That is 16 fewer private
production helper definitions. In tests, 21 repeated `apply2`/`apply3`
definitions became two definitions in the existing lazy helper, for 19 fewer
test helpers; the one added runner scenario protects a real branch left behind
by the removed checker body lock. The checker itself loses copied private
diagnostic bodies while retaining capability, authority, import/export,
loader, vocabulary, and repository-inventory enforcement. No dependency,
runtime module, public export, representation, effect, or distribution policy
was added. The only intentional behavior change is the approved diagnostic
correction from obsolete Nat wording to exact Rat wording.

The changed planning and explanatory documents fell from 5,899 baseline lines
to 2,282 lines while adding the 206-line controlling refactor
specification. The final evidence update touches only `PLAN.md`, `HANDOFF.md`,
and `docs/ACCEPTANCE.md`, none of which enters the shipped package or Linux
archive inputs; the accepted implementation artifact therefore does not need
rebuilding. The branch is complete after that documentation-only commit is
pushed. No tag, Release, upload, merge, or pull request was created.
