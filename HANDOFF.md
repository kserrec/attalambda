# Interactive AttaLambda — Phase 9 verified, Git write authorized

## Authority and exact next step

Kyle explicitly authorized the previously rejected Git metadata write and
continuation through the verified release candidate. The original
[saved specification](docs/interactive-implementation-spec.md) authorizes phases
0–11, scoped changes, isolated dependencies/builds/tests, commits/pushes and the
milestone PR. **Do not merge, tag or publish.** Never inspect dotenv contents or
overwrite unrelated work. Python remains standard-library-only test tooling.

**Next: record the verified Phase 9 commit, then push it and verify
fresh current-head CI before Phase 10 source freeze.** Before repeating a Git effect, inspect the
branch log for the checkpoint commit. Current HEAD is
`21f9324bd95bc1127201057c485f363005875048`; the intended next commit is
`Reconcile interactive documentation and CI runtime preparation`.

The previous default Git operation failed creating `.git/index.lock` because the current
sandbox exposes `.git` as read-only. The required escalation was attempted once;
the execution tool returned `Rejected("rejected by user")`. No command from that
escalated request ran. Read-only verification confirms HEAD and origin still
equal21f9324, all eight intended files remain unstaged, and there are no staged changes.
Kyle has now explicitly allowed this Git metadata write. Use the authorized
escalation for the existing repository; no alternate Git directory is needed.
No test/build permission or dependency change is needed. The exact candidate
output directory does not exist; do not substitute a dirty build for Phase11.

Phase 9 full source exec17885 finished0: 69 files, 26,845 assertions, 43 shared
terminal methods in71.605s, 6 visual methods in5.733s and both structural gates.
Log:`/tmp/attalambda-interactive-phase9-full.log`; parsed counts:
`/tmp/attalambda-interactive-phase9-full-summary.json`. The only subsequent
non-doc change is two Linux CI setup blocks; final distribution checks pass217
in `/tmp/attalambda-phase9-ci-ownership-focused.log`.

CI run34994217012 at the current HEAD finished with all Windows/macOS
build/consumer/cleanup jobs passing and only two Linux preparation failures.
The root-owned installation caused --apply and later compilation permission
failures. The final workflow transfers only the newly installed
`/usr/share/racket` to the disposable job user, then runs ordinary --apply.
Independent original-image proof covers normal compilation and all15 preparation
regressions; default caches and product inputs are unchanged. Review/logs:
`/tmp/attalambda-phase9-checkpoint-review-7jrtn7b_/`. The incomplete sudo-only
attempt and bounded setup diagnostics remain failed/limited evidence there.
New-head CI is required after push. Full old run log:
`/tmp/attalambda-phase8-ci-complete.log`; temporary remote artifacts are absent.

No source test process or owned container is running. The independent setup
diagnostic also passed package setup, actual executable embedding/distribution,
version and transcript smoke checks; its finalizer removed the container.
Record:`/tmp/attalambda-phase9-checkpoint-review-7jrtn7b_/ownership02-cache-results.json`.
Source review hashes match, and temporary artifact drivers have closed independent
review, but current-head CI, source freeze and exact artifact checks remain.
This is not a verified candidate yet.

The first full attempt36337 remains failed evidence at
`/tmp/attalambda-interactive-phase8-final-full.log`: six failures all identified
the same stale compiled adapter import. The wrapper had compiled only one of
four Python-launched Racket fixtures. It now refreshes all four; the focused
AdapterProbe passes2 methods in3.942s, independent fixture-inventory review is
clean, and the complete second run passes. No product repair or weakened test
was used for that preparation failure.

PLAN.md retains detailed phase history and previous diagnosed failures. The prior
verbose handoff is preserved at`/tmp/attalambda-interactive-handoff-before-checkpoint8.md`.
Update this handoff after the next effect, so an interruption does not repeat it.

## Git and product state

| Item | Current state |
| --- | --- |
| Branch | `interactive-attalambda` |
| HEAD/origin head | `21f9324bd95bc1127201057c485f363005875048` |
| Main/origin main | `71232f7fb47f8daad61e6a7a6bcf4a5477532352` |
| PR | https://github.com/kserrec/attalambda/pull/7 — open draft |
| Completed commits | Phases0–7:52dde70,5a9f907,bebe51a,fe70e6f,ba3d4c5,4f29dd1,542d47b,9960d4b |
| Current worktree | Phase8 committed; Phase9 documentation reconciliation and two Linux CI preparation lines are uncommitted |
| Version | VERSION0.8.0/package0.8 prepared, unpublished; remote tag and release both404 on latest read |
| Source changes | Runtime input, shared checked entry expansion, lazy retained definitions, snapshot redefinition, commands/load/reset/status, original-input ownership, cancellation, editor/completion/private bounded history |
| Canonical files | Prior canonical bytes plus previously committed narrow tooling amendment preserved; saved contract matches attachment |
| Public binary target | Linux x86-64 only; native macOS/Windows jobs remain internal evidence |

