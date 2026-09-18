# Optional static checking: Phase 2 pilot

Observed with the actual expansion-only frontend, inference kernel, and seed
catalog on the local unreleased milestone branch. This is backend evidence;
no public checking command or standalone checking candidate exists at this gate.
The published 0.8.0 binary is unchanged. No fixture was executed by the checker.

The catalog accounts for all 129 resolved public value bindings: 20 complete
seed contracts, one partial unwrap contract, and 108 entries explicitly pending
Phase 3 audit. Pending entries are internal failures if requested, not fabricated
safe signatures. The shipping catalog gate rejects any pending entry.

Expectations were recorded before implementation in PLAN.md. Each observed proof
state below matched its expectation. Established means the backend discharged
all source obligations in that fixture relative to the seed contracts; conflict
means a supported finite equation failed; unproved means a named obligation
remains. Counts use original source expression IDs, excluding generated nodes.

| Fixture | Observed state | Established expressions | Primary reasons |
| --- | --- | --- | --- |
| C01 | established | 7/7 | none |
| C02 | established | 12/12 | none |
| C03 | conflict | 9/13 | TYPE_CONFLICT |
| C04 | conflict | 11/14 | TYPE_CONFLICT |
| C05-function | established | 3/3 | none |
| C05-value | established | 1/1 | none |
| C06 | conflict | 6/9 | TYPE_CONFLICT |
| C07 | conflict | 5/6 | TYPE_CONFLICT |
| C09 | established | 16/16 | none |
| C11 | unproved | 5/8 | UNREPRESENTED_ERROR_ALTERNATIVE |
| C13 | unproved | 0/1 | UNREPRESENTED_ERROR_ALTERNATIVE |
| C14 | unproved | 4/7 | UNREPRESENTED_ERROR_ALTERNATIVE |
| C16 | conflict | 6/7 | TYPE_CONFLICT |
| usefulness | established | 24/24 | none |
| section-3.2-kernel | established | 24/24 | none |
| guarded-unwrap | unproved | 10/14 | UNREPRESENTED_ERROR_ALTERNATIVE |
| raw-self-application | unproved | 6/7 | RECURSIVE_TYPE_REQUIRED |
| seed-C12 | conflict | 6/9 | UNREPRESENTED_ERROR_ALTERNATIVE, TYPE_CONFLICT |

Identity, apply, compose, partial arithmetic, forward bindings, factorial, and
summation have usable inferred schemes. The Section 3.2 kernel fixture establishes
`double : Rat -> Rat`, `factorial : Rat -> Rat`, and the arithmetic call. Its
rendering/stdout calls join only after their Phase 3 audits.

Guarded unwraps remain unproved because V1 has no Result-variant refinement.
Raw self-application requires an unsupported recursive type. A bare unwrap alias
and a returned nested function cannot hide that gap. Definite conflicts win when
a file also has an unproved region. C16 retains double's established declaration
after rejecting the bad call. No termination or external-operation success is
claimed, including for the deliberately divergent C05 fixtures.

The additional pilot regressions cover three-binding dependency chains, captured
closures, higher-order partial use, known later arguments after earlier gaps,
conditional input-template freshening and captured monomorphism, source renaming
and declaration reordering, and C01/C07/C01 in one backend process. The repeated
C01 analyses are structurally equal; completed upstream schemes stay immutable.

Evidence: `/tmp/attalambda-static-implementation-mmgdshl_/pilot-results.json`,
`step-2.9-final.log`, and the focused step logs named in PLAN.md. Reusable source
fixtures are in `tests/helpers/static-pilot.rkt`; tests use the real frontend.
The initial `step-2.9.log` is an unsuccessful test-compilation attempt caused by
an extra closing parenthesis in the new test file. It is not a pilot result.

Review is self-review, not an independent or formal proof. The kernel composition
and catalog-label permission findings recorded in PLAN.md are resolved and
covered by regressions. Phase 2's full checkpoint passed 87 Racket test files,
26919 reported Racket tests, 49 Python methods, and both structural gates; the
tested input hashes are in `phase2-result.json`. Bounded nesting, long application,
independent-definition, and 100-alias probes also preserve expected outcomes and
exact counts across repeated analyses. Phase 3 completes the same catalog; Phase 4 adds
final report/status delivery; Phase 5 measures all public examples and verifies
an exact local standalone archive. No corpus percentage is promised.
