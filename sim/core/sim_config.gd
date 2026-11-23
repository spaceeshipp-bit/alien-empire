extends RefCounted
## The balance values the sim uses, read from a config bundle (see
## config/schema/bundle.schema.json). The Python tools and the server run the
## full schema validation; this loader re-checks types and ranges so a bad
## bundle fails loudly instead of corrupting a battle. The ranges match the
## limits the sim core re-checks (sim/native/src/core/battle.cpp).
##
## Reads the manifest, the aliens, the towers with their field upgrades, the
## counter chart, the damage rules and shield regen. The other status effects
## arrive with M2.

const DataReader := preload("res://sim/core/data_reader.gd")

const BUNDLE_FORMAT: int = 1
## Generous upper bound for any single stat; real values are far smaller.
const MAX_STAT: int = 1000000000
## Multipliers in the damage pipeline stay at or below 10x and scaling factors
## at or below 100x, so no product in the core can overflow (D-034).
const MAX_MULT_BP: int = 100000
const MAX_SCALE_BP: int = 1000000
const MAX_LEVEL: int = 10
const MAX_RELEASE: int = 100
const MAX_TOWER_TYPES: int = 64
const MAX_MS: int = 3600000
const CLASSES := ["swarm", "armored", "shielded", "air", "cloaked", "titan"]
const DAMAGE_TYPES := ["standard", "emp", "thermal", "none"]
const RATINGS := ["strong", "neutral", "weak", "cant_hit"]
## Abilities this sim version runs (D-034). A tower with any other ability can't
## be built yet; slow, reveal and mark arrive in M2.
const TOWER_ABILITIES_RUN := []
const ENEMY_ABILITIES_RUN := ["spawn_on_death"]


class EnemyType:
	extends RefCounted
	var id: String = ""
	## Position in id order. State hashes use it instead of the id text.
	var index: int = 0
	var enemy_class: String = ""
	var class_index: int = 0
	var hp_x100: int = 0
	var armor: int = 0
	var shield_x100: int = 0
	var speed_mtps: int = 0
	var air: bool = false
	var leak_lives: int = 0
	var kill_credits_x100: int = 0
	## spawn_on_death: the alien it releases where it dies, or "".
	var release_id: String = ""
	var release_count: int = 0
	## False when it has an ability this sim version doesn't run.
	var supported: bool = true


class TowerType:
	extends RefCounted
	var id: String = ""
	## Position in id order.
	var index: int = 0
	var cost_credits: int = 0
	var damage_x100: int = 0
	var shots_per_s_x100: int = 0
	var range_mt: int = 0
	var splash_mt: int = 0
	var damage_type: String = ""
	var armor_pierce_bp: int = 0
	var abilities: PackedStringArray = PackedStringArray()
	## Counter rating against each class, in CLASSES order; 0 means it can't hit.
	var rating_bp: PackedInt64Array = PackedInt64Array([0, 0, 0, 0, 0, 0])
	## Damage share against a cloaked alien nothing reveals; 0 means it can't target one.
	var unrevealed_bp: int = 0
	## The shield multiplier for its damage type (damage pipeline step 5).
	var shield_mult_bp: int = 10000
	## False when it has an ability this sim version doesn't run.
	var supported: bool = true


var config_version: int = 0
var config_hash: String = ""
var errors: PackedStringArray = PackedStringArray()
## Field tower upgrades: max_level, first_upgrade_cost_bp, cost_growth_bp,
## damage_growth_bp, range_step_bp, sell_refund_bp.
var upgrades: Dictionary = {}
var retarget_ticks: int = 1
var armor_constant: int = 100
var max_reduction_bp: int = 0
var min_damage_x100: int = 0
var regen_per_second_x100: int = 0
var regen_delay_ticks: int = 0
var _enemies: Dictionary = {}  # id -> EnemyType
var _enemy_ids: PackedStringArray = PackedStringArray()
var _towers: Dictionary = {}  # id -> TowerType
var _tower_ids: PackedStringArray = PackedStringArray()


## Reads a parsed bundle. Returns false and fills errors if anything is wrong.
func load_bundle(bundle: Dictionary) -> bool:
	var r := DataReader.new()
	r.get_int(bundle, "format", "bundle", BUNDLE_FORMAT, BUNDLE_FORMAT)
	config_hash = r.get_string(bundle, "config_hash", "bundle")
	if config_hash.length() != 64 or not config_hash.is_valid_hex_number():
		r.fail("bundle.config_hash", "expected 64 hex characters")
	var data: Dictionary = r.get_dict(bundle, "data", "bundle")
	var manifest: Dictionary = r.get_dict(data, "manifest", "data")
	config_version = r.get_int(manifest, "config_version", "data.manifest", 1, MAX_STAT)
	_read_enemies(r, r.get_dict(data, "enemies", "data"))
	var damage: Dictionary = r.get_dict(data, "damage", "data")
	_read_damage(r, damage)
	_read_towers(r, r.get_dict(data, "towers", "data"), r.get_dict(data, "counters", "data"), damage)
	_read_regen(r, r.get_dict(data, "status_effects", "data"))
	errors = r.errors
	return errors.is_empty()


