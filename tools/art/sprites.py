#!/usr/bin/env python3
"""Placeholder sprites for Alien Empire TD, drawn in code as SVG (D-031).

Rules, so Godot's SVG importer draws them as the browser does (docs/ART.md):
plain shapes, linear and radial gradients and opacity only; no filters,
patterns, masks, images or text. One unit is a hundredth of a tile. Sprites are
centered on (0, 0) and face down the screen, toward the Core. Glow is baked in
as radial-gradient halos. A tower is a fixed base plus a head that turns."""
from __future__ import annotations

import math
from pathlib import Path

# --- Palette -----------------------------------------------------------------
# From the concept boards (client/ui/ui_kit.gd) and the build prompt's art direction.
# docs/ART.md lists what each color means; class colors are checked by
# tools/art/color_check.py (D-032).
GROUND = "#0b1626"
GROUND_2 = "#0e1b30"
PANEL = "#13213a"
PANEL_2 = "#1b2d4d"
TEXT = "#e8f1ff"
MUTED = "#9db0c8"
YOU = "#7cf3ff"        # cyan marks you
YOU_DEEP = "#1f9fc0"
CLAN = "#2ec4b6"       # teal: your clan
RIVAL = "#f5a524"      # amber: rivals
HIVE = "#ff4fd8"       # magenta: the AI and the hive
DANGER = "#ff5a5f"
SHELL = "#6b3fe6"      # every alien shares violet shells...
SHELL_LIGHT = "#9b7dff"
SHELL_DARK = "#35208a"
SHELL_DEEP = "#22145e"
EYE = "#ffe14d"        # ...glowing yellow eyes...
METAL = "#dbe7f5"      # your towers: white and cyan tech
METAL_2 = "#a9bdd6"
HEAT = "#ff8a3d"
ION = "#4aa8ff"

# A class-colored glow on each alien, always paired with its icon and its own
# silhouette, so color is never the only cue. Chosen to stay apart under
# protanopia, deuteranopia and tritanopia (D-032).
CLASSES = {
    "swarm":    {"color": "#a5ef58", "name": "Swarm"},
    "armored":  {"color": "#f04b12", "name": "Armored"},
    "shielded": {"color": "#1791c5", "name": "Shielded"},
    "air":      {"color": "#f6f3eb", "name": "Air"},
    "cloaked":  {"color": "#edbbfb", "name": "Cloaked"},
    "titan":    {"color": "#f08c8e", "name": "Titan"},
}


def f(v: float) -> str:
    return f"{v:.1f}".rstrip("0").rstrip(".")


def circle(x, y, r, fill="none", stroke=None, sw=0, op=1.0, extra=""):
    s = f' stroke="{stroke}" stroke-width="{f(sw)}"' if stroke else ""
    o = f' opacity="{op}"' if op != 1.0 else ""
    return f'<circle cx="{f(x)}" cy="{f(y)}" r="{f(r)}" fill="{fill}"{s}{o} {extra}/>'


def ellipse(x, y, rx, ry, fill="none", stroke=None, sw=0, op=1.0, rot=0.0):
    s = f' stroke="{stroke}" stroke-width="{f(sw)}"' if stroke else ""
    o = f' opacity="{op}"' if op != 1.0 else ""
    t = f' transform="rotate({f(rot)} {f(x)} {f(y)})"' if rot else ""
    return f'<ellipse cx="{f(x)}" cy="{f(y)}" rx="{f(rx)}" ry="{f(ry)}" fill="{fill}"{s}{o}{t}/>'


def path(d, fill="none", stroke=None, sw=0, op=1.0, extra=""):
    s = f' stroke="{stroke}" stroke-width="{f(sw)}" stroke-linecap="round" stroke-linejoin="round"' if stroke else ""
    o = f' opacity="{op}"' if op != 1.0 else ""
    return f'<path d="{d}" fill="{fill}"{s}{o} {extra}/>'


def poly(points, **kw):
    d = "M" + " L".join(f"{f(x)} {f(y)}" for x, y in points) + " Z"
    return path(d, **kw)


def hexagon(x, y, r, rot=0.0):
    return [(x + r * math.cos(math.radians(60 * i + rot)), y + r * math.sin(math.radians(60 * i + rot))) for i in range(6)]


