"""tools/sim_cases.py: generated battles and shrinking."""
import dataclasses
import json
from pathlib import Path

import sim_cases
from reference import sim_model

GOLDEN = Path(__file__).resolve().parent.parent.parent / "sim" / "tests" / "golden"
BUNDLE = json.loads((GOLDEN / "config_bundle.json").read_text(encoding="utf-8"))


def test_a_case_rebuilds_from_its_seed_and_index():
    assert sim_cases.random_case(5, 17, BUNDLE) == sim_cases.random_case(5, 17, BUNDLE)
    assert sim_cases.random_case(5, 17, BUNDLE) != sim_cases.random_case(5, 18, BUNDLE)
    assert sim_cases.random_case(5, 17, BUNDLE) != sim_cases.random_case(6, 17, BUNDLE)


def test_every_profile_appears_in_any_ten_cases():
    for start in (0, 3, 7):
        profiles = {sim_cases.random_case(1, i, BUNDLE).profile for i in range(start, start + 10)}
        assert profiles == set(sim_cases.PROFILE_CYCLE)


def test_valid_cases_stay_inside_the_loader_limits():
    """Every valid case is one sim/core/battle_spec.gd and sim_config.gd would accept,
    so the core must accept and play it."""
    seen_air = seen_timeout = seen_jitter = 0
    for i in range(400):
        case = sim_cases.random_case(9, i, BUNDLE)
        if not case.valid:
            continue
        assert 0 <= case.seed <= sim_cases.MAX_SEED
        assert 1 <= case.max_ticks <= sim_cases.MAX_BATTLE_MS // 50
        for e in case.enemies:
            assert 1 <= e.hp_x100 <= sim_cases.MAX_STAT and 0 <= e.armor <= sim_cases.MAX_STAT
            assert 0 <= e.shield_x100 <= sim_cases.MAX_STAT and 1 <= e.speed_mtps <= sim_cases.MAX_STAT
            assert 1 <= e.leak_lives <= sim_cases.MAX_STAT
        for lane in case.lanes:
            for x, y in lane.ground + lane.air:
                assert 0 <= x <= sim_cases.MAX_COORD_MT and 0 <= y <= sim_cases.MAX_COORD_MT
            assert sim_model.build_path(lane.ground) is not None
            assert not lane.air or sim_model.build_path(lane.air) is not None
        for g in case.groups:
            assert 1 <= g.count <= sim_cases.MAX_GROUP_COUNT
            assert 0 <= g.first_tick <= 2 * (sim_cases.MAX_BATTLE_MS // 50)
            assert 0 <= g.interval_ticks <= sim_cases.MAX_BATTLE_MS // 50
            assert 0 <= g.jitter_ticks <= sim_cases.MAX_BATTLE_MS // 50
            if case.enemies[g.enemy_index].air:
                assert case.lanes[g.lane_index].air
                seen_air += 1
            seen_jitter += g.jitter_ticks > 0
        result = sim_model.run(case)
        seen_timeout += result.outcome == "timed_out"
    assert seen_air and seen_timeout and seen_jitter  # the generator reaches each kind of battle


def test_invalid_cases_say_what_they_break():
    invalid = [c for c in (sim_cases.random_case(2, i, BUNDLE) for i in range(200)) if not c.valid]
    assert len(invalid) == 20
    assert all(c.broken for c in invalid)
    assert len({c.broken.split()[0] for c in invalid}) >= 4  # several kinds of limit


def test_shrink_keeps_only_what_the_failure_needs():
    case = sim_cases.random_case(4, 0, BUNDLE)
    assert len(case.groups) > 1 or case.groups[0].count > 3

    def still_fails(c):  # stands in for "the core and the model disagree"
        return any(g.count >= 3 for g in c.groups)

    small = sim_cases.shrink(dataclasses.replace(case, groups=case.groups + (dataclasses.replace(case.groups[0], count=40),)),
                             still_fails)
    assert len(small.groups) == 1 and 3 <= small.groups[0].count <= 5
    assert small.max_ticks == 1 and small.seed == 0
    assert small.groups[0].jitter_ticks == 0 and small.groups[0].interval_ticks == 0 and small.groups[0].first_tick == 0


def test_specs_convert_to_ticks_the_way_the_loader_reads_them():
    spec = json.loads((GOLDEN / "scenarios" / "g02_bends_and_jitter.json").read_text(encoding="utf-8"))
    case = sim_cases.case_from_spec(BUNDLE, spec)
    enemy_ids = sorted(e["id"] for e in BUNDLE["data"]["enemies"]["enemies"])
    second_wave = spec["waves"][1]["groups"][1]  # phaser: start 12000 ms, offset 1000 ms
    g = case.groups[3]
    assert enemy_ids[g.enemy_index] == second_wave["enemy"] == "phaser"
    assert (g.first_tick, g.interval_ticks, g.jitter_ticks) == ((12000 + 1000) // 50, 600 // 50, 300 // 50)
    assert case.max_ticks == spec["max_ms"] // 50
