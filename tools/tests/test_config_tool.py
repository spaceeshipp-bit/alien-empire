"""Tests for tools/config_tool.py: schema, cross-file rules, bundles and battle specs.

These tests check structure and rules, never specific balance numbers, so the
owner can retune any value without touching a test.
"""
import copy
import json

import pytest

import config_tool as ct


@pytest.fixture(scope="module")
def registry():
    return ct.schema_registry()


@pytest.fixture()
def data():
    return ct.load_balance()


def tower(data, tid):
    return next(t for t in data["towers"]["towers"] if t["id"] == tid)


def enemy(data, eid):
    return next(e for e in data["enemies"]["enemies"] if e["id"] == eid)


def test_balance_config_is_valid(data, registry):
    assert ct.validate_balance(data, registry) == []


def test_every_class_appears_in_every_counter_row(data):
    for row in data["counters"]["counters"].values():
        assert sorted(row) == sorted(ct.CLASSES)


def test_decimal_numbers_are_rejected(tmp_path):
    path = tmp_path / "bad.json"
    path.write_text('{"value": 1.5}', encoding="utf-8")
    with pytest.raises(ct.ConfigError, match="integer units"):
        ct.load_json(path)


def test_schema_rejects_unknown_field(data, registry):
    tower(data, "railgun")["dps"] = 25
    errors = ct.validate_balance(data, registry)
    assert any("Additional properties" in e for e in errors)


def test_schema_rejects_ms_off_the_tick_grid(data, registry):
    data["status_effects"]["reveal"]["linger_ms"] = 3025
    errors = ct.validate_balance(data, registry)
    assert any("reveal/linger_ms" in e and "multiple of 50" in e for e in errors)


def test_missing_counter_row(data, registry):
    del data["counters"]["counters"]["railgun"]
    assert "counters: no row for attacking tower railgun" in ct.validate_balance(data, registry)


def test_counter_row_for_unknown_tower(data, registry):
    data["counters"]["counters"]["laser"] = copy.deepcopy(data["counters"]["counters"]["railgun"])
    assert "counters: row for unknown tower laser" in ct.validate_balance(data, registry)


def test_support_tower_must_not_have_counter_row(data, registry):
    data["counters"]["counters"]["sensor_beacon"] = copy.deepcopy(data["counters"]["counters"]["railgun"])
    assert "counters: support tower sensor_beacon must not have a row" in ct.validate_balance(data, registry)


def test_attacking_tower_needs_fire_rate_and_damage_type(data, registry):
    rail = tower(data, "railgun")
    rail["shots_per_s_x100"] = 0
    rail["damage_type"] = "none"
    errors = ct.validate_balance(data, registry)
    assert "towers: railgun deals damage but has shots_per_s_x100 0" in errors
    assert "towers: railgun deals damage but has damage_type none" in errors


def test_cant_hit_cloaked_means_no_unrevealed_damage(data, registry):
    data["counters"]["counters"]["flak_battery"]["cloaked"]["unrevealed_damage_bp"] = 5000
    errors = ct.validate_balance(data, registry)
    assert "counters: flak_battery can't hit cloaked, so unrevealed_damage_bp must be 0" in errors


def test_duplicate_ids(data, registry):
    data["enemies"]["enemies"].append(copy.deepcopy(enemy(data, "swarmer")))
    assert "enemies: duplicate id swarmer" in ct.validate_balance(data, registry)


def test_air_class_and_movement_must_match(data, registry):
    enemy(data, "skimmer")["movement"] = "ground"
    errors = ct.validate_balance(data, registry)
    assert "enemies: skimmer must use air movement if and only if its class is air" in errors


def test_spawn_on_death_unknown_enemy(data, registry):
    enemy(data, "hive_carrier")["abilities"][0]["enemy"] = "nope"
    assert "enemies: hive_carrier spawns unknown enemy nope" in ct.validate_balance(data, registry)


def test_spawn_on_death_cycle(data, registry):
    enemy(data, "swarmer")["abilities"] = [{"type": "spawn_on_death", "enemy": "hive_carrier", "count": 1}]
    errors = ct.validate_balance(data, registry)
    assert "enemies: swarmer spawns itself through spawn_on_death" in errors
    assert "enemies: hive_carrier spawns itself through spawn_on_death" in errors


def test_bonus_pool_thresholds_in_order(data, registry):
    data["damage"]["bonus_pool"]["full_value_until_bp"] = 9500
    errors = ct.validate_balance(data, registry)
    assert "damage: bonus_pool.full_value_until_bp must not exceed partial_value_until_bp" in errors


def test_bundle_round_trip(data, registry):
    bundle = ct.make_bundle(data)
    assert ct.check_bundle(bundle, registry) == []
    bundle["data"]["towers"]["towers"][0]["cost_credits"] += 1
    errors = ct.check_bundle(bundle, registry)
    assert any("config_hash is" in e for e in errors)


