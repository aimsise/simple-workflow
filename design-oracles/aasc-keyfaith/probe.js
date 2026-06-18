'use strict';
// AASC MR-KEYFAITH confidence probe (JS). Class (b): a KEYED structure rebuilt
// from untrusted (key, value) input pairs. Advertised contract: round-trip
// faithfulness — every key the inputs asked for returns ITS value unchanged
// (last-write-wins for a repeated key), no silent drop, no host-metadata bleed,
// and build(serialize(x)) preserves the same observable mapping.
//
// The oracle is SPEC-DERIVED and INDEPENDENT of every builder: it computes the
// expectation from the INPUT PAIRS by last-write-wins and NEVER reads it back out
// of a builder (the circular-oracle trap). The key generator names NO key literal:
// it DERIVES the dangerous accessor / reserved / private names BY REFLECTION over
// the live host structures, exactly as the (c) probe selects digits by the Unicode
// decimal-digit PROPERTY and names no script.
//
// Two self-consistent comparisons share one corpus of reflected keys:
//   FLAT  — obj[k]=v, oracle = flat last-write-wins map.
//   DEEP  — a nested "k.split('.')" deep-assign variant, oracle = deep
//           last-write-wins map. Each oracle matches its builders' key model, so a
//           CORRECT builder is a clean zero in both.

const MISSING = Symbol('MISSING');

// ===================== FLAT comparison =====================

// Independent flat oracle: expectation from the INPUT PAIRS by last-write-wins.
function oracleFlat(pairs, build, get, serialize) {
  const expected = new Map();
  for (const [k, v] of pairs) expected.set(k, v);    // later pair for a repeated key wins
  const built = build(pairs);
  for (const [k, want] of expected) {
    if (get(built, k) !== want) return false;        // silent drop or wrong-value overwrite
  }
  const again = build(serialize(built));             // round-trip: serialize then build
  for (const [k, want] of expected) {
    if (get(again, k) !== want) return false;
  }
  return true;
}

// CORRECT: a null-prototype container — no inherited accessor / reserved slot can
// be shadowed or mutated; every own key round-trips.
function buildFlatCorrect(pairs) {
  const o = Object.create(null);
  for (const [k, v] of pairs) o[String(k)] = v;      // last-write-wins
  return o;
}
// BUGGY: a plain {} — an accessor / reserved name (read off the live host by
// reflection) can shadow a prototype slot, return the inherited value, or mutate
// host-structure metadata instead of storing the pair.
function buildFlatBuggy(pairs) {
  const o = {};                                      // inherits the host object prototype
  for (const [k, v] of pairs) o[String(k)] = v;
  return o;
}
function getFlat(o, k) {
  return Object.prototype.hasOwnProperty.call(o, k) ? o[k] : MISSING;  // own-property read only
}
function serializeFlat(o) {
  return Object.keys(o).map(k => [k, o[k]]);          // own enumerable wire form
}

// ===================== DEEP comparison =====================

// Independent deep oracle: nested last-write-wins map keyed by "k.split('.')".
function setDeep(map, segs, v) {
  let cur = map;
  for (let i = 0; i < segs.length - 1; i++) {
    const s = segs[i];
    if (!(cur.get(s) instanceof Map)) cur.set(s, new Map());
    cur = cur.get(s);
  }
  cur.set(segs[segs.length - 1], v);
}
function getDeep(map, segs) {
  let cur = map;
  for (let i = 0; i < segs.length - 1; i++) {
    const s = segs[i];
    if (!(cur instanceof Map) || !cur.has(s)) return MISSING;
    cur = cur.get(s);
  }
  return (cur instanceof Map && cur.has(segs[segs.length - 1])) ? cur.get(segs[segs.length - 1]) : MISSING;
}
function oracleDeep(pairs, build, getPath, serialize) {
  const expected = new Map();
  for (const [k, v] of pairs) setDeep(expected, String(k).split('.'), v);
  const built = build(pairs);
  const want = [];
  (function walk(m, prefix) {
    for (const [k, v] of m) {
      if (v instanceof Map) walk(v, prefix.concat(k));
      else want.push([prefix.concat(k), v]);
    }
  })(expected, []);
  for (const [segs, v] of want) {
    if (getPath(built, segs) !== v) return false;
  }
  const again = build(serialize(built));
  for (const [segs, v] of want) {
    if (getPath(again, segs) !== v) return false;
  }
  return true;
}

