#!/usr/bin/env bash
# Сборка ISO Luna Linux. Запускать от root внутри LunaBuild.
#
# Профиль лежит на диске Windows (DrvFs), где нет юниксовых прав доступа,
# поэтому перед сборкой он синхронизируется на ext4. Права на файлы, которым
# они важны, всё равно задаются массивом file_permissions в profiledef.sh.
set -euo pipefail

LUNA_SRC=${LUNA_SRC:-/mnt/c/Users/anyah/Documents/Claudes work/luna}
LUNA_WORK=/var/luna

msg() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m!!!\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Запускать от root: wsl -d LunaBuild -u root"
[[ -d "$LUNA_SRC/iso" ]] || die "Профиль не найден: $LUNA_SRC/iso"
command -v mkarchiso >/dev/null || die "archiso не установлен — запусти scripts/bootstrap-host.sh"

msg "Синхронизирую профиль на ext4"
install -d "$LUNA_WORK"/{src,work,out,repo}
rsync -a --delete --no-perms --no-owner --no-group --chmod=D755,F644 \
  "$LUNA_SRC/iso/" "$LUNA_WORK/src/iso/"

# Скрипты внутри оверлея должны остаться исполняемыми.
find "$LUNA_WORK/src/iso/airootfs" -type f \
  \( -path '*/bin/*' -o -name '*.sh' -o -name '.zlogin' -o -name '.profile' \) \
  -exec chmod 755 {} + 2>/dev/null || true

# Репозиторий luna кладём ВНУТРЬ образа. Без этого установщик не сможет
# поставить пакеты luna-* на целевой диск: pacstrap ищет их в репозиториях,
# а своего сервера в сети у нас пока нет.
REPO_ON_ISO=usr/share/luna/repo
if [[ -z "$(ls -A "$LUNA_WORK/repo" 2>/dev/null)" ]]; then
  die "Репозиторий $LUNA_WORK/repo пуст — сначала scripts/build-pkgs.sh"
fi
msg "Кладу репозиторий luna в образ ($REPO_ON_ISO)"
install -d "$LUNA_WORK/src/iso/airootfs/$REPO_ON_ISO"
rsync -a --delete --no-perms --no-owner --no-group --chmod=D755,F644   "$LUNA_WORK/repo/" "$LUNA_WORK/src/iso/airootfs/$REPO_ON_ISO/"

# /etc/pacman.conf живой системы генерируем из профильного, подменив путь
# к репозиторию: при сборке это file:///var/luna/repo на хосте, а внутри
# запущенного образа — /usr/share/luna/repo. Так остаётся один источник
# правды вместо двух файлов, которые пришлось бы держать в синхроне.
msg "Готовлю /etc/pacman.conf для живой системы"
install -d "$LUNA_WORK/src/iso/airootfs/etc"
sed "s|^Server = file:///var/luna/repo|Server = file:///$REPO_ON_ISO|"   "$LUNA_SRC/iso/pacman.conf" > "$LUNA_WORK/src/iso/airootfs/etc/pacman.conf"
grep -q "file:///$REPO_ON_ISO" "$LUNA_WORK/src/iso/airootfs/etc/pacman.conf"   || die "Не удалось подменить путь к репозиторию в pacman.conf"

msg "Чищу рабочий каталог прошлой сборки"
rm -rf "${LUNA_WORK:?}/work"
install -d "$LUNA_WORK/work"

msg "Запускаю mkarchiso"
time mkarchiso -v -w "$LUNA_WORK/work" -o "$LUNA_WORK/out" "$LUNA_WORK/src/iso"

msg "Готовые образы:"
ls -lh "$LUNA_WORK/out"
