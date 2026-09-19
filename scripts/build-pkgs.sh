#!/usr/bin/env bash
# Builds the luna-* packages and updates the local pacman repository.
# Run as root inside LunaBuild.
#
#   build-pkgs.sh              build every package
#   build-pkgs.sh luna-base    build only the ones named
#
# Packages listed in pkg/aur.txt are built from the AUR in the same run and
# signed with the same key. LUNA_SKIP_AUR=1 leaves them out, which is what to
# do when there is no network: the AUR step needs one, the rest does not.
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
AUR_LIST="$LUNA_SRC/pkg/aur.txt"

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

# --- what to build ----------------------------------------------------------
aur_all=()
if [[ -f $AUR_LIST ]]; then
  mapfile -t aur_all < <(grep -vE '^[[:space:]]*(#|$)' "$AUR_LIST" | awk '{print $1}')
fi

is_aur() {
  local want=$1 have
  for have in "${aur_all[@]}"; do [[ $have == "$want" ]] && return 0; done
  return 1
}

names=()      # ours, from pkg/<name>/PKGBUILD
aur_names=()  # somebody else's, cloned from the AUR
if (( $# )); then
  # Named on the command line: each one is sorted into the right list, so that
  # build-pkgs.sh yay-bin does what it looks like it should.
  for arg in "$@"; do
    if is_aur "$arg"; then aur_names+=("$arg"); else names+=("$arg"); fi
  done
else
  mapfile -t names < <(cd "$LUNA_SRC/pkg" && ls -1d */ | tr -d '/')
  aur_names=("${aur_all[@]}")
fi
if [[ -n ${LUNA_SKIP_AUR:-} ]] && (( ${#aur_names[@]} )); then
  msg "LUNA_SKIP_AUR is set - skipping ${aur_names[*]}"
  aur_names=()
fi

# The repository is owned by builder because repo-add runs as builder. Root can
# still write here whenever it needs to.
install -d -o builder -g builder "$BUILD" "$REPO"
chown -R builder:builder "$REPO"

# Moves a freshly built package out of its build directory and into the
# repository. Shared by both loops below: getting this right for our own
# packages and wrong for the AUR ones would be a quiet way to end up with
# unsigned packages in a repository that is supposed to have none.
publish() { # name build-dir
  local name=$1 dir=$2 built n
  # The name is matched as <name>-<version> rather than as "the first package
  # file in the directory". makepkg also writes a separate -debug package
  # beside the real one whenever the build host has debug symbols switched on,
  # and the first run of this put yay-bin-debug into the repository in place of
  # yay-bin: eight kilobytes of debug symbols where the AUR helper should have
  # been. The build reported success and the database counted nine signed
  # packages, while yay simply did not exist. A version always begins with a
  # digit, which is what tells the two names apart.
  n=$(find "$dir" -maxdepth 1 -name "$name-[0-9]*.pkg.tar.*" ! -name '*.sig' | wc -l)
  (( n == 1 )) || die "$name: expected one package file, found $n"
  built=$(find "$dir" -maxdepth 1 -name "$name-[0-9]*.pkg.tar.*" ! -name '*.sig' -printf '%p\n')
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
}

for name in "${names[@]}"; do
  src="$LUNA_SRC/pkg/$name"
  [[ -f "$src/PKGBUILD" ]] || die "No PKGBUILD: $src"

  msg "Building $name"
  # Build on ext4: makepkg sets file permissions, and DrvFs has none.
  rm -rf "$BUILD/$name"
  install -d "$BUILD/$name"
  cp -rT "$src" "$BUILD/$name"
  chown -R builder:builder "$BUILD/$name"

  # pkgrel is set from the number of commits that have touched this package.
  # Without it every build comes out as 0.1.0-1 with different contents inside,
  # and pacman on an installed machine sees no reason to fetch anything: the
  # network repository would serve new packages that nobody ever downloads.
  # The count only ever grows, and only when the package really changed - which
  # also means the repository should be published from committed state, or two
  # different builds can end up sharing a version.
  rel=$(git -C "$LUNA_SRC" rev-list --count HEAD -- "pkg/$name" 2>/dev/null || echo 0)
  (( rel > 0 )) || rel=1
  sed -i "s/^pkgrel=.*/pkgrel=$rel/" "$BUILD/$name/PKGBUILD"
  grep -q "^pkgrel=$rel$" "$BUILD/$name/PKGBUILD" || die "$name: pkgrel was not set - does the PKGBUILD still declare one?"
  msg "  pkgrel $rel"

  # -d (--nodeps): the dependencies of our packages are what the installed
  # system needs, not what the build host needs. Without this flag makepkg
  # would try to drag the whole of Hyprland in here.
  # --sign --key: the signature is written next to the package as a .sig file.
  # The key has no passphrase, so the build never stops to ask.
  sudo -u builder env -C "$BUILD/$name" makepkg -f -d --noconfirm --clean --sign --key "$FPR"

  publish "$name" "$BUILD/$name"
done

# --- the ones from the AUR --------------------------------------------------
# Cloned fresh every time rather than updated in place. An AUR repository is a
# few kilobytes, and a fresh clone has no update path that can go wrong: no
# rebase, no stale branch, nothing left behind from a debugging session.
AURDIR="$BUILD/aur"
if (( ${#aur_names[@]} )); then
  install -d -o builder -g builder "$AURDIR"
fi
for name in "${aur_names[@]}"; do
  msg "Building $name from the AUR"
  rm -rf "${AURDIR:?}/$name"
  sudo -u builder git clone --quiet --depth 1 \
    "https://aur.archlinux.org/$name.git" "$AURDIR/$name" \
    || die "$name: could not be cloned from the AUR.
       That step needs network access. Without one, build with
       LUNA_SKIP_AUR=1 - none of the other packages need it."
  [[ -f "$AURDIR/$name/PKGBUILD" ]] || die "$name: no PKGBUILD in the AUR repository"

  # The same flags as our own packages, for the same reasons. makepkg checks
  # the downloaded binary against the sums in the PKGBUILD before unpacking it.
  sudo -u builder env -C "$AURDIR/$name" makepkg -f -d --noconfirm --clean --sign --key "$FPR"

  publish "$name" "$AURDIR/$name"
done

# Debug packages are of no use on the image and only take up room, so any that
# appeared are dropped before the database is built. This also clears out the
# ones left behind by earlier builds.
find "$REPO" -maxdepth 1 -name '*-debug-[0-9]*.pkg.tar.*' -delete

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
