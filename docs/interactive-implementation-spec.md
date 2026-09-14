# Interactive AttaLambda
## Autonomous implementation specification: runtime input + `atta>` REPL

**Prepared:** September 14, 2026  
**Repository:** `kserrec/attalambda`  
**Proposed release:** `0.8.0`  
**Delivery format:** one combined milestone, preserving the existing runtime-input work  
**Status:** implementation contract, not a claim that implementation or verification is complete

This document supersedes the earlier REPL proposal and its subsequent review. It is self-contained; an implementation agent does not need the preceding conversation. The prompt is **`atta>`**, the executable remains **`attalambda`**, and source files remain **`.attl`**.

## 1. Objective and baseline

Deliver a useful terminal REPL around AttaLambda's existing checked language implementation. The next release has exactly two feature themes: the already implemented input operation for running programs, and interactive development through the REPL. Do not build another interpreter or redesign the language to make the REPL easier.

The inspected input branch is `terminal-input` at `62d0f0cf7e042bd6478024697c460c9fc88b50f7`. The previously inspected `main` is `71232f7fb47f8daad61e6a7a6bcf4a5477532352`, and the published baseline is `v0.7.0`. Recheck all three before starting. These identifiers establish provenance, not permission to overwrite newer work. The input implementation and its verification record already exist; preserve and retest them. [S1–S3]

The current implementation supplies the relevant foundations: a module expander with recursion checks, a file runner, pure value rendering, and a single stateful host boundary. The design below reuses them. Its module/session plumbing and terminal handoff still require implementation-time proof; they are not presented as a tested prototype. [S4–S7]

### 1.1 What completion means

The normal autonomous endpoint is a **verified, documented, clean release candidate**, with the implementation committed and pushed according to repository rules when those operations are authorized. A release candidate is not a published release.

When the implementation assignment also explicitly authorizes merge and publication, continue through the conditional delivery phase at the end. Otherwise stop at the release candidate and report the remaining authorization accurately. Do not publish an input-only intermediate release, infer publication permission from historical plans, or reuse another project's branch workflow.

Writing this specification alone does not modify the repository or authorize actions outside a later implementation assignment.

## 2. Execution discipline

### 2.1 Work in small verified units

Each numbered step has one primary deliverable and a local verification target. Execute steps serially. For each step: inspect the affected code, make the smallest coherent change, run its focused checks, inspect the diff, and record the result before proceeding.

If an implementation detail makes a step larger than one comfortably reviewable change-and-test cycle, split it into lettered substeps in `PLAN.md` **before implementing it**. Preserve the step's scope and acceptance criteria. Do not add product features while decomposing work. Small steps reduce risk; passing evidence, rather than a promise of first-pass perfection, determines completion.

A failed check stops dependent work. Reproduce the failure, identify its cause, make a narrow correction, rerun the relevant checks, and only then continue. Do not solve failures by weakening tests, skipping purity checks, changing input semantics, or automatically expanding timeouts.

### 2.2 Authority and ordinary decisions

Read `AGENTS.md`, the active portion of `PLAN.md`, and the canonical specification index first. Preserve the project's specification hierarchy, dotenv restrictions, source classification, and Git discipline. Append narrowly scoped canonical amendments where the new tooling boundary requires them; do not rewrite historical specifications. [S2]

Choose filenames, private helper signatures, test organization, and equivalent library plumbing autonomously. Prefer an existing project idiom or documented Racket facility. Record a meaningful deviation in a few sentences: evidence, chosen solution, preserved behavior, and validating test.

Surface a blocker only when continuing requires missing authorization, unavailable essential infrastructure, an incompatible change to the language contract, or a material change to this product scope. Do not repeatedly ask the owner to choose private implementation details. Complete independent safe work and leave a reproducible handoff when a real blocker remains.

### 2.3 Checkpoints, skills, and review

At startup, discover the execution environment's actually available testing, debugging, and code-review skills. Read a relevant skill before using it. At each checkpoint, use the best applicable available skill; do not invent skill names or require a particular agent product. **Never use Graphify in this repository.** [S2]

Skills supplement, rather than replace, executable evidence. When no appropriate skill or separate reviewer is available, use these explicit fallbacks:

| Checkpoint purpose | Required fallback procedure |
|---|---|
| Behavioral correctness | Write a minimal regression, demonstrate the intended pass/fail distinction, and run the affected existing suites. |
| Failure diagnosis | Capture the smallest reproduction, inspect the actual failure, test one causal hypothesis at a time, and fix the responsible unit. |
| Architecture or purity | Trace dependency direction, inspect actual macro-expanded user terms, and run both structural gates. |
| Terminal integration | Run bounded pseudo-terminal interactions, check bytes and process state, and verify terminal restoration on failure as well as success. |
| Cold review | Review the contract, current diff, and tests afresh; search for a reproducible counterexample, not for a quota of findings. |
| Release readiness | Test the exact candidate artifact in an isolated consumer and reconcile its source revision, version, and checksum. |

A separate read-only reviewer is preferred for the major checkpoints when available. Give it a bounded scope and request actionable findings with evidence. Do not let multiple agents edit the same workstream. If review is performed by the implementation agent, label it as self-review, not independent review. Zero findings is a valid result.

### 2.4 Evidence and phase closure

Use the existing plan/handoff files rather than adding a reporting framework. Each completed step records its ID, changed paths, exact check command or test case, result, and any unresolved limitation. Keep transient logs outside the repository. Store no secrets or program-input history in logs intended for publication.

At every phase checkpoint, inspect the complete phase diff, run the focused tests, then run the complete suite and both gates before the phase commit, as required by `AGENTS.md`. The repository's current full-suite script already includes both gates: [S8]

```sh
TMPDIR=/tmp ./run-all-tests.sh
```

Useful targeted gate commands are:

```sh
TMPDIR=/tmp racket tooling/check-purity.rkt
TMPDIR=/tmp racket tooling/check-boundaries.rkt
```

Use `raco test` for the actual focused test files created or modified in that step. Preserve failing command statuses when capturing output; do not let a logging pipeline hide failure. Use dotenv-safe path exclusions for repository content inspection and diff review. Do not read, copy, stage, or alter dotenv files. Never reset, stash, clean, or overwrite unrelated user work automatically.

If a checkpoint fails, repair only that phase's responsible unit and rerun affected checks before committing. A final verification phase cannot substitute for intermediate checks.

## 3. Fixed user-facing contract

The requirements in this section are fixed. Internal mechanisms remain flexible where explicitly stated.

### 3.1 Command line and output

Support these forms:

```text
attalambda
attalambda --no-history
attalambda --repl
attalambda --repl --no-history
attalambda FILE.attl
attalambda --help
attalambda --version
```

Accept `--repl` and `--no-history` in either order; reject duplicates, unknown flags, and combinations with file mode. `--no-history` alone selects the normal no-file entry path with persistence disabled. With no explicit `--repl`, require usable terminal stdin and UI output; otherwise issue a usage diagnostic suggesting `--repl`, with the existing misuse status. Do not reinterpret a pipe silently.

Explicit `--repl` supports terminals and redirected transcripts. Interactive mode requires terminal stdin and stderr; use stderr for terminal UI. When those conditions are not met, use plain transcript mode. A supported terminal whose advanced editor cannot initialize uses the plain **interactive** fallback, not transcript mode.

Interactive startup displays a short version banner and `:help` hint. The fresh prompt is `atta> `, including one space after `>`. The plain fallback uses `...> ` for continuation. The advanced editor may use its native multiline display rather than duplicating that continuation prompt.

Automatic expression results go to stdout and begin with `=> `. Diagnostics, prompts, and explicit command information go to stderr. Program stdout remains immediate and otherwise unchanged. Keep result boundaries legible with a small separator-newline helper when necessary; never capture an entire computation's output before displaying it, rewrite its bytes, or delay a program's prompt while it waits for input.

