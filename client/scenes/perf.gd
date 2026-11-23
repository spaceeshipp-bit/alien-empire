extends Node2D
## The performance screen (M1 done-when: 60 fps on a low-end phone). It draws
## the build prompt's ceiling of 300 entities: aliens of every kind walking the
## stage's lanes with their glows and bars, 18 towers turning and firing, and
## the effects that go with them, all with the battle screen's own nodes. It
## records every frame's time for 60 seconds and shows the 50th, 95th and 99th
## percentile, so a screenshot is the evidence. Nothing here runs the sim.
##
##   --perf-seconds <n>   measure for n seconds instead of 60 (CI)

const Ground := preload("res://game/ground.gd")
const AlienView := preload("res://game/alien_view.gd")
const TowerView := preload("res://game/tower_view.gd")
const FxLayer := preload("res://game/fx_layer.gd")
const JsonFile := preload("res://sim/core/json_file.gd")
const Stage := preload("res://sim/core/stage.gd")
const Palette := preload("res://art/palette.gd")

const ALIENS := 282
const TOWERS := 18
const TARGET_MS := 1000.0 / 60.0
const ALIEN_TYPES := [["swarmer", "swarm", false, 2000], ["carapace_brute", "armored", false, 700],
		["shield_drone", "shielded", false, 1200], ["skimmer", "air", true, 1600],
		["phaser", "cloaked", false, 1400], ["hive_carrier", "titan", false, 500]]

var _tile: float = 64.0
var _routes: Array = []  # [PackedVector2Array of points in px, total length]
var _walkers: Array = []  # [AlienView, route index, distance px, speed px/s]
var _towers: Array = []
var _fx: FxLayer
var _label: Label
var _samples: PackedFloat32Array = PackedFloat32Array()
var _seconds: float = 60.0
var _elapsed: float = 0.0
var _done: bool = false
var _time: float = 0.0


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var at: int = args.find("--perf-seconds")
	if at >= 0 and at + 1 < args.size():
		_seconds = float(args[at + 1])
	var bundle: Dictionary = JsonFile.read_dict("res://data/config_bundle.json")["data"]
	var stage: Dictionary = Stage.find(bundle, "landfall_01")
	var view: Vector2 = get_viewport().get_visible_rect().size
	_tile = floorf(minf(view.x / float(stage["width"]), (view.y - 160.0) / float(stage["height"])))
	var map := Node2D.new()
	map.position = Vector2((view.x - _tile * float(stage["width"])) / 2.0, 140.0)
	map.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(map)
	var ground := Ground.new()
	map.add_child(ground)
	ground.setup(stage, _tile)
	for lane: Dictionary in stage["lanes"]:
		for kind in ["ground", "air"]:
			if lane.has(kind):
				var points := PackedVector2Array()
				for p: Array in lane[kind]:
					points.append(Vector2(float(p[0]), float(p[1])) * _tile / 1000.0)
				var length: float = 0.0
				for i in points.size() - 1:
					length += points[i].distance_to(points[i + 1])
				_routes.append([points, length, kind == "air"])
	var tiles: Array = stage["build_tiles"]
	var kinds := ["pulse_turret", "plasma_torch", "railgun"]
	for i in mini(TOWERS, tiles.size()):
		var tower := TowerView.new()
		map.add_child(tower)
		tower.setup(i + 1, kinds[i % 3], _tile)
		tower.position = (Vector2(float(tiles[i][0]), float(tiles[i][1])) + Vector2(0.5, 0.5)) * _tile
		_towers.append(tower)
	for i in ALIENS:
		var kind: Array = ALIEN_TYPES[i % ALIEN_TYPES.size()]
		var routes: Array = []
		for r in _routes.size():
			if _routes[r][2] == kind[2]:
				routes.append(r)
		var route: int = routes[i % routes.size()]
		var alien := AlienView.new()
		map.add_child(alien)
		alien.setup(i + 1, kind[0], kind[1], kind[2], _tile, kind[3])
		alien.set_health(0.3 + 0.7 * fmod(i * 0.37, 1.0), 0.5, kind[1] == "shielded")
		_walkers.append([alien, route, fmod(i * 97.0, _routes[route][1]), float(kind[3]) * _tile / 1000.0])
	_fx = FxLayer.new()
	map.add_child(_fx)
	_label = Label.new()
	_label.position = Vector2(16, 16)
	_label.add_theme_font_size_override("font_size", 24)
	_label.add_theme_color_override("font_color", Palette.TEXT)
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(_label)
	var back := Button.new()
	back.text = "Back"
	back.position = Vector2(view.x - 140, 16)
	back.custom_minimum_size = Vector2(120, 64)
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/boot.tscn"))
	layer.add_child(back)


