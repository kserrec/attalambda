# Interactive AttaLambda — in progress

Kyle authorizes autonomous phases 0–11 through the verified candidate, including
isolated dependencies, tests/builds, commits/pushes and a PR. **No merge, tag, or
publication.** Contract: [docs/interactive-implementation-spec.md](docs/interactive-implementation-spec.md).
Branch `interactive-attalambda`, based on input `62d0f0c`. Version stays 0.7.0 until
Phase 9. PLAN contains the serial checklist and detailed evidence.

Phases 0–6 are committed and pushed: `52dde70`, `5a9f907`, `bebe51a`, `fe70e6f`,
`ba3d4c5`, `4f29dd1`, `542d47b`.
Phase7 full verification and independent review passed; commit/push is the only
remaining closure action. **Next implementation step: 8.1 — integrate the editor.**
Reconcile status before resuming; do not
repeat completed effects, probes, commits or pushes.

## Current verification

Phase7 final full run passed with exit0:64 test files,17,716 reported Racket tests,
24 Python PTY cases,40 production purity modules and complete boundaries. Command:
PATH=/tmp/attalambda-racket93/bin:$PATH PLTUSERHOME=/tmp/attalambda-racket93-user
TMPDIR=/tmp ./run-all-tests.sh. Log /tmp/attalambda-interactive-phase7-full-final.log.
Exec49517/monitor448 finished; phase7-full-final-result stores exit0. Independent
command_loop_cold_review is closed. Dotenv-safe diff/whitespace checks pass.
New executable files:runner/repl.rkt and runner/output.rkt; modified launcher,
diagnostics and session phase reporting. New tests/controller/output/CLI and PTY
coverage plus exact boundary updates are separate from plan/handoff evidence.
Core/effects/runtime/lang/readers and version/package metadata have no Phase7 diff.

Phase7 memory observations:3x200 entries took10.313/10.205/10.020seconds; retained
125204976/125477904/125469192 bytes, reset115107568/115168456/115222448 bytes versus
115299864 initial. Descriptors stay7; weak-reference/reset/close assertions pass.
These observations are not universal performance guarantees.

Full Phase 6 verification completed with exit 0: 61 suites, 17,691 reported
Racket tests, 14 Python PTY cases, 40 production purity modules and complete
boundaries. Log /tmp/attalambda-interactive-phase6-full.log. Exec87292 and monitor
cell355 are finished. Independent file_load_cold_review closed both proven gate
findings after rerunning the original hunters, three boundary groups and complete
gate; no additional confirmed issue. Core/effects/runtime/lang/readers, package
metadata and VERSION have no diff from Phase 5. git diff --check passes.

Phase 6 memory observations: three 200-entry cycles take11.05/10.70/14.21seconds;
retained heap131.26/131.46/131.51MB, reset121.17/121.23/121.27MB versus121.22MB initial.
Descriptors remain7; weak-reference/reset/close assertions pass. These measurements
are observations, not universal latency or memory promises. Prior Phase 5 evidence
remains below for comparison.

Memory log `/tmp/attalambda-interactive-5.8-memory.log`: three 200-entry sessions,
about9.15/9.13/9.21seconds; retained heap131.16/131.39/131.45MB and reset heap
121.07/121.15/121.15MB versus121.18MB initial; descriptors stay 7. Weak references to
old namespace/maps clear on each reset and final close; no owned thread/port growth.
Observations are not universal performance promises. Prior Phase 4 full log
`/tmp/attalambda-interactive-phase4-full.log`:56suites,17,662 Racket-reported tests,
9PTY cases,40 purity modules and complete boundaries, exit0.

## Implemented session behavior

