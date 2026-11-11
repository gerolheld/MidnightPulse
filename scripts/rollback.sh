#!/usr/bin/env bash
# Return to the Plasma setup that existed before Midnight Pulse, from the backup install.py made.
#   rollback.sh           restore settings, panels and widgets; stop the theme's background services
#   rollback.sh --purge   also delete every installed Midnight Pulse file
set -euo pipefail
P=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
L=~/.local/share
B=$(cat "$L/midnight-pulse/backup-path.txt" 2>/dev/null || cat "$P/docs/backup-path.txt" 2>/dev/null || true)
[ -n "$B" ] && [ -d "$B" ] || { echo "backup not found: ${B:-<none>}"; exit 1; }

systemctl --user disable --now midnight-pulse-audio.service midnight-pulse-tg.service 2>/dev/null || true
wd=$(pgrep -f '^/bin/bash .*/plasmashell-watchdog\.sh$' || true)
for p in $wd; do kill -STOP "$p"; done
systemctl --user stop plasma-plasmashell.service || pkill -x plasmashell || true
sleep 1
for f in "$B"/*; do
  n=$(basename "$f")
  [ -d "$f" ] && rm -rf ~/.config/"$n"
  cp -a "$f" ~/.config/
done
rm -f ~/.config/environment.d/60-midnight-pulse.conf ~/.config/plasma-workspace/env/midnight-pulse.sh
plasma-apply-colorscheme "$(kreadconfig6 --file kdeglobals --group General --key ColorScheme)" >/dev/null 2>&1 || true
plasma-apply-desktoptheme "$(kreadconfig6 --file plasmarc --group Theme --key name)" >/dev/null 2>&1 || true
qdbus6 org.kde.KWin /KWin reconfigure || true

if [ "${1:-}" = --purge ]; then
  rm -rf "$L"/plasma/plasmoids/org.midnightpulse.* "$L"/plasma/wallpapers/org.midnightpulse.* \
         "$L"/plasma/look-and-feel/org.midnightpulse.desktop "$L"/plasma/desktoptheme/MidnightPulse* \
         "$L"/aurorae/themes/MidnightPulse* "$L"/color-schemes/MidnightPulse* \
         "$L"/icons/MidnightPulse* ~/.icons/MidnightPulse* "$L"/konsole/MidnightPulse.* \
         ~/.local/lib/qt6/plugins/styles/libmidnightpulse.so ~/.local/bin/midnight-pulse-* \
         ~/.config/systemd/user/midnight-pulse-*.service
  find "$L/midnight-pulse" -mindepth 1 -maxdepth 1 ! -name 'backup-path.txt' ! -name tg -exec rm -rf {} +
  systemctl --user daemon-reload || true
fi

systemctl --user start plasma-plasmashell.service || (setsid plasmashell --no-respawn >/dev/null 2>&1 &)
for p in $wd; do kill -CONT "$p"; done
echo "Restored configuration from $B"
[ "${1:-}" = --purge ] && echo "Midnight Pulse files removed." \
  || echo "(Midnight Pulse files stay installed; ./install.sh brings the theme back. --purge removes them.)"
echo "Log out and back in to finish."