def test_bundle_hash_ignores_key_order(data):
    reordered = json.loads(json.dumps(data, sort_keys=True))
    reordered = {k: reordered[k] for k in reversed(list(reordered))}
    assert ct.make_bundle(data)["config_hash"] == ct.make_bundle(reordered)["config_hash"]


def minimal_battle():
    return {
        "battle_id": "t",
        "mode": "pve",
        "seed": 1,
        "max_ms": 10000,
        "lives": 20,
        "credits": 300,
        "towers": ["pulse_turret"],
        "call_credits_per_s": 1,
        "call_credits_max": 15,
        "clean_wave_credits": 10,
        "map": {"lanes": [{"id": "a", "ground": [[0, 0], [0, 5000]]}], "build_tiles": [[1, 2]]},
        "waves": [
            {
                "start_ms": 0,
                "hp_bp": 10000,
                "credits_bp": 10000,
                "groups": [
                    {"enemy": "swarmer", "lane": "a", "count": 2, "offset_ms": 0, "interval_ms": 500, "jitter_ms": 0}
                ],
            }
        ],
        "commands": [{"tick": 0, "type": "place", "args": {"tower": "pulse_turret", "tile": [1, 2]}}],
    }


def test_minimal_battle_is_valid(data, registry):
    spec = minimal_battle()
    assert ct.schema_errors("battle", spec, registry, "t") == []
    assert ct.check_battle(spec, data) == []


def test_battle_seed_must_fit_json_integers(registry):
    spec = minimal_battle()
    spec["seed"] = 2**53
    assert ct.schema_errors("battle", spec, registry, "t")


def test_battle_reference_errors(data):
    spec = minimal_battle()
    group = spec["waves"][0]["groups"][0]
    group["enemy"] = "skimmer"
    spec["map"]["lanes"][0]["ground"].append([0, 5000])
    spec["towers"] = ["pulse_turret", "laser_fence"]
    spec["map"]["build_tiles"].append([1, 2])
    spec["commands"] = [
        {"tick": 5, "type": "place", "args": {"tower": "railgun", "tile": [1, 2]}},
        {"tick": 2, "type": "upgrade", "args": {"tile": [7, 7]}},
        {"tick": 200, "type": "sell", "args": {"tile": [1, 2]}},
    ]
    errors = ct.check_battle(spec, data)
    assert "t: wave 0 group 0: air enemy skimmer needs an air path on lane a" in errors
    assert "t: lane a ground path repeats point [0, 5000]" in errors
    assert "t: commands must be in tick order" in errors
    assert "t: unknown tower laser_fence" in errors
    assert "t: a build tile is listed twice" in errors
    assert "t: command 0: tower railgun isn't allowed in this battle" in errors
    assert "t: command 1: [7, 7] isn't a build tile" in errors
    assert "t: command 2: tick 200 is at or after the battle's last tick" in errors


def test_battle_schema_checks_command_arguments(registry):
    spec = minimal_battle()
    spec["commands"] = [{"tick": 0, "type": "sell", "args": {"tile": [1, 2], "tower": "pulse_turret"}}]
    assert ct.schema_errors("battle", spec, registry, "t")
    spec["commands"] = [{"tick": 0, "type": "place", "args": {"tile": [1, 2]}}]
    assert ct.schema_errors("battle", spec, registry, "t")
    spec["commands"] = [{"tick": 0, "type": "launch", "args": {"tile": [1, 2]}}]
    assert ct.schema_errors("battle", spec, registry, "t")


def test_battle_unknown_enemy_and_lane(data):
    spec = minimal_battle()
    spec["waves"][0]["groups"][0].update(enemy="ghost", lane="b")
    errors = ct.check_battle(spec, data)
    assert "t: wave 0 group 0: unknown enemy ghost" in errors
    assert "t: wave 0 group 0: unknown lane b" in errors


def test_cli_validate(capsys):
    assert ct.main(["validate"]) == 0
    assert "config OK" in capsys.readouterr().out


def test_releases_are_one_level_and_once(data, registry):
    """A release that releases again could multiply aliens without limit (D-034)."""
    chained = copy.deepcopy(data)
    swarmer = next(e for e in chained["enemies"]["enemies"] if e["id"] == "swarmer")
    swarmer["abilities"] = [{"type": "spawn_on_death", "enemy": "swarmer", "count": 1}]
    assert any("releases others" in e for e in ct.validate_balance(chained, registry))
    twice = copy.deepcopy(data)
    carrier = next(e for e in twice["enemies"]["enemies"] if e["id"] == "hive_carrier")
    carrier["abilities"].append({"type": "spawn_on_death", "enemy": "swarmer", "count": 1})
    assert "enemies: hive_carrier lists an ability twice" in ct.validate_balance(twice, registry)