Transcript mode emits no unsolicited banner, prompts, terminal controls, completion, or persistent-history access. Explicit `:help`, `:names`, and other requested command responses may still emit plain text to stderr. Successful output is not required to be a machine serialization format.

### 3.2 Commands

There are six command names:

| Command | Behavior |
|---|---|
| `:help` | Show concise syntax examples, commands, and the automatic-printing limitation. |
| `:names` | List committed user definitions, sorted by name, without forcing them. |
| `:load "path.attl"` | Execute a validated standalone file and publish its definitions after success. |
| `:echo on` / `:echo off` | Enable or disable automatic expression-result rendering; acknowledge the new setting. |
| `:reset` | Discard the evaluation session and close its resources; retain editor/history preferences and the echo setting. |
| `:quit` | End the REPL using the session/transcript status rules below. |

A command occupies a fresh entry, with optional leading whitespace. Do not scan inside ordinary source for commands. Within strings, comments, an unfinished expression, or a running program's input, command-like text is ordinary content. Reject unknown commands and invalid arguments locally. Do not mix a command and source expressions in one entry.

Parse the load argument as exactly one quoted string using the restricted data reader, not a shell. Do not expand environment variables, globs, command substitutions, or `~` as shell syntax. Require valid arguments rather than guessing.

### 3.3 Source entries and reading

Use the existing S-expression syntax and literal expansion rules, with source locations. Do not implement a parenthesis counter or a second language grammar. Configure all parsing and completeness checks to disable `#reader`, `#lang`, compiled input, and reader-selected extensions. Use a fixed trusted readtable. Unsupported source datums remain unsupported. The prompt supplies the language; users do not type `#lang attalambda`. [S4, S10]

An **entry** is the complete source buffer accepted by the editor. It may contain multiple forms. In the plain fallback and transcript mode, collect a physical source line; if the reader reports incomplete input, append another line until the buffer is complete. A complete line containing several forms is one entry. A complete form followed by an incomplete form keeps the whole buffer pending. Whitespace and comment-only entries do nothing.

Read and expand the entire entry before running any of its expressions. A genuine reader or expansion error rejects the entry without executing any of it. During execution, demand expressions in source order and stop at the first native failure or interruption. Ordinary language `Error`/`Err` values are not native failures.

Consume the source entry's own terminating newline before a program read begins. Do not leave that newline for `(read-line UNIT)` to mistake for an empty answer. Conversely, do not consume the next answer line while looking for source. Validate/decode UTF-8 only for source bytes already collected, not arbitrary future program input.

In terminal editing, all text already accepted as part of the editor entry is source. Answers belong to the subsequent program-input phase. The REPL cannot infer an unmarked boundary within a single pasted source buffer; document that distinction rather than invent heuristics. Nevertheless, bytes not accepted as source must not be lost, duplicated, or silently retained in an editor-only buffer when the program needs them.

### 3.4 Definitions and redefinition

Definitions remain lazy and silent. A successful entry's new definitions become available to later entries. Retain actual bindings and lazy values, not source that is reexecuted later. [S3, S4]

Redefinition introduces a new binding for subsequent entries. Existing functions and delayed expressions retain their captured bindings. There are no mutable language-level globals. Preserve lexical shadowing, macro hygiene, currying, sugar, and existing dependency checks.

```text
atta> (def x = 1)
atta> (def plus-x n = (add x n))
atta> (def x = 10)
atta> (plus-x 1)
=> 2
atta> (add x 1)
=> 11
```

Unknown names in an earlier entry cannot acquire meaning from a future entry. Within one entry or loaded file, retain the existing permitted acyclic module dependencies and duplicate-definition rejection. Recursive `def` and forbidden mutual cycles remain errors; self recursion uses `rec` through the existing fixed-point encoding.

In particular, redefining `x` with `(def x = (add x 1))` does **not** mean mutation of the previous `x`: its new self-reference remains a recursive `def` and must be rejected. Use another binding name or a different expression when a previous value is needed explicitly.

Publish an entry's new binding set only after required expression evaluation and, when enabled, automatic rendering complete successfully. No partial new binding set becomes visible after a native failure. Previously committed names remain available, but their shared promises may already have been forced or interrupted. There is no effect rollback or promise rollback.

### 3.5 Printing and echo control

Automatic echo defaults to **on**. Use the existing pure `value-to-string` renderer and the existing observation-side String reader. Retain canonical spellings, including `OK`, `SOME`, `NONE`, `ERR`, and `UNIT`. Do not import the runtime codec into the REPL or implement another native datatype formatter. [S5]

```text
AttaLambda 0.8.0 — :help for help
atta> (add 1/2 1/3)
=> 5/6
atta> (def double x = (mult x 2))
atta> (double 21)
=> 42
atta> (read-line UNIT)
Kyle
=> OK(SOME("Kyle"))
```

Compute each expression once. Automatic rendering uses that same result; it must not repeat the expression to determine what to print. Returned effect results are visible when echo is on. Do not suppress them based on source spelling or guessed meaning.

With `:echo off`, demand expressions exactly as ordinary file execution does, so effects still happen, but **do not call the generic renderer, inspect type tags, traverse results, or synthesize automatic-result output**. Definitions remain lazy in both modes. Explicit `print`/`stdout` retain their existing behavior. An echo setting is shell state, not an AttaLambda variable or host operation.

The existing printer supports finite well-formed tagged values with supported contents, not arbitrary untagged functions. Probing an untagged function as an encoded object can apply its body, fail, or diverge; catching an error does not undo those effects. Echo-off is an explicit way to avoid that automatic probing, not a new total printer. Explicitly printing unsupported raw terms remains outside the existing contract. [S5]

Do not special-case literal lambdas as `<lambda>`, use `procedure?` to classify encoded values, add function tags, infer result types, or introduce timeouts that kill legitimate computation. Functions, including partial applications, can be retained and applied normally without rendering their raw values.

```text
atta> :echo off
Automatic echo: off
atta> (def f ignored = (stdout "called\n"))
atta> f
atta> (f UNIT)
called
```

In this example, merely entering `f` must not call its body. The final application must call it exactly once. Require this regression; do not test unspecified printing by demanding one particular incorrect outcome.

### 3.6 Runtime input and ownership

Keep `(read-line UNIT)` and its existing typed wrapper, Result/Option values, byte preservation, laziness, cached-result reuse, and native line-ending behavior unchanged. This includes the accepted lookahead after a bare CR. Program input has no parser, implicit prompt, numeric conversion, or history. [S3]

While collecting source, the editor/reader owns input. While evaluating or rendering, it does not read source, and program input uses the launching process's stdin. Never substitute the temporary source-buffer port as program stdin. Never run two active input readers. Restore normal terminal mode before running code and restore the editor afterward.

Use the library's supported handoff behavior first. Do not add a custom terminal driver, private `/dev/tty` channel, second input registry, or source-to-program buffer-replay protocol unless a narrowly reproduced library interaction actually requires a minimal adaptation. Do not change the public input operation to accommodate editing.

On redirected input, entries are consumed incrementally. After a source entry invokes program input, following stream bytes are answers until the operation returns. No whole-stream pre-read is allowed. At EOF, a running read returns its normal `OK(NONE)`; EOF at a fresh source prompt ends the shell. A terminal EOF event delivered to a program read does not itself tell the shell to quit.

### 3.7 Failures, cancellation, and process status

At a prompt, Ctrl+C clears the current entry. During reading, expansion, evaluation, rendering, or blocked program input, Ctrl+C cancels the current entry and restores a usable interactive prompt. Do not kill the entire interactive session for a recoverable entry failure. Keep ordinary language `Error` and Result `Err` values distinct from native exceptions.

Use source names such as `repl:1` with useful line/column information, and actual file locations for loads. Reuse the runner's sanitized diagnostic classification where possible. Do not print privileged module paths, arbitrary native stack traces, or speculative “type errors” that the language did not produce. Distinguish a rendering failure from an expansion failure.

