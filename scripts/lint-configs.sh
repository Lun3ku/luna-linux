#!/usr/bin/env bash
# Syntax check for every Luna config. Run it before a build: a broken config
# does not surface as a build error but as a broken desktop on the user's
# machine, and hunting that down inside a finished image takes a long time.
set -uo pipefail

LUNA_SRC=${LUNA_SRC:-/mnt/c/Users/anyah/Documents/Claudes work/luna}
D="$LUNA_SRC/pkg/luna-desktop"
C="$LUNA_SRC/pkg/luna-cli"
I="$LUNA_SRC/iso"
fail=0

check() { # name command...
  printf '  %-16s ' "$1"; shift
  if out=$("$@" 2>&1); then printf '\033[1;32mOK\033[0m\n'
  else printf '\033[1;31mFAILED\033[0m\n%s\n' "$out"; fail=$((fail+1)); fi
}

lua_ok() { lua -e "local f,e=loadfile([[$1]]); if not f then io.stderr:write(tostring(e)) os.exit(1) end"; }
json_ok() { python3 -c "
import json,re,sys
s=open(sys.argv[1],encoding='utf-8').read()
json.loads(re.sub(r'^\s*//.*\$','',s,flags=re.M))" "$1"; }
toml_ok() { python3 -c "import tomllib,sys; tomllib.load(open(sys.argv[1],'rb'))" "$1"; }
# Icon glyphs have to be escape sequences rather than literal characters: the
# Unicode private use area gets lost when files are passed around.
glyphs_ascii() { python3 -c "
import sys
s=open(sys.argv[1],encoding='utf-8').read()
bad=[c for c in s if 0xE000 <= ord(c) <= 0xF8FF]
if bad:
    sys.stderr.write('%d literal private-use glyphs in the file; escape sequences are required' % len(bad))
    sys.exit(1)" "$1"; }

# Package signing is easy to switch off by accident: putting TrustAll back in
# one place is enough for verification to quietly stop meaning anything. Look
# in every file that sets SigLevel for the luna repository.
no_trustall() { python3 -c "
import sys
bad=[]
for path in sys.argv[1:]:
    for n,line in enumerate(open(path,encoding='utf-8'),1):
        t=line.strip()
        if t.startswith('#'): continue
        if 'SigLevel' in t and 'TrustAll' in t:
            bad.append('%s:%d: %s' % (path,n,t))
if bad:
    sys.stderr.write('signature verification is disabled: ' + '; '.join(bad))
    sys.exit(1)" "$@"; }
# The fingerprint in luna-trusted has to match the key in luna.gpg: otherwise
# pacman-key imports the key but never marks it trusted, and signed packages
# get rejected as somebody else's.
keyring_match() { python3 -c "
import subprocess,sys
d=sys.argv[1]
want=open(d+'/luna-trusted',encoding='utf-8').read().split(':')[0].strip()
out=subprocess.run(['gpg','--with-colons','--show-keys',d+'/luna.gpg'],
                   capture_output=True,text=True).stdout
got=[l.split(':')[9] for l in out.splitlines() if l.startswith('fpr:')]
if want not in got:
    sys.stderr.write('luna-trusted says %s, luna.gpg says %s' % (want, got))
    sys.exit(1)" "$1"; }

printf '\033[1;36m==>\033[0m Checking the configs\n'
check "hyprland.lua"   lua_ok       "$D/hyprland.lua"
check "config.fish"    fish -n      "$C/config.fish"
check "waybar json"    json_ok      "$D/waybar-config.jsonc"
check "waybar glyphs"  glyphs_ascii "$D/waybar-config.jsonc"
check "greetd toml"    toml_ok      "$D/greetd-luna.toml"
check "greetd live"    toml_ok      "$I/airootfs/etc/greetd/luna.toml"
check "sudoers live"   visudo -cqf  "$I/airootfs/etc/sudoers.d/10-luna-live"
check "live-user.sh"   bash -n      "$I/airootfs/usr/local/bin/luna-live-user"
check "profiledef.sh"  bash -n      "$I/profiledef.sh"
check "repo signing"   no_trustall   "$I/pacman.conf" "$LUNA_SRC/pkg/luna-installer/luna-install"
check "keyring match"  keyring_match "$LUNA_SRC/pkg/luna-keyring"

if (( fail )); then
  printf '\033[1;31m!!!\033[0m Problems: %d\n' "$fail"; exit 1
fi
printf '\033[1;32m==>\033[0m Every config is valid\n'
