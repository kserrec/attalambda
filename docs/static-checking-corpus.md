# Optional static checking: measured example corpus

Measured from local source `61a87c2ee56c3dd5e74ebf3173f6336f1ce8ff5e`
with corrected Racket CS 9.3 in the isolated implementation container.
This is unreleased feature evidence; the published 0.8.0 binary does not include
`--check`. All five tracked public `.attl` examples were analyzed unchanged with
`racket runner/attalambda.rkt --check FILE.attl`. No example was executed to
obtain these results. Commands exited with their reported static status and
empty stderr. Exact logs, example hashes, and machine-readable results are in
`/tmp/attalambda-static-implementation-mmgdshl_/corpus-results.json` and
`step-5.1.log`; the complete human-readable results are retained below.

| Example | Status | Definitions | Expressions | Unproved regions | Conflicts |
| --- | --- | --- | --- | ---: | ---: |
| [file-round-trip.attl](../examples/file-round-trip.attl) | PARTIAL (2) | 2/2 (100.0%) | 24/32 (75.0%) | 1 | 0 |
| [foundations.attl](../examples/foundations.attl) | PARTIAL (2) | 1/1 (100.0%) | 126/138 (91.3%) | 3 | 0 |
| [hello.attl](../examples/hello.attl) | FULL PASS (0) | 0/0 (n/a) | 3/3 (100.0%) | 0 | 0 |
| [http-server.attl](../examples/http-server.attl) | PARTIAL (2) | 3/5 (60.0%) | 134/199 (67.3%) | 9 | 0 |
| [stdout.attl](../examples/stdout.attl) | FULL PASS (0) | 0/0 (n/a) | 3/3 (100.0%) | 0 | 0 |

The two greeting programs establish all obligations. The other three examples
have the limitations fixed before implementation, with no definite type
conflicts. `foundations.attl` unwraps three represented arithmetic Results;
V1 does not prove their variants. `file-round-trip.attl` guards its unwrap with
`is-ok`, but V1 deliberately performs no variant refinement. Its two String
definitions are complete while the whole file remains partial.

`http-server.attl` leaves two definitions incomplete: `nat-to-decimal` unwraps
division, and `close-listener` uses a numerically constrained TCP wrapper. Its
top-level expression also uses TCP listen, unwrap, three List accesses, an
injected HTTP host factory, and raw host. The precise locations and all nine
primary reasons follow. Independent `decimal-digit`, `force-result`, and
`handler` contracts remain established. These are accepted V1 limits, not
permission to rewrite the examples, invent refinements, or claim whole-file
success from complete declarations alone.

The earlier [seed pilot](static-checking-pilot.md) remains historical. Its 18
fixed fixtures still meet their expectations with the complete inventory; the
25-case combined fixture set also covers C01–C18 (both divergent C05 forms) and
the complete specification Section 3.2 example. They pass through the backend
and real CLI in the Phase 4 checkpoint. Command faults/non-execution/C19–C22 are
covered separately. There is no arbitrary corpus percentage target.

Coverage counts discharged source obligations, not execution safety or tests.
The [contract inventory](static-checking-contracts.md) is a trusted basis; these
checks do not infer or formally verify library/runtime implementations. Ordinary
execution remains available for partial files. No claim of termination or
successful external operations follows from a complete type.

## file-round-trip.attl

Source SHA-256: `6d93711e3a96fe2372a2037a33d42592a1380dd8d9e56a50e7ac30213a998ba4`.

```text
Static type check: PARTIAL
Scope: examples/file-round-trip.attl; all source definitions and expressions
Definitions: 2/2 fully checked (100.0%)
Expressions: 24/32 fully checked (75.0%)
Unproved regions: 1
Type conflicts: 0

Inferred definitions:
  path : String
  contents : String

Diagnostics (one-based lines, zero-based columns):
examples/file-round-trip.attl:12:38 [UNREPRESENTED_ERROR_ALTERNATIVE]
  WrongResultVariant may return Error; V1 does not refine Result variants.

Trusted basis: built-in contracts, rec lowering, and host/codec contracts.
Coverage counts source obligations; it does not certify the trusted implementations.
This does not prove termination or successful external operations, or exclude deliberate Error/Result Err values.
```

## foundations.attl

Source SHA-256: `bb14118a1fcda1fb96b1d1a4bb0029e5f450d0f84141f9f85eebdb0d3040e908`.

