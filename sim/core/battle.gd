extends RefCounted
## One deterministic battle. M0 skeleton: aliens spawn from the waves, walk
## their lanes and leak at the Core. Towers, damage and commands arrive in M1.
##
## Determinism rules (docs/BUILD_PROMPT.md, Combat simulation):
## - a fixed 20 ticks per second, integer math only, the battle's own SimRng only
## - entities update in ascending id order, and ids are handed out in spawn order
## - no engine physics, navigation, timers or random functions
##
## Usage:
##   var battle := Battle.new()
##   if battle.setup(config, spec):
##       var result := battle.run()

const Fx := preload("res://sim/core/fx.gd")
const SimRng := preload("res://sim/core/sim_rng.gd")
const SimConfig := preload("res://sim/core/sim_config.gd")
const BattleSpec := preload("res://sim/core/battle_spec.gd")
const LanePath := preload("res://sim/core/lane_path.gd")
const StateHasher := preload("res://sim/core/state_hasher.gd")
const SimVersion := preload("res://sim/core/sim_version.gd")

## A checkpoint hash is recorded every 100 ticks (5 seconds), so a golden-test
## mismatch can be traced to the first stretch of the battle that diverged.
const CHECKPOINT_TICKS: int = 100
## Spawn keys pack the spawn tick above a 20-bit spawn sequence number.
const SEQ_BITS: int = 20
const SEQ_MASK: int = (1 << SEQ_BITS) - 1

enum Outcome { RUNNING, CLEARED, TIMED_OUT }
const OUTCOME_NAMES := ["running", "cleared", "timed_out"]


class Alien:
	extends RefCounted
	var id: int = 0
	var type_index: int = 0
	var lane_index: int = 0
	var air: bool = false
	var path: LanePath = null
	var distance_mt: int = 0
	## Movement carried over between ticks, in mt x TICK_RATE, so speeds that
	## don't divide by 20 still cover the exact distance over time.
	var move_accum: int = 0
	var speed_mtps: int = 0
	var hp_x100: int = 0
	var shield_x100: int = 0
	var leak_lives: int = 0
	var leaked: bool = false


var tick: int = 0
var outcome: int = Outcome.RUNNING
## Live aliens in ascending id order.
var aliens: Array[Alien] = []
var spawned_count: int = 0
var leaked_count: int = 0
var leaked_lives: int = 0
var checkpoints: PackedStringArray = PackedStringArray()
var errors: PackedStringArray = PackedStringArray()
## Alien updates so far, for speed measurements. Not part of the battle state.
var entity_updates: int = 0

var _config: SimConfig = null
var _spec: BattleSpec = null
var _rng: SimRng = null
var _next_id: int = 1
var _spawn_keys: PackedInt64Array = PackedInt64Array()
var _spawn_group: PackedInt64Array = PackedInt64Array()
var _spawn_cursor: int = 0


## Prepares the battle. Returns false and fills errors if the spec doesn't fit
## the config (unknown alien, air alien on a lane without an air route).
func setup(config: SimConfig, spec: BattleSpec) -> bool:
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
	if not errors.is_empty():
		return false
	_rng = SimRng.new(spec.battle_seed)
	_build_spawn_plan()
	return true


## Runs one 50 ms tick.
func advance() -> void:
	if outcome != Outcome.RUNNING:
		return
	_spawn_due()
	entity_updates += aliens.size()
	var any_leaked: bool = _move_aliens()
	if any_leaked:
		_drop_leaked()
	tick += 1
	if tick % CHECKPOINT_TICKS == 0:
		checkpoints.append(state_hash().substr(0, 16))
	if _spawn_cursor >= _spawn_keys.size() and aliens.is_empty():
		outcome = Outcome.CLEARED
	elif tick >= _spec.max_ticks:
		outcome = Outcome.TIMED_OUT


## Runs to the end and returns the result record.
func run() -> Dictionary:
	while outcome == Outcome.RUNNING:
		advance()
	return result()


