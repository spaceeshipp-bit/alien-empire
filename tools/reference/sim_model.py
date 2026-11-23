"""Reference model of a battle, for checking the C++ sim core (D-028, D-034).

Written from the rules, not from the C++. It plays a battle tick by tick with its
own structures: plain lists, and towers that look at every alien instead of the
core's spatial grid. tools/check_sim_native.py runs both on generated battles and
compares the outcome, the ticks, lives, credits, kills, leaks, refused commands,
every checkpoint and the final hash, so a wrong answer in either shows up.

The model never produces a result the game uses: the C++ core is the only
battle logic. When a sim change raises SIM_VERSION, this model must learn the
new rule too; check_sim_native.py refuses to compare across versions.

Every division below works on values that can't be negative, so floor division
is the same as the core's truncation toward zero.

The rules of sim version 3 (version 2's, plus D-036's: Strongest targeting,
calling a wave early, and the clean-wave bonus). The tick counter c starts at
0; a tick does, in order:

1. Commands. Every command for tick c, in log order. A command the state
   refuses changes nothing but adds one to the refused count:
   - place: the build tile must be empty and the credits must cover the build
     cost (credits are kept x100). The tower takes the next tower id and stands
     at the tile's center (col * 1000 + 500, row * 1000 + 500), at level 1,
     fully charged (2000), with no target and a re-pick time of 0.
   - upgrade: there must be a tower on the tile below the top level, and the
     credits must cover the upgrade: build cost x100 x first_upgrade_cost_bp,
     then x cost_growth_bp for each level above 1, each step truncated and
     capped at 1,000,000,000 credits. Its level damage and range are worked out
     again.
   - sell: there must be a tower on the tile. It returns everything spent on it
     x sell_refund_bp and leaves the tile.
   - call_wave: there must be a wave that hasn't started (start > c). The
     earliest (the lower index on a tie) starts now: every wave that hasn't
     started moves earlier by the same number of ticks, with its unspawned
     spawns (the rest of the plan is sorted again by tick, then plan position).
     The player gets min(skipped ticks x call_credits_per_s x 100 // 20,
     call_credits_max x 100).
2. Spawns. The spawn plan is fixed at setup: groups in spec order, units in
   group order; unit n of a group spawns at first_tick + n * interval_ticks,
   plus a seeded draw from 0 to jitter_ticks when jitter_ticks > 0. Aliens
   spawn in order of (spawn tick, plan position), every alien whose spawn tick
   is at most c, and take ids 1, 2, 3, ... HP is the type's HP x the wave's
   hp_bp (at least 1, at most 1,000,000,000); shields are the type's; kill
   credits are the type's x the wave's credits_bp (at most 1,000,000,000).
3. Moves. Each alien in id order adds its speed to a remainder, moves
   remainder // 20 thousandths of a tile and keeps the rest. At the end of its
   path it leaks: it costs its leak lives (lives stop at 0) and leaves. Every
   alien's position on its path is worked out after it moves.
4. Shield regen. An alien below its full shield, whose last hit was at least
   regen_delay_ticks ago, adds regen_per_second_x100 to a remainder and gains
   remainder // 20; full, it stops there and the remainder clears.
5. Towers, in id order. A tower whose charge is at least 2000 is ready:
   - It keeps its target if that alien is alive, hittable, in range, and c is
     before the tower's re-pick time. Otherwise it picks among every live,
     hittable alien in range the one with the least distance left to the end
     of its path, the lower id on a tie (a Strongest tower picks the most
     full HP plus full shield instead, the toughest kind, then the least
     distance left, then the lower id), and sets its re-pick time to c +
     retarget_ticks. Range is the level range; in range means dx^2 + dy^2 <=
     range^2.
   - Hittable: the tower's counter rating for the alien's class isn't 0, and
     for a cloaked alien its unrevealed damage share isn't 0 (nothing reveals
     in this version).
   - With a target, it uses 2000 charge and fires. With splash, every live,
     hittable alien within the splash radius of the target's position takes a
     hit, in id order; without, the target alone.
   Then every tower gains its shots_per_s_x100, up to 2000.
   A hit (the damage pipeline) on an alien:
   - damage = level damage (the tower's damage, x damage_growth_bp per level
     above 1, each step capped at 1,000,000,000) x the counter rating // 10000,
     and for a cloaked alien x the unrevealed share // 10000.
   - The alien's last hit becomes c and its regen remainder clears.
   - Shield first: if it has one, on_shield = damage x shield multiplier //
     10000. Below the shield, the shield loses max(on_shield, the 1-point
     floor), stopping at 0, and the hit ends. Otherwise the shield breaks and
     damage = (on_shield - shield) x 10000 // multiplier; at 0 the hit ends.
   - Hull: armor = the type's armor x (10000 - pierce) // 10000; reduction =
     min(armor x 10000 // (armor + armor_constant), max_reduction_bp); the hull
     loses max(damage x (10000 - reduction) // 10000, the 1-point floor).
   - At 0 HP or below it dies: its kill credits are paid at once and it counts
     as a kill. If its type releases others on death, it's noted, in order.
6. Released aliens join, in order of death: for each, release_count aliens of
   the released type take the next ids, on the same lane and path at the same
   distance, with the dead alien's wave scaling. They move from the next tick.
   Then the dead leave. Every alien belongs to its group's wave (a released
   one to its releaser's). A wave is done when everything it planned has
   spawned and every one of its aliens has died or leaked; in index order,
   each newly done wave with no leak pays clean_wave_credits.
7. The counter rises by one. Every 100 ticks a checkpoint hash is taken, before
   the outcome is decided. The battle is lost at 0 lives; otherwise cleared when
   every planned alien has spawned and none is left; otherwise it times out when
   the counter reaches max_ticks.
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

MODEL_SIM_VERSION = 3
TICK_RATE = 20
CHECKPOINT_TICKS = 100
SHOT_CHARGE = 2000
MAX_STAT = 1_000_000_000
CLOAKED = 4
OUTCOMES = ("running", "cleared", "timed_out", "lost")
RUNNING, CLEARED, TIMED_OUT, LOST = 0, 1, 2, 3
PLACE, UPGRADE, SELL, CALL_WAVE = 1, 2, 3, 4
STRONGEST = 1


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


@dataclass
class Alien:
    id: int
    type_index: int
    lane_index: int
    class_index: int
    air: bool
    path: LanePath
    speed: int
    hp: int
    max_hp: int
    shield: int
    max_shield: int
    lives: int
    kill_credits: int
    hp_bp: int
    credits_bp: int
    last_hit: int
    wave: int = 0
    distance: int = 0
    remainder: int = 0
    regen: int = 0
    x: int = 0
    y: int = 0
    dead: bool = False


@dataclass
class Tower:
    id: int
    type_index: int
    col: int
    row: int
    spent: int
    level: int = 1
    charge: int = SHOT_CHARGE
    target: int = 0
    next_pick: int = 0

    @property
    def x(self) -> int:
        return self.col * 1000 + 500

    @property
    def y(self) -> int:
        return self.row * 1000 + 500


@dataclass
class Result:
    outcome: str
    ticks: int
    final_hash: str
    checkpoints: list[str] = field(default_factory=list)
    lives: int = 0
    credits_x100: int = 0
    kills: int = 0
    spawned: int = 0
    leaked: int = 0
    leaked_lives: int = 0
    refused: int = 0
    entity_updates: int = 0
    # What core_check's battle_reuse sees: were aliens on the field when it
    # stopped the first run (at tick 50 or later, or at the end)?
    reuse_had_aliens: bool = False
    bot_commands: list = field(default_factory=list)

    def line(self) -> str:
        return result_line(self.outcome, self.ticks, self.lives, self.credits_x100, self.kills, self.leaked,
                           self.refused, self.spawned, self.final_hash, self.checkpoints)


def result_line(outcome, ticks, lives, credits_x100, kills, leaked, refused, spawned, final_hash, checkpoints) -> str:
    """core_check.cpp's answer to battle_run."""
    return " ".join(["result", outcome, str(ticks), f"lives={lives}", f"credits={credits_x100}", f"kills={kills}",
                     f"leaked={leaked}", f"refused={refused}", f"spawned={spawned}", final_hash, *checkpoints])


