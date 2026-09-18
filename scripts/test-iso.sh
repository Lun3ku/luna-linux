#!/usr/bin/env bash
# Запуск собранного образа Luna в QEMU.
#
# Режимы диска:
#   (без аргументов)   живая загрузка ISO
#   --install          подключить чистый диск и пройти установку
#   --boot-installed   загрузить уже установленную систему
#
# Режимы экрана:
#   --vnc     (по умолчанию) VNC + websocket, смотреть через scripts/vm-view.sh
#   --gtk     окно WSLg; на некоторых системах окно не всплывает
#   --serial  без графики, вывод в текущий терминал
#
# Прочее:
#   --reset-nvram  очистить память UEFI перед запуском. Нужен, когда
#             диск пересоздан: прошивка помнит запись загрузчика с прошлой
#             установки, не находит её и уходит в сетевую загрузку, так и
#             не добравшись до CD.
#   --gl      аппаратное ускорение через virtio-gpu + virglrenderer.
#             Без него Mesa уходит в программный рендеринг, и часть
#             приложений (например hyprpaper) может не работать.
#
# В режимах --vnc и --gtk к машине подключается последовательный порт,
# выведенный в файл /var/luna/guest.log. Изнутри гостя это /dev/ttyS0:
#
#     ваша-команда > /dev/ttyS0 2>&1
#
# так длинный вывод можно прочитать целиком на хосте, вместо того чтобы
# выуживать его со скриншотов.
set -euo pipefail

LUNA_WORK=/var/luna
DISK="$LUNA_WORK/test-disk.qcow2"
QMP_SOCK="$LUNA_WORK/qmp.sock"
GUEST_LOG="$LUNA_WORK/guest.log"
DISK_SIZE=${DISK_SIZE:-32G}
MEM=${MEM:-4G}
CPUS=${CPUS:-4}
VNC_DISPLAY=${VNC_DISPLAY:-1}      # :1 → порт 5901
VNC_WS=${VNC_WS:-5700}             # порт websocket для браузера

msg() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m!!!\033[0m %s\n' "$*" >&2; exit 1; }

MODE=live
SCREEN=vnc
for a in "$@"; do
  case "$a" in
    --install)        MODE=install ;;
    --boot-installed) MODE=installed ;;
    --vnc)            SCREEN=vnc ;;
    --gl)             GL=1 ;;
    --reset-nvram)    RESET_NVRAM=1 ;;
    --gtk)            SCREEN=gtk ;;
    --serial)         SCREEN=serial ;;
    *) die "Неизвестный аргумент: $a" ;;
  esac
done

ISO=$(ls -t "$LUNA_WORK"/out/*.iso 2>/dev/null | head -n1 || true)
[[ -n "$ISO" || $MODE == installed ]] || die "ISO не найден в $LUNA_WORK/out — сначала scripts/build-iso.sh"

# Путь к OVMF в Arch со временем менялся, поэтому ищем по вариантам.
OVMF=$(ls /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/edk2/x64/OVMF_CODE.fd \
          /usr/share/edk2-ovmf/x64/OVMF_CODE.fd 2>/dev/null | head -n1 || true)
OVMF_VARS=$(ls /usr/share/edk2/x64/OVMF_VARS.4m.fd /usr/share/edk2/x64/OVMF_VARS.fd \
               /usr/share/edk2-ovmf/x64/OVMF_VARS.fd 2>/dev/null | head -n1 || true)
[[ -n "$OVMF" ]] || die "OVMF не найден — pacman -S edk2-ovmf"

# Изменяемая копия NVRAM, чтобы не портить системный файл.
VARS="$LUNA_WORK/OVMF_VARS.fd"
[[ -n "${RESET_NVRAM:-}" ]] && rm -f "$VARS"
[[ -f "$VARS" ]] || cp "$OVMF_VARS" "$VARS"

args=(
  -machine q35 -m "$MEM" -smp "$CPUS"
  -drive "if=pflash,format=raw,readonly=on,file=$OVMF"
  -drive "if=pflash,format=raw,file=$VARS"
  -device virtio-net,netdev=n0 -netdev user,id=n0
  -device intel-hda -device hda-duplex
  -qmp "unix:$QMP_SOCK,server=on,wait=off"
)

if [[ -n "${GL:-}" ]]; then
  args+=(-device virtio-vga-gl)
  msg "Видео: virtio-vga-gl (аппаратное ускорение)"
else
  args+=(-device virtio-vga)
fi

if [[ -e /dev/kvm && -r /dev/kvm ]]; then
  args+=(-enable-kvm -cpu host)
  msg "KVM включён"
else
  args+=(-cpu max)
  msg "KVM недоступен — эмуляция будет медленной"
fi

case "$MODE" in
  live)
    args+=(-cdrom "$ISO" -boot d) ;;
  install)
    if [[ ! -f "$DISK" ]]; then
      msg "Создаю чистый диск $DISK_SIZE"
      qemu-img create -f qcow2 "$DISK" "$DISK_SIZE" >/dev/null
      # Вместе с диском обнуляем и память UEFI: иначе прошивка ищет
      # загрузчик по записи от прошлой установки и уходит в сетевую
      # загрузку, не пробуя CD.
      rm -f "$VARS"; cp "$OVMF_VARS" "$VARS"
      msg "Память UEFI очищена вместе с диском"
    fi
    args+=(-drive "file=$DISK,if=virtio,format=qcow2" -cdrom "$ISO" -boot d) ;;
  installed)
    [[ -f "$DISK" ]] || die "Диск $DISK не создан — сначала test-iso.sh --install"
    args+=(-drive "file=$DISK,if=virtio,format=qcow2" -boot c) ;;
esac

case "$SCREEN" in
  vnc)
    args+=(-display none -vnc ":${VNC_DISPLAY},websocket=${VNC_WS}"
           -serial "file:$GUEST_LOG")
    msg "Экран: VNC на :${VNC_DISPLAY}, websocket ${VNC_WS} — открой через scripts/vm-view.sh"
    msg "Вывод гостя: $GUEST_LOG (внутри это /dev/ttyS0)" ;;
  gtk)
    args+=(-display gtk -serial "file:$GUEST_LOG") ;;
  serial)
    args+=(-display none -serial mon:stdio) ;;
esac

rm -f "$QMP_SOCK" "$GUEST_LOG"
msg "Режим: $MODE${ISO:+, образ $(basename "$ISO")}"
exec qemu-system-x86_64 "${args[@]}"