Step 7.1 is implemented and verified, uncommitted. New runner/repl.rkt supplies
the basic plain source loop; runner selects it through a fixed lazy dynamic-require.
All supported flags/terminal selection pass four CLI groups and three actual CLI
PTY cases; original runner291, boundary145, three mutation groups and full gate pass.
Logs /tmp/attalambda-interactive-7.1-*.log (cli-final/gate-final). All focused
processes are finished; final Phase7 full verification is recorded above. New source-class and optional
session on-phase callback plumbing are pinned. tests/helpers/fresh-language.rkt
supports input bytes with concurrent draining/feeding and explicit pipe closure;
the actual CLI PTY class also supports redirected stderr and later artifact paths.
Step 7.2 adds help/names/load/reset/quit and passes seven CLI groups, five diagnostic
groups and complete gate (7.2-{cli,diagnostics,gate}.log). Name listings preserve
full names and safely escape controls; command/load failures recover. Exact command
case and load-token count are pinned. Step7.3 passes nine CLI groups and complete gate (7.3-{cli,gate}.log).
Echo-off skips the renderer and raw-function probing; reset retains echo.
Step7.4 passes six output groups, ten CLI groups, five CLI PTYs,145boundary
checks and complete gate (7.4 logs; boundary-final is corrected inventory).
Step7.5 has proven stream findings from file_load_cold_review: permanent source
failure retries101times; broken stderr escapes fatal handler; result-output
failures consume later entries and are mislabeled rendering. Hunter/log
/tmp/attalambda-phase7-stream-review.{rkt,log}. Repaired source/UI/result I/O as
fatal70 with protected sanitized report; actual language Err values preserved.
7.5 passes12CLIgroups,4controllergroups,2actualCLI cancellation/EOF PTYs,
1transcript interruption case and complete gate (cli-final/controller-final).
7.6 passes three live transcript cases with the writer kept open through
source/answer/recovery boundaries; final read EOF and sticky1, echo-off immediate
prompt and transcript130 are covered. Original stream hunter findings all close
(/tmp/attalambda-phase7-stream-review-fixed.log). New cleanup finding: custodian
shutdown leaves in-memory ports open; explicit test-owned port finalization and
shell forwarding-port closure are added. Controller4/output6 and gate pass in
7.6 final logs. Boundary mutants pass4groups (7.6-boundary.log). Phase7 full attempt /tmp/attalambda-interactive-phase7-full.log ended1 after
six passing suites (acceptance21,binary2168,boundary145,byte225,chars729,codec178).
Distribution failed at load with stale compiled run-command9.1 import after the
helper gained #:input. Exec28369/monitor431 finished; phase7-full-result stores1.
`raco make tests/distribution-test.rkt` passed; its focused test passes209 in
/tmp/attalambda-interactive-phase7-distribution-rebuilt.log. run-all-tests.sh now
runs raco make on its discovered tests before execution, refreshing imported
helper caches. Shell syntax and diff checks pass. Final full suite finished0
in exec49517, /tmp/attalambda-interactive-phase7-full-final.log. functions cell448
is finished and phase7-full-final-result stores exit0.
No production change for the stale ABI.

Cold command_loop_cold_review proved Ctrl+C during recoverable diagnostics escaped
to outer130. Five sibling hunters cover expansion/read/command/load and a second
break while reporting interruption. First attempted nested protected report with
parameterize-break alone failed and was reverted. A minimal isolated probe proves
custom-port callbacks queue breaks until an explicit check. Final recover helper
uses protected parameterize-break #t, show, then (break-enabled #t), and returns
interactive continue/transcript130. Original single hunter passes; six controller
groups, two targeted PTY cases and gate pass (phase7-recovery-* logs). Independent command_loop_cold_review is now closed with no remaining confirmed
Phase7 findings:5original interruption siblings,8cleanup paths and final6controller
groups pass. The last test-only global missing-file path is replaced by a child
under make-temporary-directory with dynamic-wind cleanup. The final full suite includes this completed repair.
The temporary sleep0 variant passed the original siblings, then was replaced by
the narrower synchronous public break-enabled check demonstrated independently.
Docs: https://docs.racket-lang.org/reference/breakhandler.html.

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
Step 6.1 is implemented: new runner/source-file.rkt owns shared validation and
small syntax-diagnostic selectors; existing runner calls it without changing CLI
policy. Exact source-file class and runner capability reduction are implemented.
Three file-helper cases, 291 existing runner assertions, 145 boundary assertions
and the complete boundary gate pass; logs /tmp/attalambda-interactive-6.1-*.log.
Runner-test exec94234 finished with exit 0; no Phase 6 full suite has started.
Step 6.2 is complete: session load-source-file composes the exact validated body,
restricted parser and shared evaluate-entry with explicit empty imports and void
consumer. Boundary pins this route; it adds no native filesystem primitive.
Five file groups and session-boundary mutations pass in 6.2-{file,boundary}.log.
Step 6.3 passes eight file groups in /tmp/attalambda-interactive-6.3-file.log:
reload identities/effects, old snapshots, failed publication and real cancelled
input after output, plus successful Error/Err publication. No implementation
change was needed beyond the shared transaction already implemented in 6.2.
Step 6.4 passes ten file groups and complete gate; 6.4-{file,gate}-final.log.
Initial new-test syntax failure is corrected; product behavior was not changed.
Step 6.5 adds diagnostics.rkt (pure classification/formatting plus opt-in renderer
unwind wrapper). Five diagnostic groups pass in 6.5-diagnostics.log. Exact new
boundary class/mutations pass (two mutation groups, 145 assertions, complete gate).
Default engine
exceptions and file CLI messages stay intact; Phase 7 wires controller diagnostics.
Checkpoint 6 is complete; commit542d47b is pushed. Reconcile Git
before continuing so an interrupted action is never repeated blindly.
The two cold-review findings concerned gate rejection only: omitted-port/early
preflight mutations and executable diagnostic read/expand labels. Exact protected
blocks/use counts and permanent mutation tests now reject them. Independent final
logs: /tmp/attalambda-phase6-review-{hunter,boundary,gate}-fixed.log. No product
implementation changed for those repairs. The first revised count omitted the
port->bytes import; the observed import-plus-call count of two is now enforced.

