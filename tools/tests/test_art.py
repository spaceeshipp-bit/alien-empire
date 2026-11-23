"""The placeholder art (D-031, D-032): the sprites in client/art/ are current,
use only what Godot's SVG importer draws, import at the agreed scale, and the
class colors stay apart for color-blind players."""
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tools" / "art"))
import build_art  # noqa: E402
import color_check  # noqa: E402
import sprites  # noqa: E402

ART = REPO / "client" / "art"
SVG_NS = "{http://www.w3.org/2000/svg}"

# What the sprites may use: plain shapes, gradients and opacity. Godot rasterizes
# SVG with ThorVG at import time; filters, patterns, masks, clipping, images and
# text are left out so every sprite looks the same in the game as in a browser.
ALLOWED_TAGS = {"svg", "defs", "g", "path", "circle", "ellipse", "rect", "radialGradient", "linearGradient", "stop"}
ALLOWED_ATTRS = {
    "xmlns", "width", "height", "viewBox", "id", "d", "cx", "cy", "r", "rx", "ry", "x", "y", "x1", "y1", "x2", "y2",
    "fill", "stroke", "stroke-width", "stroke-linecap", "stroke-linejoin", "stroke-dasharray", "opacity",
    "transform", "offset", "stop-color", "stop-opacity",
}


def sprite_paths():
    return sorted(ART.rglob("*.svg"))


def test_client_art_is_current():
    assert build_art.problems() == []


def test_every_sprite_and_icon_is_generated():
    files = build_art.expected_files()
    for key, _name, _kind, _draw, _scale in sprites.ALIENS:
        assert f"aliens/{key}.svg" in files
    for key, _name, _draw in sprites.TOWERS:
        assert f"towers/{key}.svg" in files
    for kind in sprites.CLASSES:
        assert f"icons/{kind}.svg" in files


@pytest.mark.parametrize("path", sprite_paths(), ids=lambda p: p.relative_to(ART).as_posix())
def test_sprite_uses_only_what_godot_draws(path):
    root = ET.fromstring(path.read_text(encoding="utf-8"))
    ids = set()
    refs = set()
    for el in root.iter():
        tag = el.tag.replace(SVG_NS, "")
        assert tag in ALLOWED_TAGS, f"{tag} isn't drawn the same by Godot"
        for attr, value in el.attrib.items():
            assert attr in ALLOWED_ATTRS, f"{tag} has {attr}"
            refs.update(re.findall(r"url\(#([^)]+)\)", value))
        if "id" in el.attrib:
            assert el.attrib["id"] not in ids, f"duplicate id {el.attrib['id']}"
            ids.add(el.attrib["id"])
    assert refs <= ids, f"undefined references: {sorted(refs - ids)}"
    # Centered on (0, 0), as the game places sprites by their center.
    x, y, w, h = (float(v) for v in root.attrib["viewBox"].split())
    assert (x, y) == (-w / 2, -h / 2)
    assert (root.attrib["width"], root.attrib["height"]) == (sprites.f(w), sprites.f(h))


@pytest.mark.parametrize("path", sprite_paths(), ids=lambda p: p.relative_to(ART).as_posix())
def test_sprite_imports_at_the_agreed_scale(path):
    """Two texture pixels per unit (200 px a tile), three for the small icons,
    so sprites stay sharp on 1080-px-wide phones, where a tile is 120 px."""
    imp = path.with_name(path.name + ".import")
    assert imp.exists(), f"commit {imp.relative_to(REPO)} (import the client in Godot)"
    params = dict(line.split("=", 1) for line in imp.read_text(encoding="utf-8").splitlines() if "=" in line and not line.startswith("["))
    want = "3.0" if path.parent.name == "icons" else "2.0"
    assert params.get("svg/scale") == want
    assert params.get("mipmaps/generate") == "true"
    assert params.get("compress/mode") == "0"  # lossless


def test_palette_matches_the_ui_kit():
    """client/ui/ui_kit.gd predates the generated palette; their shared colors must agree."""
    kit = (REPO / "client" / "ui" / "ui_kit.gd").read_text(encoding="utf-8")
    kit_colors = dict(re.findall(r"const (\w+) := Color\([^)]*\)\s+# (#[0-9a-f]{6})", kit))
    same = {"GROUND": sprites.GROUND, "PANEL": sprites.PANEL, "TEXT": sprites.TEXT, "MUTED": sprites.MUTED,
            "CYAN": sprites.YOU, "TEAL": sprites.CLAN, "AMBER": sprites.RIVAL}
    for name, value in same.items():
        assert kit_colors[name] == value, name


def test_names_match_the_balance_config():
    """Each alien, tower and class in config/balance/ has its sprite, icon and color."""
    balance = REPO / "config" / "balance"
    enemies = json.loads((balance / "enemies.json").read_text(encoding="utf-8"))["enemies"]
    towers = json.loads((balance / "towers.json").read_text(encoding="utf-8"))["towers"]
    counters = json.loads((balance / "counters.json").read_text(encoding="utf-8"))["counters"]
    assert {(e["id"], e["class"]) for e in enemies} == {(key, kind) for key, _n, kind, _d, _s in sprites.ALIENS}
    assert {t["id"] for t in towers} == {key for key, _n, _d in sprites.TOWERS}
    for row in counters.values():
        assert set(row) == set(sprites.CLASSES)


def test_class_colors_stay_apart_for_color_blind_players():
    closest = color_check.pairs(color_check.class_colors())[0]
    assert closest[0] >= color_check.MIN_DISTANCE, closest


def test_color_difference_matches_published_values():
    # Sharma, Wu and Dalal (2005), table 1: pairs 1, 7, 17 and 25.
    cases = [((50.0, 2.6772, -79.7751), (50.0, 0.0, -82.7485), 2.0425),
             ((50.0, 0.0, 0.0), (50.0, -1.0, 2.0), 2.3669),
             ((50.0, 2.5, 0.0), (73.0, 25.0, -18.0), 27.1492),
             ((60.2574, -34.0099, 36.2677), (60.4626, -34.1751, 39.4387), 1.2644)]
    for a, b, want in cases:
        assert color_check.ciede2000(a, b) == pytest.approx(want, abs=1e-4)


def test_color_vision_simulation_keeps_greys_grey():
    for vision in color_check.VISION:
        out = color_check.simulate([0.5, 0.5, 0.5], vision)
        assert out == pytest.approx([0.5, 0.5, 0.5], abs=0.01), vision
