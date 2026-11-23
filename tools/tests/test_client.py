"""The game client's text: every string key the code asks for is in the table."""
import json
import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CLIENT = REPO / "client"


def test_every_string_key_exists():
    table = json.loads((CLIENT / "strings" / "en.json").read_text(encoding="utf-8"))["strings"]
    used = set()
    for path in list((CLIENT / "game").glob("*.gd")) + list((CLIENT / "scenes").glob("*.gd")):
        used |= set(re.findall(r'\b(?:S|Strings)\.t\("([a-z0-9_.]+)"', path.read_text(encoding="utf-8")))
    used = {key for key in used if not key.endswith(".")}  # "tower." + id: test_tower_names_cover_the_config
    assert used, "no string keys found"
    assert sorted(used - set(table)) == []


def test_tower_names_cover_the_config():
    table = json.loads((CLIENT / "strings" / "en.json").read_text(encoding="utf-8"))["strings"]
    towers = json.loads((REPO / "config" / "balance" / "towers.json").read_text(encoding="utf-8"))["towers"]
    assert [t["id"] for t in towers if f"tower.{t['id']}" not in table] == []
