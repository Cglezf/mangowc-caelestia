import json
import shlex
from argparse import Namespace
from collections import ChainMap

from caelestia.utils import mango
from caelestia.utils.paths import user_config_path


def is_subset(superset, subset):
    for key, value in subset.items():
        if key not in superset:
            return False

        if isinstance(value, dict):
            if not is_subset(superset[key], value):
                return False

        elif isinstance(value, str):
            if value not in superset[key]:
                return False

        elif isinstance(value, list):
            if not set(value) <= set(superset[key]):
                return False
        elif isinstance(value, set):
            if not value <= superset[key]:
                return False

        else:
            if not value == superset[key]:
                return False

    return True


class DeepChainMap(ChainMap):
    def __getitem__(self, key):
        values = (mapping[key] for mapping in self.maps if key in mapping)
        try:
            first = next(values)
        except StopIteration:
            return self.__missing__(key)
        if isinstance(first, dict):
            return self.__class__(first, *values)
        return first

    def __repr__(self):
        return repr(dict(self))


class Command:
    args: Namespace
    cfg: dict[str, dict[str, dict[str, any]]] | DeepChainMap

    def __init__(self, args: Namespace) -> None:
        self.args = args

        self.cfg = {
            "communication": {
                "discord": {
                    "enable": True,
                    "match": [{"appid": "discord"}],
                    "command": ["discord"],
                },
                "whatsapp": {
                    "enable": True,
                    "match": [{"appid": "whatsapp"}],
                    "command": ["whatsapp"],
                },
            },
            "music": {
                "spotify": {
                    "enable": True,
                    "match": [{"appid": "Spotify"}, {"title": "Spotify"}, {"title": "Spotify Free"}],
                    "command": ["spicetify", "watch", "-s"],
                },
                "feishin": {
                    "enable": True,
                    "match": [{"appid": "feishin"}],
                    "command": ["feishin"],
                },
            },
            "sysmon": {
                "btop": {
                    "enable": True,
                    "match": [{"appid": "btop", "title": "btop"}],
                    "command": ["foot", "-a", "btop", "-T", "btop", "btop"],
                },
            },
            "todo": {
                "todoist": {
                    "enable": True,
                    "match": [{"appid": "Todoist"}],
                    "command": ["todoist"],
                },
            },
        }
        try:
            self.cfg = DeepChainMap(json.loads(user_config_path.read_text())["toggles"], self.cfg)
        except (FileNotFoundError, json.JSONDecodeError, KeyError):
            pass

    def run(self) -> None:
        if self.args.workspace == "specialws":
            self.specialws()
            return

        spawned = False
        if self.args.workspace in self.cfg:
            for client in self.cfg[self.args.workspace].values():
                if "enable" in client and client["enable"] and self.handle_client_config(client):
                    spawned = True

        if not spawned:
            mango.dispatch("toggle_scratchpad")

    def get_clients(self) -> list[dict[str, any]]:
        return mango.clients()

    def handle_client_config(self, client: dict[str, any]) -> bool:
        def selector(c: dict[str, any]) -> bool:
            # Each match is or, inside matches is and
            for match in client["match"]:
                if is_subset(c, match):
                    return True
            return False

        existing = next((c for c in self.get_clients() if selector(c)), None)
        if existing:
            return mango.dispatch("focusid", f"client,{existing['id']}")

        if "command" in client and client["command"]:
            first = client["match"][0]
            return mango.dispatch(
                "toggle_named_scratchpad", first.get("appid", ""), first.get("title", ""), shlex.join(client["command"])
            )
        return False

    def specialws(self) -> None:
        mango.dispatch("toggle_scratchpad")
