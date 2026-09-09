# AttaLambda Small Lisp Sugar

## Goal

Add exactly four small source-level sugars:

1. `(list ...)`
2. multi-argument `lambda`
3. multi-binding `let`
4. `cond`

These are syntax conveniences only.

They must expand into constructs AttaLambda already supports.

Do not add runtime behavior, core functionality, types, values, host capabilities, or new semantics.

Target roughly **80 lines or less of production implementation**, excluding tests and minor boundary-check bookkeeping. If implementation starts becoming substantially larger, stop and simplify rather than expanding the design.

---

## 1. `list`

Allow:

```lisp
(list)
(list 1 2 3)
(list x (add y 1) "hello")
```

Expand mechanically to:

```lisp
NIL
```

and:

```lisp
(cons 1
  (cons 2
    (cons 3 NIL)))
```

respectively.

Elements are ordinary AttaLambda expressions and must retain their normal lazy evaluation behavior.

Nested lists must work naturally:

```lisp
(list
  (list 1 2)
  (list 3 4))
```

Do not introduce a new List representation. This is only sugar for existing `cons` and `NIL`.

---

## 2. Multi-argument `lambda`

Current unary lambda syntax remains valid:

```lisp
(lambda (x) body)
```

Also allow:

```lisp
(lambda (x y z) body)
```

Expand to:

```lisp
(lambda (x)
  (lambda (y)
    (lambda (z)
      body)))
```

Reuse the existing currying helper already used by `def` and `rec` if practical.

Do not change the underlying rule that actual lambda abstraction is unary.

Zero-argument lambdas should remain invalid unless they are already supported for an unrelated reason.

Reject malformed or non-identifier argument lists with a clear syntax error.

---

## 3. Multi-binding `let`

Preserve the existing form:

```lisp
(let x = value
  body)
```

Also allow conventional Lisp-style bindings:

```lisp
(let ((x value-x)
      (y value-y)
      (z value-z))
  body)
```

Expand to nested existing lets:

```lisp
(let x = value-x
  (let y = value-y
    (let z = value-z
      body)))
```

Bindings therefore have normal sequential nested-let semantics.

Later bindings may refer to earlier bindings:

```lisp
(let ((x 2)
      (y (add x 3)))
  y)
```

must work.

Do not implement `letrec`, parallel binding semantics, destructuring, or named `let`.

Empty binding lists may simply return the body:

```lisp
(let () body)
```

→ `body`

if doing so is trivial; otherwise it may be rejected. Do not add complexity for this case.

---

## 4. `cond`

Allow:

```lisp
(cond
  ((lt x 0) "negative")
  ((eq x 0) "zero")
  (else "positive"))
```

Expand mechanically to:

```lisp
(if (lt x 0)
    "negative"
    (if (eq x 0)
        "zero"
        "positive"))
```

Each clause must contain exactly:

```lisp
(condition result)
```

The final `else` clause, when present, must be last.

Preserve AttaLambda's existing lazy `if` behavior: unselected result expressions must not be evaluated.

For a `cond` with no matching condition and no `else`, choose the smallest behavior consistent with the existing language. Prefer requiring a final `else` if that avoids inventing a new default value or failure semantics.

Do not add:

- `=>`
- multi-expression clause bodies
- implicit `begin`
- pattern matching
- guards
- any other Scheme/Racket `cond` features

This is just nested `if`.

---

# Implementation constraints

Prefer changes only in `lang/expander.rkt` plus whatever exact boundary-check vocabulary updates are required by the existing repository rules.

Reuse existing expansion helpers wherever sensible.

Especially:

- use the existing currying machinery for multi-argument lambdas if possible
- use small recursive compile-time helpers for list, let, and cond expansion

Do not introduce a generic macro framework.

Do not modify `core/`.

Do not modify `runtime/`.

Do not modify the host.

Do not modify object representations.

Do not weaken purity or boundary checking.

Do not add dependencies.

Do not refactor unrelated expander code.

Do not rename unrelated functions.

---

# Essential tests

Add focused language-level tests for each sugar.

## `list`

Verify:

```lisp
(list)
(list 1)
(list 1 2 3)
(list (list 1 2) (list 3 4))
```

behave exactly like equivalent hand-written `cons`/`NIL` expressions.

Include at least one list containing computed expressions rather than only literals.

## Multi-argument `lambda`

Verify:

```lisp
((lambda (x y) (add x y)) 2 3)
```

works.

Verify three arguments.

Verify the existing unary form still works unchanged.

Verify malformed argument lists fail during expansion.

## Multi-binding `let`

Verify:

```lisp
(let ((x 2)
      (y 3))
  (add x y))
```

works.

Verify a later binding can use an earlier one.

Verify the existing:

```lisp
(let x = value body)
```

form remains unchanged.

Verify malformed binding forms fail during expansion.

## `cond`

Verify:

```lisp
(cond
  (FALSE bad-expression)
  (TRUE "yes")
  (else "no"))
```

returns `"yes"` without forcing the false branch.

Verify first, middle, and `else` selection.

Verify `else` anywhere except last fails.

Verify malformed clauses fail.

---

# Purity verification

For each sugar, include at least one test showing that its expanded result remains accepted by the existing purity/boundary gates.

The sugars must disappear into already-approved AttaLambda constructs.

No new production computation form should survive expansion.

---

# Final verification

Run the complete existing test suite, purity checker, and boundary checker.

Success means:

- all four sugars work
- all old syntax still works
- no semantic behavior changes
- no purity changes
- no core/runtime changes
- implementation remains small and obvious

The production diff should stay roughly in the **tens of lines, ideally around 80 or less total**. Tests may be larger than the implementation.

If a feature requires substantial new architecture, do not build that architecture; implement the smaller direct expansion instead.