# Gradients shared by every sprite (defined once in each document).
DEFS = f"""
<radialGradient id="shell" cx="40%" cy="30%" r="75%">
  <stop offset="0" stop-color="{SHELL_LIGHT}"/><stop offset="0.55" stop-color="{SHELL}"/><stop offset="1" stop-color="{SHELL_DARK}"/>
</radialGradient>
<radialGradient id="shellDark" cx="50%" cy="40%" r="70%">
  <stop offset="0" stop-color="{SHELL}"/><stop offset="1" stop-color="{SHELL_DEEP}"/>
</radialGradient>
<linearGradient id="metal" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#f4f9ff"/><stop offset="1" stop-color="{METAL_2}"/>
</linearGradient>
<radialGradient id="base" cx="50%" cy="40%" r="65%">
  <stop offset="0" stop-color="{PANEL_2}"/><stop offset="1" stop-color="#0d182c"/>
</radialGradient>
<radialGradient id="coreGlow" cx="50%" cy="50%" r="50%">
  <stop offset="0" stop-color="#ffffff"/><stop offset="0.35" stop-color="{YOU}"/><stop offset="1" stop-color="{YOU_DEEP}" stop-opacity="0"/>
</radialGradient>
<radialGradient id="eyeHalo"><stop offset="0" stop-color="{EYE}" stop-opacity="0.75"/><stop offset="1" stop-color="{EYE}" stop-opacity="0"/></radialGradient>
<radialGradient id="shadow"><stop offset="0" stop-color="#000000" stop-opacity="0.5"/><stop offset="1" stop-color="#000000" stop-opacity="0"/></radialGradient>
""" + "".join(
    f'<radialGradient id="halo-{k}"><stop offset="0" stop-color="{v["color"]}" stop-opacity="0.8"/>'
    f'<stop offset="1" stop-color="{v["color"]}" stop-opacity="0"/></radialGradient>' for k, v in CLASSES.items())


# --- Class icons (24 units across) -----------------------------------------------

def class_icon(kind: str, x=0.0, y=0.0, s=1.0) -> str:
    c = CLASSES[kind]["color"]
    sw = 2.6
    g = []
    if kind == "swarm":
        g += [circle(-5, 4, 3.6, fill=c), circle(5, 4, 3.6, fill=c), circle(0, -5, 3.6, fill=c)]
    elif kind == "armored":
        g += [poly(hexagon(0, 0, 10, 30), stroke=c, sw=sw), path("M-5 -2 L5 -2 M-5 3 L5 3", stroke=c, sw=sw)]
    elif kind == "shielded":
        g += [path("M0 -10 L9 -6 L8 3 Q5 9 0 11 Q-5 9 -8 3 L-9 -6 Z", stroke=c, sw=sw)]
    elif kind == "air":
        g += [path("M-10 4 L0 -6 L10 4", stroke=c, sw=sw), path("M-6 9 L0 3 L6 9", stroke=c, sw=sw)]
    elif kind == "cloaked":
        g += [path("M-10 0 Q0 -9 10 0 Q0 9 -10 0 Z", stroke=c, sw=sw), circle(0, 0, 2.8, fill=c), path("M-9 9 L9 -9", stroke=c, sw=sw)]
    elif kind == "titan":
        g += [path("M-10 7 L-10 -4 L-5 1 L0 -9 L5 1 L10 -4 L10 7 Z", stroke=c, sw=sw)]
    return f'<g transform="translate({f(x)} {f(y)}) scale({f(s)})">{"".join(g)}</g>'


# --- Aliens --------------------------------------------------------------------------
# Every alien: violet shell, glowing yellow eyes, glowing spots in its class color.

def eyes(points, r=3.0):
    halos = "".join(circle(x, y, r * 2.6, fill="url(#eyeHalo)") for x, y in points)
    return halos + "".join(circle(x, y, r, fill=EYE) + circle(x - r * 0.3, y - r * 0.3, r * 0.35, fill="#fffbe0") for x, y in points)


HALO_BY_COLOR = {v["color"]: f"url(#halo-{k})" for k, v in CLASSES.items()}


def spots(points, color, r=2.2):
    halo = HALO_BY_COLOR.get(color)
    halos = "".join(circle(x, y, r * 2.8, fill=halo) for x, y in points) if halo else ""
    return halos + "".join(circle(x, y, r, fill=color) for x, y in points)


