# AASC MR-KEYFAITH (class b) — design-oracle (proof prototype)

This directory is a **committed design-oracle**: a runnable proof that the
**class (b) MR-KEYFAITH** mechanism — a reflection-derived dangerous-key corpus
that names no key literal, paired with an independent round-trip-faithfulness
oracle — is language-agnostic, constructive, and false-positive-free. It is the
keyed-structure (K-axis) sibling of `../aasc-accept-set/` (the MR-ALPHABET /
class (c) proof). It is a **proof artifact, not normative plugin content** — the
mechanism's prose lives in `skills/impl/references/accept-set-conformance-harness.md`
(§ The worked MR-KEYFAITH (b) shape) and the `ac-evaluator` / `ac-evaluator-hi`
L-ROBUSTNESS lens. Nothing here is run by the test suites or by CI.

## What it proves

The probes pair an **independent round-trip-faithfulness oracle** with a
**reflection-derived key corpus**:

- The oracle computes the expectation **from the INPUT PAIRS by last-write-wins**
  and **never reads it back out of the builder** — so a builder that drops or
  overwrites a key cannot "agree with itself" (the circular-oracle trap). It then
  checks every input key reads back ITS value through the public getter, and that
  `build(serialize(x))` preserves the same observable mapping (the round-trip leg).
- The key generator **DERIVES** the dangerous accessor / reserved / **private /
  internal slot** names **BY REFLECTION** over the live host structures (JS:
  `Object.getOwnPropertySymbols` + climbing `getPrototypeOf` collecting
  `Object.getOwnPropertyNames`; Python: `dir(type(target))` + walking
  `type(target).__mro__` and collecting each base's `vars(base)` keys), **naming
  no key literal in the generator** — exactly as the MR-ALPHABET probe selects
  digits by the Unicode decimal-digit PROPERTY and names no script. Plus the
  generic structural hostiles (empty key, duplicate of an existing key, a
  normalization-collision partner derived from an existing key).

Each probe runs a CORRECT builder (a null-prototype container / a dict-backed
store — the key namespace cannot collide with the structure's reserved slots) and
a BUGGY builder (a plain `{}` with `obj[k]=v`, plus a nested deep-assign variant /
a class doing `setattr` per pair into attribute space) **black-box** over the
reflected corpus, and diffs every verdict against the oracle.

The boundary under test (an in-memory keyed store rebuilt from `(key, value)`
pairs) is **illustrative only** — illustrative on both the domain axis and the
language axis; the mechanism (reflection-derived corpus × independent round-trip
oracle) is the point, not the example.

## Results (reproducible)

- `node probe.js` — the buggy plain-`{}` builder is caught: an input key that
  shadows a prototype slot is not stored as a faithful own-property mapping (the
  flat and deep variants both surface the violation). The correct
  `Object.create(null)` builder (flat and deep) has **zero** oracle-disagreements
  (no false-positive storm).
- `python3 probe.py` — the buggy `setattr`-into-attribute-space builder leaks its
  **private / internal slot** collisions (the input key collides with the
  instance's own internal storage slots, surfaced by the reflection-derived
  corpus that includes those names), **caught by construction** with the generator
  naming no key. The correct dict-backed store has **zero** oracle-disagreements.

The same methodology (independent round-trip-faithfulness oracle × reflection-
derived corpus naming no key) catches each language's *actual* keyed-structure
leak class — prototype-slot shadowing for the plain-object builder, internal-slot
collision for the attribute-space builder — with one oracle and no false
positives. That is the language-agnostic, constructive, false-positive-free
property the class (b) MR-KEYFAITH mechanism rests on.

## Run

```
node design-oracles/aasc-keyfaith/probe.js
python3 design-oracles/aasc-keyfaith/probe.py
```
