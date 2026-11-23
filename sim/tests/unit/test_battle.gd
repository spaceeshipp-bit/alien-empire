extends "res://sim/tests/test_case.gd"
## Battle tests: spawning, movement and leaks, then field towers, commands,
## damage and credits (D-034). Where a test depends on a speed or a price, it
## sets or reads it itself, so retuning the config never breaks these tests.

const SimConfig := preload("res://sim/core/sim_config.gd")
const BattleSpec := preload("res://sim/core/battle_spec.gd")
const Battle := preload("res://sim/core/battle.gd")
const BUNDLE := "res://sim/tests/golden/config_bundle.json"


func _config(speeds: Dictionary = {}, targeting: Dictionary = {}) -> SimConfig:
	var bundle: Dictionary = load_json(BUNDLE)
	for entry in bundle["data"]["enemies"]["enemies"]:
		if speeds.has(entry["id"]):
			entry["speed_mtps"] = speeds[entry["id"]]
	for entry in bundle["data"]["towers"]["towers"]:
		if targeting.has(entry["id"]):
			entry["targeting"] = targeting[entry["id"]]
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
		"lives": 20,
		"credits": 0,
		"towers": [],
		"call_credits_per_s": 0,
		"call_credits_max": 0,
		"clean_wave_credits": 0,
		"map": {
			"lanes": [{
				"id": "a",
				"ground": [[1000, 0], [1000, lane_mt]],
				"air": [[2000, 0], [2000, lane_mt / 2]],
			}],
			"build_tiles": [],
		},
		"waves": [{"start_ms": 0, "hp_bp": 10000, "credits_bp": 10000, "groups": groups}],
		"commands": [],
	}


## _spec with field towers: three build tiles beside the lane, which runs down
## x = 1000. Tile (2, 5) is centered 1.5 tiles from it.
func _armed(groups: Array, commands: Array, credits: int = 1000, towers: Array = ["plasma_torch", "pulse_turret", "railgun"]) -> Dictionary:
	var spec_data: Dictionary = _spec(groups)
	spec_data["credits"] = credits
	spec_data["towers"] = towers
	spec_data["map"]["build_tiles"] = [[2, 5], [2, 9], [0, 12]]
	spec_data["commands"] = commands
	return spec_data


func _command(tick: int, kind: String, tile: Array, tower: String = "") -> Dictionary:
	var args := {"tile": tile}
	if kind == "place":
		args["tower"] = tower
	return {"tick": tick, "type": kind, "args": args}


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
	expect_eq(result["lives"], 20 - config.enemy("swarmer").leak_lives, "lives left")
	return true


func test_lost_when_lives_run_out() -> bool:
	var spec_data: Dictionary = _spec([_group("swarmer", 5, 0)], 2000)
	spec_data["lives"] = 2
	var result: Dictionary = _battle(spec_data, _config({"swarmer": 2000})).run()
	expect_eq(result["outcome"], "lost", "outcome")
	expect_eq(result["lives"], 0, "lives stop at 0")
	expect_eq(result["leaked"], 5, "the leak that ends it happens with the rest of its tick")
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


func test_spec_refuses_bad_commands() -> bool:
	var bad := {
		"an unknown type": _command(0, "launch", [2, 5]),
		"a tile that isn't a build tile": _command(0, "place", [3, 5], "pulse_turret"),
		"a tower this battle doesn't allow": _command(0, "place", [2, 5], "flak_battery"),
		"a tick at the end": _command(12000, "upgrade", [2, 5]),
		"an extra field": {"tick": 0, "type": "sell", "args": {"tile": [2, 5], "tower": "railgun"}},
		"no tile": {"tick": 0, "type": "sell", "args": {}},
	}
	for what in bad:
		var spec := BattleSpec.new()
		expect_true(not spec.parse(_armed([_group("swarmer", 1)], [bad[what]])), "refuses " + what)
	var spec := BattleSpec.new()
	var out_of_order: Array = [_command(5, "upgrade", [2, 5]), _command(4, "sell", [2, 5])]
	expect_true(not spec.parse(_armed([_group("swarmer", 1)], out_of_order)), "refuses ticks out of order")
	return true


func test_tower_kills_pay_credits() -> bool:
	var config: SimConfig = _config()
	var spec_data: Dictionary = _armed([_group("swarmer", 6, 500)], [_command(0, "place", [2, 5], "pulse_turret")])
	var result: Dictionary = _battle(spec_data, config).run()
	var cost: int = config.tower("pulse_turret").cost_credits
	var pay: int = config.enemy("swarmer").kill_credits_x100
	expect_true(result["kills"] > 0, "the turret kills some of them")
	expect_eq(result["credits_x100"], (1000 - cost) * 100 + result["kills"] * pay, "credits: the build cost out, kills in")
	expect_eq(result["kills"] + result["leaked"], 6, "every swarmer dies or leaks")
	expect_eq(result["refused"], 0, "nothing refused")
	return true