func _process(delta: float) -> void:
	_time += delta
	if not _done:
		_samples.append(delta * 1000.0)
		_elapsed += delta
	for w: Array in _walkers:
		var route: Array = _routes[w[1]]
		w[2] = fmod(w[2] + w[3] * delta, route[1])
		var alien: AlienView = w[0]
		var at: Vector2 = _point(route[0], w[2])
		var ahead: Vector2 = _point(route[0], minf(w[2] + 4.0, route[1]))
		alien.position = at
		alien.facing = (ahead - at).angle() - PI / 2.0
		alien.animate(_time, delta)
	for i in _towers.size():
		var tower: TowerView = _towers[i]
		var target: AlienView = _walkers[(i * 13 + int(_time * 2.0)) % _walkers.size()][0]
		tower.aim = (target.position - tower.position).angle()
		tower.has_target = true
		if fmod(_time + i * 0.11, 0.5) < delta:
			tower.fire(tower.aim)
			target.hit()
			_fx.tracer(tower.muzzle(), target.position, Palette.YOU, _tile * 0.06, 0.1)
			_fx.burst(target.position, target.color, 6, _tile * 1.5, _tile * 0.06, 0.3)
		tower.animate(delta)
	_label.text = _report()
	if not _done and _elapsed >= _seconds:
		_done = true
		print(_report().replace("\n", " | "))
		if OS.get_cmdline_user_args().has("--quit-at-end"):
			get_tree().quit(0)


func _point(points: PackedVector2Array, distance: float) -> Vector2:
	var left: float = distance
	for i in points.size() - 1:
		var length: float = points[i].distance_to(points[i + 1])
		if left <= length:
			return points[i].lerp(points[i + 1], left / maxf(length, 0.001))
		left -= length
	return points[points.size() - 1]


func _percentile(sorted_ms: PackedFloat32Array, p: float) -> float:
	if sorted_ms.is_empty():
		return 0.0
	return sorted_ms[mini(sorted_ms.size() - 1, int(p * sorted_ms.size()))]


func _report() -> String:
	var sorted_ms: PackedFloat32Array = _samples.duplicate()
	sorted_ms.sort()
	var p95: float = _percentile(sorted_ms, 0.95)
	var status: String
	if not _done:
		status = "Measuring: %d of %d s" % [int(_elapsed), int(_seconds)]
	else:
		status = "PASS: 95%% of frames within 16.7 ms (60 fps)" if p95 <= TARGET_MS else "FAIL: under 60 fps (30 fps saver: %s)" % ("PASS" if p95 <= 2.0 * TARGET_MS else "FAIL")
	return "Performance · %d entities · %s\n%s · Godot %s\nframe ms: p50 %.1f · p95 %.1f · p99 %.1f · %d frames\n%s" % [
		ALIENS + TOWERS, OS.get_model_name(), RenderingServer.get_video_adapter_name(),
		Engine.get_version_info()["string"], _percentile(sorted_ms, 0.5), p95, _percentile(sorted_ms, 0.99),
		sorted_ms.size(), status]
