# Optional static checking — autonomous milestone in progress

Kyle explicitly authorized continuing from one verified pass to the next on
2026-09-17 without waiting for another `next`. Complete the whole specified local
candidate autonomously; stop only for an owner-dependent blocker or serious
unresolved doubt. The next skill's one-pass stop is overridden. Remote/release
actions remain outside this assignment. Phase 0 is committed as `8bde48d`;
Phase 1 passed its full checkpoint: 75 Racket files, 26879 reported Racket tests,
49 Python terminal methods, purity over 40 modules, and complete source boundaries.
The source view retains binding identity, exact source accounting, let/rec
boundaries, and locations without evaluating user code. Its real embedded driver
works after hiding both staged sources and the isolated package installation.
The checkpoint self-review has no open finding; no independent review is claimed.
`phase1-full.log` and `phase1-result.json` preserve results and executable-input
hashes. Phase 1 is committed as `20b6241c4868fada5930376315a5cce47d0a7aeb`.
Phase 2 Steps 2.1–2.4 are complete: structural types,
separate proof records, simultaneous substitution, fresh instantiation,
eligible generalization, finite unification, recursive data restrictions, and
deterministic display. `step-2.4.log` records 165 focused/kernel/boundary checks
and the complete boundary gate. A composition probe found double substitution;
the simultaneous replacement correction is covered by bounded equations.
The kernel self-review has no open finding. Step 2.5a also passed: the single
catalog contains audited Rat/Bool/if, division/Result, partial unwrap, and Error
rendering seeds; other real exports are explicitly pending. `step-2.5a.log`
records four catalog/boundary cases, the complete boundary gate, and 3519 focused
existing runtime checks. A catalog label initially let the vocabulary gate admit
native exit; inert string labels and a retained mutation regression resolved it.
Steps 2.5b–2.9 also passed elementary, lexical/module, recursion, sugar, and gap
propagation checks. All 18 seed pilot fixtures matched expectations, including
C01/C07/C01 repeated-process equality. The measured intermediate results are in
`docs/static-checking-pilot.md` and evidence `pilot-results.json`; the final
focused run is `step-2.9-final.log`. Checkpoint 2 passed the full suite with 87
Racket files, 26919 reported Racket tests, 49 Python methods, purity over 40
modules, and complete source boundaries. `phase2-result.json` verifies 191
executable input hashes against the tested snapshot. Bounded nested/application,
independent-definition, and 100-alias probes repeat identically with exact counts
(`phase2-robustness.log`). Fresh self-review has no open finding. Phase 2 closes
with local commit `de39c732bf7cf571689fdf3677b094b9d67bc1ba`.
Phase 3 Steps 3.1–3.8 also passed their focused checks and gates. All 129 actual
public value exports now have audited entries: 106 complete, 23 partial, zero
pending. `docs/static-checking-contracts.md` and `catalog-results.json` retain
shapes, reasons, implementation and test locators. Full analysis is covered by
real input/file/network/exit non-execution observations. The complete Section
3.2 example and all semantic C01–C18 fixtures meet their fixed expectations;
combined alias/callback/Error cases and retained bounded robustness tests pass.
`step-3.1.log` through `step-3.8.log` record the focused runs. No core/effects/
runtime implementation changed. Checkpoint 3 passed: 96 Racket files, 26944
reported Racket tests, 49 Python methods, purity over 40 modules, and complete
boundaries. `phase3-result.json` verifies 201 executable inputs match the tested
snapshot; `phase3-review.md` records a fresh self-review with no open finding.
No independent review is claimed. The phase closes with a local commit whose
identity is `76c2c8b`, retained in the external `state.json` and Git log.
Phase 4 Steps 4.1a–4.3 passed their focused checks: exact accounting, safe reports,
the real `--check FILE.attl` status matrix, failed writes/flushes, interruption,
resource cleanup, and observable CLI non-execution. Logs are `step-4.1a.log`,
`step-4.1b.log`, `step-4.2a.log`, `step-4.2b.log`, and `step-4.3.log`.
The public command passed Checkpoint 4: 102 Racket test files, 26967 reported
Racket tests, 49 Python terminal methods, purity over 40 modules and complete
boundaries. `phase4-result.json` verifies 218 matching executable inputs;
`phase4-review.md` records fresh self-review with no open finding, not an
independent review. The local phase commit identity is in external `state.json`
and Git history. **Next: Phase 5 corpus, documentation, final review, exact clean
build and transferred consumer.** The evidence directory's `phase5-notes.md`
contains read-only orientation, not completed Phase 5 work.
Continue autonomously;
do not wait for `next`.
The reusable isolated container is `attalambda-static-implementation`,
with source/evidence at `/tmp/attalambda-static-implementation-mmgdshl_/`.
Its `sync.py` copies only explicit non-dotenv source paths; use it before tests.
Run tests through `runuser --login attatest` inside that container, with working
directory `/evidence/source`. The owner's Racket installation is never modified.

