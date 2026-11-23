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
CORE_MAX_MULT_BP = 100_000
CORE_MAX_SCALE_BP = 1_000_000
CORE_MAX_TILE = 999
CORE_MAX_LEVEL = 10
CORE_MAX_RELEASE = 100

CLASSES = ("swarm", "armored", "shielded", "air", "cloaked", "titan")
# Abilities sim version 2 runs (D-034). The towers' slow, reveal and mark arrive in M2.
SUPPORTED_TOWER_ABILITIES: frozenset[str] = frozenset()
SUPPORTED_ENEMY_ABILITIES = frozenset({"spawn_on_death"})
KINDS = {"place": 1, "upgrade": 2, "sell": 3}


@dataclass(frozen=True)
class Enemy:
    hp_x100: int
    armor: int
    shield_x100: int
    speed_mtps: int
    air: bool
    leak_lives: int
    class_index: int = 0
    kill_credits_x100: int = 0
    release_index: int = -1  # spawn_on_death: the alien it releases, or -1
    release_count: int = 0
    supported: bool = True


@dataclass(frozen=True)
class Tower:
    """A tower type with its config lookups resolved, as sim/core/battle.gd hands it over."""
    cost_credits: int
    damage_x100: int
    shots_per_s_x100: int
    range_mt: int
    splash_mt: int
    shield_mult_bp: int
    pierce_bp: int
    rating_bp: tuple[int, ...]  # one per class, in CLASSES order
    unrevealed_bp: int
    supported: bool = True


@dataclass(frozen=True)
class Upgrades:
    max_level: int = 4
    first_upgrade_cost_bp: int = 8000
    cost_growth_bp: int = 15000
    damage_growth_bp: int = 14500
    range_step_bp: int = 500
    sell_refund_bp: int = 7000


@dataclass(frozen=True)
class Rules:
    armor_constant: int = 100
    max_reduction_bp: int = 6000
    min_damage_x100: int = 100
    regen_per_second_x100: int = 1500
    regen_delay_ticks: int = 60
    retarget_ticks: int = 5


@dataclass(frozen=True)
class Command:
    tick: int
    kind: int  # 1 place, 2 upgrade, 3 sell
    tower_index: int  # place only; -1 otherwise
    col: int
    row: int


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
    hp_bp: int = 10000
    credits_bp: int = 10000


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
    towers: tuple[Tower, ...] = ()
    upgrades: Upgrades = Upgrades()
    rules: Rules = Rules()
    lives: int = 20
    credits: int = 0
    tower_set: tuple[int, ...] = ()
    build_tiles: tuple[tuple[int, int], ...] = ()
    commands: tuple[Command, ...] = ()
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


def bundle_towers(bundle: dict) -> list[dict]:
    """Tower types in index order: sorted by id, as sim_config.gd indexes them."""
    return sorted(bundle["data"]["towers"]["towers"], key=lambda t: t["id"])


def resolve_tower(bundle: dict, tower: dict) -> Tower:
    """A tower type with its counter ratings and shield multiplier looked up, the
    way sim/core/battle.gd resolves them for the core."""
    damage = bundle["data"]["damage"]
    row = bundle["data"]["counters"]["counters"].get(tower["id"], {})
    ratings = tuple(damage["counter_ratings_bp"][row[c]["rating"]] if c in row else 0 for c in CLASSES)
    return Tower(
        tower["cost_credits"], tower["damage_x100"], tower["shots_per_s_x100"], tower["range_mt"], tower["splash_mt"],
        damage["shield_multipliers_bp"].get(tower["damage_type"], 10000), tower["armor_pierce_bp"], ratings,
        row.get("cloaked", {}).get("unrevealed_damage_bp", 0),
        all(a["type"] in SUPPORTED_TOWER_ABILITIES for a in tower["abilities"]),
    )


