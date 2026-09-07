# Acceptance evidence

This is the compact evidence map for the implemented language. The three
[language specifications](specifications/README.md) define the contract; tests
and structural checkers show how the repository enforces it. Historical phase
completion is recorded in [`PLAN-ARCHIVE.md`](../PLAN-ARCHIVE.md), and binary
release facts are in the
[standalone-distribution ledger](design/standalone-distribution.md).

Run [`run-all-tests.sh`](../run-all-tests.sh) for the source acceptance gate.
It runs every test suite, the expanded purity proof, and the repository-wide
boundary inventory. The released 0.4.0 implementation passed 41 suites with
14,100 assertions, 32 pure production modules, and the complete boundary
scan. Earlier 0.3.0 source passed 38 suites with 12,298 assertions. The
completed non-core refactor at `f772e8d` passed 38 suites with
12,301 assertions, all 29 pure production modules, and the complete boundary
scan.

Release 0.4.0 includes incremental HTTP request reading, a 21-case
canonical-empty codec matrix, explicit program exit, lowercase callable
exports and diagnostic names, ASCII Char literals, and the complete
25-function List API. Source and release verification are recorded in
[`PLAN.md`](../PLAN.md) and below; earlier unpublished build evidence remains
explicitly historical.

## Language criteria

Milestone 5's final 0.5.0 preparation passed all 41 source suites with 14,210
assertions, 32 pure production modules, and the complete boundary inventory.
The source now rejects recursive module bindings, provides pure `rec` syntax,
and reports safe recursion-specific launcher diagnostics. The Linux consumer
fixture's 31 public-API assertions and the complete migration example also
passed exact source-launcher probes. Evidence is recorded in
[`PLAN.md`](../PLAN.md); no 0.5.0 archive is published yet.

