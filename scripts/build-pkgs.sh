#!/usr/bin/env bash
# Собирает пакеты luna-* и обновляет локальный репозиторий pacman.
# Запускать от root внутри LunaBuild.
#
#   build-pkgs.sh              собрать все пакеты
#   build-pkgs.sh luna-base    собрать только указанные
set -euo pipefail

LUNA_SRC=${LUNA_SRC:-/mnt/c/Users/anyah/Documents/Claudes work/luna}
LUNA_WORK=/var/luna
BUILD="$LUNA_WORK/pkgbuild"
REPO="$LUNA_WORK/repo"
REPO_DB="$REPO/luna.db.tar.gz"

msg() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m!!!\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Запускать от root: wsl -d LunaBuild -u root"
id -u builder >/dev/null 2>&1 || die "Нет пользователя builder — запусти scripts/bootstrap-host.sh"

names=("$@")
if [[ ${#names[@]} -eq 0 ]]; then
  mapfile -t names < <(cd "$LUNA_SRC/pkg" && ls -1d */ | tr -d '/')
fi

install -d "$BUILD" "$REPO"

for name in "${names[@]}"; do
  src="$LUNA_SRC/pkg/$name"
  [[ -f "$src/PKGBUILD" ]] || die "Нет PKGBUILD: $src"

  msg "Собираю $name"
  # Собираем на ext4: makepkg ставит права на файлы, а на DrvFs их нет.
  rm -rf "$BUILD/$name"
  install -d "$BUILD/$name"
  cp -rT "$src" "$BUILD/$name"
  chown -R builder:builder "$BUILD/$name"

  # -d (--nodeps): зависимости наших пакетов — это то, что нужно
  # установленной системе, а не сборочному хосту. Без этого флага makepkg
  # попытался бы притащить сюда весь Hyprland.
  sudo -u builder env -C "$BUILD/$name" makepkg -f -d --noconfirm --clean

  built=$(find "$BUILD/$name" -maxdepth 1 -name '*.pkg.tar.*' -printf '%p\n' | head -n1)
  [[ -n "$built" ]] || die "$name: пакет не собрался"
  install -m644 "$built" "$REPO/"
  msg "  → $(basename "$built")"
done

msg "Обновляю репозиторий $REPO"
repo-add -q "$REPO_DB" "$REPO"/*.pkg.tar.* >/dev/null

msg "Содержимое репозитория:"
ls -1sh "$REPO"/*.pkg.tar.* | sed 's/^/  /'
echo
msg "Пакетов в базе: $(tar tzf "$REPO_DB" 2>/dev/null | grep -c '/desc$' || echo 0)"