def resolve_enemy(enemy: dict, index: dict[str, int]) -> Enemy:
    releases = [a for a in enemy["abilities"] if a["type"] == "spawn_on_death"]
    return Enemy(
        enemy["hp_x100"], enemy["armor"], enemy["shield_x100"], enemy["speed_mtps"], enemy["movement"] == "air",
        enemy["leak_lives"], CLASSES.index(enemy["class"]), enemy["kill_credits_x100"],
        index[releases[0]["enemy"]] if releases else -1, releases[0]["count"] if releases else 0,
        all(a["type"] in SUPPORTED_ENEMY_ABILITIES for a in enemy["abilities"]),
    )


def bundle_rules(bundle: dict) -> tuple[Upgrades, Rules]:
    data = bundle["data"]
    fu = data["towers"]["field_upgrades"]
    damage = data["damage"]
    regen = data["status_effects"]["shield_regen"]
    return (
        Upgrades(fu["max_level"], fu["first_upgrade_cost_bp"], fu["cost_growth_bp"], fu["damage_growth_bp"],
                 fu["range_step_bp"], fu["sell_refund_bp"]),
        Rules(damage["armor_constant"], damage["max_reduction_bp"], damage["min_damage_x100"],
              regen["per_second_x100"], ticks(regen["delay_ms"]), ticks(data["towers"]["retarget_ms"])),
    )


def case_from_spec(bundle: dict, spec: dict, name: str = "") -> Case:
    enemies = bundle_enemies(bundle)
    index = {e["id"]: i for i, e in enumerate(enemies)}
    towers = bundle_towers(bundle)
    tower_index = {t["id"]: i for i, t in enumerate(towers)}
    lane_ids = [lane["id"] for lane in spec["map"]["lanes"]]
    groups = []
    for wave in spec["waves"]:
        start = ticks(wave["start_ms"])
        for g in wave["groups"]:
            groups.append(Group(
                index[g["enemy"]], lane_ids.index(g["lane"]), g["count"],
                start + ticks(g["offset_ms"]), ticks(g["interval_ms"]), ticks(g["jitter_ms"]),
                wave["hp_bp"], wave["credits_bp"],
            ))
    commands = []
    for c in spec["commands"]:
        kind = KINDS[c["type"]]
        col, row = c["args"]["tile"]
        commands.append(Command(c["tick"], kind, tower_index[c["args"]["tower"]] if kind == 1 else -1, col, row))
    upgrades, rules = bundle_rules(bundle)
    return Case(
        name=name or spec["battle_id"],
        config_hash=bundle["config_hash"],
        config_version=bundle["data"]["manifest"]["config_version"],
        enemies=tuple(resolve_enemy(e, index) for e in enemies),
        battle_id=spec["battle_id"],
        seed=spec["seed"],
        max_ticks=ticks(spec["max_ms"]),
        lanes=tuple(
            Lane(tuple(tuple(p) for p in lane["ground"]), tuple(tuple(p) for p in lane.get("air", [])))
            for lane in spec["map"]["lanes"]
        ),
        groups=tuple(groups),
        towers=tuple(resolve_tower(bundle, t) for t in towers),
        upgrades=upgrades,
        rules=rules,
        lives=spec["lives"],
        credits=spec["credits"],
        tower_set=tuple(tower_index[t] for t in spec["towers"]),
        build_tiles=tuple(tuple(t) for t in spec["map"]["build_tiles"]),
        commands=tuple(commands),
    )


