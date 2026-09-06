# Host boundary design

Status: approved 2026-08-27; explicit exit amendment approved 2026-09-05.
Exit protocol, host, and public wrapper injection are implemented. The 0.3.0
representation and existing nine operations are behaviorally unchanged.

This document records the exact current contract for AttaLambda's one
outside-world boundary. The three canonical
[`docs/specifications/`](../specifications/README.md) documents remain
authoritative.

## The boundary in one page

- `runtime/host.rkt` alone defines and exports the unary `host` value.
- `runtime/codec.rkt` converts representations. It performs no external
  effect, owns no registry, and is imported in production only by the host.
- `effects/` validates arguments and constructs requests with pure lambda
  computation. It receives the host as an ordinary unary argument and never
  imports `runtime/`.
- `lang/expander.rkt` is the sole production importer of `host`; it injects
  that value once into the ten public wrappers.
- The closed effect set is standard output, whole-file read and replacement,
  blocking TCP connect/listen/accept/read/write/close, and explicit process exit.
- HTTP parsing, rendering, routing, and server decisions stay in `effects/`
  as pure computation over the TCP wrappers.
- The host inherits the launching process's permissions. It is not a sandbox.

The shortest implementation path is:

```text
effects wrapper -> host -> dispatch-request -> perform-* -> codec result
```

Explicit exit ends at `perform-exit`: successful real termination has no
return value to convert.

Start with `dispatch-request` in `runtime/host.rkt` for routing and argument
decoding. Follow only its selected `perform-*` function for the native effect,
and open `runtime/codec.rkt` only for the representation conversion it calls.

## Boundary type and request shape

Conceptually:

```text
host : List -> Error | Result (or explicit process termination)
```

A request is one canonical proper List:

```text
[operation argument ...]
```

`operation` is a typed String containing a closed lowercase ASCII name. Every
operation has exact arity. Pure wrappers check their public argument contracts;
the pure host bridge checks the complete request rules before dispatch. The
real host also decodes and defensively checks the request rather than trusting
a direct caller.

An incoming Error bubbles through the normal strict boundary. A non-List
argument returns TypeMismatch; a malformed List request returns
InvalidHostRequest. Both are bare `Error` values.
Except for exit, a valid request returns `Result`: `Ok` for success or
`Err(HostFailure)` for an expected external failure. A valid exit request
terminates with the requested status, returns nothing, and prints nothing
automatically.

## Closed operation table

| Request | Decoded constraints | Successful result |
| --- | --- | --- |
| `stdout String` | String bytes | `Ok(UNIT)` after write and flush |
| `read-file String` | path bytes must be UTF-8 | `Ok(List Byte)` with the complete file |
| `write-file String (List Byte)` | UTF-8 path and byte payload | `Ok(UNIT)` after truncating replacement |
| `tcp-connect String Rat` | nonempty UTF-8 hostname; whole port 1..65535 | `Ok(Rat)` connection handle |
| `tcp-listen String Rat Rat` | UTF-8 interface; whole port 0..65535; whole backlog 1..65535 | `Ok(List)` containing handle Rat and bound-port Rat |
| `tcp-accept Rat` | positive whole listener handle | `Ok(Rat)` connection handle |
| `tcp-read Rat Rat` | positive whole connection handle; whole maximum 1..65536 | `Ok(List Byte)`, with `NIL` at EOF |
| `tcp-write Rat (List Byte)` | positive whole connection handle and byte payload | `Ok(UNIT)` after the complete write |
| `tcp-close Rat` | positive whole listener or connection handle | `Ok(UNIT)` after removal and cleanup |
| `exit Rat` | canonical whole Rat exactly 0 or 1 | process terminates with that status; does not return |

The table's operation and arguments are List elements, not Racket command
arguments. Numeric fields remain typed Rat values at the boundary; conversion
accepts only nonnegative whole values in the listed range. Handles are
positive whole Rats but are opaque identifiers, not public resource objects.

