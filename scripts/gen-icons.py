#!/usr/bin/env python3
"""Midnight Pulse icon theme: custom glass-gradient folders + logo; everything else inherits Tela-circle-dark."""
from pathlib import Path
import shutil

P = Path(__file__).resolve().parents[1]
OUT = P / 'build/icons/MidnightPulse'

GLYPHS = {
    '': '',
    'home': '<path d="M32 26 L42 34 V44 H36 V38 H28 V44 H22 V34 Z" fill="#fff"/>',
    'desktop': '<rect x="22" y="28" width="20" height="13" rx="2" fill="none" stroke="#fff" stroke-width="2.4"/><path d="M28 45 H36" stroke="#fff" stroke-width="2.4" stroke-linecap="round"/>',
    'documents': '<path d="M24 30 H40 M24 35 H40 M24 40 H34" stroke="#fff" stroke-width="2.4" stroke-linecap="round"/>',
    'download': '<path d="M32 27 V41 M26 36 L32 42 L38 36" fill="none" stroke="#fff" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/><path d="M24 45 H40" stroke="#fff" stroke-width="2.4" stroke-linecap="round"/>',
    'music': '<path d="M29 41 V29 L39 27 V39" fill="none" stroke="#fff" stroke-width="2.4" stroke-linejoin="round"/><circle cx="26.5" cy="41.5" r="3" fill="#fff"/><circle cx="36.5" cy="39.5" r="3" fill="#fff"/>',
    'pictures': '<path d="M22 44 L29 35 L34 40 L37 37 L42 44 Z" fill="#fff"/><circle cx="37" cy="30" r="2.6" fill="#fff"/>',
    'videos': '<path d="M28 28 L40 35.5 L28 43 Z" fill="#fff"/>',
    'games': '<path d="M25 31 H39 A5 5 0 0 1 44 36 V38 A4 4 0 0 1 37 40 L35 38 H29 L27 40 A4 4 0 0 1 20 38 V36 A5 5 0 0 1 25 31 Z" fill="#fff"/><path d="M26 34 V38 M24 36 H28" stroke="#1A3C8F" stroke-width="1.6" stroke-linecap="round"/><circle cx="37" cy="35" r="1.3" fill="#1A3C8F"/><circle cx="39.5" cy="37.5" r="1.3" fill="#1A3C8F"/>',
    'git': '<circle cx="27" cy="29" r="2.6" fill="#fff"/><circle cx="27" cy="43" r="2.6" fill="#fff"/><circle cx="38" cy="33" r="2.6" fill="#fff"/><path d="M27 31.5 V40.5 M38 35.5 C38 39 31 38 28.5 41" fill="none" stroke="#fff" stroke-width="2"/>',
    'templates': '<rect x="23" y="28" width="7.5" height="7.5" rx="1.5" fill="#fff"/><rect x="33.5" y="28" width="7.5" height="7.5" rx="1.5" fill="#fff"/><rect x="23" y="38.5" width="7.5" height="7.5" rx="1.5" fill="#fff"/><rect x="33.5" y="38.5" width="7.5" height="7.5" rx="1.5" fill="#fff" opacity=".55"/>',
    'publicshare': '<circle cx="38" cy="29" r="2.8" fill="#fff"/><circle cx="26" cy="36" r="2.8" fill="#fff"/><circle cx="38" cy="43" r="2.8" fill="#fff"/><path d="M28.4 34.6 L35.6 30.4 M28.4 37.4 L35.6 41.6" stroke="#fff" stroke-width="2"/>',
    'recent': '<circle cx="32" cy="36" r="8.5" fill="none" stroke="#fff" stroke-width="2.4"/><path d="M32 31 V36.5 L35.5 38.5" fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round"/>',
    'script': '<path d="M27 31 L22.5 36 L27 41 M37 31 L41.5 36 L37 41 M33.5 29 L30.5 43" fill="none" stroke="#fff" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"/>',
    'star': '<path d="M32 27 C32.6 33 34.5 35 41 36 C34.5 37 32.6 39 32 45 C31.4 39 29.5 37 23 36 C29.5 35 31.4 33 32 27 Z" fill="#fff"/>',
}

