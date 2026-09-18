#!/usr/bin/env bash
# Takes a screenshot of a VM running under QEMU through the QMP socket.
# It exists so the graphical side of the distribution can be checked without
# relying on somebody watching the window.
#
#   vm-screenshot.sh [path.png]
set -euo pipefail

QMP_SOCK=${QMP_SOCK:-/var/luna/qmp.sock}
OUT=${1:-/var/luna/screenshot.png}

[[ -S "$QMP_SOCK" ]] || { printf 'QMP socket not found: %s (is the VM running?)\n' "$QMP_SOCK" >&2; exit 1; }

python3 - "$QMP_SOCK" "$OUT" <<'EOF'
import json, socket, sys

sock_path, out = sys.argv[1], sys.argv[2]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(15)
s.connect(sock_path)
f = s.makefile("rw", encoding="utf-8", newline="\n")

def call(cmd, **args):
    msg = {"execute": cmd}
    if args:
        msg["arguments"] = args
    f.write(json.dumps(msg) + "\n")
    f.flush()
    # QEMU sends asynchronous events between replies; skip them.
    while True:
        line = f.readline()
        if not line:
            raise RuntimeError("QMP closed the connection")
        reply = json.loads(line)
        if "event" in reply:
            continue
        if "error" in reply:
            raise RuntimeError(reply["error"].get("desc", reply["error"]))
        return reply.get("return")

f.readline()            # the server greeting
call("qmp_capabilities")
call("screendump", filename=out, format="png")
print(f"screenshot saved: {out}")
EOF
