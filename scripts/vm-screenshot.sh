#!/usr/bin/env bash
# Снимок экрана работающей в QEMU виртуалки через сокет QMP.
# Нужен, чтобы проверять графическую часть дистрибутива, не полагаясь
# на то, что кто-то смотрит в окно.
#
#   vm-screenshot.sh [путь.png]
set -euo pipefail

QMP_SOCK=${QMP_SOCK:-/var/luna/qmp.sock}
OUT=${1:-/var/luna/screenshot.png}

[[ -S "$QMP_SOCK" ]] || { printf 'QMP-сокет не найден: %s (виртуалка запущена?)\n' "$QMP_SOCK" >&2; exit 1; }

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
    # Между ответами QEMU шлёт асинхронные события — их пропускаем.
    while True:
        line = f.readline()
        if not line:
            raise RuntimeError("QMP закрыл соединение")
        reply = json.loads(line)
        if "event" in reply:
            continue
        if "error" in reply:
            raise RuntimeError(reply["error"].get("desc", reply["error"]))
        return reply.get("return")

f.readline()            # приветствие сервера
call("qmp_capabilities")
call("screendump", filename=out, format="png")
print(f"снимок сохранён: {out}")
EOF