NAMES = {
    '': ['folder', 'inode-directory', 'folder-blue', 'folder-new'],
    'home': ['user-home', 'folder-home'],
    'desktop': ['user-desktop', 'folder-desktop'],
    'documents': ['folder-documents', 'folder-text'],
    'download': ['folder-download', 'folder-downloads'],
    'music': ['folder-music', 'folder-sound', 'folder-audio'],
    'pictures': ['folder-pictures', 'folder-images', 'folder-image'],
    'videos': ['folder-videos', 'folder-video', 'folder-movies'],
    'games': ['folder-games'],
    'git': ['folder-git', 'folder-github', 'folder-gitlab', 'folder-development'],
    'templates': ['folder-templates'],
    'publicshare': ['folder-publicshare', 'folder-public'],
    'recent': ['folder-recent', 'document-open-recent-folder'],
    'script': ['folder-script', 'folder-code'],
    'star': ['folder-favorites', 'folder-important', 'folder-bookmark'],
}


def folder(glyph, open_=False):
    front_y = 22 if not open_ else 25
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<defs>
 <linearGradient id="b" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#22377A"/><stop offset="1" stop-color="#101C44"/></linearGradient>
 <linearGradient id="f" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#3FC6F5"/><stop offset=".55" stop-color="#1E8FEA"/><stop offset="1" stop-color="#3D5BFF"/></linearGradient>
 <linearGradient id="h" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".55"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>
 <filter id="g" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="1.4" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
</defs>
<path d="M6 14 A4 4 0 0 1 10 10 H24 L29 15 H54 A4 4 0 0 1 58 19 V48 A4 4 0 0 1 54 52 H10 A4 4 0 0 1 6 48 Z" fill="url(#b)"/>
<rect x="10" y="17" width="44" height="10" rx="2" fill="#DCE8FF" opacity=".85"/>
<path d="M{6 if not open_ else 4} {front_y + 4} A4 4 0 0 1 {10 if not open_ else 8} {front_y} H54 A4 4 0 0 1 58 {front_y + 4} V50 A4 4 0 0 1 54 54 H10 A4 4 0 0 1 6 50 Z" fill="url(#f)"/>
<path d="M{6 if not open_ else 4} {front_y + 4} A4 4 0 0 1 {10 if not open_ else 8} {front_y} H54 A4 4 0 0 1 58 {front_y + 4} V{front_y + 9} H6 Z" fill="url(#h)" opacity=".7"/>
<path d="M10 53.2 H54" stroke="#9FE4FF" stroke-opacity=".6" stroke-width="1"/>
<g filter="url(#g)" opacity=".95">{glyph}</g>
</svg>'''


def main():
    if OUT.exists():
        shutil.rmtree(OUT)
    places = OUT / 'scalable/places'
    places.mkdir(parents=True)
    for key, names in NAMES.items():
        svg = folder(GLYPHS[key])
        for n in names:
            (places / f'{n}.svg').write_text(svg)
    (places / 'folder-open.svg').write_text(folder('', True))
    (places / 'folder-drag-accept.svg').write_text(folder(GLYPHS['download'], True))
    apps = OUT / 'scalable/apps'
    apps.mkdir(parents=True)
    logo = (P / 'src/plasma/plasmoids/org.midnightpulse.nav/contents/images/logo.svg').read_text()
    for n in ('start-here', 'start-here-kde', 'start-here-kde-plasma', 'distributor-logo', 'kde'):
        (apps / f'{n}.svg').write_text(logo)
    # app icons referenced by desktop files that the inherited themes don't ship
    tela = Path.home() / '.local/share/icons/Tela-circle/scalable/apps'
    for alias, target in {'azure-vesktop': 'vesktop'}.items():
        src = tela / f'{target}.svg'
        if src.exists():
            shutil.copy(src.resolve(), apps / f'{alias}.svg')
    (OUT / 'index.theme').write_text('''[Icon Theme]
Name=Midnight Pulse
Comment=Glass-blue folders over Tela circle
Inherits=Tela-circle-dark,breeze-dark,hicolor
Example=folder
FollowsColorScheme=true
DisplayDepth=32
DesktopDefault=48
DesktopSizes=16,22,32,48,64,96,128,256
ToolbarDefault=22
ToolbarSizes=16,22,32,48
MainToolbarDefault=22
MainToolbarSizes=16,22,32,48
SmallDefault=16
SmallSizes=16,22,32,48
PanelDefault=48
PanelSizes=16,22,32,48,64,96,128,256
DialogDefault=32
DialogSizes=16,22,32,48,64,128,256
Directories=scalable/places,scalable/apps

[scalable/places]
Size=64
MinSize=16
MaxSize=512
Context=Places
Type=Scalable

[scalable/apps]
Size=64
MinSize=16
MaxSize=512
Context=Applications
Type=Scalable
''')
    print('icons:', sum(1 for _ in places.iterdir()), 'places')


if __name__ == '__main__':
    main()