func result() -> Dictionary:
	return {
		"battle_id": _spec.battle_id,
		"sim_version": SimVersion.SIM_VERSION,
		"config_version": _config.config_version,
		"config_hash": _config.config_hash,
		"outcome": OUTCOME_NAMES[outcome],
		"ticks": tick,
		"spawned": spawned_count,
		"leaked": leaked_count,
		"leaked_lives": leaked_lives,
		"final_hash": state_hash(),
		"checkpoints": Array(checkpoints),
		"entity_updates": entity_updates,
	}


## SHA-256 of everything that can affect the rest of the battle.
func state_hash() -> String:
	var h := StateHasher.new()
	h.add_int(SimVersion.SIM_VERSION)
	h.add_string(_config.config_hash)
	h.add_int(_spec.battle_seed)
	h.add_int(tick)
	h.add_int(outcome)
	h.add_ints(_rng.get_state())
	h.add_int(_next_id)
	h.add_int(_spawn_cursor)
	h.add_int(spawned_count)
	h.add_int(leaked_count)
	h.add_int(leaked_lives)
	h.add_int(aliens.size())
	for a in aliens:
		var pos: Vector2i = a.path.position_at(a.distance_mt)
		h.add_int(a.id)
		h.add_int(a.type_index)
		h.add_int(a.lane_index)
		h.add_int(1 if a.air else 0)
		h.add_int(a.distance_mt)
		h.add_int(a.move_accum)
		h.add_int(a.hp_x100)
		h.add_int(a.shield_x100)
		h.add_int(pos.x)
		h.add_int(pos.y)
	return h.finish_hex()


## Spawn times are fixed at setup: groups in spec order, units in group order,
## each with its seeded jitter. Keys sort by tick, then by that order.
func _build_spawn_plan() -> void:
	var keys := PackedInt64Array()
	_spawn_group = PackedInt64Array()
	var seq: int = 0
	for gi in _spec.groups.size():
		var g: BattleSpec.Group = _spec.groups[gi]
		for n in g.count:
			var spawn_tick: int = g.first_tick + n * g.interval_ticks
			if g.jitter_ticks > 0:
				spawn_tick += _rng.range_int(0, g.jitter_ticks)
			keys.append((spawn_tick << SEQ_BITS) | seq)
			_spawn_group.append(gi)
			seq += 1
	keys.sort()
	_spawn_keys = keys
	_spawn_cursor = 0


func _spawn_due() -> void:
	while _spawn_cursor < _spawn_keys.size() and (_spawn_keys[_spawn_cursor] >> SEQ_BITS) <= tick:
		var seq: int = _spawn_keys[_spawn_cursor] & SEQ_MASK
		_spawn(_spec.groups[_spawn_group[seq]])
		_spawn_cursor += 1


func _spawn(g: BattleSpec.Group) -> void:
	var enemy_type: SimConfig.EnemyType = _config.enemy(g.enemy_id)
	var a := Alien.new()
	a.id = _next_id
	_next_id += 1
	a.type_index = enemy_type.index
	a.lane_index = g.lane_index
	a.air = enemy_type.air
	if enemy_type.air:
		a.path = _spec.air_paths[g.lane_index]
	else:
		a.path = _spec.ground_paths[g.lane_index]
	a.speed_mtps = enemy_type.speed_mtps
	a.hp_x100 = enemy_type.hp_x100
	a.shield_x100 = enemy_type.shield_x100
	a.leak_lives = enemy_type.leak_lives
	aliens.append(a)
	spawned_count += 1


## Moves every alien in id order. Returns true if any reached the Core.
func _move_aliens() -> bool:
	var any_leaked: bool = false
	for a in aliens:
		a.move_accum += a.speed_mtps
		var step_mt: int = a.move_accum / Fx.TICK_RATE
		a.move_accum -= step_mt * Fx.TICK_RATE
		a.distance_mt += step_mt
		if a.distance_mt >= a.path.length:
			a.distance_mt = a.path.length
			a.leaked = true
			leaked_count += 1
			leaked_lives += a.leak_lives
			any_leaked = true
	return any_leaked


func _drop_leaked() -> void:
	var kept: Array[Alien] = []
	for a in aliens:
		if not a.leaked:
			kept.append(a)
	aliens = kept
