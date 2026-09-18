# Luna Linux

An Arch-based distribution: the latest stable kernel, Hyprland out of the box,
quality-of-life features only. Package manager: pacman.

`NAME="Luna Linux"`, `ID=luna`.

## Build environment

Luna is not built on Windows but inside a separate Arch WSL distribution named
`LunaBuild`, which lives on drive **E:** (`E:\WSL\LunaBuild`) because C: does not
have enough free space and a build needs 15-25 GB. The existing
`PistachioLinux` distribution is left alone.

The sources live here, on the Windows drive, because they are text and weigh a
few megabytes. The heavy work happens on ext4 inside `LunaBuild`, in `/var/luna`.

| What | Where |
|---|---|
| Sources | `C:\Users\anyah\Documents\Claudes work\luna` |
| The same, seen from WSL | `/mnt/c/Users/anyah/Documents/Claudes work/luna` |
| Copy of the profile on ext4 | `/var/luna/src` |
| mkarchiso work directory | `/var/luna/work` |
| Finished ISO images | `/var/luna/out` |

Creating the build host from scratch (from PowerShell):

```powershell
wsl --install archlinux --name LunaBuild --location E:\WSL\LunaBuild --vhd-size 50GB --no-launch
wsl -d LunaBuild -u root -- bash '/mnt/c/Users/anyah/Documents/Claudes work/luna/scripts/bootstrap-host.sh'
```

## Workflow

Every script runs inside `LunaBuild` as root:

```powershell
wsl -d LunaBuild -u root -- bash '/mnt/c/Users/anyah/Documents/Claudes work/luna/scripts/<script>'
```

| Script | What it does |
|---|---|
| `bootstrap-host.sh` | One-time preparation of the build host. Idempotent. |
| `check-packages.sh` | Checks that the package names still exist in the repositories. Arch is rolling; packages get renamed. |
| `make-branding.sh` | Renders the branding PNGs from the SVG sources in `branding/`. |
| `lint-configs.sh` | Checks the syntax of every Luna config. A broken config does not show up as a build error but as a broken desktop. |
| `build-pkgs.sh` | Builds the `luna-*` packages and updates the local repository. |
| `build-iso.sh` | Syncs the profile to ext4 and runs `mkarchiso`. |
| `test-iso.sh` | Boots the built image in QEMU. |
| `test-install-auto.sh` | Walks through the installer automatically with default answers. A regression test. |
| `vm-screenshot.sh` | Takes a screenshot of the VM over QMP. |
| `zoom-shot.py` | Crops a region of a screenshot and enlarges it; a 36-pixel-tall panel cannot be inspected any other way. |
| `vm-type.sh` | Sends keyboard input to the VM over QMP, including key combinations. |
| `vm-view.sh` | A noVNC web client for watching the VM in a browser. |

While debugging, the build can be made much faster at the cost of image size:

```bash
LUNA_COMP_LEVEL=3 ./scripts/build-iso.sh
```

For a release build, size wins over build time:

```bash
LUNA_COMP=xz ./scripts/build-iso.sh
```

## How to look at the VM

The WSLg window does not appear on every machine, so the primary way is a
browser. Run these in two separate long-lived processes:

```powershell
wsl -d LunaBuild -u root -- bash '/mnt/c/Users/anyah/Documents/Claudes work/luna/scripts/vm-view.sh'
wsl -d LunaBuild -u root -- bash '/mnt/c/Users/anyah/Documents/Claudes work/luna/scripts/test-iso.sh' --vnc
```

Then open:

```
http://localhost:8080/novnc/vnc.html?host=localhost&port=5700&path=&autoconnect=true&resize=scale&reconnect=true
```

`path=` is mandatory and must be empty: noVNC connects to `/websockify` by
default, while the websocket built into QEMU serves VNC only at the root `/`
and answers 404 on any other path.

A way that needs no browser is grabbing a frame straight out of the running VM:

```bash
./scripts/vm-screenshot.sh /where/to/put/it.png
```

## Layout

```
branding/ SVG sources for the splash screens and the logo
iso/      archiso profile (based on releng)
pkg/      our own packages: luna-base, luna-cli, luna-desktop, luna-installer, luna-keyring
repo/     the built local pacman repository
scripts/  building and running
docs/     notes on the decisions taken
```

## The Luna packages

| Package | What is inside | Where it is needed |
|---|---|---|
| `luna-release` | Nothing but `os-release` and the system identity. Depends on nothing. | Image and installed system |
| `luna-base` | The base (`base`, `base-devel`) and the reliability layer: btrfs + snapper + snap-pac, GRUB + grub-btrfs, zram, systemd-oomd, automatic cache cleanup, mirror refresh. | Installed system only |
| `luna-cli` | `fish` + `starship` and a modern set of tools with ready-made settings in `/etc/skel`. | Image and installed system |
| `luna-desktop` | Hyprland, waybar, rofi, mako, the login screen, the theme, the wallpaper. Configs in `/etc/skel`. | Image and installed system |
| `luna-keyring` | The public key the `luna-*` packages are signed with. | Image and installed system |

`luna-base` deliberately does **not** go onto the boot image: it pulls in
`base-devel` (+307 MB), and a compiler is of no use on a live USB stick. That
is exactly why the branding was split out into the tiny `luna-release`.

The kernel is not listed as a dependency: the user picks `linux` or `linux-zen`
in the installer, and `-headers` must match the chosen kernel. The installer
installs the kernel and its headers as a pair.

## Package signing

The `luna-*` packages are signed, and the `[luna]` repository is declared with
`SigLevel = Required DatabaseOptional`, the same as the official Arch
repositories. A package that is unsigned, or signed with somebody else's key,
will not be installed.

The chain of trust works like this:

1. `scripts/build-pkgs.sh` signs every package, and `repo-add --include-sigs`
   puts the signature inside the repository database.
2. The `luna-keyring` package carries the public key in
   `/usr/share/pacman/keyrings/` and ships on the image.
3. On the live image `pacman-init.service` fills the keyring on every boot with
   everything found in that directory, our key included.
4. The installer puts `luna-keyring` on the target disk, so after a reboot the
   system verifies the signatures of its own updates by itself.

The secret half of the key lives **only** in `~builder/.gnupg` on the build
machine and never enters the repository. The backup copy and the recovery
procedure are in `E:\Luna-Linux-Keys\README.txt`.

Creating the key from scratch (needed once, or after losing it):

```bash
./scripts/make-signing-key.sh
```

## How to add a package

The purpose decides the place:

- **onto the boot image** (installation tools, the live environment) goes into
  [iso/packages.x86_64](iso/packages.x86_64);
- **onto the installed machine** goes into `pkg/luna-*/depends.txt`, so that the
  package arrives together with our metapackage and is then updated by an
  ordinary `pacman -Syu`.

After that:

```bash
./scripts/check-packages.sh pkg/luna-desktop/depends.txt   # do the names exist?
./scripts/build-pkgs.sh luna-desktop                      # rebuild the package
./scripts/build-iso.sh                                    # rebuild the image
```

Checking the names is not optional: Arch is rolling, packages get renamed and
dropped, and finding that out halfway through an image build is unpleasant.

The reasoning behind the decisions, and the non-obvious facts behind them, are
in [docs/decisions.md](docs/decisions.md).

Luna's configuration is shipped as **real pacman packages** rather than as an
`airootfs` overlay: the overlay exists only on the live ISO and never reaches
the installed machine, whereas we want an installed system to get the same
defaults and to keep updating them through an ordinary `pacman -Syu`.
