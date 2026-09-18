#!/usr/bin/env bash
# Проверяет, что все перечисленные имена пакетов существуют в репозиториях.
# Arch — rolling: пакеты переименовывают, объединяют и выкидывают, поэтому
# списки надо перепроверять, а не узнавать о пропаже в середине сборки.
#
# Проверка идёт по профильному pacman.conf, то есть включая наш [luna] —
# так ловятся опечатки и в собственных именах вроде luna-relese.
#
#   check-packages.sh [файл ...]   по умолчанию — iso/packages.x86_64
set -euo pipefail

LUNA_SRC=${LUNA_SRC:-/mnt/c/Users/anyah/Documents/Claudes work/luna}
CONF=/tmp/luna-check-pacman.conf
DB=/tmp/luna-check-db

files=("$@")
[[ ${#files[@]} -gt 0 ]] || files=("$LUNA_SRC/iso/packages.x86_64")

names=()
for f in "${files[@]}"; do
  [[ -f "$f" ]] || { printf 'нет файла: %s\n' "$f" >&2; exit 1; }
  while read -r line; do
    line=${line%%#*}
    line=$(tr -d '[:space:]' <<<"$line")
    [[ -n "$line" ]] && names+=("$line")
  done < "$f"
done

# Базы синхронизируем не чаще раза в час — полная синхронизация на каждый
# запуск превращала бы быструю проверку в ожидание.
cp "$LUNA_SRC/iso/pacman.conf" "$CONF"
if [[ ! -d $DB/sync ]] || [[ -n $(find "$DB/sync" -name 'core.db' -mmin +60 2>/dev/null) ]]; then
  mkdir -p "$DB"
  printf '\033[1;36m==>\033[0m Синхронизирую базы пакетов\n'
  pacman --config "$CONF" --dbpath "$DB" -Sy >/dev/null 2>&1 || true
fi

q() { pacman --config "$CONF" --dbpath "$DB" "$@" 2>/dev/null; }

printf '\033[1;36m==>\033[0m Проверяю %d имён\n' "${#names[@]}"
missing=0
for p in "${names[@]}"; do
  q -Si "$p" >/dev/null && continue
  # Имя может быть не пакетом, а группой (например base-devel раньше) или
  # виртуальным provide (ttf-font, pulse-native-provider).
  [[ -n $(q -Sgq "$p") ]] && continue
  [[ -n $(q -Ssq "^${p}\$") ]] && continue
  printf '  \033[1;31mНЕТ\033[0m  %s\n' "$p"
  missing=$((missing + 1))
done

if (( missing )); then
  printf '\033[1;31m!!!\033[0m Не найдено пакетов: %d\n' "$missing"
  printf '    Если это наш пакет luna-* — сначала собери его: scripts/build-pkgs.sh\n'
  exit 1
fi
printf '\033[1;32m==>\033[0m Все имена валидны\n'
