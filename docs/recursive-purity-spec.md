# AttaLambda Recursive Definitions and Purity Repair

## Status

Implementation specification.

This change fixes the recursive-binding hole in AttaLambda's purity contract and adds a pure `rec` form for convenient named recursion.

The scope of this specification is **only recursion and recursive module bindings**. It does not alter the host boundary, object representations, evaluation strategy, typing behavior, arithmetic, effects, or any other purity concern.

---

## 1. Problem

AttaLambda promises that production computation is reducible to and actually evaluated as pure untyped unary lambda calculus: variables, one-argument lambda abstraction, and one-argument application.

The existing `def` macro expands a named function to a Racket/Lazy Racket module definition. For example:

```attalambda
(def loop value =
  (loop value))
```

currently becomes, conceptually:

```racket
(define loop
  (lambda (value)
    (loop value)))
```

The recursive occurrence of `loop` is therefore supplied by Racket's recursive module-binding semantics. It is not produced from lambda calculus by a fixed-point combinator. That violates the purity contract even though the function body otherwise consists only of unary lambda/application forms.

The existing core/effects implementation does **not** need Racket recursion for its recursive algorithms. It already uses `core/fix.rkt`:

```attalambda
(def raw-fix function =
  ((lambda (self)
     (function (self self)))
   (lambda (self)
     (function (self self)))))
```

That construction is pure and must remain the canonical mechanism from which recursion is derived.

The defect is therefore primarily an enforcement hole: ordinary user definitions can currently obtain recursion from the host binding system.

---

## 2. Goals

After this change:

1. Ordinary `def` definitions must be **acyclic**. They may name lambda values and may refer to other top-level definitions, including forward references, but they may not participate in any recursive module-binding cycle.
2. Direct self-recursion through `def` must fail at compile/expansion time.
3. Indirect or mutual recursion through several top-level definitions must also fail. Blocking only the exact same name is insufficient because Racket module bindings can provide recursion through a cycle such as `a -> b -> a`.
4. AttaLambda must expose a public `rec` syntax that allows a user to write one named recursive function directly.
5. `rec` must derive recursion exclusively from the existing pure `raw-fix` term. It must not use Racket `letrec`, recursive `define`, mutation, a host loop, or any other recursive host facility to implement the recursive call.
6. After expansion, the recursive name used inside a `rec` body must be a **lambda-bound variable**, not a reference to the top-level module binding being created.
7. Existing core/effects recursion must remain unchanged unless a test exposes an actual violation.
8. The purity checker must prove that production modules cannot regain recursion through module-binding cycles.
9. Existing tests and examples that deliberately use recursion must use `rec` rather than the now-forbidden recursive `def` behavior.

---

## 3. Non-goals

This change must not:

- expose `raw-fix` as a new public callable;
- add a public `fix` function unless separately specified later;
- automatically make every `def` recursive;
- rewrite existing internal fixed-point algorithms merely to use the new sugar;
- add native Racket recursion anywhere in object-language computation;
- add special runtime support for recursion;
- change Lazy Racket evaluation behavior;
- add mutual-recursion sugar in this change;
- weaken any existing purity or boundary rule.

Users remain free to write their own fixed-point combinator from unary lambdas if they want. `rec` is convenience syntax, not a new computational primitive.

---

## 4. Required public semantics

### 4.1 `def` becomes explicitly non-recursive

These remain valid:

```attalambda
(def identity value = value)

(def first value =
  (second value))

(def second value = value)
```

Forward references are allowed when the dependency graph is acyclic.

This must be rejected:

```attalambda
(def loop value =
  (loop value))
```

This must also be rejected:

```attalambda
(def first value =
  (second value))

(def second value =
  (first value))
```

A cycle is forbidden regardless of whether a definition calls the other binding, merely returns it, passes it as an argument, or otherwise references it. The rule concerns recursive **binding dependency**, not just syntactically obvious calls.

