# Decisions and findings

Everything below was verified in practice rather than taken from first
principles. The dates are September 2026, and the package versions are the
ones current at that time.

## Hyprland 0.56 is configured in Lua

The `hyprland` package no longer ships an example `hyprland.conf`; what it
ships instead is `/usr/share/hypr/hyprland.lua`. The binary contains the
string:

```
[cfg] Lua config not found, using legacy config at {}
```

So Lua is the primary format and the familiar ini-like `hyprland.conf` is
what remains as legacy. Luna writes its config in Lua.

The full API description lives in the package itself:
`/usr/share/hypr/stubs/hl.meta.lua` (1777 lines of LuaLS annotations). That is
the only dependable source, and every call in our config was checked against
it. It is also where the complete list of dispatchers comes from:
`hl.dsp.window.{close,float,fullscreen,center,pin,move,drag,resize,swap,...}`,
`hl.dsp.focus`, `hl.dsp.workspace.toggle_special`, `hl.dsp.layout`.

The rest of the ecosystem tools (`hyprlock`, `hypridle`, `hyprpaper`) did
**not** change format and still use their own hypr-lang `.conf`.

## The session starts through uwsm, not directly

`hyprpaper`, `hypridle`, `hyprpolkitagent`, `cliphist`, `waybar`, `mako` and
`blueman-applet` all have systemd user units bound to
`graphical-session.target`. Hyprland itself does not bring that target up, so
starting "just Hyprland" would leave every one of them dead.

Hyprland registers two sessions in `/usr/share/wayland-sessions`:

| File | Exec |
|---|---|
| `hyprland.desktop` | `/usr/bin/start-hyprland` |
| `hyprland-uwsm.desktop` | `uwsm start -e -D Hyprland hyprland.desktop` |

Luna uses the second one. Because of that, systemd runs the panel and the
notifications and restarts them when they die, and the Hyprland config has
almost no autostart in it.

## Hyprland refuses to run as root

The binary carries an `--i-am-really-stupid` flag that disables the root
check. That means the live image has to have an ordinary user, which is where
`luna-live-user.service` in the ISO overlay comes from.

## The live image user is created by a service, not by sysusers.d

Two independent obstacles:

1. During an image build, users are created by a **pacman hook**
   (`20-systemd-sysusers.hook`), while the `airootfs` overlay is copied only
   after the packages are installed. The hook would never see a file in
   `airootfs/etc/sysusers.d/`.
2. `systemd-sysusers.service` is marked `ConditionNeedsUpdate=|/etc` and may
   not run at boot at all.

So the user is created by an explicit oneshot service, the same technique
archiso itself uses for `pacman-init`.

## The login screen is enabled by a display-manager.service symlink

`greetd.service` has no `WantedBy`, only `[Install] Alias=display-manager.service`.
What starts it is `graphical.target`, which carries
`Wants=display-manager.service`. The image therefore needs two symlinks:
`default.target` -> `graphical.target` and `display-manager.service` ->
`greetd.service`.

## cow_spacesize cannot be given as a percentage

By default the overlay of the live system is **256 MB**, which is not enough
even to install a couple of packages to try them out. The value is set by the
`cow_spacesize` kernel parameter, but in the archiso hook it ends up not only
in `mount -o size=` but also in `truncate -s`, and `truncate` does not
understand percentages. A fixed size is therefore the only option. Ours is
`cow_spacesize=2G`.

## makepkg does not support subdirectories in local sources

`source=('files/config.conf')` does not work: `get_filename` strips the path
and makepkg looks for the file next to the PKGBUILD. That is why package files
live in the same directory as the PKGBUILD, with no nesting.

## Other people's configs are overridden by drop-ins, not by overwriting

`/etc/xdg/reflector/reflector.conf` and `/etc/greetd/config.toml` belong to
their own packages and are marked as backup. Rather than overwrite them, Luna
drops in a systemd override that replaces `ExecStart`:

- `reflector.service.d/10-luna.conf` gives our own arguments instead of the
  config file;
- `greetd.service.d/10-luna.conf` gives `greetd --config /etc/greetd/luna.toml`.

That way there is no file conflict and no `.pacnew` on updates.

## os-release and the login greeting

`/usr/lib/os-release` belongs to the `filesystem` package, and
`/etc/os-release` is a symlink that belongs to nobody. So `luna-release` puts
its own file at `/usr/lib/os-release-luna` and repoints the symlink from its
`.install`.

A pleasant side effect: `/etc/issue` contains `\S{PRETTY_NAME}`, that is, it
takes the name straight out of os-release. The login greeting needs no
separate editing.

## pulseaudio and pipewire-pulse are mutually exclusive

Verified in both directions: `pipewire-pulse` conflicts with `pulseaudio` and
the other way round. At the same time `pipewire-pulse` declares
`Provides: pulse-native-provider`, so the PulseAudio interface is there and
`pactl`, `pavucontrol` and browsers work unchanged. For Hyprland, pipewire is
mandatory: without it screen capture through
`xdg-desktop-portal-hyprland` does not work.

## base-devel costs 307 MB

17 packages on top of `base`, of which `gcc` is 221 MB and `binutils` 44 MB.
It is part of `luna-base` because without it one can neither build a DKMS
module nor install anything from the AUR (and an AUR helper itself lives in
the AUR, so without `makepkg` it cannot be installed).

Those 307 MB are exactly why the branding was split out into a separate
`luna-release` package: that one goes onto the boot image, while `luna-base`
goes only onto the installed system.

## hyprpaper 0.8: the config schema changed and the wiki is stale

The wallpaper never appeared, and the log held nothing but:

```
Monitor Virtual-1 has no target: no wp will be created
```

The reason: in hyprpaper 0.8 the wallpaper is set by a **section**, and the
`preload` key does not exist at all. A binary search through the program
returns zero occurrences of the string `preload`, while the source in
`src/config/ConfigManager.cpp` registers `splash`, `splash_offset`,
`splash_opacity`, `ipc` and a special `wallpaper` category with the fields
`monitor`, `path`, `fit_mode`, `timeout`, `order` and `recursive`.

The form that works:

```
wallpaper {
    monitor =
    path = /usr/share/backgrounds/luna/luna.png
    fit_mode = cover
}
```

**At the time of checking, the official wiki still described the old syntax.**
For the hypr ecosystem we treat the source and the binary as the source of
truth, not the wiki.

While we were there, `misc:background_color` was set in `hyprland.lua`: if
hyprpaper ever fails to start, the desktop will still look deliberate instead
of being a black hole.

## Nerd Font glyphs must not be written as literal characters

The panel icons disappeared: out of a dozen glyphs in the written
`waybar-config.jsonc`, two were left. Nerd Font characters live in the Unicode
private use area and get lost when a file passes through tools, editors and
terminals - silently, leaving empty strings where the icons were.

The icons are therefore written as **JSON escape sequences**, which keeps the
file pure ASCII. The `waybar glyphs` check in `scripts/lint-configs.sh` watches
over this: it fails if a literal private-use character appears in the config.

Every icon code was checked for actually being present in JetBrainsMono Nerd
Font:

```bash
fc-match ":charset=f111" family     # should return *JetBrainsMono*
```

Out of the set we checked, only `U+F6A9` turned out to be missing from the font.

The family name, incidentally, is correct: `JetBrainsMono Nerd Font`. The false
diagnosis of "wrong name" came from typing the check in the VM as
`JetBrainsMono-Nerd-Font` (with hyphens, to work around the spaces in the
command), which is a different name, and fontconfig honestly substituted a
replacement.

## WSL has no /dev/dri, so there is no hardware acceleration in the VM

The render node does not exist inside a WSL distribution, which makes
`virtio-vga-gl` and virgl useless here: the guest always runs on software
rendering (`kms_swrast`) and EGL complains in the logs. The `--gl` option in
`scripts/test-iso.sh` is kept for running on real hardware.

It is important not to blame this limitation too early: the missing wallpaper
looked like a consequence of software rendering and turned out to be a mistake
in the config.

## A channel from the guest into a file on the host

