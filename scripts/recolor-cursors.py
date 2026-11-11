#!/usr/bin/env python3
"""Recolour an Xcursor theme (Bibata Modern Classic) into Midnight Pulse colours.
usage: recolor-cursors.py <source theme dir> <output theme dir>
Dark fill -> deep navy gradient-ish (#0D1630..#1A2A55), light outline -> accent (#5FD0FF)."""
import struct, sys, shutil, os
from pathlib import Path

src, out = Path(sys.argv[1]), Path(sys.argv[2])
FILL_DARK, FILL_LIGHT = (13, 22, 48), (34, 58, 120)
EDGE = (95, 208, 255)


def remap(b, g, r, a):
    if a == 0:
        return b, g, r, a
    lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255
    if lum > 0.55:                      # outline / highlights -> accent
        t = (lum - 0.55) / 0.45
        nr = int(EDGE[0] * (0.75 + 0.25 * t)); ng = int(EDGE[1] * (0.75 + 0.25 * t)); nb = int(EDGE[2] * (0.85 + 0.15 * t))
    else:                               # body -> navy
        t = lum / 0.55
        nr = int(FILL_DARK[0] + (FILL_LIGHT[0] - FILL_DARK[0]) * t)
        ng = int(FILL_DARK[1] + (FILL_LIGHT[1] - FILL_DARK[1]) * t)
        nb = int(FILL_DARK[2] + (FILL_LIGHT[2] - FILL_DARK[2]) * t)
    # Xcursor stores premultiplied ARGB
    f = a / 255
    return int(min(255, nb * f)), int(min(255, ng * f)), int(min(255, nr * f)), a


def recolor(data: bytes) -> bytes:
    if data[:4] != b'Xcur':
        return data
    buf = bytearray(data)
    header, version, ntoc = struct.unpack_from('<III', buf, 4)
    for i in range(ntoc):
        typ, subtype, pos = struct.unpack_from('<III', buf, 16 + i * 12)
        if typ != 0xfffd0002:           # image chunk
            continue
        hdr, ctype, csub, cver, w, h, xhot, yhot, delay = struct.unpack_from('<IIIIIIIII', buf, pos)
        p = pos + hdr
        for k in range(w * h):
            o = p + k * 4
            b, g, r, a = buf[o], buf[o + 1], buf[o + 2], buf[o + 3]
            if a:
                # un-premultiply first
                f = a / 255
                ub, ug, ur = min(255, int(b / f)), min(255, int(g / f)), min(255, int(r / f))
                buf[o], buf[o + 1], buf[o + 2], buf[o + 3] = remap(ub, ug, ur, a)
    return bytes(buf)


if out.exists():
    shutil.rmtree(out)
(out / 'cursors').mkdir(parents=True)
done = 0
for f in sorted((src / 'cursors').iterdir()):
    dst = out / 'cursors' / f.name
    if f.is_symlink():
        os.symlink(os.readlink(f), dst)
    else:
        dst.write_bytes(recolor(f.read_bytes()))
        done += 1
(out / 'index.theme').write_text('[Icon Theme]\nName=Midnight Pulse Cursors\nComment=Bibata Modern recoloured for Midnight Pulse\nInherits=hicolor\n')
print('recoloured', done, 'cursor files')