## Completed Phase 0 baseline record

Branch: `optional-static-checking`. Base and fully tested executable source:
`f6938b286329532230be210de0eaaa398286d38a`. Phase 0 adds only the saved revision-3
specification, scoped append-only canonical amendments and index hashes, and the
active PLAN.md/HANDOFF.md records. Executable code, tests, build scripts, package
dependencies, version metadata, README/API, and examples remain byte-identical.
The checker is not implemented yet. Historical records below retain their bytes.

**Next unfinished step: 1.1a — add the expansion-only preparation seam.**
Follow the complete Work/Check requirements in PLAN.md and
[the supplied specification](docs/optional-static-checking-spec.md). Use the
validated source snapshot and existing restricted reader in a fresh namespace.
Do not reuse `prepare-entry`: it expands, evaluates, and instantiates user code.
Classify each new private helper and exact import direction in the same step.
The later source-analysis view and executable-embedding probe must precede
inference. Phase 0's counterexample expectations are fixed before implementation.

Kyle authorized implementation and, on resumption, the isolated Docker image
with Python 3 and Git. Do not request the same permission again. Work remains
local-only: verified local phase commits are authorized, but no push, PR, merge,
tag, asset replacement, or publication. Do not change VERSION or imply that the
published 0.8.0 binary includes optional checking. The Phase 0 commit's exact
identity is in the final response and `/tmp/attalambda-static-phase0-q0w_ycsc/state.json`.
If that temporary receipt is gone, inspect the current branch/log and PLAN.md;
do not reconstruct or repeat historical release actions.

## Environment and evidence

Prepared image:
`sha256:5366fd60f701ca1cbf5172c17bfa1150ca8a5e7500c3a9d19f5bbca4236be59c`.
Its base is the verified full Racket CS 9.3 image
`sha256:f9c540abe281413dc9e25bfbe6e35276f1a5bca1fa40213c40ac7bac6bb69c62`.
Python is 3.13.5; Git is 2.47.3. Docker client bookkeeping was confined to the
task's writable /tmp directory, resolving the earlier sandbox build blocker
without elevated execution. The owner’s installed Racket 8.10 is untouched.
Reuse the image, with fresh agent-owned source snapshots that exclude every
dotenv variant; do not use the old baseline snapshot to test later source edits.

The image does not bake in the existing dependency corrections. Inside each
disposable container, apply/check them before testing; never apply them to the
owner's runtime. The completed baseline used these exact commands at the
unchanged snapshot path `/evidence/baseline-unprivileged`. Root performs only
the disposable container preparation; package setup and tests run as its
unprivileged UID/GID 1000 user:

```sh
racket --version
python3 --version
git --version
racket tooling/prepare-racket-runtime.rkt --apply
racket tooling/prepare-racket-runtime.rkt --check
raco pkg install --batch --scope user --link --name attalambda --deps fail --no-docs --fail-fast /evidence/baseline-unprivileged
raco make tests/runner-test.rkt
raco test tests/runner-test.rkt
./run-all-tests.sh
```

The full run exited 0: 69 Racket files, 26845
reported Racket tests, 49 Python terminal methods, expanded
purity over 40 production modules, and complete source boundaries. The phase is
record-only, with identical executable/test inputs and separately verified final
documentation. No production unit or test assertion was added.

Evidence directory: `/tmp/attalambda-static-phase0-q0w_ycsc/`. Retain
`baseline-unprivileged.log`, `baseline-result.json`, `baseline-input-hashes.json`,
`environment.log`, `preflight.json`, `documentation-verification.json`, and
the final `state.json`. `runner-unprivileged.log` is the focused launcher pass;
`runner-unprivileged.sh`, `prepare-unprivileged.sh`, and
`unprivileged-preparation.log` record the test sequence and user setup. The test
user owns the disposable Racket installation for dependency bytecode rebuilding.
The first prepared run failed because root bypassed
an unreadable-file fixture's permissions; a direct probe established the cause.
PLAN.md also records the unsuccessful setup attempts
without relabeling them as successful baseline runs. The original uploaded spec
SHA-256 is `56aa3e0e8ef7688b439168e8f382698dcafa9e8f043097241fb29f588299f6c0`;
its repository copy matches exactly. Canonical preceding bytes and index hashes,
39 step IDs, 22 counterexample mappings, local links, change scope, and history
preservation pass the phase's document check.