Lexical shadowing must not create false positives. For example, the inner `loop` below is a lambda parameter and is not a recursive reference to the module definition:

```attalambda
(def loop value =
  ((lambda (loop)
     loop)
   value))
```

Likewise, arguments introduced by `def` and local names introduced by `let` are lexical bindings and must shadow equal top-level names when dependency analysis is performed.

### 4.2 Add `rec`

Public syntax:

```attalambda
(rec name argument ... = body)
```

It should mirror `def`'s argument syntax and currying behavior.

Example:

```attalambda
(rec factorial n =
  (if (eq n 0)
      1
      (mult n (factorial (sub n 1)))))
```

Conceptually, this must mean:

```attalambda
(def factorial =
  (raw-fix
   (lambda (factorial)
     (lambda (n)
       (if (eq n 0)
           1
           (mult n (factorial (sub n 1))))))))
```

`raw-fix` in that example is explanatory only. It remains private to the implementation.

For multiple arguments:

```attalambda
(rec function first second third = body)
```

must conceptually desugar to:

```attalambda
(def function =
  (raw-fix
   (lambda (function)
     (lambda (first)
       (lambda (second)
         (lambda (third)
           body))))))
```

The recursive name is therefore bound by `(lambda (function) ...)` inside the fixed-point construction. Calls to `function` in `body` are ordinary lambda-variable applications.

### 4.3 `rec` does not authorize module cycles

`rec` legalizes only the definition's **own recursive name**, because that name is transformed into a lexical lambda binding.

It must not become a loophole for mutual Racket-backed recursion. For example, this must still fail:

```attalambda
(rec first value =
  (second value))

(def second value =
  (first value))
```

After treating `first`'s self references as lexical recursion, the remaining top-level dependency graph still contains a cycle between `first` and `second`. That cycle would rely on module binding recursion and is forbidden.

Mutual recursion can be designed separately later using an explicitly lambda-encoded construction if desired.

---

## 5. Implementation design

### 5.1 Keep `raw-fix` canonical and private

Do not duplicate the fixed-point term inside the new macro.

`core/fix.rkt` remains the canonical implementation of fixed-point recursion. The public language expander should import it privately, for example under an implementation-only name such as `language-fix`:

```racket
(only-in "../core/fix.rkt"
         [raw-fix language-fix])
```

Do not export `language-fix` or `raw-fix` from `#lang attalambda`.

This keeps one auditable fixed-point implementation and makes `rec` strictly syntactic convenience over an already purity-checked lambda term.

### 5.2 Implement `rec` in `lang/expander.rkt`

Implement a language transformer such as `language-rec` and export it as public `rec`.

The transformer must:

1. require an identifier for the function name;
2. accept zero or more identifier arguments, matching `def`'s existing source shape;
3. require exactly one `=` marker and one body expression;
4. mechanically build nested unary lambdas for the declared arguments;
5. wrap those lambdas in another unary lambda whose parameter is the recursive function name;
6. apply private `language-fix` to that recursive step function;
7. bind the resulting fixed point as the top-level name.

The important invariant is the expansion shape, not the exact helper-function names. The resulting computational value must be equivalent to:

```text
language-fix
  (lambda (recursive-name)
    (lambda (arg1)
      ...
        (lambda (argN)
          body)))
```

Do not implement `rec` with Racket `letrec`, named `let`, self-referential `define`, boxes, mutation, or any hidden host recursion.

### 5.3 Make the module wrapper recognize `rec` as a definition

`language-module-begin` currently distinguishes `def` forms from top-level expressions so definitions are not wrapped in `language-discard`.

Update `language-definition-form?` so both `def` and `rec` are recognized as definition forms.

No other top-level definition syntax should be introduced.

### 5.4 Reject recursive top-level dependency cycles in user programs

The public language must reject the bad program itself. Repository-only purity checks are insufficient because arbitrary user `.attl` files do not pass through `tooling/check-purity.rkt`.

