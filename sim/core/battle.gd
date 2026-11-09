extends RefCounted
## One deterministic battle. M0 skeleton: aliens spawn from the waves, walk
## their lanes and leak at the Core. Towers, damage and commands arrive in M1.
##
## The battle runs in the C++ sim core (sim/native/src/core/battle.cpp), which
## the phone and the server's worker both load; see docs/DECISIONS.md D-026.
## This script checks that a loaded config and spec fit together and hands them
## over as plain values.
##
## Usage:
##   var battle := Battle.new()
##   if battle.setup(config, spec):
##       var result := battle.run()

const SimConfig := preload("res://sim/core/sim_config.gd")
const BattleSpec := preload("res://sim/core/battle_spec.gd")

## A checkpoint hash is recorded every 100 ticks (5 seconds), so a golden-test
## mismatch can be traced to the first stretch of the battle that diverged.
const CHECKPOINT_TICKS: int = 100
## Spawn keys pack the spawn tick above a 20-bit spawn sequence number.
const SEQ_MASK: int = (1 << 20) - 1

enum Outcome { RUNNING, CLEARED, TIMED_OUT }

var tick: int:
	get:
		return _native.get_tick()
var outcome: int:
	get:
		return _native.get_outcome()
## Live aliens in ascending id order, one Dictionary each: id, type_index,
## lane_index, air, distance_mt, move_accum, hp_x100, shield_x100, x, y.
var aliens: Array:
	get:
		return _native.get_aliens()
var spawned_count: int:
	get:
		return _native.get_spawned_count()
var leaked_count: int:
	get:
		return _native.get_leaked_count()
var leaked_lives: int:
	get:
		return _native.get_leaked_lives()
var checkpoints: PackedStringArray:
	get:
		return _native.get_checkpoints()
## Alien updates so far, for speed measurements. Not part of the battle state.
var entity_updates: int:
	get:
		return _native.get_entity_updates()
var errors: PackedStringArray = PackedStringArray()

var _native := SimNativeBattle.new()


## Prepares the battle. Returns false and fills errors if the spec doesn't fit
## the config (unknown alien, air alien on a lane without an air route).
func setup(config: SimConfig, spec: BattleSpec) -> bool:
	# A fresh core battle each time, so a failed setup leaves an empty battle.
	_native = SimNativeBattle.new()
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
	if not errors.is_empty():
		return false
	if not _native.setup(_config_data(config), _spec_data(config, spec)):
		errors = _native.get_errors()
		return false
	return true


## Runs one 50 ms tick.
func advance() -> void:
	_native.advance()


## Runs to the end and returns the result record.
func run() -> Dictionary:
	return _native.run()


## battle_id, sim_version, config_version, config_hash, outcome ("running",
## "cleared" or "timed_out"), ticks, spawned, leaked, leaked_lives, final_hash,
## checkpoints and entity_updates.
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
		})
	return {"config_hash": config.config_hash, "config_version": config.config_version, "enemies": enemies}


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
		})
	return {
		"battle_id": spec.battle_id, "seed": spec.battle_seed, "max_ticks": spec.max_ticks,
		"lanes": lanes, "groups": groups,
	}