Fishing long logs out of screenshots is unbearable, so the VM has a serial port
attached and written to `/var/luna/guest.log`. From inside the guest:

```bash
systemctl --user status hyprpaper -l -n 40 | sudo tee /dev/ttyS0 > /dev/null
```

`sudo` is needed because `/dev/ttyS0` belongs to `root:uucp`. The live image
user was added to the `uucp` group, so after a rebuild the redirection works
without sudo too.

## blueman-applet is not enabled by default

Without a bluetooth adapter the unit simply fails and spoils the failed-service
count on the panel. The bluetooth status is visible in the waybar module
anyway, and anyone who wants the applet can run
`systemctl --user enable --now blueman-applet.service`.

## The wallpaper is set by swaybg, not by hyprpaper

After the move to the new config schema, hyprpaper stopped complaining about a
missing target and started crashing with SIGSEGV instead, restarting until it
hit the systemd limit:

```
hyprpaper.service: Main process exited, code=dumped, status=11/SEGV
hyprpaper.service: Start request repeated too quickly.
```

Testing it on Hyprland's own stock wallpaper (`/usr/share/hypr/wall0.png`) gave
the same SIGSEGV, so our picture was not to blame. It crashes wherever there is
no working EGL; the log right before it says:

```
ERR from hyprtoolkit ]: [EGL] Command eglInitialize errored out with EGL_NOT_INITIALIZED
MESA-EGL: warning: NEEDS EXTENSION: falling back to kms_swrast
```

That is, in any virtual machine without a GPU passed through. A distribution
whose wallpaper crashes in a VM is hard to call a quality-of-life
distribution: people run Linux in VMs constantly, and for many the first
meeting with Luna will happen exactly there.

**swaybg worked immediately under the same conditions**: it draws through cairo
and ordinary `wl_shm` buffers and needs no GL. It weighs 34 KB.

So the wallpaper is set by the `luna-wallpaper.service` unit, which runs the
`/usr/bin/luna-wallpaper` script on top of swaybg. hyprpaper stays installed as
an alternative for anyone who has a GPU and wants IPC control over the
wallpaper:

```bash
systemctl --user disable --now luna-wallpaper
systemctl --user enable  --now hyprpaper
```

A small but pleasant thing came out of it: the wallpaper can be changed with a
single line, without editing configs or units:

```bash
echo /path/to/picture.png > ~/.config/luna/wallpaper
systemctl --user restart luna-wallpaper
```

If the file contains nonsense the script quietly falls back to the default
wallpaper: being left with a black screen because of a typo is a poor outcome.

## The system language is English, and so are the comments

Luna's interface is entirely in English: launcher labels, panel tooltips, the
lock screen, unit descriptions in `systemctl`. The comments in the configs are
English too. They were Russian at first, addressed to whoever edits the
configs rather than to whoever uses the system, and were translated later so
that the repository reads in one language throughout. The commit messages
before that point were left in Russian: rewriting them would change every
commit hash, and the v1.0 release tag is pinned to one of them.

The clock is 12-hour: `"format": "{:%I:%M %p}"`.

**The `locale` parameter must not be set in the clock module.** Pinning it to
`en_US.UTF-8` switched the clock off entirely:

```
module clock: Disabling module "clock",
locale::facet::_S_create_c_locale name not valid
```

The cause ran deeper than the clock: on the live system `locale -a` listed only
`C`, `C.utf8` and `POSIX`, that is, **not a single generated UTF-8 locale**.
That breaks more than the clock; sorting and date formatting go with it.

So the locale is generated for real, in the `.install` of the `luna-release`
package: it uncomments `en_US.UTF-8` in `/etc/locale.gen` and runs
`locale-gen`. Editing somebody else's file is justified here - glibc has no
drop-in mechanism, and locales created directly with `localedef` are wiped by
the next `locale-gen`. The file is marked as backup by glibc, so the edit
survives updates.

The `.install` script also runs during an image build: mkarchiso installs
packages with ordinary pacman, so the locale ends up inside the ISO already.

On the lock screen the same job is done by hyprlock's built-in `$TIME12`
variable; plain `$TIME` gives 24 hours.

The keyboard layout stays `us,ru` with Alt+Shift to switch: an English
interface does not mean there is no need to type in Russian.

## systemd-loop@.service is masked on the live image

When booting from a CD drive, systemd creates a `systemd-loop@` instance for
the drive itself, and it fails:

```
systemd-loop@...block-sr0.service  failed  Attach File /sys/devices/...
```

The rule that fires is in `/usr/lib/udev/rules.d/99-systemd.rules`:

```
SUBSYSTEM=="block", ENV{ID_CDROM}=="1",
ENV{ID_PART_GPT_AUTO_ROOT_DISK_NEEDS_LOOP}=="1",
  ENV{SYSTEMD_WANTS}+="systemd-loop@.service"
```

The mechanism is meant to supply a loop device when the kernel does not parse
the GPT on a disk booted through El Torito. But archiso already masks
`systemd-gpt-auto-generator`, the only consumer of that construction. The
binding is therefore pointless and can do nothing but fail.

Harmless in itself, but the Luna panel shows a failed-service counter, and a
permanent false alarm teaches people to ignore it, which is precisely the
opposite of what the module is for. So the image overlay contains
`airootfs/etc/systemd/system/systemd-loop@.service -> /dev/null`.

The mask lives **only on the image**. On an installed system the boot does not
come from an optical drive, `ID_CDROM` is not set, and the rule never fires at
all, just as it does not when the image is booted from a USB stick.

## An icon sitting off-centre is the glyph's fault, not the font's

The network icon in the panel sat noticeably lower than its neighbours. The
first hypothesis was font metrics, and the `JetBrainsMono Nerd Font Mono`
variant was tried for single-icon modules. **It did not help**: after a rebuild
the icon stayed exactly where it was.

It is the glyph itself: `sitemap` (U+F0E8) in Font Awesome is drawn offset
downwards from the baseline. The hint was on the same screen - the round clock
icon (U+F017) centred perfectly.

The cure is a different glyph, not a CSS tweak. Ethernet was moved to the globe
(U+F0AC), which is round as well. The font change was reverted: it achieved
nothing, and a comment explaining it would have stated something untrue.

The practical rule: if an icon sits off-centre, look for a different glyph, and
round ones almost always sit correctly.

Inspecting that sort of thing on a full screenshot is hopeless - the panel is
36 pixels tall. That is what `scripts/zoom-shot.py` was written for: it crops a
region and enlarges it with no external dependencies, parsing the PNG through
zlib.

```bash
python scripts/zoom-shot.py shot.png crop.png 965 4 300 40 5
```

## An empty button in the system tray

A pill with no icon hung to the right of the clock. The tray held exactly one
item, `nm-applet`, which was started from the Hyprland config. On the live
image the network is managed by `systemd-networkd`, so the applet had nothing
to show.

The autostart was removed: the network state is visible in the panel module,
and clicking it opens `nmtui`. The `network-manager-applet` package was kept -
`nm-connection-editor` from it is useful on an installed system.

The `tray` module also lost its background while we were there. The pill would
be drawn even when empty, and a button of unknown purpose is more irritating
than the absence of a backdrop behind the icons.

## Hyprland registers two sessions, and the ordinary one is a trap

The installation succeeded, the system booted, the login worked - and there was
no desktop, only a background and a cursor. Measured on the installed machine:

```
graphical-session.target  inactive
waybar                    inactive
luna-wallpaper            inactive
XDG_CURRENT_DESKTOP       (empty)
```

The cause: Hyprland puts **two** files into `/usr/share/wayland-sessions`,
`hyprland.desktop` (which runs `start-hyprland`) and `hyprland-uwsm.desktop`
(which runs `uwsm start`). The first creates no systemd session at all, while
every one of our units is bound to `graphical-session.target`. By default
tuigreet takes the first session in the list, which is exactly the broken one.

Fixed in two layers, because one is not enough:

