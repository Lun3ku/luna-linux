#!/usr/bin/env bash
# Walks through the installer automatically, taking the default answers.
#
# A regression test: it checks that an installation completes from end to end
# without anyone sitting at the keyboard. The order of keystrokes matches the
# installer's current screens, so adding or removing a screen means fixing this
# file too.
#
# Run it AFTER starting the VM with a clean disk:
#     rm -f /var/luna/test-disk.qcow2
#     scripts/test-iso.sh --install --vnc     (in one process)
#     scripts/test-install-auto.sh            (in another)
set -uo pipefail

# The lock. Two copies of this script driving the same VM do real damage: the
# keystrokes interleave and a second installer can start. That one reaches
# "sgdisk --zap-all" on the disk the first one has just finished installing to,
# and wipes both copies of the partition table. The system stays on the disk
# in full; the only thing it will not do is boot.
LOCK=/var/luna/auto-install.lock
exec 9>"$LOCK"
flock -n 9 || { echo "Another run is already in progress ($LOCK). Exiting." >&2; exit 1; }

L='/mnt/c/Users/anyah/Documents/Claudes work/luna/scripts'
SHOT=${SHOT:-/var/luna}
t() { bash "$L/vm-type.sh" "$@" >/dev/null; sleep "${DELAY:-3}"; }

# The wait is a variable because an xz image decompresses its squashfs
# noticeably more slowly than a zstd one, and the previous 125 seconds stopped
# being enough: the keystrokes went into a system that had not booted yet.
echo "== waiting for the live image to boot (${BOOT_WAIT:-210} s) =="
sleep "${BOOT_WAIT:-210}"

# The installer opens by itself on the live desktop, through the
# luna-live-installer user unit in the ISO overlay. Typing the command here as
# well would start a second one, and two installers on one disk wipe the
# partition table of whatever the first has installed.
echo "== waiting for the installer to open by itself =="
sleep 12

# Both new screens default to No, so exercising them means pressing left
# first. ENCRYPT=no / HIBERNATE=no run the plain path instead.
echo "== walking through the screens (encrypt=${ENCRYPT:-yes} hibernate=${HIBERNATE:-yes}) =="
t ret                 # Welcome -> Continue
t ret                 # Keymap  -> us
t ret                 # Region  -> UTC (first entry, the city screen is skipped)
t ret                 # Disk    -> /dev/vda
t ret                 # Scheme  -> auto
t left ret            # Confirm erase -> Erase
if [[ ${ENCRYPT:-yes} == yes ]]; then
    t left ret        # Disk encryption -> Encrypt
    t 'lunacrypt' ret # passphrase
    t 'lunacrypt' ret # passphrase again
else
    t ret             # Disk encryption -> No
fi
if [[ ${HIBERNATE:-yes} == yes ]]; then
    t left ret        # Hibernation -> Enable
else
    t ret             # Hibernation -> Skip
fi
t ret                 # Hostname -> luna
t 'anya' ret          # User
t 'lunatest' ret      # Password
t 'lunatest' ret      # Password again
t ret                 # Kernel  -> linux
t ret                 # Profile -> desktop
# There is no keystroke for the graphics screen on purpose. It only appears on
# a machine with an NVIDIA card, and QEMU has none, so under this test it is
# never shown. To exercise it, run the installer by hand with PCI_DEVICES
# pointed at a fabricated tree of devices - see has_nvidia in luna-install.
bash "$L/vm-screenshot.sh" "$SHOT/auto-summary.png" >/dev/null
t left ret            # Summary -> Install

echo "== the installation has started, waiting =="
for i in $(seq 1 40); do
    sleep 30
    bash "$L/vm-screenshot.sh" "$SHOT/auto-progress.png" >/dev/null 2>&1 || true
done