Consumer prerequisites pass for existing image
`sha256:dabaae31057cbc79baf7e2afa65b8c8cfd378b5013e4e8a95a520265fc794803`
with Python 3.12.3, no Racket/raco, and real pseudo-terminal creation. This is
not standalone artifact evidence. No static candidate archive, completed contract
inventory, measured corpus verdicts, or native macOS/Windows checks exist yet.
All remain their original later-phase gates. Review at this checkpoint is
self-review only; no independent review is claimed and no finding remains open.
Owned containers are removed. The toolchain image and isolated evidence snapshot
are retained for resumption; no program/source resource is running.

The previous temporary release receipt was absent; current main's ten passing
CI checks, publication-only delta, and public tag/release/asset metadata were
verified instead. That reconciles historical release state only. Its old
next-step wording below grants no authority for more release work.

---

# Historical handoff — published AttaLambda 0.8.0

# AttaLambda 0.8.0 — published release handoff

## Outcome and resumption

[AttaLambda 0.8.0](https://github.com/kserrec/attalambda/releases/tag/v0.8.0)
is published, latest, and verified from a fresh unauthenticated public download.
Kyle explicitly authorized merge, rebuild/verification, tag, publication and
public-download verification with “lets do it” after those actions were
explained. This superseded the candidate-only stop for 0.8.0 only. No new
feature, version, public platform or other publication is authorized.

**Read `/tmp/attalambda-080-release-state.json` before taking another action.**
It records completed effects and the exact next unfinished step. Publication
and public-copy acceptance are complete. The remaining delivery bookkeeping is
independent review and verification of these publication documents, commit/push
on main, and the resulting exact-head CI/review and clean Git state. The
post-commit receipt records the actual documentation commit and closes with
`status=complete` and no unfinished step. This document cannot contain its own
future commit hash; do not create recursive evidence commits. A complete receipt
means there is no release work to repeat.

If that local receipt is unavailable in another checkout, verify current main's
CI and that its delta from the tagged source is confined to the publication
files below. The public tag, asset digests and release ledger preserve release
identities independently of temporary local logs.

## Exact public identity

| Item | Value |
| --- | --- |
| Release ID and publication | `389458950`, `2026-09-15T20:32:24Z` |
| Unsigned annotated tag | `v0.8.0`, object `8628ca652e7ebf9ff3932d332fc57b611e3fd023` |
| Tagged clean merged/build commit | `f309199baa170ba5b12ff6b18b60dc49c114a8a1` |
| Build tree | `0ed67ac08a6f0fc2696741791e272b407d30f5c6`, identical to reviewed PR head `fd8bafa4b2c38d67046febe44b250e8c82a927f8` |
| Archive | `attalambda-0.8.0-linux-x86_64.tar.gz`, 19,602,535 bytes, asset `566456157` |
| Archive SHA-256 | `f1b8b49ba659485e089ffcf38d1d5999016131de65e21177bb922fa86013d3fc` |
| Internal manifest SHA-256 | `359b53bfca5c0cd11ed42f5528c3e8ea2bb60093b895d962cb45c689eeb3afc9` |
| Sibling SHA256SUMS | 103 bytes, asset `566456156`, SHA-256 `9129165ef63481b39a35a47035ab7bff72e194427e7811ef179481639a8d4fde` |

PR #7 is merged. All ten [merged-head CI jobs](https://github.com/kserrec/attalambda/actions/runs/35017215218)
pass: 69 Racket test files / 26,845 assertions, 43 shared terminal methods in
48.887s, 6 visual methods in 3.627s, 40 pure production modules and complete
boundaries. These results belong to the tagged build; the receipt separately
identifies the later documentation commit's checks.

## Artifact and public-download evidence

Build directory: `/tmp/attalambda-0.8.0-release/`; its `build-report.json`
and `/tmp/attalambda-080-release-build01.log` preserve provenance and cleanup.
Archive inventory: 11 regular files, two runtime files, 68,881,444 unpacked
regular-file bytes. Exact local consumption passes all 25 CLI/transcript
methods once at each path in 99.417s and 57.933s:
`/tmp/attalambda-080-release-consumer01.log` and `.json`.

Draft upload and authenticated-download identity are recorded in
`/tmp/attalambda-080-draft-verification.json`. Successful draft creation was
initially unavailable through the by-tag API; authenticated listing found the
single exact draft, then immutable-ID reads verified it. No second draft or
overwritten asset was created.

Fresh public files in `/tmp/attalambda-0.8.0-public-download/` came from the
public v0.8.0 asset URLs with HTTP 200, no authentication, and `curl -q`
to disable personal configuration. Both hashes match the verified originals.
The actual downloaded archive passes the unchanged isolated consumer: all 25
methods at both paths in 52.529s and 59.059s, runtime input and binding snapshots,
guide/APIs, file/TCP, exit and relocation. Logs/receipts:
`/tmp/attalambda-080-public-consumer01.log`, `.json`,
`/tmp/attalambda-080-public-download-verification.json`, and
`/tmp/attalambda-080-public-final-verification.json`.

The initial wrapper attempt stopped before any container because host umask
002 produced mode 0664 rather than its required 0644. Only group-write on those
two owned files was removed; bytes, driver, checks and deadlines are identical.
Its failed receipt is preserved at
`/tmp/attalambda-080-public-consumer01-precondition-failure.json`.
The later full pass does not relabel that failed precondition.

All release builder/consumer containers and transfer directories are removed.
Six earlier releases, twelve assets and six tags retain their saved identities,
metadata and digests. The final public-verification receipt binds latest/tag
readbacks and preservation checks. Never recreate this release, retag, replace
assets or substitute the pre-merge candidate archive.

## Runtime, commands and independent review

Build image: `racket/racket:9.3-full@sha256:f9c540abe281413dc9e25bfbe6e35276f1a5bca1fa40213c40ac7bac6bb69c62`.
Consumer image: `sha256:dabaae31057cbc79baf7e2afa65b8c8cfd378b5013e4e8a95a520265fc794803`,
prepared from pinned Ubuntu 24.04 with Python 3.12.3 standard-library tooling.
The consumer has no external Racket or checkout; it runs without external
networking, as a non-root user, with a read-only root and bounded resources.
Terminal tests use C.UTF-8; surrounding archive byte checks retain C.

Completed commands were `python3 /tmp/attalambda-080-release-build01.py`,
`python3 /tmp/attalambda-080-release-consumer01.py`, and
`python3 /tmp/attalambda-080-public-consumer01.py`, each with the full tagged
build SHA above as its only argument. These reviewed temporary orchestration
drivers preserve clean/expected-source checks, manifest/harness hashes,
420-second build and 900-second consumer bounds, and nested cleanup.
Do not rerun into existing output paths.

Independent reviews, with no outstanding findings:

- Source: `/tmp/attalambda-phase10-independent-review.md` and
  `/tmp/attalambda-phase10-closure-review-3ae3926.md`.
- Release preparation:
  `/tmp/attalambda-080-release-preparation-review-nizs3gbm/review.md`.
- Exact clean merged artifact:
  `/tmp/attalambda-080-release-artifact-review-c3bw_6tv/review.md`.
- Actual public download and cleanup:
  `/tmp/attalambda-080-public-review-1tngp_s6/review.md`.
- Publication-document and final-head reviews: paths/hashes in
  `/tmp/attalambda-080-release-state.json` after completion.

Phase 12 changes only README.md, docs/API.md, docs/releases/0.8.0.md,
docs/ACCEPTANCE.md, docs/design/standalone-distribution.md,
docs/design/host-boundary.md, ARCHITECTURE.md, AGENTS.md, PLAN.md and HANDOFF.md.
Canonical specifications, the saved interactive contract, product source, tests,
dependencies, runtime patches and builder/consumer scripts retain their bytes.
These later records do not change the tagged archive's provenance.

The earlier candidate receipt `/tmp/attalambda-interactive-final-state.json`
points to this release continuation. Its build from `3ae3926` and candidate-only
authority remain historical. The former handoff is saved at
`/tmp/attalambda-080-handoff-before-release-record.md`.

Known limits: raw-term printing is unspecified (use `:echo off`); demanded
effects cannot roll back; old closures may retain bindings until unreachable
or reset. Linux x86-64 is the sole supported public binary target. Python is
test tooling only and absent from the archive. Never inspect dotenv files,
modify personal/system runtimes or overwrite unrelated work. Git mutations
use separate approved commands.