The complete current suite discovers69 Racket test files. The terminal wrapper
runs43 methods frominteractive_pty.py and6 visual regression methods from
interactive_expeditor_regressions.py. The latter owns14 PTYs and23 exact
cursor/grid assertions. Artifact consumers select25 actual CLI/transcript methods
from the shared Python harness and do not receive the source-only fixtures.

## Isolated runtime and exact checks

Prepared runtime:`/tmp/attalambda-racket93-promise-candidate`; isolated user home:
`/tmp/attalambda-racket93-promise-user`. Original `/tmp/attalambda-racket93` and
personal/system runtimes were not changed. Use the corrected runtime for all
source checks:

```sh
env PATH=/tmp/attalambda-racket93-promise-candidate/bin:/usr/bin:/bin PLTUSERHOME=/tmp/attalambda-racket93-promise-user TMPDIR=/tmp ./run-all-tests.sh
```

The completed invocation logs to`/tmp/attalambda-interactive-phase8-final-full-02.log`.
The copied raco runtime cannot resolve compiler/test's process submodule when
`raco test` receives multiple files. Individual invocations work and are exactly
what run-all-tests.sh uses. Do not count the failed multi-file invocation as a
product/test failure or rerun it. Source `raco make` has completed successfully.

Two narrow existing-dependency corrections are checked in. Explicit --apply is
for isolated preparation only; ordinary suites/builders use read-only --check.
All three builders capture provenance and all three consumers require exact pins.

| Input | SHA-256 |
| --- | --- |
| Promise patch | `179be1bbde34542758c87b364ae7717c7355cba58cb880875faf137c521ab1a9` |
| Corrected promise source | `bca5b526943be123c8f3fbad24d30556fe3ffea1dc60b6d9c28ec8875e27c7eb` |
| Expeditor patch | `954cdc83b8ee684512a5c3c131d4bc48dd30c40a6a6e8c5a884b3f46dc98b755` |
| Third-party notice,103764bytes | `d480dcda59df5e54a4185fa2293a04f6ff40ebf1e79712d29e51d8490b87b024` |

All five Expeditor source pins are in`tooling/prepare-expeditor-runtime.rkt`.
The fresh combined source/loaded check passes in
`/tmp/attalambda-final-runtime-loaded-check.log`.

## Completed evidence

| Scope | Evidence |
| --- | --- |
| Actual completion | Public, defined/redefined/loaded/reset, failed-entry and lazy-value behavior pass;72 actual CLI control/unusual identifier cases preserve source. Logs`/tmp/attalambda-completion-actual-cli{,-state}.log`; the original combined run failed only an incorrect test expectation for source-edit Ctrl+C, corrected without product changes. |
| Permanent completion | 9075 checks pass in`/tmp/attalambda-permanent-completion.log`; actual helper covers549 spellings, exact inert namespace inventory,135 public+77 committed names and no demand. Independent`/tmp/attalambda-completion-wiring-review.md`. |
| Expeditor repair | Final independent28 public-API PTYs/55 visual checkpoints pass:`/tmp/attalambda-expeditor-final-cold-review.md`. Permanent6 methods/14 PTYs/23 grid+cursor assertions pass:`/tmp/attalambda-permanent-expeditor.log`; stock ASCII negative control fails both widths. |
| Preparation | Permanent15 checks pass:`/tmp/attalambda-permanent-preparation-stale-main.log`. Exact transform, mode/idempotence, unknown/symlink/partial state and fresh-process stale compiled-main rejection. Independent review closed:`/tmp/attalambda-expeditor-preparation-review-ihudogrm/review.md`. |
| Shared promises | Upstream261 tests pass; actual reader/session original-fail/corrected-pass probes; permanent cache/cancellation/retention tests. Independent`/tmp/attalambda-promise-independent-review.md`. Old40-method source terminal run passed92.721s before final completion/redraw changes. |
| Current-source review | `/tmp/attalambda-phase10-independent-review.md` and18-file`/tmp/attalambda-phase10-review.sha256`: ten runner modules plus changed language/runtime and boundary paths;31 focused groups pass. Hash recheck matches current source. |
| Output finding closed | Distinct stdout/stderr terminals incorrectly shared newline bookkeeping. The retained two-PTY hunter fails before and passes after port-file-identity comparison;7 boundary groups pass. Logs`/tmp/attalambda-separated-output-{hunter-before,hunter-after,boundary}.log`. Two TERM settings alone do not prove two collector modes because queued input can select plain collection. Other tests cover advanced editing. |
| Packaging/docs | 217 distribution checks pass:`/tmp/attalambda-final-dependency-distribution.log`. Windows0.8.0 regex hunter fails before/passes after. Scoped review:`/tmp/attalambda-phase9-packaging-review-_n1ep3qp/review.md`. Exact docs/contract integrity passes:`/tmp/attalambda-current-doc-integrity.log`. |
| macOS diagnostic | Old Intel failure had no surviving matched bytes/artifact. Current diagnostic preserves the gate, exits2 for a binary match/0 otherwise, records exact hash/needle/file/offset/context. Independent review passes; no native cause or repair claim until new CI. |
| Arithmetic timing check | Full binary-nat suite passed. Small matched original/corrected probes return identical results without a large slowdown; single larger GCD sample+18% is not a persistent-regression claim. `/tmp/attalambda-promise-nat-performance-_7drcom6/review.md`. No speculative performance change. |

