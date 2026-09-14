# Terminal line input contract

Implementation authorized by Kyle on 2026-09-14, on `terminal-input`.
This is a source feature for a future release; 0.7.0 does not include it.

## Public operation and results

`(read-line UNIT)` is a unary, strict typed operation. UNIT supplies the one
argument required by the language; it is not a prompt or an input handle.
Wrong tagged arguments produce TypeMismatch, and incoming Error values bubble
with the normal `read-line` argument frame, before any host call.

On demand it reads one line from the launching process's standard input,
using Racket's `read-bytes-line` in `any` mode, including its blocking behavior.
Success is `Ok(Some(String))`. A blank line is `Ok(Some(EMPTY-STRING))`.
End of input before any bytes is `Ok(NONE)`; a final nonempty unterminated line is returned
once as Some, followed by NONE on the next read. A subsequent request retries
the stream normally; no EOF flag or input registry is maintained.

LF, CRLF, and CR are line separators; CRLF is one separator. After CR, the
native reader waits for another byte or end of input to determine whether
LF follows. A following LF is consumed as part of CRLF; any other following
byte remains for the next line. A bare CR on a still-open stream therefore
does not guarantee immediate completion. Senders that wait for a reply
should finish their line with LF or a complete CRLF. This is the accepted
native behavior; no custom buffering or line reader is added.

Only the separator is removed. Every other byte, including spaces, tabs,
NUL, and bytes 128 through 255, is preserved as an existing byte-sized Char. No
Unicode decoding, trimming, parsing, evaluation, or numeric conversion occurs.
Like whole-file input, line input has no fixed length limit. Native
allocation failures become `Err(HostFailure(read-line, resource-exhausted))`;
other expected native read failures become `Err(HostFailure(read-line,
io-failure))`. Diagnostics do not expose exception messages or port names.
Process interruption retains the launcher's existing behavior.

## Effects, demand, and reuse

Reading neither writes a prompt nor changes terminal settings, checks for a
physical terminal, opens a device, closes standard input, nor owns buffered
state outside the input port. Redirected files and pipes are supported.
Programs write prompts separately through stdout, which already flushes.

Constructing a pending call or leaving it in an unselected branch performs
no read. Demanding a call performs one read; reusing its result reuses that
answer. Applying a function containing a fresh read on each invocation can
read successive lines. Top-level expressions are demanded in source order.
Inside a function, use the existing Result checks and branch dependencies to
order output, input, and recursion; merely naming two effects with lazy let
does not sequence them. No new sequencing primitive is introduced.

A future REPL may build expression assembly and evaluation above line input.
Continuation prompts, multiline parsing, history, editing, and retained
definitions belong to that future layer and are not part of this feature.

## Exact implementation boundary

`effects/stdin.rkt` exports `make-read-line-request` and `make-read-line`.
Both use the existing generalized checker with one Unit argument. The
builder accepts its injected unary host first. The internal request is the
proper one-element List `["read-line"]`; Unit is only the public call trigger.
The protocol's existing generalized schema walker checks exact zero request
arguments. Additional arguments yield InvalidHostRequest/wrong-arity before
dispatch; unknown operations and malformed requests retain existing rules.

Only `runtime/host.rkt` reads `current-input-port` using `read-bytes-line` in
`any` mode. It defensively checks the operation and zero-argument arity, then
converts the answer through `runtime/codec.rkt`. The codec gains only
`object-none` and unary `object-some`, constructed with existing pure Option
terms; it never reads input or inspects an input port.
`lang/expander.rkt` binds the injected wrapper privately as
`language-read-line` and exports it as `read-line`, isolating Racket's native
binding. Native input remains forbidden in the language facade, core,
effects, readers, and codec. Both structural gates retain their other rules.

The three canonical documents incorporate this contract through narrowly
scoped Terminal Line Input Amendments. Existing types, evaluation, native
capabilities, public operations, dependencies, and release versions otherwise
keep their current contracts.

Native API reference: [Racket byte and string input](https://docs.racket-lang.org/reference/Byte_and_String_Input.html).
