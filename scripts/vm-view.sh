#!/usr/bin/env bash
# Веб-клиент noVNC для просмотра экрана виртуалки в обычном браузере.
# Окно WSLg всплывает не на всех машинах, а этот путь работает всегда:
# страница отдаётся по localhost, а WSL2 сам пробрасывает порт в Windows.
#
# Запускать как долгоживущий процесс — сервер держится, пока жив скрипт.
set -euo pipefail

WWW=/var/luna/www
PORT=${PORT:-8080}
VNC_WS=${VNC_WS:-5700}

msg() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

if [[ ! -f "$WWW/novnc/vnc.html" ]]; then
  msg "Скачиваю noVNC"
  install -d "$WWW"
  rm -rf "$WWW/novnc"
  git clone --depth 1 -q https://github.com/novnc/noVNC "$WWW/novnc"
fi

# path= обязателен и пустой: noVNC по умолчанию стучится в /websockify, а
# встроенный websocket QEMU отдаёт VNC только по корню «/», иначе 404.
msg "Адрес просмотра:"
printf 'http://localhost:%s/novnc/vnc.html?host=localhost&port=%s&path=&autoconnect=true&resize=scale&reconnect=true\n' \
  "$PORT" "$VNC_WS"

exec python3 -m http.server "$PORT" --directory "$WWW" --bind 0.0.0.0
