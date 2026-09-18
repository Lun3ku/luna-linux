#!/usr/bin/env bash
# Builds the Luna Linux ISO. Run as root inside LunaBuild.
#
# The profile sits on the Windows drive (DrvFs), which has no Unix permissions,
# so it is synced to ext4 before the build. Permissions for the files that
# depend on them are set by the file_permissions array in profiledef.sh anyway.
set -euo pipefail

LUNA_SRC=${LUNA_SRC:-/mnt/c/Users/anyah/Documents/Claudes work/luna}
LUNA_WORK=/var/luna

msg() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m!!!\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root: wsl -d LunaBuild -u root"
[[ -d "$LUNA_SRC/iso" ]] || die "Profile not found: $LUNA_SRC/iso"
command -v mkarchiso >/dev/null || die "archiso is not installed - run scripts/bootstrap-host.sh"

msg "Syncing the profile to ext4"
install -d "$LUNA_WORK"/{src,work,out,repo}
rsync -a --delete --no-perms --no-owner --no-group --chmod=D755,F644 \
  "$LUNA_SRC/iso/" "$LUNA_WORK/src/iso/"

# Scripts inside the overlay have to stay executable.
find "$LUNA_WORK/src/iso/airootfs" -type f \
  \( -path '*/bin/*' -o -name '*.sh' -o -name '.zlogin' -o -name '.profile' \) \
  -exec chmod 755 {} + 2>/dev/null || true

# The luna repository goes INSIDE the image. Without it the installer cannot
# put the luna-* packages on the target disk: pacstrap looks for them in the
# repositories, and we do not have a server on the network yet.
REPO_ON_ISO=usr/share/luna/repo
if [[ -z "$(ls -A "$LUNA_WORK/repo" 2>/dev/null)" ]]; then
  die "Repository $LUNA_WORK/repo is empty - run scripts/build-pkgs.sh first"
fi
msg "Placing the luna repository into the image ($REPO_ON_ISO)"
install -d "$LUNA_WORK/src/iso/airootfs/$REPO_ON_ISO"
rsync -a --delete --no-perms --no-owner --no-group --chmod=D755,F644   "$LUNA_WORK/repo/" "$LUNA_WORK/src/iso/airootfs/$REPO_ON_ISO/"

# The live system's /etc/pacman.conf is generated from the profile's one with
# the repository path substituted: during the build it is file:///var/luna/repo
# on the host, while inside the running image it is /usr/share/luna/repo. That
# leaves one source of truth instead of two files that would have to be kept
# in sync by hand.
msg "Preparing /etc/pacman.conf for the live system"
install -d "$LUNA_WORK/src/iso/airootfs/etc"
sed "s|^Server = file:///var/luna/repo|Server = file:///$REPO_ON_ISO|"   "$LUNA_SRC/iso/pacman.conf" > "$LUNA_WORK/src/iso/airootfs/etc/pacman.conf"
grep -q "file:///$REPO_ON_ISO" "$LUNA_WORK/src/iso/airootfs/etc/pacman.conf"   || die "Failed to substitute the repository path in pacman.conf"

msg "Cleaning the work directory of the previous build"
rm -rf "${LUNA_WORK:?}/work"
install -d "$LUNA_WORK/work"

msg "Running mkarchiso"
time mkarchiso -v -w "$LUNA_WORK/work" -o "$LUNA_WORK/out" "$LUNA_WORK/src/iso"

# The work directory is around 7 GB and is wiped at the start of every build
# anyway, so between builds it is pure dead weight. Removing it here keeps the
# WSL disk from growing by a full image every time.
#
# Note that freeing space inside the virtual disk does not shrink the .vhdx
# file on the Windows side. That needs a separate compaction:
#   wsl --shutdown
#   wsl --manage LunaBuild --set-sparse true
msg "Cleaning the work directory ($(du -sh "$LUNA_WORK/work" 2>/dev/null | cut -f1))"
rm -rf "${LUNA_WORK:?}/work"

# Keep one version of each cached package. A full cache reaches a couple of
# gigabytes and is re-downloadable by definition.
if command -v paccache >/dev/null; then
    paccache -rk1 -q 2>/dev/null || true
    paccache -ruk0 -q 2>/dev/null || true
fi

msg "Finished images:"
ls -lh "$LUNA_WORK/out"
msg "Free space: $(df -h "$LUNA_WORK" | awk 'NR==2 {print $4}')"
