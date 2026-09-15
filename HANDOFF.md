# Interactive AttaLambda — in progress

Kyle authorizes autonomous phases 0–11 through the verified candidate, including
isolated dependencies, tests/builds, commits/pushes and a PR. **No merge, tag, or
publication.** Contract: [docs/interactive-implementation-spec.md](docs/interactive-implementation-spec.md).
Branch `interactive-attalambda`, based on input `62d0f0c`. Version stays0.7.0 until
Phase 9. PLAN contains the serial checklist and detailed evidence.

Phases 0–4 are committed/pushed: `52dde70`, `5a9f907`, `bebe51a`, `fe70e6f`, `ba3d4c5`.
Phase 5 is implemented but uncommitted. **Next: finish Checkpoint 5 full suite/gates,
then commit/push; only then begin6.1.** Reconcile status before resuming. Do not
repeat completed effects, probes, commits or pushes.

## Current verification

Full Phase 5 verification completed with exit 0: 59 suites, 17,674 reported
Racket tests, 14 Python PTY cases, 40 production purity modules and complete
boundaries. Log `/tmp/attalambda-interactive-phase5-full.log`. No suite/monitor
remains running. Cold `lifetime_cold_review` found no proven findings and
independently passed lifetime/input/boundary and all five new PTY cases. Memory
was close-read but not rerun alongside the measurement. No new hunter required
retention. Commit/push this verified phase, then proceed with 6.1.

Memory log `/tmp/attalambda-interactive-5.8-memory.log`: three 200-entry sessions,
about9.15/9.13/9.21seconds; retained heap131.16/131.39/131.45MB and reset heap
121.07/121.15/121.15MB versus121.18MB initial; descriptors stay 7. Weak references to
old namespace/maps clear on each reset and final close; no owned thread/port growth.
Observations are not universal performance promises. Prior Phase 4 full log
`/tmp/attalambda-interactive-phase 4-full.log`:56suites,17,662 Racket-reported tests,
9PTY cases,40 purity modules and complete boundaries, exit0.

## Implemented session behavior

Entries use checked private modules, lazy actual exports, immutable visible binding
identities, lexical snapshots, pure unary identity suspension for private forward
aliases, ordered demand and one protected publication. Core/effects/host/codec,
public facade exports and file-mode behavior are preserved. Source reader stays
restricted and incremental.

open-session captures original input/output/error (optional keyword overrides);
evaluate-entry uses them explicitly. Shared runtime is initialized once under the
session owner. Each entry gets a child custodian; failure/break releases its new
resources, success retains them. The success marker and name publication share
one short break-disabled section. Prepare/demand/render now only parameterize the
namespace, preserving the demand-time child owner. No production worker or timeout.

reset-session! initializes a candidate runtime then atomically swaps namespace,
owner and empty bindings; cleanup closes the displaced or abandoned owner.
The shell must call reset outside the old session custodian. close-session shuts
resources and clears namespace/bindings; original ports remain open. Private
session-exit(status), deliberately not exn:fail, unwinds valid language exit so
outer launcher cleanup runs before honoring0/1. Final CLI/diagnostics remain6–8.

Existing editor fixture --session uses the same engine to prove real input,
repeated Ctrl+C, rendering, reset/echo/history ownership, EOF and exit0/1/native
failure70. It is test-only; Phase 7 replaces its loop with the real controller.
Native9.3 Expeditor requires descriptor1; existing dup/dup2/close adapter routes it
to stderr only during editing. Promote/classify exact capability in Phase 8.
No alternate input registry or source/answer replay buffer was needed.

The earlier preimplementation scratch observation of a cached break escaping
subsequent work in1/31 runs remains unclassified. It did not recur in current
focused/regression review; old binding/listener survival is permanently checked.
Do not invent a fix or promise rollback: a forced shared promise may retain failure.

## Phase 6 preparation already completed read-only

reader_design_review recommends one exact new runner/source-file.rkt helper:
inspect-source-file -> validated-source(original path, strict-decoded body text,
line,column,position) or source-problem(fixed status/reason/location). Move existing
path/header/UTF8 validation and tiny sanitized syntax-expression/reason selectors;
retain stop/CLI/VERSION and actual file dynamic-require in runner/attalambda.rkt.
Return the body already read during validation; :load must not reopen it. Parse
with source-reader using exact coordinates, then shared evaluate-entry with explicit
empty imports and consume=void. Add an imports option, not a second publication path.

Preserve validation order and original path spelling: dotenv before extension,
extension before existence, final symlink before parent resolution, resolved dotenv
parent before stat/open, regular-file before content. Keep resolve-parent-path logic
for permitted parent symlinks, relative targets, symlink/.. traversal and cycle
handling. Fixed header accepts EOF/LF/CRLF, rejects BOM/space/bareCR; strictly decode
whole body first. Counted-port observed body location after LF orCRLF is2/0/18;
header-only EOF1/16/17. Compute port-next-location, do not hardcode byte offsets.
Existing runner tests163–579 pin precedence, paths, source errors and safe diagnostics.

