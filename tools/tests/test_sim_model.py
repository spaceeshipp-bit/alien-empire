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


def test_closed_form_movement_matches_stepping():
    """The model's closed form against the rule stepped literally: carry the remainder, move whole mt."""
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


def test_a_battle_with_no_aliens_clears_on_the_first_tick():
    bundle = json.loads((GOLDEN / "config_bundle.json").read_text(encoding="utf-8"))
    spec = {"battle_id": "empty", "mode": "pve", "seed": 1, "max_ms": 50_000,
            "map": {"lanes": [{"id": "a", "ground": [[0, 0], [0, 1000]]}]}, "waves": [], "commands": []}
    result = sim_model.run(sim_cases.case_from_spec(bundle, spec))
    assert (result.outcome, result.ticks, result.spawned, result.checkpoints) == ("cleared", 1, 0, [])


def test_checkpoints_say_running_even_on_the_last_tick():
    """The core hashes a checkpoint before it decides the outcome."""
    bundle = json.loads((GOLDEN / "config_bundle.json").read_text(encoding="utf-8"))
    spec = {"battle_id": "t", "mode": "pve", "seed": 1, "max_ms": 5_000,  # times out on tick 100
            "map": {"lanes": [{"id": "a", "ground": [[0, 0], [0, 1_000_000]]}]},
            "waves": [{"start_ms": 0, "groups": [{"enemy": "swarmer", "lane": "a", "count": 1,
                                                    "offset_ms": 0, "interval_ms": 0, "jitter_ms": 0}]}],
            "commands": []}
    result = sim_model.run(sim_cases.case_from_spec(bundle, spec))
    assert result.outcome == "timed_out" and result.ticks == 100 and len(result.checkpoints) == 1
    assert result.checkpoints[0] != result.final_hash[:16]  # same tick, different outcome
