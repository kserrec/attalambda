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

AttaLambda 0.9.0 is available as a self-contained Linux x86-64 archive. It
includes its own runtime, so you do not need to install Racket.

Release page: <https://github.com/kserrec/attalambda/releases/tag/v0.9.0>

Version 0.9.0 adds optional `--check FILE.attl` static checking without running
the program. It reports full passes, definite conflicts and partial results,
with exact coverage and inferred signatures. The `atta>` shell, runtime line
input, Lisp syntax, pure value rendering and `print`, exact rational
arithmetic, the complete List API, and the pure `rec` rules remain available.
The [public API reference](docs/API.md) describes the complete surface, and
the [acceptance record](docs/ACCEPTANCE.md) records source and published-archive
verification.

See the [0.9.0 release notes](docs/releases/0.9.0.md) for the new features
and compatibility.

Download, verify, extract, and run it:

```sh
curl -LO https://github.com/kserrec/attalambda/releases/download/v0.9.0/attalambda-0.9.0-linux-x86_64.tar.gz
curl -LO https://github.com/kserrec/attalambda/releases/download/v0.9.0/SHA256SUMS
sha256sum -c SHA256SUMS
tar -xzf attalambda-0.9.0-linux-x86_64.tar.gz
cd attalambda-0.9.0-linux-x86_64
./bin/attalambda --version
./bin/attalambda examples/hello.attl
```

You should see:

```text
AttaLambda 0.9.0
Hello from AttaLambda.
```

Run `./bin/attalambda` in a terminal to start the shell; enter `:help` for its
commands and `:quit` to leave. See the tested
[terminal input example](docs/API.md#terminal-line-input) and
[interactive guide](docs/API.md#interactive-shell).

Linux x86-64 is the only supported binary target. Users should not have to
bypass operating-system security protections to try the language, so macOS
builds without Apple signing and notarization and Windows builds without
Authenticode signing are not distributed.

## Optional static checking

Version 0.9.0 includes `--check FILE.attl`. From the extracted archive, check an
existing program without running it:

```sh
./bin/attalambda --check examples/hello.attl
```

The report says `FULL PASS` (status 0), `FAIL` (1), or `PARTIAL` (2), with exact
definition and expression coverage and inferred signatures. Checking needs no
annotations and performs no program input, output, file, network, or exit effect.
Ordinary execution and runtime type checks remain available unchanged.

The first version infers finite function and container types, reusable rank-1
polymorphic definitions, source lets, and ordinary `rec`. It conservatively
leaves unwrapping, empty-list access, numeric refinements, and raw host protocols
partial. A full pass relies on audited built-in contracts and does not prove
termination or successful external operations. See the [checking reference](docs/API.md#optional-static-checking),
[audited contracts](docs/static-checking-contracts.md), and
[measured results for all five examples](docs/static-checking-corpus.md).
Exact build and public-download evidence is recorded in the
[0.9.0 release notes](docs/releases/0.9.0.md) and [HANDOFF.md](HANDOFF.md).

## Run it from source

The `main` branch includes released static checking, runtime input and the
interactive shell.
The full source suite and fresh public Linux download pass their tests,
including terminal interaction and relocation. [HANDOFF.md](HANDOFF.md) records
the tagged build revision and the later publication records.

Use an isolated Racket CS 9.3 installation with the milestone's
[reviewed dependency corrections](tooling/patches/README.md). They preserve shared
lazy values after Ctrl+C and correct editor source display, history and redraw.
Explicit preparation changes only that isolated
installation; do not apply it to a personal or system runtime. The install command
below registers the checkout in that environment's Racket package registry:

```sh
git clone --branch main https://github.com/kserrec/attalambda.git
cd attalambda
racket tooling/prepare-racket-runtime.rkt --apply
racket tooling/prepare-racket-runtime.rkt --check
raco pkg install --auto --name attalambda .
racket runner/attalambda.rkt examples/hello.attl
```

This release is tested with the corrected Racket CS 9.3 and Linux Python 3 for terminal
acceptance. Runtime dependencies are `base`, `lazy`, `expeditor-lib`, and
`syntax-color-lib`; tests also use `rackunit-lib` and `net-lib`. The maintained
Expeditor and lexer packages supply terminal editing and S-expression handling.
Their transitive Parser Tools and Option Contract packages are included in
the distribution notices. Python is test tooling only and is absent from the
standalone archive.

Start the source shell in a terminal with `racket runner/attalambda.rkt`.
Type expressions without `#lang attalambda`; use `:help` for the six commands.
Definitions stay lazy, and expression results print as `=> 5`, `=> TRUE`, or
other canonical value displays. Use `:echo off` before evaluating raw functions:
their printing behavior is unspecified. `--repl` explicitly permits redirected
transcripts; `--no-history` disables persistent source history.

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
- Output, standard-input lines, files, blocking TCP, and explicit
  process exit are available through one host boundary. Pure HTTP framing,
  parsing, response rendering, and routing sit above that boundary as ordinary
  language computation.
- Automated structural checks reject host computation, hidden privileged
  imports, non-unary lambdas, and unknown source locations in production
  paths.

The goal is not to hide Racket behind a new syntax. It is to make the boundary
between lambda-calculus computation and host authority small, visible, and
testable.

`(exit 0)` reports successful completion and `(exit 1)` reports
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

Version 0.9.0 is the eighth public release. It adds optional static checking
while preserving ordinary execution, the interactive shell and pure lambda
calculus.
It includes pure value renderers and generic `print` through the stdout boundary. See
[Value Rendering and Printing](docs/API.md#value-rendering-and-printing).
The purity rule against recursive module bindings continues to apply. Rat
remains the only public number type; Unit, Byte, Option, Map, and byte-based
file/TCP payloads retain their existing representations.
[`PLAN.md`](PLAN.md) holds the current roadmap and
[`PLAN-ARCHIVE.md`](PLAN-ARCHIVE.md) the completed phase history; this README
intentionally repeats neither.

## Repository guide

| Path | Purpose |
| --- | --- |
| [`core/`](core) | Pure representations, raw algorithms, and strict typed operations. |
| [`effects/`](effects) | Pure requests and wrappers for output, line input, files, TCP, exit, and HTTP. |
| [`runtime/codec.rkt`](runtime/codec.rkt) | Deterministic conversion between lambda values and private host data. |
| [`runtime/host.rkt`](runtime/host.rkt) | The sole privileged `host`; start at `dispatch-request`. |
| [`lang/expander.rkt`](lang/expander.rkt) | Public exports, literal expansion, currying, and one-time host injection. |
| [`runner/attalambda.rkt`](runner/attalambda.rkt) | File/shell selection and sanitized launcher diagnostics. |
| [`runner/static/`](runner/static) | Private non-evaluating type inference, audited contracts, coverage, reports, and the optional checking command. |
| [`runner/repl.rkt`](runner/repl.rkt) | Commands, original-input handoff, echo, and history lifecycle. |
| [`runner/session.rkt`](runner/session.rkt) | Checked entry modules, binding snapshots, loads, and resource ownership. |
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
