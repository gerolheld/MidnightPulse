#!/usr/bin/env python3
"""Generate the Midnight Pulse Aurorae window decoration: glass titlebar + glowing accent border."""
from pathlib import Path
import shutil, json

P = Path(__file__).resolve().parents[1]
OUT = P / 'src/aurorae/themes/MidnightPulse'
PAD, R, E = 12, 10, 8          # glow padding, corner radius, stretch length
C = PAD + R                    # corner piece size


def stops(rgb, a0):
    c = f'rgb{rgb}'
    return [(0, c, a0), (0.35, c, a0 * 0.45), (0.7, c, a0 * 0.12), (1, c, 0)]


def frame(prefix, fill, fill_a, border, border_a, glow, glow_a, oy):
    defs, body = [], []
    ox = 10
    W = C * 2 + E
    def piece(pid, x, y, w, h, content):
        body.append(f'<g id="{prefix}-{pid}"><rect x="{x}" y="{y}" width="{w}" height="{h}" fill="none" stroke="none"/>{content}</g>')
    st = ''.join
    gid = prefix.replace('-', '')
    # glow gradients
    def lin(name, x1, y1, x2, y2):
        defs.append(f'<linearGradient id="{gid}{name}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">' +
                    st(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o, c, a in stops(glow, glow_a)) + '</linearGradient>')
        return f'url(#{gid}{name})'
    def rad(name, cx, cy):
        defs.append(f'<radialGradient id="{gid}{name}" gradientUnits="userSpaceOnUse" cx="{cx}" cy="{cy}" r="{C}">' +
                    st(f'<stop offset="{o * PAD / C + R / C}" stop-color="{c}" stop-opacity="{a}"/>' for o, c, a in stops(glow, glow_a)) + '</radialGradient>')
        return f'url(#{gid}{name})'
    F = f'fill="rgb{fill}" fill-opacity="{fill_a}"'
    B = f'fill="rgb{border}" fill-opacity="{border_a}"'
    x0, x1, x2, x3 = ox, ox + C, ox + C + E, ox + W
    y0, y1, y2, y3 = oy, oy + C, oy + C + E, oy + W
    # inner rounded rect starts at PAD
    a, b = PAD, PAD + R
    bw = 1
    # corners (glow quarter + fill quarter + border ring)
    for name, (bx, by, cx, cy, sx, sy) in {
        'topleft': (x0, y0, x1, y1, -1, -1), 'topright': (x2, y0, x2, y1, 1, -1),
        'bottomleft': (x0, y2, x1, y2, -1, 1), 'bottomright': (x2, y2, x2, y2, 1, 1)}.items():
        g = rad(name, cx, cy)
        # quarter disc of radius R centred at (cx,cy) in direction (sx,sy)
        def q(r):
            p1 = (cx + sx * r, cy); p2 = (cx, cy + sy * r)
            sweep = 1 if sx * sy > 0 else 0
            return f'M{cx},{cy} L{p1[0]},{p1[1]} A{r},{r} 0 0 {sweep} {p2[0]},{p2[1]} Z'
        def ring(r1, r2):
            p1 = (cx + sx * r1, cy); p2 = (cx, cy + sy * r1); p3 = (cx, cy + sy * r2); p4 = (cx + sx * r2, cy)
            sweep = 1 if sx * sy > 0 else 0
            return f'M{p1[0]},{p1[1]} A{r1},{r1} 0 0 {sweep} {p2[0]},{p2[1]} L{p3[0]},{p3[1]} A{r2},{r2} 0 0 {1 - sweep} {p4[0]},{p4[1]} Z'
        content = (f'<path d="{ring(C, R)}" fill="{g}"/>' if glow_a > 0 else '') + f'<path d="{q(R)}" {F}/>' + f'<path d="{ring(R, R - bw)}" {B}/>'
        piece(name, bx, by, C, C, content)
    # edges
    edges = {
        'top': (x1, y0, E, C, (x1, y0, E, PAD), lin('top', 0, 1, 0, 0), (x1, y0 + PAD, E, C - PAD), (x1, y0 + PAD, E, bw)),
        'bottom': (x1, y2, E, C, (x1, y3 - PAD, E, PAD), lin('bottom', 0, 0, 0, 1), (x1, y2, E, C - PAD), (x1, y3 - PAD - bw, E, bw)),
        'left': (x0, y1, C, E, (x0, y1, PAD, E), lin('left', 1, 0, 0, 0), (x0 + PAD, y1, C - PAD, E), (x0 + PAD, y1, bw, E)),
        'right': (x2, y1, C, E, (x3 - PAD, y1, PAD, E), lin('right', 0, 0, 1, 0), (x2, y1, C - PAD, E), (x3 - PAD - bw, y1, bw, E)),
    }
    for name, (bx, by, w, h, gr, gfill, fr, br) in edges.items():
        content = (f'<rect x="{gr[0]}" y="{gr[1]}" width="{gr[2]}" height="{gr[3]}" fill="{gfill}"/>' if glow_a > 0 else '')
        content += f'<rect x="{fr[0]}" y="{fr[1]}" width="{fr[2]}" height="{fr[3]}" {F}/>'
        content += f'<rect x="{br[0]}" y="{br[1]}" width="{br[2]}" height="{br[3]}" {B}/>'
        piece(name, bx, by, w, h, content)
    piece('center', x1, y1, E, E, f'<rect x="{x1}" y="{y1}" width="{E}" height="{E}" {F}/>')
    hy = y3 + 10
    for i, n in enumerate(('top', 'left', 'right', 'bottom')):
        body.append(f'<rect id="{prefix}-hint-{n}-margin" x="{10 + i * 40}" y="{hy}" width="{PAD}" height="{PAD}" fill="none" stroke="none"/>')
    return defs, body, hy + 30


