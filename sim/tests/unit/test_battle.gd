extends "res://sim/tests/test_case.gd"
## Battle skeleton tests. Where a test depends on a speed, it sets that speed
## itself, so retuning the config never breaks these tests.

const SimConfig := preload("res://sim/core/sim_config.gd")
const BattleSpec := preload("res://sim/core/battle_spec.gd")
const Battle := preload("res://sim/core/battle.gd")
const BUNDLE := "res://sim/tests/golden/config_bundle.json"


func _config(speeds: Dictionary = {}) -> SimConfig:
	var bundle: Dictionary = load_json(BUNDLE)
	for entry in bundle["data"]["enemies"]["enemies"]:
		if speeds.has(entry["id"]):
			entry["speed_mtps"] = speeds[entry["id"]]
	var config := SimConfig.new()
	expect_true(config.load_bundle(bundle), "config loads: %s" % str(config.errors))
	return config


## One lane straight down: ground route lane_mt long, air route half as long.
func _spec(groups: Array, lane_mt: int = 20000) -> Dictionary:
	return {
		"battle_id": "unit",
		"mode": "pve",
		"seed": 1,
		"max_ms": 600000,
		"map": {"lanes": [{
			"id": "a",
			"ground": [[1000, 0], [1000, lane_mt]],
			"air": [[2000, 0], [2000, lane_mt / 2]],
		}]},
		"waves": [{"start_ms": 0, "groups": groups}],
		"commands": [],
	}


func _group(enemy: String, count: int, interval_ms: int = 500, jitter_ms: int = 0) -> Dictionary:
	return {
		"enemy": enemy, "lane": "a", "count": count,
		"offset_ms": 0, "interval_ms": interval_ms, "jitter_ms": jitter_ms,
	}


func _battle(spec_data: Dictionary, config: SimConfig = null) -> Battle:
	var spec := BattleSpec.new()
	expect_true(spec.parse(spec_data), "spec parses: %s" % str(spec.errors))
	var battle := Battle.new()
	var use_config: SimConfig = config if config != null else _config()
	expect_true(battle.setup(use_config, spec), "battle sets up: %s" % str(battle.errors))
	return battle


## How many aliens had spawned after each of the first `ticks` ticks.
func _spawn_curve(spec_data: Dictionary, ticks: int) -> PackedInt64Array:
	var battle: Battle = _battle(spec_data)
	var curve := PackedInt64Array()
	for i in ticks:
		battle.advance()
		curve.append(battle.spawned_count)
	return curve


func test_same_inputs_same_result() -> bool:
	var spec_data: Dictionary = _spec([_group("swarmer", 20, 250, 500), _group("carapace_brute", 3, 2000, 1000)])
	var first: Dictionary = _battle(spec_data).run()
	var second: Dictionary = _battle(spec_data).run()
	expect_eq(second["final_hash"], first["final_hash"], "final hash")
	expect_eq(second["checkpoints"], first["checkpoints"], "checkpoints")
	expect_eq(second["ticks"], first["ticks"], "ticks")
	return true


func test_jitter_follows_the_seed() -> bool:
	var jittered: Dictionary = _spec([_group("swarmer", 20, 250, 500)])
	var curve_a: PackedInt64Array = _spawn_curve(jittered, 150)
	jittered["seed"] = 2
	var curve_b: PackedInt64Array = _spawn_curve(jittered, 150)
	expect_true(curve_a != curve_b, "different seeds move jittered spawns")
	var steady: Dictionary = _spec([_group("swarmer", 20, 250, 0)])
	var curve_c: PackedInt64Array = _spawn_curve(steady, 150)
	steady["seed"] = 2
	expect_eq(_spawn_curve(steady, 150), curve_c, "without jitter the seed changes nothing")
	return true


func test_jitter_stays_in_range() -> bool:
	var seen: Dictionary = {}
	for seed_value in range(1, 41):
		var spec_data: Dictionary = _spec([_group("swarmer", 1, 0, 500)])
		spec_data["seed"] = seed_value
		var battle: Battle = _battle(spec_data)
		var spawn_tick: int = -1
		for t in 12:
			battle.advance()
			if spawn_tick < 0 and battle.spawned_count == 1:
				spawn_tick = t
		expect_true(spawn_tick >= 0 and spawn_tick <= 10, "seed %d spawned at tick %d, outside 0..10" % [seed_value, spawn_tick])
		seen[spawn_tick] = true
	expect_true(seen.size() >= 4, "jitter spreads spawns over several ticks")
	return true


