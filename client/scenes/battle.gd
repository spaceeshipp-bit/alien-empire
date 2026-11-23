extends Node2D
## The battle screen (M1): one stage, played live. The sim core advances 20
## times a second; the map draws between ticks; taps become commands for the
## next tick, the same commands a replay of the battle needs (D-034).
##
## User arguments, for CI and recordings:
##   --autoplay            a simple builder plays: the stage's reference layout,
##                         then upgrades, whenever the credits allow
##   --fast                run the whole battle at once (no waiting on frames)
##   --replay-out <path>   write the spec with its command log and the result,
##                         for the worker to replay and compare
##   --quit-at-end         quit when the battle ends

const S := preload("res://game/strings.gd")
const MapView := preload("res://game/map_view.gd")
const Hud := preload("res://game/hud.gd")
const Palette := preload("res://art/palette.gd")
const SimLibrary := preload("res://ui/sim_library.gd")
const JsonFile := preload("res://sim/core/json_file.gd")
const Stage := preload("res://sim/core/stage.gd")

const STAGE_ID := "landfall_01"
const BUNDLE := "res://data/config_bundle.json"
const TICK := 1.0 / 20.0
const MAX_TICKS_PER_FRAME := 8

var _battle: RefCounted
var _config: RefCounted
var _spec: RefCounted
var _spec_data: Dictionary = {}
var _stage: Dictionary = {}
var _map: MapView
var _hud: Hud
var _accumulator: float = 0.0
var _paused: bool = false
var _ended: bool = false
var _autoplay: bool = false
var _fast: bool = false
var _replay_out: String = ""
var _quit_at_end: bool = false
var _started: bool = false
var _speed: int = 1
## The tower whose card was tapped once: its range shows, and a second tap builds it.
var _armed: String = ""


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_autoplay = args.has("--autoplay")
	_fast = args.has("--fast")
	_quit_at_end = args.has("--quit-at-end")
	var out_at: int = args.find("--replay-out")
	if out_at >= 0 and out_at + 1 < args.size():
		_replay_out = args[out_at + 1]
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Hud.new()
	layer.add_child(_hud)
	_hud.pause_pressed.connect(_on_pause)
	_hud.resume_pressed.connect(_on_resume)
	_hud.restart_pressed.connect(func() -> void: get_tree().reload_current_scene())
	_hud.quit_pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/boot.tscn"))
	_hud.build_pressed.connect(_on_build)
	_hud.upgrade_pressed.connect(_on_upgrade)
	_hud.sell_pressed.connect(_on_sell)
	_hud.sheet_closed.connect(_deselect)
	_hud.start_pressed.connect(func() -> void:
		_started = true
		_deselect()
	)
	_hud.speed_pressed.connect(func() -> void:
		_speed = 2 if _speed == 1 else 1
		_hud.set_speed(_speed)
	)
	var problem: String = _start()
	if not problem.is_empty():
		_ended = true
		_hud.show_end(false, problem)
		printerr(problem)
		if _quit_at_end:
			get_tree().quit(1)


## Loads the config and the stage and sets up the battle. Returns "" or what went wrong.
func _start() -> String:
	if not SimLibrary.loaded():
		return S.t("error.no_sim")
	var bundle_file: Dictionary = JsonFile.read_dict(BUNDLE)
	if not bundle_file["ok"]:
		return S.t("error.setup", [bundle_file["error"]])
	var bundle: Dictionary = bundle_file["data"]
	_config = load("res://sim/core/sim_config.gd").new()
	if not _config.load_bundle(bundle):
		return S.t("error.setup", ["; ".join(_config.errors)])
	_stage = Stage.find(bundle, STAGE_ID)
	if _stage.is_empty():
		return S.t("error.setup", ["no stage " + STAGE_ID])
	# Waves have no jitter in M1 (D-033), so the seed changes nothing yet; the
	# server issues it from M4.
	_spec_data = Stage.build_spec(_stage, 1 + (Time.get_ticks_usec() % 1000000))
	_spec = load("res://sim/core/battle_spec.gd").new()
	if not _spec.parse(_spec_data):
		return S.t("error.setup", ["; ".join(_spec.errors)])
	_battle = load("res://sim/core/battle.gd").new()
	if not _battle.setup(_config, _spec):
		return S.t("error.setup", ["; ".join(_battle.errors)])
	var view: Vector2 = get_viewport().get_visible_rect().size
	var room := Vector2(view.x, view.y - Hud.TOP_HEIGHT - Hud.SHEET_HEIGHT)
	var tile: float = floorf(minf(room.x / float(_stage["width"]), room.y / float(_stage["height"])))
	var map_size := Vector2(float(_stage["width"]), float(_stage["height"])) * tile
	_map = MapView.new()
	_map.position = Vector2((view.x - map_size.x) / 2.0, Hud.TOP_HEIGHT + (room.y - map_size.y) / 2.0).floor()
	add_child(_map)
	_map.setup(_battle, _config, _stage, tile)
	_map.tile_tapped.connect(_on_tile)
	_started = _autoplay
	if not _started:
		_hud.show_start()
	_map.command_refused.connect(func() -> void: _hud.toast(S.t("build.cant_afford")))
	_update_hud()
	return ""


