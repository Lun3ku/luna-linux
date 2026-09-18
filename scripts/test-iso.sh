#!/usr/bin/env bash
# Runs the built Luna image in QEMU.
#
# Disk modes:
#   (no arguments)     boot the ISO live
#   --install          attach a clean disk and go through the installation
#   --boot-installed   boot the system that was already installed
#
# Screen modes:
#   --vnc     (default) VNC + websocket, watch it through scripts/vm-view.sh
#   --gtk     a WSLg window; on some systems the window never appears
#   --serial  no graphics, output goes to the current terminal
#
# Other:
#   --reset-nvram  clear the UEFI variables before starting. Needed when the
#             disk has been recreated: the firmware remembers the bootloader
#             entry from the previous installation, fails to find it and falls
#             through to network boot without ever trying the CD.
#   --gl      hardware acceleration through virtio-gpu + virglrenderer.
#             Without it Mesa falls back to software rendering and some
#             applications (hyprpaper, for one) may not work at all.
#
# In --vnc and --gtk modes a serial port is attached to the machine and written
# to /var/luna/guest.log. From inside the guest that port is /dev/ttyS0:
#
#     your-command > /dev/ttyS0 2>&1
#
# which is how long output can be read in full on the host instead of being
# fished out of screenshots.
set -euo pipefail

LUNA_WORK=/var/luna
DISK="$LUNA_WORK/test-disk.qcow2"
QMP_SOCK="$LUNA_WORK/qmp.sock"
GUEST_LOG="$LUNA_WORK/guest.log"
DISK_SIZE=${DISK_SIZE:-32G}
MEM=${MEM:-4G}
CPUS=${CPUS:-4}
VNC_DISPLAY=${VNC_DISPLAY:-1}      # :1 -> port 5901
VNC_WS=${VNC_WS:-5700}             # websocket port for the browser

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
    *) die "Unknown argument: $a" ;;
  esac
done

ISO=$(ls -t "$LUNA_WORK"/out/*.iso 2>/dev/null | head -n1 || true)
[[ -n "$ISO" || $MODE == installed ]] || die "No ISO found in $LUNA_WORK/out - run scripts/build-iso.sh first"

# The path to OVMF has changed over time in Arch, so try the known variants.
OVMF=$(ls /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/edk2/x64/OVMF_CODE.fd \
          /usr/share/edk2-ovmf/x64/OVMF_CODE.fd 2>/dev/null | head -n1 || true)
OVMF_VARS=$(ls /usr/share/edk2/x64/OVMF_VARS.4m.fd /usr/share/edk2/x64/OVMF_VARS.fd \
               /usr/share/edk2-ovmf/x64/OVMF_VARS.fd 2>/dev/null | head -n1 || true)
[[ -n "$OVMF" ]] || die "OVMF not found - pacman -S edk2-ovmf"

# A writable copy of the NVRAM, so the system file is left alone.
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
  msg "Video: virtio-vga-gl (hardware acceleration)"
else
  args+=(-device virtio-vga)
fi

if [[ -e /dev/kvm && -r /dev/kvm ]]; then
  args+=(-enable-kvm -cpu host)
  msg "KVM enabled"
else
  args+=(-cpu max)
  msg "KVM unavailable - emulation will be slow"
fi

case "$MODE" in
  live)
    args+=(-cdrom "$ISO" -boot d) ;;
  install)
    if [[ ! -f "$DISK" ]]; then
      msg "Creating a clean $DISK_SIZE disk"
      qemu-img create -f qcow2 "$DISK" "$DISK_SIZE" >/dev/null
      # The UEFI variables are cleared along with the disk: otherwise the
      # firmware looks for the bootloader recorded by the previous
      # installation and falls through to network boot without trying the CD.
      rm -f "$VARS"; cp "$OVMF_VARS" "$VARS"
      msg "UEFI variables cleared along with the disk"
    fi
    args+=(-drive "file=$DISK,if=virtio,format=qcow2" -cdrom "$ISO" -boot d) ;;
  installed)
    [[ -f "$DISK" ]] || die "Disk $DISK does not exist - run test-iso.sh --install first"
    args+=(-drive "file=$DISK,if=virtio,format=qcow2" -boot c) ;;
esac

case "$SCREEN" in
  vnc)
    args+=(-display none -vnc ":${VNC_DISPLAY},websocket=${VNC_WS}"
           -serial "file:$GUEST_LOG")
    msg "Screen: VNC on :${VNC_DISPLAY}, websocket ${VNC_WS} - open it with scripts/vm-view.sh"
    msg "Guest output: $GUEST_LOG (that is /dev/ttyS0 inside)" ;;
  gtk)
    args+=(-display gtk -serial "file:$GUEST_LOG") ;;
  serial)
    args+=(-display none -serial mon:stdio) ;;
esac

rm -f "$QMP_SOCK" "$GUEST_LOG"
msg "Mode: $MODE${ISO:+, image $(basename "$ISO")}"
exec qemu-system-x86_64 "${args[@]}"