| Situation | Required status |
|---|---|
| Existing file execution | Preserve its current codes and behavior. |
| Invalid CLI invocation | Existing misuse status `64`. |
| Interactive fresh EOF or `:quit` after recoverable errors | `0`. |
| Transcript fresh EOF or `:quit`, with no recovered failures | `0`. |
| Transcript fresh EOF or `:quit`, after a recovered source/command/load/native/rendering failure | `1`; remember a sticky failure flag. |
| Actual source-stream EOF with an unfinished entry | Invalid-source status `65`. |
| Fatal launcher/installation failure | Existing unexpected-failure status `70`. |
| Interrupt in transcript mode | Terminate with `130`; do not reinterpret unread answers as new source. |
| Valid explicit language `(exit n)` | Honor the existing language exit semantics and requested status, overriding the transcript flag. |

`:reset` does not clear the transcript failure flag. A language `Error` or `Err` value by itself does not set it. For a terminal's nonempty edit buffer, retain normal editor EOF/delete behavior; distinguish that keystroke from actual stream EOF. Ensure cleanup runs for valid explicit exit as well as ordinary termination.

### 3.8 Loading files

`:load` shares the existing `.attl` extension, exact language declaration, UTF-8, regular-file, symlink, and dotenv-path validation. Extract shared validation narrowly rather than copying it or reusing a helper that exits the entire process. Preserve file-launch behavior. [S6]

After validating the fixed declaration, read the body with the restricted reader and compile the whole file before execution. Evaluate as a standalone AttaLambda file, **not** against ambient session definitions. Run explicit effects in normal order; do not automatically echo bare file expressions. Publish its user definitions only on successful completion.

Loading the same path again creates a fresh instance and deliberately reexecutes the file. Existing closures retain older bindings. Do not change the working directory or alter relative program-file behavior. A failed load keeps the shell usable and publishes no new names; effects already performed are not undone.

### 3.9 History and editing

Use `expeditor-lib` for advanced terminal editing, with a small plain fallback sharing the same parser and session engine. Configure documented hooks explicitly; do not call convenience configuration that executes user Racket initialization files. Declare and bundle actual dependencies. [S11]

Provide multiline editing, ordinary cursor movement, history navigation, paste, indentation appropriate to S-expressions, and completion of public language names plus committed session names. Completion must not force values, consult privileged runner bindings, or use a hand-maintained duplicate of the public API. Derive names from the actual public exports and committed binding metadata. Colors are optional; do not build a theme system.

Keep at most 1,000 history entries and a fixed persistent-file byte limit, initially 1 MiB. This is a history-storage limit, not a source-size or program-input limit. Oversized individual entries may remain usable without being persisted. Store history under the platform's application preference/data location, not the repository. Use one bounded inert data representation; never execute it.

Persist only submitted source/commands, never program answers. `--no-history` forbids persistent-history reads and writes but allows in-memory navigation. Use owner-only permissions where supported and atomic replacement where available. Damaged/unwritable history must not block the REPL. Best-effort last-writer-wins behavior between simultaneous sessions is sufficient; no locking or synchronization service is required. Do not read rejected symlink or unsafe history targets merely to diagnose them.

## 4. Architecture and implementation boundaries

### 4.1 Checked modules, not replay

Use a fresh uniquely named in-memory module per submitted entry within a session namespace. Reuse the existing expander's definition recognition, dependency analysis, sugar, literal expansion, and `rec` lowering. Module instantiation and lexical imports are supplied by Racket. Do not create another evaluator. [S4, S12]

Introduce a private interaction path that exposes generated lazy result bindings and user-definition exports to the runner. Ordinary file modules retain their existing force-and-discard behavior. The private wrapper must not force expression results while merely assembling transport metadata.

Each entry imports the currently visible bindings through trusted hygienic module plumbing. Exclude superseded imports where new local bindings replace them. Keep a small shell-side map from visible names to their actual binding/export identity, rather than mutable cells referenced by language functions. Do not repeatedly reexport the entire history through each module or reconstruct previously evaluated source.

User text must expand in AttaLambda's language context, not inherit the runner's `racket/base` privileges. Generated imports/exports/result names cannot collide with source names. Native plumbing is classified module scaffolding, not part of the pure object-language expression terms.

### 4.2 Session isolation and resources

Create the session's namespace and runtime module instances once per session. Initialize shared runtime modules outside a cancellable entry's resource scope. Entries within one session share the same host state; reset creates a new host instance and registry. Attaching an already instantiated expander/runtime graph from another session must not accidentally share that state. [S7, S13]

Use a session custodian and, where needed for failure cleanup, subordinate entry custodians. Keep editor resources, original stdin/stdout/stderr, and the controlling loop outside cancellable entry ownership. Successful resources remain alive for later expressions; failed/interrupted work releases only resources it newly owns. Lazy allocations belong to the scope in which they are demanded. [S14]

Prefer a straightforward break-aware control flow. Use an owned worker only if a demonstrated cancellation requirement warrants it; do not build a scheduler or process pool. Treat parsing, expansion, evaluation, and rendering as cancellable work. Protect the very short binding-publication transition from partial interruption.

Interruption cannot restore a shared promise or reverse output, reads, file writes, or explicit closes. Previously committed unrelated resources must survive, but a promise forced during failed work can retain a failure or refer to a now-closed resource. Do not retry it by replaying effects. Reset and quit close all session-owned listeners/ports/workers and discard binding tables, namespace references, and cached diagnostics. [S15]

### 4.3 Modest memory discipline

Session namespaces can retain module declarations, instances, and their bindings. Do not promise bounded memory for an arbitrarily long session, and do not confuse history limits with evaluation-state lifetime. Measure representative repeated use and verify that reset makes the old session reclaimable. [S13]

Avoid unnecessary copies of submitted source, rendered strings, result values, and cumulative import tables. Do not add custom garbage collection, automatic replay/compaction, serialization, or arbitrary session eviction. A clear reset mechanism and measured ordinary behavior are sufficient unless a concrete regression proves otherwise.

### 4.4 Expected code shape

Keep responsibilities together, splitting only at demonstrated boundaries:

| Area | Intended responsibility |
|---|---|
| `runner/attalambda.rkt` | CLI dispatch and existing file-launch compatibility. |
| A small runner REPL module, with a session helper only if useful | Loop, commands, restricted module execution, echo, and lifetime. |
| A small editor adapter only if useful | Expeditor hooks, history, fallback, and terminal ownership. |
| `lang/expander.rkt` and a private helper if necessary | Shared checked expansion and private interaction exports. |
| A shared runner-source helper where needed | Existing validation and diagnostic reuse. |
| Existing readers | Observation of rendered Strings, not a new effect layer. |
| Tests, boundary tooling, packaging, and docs | Verification and distribution of these exact changes. |

Amend the boundary checker with a narrowly specified REPL-tooling class/capability set. Do not grant a broad exception to every file under `runner/`. Unknown source classifications must still fail. Keep production core/effects/codec constraints intact and reject public access to native evaluator/import/port capabilities. No program-facing host operation beyond the input feature already implemented is added. [S2, S9]

No new language grammar, mutation model, function representation, numerical primitive, standard-library expansion, debugger, plugin system, alternate backend, or public-platform launch belongs in this milestone.

## 5. Phased implementation plan

Every phase uses the closure procedure in §2.4. Checkboxes begin unchecked because this is a plan, not execution evidence. Where a test belongs to a later integration layer, first verify the responsible helper directly and then retain the full regression when that layer exists.

### Phase 0 — Establish a safe, reproducible starting point

**Purpose:** know the actual repository state and toolchain before changing it.

