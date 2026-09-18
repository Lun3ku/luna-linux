#!/usr/bin/env bash
# Создаёт ключ, которым подписываются пакеты Luna.
#
# Запускать один раз. Повторный запуск ничего не портит: если ключ уже
# есть, скрипт только переэкспортирует публичную часть.
#
# ГДЕ ЖИВЁТ СЕКРЕТНАЯ ЧАСТЬ. Только в связке ключей пользователя builder
# на сборочном хосте (~builder/.gnupg). В репозиторий она не попадает и
# попасть не должна — там лежит лишь публичная часть и отпечаток.
#
# ПРО ОТСУТСТВИЕ ПАРОЛЯ. Ключ без парольной фразы: сборка пакетов должна
# идти без запроса пароля на каждый пакет. Для локального ключа личного
# дистрибутива это разумный размен — тот, кто получил доступ к сборочной
# машине, всё равно может подменить сами пакеты до подписи. Если Luna
# когда-нибудь станет публичной, ключ надо переделать с паролем и держать
# подпись отдельно от сборки.
set -euo pipefail

LUNA_SRC=${LUNA_SRC:-/mnt/c/Users/anyah/Documents/Claudes work/luna}
KEYRING_DIR="$LUNA_SRC/pkg/luna-keyring"
UID_NAME="Luna Linux"
UID_MAIL="luna@localhost"

msg() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m!!!\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Запускать от root: wsl -d LunaBuild -u root"
id -u builder >/dev/null 2>&1 || die "Нет пользователя builder — запусти scripts/bootstrap-host.sh"

as_builder() { sudo -u builder "$@"; }

if ! as_builder gpg --list-secret-keys "$UID_MAIL" >/dev/null 2>&1; then
    msg "Создаю ключ подписи $UID_NAME <$UID_MAIL>"
    # %no-protection — без парольной фразы, см. комментарий выше.
    as_builder gpg --batch --gen-key <<GPGEOF
%no-protection
Key-Type: RSA
Key-Length: 4096
Key-Usage: sign
Name-Real: $UID_NAME
Name-Email: $UID_MAIL
Expire-Date: 0
%commit
GPGEOF
else
    msg "Ключ уже существует, только переэкспортирую публичную часть"
fi

FPR=$(as_builder gpg --with-colons --fingerprint "$UID_MAIL" \
      | awk -F: '/^fpr:/ {print $10; exit}')
[[ -n $FPR ]] || die "Не удалось получить отпечаток ключа"

msg "Отпечаток: $FPR"

install -d "$KEYRING_DIR"
as_builder gpg --export "$UID_MAIL" > "$KEYRING_DIR/luna.gpg"

# Формат тот же, что у archlinux-trusted: отпечаток, уровень доверия, двоеточие.
# Уровень 4 — полное доверие.
printf '%s:4:\n' "$FPR" > "$KEYRING_DIR/luna-trusted"

msg "Публичная часть выгружена в pkg/luna-keyring/"
ls -l "$KEYRING_DIR/luna.gpg" "$KEYRING_DIR/luna-trusted"

# Сборочный хост должен доверять ключу: иначе mkarchiso не сможет
# поставить подписанные пакеты luna-* в образ.
msg "Регистрирую ключ в связке pacman сборочного хоста"
pacman-key --add "$KEYRING_DIR/luna.gpg" >/dev/null
pacman-key --lsign-key "$FPR" >/dev/null 2>&1
msg "Готово"