| Criterion | Executable evidence |
| --- | --- |
| Production computation expands to variables, unary lambdas, and unary application. | [`check-purity.rkt`](../tooling/check-purity.rkt) expands and inspects every `core/` and `effects/` module; [`purity-test.rkt`](../tests/purity-test.rkt) proves forbidden host forms and non-unary lambdas are rejected. |
| Public syntax is `lambda`, `def`, `rec`, `let`, `if`, and the specified `cons`; literals expand mechanically. | [`macros-test.rkt`](../tests/macros-test.rkt) covers hygiene and generated terms; [`language-test.rkt`](../tests/language-test.rkt) covers the installed `#lang attalambda` surface, shadowing, and rejected names/literals. |
| Module dependencies are acyclic; `rec` derives self recursion from the private pure fixed-point term. | [`language-test.rkt`](../tests/language-test.rkt) covers execution, currying, partial application, laziness, lexical shadowing, and rejected direct/indirect cycles. [`purity-test.rkt`](../tests/purity-test.rkt) independently checks expanded binding cycles; [`runner-test.rkt`](../tests/runner-test.rkt) pins safe diagnostics and status 65. |
| All 63 renamed callables use lowercase exports and diagnostic names; retired uppercase callable names are unbound. | [`language-test.rkt`](../tests/language-test.rkt) exercises every renamed operation, expands a public module rejecting each old name, and observes public Error frames. Existing diagnostic suites pin encoded names, roots, and propagation details. |
| ASCII Char literals agree with `make-char` and UTF-8 String bytes; named Char exports are removed. | [`language-test.rkt`](../tests/language-test.rkt) checks all 128 ASCII values through public operations and canonical codec conversion, rejects non-ASCII literals and all retired names, and proves ordinary user definitions. |
| Values carry closed Church type tags, and one arbitrary-arity checker owns strict runtime typing. | [`tags-test.rkt`](../tests/tags-test.rkt), [`objects-test.rkt`](../tests/objects-test.rkt), [`typecheck-test.rkt`](../tests/typecheck-test.rkt), and [`errors-test.rkt`](../tests/errors-test.rkt) cover tags, positions, partial application, laziness, and early Error absorption. |
| Bool and strict `if` preserve typed, lazy branch choice. | [`logic-test.rkt`](../tests/logic-test.rkt) and [`typed-logic-test.rkt`](../tests/typed-logic-test.rkt) prove canonical values, wrong-type Errors, chosen-branch forcing, and unchosen-branch laziness. |
| List uses the Michaelson representation; `NIL` is distinct from false and zero, and every tail is a List. | [`lists-test.rkt`](../tests/lists-test.rkt) and [`errors-test.rkt`](../tests/errors-test.rkt) cover proper construction, operations, contracts, and malformed tails. |
| List append/reverse preserve order and representation; map/filter enforce callback contracts. | [`list-transform-test.rkt`](../tests/list-transform-test.rkt) checks ordering, heterogeneous values, canonical NIL, partial application, wrong types, first/later callback failures, Bool validation, and stopping after Error; public programs exercise all four names. |
| Left reduction preserves argument/accumulation order; searches short-circuit and return Bool or Option as specified. | [`list-transform-test.rkt`](../tests/list-transform-test.rkt) proves left subtraction, NIL identity, Error absorption and stopping; [`list-search-test.rkt`](../tests/list-search-test.rkt) covers all five searches, asymmetric equality, canonical Rat indices, first/later stopping, Bool validation, and preserved diagnostic frames. |
| nth returns Option and validates whole nonnegative indices; predicate prefixes stop at the first false answer. | [`list-nat-test.rkt`](../tests/list-nat-test.rkt) covers valid, boundary, past-end, invalid, and Error indices; [`list-search-test.rkt`](../tests/list-search-test.rkt) proves prefix order, canonical NIL, suffix retention, callback stopping, and Error propagation. |
| Zip constructs two-element Lists, concat removes one level, and flatten recursively preserves leaf order. | [`list-transform-test.rkt`](../tests/list-transform-test.rkt) covers unequal lengths, canonical NIL, preserved concat nesting, nested empty Lists, heterogeneous leaves, invalid inner Lists, and nested Error propagation without evaluating later leaves. |
| Range uses signed whole bounds with an exclusive end; repeat validates counts and skips its value at zero. | [`list-nat-test.rkt`](../tests/list-nat-test.rkt) checks signed/cross-zero/equal/reversed ranges, fractional rejection, canonical Rat/List output, repetition counts and mixed values, lazy zero, and Errors/partial application. |
| Supported empty-producing List/String operations remain codec-compatible without weakening canonicality. | The 21 labeled cases in [`codec-test.rkt`](../tests/codec-test.rkt) assert both empty host conversion and canonical NIL identity across generic Lists, List Byte, Strings, and composition. Forged-terminator rejection remains; no producer or codec repair was needed. |
| Rat is the only public number; private Nat/Int representations remain canonical. | [`binary-nat-test.rkt`](../tests/binary-nat-test.rkt), [`int-test.rkt`](../tests/int-test.rkt), [`rat-test.rkt`](../tests/rat-test.rkt), and [`typed-rat-test.rkt`](../tests/typed-rat-test.rkt) cover normalized binary magnitude, one signed zero, reduced fractions, exact arithmetic, comparison, division, powers, and strict wrappers. [`language-test.rkt`](../tests/language-test.rkt) proves retired public Nat/Int names do not resolve. |
| Exact integer and fraction literals become canonical Rats; inexact and complex numbers are rejected. | [`language-test.rkt`](../tests/language-test.rkt) round-trips representative positive, negative, fractional, zero, and large literals through the codec and rejects floating-point, infinity, NaN, and complex forms. |
| Error represents contract/invariant failure; Result Err represents expected computational failure. | [`errors-test.rkt`](../tests/errors-test.rkt) pins distinct kinds and argument positions; arithmetic, file, TCP, and HTTP suites prove the Error/Result boundary. |
| Char is a byte-valued character, Byte has exactly 256 values, String is `List Char`, and binary payloads are `List Byte`. | [`chars-test.rkt`](../tests/chars-test.rkt), [`byte-test.rkt`](../tests/byte-test.rkt), [`strings-test.rkt`](../tests/strings-test.rkt), [`codec-test.rkt`](../tests/codec-test.rkt), and real file/TCP host tests cover canonical conversion and byte-exact round trips. |
| Unit carries successful no-value results; Option represents expected absence; Map is persistent and pure. | [`unit-test.rkt`](../tests/unit-test.rkt), [`option-test.rkt`](../tests/option-test.rkt), and [`map-test.rkt`](../tests/map-test.rkt) cover tags, operations, contracts, laziness, persistence, and custom equality. |
| Effects construct typed requests and invoke only the injected unary host. | [`stdout-test.rkt`](../tests/stdout-test.rkt), [`files-test.rkt`](../tests/files-test.rkt), [`tcp-test.rkt`](../tests/tcp-test.rkt), and [`exit-test.rkt`](../tests/exit-test.rkt) use fake-host traces to pin request shape, order, validation precedence, and one invocation. |
| The host implements exactly stdout, whole-file I/O, blocking TCP, and explicit exit. | [`host-test.rkt`](../tests/host-test.rkt), [`file-host-test.rkt`](../tests/file-host-test.rkt), and [`tcp-host-test.rkt`](../tests/tcp-host-test.rkt) exercise all ten routes, native failures, binary data, partial writes, bounds, handles, cleanup, and nonreturning exit in child processes. |
| Only Rat 0/1 can request exit; pure programs decide fatal versus recoverable failure. | [`exit-test.rkt`](../tests/exit-test.rkt) proves pure validation, Error bubbling, invalid-argument non-dispatch, and fake-host laziness. [`runner-test.rkt`](../tests/runner-test.rkt) proves exact silent OS statuses 0/1, unchanged no-exit Error/Err completion at 0, missing-file Err choices, unselected exit, and before/after effect ordering. |
| Pure HTTP values, incremental framing/accumulation, parsing/rendering, routing, and the sequential server stay lambda-built. | [`http-test.rkt`](../tests/http-test.rkt) and [`http-server-test.rkt`](../tests/http-server-test.rkt) cover every nonempty two-chunk split, byte-at-a-time input, delimiter overlaps, exact/over-cap requests, EOF, trailing data, failures, cleanup, re-forcing, and real loopback behavior. Source inspection proves no incomplete-chunk full parse or repeated old-prefix append/recount. |
| A source file runs through the public language without exposing loader machinery. | [`runner-test.rkt`](../tests/runner-test.rkt), [`language-test.rkt`](../tests/language-test.rkt), and [`milestone-two-acceptance-test.rkt`](../tests/milestone-two-acceptance-test.rkt) cover paths, diagnostics, one load, public examples, effects, Error/Err completion, and the foundational values together. |