- [ ] **0.1 — Read the governing project context.** Read `AGENTS.md`, the active plan, specification index, input contract, and current release ledger. Record applicable restrictions and the intended milestone workflow; do not treat completed historical plans as current instructions. **Check:** the short baseline record identifies the correct language authority and the input feature to preserve.
- [ ] **0.2 — Resolve current source and release refs.** Inspect repository status, current branch, input branch, main, latest release/tag, and any relevant existing PR. Compare ancestry to the pinned baseline without inspecting dotenv contents. **Check:** record exact SHAs, relevant intervening changes, and whether work already exists; never create a duplicate milestone blindly.
- [ ] **0.3 — Establish the execution environment.** Confirm source-test tooling, Racket version, the project's supported build runtime, and available container/PTY facilities. Discover relevant available skills. Use isolated temporary package/user homes for probes; do not modify the owner's normal Racket configuration. **Check:** run the untouched full suite and both gates, separating observed failures from historical evidence.
- [ ] **0.4 — Establish the milestone workspace.** When implementation/Git actions are authorized, create or reuse one milestone branch containing the input work without rewriting it. Preserve unrelated working changes. **Check:** compare its base and initial diff to the recorded source; no release artifact, tag, or main-branch write has occurred.
- [ ] **0.5 — Install the active plan and scoped amendments.** Save this contract in a suitable docs location, link the active phase list from `PLAN.md`, and add only necessary canonical tooling-boundary amendments using the repository's existing preservation/hash procedure. **Check:** old specification content is preserved, index hashes and local links match, and the new active plan grants no accidental publication authority.

**Checkpoint 0 — Baseline/authority review.** Use repository-onboarding or planning review if available; otherwise compare the baseline and proposed scope directly. Close this phase only with a reproducible environment and no unexplained baseline failures affecting the milestone. A missing final packaging environment may be recorded for later provisioning, but must not be disguised as a passed consumer test.

### Phase 1 — Prove the two risky integrations early

**Purpose:** validate library behavior before committing to substantial UI or session plumbing. Keep probes tiny and isolated; retain useful regressions, not a second implementation.

- [ ] **1.1 — Open and close the real editor.** In the supported Racket build runtime, initialize Expeditor with explicit safe hooks and `atta>`; accept one entry and close it. Exercise initialization failure through a controlled test seam. **Check:** terminal state is restored and the editor does not load user initialization files.
- [ ] **1.2 — Prove editor-to-program input handoff.** Extend the probe with an entry handler that invokes the existing AttaLambda input path through a tiny fixture, then returns to editing. Do not build a general evaluator yet. **Check:** one answer reaches the program exactly once, is not added as source history, and the next expression can be edited.
- [ ] **1.3 — Exercise type-ahead and cancellation in the probe.** Drive the probe through a PTY using ordinary typing, a multiline source paste, an answer sent after the accepted entry, and interruption during a blocked read. **Check:** distinguish already accepted source from pending program bytes; prove no dropped/duplicated bytes and no stuck terminal mode. Use event-based readiness and bounded cleanup, not sleeps as proof.
- [ ] **1.4 — Prove module-instance retention.** Build the smallest trusted test harness with two fresh Racket modules using existing lazy AttaLambda values. Retrieve a lazy binding without forcing it and reference it from another module. **Check:** a saved effect runs once on demand, not on export discovery or import, and later use shares the same answer.
- [ ] **1.5 — Prove lexical rebinding and reset isolation.** Extend only that harness with an old closure, a replacement binding, and a fresh session namespace. **Check:** the snapshot example produces `2` and `11`, and a new session does not share the previous stateful host instance. This is a plumbing proof, not permission to bypass the production expander.
- [ ] **1.6 — Record the proven implementation choices.** Select documented editor hooks, source/program-port handling, and module-instance strategy from the evidence. Identify any narrow compatibility adaptation actually needed. **Check:** there is one intended engine and one intended editor adapter; no custom interpreter, terminal driver, or language change has slipped in.

**Checkpoint 1 — Integration feasibility review.** Use a focused architecture review and terminal-integration review. A cold reviewer should challenge stdin ownership, accidental forcing, captured bindings, and runtime sharing. Do not proceed with a handoff known to lose bytes or a reset known to share old host state. Resolve the minimal mechanism here rather than hiding the problem until packaging.

### Phase 2 — Implement one restricted source reader

**Purpose:** obtain well-defined entries without changing the language grammar.

- [ ] **2.1 — Parse a completed buffer with locations.** Add one helper that reads the entire supplied source buffer under the fixed safe reader configuration and returns located forms or a structured diagnostic. **Check:** exact Rats, strings, ASCII character literals, nested forms, and multiple forms parse without executing code; unsupported datums still fail at their existing stage.
- [ ] **2.2 — Classify completeness and errors.** Distinguish empty/comment-only input, incomplete input, complete input, and genuine read failure using the native reader's behavior. **Check:** comments, escaped quotes, character literals containing delimiters, incomplete strings/block comments, and mismatched delimiters are classified correctly. Do not count parentheses manually.
- [ ] **2.3 — Assemble plain source entries incrementally.** Collect source lines only until the current buffer is complete, preserving positions and consuming its own terminator. Decode only collected source bytes. **Check:** a following answer line remains available on the same input port, including when the pipe writer stays open.
- [ ] **2.4 — Parse commands without evaluation.** Add fresh-entry recognition and exact argument validation for the six commands, reusing restricted string parsing for `:load`. **Check:** command-like text inside comments, strings, incomplete source, and program answers is not intercepted; trailing extra command arguments are rejected.
- [ ] **2.5 — Connect editor readiness to this reader.** Use the same safe parser/completeness logic for Expeditor acceptance and the fallback. Prevent the editor's default reader or error path from bypassing extension restrictions or sanitized diagnostics. **Check:** a malicious reader directive is rejected during completeness checking as well as submission, and no fixture reader module executes.

**Checkpoint 2 — Reader correctness and extension-boundary review.** Run adversarial reader cases and affected existing reader/runner tests. Inspect all places that parse source, command arguments, and later history data; each must use an explicit restricted configuration. Confirm that terminal input remains in the host, while source input remains tooling.

### Phase 3 — Add the smallest private interaction path

**Purpose:** evaluate a checked entry and retrieve results without duplicating language semantics.

- [ ] **3.1 — Factor shared definition analysis only as needed.** Make the existing definition recognition/dependency checks reusable by the private interactive wrapper, preserving their lexical context. **Check:** existing file syntax, recursive-definition rejection, sugar, and shadowing suites remain unchanged in behavior.
- [ ] **3.2 — Expose lazy user bindings privately.** Add generated exports or equivalent trusted access for definitions from an interaction module. Keep the public language export surface unchanged. **Check:** discovering exports and retrieving a definition do not demand an input/output effect hidden in its body.
- [ ] **3.3 — Expose ordered expression results privately.** Generate result bindings that preserve the original lazy expressions and their source order. Keep native transport metadata outside object-language terms. **Check:** module instantiation alone does not prematurely force these results, while ordinary file modules still execute their normal force-and-discard path.
- [ ] **3.4 — Evaluate one checked module in a session.** Add the minimal runner-side declaration/instantiation/result-demand path. Use fresh module names and the safe AttaLambda source context. **Check:** arithmetic produces the expected encoded value, expressions are demanded in order, and an expansion error anywhere in the entry prevents all its effects.
- [ ] **3.5 — Render supported results through the existing renderer.** Connect the pure `value-to-string` path and observation-side String reader, retaining the already computed result. **Check:** exact fractions, nested Lists/Options/Results, Maps, Errors, Strings, and Unit use canonical rendering, with no second evaluation and no codec import.
- [ ] **3.6 — Classify the new scaffolding precisely.** Extend boundary expectations for the new files/imports/exports and their narrowly required capabilities. **Check:** unknown source locations, unapproved production imports, and user attempts to access native `eval`, `require`, or port operations still fail closed.
- [ ] **3.7 — Check real generated terms for purity.** Feed actual interactive expansions through the existing purity-checking approach, isolating native module scaffolding as existing frontend tests do. **Check:** representative literal, sugar, `def`, and `rec` bodies contain only the allowed expanded computation; a deliberately forbidden computation fixture is rejected.

**Checkpoint 3 — Language-equivalence and purity review.** Use a focused code/architecture review. Compare file and interactive expansion paths and their tests. Reject copied recursion logic, privileged scope accidentally attached to user source, eager transport conversions, and public export leakage. Close only after the full suite and both structural gates pass.

