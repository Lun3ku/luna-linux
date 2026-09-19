#!/usr/bin/env bash
# Publishes the signed [luna] repository to GitHub Pages.
#
# This is the one script here that does NOT run inside LunaBuild. It runs in
# Git Bash on Windows, because pushing needs the Windows credential store -
# that is the only place the GitHub login lives, and from WSL the sign-in
# window never opens. It reads the built repository straight out of the WSL
# filesystem over \\wsl.localhost, so nothing has to be copied by hand first.
#
#   scripts/publish-repo.sh            publish what build-pkgs.sh last built
#   scripts/publish-repo.sh --dry-run  do everything except the push
#
# The branch is rebuilt from scratch on every publish and force-pushed. That is
# deliberate: it holds nothing but compiled packages, and keeping their history
# would grow the repository by the size of the whole set on every release
# without anyone ever wanting to read an old copy. The code's history lives on
# main and is never touched by this.
set -euo pipefail

SRC=${LUNA_REPO_SRC:-//wsl.localhost/LunaBuild/var/luna/repo}
REMOTE=${LUNA_REMOTE:-https://github.com/Lun3ku/luna-linux.git}
BRANCH=${LUNA_REPO_BRANCH:-repo}
ARCH=x86_64
SITE=${LUNA_REPO_URL:-https://lun3ku.github.io/luna-linux}

msg() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m!!!\033[0m %s\n' "$*" >&2; exit 1; }

dry=no
[[ ${1:-} == --dry-run ]] && dry=yes

[[ -d $SRC ]] || die "No repository at $SRC
       Is LunaBuild running? Try: wsl -d LunaBuild -- true"
[[ -f $SRC/luna.db.tar.gz ]] || die "No database in $SRC - run scripts/build-pkgs.sh first"

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/$ARCH"

msg "Copying the repository out of $SRC"
# -L dereferences: the database is a symlink in the built repository, and
# GitHub Pages does not follow symlinks. It would serve the link itself, so
# pacman asking for luna.db would receive fourteen bytes reading
# "luna.db.tar.gz" and report a corrupted database.
cp -L "$SRC"/*.pkg.tar.zst     "$stage/$ARCH/"
cp -L "$SRC"/*.pkg.tar.zst.sig "$stage/$ARCH/"
cp -L "$SRC/luna.db.tar.gz"    "$stage/$ARCH/luna.db.tar.gz"
cp -L "$SRC/luna.db.tar.gz"    "$stage/$ARCH/luna.db"
cp -L "$SRC/luna.files.tar.gz" "$stage/$ARCH/luna.files.tar.gz"
cp -L "$SRC/luna.files.tar.gz" "$stage/$ARCH/luna.files"

# --- checks, before anything is made public -------------------------------
if [[ -n $(find "$stage" -type l) ]]; then
  die "A symlink survived the copy; Pages would serve it as a text file"
fi

pkgs=$(find "$stage/$ARCH" -name '*.pkg.tar.zst' | wc -l)
sigs=$(find "$stage/$ARCH" -name '*.pkg.tar.zst.sig' | wc -l)
(( pkgs > 0 )) || die "No packages to publish"
(( pkgs == sigs )) || die "$pkgs packages but $sigs signatures"

# The database has to describe exactly the packages being published. A
# database listing a package that is not there turns every pacman -Syu on
# every installed machine into a 404.
indb=$(tar tzf "$stage/$ARCH/luna.db.tar.gz" | grep -c '/desc$' || true)
(( indb == pkgs )) || die "The database lists $indb packages, $pkgs are being published"

# Signatures are only meaningful if pacman can see them, which for a database
# built with repo-add --include-sigs means the %PGPSIG% field.
signed=$(tar xzOf "$stage/$ARCH/luna.db.tar.gz" --wildcards '*/desc' | grep -c '^%PGPSIG%$' || true)
(( signed == pkgs )) || die "Only $signed of $pkgs packages are signed in the database"

msg "$pkgs packages, all signed, database agrees"

# .nojekyll stops Pages running the files through Jekyll, which would take its
# own view of what to publish. index.html is there so the address is not a 404
# for a person who opens it in a browser.
touch "$stage/.nojekyll"
cat > "$stage/index.html" <<HTML
<!doctype html>
<meta charset="utf-8">
<title>Luna Linux package repository</title>
<style>
 body { font-family: system-ui, sans-serif; max-width: 42rem; margin: 4rem auto;
        padding: 0 1rem; background: #12111a; color: #e8e4f4; line-height: 1.6; }
 a { color: #b4a0ff; }
 pre { background: #1b1926; padding: 1rem; border-radius: 10px; overflow-x: auto; }
</style>
<h1>Luna Linux package repository</h1>
<p>This address serves the <code>[luna]</code> pacman repository. It is not a
web page; it is what <code>pacman -Syu</code> reads on a Luna system.</p>
<p>Every package is signed. To add it to an existing Arch install, put this in
<code>/etc/pacman.conf</code>:</p>
<pre>[luna]
SigLevel = Required DatabaseOptional
Server = $SITE/$ARCH</pre>
<p>and import the signing key from the <code>luna-keyring</code> package.</p>
<p><a href="https://github.com/Lun3ku/luna-linux">Luna Linux on GitHub</a></p>
HTML

msg "Building the $BRANCH branch from scratch"
(
  cd "$stage"
  git init -q -b "$BRANCH"
  # Binaries only: nothing here should be touched by line-ending translation.
  git config core.autocrlf false
  git add -A
  git -c user.name="Luna build" -c user.email="noreply@anthropic.com" \
      commit -q -m "Repository as of $(date -u '+%Y-%m-%d %H:%M UTC')

$(cd "$ARCH" && ls -1 *.pkg.tar.zst | sed 's/-x86_64.pkg.tar.zst$//;s/-any.pkg.tar.zst$//')"
  git remote add origin "$REMOTE"
  if [[ $dry == yes ]]; then
    msg "--dry-run: not pushing. The branch is ready in $stage"
    git log --stat -1 | head -30
  else
    msg "Force-pushing to $REMOTE ($BRANCH)"
    git push -q -f origin "$BRANCH"
  fi
)

if [[ $dry == no ]]; then
  # Held open so the temp directory is not removed before the push finishes.
  msg "Published. Pages serves it at:"
  printf '    %s/%s\n' "$SITE" "$ARCH"
  printf '\nIf this is the first publish, switch it on once at\n'
  printf '    https://github.com/Lun3ku/luna-linux/settings/pages\n'
  printf 'Source: Deploy from a branch, branch %s, folder /(root).\n' "$BRANCH"
  printf '\nThen check it:\n'
  printf '    curl -I %s/%s/luna.db\n' "$SITE" "$ARCH"
fi
