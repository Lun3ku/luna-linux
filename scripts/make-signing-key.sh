#!/usr/bin/env bash
# Creates the key the Luna packages are signed with.
#
# Run once. Running it again breaks nothing: if the key already exists, the
# script only re-exports the public half.
#
# WHERE THE SECRET HALF LIVES. Only in the keyring of the builder user on the
# build host (~builder/.gnupg). It does not go into the repository and must
# never do so; what lives there is the public half and the fingerprint.
#
# ABOUT THE MISSING PASSPHRASE. The key has none, because building packages
# must not stop to ask for a password once per package. For a local key of a
# personal distribution that is a reasonable trade: whoever gains access to the
# build machine can tamper with the packages before they are signed anyway. If
# Luna ever becomes public, the key should be remade with a passphrase and the
# signing kept apart from the building.
set -euo pipefail

LUNA_SRC=${LUNA_SRC:-/mnt/c/Users/anyah/Documents/Claudes work/luna}
KEYRING_DIR="$LUNA_SRC/pkg/luna-keyring"
UID_NAME="Luna Linux"
UID_MAIL="luna@localhost"

msg() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m!!!\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root: wsl -d LunaBuild -u root"
id -u builder >/dev/null 2>&1 || die "No builder user - run scripts/bootstrap-host.sh"

as_builder() { sudo -u builder "$@"; }

if ! as_builder gpg --list-secret-keys "$UID_MAIL" >/dev/null 2>&1; then
    msg "Creating signing key $UID_NAME <$UID_MAIL>"
    # %no-protection means no passphrase, see the comment above.
    as_builder gpg --batch --gen-key <<GPGEOF
%no-protection
Key-Type: RSA
Key-Length: 4096
Key-Usage: sign
Name-Real: $UID_NAME
Name-Email: $UID_MAIL
Expire-Date: 0
%commit
GPGEOF
else
    msg "The key already exists, only re-exporting the public half"
fi

FPR=$(as_builder gpg --with-colons --fingerprint "$UID_MAIL" \
      | awk -F: '/^fpr:/ {print $10; exit}')
[[ -n $FPR ]] || die "Could not read the key fingerprint"

msg "Fingerprint: $FPR"

install -d "$KEYRING_DIR"
as_builder gpg --export "$UID_MAIL" > "$KEYRING_DIR/luna.gpg"

# Same format as archlinux-trusted: fingerprint, trust level, colon.
# Level 4 means full trust.
printf '%s:4:\n' "$FPR" > "$KEYRING_DIR/luna-trusted"

msg "Public half exported into pkg/luna-keyring/"
ls -l "$KEYRING_DIR/luna.gpg" "$KEYRING_DIR/luna-trusted"

# The build host has to trust the key, otherwise mkarchiso cannot install the
# signed luna-* packages into the image.
msg "Registering the key in the build host's pacman keyring"
pacman-key --add "$KEYRING_DIR/luna.gpg" >/dev/null
pacman-key --lsign-key "$FPR" >/dev/null 2>&1
msg "Done"