### Phase 4 — Retain definitions with precise session semantics

**Purpose:** grow from one entry to a persistent session without replay or mutable globals.

- [ ] **4.1 — Retain and import committed binding identities.** Maintain the visible-name map and import references to existing module instances into the next entry. **Check:** definitions, functions, and retained partial applications remain usable across several entries without rerunning earlier expressions.
- [ ] **4.2 — Implement snapshot redefinition.** New entries replace visible name mappings, not old language bindings. Resolve generated imports so local replacements do not conflict. **Check:** the `x`/`plus-x` example passes, old delayed expressions retain their environment, and duplicate definitions within one entry retain current rejection behavior.
- [ ] **4.3 — Preserve name and recursion rules across entries.** Test unknown earlier names, permitted same-entry forward dependencies, recursive `def`, mutual cycles, and `rec`. **Check:** `(def x = (add x 1))` is rejected even with an earlier `x`; hidden dependencies in sugar do not bypass the checks.
- [ ] **4.4 — Preserve shadowing and hygiene.** Exercise shadowed public function/syntax names, including declaration-name shadowing where the current language permits it, across multiple entries. **Check:** recognition follows bindings rather than raw symbol spelling, and user names cannot capture generated result/import/export identifiers.
- [ ] **4.5 — Commit new names as one small transition.** Prepare an entry's new map separately and publish it only after required execution/rendering succeeds; protect only the brief commit operation against partial interruption. **Check:** read/expansion/native/render failures expose none of the entry's new names, preserve previous names, and do not claim to roll back completed effects.
- [ ] **4.6 — Expose non-evaluating name metadata.** Provide the sorted committed name set for `:names` and completion, excluding private exports. **Check:** listing names never forces a saved read, lazy error, or function body, and failed-entry names never appear.

**Checkpoint 4 — State and laziness review.** Use a code review focused on instance reuse and binding publication. The strongest tests should deliberately include observable effects and failing entries, not just arithmetic. Verify the implementation neither concatenates history nor changes closures to read mutable top-level cells.

### Phase 5 — Integrate input, cancellation, and session lifetime

**Purpose:** make interactive execution recoverable without changing existing input semantics.

- [ ] **5.1 — Wire original process ports and session runtime ownership.** Initialize the shared runtime under session lifetime and parameterize actual entry execution with the correct process ports. **Check:** temporary parsing ports never become program stdin, and one session has one consistent host instance.
- [ ] **5.2 — Integrate one live program read.** Connect the source engine to `(read-line UNIT)` through open pipes, then through the early editor adapter. **Check:** source terminators are consumed correctly, a partial answer blocks, one answer is returned exactly once, and the next source entry is readable.
- [ ] **5.3 — Prove lazy input reuse.** Retain a definition whose body reads input, inspect its name, demand it twice, and invoke a function containing a fresh read twice. **Check:** name inspection does not read; the retained answer is reused; fresh calls consume successive answers; an unselected branch performs no read. Reuse existing typing/byte/EOF/newline tests rather than rebuilding that operation.
- [ ] **5.4 — Add break-aware recovery.** Handle prompt cancellation and cancellation during expansion, infinite computation, rendering, and blocked input. **Check:** each returns to a usable interactive prompt and an unrelated earlier definition still works. Verify diagnostic context and terminal restoration; do not impose a universal computation timeout.
- [ ] **5.5 — Scope resources created by an entry.** Add the narrow custodian/worker ownership required by the proven design. **Check:** a failed entry's new listener closes, a previously committed unrelated listener survives, original standard ports remain open, and no cancelled worker continues reading or writing.
- [ ] **5.6 — Implement reset as genuine session replacement.** Shut down the old session and discard its namespace, visible-name map, runtime instance, and stored diagnostics. Retain shell preferences. **Check:** old names disappear, a listening port can be rebound, the new host registry is fresh, and input/history/echo ownership is still correct.
- [ ] **5.7 — Close cleanly on all exit paths.** Route ordinary quit/EOF, fatal failure, and valid language exit through the necessary cleanup, preserving language exit statuses. **Check:** terminal mode is restored and session resources close after normal success, `(exit 0)`, `(exit 1)`, and an injected native failure. Test processes must be isolated from the test runner.
- [ ] **5.8 — Measure repeated-use and reset behavior.** Run a modest reproducible workload, initially about 200 small entries mixing definitions, expressions, and rejected entries, across several reset cycles. **Check:** no worker/port accumulation, old session objects become reclaimable after references are dropped, and memory/latency observations show no unexplained severe growth. Record measurements without brittle universal timing/RSS thresholds; fix concrete retention bugs, not theoretical infinite-session limits.

**Checkpoint 5 — Effects, interruption, and lifetime review.** Use systematic debugging for any failures, followed by a cold review of the port/custodian/namespace paths. Tests must include failure-path cleanup and actual PTY behavior. Explicitly check forced promises are not replayed after interruption and that cleanup does not accidentally close the shared session runtime initialized for earlier entries.

### Phase 6 — Load files and reuse diagnostics

**Purpose:** integrate standalone files without weakening the existing launcher.

- [ ] **6.1 — Extract only genuinely shared validation.** Refactor source validation so the file runner can retain its terminating behavior while the REPL receives structured failures. **Check:** existing file-mode path, encoding, declaration, status, and diagnostic tests still pass exactly where their contract is fixed.
- [ ] **6.2 — Load a fresh standalone instance.** Read the validated file body with the fixed reader, preserve file locations, and use the private export path without ambient REPL imports. **Check:** file effects execute once in normal order, bare expressions are not auto-echoed, and undefined file names cannot be supplied implicitly by the session.
- [ ] **6.3 — Publish loaded definitions on success.** Integrate the loaded module's definitions through the same snapshot/publication mechanism. **Check:** names are available afterward, failed files publish none, and loading the same path again deliberately reruns it while old closures retain old bindings.
- [ ] **6.4 — Test file and working-directory boundaries.** Exercise quoted paths with spaces, relative paths, invalid extensions/declarations/UTF-8, rejected symlinks, and dotenv-path rejection without reading dotenv contents. **Check:** working directory and program-relative I/O semantics remain unchanged; rejected loads leave the session usable.
- [ ] **6.5 — Consolidate sanitized error presentation.** Share small classification/location helpers where beneficial; keep phase-specific diagnostics and the existing file launcher behavior. **Check:** malformed source, unknown names, recursion rejection, missing file, rendering failure, and unexpected native failure produce useful bounded diagnostics without leaking arbitrary native internals.

**Checkpoint 6 — Compatibility and boundary review.** Use a focused regression/code review of validation and loading. Prefer proving the shared helper preserves existing behavior over broad runner cleanup. Re-run the existing file runner/integration suites plus the new load tests and both gates.

### Phase 7 — Assemble the command loop and echo/status policy

**Purpose:** expose the working engine through the final CLI before full editing polish.

- [ ] **7.1 — Add CLI dispatch without altering file mode.** Implement only the supported command forms and terminal/transcript selection. **Check:** both flag orders work, invalid combinations return `64`, default nonterminal invocation does not consume source, and existing `--help`, `--version`, and file mode retain their contracts except the documented new help text.
- [ ] **7.2 — Connect the plain loop and commands.** Use the shared reader/session engine and implement `:help`, `:names`, `:load`, `:reset`, and `:quit`. **Check:** a full plain session exercises each command, command errors recover, and reset retains shell preferences while replacing evaluation state.
- [ ] **7.3 — Add explicit echo control.** Implement `:echo on/off` as one shell preference, default on. With echo off, use normal file-style demand and skip all renderer/type-probing paths. **Check:** supported values print canonically when on; the raw-function example in §3.5 does not invoke `f` until explicit application; explicit output remains immediate in either mode.
- [ ] **7.4 — Keep stdout and UI separate.** Add the small banner/prompt/result/diagnostic output helpers, including separator behavior after a program writes without a newline. **Check:** `atta>` is used consistently, stdout redirection contains no UI, prompts reach the terminal before blocking reads, and echo-off emits no synthetic result text.
- [ ] **7.5 — Implement transcript status tracking.** Add the sticky recovered-failure flag and explicit EOF/interruption/exit precedence from §3.7. **Check:** a bad entry followed by a good one still ends with status `1`; reset does not clear the flag; language Error/Err values alone do not set it; unfinished EOF returns `65`; explicit language exit retains its own status.
- [ ] **7.6 — Test the complete incremental transcript path.** Feed source, program answers, blank answers, multiple source forms, a recoverable error, and fresh source through an open pipe without closing the writer prematurely. **Check:** exact answer/source boundaries and expected results/statuses hold with no prompts, escapes, or history access.