## One privileged bridge

| Boundary fact | Sole production location | Enforcement |
| --- | --- | --- |
| Definition and producer export of `host` | [`runtime/host.rkt`](../runtime/host.rkt) | The boundary checker requires exactly one definition and sole export, locks its imports and vocabulary, and rejects another producer. |
| Deterministic lambda/host conversion | [`runtime/codec.rkt`](../runtime/codec.rkt), imported in production only by the host | Exact exports and imports are checked; the codec has no effects or registry. Codec tests prove canonical conversion, malformed-value rejection, and cycle handling. |
| Native stdout, filesystem, DNS, TCP, handle registry, failure mapping, and program-requested exit | [`runtime/host.rkt`](../runtime/host.rkt) | Closed imports, host-only primitives, dispatcher vocabulary, and production-wide scans reject the capabilities elsewhere. Real-host suites exercise each route. Runner-native exit has only its separate launcher role. |
| Request construction and all higher computation | [`effects/`](../effects) | The expanded purity scanner permits only pure core/effect dependencies and application of the injected unary host argument. Fake-host tests pin canonical requests. |
| Public binding of that host to the ten wrappers | [`lang/expander.rkt`](../lang/expander.rkt) | Exact facade imports/exports and fixed injection definitions allow this module to import and re-export the host without direct operating-system capability. The sole public `exit` spelling is pinned to its export; helper/template native uses, including nested syntax-data containers, are rejected. |
| Process launch and one requested module load | [`runner/attalambda.rkt`](../runner/attalambda.rkt) | The non-exporting runner validates only its requested source, emits fixed diagnostics, imports neither host nor codec, observes no lambda value, and is unreachable from production computation. |
| Observation, tests, and repository checks | [`readers/`](../readers), [`tests/`](../tests), and [`tooling/`](../tooling) | These nonproduction classes are inventoried separately. Reader capability is constrained, unknown source locations fail closed, and production dependencies on support code are rejected. |

[`check-boundaries.rkt`](../tooling/check-boundaries.rkt) owns this complete
inventory. It also pins public exports, allowed dependency directions,
privileged imports, reader limits, runner limits, and the exact source classes.

## Standalone acceptance

The [standalone contract](design/standalone-distribution.md) fixes the command,
source validation, diagnostic statuses/text, version projection, Racket CS 9.3
build, archive layout, legal bytes, and supported platform. The distribution
suite checks all build/consumer scripts and the CI workflow. The Linux consumer
then verifies a real archive in digest-pinned Ubuntu 24.04 without Racket or a
checkout, including checksum, guide commands, relocation, stdout, file/TCP/HTTP
behavior, explicit/default program statuses, and the complete public List API
with Char literals and ordinary identifiers. Fixed launcher failures are
covered by the source runner suite; they are not claimed as Linux consumer
cases.

