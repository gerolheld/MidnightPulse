#!/usr/bin/env bash
set -euo pipefail
P=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$P/build/audio"
/usr/lib/qt6/moc "$P/src/audio/pulsed.cpp" -o "$P/build/audio/pulsed.moc"
read -r -a F <<< "$(pkg-config --cflags --libs Qt6Core Qt6Gui Qt6Network Qt6WebSockets Qt6DBus)"
g++ -std=c++17 -O2 -fPIC "$P/src/audio/pulsed.cpp" -I"$P/build/audio" -o "$P/build/audio/midnight-pulse-audiod" "${F[@]}"