1. `/usr/bin/luna-session`, a wrapper the login screen receives through
   `--cmd`. By default it always starts the uwsm variant, regardless of the
   order of files in the sessions directory. Choosing another one with F3 still
   works.
2. A safety net in `hyprland.lua`: if `graphical-session.target` is inactive,
   the config imports the environment variables and brings the target up
   itself. Otherwise the ordinary entry in the login menu stays a trap for
   whoever picks it, and for whoever runs `Hyprland` by hand from a console.

After the fix, on the installed system: every unit `active`,
`XDG_CURRENT_DESKTOP=Hyprland` both in the applications' environment and in
systemd, and no failed services.

## UEFI variables in the test VM survive deleting the disk

The symptom looked like "the installer is broken": the VM would not boot at
all. What actually happened was that the firmware tried to load the
`Boot0009 "Luna"` entry left in NVRAM by the previous installation, failed to
find it on a clean disk, went through PXE and HTTP boot and gave up **without
ever trying the CD**.

The NVRAM lives in a separate `OVMF_VARS.fd` file and is not erased along with
the qcow2 disk. So `scripts/test-iso.sh` now clears it whenever it creates a
new disk, and there is a `--reset-nvram` flag as well.

This is the class of failure that is easy to blame on the distribution's own
code and then spend a long time looking for in the wrong place.

## What has been verified on an installed system

Not "should work", but verified by running it:

- the installer goes through from partitioning to configuring snapshots;
- the disk is laid out as intended: `vda1` vfat `LUNA_EFI` -> `/efi`,
  `vda2` btrfs `Luna` with the subvolumes `@ @home @snapshots @log @pkg`;
- the firmware boots through `\EFI\Luna\grubx64.efi`;
- the desktop comes up in full and `systemctl --failed` is empty;
- `snapper` works, and `grub-btrfsd` regenerates
  `/boot/grub/grub-btrfs.cfg` by itself when a snapshot appears, so the
  rollback entry shows up in the bootloader menu with no manual steps.

## Branding: SVG sources, PNGs derived

The images are not stored in the repository as opaque binaries. `branding/`
holds SVGs, which are edited as text and versioned meaningfully, and
`scripts/make-branding.sh` renders the PNGs of the needed sizes out of them.

The renderer is `rsvg-convert` from librsvg, which is already on the build host
as a dependency of gtk, so a separate imagemagick was not needed.

### The boot menu splash used to be Arch's

From the releng profile we inherited `syslinux/splash.png`, the Arch Linux logo
with the caption "A simple, lightweight linux distribution". For a derivative
distribution that is not only a mismatch in style but somebody else's trademark
inside the image. Replaced with our own splash.

It is used when booting from BIOS: mkarchiso copies exactly this file
(`install -m 0644 -- "${profile}/syslinux/splash.png" ...`).

### The image's UEFI menu was left on systemd-boot (later reversed)

We tried moving it to GRUB for the sake of a background image - archiso
supports that (`uefi-x64.grub.esp`). It turned out that mkarchiso copies **only
`.cfg` files** out of the profile's `grub/` directory, putting the config at
`/boot/grub/grub.cfg` on the image. A PNG cannot be placed there by supported
means, and without a background the change of bootloader gains almost nothing.

The decision at the time was not to change a working bootloader for zero gain.

**This was later reversed, for a completely different reason.** See "A quarter
of a gigabyte was sitting in a duplicate kernel" below: systemd-boot demands a
second copy of the kernel and the initramfs inside the bootable FAT image, and
that copy weighed 261 MiB. The background picture is still not possible, but
the weight decided it. A reverted decision is worth recording together with its
reason, because the reason can stop outweighing the alternative.

### The GRUB background is rendered at 16:9

The first attempt was 4:3, and on a wide screen the moon became noticeably
elliptical: GRUB stretches the background across the whole screen without
preserving the aspect ratio. 16:9 is the lesser evil for most monitors.

### The terminal logo was computed, not eyeballed

The moon for fastfetch is drawn with half-block characters from a circle
formula (no script in `scripts/` is needed, the generator was a one-off). The
first attempt came out squashed: I applied a correction for the font's aspect
ratio, although with half-block characters the pixel grid is **already square**
- each cell carries two pixels vertically.

The colours are given as the markers `$1` and `$2`, which fastfetch substitutes
itself, so the file stays plain text with no escape sequences - and those, as
the Nerd Font glyphs showed, are easy to lose in transit.

### The Plymouth splash is built on the stock module

The Luna theme uses `two-step`, the same module the `spinner` theme uses. The
thirty throbber frames are not duplicated but linked symbolically to
`spinner`: there is no point drawing our own white dots, and on a dark
background they look right as they are. What is ours in the theme is the moon
watermark and the colours.

Before that we checked that `two-step.so` is present in the package at all: the
mkinitcpio hook **refuses to build an initramfs** if the theme module is
missing (`error "The default plymouth plugin (%s) doesn't exist"; return 1`),
which is a direct route to a system that will not boot.

The theme is selected by `plymouth-set-default-theme` from the package's
`.install` rather than by replacing `/etc/plymouth/plymouthd.conf`, which
belongs to the plymouth package. When `luna-base` is removed the theme goes
back to `bgrt`, otherwise plymouth would keep pointing at a directory that is
about to disappear.

Verified on an installed system: the theme is `luna`, `/proc/cmdline` contains
`splash`, and `plymouth-quit-wait` is active. The splash barely gets a chance
to show itself - booting takes about ten seconds.

## Proofreading the package lists: where the money was and where it was not

The review was done by the numbers rather than by eye: the installed size of
every package in every list was measured.

### The icon font: 232 MiB -> 10 MiB

The biggest find. The `ttf-jetbrains-mono-nerd` package weighs **231.9 MiB**
and contains 96 files: every weight of every variant (Mono, Propo, NL, from
Thin to ExtraBold, with italics). Two of them are needed.

The replacement: `ttf-jetbrains-mono` (7.4 MiB) + `ttf-nerd-fonts-symbols-mono`
(2.5 MiB). Fontconfig substitutes the icons from the symbol font by itself.
Verified against every code in use:

```
fc-match ":charset=f111"  ->  Symbols Nerd Font Mono
fc-match "JetBrains Mono" ->  JetBrains Mono
```

The family name in the configs was changed from `JetBrainsMono Nerd Font` to
`JetBrains Mono`, and the panel was verified by booting it - the icons are
there.

### The image's package list is best left alone

Every candidate for removal was measured: network scanners, disk cloning tools,
VPN clients, IRC, a text browser, boot diagnostics. They add up to about
**100 MB, 4% of the image**.

What would be lost in exchange is a working rescue kit, and `open-vm-tools`
along with the VirtualBox guest additions directly improve life inside a
virtual machine, which is where the distribution is most often tried first. A
negative result is a result too: the list is inherited from releng and is
justified as it stands.

### An open question: noto-fonts-cjk, 299 MiB

Fonts for Chinese, Japanese and Korean. Without them such text shows up as
boxes - on websites, in file names, sometimes in interfaces. Kept for now:
"text is displayed" counts as quality of life as well. But this is the single
largest package in the system, and the decision is worth making deliberately.

## Package signing: where the keyring actually lives

The central fact, the one that makes the whole arrangement look unlike what you
would expect:

```
$ pacman --root /tmp/fakeroot -Qv
Root      : /tmp/fakeroot/
DB Path   : /tmp/fakeroot/var/lib/pacman/
GPG Dir   : /etc/pacman.d/gnupg/      <- not /tmp/fakeroot/etc/...
```

`--root` relocates everything except the keyring directory. That means that
during an installation, package signatures are verified against the keyring of
the **live system**, not against the one being created on the target disk. Two
consequences follow:

- `luna-keyring` has to be in `iso/packages.x86_64`. Without it the live image
  does not know the Luna key, and the installation fails on the very first
  `luna-*` package, no matter what is on the target disk.
- The keyring on the target disk is not needed for the installation but for
  what comes after the reboot: `pacman -Syu` updates.

The live image's keyring does not come from the build. `mkarchiso` calls
`pacstrap -G`, so the keyring directory never enters the image at all, which is
visible right in the build's work directory:

