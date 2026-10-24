"""Minimal reader for Project Zomboid texture packs (.pack): extracts named sprites (e.g. Item_*) as PNG bytes.

    from packread import read_pack
    sprites = read_pack(path, want=lambda name: name.startswith('Item_'))   # {name: png bytes}

Handles both layouts seen in the game: the old one (page count first) and the "PZPK" one. Each page holds a list of
entries (name, x, y, w, h, offsets) followed by the page's PNG; sprites are cropped out of that PNG.
"""
import io, struct

_PNG = bytes([0x89]) + b"PNG" + bytes([0x0D, 0x0A, 0x1A, 0x0A])


from PIL import Image


class _R:
    def __init__(self, data):
        self.d, self.p = data, 0

    def i32(self):
        v = struct.unpack_from('<i', self.d, self.p)[0]
        self.p += 4
        return v

    def s(self):
        n = self.i32()
        v = self.d[self.p:self.p + n].decode('utf8', 'replace')
        self.p += n
        return v

    def bytes(self, n):
        v = self.d[self.p:self.p + n]
        self.p += n
        return v


def read_pack(path, want=lambda name: True):
    r = _R(open(path, 'rb').read())
    if r.d[:4] == b'PZPK':
        r.p = 4
        r.i32()                      # version
    pages = r.i32()
    out = {}
    for _ in range(pages):
        r.s()                        # page name
        count = r.i32()
        r.i32()                      # page flag
        entries = []
        for _ in range(count):
            name = r.s()
            x, y, w, h, ox, oy, fx, fy = (r.i32() for _ in range(8))
            entries.append((name, x, y, w, h))
        if r.d[r.p:r.p + 8] == _PNG:     # the older layout (UI.pack...): the PNG follows at once, a marker after it
            q = r.p + 8
            while True:
                n = struct.unpack_from('>I', r.d, q)[0]
                kind = r.d[q + 4:q + 8]
                q += 12 + n
                if kind == b'IEND':
                    break
            png = r.bytes(q - r.p)
            if r.p + 4 <= len(r.d) and struct.unpack_from('<i', r.d, r.p)[0] == -559038737:   # 0xDEADBEEF page marker
                r.p += 4
        else:
            size = r.i32()
            png = r.bytes(size)
        wanted = [e for e in entries if want(e[0])]
        if not wanted:
            continue
        img = Image.open(io.BytesIO(png)).convert('RGBA')
        for name, x, y, w, h in wanted:
            buf = io.BytesIO()
            img.crop((x, y, x + w, y + h)).save(buf, 'PNG')
            out[name] = buf.getvalue()
    return out
