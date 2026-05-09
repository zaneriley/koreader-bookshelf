#!/usr/bin/env bash
set -euo pipefail

export DISPLAY="${DISPLAY:-:99}"
export KO_HOME="${KO_HOME:-/preview-home}"
export HOME="${HOME:-/root}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg-runtime-root}"
export EMULATE_READER_W="${EMULATE_READER_W:-1404}"
export EMULATE_READER_H="${EMULATE_READER_H:-1872}"
export EMULATE_READER_DPI="${EMULATE_READER_DPI:-226}"
export KOREADER_ARGS="${KOREADER_ARGS:--d}"

mkdir -p "${KO_HOME}" "${KO_HOME}/screenshots" "${XDG_RUNTIME_DIR}" /tmp/.X11-unix
chmod 700 "${XDG_RUNTIME_DIR}"
if [ -d /work ]; then
    mkdir -p /home/ko
    ln -sfn /work /home/ko/koreader
fi

Xvfb "${DISPLAY}" -screen 0 "${EMULATE_READER_W}x${EMULATE_READER_H}x24" -nolisten tcp &
xvfb_pid="$!"

sleep 0.5
x11vnc -display "${DISPLAY}" -forever -shared -nopw -listen 0.0.0.0 -rfbport 5900 >/tmp/x11vnc.log 2>&1 &
x11vnc_pid="$!"

websockify --web=/usr/share/novnc/ 0.0.0.0:6080 localhost:5900 >/tmp/novnc.log 2>&1 &
novnc_pid="$!"

cleanup() {
    kill "${novnc_pid}" "${x11vnc_pid}" "${xvfb_pid}" 2>/dev/null || true
}
trap cleanup EXIT

cd /kobuild/install/koreader
./luajit reader.lua ${KOREADER_ARGS} &
koreader_pid="$!"

echo "noVNC ready: http://localhost:6080/vnc.html?autoconnect=true&resize=scale"
echo "KOReader PID: ${koreader_pid}"
wait "${koreader_pid}"
