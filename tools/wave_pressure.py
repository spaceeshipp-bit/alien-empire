#!/usr/bin/env python3
"""Wave pressure for each PvE stage, and a playthrough with its reference layout.

The build prompt's measure (Difficulty): required damage per second = the wave's
HP / (its spawn time + time in the kill zone), compared with what the player's
credits can buy. Read for M1 as M1.md's M1-F says:
- a wave's HP is every alien's HP and shield, scaled by the wave;
- the kill zone is the stretch of each route within range of the towers that
  can hit that alien, among those the credits could have bought by the wave's
  start: the stage's reference layout, built in order, at level 1. A wave's
  time in it is the HP-weighted mean over its groups;
- what credits can buy: every credit the player has had by the wave's start
  (the starting credits plus the kill credits of every earlier wave) times the
  best damage per second per credit the stage's towers get against the wave's
  aliens, worked out with the sim's own damage pipeline and HP-weighted;
- targets: 0.4 to 0.6 on the early waves (1 to 3), 0.8 to 1.0 on the last.
  No M1 wave is a boss wave (about 1.1).

The playthrough plays the stage through the reference model (an exact twin of
the sim, D-028) with the builder the battle screen's --autoplay uses: the
reference layout in order, then upgrades in the same order, one command a tick
whenever the credits allow.

    python3 tools/wave_pressure.py             # report every stage
    python3 tools/wave_pressure.py --check     # exit 1 if a wave misses its target or the playthrough loses
    python3 tools/wave_pressure.py --tune      # search starting credits and a kill-credit scale for the targets
"""
from __future__ import annotations

import argparse
import dataclasses
import math
import sys
from pathlib import Path

import config_tool
import sim_cases
import stages
from reference import sim_model

EARLY_WAVES = 3
EARLY_TARGET = (0.4, 0.6)
LAST_TARGET = (0.8, 1.0)
# The gates --check enforces (D-035): the reference builder clears with this
# many lives left, and a builder with only Pulse Turrets loses, so counters matter.
REFERENCE_LIVES = (10, 16)
ONLY_TOWER = "pulse_turret"


@dataclasses.dataclass
class WaveReport:
    number: int
    hp: float
    spawn_s: float
    kill_zone_s: float
    required_dps: float
    credits: float
    dps_per_credit: float
    ratio: float
    target: tuple[float, float] | None

    @property
    def ok(self) -> bool:
        return self.target is None or self.target[0] <= self.ratio <= self.target[1]