def decoration():
    defs, body = [], []
    d1, b1, y = frame('decoration', (11, 18, 40), 0.94, (95, 208, 255), 0.85, (30, 176, 234), 0.34, 10)
    d2, b2, y = frame('decoration-inactive', (9, 14, 30), 0.94, (120, 160, 220), 0.16, (0, 0, 0), 0.40, y)
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="300" height="%d"><defs>%s</defs>%s</svg>'
            % (y + 10, ''.join(d1 + d2), ''.join(b1 + b2)))


GLYPHS = {
    'close': '<path d="M8 8 16 16 M16 8 8 16" fill="none" stroke="{c}" stroke-width="1.7" stroke-linecap="round"/>',
    'maximize': '<rect x="7.5" y="7.5" width="9" height="9" rx="2.5" fill="none" stroke="{c}" stroke-width="1.6"/>',
    'restore': '<rect x="7" y="9.5" width="7.5" height="7.5" rx="2" fill="none" stroke="{c}" stroke-width="1.5"/><path d="M10 7.5 H15 A1.5 1.5 0 0 1 16.5 9 V14" fill="none" stroke="{c}" stroke-width="1.5" stroke-linecap="round"/>',
    'minimize': '<path d="M7.5 12.5 H16.5" fill="none" stroke="{c}" stroke-width="1.7" stroke-linecap="round"/>',
    'alldesktops': '<circle cx="12" cy="12" r="3" fill="{c}"/>',
    'keepabove': '<path d="M8 14 12 10 16 14" fill="none" stroke="{c}" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/>',
    'keepbelow': '<path d="M8 10 12 14 16 10" fill="none" stroke="{c}" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/>',
    'shade': '<path d="M8 9.5 H16 M8 13.5 H16" fill="none" stroke="{c}" stroke-width="1.6" stroke-linecap="round"/>',
    'help': '<path d="M9.8 9.6 A2.3 2.3 0 1 1 12.6 12 C12 12.3 12 12.8 12 13.6" fill="none" stroke="{c}" stroke-width="1.6" stroke-linecap="round"/><circle cx="12" cy="16.3" r="1" fill="{c}"/>',
    'appmenu': '<path d="M8 9 H16 M8 12 H16 M8 15 H16" fill="none" stroke="{c}" stroke-width="1.5" stroke-linecap="round"/>',
}


