#!/usr/bin/env bash
# chat-privacy.sh on|off — blur the Telegram chat card live (for screen recordings)
v=$([ "${1:-on}" = off ] && echo false || echo true)
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
for (const d of desktops()) for (const w of d.widgets('org.midnightpulse.chat')) {
  w.currentConfigGroup = ['General']; w.writeConfig('privacy', $v); w.reloadConfig(); }"
echo "chat privacy: $v"
