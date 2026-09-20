# Release 0.10.0 candidate — branch `release-0.10.0`, awaiting Kyle

Candidate revision: the head of `release-0.10.0` (see `git log -1`), branched
from `main` `4eddf4a` after PR #11 merged the `list-case` / selectable-checker
milestone. Contents beyond 0.9.0: the `--check` report trim (PR #9), the
file-run diagnostics and robustness fixes (PR #10), the callable-constraints
checker patch (`9069d11`), `list-case` and `--check=hm` / `--check=simple`
(PR #11), the cold-review fixes, and the version bump to 0.10.0 with draft
notes in `docs/releases/0.10.0.md`.

What is done and verified (all in a disposable Racket CS 9.3 container as uid
1000 over this checkout, host Racket 8.10 unused):

- Cold review of PR #11 by a fresh agent: no must-fix; the two should-fix
  items and two notes are fixed on this branch (PLAN.md records them).
- Candidate archive built from a clean clone of `main` `4eddf4a` and the
  isolated Ubuntu consumer test passed on the host; this validated the changed
  build and consumer scripts (help text, `--check` acceptance).
- Complete suite and both gates on the branch's final source: all 106 test
  files, purity check (40 production files) and boundary check passed,
  wall time 1592 s. The commit that records this changes documents only.

What awaits Kyle, in order:

1. Merge `release-0.10.0` to `main` (PR opened from this branch).
2. Build the release archive from the merged `main` commit in a clean clone:
   `tooling/build-linux-distribution.sh OUTPUT_DIR` inside the container, then
   `tooling/test-linux-distribution.sh OUTPUT_DIR` on the host.
3. Tag `v0.10.0` on that commit, upload the archive and `SHA256SUMS`, publish
   the GitHub release, then replace the pending paragraph in
   `docs/releases/0.10.0.md` and the README release line with the real URL and
   timestamp, and verify the public download with the consumer test.

To reproduce the checks: `docker run -d --name attl -v "$PWD":/work -w /work
racket/racket:9.3-full sleep infinity`; as root in it
`racket tooling/prepare-racket-runtime.rkt --apply && chown -R 1000:1000
/usr/share/racket && apt-get update -qq && apt-get install -y -qq python3 git`;
then as `-u 1000:1000 -e HOME=/tmp/h`: `raco pkg install --batch --scope user
--link --name attalambda --deps fail --no-docs --fail-fast /work` and
`./run-all-tests.sh` (about 30 minutes).

# Static checker patch — callable constraints through unknown arguments

Applied on `main` on 2026-09-19 after the diagnostics/robustness merge (PR #10).
The 0.9.0 release below is unchanged: no version bump, tag, or binary. The
published 0.9.0 checker still has this gap.

Confirmed before the change: `(def bad f = (add (f (unwrap-ok (make-ok 1))) f))`
reported PARTIAL with status 2 and no conflict, while the same two uses in the
other order reported FAIL with status 1. The application branch for an operator
whose type is an established type variable required an established argument
type, so an unproved argument left the operator unconstrained. The branch now
requires the operator to be an arrow whose domain is the argument type when
known and a fresh variable otherwise. The application's own result stays
unproved through the joined proof, so no unknown return type, no `unwrap-ok`
payload, and no definition signature is established by this rule. A
data-restricted operator meeting the arrow remains an unsupported-domain gap.
Limits: diagnostics are still not order-independent in general; a failed
equation is rolled back rather than recorded, exactly as before.

Regressions: `tests/static-incomplete-callables-test.rkt` (C01–C06 conflicts,
N01–N05 gaps) and `tests/static-cli-test.rkt` (real `--check` runs, the
`CHECK-MUST-NOT-RUN` marker, a good sibling keeping its signature). The five
public example reports are byte-identical before and after.

# AttaLambda 0.9.0 — published; public download verified

[Release 0.9.0](https://github.com/kserrec/attalambda/releases/tag/v0.9.0) is
published and latest, at `2026-09-18T06:25:52Z`, release ID `391256649`. PR #8
is merged. Optional static checking is complete; the actual downloaded Linux
archive passes the complete isolated consumer. Linux x86-64 remains the only
public binary target. This release grants no authority for a later version.

## Source and verification

The exact build/tag commit is `0960a79ae797007da850a6d6f1c449482d333614`, tree
`af74508c74cc7f3ca710cb0566914c67ab56c58a`. Annotated tag `v0.9.0` has object
`ad7fa3a6b5e31a599e7f1ef5a4aaadf8a343d0ba`. The later publication record changes
documents only; it is not the artifact's source. Local main was fast-forwarded
to the verified merge before that record.

Local release verification passes 661 focused assertions and the full 104
Racket files / 26982 reported tests, 49 Python terminal methods, purity over 40
production modules and the complete boundary gate in 29m42s. All 226 executable,
packaging and workflow hashes match the tested snapshot and clean build clone.
All ten exact-head jobs pass in [PR CI](https://github.com/kserrec/attalambda/actions/runs/35311618086)
and [merged-head CI](https://github.com/kserrec/attalambda/actions/runs/35312808000),
with the same source counts/gates. Neither run retains temporary native artifacts.
The independent review below remains the scope/limitations record.

## Published assets and consumers

| Item | Identity |
| --- | --- |
| Archive | `attalambda-0.9.0-linux-x86_64.tar.gz`, 19,873,515 bytes, asset `571975742` |
| Archive SHA-256 | `1dc9493bf041463fa9ec7226af2fbe5f078a43e4d707f4f4e2d502f4dccf8186` |
| SHA256SUMS | 103 bytes, asset `571975740` |
| SHA256SUMS SHA-256 | `dc8e14364c9cc17d94822085ce07cafc5c2b0bff0880c0a6edb4f5781e3d2138` |
| Internal manifest SHA-256 | `ecd5ca1fef96e9acbbbb8133691b47ae512d0a6b06678330547448a020712afb` |

The 11-file archive includes two runtime files and no Python. The transferred
no-Racket consumer passes static checking, prior API/input/guide/dependency
checks and all 25 terminal methods at both paths in 64.910s and 59.393s.
Authenticated draft downloads match the verified files. Fresh unauthenticated
public downloads return HTTP 200 and match both hashes. The actual public
archive passes the same complete consumer, with terminal groups in 48.968s and
48.750s. Build/consumer containers and consumer transfer directories are removed.
Seven older releases, fourteen assets and seven annotated tags are unchanged.
Original pre-release candidates and all verification evidence are retained.

## Evidence and final record

Evidence root: `/tmp/attalambda-090-release-g5_0101v/`.

- `release-result.json`, `release-full.log`, `focused.log`: source checks and
  tested input identities. `pr-ci.json`, `merged-ci.json` and matching logs/results
  retain full remote run/job evidence and cleanup.
- `release-source.json`, `build.log`, `archive-result.json`, `archive-manifest.txt`:
  exact clean build clone and artifact identities. The archive/checksum are under
  `release-archive-wt2rwn29/`; the clean build clone is `build-source-kmmsijqa/`.
- `archive-consumer-result.json` and `public-consumer-result.json`, plus matching
  logs, retain each actual transferred digest, container/image identity, timing
  and cleanup. Authenticated copies are in `draft-download-qgeu8xd2/`; the actual
  tested public copies are in `public-download-wpb0ho4y/`.
- The build image is `sha256:5366fd60f701ca1cbf5172c17bfa1150ca8a5e7500c3a9d19f5bbca4236be59c`,
  with corrected Racket CS 9.3, Python 3 and Git. Archive/public consumer images
  are `sha256:e813247f535bfc2f48d8bf860265365a6542a896b8a70e68c2d05d6958190f1e` and
  `sha256:161afecb3a081b821e28eee3a43ac8dadc55b6fe52924ea47749335600982bc1`.
  Consumers use pinned Ubuntu 24.04, test-only Python, non-root UID 65534,
  read-only roots and no external network. The owner's runtime is untouched.
- `state.json` records remote side effects. `published-release.json`, download
  receipts and preservation snapshots retain the release evidence.
- `final-result.json` tracks the publication-record commit, push, exact-head CI,
  final preservation check and clean Git. It stays outside the worktree so recording
  a commit's own identity does not change that commit. Current main checks are
  also visible in [GitHub Actions](https://github.com/kserrec/attalambda/actions/workflows/tests.yml).

The final delivery action is to commit/push this documentation-only record,
verify its exact-head CI and clean main, and complete that external receipt.
Do not rebuild or retag the published archive to include publication records.

---

# Independent static-checker review — verified local candidate complete (historical)

The user-approved focused independent review found four defects in the original
candidate. All four are corrected, with retained regression drivers and a fresh
cold review finding no additional proved defect. The [review record](docs/static-checking-independent-review.md)
gives exact scope, causes, corrections and evidence limitations.

The full corrected Racket CS 9.3 run passed 104 Racket test files / 26981 reported
tests, 49 Python terminal methods, purity over 40 production modules and the
complete source boundary gate. All 225 executable/packaging input hashes match
the tested snapshot. All five public example reports are identical to the
original candidate. Evidence: `/tmp/attalambda-static-review-5du21rkr/`, especially
`review-full.log`, `review-result.json`, `corpus-results.json`, and `cold/report.md`.

## Current source and candidate

The clean tested/build source is
`7d577444bca5b8c101125d7cbf10e638a6e26cd0`, tree
`139ac8acd09c5087fc88124d4f8567b390bc02a5`, on `optional-static-checking`.
The clean build clone is
`/tmp/attalambda-static-review-5du21rkr/build-source-_qza4s2b`.
All 225 tested executable/packaging inputs match that clone. The normal builder
ran without `--allow-dirty`; original and clone remained clean.

Current archive:
`/tmp/attalambda-static-review-5du21rkr/candidate-6cba9qzj/attalambda-0.8.0-linux-x86_64.tar.gz`

SHA-256:
`a39febf5db4c7e6b2871252e52d863d903c04d3e62ad01377252e9a7690b0828`.
Size: **19,873,969 bytes**. The sibling `SHA256SUMS` verifies it. This supersedes
the original local candidate for use; the old archive remains preserved.
Version metadata stays 0.8.0 and the guide explicitly identifies the archive as
an unpublished optional-static-checking candidate. Public 0.8.0 is unchanged.

`candidate-build.log` and `candidate-consumer.log` both record exit 0. The
transferred Ubuntu consumer has no Racket/raco or source checkout, and uses a
read-only root, UID/GID 65534, dropped capabilities and loopback-only networking.
The static checker passes at both paths, including the new regression cases,
failed output and interrupted delivery. All 25 terminal methods pass at each
path (79.020s and 80.773s), as do public API, guide, file/network, input and
relocation checks. Original, transferred and final archive digests match.

The pinned consumer base is
`ubuntu:24.04@sha256:561618e2c15bf2397621dd04f96926663a3b5616c189cf7e38db7e82f5c538ea`;
the actual prepared image is
`sha256:3ded025a96a0143ab876d2a0ccd1bbdda37c5e3dbe4b26b23f88a031c8ff46f7`,
with test-only Python 3.12.3. The build uses the same isolated Racket CS 9.3
image and reviewed dependency corrections recorded below. The owner's runtime
was not changed. Remote CI and native macOS/Windows execution were not run;
Linux x86-64 remains the supported binary target.

## Completed endpoint and cleanup

All four findings are fixed; none is deferred. The fresh cold review has no open
finding. Full source and exact archive validation are complete. The owned
`attalambda-static-review` container was stopped and removed; consumer
`4695406840e1` and transfer directory `/tmp/attalambda-linux-transfer-AshSaf` are
verified absent. Builder staging is cleaned by its normal exit trap. Logs,
snapshots, build clone, images and both verified archives remain available.

This final delivery record changes only PLAN.md, HANDOFF.md, docs/ACCEPTANCE.md
and docs/static-checking-independent-review.md. Its later commit is not the
archive's source; its identity and clean status are recorded externally in
`state.json` and `candidate-result.json`. The unchanged local main remains
`f6938b286329532230be210de0eaaa398286d38a`. No push, PR, merge, tag, release-asset
replacement or publication occurred. No owner input or unfinished authorized
implementation/review step remains. Further remote or release work is separate.

---

# Original optional static-checking candidate (before independent review)

The entire revision-3 milestone is implemented, tested, self-reviewed, built and
verified as a local Linux candidate. All six phases are complete. There is no
unfinished implementation step, blocker, or required owner action. No push, PR,
merge, tag, release-asset replacement or publication occurred. Public 0.8.0 is
preserved and does not contain this feature.

## Final source and delivery identities

- Workspace: `/home/serrecchia/Projects/attalambda`, branch
  `optional-static-checking`.
- Base and unchanged local main: `f6938b286329532230be210de0eaaa398286d38a`.
- Final tested/build source: `576d8837797f254fb068d19fd839ea1174e28151`.
  This clean local commit contains every executable, test, consumer and embedded
  guide input. Earlier phases also have verified local commits, recorded below.
- Clean build clone:
  `/tmp/attalambda-static-implementation-mmgdshl_/build-source-n7a4gxle`.
  Its tree is `4fda0111607004aeb10f77413f129e35cb5b540a`. Original and clone
  HEAD/clean state were verified before and after building; all 223 tested
  executable/packaging input hashes matched. No `--allow-dirty` was used.
- This later delivery record changes only PLAN.md, HANDOFF.md and
  docs/ACCEPTANCE.md. It is not the archive's source. Its own commit identity and
  final clean workspace status are retained in the external `state.json` below
  and the completion response; no commit tries to contain its own hash.

Evidence root: `/tmp/attalambda-static-implementation-mmgdshl_/`.
`state.json`, `phase5-result.json`, `candidate-source.json`,
`candidate-result.json` and `candidate-build-manifest.txt` retain machine-readable
identities/results. Earlier baseline evidence remains in
`/tmp/attalambda-static-phase0-q0w_ycsc/`.

## Verification and review

The final `./run-all-tests.sh` ran through `runuser --login attatest` in the
isolated container, from `/evidence/source`, with a 2400-second outer deadline.
It exited 0: **102 Racket test files, 26973 reported Racket tests, 49 Python
terminal methods**, expanded purity over 40 production modules, and the complete
source inventory/boundary gate. `phase5-full.log` and `phase5-result.json` retain
the actual final run and 223 matching input hashes. Focused logs `step-1.1a.log`
through the recorded Phase 5 steps distinguish unit/contract/CLI checks from
full-suite and artifact evidence; `step-5.3-final.log` passes 223 distribution
checks plus both structural gates. Baseline/earlier checkpoints below are
historical, not substituted for the final run.

Testing/building used Linux x86-64, Racket CS 9.3, Python 3.13.5 and Git 2.47.3,
in image `sha256:5366fd60f701ca1cbf5172c17bfa1150ca8a5e7500c3a9d19f5bbca4236be59c`.
The existing reviewed promise/Expeditor corrections were applied and checked
inside the disposable runtime using `tooling/prepare-racket-runtime.rkt`.
That image is unpatched; future containers must repeat the recorded apply/check
preparation. The owner's Racket 8.10 installation was not changed. No dependency
or version metadata was added or updated.

Reviews are explicitly **self-reviews**, not independent reviews or a formal
soundness proof. `phase5-review.md` records the fresh final source review; all
confirmed earlier findings have corrections and retained tests. The substantive
kernel corrections were simultaneous substitution and closing a native-capability
vocabulary leak. Temporary test/receipt mistakes and their diagnosed corrections
are recorded in PLAN.md. No finding remains open. The A01–A26 evidence mapping
is in [docs/ACCEPTANCE.md](docs/ACCEPTANCE.md).

The [contract audit](docs/static-checking-contracts.md) accounts for all 129
public values: 106 complete, 23 explicitly partial, zero pending. The
[unchanged five-example corpus](docs/static-checking-corpus.md) has two full
passes and three partial results, no conflicts: hello/stdout each 3/3 checked
expressions; foundations 126/138, file-round-trip 24/32, http-server 134/199.
All 13 primary gap regions and dependency explanations are retained. The V1
limits remain deliberate: no variant/nonempty/range refinement, recursive types,
polymorphic recursion, or higher-rank typing; partial built-ins/raw host are not
laundered through aliases or callbacks. Checking never evaluates the program and
does not prove termination, external success, or absence of deliberate Error.

The user-directed deviation is autonomous continuation between verified passes;
oversized steps were subdivided without dropping checks. The required early
embedding probe, full corpus, clean build and actual consumer were completed.
No post-milestone language feature, public annotation syntax, or runtime typing
change was introduced.

## Exact standalone candidate

Archive:
`/tmp/attalambda-static-implementation-mmgdshl_/candidate-g7g7_p8u/attalambda-0.8.0-linux-x86_64.tar.gz`

SHA-256:
`80c08ff21090d3b725a5c6df50b56783c5f434b5129dd60fc423c2abe35a3816`

Size: **19,870,393 bytes**. Its sibling `SHA256SUMS` verifies that exact file.
The guide clearly labels this an unpublished optional-static-checking candidate;
0.8.0 metadata is retained as required. Its BUILD-MANIFEST source is the clean
`576d8837797f254fb068d19fd839ea1174e28151` revision, not this later record.

`tooling/build-linux-distribution.sh /evidence/candidate-g7g7_p8u` ran from the
clean clone in the corrected isolated runtime and exited 0 (`candidate-build.log`).
The clone's `tooling/test-linux-distribution.sh` then ran on that host output
directory with task-owned Docker configuration; it exited 0
(`candidate-consumer.log`). Original, transferred and final archive digests match.
The log ends with `consumer_acceptance=passed`, and records
`static_checking_acceptance=passed-at-both-paths`. All 25 CLI/transcript methods
passed before and after relocation (64.927s and 67.255s). Static statuses,
coverage/signatures, invalid sources, no effects, real `/dev/full` failure,
interrupted report delivery, guide/public API, file/network/exit, terminal input,
and relocation all passed using the delivered executable.

Consumer: Ubuntu 24.04 pinned to
`sha256:561618e2c15bf2397621dd04f96926663a3b5616c189cf7e38db7e82f5c538ea`;
actual prepared image
`sha256:f79d9f4012586a4c571e94f0dbcf295cc85a55e9e0f1d79e9f71f9ef2c4c9644`.
It uses test-only Python 3.12.3, UID/GID 65534, a read-only root, dropped
capabilities and no external network. Racket/raco and a source checkout are
absent; Python is not shipped in the archive. Native macOS/Windows runs were
not performed. Linux x86-64 remains the only supported binary target.

## Cleanup and endpoint

The owned implementation container `attalambda-static-implementation` was
stopped and removed. Consumer `1c462712afb9` and its transfer directory
`/tmp/attalambda-linux-transfer-SrsKIy` are verified absent. The builder cleaned
its own staging directory. Logs, source snapshots, images and the verified
candidate remain available; unrelated resources were not touched. Final record
checks compare input hashes, links, whitespace, unchanged local main and clean
Git state. The authorized endpoint is complete locally. A later remote or
publication action would be a separate assignment.

## Implementation checkpoints (historical)

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
and Git history: `61a87c2ee56c3dd5e74ebf3173f6336f1ce8ff5e`. Phase 5's complete
five-example corpus is measured unchanged (hello/stdout full, three documented
partial files, no conflicts), with all primary reasons retained in
`docs/static-checking-corpus.md`. README/API/architecture/guide/distribution/
acceptance documentation now distinguishes this unreleased work from public
0.8.0. The new consumer logic passed against the real source launcher, including
`/dev/full` and interrupted pipe delivery; this is not standalone acceptance.
Steps 5.1–5.4 source checks passed. The final full suite exited 0 with 102 Racket
files, 26973 reported tests, 49 Python methods, purity over 40 modules, and the
complete boundary inventory. `phase5-result.json` verifies 223 executable and
packaging inputs match the tested snapshot; `phase5-review.md` records fresh
self-review with no open finding. No independent review is claimed.
At this source checkpoint, the next steps were the clean local source commit,
exact build and transferred no-Racket consumer; all are now complete above. The
evidence directory's `phase5-notes.md` retains the build/delivery orientation;
its earlier proposed items must be checked against actual completed work.
Autonomous continuation completed the requested local candidate.
The isolated container used for these checkpoints was `attalambda-static-implementation`,
with source/evidence at `/tmp/attalambda-static-implementation-mmgdshl_/`.
Its `sync.py` copies only explicit non-dotenv source paths; use it before tests.
Tests ran through `runuser --login attatest` inside that container, with working
directory `/evidence/source`. It has now been removed. The owner's Racket
installation was not modified.

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
