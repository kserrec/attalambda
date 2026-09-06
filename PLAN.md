# HTTP, empty-List consistency, and explicit exit plan

Status: approved for serial execution on 2026-09-05; Phase 0 complete;
Phase 1 next.
Branch: `refactor/non-core-simplification`; no new branch.
Verified baseline: `6663ad6c55a71791df1db768652089cabcce6496`, with a clean
working tree before this planning edit.
Source: [Kyle's HTTP/List/exit specification](/home/serrecchia/Downloads/ATTALAMBDA_HTTP_LIST_EXIT_SPEC.md),
SHA-256 `b57cfc8a694ac9af02b60d50cec950ea66706641b60922c6181aed9912903e1f`.
The three [language specifications](docs/specifications/README.md) remain
normative; Phase 0 explicitly amends them before adding the new effect.

## Size and verified starting state

Three bounded changes, with five Phases and thirteen single-pass Steps as
the supplied specification requires. This is smaller in implementation scope
than the completed non-core refactor, but not three tiny passes. Empty-List
consistency is expected to require tests only; HTTP changes two existing
production modules; exit adds one small effect across existing layers.
Specification, checker, subprocess, and packaged acceptance work account for
the remaining Steps. The prior baseline full suite took about 23 minutes;
five required Phase runs plus the Linux build/consumer make verification a
material part of the work. That is prior timing, not a new runtime estimate.

- **HTTP exists:** `effects/http-server.rkt:161` implements
  `raw-read-http-request-step` with `raw-string-append`, whole-List length,
  and `parse-http-request` after each read. `effects/http.rkt:663` first
  scans for `CR LF CR LF` and returns incomplete until it is present. The
  existing parser can therefore remain the sole semantic parser.
- **Canonical reconstruction exists:** `raw-rebuild-list` in
  `core/lists.rkt` is already used by `MAKE-STRING` and public `DROP`.
  `runtime/codec.rkt:105` accepts only the canonical `NIL` terminator.
  A read-only planning probe passed all 18 requested empty-producing cases,
  checking both codec conversion and canonical List/String termination.
  The existing `tests/codec-test.rkt` suite passed 144 tests. The expanded
  persistent regression matrix has not yet been written.
- **Public exit is new:** no `effects/exit.rkt`, `tests/exit-test.rkt`,
  public exit binding, protocol entry, or host performer exists. The protocol
  and real dispatcher each contain nine operations. Native exit currently
  appears in the runner's launcher-failure path. Existing bounded Rat
  decoding and language host injection can be reused.

## Change boundary and execution

The planning turn changed only `PLAN.md`; the completed plan below is retained
as history. Kyle approved all five Phases on 2026-09-05 after discussing purity
and the exit boundary. Execute them serially without routine reconfirmation.
This named work is separate from the previous plan's final stop.

The approved scope modifies the two HTTP modules, protocol, real host, language
expander, directly affected tests/checkers, normative specifications, current
documentation, and existing Linux consumer harness named below. Create only
`effects/exit.rkt` and `tests/exit-test.rkt` as new production/test modules.
List producers change only if the persistent matrix proves a specific failure;
the planning probe gives no present reason to modify one.

Behaviorally unchanged: List representation and codec acceptance; existing
HTTP grammar, 8192-byte cap, trailing-data rejection, error propagation,
cleanup, and laziness; all nine existing host operations; launcher failure
statuses; normal status-0 completion without explicit exit. Intended changes
are incremental HTTP work and the new explicit program-chosen exit effect.
No dependencies, new runtime layer, generic streaming parser, HTTP bodies,
concurrency, timeout, TLS, stderr effect, process spawning/signals, exit codes
2..255, automatic Error printing, or final-value/status inference.

Before each Step, read `AGENTS.md`, all three normative specifications, the
named production files, and directly relevant tests. Execute and record one
Step at a time in source order; each numbered Step is one pass. Run focused
tests while working and both architectural checkers after production edits:
`racket tooling/check-purity.rkt` and `racket tooling/check-boundaries.rkt`.
After every Step, inspect `git diff --check` and the complete relevant diff,
explicitly excluding `.env`, `*.env`, `.env.*`, and `*.env.*` from every
recursive listing/search/bulk read or diff. Never inspect dotenv contents.

At each Phase boundary, run `./run-all-tests.sh`, then obtain a fresh agent
review focused only on that Phase's diff and direct interactions. Prove causes
before repairs; fix serially, at most ten findings per batch, obtain fresh
review of repairs, and repeat invalidated checks before continuing. Record
executable, test/tooling, and comment/doc changes separately. Commit and push
each verified Phase only to this branch. Use isolated temporary filesystem
fixtures, ephemeral loopback ports, and existing finite test deadlines.
Stop on a normative conflict, a broad List representation problem, or two
failed diagnostic hypotheses. No unrelated cleanup or weakened checks.

## Phase 0 — Specify exit (one Step)

### Step 0.1 — Amend the normative contract

- [x] Append dated amendments to the three normative specification files;
  update precedence/provenance and hashes in `docs/specifications/README.md`.
  Specify public `(exit status)`: Rat 0/1 only; wrong type yields ordinary
  TypeMismatch Error, other Rats yield existing InvalidCount Error, and
  incoming Error bubbles. Pure code validates/chooses; only the real host
  terminates with the requested OS status and does not return. Fake hosts
  may return. Runner-native exit remains launcher/source scaffolding;
  Error/Err values never automatically determine process status. Programs
  without exit retain normal status 0. No production changes in this Step.
  Run the full suite, diff checks, and Phase review before committing.

Step 0.1 result (2026-09-05): appended all three amendments, updated the
index's precedence and SHA-256 provenance, and verified that every original
byte remains an exact prefix. Executable/test changes: none. Documentation:
the approved plan and four specification documents. `./run-all-tests.sh`
passed all 38 suites; expanded purity passed 29 production modules and the
repository-wide boundary gate passed. Exact-file diff checks passed. Fresh
Phase 0 review found zero confirmed issues. No repairs were needed.

## Phase 1 — Prove empty-List consistency (two Steps)

### Step 1.1 — Persist the codec consistency matrix

- [ ] Extend the canonical-empty section of `tests/codec-test.rkt`. Generic
  Lists: `NIL`, singleton `TAIL`, nonempty `TAKE 0`, exact/beyond-length
  `DROP`, `TAKE 0` after another List operation, and empty `DROP` after
  `TAKE`. List Byte: singleton `TAIL`, `TAKE 0`, exact/beyond-length `DROP`.
  Strings: `MAKE-STRING NIL`, singleton `STRING-TAIL`, append two empty
  Strings, and `BYTES-TO-STRING NIL`. Also convert empty String and singleton
  String tail to bytes; compose `"A" -> STRING-TO-BYTES -> DROP 1 ->
  BYTES-TO-STRING -> STRING-TO-BYTES -> codec`. Assert empty host List/bytes
  and canonical `NIL` where required, retaining forged-terminator rejection.

### Step 1.2 — Verify; repair only a proven producer

- [ ] Run codec, List, and String suites, plus List-count/Byte suites if
  their producers change. If all cases pass, retain only the regression
  tests. Otherwise name the failing producer and repair its smallest pure
  reconstruction path using canonical `NIL`/existing `raw-rebuild-list`.
  No codec loosening or List redesign; stop if the cause is broader. Run
  applicable checkers, full suite, and Phase review before committing.

## Phase 2 — Incremental HTTP framing and accumulation (three Steps)

### Step 2.1 — Add the pure delimiter scanner

- [ ] Add `raw-scan-http-header-end` in `effects/http.rkt`, returning a raw
  Pair of found flag and next suffix. Inspect only the new chunk plus at
  most three preceding characters, using existing pure List/String tools;
  retain at most the last three characters when incomplete. Extend
  `tests/http-test.rkt` for a whole delimiter, all three internal delimiter
  splits, byte-at-a-time input, overlapping CRs, near matches, empty chunks,
  trailing characters, and every two-chunk split of a complete valid request.

### Step 2.2 — Replace the server's repeated prefix work

- [ ] Change `effects/http-server.rkt` loop state to reversed accumulated
  characters, running private binary Nat count, and at-most-three-character
  suffix. Convert/count/reverse only the new chunk; prepend its reverse
  without walking the old prefix. Check the running count against 8192
  before parsing. Scan suffix plus chunk; incomplete nonempty reads recur
  without full parsing. At completion or EOF, reconstruct once and call the
  existing parser once. Include all bytes from the completing chunk so
  trailing-data rejection stays intact. Update the loop's obsolete comments;
  preserve callers, cleanup, EOF and failure behavior. Run both HTTP suites.

### Step 2.3 — Verify server behavior across chunk boundaries

- [ ] Extend existing fake-host tests in `tests/http-server-test.rkt` for
  one chunk, one byte per chunk, every nonempty two-chunk split, and each
  delimiter split. An empty TCP read remains EOF, not an interior fragment.
  Pin premature EOF, exactly 8192 and over-cap requests, malformed and
  unsupported requests, trailing data, read failures, cleanup, read order,
  and repeated-forcing laziness. Review source to prove no full parse on
  incomplete chunks, no repeated old-prefix append traversal, and no whole
  request recount. Run both HTTP suites, checkers, full suite, and review.

## Phase 3 — Add public exit 0/1 (four Steps)

### Step 3.1 — Construct and validate the pure exit request

- [ ] Create peer `effects/exit.rkt` and `tests/exit-test.rkt`; extend
  `effects/protocol.rkt` with `exit-function-name`, `exit-operation` and
  the closed operation-table entry. Request: List `["exit", Rat(status)]`.
  Reuse the generalized checker, existing raw Rat primitives, and request
  dispatch/bubbling pattern. Validate 0/1 before calling the injected host.
  Test both encodings, unary shape, no call before forcing, exactly one call
  per valid status, TypeMismatch, InvalidCount for `-1`, `2`, and `1/2`,
  incoming Error, and fake-host return propagation. Verify direct malformed
  protocol requests retain InvalidHostRequest behavior. Change checker
  inventories only as required.

### Step 3.2 — Perform explicit process termination in the real host

- [ ] Extend `runtime/host.rkt` with the tenth dispatch case and
  `perform-exit`; reuse `decode-bounded-count` with bounds 0 and 1 for
  defensive canonical whole-Rat decoding. No automatic output, final-value
  inspection, Error mapping, or returning `Ok UNIT` after successful real
  exit. Update `tooling/check-boundaries.rkt`, host tests, and
  `docs/design/host-boundary.md` for this exact capability. Successful real
  calls run only in child processes; malformed requests must not terminate
  tests. Native exit remains forbidden in pure effects, codec, and readers.

### Step 3.3 — Expose the canonical public binding

- [ ] In `lang/expander.rkt`, inject `language-host` once into `make-exit`,
  bind internally as `language-exit`, and rename/export as `exit` without
  colliding with native Racket exit. Update language tests and exact
  import/export/injection checks; run boundary/purity suites as applicable.
  Add no other public alias or constant; runner production behavior stays.

### Step 3.4 — Prove operating-system statuses and sequencing

- [ ] Extend existing runner/subprocess tests with temporary public-only
  `#lang attalambda` programs: exit 0/1 gives exact status and empty output;
  no exit, including `(DIV 1 0)` and ordinary Error, remains status 0;
  missing-file Err chosen fatal/recoverable gives 1/0; stdout before exit
  appears, stdout afterward does not; an unselected exit branch stays lazy.
  Run exit, host, language, runner suites, both checkers, full suite, and
  Phase review. Pure AttaLambda makes every fatal/recoverable decision.

## Phase 4 — Documentation, packaged behavior, acceptance (three Steps)

### Step 4.1 — Synchronize current documentation

- [ ] Update `README.md`, `ARCHITECTURE.md`, `docs/design/host-boundary.md`,
  and `docs/ACCEPTANCE.md` for ten operations, public exit 0/1, unchanged
  no-exit completion and launcher statuses, and incremental HTTP work.
  Also update the shipped `distribution/GETTING_STARTED.md.in` status table,
  which currently has no explicit program-exit entries. Remove the
  deferred quadratic HTTP finding only after both parsing and prefix
  accumulation/count repetition are eliminated. Preserve the blocking,
  single-connection limitation; no new timeout/nonblocking claims or old
  milestone narration. Record observed implementation separately from plans.

### Step 4.2 — Extend existing Linux consumer checks

- [ ] Extend `tooling/test-linux-distribution.sh` and directly relevant
  `tests/distribution-test.rkt` checks to prove packaged exit 0, exit 1,
  and unchanged no-exit status 0, including captured stdout/stderr. Reuse
  existing temporary programs, status capture, and consumer isolation;
  no new distribution framework, artifact policy, version, or release.

### Step 4.3 — Final acceptance and fresh review

- [ ] Run the full suite and both checkers; review only this milestone's
  changes with a fresh agent. In isolated temporary fixtures, prove checker
  rejection of native computation in pure HTTP framing and native exit in
  effects, codec, and a reader; retain no mutations. Resolve proven findings
  and rerun invalidated checks. Build a recorded clean implementation commit
  with the existing Racket CS 9.3 Linux harness and run the independent
  no-Racket consumer. Record revision, checksum, packaged 0/1/default
  statuses, and pure program decisions making a missing-file Err fatal or
  recoverable. Keep acceptance artifacts unpublished. Commit/push verified
  results on this branch and stop: no pull request, merge, tag, or release
  without Kyle's explicit approval. Any later evidence-only commit must be
  distinguished from the implementation revision actually tested.

---

# Completed non-core simplification plan

Status: complete on 2026-09-05; pushed for Kyle's review. The permanent stop
at the end of Step 4.2 now applies.
Branch: `refactor/non-core-simplification`.
Starting commit: `578f1acc00566c17c18786a393cfa0b496c531ba`.

**The result must contain less code, less indirection, and less maintenance.**
The [refactor specification](docs/design/non-core-refactor.md) defines the
preserved contracts. The [language specifications](docs/specifications/README.md)
remain normative. This replaces the rejected 63-step proposal; it is not
that proposal compressed into fewer headings.

## Scope and execution

Thirteen Steps in four Phases. Each Step is one bounded change or verification;
prerequisites are completion of the previous Step and its required checks.
Execute Steps serially without routine permission requests under Kyle's
approval. Keep each Step bounded and record its result before continuing.

Work in existing modules. No new runtime layer, request types, codec importer,
prelude, literal module, generic checker, dependency, or review framework.
Pure lambda computation is protected wherever it occurs, including effects
and terms generated by macros. No List/sentinel, pathname-policy, process-exit,
public-language, resource-lifecycle, or distribution-policy redesign.
The only planned diagnostic correction replaces obsolete Nat wording with Rat.

Before each edit, name the existing code to remove, why the complete result
will be easier to follow, and the behavior checks. Revise or drop a candidate
that cannot meet those conditions; keep necessary working code. Do not create
extra work to make a Step end with a patch. Supporting edits are limited to
the affected tests, comments/docs, this plan, and the minimum existing checker
rules needed for the exact change. They cannot weaken authority.

Record concise results under the Step: files changed, removed logic, source
line difference, checks, and any no-change decision. Count helpers and callers
together. No whitespace compression, comment stripping, moved-code accounting,
or deleted safeguards to manufacture a reduction. Test additions need a
specific regression they catch. Compare implementation, tests/tooling, and
documentation separately, as well as maintained code overall.

Use focused suites first and both architectural checkers for production edits.
Run the full suite before each Phase commit; a current unchanged passing run
also satisfies the pre-commit check. Review each completed diff. At the runtime
and application Phase boundaries, check the changed paths together for real
bugs. Prove a cause before fixing it, fix serially, check siblings, and obtain
fresh review of bug/test repairs before commit under the repository rules.
At most ten fixes belong in a review batch. Zero findings is a valid result;
revisit only an actual finding or an evidence-invalidating change.

Never inspect dotenv contents, even synthetic fixtures. Every recursive
listing/search/bulk read and Git diff excludes `.env`, `*.env`, `.env.*`,
and `*.env.*`; do not follow links to them. Use isolated temporary fixtures,
ephemeral loopback ports, and finite test-harness deadlines. No Graphify.

A failed required check, normative conflict, excluded repair, or unavailable
mandatory environment is a blocker. Diagnose without speculative code edits;
after two failed hypotheses stop and report. Do not weaken tests, increase
timeouts to hide failures, or add unplanned rewrites. Adding a new workstream
requires Kyle's decision; this plan must not grow back into the rejected one.

## Phase 1 — Simplify the existing runtime

### Step 1.1 — Establish the baseline and removal targets

- [x] **Scope:** this plan and the execution/Git paragraphs of `AGENTS.md`.
  Record the approved branch, serial execution, and final stop; preserve all
  language and authority rules.
- **Work:** record source/public-export inventories, source line totals,
  current tools, and full-suite/checker results. Verify the pinned Racket CS
  9.3 Linux build/consumer path is available before production edits. Inspect
  the named candidates below and record concrete removals; no speculative
  module split. Use this plan for evidence, not another planning document.
- **Check:** `./run-all-tests.sh` passes, mandatory tools are usable without
  paid usage or privileged system changes, and no unexplained edits exist.
  Historical release runs and preliminary 8.10 probes are not this baseline.
- **Result (2026-09-05):** the unchanged starting commit passed all 38 test
  files and 12,298 assertions; purity passed for 29 production files and the
  repository-wide boundary inventory passed. The run used local Racket CS
  8.10 and took about 23 minutes. Docker already contains the exact full
  `racket/racket:9.3-full` builder image and digest-pinned Ubuntu consumer;
  direct probes confirmed Racket CS 9.3 and `main-distribution`, so final
  acceptance needs no paid or privileged setup.
- **Inventory:** 29 pure/effect production modules, 7 non-pure production
  modules, 13 readers, 42 test/support sources (38 suites), 8 tooling sources,
  and the CI workflow are inventoried. Baseline line totals are 5,510 pure,
  2,057 non-pure implementation, 13,478 tests/support, and 6,731 tooling/CI:
  27,776 maintained code lines overall and 22,266 in the refactor comparison
  surface. The exact public-surface gate passed; in the edited runtime it locks
  `host` as the sole host export and the existing codec struct/conversion/Result
  exports. No public export is scheduled to change.
- **Concrete removals:** replace the two repeated eager List-to-immutable-bytes
  pipelines and `first-codec-failure` walk with one local concrete operation;
  replace dispatch length/position plumbing with direct argument cases while
  retaining each named operation and performer; collapse paired POSIX/Windows
  membership calls into one closed helper. Later candidates remain conditional:
  the copied runner diagnostic bodies in the boundary gate have direct behavior
  coverage, while macro/reader/helper sharing must reduce its complete call
  path or remain unchanged. All current edits are the approved planning files.

### Step 1.2 — Remove duplicated codec conversion plumbing

- [x] **Scope:** `runtime/codec.rkt`.
- **Change:** simplify the repeated List decoding, first-failure selection,
  and immutable-byte construction in `object-string->bytes` and
  `object-byte-list->bytes`. Share only that concrete repeated operation
  locally if it shortens both callers. Keep the two-way API and all existing
  representation, evaluation-order, range, copy, and cycle checks.
- **Check:** `tests/codec-test.rkt`, then host/file/TCP callers. The complete
  codec is shorter and easier to trace, or the existing direct code is retained.
  No new representation acceptance or universal conversion mechanism.
- **Result (2026-09-05):** `object-list->immutable-bytes` now owns the two
  identical eager decode/failure/freeze pipelines; `first-codec-failure` and
  both duplicate blocks are gone. The public codec is unchanged and is 12
  lines shorter; the vocabulary edit only records the replacement names.
  Codec tests passed 144 assertions, direct host/file/TCP tests passed 353,
  and both purity and boundary gates passed.

### Step 1.3 — Shorten native request dispatch

- [x] **Scope:** `dispatch-request`, `dispatch-*`, and
  `decode-bounded-count` in `runtime/host.rkt`.
- **Change:** consolidate repeated arity and argument-selection branches into
  straightforward cases in this module. Keep concrete argument decoding and
  the existing performers; remove superseded dispatch plumbing. No request
  structs, schema, generated dispatch, callback framework, or second route.
- **Check:** `tests/host-test.rkt`, `tests/file-host-test.rkt`, and
  `tests/tcp-host-test.rkt` preserve all nine operations, left-to-right
  rejection precedence, malformed requests, ranges, and actual effects.
- **Result (2026-09-05):** `dispatch-request` now strips and counts arguments
  once and keeps each operation's arity/decode path beside its route. Seven
  intermediate dispatch functions are gone; one two-line `wrong-arity` helper
  serves all routes, and the two genuinely identical one-String operations
  retain their small shared helper. `host.rkt` is 18 lines shorter. The 353
  direct host/file/TCP assertions and both architecture gates passed.

### Step 1.4 — Remove repeated host error plumbing

- [x] **Scope:** `errno-in?`, the two native failure mappings, and trivial
  error wrappers in `runtime/host.rkt`.
- **Change:** simplify repeated POSIX/Windows membership tests and equivalent
  error forwarding. Keep every existing code/category and OS mapping, UTF-8
  handling, and meaningful cleanup helper. Do not redesign handles, write
  loops, close ordering, or resource registration.
- **Check:** host/file/TCP suites, including failure cleanup and partial writes.
  Review the changed host/codec path together for correctness and reading
  effort; retain only improvements. Run Phase checks, commit, and push.
- **Result (2026-09-05):** `errno-in?` now selects the existing POSIX or
  Windows number list itself, removing 13 paired/custom membership branches
  without moving any number or category. The file/network wrappers remain
  because they separate mapping from Error construction for multiple callers.
  This Step removes 11 more host lines; Phase 1 removes 41 runtime lines total.
  A scoped bughunt close-read both runtime modules and every changed branch,
  traced all nine pure request shapes, checked the prior codec cycle/canonical
  fix, and compared every OS mapping. Direct tests and checkers were skimmed
  for their interactions; unrelated code was outside scope. There were zero
  confirmed, likely, or latent findings. The full suite passed all 38 files
  and 12,298 assertions, followed by the 29-file purity proof and complete
  boundary inventory.

## Phase 2 — Simplify application glue where it earns its place

### Step 2.1 — Simplify runner validation and diagnostics

- [x] **Scope:** `runner/attalambda.rkt`.
- **Change:** remove repeated preflight or exception plumbing only where
  existing behavior is demonstrably preserved. Replace custom path work with
  an ordinary Racket operation only if it preserves the current path policy
  and diagnostics. Correct the unsupported-literal message from Nat to Rat.
  Keep current symlink/dotenv restrictions, source loading, and exit behavior.
- **Check:** `tests/runner-test.rkt` and `tests/language-test.rkt`: paths,
  links/cycles, unavailable/nonregular inputs, UTF-8/header/syntax, sanitized
  failures, version/help, and unchanged Error/Err completion. A resolver change
  that needs a new policy is omitted rather than turned into another project.
- **Result (2026-09-05):** `stop` now defaults its line and column, removing
  the repeated `#f #f` plumbing from every locationless caller without adding
  a helper; the runner remains 251 lines and is 92 bytes shorter. Its stale
  unsupported-literal diagnostic now says exact Rat and String. A filesystem
  probe showed that Racket's ordinary path simplifiers do not resolve an
  intermediate parent link, so the tested custom resolver remains. All 181
  runner and 82 language assertions passed, as did both architecture gates.

### Step 2.2 — Reduce repeated compile-time emission

- [x] **Scope:** `macros/macros.rkt` and `lang/expander.rkt`.
- **Change:** share existing bit/List emission only if a small helper in an
  existing module reduces total code while keeping use-site and definition-site
  bindings explicit. Otherwise keep the small direct implementations. Preserve
  the public prelude, one-time host injection, and generated pure terms.
- **Check:** macro/language/purity suites, public-export comparison, hygiene,
  shadowing, literal encodings, laziness, and exactly-once effects. No new
  literal/prelude module, renaming layer, or native object-language computation.
- **Result (2026-09-05, no code change):** the similar emitters require
  opposite binding contexts: function-name expansion deliberately creates
  caller-context identifiers, while language literals capture the expander's
  imports against user shadowing. Sharing them would require a cross-phase
  generic context API and increase the complete call path. The existing direct
  code stays. Macro/language tests passed 94 assertions; the preceding boundary
  and purity gates preserve exact exports, hygiene, and generated pure terms.

### Step 2.3 — Trim only useful reader and test-helper duplication

- [x] **Scope:** existing `readers/` modules and
  `tests/helpers/lazy.rkt`, `tests/helpers/values.rkt`, and
  `tests/helpers/fresh-language.rkt`, with affected callers.
- **Change:** remove concrete unused or repeated support code only when the
  whole call path becomes smaller. Keep short local helpers when sharing
  them would increase reading effort. Preserve reader output, subprocess
  isolation, staging exclusions, deadlines, cleanup, and real installed tests.
- **Check:** affected reader tests plus language/runner/distribution suites.
  Review this Phase's changed paths for hygiene, laziness, unintended effects,
  and diagnostics. No rendering, mocking, or process framework. Run Phase
  checks, commit, and push; a justified no-change result needs no extra sweep.
- **Result (2026-09-05):** ten small readers now show their one to three
  `force` applications directly, removing ten copied `lazy-apply` definitions
  and 30 reader lines; the two readers where the helper prevents difficult
  nesting retain it. `apply2` and `apply3` now live once in the already-imported
  lazy test helper, replacing 21 identical local definitions across 14 tests
  and removing 87 test/support lines net. No assertion or import edge changed;
  broader `typed-value?` sharing was rejected because it would couple unrelated
  suites to the object-value helper. Focused reader tests passed 6,263
  assertions. A Phase bughunt close-read every executable/helper change and
  mechanical removal and skimmed surrounding callers; unrelated test bodies
  were outside scope. It found zero confirmed, likely, or latent bugs. The
  Phase full suite passed all 38 files and 12,298 assertions, purity passed 29
  files, and the complete boundary inventory passed.

## Phase 3 — Reduce maintenance in checks, tests, and documentation

### Step 3.1 — Remove only demonstrably redundant boundary locks — complete

- [x] **Scope:** `tooling/check-boundaries.rkt` and its focused tests.
- **Change:** start with the copied runner diagnostic bodies and their
  duplicate checks. For each removal, name the promise, remaining enforcement,
  and behavioral test. Keep any rule still needed to restrict capability.
  No new binding-analysis mechanism or replacement of all class rules.
- **Check:** boundary/runner suites; isolated violations still fail for the
  intended reason, and an equivalent private change passes each removed lock.
  Preserve closed imports, implicit/renamed capability restrictions, sole host
  authority, exact public surfaces, and rejection of unknown source locations.
  Keep the expanded purity checker; change only mechanical references required
  by an earlier Step. A smaller blacklist is not equivalent enforcement.

**Result:** Removed the checker's copied `stop` and
`syntax-failure-reason` bodies and the exact-body comparison, deleting 40
checker lines. Those copies protected diagnostic behavior, which
`tests/runner-test.rkt` already verifies through the real command surface.
The checker still requires the exact runner definition set, imports, exports,
status definitions, input targets, entry/load shape, closed vocabulary,
capability restrictions, and repository inventory. An isolated fixture
reordered the side-effect-free operands of `stop`'s private location condition
and passed the remaining boundary rules; the old exact-body lock would have
rejected it. The boundary and runner suites passed 296 assertions, and the
complete boundary inventory passed.

### Step 3.2 — Remove superseded test machinery without losing protection — complete

- [x] **Scope:** only tests and fixtures affected by Steps 1.2–3.1.
- **Change:** remove source-copy/private-name assertions superseded by proven
  behavior or capability checks, and their unused fixtures. Reuse existing
  coverage. Approval of this plan permits those evidenced replacements;
  necessary regression tests and sole coverage stay.
- **Check:** run affected suites and a targeted isolated mutation for each
  replacement's named promise. A test that fails only from malformed syntax
  proves nothing about the intended rule. Review repaired tests freshly;
  no coverage quota, new test tier, or repeated whole-suite audit.

**Result:** Audited the affected host, codec, runner, boundary, reader, and
shared-helper tests under the project rule that tests need a named failure and
must preserve behavior, invariants, error propagation, partial application,
and laziness where applicable. The only redundant machinery was a seven-line
runner assertion that counted the private loader expression before replacing
it in a fault-injection fixture. The boundary checker independently enforces
exactly one `(dynamic-require source-path #f)` call. An isolated duplicate-call
mutation failed with `invalid-runner-entry-or-loader`, so the private count was
removed. The fault-injection fixture remains: changing the generic failure
handler to expose `exn-message` produced exactly two failures in that fixture,
proving it still catches raw-detail leakage. No other assertion was removed;
the same-layer candidates protect distinct argument precedence, conversion,
resource-lifecycle, or representation cases. The restored runner suite passed
all 180 assertions. A fresh reviewer close-read the affected checker/test diff
and rules, independently confirmed that the equivalent private `stop` change
passes while a duplicate loader call fails, and confirmed the diagnostic
fixture catches raw-detail leakage. It found no blocking defect. The reviewer
also caught an overbroad test comment: source validation is proven by runner
behavior, while the structural rule proves that the one loader call uses
`source-path`; the comment now states that exact division.

### Step 3.3 — Make the current system quick to understand — complete

- [x] **Scope:** the non-pure architecture passages in `ARCHITECTURE.md`,
  `README.md`'s repository guide, and `docs/design/host-boundary.md`.
- **Change:** give each role a short explanation and real entry points:
  host performs effects; codec converts; frontend emits/injects; runner loads;
  readers observe; checkers enforce. Remove duplicated current descriptions
  and stale phase narration. Keep pure representation reference material,
  canonical specifications, and the exact current host contracts.
- **Check:** trace claims to code. A maintainer can explain a host request and
  conversion from host/codec alone, following only relevant named functions.
  Other roles have equally direct entry points. No new documentation framework.

**Result:** Replaced the architecture's milestone-by-milestone narration and
test catalog with a task-based reading map, the five-step host path, concise
frontend/runner/reader roles, the current dependency directions, and the two
actual structural gates. Rewrote the host-boundary document around the current
Rat, Unit, and `List Byte` contract instead of retaining an obsolete contract
under a later amendment; all nine operations, bounds, results, failure codes,
byte/path rules, lifecycle guarantees, authority, and approval remain stated.
The README repository table now points directly to host, codec, expander, and
runner entry files. The three documents fell from 1,743 to 903 lines. The pure
representation/runtime-typing reference remained unchanged in this Step.
Final review later corrected three pre-existing public Nat sentences to the
implemented Rat boundary while leaving the private Nat descriptions intact.
Every local link resolves. Claims were traced to
`dispatch-request`/`perform-*`, the codec exports, pure request constructors,
the expander bindings, runner flow, reader exports, and both checker entry
points.

### Step 3.4 — Remove obsolete process narration

- [x] **Scope:** `HANDOFF.md`, `docs/ACCEPTANCE.md`,
  `docs/design/standalone-distribution.md`, and the two existing plan archives.
- **Change:** remove duplicated session instructions and stale active plans;
  retain unique release evidence, legal text, current platform constraints,
  and the deferred HTTP-parser finding in a clearly marked existing home.
  Do not archive the rejected refactor proposals into more repository docs.
- **Check:** retained facts and local links remain intact; historical records
  cannot authorize new work. No distribution script, CI workflow, release,
  support policy, or legal-byte change. Run Phase checks, commit, and push.

**Result:** Replaced repeated phase narratives with one 107-line current
acceptance map, one 297-line distribution contract/release ledger, one 132-line
completed-milestone ledger, and a 32-line active handoff. Deleted the second
plan archive after moving its unique Milestone 4 outcomes, correction record,
0.3.0 evidence, and deferred HTTP-parser finding into those existing homes.
These five files fell from 4,043 to 568 lines, removing 3,475 documentation
lines. Exact 0.2.0/0.3.0 commits, tags, artifact names, sizes, IDs and hashes;
the desktop withdrawal record; legal hashes; Racket CS 9.3 build/consumer
contract; Linux-only support; publication authority; and the bounded O(cap²)
finding remain explicit. All local links resolve, the legal bytes retain their
approved hashes, and no distribution script, workflow, release, support
policy, or legal file changed. Phase-focused boundary, runner, and distribution
tests passed 502 assertions; the full gate passed all 38 suites and 12,297
assertions, the 29-file purity proof, and the complete boundary inventory.

## Phase 4 — Verify the benefit and stop

### Step 4.1 — Fresh review of the completed changes

- [x] **Scope:** the completed non-pure diff and its direct interactions.
- **Work:** a fresh agent that did not author the changes reviews correctness,
  authority, unnecessary abstractions, and reading effort. Require evidence
  for bugs and a concrete benefit for suggested cleanup. Record close-read,
  skimmed, and unexamined scope. Zero findings is a valid result.
- **Check:** repair proven in-scope defects serially in their owning Step,
  check siblings, and obtain fresh review of repairs. Revisit only affected
  evidence; do not launch another skill chain or find work to justify a pass.

**Result:** A fresh agent close-read the complete production diff, every
changed reader/helper caller, runner/boundary changes, all rewritten non-core
documents, and the approved plan/specification; it skimmed unchanged adjacent
performers/tests and did not re-audit unrelated pure algorithms or complete
desktop harnesses. Six focused suites passed 792 assertions, the boundary
inventory passed, and purity passed all 29 production files. It found no
production correctness, purity, authority, or API regression, and confirmed
the code reduction lowers reading effort.

The review proved four bounded omissions: the runner's generic syntax fallback
lacked behavioral coverage after its body lock was removed; three retained
Architecture sentences still called public Rat boundaries Nat; the handoff
predated the Phase 3 commit; and the Linux transfer description omitted the
consumer harness itself. One invalid two-argument-lambda case now pins status
65, source location, exact fallback text, empty stdout, and sanitized stderr;
the runner suite passes 184 assertions. The three public contracts now say Rat,
the handoff names all pushed phase commits, and the transfer names archive,
checksum, and harness. A second independent close-read traced each repair to
the runner, List/Char/String implementations, and Linux transfer commands. It
found no excess scope or remaining repair finding; `git diff --check` and local
links pass. Zero confirmed findings remain.

### Step 4.2 — Final acceptance, comparison, and completion

- [x] **Scope:** verification and concise final evidence in this plan.
- **Work:** run the complete suite and both checkers; build and consume a
  clean, recorded implementation commit using the existing Racket CS 9.3
  Linux scripts and an independent consumer without Racket. Record revision,
  checksum, help/version, stdout, file/TCP/HTTP, relocation, and exit behavior.
  Preserve isolation, cleanup, notices, and artifact policy; publish nothing.
- **Check:** compare against the baseline: less non-pure implementation code,
  less maintained code overall including tests/tooling, fewer unnecessary
  functions/branches, and easier reading paths. Documentation savings cannot
  substitute for code reduction. Count new helpers and explain actual removed
  logic; do not credit formatting or relocation. Required checks pass and no
  confirmed finding remains. If those conditions fail, report the unmet goal;
  do not manufacture more changes or declare completion.
- **Close:** commit/push only the verified refactor branch and leave it clean.
  Identify any later documentation-only commit separately from the tested
  implementation commit; if it changes shipped/build inputs, repeat acceptance.
  Keep a concise completed plan and useful evidence. **Stop here.** No PR until
  Kyle reviews the completed branch and explicitly approves it. No merge,
  release, new milestone, or further cleanup, even after a generic `next`
  or skill invocation. Separate future work needs a separately named request.

**Result:** Exact implementation/test revision
`f772e8d1f87cf1df7d171476046f9986426192af` passed all 38 suites and 12,301
assertions, the expanded purity proof over all 29 production files, and the
complete boundary inventory. This includes the final review repair and the
real filesystem, TCP, HTTP, runner, language, distribution-contract, and
mutation suites. No confirmed review finding remains.

The clean revision then built with full Racket CS 9.3 from pinned image
`racket/racket:9.3-full` (image ID
`f9c540abe281413dc9e25bfbe6e35276f1a5bca1fa40213c40ac7bac6bb69c62`).
The resulting `attalambda-0.3.0-linux-x86_64.tar.gz` is 13,936,532 bytes with
SHA-256
`355cced2e6c7d8954e80404aaa53d2969329319c52446b083f6446b56141ce5c`;
it contains 11 regular files totaling 59,741,483 bytes, including two runtime
files. This is an unpublished acceptance artifact in `/tmp`, not a release.

The existing consumer passed in read-only digest-pinned
`ubuntu:24.04@sha256:561618e2c15bf2397621dd04f96926663a3b5616c189cf7e38db7e82f5c538ea`
with Racket and `raco` absent, no checkout, all capabilities dropped, and
external networking disabled. Checksum, exact inventory, permissions, legal
bytes, guide workflow, help/version, launcher statuses and sanitized
diagnostics, stdout, binary file round-trip, TCP/HTTP loopback, foundations,
and relocation all passed. First startup was 470 ms and relocated startup was
369 ms.

| Maintained code | Baseline | Final | Change |
| --- | ---: | ---: | ---: |
| Pure `core/` + `effects/` | 5,510 | 5,510 | 0 |
| Non-pure implementation | 2,057 | 1,986 | -71 |
| Tests/support | 13,478 | 13,398 | -80 |
| Tooling/CI | 6,731 | 6,689 | -42 |
| **All maintained code** | **27,776** | **27,583** | **-193** |
| Refactor surface excluding the pure center | 22,266 | 22,073 | -193 |

The production reduction comes from one codec conversion path replacing two
pipelines, direct host dispatch replacing seven route helpers, and ten reader
`lazy-apply` wrappers becoming direct applications. That is 16 fewer private
production helper definitions. In tests, 21 repeated `apply2`/`apply3`
definitions became two definitions in the existing lazy helper, for 19 fewer
test helpers; the one added runner scenario protects a real branch left behind
by the removed checker body lock. The checker itself loses copied private
diagnostic bodies while retaining capability, authority, import/export,
loader, vocabulary, and repository-inventory enforcement. No dependency,
runtime module, public export, representation, effect, or distribution policy
was added. The only intentional behavior change is the approved diagnostic
correction from obsolete Nat wording to exact Rat wording.

The changed planning and explanatory documents fell from 5,899 baseline lines
to 2,282 lines while adding the 206-line controlling refactor
specification. The final evidence update touches only `PLAN.md`, `HANDOFF.md`,
and `docs/ACCEPTANCE.md`, none of which enters the shipped package or Linux
archive inputs; the accepted implementation artifact therefore does not need
rebuilding. The branch is complete after that documentation-only commit is
pushed. No tag, Release, upload, merge, or pull request was created.
