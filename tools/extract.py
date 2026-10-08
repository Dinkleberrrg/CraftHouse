import os, sys, re
from mpq import MPQ
DATA = r"D:\Games\OctoWoW - HD Upgrade\Data"
PREFIX = "DBFilesClient" + chr(92)


def order(fn):
    l = fn.lower()
    if l == 'dbc.mpq':
        return (0, '')
    if l == 'patch.mpq':
        return (1, '')
    m = re.match(r'patch-(\w)\.mpq$', l)
    if m:
        c = m.group(1)
        return (2, c) if c.isdigit() else (3, c)
    return None


files = sorted([f for f in os.listdir(DATA) if order(f)], key=order)
print("order:", files)
for name in sys.argv[1:]:
    got = None
    for fn in files:
        try:
            m = MPQ(os.path.join(DATA, fn))
            if m.find(PREFIX + name) is not None:
                got = (fn, m.read(PREFIX + name))
        except Exception as e:
            print(fn, 'ERR', e)
    if got:
        open(name, 'wb').write(got[1])
        print(name, 'from', got[0], len(got[1]))
    else:
        print(name, 'NOT FOUND')
