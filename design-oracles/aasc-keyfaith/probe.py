# AASC MR-KEYFAITH confidence probe (Python). Class (b): a KEYED structure rebuilt
# from untrusted (key, value) input pairs. Advertised contract: round-trip
# faithfulness — every key the inputs asked for returns ITS value unchanged
# (last-write-wins for a repeated key), no silent drop, no internal-slot bleed,
# and build(serialize(x)) preserves the same observable mapping.
#
# The oracle is SPEC-DERIVED and INDEPENDENT of both builders: it computes the
# expectation from the INPUT PAIRS by last-write-wins and NEVER reads it back out
# of a builder (the circular-oracle trap). The key generator names NO key literal:
# it DERIVES the dangerous reserved / accessor / private-slot names BY REFLECTION
# over the live type (dir + the __mro__ vars walk), exactly as the (c) probe
# selects digits by the Unicode decimal-digit PROPERTY and names no script.
import json

_MISSING = object()


# ---- Independent round-trip-faithfulness oracle (no builder reuse) ----
# `expected` is derived ONLY from the input pairs (last-write-wins). It is never
# read out of a builder, so a builder that drops a key cannot "agree with itself".
def oracle_faithful(pairs, build, get, serialize):
    expected = {}
    for k, v in pairs:
        expected[k] = v                          # later pair for a repeated key wins
    built = build(pairs)
    for k, want in expected.items():
        if get(built, k) != want:                # silent drop or wrong-value overwrite
            return False
    again = build(serialize(built))              # round-trip: serialize then build
    for k, want in expected.items():
        if get(again, k) != want:
            return False
    return True


# ---- Builders under test ----
# BUGGY: a class that does setattr per pair into ATTRIBUTE space — an input key
# that collides with the class's own reserved / accessor / private slot name (read
# off the live type by reflection) overwrites that slot or is shadowed by it,
# instead of being stored as data. Reads come back through getattr.
class _AttrStore:
    def __init__(self, pairs):
        for k, v in pairs:
            setattr(self, str(k), v)             # last-write-wins, but pollutes attribute space


def build_buggy(pairs):
    return _AttrStore(pairs)


def get_buggy(store, k):
    return getattr(store, k, _MISSING)


def serialize_buggy(store):
    # wire form = the instance's own __dict__ items (data attributes only).
    return list(vars(store).items())


# CORRECT: a dict-backed store — keys live in a data namespace that cannot collide
# with the type's reserved / accessor / private slots; every key round-trips.
class _DictStore:
    def __init__(self, pairs):
        self._d = {}
        for k, v in pairs:
            self._d[str(k)] = v                  # last-write-wins, isolated namespace


def build_correct(pairs):
    return _DictStore(pairs)


def get_correct(store, k):
    return store._d.get(k, _MISSING)


def serialize_correct(store):
    return list(store._d.items())


# ---- REFLECTION-DERIVED key generator (NAMES NO KEY LITERAL) ----
# Read the reserved / accessor / private-slot names off the live types by
# reflection — dir(type(target)) plus walking type(target).__mro__ and collecting
# each base's vars(base) keys. This INCLUDES private / internal slot names
# (leading-underscore / name-mangled / dunder); no name is hard-coded.
def reflect_hostile_keys():
    keys = set()
    for target in ({}, [], _AttrStore([]), _DictStore([])):  # live host structures
        t = type(target)
        keys.update(dir(t))                       # the type's own method + accessor + dunder names
        for base in t.__mro__:                    # walk the resolution order to the root
            keys.update(vars(base).keys())        # each ancestor's own attribute names (incl private slots)
    return keys


def make_key_corpus(existing_keys):
    hostile = reflect_hostile_keys()              # reflection-derived reserved / accessor / private names
    generic = set()
    generic.add('')                               # empty key (generic structural hostile)
    if existing_keys:
        generic.add(next(iter(existing_keys)))    # duplicate of an existing key
    # normalized-collision partner: derived from an existing key, no literal pair.
    for k in existing_keys:
        if isinstance(k, str) and k != k.casefold():
            generic.add(k.casefold())
            break
    return hostile | generic


seed_keys = ['alpha', 'Beta']                     # benign anchors that must always round-trip
hostile_keys = sorted(k for k in make_key_corpus(seed_keys) if isinstance(k, str))


def pairs_for(k):
    # benign anchors + candidate key (synthetic value) + repeated key (last-write-wins).
    return [('alpha', 1), ('Beta', 2), (k, 'V:' + k), (k, 'V2:' + k)]


def run(build, get, serialize):
    violations = []
    for k in hostile_keys:
        pairs = pairs_for(k)
        try:
            ok = oracle_faithful(pairs, build, get, serialize)
        except Exception as e:
            violations.append((k, 'threw:' + type(e).__name__))
            continue
        if not ok:
            violations.append((k, 'unfaithful'))
    return violations


def hexs(s):
    return ''.join('U+%04X' % ord(c) for c in s)


def sample(a, n):
    return ', '.join(json.dumps(k) + '(' + hexs(k) + ',' + r + ')' for k, r in a[:n])


buggy_v = run(build_buggy, get_buggy, serialize_buggy)
correct_v = run(build_correct, get_correct, serialize_correct)
priv_caught = [(k, r) for k, r in buggy_v if k.startswith('_')]

print('== PY probe :: class (b) MR-KEYFAITH — keyed structure round-trip faithfulness ==')
print('reflection-derived hostile keys:', len(hostile_keys), '| names no key literal in generator')
print('-- BUGGY builder (setattr into attribute space) --')
print('  faithfulness violations (caught by oracle):', len(buggy_v))
print('  sample:', sample(buggy_v, 10))
print('  private/internal-slot collisions among catches:', len(priv_caught),
      ('(e.g. ' + sample(priv_caught, 4) + ')') if priv_caught else '')
print('-- CORRECT builder (dict-backed store) --')
dis = len(correct_v)
print('  oracle disagreements:', dis, '->',
      'false-positive-storm ABSENT (0)' if dis == 0 else 'STORM PRESENT')
print('VERDICT PY: buggy caught =', len(buggy_v) > 0,
      '| private-slot leak caught =', len(priv_caught) > 0,
      '| correct clean =', dis == 0)
