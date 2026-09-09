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
