import json
import os
import subprocess
from argparse import Namespace
from pathlib import Path

from caelestia.utils.paths import c_cache_dir, user_config_path


class Command:
    args: Namespace

    def __init__(self, args: Namespace) -> None:
        self.args = args

    def instance_args(self) -> list[str]:
        # MangoWM launches the shell with `-p <path>` (no "caelestia" config name),
        # so allow the instance to be selected from cli.json / env when set.
        path = os.getenv("CAELESTIA_SHELL_DIR")
        if not path:
            try:
                config = json.loads(user_config_path.read_text())
                path = config.get("shell", {}).get("path", "")
            except (FileNotFoundError, json.JSONDecodeError):
                path = ""
        if path:
            return ["quickshell", "-p", path]

        detected = self.detect_instance_path()
        if detected:
            return ["quickshell", "-p", detected]

        # Fall back to the upstream (Hyprland) config-name convention.
        return ["qs", "-c", "caelestia"]

    # Directory names a caelestia shell config can live in: the quickshell config name
    # (/etc/xdg/quickshell/caelestia) and the Nix/COPR install dir (share/caelestia-shell).
    SHELL_DIR_NAMES = ("caelestia", "caelestia-shell")

    def detect_instance_path(self) -> str:
        # Only a caelestia instance counts: other quickshell instances (DMS, a greeter,
        # helper overlays) also show up in `quickshell list --all`.
        try:
            out = subprocess.check_output(["quickshell", "list", "--all"], text=True, stderr=subprocess.DEVNULL)
        except (subprocess.CalledProcessError, FileNotFoundError):
            return ""
        paths = [line.split("Config path:", 1)[1].strip() for line in out.splitlines() if "Config path:" in line]
        dirs = [Path(p).parent for p in paths]
        matches = [d for d in dirs if d.name in self.SHELL_DIR_NAMES]
        if not matches:
            return ""
        return str(matches[-1])

    def run(self) -> None:
        if self.args.show:
            # Print the ipc
            self.print_ipc()
        elif self.args.log:
            # Print the log
            self.print_log()
        elif self.args.kill:
            # Kill the shell
            self.shell("kill")
        elif self.args.message:
            # Send a message
            self.message(*self.args.message)
        else:
            # Start the shell
            args = self.instance_args() + ["-n"]
            if self.args.log_rules:
                args.extend(["--log-rules", self.args.log_rules])
            if self.args.daemon:
                args.append("-d")
                subprocess.run(args)
            else:
                shell = subprocess.Popen(args, stdout=subprocess.PIPE, universal_newlines=True)
                for line in shell.stdout:
                    if self.filter_log(line):
                        print(line, end="")

    def shell(self, *args: list[str]) -> str:
        return subprocess.check_output([*self.instance_args(), *args], text=True)

    def filter_log(self, line: str) -> bool:
        return f"Cannot open: file://{c_cache_dir}/imagecache/" not in line

    def print_ipc(self) -> None:
        print(self.shell("ipc", "show"), end="")

    def print_log(self) -> None:
        if self.args.log_rules:
            log = self.shell("log", "-r", self.args.log_rules)
        else:
            log = self.shell("log")
        # FIXME: remove when logging rules are added/warning is removed
        for line in log.splitlines():
            if self.filter_log(line):
                print(line)

    def message(self, *args: list[str]) -> None:
        print(self.shell("ipc", "call", *args), end="")