def shadow(x, y, rx, ry):
    """A soft shadow under a unit; flyers cast theirs further away."""
    return ellipse(x, y, rx, ry, fill="url(#shadow)")


def legs(pairs, sw=3.2, color=SHELL_DEEP):
    return "".join(path(f"M{f(x0)} {f(y0)} L{f(x1)} {f(y1)} L{f(x2)} {f(y2)}", stroke=color, sw=sw) for (x0, y0), (x1, y1), (x2, y2) in pairs)


def mirror(pairs):
    out = []
    for p in pairs:
        out.append(p)
        out.append(tuple((-x, y) for x, y in p))
    return out


def swarmer() -> str:
    c = CLASSES["swarm"]["color"]
    g = [shadow(3, 4, 24, 26)]
    g.append(legs(mirror([((-9, -6), (-17, -10), (-21, -4)), ((-11, 1), (-19, 2), (-23, 8)), ((-9, 8), (-15, 13), (-17, 20))]), sw=3.4))
    g.append(ellipse(0, -1, 14, 17, fill="url(#shell)"))
    g.append(path("M0 -17 Q3 -6 0 6", stroke=SHELL_DARK, sw=1.6, op=0.8))
    g.append(ellipse(0, 13, 9, 6.5, fill="url(#shellDark)"))
    g.append(path("M-5 18 Q-3 23 -1 20 M5 18 Q3 23 1 20", stroke=SHELL_LIGHT, sw=1.6))
    g.append(spots([(-6, -7), (6, -5), (-3, 0)], c, 2.0))
    g.append(eyes([(-4, 14), (4, 14)], 2.6))
    return "".join(g)


def carapace_brute() -> str:
    c = CLASSES["armored"]["color"]
    g = [shadow(4, 6, 48, 50)]
    g.append(legs(mirror([((-24, -14), (-38, -18), (-42, -6)), ((-28, 6), (-42, 10), (-44, 22)), ((-20, 20), (-30, 30), (-30, 40))]), sw=6))
    g.append(path("M-30 -8 Q-34 -32 0 -36 Q34 -32 30 -8 Q34 18 18 28 Q0 34 -18 28 Q-34 18 -30 -8 Z", fill="url(#shellDark)"))
    for (x, y, r) in [(0, -16, 15), (-15, 4, 13), (15, 4, 13), (0, 14, 11)]:
        g.append(poly(hexagon(x, y, r, 30), fill="url(#shell)", stroke=SHELL_DEEP, sw=2.4))
        g.append(poly(hexagon(x, y - 1.5, r * 0.6, 30), fill=SHELL_LIGHT, op=0.35))
    g.append(spots([(-8, -6), (8, -6), (0, 4), (-21, 15), (21, 15)], c, 2.2))
    g.append(path("M-17 26 Q0 40 17 26 Q14 38 0 41 Q-14 38 -17 26 Z", fill=SHELL_DEEP))
    g.append(path("M-14 28 Q0 33 14 28", stroke=SHELL_LIGHT, sw=2.2))
    g.append(eyes([(-7, 33), (7, 33)], 2.4))
    return "".join(g)


def shield_drone() -> str:
    c = CLASSES["shielded"]["color"]
    g = [shadow(8, 12, 30, 30)]
    g.append(circle(0, 0, 29, fill=c, op=0.12))
    s6, cells = 6.0, []
    for row in range(-4, 5):
        for col in range(-4, 5):
            x, y = (col + (row % 2) * 0.5) * s6 * math.sqrt(3), row * s6 * 1.5
            if math.hypot(x, y) <= 29 - s6:
                cells.append("M" + " L".join(f"{f(px)} {f(py)}" for px, py in hexagon(x, y, s6 - 0.6, 30)) + " Z")
    g.append(path(" ".join(cells), stroke=c, sw=0.9, op=0.45))
    g.append(circle(0, 0, 29, stroke=c, sw=2.2, op=0.9))
    g.append(circle(0, 0, 25, stroke=c, sw=0.8, op=0.45))
    g.append(path("M-8 15 L-5 24 L-2 15 Z M8 15 L5 24 L2 15 Z", fill=c, op=0.8))
    g.append(circle(0, 0, 16, fill="url(#shell)"))
    g.append(path("M-16 2 Q0 9 16 2", stroke=SHELL_DEEP, sw=2.6))
    g.append(path("M-12 -9 Q0 -15 12 -9", stroke=SHELL_LIGHT, sw=1.6, op=0.7))
    g.append(spots([(-9, -4), (9, -4), (0, -10)], c, 1.9))
    g.append(eyes([(-5, 8), (5, 8)], 2.7))
    return "".join(g)


