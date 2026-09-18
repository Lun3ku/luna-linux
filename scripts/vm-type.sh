#!/usr/bin/env bash
# Набор текста и нажатие клавиш в работающей виртуалке через QMP.
# Нужен, чтобы проверять TUI-установщик автоматически, не сидя за клавиатурой.
#
#   vm-type.sh 'findmnt /' ret          напечатать строку и нажать Enter
#   vm-type.sh down down ret            только клавиши
#   vm-type.sh ctrl+alt+f2              сочетание клавиш
#   vm-type.sh meta_l+ret               Super+Enter
#
# Аргумент считается клавишей, если он есть в списке известных
# (ret, tab, esc, up, down, left, right, spc, backspace, f1..f12,
# ctrl, alt, shift, meta_l) или содержит «+» — тогда это сочетание.
# Всё остальное печатается посимвольно.
set -euo pipefail

QMP_SOCK=${QMP_SOCK:-/var/luna/qmp.sock}
[[ -S "$QMP_SOCK" ]] || { printf 'QMP-сокет не найден: %s (виртуалка запущена?)\n' "$QMP_SOCK" >&2; exit 1; }

python3 - "$QMP_SOCK" "$@" <<'EOF'
import json, socket, sys, time

sock_path, *items = sys.argv[1:]
if items and items[0] == "--keys":
    items = items[1:]

KEYS = {"ret","tab","esc","spc","backspace","delete","up","down","left","right",
        "home","end","pgup","pgdn","insert","kp_enter","print",
        "ctrl","alt","shift","meta_l","meta_r",
        *(f"f{i}" for i in range(1, 13))}

# Символ -> (нужен ли shift, имя клавиши в терминах QEMU).
PLAIN = {" ":"spc","-":"minus","=":"equal","[":"bracket_left","]":"bracket_right",
         ";":"semicolon","'":"apostrophe","`":"grave_accent","\\":"backslash",
         ",":"comma",".":"dot","/":"slash","\n":"ret","\t":"tab"}
SHIFTED = {"!":"1","@":"2","#":"3","$":"4","%":"5","^":"6","&":"7","*":"8",
           "(":"9",")":"0","_":"minus","+":"equal","{":"bracket_left",
           "}":"bracket_right",":":"semicolon",'"':"apostrophe","~":"grave_accent",
           "|":"backslash","<":"comma",">":"dot","?":"slash"}

def codes_for(ch):
    if ch.islower() or ch.isdigit():
        return [ch]
    if ch.isupper():
        return ["shift", ch.lower()]
    if ch in PLAIN:
        return [PLAIN[ch]]
    if ch in SHIFTED:
        return ["shift", SHIFTED[ch]]
    raise SystemExit(f"не знаю, как набрать символ: {ch!r}")

s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(15)
s.connect(sock_path)
f = s.makefile("rw", encoding="utf-8", newline="\n")

def call(cmd, **args):
    f.write(json.dumps({"execute": cmd, **({"arguments": args} if args else {})}) + "\n")
    f.flush()
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

def press(codes):
    call("send-key", keys=[{"type": "qcode", "data": c} for c in codes])
    time.sleep(0.03)   # без паузы гость теряет часть нажатий

f.readline()            # приветствие сервера
call("qmp_capabilities")

for item in items:
    if "+" in item and len(item) > 1:
        # Сочетание: все клавиши нажимаются одновременно, как ctrl+alt+f2.
        press([p.strip() for p in item.split("+") if p.strip()])
    elif item in KEYS:
        press([item])
    else:
        for ch in item:
            press(codes_for(ch))
print("ввод отправлен")
EOF
