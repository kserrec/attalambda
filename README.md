# AttaLambda

AttaLambda is a small programming language built around a big question:

> How much of a practical language can be made from pure lambda calculus?

Programs use familiar Lisp-shaped syntax, but ordinary computation expands to
only variables, one-argument lambdas, and function application. Racket supplies
lazy evaluation and module machinery; effects cross one explicit `host`
boundary.

This is a complete AttaLambda program:

```racket
#lang attalambda

(stdout "Hello from AttaLambda.\n")
```

## Try it on Linux

AttaLambda 0.5.0 is available as a self-contained Linux x86-64 archive. It
includes its own runtime, so you do not need to install Racket.

Release page: <https://github.com/kserrec/attalambda/releases/tag/v0.5.0>

Version 0.5.0 adds pure self recursion with `rec` and rejects recursive module
bindings. Change a self-recursive declaration from `def` to `rec`; mutual
top-level cycles remain invalid. The complete List API, exact rational
arithmetic, and existing host capabilities are behaviorally unchanged.
The [public API reference](docs/API.md) describes the complete surface, and
the [acceptance record](docs/ACCEPTANCE.md) records source and published-archive
verification.

See the [0.5.0 migration and release notes](docs/releases/0.5.0.md) for a
complete recursive-function example and the compatibility changes.

Download, verify, extract, and run it:

```sh
curl -LO https://github.com/kserrec/attalambda/releases/download/v0.5.0/attalambda-0.5.0-linux-x86_64.tar.gz
curl -LO https://github.com/kserrec/attalambda/releases/download/v0.5.0/SHA256SUMS
sha256sum -c SHA256SUMS
tar -xzf attalambda-0.5.0-linux-x86_64.tar.gz
cd attalambda-0.5.0-linux-x86_64
./bin/attalambda --version
./bin/attalambda examples/hello.attl
```

You should see:

```text
AttaLambda 0.5.0
Hello from AttaLambda.
```

Linux x86-64 is the only supported binary target. Users should not have to
bypass operating-system security protections to try the language, so macOS
builds without Apple signing and notarization and Windows builds without
Authenticode signing are not distributed.

## Run it from source

You need Racket. The install command registers the checkout in your user-level
Racket package registry and does not require administrator access:

```sh
git clone https://github.com/kserrec/attalambda.git
cd attalambda
raco pkg install --auto --name attalambda .
racket runner/attalambda.rkt examples/hello.attl
```

AttaLambda has no third-party package dependencies. Its runtime dependencies
are Racket's `base` and `lazy` packages; tests also use `rackunit-lib` and
`net-lib`.

To run the complete test and structural-purity suite:

```sh
./run-all-tests.sh
```

## What makes AttaLambda unusual?

- Every ordinary function is built from nested one-argument lambdas. Partial
  application follows naturally from that representation.
- Bool, List, Rat, Unit, Byte, Option, Map, Error, Result, Char, and String
  are all lambda-encoded values. Operations check their type tags at
  runtime.
- The one public number type is Rat: exact rationals stored as a reduced
  signed numerator over a positive denominator, with normalized binary digit
  Lists underneath instead of Church numerals. Arithmetic is exact, never
  grows with a unary encoding, and fractions like `-7/3` are ordinary
  literals.
- Errors are ordinary structured values. Expected computational failures use
  `Result`; contract and representation failures use `Error`.
- Output, files, blocking TCP, and explicit process exit are available through
  one host boundary. Pure HTTP framing, parsing, response rendering, and
  routing sit above that boundary as ordinary language computation.
- Automated structural checks reject host computation, hidden privileged
  imports, non-unary lambdas, and unknown source locations in production
  paths.

The goal is not to hide Racket behind a new syntax. It is to make the boundary
between lambda-calculus computation and host authority small, visible, and
testable.

