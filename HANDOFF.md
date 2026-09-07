# Session handoff

Status recorded 2026-09-07: pure-recursion implementation for target 0.5.0
is on `milestone-5-recursive-purity`, based on `0987c8a`. Kyle authorized
starting the supplied recursion specification after choosing 0.5.0.
Phase 1 implementation and verification are complete: all 41 test files
passed 14,209 assertions, expanded purity passed all 32 production modules,
and complete boundaries/source inventory passed. The cold reviewer confirmed
the final corrections with no remaining concrete issue. Kyle explicitly
approved verification, commit, and push; an earlier execution-tool rejection
did not come from him. This verified Phase 1 commit closes the implementation.
See PLAN.md for exact scope, corrections, and logs.

The active [PLAN.md](PLAN.md) controls this milestone. Phase 2 now has the
exact 0.5.0/0.5 version state, migration notes, and updated distribution
validation. Focused tests passed 564 assertions. The Linux consumer's embedded
recursive fixture was migrated to `rec`; its 31 public-API checks and the
release-note factorial example passed exact source-launcher probes.
Full verification passed all 41 suites with 14,210 assertions, 32-module
expanded purity, and complete boundaries/source inventory. The full log is
`/tmp/attalambda-050-full.log`; per-file counts are in
`/tmp/attalambda-050-verification.json`. No source test failure remains.
Phase 2 closes with the version/release-preparation commit on the same branch
and its PR to main. `gh pr view milestone-5-recursive-purity` identifies the
PR, exact head, and live CI state without relying on a stale copied status.
Next: evaluate CI/reviews, then obtain Kyle's approval before merge/release.

Merge to main requires explicit approval. No 0.5.0 release is published;
source metadata identifies 0.5.0, while current downloads remain 0.4.0.
Migration and prepared release notes are in
[docs/releases/0.5.0.md](docs/releases/0.5.0.md).
[docs/API.md](docs/API.md) distinguishes the new source recursion rules
from that published binary. The supplied spec is preserved verbatim in
[docs/recursive-purity-spec.md](docs/recursive-purity-spec.md).

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
