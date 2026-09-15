# Interactive AttaLambda — candidate evidence checkpoint

## State and exact resumption rule

The runtime-input and interactive-shell implementation, source gates, clean Linux
build and exact isolated consumer are verified at
`3ae392629ecfb380d3dd31451c33fd5617d53f51`. All ten CI jobs at that revision pass;
independent source and artifact reviews have no actionable findings. Phases 0–11
are recorded in [PLAN.md](PLAN.md), against the unchanged
[supplied contract](docs/interactive-implementation-spec.md).

This checkpoint changes documentation only. **Do not merge, tag or publish.**
The final delivery step is to commit/push this record, verify that resulting
head's CI/review, and save `/tmp/attalambda-interactive-final-state.json` with the
exact record SHA, PR readback, final checks and cleanup. That post-commit receipt
is the authority for the final current-head state: its absence or pending status
means that step remains unfinished. Inspect Git and the receipt before repeating
any effect. The record commit cannot contain its own Git SHA. The earlier build
SHA and archive bytes below must never be relabeled as built from this record.

The milestone branch is `interactive-attalambda`; PR #7 is open:
https://github.com/kserrec/attalambda/pull/7 . Main remains
`71232f7fb47f8daad61e6a7a6bcf4a5477532352`; public downloads remain 0.7.0.
Product version is 0.8.0 and package version is 0.8, unpublished.

## Source, checks and review

| Evidence | Exact result |
| --- | --- |
| Reviewed and built source | `3ae392629ecfb380d3dd31451c33fd5617d53f51` |
| Clean source tree | `550b4ae2c255929cff90d7fa823161030c7d7681` |
| Frozen-source CI | https://github.com/kserrec/attalambda/actions/runs/35010700799 — all 10 jobs pass |
| Full source suite | 69 Racket files; 26,845 assertions |
| Shared terminal suite | 43 methods, 51.387 seconds |
| Visual terminal suite | 6 methods, 3.902 seconds; owns 14 PTYs and 23 cursor/grid checks |
| Structural gates | 40 pure production modules; complete source inventory and boundary check |
| Portability CI | Linux distribution; Windows x86-64 and macOS Intel/ARM build/consumer checks pass; temporary transfer artifacts deleted |
| Scope | Runtime line input, checked lazy interactive entries, lexical snapshots, six commands, standalone loads, cancellation, reset, completion and bounded private history |
| Python | Standard-library-only test tooling; absent from the product archive; no pip dependencies |

The CI merge commit `2dcc67ef7f8fb17e8b2c7f88ce8d16a21c0c6761` has the exact
same tree as the build revision. Full log and parsed results:
`/tmp/attalambda-phase10-ci-complete.log`,
`/tmp/attalambda-phase10-ci-summary.json`, and
`/tmp/attalambda-phase10-ci-merge-tree.json`. Remote temporary artifacts: zero.

Independent source review:
`/tmp/attalambda-phase10-independent-review.md` and its 18-file hash manifest
`/tmp/attalambda-phase10-review.sha256`; final committed-scope reconciliation:
`/tmp/attalambda-phase10-closure-review-3ae3926.md` with JSON/SHA256 companions.
It covers the ten runner modules, changed language/runtime paths, boundary
ownership, purity, lazy binding retention, effects, input, cancellation, loads,
history/completion and repaired findings. Review limitations remain in those
reports; this is not a claim of exhaustive correctness.

Independent exact-artifact review:
`/tmp/attalambda-final-artifact-review-t48v0bdw/review.md`; adjacent structured
observations and `evidence-hashes.json` verify actual archive contents, frozen
source/guide/examples, dependency pins, both exact method sets, isolation and
cleanup. No actionable finding remains. No build or tests were rerun by that
reviewer.

Source verification uses the isolated corrected Racket CS 9.3 runtime:

```sh
env PATH=/tmp/attalambda-racket93-promise-candidate/bin:/usr/bin:/bin PLTUSERHOME=/tmp/attalambda-racket93-promise-user TMPDIR=/tmp ./run-all-tests.sh
```

The latest full local run also passes 69 files / 26,845 assertions, 43 shared
methods in 71.605s and 6 visual methods in 5.733s, plus both gates:
`/tmp/attalambda-interactive-phase9-full.log`. Current-source CI independently
reruns the complete script. The copied local raco runner does not support its
multi-file process submodule; individual invocations work and the full script
uses them. Do not repeat the failed multi-file invocation.

## Exact standalone Linux artifact

Directory: `/tmp/attalambda-interactive-candidate-01`.

| Item | Value |
| --- | --- |
| Archive | `attalambda-0.8.0-linux-x86_64.tar.gz` |
| Archive size | 19,602,521 bytes |
| Archive SHA-256 | `1b4b4a338028b11fafe22a4b52c7862c77f9c57e0241e4e037c6b022f6761785` |
| Internal `BUILD-MANIFEST.txt` SHA-256 | `e0597d0506f08ad0661c0dc9d1dab2ac1257afb8d799d3aca3cbb2725a44a95b` |
| Sibling `SHA256SUMS` SHA-256 | `a5382b07aa7190196f114536cf47e86d029a8017b43cc4cd934a88db25fc11ba` |
| Inventory | 11 regular files; 68,881,441 unpacked bytes; 2 runtime files |
| Build | Clean exact source; existing builder without `--allow-dirty`; exit 0 |
| Consumer | Exact transferred bytes; 25 CLI/transcript methods at each of two paths, all pass |
| Terminal timings | First path 67.185s; relocated path 78.388s |
| Other acceptance | Guide commands, hello/stdout/file/HTTP examples, public APIs, statuses, runtime input/snapshots, provenance and relocation pass |
| Isolation | No external Racket/raco or source checkout; private home; no personal initialization; offline except ephemeral loopback |
| Native terminal locale | C.UTF-8 for the two terminal test invocations; C retained for archive byte/sorting checks |
| Cleanup | Build/consumer containers absent; transfer directory removed; terminal children/descriptors restored and closed |

