#!/usr/bin/env bash
# preview.sh <qml> <out.png> [w h delay]  — GPU offscreen render with Plasma stubs
P=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
QT_FORCE_STDERR_LOGGING=1 QT_QUICK_BACKEND=rhi QSG_RHI_BACKEND=opengl QML_IMPORT_PATH=$P/tools/stubs:${EXTRA_IMPORT:-} QT_QPA_PLATFORM=offscreen \
 timeout 30 qml6 "$P/tools/grab.qml" -- "$(realpath "$1")" "$2" "${3:-1920}" "${4:-1080}" "${5:-4000}" 2>&1 | grep -vE '^\s*$|Animation Driver' | tail -${LOGN:-6}
