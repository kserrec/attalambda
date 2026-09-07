# Standalone distribution

This document records the current launcher and binary-distribution contract,
then preserves the evidence for the three public releases. The language itself
is defined by the [specifications](../specifications/README.md); the
[host-boundary design](host-boundary.md) defines the effects available to a
running program.

The current source prepares 0.5.0 with pure `rec` definitions and rejection
of recursive module bindings. The published release remains 0.4.0, including
explicit program exit, lowercase public callables, ASCII Char literals, and
the complete List library. The [0.5.0 migration notes](../releases/0.5.0.md)
describe the source changes; the release ledger records published artifacts.

## Current public support

Linux x86-64 is the sole supported public binary target. The supported
workflow is to download the archive and its sibling `SHA256SUMS`, verify it,
extract it, and run:

```text
attalambda FILE.attl
```

The archive includes its private Racket CS runtime. Running it requires no
Racket installation, package registry, AttaLambda checkout, build directory,
or network service. This is a distribution promise, not a sandbox promise: a
program using the real host receives the launching process's documented
stdout, filesystem, DNS, connection, and listening authority.
The current source also permits a program to terminate its own process through
explicit `exit`; it grants no process-spawning or signal capability.

The macOS and Windows builders and consumers remain portability checks in CI.
They do not make those systems supported public targets. Public macOS binaries
would require a normal downloaded-user Gatekeeper path, including appropriate
signing and notarization. No Windows client machine is available to establish
the corresponding downloaded-user path.

## Source and command contract

[`runner/attalambda.rkt`](../../runner/attalambda.rkt) implements the complete
command surface:

```text
attalambda FILE.attl
attalambda --help
attalambda --version
```

There are no aliases, short flags, program arguments, REPL, stdin-source,
compiler, or package-manager modes. A source path beginning with `-` must use
an explicit directory component such as `./-example.attl`.

A runnable source has these properties:

- Its supplied final component ends in exact lowercase `.attl` bytes.
- It is a regular file rather than a directory, device, FIFO, or symbolic-link
  entry.
- Its first logical line is exactly `#lang attalambda`, followed by LF, CRLF,
  or end of file.
- Its remaining bytes are valid UTF-8 and are read and expanded by the
  existing language reader and expander. The launcher has no second parser,
  evaluator, or literal implementation.
- Relative and absolute paths, spaces, and non-ASCII path characters are
  supported. The launcher leaves the caller's working directory unchanged.
- The launcher loads exactly the supplied source once. It performs no project,
  import, package, directory, or network discovery.

A path component is refused, case-insensitively, when its name matches
`(^|\.)env($|\.)`. The launcher checks both supplied components and resolved
parent components before reading source content. It may inspect only the path
metadata needed to make that decision. The original command-line spelling is
always the public diagnostic name.

Validation has one fixed order:

1. command shape;
2. forbidden supplied path spelling;
3. lowercase `.attl` suffix;
4. symbolic-link source entry;
5. resolved parent path and its forbidden components;
6. existence, regular-file status, and readability;
7. declaration, encoding, read, expansion, and one module instantiation.

`--help` prints exactly:

```text
Usage:
  attalambda FILE.attl
  attalambda --help
  attalambda --version
```

`--version` prints `AttaLambda VERSION` and one newline. Both commands write
only stdout and inspect no source. Successful source execution reserves stdout
for effects explicitly requested by the program; launcher diagnostics use
stderr.

### Completion and diagnostics

Launcher-controlled completion uses this table:

| Status | Meaning | Conditions |
| ---: | --- | --- |
| `0` | success | help/version completed, or the source instantiated without an uncaught host failure |
| `64` | command misuse | missing, unknown, or extra command arguments |
| `65` | invalid source | suffix, declaration, encoding, read, syntax, or expansion failure |
| `66` | unavailable/refused input | forbidden path, symlink, missing path, nonregular input, or inspection/read failure |
| `70` | unexpected launcher failure | a catchable Racket failure outside the preceding classes and approved host Results |

The launcher imposes no execution timeout. External signals, forced process
termination, or failures too severe for Racket to catch may produce another
operating-system status.

An object-language Error, `Result Err`, or `Result Ok` is ordinary completed
lambda data. The module wrapper forces each top-level expression for requested
effects and discards its value; the launcher never decodes that value or bases
its exit status on it. Without a performed explicit exit, normal completion
remains status `0`, including when an expression produces Error or Err. An
operating-system failure from a valid returning host request becomes the
specified `Result Err`, not status `70`.