For `tcp-listen`, an empty interface String means all local interfaces. Port
zero requests an ephemeral port and the returned pair reports the actual bound
port. `tcp-read` blocks until data, EOF, or failure. An empty write still
validates the connection and succeeds without a platform write.

## Pure wrappers

The wrapper names in the approved language contract are:

```text
stdout
read-file
write-file
tcp-connect
tcp-listen
tcp-accept
tcp-read
tcp-write
tcp-close
exit
```

`effects/stdout.rkt`, `effects/files.rkt`, `effects/tcp.rkt`, and
`effects/exit.rkt` build these wrappers. Each builder accepts a host first,
which lets tests inject a unary fake. That injection is ordinary lambda
calculus and does not create another privileged primitive.

Request construction and validation remain pure. A bad typed argument,
non-whole count, or non-Byte payload element becomes the specified Error
before the host is called. The pure host bridge rejects an out-of-range whole
count before its strict dispatcher runs. Early Errors retain exact remaining
unary arity and normal propagation frames.

For exit, the generalized checker produces TypeMismatch for a non-Rat and
bubbles an incoming Error with its normal frame. Pure Rat equality admits
only 0 or 1; every other Rat produces InvalidCount without a host call.
Malformed direct List requests retain InvalidHostRequest instead. The host
uses the unchanged codec and bounded-count decoder to defensively require a
canonical whole Rat 0 or 1. It does not choose a status from any other value.

## Errors and external failures

InvalidHostRequest and HostFailure use Error kinds in the approved tiny Church
metadata namespace; they are not new object-language types.

```text
InvalidHostRequest details = raw-pair(operation String, reason String)
HostFailure details         = raw-pair(operation String, code String)
```

If the operation cannot be recovered, its detail is `EMPTY-STRING`. The
closed malformed-request reasons are:

```text
unknown-operation
wrong-arity
wrong-type
out-of-range
```

The closed external failure codes are:

```text
not-found
permission-denied
invalid-path
invalid-text
invalid-handle
wrong-handle-kind
address-in-use
connection-refused
connection-reset
broken-pipe
network-unreachable
name-resolution-failed
resource-exhausted
timed-out
io-failure
```

`runtime/host.rkt` maps stable Racket and operating-system categories to the
most specific code above and uses `io-failure` as the fallback. Returned data
never contains exception text, errno data, a native path or hostname, a port,
socket, or other Racket value.

Malformed direct calls are contract failures and therefore bare Error values.
Operating-system rejection of a valid request is expected computational
failure and therefore `Result Err`.

## Codec contract

`runtime/codec.rkt` exports concrete conversions for:

- proper List to and from a private host list;
- String to and from immutable bytes;
- `List Byte` to and from immutable bytes;
- exact Rat to and from a Racket exact rational;
- canonical Unit, Ok, and Err construction.

Decoding checks tags, proper List tails, cycles, Byte/Char bounds, normalized
binary magnitudes, reduced Rat parts, a positive denominator, and the sole
positive `0/1` zero. A malformed representation returns `codec-failure` and
never reaches a native effect. Encoding builds canonical lambda values and
does not run object-language arithmetic.

The codec may force validated values and use temporary private Racket data for
translation. It may not interpret paths, dispatch operations, perform I/O,
map exceptions, mutate resource state, implement language algorithms,
format values for people, terminate the process, or decide program success.

## Bytes, paths, and files

Stdout, file contents, and TCP payloads are byte-exact. No newline, text
normalization, or character encoding is implicit:

```text
one object Char or Byte <-> one host byte
```

Path and TCP name Strings are the exception: the host interprets their bytes
as UTF-8. Invalid encoding returns `invalid-text`. Host rejection of a decoded
path returns the applicable closed filesystem code.

Relative paths use the process's current directory; absolute paths are
allowed. Host-default symlink traversal applies. `read-file` reads the complete
file. `write-file` creates a missing file or truncates and replaces an existing
one. It creates no parent directory and is not atomic, so a failed write may
leave a partial file.

