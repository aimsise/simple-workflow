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

The four-part contract below is the canonical, domain-agnostic shape. The single
worked module under each part uses **one** neutral domain (deriving a calendar
date / weekday from a day-number) purely to make the shape concrete and
copyable; that domain is **illustrative only** — it is not a recommended target
and carries no special status. Transcribe the ROLES (a)/(b)/(c)/(d), the
mutual-validation rule, and the fail-open degradation into whatever domain your
AC actually inhabits.

A trustworthy oracle module has FOUR parts. An expected value is trusted only
when the first-principles formula and the independent library agree within
tolerance — neither alone is enough, because a single library silently shares
its own conventions.

## (a) First-principles block — the spec formula, NO library

Implement the published spec / definition directly, with no dependency on the
implementation's core or on any third-party library. This is the channel that
is independent of EVERY library's conventions.

```js
// ILLUSTRATIVE ONLY (neutral domain): proleptic-Gregorian date from a day-number,
// hand-implemented from the published civil-from-days algorithm. No library.
function civilFromDaysFP(z) {                       // z = days since 1970-01-01
  z += 719468;
  const era = Math.floor((z >= 0 ? z : z - 146096) / 146097);
  const doe = z - era * 146097;                     // [0, 146096]
  const yoe = Math.floor((doe - Math.floor(doe / 1460) + Math.floor(doe / 36524) - Math.floor(doe / 146096)) / 365);
  const y = yoe + era * 400;
  const doy = doe - (365 * yoe + Math.floor(yoe / 4) - Math.floor(yoe / 100));
  const mp = Math.floor((5 * doy + 2) / 153);       // [0, 11], March-based
  const d = doy - Math.floor((153 * mp + 2) / 5) + 1;
  const m = mp < 10 ? mp + 3 : mp - 9;
  return { year: m <= 2 ? y + 1 : y, month: m, day: d };
}
```

## (b) Independent-library block — a DIFFERENT library than the SUT

Wrap a reference library that does NOT share the implementation's core (if the
SUT rolls its own date math, the oracle reaches for a maintained datetime
library; if the SUT already depends on that library, pick a different one). This
catches spec-implementation mistakes the first-principles block might also make.

```js
// ILLUSTRATIVE ONLY: a maintained datetime library as the independent reference.
import { DateTime } from 'luxon';
const libCivilFromDays = (z) => {
  const { year, month, day } = DateTime.fromMillis(z * 86400000, { zone: 'utc' });
  return { year, month, day };
};
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
// const rng = makeRng(101);
// for (let i = 0; i < 1000; i++) {
//   const z = Math.floor((rng() - 0.5) * 2_000_000);   // wide, reproducible day-number sweep
//   /* assert the invariant holds AND every oracle channel agrees on civilFromDays(z) */
// }
```

## (d) Second-algorithm differential helper — algorithm-vs-algorithm

Where a SECOND independent ALGORITHM for the same contract exists, expose it so
the test can compare algorithm-vs-algorithm within tolerance (or exactly, for
integer-valued contracts). A bare **membership / range** check (e.g. "the result
is a valid-only value within range" — the analogue of asserting a point is
in-range rather than the right point) is necessary-not-sufficient, because a
wrong result can still land inside the valid set: a containment invariant such as
"the mapped point stays within the allowed range / region" (the kind a gamut or
color-space membership test expresses) catches out-of-range escapes but never a
mere mis-mapping inside the boundary.

```js
// ILLUSTRATIVE ONLY: Zeller's congruence — a DIFFERENT algorithm for the weekday
// than counting days-mod-7 off the epoch. Exact agreement is expected (integer contract).
function zellerWeekday({ year, month, day }) {       // 0 = Saturday … 6 = Friday
  let m = month, y = year;
  if (m < 3) { m += 12; y -= 1; }
  const K = y % 100, J = Math.floor(y / 100);
  return (day + Math.floor(13 * (m + 1) / 5) + K + Math.floor(K / 4) + Math.floor(J / 4) + 5 * J) % 7;
}
const weekdayFromEpoch = (z) => ((((z % 7) + 7) % 7) + 4) % 7;   // 1970-01-01 was a Thursday
// const civ = civilFromDaysFP(z);
// expect((zellerWeekday(civ) + 1) % 7).toBe(weekdayFromEpoch(z));   // re-base Zeller's Sat=0 to Sun=0
```

## Mutual validation before trust (H1)

```js
// The two independent oracles must agree BEFORE either is used as truth:
expect(civilFromDaysFP(z)).toEqual(libCivilFromDays(z));   // or toBeCloseTo within tolerance for float contracts
// ...only then compare the implementation's RAW (pre-rounding / pre-canonicalisation) value against them.
```

## Degradation (fail-open)

Where the domain has no published spec, no second independent library, or no
second algorithm, use whichever channels DO exist and record a one-line Caveat —
the harness never fabricates an oracle, and a missing oracle is never a FAIL.
This shape is read at authoring time; it is not a runtime gate.
