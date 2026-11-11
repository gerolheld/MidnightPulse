#!/usr/bin/env python3
"""Re-colour the static parts of Midnight Pulse to a theme hue.

   recolor.py H O S NAME

H — hue (°) the Midnight accent #1EB0EA (197°) maps to, O — hue offset of the partner colour
(+29° in the original), S — saturation multiplier, NAME — preset id or "custom".
Same transform as Palette.qml and the wallpaper shader. Called by midnight-pulse-audiod whenever a
preset or custom colour is chosen. Pristine sources live in ~/.local/share/midnight-pulse/base
(copied there by install.py); every run writes fresh, uniquely named variants and applies them so
Plasma/KWin actually reload (re-applying the same name is a no-op for them).
"""
import colorsys, json, re, shutil, subprocess, sys, time
from pathlib import Path

H = Path.home()
L = H / '.local/share'
BASE = L / 'midnight-pulse/base'
h0, o0, s0 = (float(a) for a in sys.argv[1:4])
name = sys.argv[4] if len(sys.argv) > 4 else 'custom'
identity = abs(h0 - 197) < 0.01 and abs(o0 - 29) < 0.01 and abs(s0 - 1) < 0.001


def tx_rgb(r, g, b):
    """0..255 ints → transformed 0..255 ints (blue family only)."""
    hv, sv, vv = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    if sv < 1e-4:
        return r, g, b
    rel = ((hv * 360 - 197) % 360 + 540) % 360 - 180
    if abs(rel) > 75:
        return r, g, b
    nh = ((h0 + rel * o0 / 29) % 360) / 360
    nr, ng, nb = colorsys.hsv_to_rgb(nh, min(1.0, sv * s0), vv)
    return round(nr * 255), round(ng * 255), round(nb * 255)


HEX = re.compile(r'#([0-9A-Fa-f]{6})([0-9A-Fa-f]{2})?\b')
RGBF = re.compile(r'(rgba?\()\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)')
TRIPLE = re.compile(r'(?<![\d.])(\d{1,3}),(\d{1,3}),(\d{1,3})(?![\d.])')   # .colors / konsole / aurorae rc
BARE = re.compile(r'^(\s*[\w-]+\s*=\s*)([0-9A-Fa-f]{6})\s*$', re.M)        # spicetify color.ini


def recolor_text(t, triples=False, bare=False):
    def hx(m):
        r, g, b = (int(m.group(1)[i:i + 2], 16) for i in (0, 2, 4))
        return '#%02X%02X%02X' % tx_rgb(r, g, b) + (m.group(2) or '')
    t = HEX.sub(hx, t)
    t = RGBF.sub(lambda m: m.group(1) + '%d,%d,%d' % tx_rgb(*(int(m.group(i)) for i in (2, 3, 4))), t)
    if triples:
        t = TRIPLE.sub(lambda m: '%d,%d,%d' % tx_rgb(*(int(m.group(i)) for i in (1, 2, 3)))
                       if max(int(m.group(i)) for i in (1, 2, 3)) <= 255 else m.group(0), t)
    if bare:
        t = BARE.sub(lambda m: m.group(1) + '%02X%02X%02X' % tx_rgb(*(int(m.group(2)[i:i + 2], 16) for i in (0, 2, 4))), t)
    return t


def recolor_tree(src, dst, renames=()):
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(src, dst)
    for f in dst.rglob('*'):
        if not f.is_file():
            continue
        if f.suffix == '.svg':
            f.write_text(recolor_text(f.read_text()))
        elif f.suffix == '.svgz':
            import gzip
            f.write_bytes(gzip.compress(recolor_text(gzip.decompress(f.read_bytes()).decode()).encode()))
        elif f.name == 'colors' or f.name.endswith('rc') or f.suffix == '.colors':
            f.write_text(recolor_text(f.read_text(), triples=True))
    for old, new in renames:
        for f in list(dst.rglob(old)):
            f.rename(f.with_name(new))


