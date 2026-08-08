import json
import os
import shutil
import subprocess
from pathlib import Path

# Mango border/colour keys (mango_core.conf) mapped to Material palette keys.
MANGO_COLOR_KEYS = {
    "bordercolor": "outline",
    "focuscolor": "primary",
    "maximizescreencolor": "secondary",
    "urgentcolor": "error",
    "scratchpadcolor": "tertiary",
    "globalcolor": "onSurfaceVariant",
    "overlaycolor": "surfaceContainerHighest",
    "shadowscolor": "shadow",
}


def config_dir() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME", "~/.config")).expanduser() / "mango"


def apply_border_colours(colours: dict[str, str]) -> None:
    """Rewrite the colour keys in mango_core.conf from the generated palette and reload."""
    config = config_dir() / "mango_core.conf"
    if not config.is_file():
        return

    colours_hex = {k: f"0x{v}ff" for k, v in colours.items()}
    new_lines = []
    replaced = set()
    for line in config.read_text().splitlines():
        key = line.split("=", 1)[0].strip()
        if key in MANGO_COLOR_KEYS:
            palette_key = MANGO_COLOR_KEYS[key]
            new_lines.append(f"{key}={colours_hex[palette_key]}")
            replaced.add(key)
        else:
            new_lines.append(line)
    for key, palette_key in MANGO_COLOR_KEYS.items():
        if key not in replaced:
            new_lines.append(f"{key}={colours_hex[palette_key]}")

    if new_lines:
        config.write_text("\n".join(new_lines) + "\n")

    if available():
        subprocess.run(["mmsg", "dispatch", "reload_config"], stderr=subprocess.DEVNULL)


def available() -> bool:
    return shutil.which("mmsg") is not None


def _mmsg(args: list[str]) -> str:
    return subprocess.check_output(["mmsg", *args], text=True)


def _json(args: list[str]) -> dict[str, any] | None:
    try:
        return json.loads(_mmsg(args))
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        return None


def monitors() -> list[dict[str, any]]:
    data = _json(["get", "all-monitors"])
    return data.get("monitors", []) if data else []


def clients() -> list[dict[str, any]]:
    data = _json(["get", "all-clients"])
    return data.get("clients", []) if data else []


def focused_monitor() -> dict[str, any] | None:
    monitors_list = monitors()
    for monitor in monitors_list:
        if monitor.get("active"):
            return monitor
    return monitors_list[0] if monitors_list else None


def dispatch(dispatcher: str, *args: list[any]) -> bool:
    func = ",".join(part for part in (dispatcher, *map(str, args)) if part)
    data = _json(["dispatch", func])
    return bool(data.get("success")) if data else False
