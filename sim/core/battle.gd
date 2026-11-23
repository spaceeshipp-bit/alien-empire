extends RefCounted
## One deterministic battle: aliens spawn from the waves and walk their lanes,
## field towers bought with credits shoot them, and leaks cost lives (D-034).
##
## The battle runs in the C++ sim core (sim/native/src/core/battle.cpp), which
## the phone and the server's worker both load; see docs/DECISIONS.md D-026.
## This script checks that a loaded config and spec fit together, resolves the
## config lookups the core needs (counter ratings, shield multipliers) and hands
## everything over as plain values.
##
## Usage:
##   var battle := Battle.new()
##   if battle.setup(config, spec):
##       var result := battle.run()
## or, live: battle.queue_command("place", Vector2i(2, 3), "pulse_turret"),
## then battle.advance() once per tick.

const SimConfig := preload("res://sim/core/sim_config.gd")
const BattleSpec := preload("res://sim/core/battle_spec.gd")

## A checkpoint hash is recorded every 100 ticks (5 seconds), so a golden-test
## mismatch can be traced to the first stretch of the battle that diverged.
const CHECKPOINT_TICKS: int = 100
## Spawn keys pack the spawn tick above a 20-bit spawn sequence number.
const SEQ_MASK: int = (1 << 20) - 1
const COMMAND_KINDS := {"place": 1, "upgrade": 2, "sell": 3, "call_wave": 4}

enum Outcome { RUNNING, CLEARED, TIMED_OUT, LOST }
## What happened in the last tick (get_events), as in sim/native/src/core/battle.h.
enum Event { SHOT = 1, KILL = 2, LEAK = 3, PLACED = 4, UPGRADED = 5, SOLD = 6, REFUSED = 7, WAVE_DONE = 8, CALLED = 9 }

var tick: int:
	get:
		return _native.get_tick()
var outcome: int:
	get:
		return _native.get_outcome()
## Live aliens in ascending id order, one Dictionary each: id, type_index,
## lane_index, class_index, air, distance_mt, move_accum, hp_x100, max_hp_x100,
## shield_x100, max_shield_x100, kill_credits_x100, x, y.
var aliens: Array:
	get:
		return _native.get_aliens()
## Towers in ascending id order, one Dictionary each: id, type_index, level,
## col, row, x, y, charge, target_id, damage_x100, range_mt, spent_x100,
## refund_x100, upgrade_cost_x100 (-1 at the top level).
var towers: Array:
	get:
		return _native.get_towers()
var spawned_count: int:
	get:
		return _native.get_spawned_count()
var leaked_count: int:
	get:
		return _native.get_leaked_count()
var leaked_lives: int:
	get:
		return _native.get_leaked_lives()
var lives: int:
	get:
		return _native.get_lives()
var credits_x100: int:
	get:
		return _native.get_credits_x100()
var kills: int:
	get:
		return _native.get_kills()
var refused_commands: int:
	get:
		return _native.get_refused_commands()
## Each wave's start tick now: calling a wave early moves every later one.
var wave_starts: PackedInt64Array:
	get:
		return _native.get_wave_starts()
var checkpoints: PackedStringArray:
	get:
		return _native.get_checkpoints()
## Alien updates so far, for speed measurements. Not part of the battle state.
var entity_updates: int:
	get:
		return _native.get_entity_updates()
var errors: PackedStringArray = PackedStringArray()

var _native := SimNativeBattle.new()
var _config: SimConfig
var _spec: BattleSpec


## Prepares the battle. Returns false and fills errors if the spec doesn't fit
## the config (an unknown alien or tower, an air alien on a lane without an air
## route, or an ability this sim version doesn't run).
func setup(config: SimConfig, spec: BattleSpec) -> bool:
	# A fresh core battle each time, so a failed setup leaves an empty battle.
	_native = SimNativeBattle.new()
	_config = config
	_spec = spec
	errors = PackedStringArray()
	if spec.total_spawns > SEQ_MASK:
		errors.append("too many spawns: %d" % spec.total_spawns)
	for gi in spec.groups.size():
		var g: BattleSpec.Group = spec.groups[gi]
		var enemy_type: SimConfig.EnemyType = config.enemy(g.enemy_id)
		if enemy_type == null:
			errors.append("group %d: unknown enemy %s" % [gi, g.enemy_id])
		elif enemy_type.air and spec.air_paths[g.lane_index] == null:
			errors.append("group %d: air enemy %s needs an air route on lane %s" % [gi, g.enemy_id, spec.lane_ids[g.lane_index]])
		elif not enemy_type.supported:
			errors.append("group %d: %s has an ability this sim version doesn't run" % [gi, g.enemy_id])
	for id in spec.tower_ids:
		var tower_type: SimConfig.TowerType = config.tower(id)
		if tower_type == null:
			errors.append("unknown tower %s" % id)
		elif not tower_type.supported:
			errors.append("tower %s has an ability this sim version doesn't run (%s)" % [id, ", ".join(tower_type.abilities)])
	if not errors.is_empty():
		return false
	if not _native.setup(_config_data(config), _spec_data(config, spec)):
		errors = _native.get_errors()
		return false
	return true


## Queues a player command for the next tick to run (or a later tick). kind is
## place, upgrade or sell; place names a tower id. Returns "" or why it was
## refused. The battle's state can still refuse it when it applies: not enough
## credits, a tile that's taken or empty, the top level.
func queue_command(kind: String, tile: Vector2i, tower_id: String = "", at_tick: int = -1) -> String:
	if not COMMAND_KINDS.has(kind):
		return "unknown command %s" % kind
	if kind == "call_wave":
		tile = Vector2i.ZERO
	var tower_index: int = -1
	if kind == "place":
		var tower_type: SimConfig.TowerType = _config.tower(tower_id) if _config != null else null
		if tower_type == null:
			return "unknown tower %s" % tower_id
		tower_index = tower_type.index
	return _native.queue_command({
		"tick": tick if at_tick < 0 else at_tick, "kind": COMMAND_KINDS[kind], "tower_index": tower_index,
		"col": tile.x, "row": tile.y,
	})