```
$ ls /var/luna/work/x86_64/airootfs/etc/pacman.d/
hooks  mirrorlist          # no gnupg
```

It is created on every boot by `pacman-init.service` from the archiso profile:
it mounts a tmpfs on `/etc/pacman.d/gnupg`, then runs `pacman-key --init` and
`pacman-key --populate` with no arguments. Populate with no arguments takes
**every** keyring from `/usr/share/pacman/keyrings/`, so it is enough for the
`luna-keyring` package to put `luna.gpg` and `luna-trusted` there; nothing has
to be enabled separately.

### pacstrap -K creates the keyring but does not populate it

```
if (( initkeyring )); then
    pacman-key --gpgdir "$newroot/$gpg_dir" --init
```

There is no `--populate` next to it, and `pacman-key` does not do one inside
`--init` either. What fills the target system's keyring is the keyring
package's scriptlet, already inside the chroot.

### The keyring package has to depend on pacman

The `luna-keyring` scriptlet calls `pacman-key`. The install order within a
single transaction is decided by dependencies, and a package that depends on
nothing may end up installed before `pacman` itself - in which case the
scriptlet quietly does nothing and the `if pacman-key -l` guard hides that.
Hence `depends=('pacman')`. For good measure the installer calls
`pacman-key --populate luna` in the chroot once more after `pacstrap`: the
operation is idempotent.

### repo-add without --include-sigs does not write the signature into the database

Signing the packages is not enough. The first build produced six `.sig` files
and zero `%PGPSIG%` fields in the database:

```
==> Packages in the database: 6
==> Of those, signed in the database: 0
```

The field is only added with the `--include-sigs` flag. Without it pacman looks
for a `.sig` file next to the package on the server, and the arrangement works
right up until those files are lost while the repository is copied around - and
ours is copied twice, onto the image and onto the target disk. A signature
inside the database does not fear that loss. The build now compares the number
of packages against the number of `%PGPSIG%` fields itself and fails on a
mismatch.

### The database itself is not signed, and that is not an oversight

The first attempt signed the database as well (`repo-add -s`). The image build
started emitting:

```
warning: Public keyring not found; have you run 'pacman-key --init'?
error: luna: key "5F6AD9A1840D7E15D5A4B743C7EE1CD46EE15432" is unknown
error: keyring is not writable
```

The culprit is `mkarchiso`'s final step: it calls `pacman -Q --sysroot` against
the built image in order to write the package list onto the ISO. Unlike
`--root`, the `--sysroot` option relocates the keyring directory too - and the
image has no keyring of its own, since it is created only at boot. The package
list still came out intact, so the error was harmless. A harmless error in a
build log is worse than a useful one: people get used to it and stop reading.

A database signature protects nothing here. Every package in the database
carries its own signature (`%PGPSIG%`), and a database signature neither helps
nor hinders swapping a package for somebody else's. Arch does not sign its own
databases for the same reason. Removed; when a network repository appears the
question is worth revisiting.

**One consequence to keep in mind.** Anyone who synced the repository while the
database was still signed keeps a cached `luna.db.sig` in their `dbpath`. It no
longer matches the rebuilt database, and pacman then rejects the whole
repository:

```
error: luna: signature from "Luna Linux <luna@localhost>" is invalid
error: failed to synchronize all databases (invalid or corrupted database (PGP signature))
```

The cure is deleting that one stale file. A freshly installed system never sees
this, because its dbpath starts empty - only a machine that was used during the
intermediate state is affected.

### pacman's cache breaks rebuilding a package at the same version

An image build failed out of nowhere:

```
error: luna-cli: signature from "Luna Linux <luna@localhost>" is invalid
:: File /var/cache/pacman/pkg/luna-cli-0.1.0-1-any.pkg.tar.zst is corrupted
```

Rebuilding does not change the version `0.1.0-1`, but it does change the
contents of the package (timestamps at the very least). `mkarchiso` calls
`pacstrap -c`, that is, with the host's cache; pacman finds a file with the
expected name there from the previous build and checks it against the fresh
signature. While the packages were unsigned the discrepancy never showed.

`build-pkgs.sh` now deletes the built package from `/var/cache/pacman/pkg`
right after building it. The same trap spoiled a manual signature test as well:
an unsigned package "installed" only because pacman had taken a copy from the
cache, left there by the previous, successful run. Any signature test has to
set its own `--cachedir`.

### Image compression: zstd for working, xz for a release

The sizes of one and the same content (4.5 GiB before compression):

| Compression | ISO size | What for |
|---|---|---|
| zstd, level 3 | 2.48 GiB | debugging, a build in minutes |
| zstd, level 19 | 2.20 GiB | an ordinary build |
| xz + the x86 BCJ filter | 2.12 GiB | a release |

The gain of xz over zstd-19 turned out to be only 3.4%, noticeably less than
expected, and on its own it was not enough for the limit. About 132 MB were
still missing, and they were not found in compression (see the next section).

The choice is not only about aesthetics: a file in a GitHub release has to be
**under 2 GiB**, and zstd does not fit inside that. It is switched with the
`LUNA_COMP=xz` variable.

Compressing the finished ISO with an archiver is not a way out, and that was
measured rather than assumed: WinRAR at its maximum level gained **3.45%** on a
slice of the image, because what is inside is already a compressed squashfs.
That does not reach the limit, and bootability is lost entirely.

### How it was checked that verification is not decoration

The first three attempts at a check turned out to be worthless, and that is
worth writing down, because the mistakes are typical ones:

1. **The shared pacman cache.** An unsigned package "installed" because pacman
   took a copy out of `/var/cache/pacman/pkg` that a previous, successful test
   had downloaded, signature and all. Any signature test has to set its own
   `--cachedir`.
2. **grepping for the word error.** The dependency list contains
   `libgpg-error`, so a check of "is there an error in the output" fired every
   single time. The verdict has to come from the exit code.
3. **Too crude a forgery.** Bytes appended to the end of a package are rejected
   before the signature is ever checked, on the size recorded in the database.
   That is a protection too, but it is not testing what we meant to test.

A sound test: a genuine package with a genuine detached signature, but made
with somebody else's key - then the only thing that can stop the installation
is signature verification.

```
error: key "9F23B793E8460BEA" could not be looked up remotely
error: required key missing from keyring
Errors occurred, no packages were upgraded.
```

### The key

No passphrase, because otherwise the build would ask for a password once per
package, six times over. The secret half lives only in `~builder/.gnupg` on the
build machine and never enters the repository. The backup copy is in
`E:\Luna-Linux-Keys\`, together with a README describing how to restore it. The
copy has been verified: imported into an empty keyring, used to sign a file,
and the signature checked out.

Losing the key cannot be repaired: a new key means every already-installed
system stops trusting updates until `luna-keyring` is updated on it by hand.


## A quarter of a gigabyte was sitting in a duplicate kernel

The xz image weighed 2.12 GiB while the squashfs inside it was only 1.62 GiB.
The half-gigabyte difference was found like this:

```
$ xorriso -indev luna.iso -report_el_torito plain
El Torito boot img : 1  BIOS ...      4 blocks
El Torito boot img : 2  UEFI ... 133632 blocks     # 261 MiB
```

The bootable FAT image for UEFI weighed 261 MiB. The reason is visible right
inside `mkarchiso`: the systemd-boot mode puts the kernel, the initramfs and
the microcode into that image -

```bash
efiboot_files=("${isofs_dir}/EFI/" "${isofs_dir}/loader/" ...
               "${boot_dir}/vmlinuz-"* "${boot_dir}/initramfs-"*".img" ...)