func test_refused_commands_change_nothing_but_the_count() -> bool:
	# The aliens arrive a minute in, so only the commands act in the first ticks.
	var late: Dictionary = _group("swarmer", 1)
	late["offset_ms"] = 60000
	var commands: Array = [
		_command(0, "place", [2, 9], "railgun"),  # 200 > 150: not enough credits
		_command(0, "place", [2, 5], "pulse_turret"),  # 100: leaves 50
		_command(1, "place", [2, 5], "pulse_turret"),  # taken
		_command(2, "upgrade", [2, 9]),  # empty
		_command(3, "sell", [0, 12]),  # empty
		_command(4, "upgrade", [2, 5]),  # 80 > 50
		_command(5, "sell", [2, 5]),  # returns 70% of 100
	]
	var config: SimConfig = _config()
	var battle: Battle = _battle(_armed([late], commands, 150), config)
	for i in 10:
		battle.advance()
	var refund: int = 100 * config.tower("pulse_turret").cost_credits * int(config.upgrades.sell_refund_bp) / 10000
	expect_eq(battle.refused_commands, 5, "refused")
	expect_eq(battle.credits_x100, 5000 + refund, "credits")
	expect_eq(battle.towers.size(), 0, "towers left")
	return true


func test_upgrades_follow_the_config_and_sell_returns_its_share() -> bool:
	var config: SimConfig = _config()
	var commands: Array = [_command(0, "place", [2, 5], "pulse_turret")]
	for t in range(1, 5):
		commands.append(_command(t, "upgrade", [2, 5]))
	var late: Dictionary = _group("swarmer", 1)
	late["offset_ms"] = 60000
	var battle: Battle = _battle(_armed([late], commands, 1000), config)
	var spent: int = config.tower("pulse_turret").cost_credits * 100
	for level in range(1, int(config.upgrades.max_level)):
		spent += config.upgrade_cost_x100("pulse_turret", level)
	for i in 6:
		battle.advance()
	var tower: Dictionary = battle.towers[0]
	expect_eq(tower.level, int(config.upgrades.max_level), "level")
	expect_eq(tower.spent_x100, spent, "spent matches the loader's upgrade costs")
	expect_eq(tower.upgrade_cost_x100, -1, "no upgrade past the top level")
	expect_eq(battle.refused_commands, 4 - (int(config.upgrades.max_level) - 1), "upgrades past the top are refused")
	expect_eq(battle.credits_x100, 100000 - spent, "credits")
	expect_eq(tower.refund_x100, spent * int(config.upgrades.sell_refund_bp) / 10000, "refund: a share of everything spent")
	return true


func test_live_commands_match_the_log() -> bool:
	var commands: Array = [
		_command(0, "place", [2, 5], "plasma_torch"), _command(40, "place", [2, 9], "railgun"),
		_command(90, "upgrade", [2, 5]), _command(200, "sell", [2, 9]), _command(201, "place", [2, 9], "pulse_turret"),
	]
	var groups: Array = [_group("swarmer", 12, 250), _group("carapace_brute", 2, 3000)]
	var logged: Dictionary = _battle(_armed(groups, commands, 600)).run()
	var live: Battle = _battle(_armed(groups, [], 600))
	var next: int = 0
	while live.outcome == Battle.Outcome.RUNNING:
		while next < commands.size() and int(commands[next]["tick"]) == live.tick:
			var c: Dictionary = commands[next]
			var problem: String = live.queue_command(c["type"], Vector2i(c["args"]["tile"][0], c["args"]["tile"][1]), c["args"].get("tower", ""))
			expect_eq(problem, "", "queued live")
			next += 1
		live.advance()
	expect_eq(live.result()["final_hash"], logged["final_hash"], "the same battle either way")
	expect_eq(live.command_log(), commands, "the log a replay needs")
	return true


func test_queue_command_refuses_the_past_and_unknown_towers() -> bool:
	var battle: Battle = _battle(_armed([_group("swarmer", 3)], []))
	for i in 5:
		battle.advance()
	expect_true(battle.queue_command("upgrade", Vector2i(2, 5), "", 2) != "", "a tick already run")
	expect_true(battle.queue_command("place", Vector2i(2, 5), "no_such_tower") != "", "an unknown tower")
	expect_true(battle.queue_command("place", Vector2i(3, 3), "pulse_turret") != "", "not a build tile")
	expect_eq(battle.queue_command("place", Vector2i(2, 5), "pulse_turret"), "", "a good one")
	return true


