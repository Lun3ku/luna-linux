#!/usr/bin/env bash
# shellcheck disable=SC2034
# The Luna Linux build profile. mkarchiso substitutes %INSTALL_DIR%, %ARCH% and
# %ARCHISO_UUID% inside the bootloader configs itself, so install_dir and the
# label can be changed here without touching syslinux/grub/efiboot.

iso_name="luna"
iso_label="LUNA_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Luna Linux"
iso_application="Luna Linux Live/Install Medium"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="luna"
buildmodes=('iso')
# The UEFI menu is drawn by GRUB, and the reason is weight rather than taste.
#
# systemd-boot cannot read ISO9660 and requires the kernel and the initramfs to
# live inside the bootable FAT image. They already live on the ISO itself, so
# they end up in the image twice. Measured on a finished ISO:
#
#   El Torito boot img : 2  UEFI ... 133632 blocks  = 261 MiB
#
# GRUB reads ISO9660 by itself, so only the bootloader goes into the FAT image
# and the kernel is stored once. The difference is around 260 MiB, and that is
# exactly what decides whether a release fits GitHub's limit (2 GiB per file).
#
# The price: a background image cannot be placed into the GRUB menu by
# supported means, because mkarchiso copies only .cfg files out of the
# profile's grub directory. We once reverted this switch for the sake of that
# picture; for the sake of a quarter of a gigabyte it is worth it. The
# splash.png shown when booting from BIOS still works as before.
bootmodes=('bios.syslinux'
           'uefi.grub')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"

# Compression is switched by a variable, because a build serves two different
# purposes.
#
#   LUNA_COMP=zstd  (the default) is for working. It compresses almost as well
#                   as xz, decompresses noticeably faster on the live system
#                   and builds many times faster. LUNA_COMP_LEVEL=3 is for
#                   debugging.
#   LUNA_COMP=xz    is for a release. The image is roughly a tenth smaller at
#                   the cost of a long build. That pays off where an image is
#                   built once and downloaded many times. It is also what
#                   releng itself does. The x86 BCJ filter adds a couple more
#                   percent on executables.
#
# Size also has an external constraint: a file in a GitHub release has to be
# under 2 GiB, and with zstd the image does not fit within that limit.
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
  # sudo silently ignores a file whose permissions are wider than 0440.
  ["/etc/sudoers.d/10-luna-live"]="0:0:440"
)
