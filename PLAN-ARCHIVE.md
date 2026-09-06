# Completed milestone ledger

This file records what the completed milestones established. It is historical
evidence, not authority to begin or extend work. [`PLAN.md`](PLAN.md) controls
current work; the [language specifications](docs/specifications/README.md)
control behavior; [`docs/ACCEPTANCE.md`](docs/ACCEPTANCE.md) maps the current
implementation to executable evidence. Git history retains the former
step-by-step plans.

Historical commits before Phase 27 may use the former `all_the_lambdas`,
`#lang alone_the_lambdas`, `.atl`, and `atl run` names. Phase 27 replaced those
with AttaLambda, `#lang attalambda`, `.attl`, and the direct `attalambda`
command. Historical public Nat references were superseded by Milestone 4.

## Milestone 1 — Pure language foundation

**Completed 2026-08-24; Phases 0–12.**

The repository established:

- a lazy unary-lambda core and mechanical `lambda`, `def`, and `let` syntax;
- closed Church type tags and a strict generalized curried checker;
- Michaelson-style List, structured Error, Bool and strict typed `if`;
- normalized binary Nat arithmetic, Result and safe division, Char, and
  UTF-8-backed String;
- framed Errors with deterministic argument positions;
- structural purity checks, exact public-surface checks, classified source
  locations, and a complete dependency inventory.

Nat was the public number during this milestone. Milestone 4 deliberately
retired that surface while preserving binary Nat as a private foundation.

## Milestone 2 — Effects and standalone language

**Completed 2026-08-27; Phases 13–20. Completion commit `aa980d2`.**

The milestone specified and implemented the one-bridge model:

- [`runtime/host.rkt`](runtime/host.rkt) became the sole native authority and
  sole producer of `host`;
- [`runtime/codec.rkt`](runtime/codec.rkt) became the deterministic conversion
  exception, imported in production only by the host;
- pure effect wrappers added stdout, whole-file operations, and blocking TCP;
- pure HTTP values, parser/renderer, routing, and a single-connection server
  were built from lambdas;
- the public `#lang` facade injected the same host into nine fixed wrappers;
- runnable examples and end-to-end tests proved fake-host traces and real
  stdout, filesystem, TCP, and loopback HTTP behavior.

The milestone did not claim sandboxing. A real-host program inherits the
launching process's relevant authority.

## Milestone 3 — Independent distribution

**Completed 2026-08-29; Phases 21–30.**

The milestone established the current source-launch and distribution shape:

- a strict `.attl` source contract, one-file trusted runner, fixed diagnostics,
  and statuses 0/64/65/66/70;
- a self-contained Racket CS 9.3 archive built in isolation with `raco exe`
  and `raco distribute`;
- independent Linux, macOS, and Windows build/consumer harnesses, relocation,
  legal-file pinning, manifest inventory, and external checksums;
- the Apache-2.0 license and AttaLambda public rename;
- novice download instructions and the first public release.

AttaLambda 0.2.0 was published from commit `42ff0a7` under annotated tag
`v0.2.0`. After a consumer Mac demonstrated a Gatekeeper block and the Windows
download path remained unsigned and untested on a client system, Kyle withdrew
the two macOS assets and Windows asset. Linux x86-64 became the sole supported
public binary. Exact original assets, hashes, IDs, retained files, and the
withdrawal record are preserved in the
[release ledger](docs/design/standalone-distribution.md#attalambda-020--2026-08-29).

### Maintenance and security corrections

The post-Phase 27 seam review removed duplicated trusted-boundary plumbing and
fixed concrete framing, canonical decoding, test-isolation, and coverage gaps
(`706acee`, `a9da8b7`, `505a46b`). A security audit then proved that a hostile
HTTP peer could cause unbounded request buffering; `be1fd1a` imposed the
current 8,192-byte cap.

One related performance finding remains intentionally deferred: the pure HTTP
parser re-parses the accumulated request after each chunk, so one connection
can consume O(cap²) interpreter work before rejection. Fixing it requires an
incremental-parser design rather than a local hardening patch. The bounded
limitation remains visible in [`docs/ACCEPTANCE.md`](docs/ACCEPTANCE.md).

## Milestone 4 — Exact rationals and foundational values

**Completed 2026-09-01; Phases 31–40. Acceptance commits `a1f125b` and
`f2ccf69`.**

The milestone amended the specifications first, then changed the language in
dependency order:

- binary Nat became a normalized private magnitude layer with quotient,
  remainder, gcd, lcm, parity, halving, and squaring exponentiation;
- private Int added sign and magnitude with one zero;
- private Rat added canonical reduction, exact arithmetic, division, and
  whole-exponent powers;
- strict tagged Rat became the only public number, with exact integer and
  fraction literals; public Nat/Int names and tag 3 were retired;
- all whole-number consumers and host fields moved to Rat;
- Unit replaced empty-List acknowledgements;
- Byte became distinct from Char, and file/TCP payloads became `List Byte`;
- Option and persistent Map completed the foundational values;
- the expanded purity proof grew to all 29 core and effects modules.

An adversarial pre-release review found ten concrete issues. Commits
`fb96dea`, `af6572a`, and `3254354` fixed them and received an independent cold
review. Durable corrections include distinct Error kinds 14/15/16, canonical
`NIL` from empty `MAKE-STRING`/`DROP`, linear Floyd cycle detection in codec
List decoding, canonical cached Byte/Char objects, effects-layer purity
coverage, and a raw TCP test peer that avoids cross-thread lazy-promise entry.

## AttaLambda 0.3.0 release

**Published 2026-09-02 from commit `1b51603`, annotated tag `v0.3.0`.**

The exact Linux x86-64 archive passed the clean Racket CS 9.3 build and the
independent digest-pinned Ubuntu 24.04 no-Racket consumer, then matched a fresh
public download. The release source passed 38 suites with 12,298 assertions,
the 29-module purity proof, and the complete boundary inventory. Exact archive
size, SHA-256, layout, and URL are in the
[release ledger](docs/design/standalone-distribution.md#attalambda-030--2026-09-02).

Two later CI-only repairs did not change shipped bytes: `a1a81bc` added 0.3.x
forms to the Windows archive-name check, and `cb3e226` raised the full-suite
workflow timeout from 10 to 20 minutes after logs proved cancellation rather
than a test failure. Run 33674071955 was fully green on that main-line tip.