On this branch, `(exit 0)` reports successful completion and `(exit 1)` reports
unsuccessful completion. Only Rat 0 or 1 is accepted: another type returns
TypeMismatch Error; another Rat returns InvalidCount Error, without calling
the host. Pure AttaLambda chooses and validates the status; only the host
terminates the process. Exit prints nothing automatically and prevents later
effects. Without an exit call, normal completion remains status 0, even when
the program produces an Error or Result Err. Launcher failures keep their
separate statuses.

## Examples

The repository includes five programs written entirely through the public
`#lang attalambda` surface:

| Example | What it does |
| --- | --- |
| [`hello.attl`](examples/hello.attl) | Prints a greeting. |
| [`stdout.attl`](examples/stdout.attl) | Exercises explicit standard output. |
| [`foundations.attl`](examples/foundations.attl) | Exercises exact rational arithmetic, Unit, Byte, Option, and Map end to end. |
| [`file-round-trip.attl`](examples/file-round-trip.attl) | Writes and reads back a file. |
| [`http-server.attl`](examples/http-server.attl) | Serves one request on an ephemeral loopback port, then exits. |

Run any example from a registered source checkout with:

```sh
racket runner/attalambda.rkt examples/hello.attl
```

AttaLambda does not sandbox programs. A program can use the same relevant
standard-output, filesystem, and network permissions as the Racket or
AttaLambda process that launched it, and can terminate its own process with
status 0 or 1. Inspect unfamiliar `.attl` files before running them. In
particular, `file-round-trip.attl` creates or truncates
`attalambda-round-trip.txt` in its current directory.

## Project status

Version 0.5.0 is the fourth public release. It adds `rec` and enforces the
purity rule against recursive module bindings. Rat
remains the only public number type; Unit, Byte, Option, Map, and byte-based
file/TCP payloads retain their existing representations.
[`PLAN.md`](PLAN.md) holds the current roadmap and
[`PLAN-ARCHIVE.md`](PLAN-ARCHIVE.md) the completed phase history; this README
intentionally repeats neither.

## Repository guide

| Path | Purpose |
| --- | --- |
| [`core/`](core) | Pure representations, raw algorithms, and strict typed operations. |
| [`effects/`](effects) | Pure requests and wrappers for output, files, TCP, exit, and HTTP. |
| [`runtime/codec.rkt`](runtime/codec.rkt) | Deterministic conversion between lambda values and private host data. |
| [`runtime/host.rkt`](runtime/host.rkt) | The sole privileged `host`; start at `dispatch-request`. |
| [`lang/expander.rkt`](lang/expander.rkt) | Public exports, literal expansion, currying, and one-time host injection. |
| [`runner/attalambda.rkt`](runner/attalambda.rkt) | Command, source validation, sanitized diagnostics, and one source load. |
| [`macros/`](macros) | The two trusted mechanical-expansion modules every production file compiles through. |
| [`readers/`](readers) | One-way human-readable observation used outside production computation. |
| [`tests/`](tests) | Behavioral, representation, error, laziness, and boundary tests. |
| [`tooling/`](tooling) | Purity, boundary, and distribution checks. |

For more detail:

- [`docs/API.md`](docs/API.md) describes the implemented public source API.
- [`ARCHITECTURE.md`](ARCHITECTURE.md) explains the layers and dependency
  direction.
- [`docs/specifications/`](docs/specifications/README.md) contains the three
  documents that define the language.
- [`docs/ACCEPTANCE.md`](docs/ACCEPTANCE.md) maps requirements to executable
  and structural evidence.
- [`docs/design/host-boundary.md`](docs/design/host-boundary.md) records the
  approved host protocol and its exact authority.
- [`AGENTS.md`](AGENTS.md) contains the implementation rules for contributors
  and coding agents.

## License

Copyright 2026 Kyle Serrecchia.

AttaLambda is available under the [Apache License 2.0](LICENSE). Self-contained
release archives include the applicable Racket runtime notices and license
texts.
