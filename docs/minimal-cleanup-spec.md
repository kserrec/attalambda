# AttaLambda Minimal Cleanup

## Goal

Fix the concrete launcher path-resolution bug and remove two small pieces of unnecessary maintenance coupling without changing AttaLambda semantics, purity guarantees, public APIs, runtime behavior, or architecture.

This is **not** a general refactor.

Do not clean up unrelated code while doing this.

---

## Phase 1 — Fix relative symlink resolution

### Problem

`runner/attalambda.rkt` follows a symlink with `resolve-path`, then passes the result directly to `path->complete-path`.

When the symlink target is relative, that target must be interpreted relative to the directory containing the symlink, not the process working directory.

### Change

Modify only the path-resolution logic necessary to correctly resolve relative symlink targets.

When `resolve-path next` returns:

- an absolute path: use it normally
- a relative path: resolve it relative to the directory containing `next`

Preserve the existing loop detection, `.env` rejection, regular-file checking, and all other launcher behavior.

Do not redesign `resolve-parent-path`.

### Tests

Add the smallest regression coverage necessary:

1. Create a directory symlink whose target is relative.
2. Put a valid `.attl` program beneath the target.
3. Launch AttaLambda from a working directory different from the symlink directory.
4. Verify the program runs successfully.

Also verify the existing symlink/path-security tests still pass unchanged.

---

## Phase 2 — Stop hardcoding every historical version in the runner

### Problem

`embedded-product-version` accepts only an explicit list of previously known AttaLambda versions.

That means a future valid release requires changing executable code merely to permit the new `VERSION`.

### Change

Keep reading `VERSION` exactly as now.

Replace the explicit historical-version alternation with a small validation of the version format AttaLambda actually supports.

Accept ordinary semantic versions of the form:

`MAJOR.MINOR.PATCH`

and the development/release-candidate suffix forms already used by the project, if those formats are still required.

Do not change:

- how `VERSION` is embedded
- `--version` output
- package-version projection logic elsewhere unless a failing test proves it must change
- release behavior

The runner should validate that `VERSION` is structurally valid, not maintain a list of every release that has ever existed.

### Tests

Keep all current version tests.

Add one test using a valid hypothetical future version, such as `0.6.1`, proving the runner no longer requires source modification for every release.

Keep malformed-version rejection coverage.

---

## Phase 3 — Remove only unnecessary local-name policing from the boundary checker

### Problem

`tooling/check-boundaries.rkt` currently uses strict vocabulary lists that include ordinary local identifiers.

This means harmless local-variable renames can require changes to the architectural boundary checker even though no capability, dependency, effect, export, or trust boundary changed.

### Change

Narrow this behavior only enough that **ordinary local binding names are not part of the security/purity contract**.

Continue enforcing all meaningful restrictions, including:

- allowed module languages
- allowed imports
- allowed exports
- privileged host identifiers
- forbidden capabilities
- mutation restrictions
- runtime/host separation
- codec restrictions
- runner loading restrictions
- effect boundaries
- production source classification
- purity checks
- exact structural checks where the structure itself is security-sensitive

Do **not** replace the boundary checker.

Do **not** broadly remove its allowlists.

Do **not** weaken `check-purity.rkt`.

The intended test is simple:

> Renaming a harmless local variable in trusted surrounding implementation code should not require editing the boundary checker merely to add the new local name.

If separating local bindings from capability names would require a large redesign, **skip Phase 3 rather than expanding scope**. Phases 1 and 2 are independently valuable and should not depend on it.

### Tests

Add one focused fixture/test demonstrating that an otherwise-identical allowed module does not fail solely because a harmless local binding has a previously unseen name.

Existing tests must continue proving that adding a prohibited capability or import still fails.

---

# Explicit non-goals

Do not modify:

- `core/` semantics
- lambda encodings
- `raw-fix`
- `rec`
- type checking
- rendering or printing
- object representations
- host request validation
- host operation allowlist
- file/TCP behavior
- HTTP server behavior
- error semantics
- public AttaLambda syntax
- public API names

Do not introduce new abstractions merely to implement these changes.

Do not rename unrelated identifiers.

Do not reformat unrelated files.

Do not deduplicate unrelated code.

Do not add configuration.

Do not add dependencies.

---

# Verification

After each phase, run the smallest relevant tests first.

At the end run the complete existing test suite, purity checker, and boundary checker.

The final state must satisfy:

1. Relative symlink targets resolve correctly independent of process working directory.
2. Future structurally valid AttaLambda versions do not require editing the runner's historical version list.
3. If Phase 3 is safely achievable, harmless local renames are not architectural boundary violations.
4. All existing purity and boundary guarantees remain intact.
5. All existing tests pass.
6. No unrelated production behavior changes.

Keep the diff as small as possible.

If any proposed simplification starts requiring substantial architectural changes, preserve the existing implementation instead.