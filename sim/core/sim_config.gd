extends RefCounted
## The balance values the sim uses, read from a config bundle (see
## config/schema/bundle.schema.json). The Python tools and the server run the
## full schema validation; this loader re-checks types and ranges so a bad
## bundle fails loudly instead of corrupting a battle.
##
## M0 reads the manifest and the aliens. Towers, counters, damage and status
## effects are read here when the sim starts using them (M1, M2).

const DataReader := preload("res://sim/core/data_reader.gd")

const BUNDLE_FORMAT: int = 1
## Generous upper bound for any single stat; real values are far smaller.
const MAX_STAT: int = 1000000000
const CLASSES := ["swarm", "armored", "shielded", "air", "cloaked", "titan"]


class EnemyType:
	extends RefCounted
	var id: String = ""
	## Position in id order. State hashes use it instead of the id text.
	var index: int = 0
	var enemy_class: String = ""
	var hp_x100: int = 0
	var armor: int = 0
	var shield_x100: int = 0
	var speed_mtps: int = 0
	var air: bool = false
	var leak_lives: int = 0


var config_version: int = 0
var config_hash: String = ""
var errors: PackedStringArray = PackedStringArray()
var _enemies: Dictionary = {}  # id -> EnemyType
var _enemy_ids: PackedStringArray = PackedStringArray()


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
		if not CLASSES.has(e.enemy_class):
			r.fail(path + ".class", "unknown class %s" % e.enemy_class)
		e.hp_x100 = r.get_int(d, "hp_x100", path, 1, MAX_STAT)
		e.armor = r.get_int(d, "armor", path, 0, MAX_STAT)
		e.shield_x100 = r.get_int(d, "shield_x100", path, 0, MAX_STAT)
		e.speed_mtps = r.get_int(d, "speed_mtps", path, 1, MAX_STAT)
		var movement: String = r.get_string(d, "movement", path)
		if movement != "ground" and movement != "air":
			r.fail(path + ".movement", "expected ground or air")
		e.air = movement == "air"
		e.leak_lives = r.get_int(d, "leak_lives", path, 1, MAX_STAT)
		if _enemies.has(e.id):
			r.fail(path + ".id", "duplicate id %s" % e.id)
		_enemies[e.id] = e
	var ids: Array = _enemies.keys()
	ids.sort()
	_enemy_ids = PackedStringArray(ids)
	for i in ids.size():
		var e: EnemyType = _enemies[ids[i]]
		e.index = i
