# Accept-set conformance harness (executed grammar-complement sweep)

Binding parties: the `ac-evaluator` / `ac-evaluator-hi` (which EXECUTE the sweep
in scratch), and the `implementer` / `test-writer` (which commit the fixed
rejection test to the PRODUCT tests when the sweep finds a leak). This file gives
the **copyable SHAPE** of an executed accept-set conformance sweep so the
`## Failure-class panel` L-ROBUSTNESS accept-set obligation can be satisfied by
transcribing a known-good structure instead of re-deriving it. See
[`evidence-channels.md`](evidence-channels.md) (EC-METAMORPHIC) and
[`test-authoring-guidance.md`](test-authoring-guidance.md) rules 4 / 7 for the
obligations this shape satisfies.

The load-bearing element is **execution**: a contract that advertises strict /
canonical / lossless / limit is satisfied by READING, and live runs leaked
despite the prose contract existing — the only thing that catches a one-character
validator regression is the evaluator actually RUNNING the complement corpus
black-box against an INDEPENDENT spec oracle. Adding more prose does not raise
the catch-rate; running the sweep does.

The single worked module below uses **one** neutral, NON-colour domain (a strict
unsigned decimal integer bounded `[0, 255]`) purely to make the shape concrete
and copyable; that boundary is **illustrative only** — illustrative on both the
domain axis and the language axis, carrying no special status. Transcribe the
ROLES (the Grammar Card, the four MRs, the watchdog, the seeded corpus, the
independent oracle, the fail-open degradation) into whatever boundary your AC
actually inhabits.

## Trigger (when this sweep is mandatory)

Run the sweep when EITHER holds:
- the boundary's contract lexically advertises **strict / canonical / lossless /
  limit** (word-existence in the AC, its Implementation Notes, the docstring, the
  declared schema, or a `--help` line); OR
- a sibling unit accepts the **same input class** (the `shared_input_boundary`
  peer signal the planner / ticket-evaluator forward).

It is **always-on** — independent of the verification-depth tier, applied at
`standard` as well — gated only by `constraints.accept_set_conformance`
(`Accept-set conformance: {auto|off}` in the spawn prompt; absent → `auto`).

## Grammar Card — derive the axes from the AC/spec

Read the boundary's spec and fill the four axes; each axis drives one MR:

- **A — Alphabet**: the symbol set the boundary advertises (e.g. ASCII decimal
  digits `0-9`). Drives MR-ALPHABET.
- **U — Unicode transform**: any normalization / digit-folding the boundary
  applies before validation (e.g. NFC, a digit-folding numeric parse). Drives the
  astral span of MR-ALPHABET.
- **W — canonical Writer**: the single canonical output form the boundary
  promises (e.g. no leading zero). Drives MR-CANONICAL (parse-side: a
  non-canonical INPUT is rejected or normalized-idempotent) AND, when the
  boundary advertises **lossless / exact / round-trip** between a value-form and
  its canonical string-form, MR-ROUNDTRIP (write-side: an exactly-representable
  value must survive `parse(format(x)) == x`).
- **K — Keyed structure**: any map / record built from untrusted input. Drives
  MR-KEYFAITH.

## The independent oracle — SPEC-derived, never the unit's own validator

Hand-code the accept predicate from the SPEC. It MUST NOT call the unit's
validator, and MUST NOT lean on a language primitive that shares the bug class
(`int()` / `Number()` / `str.isdigit()` accept the whole Unicode decimal-digit
property, which is exactly the leak under test) — check character codes by hand.

```python
# ILLUSTRATIVE ONLY (neutral domain, Python): strict unsigned decimal octet [0,255].
# Oracle is SPEC-DERIVED and INDEPENDENT of the unit: hand char-code check,
# never int() / str.isdigit().
def oracle_accepts(s):
    if not isinstance(s, str) or len(s) == 0:
        return False
    for ch in s:
        if ord(ch) < 0x30 or ord(ch) > 0x39:        # ASCII digits only
            return False
    if len(s) > 1 and s[0] == '0':                   # canonical: no leading zero
        return False
    v = 0
    for ch in s:
        v = v * 10 + (ord(ch) - 0x30)
        if v > 255:                                  # MR-FINITE: bounded magnitude
            return False
    return True
```