The 0.3.0 publication used release commit `1b51603` and annotated tag
`v0.3.0`. Its sole binary archive is 13,938,743 bytes with SHA-256
`7adc7343720b0a1d6ed86af47059f031f571ab93649a314303c56d6b8a3d7870`.
It passed the independent no-Racket consumer before upload and matched a fresh
public download afterward. Building or testing a future archive grants no
publication authority.

### AttaLambda 0.4.0 publication — 2026-09-06

PR https://github.com/kserrec/attalambda/pull/2 received a completed automated
review with no actionable findings. The subsequent version-only preparation
passed the local 41-suite, 14,100-assertion gate and both architectural checks;
all ten PR CI jobs passed on `d6f50ee`. The merged commit
`bd1dd56925765f8d8359609a49e333ba570bcfc6` has exactly the same file tree, and
all ten post-merge CI jobs passed before publication.

The clean merged commit produced the final 0.4.0 Linux archive with Racket CS
9.3. That exact archive passed the isolated Ubuntu consumer, including all 30
public-API markers, guide, file/TCP/HTTP, exit-status, and relocation checks.
The annotated tag points to the exact build commit. The latest stable release
is https://github.com/kserrec/attalambda/releases/tag/v0.4.0; fresh public
downloads of its archive and checksum manifest matched both verified local
hashes. Exact tag/asset IDs, sizes, SHA-256 values, and CI URLs are in the
[release ledger](design/standalone-distribution.md#attalambda-040--2026-09-06).
Linux x86-64 remains the sole supported binary download. Later documentation
records do not change the tagged build inputs.

### Public API and List library implementation acceptance — 2026-09-06

The final Phase 8 source run passed all 41 suites with 14,099 assertions, expanded
purity for 32 production modules, and the complete boundary/inventory gate.
Exact export comparison against the baseline and normative inventory found
105 callables, 10 constants, and seven syntax/module bindings: exactly 63
lowercase renames, 85 removed named Chars, and 18 new List operations. The API
reference covers that complete surface. Installed-language tests exercise the
renamed/new operations and all 128 ASCII literals, reject retired names, and
prove that ordinary former Char names can be defined.

The complete production diff contains two new pure List modules, extensions
to the existing numeric List module, encoded diagnostic names, explicit facade
imports/exports, the small Char literal expansion case, and the runner's
matching literal diagnostic text. Existing raw List algorithms, generalized
checker, tags, macros, readers, effects, codec, and host modules are unchanged.
No new dependency, representation, runtime wrapper, dispatcher, or host
capability was added. The existing boundary checker changes only its exact
facade tables/vocabulary; the purity checker is unchanged.

The unchanged Linux builder produced an archive from clean implementation
commit `17641cc41f53d00e96308846500f8ed65e633203` with Racket CS 9.3 in cached
image `sha256:f9c540abe281413dc9e25bfbe6e35276f1a5bca1fa40213c40ac7bac6bb69c62`.
The source checkout and existing Git executable were mounted read-only;
external networking was disabled. The manifest records the clean commit.
Archive SHA-256 is
`38329c11591b5d724ced243bc3327576dbe2bc3d06b428ae65fbad6b84af3acf`:
14,016,761 compressed bytes, 59,860,173 unpacked regular-file bytes, 11 files,
including two runtime files. It remains at
`/tmp/attalambda-public-api-final-linux/attalambda-0.3.0-linux-x86_64.tar.gz`
with sibling `SHA256SUMS`. This is unpublished branch evidence; it does not
replace the published 0.3.0 archive.

The existing Linux consumer ran in
`ubuntu:24.04@sha256:561618e2c15bf2397621dd04f96926663a3b5616c189cf7e38db7e82f5c538ea`,
with no Racket, raco, checkout, or external network. One additional ordinary
public-language program exercised all 25 List functions, left reduction,
one-level concat versus recursive flatten, signed range, lazy zero repeat,
predicate stopping, Char literals/whitespace, user-defined a/x/n/m, and Map
alongside List map. It produced exactly 30 success markers. Checksum, guide,
stdout, file/TCP/HTTP, explicit/default exit statuses, and relocation also
passed. The final marker was `consumer_acceptance=passed`; first/relocated
version startup measured 331/311 ms, without a performance guarantee.

The later Phase 8 acceptance commit changes only the consumer program and
documentation. Its production sources and shipped examples are identical to
the recorded build commit. At that completion point, version and legal bytes
were unchanged and no pull request, merge, tag, or publication had occurred.
The separately authorized 0.4.0 publication above followed this verification.

### HTTP/List/exit milestone acceptance — 2026-09-05

The final source run passed all 39 suites with 13,606 assertions, expanded
purity for 30 production modules, and the complete boundary/inventory gate.
Fresh review of all 28 milestone-delta files and their direct interactions
found no confirmed defects or material test gaps; its independent focused run
passed 980 assertions. Isolated mutations proved rejection of native arithmetic
in HTTP framing and native exit in effects, codec, and readers. The copied
sources passed before mutation, were rejected after mutation, and passed again
after restoration with hashes identical to their originals.

The unchanged builder produced the Linux archive from clean implementation
commit `31138222bd5299d6554ad036c4f44e9c74fe0d4c`, as recorded in its manifest.
It used Racket CS 9.3 from cached image
`sha256:f9c540abe281413dc9e25bfbe6e35276f1a5bca1fa40213c40ac7bac6bb69c62`,
with the existing Git executable mounted read-only for provenance checks.
The archive has SHA-256
`cb2eab3a0041b8733467f4839869e9a726b129b362dce9a8e2632218c4c5b981`:
13,948,353 compressed bytes, 59,765,547 unpacked regular-file bytes, 11 files,
including two runtime files. It remains only at
`/tmp/attalambda-http-exit-build-X0sRsh/attalambda-0.3.0-linux-x86_64.tar.gz`;
this is unpublished acceptance evidence, not a replacement for released 0.3.0.

The independent consumer used
`ubuntu:24.04@sha256:561618e2c15bf2397621dd04f96926663a3b5616c189cf7e38db7e82f5c538ea`,
with no Racket, raco, checkout, or external network. Checksum, guide workflow,
stdout, file/TCP/HTTP behavior, and relocation checks all passed. The new
public-only programs also passed these exact checks, each with empty stdout
and stderr:

| Program completion decision | Observed OS status |
| --- | ---: |
| Explicit `(exit 0)` | 0 |
| Explicit `(exit 1)` | 1 |
| No exit, including ordinary Error and Result Err values | 0 |
| Missing-file Err deliberately treated as fatal | 1 |
| Missing-file Err deliberately treated as recoverable | 0 |

First and relocated version startup took 461 ms and 409 ms in this run;
these are observations, not performance guarantees. The final consumer marker
was `consumer_acceptance=passed`. The later acceptance-record commit changes
only this document and `PLAN.md`; it is not the built implementation revision.
Version and legal bytes are unchanged. No pull request, merge, tag, or release
was created for this milestone.

## Limits

The project does not claim sandboxing or per-program permission prompts. A
real-host program inherits the launching process's relevant authority. It has
no program-argument API, general parser, optimizer, compiler, records, JSON,
environment access or process spawning, directory operations, atomic file replacement,
TLS, UDP, timeouts, asynchronous server, production concurrency, or general
HTTP framework. The HTTP server implements only its documented blocking
HTTP/1.1 subset and serves one connection at a time. Linux x86-64 is the sole
supported public binary; no compatibility floor below the exact Ubuntu 24.04
consumer, signature, installer, or broader support policy is claimed.

AttaLambda is an interpreted lazy-lambda tower. Rat arithmetic reduces through
binary gcd and is orders of magnitude slower than host arithmetic. Map lookup
walks linearly and calls a lambda-encoded equality at each entry.

HTTP request buffering remains capped at 8,192 bytes. Framing now examines
only each new chunk plus at most three preceding characters; accumulation
walks the new chunk, and a private binary running count replaces whole-request
recounts. The server reconstructs and parses once at header completion or EOF.
This removes the documented repeated-prefix/reparse work without redesigning
the semantic parser. The blocking server still has no read deadline.

## Material corrections before 0.3.0

The Milestone 4 branch received an adversarial review before release. All ten
confirmed findings were fixed in commit `3254354` and independently reviewed.
The lasting corrections were:

- new Error kinds moved to 14, 15, and 16 after collision with the existing
  HTTP kind 13, and all kinds are pairwise pinned;
- `MAKE-STRING` and `DROP` restore canonical `NIL` on empty results;
- codec List decoding uses linear Floyd cycle detection and canonical cached
  Byte/Char objects;
- the expanded purity proof includes the entire effects layer;
- TCP tests use a raw peer where crossing a lazy promise between threads would
  violate Racket's re-entrant-promise rule.

The earlier HTTP security pass added the 8,192-byte request cap after proving
that hostile peers could otherwise cause unbounded buffering. These corrections
are part of the current implementation, not open work.
