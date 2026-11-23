#!/usr/bin/env python3
"""Checks the class colors stay apart for color-blind players (D-032).

Simulates protanopia, deuteranopia and tritanopia at full strength (Machado,
Oliveira and Fernandes 2009, applied in linear RGB) and measures every pair of
class colors with CIEDE2000. The build prompt asks for class colors that work
for color-blind players, always paired with a shape or icon; this checks the
colors, and the icons in tools/art/sprites.py carry the shapes.

    python3 tools/art/color_check.py
"""
from __future__ import annotations

import itertools
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import sprites  # noqa: E402

# Every pair of class colors must be at least this far apart (CIEDE2000) for
# normal vision and each simulated color-vision type. About 2 is a just
# noticeable difference; 15 reads as clearly different at a glance.
MIN_DISTANCE = 15.0

VISION = {
    "normal": None,
    "protanopia": [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]],
    "deuteranopia": [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]],
    "tritanopia": [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]],
}


def hex_rgb(color: str) -> list[float]:
    h = color.lstrip("#")
    return [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]


def _linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _encoded(c: float) -> float:
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def simulate(rgb: list[float], vision: str) -> list[float]:
    """The sRGB color as someone with this color vision sees it."""
    matrix = VISION[vision]
    if matrix is None:
        return list(rgb)
    lin = [_linear(c) for c in rgb]
    out = [sum(matrix[r][k] * lin[k] for k in range(3)) for r in range(3)]
    return [_encoded(min(1.0, max(0.0, c))) for c in out]


def lab(rgb: list[float]) -> tuple[float, float, float]:
    """sRGB (D65) to CIELAB."""
    r, g, b = (_linear(c) for c in rgb)
    x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
    y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
    z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883

    def f(t: float) -> float:
        return t ** (1 / 3) if t > 216 / 24389 else (24389 / 27 * t + 16) / 116

    fx, fy, fz = f(x), f(y), f(z)
    return 116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)


def ciede2000(lab1, lab2) -> float:
    """Sharma, Wu and Dalal's implementation notes (2005), with kL = kC = kH = 1."""
    l1, a1, b1 = lab1
    l2, a2, b2 = lab2
    c_bar = (math.hypot(a1, b1) + math.hypot(a2, b2)) / 2
    g = 0.5 * (1 - math.sqrt(c_bar ** 7 / (c_bar ** 7 + 25 ** 7)))
    a1p, a2p = (1 + g) * a1, (1 + g) * a2
    c1p, c2p = math.hypot(a1p, b1), math.hypot(a2p, b2)
    h1p = math.degrees(math.atan2(b1, a1p)) % 360 if c1p else 0.0
    h2p = math.degrees(math.atan2(b2, a2p)) % 360 if c2p else 0.0
    dl, dc = l2 - l1, c2p - c1p
    if c1p * c2p == 0:
        dh = 0.0
    else:
        dh = h2p - h1p
        if dh > 180:
            dh -= 360
        elif dh < -180:
            dh += 360
    dh_big = 2 * math.sqrt(c1p * c2p) * math.sin(math.radians(dh / 2))
    l_bar, cp_bar = (l1 + l2) / 2, (c1p + c2p) / 2
    if c1p * c2p == 0:
        h_bar = h1p + h2p
    elif abs(h1p - h2p) <= 180:
        h_bar = (h1p + h2p) / 2
    elif h1p + h2p < 360:
        h_bar = (h1p + h2p + 360) / 2
    else:
        h_bar = (h1p + h2p - 360) / 2
    t = (1 - 0.17 * math.cos(math.radians(h_bar - 30)) + 0.24 * math.cos(math.radians(2 * h_bar))
         + 0.32 * math.cos(math.radians(3 * h_bar + 6)) - 0.20 * math.cos(math.radians(4 * h_bar - 63)))
    d_theta = 30 * math.exp(-(((h_bar - 275) / 25) ** 2))
    r_c = 2 * math.sqrt(cp_bar ** 7 / (cp_bar ** 7 + 25 ** 7))
    s_l = 1 + 0.015 * (l_bar - 50) ** 2 / math.sqrt(20 + (l_bar - 50) ** 2)
    s_c = 1 + 0.045 * cp_bar
    s_h = 1 + 0.015 * cp_bar * t
    r_t = -math.sin(math.radians(2 * d_theta)) * r_c
    return math.sqrt((dl / s_l) ** 2 + (dc / s_c) ** 2 + (dh_big / s_h) ** 2 + r_t * (dc / s_c) * (dh_big / s_h))


def pairs(colors: dict[str, str]) -> list[tuple[float, str, str, str]]:
    """(distance, vision, a, b) for every pair under every vision, closest first."""
    out = []
    for vision in VISION:
        seen = {k: lab(simulate(hex_rgb(v), vision)) for k, v in colors.items()}
        for a, b in itertools.combinations(colors, 2):
            out.append((ciede2000(seen[a], seen[b]), vision, a, b))
    return sorted(out)


def class_colors() -> dict[str, str]:
    return {k: v["color"] for k, v in sprites.CLASSES.items()}


def main() -> int:
    closest = pairs(class_colors())
    for vision in VISION:
        rows = [p for p in closest if p[1] == vision][:3]
        print(f"{vision:13} closest: " + ", ".join(f"{a}/{b} {d:.1f}" for d, _v, a, b in rows))
    worst = closest[0]
    ok = worst[0] >= MIN_DISTANCE
    print(f"{'PASS' if ok else 'FAIL'}: closest pair {worst[2]}/{worst[3]} under {worst[1]} is "
          f"{worst[0]:.1f} apart (need {MIN_DISTANCE})")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