**Checkpoint 7 — End-to-end plain REPL review.** Use a behavioral code review against the fixed contract. At this point the feature works without advanced editing. Inspect especially echo-off for accidental tag probing and transcript handling for read-ahead or hidden process-status failures.

### Phase 8 — Complete terminal editing and bounded history

**Purpose:** polish one working engine, not add another execution path.

- [ ] **8.1 — Integrate the proven editor adapter.** Promote the early editor probe into the real loop using the shared safe reader. Declare the actual direct package dependencies and corresponding narrow boundary changes. **Check:** advanced and fallback modes produce equivalent entry semantics and the library still does not execute Racket initialization files.
- [ ] **8.2 — Configure multiline editing and indentation.** Select appropriate documented lexer/indentation/parenthesis hooks without importing the entire Racket REPL. **Check:** nested expressions, comments, escaped strings, cursor movement, and multi-form paste work; no second parser or custom terminal escape engine is introduced.
- [ ] **8.3 — Add non-evaluating completion.** Derive visible language names from actual public exports and combine them with committed user names through a supported editor mechanism. **Check:** newly defined/redefined/loaded names appear, reset removes user names, failed names never appear, and lazy definitions are not forced. Filter private scaffolding, not legitimate public language exports.
- [ ] **8.4 — Implement bounded inert history reading.** Choose one simple data format and safe application-data path; enforce the entry and byte bounds before unbounded parsing/allocation. **Check:** valid multiline entries round-trip, oversized/corrupt/unsafe files are ignored safely, reader directives cannot execute, and `--no-history` performs no persistent read.
- [ ] **8.5 — Implement best-effort history persistence.** Save submitted source/commands with appropriate permissions and atomic replacement where supported. Skip oversized entries rather than rejecting their execution. **Check:** program answers are absent, an unwritable target does not break the session, a failed save does not corrupt an existing valid file, and `--no-history` performs no persistent write.
- [ ] **8.6 — Finalize editor failure and fallback paths.** Handle unrecognized terminals, controlled initialization failure, EOF, interrupt, and process exit without exposing the editor's internal errors as language values. **Check:** no terminal-mode residue, no duplicate input reader, and the plain fallback retains multiline source support; advanced features are required on the supported normal Linux terminal, not silently waived.
- [ ] **8.7 — Run full PTY acceptance.** Drive the actual executable through editing, history recall, completion, multiline paste, program input, Ctrl+C, Ctrl+D, and explicit exit. **Check:** terminal state is restored on every termination path and the source/program handoff still passes after history/completion integration. Exercise source entered before and after blocked reads.

**Checkpoint 8 — Terminal usability and history review.** Use terminal-integration review plus a narrow privacy/boundary review of history and startup behavior. The complete program, not just the probe, must pass real PTY tests. No general penetration-testing framework or new account/service integration is needed.

### Phase 9 — Reconcile documentation and distribution inputs

**Purpose:** make the implemented feature accurately documented and packageable.

- [ ] **9.1 — Run a contract-to-test audit.** Map every acceptance row in §6 to an existing test, new test, or explicit artifact check. **Check:** critical behaviors have executable evidence; observational memory measurements and unperformed platform checks are labeled honestly, not converted into claims of proof.
- [ ] **9.2 — Update user documentation and executable examples.** Update README/API/help/release notes for runtime input, `atta>`, commands, snapshot redefinition, lazy effects, echo-off, load semantics, and transcript status behavior. **Check:** execute the documented examples, confirm uppercase canonical rendering, and remove obsolete references to `att>` or special literal-lambda printing.
- [ ] **9.3 — Reconcile architecture and specification records.** Document the narrow REPL-tooling exception, shared expansion path, unchanged host-input contract, source inventory, and dependency direction. Update canonical amendment/index evidence as required. **Check:** docs describe observed code separately from remaining release work and contain no blanket purity exception for arbitrary runner modules.
- [ ] **9.4 — Prepare candidate version metadata.** After confirming `0.8.0` is still unused and appropriate, update `VERSION`, package projection `0.8`, and every exact version acceptance table/test that actually depends on them. **Check:** Linux and existing internal portability scripts agree; do not broaden version validators generically just to avoid listing the new supported state. If the version was taken by intervening work, do not reuse its tag or overwrite artifacts.
- [ ] **9.5 — Include the editor and new runner modules in distribution.** Adjust only the dependency/bundling inputs needed by the existing build machinery, including any modules reached through dynamic lookup. **Check:** declared package closure and bundled modules cover the real code path, with no dependence on a developer package home or unbundled source checkout.
- [ ] **9.6 — Preserve notices and packaging integrity.** Add any required notices for newly bundled dependencies through the existing notice/hash process without deleting prior notices or weakening checks. **Check:** version, notices, archive layout, and source-selection validations all remain explicit and reproducible.
- [ ] **9.7 — Extend the existing Linux consumer tests.** Add REPL and runtime-input cases to the current consumer workflow, using external test-only PTY tooling when needed. **Check:** the consumer still proves there is no system Racket/raco and covers default/explicit REPL, fallback/transcript, editing, input, cancellation, load/reset, and the old examples. Preserve existing internal portability evidence without claiming new public platforms.

**Checkpoint 9 — Documentation and packaging review.** Use release-readiness review. Check executable docs and static packaging coverage before the final clean build. The full suite and existing CI configuration must include the new tests or invoke them explicitly; a successful old test count alone is not evidence of the new feature.

### Phase 10 — Review and freeze the candidate source

**Purpose:** close implementation review and establish the clean source revision used by the artifact phase.

- [ ] **10.1 — Perform a cold implementation review.** Review the current complete milestone diff, this contract, and tests using a separate read-only reviewer when available. Focus on purity, effects/laziness, imports/shadowing, cancellation, stdin, loading, history, and scope. **Check:** each finding has evidence and a severity/rationale; do not manufacture changes when no defect is found.
- [ ] **10.2 — Resolve confirmed findings in small units.** For each actual finding, add a regression or reproducible check, patch only the responsible code, and rerun focused checks. Split independent fixes into separate numbered substeps. **Check:** no unresolved correctness or security-boundary blocker remains; rejected suggestions have an evidence-based explanation.
- [ ] **10.3 — Run final source verification.** Run the entire suite, expanded purity, boundary inventory, and PTY cases on the final candidate inputs. Review dotenv-safe diff/whitespace checks and generated-file exclusions. **Check:** record the runtime, commands, logs, actual results, and any outstanding artifact-only checks.

**Checkpoint 10 — Source freeze.** Use a final scope and code review; close the verified phase with its commit/push when authorized. Record the resulting exact candidate commit without claiming the archive is already verified. Do not amend executable inputs during artifact testing without returning to the responsible implementation step and refreshing affected evidence.

### Phase 11 — Build and verify the exact release candidate

**Purpose:** test the artifact from the frozen source, then record artifact-only evidence separately.