def button(name):
    hot = (255, 92, 138) if name == 'close' else (30, 176, 234)
    states = {
        # id: (bg rgb, bg alpha, glyph colour, ring alpha)
        'active-center': ((255, 255, 255), 0.06, '#DCE8FF', 0.0),
        'hover-center': (hot, 0.85, '#070B18' if name != 'close' else '#FFFFFF', 0.5),
        'pressed-center': (hot, 1.0, '#FFFFFF', 0.0),
        'inactive-center': ((255, 255, 255), 0.03, '#5B6E94', 0.0),
        'hover-inactive-center': (hot, 0.6, '#FFFFFF', 0.3),
        'pressed-inactive-center': (hot, 0.9, '#FFFFFF', 0.0),
        'deactivated-center': ((255, 255, 255), 0.02, '#3A4A6A', 0.0),
        'deactivated-inactive-center': ((255, 255, 255), 0.02, '#3A4A6A', 0.0),
        'center': ((255, 255, 255), 0.06, '#DCE8FF', 0.0),
    }
    parts = []
    for i, (sid, (rgb, a, gc, ring)) in enumerate(states.items()):
        x = (i % 5) * 30
        y = (i // 5) * 30
        g = GLYPHS[name].replace('{c}', gc)
        ringsvg = f'<circle cx="12" cy="12" r="11.5" fill="none" stroke="rgb{rgb}" stroke-opacity="{ring}"/>' if ring else ''
        parts.append(f'<g id="{sid}" transform="translate({x} {y})"><rect width="24" height="24" fill="none"/>'
                     f'<circle cx="12" cy="12" r="10" fill="rgb{rgb}" fill-opacity="{a}"/>{ringsvg}{g}</g>')
    return '<svg xmlns="http://www.w3.org/2000/svg" width="150" height="60">' + ''.join(parts) + '</svg>'


def main():
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    (OUT / 'decoration.svg').write_text(decoration())
    for n in GLYPHS:
        (OUT / f'{n}.svg').write_text(button(n))
    (OUT / 'MidnightPulserc').write_text(f'''[General]
TitleAlignment=Center
TitleVerticalAlignment=Center
ActiveTextColor=220,232,255
InactiveTextColor=91,110,148
UseTextShadow=false
Animation=180
Shadow=true
LeftButtons=M
RightButtons=IAX

[Layout]
BorderLeft=1
BorderRight=1
BorderBottom=1
BorderTop=0
TitleEdgeTop=6
TitleEdgeBottom=6
TitleEdgeLeft=12
TitleEdgeRight=10
TitleBorderLeft=8
TitleBorderRight=8
TitleHeight=22
ButtonWidth=24
ButtonHeight=24
ButtonSpacing=6
ButtonMarginTop=0
ExplicitButtonSpacer=8
PaddingTop={PAD}
PaddingBottom={PAD}
PaddingLeft={PAD}
PaddingRight={PAD}
''')
    meta = {'KPlugin': {'Id': '__aurorae__svg__MidnightPulse', 'Name': 'Midnight Pulse', 'Description': 'Glass titlebar with a glowing accent edge',
                        'Version': '1.0', 'License': 'MIT', 'Authors': [{'Name': 'Midnight Pulse'}]},
            'KPackageStructure': 'KWin/Decoration', 'X-Plasma-API': 'javascript'}
    (OUT / 'metadata.json').write_text(json.dumps(meta, indent=2))
    (OUT / 'metadata.desktop').write_text('[Desktop Entry]\nName=Midnight Pulse\nX-KDE-PluginInfo-Name=__aurorae__svg__MidnightPulse\nX-KDE-ServiceTypes=KWin/Decoration\nX-Plasma-API=javascript\n')
    print('aurorae generated')


if __name__ == '__main__':
    main()
