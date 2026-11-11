#!/usr/bin/env python3
"""Install and activate Midnight Pulse (KDE Plasma 6).

   install.py                 copy every component to ~/.local and apply settings
   install.py --layout        + rebuild panels, dock and desktop widgets
   install.py --files         only copy files (no settings changes)
   install.py --build         rebuild the audio daemon, Qt style, icons and cursor even if built
   install.py --city NAME     weather city (with --layout)
   install.py --telegram      also set up the optional Telegram chat card (off by default)
   install.py --no-telegram   never touch the Telegram part

First-time users: run ./install.sh from the repository root instead — it installs the system
packages, then calls this with --layout. Everything goes to your home directory; your previous
Plasma settings are saved first and scripts/rollback.sh brings them back."""
from pathlib import Path
import os, shutil, subprocess, sys, tempfile, time

P = Path(__file__).resolve().parents[1]
H = Path.home()
L = H / '.local/share'
MP = L / 'midnight-pulse'
BUILD = P / 'build'
TG_CFG = H / '.config/midnight-pulse/tg.json'
ARGS = sys.argv[1:]


def arg(name):
    return ARGS[ARGS.index(name) + 1] if name in ARGS and ARGS.index(name) + 1 < len(ARGS) else None


TELEGRAM = '--no-telegram' not in ARGS and ('--telegram' in ARGS or TG_CFG.exists())