func _process(delta: float) -> void:
	if _ended or _paused or _battle == null:
		return
	if not _started:
		_update_hud()
		return
	if _fast:
		while not _ended:
			_step()
		_update_hud()
		return
	var tick_time: float = TICK / _speed
	_accumulator += delta
	var steps: int = 0
	while _accumulator >= tick_time and steps < MAX_TICKS_PER_FRAME and not _ended:
		_accumulator -= tick_time
		steps += 1
		_step()
	if steps == MAX_TICKS_PER_FRAME:
		_accumulator = 0.0  # a long stall: drop the backlog rather than race
	_map.alpha = clampf(_accumulator / tick_time, 0.0, 1.0)
	_update_hud()


func _step() -> void:
	if _autoplay:
		_autoplay_turn()
	var credits_before: int = _battle.credits_x100
	_battle.advance()
	_map.on_tick(credits_before)
	if _battle.outcome != 0:
		_finish()


func _update_hud() -> void:
	var tick: int = _battle.tick
	var starts: PackedInt64Array = _spec.wave_starts
	var wave: int = 0
	var next_seconds: int = -1
	for start: int in starts:
		if start <= tick:
			wave += 1
		elif next_seconds < 0:
			next_seconds = int(ceil(float(start - tick) * TICK))
	_hud.set_status(wave, starts.size(), next_seconds, _battle.lives, _battle.credits_x100 / 100)
	if wave < starts.size():
		_hud.set_next_wave(_wave_classes(wave), _uncovered(_wave_classes(wave)))
	else:
		_hud.set_next_wave([], [])


## The classes in wave index (counted from 0), in order of first appearance.
func _wave_classes(index: int) -> Array:
	var classes: Array = []
	for group: Dictionary in _spec_data["waves"][index]["groups"]:
		var klass: String = _config.enemy(String(group["enemy"])).enemy_class
		if not classes.has(klass):
			classes.append(klass)
	return classes


## Which of these classes no tower on the map can hit (before anything is built, none).
func _uncovered(classes: Array) -> Array:
	var built: Array = _battle.towers
	if built.is_empty():
		return []
	var out: Array = []
	for klass: String in classes:
		var c: int = _config.CLASSES.find(klass)
		var covered: bool = false
		for t: Dictionary in built:
			var tower: RefCounted = _config.tower(_config.tower_ids()[int(t.type_index)])
			if tower.rating_bp[c] > 0 and (klass != "cloaked" or tower.unrevealed_bp > 0):
				covered = true
		if not covered:
			out.append(klass)
	return out


func _on_tile(tile: Vector2i) -> void:
	if _ended or _paused:
		return
	if not _map.is_build_tile(tile):
		_deselect()
		return
	_map.selected = tile
	_armed = ""
	_show_sheet()


func _show_sheet() -> void:
	var tile: Vector2i = _map.selected
	if tile.x < 0:
		_hud.show_hint()
		return
	var tower: Dictionary = _map.tower_at(tile)
	var credits: int = _battle.credits_x100 / 100
	if tower.is_empty():
		var cards: Array = []
		for id: String in _spec.tower_ids:
			cards.append({"id": id, "cost": _config.tower(id).cost_credits, "classes": _shown_classes(id)})
		_hud.show_build(cards, credits, _armed)
		_map.preview_range = float(_config.tower(_armed).range_mt) * _map.k if not _armed.is_empty() else 0.0
		return
	var tower_type: String = _config.tower_ids()[int(tower.type_index)]
	var upgrade: int = int(tower.upgrade_cost_x100)
	_hud.show_tower(tower_type, int(tower.level), float(tower.damage_x100) / 100.0, float(tower.range_mt) / 1000.0,
			-1 if upgrade < 0 else int(ceil(upgrade / 100.0)), int(tower.refund_x100) / 100, credits)


## The class icons a tower's card shows: what it's strong against, and air if it can hit air.
func _shown_classes(tower_id: String) -> Array:
	var t: RefCounted = _config.tower(tower_id)
	var classes: Array = []
	for i in t.rating_bp.size():
		if t.rating_bp[i] > 10000:
			classes.append(_config.CLASSES[i])
	var air: int = _config.CLASSES.find("air")
	if t.rating_bp[air] > 0 and not classes.has("air"):
		classes.append("air")
	return classes


func _deselect() -> void:
	_armed = ""
	if _map != null:
		_map.selected = Vector2i(-1, -1)
		_map.preview_range = 0.0
	if _started or _ended:
		_hud.show_hint()
	else:
		_hud.show_start()


