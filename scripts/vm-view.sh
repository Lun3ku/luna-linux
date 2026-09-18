#!/usr/bin/env bash
# A noVNC web client for watching the VM screen in an ordinary browser.
# The WSLg window does not appear on every machine, whereas this path always
# works: the page is served over localhost and WSL2 forwards the port into
# Windows by itself.
#
# Run it as a long-lived process: the server stays up as long as the script does.
set -euo pipefail

WWW=/var/luna/www
PORT=${PORT:-8080}
VNC_WS=${VNC_WS:-5700}

msg() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

if [[ ! -f "$WWW/novnc/vnc.html" ]]; then
  msg "Downloading noVNC"
  install -d "$WWW"
  rm -rf "$WWW/novnc"
  git clone --depth 1 -q https://github.com/novnc/noVNC "$WWW/novnc"
fi

# path= is mandatory and must be empty: by default noVNC knocks on /websockify,
# while the websocket built into QEMU serves VNC only at the root "/" and
# answers 404 anywhere else.
msg "Viewing address:"
printf 'http://localhost:%s/novnc/vnc.html?host=localhost&port=%s&path=&autoconnect=true&resize=scale&reconnect=true\n' \
  "$PORT" "$VNC_WS"

exec python3 -m http.server "$PORT" --directory "$WWW" --bind 0.0.0.0
