import struct, zlib, os, sys

def _crypt_table():
    t = [0] * 0x500
    seed = 0x00100001
    for i in range(0x100):
        idx = i
        for j in range(5):
            seed = (seed * 125 + 3) % 0x2AAAAB
            a = (seed & 0xFFFF) << 16
            seed = (seed * 125 + 3) % 0x2AAAAB
            b = seed & 0xFFFF
            t[idx] = a | b
            idx += 0x100
    return t

CT = _crypt_table()

def hash_string(s, ht):
    s1, s2 = 0x7FED7FED, 0xEEEEEEEE
    for ch in s.upper().replace('/', '\\'):
        c = ord(ch)
        s1 = CT[(ht << 8) + c] ^ ((s1 + s2) & 0xFFFFFFFF)
        s2 = (c + s1 + s2 + (s2 << 5) + 3) & 0xFFFFFFFF
    return s1

def decrypt(data, key):
    out = bytearray()
    seed = 0xEEEEEEEE
    n = len(data) // 4
    vals = struct.unpack('<%dI' % n, data[:n * 4])
    res = []
    for v in vals:
        seed = (seed + CT[0x400 + (key & 0xFF)]) & 0xFFFFFFFF
        ch = v ^ ((key + seed) & 0xFFFFFFFF)
        key = ((((~key) << 0x15) + 0x11111111) | (key >> 0x0B)) & 0xFFFFFFFF
        seed = (ch + seed + (seed << 5) + 3) & 0xFFFFFFFF
        res.append(ch)
    return struct.pack('<%dI' % n, *res) + data[n * 4:]

# ---- PKWARE DCL explode ----
def explode(data):
    import io
    # minimal implementation based on blast.c (Mark Adler)
    pos = [0]
    bitbuf = [0]; bitcnt = [0]
    def bits(need):
        val = bitbuf[0]
        while bitcnt[0] < need:
            if pos[0] >= len(data): raise ValueError('eof')
            val |= data[pos[0]] << bitcnt[0]; pos[0] += 1; bitcnt[0] += 8
        bitbuf[0] = val >> need; bitcnt[0] -= need
        return val & ((1 << need) - 1)
    def construct(rep):
        lengths = []
        for b in rep:
            l = (b & 15) + 2; ln = (b >> 4) + 1
            lengths += [l] * ln
        # build canonical huffman (blast uses inverted bits)
        count = [0] * 14
        for l in lengths: count[l] += 1
        offs = [0] * 14
        for i in range(1, 13): offs[i + 1] = offs[i] + count[i]
        sym = [0] * len(lengths)
        for s, l in enumerate(lengths):
            sym[offs[l]] = s; offs[l] += 1
        return count, sym
    def decode(h):
        count, sym = h
        code = first = index = 0
        for l in range(1, 14):
            code |= bits(1) ^ 1
            c = count[l]
            if code < first + c: return sym[index + (code - first)]
            index += c; first += c; first <<= 1; code <<= 1
        raise ValueError('bad code')
    litlen = [11, 124, 8, 7, 28, 7, 188, 13, 76, 4, 10, 8, 12, 10, 12, 10, 8, 23, 8, 9, 7, 6, 7, 8, 7, 6, 55, 8, 23, 24, 12, 11, 7, 9, 11, 12, 6, 7, 22, 5, 7, 24, 6, 11, 9, 6, 7, 22, 7, 11, 38, 7, 9, 8, 25, 11, 8, 11, 9, 12, 8, 12, 5, 38, 5, 38, 5, 11, 7, 5, 6, 21, 6, 10, 53, 8, 7, 24, 10, 27, 44, 253, 253, 253, 252, 252, 252, 13, 12, 45, 12, 45, 12, 61, 12, 45, 44, 173]
    lenlen = [2, 35, 36, 53, 38, 23]
    distlen = [2, 20, 53, 230, 247, 151, 248]
    base = [3, 2, 4, 5, 6, 7, 8, 9, 10, 12, 16, 24, 40, 72, 136, 264]
    extra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8]
    litcode = construct(litlen); lencode = construct(lenlen); distcode = construct(distlen)
    lit = bits(8); dictb = bits(8)
    out = bytearray()
    while True:
        if bits(1):
            sym = decode(lencode)
            ln = base[sym] + bits(extra[sym])
            if ln == 519: break
            sym = 2 if ln == 2 else dictb
            dist = decode(distcode) << sym
            dist += bits(sym); dist += 1
            for _ in range(ln): out.append(out[-dist])
        else:
            out.append(decode(litcode) if lit else bits(8))
    return bytes(out)

def decompress(buf):
    m = buf[0]; d = buf[1:]
    if m == 0x02: return zlib.decompress(d)
    if m == 0x08: return explode(d)
    if m == 0x10:
        import bz2; return bz2.decompress(d)
    raise ValueError('compression %x' % m)

class MPQ:
    def __init__(self, path):
        self.f = open(path, 'rb')
        f = self.f
        off = 0
        while True:
            f.seek(off)
            if f.read(4) == b'MPQ\x1a': break
            off += 0x200
        self.base = off
        f.seek(off)
        hdr = f.read(32)
        _, hsz, asz, fmt, sec, htp, btp, hn, bn = struct.unpack('<4sIIHHIIII', hdr)
        self.sector = 512 << sec
        f.seek(off + htp); ht = decrypt(f.read(hn * 16), hash_string('(hash table)', 3))
        f.seek(off + btp); bt = decrypt(f.read(bn * 16), hash_string('(block table)', 3))
        self.hash = [struct.unpack_from('<IIHHI', ht, i * 16) for i in range(hn)]
        self.block = [struct.unpack_from('<IIII', bt, i * 16) for i in range(bn)]
        self.hn = hn

    def find(self, name):
        a = hash_string(name, 1); b = hash_string(name, 2); i = hash_string(name, 0) % self.hn
        start = i
        while True:
            h1, h2, loc, plat, bi = self.hash[i]
            if bi == 0xFFFFFFFF: return None
            if h1 == a and h2 == b and bi != 0xFFFFFFFE: return bi
            i = (i + 1) % self.hn
            if i == start: return None

    def read(self, name):
        bi = self.find(name)
        if bi is None: return None
        boff, csize, fsize, flags = self.block[bi]
        if not flags & 0x80000000: return None
        f = self.f
        f.seek(self.base + boff)
        raw = f.read(csize)
        if flags & 0x00010000: raise ValueError('encrypted')
        if flags & 0x01000000:  # single unit
            return decompress(raw) if (flags & 0x200 and csize < fsize) else raw
        if not (flags & 0x0000FF00):
            return raw[:fsize]
        ns = (fsize + self.sector - 1) // self.sector
        offs = struct.unpack_from('<%dI' % (ns + 1), raw)
        out = bytearray()
        for k in range(ns):
            chunk = raw[offs[k]:offs[k + 1]]
            want = min(self.sector, fsize - k * self.sector)
            if len(chunk) < want:
                if flags & 0x200: chunk = decompress(chunk)
                else: chunk = explode(chunk)
            out += chunk
        return bytes(out)

if __name__ == '__main__':
    d = sys.argv[1]; name = sys.argv[2]
    for fn in sorted(os.listdir(d)):
        if not fn.lower().endswith('.mpq'): continue
        try:
            m = MPQ(os.path.join(d, fn))
            bi = m.find(name)
            if bi is not None:
                print(fn, m.block[bi])
        except Exception as e:
            print(fn, 'ERR', e)