## The commands so far, in the spec's JSON form: what a replay of this battle needs.
func command_log() -> Array:
	var out: Array = []
	var names: PackedStringArray = _config.tower_ids()
	for c: Dictionary in _native.get_commands():
		var kind: String = COMMAND_KINDS.find_key(c.kind)
		var args := {"tile": [c.col, c.row]} if kind != "call_wave" else {}
		if kind == "place":
			args["tower"] = names[c.tower_index]
		out.append({"tick": c.tick, "type": kind, "args": args})
	return out


## Live aliens for drawing: SimNative.ALIEN_VIEW_STRIDE values each, in id
## order: id, type_index, class_index, air, x, y, hp_x100, max_hp_x100,
## shield_x100, max_shield_x100.
func alien_view() -> PackedInt64Array:
	return _native.get_alien_view()


## The last tick's events, 5 values each: kind (Event), a, b, x, y.
func events() -> PackedInt64Array:
	return _native.get_events()


## Runs one 50 ms tick.
func advance() -> void:
	_native.advance()


## Runs to the end and returns the result record.
func run() -> Dictionary:
	return _native.run()


## battle_id, sim_version, config_version, config_hash, outcome ("running",
## "cleared", "timed_out" or "lost"), ticks, spawned, leaked, leaked_lives,
## lives, credits_x100, kills, refused, final_hash, checkpoints and
## entity_updates.
func result() -> Dictionary:
	return _native.result()


## SHA-256 of everything that can affect the rest of the battle.
func state_hash() -> String:
	return _native.state_hash()


func _config_data(config: SimConfig) -> Dictionary:
	var enemies: Array = []
	for id in config.enemy_ids():
		var e: SimConfig.EnemyType = config.enemy(id)
		enemies.append({
			"hp_x100": e.hp_x100, "armor": e.armor, "shield_x100": e.shield_x100,
			"speed_mtps": e.speed_mtps, "air": e.air, "leak_lives": e.leak_lives,
			"class_index": e.class_index, "kill_credits_x100": e.kill_credits_x100,
			"release_index": config.enemy(e.release_id).index if not e.release_id.is_empty() else -1,
			"release_count": e.release_count, "supported": e.supported,
		})
	var towers_data: Array = []
	for id in config.tower_ids():
		var t: SimConfig.TowerType = config.tower(id)
		towers_data.append({
			"cost_credits": t.cost_credits, "damage_x100": t.damage_x100, "shots_per_s_x100": t.shots_per_s_x100,
			"range_mt": t.range_mt, "splash_mt": t.splash_mt, "shield_mult_bp": t.shield_mult_bp,
			"pierce_bp": t.armor_pierce_bp, "rating_bp": t.rating_bp, "unrevealed_bp": t.unrevealed_bp,
			"supported": t.supported, "targeting": t.targeting,
		})
	return {
		"config_hash": config.config_hash, "config_version": config.config_version, "enemies": enemies,
		"towers": towers_data, "upgrades": config.upgrades, "armor_constant": config.armor_constant,
		"max_reduction_bp": config.max_reduction_bp, "min_damage_x100": config.min_damage_x100,
		"regen_per_second_x100": config.regen_per_second_x100, "regen_delay_ticks": config.regen_delay_ticks,
		"retarget_ticks": config.retarget_ticks,
	}


func _spec_data(config: SimConfig, spec: BattleSpec) -> Dictionary:
	var lanes: Array = []
	for i in spec.lane_ids.size():
		var ground = spec.ground_paths[i]
		var air = spec.air_paths[i]
		lanes.append({
			"ground_x": ground.xs, "ground_y": ground.ys,
			"air_x": air.xs if air != null else PackedInt64Array(),
			"air_y": air.ys if air != null else PackedInt64Array(),
		})
	var groups: Array = []
	for g: BattleSpec.Group in spec.groups:
		groups.append({
			"enemy_index": config.enemy(g.enemy_id).index, "lane_index": g.lane_index, "count": g.count,
			"first_tick": g.first_tick, "interval_ticks": g.interval_ticks, "jitter_ticks": g.jitter_ticks,
			"hp_bp": g.hp_bp, "credits_bp": g.credits_bp, "wave_index": g.wave_index,
		})
	var tower_set := PackedInt64Array()
	for id in spec.tower_ids:
		tower_set.append(config.tower(id).index)
	var tiles := PackedInt64Array()
	for tile: Vector2i in spec.build_tiles:
		tiles.append(tile.x)
		tiles.append(tile.y)
	var commands: Array = []
	for c: BattleSpec.Command in spec.commands:
		commands.append({
			"tick": c.tick, "kind": COMMAND_KINDS[c.kind],
			"tower_index": config.tower(c.tower_id).index if c.kind == "place" else -1,
			"col": c.col if c.kind != "call_wave" else 0, "row": c.row if c.kind != "call_wave" else 0,
		})
	return {
		"battle_id": spec.battle_id, "seed": spec.battle_seed, "max_ticks": spec.max_ticks,
		"lives": spec.lives, "credits": spec.credits, "tower_set": tower_set, "build_tiles": tiles,
		"wave_starts": spec.wave_starts, "call_credits_per_s": spec.call_credits_per_s,
		"call_credits_max": spec.call_credits_max, "clean_wave_credits": spec.clean_wave_credits,
		"lanes": lanes, "groups": groups, "commands": commands,
	}
