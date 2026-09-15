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