Separately from launcher-controlled completion, `(exit 0)` and `(exit 1)`
request those exact operating-system statuses. Pure AttaLambda code decides
whether a condition is fatal and validates the status; only the real host
terminates the process, without returning a value or printing a diagnostic.
Wrong types yield TypeMismatch Error, other Rats yield InvalidCount Error, and
incoming Errors bubble without dispatch. An unselected exit remains lazy; a
performed exit prevents later expressions from running. The
[host-boundary contract](host-boundary.md) defines this tenth operation.

Diagnostics use one of these shapes, where `SOURCE` is the safely quoted
original spelling, line numbers are one-based, and columns are zero-based:

```text
AttaLambda: REASON
AttaLambda: "SOURCE": REASON
AttaLambda: "SOURCE":LINE:COLUMN: REASON
```

The exact reasons are:

| Class | Status | Reason |
| --- | ---: | --- |
| command misuse | 64 | `expected attalambda FILE.attl, attalambda --help, or attalambda --version` |
| forbidden path | 66 | `refused source path because dotenv files are never read` |
| wrong extension | 65 | `source file name must end in lowercase .attl` |
| source symlink | 66 | `refused symbolic-link source; choose a regular .attl file` |
| uninspectable metadata | 66 | `source path could not be inspected` |
| missing source | 66 | `source file was not found` |
| nonregular source | 66 | `source path is not a regular file` |
| unreadable source | 66 | `source file could not be read` |
| malformed declaration | 65 | `line 1 must be exactly #lang attalambda` |
| invalid encoding | 65 | `source is not valid UTF-8` |
| reader failure | 65 | `source could not be read; check delimiters and UTF-8 encoding` |
| unavailable identifier | 65 | `unknown AttaLambda name: IDENTIFIER` |
| unsupported datum | 65 | `unsupported literal; only exact Rat, String, and ASCII Char literals are supported` |
| other expansion failure | 65 | `source has invalid syntax` |
| unexpected failure | 70 | `unexpected launcher failure; verify the AttaLambda installation` |

No exception message, stack trace, package path, checkout path, or build path
is copied into a diagnostic.

## Trusted launcher boundary

The runner is process-loading scaffolding, separate from object-language
computation. It may inspect its command-line arguments, write the fixed output
above, set the process exit status, validate the one requested path and source,
load that source once, classify failures, and read embedded product-version
metadata.

It exports no binding. Production modules cannot import it, and AttaLambda
source cannot name or invoke it. It imports neither the host nor the codec,
does not observe a completed lambda value, and cannot add an object-language
effect. It may not enumerate environment variables, launch another process,
use a shell or FFI, contact a network service, or discover another source.
[`tooling/check-boundaries.rkt`](../../tooling/check-boundaries.rkt) enforces
this class and rejects unknown Racket source locations.

## Version authority

Root [`VERSION`](../../VERSION) is the sole manually edited product version.
It contains one approved value and one LF. The CLI, archive names, guide,
manifest, and release naming derive from it. Racket package metadata needs a
different syntax, so build tooling checks this closed projection:

| Product version | `info.rkt` version |
| --- | --- |
| `0.2.0-dev` | `0.1.900` |
| `0.2.0-rc.1` | `0.1.901` |
| `0.2.0` | `0.2` |
| `0.3.0-dev` | `0.2.900` |
| `0.3.0` | `0.3` |
| `0.4.0` | `0.4` |
| `0.5.0` | `0.5` |

A new version state requires an explicit plan change. Milestone 5 Phase 2
authorizes exactly 0.5.0 for pure recursive definitions. Publication evidence
is recorded separately from version preparation; merge and publication are
pending approval of the concrete reviewed release.

## Build, archive, and consumer contract

[`tooling/build-linux-distribution.sh`](../../tooling/build-linux-distribution.sh)
builds with exactly full Racket CS 9.3:

1. copy package sources into an isolated temporary package home;
2. compile the runner with `raco exe` using the default `-U` isolation and
   explicit `++lang attalambda` language embedding;
3. assemble the private runtime with `raco distribute`;
4. inventory and archive the result outside the checkout;
5. write the archive digest to an external sibling `SHA256SUMS`.

The build refuses an output inside the checkout, an existing destination,
wrong version metadata, the wrong Racket variant/version, symlinks, unsafe
archive paths, missing runtime files, unresolved native libraries, legal-byte
changes, or absolute build-path leakage. A release build also requires a clean
source tree; `--allow-dirty` exists only for internal testing and records that
state in the manifest. Runtime closure must not depend on a Racket command,
user package registry, checkout, build directory, or network service.