## The four metamorphic relations + the generated corpus

```python
# ILLUSTRATIVE ONLY: build the complement corpus by PROPERTY, naming no script.
import unicodedata

def make_corpus():
    corpus = list('0 1 9 10 42 99 100 199 255'.split())          # in-set anchors
    corpus += ['256','300','00','01','0255','+1','-1','1.0','1e2','','  ','\t9']  # MR-FINITE / MR-CANONICAL
    bmp = astral = 0
    for cp in range(0x110000):                                   # MR-ALPHABET: iterate the codepoint space
        if 0x30 <= cp <= 0x39 or 0xD800 <= cp <= 0xDFFF:
            continue
        ch = chr(cp)
        if unicodedata.category(ch) == 'Nd':                     # select by the decimal-digit PROPERTY
            corpus.append(ch)                                    # every script's digits, BMP + astral
            astral += (cp > 0xFFFF)
            bmp += (cp <= 0xFFFF)
    return corpus, bmp, astral
```

- **MR-FINITE** — a parse-accepted input whose conversion overflows to a
  non-finite / out-of-range intermediate must be rejected (`256`, an
  overflowing magnitude). A hang under the watchdog is a FAIL.
- **MR-ALPHABET** — every member of the Unicode decimal-digit property complement
  (BMP **and** astral) that the spec's alphabet excludes must be rejected. The
  generator names NO script and hard-codes NO codepoint list; a non-zero astral
  count is the proof the complement actually crossed the BMP boundary.
- **MR-CANONICAL** — a structurally-valid-but-non-canonical form the canonical
  Writer would never emit (`01`, `0255`) must be rejected OR be
  normalized-idempotent (`f(f(x)) == f(x)` and `f(x)` is the canonical form).
- **MR-ROUNDTRIP** (the forward-direction W-axis counterpart to MR-CANONICAL) —
  when the boundary advertises **lossless / exact / round-trip** between a
  value-form and its canonical string-form, an exactly-representable value driven
  THROUGH the writer must round-trip: `parse(format(x)) == x` for every `x` the
  writer's grammar can represent exactly. The value corpus is generated from the
  writer's OWN grammar — each canonical anchor PLUS values sampled in the open
  interval between adjacent anchors, INCLUDING the just-below-next-anchor extreme
  where significant-figure / display rounding corrupts an exactly-representable
  value — the generator names no unit and hard-codes no value. The independent
  oracle is `parse` applied to the writer's output (round-trip identity), never
  `format`'s own internals. A representable `x` whose canonical output is lossy
  (`parse(format(x)) != x`) is subject to the SAME oracle-authoritative two-tier
  FAIL gating: FAIL when lossless / exact / canonical is advertised and the
  round-trip breaks on a representable `x`; ADVISORY when the output grammar
  genuinely cannot hold the value (a real cross-representation lossy case the
  writer documents). This catches the writer that rounds an exactly-representable
  value to a lossy canonical string — invisible to the parse-side MRs because the
  lossy output is a clean rc=0, not a parse false-accept.
