#!/usr/bin/env bash
# shellcheck disable=SC2034
# Профиль сборки Luna Linux. %INSTALL_DIR%, %ARCH% и %ARCHISO_UUID% в конфигах
# загрузчиков подставляет сам mkarchiso, поэтому install_dir и метку можно
# менять здесь, не трогая syslinux/grub/efiboot.

iso_name="luna"
iso_label="LUNA_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Luna Linux"
iso_application="Luna Linux Live/Install Medium"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="luna"
buildmodes=('iso')
# UEFI-меню рисует systemd-boot. Пробовали перевести его на GRUB ради
# фоновой картинки — не вышло: mkarchiso копирует в каталог grub образа
# только файлы .cfg, и положить туда PNG штатными средствами нельзя.
# Без фона смена загрузчика даёт почти ничего, поэтому оставлено как есть.
# Заставка splash.png работает при загрузке с BIOS: её mkarchiso копирует.
bootmodes=('bios.syslinux'
           'uefi.systemd-boot')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"

# releng жмёт образ xz — это даёт минимальный ISO ценой очень долгой сборки.
# Для дистрибутива, который мы пересобираем десятки раз, zstd выгоднее: жмёт
# почти так же, а распаковывается на живой системе заметно быстрее.
# На время отладки уровень можно снизить: LUNA_COMP_LEVEL=3 ./scripts/build-iso.sh
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' "${LUNA_COMP_LEVEL:-19}" '-b' '1M')

bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/root/.gnupg"]="0:0:700"
  ["/usr/local/bin/choose-mirror"]="0:0:755"
  ["/usr/local/bin/Installation_guide"]="0:0:755"
  ["/usr/local/bin/livecd-sound"]="0:0:755"
  ["/usr/local/bin/luna-live-user"]="0:0:755"
  # sudo молча игнорирует файл с правами шире 0440.
  ["/etc/sudoers.d/10-luna-live"]="0:0:440"
)
