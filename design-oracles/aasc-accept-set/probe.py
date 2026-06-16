# AASC confidence probe (Python). Same boundary: strict unsigned decimal octet [0,255].
# Oracle is SPEC-DERIVED and INDEPENDENT of both impls: hand char-code check,
# never calls int()/str.isdigit().
import unicodedata, json

def oracle_accepts(s):
    if not isinstance(s, str) or len(s) == 0:
        return False
    for ch in s:
        if ord(ch) < 0x30 or ord(ch) > 0x39:   # ASCII digits only
            return False
    if len(s) > 1 and s[0] == '0':              # canonical: no leading zero
        return False
    v = 0
    for ch in s:
        v = v * 10 + (ord(ch) - 0x30)
        if v > 255:
            return False
    return True

import re
_pat = re.compile(r'(0|[1-9][0-9]{0,2})')       # ASCII literals -> ASCII-only by construction
def impl_correct(s):
    return _pat.fullmatch(s) is not None and int(s) <= 255

def impl_buggy(s):                               # "looks like digits and in range" shortcut
    return s.isdigit() and 0 <= int(s) <= 255

# GENERATIVE corpus (property-driven; names no script)
corpus = []
for s in ['0','1','9','10','42','99','100','199','255']:
    corpus.append(s)
for s in ['256','300','999','00','01','0255','+1','-1','1.0','1e2','0x1f','','  ',' 12','12 ','\t9']:
    corpus.append(s)
nd_bmp = nd_astral = 0
for cp in range(0x110000):
    if 0x30 <= cp <= 0x39 or 0xD800 <= cp <= 0xDFFF:
        continue
    ch = chr(cp)
    if unicodedata.category(ch) == 'Nd':        # Unicode decimal digit, non-ASCII
        corpus.append(ch)
        if cp > 0xFFFF:
            nd_astral += 1
        else:
            nd_bmp += 1
for s in ['²', 'Ⅰ', '½', '〇']:   # non-Nd numeric lookalikes
    corpus.append(s)

def run(impl):
    fa, fr, threw = [], [], []
    for s in corpus:
        want = oracle_accepts(s)
        try:
            got = impl(s)
        except Exception:
            threw.append(s)
            continue
        if got and not want:
            fa.append(s)
        if (not got) and want:
            fr.append(s)
    return fa, fr, threw

def hexs(s):
    return ''.join('U+%04X' % ord(c) for c in s)
def sample(a, n):
    return ', '.join(json.dumps(x) + '(' + hexs(x) + ')' for x in a[:n])

fb, frb, tb = run(impl_buggy)
fc, frc, tc = run(impl_correct)
print('== PY probe :: boundary = strict unsigned decimal octet [0,255] ==')
print('corpus size:', len(corpus), '| nd-nonascii BMP:', nd_bmp, 'astral:', nd_astral)
print('-- BUGGY impl (str.isdigit()+int()+range) --')
print('  false-accepts (leak caught by oracle):', len(fb))
print('  sample:', sample(fb, 14))
astral_caught = [s for s in fb if any(ord(c) > 0xFFFF for c in s)]
print('  ASTRAL among catches:', len(astral_caught), ('(e.g. ' + sample(astral_caught, 3) + ')') if astral_caught else '')
print('  threw (robustness defect, e.g. int() on digit-ish non-Nd):', len(tb), ('(e.g. ' + sample(tb, 4) + ')') if tb else '')
print('-- CORRECT impl (ascii regex + value) --')
dis = len(fc) + len(frc) + len(tc)
print('  disagreements with oracle:', dis, '->', 'false-positive-storm ABSENT (0)' if dis == 0 else 'STORM PRESENT')
print('VERDICT PY: buggy caught =', len(fb) > 0, '| ASTRAL leak caught =', len(astral_caught) > 0, '| correct clean =', dis == 0)