func test_plasma_torch_cant_hit_air() -> bool:
	var spec_data: Dictionary = _armed([_group("skimmer", 4, 500)], [_command(0, "place", [2, 5], "plasma_torch")], 1000, ["plasma_torch"])
	spec_data["map"]["build_tiles"] = [[2, 5]]
	# The air route runs down x = 2000, half a tile from the torch's tile center.
	var result: Dictionary = _battle(spec_data).run()
	expect_eq(result["kills"], 0, "no kills")
	expect_eq(result["leaked"], 4, "every skimmer leaks")
	return true


func test_hive_carrier_releases_swarmers() -> bool:
	var config: SimConfig = _config()
	var carrier: Dictionary = _group("hive_carrier", 1)
	var spec_data: Dictionary = _armed([carrier], [_command(0, "place", [2, 5], "railgun"), _command(0, "place", [2, 9], "railgun")], 1000)
	spec_data["waves"][0]["hp_bp"] = 1  # a carrier that dies to its shield breaking
	var result: Dictionary = _battle(spec_data, config).run()
	var release: SimConfig.EnemyType = config.enemy("hive_carrier")
	expect_eq(release.release_id, "swarmer", "it releases swarmers")
	expect_true(result["kills"] >= 1, "the carrier dies")
	expect_eq(result["spawned"], 1 + release.release_count, "the carrier and what it released")
	return true


func test_towers_with_abilities_wait_for_m2() -> bool:
	var spec := BattleSpec.new()
	expect_true(spec.parse(_armed([_group("swarmer", 1)], [], 1000, ["ion_disruptor"])), "the spec itself is fine")
	var battle := Battle.new()
	expect_true(not battle.setup(_config(), spec), "setup refuses a tower whose slow isn't in this sim version")
	expect_true("ability" in str(battle.errors), "and says why: %s" % str(battle.errors))
	return true


func test_spec_refuses_coordinates_past_the_limit_without_building() -> bool:
	var spec_data: Dictionary = _spec([_group("swarmer", 1)])
	spec_data["map"]["lanes"][0]["ground"] = [[0, 0], [9007199254740991, 0]]
	var spec := BattleSpec.new()
	expect_true(not spec.parse(spec_data), "a lane far off the map is refused")
	return true


# Sim version 3 (D-036): targeting, calling a wave early, the clean-wave bonus.

## The last tick's events of one kind, as [a, b] pairs.
func _events_of(battle: Battle, kind: int) -> Array:
	var out: Array = []
	var ev: PackedInt64Array = battle.events()
	for i in range(0, ev.size(), 5):
		if ev[i] == kind:
			out.append([ev[i + 1], ev[i + 2]])
	return out


## Three waves of one Swarmer each, at 0, 10 and 20 seconds, and nothing to shoot them.
func _three_waves(per_s: int, cap: int) -> Dictionary:
	var spec_data: Dictionary = _spec([])
	spec_data["call_credits_per_s"] = per_s
	spec_data["call_credits_max"] = cap
	spec_data["waves"] = []
	for i in 3:
		spec_data["waves"].append({"start_ms": i * 10000, "hp_bp": 10000, "credits_bp": 10000, "groups": [_group("swarmer", 1)]})
	return spec_data


func test_calling_a_wave_pays_and_moves_every_later_wave() -> bool:
	var battle: Battle = _battle(_three_waves(1, 15))
	expect_eq(battle.wave_starts, PackedInt64Array([0, 200, 400]), "wave starts in ticks")
	for i in 20:
		battle.advance()
	expect_eq(battle.queue_command("call_wave", Vector2i(3, 4)), "", "a call takes no tile")
	battle.advance()  # tick 20: wave 2 was 180 ticks (9 s) away
	expect_eq(battle.credits_x100, 900, "1 credit a second skipped")
	expect_eq(battle.wave_starts, PackedInt64Array([0, 20, 220]), "every wave not yet started moved 180 ticks sooner")
	expect_eq(battle.spawned_count, 2, "and its aliens with it: wave 2's Swarmer spawned on the call's tick")
	expect_eq(_events_of(battle, Battle.Event.CALLED), [[1, 900]], "the event names the wave and the bonus")
	expect_eq(battle.command_log(), [{"tick": 20, "type": "call_wave", "args": {}}], "the log a replay needs")
	return true