- [ ] **11.1 — Build from the clean candidate revision.** Use the repository's approved Racket CS build runtime and existing Linux build script, with a fresh output directory outside the checkout. Do not use `--allow-dirty` for the candidate artifact. **Check:** record the clean source revision, product/package versions, build command, artifact names, and checksums.
- [ ] **11.2 — Consume the exact artifact without development dependencies.** Run the existing isolated Linux consumer on the output directory, including real terminal tests and relocation to a path with spaces. **Check:** the extracted executable supports both new feature themes without external Racket, source checkout, personal packages, or user initialization files. Artifact failures require a fix, refreshed source verification as affected, and a new clean build.
- [ ] **11.3 — Reconcile delivery state and handoff.** Verify that the reviewed source, tested source, clean build revision, and recorded artifact actually correspond. Open or update the milestone PR when authorized, verify current-head checks/review, and record any pending external checks without calling them passed. **Check:** provide the concise handoff in §7; stop at the candidate unless explicit merge/publication authority is present.

**Checkpoint 11 — Final release-candidate gate.** Use release verification and a final scope review. Close this phase with a documentation-only evidence commit when authorized; preserve the exact earlier build SHA rather than relabeling the archive as built from the later record commit. No executable-input change may rely solely on stale evidence. If only publication-record documentation changes afterward, state why prior artifact evidence still applies. Leave no owned test workers, listeners, containers, or temporary source modifications running or staged accidentally.

## 6. Acceptance coverage and test rules

This matrix is a coverage index, not a demand for one test file per row. Group related cases into a small set of suites fitting the repository. Tests named during implementation must be discoverable by `run-all-tests.sh`, or invoked explicitly by a tested existing integration entry point.

| ID | Required observable behavior | Primary steps |
|---|---|---|
| A01 | Default/explicit REPL, terminal fallback, flag validation, preserved file/help/version behavior. | 7.1, 7.6, 8.6 |
| A02 | Multiline and multi-form entries; correct comments/strings/characters; whole-entry read/expand rejection before effects. | 2.1–2.5, 3.4 |
| A03 | Reader directives/compiled input cannot execute at completeness, source, load, or history parsing. | 2.5, 6.2, 8.4 |
| A04 | Retained definitions/partial applications; snapshot rebinding; no history replay or eager definition demand. | 3.2–3.3, 4.1–4.2 |
| A05 | Existing `def`/`rec`, dependency-cycle, shadowing, duplicate-name, and hygiene rules remain intact. | 3.1, 4.3–4.4 |
| A06 | Actual generated language terms pass purity; unapproved native capabilities/imports and unknown source classes fail. | 3.6–3.7, 9.3 |
| A07 | Canonical rendering uses one computed result; echo-off never probes a raw function; explicit effects still run once. | 3.5, 7.3–7.4 |
| A08 | Saved reads are shared; fresh reads are fresh; blank line/EOF/bytes/newlines/type checks retain existing behavior. | 5.2–5.3 plus existing stdin suites |
| A09 | Source newline/answer boundary is correct; live pipes and PTYs show no lost/duplicated bytes or concurrent readers. | 1.2–1.3, 5.2, 7.6, 8.7 |
| A10 | Ctrl+C recovers during source collection, expansion, evaluation, rendering, and blocked input; unrelated names survive. | 5.4, 8.7 |
| A11 | Failed entries publish no names; language Error/Err values remain values; no effect/promise rollback is falsely promised. | 4.5, 5.4–5.5, 7.5 |
| A12 | Entry cleanup preserves old unrelated resources; reset/quit release session resources and isolate host registries. | 1.5, 5.5–5.8 |
| A13 | Loads validate safely, run standalone, preserve paths, rerun deliberately, and publish only on success. | 6.1–6.4 |
| A14 | Transcript errors remain visible in final status; incomplete EOF, signals, and explicit exit follow precedence. | 5.7, 7.5–7.6 |
| A15 | Completion/names/history do not force values; history is bounded, inert, private, optional, and excludes answers. | 4.6, 8.3–8.5 |
| A16 | The normal Linux editor is genuinely usable and restores terminal state on success, cancellation, EOF, and exit. | 1.1–1.3, 8.1–8.2, 8.6–8.7 |
| A17 | Repeated ordinary use has measured behavior; reset makes old session state reclaimable without replay/compaction. | 5.8 |
| A18 | A clean, relocated Linux artifact works without system Racket, personal packages, or the source checkout. | 9.5–9.7, 11.1–11.2 |

### 6.1 Minimum end-to-end transcripts

Keep executable fixtures for the following. Terminal output includes prompts; transcript output does not. Prefer exact expected results for defined values, and assert effects/ordering separately from UI formatting.

**Arithmetic, functions, and exact values:** use the examples in §3.4–3.5, plus one retained partial application and one `rec` example already demonstrated by the existing language suite.

**Saved input, without replay:**

```text
(def answer = (read-line UNIT))
:names
answer
Kyle
answer
:quit
```

The name listing must not consume input. Both result expressions must show `OK(SOME("Kyle"))`; only the first demand reads the answer. The final status is `0`. Run an additional fresh-read fixture with two distinct answers.

**Recovery and sticky transcript failure:**

```text
(def keep = 7)
missing_name
keep
:reset
(add 1 2)
:quit
```

There must be an unknown-name diagnostic, results `7` and `3`, and final status `1`. Use a separate test to show `keep` is unknown after reset. Another fixture returning a defined language `Error`/`Err` value, without native failure, must exit `0`.

**Raw functions with automatic echo disabled:** execute the example in §3.5. Assert no output from defining or merely entering `f`, and exactly one `called` line from `(f UNIT)`. Do not invoke unsupported auto-rendering and then mistake an arbitrary result for a required contract.

**File loading:** load a small standalone fixture defining a function and emitting a short marker. Call the function, reload the file, and verify one marker per load with no automatic echo for the file's bare expressions. Add a failing-file fixture that would print if executed before a later expansion error; that marker must be absent.

### 6.2 Deterministic tests and resource cleanup

Every subprocess, pipe, thread, listener, PTY, and temporary directory owned by a test must have bounded teardown in success and failure paths. Use ephemeral loopback ports and temporary directories only. Close pipe/PTY endpoints explicitly when their API does not promise custodian cleanup. Do not assume all port kinds are custodian-managed. [S14]

Observe readiness through events, expected prompt bytes, or instrumented read consumption before asserting that an operation is blocked. Avoid tests that pass only because a short sleep happened to expire. Test-harness deadlines protect the suite; they are not production computation limits.

Have at least one permanent regression that intentionally takes the harness's failure/cancellation path and proves that its reader process and descriptors are gone afterward. Terminal tests need actual PTYs; pipe-only tests do not establish terminal behavior. Do not silently skip the Linux terminal acceptance gate when it is required for the released feature.

For boundary rejection and dangerous-reader tests, use synthetic inert fixtures or instrumentation, never real secrets, external targets, or the owner's configuration files. A controlled negative test should prove the checker can reject the class of violation, rather than merely inspect that an allowlist contains expected words.

For memory observations, drop test-held references before collection checks. Prefer weak-reference/resource-lifetime evidence for reset correctness and recorded measurements for performance; do not assert an exact RSS value across machines. Severe unexplained growth is a blocker to investigate, not permission to add a new memory subsystem by default.

## 7. Candidate handoff and conditional release

### 7.1 Required candidate handoff

Provide a brief summary plus an evidence table containing:

| Item | Required content |
|---|---|
| Source | Milestone branch, reviewed candidate SHA, current head, and relevant PR URL/status when authorized. |
| Implementation | Completed phase/step IDs; any deviations with evidence; no unchecked behavior hidden behind “done.” |
| Verification | Exact full-suite, purity, boundary, and PTY results; runtime; logs; review mode and disposition. |
| Artifact | Exact build SHA, build environment, archive/manifest names, hashes, and isolated consumer result. |
| Known limits | Raw-term printing domain, non-rollback behavior, session retention/reset policy, and supported public platform. |
| Delivery | Whether merge/publication is authorized; what is still pending; whether checks are running, failed, or complete. |
| Cleanup | Repository status and confirmation that owned test processes/resources have been closed. |

