#!/usr/bin/env bash
# Подготовка сборочного хоста Luna Linux (запускать от root внутри WSL-дистрибутива LunaBuild).
# Идемпотентен: повторный запуск ничего не ломает.
set -euo pipefail

LUNA_WORK=/var/luna

msg() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m!!!\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Запускать от root: wsl -d LunaBuild -u root"

msg "Обновляю связку ключей и систему"
pacman-key --init >/dev/null 2>&1 || true
pacman-key --populate archlinux >/dev/null 2>&1 || true
pacman -Sy --needed --noconfirm archlinux-keyring
pacman -Su --noconfirm

msg "Ставлю инструменты сборки"
pacman -S --needed --noconfirm \
  archiso git base-devel rsync \
  qemu-base qemu-ui-gtk qemu-hw-display-virtio-gpu qemu-hw-display-virtio-gpu-gl qemu-hw-display-virtio-vga qemu-hw-display-virtio-vga-gl virglrenderer edk2-ovmf mtools dosfstools \
  dialog arch-install-scripts pacman-contrib

msg "Генерирую локаль"
# Без сгенерированной локали makepkg и bsdtar засыпают вывод сообщениями
# «Failed to set default locale», в которых теряются настоящие ошибки.
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen >/dev/null
[[ -f /etc/locale.conf ]] || echo 'LANG=en_US.UTF-8' > /etc/locale.conf

msg "Создаю рабочие каталоги в $LUNA_WORK"
install -d "$LUNA_WORK"/{src,work,out,repo}

# makepkg отказывается работать от root — нужен непривилегированный пользователь.
if ! id -u builder >/dev/null 2>&1; then
  msg "Создаю пользователя builder для makepkg"
  useradd -m -G wheel -s /bin/bash builder
  passwd -d builder
fi
echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/99-luna-builder
chmod 0440 /etc/sudoers.d/99-luna-builder
chown -R builder:builder "$LUNA_WORK"

msg "Проверяю окружение"
printf '  archiso : %s\n' "$(pacman -Q archiso | awk '{print $2}')"
printf '  qemu    : %s\n' "$(pacman -Q qemu-base | awk '{print $2}')"
if [[ -e /dev/kvm ]]; then
  printf '  KVM     : \033[1;32mдоступен\033[0m (%s)\n' "$(stat -c '%A' /dev/kvm)"
else
  printf '  KVM     : \033[1;33mнет\033[0m — QEMU будет работать без ускорения\n'
fi
OVMF=$(ls /usr/share/edk2/x64/OVMF_CODE*.fd /usr/share/edk2/x64/OVMF.4m.fd \
          /usr/share/edk2-ovmf/x64/OVMF_CODE.fd 2>/dev/null | head -n1 || true)
printf '  OVMF    : %s\n' "${OVMF:-НЕ НАЙДЕН}"

msg "Готово. Сборочный хост настроен."
