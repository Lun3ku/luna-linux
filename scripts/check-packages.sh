#!/usr/bin/env bash
# Checks that every package name listed actually exists in the repositories.
# Arch is rolling: packages get renamed, merged and dropped, so the lists have
# to be re-checked rather than found broken halfway through a build.
#
# The check uses the profile's pacman.conf, which means our [luna] repository
# is included, so typos in our own names such as luna-relese get caught too.
#
#   check-packages.sh [file ...]   defaults to iso/packages.x86_64
set -euo pipefail

LUNA_SRC=${LUNA_SRC:-/mnt/c/Users/anyah/Documents/Claudes work/luna}
CONF=/tmp/luna-check-pacman.conf
DB=/tmp/luna-check-db

files=("$@")
[[ ${#files[@]} -gt 0 ]] || files=("$LUNA_SRC/iso/packages.x86_64")

names=()
for f in "${files[@]}"; do
  [[ -f "$f" ]] || { printf 'no such file: %s\n' "$f" >&2; exit 1; }
  while read -r line; do
    line=${line%%#*}
    line=$(tr -d '[:space:]' <<<"$line")
    [[ -n "$line" ]] && names+=("$line")
  done < "$f"
done

# The databases are synced at most once an hour: a full sync on every run would
# turn a quick check into a wait.
cp "$LUNA_SRC/iso/pacman.conf" "$CONF"
if [[ ! -d $DB/sync ]] || [[ -n $(find "$DB/sync" -name 'core.db' -mmin +60 2>/dev/null) ]]; then
  mkdir -p "$DB"
  printf '\033[1;36m==>\033[0m Syncing the package databases\n'
  pacman --config "$CONF" --dbpath "$DB" -Sy >/dev/null 2>&1 || true
fi

q() { pacman --config "$CONF" --dbpath "$DB" "$@" 2>/dev/null; }

printf '\033[1;36m==>\033[0m Checking %d names\n' "${#names[@]}"
missing=0
for p in "${names[@]}"; do
  q -Si "$p" >/dev/null && continue
  # A name may not be a package but a group (base-devel used to be one) or a
  # virtual provide (ttf-font, pulse-native-provider).
  [[ -n $(q -Sgq "$p") ]] && continue
  [[ -n $(q -Ssq "^${p}\$") ]] && continue
  printf '  \033[1;31mMISSING\033[0m  %s\n' "$p"
  missing=$((missing + 1))
done

if (( missing )); then
  printf '\033[1;31m!!!\033[0m Packages not found: %d\n' "$missing"
  printf '    If it is one of our own luna-* packages, build it first: scripts/build-pkgs.sh\n'
  exit 1
fi
printf '\033[1;32m==>\033[0m All names are valid\n'