```text
Static type check: PARTIAL
Scope: examples/foundations.attl; all source definitions and expressions
Definitions: 1/1 fully checked (100.0%)
Expressions: 126/138 fully checked (91.3%)
Unproved regions: 3
Type conflicts: 0

Inferred definitions:
  show : String -> Bool -> Result(Unit)

Diagnostics (one-based lines, zero-based columns):
examples/foundations.attl:12:28 [UNREPRESENTED_ERROR_ALTERNATIVE]
  WrongResultVariant may return Error; V1 does not refine Result variants.
examples/foundations.attl:13:19 [UNREPRESENTED_ERROR_ALTERNATIVE]
  WrongResultVariant may return Error; V1 does not refine Result variants.
examples/foundations.attl:14:28 [UNREPRESENTED_ERROR_ALTERNATIVE]
  WrongResultVariant may return Error; V1 does not refine Result variants.

Trusted basis: built-in contracts, rec lowering, and host/codec contracts.
Coverage counts source obligations; it does not certify the trusted implementations.
This does not prove termination or successful external operations, or exclude deliberate Error/Result Err values.
```

## hello.attl

Source SHA-256: `1f3cfbadbd4a2dcf6e6245af8e4b414f31442f7299f52c32d927a7c9dcb20ae4`.

```text
Static type check: FULL PASS
Scope: examples/hello.attl; all source definitions and expressions
Definitions: 0/0 fully checked (n/a)
Expressions: 3/3 fully checked (100.0%)
Unproved regions: 0
Type conflicts: 0

Trusted basis: built-in contracts, rec lowering, and host/codec contracts.
Coverage counts source obligations; it does not certify the trusted implementations.
This does not prove termination or successful external operations, or exclude deliberate Error/Result Err values.
```

## http-server.attl

Source SHA-256: `2934b61dab540ffe5bd48a4494b8bbede86ae9a9dc524ee4389c812a14b78e42`.

```text
Static type check: PARTIAL
Scope: examples/http-server.attl; all source definitions and expressions
Definitions: 3/5 fully checked (60.0%)
Expressions: 134/199 fully checked (67.3%)
Unproved regions: 9
Type conflicts: 0

Inferred definitions:
  decimal-digit : Rat -> Char
  force-result : forall a:data b. Result(a) -> (Result(a) -> b) -> b
  handler : String -> Result(String)

Diagnostics (one-based lines, zero-based columns):
examples/http-server.attl:30:30 [UNREPRESENTED_ERROR_ALTERNATIVE] in nat-to-decimal
  WrongResultVariant may return Error; V1 does not refine Result variants.
examples/http-server.attl:42:23 [UNREPRESENTED_ERROR_ALTERNATIVE] in close-listener
  Numeric fields require nonnegative integers; the pure wrapper may return InvalidCount Error.
examples/http-server.attl:55:22 [UNREPRESENTED_ERROR_ALTERNATIVE]
  Numeric fields require nonnegative integers; the pure wrapper may return InvalidCount Error.
examples/http-server.attl:57:32 [UNREPRESENTED_ERROR_ALTERNATIVE]
  WrongResultVariant may return Error; V1 does not refine Result variants.
examples/http-server.attl:58:25 [UNREPRESENTED_ERROR_ALTERNATIVE]
  An empty List returns Error; V1 has no nonempty refinement.
examples/http-server.attl:59:23 [UNREPRESENTED_ERROR_ALTERNATIVE]
  An empty List returns Error; V1 has no nonempty refinement.
examples/http-server.attl:59:29 [UNREPRESENTED_ERROR_ALTERNATIVE]
  An empty List returns Error; V1 has no nonempty refinement.
examples/http-server.attl:68:21 [UNSUPPORTED_CONTRACT]
  anonymous lambda at examples/http-server.attl:65:13 (source span 351 characters)
  The injected host protocol is outside V1; numeric listener/read limits can also return Error.
examples/http-server.attl:68:41 [UNSUPPORTED_CONTRACT]
  anonymous lambda at examples/http-server.attl:65:13 (source span 351 characters)
  Raw host uses an operation-dispatched request protocol; V1 establishes no result contract.

Incomplete definitions (one reason path each):
  nat-to-decimal: [UNREPRESENTED_ERROR_ALTERNATIVE] at examples/http-server.attl:30:30
  close-listener: [UNREPRESENTED_ERROR_ALTERNATIVE] at examples/http-server.attl:42:23

Dependent top-level expressions:
  examples/http-server.attl:55:0 depends on nat-to-decimal: [UNREPRESENTED_ERROR_ALTERNATIVE] at examples/http-server.attl:30:30

Trusted basis: built-in contracts, rec lowering, and host/codec contracts.
Coverage counts source obligations; it does not certify the trusted implementations.
This does not prove termination or successful external operations, or exclude deliberate Error/Result Err values.
```

## stdout.attl

Source SHA-256: `1f3cfbadbd4a2dcf6e6245af8e4b414f31442f7299f52c32d927a7c9dcb20ae4`.

```text
Static type check: FULL PASS
Scope: examples/stdout.attl; all source definitions and expressions
Definitions: 0/0 fully checked (n/a)
Expressions: 3/3 fully checked (100.0%)
Unproved regions: 0
Type conflicts: 0

Trusted basis: built-in contracts, rec lowering, and host/codec contracts.
Coverage counts source obligations; it does not certify the trusted implementations.
This does not prove termination or successful external operations, or exclude deliberate Error/Result Err values.
```