def skimmer() -> str:
    c = CLASSES["air"]["color"]
    g = [shadow(12, 26, 34, 16)]  # it flies, so its shadow falls further away
    g.append(path("M0 -14 Q-6 -24 -2 -36 M0 -14 Q6 -24 2 -36", stroke=SHELL_DEEP, sw=2.2))
    wing = "M0 -16 Q-14 -14 -34 -2 Q-26 4 -18 6 Q-10 8 -6 16 L0 20 L6 16 Q10 8 18 6 Q26 4 34 -2 Q14 -14 0 -16 Z"
    g.append(path(wing, fill="url(#shell)"))
    g.append(path("M-32 -2 Q-18 0 -8 10 M32 -2 Q18 0 8 10", stroke=SHELL_LIGHT, sw=1.6, op=0.8))
    g.append(ellipse(0, 2, 7, 13, fill="url(#shellDark)"))
    g.append(spots([(-22, -3), (-15, 0), (22, -3), (15, 0)], c, 1.8))
    g.append(eyes([(-3.5, 12), (3.5, 12)], 2.3))
    return "".join(g)


def phaser() -> str:
    c = CLASSES["cloaked"]["color"]
    g = [shadow(3, 4, 18, 28), '<g opacity="0.62">']
    g.append(legs(mirror([((-6, -10), (-14, -16), (-16, -24)), ((-6, -2), (-15, 0), (-18, 6))]), sw=2.2))
    g.append(path("M-6 6 L-14 14 L-8 24 M6 6 L14 14 L8 24", stroke=SHELL_LIGHT, sw=2.6))
    g.append(ellipse(0, -14, 7, 10, fill="url(#shell)"))
    g.append(ellipse(0, 0, 8, 9, fill="url(#shell)"))
    g.append(ellipse(0, 12, 6, 7, fill="url(#shellDark)"))
    g.append("</g>")
    g.append(path("M0 -25 Q10 -14 8 0 Q9 12 0 20 Q-9 12 -8 0 Q-10 -14 0 -25 Z", stroke=c, sw=1.6, extra='stroke-dasharray="3 3"'))
    g.append(spots([(-3, -14), (3, -8), (-2, 0)], c, 1.6))
    g.append(eyes([(-3, 14), (3, 14)], 2.2))
    return "".join(g)


def hive_carrier() -> str:
    c = CLASSES["titan"]["color"]
    g = [shadow(5, 8, 74, 76)]
    g.append(legs(mirror([((-36, -24), (-56, -32), (-62, -16)), ((-42, -2), (-62, 2), (-66, 18)), ((-38, 20), (-56, 30), (-58, 46)), ((-24, 36), (-34, 50), (-32, 62))]), sw=7))
    g.append(ellipse(0, -2, 48, 52, fill="url(#shellDark)"))
    g.append(ellipse(0, -8, 42, 42, fill="url(#shell)", op=0.9))
    for (x, y) in [(-16, -26), (16, -26), (-24, -2), (24, -2), (-10, 18), (10, 18)]:
        g.append(ellipse(x, y, 10.5, 12, fill=SHELL_DEEP))
        g.append(ellipse(x, y, 8, 9.5, fill="#2a1870"))
        g.append(circle(x - 2.4, y + 2, 1.3, fill=EYE) + circle(x + 2.4, y + 2, 1.3, fill=EYE))
    g.append(spots([(0, -40), (-34, -18), (34, -18), (0, 6), (-30, 22), (30, 22)], c, 3.0))
    g.append(path("M-26 38 Q0 64 26 38 Q22 60 0 66 Q-22 60 -26 38 Z", fill=SHELL_DEEP))
    g.append(path("M-22 42 Q0 52 22 42", stroke=SHELL_LIGHT, sw=2.6))
    g.append(path("M-40 46 Q0 84 40 46", stroke=CLASSES["shielded"]["color"], sw=2.4, op=0.55))
    g.append(eyes([(-10, 54), (10, 54)], 3.6))
    g.append(eyes([(-20, 48), (20, 48)], 2.2))
    return "".join(g)