```

- while the very same files are already on the ISO separately, in
`/luna/boot/x86_64/`. There is no other way: systemd-boot cannot read ISO9660
and sees only FAT.

The `uefi.grub` mode puts a single bootloader into the FAT image:

```bash
efiboot_files=("${isofs_dir}/EFI")
```

GRUB reads ISO9660 itself, and the kernel stays in the image in one copy.

This is the very switch that had been reverted earlier, because `mkarchiso`
copies only `.cfg` files out of the profile's `grub/` directory and there is no
way to put a background picture into the menu. Back then there was nothing to
pay for it with. Now there is a quarter of a gigabyte on the other side of the
scale, and the decision flips. A useful lesson: a reverted decision is worth
recording together with its reason, because the reason can stop outweighing the
alternative.

What matters is that the thing to look for was the **difference** between the
size of the ISO and the size of the squashfs. As long as you stare at the final
number, the only obvious candidate for cutting is the content of the system,
that is, the 299 MiB of CJK fonts. Those would have been thrown out, although
they have nothing to do with it.

## Two automated installers on one VM wipe the partition table

The installed system would not boot:

```
BdsDxe: failed to load Boot0009 "Luna" from HD(1,GPT,...)/EFI/Luna/grubx64.efi: Not Found
```

The disk turned out to be in a strange state: both copies of the GPT, the
primary one in sector 0 and the backup in the last sector, were completely
zeroed, while the filesystems were intact. The FAT at the 1 MiB mark was
readable, the btrfs further along was in place as well, and 4.4 GiB of data had
been written.

Exactly one command produces that combination: `sgdisk --zap-all`, the first
line of `do_partition`. In other words, the installer had started a **second
time** and got as far as partitioning the disk the first one had just finished
installing to. It is visible on the screenshot too: next to the "Installation
complete" window hangs a second one saying "Partitioning /dev/vda".

The distribution is not to blame here, the test rig is:
`test-install-auto.sh` had been started twice against the same VM. The first
run did not wait long enough for the boot (an xz image takes longer than the
previous 125 seconds), its keystrokes went nowhere, and then part of them
arrived after all and opened a second installer.

Fixed in two ways at once:

- the boot wait was moved into a `BOOT_WAIT` variable with a value of 210
  seconds instead of the hard-coded 125;
- the script takes a `flock` on `/var/luna/auto-install.lock` and refuses to
  start as the second instance.

Verified on a live run: a second start answers "Another run is already in
progress" and exits with code 1.

The method of diagnosis is worth remembering separately. The symptom, "it does
not boot", explains nothing. What explained it was the pattern of the damage:
**what exactly was destroyed and what survived**. Both copies of the GPT zeroed
while the filesystems were alive is the signature of one specific command, and
it named the culprit immediately.

## First install on real hardware: two messages, one of them ours

Luna was installed on a laptop, outside QEMU for the first time. The
installation went through and the installed system works. Two things appeared
on screen along the way, neither of which stopped anything.

### The GRUB serial error was ours, and QEMU hid it

Before the menu drew, with a beep:

```
error: term/serial.c:grub_cmd_serial:278:serial port 'com0' isn't found.
```

The cause was in our own `iso/grub/grub.cfg`, inherited from releng:

```
if serial --unit=0 --speed=115200; then
```

A modern laptop has no physical COM port, so the command fails. The
surrounding `if` keeps the config from aborting, but it does **not** suppress
the message: GRUB prints the error when the command runs, and only afterwards
is the exit status swallowed. A conditional guards control flow, not output.

Two things are worth keeping from this.

**It was introduced by the switch to GRUB.** While the UEFI menu was drawn by
systemd-boot, this `grub.cfg` was dead weight that nothing read. Moving UEFI to
GRUB for the sake of 261 MiB put the file into service and its serial block
with it. A change that removes one problem can hand a dormant file a new job.

**The test environment was gentler than reality.** QEMU provides a serial port,
so `serial --unit=0` succeeded in every run we made, and the error could not
appear. A virtual machine is not a weaker version of real hardware; it is
different hardware, and it can be missing exactly the defect you would want to
find. Here it was the other way round: the VM *had* something a laptop does
not.

The block was removed. In this profile `grub.cfg` is the UEFI path only (BIOS
boots through syslinux), so it could never have done anything but fail on the
hardware Luna is aimed at. The comment left in its place carries the block for
anyone who does need a GRUB serial console.

### The ACPI errors are the laptop's firmware, not ours

After choosing Luna in the menu:

```
ACPI BIOS Error (bug): Attempt to CreateField of length zero (20260408/dsopcode-133)
ACPI Error: Aborting method \_SB.WMID.WQBC due to previous error (AE_AML_OPERAND_VALUE)
ACPI BIOS Error (bug): Attempt to CreateField of length zero (20260408/dsopcode-133)
ACPI Error: Aborting method \_SB.WMID.WQBE due to previous error (AE_AML_OPERAND_VALUE)
```

The `(bug)` in the first line is the kernel stating plainly that the defect is
in the firmware's ACPI tables. `\_SB.WMID.WQBC` and `WQBE` are WMI methods,
which is how a vendor exposes hardware data. These lines appear on that laptop
under any Linux distribution and are fixed only by a BIOS update from the
vendor. Nothing to do on our side.

More of the same appeared earlier in the very same boot, at 0.3-0.5 seconds,
while the kernel was loading the ACPI tables:

```
ACPI BIOS Error (bug): Could not resolve symbol [\_SB.PCI0.GPP2.BCM5], AE_NOT_FOUND
ACPI BIOS Error (bug): Could not resolve symbol [\_SB.PCI0.GPP1.DEV0], AE_NOT_FOUND
ACPI BIOS Error (bug): Could not resolve symbol [\_SB.WLBU._STA.WLVD], AE_NOT_FOUND
ACPI Error: Aborting method \_SB.WLBU._STA due to previous error (AE_NOT_FOUND)
```

The firmware's own tables reference objects those tables do not contain. The
only practical consequence worth checking is `\_SB.WLBU._STA`, which by its
name is the status method of a wireless button: if a hardware wireless toggle
misbehaves on such a machine, this is where it comes from.

One line in that block is not an error at all and only looks like one in
context:

```
virt/tdx: TDX not supported by the host platform
```

TDX is an Intel technology, and the `GPP1`/`GPP2` naming of the PCIe ports is
what AMD chipsets use. On an AMD machine that line is a statement of fact, and
it is printed on almost any machine.

Hiding all of it with `quiet loglevel=3` on the live entry was considered and
rejected: it would hide genuine kernel errors along with them, and archiso
shows boot messages deliberately.


## mkinitcpio changed its default hooks, and a silent sed hid it for weeks

The installer had always contained this line:

```bash
sed -i 's/^HOOKS=(base udev /HOOKS=(base udev plymouth /' /mnt/etc/mkinitcpio.conf
```

It stopped matching when mkinitcpio made the systemd-based hooks its default:

```
HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block filesystems fsck)
```

So `plymouth` was never added to the initramfs. Nobody noticed, because **a sed
that matches nothing says nothing**. The check we thought covered this - "the
theme is luna, /proc/cmdline has splash, plymouth-quit-wait is active" - was
looking at the wrong place entirely: none of it inspects HOOKS.

The two styles also want different names for the same jobs:

| job | udev style | systemd style |
|---|---|---|
| unlock LUKS | `encrypt` hook, `cryptdevice=` on the cmdline | `sd-encrypt` hook, a line in `/etc/crypttab` |
| resume | `resume` hook | nothing; systemd reads `resume=` itself |

The installer now reads the style out of the file, edits accordingly, and then
**verifies the result**, failing with a clear reason if a hook it expected is
missing. The verification is the part that matters: the edit was never the
fragile bit, the silence was.

## An installation that failed and said nothing

The disk came out with a complete system, a correct fstab, plymouth in the
hooks - and an **empty EFI partition**. The firmware had nothing to boot and
fell back to its device menu.

The cause was one line, the last one in `do_configure`:

```bash
[[ ${CFG[encrypt]} == yes ]] && runsh "chmod 600 /mnt/boot/initramfs-*.img"
}
```

On an unencrypted install the condition is false, so the `&&` list returns 1,
so **the function returns 1**, and `set -e` ends the installation right there -
before the bootloader step. No failure marker was written, because the exit did
not go through `run()`, so `main()` found nothing wrong and carried on.

Bash exempts the left-hand side of `&&` from errexit, which is why the pattern
is safe in the middle of a function and dangerous as the last statement: there
it decides the function's return value.

Two fixes, and the second matters more:

1. The line became a proper `if` block.
2. An `ERR` trap now records any failure that does not go through `run()`:

```bash
trap 'on_error $? $LINENO' ERR
```

Verified on a reduced copy of the exact bug: before, silence and a wrong
"complete"; after, `unexpected error at line 14 (exit 1)`.

An installer is allowed to fail. It is not allowed to fail quietly.

## The live image locked the user out of the installer

Installing takes ten to fifteen minutes and needs no keystrokes. `hypridle` on
the live image counts that as idleness: at five minutes it dims, at ten it runs
`hyprlock`. The live user has no password by design, and an empty one is not
accepted, so the screen could not be unlocked. The installation kept running
behind the lock, unreachable.

Giving the live user a password would be worse - it would have to be written
down somewhere public. An installation medium simply has no business locking
itself, so `hypridle.service` is masked in the ISO overlay. On an installed
system it works as before, where there is a real password.

## The live image now uses NetworkManager, like the installed system

archiso's releng profile brings up `iwd` and `systemd-networkd`. Our panel's
network module, shipped for the installed system, runs `nmtui` when clicked -
and NetworkManager was not running on the image. So the one moment a person
most needs it, "connect Wi-Fi before installing", answered with
"NetworkManager is not running".

The image was switched to NetworkManager: the same tool, the same click and the
same `nmtui` as on the installed system. `iwd` was dropped from the package
list, since nothing used it any more.

While there, `/etc/motd` turned out to be entirely Arch's - it told the reader
to install Arch Linux by following the Arch wiki, and to use `iwctl` for Wi-Fi.
Rewritten for Luna.

## The installer opens by itself on the live desktop

Booting the live image is almost always done in order to install, and nothing
on screen said how: the desktop appeared, and `sudo luna-install` had to be
known in advance. A user unit in the ISO overlay now opens the installer two
seconds after the panel is up.

Its own first screen is a welcome dialog with Continue and Quit, so anyone who
only wants to look around is one keypress away from a normal desktop. The unit
lives in the overlay, not in the package: an installed system must not open an
installer on every login.

This also meant the automated test had to stop typing `sudo luna-install`
itself - otherwise two installers run, which is the disaster described above.

## Laptop or desktop: waybar already decides for itself

A battery indicator on a desktop machine is nonsense. It turned out no work was
needed: waybar hides the battery module when there is no battery, and the proof
had been in front of us all along - QEMU has no battery, and no battery pill
ever appeared in any screenshot of the panel.

Where the distinction does matter is hibernation, because a swap file the size
of RAM is a real cost on a desktop with a lot of it. There the installer asks,
defaulting to Yes only where a battery exists. The detection uses two
independent signs: `/sys/class/power_supply/BAT*` and the chassis type from
`hostnamectl`.

For units that genuinely only make sense on a laptop, systemd has
`ConditionPathExistsGlob=/sys/class/power_supply/BAT*`, which is better than
any detection we could write.

## Build leftovers, and why the disk did not shrink

After a day of builds the WSL disk held 6.9 GB of mkarchiso work directory,
1.7 GB of package cache and a pile of debugging screenshots. The work directory
is wiped at the start of every build anyway, so between builds it was pure dead
weight. `build-iso.sh` now removes it at the end and trims the cache to one
version per package.

The part worth remembering: **freeing space inside the virtual disk does not
shrink the .vhdx file on the Windows side**. That needs a separate compaction,
with WSL stopped:

```
wsl --shutdown
wsl --manage LunaBuild --set-sparse true
```

## Deleting a lock file defeats flock

The two-installer disaster happened a second time, and again by our own hand:
the cleanup between test runs contained `rm -f /var/luna/auto-install.lock`.
`flock` holds a lock on an inode, not on a path. Removing the file leaves the
first process holding a lock on an inode nobody can reach any more, and the
second process creates a fresh file and locks that instead.

The lock file is not rubbish to be cleaned up. It is the lock.

## Hibernation: written correctly, not restored under QEMU

The swap file is created, the parameters are right, `systemctl hibernate`
powers the machine off in five seconds - and the next boot comes up fresh, at
the login screen, with the session gone. The kernel says:

```
[    1.383896] PM: Image not found (code -22)
```

Narrowing this down took several passes, and the order of the checks is the
useful part.

**Is it our encryption plumbing?** The same install without LUKS behaves the
same way. So no - and that ruled out the largest suspect in one step.

**Is zram stealing the image?** zram runs at swap priority 100 and the swap
file at -1, so it was a fair suspicion: an image written into compressed RAM
disappears with the power. Testing it was cheap: `swapoff /dev/zram0`, then
hibernate. Still no resume. Not zram.

**Is the offset wrong?** This is where it gets interesting. All three numbers
agree:

```
btrfs inspect-internal map-swapfile -r   140544
/sys/power/resume_offset                 140544
/sys/power/resume                        254:2      (that is /dev/vda2)
```

and reading the raw partition at that page lands exactly on the swap file's
header. So the kernel is told to look in precisely the right place.

**Is the image written at all?** Hibernate, let the machine power off, then read
the disk image from the host while nothing is running:

```
$ dd if=/dev/nbd0p2 bs=4096 skip=140544 count=1 | strings
SWAPSPACE2S1SUSPEND
```

`S1SUSPEND` is the hibernation signature. **The image is written correctly, at
exactly the offset the kernel is told to read from.**

So everything Luna configures is right, and what fails is the restore itself.
With encryption the machine resets the moment systemd reports "Starting Resume
from hibernation"; without it, the image is simply not picked up.

That is the honest state of it: **configured correctly, verified up to and
including the write, not restored under QEMU.** Whether it restores on real
hardware is untested from here, and the one machine that could answer that is
the laptop this is meant for.

Two things worth keeping from the method:

- Each step removed one suspect entirely rather than adjusting something and
  hoping. Encryption, then zram, then the offset, then the write.
- The decisive evidence came from outside the guest. Everything measured inside
  a running system is measured after the interesting moment has passed; reading
  the powered-off disk from the host is what showed that the write had been
  fine all along.

## The AUR, built and signed like everything else

yay and localsend are both things the system is expected to have, and neither
is in the Arch repositories. That is a circular problem in yay's case in
particular: the usual way to install something from the AUR is to use an AUR
helper, and the helper is the thing being installed.

So they are built here. `pkg/aur.txt` lists them, `build-pkgs.sh` clones each
one from the AUR, builds it with the same flags as our own packages and signs
it with the same key, and the result goes into the `[luna]` repository that the
installer uses. From the installed system they are ordinary signed packages
from a configured repository.

Two decisions inside that:

**They are declared as dependencies, not named in the installer.** `yay-bin` is
a dependency of `luna-cli`, `localsend-bin` of `luna-apps`. A package that says
what it needs is easier to reason about than an installer with a growing list
of package names in it, and it means removing `luna-apps` takes localsend with
it.

**The `-bin` variants, deliberately.** An AUR PKGBUILD is somebody else's code
and makepkg runs it; the `-bin` packages unpack a released binary instead of
building from source, which is a much smaller thing to be running. makepkg
checks the download against the sha256 sums in the PKGBUILD before it unpacks
anything.

The AUR step is the only part of the build that needs network access, so
`LUNA_SKIP_AUR=1` turns it off without touching the rest.

## A debug package took the place of yay

The first AUR build finished cleanly. The log said nine packages and nine
signatures. The repository listing looked right at a glance, and yay did not
exist.

What was in the repository was `yay-bin-debug-13.0.1-1-x86_64.pkg.tar.zst`:
eight kilobytes of debug symbols sitting where a 4.7 MiB AUR helper should have
been.

makepkg writes a separate `-debug` package next to the real one whenever the
build host has debug symbols switched on, so the build directory held two
packages. The code that moved a finished package into the repository was this:

```bash
built=$(find "$dir" -maxdepth 1 -name '*.pkg.tar.*' ! -name '*.sig' | head -n1)
```

"The first package file in the directory" - and `find` returns directory order,
which is not alphabetical and not anything else worth relying on. It happened
to hand back the debug package.

Nothing downstream could catch it. The signature was real, `repo-add` recorded
it, the count of signed packages matched the count of packages, and every check
that exists passed. The only symptom would have been `yay: command not found`
on an installed system, a week later.

The fix matches the package by name rather than by position, which is what the
cleanup line four lines below was already doing:

```bash
find "$dir" -maxdepth 1 -name "$name-[0-9]*.pkg.tar.*" ! -name '*.sig'
```

A version always starts with a digit, so `yay-bin-13.0.1` matches and
`yay-bin-debug-13.0.1` does not. The count is checked too: anything other than
exactly one match is now an error rather than a coin toss. Debug packages are
deleted from the repository before the database is built, since they are of no
use on the image.

The lesson is the one this project keeps relearning: a check that counts things
cannot see which things it counted.

## Night mode is a schedule, not a shortcut

hyprsunset was already installed and did nothing, because nothing started it.
It could have been put on a key, but a blue-light filter that has to be
remembered every evening is a feature only in the sense that it exists.

It runs as a service now, with the schedule in
`~/.config/hypr/hyprsunset.conf`: daylight from 07:00, 4000K from 21:00. On
start it applies whichever profile is current, so turning the machine on at
midnight already gets the warm screen. `Super+N` (`luna-night`) forces it on or
off in between.

Two details found by reading rather than guessing:

- The config keys were taken from the wiki after `strings` on the binary showed
  `profile`, `time`, `temperature` and `max-gamma` but no filename at all - the
  path is composed at runtime. Guessing a key name here fails silently, which
  is the same failure mode as everything else in this file.
- `gamma` is left alone. It can push perceived brightness below the monitor's
  own minimum, which is useful on a desktop screen, but it costs colour
  accuracy, and on a laptop `brightnessctl` already goes low enough.

hyprsunset works through the output's gamma table rather than a shader over the
screen, so the warm tint does not appear in screenshots or recordings. A shader
would tint them orange.

`luna-night` keeps its state in a file under `XDG_RUNTIME_DIR` because
hyprsunset has no toggle and no reliable way to be asked "are you warm right
now". That directory is wiped when the session ends, which is also when
hyprsunset restarts - so the mark and reality cannot drift apart across a
login.

## Two bindings on one key

`Super+L` locked the screen. `Super+L` also moved focus to the right, from the
vim-style `hjkl` block added later. Both bindings were live at once.

Which one Hyprland runs is not something worth depending on, and of the two,
the one that must not misfire is the lock. The vim `l` is gone; `h`, `j` and
`k` stay, and focus to the right is still on `Super+Right`, which was always
bound. The comment in `hyprland.lua` says why, so the gap does not look like an
oversight to the next person to read it.

Found by reading the file for something else entirely, which is the usual way.

## Two more checks, and one that nearly checked nothing

`lint-configs.sh` grew a check that every shell script Luna ships parses, and
one that every file named in a PKGBUILD `source=()` actually exists with a
matching number of `sha256sums`. The second one was written directly after
adding three files to a `source=()` array by hand.

Both were tested against deliberate breakage before being trusted - a missing
source file, a mismatched sum count - because a check that cannot fail is worse
than no check, it is a check that lies.

The script check in particular came close to being exactly that. It finds its
own inputs:

```bash
grep -rl '^#!.*bash' "$LUNA_SRC/pkg" "$LUNA_SRC/iso" "$LUNA_SRC/scripts"
```

If that had matched nothing, the loop would have run zero times, returned 0 and
printed OK for ever. It was run on its own to confirm it finds 22 scripts,
including the two written that evening.

## Bluetooth was installed and never started

`luna-desktop` pulled in bluez, bluez-utils and blueman. The panel had a
bluetooth button with a tooltip listing connected devices. `bluetoothd` was not
enabled anywhere, so on a freshly installed system none of it worked.

This is the same shape as hyprsunset, and it is worth naming the shape: adding
a package to a dependency list feels like adding a feature, and for a library
it is. For anything with a daemon it is half the job, and the missing half is
invisible until somebody tries to use it.

Enabling it unconditionally turned out to be safe, which was worth checking
rather than assuming, because a unit that fails on a desktop with no adapter
would show up in the panel's failed-services count for ever:

- `bluetooth.service` carries `ConditionPathIsDirectory=/sys/class/bluetooth`,
  so with no adapter it is skipped rather than failed.
- It is `WantedBy=bluetooth.target`, and that target is not part of any boot
  sequence. What pulls it in is systemd's own udev rule, in `99-systemd.rules`:
  `SUBSYSTEM=="bluetooth", TAG+="systemd", ENV{SYSTEMD_WANTS}+="bluetooth.target"`.

So a desktop with no Bluetooth starts nothing at all, and plugging a dongle in
starts the daemon by itself. Both facts were read out of the files in the image
being built rather than recalled.

The same audit found nothing else missing: paccache, reflector, fwupd-refresh,
the snapper timers, grub-btrfsd, systemd-oomd and timesyncd are all in
`90-luna.preset` already, and cups got its own preset when `luna-apps` was
added.

## is-enabled says disabled while the unit is running

While checking the tldr timer on the installed system:

```
$ systemctl --user is-enabled luna-tldr-update.timer
disabled
```

which looks like the feature simply did not work. It does work:

```
$ systemctl --user is-active luna-tldr-update.timer
active
$ systemctl --user list-timers --all
Sat 2026-09-26 00:14:23 UTC  6 days  ...  luna-tldr-update.timer
```

It had already run, two minutes after the first login, exactly as intended.

The explanation is that `is-enabled` reports on symlinks in `/etc/systemd`,
while Luna enables its user units with symlinks shipped in
`/usr/lib/systemd/user/<target>.wants/`. systemd honours those - it is how the
panel, the notifications and the wallpaper have always started - but
`is-enabled` does not count them as "enabled".

The control that proves this is waybar, which is unquestionably running:

```
$ systemctl --user is-enabled waybar.service
disabled
$ systemctl --user is-active waybar.service
active
```

So `is-enabled` is the wrong question to ask about anything Luna ships. Ask
`is-active`, or `list-timers` for a timer.

## A cheat sheet that said "Super+1  __lua 56"

`Super+/` opened, rofi came up, and every line of it was useless:

```
Super+1     __lua 56
Super+2     __lua 60
Print       __lua 34
```

The list is built from `hyprctl binds -j`, which was the right decision - a
cheat sheet kept by hand drifts the first time somebody edits a binding. But
Hyprland's Lua config registers each binding as a Lua callback, so the
dispatcher it reports is the literal string `__lua` and the argument is the
number of that callback. There is nothing there for a person to read.

Hyprland does keep a description per binding. Whether the Lua API accepted one
was settled by trying it on the running system rather than by reading around
it: append a binding with a description to `~/.config/hypr/hyprland.lua`,
`hyprctl reload`, and ask for it back.

```
$ hyprctl binds -j | jq -c '.[] | select(.key=="F9")'
{... "has_description":true, ... "description":"a test label",
 "dispatcher":"__lua","arg":"126"}