def level_damage(tower_type, upgrades, level: int) -> int:
    damage = tower_type.damage_x100
    for _ in range(level - 1):
        damage = min(damage * upgrades.damage_growth_bp // 10000, MAX_STAT)
    return damage


def level_range(tower_type, upgrades, level: int) -> int:
    return min(tower_type.range_mt * (10000 + upgrades.range_step_bp * (level - 1)) // 10000, MAX_STAT)


def upgrade_cost(tower_type, upgrades, level: int) -> int:
    """x100 credits to take a tower from level to level + 1."""
    cost = min(tower_type.cost_credits * 100 * upgrades.first_upgrade_cost_bp // 10000, MAX_STAT * 100)
    for _ in range(level - 1):
        cost = min(cost * upgrades.cost_growth_bp // 10000, MAX_STAT * 100)
    return cost


def hit_result(damage: int, rating_bp: int, cloaked: bool, unrevealed_bp: int, shield: int, shield_mult_bp: int,
               armor: int, pierce_bp: int, rules) -> tuple[int, int]:
    """One hit of the damage pipeline: (the shield left, the hull damage).
    damage is the tower's level damage; the rest describe the alien and tower."""
    damage = damage * rating_bp // 10000
    if cloaked:
        damage = damage * unrevealed_bp // 10000
    if shield > 0:
        on_shield = damage * shield_mult_bp // 10000
        if on_shield < shield:
            return max(0, shield - max(on_shield, rules.min_damage_x100)), 0
        damage = (on_shield - shield) * 10000 // shield_mult_bp
        shield = 0
        if damage <= 0:
            return 0, 0
    armor = armor * (10000 - pierce_bp) // 10000
    reduction = min(armor * 10000 // (armor + rules.armor_constant), rules.max_reduction_bp)
    return shield, max(damage * (10000 - reduction) // 10000, rules.min_damage_x100)


def run(case, credits_trace: list | None = None, bot=None) -> Result:
    """Plays a battle (a tools/sim_cases.Case that the core accepts). With
    credits_trace, appends the credits (x100) at the start of every tick, before
    its commands. With bot, calls bot(tick, credits_x100) at the start of every
    tick; the commands it returns apply after the case's own for that tick, as
    if queued live, and land in result.bot_commands. Both are for tools that
    plan play (tools/wave_pressure.py); neither changes a rule."""
    paths = []
    for lane in case.lanes:
        ground = build_path(lane.ground)
        air = build_path(lane.air) if lane.air else None
        if ground is None or (lane.air and air is None):
            raise ValueError("the model only plays battles the core accepts")
        paths.append((ground, air))
    enemies, towers_cfg, up, rules = case.enemies, case.towers, case.upgrades, case.rules

    rng = Rng(case.seed)
    plan = []  # (spawn tick, plan position, group)
    for group in case.groups:
        for n in range(group.count):
            jitter = rng.range_int(0, group.jitter_ticks) if group.jitter_ticks > 0 else 0
            plan.append((group.first_tick + n * group.interval_ticks + jitter, len(plan), group))
    plan.sort()
    rng_words = list(rng.s)  # nothing else draws from the generator in sim version 2

    # Waves (D-036): each one's start now, its aliens not yet resolved, whether one leaked, and whether it's done.
    starts = list(case.wave_starts)
    pending = [sum(g.count for g in case.groups if g.wave_index == w) for w in range(len(starts))]
    leaked_wave = [0] * len(starts)
    done = [0] * len(starts)
    tiles = {tile: i for i, tile in enumerate(case.build_tiles)}
    on_tile: dict[tuple[int, int], int] = {}  # tile -> tower id
    aliens: list[Alien] = []
    towers: list[Tower] = []
    s = {"tick": 0, "next_id": 1, "next_tower": 1, "plan": 0, "cmd": 0, "spawned": 0, "leaked": 0,
         "leaked_lives": 0, "lives": case.lives, "credits": case.credits * 100, "kills": 0, "refused": 0, "updates": 0}

    def new_alien(enemy_index: int, lane_index: int, hp_bp: int, credits_bp: int, distance: int, wave: int) -> None:
        e = enemies[enemy_index]
        ground, air = paths[lane_index]
        path = air if e.air else ground
        if path is None:
            raise ValueError("an air alien needs an air route")
        a = Alien(
            id=s["next_id"], type_index=enemy_index, lane_index=lane_index, class_index=e.class_index, air=e.air,
            path=path, speed=e.speed_mtps, hp=max(1, min(e.hp_x100 * hp_bp // 10000, MAX_STAT)), max_hp=0,
            shield=e.shield_x100, max_shield=e.shield_x100, lives=e.leak_lives,
            kill_credits=min(e.kill_credits_x100 * credits_bp // 10000, MAX_STAT), hp_bp=hp_bp, credits_bp=credits_bp,
            last_hit=s["tick"], distance=distance, wave=wave,
        )
        a.max_hp = a.hp
        a.x, a.y = path.position(distance)
        s["next_id"] += 1
        s["spawned"] += 1
        aliens.append(a)

    def hittable(t, a: Alien) -> bool:
        return t.rating_bp[a.class_index] > 0 and (a.class_index != CLOAKED or t.unrevealed_bp > 0)

    def in_reach(x: int, y: int, a: Alien, radius: int) -> bool:
        return (a.x - x) ** 2 + (a.y - y) ** 2 <= radius * radius

    released: list[Alien] = []

    def hit(tower: Tower, t, a: Alien) -> None:
        a.last_hit = s["tick"]
        a.regen = 0
        a.shield, hull = hit_result(level_damage(t, up, tower.level), t.rating_bp[a.class_index], a.class_index == CLOAKED,
                                    t.unrevealed_bp, a.shield, t.shield_mult_bp, enemies[a.type_index].armor,
                                    t.pierce_bp, rules)
        a.hp -= hull
        if hull and a.hp <= 0:
            a.dead = True
            s["credits"] += a.kill_credits
            s["kills"] += 1
            pending[a.wave] -= 1
            if enemies[a.type_index].release_index >= 0:
                released.append(a)

    def state_hash(outcome: int) -> str:
        out = bytearray()

        def add(v: int) -> None:
            out.extend(struct.pack("<q", v))

        add(MODEL_SIM_VERSION)
        text = case.config_hash.encode("utf-8")
        add(len(text))
        out.extend(text)
        for v in (case.seed, s["tick"], outcome, *rng_words, s["next_id"], s["plan"], s["spawned"], s["leaked"],
                  s["leaked_lives"], s["lives"], s["credits"], s["kills"], s["refused"], s["cmd"], s["next_tower"],
                  len(towers)):
            add(v)
        for t in towers:
            for v in (t.id, t.type_index, t.level, t.col, t.row, t.charge, t.target, t.next_pick, t.spent):
                add(v)
        add(len(aliens))
        for a in aliens:
            for v in (a.id, a.type_index, a.lane_index, int(a.air), a.distance, a.remainder, a.hp, a.shield, a.x, a.y,
                      a.regen, a.last_hit, a.kill_credits, a.hp_bp, a.credits_bp, a.wave):
                add(v)
        add(len(starts))
        for w in range(len(starts)):
            for v in (starts[w], pending[w], leaked_wave[w], done[w]):
                add(v)
        return hashlib.sha256(bytes(out)).hexdigest()

    def apply_command(cmd, c: int) -> None:
        if cmd.kind == CALL_WAVE:
            waiting = [w for w in range(len(starts)) if starts[w] > c]
            if not waiting:
                s["refused"] += 1
                return
            nxt = min(waiting, key=lambda w: (starts[w], w))
            skip = starts[nxt] - c
            for w in waiting:
                starts[w] -= skip
            rest = [(t - skip if grp.wave_index in waiting else t, pos, grp) for t, pos, grp in plan[s["plan"]:]]
            plan[s["plan"]:] = sorted(rest, key=lambda e: (e[0], e[1]))
            s["credits"] += min(skip * case.call_credits_per_s * 100 // TICK_RATE, case.call_credits_max * 100)
            return
        tile = (cmd.col, cmd.row)
        assert tile in tiles, "the model only plays battles the core accepts"
        occupant = on_tile.get(tile)
        tower = next((t for t in towers if t.id == occupant), None)
        if cmd.kind == PLACE:
            cost = towers_cfg[cmd.tower_index].cost_credits * 100
            if tower is not None or s["credits"] < cost:
                s["refused"] += 1
                return
            towers.append(Tower(id=s["next_tower"], type_index=cmd.tower_index, col=cmd.col, row=cmd.row, spent=cost))
            on_tile[tile] = s["next_tower"]
            s["next_tower"] += 1
            s["credits"] -= cost
        elif cmd.kind == UPGRADE:
            if tower is None or tower.level >= up.max_level:
                s["refused"] += 1
                return
            cost = upgrade_cost(towers_cfg[tower.type_index], up, tower.level)
            if s["credits"] < cost:
                s["refused"] += 1
                return
            s["credits"] -= cost
            tower.spent += cost
            tower.level += 1
        else:
            if tower is None:
                s["refused"] += 1
                return
            s["credits"] += tower.spent * up.sell_refund_bp // 10000
            towers.remove(tower)
            del on_tile[tile]

    checkpoints: list[str] = []
    outcome = RUNNING
    reuse_had_aliens = None
    bot_log: list = []
    while outcome == RUNNING:
        c = s["tick"]
        if credits_trace is not None:
            credits_trace.append(s["credits"])
        # 1. Commands: the case's for this tick, then any the bot sends
        todo = []
        while s["cmd"] < len(case.commands) and case.commands[s["cmd"]].tick == c:
            todo.append(case.commands[s["cmd"]])
            s["cmd"] += 1
        if bot is not None:
            sent = list(bot(c, s["credits"]))
            bot_log.extend(sent)
            todo.extend(sent)
        for cmd in todo:
            apply_command(cmd, c)
        # 2. Spawns
        while s["plan"] < len(plan) and plan[s["plan"]][0] <= c:
            group = plan[s["plan"]][2]
            new_alien(group.enemy_index, group.lane_index, group.hp_bp, group.credits_bp, 0, group.wave_index)
            s["plan"] += 1
        s["updates"] += len(aliens)
        # 3. Moves
        for a in aliens:
            a.remainder += a.speed
            a.distance += a.remainder // TICK_RATE
            a.remainder %= TICK_RATE
            if a.distance >= a.path.length:
                a.distance = a.path.length
                s["leaked"] += 1
                s["leaked_lives"] += a.lives
                s["lives"] = max(0, s["lives"] - a.lives)
                pending[a.wave] -= 1
                leaked_wave[a.wave] = 1
                a.dead = True  # gone from the field
            a.x, a.y = a.path.position(a.distance)
        aliens[:] = [a for a in aliens if not a.dead]
        # 4. Shield regen
        if rules.regen_per_second_x100:
            for a in aliens:
                if a.shield < a.max_shield and c - a.last_hit >= rules.regen_delay_ticks:
                    a.regen += rules.regen_per_second_x100
                    a.shield += a.regen // TICK_RATE
                    a.regen %= TICK_RATE
                    if a.shield >= a.max_shield:
                        a.shield, a.regen = a.max_shield, 0
        # 5. Towers
        for tower in towers:
            t = towers_cfg[tower.type_index]
            reach = level_range(t, up, tower.level)
            if tower.charge >= SHOT_CHARGE:
                target = None
                if tower.target and c < tower.next_pick:
                    kept = next((a for a in aliens if a.id == tower.target), None)
                    if kept and not kept.dead and hittable(t, kept) and in_reach(tower.x, tower.y, kept, reach):
                        target = kept
                if target is None:
                    choices = [a for a in aliens if not a.dead and hittable(t, a) and in_reach(tower.x, tower.y, a, reach)]
                    if t.targeting == STRONGEST:
                        target = min(choices, key=lambda a: (-(a.max_hp + a.max_shield), a.path.length - a.distance, a.id),
                                     default=None)
                    else:
                        target = min(choices, key=lambda a: (a.path.length - a.distance, a.id), default=None)
                    tower.next_pick = c + rules.retarget_ticks
                    tower.target = target.id if target else 0
                if target is not None:
                    tower.charge -= SHOT_CHARGE
                    if t.splash_mt:
                        x, y = target.x, target.y
                        for a in [a for a in aliens if not a.dead and hittable(t, a) and in_reach(x, y, a, t.splash_mt)]:
                            if not a.dead:
                                hit(tower, t, a)
                    else:
                        hit(tower, t, target)
            tower.charge = min(tower.charge + t.shots_per_s_x100, SHOT_CHARGE)
        # 6. Released aliens join; the dead leave
        for a in released:
            e = enemies[a.type_index]
            for _ in range(e.release_count):
                new_alien(e.release_index, a.lane_index, a.hp_bp, a.credits_bp, a.distance, a.wave)
            pending[a.wave] += e.release_count
        released.clear()
        aliens[:] = [a for a in aliens if not a.dead]
        # 6b. Waves finish, in index order: a clean one pays its bonus.
        for w in range(len(starts)):
            if not done[w] and pending[w] == 0:
                done[w] = 1
                if not leaked_wave[w]:
                    s["credits"] += case.clean_wave_credits * 100
        # 7. The counter, checkpoints and the outcome
        s["tick"] += 1
        if s["tick"] % CHECKPOINT_TICKS == 0:
            checkpoints.append(state_hash(RUNNING)[:16])
        if s["lives"] <= 0:
            outcome = LOST
        elif s["plan"] >= len(plan) and not aliens:
            outcome = CLEARED
        elif s["tick"] >= case.max_ticks:
            outcome = TIMED_OUT
        if reuse_had_aliens is None and outcome == RUNNING and s["tick"] >= 50 and aliens:
            reuse_had_aliens = True
    if reuse_had_aliens is None:
        reuse_had_aliens = bool(aliens)

    return Result(
        outcome=OUTCOMES[outcome], ticks=s["tick"], final_hash=state_hash(outcome), checkpoints=checkpoints,
        lives=s["lives"], credits_x100=s["credits"], kills=s["kills"], spawned=s["spawned"], leaked=s["leaked"],
        leaked_lives=s["leaked_lives"], refused=s["refused"], entity_updates=s["updates"],
        reuse_had_aliens=reuse_had_aliens, bot_commands=bot_log,
    )