ALIENS = [
    ("swarmer", "Swarmer", "swarm", swarmer, 0.85),
    ("carapace_brute", "Carapace Brute", "armored", carapace_brute, 1.0),
    ("shield_drone", "Shield Drone", "shielded", shield_drone, 0.9),
    ("skimmer", "Skimmer", "air", skimmer, 0.95),
    ("phaser", "Phaser", "cloaked", phaser, 0.95),
    ("hive_carrier", "Hive Carrier", "titan", hive_carrier, 1.0),
]


# --- Towers ----------------------------------------------------------------------------
# Your towers: white and cyan tech on a dark base with a cyan rim.

def tower_base(rim=YOU) -> str:
    pts = hexagon(0, 0, 40, 30)
    g = [poly(pts, fill="url(#base)", stroke=rim, sw=2.4)]
    g.append(poly(hexagon(0, 0, 33, 30), stroke="#2a4470", sw=1.6))
    for x, y in hexagon(0, 0, 36.5, 30)[::2]:
        g.append(circle(x, y, 1.8, fill=rim))
    return "".join(g)


def pulse_turret() -> str:
    g = []
    g.append(path("M-7 -8 L-7 -34 M7 -8 L7 -34", stroke=METAL_2, sw=6.5))
    g.append(path("M-7 -12 L-7 -33 M7 -12 L7 -33", stroke="url(#metal)", sw=4.5))
    g.append(circle(-7, -35, 3, fill=YOU) + circle(7, -35, 3, fill=YOU))
    g.append(circle(0, 0, 17, fill="url(#metal)", stroke=YOU, sw=2.2))
    g.append(circle(0, 0, 7, fill=YOU))
    g.append(circle(0, 0, 3.5, fill="#ffffff"))
    return "".join(g)


def plasma_torch() -> str:
    g = []
    for dx in (-21, 21):  # fuel tanks
        g.append(f'<rect x="{dx - 6}" y="-10" width="12" height="26" rx="6" fill="url(#metal)" stroke="{YOU}" stroke-width="1.8"/>')
        g.append(path(f"M{dx - 3} -4 L{dx + 3} -4 M{dx - 3} 2 L{dx + 3} 2", stroke=HEAT, sw=2))
    g.append(circle(0, 4, 17, fill="url(#metal)", stroke=YOU, sw=2.2))
    g.append(path("M-8 -8 L-13 -30 L13 -30 L8 -8 Z", fill="url(#metal)", stroke=YOU, sw=2))
    g.append(circle(0, -32, 13, fill="url(#halo-armored)"))
    g.append(ellipse(0, -30, 13, 4.2, fill=HEAT))
    g.append(ellipse(0, -30, 7, 2.2, fill="#fff1d6"))
    g.append(circle(0, 4, 6, fill=HEAT))
    g.append(circle(0, 4, 2.6, fill="#fff1d6"))
    return "".join(g)


def railgun() -> str:
    g = []
    g.append(path("M0 -8 L0 -62", stroke=METAL_2, sw=9))
    g.append(path("M0 -10 L0 -60", stroke="url(#metal)", sw=6))
    for y in (-26, -38, -50):
        g.append(ellipse(0, y, 8.5, 3, stroke=YOU, sw=2.4))
    g.append(circle(0, -63, 3.6, fill=YOU))
    g.append(path("M-14 -6 L14 -6 L18 12 L-18 12 Z", fill="url(#metal)", stroke=YOU, sw=2.2))
    g.append(path("M-10 4 L10 4", stroke=YOU, sw=2.4))
    return "".join(g)


def ion_disruptor() -> str:
    g = []
    g.append(circle(0, 0, 21, fill="url(#metal)", stroke=YOU, sw=2.2))
    g.append(circle(0, 0, 14, stroke=METAL_2, sw=2))
    g.append(circle(0, 0, 8, stroke=ION, sw=2.4))
    g.append(path("M0 -4 L0 -30", stroke=METAL_2, sw=3.4))
    g.append(circle(0, -31, 4, fill=ION))
    g.append(path("M-12 -38 Q0 -46 12 -38", stroke=ION, sw=2.4))
    g.append(path("M-18 -44 Q0 -55 18 -44", stroke=ION, sw=2, op=0.6))
    return "".join(g)