All five packaged examples match the frozen source bytes. The foundations
example is inventoried in the consumer; its execution is covered by the source
suite, not by a packaged-consumer invocation.

Completed invocation commands (do not rerun into the existing output path):

```sh
python3 /tmp/attalambda-interactive-candidate-build01.py 3ae392629ecfb380d3dd31451c33fd5617d53f51
python3 /tmp/attalambda-interactive-candidate-consumer01.py 3ae392629ecfb380d3dd31451c33fd5617d53f51
```

Build log `/tmp/attalambda-interactive-candidate-build-01.log` and receipt
`/tmp/attalambda-interactive-candidate-01/build-report.json` record exit 0.
Consumer log/report `/tmp/attalambda-interactive-candidate01-consumer.log` and
`.json` record exit 0 and cleanup. Combined parsed receipt:
`/tmp/attalambda-interactive-candidate01-summary.json`.

The builder image is the original official
`racket/racket:9.3-full@sha256:f9c540abe281413dc9e25bfbe6e35276f1a5bca1fa40213c40ac7bac6bb69c62`.
It installs Git and applies the pinned dependency corrections only inside the
disposable builder; source is read-only. The consumer reuses immutable image
`sha256:dabaae31057cbc79baf7e2afa65b8c8cfd378b5013e4e8a95a520265fc794803`, based on
pinned Ubuntu 24.04 with isolated Python 3.12.3 test tooling. It runs as UID 65534,
read-only filesystem, writable temporary memory filesystem, no capabilities,
no-new-privileges and bounded processes/memory. No test dependency enters the
archive. Prepared test-image cost was 14 packages, 7.274 MB download / 27.9 MB
installed, with no pip tree. First version startup 714ms / relocated 630ms are
observations, not guarantees.

## Verified corrections and historical failures

| Correction | Evidence and preserved scope |
| --- | --- |
| Completed shared Racket promises | Narrow pending-only redirection correction prevents cancellation poisoning completed shared values; upstream 261 tests plus original-fail/corrected-pass probes. `/tmp/attalambda-promise-independent-review.md` |
| Expeditor display/history | Exact source/display separation, control-width, narrow prompt and redraw corrections; independent 28 PTYs / 55 visual checkpoints, permanent 6-method regressions and stock negative control. `/tmp/attalambda-expeditor-final-cold-review.md` |
| Runtime preparation | Explicit isolated `--apply`; normal checks read-only. Exact source plus loaded implementation identity rejects stale caches; 15 permanent checks. `/tmp/attalambda-expeditor-preparation-review-ihudogrm/review.md` |
| Linux CI ownership | Only fresh CI `/usr/share/racket` transfers to job user before ordinary preparation. Original-image compiler/embedding proof; successful new-head CI. `/tmp/attalambda-phase9-checkpoint-review-7jrtn7b_/review.md` |
| Linux terminal fixture locale | Unchanged 72-name case fails under C, passes under C.UTF-8; direct input sibling proves native decoding. Only two invocation environments changed; all cases/deadlines preserved. `/tmp/attalambda-phase10-locale-review.md` |
| Separate output terminals | Actual two-PTY failure corrected using output-port identity; regression and exact boundary checks pass. `/tmp/attalambda-separated-output-hunter-after.log` |
| Fixture compilation | Initial full run failed six stale-adapter imports; all four Python-launched fixtures now compiled before the harness, and complete subsequent runs pass. |

Promise patch SHA-256:
`179be1bbde34542758c87b364ae7717c7355cba58cb880875faf137c521ab1a9`.
Corrected promise source:
`bca5b526943be123c8f3fbad24d30556fe3ffea1dc60b6d9c28ec8875e27c7eb`.
Expeditor patch SHA-256:
`954cdc83b8ee684512a5c3c131d4bc48dd30c40a6a6e8c5a884b3f46dc98b755`.
All five corrected Expeditor source hashes appear in the actual build manifest.
The 103,764-byte third-party notice hashes to
`d480dcda59df5e54a4185fa2293a04f6ff40ebf1e79712d29e51d8490b87b024`.

Earlier CI34994217012 and CI35008188837 remain failed historical runs; the latter
failed only the ASCII-locale Linux consumer. CI35010700799 verifies the correction.
Development07/08 archives are historical and are never substituted for this
candidate. Failed logs, diagnosis steps, focused commands, acceptance rows A01–A18,
phase commits and prior review detail remain in PLAN.md. The verbose prior handoff
is also preserved at `/tmp/attalambda-handoff-before-final-record.md`.

## Limits and safe continuation

Automatic rendering of raw untagged terms is unspecified; use `:echo off`.
A failed entry cannot roll back already demanded effects or shared promises.
Old closures can retain their captured binding graphs until unreachable or reset;
no replay or automatic compaction is promised. Linux x86-64 is the sole supported
public binary platform. Native Windows/macOS CI is portability evidence only.
Unicode editing under an explicitly non-UTF-8 native locale is not claimed.

Keep dotenv files opaque and excluded from every recursive content operation.
No unrelated work, personal/system runtime, or historical release was changed.
Git writes work as separate approved `git add`, `git commit`, and `git push`
operations; combined requests previously failed. Inspect the log before repeating
any effect. PR edits use GitHub REST PATCH with a JSON body file and readback;
legacy `gh pr edit` fails on projectCards in this environment.

No owned source worker, listener, builder or consumer remains running. Final
record-head CI and Git cleanup are recorded in the post-commit receipt named
above. Any further merge, tag or publication requires separate authorization.