- **MR-KEYFAITH** — a reserved / accessor / colliding key in a K-axis structure
  must not mutate host-structure metadata or be silently dropped. A CONCRETE
  round-trip-faithfulness violation (a drop, an overwrite, or a host-metadata
  mutation) is subject to the SAME oracle-authoritative two-tier FAIL gating as
  the other MRs (see [§ FAIL gating](#fail-gating--oracle-authoritative-two-tier-no-false-positive-storm)
  below): a violation on a lossless / strict keyed boundary the oracle
  authoritatively narrows is a FAIL; a legitimately-WIDE keyed boundary (arbitrary
  keys accepted by contract, last-write-wins, no protected metadata) is advisory
  (`authoritative=n`, a Caveat). The copyable shape for this class lives in
  [§ The worked MR-KEYFAITH (b) shape](#the-worked-mr-keyfaith-b-shape-reflection-derived-keyed-structure)
  below — a reflection-derived key generator paired with an independent
  round-trip-faithfulness oracle.

## The worked MR-KEYFAITH (b) shape reflection-derived keyed structure

The MR-ALPHABET module above derives its corpus from a **property** (the Unicode
decimal-digit category) and names no script or codepoint. The K-axis class needs
the same move so the self-elicited sweep DERIVES the dangerous keys instead of
naming literals: a hand-picked reserved-key list is the keyed-structure analogue
of hard-coding a per-script digit table — it tests only the keys the author
happened to recall, and the one that ships the leak is the one nobody listed.
This subsection gives MR-KEYFAITH the same copyable structure as MR-ALPHABET, for
a K-axis structure built from untrusted `(key, value)` input pairs. It is
**illustrative only** on both the domain axis and the language axis; transcribe
the ROLES (independent round-trip-faithfulness oracle; reflection-derived
generator; black-box diff), not the surface domain. Gating follows the shared two-tier gate (see the MR-KEYFAITH bullet
above): a concrete drop / overwrite / host-metadata mutation on a lossless /
strict keyed boundary the oracle authoritatively narrows is a FAIL; a
legitimately-wide keyed boundary is advisory.

The oracle is **round-trip-faithfulness** and is INDEPENDENT of the builder: it
reasons only from the input PAIRS and never calls the builder under test to
decide what is correct. The expectation is
computed from the INPUT PAIRS by last-write-wins; it is NEVER read back out of the
builder (the dogfood-50 trap:
deriving `expected` by re-invoking the builder makes the oracle circular — a
builder that drops a key would "agree with itself"). The round-trip leg below
re-runs the builder only to confirm SERIALIZE then BUILD stability; the truth it is
diffed against stays the pairs-derived mapping, never the builder's own output.

```python
# ILLUSTRATIVE ONLY (neutral domain, Python): round-trip faithfulness for a
# structure rebuilt from untrusted (key, value) pairs. SPEC-DERIVED and
# INDEPENDENT of the builder: the expectation is computed from the INPUT PAIRS by
# last-write-wins, never by asking the builder what it produced.
#   build(pairs) -> the structure under test;  get(struct, k) -> value or a
#   sentinel if absent;  serialize(struct) -> the structure's wire form.
def oracle_faithful(pairs, build, get, serialize, MISSING=object()):
    # 1. last-write-wins truth, derived only from the inputs.
    expected = {}
    for k, v in pairs:
        expected[k] = v                      # later pair for a repeated key wins
    built = build(pairs)
    # 2. every key the inputs asked for returns ITS value unchanged (no drop /
    #    overwrite / host-metadata bleed) — read back through the public getter.
    for k, want in expected.items():
        if get(built, k) != want:
            return False                     # silent drop or wrong-value overwrite
    # 3. round-trip: build(serialize(x)) preserves the same observable mapping.
    again = build(serialize(built))
    for k, want in expected.items():
        if get(again, k) != want:
            return False
    return True
```

The generator DERIVES the host structure's own reserved / accessor key names BY
REFLECTION at runtime and names no key literal — exactly as MR-ALPHABET selects
by the decimal-digit PROPERTY and names no script. The reflected set MUST include
the structure's own private / internal slot names (the leading-underscore /
name-mangled / non-public attribute names), not only its public methods and
dunders — a private-slot collision (an input key that shadows the structure's own
internal storage slot) is a real drop / overwrite class, and reflection already
exposes those names, so enumerate the FULL reflected set, never a truncated or
sliced subset. The reflection API calls
(below) are introspection plumbing, not key literals; the dangerous names are
whatever the live host happens to expose, so the source stays decontaminated.

```python
# ILLUSTRATIVE ONLY: derive the hostile key corpus BY REFLECTION over the live
# host structure — name NO key literal. The accessor / reserved names are read
# off the runtime type at sweep time, so this generator is portable across hosts
# and stays free of any product-specific key denylist.
#
#   JS  illustration : keys = new Set(Object.getOwnPropertySymbols(target));
#                      for (let p = target; p; p = Object.getPrototypeOf(p))
#                        Object.getOwnPropertyNames(p).forEach(n => keys.add(n));
#                      // climb the ancestor chain via getPrototypeOf to its root,
#                      // adding each level's own names — names the accessor /
#                      // reserved set by reflection, no literal.
#   Py  illustration : as below, via dir(type(target)) over the live type
def reflect_hostile_keys(target):
    keys = set()
    t = type(target)
    keys.update(dir(t))                       # the type's own method + dunder names
    for base in t.__mro__:                    # walk the resolution order to the root
        keys.update(vars(base).keys())        # each ancestor's own attribute names
    return keys

def make_key_corpus(target, existing_keys):
    hostile = reflect_hostile_keys(target)    # reflection-derived accessor names
    generic = set()
    generic.add('')                           # empty key (generic structural hostile)
    if existing_keys:
        generic.add(next(iter(existing_keys)))  # duplicate of an existing key
    # a key that COLLIDES only after the structure's own normalization (the
    # structure decides the fold; we derive a colliding partner from an existing
    # key rather than naming a literal collision pair).
    for k in existing_keys:
        if isinstance(k, str) and k != k.casefold():
            generic.add(k.casefold())         # normalized-collision partner
            break
    return hostile | generic
```

Run the REAL builder black-box over `make_key_corpus(...)` as `(key, value)`
pairs (synthetic values, so the only variable is the key), then DIFF against
`oracle_faithful`. A non-faithful build — a reflection-derived accessor name that
overwrites host-structure metadata, an empty / duplicate / normalized-collision
key that silently drops a value, or a round-trip that loses a mapping — is the
catch; name the offending class in Feedback so the producer round can pin it. A
faithful builder returns a clean zero over the whole reflected corpus (no
false-positive storm), because the oracle accepts exactly the last-write-wins
mapping the inputs demanded.

## The worked MR-ROUNDTRIP shape forward-direction canonical-writer losslessness

MR-CANONICAL above checks the PARSE side (a non-canonical INPUT is rejected or
normalized). MR-ROUNDTRIP is its FORWARD counterpart: it drives an
exactly-representable VALUE through the REAL writer and checks the canonical
string round-trips. The miss it closes is a writer that applies
significant-figure / display rounding to a value that is exactly representable in
its own output grammar — `format(x)` returns a lossy string at a clean rc=0, so
the parse-side MRs (which only diff accept/reject of INPUTS) never see it. The
corpus is generated from the writer's OWN grammar and names no value: each
canonical anchor PLUS values sampled in the open interval between adjacent
anchors, INCLUDING the just-below-next-anchor extreme — the largest magnitude
still representable in the lower-granularity output term before the writer
switches term/scale, which is exactly where round-to-N-significant-figures
corrupts an exactly-representable value. It is **illustrative only** on both the
domain and language axes; transcribe the ROLES (grammar-derived anchor +
inter-anchor sampling; the REAL writer; the independent `parse` inverse oracle;
the black-box round-trip diff), never the surface domain.

```python
# ILLUSTRATIVE ONLY (neutral domain, Python): forward round-trip losslessness for
# a writer that renders a non-negative integer into a compact canonical string and
# a parser that reads it back. The writer ADVERTISES lossless round-trip. The
# generator derives the corpus from the writer's OWN grammar — naming no literal
# value — and the oracle is `parse` applied to the writer's output (round-trip
# identity), INDEPENDENT of format's internals.
def make_value_corpus(anchors, between):
    # anchors: the exact representable points the writer emits crisply (each
    #   scale/term multiple), derived from the grammar — not a hard-coded list.
    # between(a, b): yields interior values in (a, b), INCLUDING b-1 (the largest
    #   magnitude still in the lower-granularity term before the writer switches
    #   scale) — exactly where significant-figure rounding fires.
    corpus = list(anchors)
    for a, b in zip(anchors, anchors[1:]):
        corpus += list(between(a, b))            # interior incl. just-below-next-anchor
    return corpus

def run_writer_roundtrip(format_fn, parse_fn, value_corpus):
    # drive each representable value through the REAL writer, parse it back, and
    # FAIL when parse(format(x)) != x for an x the grammar represents exactly.
    lossy = []
    for x in value_corpus:
        s = format_fn(x)                         # the REAL writer boundary
        back = parse_fn(s)                       # independent inverse (round-trip identity)
        if back != x:
            lossy.append((x, s, back))           # an exactly-representable value the writer rounded
    return lossy
```

A non-empty `lossy` on a writer that advertises lossless / exact / round-trip is
the catch — name the offending value class in Feedback so the producer round can
pin it. A writer that genuinely cannot hold the value (a documented
cross-representation lossy case) is advisory (`authoritative=n`), under the same
two-tier gate as the other MRs. A correct lossless writer returns a clean empty
`lossy` over the whole grammar-derived corpus.

## Black-box diff under a watchdog (the executed step)

```python
# ILLUSTRATIVE ONLY: drive the corpus through the REAL boundary, diff vs oracle.
# A SIGKILL watchdog turns a hang into a FAIL (MR-FINITE DoS arm). The seed makes
# any random extension reproducible (mulberry32 in JS; random.Random(seed) here).
def run_sweep(unit_accepts, corpus):
    false_accepts, false_rejects, threw = [], [], []
    for s in corpus:
        want = oracle_accepts(s)
        try:
            got = unit_accepts(s)            # the REAL public boundary, never an internal handler
        except Exception:
            threw.append(s); continue
        if got and not want:                 # candidate accept-set DIVERGENCE
            false_accepts.append(s)
        if (not got) and want:
            false_rejects.append(s)
    return false_accepts, false_rejects, threw
```

## FAIL gating — oracle-authoritative two-tier (NO false-positive storm)

A non-empty `false_accepts` is only a candidate. Gate the verdict on whether the
hand-coded oracle is AUTHORITATIVE for this boundary:

- **FAIL** the AC only when the oracle authoritatively reflects a spec that is
  STRICTLY NARROWER than the unit's accept-set — the advertised contract is
  narrow and explicit (e.g. "ASCII digits only", "no leading zero",
  "bounded [0,N]"). A narrow-spec false-accept the oracle rejects is the leak;
  name the leaking class in Feedback so the producer round can pin it. Emit
  `authoritative=y` on the marker.
- **ADVISORY only (PASS-WITH-CAVEATS, never force-FAIL)** when the advertised
  width is NOT unambiguously narrower than what the unit accepts — the boundary
  is legitimately or arguably WIDE (Unicode-aware, locale-flexible,
  list-format-tolerant). Here the oracle, not the unit, is the suspect: record
  the divergence as `[MEDIUM]` Feedback and a Caveat. Emit `authoritative=n`.

On a CORRECT narrow unit the sweep is a clean zero (the false-positive-storm
absent check the worked example demonstrates by construction).

## Two-surface retention (who commits what)

- **Evaluator (read-only)**: the sweep above runs in `.simple-workflow/scratch/`
  and is **discarded** after the round; the evaluator cannot write PRODUCT tests.
  It records the divergence in Feedback, the persisted `## Accept-set sweep`
  report section, and the `[ACCEPT-SET-SWEEP]` marker.
- **Producer (`implementer` / `test-writer`)**: when the evaluator's Feedback
  reports an accept-set leak, the next round commits a **fixed rejection
  characterization test** to the PRODUCT tests (the leaking input as a RED case;
  the validator fix is GREEN) so the regression is locked in the committed suite.

## No-runnable-artifact caveat (compiled languages)

When the unit is a COMPILED-language artifact you cannot run black-box (the
evaluator allowlist grants `node` / `python3` but, for Rust/Go, only
`cargo test` / `go test` — no `rustc` / `cargo run` / `go run` / built binary),
you cannot drive the corpus through the real boundary. Run the oracle alone,
record what divergence you CAN derive statically, set
`caveat=no-runnable-artifact` on the marker, and record a one-line Caveat —
never a force-FAIL.

## Degradation (fail-open)

Four fail-open arms — the harness never fabricates an oracle and a missing /
non-authoritative oracle is never a FAIL:

1. **No trigger**: the boundary advertises no strict / canonical / lossless /
   limit contract and no same-input-class sibling exists — the sweep is `n/a`.
2. **No runnable artifact**: a compiled unit with no runnable binary — oracle
   alone, `caveat=no-runnable-artifact`, Caveat.
3. **No spec**: the domain has no spec to hand-code an oracle from — use whichever
   channels DO exist and record a Caveat.
4. **Wide-but-spec-correct**: the spec PERMITS a wider accept-set than the oracle
   encodes (the boundary is advertised flexible / Unicode-aware /
   locale-tolerant) — do NOT force-FAIL on `false_accepts` the oracle rejects;
   the oracle, not the unit, is the suspect. Downgrade to advisory
   (`authoritative=n`) and record a Caveat.

This shape is read at evaluation time to drive an EXECUTED sweep; the producer
half is read at authoring time.
