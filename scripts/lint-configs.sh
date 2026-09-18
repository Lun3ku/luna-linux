#!/usr/bin/env bash
# Проверка синтаксиса всех конфигов Luna. Запускать перед сборкой:
# битый конфиг оборачивается не ошибкой сборки, а неработающим
# рабочим столом у пользователя, и ловить это в собранном образе долго.
set -uo pipefail

LUNA_SRC=${LUNA_SRC:-/mnt/c/Users/anyah/Documents/Claudes work/luna}
D="$LUNA_SRC/pkg/luna-desktop"
C="$LUNA_SRC/pkg/luna-cli"
I="$LUNA_SRC/iso"
fail=0

check() { # имя команда...
  printf '  %-16s ' "$1"; shift
  if out=$("$@" 2>&1); then printf '\033[1;32mOK\033[0m\n'
  else printf '\033[1;31mОШИБКА\033[0m\n%s\n' "$out"; fail=$((fail+1)); fi
}

lua_ok() { lua -e "local f,e=loadfile([[$1]]); if not f then io.stderr:write(tostring(e)) os.exit(1) end"; }
json_ok() { python3 -c "
import json,re,sys
s=open(sys.argv[1],encoding='utf-8').read()
json.loads(re.sub(r'^\s*//.*\$','',s,flags=re.M))" "$1"; }
toml_ok() { python3 -c "import tomllib,sys; tomllib.load(open(sys.argv[1],'rb'))" "$1"; }
# Глифы иконок обязаны быть escape-последовательностями, а не живыми
# символами: приватная область Unicode теряется при передаче файлов.
glyphs_ascii() { python3 -c "
import sys
s=open(sys.argv[1],encoding='utf-8').read()
bad=[c for c in s if 0xE000 <= ord(c) <= 0xF8FF]
if bad:
    sys.stderr.write('в файле %d живых глифов приватной области; нужны escape-последовательности' % len(bad))
    sys.exit(1)" "$1"; }

printf '\033[1;36m==>\033[0m Проверяю конфиги\n'
check "hyprland.lua"   lua_ok       "$D/hyprland.lua"
check "config.fish"    fish -n      "$C/config.fish"
check "waybar json"    json_ok      "$D/waybar-config.jsonc"
check "waybar глифы"   glyphs_ascii "$D/waybar-config.jsonc"
check "greetd toml"    toml_ok      "$D/greetd-luna.toml"
check "greetd live"    toml_ok      "$I/airootfs/etc/greetd/luna.toml"
check "sudoers live"   visudo -cqf  "$I/airootfs/etc/sudoers.d/10-luna-live"
check "live-user.sh"   bash -n      "$I/airootfs/usr/local/bin/luna-live-user"
check "profiledef.sh"  bash -n      "$I/profiledef.sh"

if (( fail )); then
  printf '\033[1;31m!!!\033[0m Проблем: %d\n' "$fail"; exit 1
fi
printf '\033[1;32m==>\033[0m Все конфиги валидны\n'
