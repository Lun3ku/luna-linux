#!/usr/bin/env bash
# Types text and presses keys in a running VM through QMP.
# It exists so the TUI installer can be exercised automatically, without
# anyone sitting at the keyboard.
#
#   vm-type.sh 'findmnt /' ret          type a string and press Enter
#   vm-type.sh down down ret            keys only
#   vm-type.sh ctrl+alt+f2              a key combination
#   vm-type.sh meta_l+ret               Super+Enter
#
# An argument is treated as a key if it appears in the list of known ones
# (ret, tab, esc, up, down, left, right, spc, backspace, f1..f12, ctrl, alt,
# shift, meta_l) or if it contains a "+", in which case it is a combination.
# Everything else is typed character by character.
set -euo pipefail

QMP_SOCK=${QMP_SOCK:-/var/luna/qmp.sock}
[[ -S "$QMP_SOCK" ]] || { printf 'QMP socket not found: %s (is the VM running?)\n' "$QMP_SOCK" >&2; exit 1; }

python3 - "$QMP_SOCK" "$@" <<'EOF'
import json, socket, sys, time

sock_path, *items = sys.argv[1:]
if items and items[0] == "--keys":
    items = items[1:]

KEYS = {"ret","tab","esc","spc","backspace","delete","up","down","left","right",
        "home","end","pgup","pgdn","insert","kp_enter","print",
        "ctrl","alt","shift","meta_l","meta_r",
        *(f"f{i}" for i in range(1, 13))}

# Character -> the key name in QEMU's terms; SHIFTED ones also need shift.
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
    raise SystemExit(f"do not know how to type the character: {ch!r}")

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
            raise RuntimeError("QMP closed the connection")
        reply = json.loads(line)
        if "event" in reply:
            continue
        if "error" in reply:
            raise RuntimeError(reply["error"].get("desc", reply["error"]))
        return reply.get("return")

def press(codes):
    call("send-key", keys=[{"type": "qcode", "data": c} for c in codes])
    time.sleep(0.03)   # without a pause the guest drops some of the keystrokes

f.readline()            # the server greeting
call("qmp_capabilities")

MODS = {"ctrl", "alt", "shift", "meta_l", "meta_r"}

for item in items:
    parts = [p.strip() for p in item.split("+") if p.strip()]
    # A combination is recognised by starting with a modifier, not merely by
    # containing a plus. Anything with a "+" in it used to be taken for one,
    # which made it impossible to type a line of text that happened to contain
    # a plus - a Hyprland binding such as "SUPER + F9", for instance, which is
    # exactly what one wants to type into a config while testing.
    # A leading modifier is the whole test. Requiring the other parts to be
    # known key names was tried and was wrong: QEMU has qcodes for far more
    # keys than the list above, "slash" among them, so meta_l+slash was
    # typed out as text instead of pressed.
    if len(parts) > 1 and parts[0] in MODS:
        # Every key is pressed at once, as in ctrl+alt+f2.
        press(parts)
    elif item in KEYS:
        press([item])
    else:
        for ch in item:
            press(codes_for(ch))
print("input sent")
EOF