Source-file must have its own exact path/import/export/read-target class; source-reader
gets no filesystem capability. Session retains closed native loader targets/single
publication. Caller working directory and program-relative I/O never change.
Final launcher distinguishes expansion/render/native errors without arbitrary native
messages/paths; missing-source vs missing-installation remains file-launch logic.
No Phase 6 implementation or helper creation has happened yet.

Phase 8 read-only API review is running with editor_probe_review: installed
Expeditor main does not export its private completer or history-limit parameters.
Candidate supported approach uses an empty metadata-only completion namespace
and fresh public editor state per read from shell-owned history (up to 1,000),
so private internal history trimming cannot discard the shell history. Await
its exact primary-source findings before implementing Phase 8. A blank-Enter
probe passed: it retains editing and only repositions the cursor; do not expect
a newly printed prompt as the readiness signal. No repository change from that probe.

## Environment / remaining endpoint

Use CS 9.3: PATH=/tmp/attalambda-racket93/bin:$PATH,
PLTUSERHOME=/tmp/attalambda-racket93-user, TMPDIR=/tmp. One file per raco test call
(relocated multi-file process mode fails). ./run-all-tests.sh includes both gates.
Approved cached image racket/racket:9.3-full digest
sha256:f9c540abe281413dc9e25bfbe6e35276f1a5bca1fa40213c40ac7bac6bb69c62.
Prior8.10 ignored caches were rebuilt. Phase 3 package staging added readers to all
four sibling lists; final artifacts remain unverified.

Phases 6–11 remain: shared validation/loading/diagnostics; actualCLI/status/echo;
editor/history/completion; version0.8/docs/packaging; cold final source review;
clean exact Linux archive build + isolated no-Racket consumer/PTYS/relocation;
PR/current-head CI/review and final candidate evidence. No PR created yet.
Never inspect dotenv contents, use Graphify, merge main, tag, or publish.

---

## Historical completed release handoffs

# Small Lisp sugar and release 0.7.0 — complete

Updated 2026-09-09; superseded only by new project work. Kyle authorized the
sugar implementation, PR, merge to main, and release. All work is complete;
no permission or manual check is pending. Future work needs a new instruction.