def _covered_length(points: list, towers: list[tuple[int, int, int]]) -> float:
    """mt of the path within reach of at least one (x, y, range) tower."""
    covered = 0.0
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        length = math.hypot(x1 - x0, y1 - y0)
        steps = max(1, int(length // 50))
        for k in range(steps):
            f = (k + 0.5) / steps
            x, y = x0 + (x1 - x0) * f, y0 + (y1 - y0) * f
            if any((x - tx) ** 2 + (y - ty) ** 2 <= r * r for tx, ty, r in towers):
                covered += length / steps
    return covered


def _context(data: dict, stage: dict, kill_scale: float = 1.0):
    bundle = config_tool.make_bundle(data)
    enemies = {e["id"]: e for e in data["enemies"]["enemies"]}
    index = {e["id"]: i for i, e in enumerate(sim_cases.bundle_enemies(bundle))}
    towers = {t["id"]: t for t in data["towers"]["towers"]}
    resolved = {tid: sim_cases.resolve_tower(bundle, towers[tid]) for tid in stage["towers"]}
    resolved_enemies = {eid: sim_cases.resolve_enemy(e, index) for eid, e in enemies.items()}
    upgrades, rules = sim_cases.bundle_rules(bundle)
    return bundle, enemies, resolved, resolved_enemies, upgrades, rules


def _hittable(tower: sim_cases.Tower, enemy: sim_cases.Enemy) -> bool:
    return tower.rating_bp[enemy.class_index] > 0 and (enemy.class_index != sim_model.CLOAKED or tower.unrevealed_bp > 0)


def pressure(data: dict, stage: dict, credits: int | None = None, kill_scale: float = 1.0) -> list[WaveReport]:
    """The pressure of each wave. credits and kill_scale override the stage's
    starting credits and scale every kill credit, for --tune."""
    _bundle, enemies, towers, resolved_enemies, upgrades, rules = _context(data, stage)
    lanes = {lane["id"]: lane for lane in stage["lanes"]}
    layout = [(place["tower"], place["tile"]) for place in stage["reference_layout"]]
    banked = float(stage["credits"] if credits is None else credits)
    reports = []
    waves = stage["waves"]
    for w, wave in enumerate(waves):
        hp_bp = stages.wave_scale_bp(stage["hp_growth_bp"], w)
        credits_bp = stages.wave_scale_bp(stage["credit_growth_bp"], w)
        total_hp = 0.0
        weighted_zone = 0.0
        credit_seconds = 0.0  # credits needed for 1 second of the damage the wave asks for, summed by HP
        spawn_end = 0.0
        earned = 0.0
        built, spent = [], 0
        for tid, tile in layout:
            spent += towers[tid].cost_credits
            if spent > banked:
                break
            built.append((tid, tile))
        for group in wave["groups"]:
            enemy, resolved = enemies[group["enemy"]], resolved_enemies[group["enemy"]]
            hp = (max(1, enemy["hp_x100"] * hp_bp // 10000) + enemy["shield_x100"]) / 100.0 * group["count"]
            total_hp += hp
            spawn_end = max(spawn_end, (group["offset_ms"] + (group["count"] - 1) * group["interval_ms"]) / 1000.0)
            route = lanes[group["lane"]]["air" if enemy["movement"] == "air" else "ground"]
            reach = [(tile[0] * 1000 + 500, tile[1] * 1000 + 500, sim_model.level_range(towers[tid], upgrades, 1))
                     for tid, tile in built if _hittable(towers[tid], resolved)]
            zone_s = _covered_length(route, reach) / enemy["speed_mtps"]
            weighted_zone += zone_s * hp
            best = 0.0
            for tower in towers.values():
                if not _hittable(tower, resolved):
                    continue
                _, hull = sim_model.hit_result(tower.damage_x100, tower.rating_bp[resolved.class_index],
                                               resolved.class_index == sim_model.CLOAKED, tower.unrevealed_bp, 0,
                                               tower.shield_mult_bp, enemy["armor"], tower.pierce_bp, rules)
                best = max(best, hull / 100.0 * tower.shots_per_s_x100 / 100.0 / tower.cost_credits)
            credit_seconds += hp / best if best > 0 else math.inf
            earned += enemy["kill_credits_x100"] * kill_scale * credits_bp / 10000 / 100.0 * group["count"]
        zone = weighted_zone / total_hp
        required = total_hp / (spawn_end + zone) if spawn_end + zone > 0 else math.inf
        per_credit = total_hp / credit_seconds if credit_seconds > 0 else 0.0
        affordable = banked * per_credit
        if w < EARLY_WAVES:
            target = EARLY_TARGET
        elif w == len(waves) - 1:
            target = LAST_TARGET
        else:
            target = None
        reports.append(WaveReport(w + 1, total_hp, spawn_end, zone, required, banked, per_credit,
                                  required / affordable if affordable > 0 else math.inf, target))
        banked += earned
    return reports


def playthrough(data: dict, stage: dict, seed: int = 1, only: str = "") -> tuple[sim_model.Result, list[dict]]:
    """The stage played by the battle screen's --autoplay builder, through the
    reference model. Returns the result and the commands it sent. With only,
    every tower in the layout is that tower instead."""
    bundle = config_tool.make_bundle(data)
    spec = stages.build_spec(stage, seed)
    towers = {t["id"]: t for t in data["towers"]["towers"]}
    fu = data["towers"]["field_upgrades"]
    layout = [(place["tile"], only or place["tower"]) for place in stage["reference_layout"]]
    plan: list[tuple[str, list[int], str]] = [("place", tile, tower) for tile, tower in layout]
    for tile, tower in layout:
        for _ in range(fu["max_level"] - 1):
            plan.append(("upgrade", tile, tower))
    commands: list[dict] = []
    levels: dict[tuple[int, int], int] = {}
    next_from = 0
    for kind, tile, tower_id in plan:
        tower = sim_cases.resolve_tower(bundle, towers[tower_id])
        up = sim_cases.bundle_rules(bundle)[0]
        if kind == "place":
            cost = tower.cost_credits * 100
        else:
            cost = sim_model.upgrade_cost(tower, up, levels[tuple(tile)])
        trace: list[int] = []
        spec["commands"] = commands
        sim_model.run(sim_cases.case_from_spec(bundle, spec), trace)
        tick = next((t for t in range(next_from, len(trace)) if trace[t] >= cost), None)
        if tick is None:
            break  # never affordable before the battle ends
        args = {"tile": list(tile)} if kind == "upgrade" else {"tower": tower_id, "tile": list(tile)}
        commands = commands + [{"tick": tick, "type": kind, "args": args}]
        levels[tuple(tile)] = levels.get(tuple(tile), 0) + 1
        next_from = tick + 1
    spec["commands"] = commands
    return sim_model.run(sim_cases.case_from_spec(bundle, spec)), commands


def report(data: dict, stage: dict, strict_last: bool = False) -> bool:
    ok = True
    print(f"Stage {stage['id']}: {stage['credits']} starting credits, {len(stage['waves'])} waves")
    print(" wave      HP  spawn s  zone s  needs dps   credits  dps/credit  ratio  target")
    for r in pressure(data, stage):
        target = f"{r.target[0]:.1f}-{r.target[1]:.1f}" if r.target else ""
        last = r.number == len(stage["waves"])
        flag = "" if r.ok else ("  << out of target" if strict_last or not last else "  (reported, not gated: D-035)")
        ok = ok and (r.ok or (last and not strict_last))
        print(f" {r.number:4d} {r.hp:7.0f} {r.spawn_s:8.1f} {r.kill_zone_s:7.1f} {r.required_dps:10.1f} "
              f"{r.credits:9.0f} {r.dps_per_credit:11.3f} {r.ratio:6.2f}  {target}{flag}")
    result, commands = playthrough(data, stage)
    upgrades = sum(1 for c in commands if c["type"] == "upgrade")
    print(f"Reference playthrough: {result.outcome} at {result.ticks / 20:.0f} s, {result.lives} of {stage['lives']} lives, "
          f"{result.kills} kills, {result.leaked} leaks; {len(commands) - upgrades} towers and {upgrades} upgrades")
    low, high = REFERENCE_LIVES
    if result.outcome != "cleared" or not low <= result.lives <= high:
        print(f"  << the reference builder should clear with {low} to {high} lives left")
        ok = False
    only, _ = playthrough(data, stage, only=ONLY_TOWER)
    print(f"{ONLY_TOWER} only: {only.outcome} at {only.ticks / 20:.0f} s, {only.lives} lives, {only.kills} kills")
    if only.outcome == "cleared":
        print(f"  << {ONLY_TOWER} alone shouldn't clear the stage: counters must matter")
        ok = False
    return ok


def tune(data: dict, stage: dict) -> None:
    """Starting credits and a kill-credit scale that put the early and last waves
    in their targets, closest to the middle of each target."""
    best = None
    for credits in range(100, 1501, 25):
        for scale_x8 in range(4, 81):
            scale = scale_x8 / 8.0
            reports = pressure(data, stage, credits, scale)
            if not all(r.ok for r in reports):
                continue
            miss = sum((r.ratio - sum(r.target) / 2) ** 2 for r in reports if r.target)
            if best is None or miss < best[0]:
                best = (miss, credits, scale)
    if best is None:
        print(f"{stage['id']}: no starting credits and kill-credit scale meet every target; change the waves")
        return
    _, credits, scale = best
    print(f"{stage['id']}: starting credits {credits}, kill credits x{scale:.2f}")
    for e in data["enemies"]["enemies"]:
        print(f"  {e['id']}: kill_credits_x100 {e['kill_credits_x100']} -> {round(e['kill_credits_x100'] * scale / 50) * 50}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="exit 1 if a wave misses its target or the playthrough loses")
    parser.add_argument("--tune", action="store_true", help="search credits that meet the targets")
    args = parser.parse_args(argv)
    data = config_tool.load_balance()
    ok = True
    for stage in data["stages"]["stages"]:
        if args.tune:
            tune(data, stage)
            continue
        ok = report(data, stage) and ok
    if args.check:
        print("RESULT: " + ("PASS" if ok else "FAIL"))
        return 0 if ok else 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
