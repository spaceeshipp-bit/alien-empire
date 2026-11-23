"""tools/reference/sim_model.py: the independent model the C++ core is checked against."""
import json
import random
from pathlib import Path

import pytest

import sim_cases
from reference import sim_model

GOLDEN = Path(__file__).resolve().parent.parent.parent / "sim" / "tests" / "golden"


def test_model_reproduces_the_recorded_goldens():
    """The goldens were recorded by the core; the model, written another way, must agree exactly."""
    expected_path = GOLDEN / "expected.json"
    if not expected_path.exists():
        pytest.skip("expected.json is being re-recorded (D-008)")
    bundle = json.loads((GOLDEN / "config_bundle.json").read_text(encoding="utf-8"))
    expected = json.loads(expected_path.read_text(encoding="utf-8"))["scenarios"]
    assert expected
    for name, want in expected.items():
        spec = json.loads((GOLDEN / "scenarios" / f"{name}.json").read_text(encoding="utf-8"))
        got = sim_model.run(sim_cases.case_from_spec(bundle, spec, name))
        assert (got.outcome, got.ticks, got.final_hash, got.checkpoints) == (
            want["outcome"], want["ticks"], want["final_hash"], want["checkpoints"]), name
        assert (got.lives, got.credits_x100, got.kills, got.leaked, got.refused, got.spawned) == (
            want["lives"], want["credits_x100"], want["kills"], want["leaked"], want["refused"], want["spawned"]), name