The earlier documentation-only spacing edit had altered some /tmp phase log
spellings; those paths and the stale Phase 5 next-step text are corrected now.

Phase 8 read-only editor_probe_review is complete. Use a fresh empty metadata-only
completion namespace each prompt; removing bindings with namespace-undefine-variable!
leaves stale identifier mappings. Public hooks and placeholder bindings never force
values or expose native names. Keep shell-owned history (up to 1,000) and reopen
public Expeditor state for each read: PTY probes reached entries 999/1,000, whereas
the library's returned history trims to 256. Do not import private parameters.
API: https://docs.racket-lang.org/expeditor/Expeditor_API.html and
https://docs.racket-lang.org/reference/Namespaces.html.

The existing and fresh-editor fixtures both fail 3/3 when source, its program
answer and the following source arrive in one write before acceptance: Racket's
stdin buffer retains the next line while Expeditor reads descriptor 0 directly.
After evaluation, if byte-ready? on original stdin, collect the next entry with
the existing read-source-entry on that same port; otherwise use Expeditor.
This minimal non-replay handoff passed complete queued source, incomplete source
with and without LF, two program reads, and program Ctrl+D followed by editing.
Already-buffered incomplete entries finish through the plain collector; subsequent
ordinary prompts regain advanced editing. Section 3.6 permits this demonstrated
minimal adaptation; retain all cases in actual CLI PTY tests in Phase 8.
Evidence: /tmp/attalambda-phase8-{editor-api,gated-editor-api,pending}-review.rkt.
Blank Enter retains editing and repositions the cursor; use the returned value
for EOF, not prompt repainting. Review made no repository changes.
Completion follow-up: the library's common native identifier list only ranks
already available candidates. Seven PTYs in /tmp/attalambda-phase8-common-name-review.py
prove native prefixes do not complete, positive metadata names do, and promises
remain unforced. No private completer hook or upstream adaptation is needed.

Phase 7.4 read-only preparation: port-count-lines!/port-next-location alone fails
separator tracking. Bare CR and LF report identical locations, and Expeditor's
fresh-line alters stdout's counter while fd1 is routed to stderr (even with piped
stdout). terminal-port? changes during dup2; snapshot original status beforehand.
editor_probe_review proved the 28-line public make-output-port candidate at
/tmp/attalambda-phase7-forward-output-review.rkt for session program output only.
It forwards immediately and retains accepted-byte count/last byte, with close=void
preserving original stdout. Five focused tests (forward-output-test.rkt) and five
engine/PTY scenarios (forward-integration.{rkt,py}) pass: partial/nonblocking writes,
cancelled blocking write, exact CR/LF/UTF8, flush/error metadata, immediate prompts,
echo-off and editor handoff with terminal/piped stdout. Keep stdout-result boundary
and visual-prompt separation distinct; editor uses original ports. No whole-output
capture, repo implementation change or test waiver. Counter failure evidence:
/tmp/attalambda-phase7-editor-{True,False}.log. Primary API documentation:
https://docs.racket-lang.org/reference/Byte_and_String_Output.html and
https://docs.racket-lang.org/reference/customport.html.

