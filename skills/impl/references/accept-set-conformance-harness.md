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
  promises (e.g. no leading zero). Drives MR-CANONICAL.
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
- **MR-KEYFAITH** — *(ASSUMED, not proven)* a reserved / accessor / colliding key
  in a K-axis structure must not mutate host-structure metadata or be silently
  dropped. The structural-key reflection this hypothesises is unverified; treat
  an MR-KEYFAITH divergence as advisory unless a concrete drop / mutation is
  observed.

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