def driver_lines(case: Case) -> list[str]:
    """The lines that load a case into core_check.cpp (then send battle_run)."""
    lines = ["battle_begin", f"config {case.config_hash} {case.config_version}"]
    for e in case.enemies:
        lines.append(f"enemy {e.hp_x100} {e.armor} {e.shield_x100} {e.speed_mtps} {int(e.air)} {e.leak_lives} "
                     f"{e.class_index} {e.kill_credits_x100} {e.release_index} {e.release_count} {int(e.supported)}")
    for t in case.towers:
        lines.append(" ".join(str(v) for v in (
            "tower", t.cost_credits, t.damage_x100, t.shots_per_s_x100, t.range_mt, t.splash_mt, t.shield_mult_bp,
            t.pierce_bp, *t.rating_bp, t.unrevealed_bp, int(t.supported))))
    u, r = case.upgrades, case.rules
    lines.append(f"upgrades {u.max_level} {u.first_upgrade_cost_bp} {u.cost_growth_bp} {u.damage_growth_bp} "
                 f"{u.range_step_bp} {u.sell_refund_bp}")
    lines.append(f"damage {r.armor_constant} {r.max_reduction_bp} {r.min_damage_x100}")
    lines.append(f"timing {r.regen_per_second_x100} {r.regen_delay_ticks} {r.retarget_ticks}")
    lines.append(f"spec {case.battle_id} {case.seed} {case.max_ticks} {case.lives} {case.credits}")
    lines.append(" ".join(["towerset", str(len(case.tower_set)), *(str(i) for i in case.tower_set)]))
    for col, row in case.build_tiles:
        lines.append(f"tile {col} {row}")
    for lane in case.lanes:
        parts = ["lane", str(len(lane.ground))]
        parts += [str(p[0]) for p in lane.ground] + [str(p[1]) for p in lane.ground]
        parts.append(str(len(lane.air)))
        parts += [str(p[0]) for p in lane.air] + [str(p[1]) for p in lane.air]
        lines.append(" ".join(parts))
    for g in case.groups:
        lines.append(f"group {g.enemy_index} {g.lane_index} {g.count} {g.first_tick} {g.interval_ticks} {g.jitter_ticks} "
                     f"{g.hp_bp} {g.credits_bp}")
    for c in case.commands:
        lines.append(f"command {c.tick} {c.kind} {c.tower_index} {c.col} {c.row}")
    return lines


# ---------------------------------------------------------------------------
# Generation