`stdout` writes raw String bytes to the current output port and flushes before
returning. It appends nothing and does not write stderr.

## TCP registry and cleanup

The host owns one private registry of listeners and full-duplex connections.
Handles start at one, increase monotonically, and are never reused within a
runtime instance. A fabricated, closed, or foreign handle returns
`invalid-handle`; using a listener as a connection or the reverse returns
`wrong-handle-kind`.

Connect, listen, and accept register a resource only after successful
acquisition. If registration or result conversion fails, the newly acquired
resource is cleaned up. Read or write failure removes and closes its
connection. Close removes the handle before attempting native cleanup, tries
both ports of a connection, and leaves the handle stale even if cleanup
reports failure. The current custodian closes any resources left at process
shutdown, but normal language paths still close handles explicitly.

The TCP API is synchronous and blocking. It has no timeout argument,
half-close, readiness, TLS, UDP, asynchronous operation, production thread, or
cancellation surface. Hostname resolution is part of `tcp-connect`.

## Laziness and order

Constructing a request has no effect. The effect occurs when the host
application is forced. A forced promise caches its value, so forcing the same
bound application again does not repeat the effect; making another host
application requests another effect.

Successful real exit never returns to be forced again. An injected fake host
may return an ordinary value; the exit wrapper preserves that value and its
normal force-once behavior. An exit in an unselected branch remains unforced.

Programs sequence effects through a data dependency: inspect the first Result,
select an Ok or Err continuation with the strict lazy conditional, and create
the next host application only in the selected continuation. Binding an unused
first result does not establish order.

Pure AttaLambda decides whether a failure is fatal and explicitly calls exit
with 1 (unsuccessful completion) or 0 (successful completion). Error and
Result Err remain ordinary values; neither the host nor runner automatically
prints them or derives a status from them. Without an exit call, normal
program completion remains status 0. A performed exit prevents later effects.
The runner's separate native exit path remains limited to launcher, source,
and scaffolding failures; only the host performs program-requested exit.

## Authority

The real host has the launching process's relevant authority. An AttaLambda
program can write stdout, read permitted files, create or truncate permitted
paths including symlink targets, resolve names, connect to permitted remote TCP
endpoints, bind permitted local ports, and terminate its own process with
status 0 or 1. Users must inspect and trust a program before running it.

The closed host does not expose environment enumeration, subprocesses, shell
commands, dynamic loading, evaluation, namespaces, FFI, directory listing or
deletion, clocks, randomness, UDP, TLS, or an HTTP library. This closed set
limits available operations; it does not create a filesystem or network
sandbox.

## Dependency and enforcement

```text
core <- effects <- lang
core <- runtime/codec <- runtime/host <- lang
core <- effects/protocol <- runtime/host
```

`tooling/check-purity.rkt` verifies that `core/` and `effects/` expand only to
the permitted lambda terms. `tooling/check-boundaries.rkt` enforces the sole
host definition/export/import path, sole production codec importer, closed
runtime imports and capabilities, reader separation, and complete source
classification. Focused tests cover request precedence, all codec directions,
failure mapping, force-once behavior, byte-exact files and stdout, loopback TCP
lifecycle, cleanup, and hostile boundary mutations.

## Approval record

Kyle approved the high-level `host` boundary and this concrete request,
conversion, authority, and runtime design on 2026-08-27 by replying:

```text
Approve the Phase 13 host-boundary design.
```

The approved implementation subsequently replaced public Nat counts and
handles with whole Rat values, acknowledgements with Unit, and file/TCP
payload Strings with `List Byte` as part of the completed 0.3.0 language
change. The current contract above includes those approved representations;
the operation set and sole-host authority did not change.

On 2026-09-05 Kyle approved the five-phase HTTP/List/exit plan. Its matching
amendments to all three normative specifications add exactly the tenth exit
operation above. The sole-host architecture, deterministic codec role, and
absolute object-language purity remain in force. No process spawning,
signals, other exit statuses, or automatic Error/Result status mapping was
approved.
