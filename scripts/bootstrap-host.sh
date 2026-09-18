#!/usr/bin/env bash
# Prepares the Luna Linux build host (run as root inside the LunaBuild WSL distribution).
# Idempotent: running it again breaks nothing.
set -euo pipefail

LUNA_WORK=/var/luna

msg() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m!!!\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root: wsl -d LunaBuild -u root"

msg "Refreshing the keyring and the system"
pacman-key --init >/dev/null 2>&1 || true
pacman-key --populate archlinux >/dev/null 2>&1 || true
pacman -Sy --needed --noconfirm archlinux-keyring
pacman -Su --noconfirm

# grub is installed on the host not to boot the host itself: in uefi.grub mode
# mkarchiso calls grub-install, and without the package the build aborts while
# validating the profile.
msg "Installing the build tools"
pacman -S --needed --noconfirm \
  archiso git base-devel rsync \
  qemu-base qemu-ui-gtk qemu-hw-display-virtio-gpu qemu-hw-display-virtio-gpu-gl qemu-hw-display-virtio-vga qemu-hw-display-virtio-vga-gl virglrenderer edk2-ovmf mtools dosfstools \
  dialog arch-install-scripts pacman-contrib \
  grub

msg "Generating the locale"
# Without a generated locale, makepkg and bsdtar bury the output under
# "Failed to set default locale" messages, and real errors get lost in them.
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen >/dev/null
[[ -f /etc/locale.conf ]] || echo 'LANG=en_US.UTF-8' > /etc/locale.conf

msg "Creating the work directories in $LUNA_WORK"
install -d "$LUNA_WORK"/{src,work,out,repo}

# makepkg refuses to run as root, so an unprivileged user is required.
if ! id -u builder >/dev/null 2>&1; then
  msg "Creating the builder user for makepkg"
  useradd -m -G wheel -s /bin/bash builder
  passwd -d builder
fi
echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/99-luna-builder
chmod 0440 /etc/sudoers.d/99-luna-builder
chown -R builder:builder "$LUNA_WORK"

msg "Checking the environment"
printf '  archiso : %s\n' "$(pacman -Q archiso | awk '{print $2}')"
printf '  qemu    : %s\n' "$(pacman -Q qemu-base | awk '{print $2}')"
if [[ -e /dev/kvm ]]; then
  printf '  KVM     : \033[1;32mavailable\033[0m (%s)\n' "$(stat -c '%A' /dev/kvm)"
else
  printf '  KVM     : \033[1;33mmissing\033[0m - QEMU will run without acceleration\n'
fi
OVMF=$(ls /usr/share/edk2/x64/OVMF_CODE*.fd /usr/share/edk2/x64/OVMF.4m.fd \
          /usr/share/edk2-ovmf/x64/OVMF_CODE.fd 2>/dev/null | head -n1 || true)
printf '  OVMF    : %s\n' "${OVMF:-NOT FOUND}"

msg "Done. The build host is ready."