# Profiles in a fixed cycle, so even a short run covers each kind.
PROFILE_CYCLE = (
    "combat", "typical", "random_config", "edges", "combat",
    "invalid", "random_config", "combat", "edges", "long",
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
    """A config the loaders would accept, with values anywhere in their ranges."""
    def stat(lo: int) -> int:
        return rnd.choice((lo, lo + 1, MAX_STAT, rnd.randint(lo, 10 ** rnd.randint(1, 9))))

    def bp(lo: int, hi: int) -> int:
        return rnd.choice((lo, hi, rnd.randint(lo, hi), rnd.randint(lo, min(hi, 20000))))

    enemies = []
    for i in range(rnd.randint(1, 6)):
        movement = "air" if rnd.random() < 0.3 else "ground"
        enemies.append({
            "id": f"e{i}",
            "class": "air" if movement == "air" else rnd.choice([c for c in CLASSES if c != "air"]),
            "hp_x100": rnd.choice((stat(1), rnd.randint(1000, 50_000))),
            # Armor past what the cap allows is common, so the cap is tested.
            "armor": rnd.choice((0, 50, 150, 300, 1000, 20_000, stat(0))),
            "shield_x100": stat(0) if rnd.random() < 0.6 else 0,
            "speed_mtps": rnd.choice(SPECIAL_SPEEDS) if rnd.random() < 0.5 else rnd.randint(1, 5000),
            "movement": movement,
            "leak_lives": stat(1),
            "kill_credits_x100": stat(0),
            "abilities": [],
        })
    for e in enemies:  # now and then, one releases a same-moving alien with a lower index
        same = [o for o in enemies[:enemies.index(e)] if o["movement"] == e["movement"]]
        if same and rnd.random() < 0.3:
            e["abilities"].append({"type": "spawn_on_death", "enemy": rnd.choice(same)["id"],
                                   "count": rnd.choice((1, 2, 6, CORE_MAX_RELEASE))})
    damage_types = ("standard", "emp", "thermal")
    towers, counters = [], {}
    for i in range(rnd.randint(0, 4)):
        tid = f"t{i}"
        towers.append({
            "id": tid,
            "cost_credits": stat(1),
            "damage_x100": stat(0),
            "shots_per_s_x100": rnd.choice((0, 1, 50, 200, 200, 800, 2000, 2001, rnd.randint(1, 5000))),
            "range_mt": rnd.choice((0, 1, 1000, 3000, rnd.randint(0, 20000), MAX_STAT)),
            "splash_mt": rnd.choice((0, 0, 1, 1000, rnd.randint(0, 5000))),
            "damage_type": rnd.choice(damage_types),
            "armor_pierce_bp": rnd.choice((0, 7500, 10000, rnd.randint(0, 10000))),
            "abilities": [{"type": "slow", "slow_bp": 2000}] if rnd.random() < 0.15 else [],
        })
        counters[tid] = {c: {"rating": rnd.choice(("strong", "neutral", "weak", "cant_hit"))} for c in CLASSES}
        counters[tid]["cloaked"]["unrevealed_damage_bp"] = rnd.choice((0, 5000, 10000, bp(0, CORE_MAX_MULT_BP)))
    return {
        "config_hash": "%064x" % rnd.getrandbits(256),
        "data": {
            "manifest": {"config_version": rnd.randint(1, MAX_STAT)},
            "enemies": {"enemies": enemies},
            "towers": {
                "towers": towers,
                "retarget_ms": rnd.choice((50, 250, 2000, 5000, _ms(rnd, 50, 5000))),
                "field_upgrades": {
                    "max_level": rnd.randint(1, CORE_MAX_LEVEL),
                    "first_upgrade_cost_bp": bp(0, CORE_MAX_SCALE_BP),
                    "cost_growth_bp": bp(0, CORE_MAX_SCALE_BP),
                    "damage_growth_bp": bp(0, CORE_MAX_SCALE_BP),
                    "range_step_bp": bp(0, CORE_MAX_SCALE_BP),
                    "sell_refund_bp": bp(0, 10000),
                },
            },
            "counters": {"counters": counters},
            "damage": {
                "counter_ratings_bp": {"strong": bp(0, CORE_MAX_MULT_BP), "neutral": bp(0, CORE_MAX_MULT_BP),
                                       "weak": bp(0, CORE_MAX_MULT_BP), "cant_hit": 0},
                "shield_multipliers_bp": {t: bp(1, CORE_MAX_MULT_BP) for t in damage_types},
                "armor_constant": rnd.choice((1, 100, stat(1))),
                "max_reduction_bp": rnd.choice((0, 6000, 6000, bp(0, 10000))),
                "min_damage_x100": rnd.choice((0, 1, 100, stat(0))),
            },
            "status_effects": {"shield_regen": {"per_second_x100": rnd.choice((0, 1, 1500, stat(0))),
                                                "delay_ms": rnd.choice((0, 50, 3000, _ms(rnd, 0, 60_000)))}},
        },
    }


def _combat_map(rnd: random.Random) -> tuple[list[dict], list[list[int]]]:
    """A compact map like a real stage: zigzag lanes from the top edge down a
    few tiles' width, straight air routes, and build tiles right beside them."""
    width, height = rnd.randint(5, 12), rnd.randint(8, 18)
    lanes, tiles = [], []
    for i in range(rnd.randint(1, 3)):
        x, y = rnd.randrange(width), 0
        points = [[x * 1000 + 500, 0]]
        while y < height - 1:
            y = min(height - 1, y + rnd.randint(1, 4))
            points.append([x * 1000 + 500, y * 1000 + 500])
            x = rnd.randrange(width)
            points.append([x * 1000 + 500, y * 1000 + 500])
        lane = {"id": f"l{i}", "ground": points}
        if rnd.random() < 0.6:
            lane["air"] = [points[0], [width * 500, height * 1000]]
        lanes.append(lane)
        for (x0, y0), (x1, y1) in zip(points, points[1:]):
            for _ in range(rnd.randint(0, 2)):
                f = rnd.random()
                cx, cy = int(x0 + (x1 - x0) * f) // 1000, int(y0 + (y1 - y0) * f) // 1000
                tile = [min(max(cx + rnd.choice((-1, 1, 0, 2, -2)), 0), CORE_MAX_TILE),
                        min(max(cy + rnd.choice((-1, 1, 0)), 0), CORE_MAX_TILE)]
                if tile not in tiles:
                    tiles.append(tile)
    return lanes, tiles[:24]


def random_spec(rnd: random.Random, bundle: dict, profile: str, battle_id: str) -> dict:
    """A JSON battle spec that sim/core/battle_spec.gd accepts, using bundle's enemies."""
    enemies = [e for e in bundle_enemies(bundle)
               if all(a["type"] in SUPPORTED_ENEMY_ABILITIES for a in e["abilities"])]
    if not enemies:
        raise ValueError("no enemy this sim version can spawn")
    edges = profile == "edges"
    long_run = profile == "long"
    combat = profile == "combat"
    span = rnd.choice((2_000, 20_000, 60_000)) if not long_run else rnd.choice((200_000, MAX_COORD_MT))
    lanes = []
    combat_tiles: list[list[int]] = []
    if combat:
        lanes, combat_tiles = _combat_map(rnd)
    for i in range(0 if combat else rnd.randint(1, 3 if not edges else 4)):
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

    # Total aliens, to keep a case quick for the model, which plays every tick.
    budget = 8 if long_run else (60 if combat else 40)
    waves = []
    for _ in range(rnd.randint(1, 3)):
        groups = []
        for _ in range(rnd.randint(1, 3)):
            if budget <= 0 and groups:
                break
            enemy = rnd.choice(usable)
            lane = rnd.choice(air_lanes if enemy["movement"] == "air" else ground_lanes)
            count = rnd.randint(1, max(1, min(budget, 25 if not edges else 60)))
            budget -= count
            if combat:
                interval = rnd.choice((0, 50, 250, 500, _ms(rnd, 0, 1500)))
                jitter = rnd.choice((0, 0, 200, _ms(rnd, 0, 1000)))
            elif edges:
                interval = rnd.choice((0, 0, 50, _ms(rnd, 0, 3000)))
                jitter = rnd.choice((0, 50, _ms(rnd, 0, 2000), _ms(rnd, 0, 2000), _ms(rnd, 0, MAX_BATTLE_MS)))
            if not combat and not edges:
                interval = _ms(rnd, 0, 2000)
                jitter = 0 if rnd.random() < 0.4 else _ms(rnd, 0, 1500)
            far = edges and rnd.random() < 0.2  # now and then, a group that may never arrive
            groups.append({
                "enemy": enemy["id"], "lane": lane, "count": count,
                "offset_ms": _ms(rnd, 0, MAX_BATTLE_MS if far else 5000),
                "interval_ms": interval, "jitter_ms": jitter,
            })
        late = edges and rnd.random() < 0.15
        waves.append({
            "start_ms": _ms(rnd, 0, MAX_BATTLE_MS if late else 40_000),
            "hp_bp": (rnd.choice((1, 10000, 1_000_000)) if edges else
                      rnd.choice((300, 2000, 10000, 10900, rnd.randint(1, 30000))) if combat else
                      rnd.choice((10000, 10900, rnd.randint(1, 30000)))),
            "credits_bp": rnd.choice((10000, 10300, rnd.randint(0, 20000))) if not edges else rnd.choice((0, 1_000_000)),
            "groups": groups,
        })
    if long_run:
        max_ms = _ms(rnd, 300_000, 1_000_000)
    elif edges:
        max_ms = rnd.choice((50, 100, 4950, 5000, 5050, _ms(rnd, 50, 90_000)))
    elif combat:
        max_ms = _ms(rnd, 30_000, 120_000)
    else:
        max_ms = _ms(rnd, 2_000, 90_000)

    # Field towers: build tiles near the lanes, and commands that place, upgrade
    # and sell on them, some of which the state will refuse.
    buildable = sorted(t["id"] for t in bundle_towers(bundle)
                       if all(a["type"] in SUPPORTED_TOWER_ABILITIES for a in t["abilities"]))
    if combat:
        tower_set = rnd.sample(buildable, max(0, len(buildable) - (rnd.random() < 0.3)))
    else:
        tower_set = rnd.sample(buildable, rnd.randint(0, len(buildable))) if buildable else []
    tiles: list[list[int]] = combat_tiles
    for _ in range(0 if combat else rnd.randint(0, 10)):
        lane = rnd.choice(lanes)
        px, py = rnd.choice(lane["ground"])
        tile = [min(max(px // 1000 + rnd.randint(-3, 3), 0), CORE_MAX_TILE),
                min(max(py // 1000 + rnd.randint(-3, 3), 0), CORE_MAX_TILE)]
        if tile not in tiles:
            tiles.append(tile)
    last_tick = max_ms // MS_PER_TICK - 1
    commands = []
    if tiles and combat:
        # Build early, then upgrade, sell and rebuild while the waves come.
        ticks_ = sorted([rnd.randint(0, min(last_tick, 60)) for _ in range(rnd.randint(2, 10))] +
                        [rnd.randint(0, min(last_tick, 2000)) for _ in range(rnd.randint(0, 14))])
        for tick in ticks_:
            roll = rnd.random()
            tile = rnd.choice(tiles)
            if (roll < 0.5 or tick <= 60) and tower_set:
                commands.append({"tick": tick, "type": "place", "args": {"tower": rnd.choice(tower_set), "tile": tile}})
            elif roll < 0.9:
                commands.append({"tick": tick, "type": "upgrade", "args": {"tile": tile}})
            else:
                commands.append({"tick": tick, "type": "sell", "args": {"tile": tile}})
    elif tiles:
        for tick in sorted(rnd.randint(0, min(last_tick, rnd.choice((40, 400, 1200)))) for _ in range(rnd.randint(0, 14))):
            roll = rnd.random()
            tile = rnd.choice(tiles)
            if roll < 0.6 and tower_set:
                commands.append({"tick": tick, "type": "place", "args": {"tower": rnd.choice(tower_set), "tile": tile}})
            elif roll < 0.85:
                commands.append({"tick": tick, "type": "upgrade", "args": {"tile": tile}})
            else:
                commands.append({"tick": tick, "type": "sell", "args": {"tile": tile}})
    return {
        "battle_id": battle_id, "mode": "pve", "seed": _seed(rnd), "max_ms": max_ms,
        "lives": rnd.choice((1, 3, 20, 20, 50, MAX_STAT)) if edges else rnd.choice((5, 20, 20, 100, 1000)),
        "credits": (rnd.choice((0, 1, MAX_STAT)) if edges else
                    rnd.choice((300, 2000, 5000, 100_000)) if combat else rnd.choice((0, 300, 500, 2000, 2000, 100_000))),
        "towers": tower_set,
        "map": {"lanes": lanes, "build_tiles": tiles}, "waves": waves, "commands": commands,
    }


def _break_one(rnd: random.Random, case: Case) -> Case:
    """Pushes exactly one value past the core's limits."""
    lanes = list(case.lanes)
    groups = list(case.groups)
    enemies = list(case.enemies)
    choice = rnd.randrange(13 + len(_BREAK_M1))
    if choice >= 13:
        return _BREAK_M1[choice - 13](rnd, case)
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


def _break_tower(rnd: random.Random, case: Case) -> Case:
    towers = list(case.towers) or [Tower(100, 1000, 200, 3000, 0, 10000, 0, (10000,) * 6, 0)]
    i = rnd.randrange(len(towers))
    stat, bad = rnd.choice((("cost_credits", 0), ("cost_credits", MAX_STAT + 1), ("damage_x100", -1),
                            ("shots_per_s_x100", -1), ("range_mt", MAX_STAT + 1), ("splash_mt", -1),
                            ("shield_mult_bp", 0), ("shield_mult_bp", CORE_MAX_MULT_BP + 1), ("pierce_bp", 10001),
                            ("unrevealed_bp", CORE_MAX_MULT_BP + 1), ("rating_bp", -1)))
    if stat == "rating_bp":
        ratings = list(towers[i].rating_bp)
        ratings[rnd.randrange(len(ratings))] = rnd.choice((-1, CORE_MAX_MULT_BP + 1))
        towers[i] = dataclasses.replace(towers[i], rating_bp=tuple(ratings))
    else:
        towers[i] = dataclasses.replace(towers[i], **{stat: bad})
    return dataclasses.replace(case, towers=tuple(towers), broken=f"tower {i} {stat}")


def _break_rules(rnd: random.Random, case: Case) -> Case:
    roll = rnd.randrange(4)
    if roll == 0:
        stat, bad = rnd.choice((("max_level", 0), ("max_level", CORE_MAX_LEVEL + 1), ("sell_refund_bp", 10001),
                                ("cost_growth_bp", CORE_MAX_SCALE_BP + 1), ("damage_growth_bp", -1)))
        return dataclasses.replace(case, upgrades=dataclasses.replace(case.upgrades, **{stat: bad}), broken=f"upgrades {stat}")
    stat, bad = rnd.choice((("armor_constant", 0), ("max_reduction_bp", 10001), ("min_damage_x100", -1),
                            ("regen_per_second_x100", -1), ("regen_delay_ticks", CORE_MAX_TICKS + 1),
                            ("retarget_ticks", 0)))
    return dataclasses.replace(case, rules=dataclasses.replace(case.rules, **{stat: bad}), broken=f"rules {stat}")


def _break_spec(rnd: random.Random, case: Case) -> Case:
    roll = rnd.randrange(6)
    if roll == 0:
        return dataclasses.replace(case, lives=rnd.choice((0, -1, MAX_STAT + 1)), broken="lives")
    if roll == 1:
        return dataclasses.replace(case, credits=rnd.choice((-1, MAX_STAT + 1)), broken="credits")
    if roll == 2:
        bad = rnd.choice((-1, len(case.towers)))
        return dataclasses.replace(case, tower_set=case.tower_set + (bad,), broken="tower set: unknown tower")
    if roll == 3 and case.tower_set:
        return dataclasses.replace(case, tower_set=case.tower_set + (case.tower_set[0],), broken="tower set: twice")
    if roll == 4 and case.build_tiles:
        return dataclasses.replace(case, build_tiles=case.build_tiles + (case.build_tiles[0],), broken="tile twice")
    tile = rnd.choice(((-1, 0), (0, CORE_MAX_TILE + 1)))
    return dataclasses.replace(case, build_tiles=case.build_tiles + (tile,), broken="tile out of range")


def _break_group_scale(rnd: random.Random, case: Case) -> Case:
    groups = list(case.groups)
    g = rnd.randrange(len(groups))
    stat, bad = rnd.choice((("hp_bp", 0), ("hp_bp", CORE_MAX_SCALE_BP + 1), ("credits_bp", -1)))
    groups[g] = dataclasses.replace(groups[g], **{stat: bad})
    return dataclasses.replace(case, groups=tuple(groups), broken=f"group {g} {stat}")


def _break_command(rnd: random.Random, case: Case) -> Case:
    """A command no loader would pass: the core must refuse the whole battle."""
    tiles = case.build_tiles or ((0, 0),)
    col, row = tiles[0]
    cases = [
        ("tick at the end", Command(case.max_ticks, 2, -1, col, row)),
        ("negative tick", Command(-1, 2, -1, col, row)),
        ("unknown kind", Command(0, rnd.choice((0, 4)), -1, col, row)),
        ("not a build tile", Command(0, 2, -1, CORE_MAX_TILE, CORE_MAX_TILE)
         if (CORE_MAX_TILE, CORE_MAX_TILE) not in tiles else Command(0, 2, -1, -1, 0)),
        ("tower not in the set", Command(0, 1, len(case.towers), col, row)),
        ("upgrade names a tower", Command(0, 2, 0, col, row)),
    ]
    what, bad = rnd.choice(cases)
    build_tiles = case.build_tiles or ((0, 0),)
    commands = list(case.commands)
    if what in ("negative tick",) or not commands:
        commands.insert(0, bad)
    elif what == "tick at the end":
        commands.append(bad)
    else:
        commands.append(dataclasses.replace(bad, tick=commands[-1].tick))
    # Out of order: a tick before the one ahead of it.
    if rnd.random() < 0.2 and len(case.commands) >= 1 and case.commands[-1].tick > 0:
        what = "ticks out of order"
        last = case.commands[-1]
        commands = list(case.commands) + [dataclasses.replace(last, tick=last.tick - 1)]
    return dataclasses.replace(case, build_tiles=build_tiles, commands=tuple(commands), broken=f"command: {what}")


def _break_unsupported(rnd: random.Random, case: Case) -> Case:
    """A tower or alien with an ability this sim version doesn't run, in use."""
    if case.towers and rnd.random() < 0.5:
        i = rnd.randrange(len(case.towers))
        towers = list(case.towers)
        towers[i] = dataclasses.replace(towers[i], supported=False)
        tower_set = case.tower_set if i in case.tower_set else case.tower_set + (i,)
        return dataclasses.replace(case, towers=tuple(towers), tower_set=tower_set, broken=f"tower {i} unsupported")
    g = rnd.randrange(len(case.groups))
    enemies = list(case.enemies)
    e = case.groups[g].enemy_index
    enemies[e] = dataclasses.replace(enemies[e], supported=False)
    return dataclasses.replace(case, enemies=tuple(enemies), broken=f"enemy {e} unsupported")


def _break_release(rnd: random.Random, case: Case) -> Case:
    enemies = list(case.enemies)
    e = rnd.randrange(len(enemies))
    bad = rnd.choice(((len(enemies), 1), (-2, 1), (e, 0), (e, CORE_MAX_RELEASE + 1)))
    enemies[e] = dataclasses.replace(enemies[e], release_index=bad[0], release_count=bad[1])
    return dataclasses.replace(case, enemies=tuple(enemies), broken=f"enemy {e} release")


_BREAK_M1 = (_break_tower, _break_rules, _break_spec, _break_group_scale, _break_command, _break_command,
             _break_unsupported, _break_release)


def random_case(seed: int, index: int, frozen_bundle: dict) -> Case:
    rnd = random.Random(f"aetd-sim-fuzz:{seed}:{index}")
    profile = PROFILE_CYCLE[index % len(PROFILE_CYCLE)]
    bundle = _random_bundle(rnd) if profile == "random_config" else frozen_bundle
    spec_profile = rnd.choice(("typical", "combat")) if profile in ("random_config", "invalid") else profile
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
    commands = list(case.commands)
    for i in range(len(commands)):
        yield dataclasses.replace(case, commands=tuple(commands[:i] + commands[i + 1:]))
    used = {(c.col, c.row) for c in commands}
    tiles = [t for t in case.build_tiles if t in used]
    if len(tiles) < len(case.build_tiles):
        yield dataclasses.replace(case, build_tiles=tuple(tiles))
    placed = {c.tower_index for c in commands if c.kind == 1}
    tower_set = tuple(t for t in case.tower_set if t in placed)
    if len(tower_set) < len(case.tower_set):
        yield dataclasses.replace(case, tower_set=tower_set)
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