def flak_battery() -> str:
    g = []
    g.append(path("M-20 -18 L20 -18 L22 16 L-22 16 Z", fill="url(#metal)", stroke=YOU, sw=2.2))
    for x, y in [(-9, -7), (9, -7), (-9, 7), (9, 7)]:
        g.append(circle(x, y, 6.4, fill="#0d182c", stroke=METAL_2, sw=1.6))
        g.append(circle(x, y, 2.4, fill=YOU))
    g.append(path("M-20 -22 L20 -22", stroke=YOU, sw=2.4))
    return "".join(g)


def sensor_beacon() -> str:
    g = []
    g.append(path("M0 0 L-26 -38 Q0 -50 26 -38 Z", fill=YOU, op=0.16))
    g.append(circle(0, 0, 15, fill="url(#metal)", stroke=YOU, sw=2.2))
    g.append(path("M-12 -22 Q0 -30 12 -22", stroke=METAL, sw=3.2))
    g.append(path("M0 -4 L0 -24", stroke=METAL_2, sw=2.6))
    g.append(circle(0, 0, 5, fill=YOU))
    g.append(circle(0, -26, 3, fill="#ffffff"))
    return "".join(g)


def tower(head) -> str:
    """A whole tower for previews: the base with its head on top."""
    return tower_base() + head()


TOWERS = [
    ("pulse_turret", "Pulse Turret", pulse_turret),
    ("plasma_torch", "Plasma Torch", plasma_torch),
    ("railgun", "Railgun", railgun),
    ("ion_disruptor", "Ion Disruptor", ion_disruptor),
    ("flak_battery", "Flak Battery", flak_battery),
    ("sensor_beacon", "Sensor Beacon", sensor_beacon),
]


def core() -> str:
    """The colony's Core: a cyan reactor, two tiles wide."""
    g = [circle(0, 0, 92, fill="url(#coreGlow)", op=0.35)]
    g.append(poly(hexagon(0, 0, 74, 0), fill="url(#base)", stroke=YOU, sw=3))
    for i in range(8):
        a0, a1 = math.radians(i * 45 + 6), math.radians(i * 45 + 39)
        r = 56
        g.append(path(f"M{f(r*math.cos(a0))} {f(r*math.sin(a0))} A{r} {r} 0 0 1 {f(r*math.cos(a1))} {f(r*math.sin(a1))}", stroke=YOU, sw=6))
    g.append(circle(0, 0, 42, stroke=METAL_2, sw=2.4))
    g.append(poly(hexagon(0, 0, 28, 30), fill="url(#metal)", stroke=YOU, sw=2.6))
    g.append(poly(hexagon(0, 0, 15, 30), fill=YOU))
    g.append(circle(0, 0, 7, fill="#ffffff"))
    return "".join(g)


def doc(width, height, body, extra_defs=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">'
            f"<defs>{DEFS}{extra_defs}</defs>{body}</svg>")


def halo() -> str:
    """A white glow; the game tints it with a class color."""
    return ('<radialGradient id="glow"><stop offset="0" stop-color="#ffffff" stop-opacity="0.9"/>'
            '<stop offset="0.45" stop-color="#ffffff" stop-opacity="0.35"/>'
            '<stop offset="1" stop-color="#ffffff" stop-opacity="0"/></radialGradient>'
            + circle(0, 0, 50, fill="url(#glow)"))


def sprite_svg(drawing: str, size=100) -> str:
    """A standalone sprite, size units across, centered on (0, 0)."""
    h = size / 2
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{f(size)}" height="{f(size)}" '
            f'viewBox="{f(-h)} {f(-h)} {f(size)} {f(size)}"><defs>{DEFS}</defs>{drawing}</svg>\n')


def sprite_files() -> dict[str, str]:
    """Every sprite the game loads, by path under client/art/."""
    files = {}
    sizes = {"hive_carrier": 170}
    for key, _name, _kind, draw, _scale in ALIENS:
        files[f"aliens/{key}.svg"] = sprite_svg(draw(), sizes.get(key, 100))
    files["towers/base.svg"] = sprite_svg(tower_base(), 100)
    for key, _name, draw in TOWERS:
        files[f"towers/{key}.svg"] = sprite_svg(draw(), 140)
    files["core/core.svg"] = sprite_svg(core(), 200)
    for kind in CLASSES:
        files[f"icons/{kind}.svg"] = sprite_svg(class_icon(kind), 26)
    files["fx/halo.svg"] = sprite_svg(halo(), 100)
    return files