[PR #6](https://github.com/kserrec/attalambda/pull/6) merged as
`ab8c9b28bf544fe368695b40a33b1a254d1cf8dc` after all ten CI jobs and automated review passed.
Its tree equals the tree of reviewed head
`8e18f043607b1295b4ae6b765ebfbc9213347c74`. Local and CI source gates each pass
46 suites, 17,290 assertions, 39-module expanded purity, and complete boundaries.

[AttaLambda 0.7.0](https://github.com/kserrec/attalambda/releases/tag/v0.7.0) was published at `2026-09-09T10:54:27Z` and marked
latest. Unsigned annotated tag `v0.7.0` points to the exact clean merged commit
used for the Racket CS 9.3 Linux archive. The final archive and a fresh public
download each passed the isolated no-Racket consumer, including the four
sugars, existing API/printing, files/network, statuses, guide, and relocation.
Archive SHA-256: `af3e14784f7e6c885db38a055ab2d9faeaf7bf5a4e3a475d21e53055aa184f28`.
Linux x86-64 remains the only supported binary; all older releases are preserved.

[PLAN.md](PLAN.md) and the [release ledger](docs/design/standalone-distribution.md)
record exact commits, tag/asset IDs, sizes, hashes, and logs. Publication records
change only documentation outside the tagged build inputs. The earlier
uncommitted preview was not published. No session-owned process or container
remains running. The publication-record commit leaves main clean and pushed.

---

## Completed release 0.6.0 handoff (historical)

# Session handoff

AttaLambda 0.6.0 is published and verified. Kyle explicitly authorized the
release on 2026-09-08. Both release phases in [PLAN.md](PLAN.md) are complete;
no implementation, merge, or release action remains pending. Future work needs
a new instruction.

Release: <https://github.com/kserrec/attalambda/releases/tag/v0.6.0>, published at
`2026-09-08T13:59:26Z` as the latest stable release. Unsigned annotated tag
`v0.6.0` peels to clean build commit `dfa5d52a1c9f4a5841bacbba88e06b8eae90e824`;
tag object is `af80443d34027d3c9c414c0506213da23f57c2a1`. PR #4 merged the
printing implementation before release preparation. Linux x86-64 remains the
only supported public binary; older releases, tags, and assets are preserved.

Both local Racket CS 8.10 and CI Racket CS 9.3 passed 45 files, 17,065 assertions,
39-module purity, and complete boundaries. All ten jobs passed for the build
commit in [CI run 34233310627](https://github.com/kserrec/attalambda/actions/runs/34233310627).
The final archive and fresh public download each passed the isolated no-Racket
Ubuntu consumer: 31 existing public-API checks, 13 printing checks covering
every new callable, guide, file/TCP/HTTP, process statuses, and relocation.

Archive SHA-256:
`c3d9ea5263f7ab09e5f9b8d3260b8ead1335d8f1a052c7aba11edd4bf020bb4f`.
The archive is 14,159,078 bytes; SHA256SUMS is 103 bytes with digest
`5380ea26bf9bb906d70ac8f1b52301b763dfeb93a3ed737810cfe13f6093f3f6`. GitHub's digests, draft downloads,
and unauthenticated public downloads all matched the originals. Exact tag,
asset IDs, hashes, and provenance are in the
[release ledger](docs/design/standalone-distribution.md#attalambda-060--2026-09-08).
The publication record changes documentation only, outside the tagged inputs.

Local evidence: `/tmp/attalambda-060-release-state.json`,
`/tmp/attalambda-060-full-suite.log`, `/tmp/attalambda-060-ci-tests.log`,
`/tmp/attalambda-060-build.log`, `/tmp/attalambda-060-consumer.log`, and
`/tmp/attalambda-060-public-consumer.log`. Use `env TMPDIR=/tmp` for local source
checks so temporary fixtures stay within permitted paths; no test deadline or
purity rule was weakened. The [0.6.0 notes](docs/releases/0.6.0.md) and
[API reference](docs/API.md) describe the published printing contract.

## Completed 0.5.0 release (historical)

Status recorded 2026-09-07: the recursive-purity milestone and 0.5.0 release
are complete on main. Kyle authorized continuing through the described
merge/build/verify/publish steps. No release work or confirmed review finding
remains pending; future work requires a new request.

PR https://github.com/kserrec/attalambda/pull/3 merged as
`d770b8335a06a8ec6e5925030c4a92cde88e85d8`. Its tree equals reviewed head
`39fa142800c7bfc33e407fb93718960f91fe90d9`. All ten PR CI jobs and all ten
post-merge jobs passed. The local and merged CI source gates each passed
41 suites, 14,210 assertions, 32-module expanded purity, and complete
boundaries/source inventory. The automated review's one suggestion did not
match observed module-wide binding behavior; source and packaged-runtime
probes disproved it, the PR records the assessment, and its thread is resolved.

Published release: https://github.com/kserrec/attalambda/releases/tag/v0.5.0,
at `2026-09-07T20:21:07Z`. Unsigned annotated tag `v0.5.0` points to the exact
clean merged commit used for the Racket CS 9.3 Linux archive. The final archive
passed the isolated Ubuntu consumer, including 31 public-API checks with
`rec` execution and partial application, guide, file/TCP/HTTP, process statuses,
and relocation. Fresh public downloads matched both verified local hashes.
Archive SHA-256:
`9d87027d3fcad80c58668ce2d1d31365bba507131bc67889118e3d2ae7af36c4`.
Linux x86-64 remains the sole supported binary download; older releases remain
preserved. macOS and Windows provide internal portability evidence only.

[PLAN.md](PLAN.md) records the completed work and local evidence paths.
[docs/releases/0.5.0.md](docs/releases/0.5.0.md) explains `rec` and migration
from recursive `def`; [docs/API.md](docs/API.md) describes the released API.
The [release ledger](docs/design/standalone-distribution.md) records exact
commits, tag/asset IDs, sizes, hashes, and consumer results. The publication
record changes documentation only, outside the tagged build inputs.

---

## Completed 0.4.0 release (historical)

Status recorded 2026-09-06: the public API/List update, PR review, merge, and
0.4.0 release are complete. Kyle explicitly authorized each of those actions.
The checkout is on main. Subsequent release/feature work requires a new request;
the completed plans are historical evidence, not instructions to repeat work.

- PR https://github.com/kserrec/attalambda/pull/2 merged at 17:45:00 UTC as
  `bd1dd56925765f8d8359609a49e333ba570bcfc6`. Its tree equals final PR revision
  `d6f50eec467062a0d33ce0697229f0b691735a06`.
- Automated review of the language implementation completed without findings;
  no actionable inline comments or review threads remained. Version-only
  preparation was reviewed locally. The local full suite passed all 41 files,
  14,100 assertions, 32-module expanded purity, and complete boundaries.
- All ten jobs passed in both PR CI
  https://github.com/kserrec/attalambda/actions/runs/34048807658 and post-merge CI
  https://github.com/kserrec/attalambda/actions/runs/34049568221.
- Latest stable release: https://github.com/kserrec/attalambda/releases/tag/v0.4.0,
  published at 18:00:46 UTC. Annotated tag `v0.4.0` points to the exact clean
  merged commit used to build the Racket CS 9.3 Linux archive. Linux x86-64
  remains the sole supported binary download; older releases were preserved.
- The exact archive passed the isolated Ubuntu consumer, including all 25 List
  functions, Char literals, ordinary identifiers, Map, laziness, effects, and
  relocation. Fresh public downloads matched both verified local hashes.
  Archive SHA-256 is
  `29728792d17843c7c09faf5f9be0cb4b215e13a43113a7b65d83d909dd37ac8b`.

[`PLAN.md`](PLAN.md) records completion and local evidence paths.
[`docs/API.md`](docs/API.md) describes the released API; the
[release ledger](docs/design/standalone-distribution.md) records exact commits,
tag/asset IDs, sizes, hashes, and consumer results. The final publication-record
commit changes documentation only, outside the tagged build inputs. No code
fix, review finding, merge, or publication remains pending.