func test_a_call_pays_at_most_the_cap_and_needs_a_wave_to_call() -> bool:
	var battle: Battle = _battle(_three_waves(1, 5))
	battle.queue_command("call_wave", Vector2i.ZERO)
	battle.advance()  # tick 0: wave 2 is 10 s away, but the cap is 5 credits
	expect_eq(battle.credits_x100, 500, "the cap")
	expect_eq(battle.wave_starts, PackedInt64Array([0, 0, 200]), "wave 3 moved as far as wave 2")
	battle.queue_command("call_wave", Vector2i.ZERO)
	battle.advance()  # tick 1: wave 3, 199 ticks away, capped again
	expect_eq(battle.credits_x100, 1000, "capped again")
	battle.queue_command("call_wave", Vector2i.ZERO)
	battle.advance()  # tick 2: every wave has started
	expect_eq(battle.refused_commands, 1, "nothing left to call")
	expect_eq(_events_of(battle, Battle.Event.REFUSED).size(), 1, "a refused event")
	expect_eq(battle.credits_x100, 1000, "and no pay")
	return true


func test_live_calls_match_the_log() -> bool:
	var commands: Array = [{"tick": 30, "type": "call_wave", "args": {}}, {"tick": 31, "type": "call_wave", "args": {}}]
	var logged_data: Dictionary = _three_waves(1, 15)
	logged_data["commands"] = commands
	var logged: Dictionary = _battle(logged_data).run()
	var live: Battle = _battle(_three_waves(1, 15))
	while live.outcome == Battle.Outcome.RUNNING:
		if live.tick == 30 or live.tick == 31:
			expect_eq(live.queue_command("call_wave", Vector2i.ZERO), "", "queued live")
		live.advance()
	expect_eq(live.result()["final_hash"], logged["final_hash"], "the same battle either way")
	expect_eq(live.command_log(), commands, "the log")
	return true


## A Railgun on tile (2, 5), 1.5 tiles beside the lane; it fires every 40 ticks.
func _railgun_duel(groups: Array, targeting: String) -> Battle:
	var spec_data: Dictionary = _armed(groups, [_command(0, "place", [2, 5], "railgun")])
	return _battle(spec_data, _config({}, {"railgun": targeting}))


func test_first_shoots_the_leader_and_strongest_the_toughest() -> bool:
	# A Swarmer leads a Brute down the lane; by the Railgun's second shot both are in range.
	var groups: Array = [_group("swarmer", 1), _group("carapace_brute", 1)]
	for targeting: String in ["first", "strongest"]:
		var battle: Battle = _railgun_duel(groups, targeting)
		for i in 60:
			battle.advance()
		var target: int = battle.towers[0].target_id
		if targeting == "first":
			expect_eq(target, 1, "first: the Swarmer in front (id 1)")
		else:
			expect_eq(target, 2, "strongest: the Brute (id 2)")
	return true


func test_strongest_finishes_the_alien_it_started_on() -> bool:
	# Two Swarmers a tick apart: a Railgun hit leaves the leader at 15 of 40 HP. Ranked by full
	# HP the two tie, so the second shot goes to the leader again and kills it; ranked by HP
	# left it would have gone to the fresh one. (First would also kill it here: the test above
	# is the one that tells Strongest from First.)
	var battle: Battle = _railgun_duel([_group("swarmer", 2, 50)], "strongest")
	for i in 60:
		battle.advance()
	expect_eq(battle.kills, 1, "the second shot finished the first Swarmer")
	return true


func test_a_clean_wave_pays_and_a_leaking_one_doesnt() -> bool:
	var config: SimConfig = _config()
	var clean_data: Dictionary = _armed([_group("swarmer", 1)], [_command(0, "place", [2, 5], "railgun")])
	clean_data["clean_wave_credits"] = 15
	var clean: Battle = _battle(clean_data, config)
	var done: Array = []
	while clean.outcome == Battle.Outcome.RUNNING:
		clean.advance()
		done.append_array(_events_of(clean, Battle.Event.WAVE_DONE))
	var paid: int = (1000 - config.tower("railgun").cost_credits) * 100 + config.enemy("swarmer").kill_credits_x100
	expect_eq(clean.kills, 1, "the Railgun kills it")
	expect_eq(clean.credits_x100, paid + 1500, "the kill and the clean-wave bonus")
	expect_eq(done, [[0, 1]], "wave 1 done, clean")
	var leaky_data: Dictionary = _spec([_group("swarmer", 1)])
	leaky_data["clean_wave_credits"] = 15
	var leaky: Battle = _battle(leaky_data, config)
	done = []
	while leaky.outcome == Battle.Outcome.RUNNING:
		leaky.advance()
		done.append_array(_events_of(leaky, Battle.Event.WAVE_DONE))
	expect_eq(leaky.credits_x100, 0, "no bonus after a leak")
	expect_eq(done, [[0, 0]], "wave 1 done, not clean")
	return true

