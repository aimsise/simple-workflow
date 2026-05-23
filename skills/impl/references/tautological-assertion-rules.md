# Tautological Assertion Rules

Canonical detection rules for tautological (always-true) assertions in test
files. Binding parties: the `ac-evaluator` agent. The agent loads this file
during every evaluation round and rejects any test file that violates a rule
unless the file carries an explicit hint comment (see `## Hint Expressions`).

The rules are deliberately language- and framework-agnostic at the canonical
level. Concrete `BAD` / `GOOD` snippets in this file appear inside fenced
example blocks and are illustrative only.

## Rules

### R1: Reference Equality of the Same Symbol

A test asserts that an expression equals itself, either because the two
operands are the same identifier text or because they resolve to the same
runtime reference. Such an assertion can never observe a regression — it
holds vacuously regardless of the system under test.

Canonical signature: `assert_equal(X, X)` where `X` and `Y` denote the same
symbol (identifier-level or reference-level).

First-stage detection (grep-based): operand text on both sides of an
equality assertion is the **same identifier token** (e.g. the same variable
name appearing twice).

<example lang="javascript">
BAD:
  const arr = [1, 2, 3];
  expect(arr).toEqual(arr);   // R1: same identifier on both sides

GOOD:
  const expected = [1, 2, 3];
  const actual = subject.snapshot();
  expect(actual).toEqual(expected);
</example>

### R2: Vacuous Numeric Boundary

A test asserts a numeric bound that is trivially true given the type of the
value (or the bound is the absolute extremum of the numeric domain). The
assertion conveys no information about the system under test.

Canonical signature: `assert_compare(X, op, K)` where `K` is the type-bound
extremum for `op` (e.g. `>= 0` for an unsigned counter, `<= MAX_VALUE`,
`> -Infinity`).

First-stage detection (grep-based): the right-hand side is a **constant
literal** known to be a vacuous extremum (`0`, `Number.MAX_VALUE`,
`-Infinity`, `Infinity`, `Number.MIN_SAFE_INTEGER`, `Number.MAX_SAFE_INTEGER`).
If the right-hand side is a non-literal expression (a variable, a property
access, a function call, etc.), the rule does NOT fire — see Limitations.

<example lang="javascript">
BAD:
  expect(finalSize).toBeGreaterThanOrEqual(0);             // R2: 0 is vacuous for unsigned size
  expect(elapsed).toBeLessThanOrEqual(Number.MAX_VALUE);   // R2: MAX_VALUE is the type extremum
  expect(score).toBeGreaterThan(-Infinity);                // R2: -Infinity is the domain extremum

GOOD:
  expect(finalSize).toBeGreaterThanOrEqual(initialSize);   // bound is a meaningful variable
  expect(elapsed).toBeLessThan(timeoutMs);                 // bound is a non-constant threshold
</example>

### R3: Constant-Only Boolean Assertion

A test asserts the truthiness of a value that is statically a constant
boolean, or of an expression that has been forced to a constant by an
algebraic short-circuit (`X || true`, `X && false`, etc.).

Canonical signature: `assert_truthy(K)` or `assert_falsy(K)` where `K` is a
literal boolean or an expression that statically reduces to one.

First-stage detection (grep-based):
- Both sides of an equality assertion are boolean literals
  (`expect(true).toBe(true)`, `expect(false).toBe(false)`).
- A truthiness assertion wraps a literal boolean
  (`expect(true).toBeTruthy()`, `expect(false).toBeFalsy()`).
- The asserted expression contains the short-circuit pattern `|| true)` or
  `&& false)` at its top level.

<example lang="javascript">
BAD:
  expect(true).toBe(true);                 // R3: constant boolean both sides
  expect(false).toBeFalsy();               // R3: constant literal under truthiness
  expect(flag || true).toBe(true);         // R3: short-circuit forces the constant

GOOD:
  expect(predicate(input)).toBe(true);     // truthiness of a real computation
  expect(state.isReady).toBeTruthy();      // truthiness of a non-literal value
</example>

## Hint Expressions

A test file MAY exempt itself from R1 (and only R1, since R2 and R3 have no
legitimate same-file-wide override) by carrying any of the following marker
comments anywhere in the file. Detection skips the entire file when a hint
is found.

- `// intentional reference equality test`
- `// intentional reference identity test`
- `// reference-equality: intentional`
- `# intentional reference equality test` (Python-style line comment)

These strings are matched literally and case-sensitively. Do NOT use the
hint as a blanket "disable detector" — it MUST describe a real
reference-identity contract that the test exists to verify (e.g. the system
under test is `Object.is`, a cache returning the same instance, or a
singleton accessor).

## Limitations

The first-stage implementation is **grep-based** and runs through the
ac-evaluator's text-inspection tools (`Read`, `Grep`, `Glob`). It catches the
common forms above by literal pattern matching. It deliberately does not
attempt the following, which would require AST analysis or program
reasoning that no `Read` / `Grep` / `Glob` workflow can deliver:

- **Variable resolution**: `expect(a).toEqual(b)` where `a` and `b` are
  distinct identifier tokens that nevertheless bind to the same object at
  runtime (alias chains, destructured references, returned-twice values).
- **Type inference**: `expect(unsignedCounter).toBeGreaterThanOrEqual(min)`
  where `min` is statically the type-floor — detection requires knowing the
  static type of the operand.
- **Cross-file analysis**: a constant exported from another module that
  evaluates to a vacuous extremum (e.g. `import { MIN } from './const'; ...
  toBeGreaterThanOrEqual(MIN)` where `MIN === 0`).
- **Algebraic simplification beyond the literal short-circuit**: e.g.
  `expect(x === x).toBe(true)`, `expect(NaN !== NaN).toBe(true)`, or
  arbitrary tautologies expressed through nested logical operators.
- **Framework-specific helper detection**: assertion helpers that wrap
  `expect(...)` in a project-local matcher are not unwrapped.

These cases remain out-of-scope for the first stage and are tracked as
future work; closing them requires introducing AST tooling to the
evaluator's allowed-tool surface.