def test_closed_form_movement_matches_stepping():
    """Movement stepped literally (carry the remainder, move whole mt) has a closed
    form: after k moves, k * speed // 20 mt, and it leaks on move ceil(20 * length / speed)."""
    pick = random.Random(11)
    for _ in range(3000):
        speed = pick.choice((1, 7, 19, 20, 21, pick.randint(1, 5000), pick.randint(1, 10**9)))
        length = pick.randint(1, 50_000)
        moved, carry, k = 0, 0, 0
        while True:
            k += 1
            carry += speed
            step = carry // sim_model.TICK_RATE
            carry -= step * sim_model.TICK_RATE
            moved += step
            if moved >= length:
                break
            assert moved == k * speed // 20 and carry == k * speed % 20
            if k > 2000:
                break
        if moved >= length:
            assert k == -(-20 * length // speed), (speed, length)


def test_division_truncates_toward_zero():
    assert [sim_model.tdiv(a, b) for a, b in ((7, 2), (-7, 2), (7, -2), (-7, -2), (0, 5), (-1, 3))] == [3, -3, -3, 3, 0, 0]


def test_paths_drop_repeated_points_and_need_two():
    path = sim_model.build_path([(0, 0), (0, 0), (3, 4), (3, 4), (3, 10)])
    assert path.xs == (0, 3, 3) and path.ys == (0, 4, 10) and path.starts == (0, 5, 11)
    assert sim_model.build_path([(5, 5), (5, 5)]) is None
    assert sim_model.build_path([(5, 5)]) is None


def test_positions_truncate_toward_zero_on_falling_segments():
    # Segment (10, 0) -> (0, 7): length isqrt(149) = 12. At 5 along, x moves -50 / 12:
    # truncating gives -4 (x = 6), where flooring would give -5 (x = 5).
    path = sim_model.build_path([(10, 0), (0, 7)])
    assert path.length == 12
    assert path.position(5) == (6, 2)
    assert path.position(0) == (10, 0) and path.position(12) == (0, 7) and path.position(99) == (0, 7)


def _bundle() -> dict:
    return json.loads((GOLDEN / "config_bundle.json").read_text(encoding="utf-8"))


def _spec(groups=(), lane_end=1000, **extra) -> dict:
    spec = {"battle_id": "t", "mode": "pve", "seed": 1, "max_ms": 50_000, "lives": 20, "credits": 0, "towers": [],
            "call_credits_per_s": 0, "call_credits_max": 0, "clean_wave_credits": 0,
            "map": {"lanes": [{"id": "a", "ground": [[0, 0], [0, lane_end]]}], "build_tiles": []},
            "waves": [{"start_ms": 0, "hp_bp": 10000, "credits_bp": 10000, "groups": list(groups)}] if groups else [],
            "commands": []}
    spec.update(extra)
    return spec


def _group(enemy="swarmer", count=1, **extra) -> dict:
    return {"enemy": enemy, "lane": "a", "count": count, "offset_ms": 0, "interval_ms": 0, "jitter_ms": 0, **extra}


def test_a_battle_with_no_aliens_clears_on_the_first_tick():
    result = sim_model.run(sim_cases.case_from_spec(_bundle(), _spec()))
    assert (result.outcome, result.ticks, result.spawned, result.checkpoints) == ("cleared", 1, 0, [])


def test_checkpoints_say_running_even_on_the_last_tick():
    """The core hashes a checkpoint before it decides the outcome."""
    spec = _spec([_group()], lane_end=1_000_000, max_ms=5_000)  # times out on tick 100
    result = sim_model.run(sim_cases.case_from_spec(_bundle(), spec))
    assert result.outcome == "timed_out" and result.ticks == 100 and len(result.checkpoints) == 1
    assert result.checkpoints[0] != result.final_hash[:16]  # same tick, different outcome


# The damage pipeline with the build prompt's numbers (D-034), one case per step and floor.
RULES = sim_cases.Rules()  # the build prompt's: armor constant 100, 60% cap, 1-point floor


def test_railgun_pierces_the_brutes_armor():
    # 50 damage, Strong (1.5) against armor 150, of which it ignores 75%: armor 37,
    # reduction 37 / 137 = 27.00% (2700 bp), hull damage 75 x 0.73 = 54.75.
    assert sim_model.hit_result(5000, 15000, False, 0, 0, 10000, 150, 7500, RULES) == (0, 5475)


def test_armor_reduction_is_capped_at_sixty_percent():
    # The Pulse Turret (10, Weak 0.5) against armor 150 sits exactly on the cap: 150 / 250.
    assert sim_model.hit_result(1000, 5000, False, 0, 0, 10000, 150, 0, RULES) == (0, 200)
    # Armor 1000 would reduce 90.9%; the cap keeps it at 60%.
    assert sim_model.hit_result(1000, 10000, False, 0, 0, 10000, 1000, 0, RULES) == (0, 400)


def test_every_hit_deals_at_least_one_point():
    assert sim_model.hit_result(50, 10000, False, 0, 0, 10000, 0, 0, RULES) == (0, 100)
    assert sim_model.hit_result(10, 10000, False, 0, 24000, 5000, 0, 0, RULES) == (23900, 0)  # on the shield


def test_thermal_does_half_to_shields():
    # The Plasma Torch (5, Neutral) against the Shield Drone's 240-point shield.
    assert sim_model.hit_result(500, 10000, False, 0, 24000, 5000, 20, 0, RULES) == (23750, 0)


def test_a_broken_shield_passes_the_excess_to_the_hull():
    # 300 EMP damage x3 = 900 on a 240 shield: 660 left over is 220 raw damage,
    # then armor 20 takes 16.66% off: 183.34.
    assert sim_model.hit_result(30000, 10000, False, 0, 24000, 30000, 20, 0, RULES) == (0, 18334)
    # Exactly the shield: it breaks and nothing reaches the hull.
    assert sim_model.hit_result(24000, 10000, False, 0, 24000, 10000, 20, 0, RULES) == (0, 0)


def test_unrevealed_cloaked_aliens_take_the_unrevealed_share():
    # The Plasma Torch hits an unrevealed Phaser at 50%: 2.5, then armor 30 (23.07%).
    assert sim_model.hit_result(500, 10000, True, 5000, 0, 5000, 30, 0, RULES) == (0, 192)


def test_field_tower_levels_follow_the_build_prompt():
    bundle = _bundle()
    case = sim_cases.case_from_spec(bundle, _spec())
    pulse = case.towers[[t["id"] for t in sim_cases.bundle_towers(bundle)].index("pulse_turret")]
    up = case.upgrades
    # Damage x1.45 per level, each step truncated: 10, 14.5, 21.02, 30.47.
    assert [sim_model.level_damage(pulse, up, level) for level in (1, 2, 3, 4)] == [1000, 1450, 2102, 3047]
    # Upgrades cost 0.8 x the build cost, then x1.5 per level: 80, 120, 180.
    assert [sim_model.upgrade_cost(pulse, up, level) for level in (1, 2, 3)] == [8000, 12000, 18000]
    # Range +5% of the base range per level.
    assert [sim_model.level_range(pulse, up, level) for level in (1, 2, 3, 4)] == [3000, 3150, 3300, 3450]


def test_selling_refunds_seventy_percent_of_everything_spent():
    bundle = _bundle()
    commands = [{"tick": 0, "type": "place", "args": {"tower": "pulse_turret", "tile": [0, 0]}}]
    commands += [{"tick": t, "type": "upgrade", "args": {"tile": [0, 0]}} for t in (1, 2, 3)]
    commands.append({"tick": 4, "type": "sell", "args": {"tile": [0, 0]}})
    late = _group(offset_ms=40_000)
    spec = _spec([late], lane_end=100_000, credits=1000, towers=["pulse_turret"], commands=commands, max_ms=1000)
    spec["map"]["build_tiles"] = [[0, 0]]
    result = sim_model.run(sim_cases.case_from_spec(bundle, spec))
    # 100 + 80 + 120 + 180 = 480 spent; 70% back is 336.
    assert (result.credits_x100, result.refused) == ((1000 - 480 + 336) * 100, 0)


def test_towers_pick_the_alien_closest_to_the_core():
    """A fast alien that spawns later overtakes a slow one; the tower, placed after
    the overtake, kills the fast one first, though its id is higher."""
    slow = sim_cases.Enemy(100, 0, 0, 200, False, 1, kill_credits_x100=100)
    fast = sim_cases.Enemy(100, 0, 0, 2000, False, 1, kill_credits_x100=10000)
    gun = sim_cases.Tower(10, 10**6, 50, 100_000, 0, 10000, 0, (10000,) * 6, 0)
    case = sim_cases.Case(
        name="first", config_hash="0" * 64, config_version=1, enemies=(slow, fast), battle_id="first", seed=1,
        max_ticks=51, lanes=(sim_cases.Lane(((500, 0), (500, 100_000))),),
        groups=(sim_cases.Group(0, 0, 1, 0, 0, 0), sim_cases.Group(1, 0, 1, 40, 0, 0)),
        towers=(gun,), credits=10, tower_set=(0,), build_tiles=((0, 0),), wave_starts=(0,),
        commands=(sim_cases.Command(50, 1, 0, 0, 0),),  # by tick 50 the fast one leads, 1000 mt to 500
    )
    result = sim_model.run(case)
    assert (result.kills, result.credits_x100) == (1, 10000)


# Sim version 3 (D-036): Strongest targeting, calling a wave early, the clean-wave bonus.

def _duel(targeting: int):
    """A slow tough alien ahead, a fast weak one behind but in range: which does one shot hit?"""
    tough = sim_cases.Enemy(50_000, 0, 0, 100, False, 1, kill_credits_x100=0)
    weak = sim_cases.Enemy(100, 0, 0, 100, False, 1, kill_credits_x100=10_000)
    gun = sim_cases.Tower(10, 10**6, 50, 100_000, 0, 10000, 0, (10000,) * 6, 0, targeting=targeting)
    return sim_cases.Case(
        name="duel", config_hash="0" * 64, config_version=1, enemies=(tough, weak), battle_id="duel", seed=1,
        max_ticks=12, lanes=(sim_cases.Lane(((500, 0), (500, 100_000))),),
        groups=(sim_cases.Group(1, 0, 1, 0, 0, 0), sim_cases.Group(0, 0, 1, 5, 0, 0)),
        towers=(gun,), credits=10, tower_set=(0,), build_tiles=((0, 0),), wave_starts=(0,),
        commands=(sim_cases.Command(10, 1, 0, 0, 0),),
    )


def test_first_shoots_the_leader_and_strongest_the_toughest():
    # The weak one spawned first and leads: First kills it (10,000 credits); Strongest hits the tough one.
    assert sim_model.run(_duel(0)).credits_x100 == 10_000
    assert sim_model.run(_duel(1)).credits_x100 == 0


def test_strongest_finishes_the_alien_it_started_on():
    # Two of a kind a tick apart, a gun that kills in 2 shots and re-picks every shot.
    # By what's left it would switch to the fresh one after a hit; by full HP it stays
    # on the leader, so the second shot kills (one kill and its 100 credits).
    kind = sim_cases.Enemy(10_000, 0, 0, 100, False, 1, kill_credits_x100=10_000)
    gun = sim_cases.Tower(10, 6_000, 2_000, 100_000, 0, 10000, 0, (10000,) * 6, 0, targeting=1)
    case = sim_cases.Case(
        name="focus", config_hash="0" * 64, config_version=1, enemies=(kind,), battle_id="focus", seed=1,
        max_ticks=6, lanes=(sim_cases.Lane(((500, 0), (500, 100_000))),),
        groups=(sim_cases.Group(0, 0, 2, 0, 1, 0),), towers=(gun,), credits=10, tower_set=(0,),
        build_tiles=((0, 0),), wave_starts=(0,), commands=(sim_cases.Command(4, 1, 0, 0, 0),),
        rules=sim_cases.Rules(retarget_ticks=0),
    )
    result = sim_model.run(case)
    assert (result.kills, result.credits_x100) == (1, 10_000)


def _waves_case(commands, clean=0, per_s=1, cap=15, leak=False):
    swarmer = sim_cases.Enemy(100, 0, 0, 1000 if leak else 1, False, 1)
    return sim_cases.Case(
        name="waves", config_hash="0" * 64, config_version=1, enemies=(swarmer,), battle_id="waves", seed=1,
        max_ticks=4000, lanes=(sim_cases.Lane(((500, 0), (500, 1000))),),
        groups=(sim_cases.Group(0, 0, 1, 100, 0, 0, wave_index=0), sim_cases.Group(0, 0, 1, 400, 0, 0, wave_index=1),
                sim_cases.Group(0, 0, 1, 700, 0, 0, wave_index=2)),
        wave_starts=(100, 400, 700), commands=tuple(commands), call_credits_per_s=per_s, call_credits_max=cap,
        clean_wave_credits=clean, lives=100,
    )


def test_calling_a_wave_pays_per_second_skipped_up_to_the_cap():
    # At tick 50, wave 0 (tick 100) is 50 ticks away: 2.5 s at 1 credit a second pays 250 (x100).
    assert sim_model.run(_waves_case([sim_cases.Command(50, 4, -1, 0, 0)])).credits_x100 == 250
    # At tick 0 it's 5 s away; a cap of 3 credits pays 300.
    assert sim_model.run(_waves_case([sim_cases.Command(0, 4, -1, 0, 0)], cap=3)).credits_x100 == 300


def test_calling_moves_every_later_wave_and_refuses_when_none_is_left():
    early = sim_model.run(_waves_case([sim_cases.Command(0, 4, -1, 0, 0)], leak=True))
    late = sim_model.run(_waves_case([], leak=True))
    assert late.ticks - early.ticks == 100  # every wave came 100 ticks sooner
    refused = sim_model.run(_waves_case([sim_cases.Command(705, 4, -1, 0, 0)], leak=True))  # the last wave began at 700
    assert refused.refused == 1


def test_a_wave_that_leaks_pays_no_clean_bonus():
    # Nothing kills these aliens, so every wave leaks and nothing is paid.
    assert sim_model.run(_waves_case([], clean=10, leak=True)).credits_x100 == 0
