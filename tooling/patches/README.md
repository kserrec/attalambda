# Racket 9.3 dependency corrections

## Shared promises

Interactive cancellation exposed a defect in the existing Racket promise
implementation: a new demand can redirect an already completed shared value into
its running root, then cache a break that makes that prior value unusable.
Actual AttaLambda reader and session `NIL` values reproduce the failure.

`racket-9.3-completed-promises.patch` changes only the existing composable forcer.
Completed values, existing forwarding links, and running/cached-failure markers
retain their state. Newly demanded thunks still share their active root and cache
its failure. The original tail loop remains; no effects or promises are replayed.
This is a local dependency correction, not an upstream Racket release.

The upstream source is Racket's `racket/collects/racket/private/promise.rkt` at
[v9.3](https://github.com/racket/racket/blob/v9.3/racket/collects/racket/private/promise.rkt).
Racket's existing licenses remain in the distribution notices.

| Input | SHA-256 |
| --- | --- |
| Original source | `ad9009b58587dc5e326270e02d21788264abbc5b033cbef716521ff02663b628` |
| Corrected source | `bca5b526943be123c8f3fbad24d30556fe3ffea1dc60b6d9c28ec8875e27c7eb` |
| Unified patch | `179be1bbde34542758c87b364ae7717c7355cba58cb880875faf137c521ab1a9` |

Use `racket tooling/prepare-racket-runtime.rkt --apply` only with an isolated,
task-owned Racket CS 9.3 installation. This explicitly changes that installation's
promise and editor sources; it refuses unknown source bytes and does nothing if already
corrected. Do not apply it to a personal or system installation. In a fresh process,
`racket tooling/prepare-racket-runtime.rkt --check` verifies both source hashes and
loaded behavior without mutation. Ordinary tests and builders must only check;
isolated environment preparation owns the explicit apply step.

The original Racket image remains pinned. Builds must record both patch and
corrected-source hashes in their manifests. Verification requires the upstream
promise tests, permanent cache/cancellation/retention regressions, actual terminal
recovery, full source gates, and the exact standalone consumer. See `PLAN.md` and
`HANDOFF.md` for current evidence; an isolated patch test is not a release candidate.

## Expeditor source display and redraw

`expeditor-1.2-source-display.patch` corrects the existing Expeditor 1.2 snapshot
at [65e20a410bdc5f09c0682a1bb57cac2b68d73506](https://github.com/racket/expeditor/tree/65e20a410bdc5f09c0682a1bb57cac2b68d73506/expeditor-lib).
It preserves every source character and completion name, while displaying C0/DEL
controls as caret notation and C1 controls as ASCII hex. A character that cannot
fit anywhere in an extremely narrow terminal displays as `?`; its source remains
intact. History reconstruction preserves tabs and carriage returns.

The existing terminal operations and complete redraw handle width-changing edits.
The correction also aligns completion-list widths, continuation prompts, resize
caches and source/UI newline handling. The configured prompt is restored when a
narrow terminal widens. No product code imports private editor APIs.

Patch SHA-256:
`954cdc83b8ee684512a5c3c131d4bc48dd30c40a6a6e8c5a884b3f46dc98b755`.
`../prepare-expeditor-runtime.rkt` pins original and corrected hashes for all five
changed files and applies the exact patch without an external patch executable.
The ordinary preparation command above includes both dependency corrections;
its read-only check also verifies loaded editor behavior. Manifests record the
patch and all five corrected-source hashes, checked by every native consumer.
The original upstream licenses remain in the distribution notices.

Independent verification covers 28 terminal interactions and 55 cursor/grid
checkpoints, including the reproduced history, wrapped deletion, stale cells,
indentation, continuation-row and narrow-screen failures. Full product and
standalone candidate evidence remains governed by the active plan.