## Development artifact and final artifact preparation

Development08 passed the isolated no-Racket consumer,22 terminal methods at each
of two extraction paths, examples, input, relocation and provenance. It predates
final completion/redraw/notice/output changes and **is not the candidate**.
Archive:`/tmp/attalambda-interactive-development-probe-08/attalambda-0.8.0-linux-x86_64.tar.gz`;
SHA256`facbcf81dc36dbe74938ff1b98078569cdf04e23713c6ba4f4142974f15b2fda`.
Logs/report:`/tmp/attalambda-promise-development08-consumer.{log,json}`.
Old development07's21/22 cancellation failure remains historical, not a pass.

Reuse the prepared consumer image:
`sha256:dabaae31057cbc79baf7e2afa65b8c8cfd378b5013e4e8a95a520265fc794803`, ID file
`/tmp/attalambda-interactive-consumer-image-id-resume`. Its isolated preparation
installed14 Ubuntu packages,7.274MB download/27.9MB installed; no pip packages.
The prior preparation permission blocker is resolved. Do not rebuild blindly.

Final drivers are prepared, independently reviewed and **not executed**:
`/tmp/attalambda-interactive-candidate-build01.py` takes the exact frozen HEAD as
its argument, asserts it matches, then calls the existing Linux builder without
--allow-dirty into a new`/tmp/attalambda-interactive-candidate-01` directory.
It uses the original pinned official CS9.3 image
`racket/racket:9.3-full@sha256:f9c540abe281413dc9e25bfbe6e35276f1a5bca1fa40213c40ac7bac6bb69c62`,
installs Git only inside the disposable builder, applies/checks both patches,
mounts source read-only at`/attalambda-project-workspace`, and retains the existing
420-second bound. Build log:`/tmp/attalambda-interactive-candidate-build-01.log`.
The mount name matters: old generic`/source` collided with abbreviated source-file
basenames in the unchanged leakage gate; the distinctive name avoids that proven
invocation collision without weakening the gate.

`/tmp/attalambda-interactive-candidate-consumer01.py` takes the same exact build SHA
as an argument and then copies only the archive,
checksum and existing self-contained consumer/Python harness into its owned
transfer directory. It reuses the immutable image, offline/read-only/nonroot,
capabilities dropped, with bounded process/memory and cleanup. It records archive,
harness and consumer hashes; log/report:
`/tmp/attalambda-interactive-candidate01-consumer.{log,json}`. Do not run it against
an old archive or label dirty development evidence as clean candidate evidence.

The corrected drivers verify expected HEAD before/inside/after the build, exact
manifest source/clean state, archive/checksum/manifest hashes, original file
preconditions and frozen consumer/harness bytes. Nested finalizers retain cleanup
evidence even on a removal exception. Review and exact input hashes:
`/tmp/attalambda-interactive-candidate01-review.md` and
`/tmp/attalambda-interactive-candidate01-review-hashes.json`. Neither driver has run.

## Remaining delivery sequence

Phase8 is closed. Phase9 verification passes and its commit/push is next;
Phase10 source freeze still requires current-head verification and its commit. CI run34994217012 finished at21f9324 with only the two diagnosed Linux preparation failures. Earlier
PR checks at9960d4b are old: source passed, Linux/Windows/macOS Intel had failures;
those results do not validate this worktree. Recheck current-head CI/review after
push, investigate any actual failures, and preserve existing native gates.

PR body preparation:`/tmp/attalambda-interactive-pr-candidate-body.md`. gh pr edit
fails on legacy projectCards; use gh api PATCH with a JSON file and GET to verify.
No review request is a completed review. Final Phase11 evidence is a docs-only
commit that names the earlier clean build SHA and exact archive/manifest hashes;
it must not relabel the artifact as built from the later record commit.

Known limits remain: printing raw untagged terms is unspecified; failed entries
cannot roll back effects already demanded; closures may retain old binding graphs
until unreachable/reset; only Linux x86-64 is a supported public binary target.
No candidate, tag, release or publication is claimed. The Phase9 suite finished0;
the independent CI permission/embedding probe finished and removed its container.

Patch-format whitespace check: the staged whole-diff check reports18 whitespace
lines, all validated as unchanged unified-diff context in the two SHA-pinned
dependency patches (blank context markers and existing upstream indentation).
No added patch source line is implicated. Source whitespace passes with patch
serialization paths excluded; exact patch application/source hashes remain checked.
No source rule or acceptance test was weakened.

PR status was updated and read back at 2026-09-15T16:50:53Z. It now names the
actual failed Linux preparation and verified, unpushed correction; no current CI
or candidate pass is claimed. Receipt:
`/tmp/attalambda-interactive-pr-phase9-status-readback.json`. This is the only
external write after the Git denial; it did not change any repository ref.