```

So every binding in `hyprland.lua` now carries a description, and `luna-keys`
prefers it, falling back to the dispatcher for anything without one - which is
what a legacy `hyprland.conf` would report, and is readable enough.

Two smaller things came out of that experiment:

- Hyprland reports a broken config in a banner across the top of the screen
  rather than by refusing to reload. The first attempt wrote `"SUPER x2b F9"`
  into the config, because `printf \x2b` without quotes prints `x2b`, and the
  banner said so precisely: `Unknown keysym "SUPER x2b F9", did you forget a +?`
- `vm-type.sh` could not type that line at all. It treated any argument
  containing a `+` as a key combination, so `"SUPER + F9"` became a keypress
  instead of text. It now recognises a combination by its leading modifier.
  Getting the text in took a detour through base32, whose alphabet, unlike
  base64's, has no `+` in it.

## The menu was painting itself with somebody else's colours

Opening the cheat sheet also showed what the launcher had been doing all along:
cream rows with dark text inside a dark purple window, with the highlighted row
a washed-out grey. `Super+R` and `Super+Tab` looked exactly the same, so this
was not new - it had simply never been looked at against the rest of the
theme.

`rofi-luna.rasi` styled `window`, `inputbar` and `element selected`, and said
nothing about ordinary rows. rofi fills the gap from its own built-in theme,
which is light. The `background-color: transparent` in the `*` block does not
help: a more specific default beats a general rule.

The fix is to name every state - `normal.normal`, `alternate.normal`,
`selected.*`, and the `active` ones the window switcher uses for the current
window - and to give `element-text` `text-color: inherit`, without which the
text keeps one colour and turns unreadable on the highlighted row.

The general point is that a theme which sets only the states it happens to
think of inherits the rest from somewhere, and "somewhere" is rarely the same
palette.

## The repository on the network, and two things that would have made it useless

Until now an installed Luna carried its own `[luna]` repository as a directory
on the disk, copied off the installation medium, with
`Server = file:///usr/share/luna/repo` in `pacman.conf`. `pacman -Syu` worked
and updated everything from the Arch mirrors, and Luna's own packages sat at
whatever version the image had been built with, for ever.

