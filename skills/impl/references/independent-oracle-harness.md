# Independent-oracle harness (gold-standard shape)

Binding parties: the `implementer` and `test-writer` agents (authoring), and the
`ac-evaluator` (when building a scratch oracle probe). This file gives the
**copyable SHAPE** of an independent-oracle module for a standard-backed
computational target, so the multi-oracle (H1), committed-seeded-fuzz (H2), and
algorithm-vs-algorithm differential (H3) requirements at the `thorough` /
`exhaustive` evidence_floor can be satisfied by transcribing a known-good
structure instead of re-deriving it. See
[`test-authoring-guidance.md`](test-authoring-guidance.md) rules 1 / 3 / 7 and
[`evidence-channels.md`](evidence-channels.md) (EC-ORACLE / EC-DIFFERENTIAL /
EC-PROPERTY) for the obligations this shape satisfies.

A trustworthy oracle module has FOUR parts. An expected value is trusted only
when the first-principles formula and the independent library agree within
tolerance — neither alone is enough, because a single library silently shares
its own conventions.

## (a) First-principles block — the spec formula, NO library

Implement the published spec directly, with no dependency on the
implementation's core or on any third-party library. This is the channel that
is independent of EVERY library's conventions.

```js
// WCAG 2.x relative luminance / contrast, hand-implemented from the spec.
function srgbToLinear(c) { return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4; }
function relativeLuminanceFP(r8, g8, b8) {
  const r = srgbToLinear(r8 / 255), g = srgbToLinear(g8 / 255), b = srgbToLinear(b8 / 255);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
function contrastRatioFP(a, b) {
  const la = relativeLuminanceFP(...a), lb = relativeLuminanceFP(...b);
  const hi = Math.max(la, lb), lo = Math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}
```

## (b) Independent-library block — a DIFFERENT library than the SUT

Wrap a reference library that does NOT share the implementation's core (the SUT
uses culori → the oracle uses colorjs.io). This catches spec-implementation
mistakes the first-principles block might also make.

```js
import Color from 'colorjs.io';
const cjsContrast = (a, b) => new Color(a).contrast(new Color(b), 'WCAG21');
```

## (c) Seeded PRNG — reproducible fuzz

A deterministic PRNG seeded by a literal makes a fuzz run reproducible AND
exploratory. Commit the loop; do not hand-pick a grid.

```js
function makeRng(seed) {                          // mulberry32
  let a = seed >>> 0;
  return () => {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
// const rng = makeRng(101); for (let i = 0; i < 1000; i++) { /* assert invariant + oracle agree */ }
```

## (d) Second-algorithm differential helper — algorithm-vs-algorithm

Where a SECOND independent ALGORITHM for the same contract exists, expose it so
the test can compare algorithm-vs-algorithm within tolerance — a membership
check (`inGamut`) is necessary-not-sufficient, because a wrong result can still
be in-range.

```js
// colorjs.io CSS (MINDE) gamut mapping — a DIFFERENT algorithm than culori's clampChroma.
const cjsToGamutCssHex = (input) =>
  new Color(input).toGamut({ space: 'srgb', method: 'css' }).to('srgb').toString({ format: 'hex' });
const cjsDeltaEOK = (a, b) => new Color(a).deltaE(new Color(b), { method: 'ok' });
// expect(cjsDeltaEOK(engineResult, cjsToGamutCssHex(input))).toBeLessThan(0.1);
```

## Mutual validation before trust (H1)

```js
// The two independent oracles must agree BEFORE either is used as truth:
expect(Math.abs(contrastRatioFP(rgbA, rgbB) - cjsContrast(a, b))).toBeLessThan(2e-3);
// ...only then compare the implementation's RAW (pre-rounding) value against them.
```

## Degradation (fail-open)

Where the domain has no published spec, no second independent library, or no
second algorithm, use whichever channels DO exist and record a one-line Caveat —
the harness never fabricates an oracle, and a missing oracle is never a FAIL.
This shape is read at authoring time; it is not a runtime gate.
