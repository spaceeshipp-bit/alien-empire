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
const MAX_STAT: int = 1000000000
const MAX_SCALE_BP: int = 1000000
const MAX_TILE: int = 999
const MAX_BUILD_TILES: int = 4096
const MAX_TOWERS_ALLOWED: int = 64
const MAX_COMMANDS: int = 100000
## Command types this sim version understands (D-034).
const KNOWN_COMMANDS := ["place", "upgrade", "sell"]


class Group:
	extends RefCounted
	var enemy_id: String = ""
	var lane_index: int = 0
	var count: int = 0
	var first_tick: int = 0
	var interval_ticks: int = 0
	var jitter_ticks: int = 0
	## The wave's scaling of HP and kill credits.
	var hp_bp: int = 10000
	var credits_bp: int = 10000
	## Which wave it belongs to, counted from 0.
	var wave_index: int = 0


class Command:
	extends RefCounted
	var tick: int = 0
	## place, upgrade or sell.
	var kind: String = ""
	## The tower to place; "" for upgrade and sell.
	var tower_id: String = ""
	var col: int = 0
	var row: int = 0


var battle_id: String = ""
var mode: String = ""
var battle_seed: int = 0
var max_ticks: int = 0
var lives: int = 0
var credits: int = 0
## Tower ids the player may build in this battle.
var tower_ids: PackedStringArray = PackedStringArray()
## Build tiles, as Vector2i(column, row).
var build_tiles: Array[Vector2i] = []
## The start tick of each wave.
var wave_starts: PackedInt64Array = PackedInt64Array()
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
	lives = r.get_int(spec, "lives", "spec", 1, MAX_STAT)
	credits = r.get_int(spec, "credits", "spec", 0, MAX_STAT)
	_parse_towers(r, r.get_array(spec, "towers", "spec"))
	_parse_map(r, r.get_dict(spec, "map", "spec"))
	_parse_waves(r, r.get_array(spec, "waves", "spec"))
	_parse_commands(r, r.get_array(spec, "commands", "spec"))
	errors = r.errors
	return errors.is_empty()


func has_build_tile(tile: Vector2i) -> bool:
	return build_tiles.has(tile)


func _parse_towers(r: DataReader, list: Array) -> void:
	tower_ids = PackedStringArray()
	if list.size() > MAX_TOWERS_ALLOWED:
		r.fail("spec.towers", "more than %d towers" % MAX_TOWERS_ALLOWED)
	for i in list.size():
		if typeof(list[i]) != TYPE_STRING:
			r.fail("spec.towers[%d]" % i, "expected a tower id")
			continue
		if tower_ids.has(list[i]):
			r.fail("spec.towers[%d]" % i, "tower %s is listed twice" % list[i])
		tower_ids.append(list[i])


func _parse_tile(r: DataReader, value: Variant, path: String) -> Vector2i:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 2:
		r.fail(path, "expected [column, row]")
		return Vector2i(-1, -1)
	var pair: Array = value
	var col: int = r.to_int(pair[0], path + "[0]")
	var row: int = r.to_int(pair[1], path + "[1]")
	if col < 0 or col > MAX_TILE or row < 0 or row > MAX_TILE:
		r.fail(path, "tiles must be within 0..%d" % MAX_TILE)
	return Vector2i(col, row)


func _parse_map(r: DataReader, map_data: Dictionary) -> void:
	lane_ids = PackedStringArray()
	ground_paths = []
	air_paths = []
	build_tiles = []
	var tiles: Array = r.get_array(map_data, "build_tiles", "spec.map")
	if tiles.size() > MAX_BUILD_TILES:
		r.fail("spec.map.build_tiles", "more than %d build tiles" % MAX_BUILD_TILES)
	for i in tiles.size():
		var tile: Vector2i = _parse_tile(r, tiles[i], "spec.map.build_tiles[%d]" % i)
		if build_tiles.has(tile):
			r.fail("spec.map.build_tiles[%d]" % i, "tile %s is listed twice" % tile)
		build_tiles.append(tile)
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
	wave_starts = PackedInt64Array()
	total_spawns = 0
	for w in waves.size():
		var wave_path: String = "spec.waves[%d]" % w
		var wave: Dictionary = r.item_dict(waves, w, "spec.waves")
		var start_tick: int = r.get_ticks(wave, "start_ms", wave_path, 0, MAX_BATTLE_MS)
		var hp_bp: int = r.get_int(wave, "hp_bp", wave_path, 1, MAX_SCALE_BP)
		var credits_bp: int = r.get_int(wave, "credits_bp", wave_path, 0, MAX_SCALE_BP)
		wave_starts.append(start_tick)
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
			group.hp_bp = hp_bp
			group.credits_bp = credits_bp
			group.wave_index = w
			total_spawns += group.count
			groups.append(group)
	if total_spawns > MAX_SPAWNS:
		r.fail("spec.waves", "%d spawns is over the limit of %d" % [total_spawns, MAX_SPAWNS])


func _parse_commands(r: DataReader, list: Array) -> void:
	commands = []
	var previous_tick: int = 0
	if list.size() > MAX_COMMANDS:
		r.fail("spec.commands", "more than %d commands" % MAX_COMMANDS)
	for i in list.size():
		var path: String = "spec.commands[%d]" % i
		var d: Dictionary = r.item_dict(list, i, "spec.commands")
		var command := Command.new()
		command.tick = r.get_int(d, "tick", path, 0, maxi(0, max_ticks - 1))
		command.kind = r.get_string(d, "type", path)
		var args: Dictionary = r.get_dict(d, "args", path)
		if command.tick < previous_tick:
			r.fail(path + ".tick", "commands must be in tick order")
		previous_tick = command.tick
		if not KNOWN_COMMANDS.has(command.kind):
			r.fail(path + ".type", "unknown command type %s" % command.kind)
			continue
		var allowed: Array = ["tower", "tile"] if command.kind == "place" else ["tile"]
		for key in args.keys():
			if not allowed.has(key):
				r.fail(path + ".args", "unexpected field %s" % key)
		var tile: Vector2i = _parse_tile(r, args.get("tile"), path + ".args.tile")
		command.col = tile.x
		command.row = tile.y
		if not build_tiles.has(tile):
			r.fail(path + ".args.tile", "%s isn't a build tile" % tile)
		if command.kind == "place":
			command.tower_id = r.get_string(args, "tower", path + ".args")
			if not tower_ids.has(command.tower_id):
				r.fail(path + ".args.tower", "tower %s isn't allowed in this battle" % command.tower_id)
		commands.append(command)
