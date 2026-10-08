import struct, re

def load(path):
    d = open(path, 'rb').read()
    _, n, nf, rs, ss = struct.unpack('<4sIIII', d[:20])
    strings = d[20 + n * rs:]
    rows = []
    for i in range(n):
        rows.append(struct.unpack_from('<%dI' % nf, d, 20 + i * rs))
    def s(off):
        e = strings.find(b'\0', off)
        return strings[off:e].decode('utf-8', 'replace')
    return rows, s

def f32(u):
    return struct.unpack('<f', struct.pack('<I', u))[0]

def i32(u):
    return struct.unpack('<i', struct.pack('<I', u))[0]

srows, sstr = load('Spell.dbc')
SPELL = {r[0]: r for r in srows}
ctrows, _ = load('SpellCastTimes.dbc')
CAST = {r[0]: i32(r[1]) for r in ctrows}
durrows, _ = load('SpellDuration.dbc')
DUR = {r[0]: i32(r[1]) for r in durrows}

def name(sid): r = SPELL[sid]; return sstr(r[120])
def rank(sid): r = SPELL[sid]; return sstr(r[129])
def desc(sid): r = SPELL[sid]; return sstr(r[138])
def tip(sid): r = SPELL[sid]; return sstr(r[147])

def eff(sid, k):
    r = SPELL[sid]
    return dict(effect=r[61 + k], die=i32(r[64 + k]), dice=i32(r[67 + k]), bp=i32(r[76 + k]),
                aura=r[91 + k], amp=r[94 + k], misc=i32(r[106 + k]), itemtype=r[103 + k],
                trig=r[109 + k], mult=f32(r[97 + k]), dmgmult=f32(r[167 + k]))

def s_val(sid, k):
    e = eff(sid, k)
    return e['bp'] + max(e['dice'], 1) if e['die'] <= 1 else (e['bp'] + 1, e['bp'] + e['die'])

def resolve(sid, text):
    def rep(m):
        ref, var, idx = m.group(1), m.group(2), int(m.group(3))
        t = int(ref) if ref else sid
        if t not in SPELL: return m.group(0)
        if var in ('s', 'm'):
            v = s_val(t, idx - 1)
            if isinstance(v, tuple): return '%d-%d' % v
            return str(abs(v))
        if var == 'o':
            e = eff(t, idx - 1); d = DUR.get(SPELL[t][30], 0)
            return str(abs(e['bp'] + 1) * (d // e['amp'] if e['amp'] else 1))
        if var == 'd':
            return '%ds' % (DUR.get(SPELL[t][30], 0) // 1000)
        if var == 't':
            return '%g' % (eff(t, idx - 1)['amp'] / 1000)
        return m.group(0)
    text = re.sub(r'\$(\d*)([smotd])(\d)', rep, text)
    text = re.sub(r'\$d', lambda m: '%ds' % (DUR.get(SPELL[sid][30], 0) // 1000), text)
    return text