It is now served from GitHub Pages:

```
https://lun3ku.github.io/luna-linux/$arch
```

**Why Pages rather than Releases.** A release asset is the natural home for a
2 GiB image, and a poor home for a package repository: updating it means
uploading a dozen files, and without the GitHub CLI installed that is a dozen
drag-and-drops through a browser, every time. Pages is a plain static
directory, and updating it is a git push, which already works here. The
`repo` branch is rebuilt from scratch and force-pushed on every publish, so the
repository does not grow by 26 MiB of binaries per release, and `main` never
sees any of it.

Two things were found before anything was published, and either would have
been quietly fatal.

### The database is a symlink

`repo-add` leaves the repository looking like this:

```
luna.db -> luna.db.tar.gz
luna.files -> luna.files.tar.gz
```

which is invisible over `file://` and fatal over HTTP: **GitHub Pages does not
follow symlinks.** It serves the link itself, so pacman asking for `luna.db`
would have received fourteen bytes reading `luna.db.tar.gz` and reported a
corrupted database on every machine.

`publish-repo.sh` copies with `cp -L` and then refuses to publish if
`find -type l` finds anything at all. It also checks that the database
describes exactly the packages being published and that every one of them
carries a `%PGPSIG%`, because a database that lists a package which is not
there turns every `pacman -Syu` everywhere into a 404.