The archive root is `attalambda-VERSION-linux-x86_64/` and contains exactly
these top-level entries:

```text
bin/
lib/
examples/
BUILD-MANIFEST.txt
GETTING_STARTED.md
LICENSE
THIRD_PARTY_NOTICES.md
```

`bin/` contains only `attalambda`. `examples/` contains `hello.attl`,
`stdout.attl`, `file-round-trip.attl`, `http-server.attl`, and
`foundations.attl`. `BUILD-MANIFEST.txt` records the product version, source
commit and tree state, target, Racket version/variant, exact file inventory,
legal hashes, checksum arrangement, and observed native-library assumptions.
It records no user name, secret, timestamp, package registry, checkout path,
or temporary path.

The shipped Apache-2.0 [`LICENSE`](../../LICENSE) is exactly 11,358 bytes with
SHA-256
`cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30`.
The approved Racket CS 9.3
[`THIRD_PARTY_NOTICES.md.in`](../../distribution/THIRD_PARTY_NOTICES.md.in) is
exactly 100,024 bytes with SHA-256
`516b3a08454709bf111494c92ed260a5c4afb47c91d06efca924b500c89e17ad`.
The build copies these bytes unchanged.

[`tooling/test-linux-distribution.sh`](../../tooling/test-linux-distribution.sh)
crosses a build-to-consumer transfer boundary into
`ubuntu:24.04@sha256:561618e2c15bf2397621dd04f96926663a3b5616c189cf7e38db7e82f5c538ea`.
The consumer has no Racket command or source checkout and receives the archive,
checksum, and self-contained consumer harness. It verifies the checksum,
layout, permissions, manifest, legal bytes, guide commands, version/help,
stdout, byte-exact file-example round-trip, TCP/HTTP loopback behavior, and
relocation. The current consumer also checks explicit/default program statuses
and both fatal and recoverable missing-file decisions. The foundations example
is inventoried but not executed by this consumer. Fixed launcher-failure
statuses and sanitized diagnostics are covered by `tests/runner-test.rkt`;
foundations execution is covered by `tests/milestone-two-acceptance-test.rkt`.
Those are source-suite checks, not packaged-consumer results. External
networking is disabled; only ephemeral loopback service is used.

Building or verifying an archive does not authorize a tag, Release, upload,
signing or notarization operation, paid account use, purchase, or publication.
Each publication needs Kyle's explicit approval for the exact commit, tag,
files, checksums, support claims, and public action.

## Public release ledger

### AttaLambda 0.4.0 — 2026-09-06

PR https://github.com/kserrec/attalambda/pull/2 merged as
`bd1dd56925765f8d8359609a49e333ba570bcfc6`. Its complete tree equals verified
PR revision `d6f50eec467062a0d33ce0697229f0b691735a06`. Automated review of the
language implementation found no actionable issue. All ten PR CI jobs and
all ten post-merge CI jobs passed; the local source gate passed 41 suites,
14,100 assertions, expanded purity for 32 production modules, and complete
boundaries. These are the CI runs:

- https://github.com/kserrec/attalambda/actions/runs/34048807658
- https://github.com/kserrec/attalambda/actions/runs/34049568221

The exact merged commit built cleanly with full Racket CS 9.3 from cached
image `sha256:f9c540abe281413dc9e25bfbe6e35276f1a5bca1fa40213c40ac7bac6bb69c62`.
Unsigned annotated tag `v0.4.0` has tag-object SHA
`baba89b99fafbc5109af1b5dc23f5f1df90ed591` and peels to that build commit.
GitHub release ID `383668323` was published at `2026-09-06T18:00:46Z` and
marked latest, with exactly these supported assets:

| Asset | Bytes | SHA-256 |
| --- | ---: | --- |
| `attalambda-0.4.0-linux-x86_64.tar.gz` | `14,016,817` | `29728792d17843c7c09faf5f9be0cb4b215e13a43113a7b65d83d909dd37ac8b` |
| `SHA256SUMS` | `103` | `4bf58df3b8ea6e5c9fc36b1227d7065283925aedcc744fe6cf40f7269bfc19dd` |

Their asset IDs are `547488679` and `547488678`, respectively. The release
page is https://github.com/kserrec/attalambda/releases/tag/v0.4.0.
Fresh unauthenticated downloads from its two public asset URLs matched both
local build hashes, and the downloaded checksum manifest passed verification.
Older release assets were preserved. macOS/Windows remain internal portability
evidence, not supported public downloads.

