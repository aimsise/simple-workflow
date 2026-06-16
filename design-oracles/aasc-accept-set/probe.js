'use strict';
// AASC confidence probe (JS). Boundary: strict unsigned decimal octet [0,255].
// Advertised accept-set: ASCII digits only, canonical (no leading zero),
// no sign / whitespace / radix prefix, value 0..255.
// The oracle is SPEC-DERIVED and INDEPENDENT of both impls: it does a hand
// char-code check and never calls Number()/parseInt — so it cannot share an
// impl's parsing convention.

// ---- Independent spec oracle (no library, no impl reuse) ----
function oracleAccepts(s) {
  if (typeof s !== 'string' || s.length === 0) return false;
  for (const ch of s) {                 // for..of iterates by code point (astral-safe)
    const cp = ch.codePointAt(0);
    if (cp < 0x30 || cp > 0x39) return false;   // ASCII digits only
  }
  if (s.length > 1 && s[0] === '0') return false; // canonical: no leading zero
  let v = 0;
  for (const ch of s) { v = v * 10 + (ch.codePointAt(0) - 0x30); if (v > 255) return false; }
  return true;
}

// ---- Impls under test ----
function implCorrect(s) {
  return /^(0|[1-9][0-9]{0,2})$/.test(s) && Number(s) <= 255;
}
function implBuggy(s) {                  // "looks numeric and in range" shortcut
  const n = Number(s);
  return Number.isInteger(n) && n >= 0 && n <= 255;
}

// ---- GENERATIVE corpus (grammar/property-driven; NAMES NO SCRIPT) ----
const corpus = [];
const add = (s) => corpus.push(s);
['0','1','9','10','42','99','100','199','255'].forEach(add);                        // ascii accepts
['256','300','999','00','01','0255','+1','-1','1.0','1e2','0x1f','0b1','1_0','',' 12','12 ','  ','\t9'].forEach(add); // ascii rejects
// Unicode decimal-digit COMPLEMENT sweep: every codepoint that is \p{Nd}
// but NOT ASCII 0-9. Enumerated by PROPERTY — recalls no script name.
let ndBmp = 0, ndAstral = 0;
for (let cp = 0; cp <= 0x10FFFF; cp++) {
  if (cp >= 0xD800 && cp <= 0xDFFF) continue;   // lone surrogates
  if (cp >= 0x30 && cp <= 0x39) continue;       // exclude ASCII
  const ch = String.fromCodePoint(cp);
  if (/\p{Nd}/u.test(ch)) { add(ch); if (cp > 0xFFFF) ndAstral++; else ndBmp++; }
}
['²','Ⅰ','½','〇'].forEach(add);  // non-Nd numeric lookalikes (must reject)

// ---- Run + diff vs oracle ----
function run(impl) {
  const fa = [], fr = [], threw = [];
  for (const s of corpus) {
    const want = oracleAccepts(s);
    let got;
    try { got = impl(s); } catch (_) { threw.push(s); continue; }
    if (got && !want) fa.push(s);
    if (!got && want) fr.push(s);
  }
  return { fa, fr, threw };
}
const hex = (s) => [...s].map(c => 'U+' + c.codePointAt(0).toString(16).toUpperCase().padStart(4, '0')).join('');
const sample = (a, n) => a.slice(0, n).map(s => JSON.stringify(s) + '(' + hex(s) + ')').join(', ');

const rb = run(implBuggy), rc = run(implCorrect);
console.log('== JS probe :: boundary = strict unsigned decimal octet [0,255] ==');
console.log('corpus size:', corpus.length, '| nd-nonascii BMP:', ndBmp, 'astral:', ndAstral);
console.log('-- BUGGY impl (Number()+range shortcut) --');
console.log('  false-accepts (leak caught by oracle):', rb.fa.length);
console.log('  sample:', sample(rb.fa, 14));
const buggyAstral = rb.fa.filter(s => [...s].some(c => c.codePointAt(0) > 0xFFFF));
console.log('  astral among catches:', buggyAstral.length);
console.log('-- CORRECT impl (regex+value) --');
const dis = rc.fa.length + rc.fr.length + rc.threw.length;
console.log('  disagreements with oracle:', dis, '->', dis === 0 ? 'false-positive-storm ABSENT (0)' : 'STORM PRESENT');
console.log('VERDICT JS: buggy caught =', rb.fa.length > 0, '| correct clean =', dis === 0);