Add a compile-time validation step to `language-module-begin` before it emits the module body.

The validator must:

1. collect all top-level `def` and `rec` names in the source module;
2. inspect each definition body and collect references to those top-level names that are free with respect to that definition's lexical bindings;
3. treat all arguments declared by a `def` as lexical bindings in its body;
4. treat all arguments declared by a `rec` as lexical bindings in its body;
5. additionally treat the `rec` definition's own name as lexical within its body, because `rec` will lambda-bind that name during desugaring;
6. recognize `lambda` parameters as lexical bindings inside lambda bodies;
7. recognize `let` names as lexical only in the `let` body, not in the value expression;
8. construct the directed graph of remaining top-level dependencies;
9. reject every graph cycle, including self-cycles and cycles of two or more bindings.

A standard DFS cycle detector or strongly-connected-component algorithm is sufficient. Keep this checker small and explicit; do not introduce a generalized compiler framework.

The error should clearly tell the user why the source is invalid. Suggested wording:

```text
recursive def binding is not allowed; use rec for self recursion
```

For a multi-binding cycle, wording may instead identify the cyclic names and state that module-binding recursion is forbidden. Do not claim `rec` supports mutual recursion if it does not.

### 5.5 Preserve acyclic module bindings

Do not ban all forward references or all references between top-level definitions.

This is legal:

```attalambda
(def use-helper value =
  (helper value))

(def helper value = value)
```

because the dependency graph contains `use-helper -> helper` but no path back to `use-helper`.

The purity rule forbids host-provided recursion, not ordinary module naming scaffolding.

---

## 6. Strengthen `tooling/check-purity.rkt`

The production purity checker currently verifies the shape of each expanded expression but permits references to bindings in the same project/module. That is why a self-recursive unary lambda can look pure locally while still relying on Racket's recursive module binding.

Add an explicit expanded-module binding-cycle check.

### Required behavior

For each scanned production module:

1. identify its single-name `define-values` bindings after full expansion;
2. for each definition RHS, traverse the already-expanded accepted lambda/application tree and collect references whose binding resolves to another phase-0 binding in the **same module**;
3. lexical references must not become graph edges;
4. imported project bindings must not become same-module graph edges;
5. build the same-module dependency graph;
6. report a purity violation for every recursive strongly connected component or otherwise deterministically report the cycle;
7. a one-node component with a self-edge is a violation;
8. a component of two or more definitions is a violation.

Use a clear violation kind such as:

```text
recursive-module-binding
```

The checker must continue accepting explicit lambda self-application and `raw-fix`, because their recursive variables are lexical bindings rather than module-binding cycles.

Do not weaken any existing expanded-form checks.

---

## 7. Update the structural boundary checker

Because `lang/expander.rkt` is intentionally pinned by `tooling/check-boundaries.rkt`, update its exact expectations rather than loosening them.

Expected changes include only what the new language syntax requires:

- add the private `core/fix.rkt` import with the exact selected binding;
- add `language-rec` to the approved language transformer set;
- add any small compile-time helper functions needed for currying, dependency collection, and cycle detection to the approved syntax-helper set;
- export `language-rec` only under the public spelling `rec`;
- add the exact new identifiers to the language-expander vocabulary;
- update the definition-form recognition expectations if pinned;
- keep every existing host-capability prohibition unchanged.

Do **not** solve boundary failures by broadening vocabulary or import rules beyond the exact identifiers introduced by this feature.

---

## 8. Tests

### 8.1 `tests/language-test.rkt`

Add public-language acceptance/rejection coverage.

#### Must fail

Direct recursive `def`:

```attalambda
(def loop value =
  (loop value))
```

Direct recursive value alias:

```attalambda
(def loop = loop)
```

Mutual recursion:

```attalambda
(def first value = (second value))
(def second value = (first value))
```

Cycle involving `rec` plus another top-level binding:

```attalambda
(rec first value = (second value))
(def second value = (first value))
```