The exact archive passed the existing digest-pinned Ubuntu 24.04 consumer
without Racket, a checkout, or external networking. Its 30 public-API markers
covered all 25 List functions, Char literals, ordinary identifiers, Map, and
laziness. Guide workflow, stdout, file/TCP/HTTP, exit statuses, and relocation
also passed. The archive has 11 files and 59,860,179 unpacked regular-file
bytes, including two runtime files. First/relocated version startup measured
435/521 ms in that run, without a performance guarantee. The source, legal
bytes, and runtime assumptions are recorded in its clean build manifest.

Local evidence remains in `/tmp/attalambda-0.4.0-release/`,
`/tmp/attalambda-0.4.0-public-download/`, and the preparation/build/consumer
logs named in `PLAN.md`. Later publication-record commits change documentation
only; the tagged commit is the exact artifact source.

### AttaLambda 0.3.0 — 2026-09-02

The 0.3.0 release was built from clean commit
`1b51603671e87bcc524e2413491c94ad1ea7d763` with full Racket CS 9.3 in
`racket/racket:9.3-full`. Annotated tag `v0.3.0` peels to that commit. The
independent no-Racket Ubuntu 24.04 consumer passed checksum, guide, relocation,
and loopback networking with a 362 ms first startup. Linux x86-64 was the only
published binary target.

| Asset | Bytes | SHA-256 |
| --- | ---: | --- |
| `attalambda-0.3.0-linux-x86_64.tar.gz` | `13,938,743` | `7adc7343720b0a1d6ed86af47059f031f571ab93649a314303c56d6b8a3d7870` |
| `SHA256SUMS` | `103` | single-entry manifest for that archive |

Both [public download URLs](https://github.com/kserrec/attalambda/releases/tag/v0.3.0)
were downloaded again after publication. Their byte counts matched and the
manifest verified the archive. The archive contains 11 files totaling
59,742,960 unpacked bytes, including two runtime files. The release source
passed 38 suites with 12,298 assertions, the 29-module expanded purity proof,
and the complete boundary inventory.

### AttaLambda 0.2.0 — 2026-08-29

The first release's unsigned annotated tag `v0.2.0` has tag-object SHA
`5537cf8b4dc1db31f8855e10118729ac78bc0dd0` and peels to tested commit
`42ff0a7810ebeced445ab23561433a2dc423e433`. GitHub Release ID `379061612`
was originally published with these manually uploaded assets:

| Asset | Bytes | Asset ID | SHA-256 |
| --- | ---: | ---: | --- |
| `attalambda-0.2.0-linux-x86_64.tar.gz` | `13,728,716` | `535549598` | `86f980d696b45b42c251b78e6a66b9cd875f649217bfb09731cf6b47c66b00ac` |
| `attalambda-0.2.0-macos-arm64.tar.gz` | `13,743,188` | `535549609` | `5791ca3c28717972409d0d3503e135f685bcb7011ec24e6e4f9e70c7e5426b2b` |
| `attalambda-0.2.0-macos-x86_64.tar.gz` | `13,714,720` | `535549602` | `72f56f4d95665a3ca802160175c4082ce42b08054a35b963a10b0597b9d91fdc` |
| `attalambda-0.2.0-windows-x86_64.zip` | `15,296,844` | `535549611` | `0ffcf7cd7218459efe1de1de87c7ff650328d01b16caa253deb6aa621188015a` |
| `SHA256SUMS` | `410` | `535549605` | `7786bf553caac0087ab22f3636d546a1fe00f89a446611c1516cc58f411f6f7f` |

All four consumers passed in [Actions run 33262922610](https://github.com/kserrec/attalambda/actions/runs/33262922610),
and the public downloads matched the staged bytes. The macOS executables were
unsigned/unnotarized for the normal downloaded-user path; a consumer Mac then
showed a Gatekeeper malware-verification block. The Windows executable was
Authenticode `NotSigned`, and its only consumer evidence came from Windows
Server 2025 rather than a client system. Kyle therefore authorized withdrawing
both macOS archives and the Windows archive.

Before deletion, recovery copies matched the published hashes. Release
`379061612` now presents Linux x86-64 as its sole supported binary; its revised
body has SHA-256
`c25dca80acc2d53564be8a88f211d925e0d5fb79ef67f1ea251fd8d7db204db5`.
The Linux asset and original combined manifest remain byte-identical. The
manifest still lists the withdrawn files as an immutable record of the
original release. Re-uploading any withdrawn asset requires a new explicit
decision. The tag, source commit, Linux bytes, legal notices, and GitHub source
archives were not changed.
