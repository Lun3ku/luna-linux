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
# UEFI-меню рисует GRUB, и причина этому не вкусовая, а весовая.
#
# systemd-boot не умеет читать ISO9660 и требует, чтобы ядро с initramfs
# лежали внутри загрузочного FAT-образа. А они и так лежат на самом ISO —
# то есть попадают в образ дважды. Измерено на собранном ISO:
#
#   El Torito boot img : 2  UEFI ... 133632 блоков  = 261 МиБ
#
# GRUB читает ISO9660 сам, поэтому в FAT-образ идёт только загрузчик, а
# ядро берётся с диска в одном экземпляре. Разница около 260 МиБ — как раз
# она решает, помещается ли релиз в лимит GitHub (2 ГиБ на файл).
#
# Цена: фоновую картинку в меню GRUB штатными средствами не положить —
# mkarchiso копирует из каталога grub профиля только файлы .cfg. Ради
# картинки мы этот переход когда-то откатили; ради четверти гигабайта он
# оправдан. Заставка splash.png при загрузке с BIOS работает как прежде.
bootmodes=('bios.syslinux'
           'uefi.grub')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"

# Сжатие переключается переменной, потому что у сборки два разных смысла.
#
#   LUNA_COMP=zstd  (по умолчанию) — для работы. Жмёт почти как xz, но
#                   распаковывается на живой системе заметно быстрее, а
#                   собирается в разы быстрее. LUNA_COMP_LEVEL=3 — для отладки.
#   LUNA_COMP=xz    — для релиза. Образ меньше примерно на десятую часть
#                   ценой долгой сборки. Это оправдано там, где образ
#                   собирают один раз, а скачивают много. Заодно так делает
#                   сам releng. Фильтр x86 BCJ добавляет ещё пару процентов
#                   на исполняемых файлах.
#
# Размер имеет и внешнее ограничение: файл в релизе GitHub обязан быть
# меньше 2 ГиБ, а на zstd образ в этот предел не помещается.
if [[ "${LUNA_COMP:-zstd}" == xz ]]; then
  airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M')
else
  airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' "${LUNA_COMP_LEVEL:-19}" '-b' '1M')
fi

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