## 1234 mt/s doesn't divide by 20 ticks; the carried remainder keeps the total exact.
func test_uneven_speed_covers_exact_distance() -> bool:
	var battle: Battle = _battle(_spec([_group("swarmer", 1)], 100000), _config({"swarmer": 1234}))
	for i in 20:
		battle.advance()
	expect_eq(battle.aliens[0].distance_mt, 1234, "distance after 1 second")
	for i in 40:
		battle.advance()
	expect_eq(battle.aliens[0].distance_mt, 3702, "distance after 3 seconds")
	return true


func test_leak_costs_lives_and_clears() -> bool:
	var config: SimConfig = _config({"swarmer": 2000})
	var result: Dictionary = _battle(_spec([_group("swarmer", 1)], 2000), config).run()
	expect_eq(result["outcome"], "cleared", "outcome")
	expect_eq(result["ticks"], 20, "100 mt per tick over 2000 mt")
	expect_eq(result["leaked"], 1, "leaked")
	expect_eq(result["leaked_lives"], config.enemy("swarmer").leak_lives, "lives lost")
	return true


func test_ids_follow_spawn_order() -> bool:
	var battle: Battle = _battle(_spec([_group("carapace_brute", 2, 0), _group("swarmer", 2, 0)]))
	battle.advance()
	var ids: Array = []
	var types: Array = []
	for alien in battle.aliens:
		ids.append(alien.id)
		types.append(alien.type_index)
	var config: SimConfig = _config()
	var brute: int = config.enemy("carapace_brute").index
	var swarm: int = config.enemy("swarmer").index
	expect_eq(ids, [1, 2, 3, 4], "ids in spawn order")
	expect_eq(types, [brute, brute, swarm, swarm], "groups spawn in spec order")
	return true


func test_air_aliens_fly_the_air_route() -> bool:
	var config: SimConfig = _config({"skimmer": 2000})
	var result: Dictionary = _battle(_spec([_group("skimmer", 1)], 20000), config).run()
	expect_eq(result["ticks"], 100, "10,000 mt air route at 100 mt per tick")
	return true


func test_air_alien_needs_an_air_route() -> bool:
	var spec_data: Dictionary = _spec([_group("skimmer", 1)])
	var lane: Dictionary = spec_data["map"]["lanes"][0]
	lane.erase("air")
	var spec := BattleSpec.new()
	expect_true(spec.parse(spec_data), "the spec itself is fine")
	var battle := Battle.new()
	expect_true(not battle.setup(_config(), spec), "setup refuses an air alien on a lane without an air route")
	return true


func test_failed_setup_leaves_an_empty_battle() -> bool:
	var battle: Battle = _battle(_spec([_group("swarmer", 3)]))
	for i in 40:
		battle.advance()
	expect_true(battle.aliens.size() > 0, "aliens are on the lane before the second setup")
	var spec_data: Dictionary = _spec([_group("skimmer", 1)])
	var lane: Dictionary = spec_data["map"]["lanes"][0]
	lane.erase("air")
	var spec := BattleSpec.new()
	expect_true(spec.parse(spec_data), "the spec itself is fine")
	expect_true(not battle.setup(_config(), spec), "the second setup is refused")
	expect_eq(battle.aliens.size(), 0, "aliens left from the first battle")
	expect_eq(battle.tick, 0, "tick")
	expect_eq(battle.spawned_count, 0, "spawned")
	return true


func test_times_out_at_max() -> bool:
	var spec_data: Dictionary = _spec([_group("swarmer", 1)], 900000)
	spec_data["max_ms"] = 5000
	var result: Dictionary = _battle(spec_data).run()
	expect_eq(result["outcome"], "timed_out", "outcome")
	expect_eq(result["ticks"], 100, "5000 ms is 100 ticks")
	return true


func test_spec_refuses_off_grid_times() -> bool:
	var spec := BattleSpec.new()
	expect_true(not spec.parse(_spec([_group("swarmer", 1, 525)])), "a 525 ms interval is refused")
	return true


func test_spec_refuses_commands_for_now() -> bool:
	var spec_data: Dictionary = _spec([_group("swarmer", 1)])
	spec_data["commands"] = [{"tick": 0, "type": "place_tower", "args": {}}]
	var spec := BattleSpec.new()
	expect_true(not spec.parse(spec_data), "M0 knows no command types")
	return true