def sh(*cmd, check=False, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if r.returncode and check:
        print('FAILED:', ' '.join(map(str, cmd)), (r.stderr or r.stdout).strip()[-800:])
    return r


def step(msg):
    print(f'\033[1;36m✦\033[0m {msg}', flush=True)


def copytree(src, dst):
    if dst.exists():
        shutil.rmtree(dst)
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(src, dst, symlinks=True)


def kw(file, group, key, value):
    args = ['kwriteconfig6', '--file', file]
    for g in group if isinstance(group, (list, tuple)) else [group]:
        args += ['--group', g]
    sh(*args, '--key', key, str(value), check=True)


def newer(src, out):
    return not out.exists() or src.stat().st_mtime > out.stat().st_mtime


# ---- build / fetch the generated parts ------------------------------------------------------
def icon_theme_dirs():
    return [L / 'icons', H / '.icons', Path('/usr/share/icons')]


def has_icon_theme(name):
    return any((d / name / 'index.theme').exists() for d in icon_theme_dirs())


def download(url, dst):
    r = sh('curl', '-fsSL', '--retry', '3', '-o', str(dst), url)
    if r.returncode:
        print('  не удалось скачать', url, '—', r.stderr.strip()[-300:])
        return False
    return True


def build():
    force = '--build' in ARGS
    daemon = BUILD / 'audio/midnight-pulse-audiod'
    if force or newer(P / 'src/audio/pulsed.cpp', daemon):
        step('Собираю аудио-демон…')
        sh('bash', str(P / 'scripts/build-audio.sh'), check=True)

    style = BUILD / 'qt-style/plugins/styles/libmidnightpulse.so'
    if force or newer(P / 'src/qt-style/midnightpulse.cpp', style):
        step('Собираю Qt-стиль (стекло в Dolphin, Параметрах, Kate)…')
        b = BUILD / 'qt-style'
        sh('cmake', '-S', str(P / 'src/qt-style'), '-B', str(b), '-DCMAKE_BUILD_TYPE=Release', check=True)
        sh('cmake', '--build', str(b), '-j', str(os.cpu_count() or 4), check=True)

    if not has_icon_theme('Tela-circle-dark'):
        step('Скачиваю базовые иконки Tela circle…')
        with tempfile.TemporaryDirectory() as t:
            src = Path(t) / 'tela'
            if sh('git', 'clone', '-q', '--depth', '1', 'https://github.com/vinceliuice/Tela-circle-icon-theme.git', str(src)).returncode == 0:
                (L / 'icons').mkdir(parents=True, exist_ok=True)
                sh('bash', str(src / 'install.sh'), '-d', str(L / 'icons'), cwd=src, check=True)
            else:
                print('  git clone не удался — папки будут поверх breeze-dark')
    if force or not (BUILD / 'icons/MidnightPulse/index.theme').exists():
        step('Генерирую иконки Midnight Pulse…')
        sh(sys.executable, str(P / 'scripts/gen-icons.py'), check=True)

    cur = BUILD / 'cursors/MidnightPulse-Cursors'
    if force or not (cur / 'index.theme').exists():
        step('Скачиваю курсор Bibata и перекрашиваю…')
        with tempfile.TemporaryDirectory() as t:
            tar = Path(t) / 'bibata.tar.xz'
            url = 'https://github.com/ful1e5/Bibata_Cursor/releases/latest/download/Bibata-Modern-Classic.tar.xz'
            if download(url, tar) and sh('tar', '-xJf', str(tar), '-C', t).returncode == 0:
                src = next(Path(t).glob('Bibata-Modern-Classic*'), None)
                if src:
                    sh(sys.executable, str(P / 'scripts/recolor-cursors.py'), str(src), str(cur), check=True)


# ---- files ----------------------------------------------------------------------------------
def files():
    env = dict(os.environ, MP_TELEGRAM='1' if TELEGRAM else '0')
    sh(str(P / 'scripts/install-packages.sh'), check=True, env=env)
    copytree(P / 'src/plasma/desktoptheme/MidnightPulse', L / 'plasma/desktoptheme/MidnightPulse')
    copytree(P / 'src/plasma/look-and-feel/org.midnightpulse.desktop', L / 'plasma/look-and-feel/org.midnightpulse.desktop')
    copytree(P / 'src/aurorae/themes/MidnightPulse', L / 'aurorae/themes/MidnightPulse')
    (L / 'color-schemes').mkdir(parents=True, exist_ok=True)
    shutil.copy2(P / 'src/color-schemes/MidnightPulse.colors', L / 'color-schemes/MidnightPulse.colors')
    style = BUILD / 'qt-style/plugins/styles/libmidnightpulse.so'
    if style.exists():
        d = H / '.local/lib/qt6/plugins/styles'
        d.mkdir(parents=True, exist_ok=True)
        shutil.copy2(style, d / 'libmidnightpulse.so')
    for extra in ('icons', 'cursors'):
        for theme in (BUILD / extra).glob('MidnightPulse*') if (BUILD / extra).exists() else []:
            copytree(theme, L / 'icons' / theme.name)
            if extra == 'cursors':
                copytree(theme, H / '.icons' / theme.name)   # KDE's cursor KCM scans ~/.icons
    # pristine Midnight sources for live re-colouring (recolor.py, run by the audio daemon)
    base = MP / 'base'
    copytree(P / 'src/plasma/desktoptheme/MidnightPulse', base / 'desktoptheme/MidnightPulse')
    copytree(P / 'src/aurorae/themes/MidnightPulse', base / 'aurorae/MidnightPulse')
    (base / 'color-schemes').mkdir(parents=True, exist_ok=True)
    shutil.copy2(P / 'src/color-schemes/MidnightPulse.colors', base / 'color-schemes/MidnightPulse.colors')
    (base / 'apps').mkdir(parents=True, exist_ok=True)
    for src, dst in {'src/konsole/MidnightPulse.colorscheme': 'MidnightPulse.colorscheme',
                     'src/apps/alacritty-midnight-pulse.toml': 'midnight-pulse.toml',
                     'src/apps/cava.config': 'cava.config',
                     'src/apps/vesktop/MidnightPulse.theme.css': 'MidnightPulse.theme.css',
                     'src/apps/spicetify/MidnightPulse/color.ini': 'spicetify-color.ini',
                     'src/apps/spicetify/MidnightPulse/user.css': 'spicetify-user.css'}.items():
        shutil.copy2(P / src, base / 'apps' / dst)
    if (BUILD / 'cursors/MidnightPulse-Cursors').exists():
        copytree(BUILD / 'cursors/MidnightPulse-Cursors', base / 'cursors/MidnightPulse-Cursors')
    shutil.copy2(P / 'scripts/recolor.py', MP / 'recolor.py')
    audio()
    apps()
    env_path()
    if TELEGRAM:
        telegram()
    for f in (H / '.cache').glob('plasma_theme_MidnightPulse*'):
        f.unlink()
    for f in (H / '.cache').glob('ksvg-elements*'):
        f.unlink() if f.is_file() else None
    step('Файлы установлены')


def audio():
    """Spectrum/beat broadcaster for every widget (PipeWire → cava → ws://127.0.0.1:47800)."""
    daemon = BUILD / 'audio/midnight-pulse-audiod'
    if not daemon.exists():
        print('  аудио-демон не собран — виджеты будут без музыки (запусти install.py --build)')
        return
    b = H / '.local/bin'
    b.mkdir(parents=True, exist_ok=True)
    tmp = b / '.midnight-pulse-audiod.new'
    shutil.copy2(daemon, tmp)
    tmp.replace(b / 'midnight-pulse-audiod')               # atomic: safe while the old one runs
    unit = H / '.config/systemd/user/midnight-pulse-audio.service'
    unit.parent.mkdir(parents=True, exist_ok=True)
    unit.write_text("""[Unit]
Description=Midnight Pulse audio spectrum broadcaster
After=pipewire-pulse.service

[Service]
ExecStart=%h/.local/bin/midnight-pulse-audiod
Restart=on-failure
RestartSec=3
Nice=5

[Install]
WantedBy=graphical-session.target
""")
    sh('systemctl', '--user', 'daemon-reload')
    sh('systemctl', '--user', 'enable', 'midnight-pulse-audio')
    sh('systemctl', '--user', 'restart', 'midnight-pulse-audio')


def apps():
    """Konsole profile + fastfetch; Alacritty/cava/Vesktop/Spicetify colours only where the app is set up."""
    k = L / 'konsole'
    k.mkdir(parents=True, exist_ok=True)
    for f in ('MidnightPulse.colorscheme', 'MidnightPulse.profile'):
        shutil.copy2(P / 'src/konsole' / f, k / f)
    kw('konsolerc', 'Desktop Entry', 'DefaultProfile', 'MidnightPulse.profile')
    ff = H / '.config/fastfetch'
    if not (ff / 'config.jsonc').exists():
        ff.mkdir(parents=True, exist_ok=True)
        shutil.copy2(P / 'src/konsole/fastfetch.jsonc', ff / 'config.jsonc')
        shutil.copy2(P / 'src/konsole/logo.txt', ff / 'midnight-pulse-logo.txt')
    cava = H / '.config/cava'
    if not (cava / 'config').exists():
        cava.mkdir(parents=True, exist_ok=True)
        shutil.copy2(P / 'src/apps/cava.config', cava / 'config')
    if (H / '.config/alacritty').exists():
        shutil.copy2(P / 'src/apps/alacritty-midnight-pulse.toml', H / '.config/alacritty/midnight-pulse.toml')
    if (H / '.config/vesktop').exists():
        (H / '.config/vesktop/themes').mkdir(exist_ok=True)
        shutil.copy2(P / 'src/apps/vesktop/MidnightPulse.theme.css', H / '.config/vesktop/themes/MidnightPulse.theme.css')
    if shutil.which('spicetify'):
        copytree(P / 'src/apps/spicetify/MidnightPulse', H / '.config/spicetify/Themes/MidnightPulse')


def env_path():
    """Plasma must find the Qt style in ~/.local/lib/qt6/plugins (takes effect after re-login)."""
    d = H / '.config/environment.d'
    d.mkdir(parents=True, exist_ok=True)
    (d / '60-midnight-pulse.conf').write_text('QT_PLUGIN_PATH=${HOME}/.local/lib/qt6/plugins:${QT_PLUGIN_PATH:-}\n')
    e = H / '.config/plasma-workspace/env'
    e.mkdir(parents=True, exist_ok=True)
    (e / 'midnight-pulse.sh').write_text('''#!/bin/sh
case ":${QT_PLUGIN_PATH:-}:" in
  *":$HOME/.local/lib/qt6/plugins:"*) ;;
  *) export QT_PLUGIN_PATH="$HOME/.local/lib/qt6/plugins${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}" ;;
esac
''')


def wl_clipboard(dst):
    """wl-paste for pasting screenshots into the chat. Uses the system one if installed; else a
    signature-verified copy of the distro package (pacman systems only)."""
    if shutil.which('wl-paste') or (dst / 'wl-paste').exists() or not shutil.which('pacman'):
        return
    dst.mkdir(parents=True, exist_ok=True)
    url = sh('pacman', '-Sp', 'wl-clipboard').stdout.strip().splitlines()
    if not url:
        return
    with tempfile.TemporaryDirectory() as t:
        pkg = Path(t) / 'wl.pkg.tar.zst'
        if (not download(url[-1], pkg) or not download(url[-1] + '.sig', Path(f'{pkg}.sig'))
           or sh('pacman-key', '--verify', f'{pkg}.sig', str(pkg)).returncode):
            print('  wl-clipboard: пакет не скачался или подпись не сошлась — вставка картинок недоступна')
            return
        sh('tar', '-xf', str(pkg), '-C', t, 'usr/bin/wl-paste', 'usr/bin/wl-copy')
        for b in ('wl-paste', 'wl-copy'):
            shutil.copy2(Path(t) / 'usr/bin' / b, dst / b)


def telegram():
    """Optional Telegram chat card backend: venv + daemon + login command + user service."""
    step('Telegram-карточка: бэкенд…')
    venv = MP / 'tg-venv'
    if not (venv / 'bin/python').exists():
        sh('uv', 'venv', '-q', str(venv), check=True)
        sh('uv', 'pip', 'install', '-q', '--python', str(venv / 'bin/python'), 'telethon', 'websockets', 'qrcode[pil]', check=True)
    for f in ('tgd.py', 'tg-login.py'):
        shutil.copy2(P / 'src/tg' / f, MP / f)
    wl_clipboard(MP / 'bin')
    b = H / '.local/bin/midnight-pulse-tg-login'
    b.parent.mkdir(parents=True, exist_ok=True)
    b.write_text(f'#!/bin/sh\nexec "{venv}/bin/python" "{MP}/tg-login.py" "$@"\n')
    b.chmod(0o755)
    unit = H / '.config/systemd/user/midnight-pulse-tg.service'
    unit.parent.mkdir(parents=True, exist_ok=True)
    unit.write_text(f"""[Unit]
Description=Midnight Pulse Telegram chat widget backend
After=network-online.target

[Service]
ExecStart={venv}/bin/python {MP}/tgd.py
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=default.target
""")
    sh('systemctl', '--user', 'daemon-reload')
    if TG_CFG.exists():                       # only once logged in (midnight-pulse-tg-login)
        sh('systemctl', '--user', 'enable', 'midnight-pulse-tg')
        sh('systemctl', '--user', 'restart', 'midnight-pulse-tg')
    else:
        print('  войди в Telegram командой: midnight-pulse-tg-login')


# ---- backup + settings ----------------------------------------------------------------------
BACKUP_FILES = ['kdeglobals', 'kwinrc', 'plasmarc', 'plasmashellrc', 'plasma-org.kde.plasma.desktop-appletsrc',
                'ksplashrc', 'kscreenlockerrc', 'kcminputrc', 'konsolerc', 'gtk-3.0', 'gtk-4.0', 'cava', 'fastfetch']


def backup_path():
    for f in (MP / 'backup-path.txt', P / 'docs/backup-path.txt'):
        if f.exists():
            return Path(f.read_text().strip())
    return None


def backup():
    """Save the Plasma setup that existed before Midnight Pulse — once, on the first install."""
    if backup_path():
        return
    b = L / 'midnight-pulse-backup' / time.strftime('%Y%m%d-%H%M%S')
    b.mkdir(parents=True)
    for name in BACKUP_FILES:
        src = H / '.config' / name
        if src.is_dir():
            shutil.copytree(src, b / name, symlinks=True)
        elif src.exists():
            shutil.copy2(src, b / name)
    MP.mkdir(parents=True, exist_ok=True)
    (MP / 'backup-path.txt').write_text(f'{b}\n')
    step(f'Бэкап твоих настроек: {b}')


def settings():
    backup()
    sh('plasma-apply-colorscheme', 'MidnightPulse', check=True)
    sh('plasma-apply-desktoptheme', 'MidnightPulse', check=True)
    kw('kdeglobals', 'General', 'AccentColor', '30,176,234')
    kw('kdeglobals', 'KDE', 'widgetStyle', 'MidnightPulse')
    kw('kdeglobals', 'KDE', 'LookAndFeelPackage', 'org.midnightpulse.desktop')
    font = 'Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1'
    for k in ('font', 'menuFont', 'toolBarFont'):
        kw('kdeglobals', 'General', k, font)
    kw('kdeglobals', 'General', 'smallestReadableFont', 'Inter,8,-1,5,400,0,0,0,0,0,0,0,0,0,0,1')
    kw('kdeglobals', 'WM', 'activeFont', 'Inter,10,-1,5,600,0,0,0,0,0,0,0,0,0,0,1')
    kw('kwinrc', 'org.kde.kdecoration2', 'library', 'org.kde.kwin.aurorae')
    kw('kwinrc', 'org.kde.kdecoration2', 'theme', '__aurorae__svg__MidnightPulse')
    kw('kwinrc', 'org.kde.kdecoration2', 'BorderSize', 'Normal')
    kw('kwinrc', 'Plugins', 'blurEnabled', 'true')
    kw('kwinrc', 'Effect-blur', 'BlurStrength', '9')
    kw('kwinrc', 'Effect-blur', 'NoiseStrength', '3')
    kw('kwinrc', 'Plugins', 'scaleEnabled', 'true')
    kw('kwinrc', 'Plugins', 'glideEnabled', 'false')
    kw('kwinrc', 'Plugins', 'magiclampEnabled', 'true')        # genie-style minimise into the dock
    kw('kwinrc', 'Plugins', 'squashEnabled', 'false')
    kw('kwinrc', 'Plugins', 'wobblywindowsEnabled', 'false')
    kw('kwinrc', 'Plugins', 'slideEnabled', 'true')
    kw('kwinrc', 'Effect-slide', 'SlideBackground', 'false')
    kw('ksplashrc', 'KSplash', 'Engine', 'KSplashQML')
    kw('ksplashrc', 'KSplash', 'Theme', 'org.midnightpulse.desktop')
    kw('kscreenlockerrc', 'Greeter', 'Theme', 'org.midnightpulse.desktop')
    kw('kscreenlockerrc', 'Greeter', 'WallpaperPlugin', 'org.midnightpulse.sky')
    kw('kscreenlockerrc', ['Greeter', 'LnF', 'General'], 'showMediaControls', 'true')
    kw('kscreenlockerrc', ['Greeter', 'LnF', 'General'], 'alwaysShowClock', 'true')
    if (L / 'icons/MidnightPulse').exists():
        sh('plasma-changeicons', 'MidnightPulse')
        sh('/usr/lib/plasma-changeicons', 'MidnightPulse')
        kw('kdeglobals', 'Icons', 'Theme', 'MidnightPulse')
    if (L / 'icons/MidnightPulse-Cursors').exists():
        sh('plasma-apply-cursortheme', 'MidnightPulse-Cursors')
    sh('qdbus6', 'org.kde.KWin', '/KWin', 'reconfigure')
    step('Настройки применены')


# ---- panels + desktop widgets ---------------------------------------------------------------
# The dock's pinned apps: this list, minus apps that aren't installed. A missing browser /
# Discord falls back to the default browser / Vesktop.
DOCK = ['org.kde.konsole', 'discord', 'spotify', 'steam', 'Blender', 'org.kde.dolphin', 'systemsettings', 'zen']
APP_DIRS = [Path('/usr/share/applications'), L / 'applications', Path('/var/lib/flatpak/exports/share/applications'),
            L / 'flatpak/exports/share/applications']


def desktop_file(name):
    for d in APP_DIRS:
        if (d / f'{name}.desktop').exists():
            return name
    for d in APP_DIRS:                             # flatpak ids: com.spotify.Client, com.valvesoftware.Steam …
        for f in d.glob(f'*.{name}.desktop') if d.exists() else []:
            return f.stem
        for f in d.glob(f'*{name.capitalize()}*.desktop') if d.exists() else []:
            return f.stem
    return None


def launchers():
    out = []
    for n in DOCK:
        got = desktop_file(n)
        if not got and n == 'discord':
            got = desktop_file('vesktop')
        if not got and n == 'zen':
            browser = sh('xdg-settings', 'get', 'default-web-browser').stdout.strip().removesuffix('.desktop')
            got = desktop_file(browser) if browser else desktop_file('firefox')
        if got and f'applications:{got}.desktop' not in out:
            out.append(f'applications:{got}.desktop')
    return out


def current_city():
    """Keep the weather city across a re-layout (read from the widget that is about to be replaced)."""
    rc = H / '.config/plasma-org.kde.plasma.desktop-appletsrc'
    if not rc.exists():
        return None
    lines = rc.read_text(errors='replace').splitlines()
    weather = set()
    for i, l in enumerate(lines):
        if l.strip() == 'plugin=org.midnightpulse.weather':
            for j in range(i, -1, -1):
                if lines[j].startswith('[Containments]'):
                    weather.add(lines[j].strip()); break
    for i, l in enumerate(lines):
        if any(l.startswith(w[:-1] + '][Configuration][General]') for w in weather):
            for m in lines[i + 1:]:
                if m.startswith('['):
                    break
                if m.startswith('city='):
                    return m[5:]
    return None


def js_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


def layout():
    city = arg('--city') or current_city()
    pre = [f'var MP_LAUNCHERS = [{", ".join(js_str(x) for x in launchers())}];']
    if city:
        pre.append(f'var MP_CITY = {js_str(city)};')
    if TELEGRAM and TG_CFG.exists():
        pre.append('var MP_CHAT = true;')
    js = '\n'.join(pre) + '\n' + (P / 'scripts/layout.js').read_text()
    r = sh('qdbus6', 'org.kde.plasmashell', '/PlasmaShell', 'org.kde.PlasmaShell.evaluateScript', js)
    msg = r.stdout.strip() or r.stderr.strip()
    print(msg)
    size = msg.rsplit(' ', 1)[-1]
    if 'x' in size and size.replace('x', '').isdigit():
        place_widgets(*map(int, size.split('x')))


def widget_rects(w, h):
    """Desktop widget positions (x, y, width, height) for a w×h screen — same margins on any size."""
    return {'org.midnightpulse.weather': (32, 64, 432, 288),
            'org.midnightpulse.system': (w - 432, 64, 400, 288),
            'org.midnightpulse.chat': (32, 464, 368, 464),
            'org.midnightpulse.player': (w - 480, h - 424, 448, 272)}


def place_widgets(w, h):
    """Plasma 6 ignores applet.geometry from scripts (new widgets pile up in the centre), so write the
    folder containment's ItemGeometries directly while plasmashell is stopped."""
    time.sleep(3)                                          # let plasmashell save the new layout
    wd = sh('pgrep', '-f', 'plasmashell-watchdog').stdout.split()
    for p in wd:
        sh('kill', '-STOP', p)
    if sh('systemctl', '--user', 'stop', 'plasma-plasmashell').returncode:
        sh('kquitapp6', 'plasmashell')
    time.sleep(1)
    try:
        rc = H / '.config/plasma-org.kde.plasma.desktop-appletsrc'
        cont, plug, sky = {}, {}, set()
        cur = None
        for line in rc.read_text(errors='replace').splitlines():
            if line.startswith('['):
                parts = line.strip('[]').split('][')
                cur = parts
            elif cur and line.startswith('plugin='):
                if len(cur) == 4 and cur[0] == 'Containments' and cur[2] == 'Applets':
                    plug[cur[3]] = (cur[1], line[7:])
            elif cur and len(cur) == 2 and cur[0] == 'Containments' and line == 'wallpaperplugin=org.midnightpulse.sky':
                sky.add(cur[1])
        rects = widget_rects(w, h)
        for c in sky:
            items = ''.join(f'Applet-{a}:{",".join(map(str, rects[t]))},0;'
                            for a, (cc, t) in sorted(plug.items(), key=lambda x: int(x[0])) if cc == c and t in rects)
            if items:
                for key in (f'ItemGeometries-{w}x{h}', 'ItemGeometriesHorizontal'):
                    kw('plasma-org.kde.plasma.desktop-appletsrc', ['Containments', c], key, items)
    finally:
        if sh('systemctl', '--user', 'start', 'plasma-plasmashell').returncode:
            subprocess.Popen(['setsid', 'plasmashell', '--no-respawn'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for p in wd:
            sh('kill', '-CONT', p)
    step('Виджеты расставлены')


if __name__ == '__main__':
    build()
    files()
    if '--files' not in ARGS:
        settings()
    if '--layout' in ARGS:
        layout()
