#!/usr/bin/env bash
# Собирает пакеты luna-* и обновляет локальный репозиторий pacman.
# Запускать от root внутри LunaBuild.
#
#   build-pkgs.sh              собрать все пакеты
#   build-pkgs.sh luna-base    собрать только указанные
#
# Все пакеты подписываются ключом Luna, база репозитория — тоже. Ключ
# создаёт scripts/make-signing-key.sh, его секретная часть живёт только в
# ~builder/.gnupg на этой машине; резервная копия — E:\Luna-Linux-Keys.
set -euo pipefail

LUNA_SRC=${LUNA_SRC:-/mnt/c/Users/anyah/Documents/Claudes work/luna}
LUNA_WORK=/var/luna
BUILD="$LUNA_WORK/pkgbuild"
REPO="$LUNA_WORK/repo"
REPO_DB="$REPO/luna.db.tar.gz"
KEYRING_DIR="$LUNA_SRC/pkg/luna-keyring"

msg() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m!!!\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Запускать от root: wsl -d LunaBuild -u root"
id -u builder >/dev/null 2>&1 || die "Нет пользователя builder — запусти scripts/bootstrap-host.sh"

# --- ключ подписи -----------------------------------------------------------
# Отпечаток берём из того же файла, который уезжает в пакет luna-keyring:
# так подпись и доверие к ней не могут разъехаться между собой.
[[ -f "$KEYRING_DIR/luna-trusted" ]] || die "Нет $KEYRING_DIR/luna-trusted — запусти scripts/make-signing-key.sh"
FPR=$(cut -d: -f1 "$KEYRING_DIR/luna-trusted")
[[ -n $FPR ]] || die "Пустой отпечаток в luna-trusted"

sudo -u builder gpg --list-secret-keys "$FPR" >/dev/null 2>&1 \
  || die "У builder нет секретного ключа $FPR.
       Создать новый:      scripts/make-signing-key.sh
       Восстановить копию: sudo -u builder gpg --import /mnt/e/Luna-Linux-Keys/luna-signing-SECRET.asc"

# Сборочный хост должен доверять ключу сам: mkarchiso ставит наши пакеты в
# образ обычным pacman, а тот теперь проверяет подписи по-настоящему.
if ! pacman-key --list-keys "$FPR" >/dev/null 2>&1; then
  msg "Регистрирую ключ в связке pacman сборочного хоста"
  pacman-key --add "$KEYRING_DIR/luna.gpg" >/dev/null
  pacman-key --lsign-key "$FPR" >/dev/null 2>&1
fi

msg "Подписываю ключом $FPR"

names=("$@")
if [[ ${#names[@]} -eq 0 ]]; then
  mapfile -t names < <(cd "$LUNA_SRC/pkg" && ls -1d */ | tr -d '/')
fi

# Репозиторий держим за builder: repo-add подписывает базу, а ключ есть
# только у него. Root всё равно может писать сюда при необходимости.
install -d -o builder -g builder "$BUILD" "$REPO"
chown -R builder:builder "$REPO"

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
  # --sign --key: подпись кладётся рядом файлом .sig; ключ без парольной
  # фразы, поэтому сборка не останавливается на вопросе.
  sudo -u builder env -C "$BUILD/$name" makepkg -f -d --noconfirm --clean --sign --key "$FPR"

  built=$(find "$BUILD/$name" -maxdepth 1 -name '*.pkg.tar.*' ! -name '*.sig' -printf '%p\n' | head -n1)
  [[ -n "$built" ]] || die "$name: пакет не собрался"
  [[ -f "$built.sig" ]] || die "$name: пакет собрался без подписи"

  # Старые версии этого же пакета убираем: иначе в каталоге копится хлам,
  # а вместе с ним и подписи, к которым уже нет записи в базе.
  find "$REPO" -maxdepth 1 -name "$name-[0-9]*.pkg.tar.*" -delete

  install -o builder -g builder -m644 "$built"     "$REPO/"
  install -o builder -g builder -m644 "$built.sig" "$REPO/"

  # Из кэша pacman копию прошлой сборки надо убрать. Версия пакета не
  # меняется от пересборки, а содержимое меняется — и pacman, найдя в кэше
  # файл с нужным именем, сверит его с новой подписью и объявит
  # повреждённым. Так уже падала сборка образа.
  rm -f "/var/cache/pacman/pkg/$(basename "$built")"         "/var/cache/pacman/pkg/$(basename "$built").sig"

  msg "  → $(basename "$built") + подпись"
done

msg "Обновляю репозиторий $REPO"
mapfile -t pkgfiles < <(find "$REPO" -maxdepth 1 -name '*.pkg.tar.*' ! -name '*.sig' | sort)
[[ ${#pkgfiles[@]} -gt 0 ]] || die "В репозитории нет пакетов"
# Базу пересобираем с нуля, а не дописываем: список пакетов передаётся
# целиком, так что старые записи об удалённых пакетах не переживут сборку.
# Заодно это снимает проблему первого запуска — repo-add не пришлось бы
# проверять подпись базы, которой ещё нет.
rm -f "$REPO_DB" "$REPO_DB.sig" "${REPO_DB%.tar.gz}.files.tar.gz"       "$REPO/luna.files.tar.gz" "$REPO/luna.files.tar.gz.sig"
# --include-sigs кладёт подпись пакета прямо в базу: иначе pacman ищет
# файл .sig рядом с пакетом, и любая потеря этих файлов при копировании
# репозитория молча превращает проверку в её отсутствие.
#
# Сама база НЕ подписывается, и это осознанно. Arch не подписывает свои
# базы по той же причине: подпись базы защищала бы только список пакетов,
# тогда как каждый пакет в списке и так несёт собственную подпись внутри
# базы. Подменить пакет чужим она не позволит в любом случае.
# Практический вред от подписи базы был измерен: mkarchiso в конце сборки
# зовёт pacman -Q --sysroot по образу, у образа своей связки ключей нет
# (archiso создаёт её только при загрузке, сервисом pacman-init), и сборка
# начинала выдавать «key is unknown / keyring is not writable». Ошибки в
# логе сборки, которые ничего не значат, — верный способ не заметить
# настоящую.
sudo -u builder repo-add -q --include-sigs "$REPO_DB" "${pkgfiles[@]}" >/dev/null
# repo-add оставляет позади прошлую версию базы. В репозиторий, который
# целиком уезжает на образ, этот хвост тащить незачем.
rm -f "$REPO"/*.old

msg "Содержимое репозитория:"
ls -1sh "$REPO"/*.pkg.tar.zst | sed 's/^/  /'
echo
msg "Пакетов в базе: $(tar tzf "$REPO_DB" 2>/dev/null | grep -c '/desc$' || echo 0)"

# Подпись, которой нет в базе, pacman проигнорирует — проверяем, что поле
# %PGPSIG% реально записано для каждого пакета, а не только лежит файлом.
signed_in_db=$(tar xzOf "$REPO_DB" --wildcards '*/desc' 2>/dev/null | grep -c '^%PGPSIG%$' || true)
msg "Из них с подписью в базе: $signed_in_db"
[[ "$signed_in_db" -eq "${#pkgfiles[@]}" ]] \
  || die "Подписаны не все: пакетов ${#pkgfiles[@]}, подписей в базе $signed_in_db"
