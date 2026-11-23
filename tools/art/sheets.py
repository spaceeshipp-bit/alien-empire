#!/usr/bin/env python3
"""The cast sheet: every placeholder sprite on one page, with the glow a
browser can add (docs/art/cast_sheet.png). Preview only; the game loads the
sprites from client/art/."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import sprites as c  # noqa: E402

GLOW_DEFS = """
<filter id="bloom" x="-50%" y="-50%" width="200%" height="200%">
  <feGaussianBlur in="SourceGraphic" stdDeviation="2.2" result="b"/>
  <feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>
</filter>
<filter id="aura" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="9"/></filter>
<filter id="softer" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="16"/></filter>
"""
FONT = "font-family=\"'Exo 2', Inter, sans-serif\""


def glowing_alien(drawing: str, kind: str, x: float, y: float, scale: float, aura_r=34) -> str:
    color = c.CLASSES[kind]["color"]
    return (f'<g transform="translate({c.f(x)} {c.f(y)}) scale({c.f(scale)})">'
            f'<circle r="{aura_r}" fill="{color}" opacity="0.42" filter="url(#aura)"/>'
            f'<g filter="url(#bloom)">{drawing}</g></g>')


def glowing_tower(drawing: str, x: float, y: float, scale: float) -> str:
    return (f'<g transform="translate({c.f(x)} {c.f(y)}) scale({c.f(scale)})">'
            f'<circle r="44" fill="{c.YOU}" opacity="0.16" filter="url(#aura)"/>'
            f'<g filter="url(#bloom)">{drawing}</g></g>')


def text(x, y, s, size=28, fill=c.TEXT, weight=700, anchor="middle", extra=""):
    return (f'<text x="{c.f(x)}" y="{c.f(y)}" {FONT} font-size="{size}" font-weight="{weight}" '
            f'fill="{fill}" text-anchor="{anchor}" {extra}>{s}</text>')


def card(x, y, w, h, stroke=c.PANEL_2):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="22" fill="{c.PANEL}" stroke="{stroke}" stroke-width="2"/>'


def cast_sheet() -> str:
    W, H = 1080, 2060
    b = [f'<rect width="{W}" height="{H}" fill="{c.GROUND}"/>']
    b.append(text(48, 74, "ALIEN EMPIRE TD", 40, c.YOU, 800, "start", 'letter-spacing="4"'))
    b.append(text(48, 112, "Placeholder art v1 · final art comes later · drawn in code", 24, c.MUTED, 500, "start"))
    # The hive: 3 x 2 cards
    b.append(text(48, 178, "THE HIVE", 26, c.HIVE, 800, "start", 'letter-spacing="3"'))
    cw, ch = 312, 300
    for i, (key, name, kind, draw, scale) in enumerate(c.ALIENS):
        col, row = i % 3, i // 3
        x, y = 48 + col * (cw + 24), 200 + row * (ch + 24)
        b.append(card(x, y, cw, ch))
        s = 2.05 * scale if key != "hive_carrier" else 1.22
        b.append(glowing_alien(draw(), kind, x + cw / 2, y + (128 if key != "hive_carrier" else 118), s, 36 if key != "hive_carrier" else 56))
        b.append(text(x + cw / 2, y + 252, name, 27, c.TEXT, 700))
        b.append(c.class_icon(kind, x + cw / 2 - 52, y + 278, 0.85))
        b.append(text(x + cw / 2 - 34, y + 286, c.CLASSES[kind]["name"].upper(), 18, c.CLASSES[kind]["color"], 700, "start", 'letter-spacing="2"'))
    # Your towers
    top = 200 + 2 * (ch + 24) + 24
    b.append(text(48, top, "YOUR TOWERS", 26, c.YOU, 800, "start", 'letter-spacing="3"'))
    th = 250
    for i, (key, name, draw) in enumerate(c.TOWERS):
        col, row = i % 3, i // 3
        x, y = 48 + col * (cw + 24), top + 22 + row * (th + 24)
        b.append(card(x, y, cw, th))
        b.append(glowing_tower(c.tower(draw), x + cw / 2, y + 118, 1.75))
        b.append(text(x + cw / 2, y + 226, name, 27, c.TEXT, 700))
    # The Core, class icons and palette
    y0 = top + 22 + 2 * (th + 24) + 10
    b.append(card(48, y0, 312, 250))
    b.append(f'<g transform="translate({48 + 156} {y0 + 112}) scale(1.1)"><g filter="url(#bloom)">{c.core()}</g></g>')
    b.append(text(48 + 156, y0 + 232, "The Core", 27, c.TEXT, 700))
    b.append(card(384, y0, 648, 250))
    b.append(text(408, y0 + 42, "CLASS ICONS AND COLORS", 20, c.MUTED, 700, "start", 'letter-spacing="2"'))
    for i, kind in enumerate(c.CLASSES):
        x = 432 + i * 100
        b.append(f'<circle cx="{x}" cy="{y0 + 98}" r="34" fill="{c.GROUND}" stroke="{c.CLASSES[kind]["color"]}" stroke-width="2.5"/>')
        b.append(c.class_icon(kind, x, y0 + 98, 1.6))
        b.append(text(x, y0 + 158, c.CLASSES[kind]["name"], 17, c.TEXT, 600))
    swatches = [("You", c.YOU), ("Clan", c.CLAN), ("Rivals", c.RIVAL), ("Hive", c.HIVE), ("Shell", c.SHELL), ("Eyes", c.EYE)]
    for i, (label, color) in enumerate(swatches):
        x = 408 + i * 104
        b.append(f'<rect x="{x}" y="{y0 + 184}" width="86" height="26" rx="8" fill="{color}"/>')
        b.append(text(x + 43, y0 + 236, label, 16, c.MUTED, 600))
    # At phone size: one tile is 120 px on a 1080-px-wide screen (80 px at the 720 base).
    y1 = y0 + 274
    b.append(card(48, y1, 984, 330))
    b.append(text(72, y1 + 42, "AT PHONE SIZE · ONE TILE = 120 PX ON A 1080-PX SCREEN", 20, c.MUTED, 700, "start", 'letter-spacing="2"'))
    gx, gy, t = 60, y1 + 62, 120
    grid = "".join(f'<rect x="{gx + i * t}" y="{gy + j * t}" width="{t}" height="{t}" fill="none" stroke="{c.PANEL_2}" stroke-width="1"/>'
                   for i in range(8) for j in range(2))
    b.append(f'<rect x="{gx}" y="{gy}" width="{8 * t}" height="{2 * t}" fill="{c.GROUND}"/>' + grid)
    by_key = {a[0]: a for a in c.ALIENS}
    placed = [("swarmer", 0.3, 0.35), ("swarmer", 0.7, 0.45), ("swarmer", 0.45, 0.75), ("carapace_brute", 1.5, 0.5),
              ("shield_drone", 2.5, 0.5), ("skimmer", 3.5, 0.45), ("phaser", 4.5, 0.5), ("hive_carrier", 6.0, 1.0)]
    for key, tx, ty in placed:
        _, _, kind, draw, scale = by_key[key]
        b.append(glowing_alien(draw(), kind, gx + tx * t, gy + ty * t, 1.2 * scale, 30))
    for i, (_, _, draw) in enumerate(c.TOWERS[:5]):
        b.append(glowing_tower(c.tower(draw), gx + (i + 0.5) * t, gy + 1.5 * t, 1.2))
    return c.doc(W, H, "".join(b), GLOW_DEFS)


SIZE = (1080, 2060)
