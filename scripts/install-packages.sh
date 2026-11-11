#!/usr/bin/env bash
# Install Midnight Pulse plasmoids + wallpaper into ~/.local/share/plasma, injecting shared QML.
set -euo pipefail
P=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
D=~/.local/share/plasma
install_pkg() { # src dest
  rm -rf "$2"; mkdir -p "$(dirname "$2")"; cp -a "$1" "$2"
  mkdir -p "$2/contents/ui/common"; cp -a "$P"/src/common/*.qml "$2/contents/ui/common/"
}
for w in "$P"/src/wallpaper/org.*; do install_pkg "$w" "$D/wallpapers/$(basename "$w")"; done
# the Telegram chat card is optional: only when Telegram is set up (or MP_TELEGRAM=1)
TG=${MP_TELEGRAM:-$([ -f ~/.config/midnight-pulse/tg.json ] && echo 1 || echo 0)}
for p in "$P"/src/plasma/plasmoids/org.*; do
  [ -d "$p" ] || continue
  [ "$(basename "$p")" = org.midnightpulse.chat ] && [ "$TG" != 1 ] && continue
  install_pkg "$p" "$D/plasmoids/$(basename "$p")"
done
# the lock screen carries its own copies of the palette + bars (no Common import there)
LS="$P/src/plasma/look-and-feel/org.midnightpulse.desktop/contents/lockscreen"
cp -a "$P/src/common/Palette.qml" "$P/src/common/SpectrumBars.qml" "$P/src/common/PulseSource.qml" "$LS/"
echo "installed: $(ls "$P"/src/wallpaper "$P"/src/plasma/plasmoids | grep -c org.)"
