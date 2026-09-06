# Session handoff

Status recorded 2026-09-05: the refactor is complete, verified, pushed, and
awaiting Kyle's review. This handoff becomes stale if the branch changes after
the final wrapup commit, a pull request or merge is created, or `main` or the
public release changes.

The completed non-core simplification is on branch
`refactor/non-core-simplification`, based on
`578f1acc00566c17c18786a393cfa0b496c531ba`. Kyle authorized unattended
execution on 2026-09-05. [`PLAN.md`](PLAN.md) records the completed procedure
and evidence; [`docs/design/non-core-refactor.md`](docs/design/non-core-refactor.md)
defines the preserved behavior and reduction goal.

Phases 1 through 3 are committed and pushed:

- `1f08b78` — simplify the codec and native host dispatch;
- `2ee5205` — simplify runner call sites, readers, and shared test helpers;
- `b0081ab` — reduce redundant checker/test locks and historical documentation.

Phase 3 passed 12,297 assertions, the 29-module purity proof, and the complete
boundary inventory before its commit. Phase 4's independent review found no
production correctness or authority regression; its four bounded test/doc
findings were repaired, independently re-reviewed, and committed as `f772e8d`.
That exact revision passed all 38 suites and 12,301 assertions, both structural
gates, the clean Racket CS 9.3 Linux build, and the isolated no-Racket Ubuntu
consumer. [`PLAN.md`](PLAN.md) records the complete comparison and artifact
evidence. No confirmed finding remains.

The refactor is complete. Its final evidence commit changes only planning and
acceptance documentation outside the shipped package/archive inputs. Stop
here: do not open a pull request, merge, release, tag, or start later work
without Kyle's separate explicit request.

The current public release remains AttaLambda 0.3.0 at commit `1b51603` and tag
`v0.3.0`. Linux x86-64 is the sole supported binary target. Exact release and
withdrawal evidence is in the
[standalone-distribution ledger](docs/design/standalone-distribution.md).

Two post-release CI-only fixes on `main` do not affect published bytes:
`a1a81bc` accepts 0.3.x version forms in the Windows harness, and `cb3e226`
raises the suite workflow cap to 20 minutes. Main-tip run
[33674071955](https://github.com/kserrec/attalambda/actions/runs/33674071955)
was fully green.
