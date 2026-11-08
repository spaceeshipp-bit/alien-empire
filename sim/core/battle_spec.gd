extends RefCounted
## A battle's inputs besides the config: seed, map lanes, waves and the command
## log (config/schema/battle.schema.json). Parsing re-checks every type and
## range, because the server will feed the sim worker specs built from player
## input.

const DataReader := preload("res://sim/core/data_reader.gd")
const LanePath := preload("res://sim/core/lane_path.gd")

const MAX_SEED: int = 9007199254740991
## 1,000 tiles: far beyond any map, small enough that squared distances can't overflow.
const MAX_COORD_MT: int = 1000000
const MAX_BATTLE_MS: int = 3600000
const MAX_GROUP_COUNT: int = 500
const MAX_SPAWNS: int = 100000
## Command types this sim version understands. M0 has none; M1 adds field towers.
const KNOWN_COMMANDS := []


class Group:
	extends RefCounted
	var enemy_id: String = ""
	var lane_index: int = 0
	var count: int = 0
	var first_tick: int = 0
	var interval_ticks: int = 0
	var jitter_ticks: int = 0


class Command:
	extends RefCounted
	var tick: int = 0
	var kind: String = ""
	var args: Dictionary = {}


var battle_id: String = ""
var mode: String = ""
var battle_seed: int = 0
var max_ticks: int = 0
var lane_ids: PackedStringArray = PackedStringArray()
var ground_paths: Array[LanePath] = []
## One entry per lane: a LanePath, or null when the lane has no air route.
var air_paths: Array = []
var groups: Array[Group] = []
var commands: Array[Command] = []
var total_spawns: int = 0
var errors: PackedStringArray = PackedStringArray()


## Reads a parsed battle spec. Returns false and fills errors if anything is wrong.
func parse(spec: Dictionary) -> bool:
	var r := DataReader.new()
	battle_id = r.get_string(spec, "battle_id", "spec")
	mode = r.get_string(spec, "mode", "spec")
	if mode != "pve":
		r.fail("spec.mode", "this sim version only runs pve battles")
	battle_seed = r.get_int(spec, "seed", "spec", 0, MAX_SEED)
	max_ticks = r.get_ticks(spec, "max_ms", "spec", 50, MAX_BATTLE_MS)
	_parse_map(r, r.get_dict(spec, "map", "spec"))
	_parse_waves(r, r.get_array(spec, "waves", "spec"))
	_parse_commands(r, r.get_array(spec, "commands", "spec"))
	errors = r.errors
	return errors.is_empty()


func _parse_map(r: DataReader, map_data: Dictionary) -> void:
	lane_ids = PackedStringArray()
	ground_paths = []
	air_paths = []
	var lanes: Array = r.get_array(map_data, "lanes", "spec.map")
	if lanes.is_empty():
		r.fail("spec.map.lanes", "needs at least one lane")
	for i in lanes.size():
		var path: String = "spec.map.lanes[%d]" % i
		var lane: Dictionary = r.item_dict(lanes, i, "spec.map.lanes")
		var id: String = r.get_string(lane, "id", path)
		if lane_ids.has(id):
			r.fail(path + ".id", "duplicate lane id %s" % id)
		lane_ids.append(id)
		ground_paths.append(_parse_path(r, r.get_array(lane, "ground", path), path + ".ground"))
		if lane.has("air"):
			air_paths.append(_parse_path(r, r.get_array(lane, "air", path), path + ".air"))
		else:
			air_paths.append(null)


func _parse_path(r: DataReader, points: Array, path: String) -> LanePath:
	var px := PackedInt64Array()
	var py := PackedInt64Array()
	for i in points.size():
		var where: String = "%s[%d]" % [path, i]
		var point: Variant = points[i]
		if typeof(point) != TYPE_ARRAY or (point as Array).size() != 2:
			r.fail(where, "expected [x, y]")
			continue
		var pair: Array = point
		var x: int = r.to_int(pair[0], where + "[0]")
		var y: int = r.to_int(pair[1], where + "[1]")
		if x < 0 or x > MAX_COORD_MT or y < 0 or y > MAX_COORD_MT:
			r.fail(where, "coordinates must be within 0..%d" % MAX_COORD_MT)
		px.append(x)
		py.append(y)
	var lane_path := LanePath.new()
	var problem: String = lane_path.build(px, py)
	if not problem.is_empty():
		r.fail(path, problem)
	return lane_path


func _parse_waves(r: DataReader, waves: Array) -> void:
	groups = []
	total_spawns = 0
	for w in waves.size():
		var wave_path: String = "spec.waves[%d]" % w
		var wave: Dictionary = r.item_dict(waves, w, "spec.waves")
		var start_tick: int = r.get_ticks(wave, "start_ms", wave_path, 0, MAX_BATTLE_MS)
		var list: Array = r.get_array(wave, "groups", wave_path)
		if list.is_empty():
			r.fail(wave_path + ".groups", "needs at least one group")
		for g in list.size():
			var path: String = "%s.groups[%d]" % [wave_path, g]
			var d: Dictionary = r.item_dict(list, g, wave_path + ".groups")
			var group := Group.new()
			group.enemy_id = r.get_string(d, "enemy", path)
			var lane_id: String = r.get_string(d, "lane", path)
			group.lane_index = lane_ids.find(lane_id)
			if group.lane_index < 0:
				r.fail(path + ".lane", "unknown lane %s" % lane_id)
				group.lane_index = 0
			group.count = r.get_int(d, "count", path, 1, MAX_GROUP_COUNT)
			group.first_tick = start_tick + r.get_ticks(d, "offset_ms", path, 0, MAX_BATTLE_MS)
			group.interval_ticks = r.get_ticks(d, "interval_ms", path, 0, MAX_BATTLE_MS)
			group.jitter_ticks = r.get_ticks(d, "jitter_ms", path, 0, MAX_BATTLE_MS)
			total_spawns += group.count
			groups.append(group)
	if total_spawns > MAX_SPAWNS:
		r.fail("spec.waves", "%d spawns is over the limit of %d" % [total_spawns, MAX_SPAWNS])


func _parse_commands(r: DataReader, list: Array) -> void:
	commands = []
	var previous_tick: int = 0
	for i in list.size():
		var path: String = "spec.commands[%d]" % i
		var d: Dictionary = r.item_dict(list, i, "spec.commands")
		var command := Command.new()
		command.tick = r.get_int(d, "tick", path, 0, MAX_BATTLE_MS / 50)
		command.kind = r.get_string(d, "type", path)
		command.args = r.get_dict(d, "args", path)
		if command.tick < previous_tick:
			r.fail(path + ".tick", "commands must be in tick order")
		previous_tick = command.tick
		if not KNOWN_COMMANDS.has(command.kind):
			r.fail(path + ".type", "unknown command type %s" % command.kind)
		commands.append(command)
