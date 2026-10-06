# caelestia-cli-mango

The main control script for the Caelestia shell, ported and adapted for **MangoWM**.

A fork of [`caelestia-dots/cli`](https://github.com/caelestia-dots/cli) with all Hyprland
coupling replaced by [MangoWM](https://mangowm.github.io/) equivalents (`mmsg` / `mango`).

## Changes from upstream

- `utils/hypr.py` → `utils/mango.py` — Mango bridge via `mmsg` (monitors, clients, dispatch)
- `record` — monitor/refresh-rate resolution via `mmsg get all-monitors` instead of `hyprctl monitors -j`
- `toggle` — special workspaces → Mango **named scratchpads** (`toggle_named_scratchpad`) and
  scratchpad focus (`focusid`); client matching uses `appid` instead of Hyprland `class`
- `random` wallpaper size filter — uses `mmsg get all-monitors`; skips undecodable/corrupt images
- Removed `resizer` (Hyprland socket event watcher) and the Hyprland theme applier (`enableHypr`)
- Fixed the `--version` git-describe noise against `~/.config/hypr`

<details><summary id="dependencies">External dependencies</summary>

-   [`mmsg`](https://github.com/mangowm/mango) (MangoWM) - compositor IPC
-   [`libnotify`](https://gitlab.gnome.org/GNOME/libnotify) - sending notifications
-   [`glib2`](https://gitlab.gnome.org/GNOME/glib) - `gdbus` closing notifications
-   [`swappy`](https://github.com/jtheoof/swappy) - screenshot editor
-   [`grim`](https://gitlab.freedesktop.org/emersion/grim) - taking screenshots
-   [`app2unit`](https://github.com/Vladimir-csp/app2unit) - launching apps
-   [`wl-clipboard`](https://github.com/bugaevc/wl-clipboard) - copying to clipboard
-   [`slurp`](https://github.com/emersion/slurp) - selecting an area
-   [`gpu-screen-recorder`](https://git.dec05eba.com/gpu-screen-recorder/about) - screen recording
-   [`cliphist`](https://github.com/sentriz/cliphist) - clipboard history
-   [`fuzzel`](https://codeberg.org/dnkl/fuzzel) - clipboard history/emoji picker
-   [`procps`](https://gitlab.com/procps-ng/procps) - `killall` theme reloads (cava/btop/htop)

</details>

## Installation

Requires Python ≥ 3.13.

```sh
git clone https://github.com/Ackerman-00/caelestia-cli-mango.git
cd caelestia-cli-mango
python -m pip install --user -e .
```

The `caelestia` binary is installed to `~/.local/bin`.

> **Need the shell too?** The `caelestia-shell-mango` desktop shell is a separate project — head over to [caelestia-shell-mango](https://github.com/Ackerman-00/caelestia-shell-mango) for install and configuration instructions.
>
> **MangoWM configuration?** The full dotfiles (keybinds, rules, monitor setup, `mango_core.conf`) live in [mango-config](https://github.com/Ackerman-00/mango-config.git) — head over there.

## Usage

All subcommands/options can be explored via the help flag.

```
$ caelestia -h
usage: caelestia [-h] [-v] COMMAND ...

subcommands:
    shell        start or message the shell
    toggle       toggle a scratchpad
    scheme       manage the colour scheme
    screenshot   take a screenshot
    record       start a screen recording
    clipboard    open clipboard history
    emoji        emoji/glyph utilities
    wallpaper    manage the wallpaper
```

## Configuring

All configuration options are in `~/.config/caelestia/cli.json`.

<details><summary>Example configuration</summary>

```json
{
    "record": {
        "extraArgs": [],
        "fps": 144
    },
    "wallpaper": {
        "postHook": "echo $WALLPAPER_PATH"
    },
    "theme": {
        "enableTerm": true,
        "enableDiscord": true,
        "enableSpicetify": true,
        "enableFuzzel": true,
        "enableBtop": true,
        "enableGtk": true,
        "enableQt": true,
        "enableMango": true
    },
    "toggles": {
        "communication": {
            "discord": {
                "enable": true,
                "match": [{ "appid": "discord" }],
                "command": ["discord"]
            },
            "whatsapp": {
                "enable": true,
                "match": [{ "appid": "whatsapp" }],
                "command": ["whatsapp"]
            }
        },
        "music": {
            "spotify": {
                "enable": true,
                "match": [{ "appid": "Spotify" }, { "title": "Spotify" }, { "title": "Spotify Free" }],
                "command": ["spicetify", "watch", "-s"]
            },
            "feishin": {
                "enable": true,
                "match": [{ "appid": "feishin" }],
                "command": ["feishin"]
            }
        },
        "sysmon": {
            "btop": {
                "enable": true,
                "match": [{ "appid": "btop", "title": "btop" }],
                "command": ["foot", "-a", "btop", "-T", "btop", "fish", "-C", "exec btop"]
            }
        },
        "todo": {
            "todoist": {
                "enable": true,
                "match": [{ "appid": "Todoist" }],
                "command": ["todoist"]
            }
        }
    }
}
```

</details>