"""PvE stages (config/balance/stages.json): the battle spec a stage and a seed
make, and the map geometry the config tool checks.

sim/core/stage.gd builds the same spec in the game; tools/gen_battles.py writes
sim/tests/generated/stage_specs.json from this module, and the GDScript tests
check stage.gd gives the same answer.
"""
from __future__ import annotations

import copy
import math

TILE_MT = 1000


def wave_scale_bp(growth_bp: int, wave_index: int) -> int:
    """The x growth^wave_index factor in basis points, truncated at each step,
    as both builders compute it: wave 1 is 10000."""
    scale = 10000
    for _ in range(wave_index):
        scale = scale * growth_bp // 10000
    return scale


def build_spec(stage: dict, seed: int, battle_id: str = "") -> dict:
    """The battle spec for one play of a stage: no jitter (Q3, D-033), no
    commands yet; the player's commands join as the battle runs."""
    waves = []
    for i, wave in enumerate(stage["waves"]):
        waves.append({
            "start_ms": wave["start_ms"],
            "hp_bp": wave_scale_bp(stage["hp_growth_bp"], i),
            "credits_bp": wave_scale_bp(stage["credit_growth_bp"], i),
            "groups": [{**copy.deepcopy(g), "jitter_ms": 0} for g in wave["groups"]],
        })
    return {
        "battle_id": battle_id or stage["id"],
        "mode": "pve",
        "seed": seed,
        "max_ms": stage["max_ms"],
        "lives": stage["lives"],
        "credits": stage["credits"],
        "towers": list(stage["towers"]),
        "map": {"lanes": copy.deepcopy(stage["lanes"]), "build_tiles": copy.deepcopy(stage["build_tiles"])},
        "waves": waves,
        "commands": [],
    }


def path_length(points) -> int:
    """As the sim measures it: the sum of each segment's floored square root."""
    return sum(math.isqrt((x1 - x0) ** 2 + (y1 - y0) ** 2) for (x0, y0), (x1, y1) in zip(points, points[1:]))


def tiles_on_path(points) -> set[tuple[int, int]]:
    """Every tile a path touches, counting both sides of a tile edge it runs along."""
    out: set[tuple[int, int]] = set()
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        steps = max(1, math.isqrt((x1 - x0) ** 2 + (y1 - y0) ** 2) // 50)
        for k in range(steps + 1):
            x = x0 + (x1 - x0) * k // steps
            y = y0 + (y1 - y0) * k // steps
            for cx in range((x - 1) // TILE_MT, (x + 1) // TILE_MT + 1):
                for cy in range((y - 1) // TILE_MT, (y + 1) // TILE_MT + 1):
                    out.add((cx, cy))
    return out


def check_stages(stages: list[dict], enemies: dict[str, dict], towers: set[str]) -> list[str]:
    """Rules a schema can't state (M1.md): lanes stay on the map, build tiles
    never sit on a lane or the Core, the air route is about 40% shorter, and the
    waves and layouts name things that exist."""
    errors: list[str] = []
    seen: set[str] = set()
    for stage in stages:
        sid = stage["id"]
        if sid in seen:
            errors.append(f"stages: duplicate id {sid}")
        seen.add(sid)
        w, h = stage["width"] * TILE_MT, stage["height"] * TILE_MT
        core = tuple(stage["core"])
        if not (0 <= core[0] < stage["width"] and 0 <= core[1] < stage["height"]):
            errors.append(f"stages: {sid} core {list(core)} is off the map")
        core_center = (core[0] * TILE_MT + TILE_MT // 2, core[1] * TILE_MT + TILE_MT // 2)
        lanes: dict[str, dict] = {}
        on_lane: set[tuple[int, int]] = set()
        for lane in stage["lanes"]:
            lid = lane["id"]
            if lid in lanes:
                errors.append(f"stages: {sid} lane {lid} is listed twice")
            lanes[lid] = lane
            for kind in ("ground", "air"):
                points = lane.get(kind)
                if not points:
                    continue
                if any(not (0 <= x <= w and 0 <= y <= h) for x, y in points):
                    errors.append(f"stages: {sid} lane {lid} {kind} route leaves the map")
                if any(a == b for a, b in zip(points, points[1:])):
                    errors.append(f"stages: {sid} lane {lid} {kind} route repeats a point")
                end = points[-1]
                if math.isqrt((end[0] - core_center[0]) ** 2 + (end[1] - core_center[1]) ** 2) > 3 * TILE_MT // 2:
                    errors.append(f"stages: {sid} lane {lid} {kind} route doesn't end at the Core")
                if points[0][1] != 0:
                    errors.append(f"stages: {sid} lane {lid} {kind} route doesn't start at the top edge")
            on_lane |= tiles_on_path(lane["ground"])
            if lane.get("air"):
                ground, air = path_length(lane["ground"]), path_length(lane["air"])
                if not 5500 <= air * 10000 // max(1, ground) <= 6500:
                    errors.append(f"stages: {sid} lane {lid} air route is {air} mt against {ground} on the ground; "
                                  "it should be 35% to 45% shorter")
        tiles = [tuple(t) for t in stage["build_tiles"]]
        if len(tiles) != len(set(tiles)):
            errors.append(f"stages: {sid} lists a build tile twice")
        for tile in tiles:
            if not (0 <= tile[0] < stage["width"] and 0 <= tile[1] < stage["height"]):
                errors.append(f"stages: {sid} build tile {list(tile)} is off the map")
            if tile in on_lane:
                errors.append(f"stages: {sid} build tile {list(tile)} is on a lane")
            if tile == core:
                errors.append(f"stages: {sid} build tile {list(tile)} is the Core")
        for tid in stage["towers"]:
            if tid not in towers:
                errors.append(f"stages: {sid} names unknown tower {tid}")
        starts = [wave["start_ms"] for wave in stage["waves"]]
        if starts != sorted(set(starts)):
            errors.append(f"stages: {sid} waves must start in order, each after the last")
        if stage["max_ms"] <= starts[-1]:
            errors.append(f"stages: {sid} max_ms ends the battle before its last wave")
        for wi, wave in enumerate(stage["waves"]):
            for gi, group in enumerate(wave["groups"]):
                where = f"stages: {sid} wave {wi + 1} group {gi + 1}"
                enemy = enemies.get(group["enemy"])
                lane = lanes.get(group["lane"])
                if enemy is None:
                    errors.append(f"{where}: unknown enemy {group['enemy']}")
                if lane is None:
                    errors.append(f"{where}: unknown lane {group['lane']}")
                if enemy and lane and enemy["movement"] == "air" and not lane.get("air"):
                    errors.append(f"{where}: air enemy {enemy['id']} needs an air route on lane {lane['id']}")
        used: set[tuple[int, int]] = set()
        for place in stage["reference_layout"]:
            tile = tuple(place["tile"])
            if place["tower"] not in stage["towers"]:
                errors.append(f"stages: {sid} reference layout uses {place['tower']}, which the stage doesn't allow")
            if tile not in tiles:
                errors.append(f"stages: {sid} reference layout uses {list(tile)}, which isn't a build tile")
            if tile in used:
                errors.append(f"stages: {sid} reference layout puts two towers on {list(tile)}")
            used.add(tile)
    return errors