func _on_build(tower_id: String) -> void:
	var tile: Vector2i = _map.selected
	if tile.x < 0:
		return
	if _battle.credits_x100 < _config.tower(tower_id).cost_credits * 100:
		_hud.toast(S.t("build.cant_afford"))
		return
	if _armed != tower_id:
		# First tap: show where it would reach; a second tap builds.
		_armed = tower_id
		_show_sheet()
		return
	var problem: String = _battle.queue_command("place", tile, tower_id)
	if not problem.is_empty():
		_hud.toast(problem)
		return
	_deselect()


func _on_upgrade() -> void:
	var tower: Dictionary = _map.tower_at(_map.selected)
	if tower.is_empty() or int(tower.upgrade_cost_x100) < 0:
		return
	if _battle.credits_x100 < int(tower.upgrade_cost_x100):
		_hud.toast(S.t("build.cant_afford"))
		return
	var problem: String = _battle.queue_command("upgrade", _map.selected)
	if not problem.is_empty():
		_hud.toast(problem)
		return
	_deselect()


func _on_sell() -> void:
	if _map.tower_at(_map.selected).is_empty():
		return
	var problem: String = _battle.queue_command("sell", _map.selected)
	if not problem.is_empty():
		_hud.toast(problem)
		return
	_deselect()


func _on_pause() -> void:
	if _ended:
		return
	_paused = true
	_hud.show_pause()


func _on_resume() -> void:
	_paused = false
	_hud.hide_overlay()


## A simple builder for recordings and the replay check: the stage's reference
## layout in order, then upgrades in the same order, one command a tick, only
## when the credits allow, so no command is ever refused.
func _autoplay_turn() -> void:
	var credits: int = _battle.credits_x100
	for place: Dictionary in _stage["reference_layout"]:
		var tile := Vector2i(int(place["tile"][0]), int(place["tile"][1]))
		if _map.tower_at(tile).is_empty() and not _queued_this_tick(tile):
			if credits >= _config.tower(String(place["tower"])).cost_credits * 100:
				_battle.queue_command("place", tile, String(place["tower"]))
			return
	for place: Dictionary in _stage["reference_layout"]:
		var tile := Vector2i(int(place["tile"][0]), int(place["tile"][1]))
		var tower: Dictionary = _map.tower_at(tile)
		var cost: int = int(tower.get("upgrade_cost_x100", -1))
		if cost >= 0:
			if credits >= cost and not _queued_this_tick(tile):
				_battle.queue_command("upgrade", tile)
			return


func _queued_this_tick(tile: Vector2i) -> bool:
	for c: Dictionary in _battle.command_log():
		if int(c["tick"]) >= _battle.tick and int(c["args"]["tile"][0]) == tile.x and int(c["args"]["tile"][1]) == tile.y:
			return true
	return false


func _finish() -> void:
	_ended = true
	var result: Dictionary = _battle.result()
	# Only clearing every wave wins; running out of time with aliens left is a loss.
	var won: bool = _battle.outcome == 1
	# Stars for lives kept (build prompt, Story campaign): all three for 90% or
	# more, two for half or more, one for clearing.
	var kept: float = float(_battle.lives) / float(_spec_data["lives"])
	var stars: int = 0 if not won else (3 if kept >= 0.9 else (2 if kept >= 0.5 else 1))
	var lines: PackedStringArray = PackedStringArray([S.t("end.stars", [stars]),
			S.t("end.stats", [result["kills"], result["lives"], int(result["credits_x100"]) / 100])])
	var best_id: int = -1
	for id: int in _map.kills_by_tower:
		if best_id < 0 or int(_map.kills_by_tower[id]) > int(_map.kills_by_tower[best_id]):
			best_id = id
	if best_id >= 0 and _map.built.has(best_id):
		lines.append(S.t("end.best", [S.t("tower." + String(_map.built[best_id][0])), _map.kills_by_tower[best_id]]))
	_hud.show_end(won, "\n".join(lines))
	print("Battle %s: %s at tick %d, lives %d, kills %d, credits %d, hash %s" % [
		_stage["id"], result["outcome"], result["ticks"], result["lives"], result["kills"],
		int(result["credits_x100"]) / 100, result["final_hash"]])
	if not _replay_out.is_empty():
		var spec_with_log: Dictionary = _spec_data.duplicate(true)
		spec_with_log["commands"] = _battle.command_log()
		var file := FileAccess.open(_replay_out, FileAccess.WRITE)
		if file == null:
			printerr("can't write %s: %s" % [_replay_out, error_string(FileAccess.get_open_error())])
			if _quit_at_end:
				get_tree().quit(1)
			return
		file.store_string(JSON.stringify({"spec": spec_with_log, "result": result}, " "))
		file.close()
	if _quit_at_end:
		get_tree().quit(0)
