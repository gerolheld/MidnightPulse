#!/usr/bin/env python3
"""Generate the Midnight Pulse Plasma Style (9-slice glass frames, blur masks, glow shadows)."""
from pathlib import Path
import json, shutil

P = Path(__file__).resolve().parents[1]
OUT = P / 'src/plasma/desktoptheme/MidnightPulse'

# ---- palette ---------------------------------------------------------------
BG, PANEL, SURF = (7, 11, 24), (13, 22, 48), (17, 29, 61)
ACCENT, ACCENT2, TEXT, MUTED = (30, 176, 234), (61, 107, 255), (220, 232, 255), (127, 147, 184)


def rgba(c, a): return f'rgb({c[0]},{c[1]},{c[2]})', a


class Svg:
    def __init__(self):
        self.defs, self.body, self.y = [], [], 0

    def grad(self, gid, stops, x2=0, y2=1, radial=False, cx=1, cy=1, r=1):
        s = ''.join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o, c, a in stops)
        if radial:
            self.defs.append(f'<radialGradient id="{gid}" cx="{cx}" cy="{cy}" r="{r}" gradientUnits="objectBoundingBox">{s}</radialGradient>')
        else:
            self.defs.append(f'<linearGradient id="{gid}" x1="0" y1="0" x2="{x2}" y2="{y2}">{s}</linearGradient>')

    def text(self):
        self.body.append('<rect id="hint-stretch-borders" x="0" y="0" width="1" height="1" fill="none" stroke="none"/>') if 'hint-stretch-borders' not in ''.join(self.body) else None
        return ('<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="400" height="%d">'
                '<defs>%s</defs>%s</svg>' % (max(400, self.y + 20), ''.join(self.defs), ''.join(self.body)))


def frame(svg, prefix, R, fill, stroke=None, glow=None, inner=None, bw=1.0):
    """Add a 9-slice frame built from explicit per-piece geometry (KSvg ignores clip paths).
    fill/stroke: (rgb, alpha) tuples or gradient-factory callables taking (y0, y1) -> 'url(#id)'."""
    ox, oy = 10, svg.y + 10
    E = 8
    W = R * 2 + E
    def paint(v, y0, y1, kind):
        if v is None: return f'{kind}="none"'
        if callable(v): return f'{kind}="{v(y0, y1)}"'
        return f'{kind}="{v[0]}" {kind}-opacity="{v[1]}"'
    F = paint(fill, oy, oy + W, 'fill')
    S = paint(stroke, oy, oy + W, 'stroke') if stroke else None
    h = bw / 2
    def piece(pid, x, y, w, ht, content):
        svg.body.append(f'<g id="{prefix}{pid}"><rect x="{x}" y="{y}" width="{w}" height="{ht}" fill="none" stroke="none"/>{content}</g>')
    x0, x1, x2, x3 = ox, ox + R, ox + R + E, ox + W
    y0, y1, y2, y3 = oy, oy + R, oy + R + E, oy + W
    S = S.replace('stroke', 'fill') if S else None   # border is drawn as filled geometry (no stroke bounds growth)
    r2 = R - bw
    corners = {
        'topleft': (x0, y0, f'M{x0},{y1} A{R},{R} 0 0 1 {x1},{y0} L{x1},{y1} Z',
                    f'M{x0},{y1} A{R},{R} 0 0 1 {x1},{y0} L{x1},{y0+bw} A{r2},{r2} 0 0 0 {x0+bw},{y1} Z'),
        'topright': (x2, y0, f'M{x2},{y0} A{R},{R} 0 0 1 {x3},{y1} L{x2},{y1} Z',
                     f'M{x2},{y0} A{R},{R} 0 0 1 {x3},{y1} L{x3-bw},{y1} A{r2},{r2} 0 0 0 {x2},{y0+bw} Z'),
        'bottomleft': (x0, y2, f'M{x0},{y2} L{x1},{y2} L{x1},{y3} A{R},{R} 0 0 1 {x0},{y2} Z',
                       f'M{x1},{y3} A{R},{R} 0 0 1 {x0},{y2} L{x0+bw},{y2} A{r2},{r2} 0 0 0 {x1},{y3-bw} Z'),
        'bottomright': (x2, y2, f'M{x2},{y2} L{x3},{y2} A{R},{R} 0 0 1 {x2},{y3} Z',
                        f'M{x3},{y2} A{R},{R} 0 0 1 {x2},{y3} L{x2},{y3-bw} A{r2},{r2} 0 0 0 {x3-bw},{y2} Z'),
    }
    for name, (bx, by, fp, bp) in corners.items():
        c = f'<path d="{fp}" {F}/>'
        if S: c += f'<path d="{bp}" {S}/>'
        piece(name, bx, by, R, R, c)
    edges = {
        'top': (x1, y0, E, R, (x1, y0, E, bw)), 'bottom': (x1, y2, E, R, (x1, y3 - bw, E, bw)),
        'left': (x0, y1, R, E, (x0, y1, bw, E)), 'right': (x2, y1, R, E, (x3 - bw, y1, bw, E)),
    }
    for name, (bx, by, w, ht, br) in edges.items():
        c = f'<rect x="{bx}" y="{by}" width="{w}" height="{ht}" {F}/>'
        if S: c += f'<rect x="{br[0]}" y="{br[1]}" width="{br[2]}" height="{br[3]}" {S}/>'
        piece(name, bx, by, w, ht, c)
    piece('center', x1, y1, E, E, f'<rect x="{x1}" y="{y1}" width="{E}" height="{E}" {F}/>')
    svg.y = oy + W + 10
    return W


