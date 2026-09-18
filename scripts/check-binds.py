import re
import sys

# Every key combination bound in hyprland.lua, checked for being bound twice.
# Super+L was the lock screen and, thirty lines further down, focus to the
# right. Both bindings were live and nothing said so.
#
# Bindings whose key is computed rather than written out - the workspace loop
# builds its own from a counter - are skipped: they cannot be read off the
# source, and they are generated from a single line anyway.
text = open(sys.argv[1], encoding="utf-8").read()

seen = {}
dupes = []
for num, line in enumerate(text.split("\n"), 1):
    m = re.match(r"\s*hl\.bind\(([^,]*),", line)
    if not m:
        continue
    expr = m.group(1).strip()
    # mod is the one variable that is a constant in practice.
    expr = expr.replace("mod ..", '"SUPER" ..')
    parts = re.findall(r'"([^"]*)"', expr)
    # Anything left outside quotes after that is a variable: a computed key.
    stripped = re.sub(r'"[^"]*"', "", expr).replace("..", "").strip()
    if stripped:
        continue
    combo = "".join(parts)
    keys = [p.strip().upper() for p in combo.split("+") if p.strip()]
    if not keys:
        continue
    mods = sorted(k for k in keys if k in ("SUPER", "SHIFT", "CTRL", "ALT"))
    rest = [k for k in keys if k not in ("SUPER", "SHIFT", "CTRL", "ALT")]
    norm = "+".join(mods + rest)
    if norm in seen:
        dupes.append("%s bound at line %d and again at line %d" % (norm, seen[norm], num))
    else:
        seen[norm] = num

if dupes:
    sys.stderr.write("; ".join(dupes))
    sys.exit(1)
if len(seen) < 20:
    sys.stderr.write("only %d bindings found - the parser is probably not "
                     "matching the file any more" % len(seen))
    sys.exit(1)
