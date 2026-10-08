<h1 align="center">mangowc-caelestia</h1>

<div align="center">

![License](https://img.shields.io/github/license/caelestia-dots/shell?style=for-the-badge&labelColor=101418&color=9ccbfb)
![Quickshell](https://img.shields.io/badge/quickshell-0.3-64DBB5?style=for-the-badge&labelColor=101418)
![wlroots](https://img.shields.io/badge/wlroots-0.20-7B68EE?style=for-the-badge&labelColor=101418)

</div>

https://github.com/user-attachments/assets/0840f496-575c-4ca6-83a8-87bb01a85c5f

---

This repository is the **integration of two repositories by [Ackerman-00](https://github.com/Ackerman-00)** into one:

| Repository | What it is | Lives here in |
|------------|------------|---------------|
| [**caelestia-shell-mango**](https://github.com/Ackerman-00/caelestia-shell-mango) | The Caelestia desktop shell (Quickshell/QML + C++ plugin) ported to MangoWM | repository root |
| [**caelestia-cli-mango**](https://github.com/Ackerman-00/caelestia-cli-mango) | The `caelestia` CLI (colour schemes, wallpapers, screenshots, recording…) ported to MangoWM | `cli/` (`git subtree`) |

**All the work is Ackerman-00's**: the port of both projects to MangoWM, which in turn are forks of
[caelestia-dots/shell](https://github.com/caelestia-dots/shell) and [caelestia-dots/cli](https://github.com/caelestia-dots/cli).
The only purpose of this repository is to **make installation easier**: one clone, one `PKGBUILD` that builds and
installs shell and CLI together on Arch, and a ready-to-source MangoWC config fragment (`mango/caelestia.conf`).
On top of that it carries a few small fixes (see `git log`).

The original READMEs of both projects are kept in this repository:

- Shell: [`docs/upstream/caelestia-shell-mango.md`](docs/upstream/caelestia-shell-mango.md) (IPC reference, configuration, Fedora/CMake/Nix install)
- CLI: [`cli/README.md`](cli/README.md) (subcommands, `cli.json` configuration)

---

## Install

One script for the **Arch family** (Arch, CachyOS, EndeavourOS, Manjaro…) and the **Debian family**
(PikaOS, Debian sid…). It installs MangoWM, the shell, the CLI and every dependency, and wires the shell
into mango's config:

```sh
git clone https://github.com/Cglezf/mangowc-caelestia.git
cd mangowc-caelestia
./install.sh
```

Then log out and pick the **Mango** session. The shell starts on its own; `Super+A` opens the launcher and
every bind is listed in `~/.config/mango/caelestia.conf`.

| Option | Effect |
|--------|--------|
| `-y` | don't ask the package manager for confirmation |
| `--no-config` | install packages only, leave `~/.config/mango` alone |
| `--only-config` | only (re)install the mango config |
| `--uninstall` | remove what the script installed (the mango config stays) |

### What it does

**Arch family:** installs the AUR dependencies (`libcava app2unit python-materialyoucolor
ttf-material-symbols-variable ttf-rubik-vf`) with `paru`/`yay` (or plain `makepkg` if neither is there), then
builds `packaging/arch/PKGBUILD`: a split package, `mangowc-caelestia-shell` + `mangowc-caelestia-cli`, which
pulls `mangowm`, `quickshell` and the rest from the official repositories. The PKGBUILD builds the
**committed** state of the repository.

**Debian family:** requires `mangowm` (or `mangowc`) and `quickshell` ≥ 0.3.1 in apt, which is the case on
PikaOS. Everything else comes from apt, except what Debian does not package:

| Missing in apt | How the script gets it |
|----------------|------------------------|
| `libcava` (the `cava` package has no library) | builds [LukashonakV/cava](https://github.com/LukashonakV/cava) 1.0.0 into `/usr/local` |
| `app2unit` | [v1.4.4](https://github.com/Vladimir-csp/app2unit) into `/usr/local/bin` |
| `materialyoucolor` (CLI) | the CLI goes into a venv at `/opt/mangowc-caelestia/cli`, linked as `/usr/local/bin/caelestia` |
| Material Symbols Rounded, Rubik, CaskaydiaCove NF | downloaded into `/usr/local/share/fonts/mangowc-caelestia` |
| `dart-sass` | not installed: only the Discord theme of `caelestia scheme` needs it |

The shell is built with CMake and installed to the same paths as the Arch package
(`/etc/xdg/quickshell/caelestia`, `/usr/lib/caelestia`, Qt's QML dir), plus `/usr/local/bin/caelestia-shell`.
Every file installed outside apt is listed under `/usr/local/share/mangowc-caelestia` so `--uninstall` can remove it.

The script leaves your existing desktop alone. If something already provides `wl-copy`/`wl-paste` (PikaOS's
`otter-clip`), it uses that instead of `wl-clipboard`. It installs nothing from the Hyprland ecosystem, so the
`hyprpicker` bind in `caelestia.conf` only works if you install it yourself. If apt would still remove any
package, the script stops and lists them; with `-y` it aborts.

**Both:** copies `mango/caelestia.conf` to `~/.config/mango/` and adds `source-optional = ./caelestia.conf` at the
**top** of `config.conf` (created from `/etc/mango/config.conf` if missing). In mango the first matching `bind`
wins, so caelestia's binds take precedence over mango's defaults. Any file it changes is backed up as `*.bak`.

### Other distributions

Fedora has packages in Ackerman-00's COPR (`ackerman/nexus`), and both projects can be built by hand or with
Nix; see the original READMEs above.

## Dependencies

### Shell (caelestia-shell-mango)

Build:

| Dependency | Needed for |
|------------|-----------|
| `cmake` (≥ 3.19), `ninja` | build system |
| C++20 compiler (`gcc` or `clang`), `pkgconf` | build |
| Qt6 base + declarative, `qt6-wayland`, `qt6-shadertools` | Qt6 core, gui, qml, quick, network, dbus, sql, concurrent; Wayland; shaders |
| `libglvnd`, `wayland` | OpenGL loader, Wayland protocols |
| `libqalculate` | in-app calculator |
| `pipewire` | audio control |
| `aubio` | audio beat detection |
| `libcava`, `fftw` | audio visualiser |

Runtime:

| Package | Notes |
|---------|-------|
| `quickshell` (≥ 0.3.1) | the shell runtime |
| `mangowm` | compositor, with `mmsg` IPC |
| `caelestia-cli-mango` | colour schemes and wallpapers (in this repo: `cli/`) |
| `networkmanager` | network info |
| `lm_sensors` | hardware monitoring |
| `grim`, `swappy` | screenshots, window preview, screenshot editor |
| `wl-clipboard`, `cliphist` | clipboard and its history |
| `app2unit` | application launcher |
| `libnotify` | `notify-send` |
| `procps-ng`, `util-linux` | `pidof`, `lsblk` |
| `libxml2`, `xkeyboard-config`, `setxkbmap` | XKB layout parsing (`xmllint`) and switching |
| `systemd`, `polkit` | `loginctl`/`systemctl`, `pkexec` |
| `iproute2` | VPN/WireGuard status |
| `bash` | shell commands |
| Fonts: Material Symbols, Rubik, Caskaydia Cove Nerd Font | icons and UI text |

Optional: `ddcutil` (external monitors), `brightnessctl` (backlight), `asdbctl` (ASUS displays),
`gpu-screen-recorder` (recording), `fprintd` (fingerprint), `power-profiles-daemon`, `nvidia-smi`/`glxinfo`/`lspci`
(GPU name), `tailscale`/`netbird`/`warp-cli` (VPN status), `fish`.

### CLI (caelestia-cli-mango)

Python ≥ 3.13 with `pillow` and `materialyoucolor` (built with `hatchling`), plus:

| Package | Notes |
|---------|-------|
| `mmsg` (MangoWM) | compositor IPC |
| `libnotify`, `glib2` | sending (`notify-send`) and closing (`gdbus`) notifications |
| `grim`, `slurp`, `swappy` | screenshots, area selection, editor |
| `wl-clipboard`, `cliphist`, `fuzzel` | clipboard, its history, emoji/clipboard picker |
| `gpu-screen-recorder` | screen recording |
| `app2unit` | launching apps |
| `dart-sass` | Discord theme (`sass`) |
| `dconf` | GTK theme and colour scheme |
| `procps-ng` | `killall` to reload cava/btop/htop themes |
| `git` | version reporting |

## Updating from upstream

```sh
git remote add upstream https://github.com/Ackerman-00/caelestia-shell-mango.git   # once
git pull upstream main
git subtree pull --prefix=cli https://github.com/Ackerman-00/caelestia-cli-mango.git main
```

If the upstream READMEs change, refresh `docs/upstream/caelestia-shell-mango.md` (the subtree pull already updates `cli/README.md`).

---

<div align="center">
  <sub>Work by Ackerman-00, based on caelestia-dots. GPL-3.0. Not affiliated with the official Caelestia project.</sub>
</div>
