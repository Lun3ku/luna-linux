#!/usr/bin/env bash
# Builds the luna-* packages and updates the local pacman repository.
# Run as root inside LunaBuild.
#
#   build-pkgs.sh              build every package
#   build-pkgs.sh luna-base    build only the ones named
#
# Every package is signed with the Luna key. The key is created by
# scripts/make-signing-key.sh; its secret half lives only in ~builder/.gnupg
# on this machine, and the backup copy is in E:\Luna-Linux-Keys.
set -euo pipefail

LUNA_SRC=${LUNA_SRC:-/mnt/c/Users/anyah/Documents/Claudes work/luna}
LUNA_WORK=/var/luna
BUILD="$LUNA_WORK/pkgbuild"
REPO="$LUNA_WORK/repo"
REPO_DB="$REPO/luna.db.tar.gz"
KEYRING_DIR="$LUNA_SRC/pkg/luna-keyring"

msg() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m!!!\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root: wsl -d LunaBuild -u root"
id -u builder >/dev/null 2>&1 || die "No builder user - run scripts/bootstrap-host.sh"

# --- the signing key --------------------------------------------------------
# The fingerprint is read from the very file that ships in the luna-keyring
# package, so the signature and the trust placed in it cannot drift apart.
[[ -f "$KEYRING_DIR/luna-trusted" ]] || die "No $KEYRING_DIR/luna-trusted - run scripts/make-signing-key.sh"
FPR=$(cut -d: -f1 "$KEYRING_DIR/luna-trusted")
[[ -n $FPR ]] || die "Empty fingerprint in luna-trusted"

sudo -u builder gpg --list-secret-keys "$FPR" >/dev/null 2>&1 \
  || die "builder has no secret key $FPR.
       Create a new one:     scripts/make-signing-key.sh
       Restore the backup:   sudo -u builder gpg --import /mnt/e/Luna-Linux-Keys/luna-signing-SECRET.asc"

# The build host has to trust the key itself: mkarchiso installs our packages
# into the image with ordinary pacman, and pacman now verifies signatures for
# real.
if ! pacman-key --list-keys "$FPR" >/dev/null 2>&1; then
  msg "Registering the key in the build host's pacman keyring"
  pacman-key --add "$KEYRING_DIR/luna.gpg" >/dev/null
  pacman-key --lsign-key "$FPR" >/dev/null 2>&1
fi

msg "Signing with key $FPR"

names=("$@")
if [[ ${#names[@]} -eq 0 ]]; then
  mapfile -t names < <(cd "$LUNA_SRC/pkg" && ls -1d */ | tr -d '/')
fi

# The repository is owned by builder because repo-add runs as builder. Root can
# still write here whenever it needs to.
install -d -o builder -g builder "$BUILD" "$REPO"
chown -R builder:builder "$REPO"

for name in "${names[@]}"; do
  src="$LUNA_SRC/pkg/$name"
  [[ -f "$src/PKGBUILD" ]] || die "No PKGBUILD: $src"

  msg "Building $name"
  # Build on ext4: makepkg sets file permissions, and DrvFs has none.
  rm -rf "$BUILD/$name"
  install -d "$BUILD/$name"
  cp -rT "$src" "$BUILD/$name"
  chown -R builder:builder "$BUILD/$name"

  # -d (--nodeps): the dependencies of our packages are what the installed
  # system needs, not what the build host needs. Without this flag makepkg
  # would try to drag the whole of Hyprland in here.
  # --sign --key: the signature is written next to the package as a .sig file.
  # The key has no passphrase, so the build never stops to ask.
  sudo -u builder env -C "$BUILD/$name" makepkg -f -d --noconfirm --clean --sign --key "$FPR"

  built=$(find "$BUILD/$name" -maxdepth 1 -name '*.pkg.tar.*' ! -name '*.sig' -printf '%p\n' | head -n1)
  [[ -n "$built" ]] || die "$name: the package did not build"
  [[ -f "$built.sig" ]] || die "$name: the package built without a signature"

  # Older versions of this same package are removed: otherwise the directory
  # collects junk, and with it signatures that no longer have an entry in the
  # database.
  find "$REPO" -maxdepth 1 -name "$name-[0-9]*.pkg.tar.*" -delete

  install -o builder -g builder -m644 "$built"     "$REPO/"
  install -o builder -g builder -m644 "$built.sig" "$REPO/"

  # The previous build's copy has to be dropped from pacman's cache. Rebuilding
  # does not change the package version but does change its contents, so pacman
  # finds a file with the expected name in the cache, checks it against the new
  # signature and declares it corrupted. An image build has already failed this
  # way.
  rm -f "/var/cache/pacman/pkg/$(basename "$built")" "/var/cache/pacman/pkg/$(basename "$built").sig"

  msg "  -> $(basename "$built") + signature"
done

msg "Updating the repository in $REPO"
mapfile -t pkgfiles < <(find "$REPO" -maxdepth 1 -name '*.pkg.tar.*' ! -name '*.sig' | sort)
[[ ${#pkgfiles[@]} -gt 0 ]] || die "No packages in the repository"
# The database is rebuilt from scratch rather than appended to: the full list
# of packages is passed in, so stale entries for removed packages do not
# survive a build. It also removes the first-run problem, since repo-add never
# has to verify a database signature that does not exist yet.
rm -f "$REPO_DB" "$REPO_DB.sig" "${REPO_DB%.tar.gz}.files.tar.gz" "$REPO/luna.files.tar.gz" "$REPO/luna.files.tar.gz.sig"
# --include-sigs puts the package signature straight into the database.
# Without it pacman looks for a .sig file next to the package, and losing those
# files while copying the repository around silently turns verification into
# the absence of verification.
#
# The database itself is deliberately NOT signed. Arch does not sign its own
# databases for the same reason: a database signature would only protect the
# list of packages, while every package in that list already carries its own
# signature inside the database. It would not help against a package being
# swapped for somebody else's either way.
# The practical harm of signing the database was measured: at the end of a
# build mkarchiso calls pacman -Q --sysroot against the image, the image has no
# keyring of its own (archiso creates it only at boot, through pacman-init),
# and the build started emitting "key is unknown / keyring is not writable".
# Errors in a build log that mean nothing are a reliable way to miss the one
# that does.
sudo -u builder repo-add -q --include-sigs "$REPO_DB" "${pkgfiles[@]}" >/dev/null
# repo-add leaves the previous version of the database behind. There is no
# reason to drag that tail into a repository that is copied onto the image
# whole.
rm -f "$REPO"/*.old

msg "Repository contents:"
ls -1sh "$REPO"/*.pkg.tar.zst | sed 's/^/  /'
echo
msg "Packages in the database: $(tar tzf "$REPO_DB" 2>/dev/null | grep -c '/desc$' || echo 0)"

# A signature that is not in the database is ignored by pacman, so check that
# the %PGPSIG% field is really recorded for every package and not merely
# present as a file.
signed_in_db=$(tar xzOf "$REPO_DB" --wildcards '*/desc' 2>/dev/null | grep -c '^%PGPSIG%$' || true)
msg "Of those, signed in the database: $signed_in_db"
[[ "$signed_in_db" -eq "${#pkgfiles[@]}" ]] \
  || die "Not all are signed: ${#pkgfiles[@]} packages, $signed_in_db signatures in the database"