def hints(svg, prefix, t, l, r, b):
    y = svg.y
    for i, (n, s) in enumerate((('top', t), ('left', l), ('right', r), ('bottom', b))):
        svg.body.append(f'<rect id="{prefix}hint-{n}-margin" x="{10 + i * 40}" y="{y}" width="{max(s,1)}" height="{max(s,1)}" fill="none" opacity="0"/>')
    svg.y = y + 50


def shadow(svg, prefix, S, R, color, alpha, offset_y=0):
    """Glow/shadow ring around a frame: S = shadow size, R = frame radius."""
    ox, oy = 10, svg.y + 10
    E = 8
    total = S * 2 + E
    g = f'sh{prefix.replace("-", "")}{oy}'
    c = f'rgb({color[0]},{color[1]},{color[2]})'
    stops = [(0, c, alpha), (0.35, c, alpha * 0.45), (0.7, c, alpha * 0.12), (1, c, 0)]
    svg.grad(g + 'r', [(o, cc, a) for o, cc, a in stops], radial=True, cx=1, cy=1, r=1)
    for name, (bx, by, w, h) in {
        'topleft': (0, 0, S, S), 'top': (S, 0, E, S), 'topright': (S + E, 0, S, S),
        'left': (0, S, S, E), 'right': (S + E, S, S, E),
        'bottomleft': (0, S + E, S, S), 'bottom': (S, S + E, E, S), 'bottomright': (S + E, S + E, S, S),
    }.items():
        x, y = ox + bx, oy + by
        if name in ('top', 'bottom', 'left', 'right'):
            d = {'top': (0, 1, 0, 0), 'bottom': (0, 0, 0, 1), 'left': (1, 0, 0, 0), 'right': (0, 0, 1, 0)}[name]
            lg = f'{g}{name}'
            svg.defs.append(f'<linearGradient id="{lg}" x1="{d[0]}" y1="{d[1]}" x2="{d[2]}" y2="{d[3]}">' +
                            ''.join(f'<stop offset="{o}" stop-color="{cc}" stop-opacity="{a}"/>' for o, cc, a in stops) + '</linearGradient>')
            content = f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="url(#{lg})"/>'
        else:
            fx, fy = {'topleft': (1, 1), 'topright': (0, 1), 'bottomleft': (1, 0), 'bottomright': (0, 0)}[name]
            rg = f'{g}{name}'
            svg.defs.append(f'<radialGradient id="{rg}" cx="{x + fx * w}" cy="{y + fy * h}" r="{S}" gradientUnits="userSpaceOnUse">' +
                            ''.join(f'<stop offset="{o}" stop-color="{cc}" stop-opacity="{a}"/>' for o, cc, a in stops) + '</radialGradient>')
            content = f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="url(#{rg})"/>'
        svg.body.append(f'<g id="{prefix}shadow-{name}"><rect x="{x}" y="{y}" width="{w}" height="{h}" fill="none" opacity="0"/>{content}</g>'
                        if prefix != 'RAW' else content)
    svg.body.append(f'<rect id="{prefix}shadow-center" x="{ox + S}" y="{oy + S}" width="{E}" height="{E}" fill="none" opacity="0"/>')
    svg.y = oy + total + 10
    m = max(1, S - R // 2)
    hints(svg, prefix + 'shadow-', m - offset_y, m, m, m + offset_y)


def glass_grad(svg, gid, top, bottom, a_top, a_bot):
    mid = tuple(round((t + b_) / 2) for t, b_ in zip(top, bottom))
    return (f'rgb{mid}', round((a_top + a_bot) / 2, 3))


def panel(alpha):
    s = Svg()
    f = glass_grad(s, 'pf', (20, 33, 70), (9, 15, 34), alpha, alpha + 0.08)
    st = glass_grad(s, 'ps', (120, 190, 255), (40, 90, 170), 0.30, 0.10)
    for pre in ('', 'floating-'):
        frame(s, pre, 14, f, st)
        hints(s, pre, 4, 8, 8, 4)
        frame(s, pre + 'mask-', 14, ('rgb(0,0,0)', 1))
        hints(s, pre + 'mask-', 4, 8, 8, 4)
    shadow(s, '', 18, 14, (0, 0, 0), 0.45, 2)
    s.body.append('<rect id="hint-stretch-borders" x="0" y="0" width="1" height="1" fill="none" opacity="0"/>')
    return s.text()


def dialog(alpha):
    s = Svg()
    f = glass_grad(s, 'df', (16, 27, 58), (8, 13, 30), alpha, alpha + 0.06)
    st = glass_grad(s, 'ds', (90, 200, 255), (61, 107, 255), 0.55, 0.25)
    frame(s, '', 16, f, st)
    hints(s, '', 12, 12, 12, 12)
    frame(s, 'mask-', 16, ('rgb(0,0,0)', 1))
    hints(s, 'mask-', 12, 12, 12, 12)
    shadow(s, '', 26, 16, (30, 140, 234), 0.30, 3)
    return s.text()


def widget(alpha):
    s = Svg()
    f = glass_grad(s, 'wf', (18, 30, 64), (8, 13, 30), alpha, alpha + 0.08)
    st = glass_grad(s, 'ws', (130, 200, 255), (40, 80, 160), 0.28, 0.08)
    frame(s, '', 22, f, st)
    hints(s, '', 14, 14, 14, 14)
    frame(s, 'mask-', 22, ('rgb(0,0,0)', 1))
    hints(s, 'mask-', 14, 14, 14, 14)
    shadow(s, '', 24, 22, (0, 0, 0), 0.40, 4)
    return s.text()


def tooltip(alpha):
    s = Svg()
    f = glass_grad(s, 'tf', (18, 30, 64), (9, 15, 34), alpha, alpha + 0.05)
    frame(s, '', 10, f, ('rgb(30,176,234)', 0.45))
    hints(s, '', 6, 8, 8, 6)
    frame(s, 'mask-', 10, ('rgb(0,0,0)', 1))
    hints(s, 'mask-', 6, 8, 8, 6)
    shadow(s, '', 16, 10, (30, 140, 234), 0.25, 2)
    return s.text()


def colors_ini():
    def c(t): return ','.join(map(str, t))
    common = dict(ForegroundNormal=c(TEXT), ForegroundInactive=c(MUTED), ForegroundActive=c((95, 208, 255)),
                  ForegroundLink=c((79, 196, 255)), ForegroundVisited=c((160, 150, 255)), ForegroundNegative='255,112,150',
                  ForegroundNeutral='255,196,110', ForegroundPositive='96,230,190', DecorationFocus=c(ACCENT), DecorationHover='70,195,245')
    groups = {
        'Window': ((9, 14, 30), (13, 20, 42)), 'View': ((7, 11, 24), (11, 17, 36)), 'Button': ((17, 27, 56), (22, 35, 70)),
        'Selection': ((22, 92, 160), (28, 108, 186)), 'Tooltip': ((11, 18, 40), (16, 26, 54)),
        'Complementary': ((7, 11, 24), (13, 22, 48)), 'Header': ((10, 16, 36), (14, 22, 46)),
    }
    out = ['[General]', 'Name=Midnight Pulse', 'ColorScheme=MidnightPulse', 'shadeSortColumn=true', '', '[KDE]', 'contrast=4', '']
    for g, (n, a) in groups.items():
        out.append(f'[Colors:{g}]')
        out += [f'BackgroundNormal={c(n)}', f'BackgroundAlternate={c(a)}']
        cm = dict(common)
        if g == 'Selection':
            cm['ForegroundNormal'] = '240,248,255'
        out += [f'{k}={v}' for k, v in cm.items()] + ['']
    out += ['[Colors:Header][Inactive]', 'BackgroundNormal=9,14,30', 'BackgroundAlternate=13,20,42'] + [f'{k}={v}' for k, v in common.items()] + ['']
    out += ['[ColorEffects:Disabled]', 'Color=7,11,24', 'ColorAmount=0', 'ColorEffect=0', 'ContrastAmount=0.55', 'ContrastEffect=1',
            'IntensityAmount=0', 'IntensityEffect=0', '', '[ColorEffects:Inactive]', 'Enable=false', '',
            '[WM]', 'activeBackground=10,16,36', f'activeForeground={c(TEXT)}', 'inactiveBackground=7,11,24',
            f'inactiveForeground={c(MUTED)}', 'activeBlend=30,176,234', 'inactiveBlend=60,80,120', '']
    return '\n'.join(out)


def main():
    if OUT.exists():
        shutil.rmtree(OUT)
    files = {
        'widgets/panel-background.svg': panel(0.60), 'translucent/widgets/panel-background.svg': panel(0.52),
        'solid/widgets/panel-background.svg': panel(0.92), 'opaque/widgets/panel-background.svg': panel(0.96),
        'dialogs/background.svg': dialog(0.86), 'translucent/dialogs/background.svg': dialog(0.74),
        'solid/dialogs/background.svg': dialog(0.96), 'opaque/dialogs/background.svg': dialog(0.98),
        'widgets/background.svg': widget(0.62), 'translucent/widgets/background.svg': widget(0.50),
        'solid/widgets/background.svg': widget(0.92), 'opaque/widgets/background.svg': widget(0.96),
        'widgets/tooltip.svg': tooltip(0.88), 'translucent/widgets/tooltip.svg': tooltip(0.78),
        'solid/widgets/tooltip.svg': tooltip(0.96), 'opaque/widgets/tooltip.svg': tooltip(0.98),
    }
    for rel, text in files.items():
        f = OUT / rel
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(text)
    (OUT / 'colors').write_text(colors_ini())
    (OUT / 'plasmarc').write_text('[BlurBehindEffect]\nenabled=true\n\n[ContrastEffect]\nenabled=false\n\n[AdaptiveTransparency]\nenabled=false\n\n[Settings]\nFallbackTheme=default\n')
    (OUT / 'metadata.json').write_text(json.dumps({
        'KPlugin': {'Id': 'MidnightPulse', 'Name': 'Midnight Pulse', 'Description': 'Deep night-blue glass with a pulsing accent',
                    'Version': '1.0', 'License': 'MIT', 'Authors': [{'Name': 'Midnight Pulse'}]},
        'X-Plasma-API-Minimum-Version': '6.0', 'KPackageStructure': 'Plasma/Theme'}, indent=2))
    cs = P / 'src/color-schemes/MidnightPulse.colors'
    cs.parent.mkdir(parents=True, exist_ok=True)
    cs.write_text(colors_ini())
    print('generated', len(files), 'svgs')


if __name__ == '__main__':
    main()