// CORRECT deep: null-proto at every level — no reserved slot collision.
function buildDeepCorrect(pairs) {
  const root = Object.create(null);
  for (const [k, v] of pairs) {
    const segs = String(k).split('.');
    let cur = root;
    for (let i = 0; i < segs.length - 1; i++) {
      const s = segs[i];
      if (typeof cur[s] !== 'object' || cur[s] === null) cur[s] = Object.create(null);
      cur = cur[s];
    }
    cur[segs[segs.length - 1]] = v;
  }
  return root;
}
// BUGGY deep: deep-assign onto plain {} — a reserved segment pollutes / shadows.
function buildDeepBuggy(pairs) {
  const root = {};
  for (const [k, v] of pairs) {
    const segs = String(k).split('.');
    let cur = root;
    for (let i = 0; i < segs.length - 1; i++) {
      const s = segs[i];
      if (typeof cur[s] !== 'object' || cur[s] === null) cur[s] = {};
      cur = cur[s];
    }
    cur[segs[segs.length - 1]] = v;
  }
  return root;
}
function getDeepPath(root, segs) {
  let cur = root;
  for (let i = 0; i < segs.length - 1; i++) {
    const s = segs[i];
    if (typeof cur !== 'object' || cur === null || !Object.prototype.hasOwnProperty.call(cur, s)) return MISSING;
    cur = cur[s];
  }
  const last = segs[segs.length - 1];
  return (typeof cur === 'object' && cur !== null && Object.prototype.hasOwnProperty.call(cur, last)) ? cur[last] : MISSING;
}
function serializeDeep(root) {
  const out = [];
  (function walk(o, prefix) {
    for (const k of Object.keys(o)) {
      const v = o[k];
      if (v && typeof v === 'object' && !Array.isArray(v)) walk(v, prefix.concat(k));
      else out.push([prefix.concat(k).join('.'), v]);
    }
  })(root, []);
  return out;
}

// ===================== REFLECTION-DERIVED key generator (NAMES NO KEY LITERAL) =====================
// Climb the prototype chain of live host structures, collecting every own property
// name + symbol at every level. The accessor / reserved / private slot names are
// whatever the runtime exposes — no denylist, no hard-coded key.
function reflectHostileKeys() {
  const keys = new Set();
  for (const target of [{}, new Map(), []]) {
    for (let p = target; p; p = Object.getPrototypeOf(p)) {
      for (const n of Object.getOwnPropertyNames(p)) keys.add(n);
      for (const s of Object.getOwnPropertySymbols(p)) keys.add(s);
    }
  }
  return keys;
}
function makeKeyCorpus(existingKeys) {
  const hostile = reflectHostileKeys();              // reflection-derived accessor / reserved names
  const generic = new Set();
  generic.add('');                                   // empty key (generic structural hostile)
  if (existingKeys.length) generic.add(existingKeys[0]);  // duplicate of an existing key
  for (const k of existingKeys) {                    // normalized-collision partner, no literal pair
    if (typeof k === 'string' && k !== k.normalize('NFC')) { generic.add(k.normalize('NFC')); break; }
  }
  return [...hostile, ...generic].filter(k => typeof k === 'string'); // symbols have no string wire form
}

// Synthetic-value pairs; the candidate key is the only variable (+ a repeat for
// last-write-wins). Benign anchors must always round-trip.
const seedKeys = ['alpha', 'beta'];
const hostileKeys = makeKeyCorpus(seedKeys);
const flatPairs = (k) => [['alpha', 1], ['beta', 2], [k, 'V:' + k], [k, 'V2:' + k]];
const deepPairs = (k) => [['x.alpha', 1], ['x.beta', 2], [k, 'V:' + k], [k, 'V2:' + k]];

function run(build, get, serialize, oracle, pairsFor) {
  const violations = [];
  for (const k of hostileKeys) {
    let ok;
    try { ok = oracle(pairsFor(k), build, get, serialize); }
    catch (_) { violations.push({ k, reason: 'threw' }); continue; }
    if (!ok) violations.push({ k, reason: 'unfaithful' });
  }
  return violations;
}

const flatBuggyV = run(buildFlatBuggy, getFlat, serializeFlat, oracleFlat, flatPairs);
const flatCorrectV = run(buildFlatCorrect, getFlat, serializeFlat, oracleFlat, flatPairs);
const deepBuggyV = run(buildDeepBuggy, getDeepPath, serializeDeep, oracleDeep, deepPairs);
const deepCorrectV = run(buildDeepCorrect, getDeepPath, serializeDeep, oracleDeep, deepPairs);

const hex = (k) => [...k].map(c => 'U+' + c.codePointAt(0).toString(16).toUpperCase().padStart(4, '0')).join('');
const sample = (a, n) => a.slice(0, n).map(x => JSON.stringify(x.k) + '(' + hex(x.k) + ',' + x.reason + ')').join(', ');

console.log('== JS probe :: class (b) MR-KEYFAITH — keyed structure round-trip faithfulness ==');
console.log('reflection-derived hostile keys (string-serializable):', hostileKeys.length, '| names no key literal in generator');
console.log('-- BUGGY builder (plain {} + obj[k]=v, flat) --');
console.log('  faithfulness violations (caught by oracle):', flatBuggyV.length);
console.log('  sample:', sample(flatBuggyV, 8));
console.log('-- BUGGY builder (deep-assign onto plain {}) --');
console.log('  faithfulness violations (caught by oracle):', deepBuggyV.length);
console.log('  sample:', sample(deepBuggyV, 8));
console.log('-- CORRECT builder (Object.create(null), flat) --');
console.log('  oracle disagreements:', flatCorrectV.length, '->', flatCorrectV.length === 0 ? 'false-positive-storm ABSENT (0)' : 'STORM PRESENT');
console.log('-- CORRECT builder (deep null-proto) --');
console.log('  oracle disagreements:', deepCorrectV.length, '->', deepCorrectV.length === 0 ? 'false-positive-storm ABSENT (0)' : 'STORM PRESENT');
const buggyCaught = flatBuggyV.length > 0 && deepBuggyV.length > 0;
const correctClean = flatCorrectV.length + deepCorrectV.length;
console.log('VERDICT JS: buggy caught =', buggyCaught, '| correct clean =', correctClean);