A source-only result is not a verified binary candidate. A candidate is not a release. A review request is not a completed review. Record a genuine environment/permission blocker with the failing operation and the smallest necessary next action; do not fabricate evidence or broaden scope to work around it.

The current build and consumer accept an output directory. After provisioning the approved runtime and confirming the script contracts, the clean-candidate path is: [S16]

```sh
build_dir="$(mktemp -d /tmp/attalambda-080-build.XXXXXX)"
tooling/build-linux-distribution.sh "$build_dir"
tooling/test-linux-distribution.sh "$build_dir"
```

Use the actual artifact names generated by the script and the repository's established checksumming/ledger procedure. Do not infer that a file is verified merely because the build command returned successfully.

### 7.2 Phase 12 — Deliver only when explicitly authorized

This phase is conditional. Execute it autonomously only when the current assignment explicitly authorizes the required GitHub writes, merge, and publication. Otherwise the successful endpoint is Checkpoint 11. Preserve older releases, tags, and assets.

- [ ] **12.1 — Reconfirm authority and current-head readiness.** Verify the intended release number, PR head/base, required checks, and actionable review disposition at the exact current head. **Check:** no stale-head CI or unreviewed executable change is being presented as approved.
- [ ] **12.2 — Merge through AttaLambda's established workflow.** Merge the reviewed milestone to `main` only with explicit authority, without triggering an unrelated release mechanism. **Check:** record the resulting merge SHA/tree and verify the required merged-head checks.
- [ ] **12.3 — Build and consume clean merged source.** Build the exact clean revision intended for the tag using the approved runtime and rerun the isolated consumer. **Check:** archive contents, source SHA, version, notices, and checksums correspond to that revision, not merely to a pre-merge candidate.
- [ ] **12.4 — Stage and verify release assets.** Create the established release tag/draft and upload the exact verified archive and checksum manifest using the repository's existing process. **Check:** downloads of draft assets match the locally verified bytes; do not overwrite an existing version or guess asset identities.
- [ ] **12.5 — Publish and verify public downloads.** Publish only after the preceding gate passes, then obtain fresh public downloads. **Check:** both hashes match, the released archive passes the established consumer verification, the intended release metadata is correct, and previous releases remain intact.
- [ ] **12.6 — Record publication evidence.** Update only the appropriate release ledger/handoff records and commit/push those records according to project practice. **Check:** state exactly which SHA was built/tagged and distinguish any later documentation-only commit. Close all owned temporary resources and report the actual published state.

**Checkpoint 12 — Published-release verification.** Use release verification, not merely a successful upload response. On failure, report the actual state and correct only the specific delivery defect under existing authority; never delete older releases or silently substitute different artifact bytes.

## 8. Source references and provenance

The implementation decisions and acceptance rules above are the new contract. The references below support the inspected baseline and library mechanisms, not a claim that the proposed REPL already exists. Project source links are pinned to the inspected input revision unless otherwise stated. Recheck relevant APIs against the runtime actually used for implementation and release.

**S1 — Inspected repository state.** [Input branch](https://github.com/kserrec/attalambda/tree/62d0f0cf7e042bd6478024697c460c9fc88b50f7), [input commit](https://github.com/kserrec/attalambda/commit/62d0f0cf7e042bd6478024697c460c9fc88b50f7), and [published 0.7.0 baseline](https://github.com/kserrec/attalambda/releases/tag/v0.7.0).

**S2 — Governing repository rules.** [AGENTS.md](https://github.com/kserrec/attalambda/blob/62d0f0cf7e042bd6478024697c460c9fc88b50f7/AGENTS.md), [active/history plan](https://github.com/kserrec/attalambda/blob/62d0f0cf7e042bd6478024697c460c9fc88b50f7/PLAN.md), and [canonical specification index](https://github.com/kserrec/attalambda/blob/62d0f0cf7e042bd6478024697c460c9fc88b50f7/docs/specifications/README.md).

**S3 — Existing terminal input.** [Input contract](https://github.com/kserrec/attalambda/blob/62d0f0cf7e042bd6478024697c460c9fc88b50f7/docs/terminal-input-spec.md), [pure input wrapper](https://github.com/kserrec/attalambda/blob/62d0f0cf7e042bd6478024697c460c9fc88b50f7/effects/stdin.rkt), and the recorded verification in S2.

**S4 — Checked language frontend.** [Expander](https://github.com/kserrec/attalambda/blob/62d0f0cf7e042bd6478024697c460c9fc88b50f7/lang/expander.rkt) and [reader](https://github.com/kserrec/attalambda/blob/62d0f0cf7e042bd6478024697c460c9fc88b50f7/lang/reader.rkt).

**S5 — Pure printing and raw-term limitation.** [Public rendering functions](https://github.com/kserrec/attalambda/blob/62d0f0cf7e042bd6478024697c460c9fc88b50f7/core/to-string.rkt), [generic renderer](https://github.com/kserrec/attalambda/blob/62d0f0cf7e042bd6478024697c460c9fc88b50f7/core/render-value.rkt), [rendered spellings](https://github.com/kserrec/attalambda/blob/62d0f0cf7e042bd6478024697c460c9fc88b50f7/core/render-text.rkt), [object selectors](https://github.com/kserrec/attalambda/blob/62d0f0cf7e042bd6478024697c460c9fc88b50f7/core/objects.rkt), and [pair selectors](https://github.com/kserrec/attalambda/blob/62d0f0cf7e042bd6478024697c460c9fc88b50f7/core/pair.rkt).

**S6 — Existing launcher.** [File validation, execution, diagnostics, and CLI](https://github.com/kserrec/attalambda/blob/62d0f0cf7e042bd6478024697c460c9fc88b50f7/runner/attalambda.rkt).

**S7 — Stateful host boundary.** [Host input, effects, and handle registry](https://github.com/kserrec/attalambda/blob/62d0f0cf7e042bd6478024697c460c9fc88b50f7/runtime/host.rkt).

**S8 — Test entry point.** [Full suite and structural gate invocation](https://github.com/kserrec/attalambda/blob/62d0f0cf7e042bd6478024697c460c9fc88b50f7/run-all-tests.sh).

**S9 — Structural boundaries.** [Boundary checker](https://github.com/kserrec/attalambda/blob/62d0f0cf7e042bd6478024697c460c9fc88b50f7/tooling/check-boundaries.rkt) and [purity checker](https://github.com/kserrec/attalambda/blob/62d0f0cf7e042bd6478024697c460c9fc88b50f7/tooling/check-purity.rkt).

**S10 — Racket reading.** [Reader API and extension controls](https://docs.racket-lang.org/reference/Reading.html).

**S11 — Expeditor.** [Public API, explicit configuration hooks, lifecycle, and history](https://docs.racket-lang.org/expeditor/Expeditor_API.html). Its configuration convenience function may load an initialization file; that is why this contract requires explicit hooks.

**S12 — Racket module mechanisms.** [Module names and loading](https://docs.racket-lang.org/reference/Module_Names_and_Loading.html).

**S13 — Racket namespaces.** [Namespace creation, module registries, and module attachment](https://docs.racket-lang.org/reference/Namespaces.html).

**S14 — Racket resource ownership.** [Custodians and documented managed resource kinds](https://docs.racket-lang.org/reference/custodians.html).

**S15 — Lazy evaluation.** [Racket promises, forcing, and cached values/exceptions](https://docs.racket-lang.org/reference/Delayed_Evaluation.html). Test actual Lazy Racket behavior used by this project; this reference is not a substitute for those tests.

**S16 — Existing Linux release tooling.** [Build script](https://github.com/kserrec/attalambda/blob/62d0f0cf7e042bd6478024697c460c9fc88b50f7/tooling/build-linux-distribution.sh) and [isolated consumer script](https://github.com/kserrec/attalambda/blob/62d0f0cf7e042bd6478024697c460c9fc88b50f7/tooling/test-linux-distribution.sh). The inspected builder targets Racket CS 9.3 and exact version states; the consumer verifies the absence of external Racket.
