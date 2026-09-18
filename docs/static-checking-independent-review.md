# Optional static checking: independent review

This is the focused follow-up Kyle requested after the completed local candidate,
not a whole-project audit or a formal soundness proof. It reviews the milestone
from `f6938b286329532230be210de0eaaa398286d38a` through
`ab521b034bd7ff0ea06daf70046518d1995c0499`, plus the corrections described here.
The original archive and its receipt remain historical evidence, not evidence
for these later changes. Nothing in this review authorizes remote publication.

## Coverage and limits

Three independent read-only reviewers examined separate areas. The inference
reviewer close-read all seven kernel/inference/proof modules, source accounting,
reporting, static metadata, and sixteen focused test files. The contract reviewer
checked all 129 public catalog entries against their strict wrappers, raw normal
return paths, effects, host/codec implementation, readers, and ten contract test
files. Deep binary arithmetic algorithms were outside that contract review.

The frontend reviewer close-read static metadata/source lowering, the entire
expander, frontend, coverage/report/command modules, launcher, source-file policy,
restricted reader and diagnostics, plus fourteen focused test/helper files.
That review turn ended before its final written report; its completed probes
are retained separately and are not represented as a finished final report.
Root independently checked those reproductions and the changed implementation.
A separate reviewer diagnosed syntax provenance with raw expansion instrumentation
and a bounded twenty-case classifier before the corresponding correction.

Root examined the changed structural gate logic, negative boundary tests, Linux
consumer static-checking path, platform consumer help changes, distribution
assertions and integration. The large helper vocabulary was checked as a
capability inventory and in each modified rule, rather than treated as a second
line-by-line implementation review. Dependency manifests, version metadata,
ignore rules, builder and workflow changes were checked against the milestone
base: no new dependency, installation script, CI permission, deployment or
publication mechanism was introduced. Existing workflow sections were inspected
for how the consumer artifacts are transferred and removed. This is not a
history-wide credential audit; dotenv contents were never inspected.

The new command is local source-analysis tooling, not a hosted execution service
or a resource sandbox. No source-controlled reader extension, arbitrary module
import, user-program evaluation or instantiation bypass was demonstrated. Tests
exercise reader restrictions, no effects, inert source analysis, safe diagnostics,
resource cleanup and exact structural boundaries. Native macOS and Windows
execution is outside this Linux review. Unchanged historical subsystems were
examined only where needed to establish the new checker's contracts.

## Confirmed findings

All four are defects in the completed milestone, rather than accepted limitations
or work already planned for another phase. No finding is deferred.

### H1: incomplete functions lose known parameter constraints

The checker reported PARTIAL, with no conflict, for
`(rec bad n = (if (is-zero n) (head NIL) (bad TRUE)))`.
The unknown result of `head` hid the independently known Rat/Bool mismatch in
the recursive argument. The same cause affected direct calls to incomplete
lambdas and callbacks such as `(map head (list 1))`.

The value-proof separation was correct: an incomplete result must have no
established type. The defect was discarding known input obligations along with
that result. The correction retains only the known remaining input domains,
with a fresh opaque final result placeholder used for constraint comparison.
It preserves identities/restrictions inside parameters and callback contracts.
This shape never establishes a value signature or checked expression. Recursive
consistency and higher-order argument checking now compare that input evidence.
The bounded inference hunter is retained in
`tests/static-incomplete-callables-test.rkt`, including negative controls that
must remain PARTIAL without fabricated result conflicts.

### H2: ordinary explicit application and literal forms fail internally

Ordinary expansion accepts `(#%app add 1 2)` and `(#%datum . 1)`, but checking
returned status 70. Mechanical source lowering treated the syntax operator as
a catalog value, or the dotted literal form as an unsupported literal.

The correction recognizes the existing syntax bindings by identity and lowers
them to the same application/literal nodes as implicit forms. It adds no public
syntax or runtime behavior. Regressions cover dotted application, nesting,
aliases, all supported literal kinds, invalid literal/arity controls, source
locations, source counts and ordinary/analyzed expansion equivalence.

### H3: tcp-listen's audited success hint has the wrong shape

The catalog and its documentation said `Result(Rat)`. The actual success payload
is a two-element List containing listener handle and bound port, so the correct
hint is `Result(List(Rat))`. The operation remains partial; the incorrect hint
did not itself establish a false FULL PASS.

The catalog and documentation are corrected. A bounded real loopback driver in
`tests/static-tcp-contracts-test.rkt` checks all six TCP normal return shapes
against the catalog and retains their partial classification. It uses an
ephemeral listener and closes all owned handles, including on failure.

### H4: a trusted syntax fault is mislabeled as a user source error

The frontend caught every syntax exception during expansion as status 65.
A private trusted module-resolution fault therefore exposed a private identifier
and implementation line number as if they belonged to the submitted file.
This was demonstrated with test-only resolver injection; no user-controlled
execution or access to private files was established.

The correction distinguishes source-attributable syntax failures from
unattributed trusted failures, including generated syntax whose user provenance
is retained in origins or child nodes. Unattributed failures use the existing
safe status 70 diagnostic. Metadata validation is outside the syntax handler.
Genuine malformed nested definitions retain status 65 and source locations,
without naming generated implementation identifiers as unknown user names.

## Evidence and verification

Evidence root: `/tmp/attalambda-static-review-5du21rkr/`. Reviewer reports and
original proof scripts/logs are under `inference/`, `contracts/`, and `frontend/`.
All execution uses an isolated corrected Racket CS 9.3 container as unprivileged
`attatest`. The owner's runtime is unchanged.

The initial independent kernel run passed eighteen tests; a separate bounded
probe checked 704 successful two-equation states for equation preservation,
substitution idempotence and data restrictions. The initial contract probe
checked 954 runtime witnesses across all 106 complete entries with no observed
wrong result shape. The TCP family probe identified only H3 and cleaned up all
handles. These are bounded checks, not exhaustive proofs.

An earlier aggregate inference test run hit its 120-second outer deadline during
the 5000-expression coverage case. It is recorded as incomplete, not a pass or
a demonstrated product defect. Correction-focused logs distinguish their actual
results; an initial regression assertion incorrectly required literal `#t` from
a membership predicate returning a non-false list, and was corrected as test code.
The first resolver-injection test compared an unresolved `tests/../lang` path
with the frontend's normalized path and did not inject. Observing both paths
identified this test mistake; normalizing the test path made the injection run.
No production workaround was added for either test mistake.

The fresh cold reviewer close-read every production correction and its surrounding
inference, proof, substitution, source, frontend and diagnostics paths, then the
associated tests, gates, documentation and final consumer additions. Eighteen
additional inference probes passed (eleven conflicts, seven deliberately partial),
as did thirty-four ordinary/analyzed syntax comparisons and five provenance
fault cases. No additional proved finding remained. Exact coverage and probes
are retained in `cold/report.md`; the reviewer made no source changes.

The five existing public example reports match the original candidate byte for
byte, including their counts, signatures and gap explanations. Focused correction
checks and structural boundaries passed. `review-full.log` records the completed
full run: 104 Racket test files, 26981 reported tests, 49 Python terminal methods,
purity over 40 production files, and the repository-wide source boundary gate.
`review-result.json` verifies all 225 executable/packaging inputs against that
snapshot. The replacement-candidate build and consumer remain the final delivery
step. Remote CI and native macOS/Windows execution have not been run in this
local-only review.
