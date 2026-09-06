# Specifications

These files are the canonical design inputs for AttaLambda. Phase 27 updated
only the superseded project identity from the original brief. Step 31.1
(2026-09-01) appended an explicitly dated Milestone 4 Amendment to each file
for the exact-rational-numbers-and-foundational-values milestone; each
amendment states that it wins over the earlier sections of its own file, and
the pre-amendment text remains the literal historical contract for the
completed milestones. The Explicit Exit Amendments (2026-09-05) add the
program-chosen exit 0/1 contract, preserve absolute object-language purity,
and specify the public name and existing host boundary before implementation.

The Public API and List Library Amendments (2026-09-06) specify lowercase
callable names, mechanical ASCII Char literals, and the expanded List API.
They preserve the earlier text as history and keep all purity boundaries.
The implementation is complete and published in AttaLambda 0.4.0.
[PLAN.md](../../PLAN.md) records verification; [docs/API.md](../API.md)
describes the implemented surface. The published 0.3.0 archive retains its
earlier API.

Read them in this precedence order:

1. [01-greenfield-core-language.md](01-greenfield-core-language.md) defines the
   base language and first milestone, and its Milestone 4 Amendment defines
   the final public type set, Rat, Unit, Byte, Option, and Map contracts.
2. [02-type-tags-and-absolute-lambda-purity.md](02-type-tags-and-absolute-lambda-purity.md)
   strengthens the type-tag decision and object-language purity rules, and
   its Milestone 4 Amendment fixes the amended tag table and extends the
   absolute purity rule to the new types.
3. [03-canonical-public-naming-and-host-isolation.md](03-canonical-public-naming-and-host-isolation.md)
   overrides conflicting naming examples and isolates Racket-specific names
   from the public language; its Milestone 4 Amendment fixes the exact new
   and retired public spellings.

Later documents override earlier documents only where they explicitly refine
or replace a decision. Within each document, its Milestone 4 Amendment
overrides that document's earlier sections wherever they conflict. Each
Explicit Exit Amendment takes precedence over that document's earlier text
only for its explicitly stated scope. Each Public API and List Library
Amendment takes precedence over earlier text only for the naming, literal,
and List contracts it explicitly changes; all other contracts remain in force.

## Provenance

| File | SHA-256 |
| --- | --- |
| `01-greenfield-core-language.md` | `503e8873f92bb5436df863eb095b871de385e5d6f7ba2d7c6c8240ddccc3df25` |
| `02-type-tags-and-absolute-lambda-purity.md` | `153941fd5d83171146a7ea702f6b72b6e2a8061e5d4e1f715fbdc68181e462c0` |
| `03-canonical-public-naming-and-host-isolation.md` | `9e39495ef071bab601f16f025f7721154142d45bf2ce96012e5680bd982106a5` |

If a specification copy changes intentionally, update its hash here in the
same commit and explain why.

Hash history: the pre-amendment copies preserved verbatim since Phase 0
(identity wording updated in Phase 27) had SHA-256
`6ca00dd7659cacf869242726b136db379e384c0bfe69786cea12329d7236b45b`,
`50a18b3e7f8a40b9343ad6cb475b19d8431771d51f827d990219b27691fa419e`, and
`2a179720d307eeee68f373b5cc56c6bc71a717765d73cd834639dd9b348cd0a1`
respectively. The 2026-09-01 change appended the three Milestone 4
Amendments authorized by the approved Milestone 4 plan (Step 31.1) and
changed nothing above the amendment markers.

Before the 2026-09-05 Explicit Exit Amendments, the respective hashes were
`d4bdd84bb85f8ac0edba2bb993c5bdfb8efeeb33642f423ef3cfd1b66c6a5d20`,
`34b7caf70674979421c794460a8b33d89bc16fe93f8da7c78632cd21814381f7`, and
`d9830bfc16612ba88c1ab485720ea65ecafdb4c5c851f140be95452e2aaaf29d`.
Phase 0 of the approved HTTP/List/exit plan appended the new amendments,
preserving every byte of the preceding contract.

Before the 2026-09-06 Public API and List Library Amendments, the respective
hashes were
`6d03e5cb9181ef250c9e23ecabe2cf9e2774bf203a9be831e57e8035569e8fa4`,
`5561e0acb4ba2eb5399ffdb9fa0f5f4aa8cfd955b2b656aa93573c74ed4864df`,
`216457319c579eaf3ad506550f2467e3071117399f04242a418aee6f391c66fe`.
Step 1.1 appended the approved amendments without changing any preceding byte.