func has_enemy(id: String) -> bool:
	return _enemies.has(id)


## The alien type with this id, or null.
func enemy(id: String) -> EnemyType:
	return _enemies.get(id, null)


## All alien ids in sorted order.
func enemy_ids() -> PackedStringArray:
	return _enemy_ids


## The tower type with this id, or null.
func tower(id: String) -> TowerType:
	return _towers.get(id, null)


## All tower ids in sorted order.
func tower_ids() -> PackedStringArray:
	return _tower_ids


## What taking a tower of this type from level to level + 1 costs, x100: the
## same steps as the core (D-034).
func upgrade_cost_x100(tower_id: String, level: int) -> int:
	var t: TowerType = tower(tower_id)
	var cost: int = mini(t.cost_credits * 100 * int(upgrades.first_upgrade_cost_bp) / 10000, MAX_STAT * 100)
	for _l in level - 1:
		cost = mini(cost * int(upgrades.cost_growth_bp) / 10000, MAX_STAT * 100)
	return cost


func _read_enemies(r: DataReader, part: Dictionary) -> void:
	_enemies = {}
	var list: Array = r.get_array(part, "enemies", "data.enemies")
	for i in list.size():
		var path: String = "data.enemies.enemies[%d]" % i
		var d: Dictionary = r.item_dict(list, i, "data.enemies.enemies")
		if d.is_empty():
			continue
		var e := EnemyType.new()
		e.id = r.get_string(d, "id", path)
		e.enemy_class = r.get_string(d, "class", path)
		e.class_index = CLASSES.find(e.enemy_class)
		if e.class_index < 0:
			r.fail(path + ".class", "unknown class %s" % e.enemy_class)
			e.class_index = 0
		e.hp_x100 = r.get_int(d, "hp_x100", path, 1, MAX_STAT)
		e.armor = r.get_int(d, "armor", path, 0, MAX_STAT)
		e.shield_x100 = r.get_int(d, "shield_x100", path, 0, MAX_STAT)
		e.speed_mtps = r.get_int(d, "speed_mtps", path, 1, MAX_STAT)
		var movement: String = r.get_string(d, "movement", path)
		if movement != "ground" and movement != "air":
			r.fail(path + ".movement", "expected ground or air")
		e.air = movement == "air"
		e.leak_lives = r.get_int(d, "leak_lives", path, 1, MAX_STAT)
		e.kill_credits_x100 = r.get_int(d, "kill_credits_x100", path, 0, MAX_STAT)
		var abilities: Array = r.get_array(d, "abilities", path)
		for k in abilities.size():
			var a: Dictionary = r.item_dict(abilities, k, path + ".abilities")
			var kind: String = r.get_string(a, "type", "%s.abilities[%d]" % [path, k])
			if not ENEMY_ABILITIES_RUN.has(kind):
				e.supported = false
			elif kind == "spawn_on_death":
				e.release_id = r.get_string(a, "enemy", "%s.abilities[%d]" % [path, k])
				e.release_count = r.get_int(a, "count", "%s.abilities[%d]" % [path, k], 1, MAX_RELEASE)
		if _enemies.has(e.id):
			r.fail(path + ".id", "duplicate id %s" % e.id)
		_enemies[e.id] = e
	var ids: Array = _enemies.keys()
	ids.sort()
	_enemy_ids = PackedStringArray(ids)
	for i in ids.size():
		var e: EnemyType = _enemies[ids[i]]
		e.index = i
	for id in ids:
		var e: EnemyType = _enemies[id]
		if e.release_id.is_empty():
			continue
		var released: EnemyType = _enemies.get(e.release_id, null)
		if released == null:
			r.fail("data.enemies", "%s releases unknown enemy %s" % [e.id, e.release_id])
		elif released.air != e.air:
			r.fail("data.enemies", "%s releases %s, which moves differently" % [e.id, e.release_id])


func _read_damage(r: DataReader, damage: Dictionary) -> void:
	armor_constant = r.get_int(damage, "armor_constant", "data.damage", 1, MAX_STAT)
	max_reduction_bp = r.get_int(damage, "max_reduction_bp", "data.damage", 0, 10000)
	min_damage_x100 = r.get_int(damage, "min_damage_x100", "data.damage", 0, MAX_STAT)