All should fail during source expansion/compilation, before execution.

#### Must succeed

A simple recursive function implemented with `rec`, with its result observed through existing public operations.

A multi-argument recursive function using `rec`, proving currying remains unary underneath.

Acyclic forward top-level references.

A definition in which a local `lambda` or `let` shadows the same spelling as the top-level definition, proving the cycle detector is lexical rather than textual.

### 8.2 Convert existing recursive language-test fixtures

The list-library fixture currently defines a divergent helper with:

```attalambda
(def loop value = (loop value))
```

Change it to:

```attalambda
(rec loop value = (loop value))
```

The separate lazy-branch fixture must be changed the same way.

Keep the behavior being tested identical: the recursive function must diverge if evaluated, while lazy branches/list operations that should not evaluate it must continue succeeding.

These tests are especially useful because they prove that `rec` produces a genuinely usable recursive function while preserving laziness.

### 8.3 `tests/purity-test.rkt`

Add checker-level regression cases proving that expanded production modules cannot use module-binding recursion.

At minimum:

- a directly self-referential module definition produces `recursive-module-binding`;
- two otherwise-pure definitions that reference one another produce `recursive-module-binding`;
- a raw-fix-shaped definition using lexical self-application continues to pass;
- acyclic same-module references continue to pass;
- existing real-core and real-effects scans remain clean.

Do not replace existing shape tests; add cycle tests alongside them.

### 8.4 Transformer/boundary tests

Update the tests that pin `lang/expander.rkt` so `rec` and the private fixed-point import are exact approved changes.

Add a test proving `raw-fix`/`language-fix` is **not** a public AttaLambda name.

If there is a public-name isolation test, add `rec` as available syntax while confirming the private fix binding remains inaccessible.

---

## 9. Update the HTTP example

`examples/http-server.attl` currently contains the one known example of ordinary user-level recursive `def`:

```attalambda
(def nat-to-decimal value =
  ...
  (nat-to-decimal quotient)
  ...)
```

Change only the definition form:

```attalambda
(rec nat-to-decimal value =
  ...
  (nat-to-decimal quotient)
  ...)
```

Do not rewrite the algorithm or change the example's behavior.

The example should continue serving the same request and formatting the selected port the same way. Its purpose after this change is also to demonstrate the intended public recursion syntax.

---

## 10. Documentation

Update `docs/API.md` syntax table to distinguish the two forms clearly:

```text
(def name first second = body)  Named acyclic definition; arguments curry to unary lambdas.
(rec name first second = body)  Pure recursive definition; sugar over the lambda fixed-point combinator.
```

State explicitly that:

- `def` cannot recursively depend on itself, directly or indirectly through other top-level definitions;
- `rec` provides self recursion by lambda-binding the function name through the pure fixed-point combinator;
- `rec` is syntax, not a runtime primitive;
- `raw-fix` remains private;
- all resulting computation is still unary untyped lambda calculus.

Update the absolute-purity specification with a short amendment recording this rule so future work cannot accidentally restore recursive module bindings.

The required invariant should be stated approximately as:

> Top-level names are module scaffolding only. No cycle among object-language top-level bindings may provide computational recursion. `rec` is permitted only because it mechanically translates a self-recursive source definition into an acyclic top-level binding whose recursive name is lambda-bound inside the existing pure fixed-point term.

Do not add lengthy tutorial material in this change.

---

## 11. Expected files

The implementation should normally be confined to approximately these files:

```text
lang/expander.rkt
core/fix.rkt                         # normally unchanged; verify only
tooling/check-purity.rkt
tooling/check-boundaries.rkt
tests/language-test.rkt
tests/purity-test.rkt
tests/boundary-check-test.rkt         # if required by pinned expectations
examples/http-server.attl
docs/API.md
docs/specifications/02-type-tags-and-absolute-lambda-purity.md
```

