# AASC accept-set-conformance — design-oracle (proof prototype)

This directory is a **committed design-oracle**: a runnable proof that the
**Advertised-Accept-Set Conformance (AASC)** mechanism is language-agnostic,
constructive, and false-positive-free. It satisfies the charter `§F-1` evidence
item ("commit the prototype as a repo design-oracle"). It is a **proof artifact,
not normative plugin content** — the AASC mechanism itself is NOT yet wired into
the harness; its implementation is gated on the charter `§F-4` discriminating-subject
live dogfood. Nothing here is run by the test suites or by CI.

## What it proves

The probes pair an **independent, hand-coded spec oracle** (accept/reject derived
from the advertised grammar, never importing the implementation) with a
**property-generated complement corpus**: the generator enumerates the Unicode
decimal-digit codepoints that are NOT ASCII (the `\p{Nd}` / Unicode-category
complement of `U+0030..U+0039`), across the BMP **and the astral planes**, **naming
no script in code**. It then runs each implementation **black-box** and diffs every
verdict against the oracle, with accepted-domain idempotence.

The boundary under test (a strict unsigned decimal octet `[0,255]`) is **illustrative
only** — illustrative on both the domain axis and the language axis; the mechanism is
the point, not the example.

## Results (reproducible)

- `node probe.js` — the buggy "looks-numeric-and-in-range" implementation is caught
  (its leaks are structural / non-canonical: leading-zero, whitespace, hex, scientific
  notation, empty); `astral among catches: 0` is **correct** here, because the JS
  native numeric parser is ASCII-only and so leaks no Unicode alphabet. The correct
  implementation has **zero** oracle-disagreements (no false-positive storm).
- `python3 probe.py` — the buggy `str.isdigit()`-then-`int()` implementation leaks the
  **full Unicode-Nd alphabet including ~390 astral codepoints** (the exact class a prior
  dogfood shipped), **caught by construction** with the generator naming no script. The
  correct implementation has **zero** oracle-disagreements.

The same methodology (independent oracle × property-generated complement corpus)
catches each language's *actual* leak class — structural for the ASCII-native parser,
input-alphabet for the Unicode-permissive parser — with one oracle and no false
positives. That is the language-agnostic, constructive, false-positive-free property
AASC rests on.

## Run

```
node design-oracles/aasc-accept-set/probe.js
python3 design-oracles/aasc-accept-set/probe.py
```
