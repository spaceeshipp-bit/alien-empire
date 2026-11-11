"""Reference model of the M0 battle, for checking the C++ sim core (D-028).

Written from the rules, not from the C++. The core steps every alien tick by
tick; this model works out, in closed form, when each alien spawns, where it is
at any tick and when it reaches the Core. tools/check_sim_native.py runs both
on generated battles and compares outcome, ticks, every checkpoint and the
final hash, so a wrong answer in either one shows up as a mismatch.

The model never produces a result the game uses: the C++ core is the only
battle logic. When a sim change raises SIM_VERSION, this model must learn the
new rule too; check_sim_native.py refuses to compare across versions.

The rules of sim version 1, in the order a tick applies them:
1. Spawn plan, fixed at setup: groups in spec order, units in group order. Unit
   n of a group spawns at first_tick + n * interval_ticks, plus a seeded draw
   from 0 to jitter_ticks when jitter_ticks > 0. Aliens spawn in order of
   (spawn tick, plan position) and take ids 1, 2, 3, ... in that order.
2. A tick that starts at tick counter c spawns every alien whose spawn tick is
   at most c, then moves every alien on the field. After its k-th move an alien
   has covered floor(k * speed / 20) thousandths of a tile, and k * speed mod 20
   is the remainder it carries. Reaching the end of its path, it leaks: it
   leaves the field and costs its leak lives.
3. The counter then rises by one. Every 100 ticks a checkpoint hash is taken,
   before the outcome is decided. The battle is cleared when every alien has
   spawned and none is left; otherwise it times out when the counter reaches
   max_ticks.
"""
from __future__ import annotations

import bisect
import hashlib
import math
import struct
import sys
from dataclasses import dataclass, field
from pathlib import Path

TOOLS = str(Path(__file__).resolve().parent.parent)
if TOOLS not in sys.path:
    sys.path.insert(0, TOOLS)
from gen_vectors import Rng  # noqa: E402  (the Python twin of the sim's generator)

MODEL_SIM_VERSION = 1
TICK_RATE = 20
CHECKPOINT_TICKS = 100
OUTCOMES = ("running", "cleared", "timed_out")
RUNNING, CLEARED, TIMED_OUT = 0, 1, 2


def tdiv(a: int, b: int) -> int:
    """Integer division that truncates toward zero, as C++ and GDScript do."""
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


@dataclass(frozen=True)
class LanePath:
    xs: tuple[int, ...]
    ys: tuple[int, ...]
    starts: tuple[int, ...]  # distance along the path at each point

    @property
    def length(self) -> int:
        return self.starts[-1]

    def position(self, d: int) -> tuple[int, int]:
        if d <= 0:
            return self.xs[0], self.ys[0]
        if d >= self.length:
            return self.xs[-1], self.ys[-1]
        i = bisect.bisect_right(self.starts, d) - 1
        seg = self.starts[i + 1] - self.starts[i]
        into = d - self.starts[i]
        return (
            self.xs[i] + tdiv((self.xs[i + 1] - self.xs[i]) * into, seg),
            self.ys[i] + tdiv((self.ys[i + 1] - self.ys[i]) * into, seg),
        )


def build_path(points) -> LanePath | None:
    """A lane path: repeated consecutive points are dropped, and each segment is
    as long as the integer square root of its squared length. None if fewer than
    two different points remain."""
    kept: list[tuple[int, int]] = []
    for x, y in points:
        if not kept or kept[-1] != (x, y):
            kept.append((x, y))
    if len(kept) < 2:
        return None
    starts = [0]
    for (x0, y0), (x1, y1) in zip(kept, kept[1:]):
        dx, dy = x1 - x0, y1 - y0
        # math.isqrt is the exact floor square root: the same function as the
        # core's Newton iteration, computed a different way.
        starts.append(starts[-1] + math.isqrt(dx * dx + dy * dy))
    return LanePath(tuple(p[0] for p in kept), tuple(p[1] for p in kept), tuple(starts))


@dataclass(frozen=True)
class Alien:
    id: int
    type_index: int
    lane_index: int
    air: bool
    path: LanePath
    speed: int
    hp: int
    shield: int
    lives: int
    spawn: int  # the tick counter at the start of the tick it spawns in
    moves_to_leak: int  # the move on which it reaches the Core

    @property
    def leak_tick(self) -> int:
        """The tick counter right after the tick it leaks in."""
        return self.spawn + self.moves_to_leak

    def alive_at(self, t: int) -> bool:
        """On the field when the tick counter reads t."""
        return self.spawn < t < self.leak_tick