func _read_towers(r: DataReader, part: Dictionary, counters_part: Dictionary, damage: Dictionary) -> void:
	_towers = {}
	retarget_ticks = r.get_ticks(part, "retarget_ms", "data.towers", 50, MAX_MS)
	var fu: Dictionary = r.get_dict(part, "field_upgrades", "data.towers")
	upgrades = {
		"max_level": r.get_int(fu, "max_level", "data.towers.field_upgrades", 1, MAX_LEVEL),
		"first_upgrade_cost_bp": r.get_int(fu, "first_upgrade_cost_bp", "data.towers.field_upgrades", 0, MAX_SCALE_BP),
		"cost_growth_bp": r.get_int(fu, "cost_growth_bp", "data.towers.field_upgrades", 0, MAX_SCALE_BP),
		"damage_growth_bp": r.get_int(fu, "damage_growth_bp", "data.towers.field_upgrades", 0, MAX_SCALE_BP),
		"range_step_bp": r.get_int(fu, "range_step_bp", "data.towers.field_upgrades", 0, MAX_SCALE_BP),
		"sell_refund_bp": r.get_int(fu, "sell_refund_bp", "data.towers.field_upgrades", 0, 10000),
	}
	var ratings: Dictionary = r.get_dict(damage, "counter_ratings_bp", "data.damage")
	var rating_bp := {}
	for name in RATINGS:
		rating_bp[name] = r.get_int(ratings, name, "data.damage.counter_ratings_bp", 0, MAX_MULT_BP)
	var shields: Dictionary = r.get_dict(damage, "shield_multipliers_bp", "data.damage")
	var counters: Dictionary = r.get_dict(counters_part, "counters", "data.counters")
	var list: Array = r.get_array(part, "towers", "data.towers")
	if list.size() > MAX_TOWER_TYPES:
		r.fail("data.towers.towers", "more than %d tower types" % MAX_TOWER_TYPES)
	for i in list.size():
		var path: String = "data.towers.towers[%d]" % i
		var d: Dictionary = r.item_dict(list, i, "data.towers.towers")
		if d.is_empty():
			continue
		var t := TowerType.new()
		t.id = r.get_string(d, "id", path)
		t.cost_credits = r.get_int(d, "cost_credits", path, 1, MAX_STAT)
		t.damage_x100 = r.get_int(d, "damage_x100", path, 0, MAX_STAT)
		t.shots_per_s_x100 = r.get_int(d, "shots_per_s_x100", path, 0, MAX_STAT)
		t.range_mt = r.get_int(d, "range_mt", path, 0, MAX_STAT)
		t.splash_mt = r.get_int(d, "splash_mt", path, 0, MAX_STAT)
		t.damage_type = r.get_string(d, "damage_type", path)
		if not DAMAGE_TYPES.has(t.damage_type):
			r.fail(path + ".damage_type", "unknown damage type %s" % t.damage_type)
		t.armor_pierce_bp = r.get_int(d, "armor_pierce_bp", path, 0, 10000)
		var abilities: Array = r.get_array(d, "abilities", path)
		for k in abilities.size():
			var a: Dictionary = r.item_dict(abilities, k, path + ".abilities")
			var kind: String = r.get_string(a, "type", "%s.abilities[%d]" % [path, k])
			t.abilities.append(kind)
			if not TOWER_ABILITIES_RUN.has(kind):
				t.supported = false
		if t.damage_type != "none":
			t.shield_mult_bp = r.get_int(shields, t.damage_type, "data.damage.shield_multipliers_bp", 1, MAX_MULT_BP)
		if counters.has(t.id):
			var row: Variant = counters[t.id]
			if typeof(row) != TYPE_DICTIONARY:
				r.fail("data.counters.counters." + t.id, "expected an object")
			else:
				_read_counter_row(r, row, t, rating_bp, "data.counters.counters." + t.id)
		if _towers.has(t.id):
			r.fail(path + ".id", "duplicate id %s" % t.id)
		_towers[t.id] = t
	for id in counters.keys():
		if not _towers.has(id):
			r.fail("data.counters.counters", "row for unknown tower %s" % id)
	var ids: Array = _towers.keys()
	ids.sort()
	_tower_ids = PackedStringArray(ids)
	for i in ids.size():
		var t: TowerType = _towers[ids[i]]
		t.index = i


func _read_counter_row(r: DataReader, row: Dictionary, t: TowerType, rating_bp: Dictionary, path: String) -> void:
	for c in CLASSES.size():
		var cell: Dictionary = r.get_dict(row, CLASSES[c], path)
		var rating: String = r.get_string(cell, "rating", "%s.%s" % [path, CLASSES[c]])
		if not rating_bp.has(rating):
			r.fail("%s.%s.rating" % [path, CLASSES[c]], "unknown rating %s" % rating)
			continue
		t.rating_bp[c] = rating_bp[rating]
	var cloaked: Dictionary = r.get_dict(row, "cloaked", path)
	t.unrevealed_bp = r.get_int(cloaked, "unrevealed_damage_bp", path + ".cloaked", 0, MAX_MULT_BP)


func _read_regen(r: DataReader, effects: Dictionary) -> void:
	var regen: Dictionary = r.get_dict(effects, "shield_regen", "data.status_effects")
	regen_per_second_x100 = r.get_int(regen, "per_second_x100", "data.status_effects.shield_regen", 0, MAX_STAT)
	regen_delay_ticks = r.get_ticks(regen, "delay_ms", "data.status_effects.shield_regen", 0, MAX_MS)
