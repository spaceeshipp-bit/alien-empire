"""Battles for checking the C++ sim core: conversion, generation and shrinking.

A Case is a battle in the units the core takes (ticks, config indices), built
either from a JSON battle spec and config bundle, the way sim/core/sim_config.gd
and battle_spec.gd read them, or by the seeded generator below. The same Case
feeds sim/native/tests/core_check.cpp (driver_lines) and the reference model
(tools/reference/sim_model.py).

The generator draws each case from (seed, index) alone, so any one case can be
rebuilt without the others: check_sim_native.py --fuzz-seed S --fuzz-case I.
"""
from __future__ import annotations

import dataclasses
import random
from dataclasses import dataclass

MAX_SEED = 2**53 - 1
MS_PER_TICK = 50
# The limits sim/core/battle_spec.gd and sim_config.gd enforce. Valid cases stay
# inside them; the core must accept every such battle.
MAX_COORD_MT = 1_000_000
MAX_BATTLE_MS = 3_600_000
MAX_GROUP_COUNT = 500
MAX_STAT = 1_000_000_000
# The core's own limits (sim/native/src/core/battle.cpp), past which it must refuse.
CORE_MAX_TICKS = 72_000
CORE_MAX_FIRST_TICK = 2 * CORE_MAX_TICKS
SEQ_MASK = (1 << 20) - 1


@dataclass(frozen=True)
class Enemy:
    hp_x100: int
    armor: int
    shield_x100: int
    speed_mtps: int
    air: bool
    leak_lives: int


@dataclass(frozen=True)
class Lane:
    ground: tuple[tuple[int, int], ...]
    air: tuple[tuple[int, int], ...] = ()  # empty: no air route


@dataclass(frozen=True)
class Group:
    enemy_index: int
    lane_index: int
    count: int
    first_tick: int
    interval_ticks: int
    jitter_ticks: int


@dataclass(frozen=True)
class Case:
    name: str
    config_hash: str
    config_version: int
    enemies: tuple[Enemy, ...]
    battle_id: str
    seed: int
    max_ticks: int
    lanes: tuple[Lane, ...]
    groups: tuple[Group, ...]
    # False for a case built to break one of the core's limits; the core must refuse it.
    valid: bool = True
    profile: str = "spec"
    broken: str = ""  # what an invalid case breaks

    def to_json(self) -> dict:
        return dataclasses.asdict(self)


def ticks(ms: int) -> int:
    return ms // MS_PER_TICK


def bundle_enemies(bundle: dict) -> list[dict]:
    """Enemy types in index order: sorted by id, as sim_config.gd indexes them."""
    return sorted(bundle["data"]["enemies"]["enemies"], key=lambda e: e["id"])


def case_from_spec(bundle: dict, spec: dict, name: str = "") -> Case:
    enemies = bundle_enemies(bundle)
    index = {e["id"]: i for i, e in enumerate(enemies)}
    lane_ids = [lane["id"] for lane in spec["map"]["lanes"]]
    groups = []
    for wave in spec["waves"]:
        start = ticks(wave["start_ms"])
        for g in wave["groups"]:
            groups.append(Group(
                index[g["enemy"]], lane_ids.index(g["lane"]), g["count"],
                start + ticks(g["offset_ms"]), ticks(g["interval_ms"]), ticks(g["jitter_ms"]),
            ))
    return Case(
        name=name or spec["battle_id"],
        config_hash=bundle["config_hash"],
        config_version=bundle["data"]["manifest"]["config_version"],
        enemies=tuple(
            Enemy(e["hp_x100"], e["armor"], e["shield_x100"], e["speed_mtps"], e["movement"] == "air", e["leak_lives"])
            for e in enemies
        ),
        battle_id=spec["battle_id"],
        seed=spec["seed"],
        max_ticks=ticks(spec["max_ms"]),
        lanes=tuple(
            Lane(tuple(tuple(p) for p in lane["ground"]), tuple(tuple(p) for p in lane.get("air", [])))
            for lane in spec["map"]["lanes"]
        ),
        groups=tuple(groups),
    )


def driver_lines(case: Case) -> list[str]:
    """The lines that load a case into core_check.cpp (then send battle_run)."""
    lines = ["battle_begin", f"config {case.config_hash} {case.config_version}"]
    for e in case.enemies:
        lines.append(f"enemy {e.hp_x100} {e.armor} {e.shield_x100} {e.speed_mtps} {int(e.air)} {e.leak_lives}")
    lines.append(f"spec {case.battle_id} {case.seed} {case.max_ticks}")
    for lane in case.lanes:
        parts = ["lane", str(len(lane.ground))]
        parts += [str(p[0]) for p in lane.ground] + [str(p[1]) for p in lane.ground]
        parts.append(str(len(lane.air)))
        parts += [str(p[0]) for p in lane.air] + [str(p[1]) for p in lane.air]
        lines.append(" ".join(parts))
    for g in case.groups:
        lines.append(f"group {g.enemy_index} {g.lane_index} {g.count} {g.first_tick} {g.interval_ticks} {g.jitter_ticks}")
    return lines