@dataclass
class Result:
    outcome: str
    ticks: int
    final_hash: str
    checkpoints: list[str] = field(default_factory=list)
    spawned: int = 0
    leaked: int = 0
    leaked_lives: int = 0
    entity_updates: int = 0
    # What core_check's battle_reuse sees: were aliens on the field when it
    # stopped the first run (at tick 50 or later, or at the end)?
    reuse_had_aliens: bool = False

    def line(self) -> str:
        return " ".join(["result", self.outcome, str(self.ticks), self.final_hash, *self.checkpoints])


def run(case) -> Result:
    """Plays a battle (a tools/sim_cases.Case that the core accepts)."""
    paths = []
    for lane in case.lanes:
        ground = build_path(lane.ground)
        air = build_path(lane.air) if lane.air else None
        if ground is None or (lane.air and air is None):
            raise ValueError("the model only plays battles the core accepts")
        paths.append((ground, air))

    rng = Rng(case.seed)
    plan = []  # (spawn tick, plan position, group)
    for group in case.groups:
        for n in range(group.count):
            jitter = rng.range_int(0, group.jitter_ticks) if group.jitter_ticks > 0 else 0
            plan.append((group.first_tick + n * group.interval_ticks + jitter, len(plan), group))
    plan.sort()
    rng_words = list(rng.s)  # nothing else draws from the generator in sim version 1

    aliens: list[Alien] = []
    for number, (spawn, _, group) in enumerate(plan, start=1):
        enemy = case.enemies[group.enemy_index]
        ground, air = paths[group.lane_index]
        path = air if enemy.air else ground
        if path is None:
            raise ValueError("an air alien needs an air route")
        moves = -(-TICK_RATE * path.length // enemy.speed_mtps)  # ceil(20 * length / speed)
        aliens.append(Alien(
            id=number, type_index=group.enemy_index, lane_index=group.lane_index, air=enemy.air,
            path=path, speed=enemy.speed_mtps, hp=enemy.hp_x100, shield=enemy.shield_x100,
            lives=enemy.leak_lives, spawn=spawn, moves_to_leak=moves,
        ))
    spawns = [a.spawn for a in aliens]  # ascending, like the ids

    # Cleared on the first tick when every alien has spawned and none is left:
    # the last leak, or tick 1 when no alien ever spawns.
    clear_tick = max([1] + [a.leak_tick for a in aliens])
    if clear_tick <= case.max_ticks:
        outcome, end = CLEARED, clear_tick
    else:
        outcome, end = TIMED_OUT, case.max_ticks

    def state_hash(t: int, state: int) -> str:
        spawned = bisect.bisect_right(spawns, t - 1)
        leaked = [a for a in aliens[:spawned] if a.leak_tick <= t]
        alive = [a for a in aliens[:spawned] if a.alive_at(t)]
        out = bytearray()

        def add(v: int) -> None:
            out.extend(struct.pack("<q", v))

        add(MODEL_SIM_VERSION)
        text = case.config_hash.encode("utf-8")
        add(len(text))
        out.extend(text)
        add(case.seed)
        add(t)
        add(state)
        for word in rng_words:
            add(word)
        add(spawned + 1)  # next id
        add(spawned)  # spawn plan entries used
        add(spawned)
        add(len(leaked))
        add(sum(a.lives for a in leaked))
        add(len(alive))
        for a in alive:
            moves = t - a.spawn
            distance = moves * a.speed // TICK_RATE
            x, y = a.path.position(distance)
            for v in (a.id, a.type_index, a.lane_index, int(a.air), distance, moves * a.speed % TICK_RATE,
                      a.hp, a.shield, x, y):
                add(v)
        return hashlib.sha256(bytes(out)).hexdigest()

    # Checkpoints are taken before the outcome is decided, so they say "running".
    checkpoints = [state_hash(t, RUNNING)[:16] for t in range(CHECKPOINT_TICKS, end + 1, CHECKPOINT_TICKS)]
    final = state_hash(end, outcome)

    def alive_somewhere(lo: int, hi: int) -> bool:
        return any(max(a.spawn + 1, lo) <= min(a.leak_tick - 1, hi) for a in aliens)

    leaked = [a for a in aliens if a.leak_tick <= end]
    return Result(
        outcome=OUTCOMES[outcome],
        ticks=end,
        final_hash=final,
        checkpoints=checkpoints,
        spawned=bisect.bisect_right(spawns, end - 1),
        leaked=len(leaked),
        leaked_lives=sum(a.lives for a in leaked),
        entity_updates=sum(max(0, min(a.moves_to_leak, end - a.spawn)) for a in aliens),
        reuse_had_aliens=alive_somewhere(50, end - 1) or any(a.alive_at(end) for a in aliens),
    )
