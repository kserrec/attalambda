# Addendum: Raw Function Printing Contract

This clarification modifies the generic `value-to-string` / `print` contract for untagged functions.

## Supported Inputs

`value-to-string` and `print` are defined for valid **tagged AttaLambda data values**:

- Error
- Bool
- List
- Result
- Char
- String
- Rat
- Unit
- Byte
- Option
- Map

Raw AttaLambda functions are ordinary untagged lambda values and are **not printable values**.

## Raw Functions Are Outside the Contract

Do not attempt to detect, tag, inspect, stringify, or safely reject arbitrary raw functions.

For example:

```lisp
(print (lambda (x) x))
```

is outside the defined contract of `print`.

Likewise, a function nested inside otherwise printable data is outside the contract:

```lisp
(print
  (cons 1
    (cons (lambda (x) x) NIL)))
```

Because AttaLambda's underlying representation is untyped lambda calculus, an arbitrary lambda cannot in general be safely distinguished from a lambda-encoded tagged object before attempting to interpret it as one.

Therefore, passing an untagged function to `value-to-string` or `print`, directly or recursively inside another value, has **unspecified behavior**.

No structured AttaLambda Error is guaranteed in this case.

The implementation must not add defensive Racket checks or host-side detection to make this case safe.

## Unknown-Tag Fallback

The spec's fallback:

```text
<UNPRINTABLE-TYPE:n>
```

applies only when the input is a **well-formed tagged AttaLambda object** whose tag is not one of the currently supported public tags.

It does not apply to arbitrary untagged lambda functions.

## Do Not Change the Language Model

Do not solve this limitation by adding:

- a Function tag
- an Any tag
- runtime reflection
- host-side function detection
- Racket procedure checks
- a new wrapper around all functions
- a new purity exception

This limitation is accepted deliberately in order to preserve AttaLambda's existing representation and purity model.

All behavior for supported tagged values must remain fully pure and must continue to occur entirely within the existing untyped unary lambda-calculus computation layer.