def sh(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def kw(file, group, key, value):
    sh('kwriteconfig6', '--file', file, '--group', group, '--key', key, value)


# a unique suffix each run, so Plasma/KWin see a "new" theme and reload it
tag = 'MidnightPulse' if identity else f'MidnightPulse-{name}-{int(time.time()) % 100000}'
pretty = 'Midnight Pulse' if identity else f'Midnight Pulse · {name.capitalize()}'

# ---- colour scheme -------------------------------------------------------------------------
cs_src = BASE / 'color-schemes/MidnightPulse.colors'
cs = recolor_text(cs_src.read_text(), triples=True)
cs = re.sub(r'^Name=.*$', f'Name={pretty}', cs, flags=re.M)
(L / 'color-schemes').mkdir(parents=True, exist_ok=True)
(L / f'color-schemes/{tag}.colors').write_text(cs)

# ---- Plasma style --------------------------------------------------------------------------
dt = L / f'plasma/desktoptheme/{tag}'
if not identity:
    recolor_tree(BASE / 'desktoptheme/MidnightPulse', dt)
    meta = json.loads((dt / 'metadata.json').read_text())
    meta['KPlugin']['Id'] = tag
    meta['KPlugin']['Name'] = pretty
    (dt / 'metadata.json').write_text(json.dumps(meta, indent=2, ensure_ascii=False))

# ---- window decoration ---------------------------------------------------------------------
au = L / f'aurorae/themes/{tag}'
if not identity:
    recolor_tree(BASE / 'aurorae/MidnightPulse', au, renames=[('MidnightPulserc', f'{tag}rc')])
    meta = json.loads((au / 'metadata.json').read_text())
    meta['KPlugin']['Id'] = f'__aurorae__svg__{tag}'
    meta['KPlugin']['Name'] = pretty
    (au / 'metadata.json').write_text(json.dumps(meta, indent=2, ensure_ascii=False))
    md = au / 'metadata.desktop'
    if md.exists():
        t = md.read_text().replace('__aurorae__svg__MidnightPulse', f'__aurorae__svg__{tag}')
        md.write_text(re.sub(r'^Name=.*$', f'Name={pretty}', t, flags=re.M))

# ---- apps (overwritten in place; they reload on their own or on next start) ----------------
apps = {
    BASE / 'apps/MidnightPulse.colorscheme': L / 'konsole/MidnightPulse.colorscheme',
    BASE / 'apps/midnight-pulse.toml': H / '.config/alacritty/midnight-pulse.toml',
    BASE / 'apps/cava.config': H / '.config/cava/config',
    BASE / 'apps/MidnightPulse.theme.css': H / '.config/vesktop/themes/MidnightPulse.theme.css',
    BASE / 'apps/spicetify-color.ini': H / '.config/spicetify/Themes/MidnightPulse/color.ini',
    BASE / 'apps/spicetify-user.css': H / '.config/spicetify/Themes/MidnightPulse/user.css',
}
for src, dst in apps.items():
    if src.exists() and dst.parent.exists():
        dst.write_text(recolor_text(src.read_text(), triples=src.suffix == '.colorscheme', bare=src.suffix == '.ini'))

# ---- cursor (Xcursor image chunks only; headers untouched) ---------------------------------
def recolor_xcursor(data, cache):
    import struct
    from array import array
    if data[:4] != b'Xcur':
        return data
    buf = bytearray(data)
    ntoc = struct.unpack_from('<I', buf, 12)[0]
    for i in range(ntoc):
        typ, _sub, pos = struct.unpack_from('<III', buf, 16 + i * 12)
        if typ != 0xfffd0002:
            continue
        hdr, _t, _s, _v, w, h = struct.unpack_from('<IIIIII', buf, pos)
        p0, p1 = pos + hdr, pos + hdr + w * h * 4
        px = array('I'); px.frombytes(bytes(buf[p0:p1]))
        out = array('I', (cache[v] if v in cache else cache.setdefault(v, tx_argb(v)) for v in px))
        buf[p0:p1] = out.tobytes()
    return bytes(buf)


def tx_argb(v):
    a = v >> 24
    if not a:
        return v
    f = a / 255                                   # Xcursor pixels are premultiplied
    r = min(255, round(((v >> 16) & 255) / f)); g = min(255, round(((v >> 8) & 255) / f)); b = min(255, round((v & 255) / f))
    r, g, b = tx_rgb(r, g, b)
    return (a << 24) | (round(r * f) << 16) | (round(g * f) << 8) | round(b * f)


cursor = 'MidnightPulse-Cursors' if identity else tag.replace('MidnightPulse', 'MidnightPulse-Cursors', 1)
cur_src = BASE / 'cursors/MidnightPulse-Cursors'
if not identity and cur_src.exists():
    import os
    cache = {}
    for root in (L / 'icons', H / '.icons'):
        dst = root / cursor
        if dst.exists():
            shutil.rmtree(dst)
        (dst / 'cursors').mkdir(parents=True)
        for f in sorted((cur_src / 'cursors').iterdir()):
            t = dst / 'cursors' / f.name
            if f.is_symlink():
                os.symlink(os.readlink(f), t)
            elif root == L / 'icons':
                t.write_bytes(recolor_xcursor(f.read_bytes(), cache))
            else:                                  # ~/.icons copy = same bytes as the one just written
                t.write_bytes((L / 'icons' / cursor / 'cursors' / f.name).read_bytes())
        (dst / 'index.theme').write_text(f'[Icon Theme]\nName={pretty} Cursors\nComment=Bibata Modern in Midnight Pulse colours\nInherits=hicolor\n')

# ---- apply ---------------------------------------------------------------------------------
r, g, b = tx_rgb(30, 176, 234)
# Each reload costs plasmashell/KWin ~0.1 s of main-thread work; back to back they stacked into a ~0.35 s
# freeze of every animation. Spaced out, each one is a single dropped frame or two.
GAP = 0.45
kw('kdeglobals', 'General', 'AccentColor', f'{r},{g},{b}')
sh('plasma-apply-colorscheme', tag)
time.sleep(GAP)
for f in (H / '.cache').glob('plasma_theme_MidnightPulse*'):
    f.unlink(missing_ok=True)
sh('plasma-apply-desktoptheme', tag)
time.sleep(GAP)
kw('kwinrc', 'org.kde.kdecoration2', 'theme', f'__aurorae__svg__{tag}')
sh('qdbus6', 'org.kde.KWin', '/KWin', 'reconfigure')
sh('pkill', '-USR2', '-x', 'cava')            # cava reloads its colours on SIGUSR2
time.sleep(GAP)
sh('plasma-apply-cursortheme', cursor)

# ---- drop older variants (but never the one in use) ----------------------------------------
time.sleep(2)
for d in list((L / 'plasma/desktoptheme').glob('MidnightPulse-*')) + list((L / 'aurorae/themes').glob('MidnightPulse-*')):
    if d.name != tag:
        shutil.rmtree(d, ignore_errors=True)
for root in (L / 'icons', H / '.icons'):
    for d in root.glob('MidnightPulse-Cursors-*'):
        if d.name != cursor:
            shutil.rmtree(d, ignore_errors=True)
for f in (L / 'color-schemes').glob('MidnightPulse-*.colors'):
    if f.stem != tag:
        f.unlink(missing_ok=True)
print('recoloured →', tag)
