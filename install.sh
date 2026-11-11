#!/usr/bin/env bash
# Midnight Pulse — установка одной командой:   ./install.sh
#   ./install.sh --city "Warszawa"   город для погоды без вопроса
#   ./install.sh --no-deps           не ставить системные пакеты (поставил сам)
#   ./install.sh --telegram          + карточка чата Telegram (по желанию, см. README)
set -euo pipefail
P=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
c() { printf '\033[1;36m✦\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

CITY="" DEPS=1 TG=--no-telegram
while [ $# -gt 0 ]; do
  case "$1" in
    --city) CITY=${2:-}; shift ;;
    --no-deps) DEPS=0 ;;
    --telegram) TG=--telegram ;;
    -h|--help) sed -n 2,5p "$0"; exit 0 ;;
    *) die "неизвестный параметр: $1" ;;
  esac
  shift
done

[ "$(id -u)" -ne 0 ] || die "запускай от своего пользователя, не от root (sudo спросится сам)"
command -v plasmashell >/dev/null || die "нужен KDE Plasma 6 — plasmashell не найден"
ver=$(plasmashell --version 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)
[ "${ver:-0}" -ge 6 ] || die "нужен KDE Plasma 6 (найден: $(plasmashell --version 2>/dev/null))"
[ "${XDG_SESSION_TYPE:-}" = wayland ] || c "Внимание: сессия не Wayland — тема делалась под Wayland, что-то может выглядеть иначе"

PKGS=(base-devel cmake extra-cmake-modules pkgconf git curl xz python
      qt6-base qt6-declarative qt6-websockets qt6-5compat qt6-multimedia qt6-tools
      kwindowsystem kconfig plasma-workspace xdg-utils
      cava libpulse pipewire-pulse
      inter-font ttf-meslo-nerd fastfetch)
[ "$TG" = --telegram ] && PKGS+=(uv wl-clipboard)

if [ "$DEPS" = 1 ]; then
  if command -v pacman >/dev/null; then
    c "Ставлю системные пакеты (попросит пароль sudo)…"
    sudo pacman -S --needed --noconfirm "${PKGS[@]}" \
      || die "pacman не смог поставить пакеты. Обнови систему (sudo pacman -Syu) и запусти снова."
  else
    c "Это не Arch: поставь аналоги этих пакетов сам и запусти ./install.sh --no-deps"
    printf '   %s\n' "${PKGS[*]}"
    exit 1
  fi
fi

if [ -z "$CITY" ] && [ -t 0 ]; then
  read -rp "$(printf '\033[1;36m✦\033[0m') Город для погоды (латиницей или по-русски) [London]: " CITY
fi
CITY=${CITY:-London}

c "Устанавливаю Midnight Pulse…"
python3 "$P/scripts/install.py" --layout --city "$CITY" "$TG"

cat <<EOF

💙 Готово!
   • Выйди из системы и зайди снова — тогда подхватятся стиль окон, курсор и шрифты.
   • Цвет темы: ✦ слева сверху → радужный кружок (18 палитр, RGB, цвет обложки, свой).
   • Город погоды: правый клик по часам с погодой → «Настроить».
   • Вернуть как было: $P/scripts/rollback.sh
EOF