`macros/macros.rkt` should **not need to change** under the preferred design because `rec` belongs to the public language expander and can privately reuse `raw-fix` there. If implementation pressure suggests changing `macros/macros.rkt`, stop and confirm that doing so is actually simpler and does not duplicate the fixed-point implementation or widen the macro layer's role.

---

## 12. Implementation order

### Phase 1 — Lock the failure down

1. Add failing language tests for direct recursive `def`, mutual recursive `def`, and a cycle crossing `rec`/`def` once `rec` exists.
2. Add failing purity-checker fixtures for direct and mutual same-module recursive bindings.
3. Confirm the tests demonstrate the current hole before changing enforcement.

### Phase 2 — Add public pure recursion

1. Privately import `raw-fix` into `lang/expander.rkt`.
2. Add the `language-rec` transformer and its minimal unary-currying helper.
3. Export it as `rec`.
4. Teach `language-module-begin` to treat `rec` as a definition.
5. Add successful `rec` execution tests, including multiple source arguments and lazy non-evaluation.

### Phase 3 — Remove host-backed recursive definitions

1. Add top-level dependency analysis to the public language module wrapper.
2. Reject every cyclic top-level dependency after treating a `rec` definition's own recursive name as lexical.
3. Preserve acyclic forward references and lexical shadowing.
4. Add explicit error-message assertions where stable enough to be useful.

### Phase 4 — Close the repository purity proof

1. Add same-module binding graph analysis to `tooling/check-purity.rkt` using expanded binding identity.
2. Reject direct and mutual module-binding cycles.
3. Verify `raw-fix` and other lexical self-application remain accepted.
4. Run the full core/effects purity scan with zero violations.

### Phase 5 — Update pinned boundaries and usages

1. Update `tooling/check-boundaries.rkt` and boundary tests only for the exact new expander import/export/helpers.
2. Convert recursive test helpers from `def` to `rec`.
3. Convert `examples/http-server.attl`'s `nat-to-decimal` from `def` to `rec` without altering its body.
4. Update the API and purity documentation.

### Phase 6 — Final verification

Run the full repository test suite and both architectural checks.

No phase is complete until all existing tests plus the new recursion tests pass.

---

## 13. Acceptance criteria

The change is complete only if all of the following are true:

1. `(def loop x = (loop x))` is rejected by `#lang attalambda`.
2. Mutual recursion through two or more ordinary top-level bindings is rejected.
3. Acyclic references between top-level definitions, including forward references, still compile.
4. Lexical shadowing does not trigger false recursion errors.
5. `(rec loop x = (loop x))` compiles successfully.
6. A terminating recursive `rec` program returns the expected result.
7. A divergent `rec` helper remains unevaluated in the existing lazy-branch/list tests where it should not be forced.
8. Multi-argument `rec` behaves as a curried unary function.
9. `rec` expands through the existing `raw-fix`; no host recursive form is introduced.
10. The recursive name inside a `rec` body is lambda-bound after desugaring rather than module-bound.
11. `raw-fix` remains inaccessible as a public AttaLambda identifier.
12. `tooling/check-purity.rkt` rejects direct and mutual same-module recursive bindings.
13. `tooling/check-purity.rkt` still accepts `core/fix.rkt` and the entire existing core/effects tree.
14. The HTTP example uses `rec` and behaves identically to before.
15. `tooling/check-boundaries.rkt` passes without broadening any host or production capability allowlist beyond the exact identifiers required for this feature.
16. The complete test suite passes.

---

## 14. Purity invariant after the change

After implementation, AttaLambda's recursion story must be simple enough to state exactly:

> `def` gives an acyclic module name to a lambda term. It never supplies recursion. `rec` is syntax that transforms a self-recursive source definition into an application of AttaLambda's existing lambda-encoded fixed-point combinator to a unary lambda that binds the recursive name. Therefore recursive execution still arises entirely from untyped unary lambda abstraction and application, never from Racket recursion.

That invariant is the reason for the change. Convenience must not weaken it.