# ---------------------------------------------------------------------------
# Generation

# Profiles in a fixed cycle, so even a short run covers each kind.
PROFILE_CYCLE = (
    "typical", "typical", "random_config", "edges", "typical",
    "invalid", "random_config", "typical", "edges", "long",
)
SPECIAL_SEEDS = (0, 1, 2**31 - 1, 2**32 - 1, 2**32, 2**52, MAX_SEED)
SPECIAL_SPEEDS = (1, 2, 3, 7, 19, 20, 21, 39, 40, 41, 333, 999, 1000, 1001, 12_345, 1_000_000, MAX_STAT)


def _ms(rnd: random.Random, lo: int, hi: int) -> int:
    """A whole number of ticks' worth of ms in [lo, hi] (multiples of 50)."""
    return rnd.randint(lo // MS_PER_TICK, hi // MS_PER_TICK) * MS_PER_TICK


def _seed(rnd: random.Random) -> int:
    return rnd.choice(SPECIAL_SEEDS) if rnd.random() < 0.2 else rnd.randint(0, MAX_SEED)


def _walk(rnd: random.Random, points: int, span: int, start: tuple[int, int] | None = None) -> list[list[int]]:
    """A lane path that wanders, with the odd repeated or collinear point."""
    x, y = start if start else (rnd.randint(0, span), rnd.randint(0, span // 8))
    out = [[x, y]]
    while len(out) < points:
        roll = rnd.random()
        if roll < 0.08:
            out.append(list(out[-1]))  # repeated point: the path drops it
            continue
        if roll < 0.16 and len(out) >= 2:
            (x0, y0), (x1, y1) = out[-2], out[-1]
            nx, ny = x1 + (x1 - x0), y1 + (y1 - y0)  # collinear continuation
        else:
            nx = x + rnd.randint(-span // 4, span // 4)
            ny = y + rnd.randint(-span // 10, span // 3)
        nx = min(max(nx, 0), MAX_COORD_MT)
        ny = min(max(ny, 0), MAX_COORD_MT)
        x, y = nx, ny
        out.append([x, y])
    if all(p == out[0] for p in out):
        out[-1] = [min(out[0][0] + 1, MAX_COORD_MT) if out[0][0] < MAX_COORD_MT else out[0][0] - 1, out[0][1]]
    return out


def _random_bundle(rnd: random.Random) -> dict:
    enemies = []
    for i in range(rnd.randint(1, 6)):
        def stat(lo: int) -> int:
            return rnd.choice((lo, lo + 1, MAX_STAT, rnd.randint(lo, 10 ** rnd.randint(1, 9))))
        enemies.append({
            "id": f"e{i}",
            "hp_x100": stat(1),
            "armor": stat(0),
            "shield_x100": stat(0),
            "speed_mtps": rnd.choice(SPECIAL_SPEEDS) if rnd.random() < 0.5 else rnd.randint(1, 5000),
            "movement": "air" if rnd.random() < 0.3 else "ground",
            "leak_lives": stat(1),
        })
    return {
        "config_hash": "%064x" % rnd.getrandbits(256),
        "data": {"manifest": {"config_version": rnd.randint(1, MAX_STAT)}, "enemies": {"enemies": enemies}},
    }


def random_spec(rnd: random.Random, bundle: dict, profile: str, battle_id: str) -> dict:
    """A JSON battle spec that sim/core/battle_spec.gd accepts, using bundle's enemies."""
    enemies = bundle_enemies(bundle)
    edges = profile == "edges"
    long_run = profile == "long"
    span = rnd.choice((2_000, 20_000, 60_000)) if not long_run else rnd.choice((200_000, MAX_COORD_MT))
    lanes = []
    for i in range(rnd.randint(1, 3 if not edges else 4)):
        if edges and rnd.random() < 0.35:
            ground = rnd.choice((
                [[0, 0], [1, 0]],  # one thousandth of a tile long
                [[5, 5], [5, 5], [5, 5], [9, 5]],
                [[0, 0], [MAX_COORD_MT, MAX_COORD_MT]],
                [[0, MAX_COORD_MT], [MAX_COORD_MT, 0], [0, 0]],
                [[100, 100], [900, 100], [100, 100], [900, 100]],  # doubles back
                [[0, 0], [0, 0], [3, 4]],
            ))
        else:
            ground = _walk(rnd, rnd.randint(2, 7), span)
        lane = {"id": f"l{i}", "ground": ground}
        if rnd.random() < 0.5:
            lane["air"] = _walk(rnd, rnd.randint(2, 3), span, tuple(ground[0]))
        lanes.append(lane)
    if all(e["movement"] == "air" for e in enemies) and not any("air" in lane for lane in lanes):
        lanes[0]["air"] = _walk(rnd, 2, span, tuple(lanes[0]["ground"][0]))  # somewhere for them to fly
    air_lanes = [lane["id"] for lane in lanes if "air" in lane]
    usable = [e for e in enemies if e["movement"] != "air" or air_lanes]
    ground_lanes = [lane["id"] for lane in lanes]

    budget = 300 if not long_run else 20  # total aliens, to keep a case quick
    waves = []
    for _ in range(rnd.randint(1, 3)):
        groups = []
        for _ in range(rnd.randint(1, 3)):
            if budget <= 0 and groups:
                break
            enemy = rnd.choice(usable)
            lane = rnd.choice(air_lanes if enemy["movement"] == "air" else ground_lanes)
            count = rnd.randint(1, max(1, min(budget, 60 if not edges else MAX_GROUP_COUNT)))
            budget -= count
            if edges:
                interval = rnd.choice((0, 0, 50, _ms(rnd, 0, 3000)))
                jitter = rnd.choice((0, 50, _ms(rnd, 0, 2000), _ms(rnd, 0, 2000), _ms(rnd, 0, MAX_BATTLE_MS)))
            else:
                interval = _ms(rnd, 0, 2000)
                jitter = 0 if rnd.random() < 0.4 else _ms(rnd, 0, 1500)
            far = edges and rnd.random() < 0.2  # now and then, a group that may never arrive
            groups.append({
                "enemy": enemy["id"], "lane": lane, "count": count,
                "offset_ms": _ms(rnd, 0, MAX_BATTLE_MS if far else 5000),
                "interval_ms": interval, "jitter_ms": jitter,
            })
        late = edges and rnd.random() < 0.15
        waves.append({"start_ms": _ms(rnd, 0, MAX_BATTLE_MS if late else 60_000), "groups": groups})
    if long_run:
        max_ms = _ms(rnd, 600_000, MAX_BATTLE_MS)
    elif edges:
        max_ms = rnd.choice((50, 100, 4950, 5000, 5050, _ms(rnd, 50, 240_000)))
    else:
        max_ms = _ms(rnd, 2_000, 240_000)
    return {
        "battle_id": battle_id, "mode": "pve", "seed": _seed(rnd), "max_ms": max_ms,
        "map": {"lanes": lanes}, "waves": waves, "commands": [],
    }


def _break_one(rnd: random.Random, case: Case) -> Case:
    """Pushes exactly one value past the core's limits."""
    lanes = list(case.lanes)
    groups = list(case.groups)
    enemies = list(case.enemies)
    choice = rnd.randrange(13)
    if choice == 0:
        return dataclasses.replace(case, seed=rnd.choice((-1, MAX_SEED + 1)), broken="seed")
    if choice == 1:
        return dataclasses.replace(case, max_ticks=rnd.choice((0, -5, CORE_MAX_TICKS + 1)), broken="max_ticks")
    if choice == 2:
        i = rnd.randrange(len(enemies))
        stat, bad = rnd.choice((("hp_x100", 0), ("hp_x100", MAX_STAT + 1), ("armor", -1), ("shield_x100", -1),
                                ("speed_mtps", 0), ("speed_mtps", MAX_STAT + 1), ("leak_lives", 0)))
        enemies[i] = dataclasses.replace(enemies[i], **{stat: bad})
        return dataclasses.replace(case, enemies=tuple(enemies), broken=f"enemy {i} {stat}")
    if choice == 3:
        i = rnd.randrange(len(lanes))
        points = list(lanes[i].ground)
        j = rnd.randrange(len(points))
        points[j] = (rnd.choice((-1, MAX_COORD_MT + 1)), points[j][1])
        lanes[i] = dataclasses.replace(lanes[i], ground=tuple(points))
        return dataclasses.replace(case, lanes=tuple(lanes), broken=f"lane {i} coordinate")
    if choice == 4:
        i = rnd.randrange(len(lanes))
        lanes[i] = dataclasses.replace(lanes[i], ground=(lanes[i].ground[0],) * rnd.randint(1, 3))
        return dataclasses.replace(case, lanes=tuple(lanes), broken=f"lane {i} has one point")
    g = rnd.randrange(len(groups))
    if choice == 5:
        groups[g] = dataclasses.replace(groups[g], enemy_index=rnd.choice((-1, len(enemies))))
    elif choice == 6:
        groups[g] = dataclasses.replace(groups[g], lane_index=rnd.choice((-1, len(lanes))))
    elif choice == 7:
        groups[g] = dataclasses.replace(groups[g], count=rnd.choice((0, SEQ_MASK + 1)))
    elif choice == 8:
        groups[g] = dataclasses.replace(groups[g], first_tick=rnd.choice((-1, CORE_MAX_FIRST_TICK + 1)))
    elif choice == 9:
        groups[g] = dataclasses.replace(groups[g], interval_ticks=rnd.choice((-1, CORE_MAX_TICKS + 1)))
    elif choice == 10:
        groups[g] = dataclasses.replace(groups[g], jitter_ticks=rnd.choice((-1, CORE_MAX_TICKS + 1)))
    elif choice == 11:
        # An air alien on a lane with no air route.
        enemies.append(Enemy(100, 0, 0, 100, True, 1))
        lanes[groups[g].lane_index] = dataclasses.replace(lanes[groups[g].lane_index], air=())
        groups[g] = dataclasses.replace(groups[g], enemy_index=len(enemies) - 1)
        return dataclasses.replace(case, enemies=tuple(enemies), lanes=tuple(lanes), groups=tuple(groups),
                                   broken=f"group {g} air alien without an air route")
    else:
        # Every group within its own limit, but more spawns in total than the plan can number.
        half = SEQ_MASK // 2 + 1
        groups = [dataclasses.replace(groups[0], count=half), dataclasses.replace(groups[0], count=half)]
        return dataclasses.replace(case, groups=tuple(groups), broken="too many spawns in total")
    return dataclasses.replace(case, groups=tuple(groups), broken=f"group {g} field {choice}")


def random_case(seed: int, index: int, frozen_bundle: dict) -> Case:
    rnd = random.Random(f"aetd-sim-fuzz:{seed}:{index}")
    profile = PROFILE_CYCLE[index % len(PROFILE_CYCLE)]
    bundle = _random_bundle(rnd) if profile == "random_config" else frozen_bundle
    spec_profile = "typical" if profile in ("random_config", "invalid") else profile
    battle_id = f"fuzz-{seed}-{index}"
    case = case_from_spec(bundle, random_spec(rnd, bundle, spec_profile, battle_id), battle_id)
    case = dataclasses.replace(case, profile=profile)
    if profile == "invalid":
        case = dataclasses.replace(_break_one(rnd, case), valid=False)
    return case


# ---------------------------------------------------------------------------
# Shrinking


def _smaller(case: Case):
    """Candidate cases one step simpler than case, biggest cuts first. A shorter
    battle comes first: it makes every later candidate quicker to run."""
    for max_ticks in (1, case.max_ticks // 4, case.max_ticks // 2, case.max_ticks * 3 // 4):
        if 1 <= max_ticks < case.max_ticks:
            yield dataclasses.replace(case, max_ticks=max_ticks)
    groups = list(case.groups)
    for i in range(len(groups)):
        if len(groups) > 1:
            yield dataclasses.replace(case, groups=tuple(groups[:i] + groups[i + 1:]))
    for i, g in enumerate(groups):
        for change in (
            {"count": 1}, {"count": max(1, g.count // 4)}, {"count": max(1, g.count // 2)},
            {"jitter_ticks": 0}, {"interval_ticks": 0},
            {"first_tick": 0}, {"first_tick": g.first_tick // 2},
        ):
            smaller = dataclasses.replace(g, **change)
            if smaller != g:
                yield dataclasses.replace(case, groups=tuple(groups[:i] + [smaller] + groups[i + 1:]))
    lanes = list(case.lanes)
    for i, lane in enumerate(lanes):
        if lane.air and not any(g.lane_index == i and case.enemies[g.enemy_index].air for g in groups
                                if 0 <= g.enemy_index < len(case.enemies)):
            yield dataclasses.replace(case, lanes=tuple(lanes[:i] + [dataclasses.replace(lane, air=())] + lanes[i + 1:]))
        for j in range(1, len(lane.ground) - 1):
            ground = lane.ground[:j] + lane.ground[j + 1:]
            yield dataclasses.replace(case, lanes=tuple(lanes[:i] + [dataclasses.replace(lane, ground=ground)] + lanes[i + 1:]))
    if case.seed != 0:
        yield dataclasses.replace(case, seed=0)


def shrink(case: Case, still_fails, max_steps: int = 3000) -> Case:
    """The simplest case found, by greedy steps, for which still_fails(case) is true.
    still_fails must say no to a candidate the core would refuse: a smaller
    failure has to be a battle the core accepts, or it's a different failure."""
    steps = 0
    progress = True
    while progress and steps < max_steps:
        progress = False
        for candidate in _smaller(case):
            steps += 1
            if still_fails(candidate):
                case = candidate
                progress = True
                break
            if steps >= max_steps:
                break
    return case