Phase 8 history read-only preparation is complete (reader_design_review).
Recommend one private history helper, newest-first, with magic/version + u16 count
+ u32 UTF8 byte lengths. Cap count1000 and complete encoded file1048576 bytes;
strictly reject invalid UTF8/framing/trailing bytes. A native data reader can amplify
11 bytes (#1000000(0)) into a million-element vector even with extensions disabled,
so do not use unrestricted native read for a supposedly bounded history file.
Use string-utf-8-length to skip oversized source before allocating encoded bytes.
History disabled/transcript paths return before path lookup, stat, encoding or writes.

Path recommendation: (find-system-path 'pref-dir)/attalambda/history-v1; PLTUSERHOME
isolates it under the existing temporary Racket home. Check no-follow metadata for
existing ancestors, reject symlinks/non-directories/unsafe writable ancestors; only
the root-owned sticky system-temp ancestor is allowed for isolated /tmp fixtures.
Create missing directories0700; require app directory0700 and private regular
single-link history before reading. Check stat size then cap actual read1048577
to cover growth. Reject unsafe leaves before content reads; never chmod unsafe
existing paths. Atomic temporary files default0664 here, so set temporary mode0600
before writing. Use an atomic helper rename-failure handler that re-raises, preserving
the prior target rather than a fallback rename dance. Persistence failure is best
effort; breaks retain their normal control flow. Public metadata proves modes/types/
links/size, not an independent current-UID comparison; no UID-witness/FFI subsystem
is required. Windows stat modes do not establish ACL privacy; keep optional history
policy separate from internal file-launch portability. Probe:
/tmp/attalambda-history-api-probe.rkt (private fixtures /tmp/attalambda-history-api-5m2q98p4).
Retain tests for framing/count/byte edges, directive inertness, growth, links/FIFO/
directories/modes, midwrite/rename preservation and zero filesystem access when off.
Continue the already proven shell-owned1000-entry editor history; no private imports.

## Environment / remaining endpoint

Use CS 9.3: PATH=/tmp/attalambda-racket93/bin:$PATH,
PLTUSERHOME=/tmp/attalambda-racket93-user, TMPDIR=/tmp. One file per raco test call
(relocated multi-file process mode fails). ./run-all-tests.sh includes both gates.
Approved cached image racket/racket:9.3-full digest
sha256:f9c540abe281413dc9e25bfbe6e35276f1a5bca1fa40213c40ac7bac6bb69c62.
Prior8.10 ignored caches were rebuilt. Phase 3 package staging added readers to all
four sibling lists; final artifacts remain unverified.

Phases 7–11 remain: actual CLI/status/echo;
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

Additional Phase8 read-only metadata probe:
/tmp/attalambda-phase8-public-exports-probe.rkt observed actual language exports:
129 phase-zero variables +10 syntax exports =139 unique names. Exactly four
scaffolding names are #%app/#%datum/#%module-begin/#%top; filtering those leaves
135 completion names, including legitimate public host. No eval/dynamic-require/
open-input-file export. Probe closes its isolated session; no production change.

Read-only Phase8 adapter follow-up by editor_probe_review is now PROVEN:
final flush failure skips dup2 restore/close in the current test-only descriptor
helper; fd1 remains on stderr and descriptors grow7→8. A body failure plus final
flush failure replaces the original action error. Success, initial-flush failure,
action failure and action break controls all restore descriptors/count7.
Proof /tmp/attalambda-phase8-descriptor-failure-review.{rkt,py}, using live
/proc/PID/fd checks from the parent. Narrow cleanup sketch is proven at
/tmp/attalambda-phase8-descriptor-safe-review.rkt with seven passing subprocess
scenarios in descriptor-safe-probe.{rkt,py}: nested finalizer always restores/closes
fd1; it preserves an already propagating action failure or break. No new FFI
operation. Promote via lazy fixed module load after supported interactive-platform
selection, since current top-level get-ffi-obj resolves POSIX symbols eagerly.
This does not affect Phase7 production (no FFI).

Phase8 completion follow-up (not Phase7 blocker): nine PTYs in
/tmp/attalambda-phase8-escaped-name-review.{rkt,py} prove raw metadata namespace
names insert invalid source for valid escaped symbols: tw<Tab> -> two words
(two source forms); lef<Tab> -> left|right (incomplete). Prefixes containing
source bar/backslash spelling do not match raw symbol names. Raw ESC in a name
also reaches the PTY (though that candidate parses as the intended identifier).
Promises remain unforced and all terminal cleanup passes. Native token lexer
retains source spelling, while completion compares symbol->string metadata and
inserts suffixes. Follow-up /tmp/attalambda-phase8-adjusted-spelling-review.{rkt,py}
proves a source-spelling adaptation: print each symbol with read-accept-bar-quote
disabled, then escape every vertical bar. Thirteen PTYs plus a numeric-prefix
case preserve the exact identifier under the unchanged restricted reader, with
unforced promises and restored terminal/stdout. This covers spaces, bars,
existing backslashes, semicolons and number/Boolean-like names. An unfinished
bar-quoted prefix such as |tw still is not a completion token.

Literal-control names remain unresolved: the same candidate emits raw ESC.
The documented lexer/key hooks provide no separate source/display representation;
ee-insert-self rejects control characters, while make-ee-insert-string and the
native display path emit the raw entry string. Independent supported-surface
review is complete; no compliant public adaptation was found. Do not silently
exclude legitimate names, invent grammar/private imports/custom terminal handling,
or claim this case passed. Resolve its contract impact at8.3. No Phase8 repository
implementation has started.