### Every package was version 0.1.0-1, for ever

This is the one that matters. All seven `luna-*` packages had `pkgver=0.1.0`
and `pkgrel=1` written into the PKGBUILD, and nothing ever changed them. A
rebuild produced a package with the same version and different contents
inside.

pacman compares versions. Publishing a repository full of packages whose
versions have not moved means every installed machine checks, finds nothing
newer, and does nothing. The network repository would have been decorative -
working perfectly, serving files correctly, and never updating anybody.

`pkgrel` is now derived, in `build-pkgs.sh`, from the number of commits that
have touched that package's directory:

```bash
rel=$(git -C "$LUNA_SRC" rev-list --count HEAD -- "pkg/$name")
sed -i "s/^pkgrel=.*/pkgrel=$rel/" "$BUILD/$name/PKGBUILD"
```

It only grows, and only when the package actually changed. It is set on the
copy that makepkg builds rather than in the PKGBUILD itself, because the copy
is not a git repository and the PKGBUILD cannot work it out for itself; the
committed PKGBUILD keeps `pkgrel=1` for anyone building one by hand.

The consequence worth remembering: **publish from committed state.** Two
builds from the same commit with different uncommitted edits share a version,
which is the same trap in a smaller form.

### What stays where

The copy of the repository on the installation medium stays: `pacstrap` reads
it during installation, so installing does not depend on the site being
reachable. It is no longer copied onto the disk - that copy could never change,
and offering pacman a second, permanently stale source is worse than offering
it none.

## Luna had no graphics drivers at all

Searching the whole repository for `nvidia`, `mesa`, `vulkan` or `amdgpu`
returned nothing. Not a decision anybody had made - a gap nobody had looked
for, and one that was invisible on the only machine Luna had ever been
installed on, because mesa arrives as a dependency of the Wayland stack and
Intel graphics need nothing else.

It stops being invisible on NVIDIA. Hyprland on nouveau is slow on older cards
and, on new ones, often does not start at all. The question only came up
because the next machine to be installed on has an NVIDIA card in it; had it
not, the first sign would have been a black screen after a fresh install.

### Choosing the driver from the card rather than from a guess

NVIDIA's own position, as the Hyprland wiki records it, is that the open
kernel modules are **required** from the 50xx series on, **recommended** for
Turing and Ampere, and **not supported at all** on anything older. So the
choice cannot be made once for everybody.

The only thing readable before the driver is loaded is the PCI device id, and
ids from Turing onwards start at `0x1e00`. Above that the installer picks
`nvidia-open-dkms`, below it `nvidia-dkms`. The DKMS variants rather than the
prebuilt ones, because the installer offers a choice of two kernels and the
matching headers are already installed for whichever one was picked.

### Reading sysfs, not lspci

The obvious way to find the card is `lspci`. It is also the wrong way here:
`pciutils` is not on the installation medium. A check that needs a package
nobody installed is a check that answers "no NVIDIA here" on every machine in
the world - it would never have failed loudly, it would simply never have
found anything.

So both helpers walk `/sys/bus/pci/devices/*` and read `vendor`, `class` and
`device` directly. They take the directory from a variable, which exists for
one reason: to point them at a tree of fabricated devices and check what they
say. Eight cases, including two that matter:

- **A hybrid laptop**, where the NVIDIA card appears as class `0x0302`, a 3D
  controller, rather than `0x0300`. Matching only VGA controllers would miss
  every laptop.
- **The vendor-id trap.** An NVIDIA card also exposes an HDMI audio function
  on the same PCI vendor id, `0x10de`. Checking the vendor alone would report
  a graphics card on a machine whose graphics card had been removed.

### Early KMS against hibernation

The wiki's instructions say to load the NVIDIA modules from the initramfs, and
then warn, in the same section, that doing so is known to stop resume from
hibernation working - the machine boots instead of resuming.

Luna offers hibernation in the installer. So the two cannot both be applied
blindly, and the installer no longer tries: early KMS is added unless
hibernation was chosen, and when it is skipped the log says why. A cosmetic
improvement loses to a feature the user asked for by name.

### Variables that must not be set on other machines

The wiki asks for `LIBVA_DRIVER_NAME=nvidia` and
`__GLX_VENDOR_LIBRARY_NAME=nvidia` in the Hyprland config. But `hyprland.lua`
ships to every machine through `/etc/skel`, and on an Intel one that first
variable points libva at a driver that is not installed and takes hardware
video decoding away.

The config therefore detects rather than assumes. `/sys/module/nvidia/version`
exists only while the proprietary driver is loaded, which is exactly the
condition those variables belong to - on nouveau they are wrong as well.

### What could not be tested, and the way round it

None of this can be verified here. QEMU has no NVIDIA card, so the screen
never appears, the packages are never installed and the modules are never
loaded. What was tested is everything that does not need the hardware: the
detection against fabricated devices, the `mkinitcpio` edit together with the
guard that catches it doing nothing, and that all five package names still
exist in the repositories.

The remaining risk is the first boot of the installation medium itself: if
nouveau cannot drive the card, there is no desktop and therefore no installer.
That turned out to have an answer already, and it was checked rather than
assumed:

```
Ctrl+Alt+F2  ->  luna login: root   (no password on the live medium)
                 # luna-install
```

greetd occupies tty1 only, systemd spawns a getty on any other console on
demand, and the live root account has an empty password - so the installer is
reachable from a text console even with the graphical session dead. Verified
on the built image, not deduced.
