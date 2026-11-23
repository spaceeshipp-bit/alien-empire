extends Node2D
## The battle as the player sees it. It only reads the sim (sim/core/battle.gd):
## after every tick it copies where aliens and towers are, turns the tick's
## events into light and motion, and between ticks it slides every alien from
## where it was to where it is, so the 20-tick sim looks smooth at 60 fps. It
## never feeds anything back, so what's drawn can't change a battle's result.

signal tile_tapped(tile: Vector2i)
## The sim skipped a command: the state couldn't take it when it applied.
signal command_refused

const Ground := preload("res://game/ground.gd")
const AlienView := preload("res://game/alien_view.gd")
const TowerView := preload("res://game/tower_view.gd")
const FxLayer := preload("res://game/fx_layer.gd")
const Art := preload("res://game/art.gd")
const Palette := preload("res://art/palette.gd")
const SimConfig := preload("res://sim/core/sim_config.gd")
const STRIDE := 10
## Event kinds, as sim/core/battle.gd's Event: not preloaded here, so this
## script loads even where the sim library didn't.
const SHOT := 1
const KILL := 2
const LEAK := 3
const PLACED := 4
const UPGRADED := 5
const SOLD := 6
const REFUSED := 7

## Pixels a tile, and pixels a thousandth of a tile.
var tile_px: float = 80.0
var k: float = 0.08
## How far through the current tick the screen is, 0 to 1.
var alpha: float = 0.0
## The build tile the player picked, or (-1, -1).
var selected: Vector2i = Vector2i(-1, -1)
## A range to preview around the selected tile, in pixels (0 for none).
var preview_range: float = 0.0

var _battle: RefCounted  # sim/core/battle.gd
var _config: SimConfig
var _stage: Dictionary
var _ground: Ground
var _pads: Node2D
var _towers_layer: Node2D
var _aliens_layer: Node2D
var _fx: FxLayer
var _core: Sprite2D
var _core_glow: Sprite2D
var _aliens: Dictionary = {}  # alien id -> AlienView
var _pool: Array = []
var _prev: Dictionary = {}  # alien id -> Vector2, before the last tick
var _cur: Dictionary = {}  # alien id -> Vector2, after it
var _towers: Dictionary = {}  # tower id -> TowerView
var _tower_state: Dictionary = {}  # tower id -> the tower's Dictionary from the sim
var _sold: Dictionary = {}  # tower ids sold, so the end screen can still name them
## Every tower ever built: id -> [type id, tile], for the end screen.
var built: Dictionary = {}
var _enemy_ids: PackedStringArray = PackedStringArray()
var _tower_ids: PackedStringArray = PackedStringArray()
var _build_tiles: Dictionary = {}  # Vector2i -> true
var _time: float = 0.0
var _core_hit: float = 0.0
var _origin: Vector2 = Vector2.ZERO
## Kills by tower id, for the end screen.
var kills_by_tower: Dictionary = {}


func setup(battle: RefCounted, config: SimConfig, stage: Dictionary, tile_size: float) -> void:
	_battle = battle
	_config = config
	_stage = stage
	tile_px = tile_size
	k = tile_size / 1000.0
	_enemy_ids = config.enemy_ids()
	_tower_ids = config.tower_ids()
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for child in get_children():
		child.queue_free()
	_aliens.clear()
	_pool.clear()
	_prev.clear()
	_cur.clear()
	_towers.clear()
	_tower_state.clear()
	_build_tiles.clear()
	for t: Array in stage["build_tiles"]:
		_build_tiles[Vector2i(int(t[0]), int(t[1]))] = true
	_ground = Ground.new()
	add_child(_ground)
	_ground.setup(stage, tile_px)
	_pads = Node2D.new()
	_pads.draw.connect(_draw_pads)
	add_child(_pads)
	var core_at: Vector2 = (Vector2(float(stage["core"][0]), float(stage["core"][1])) + Vector2(0.5, 0.5)) * tile_px
	_core_glow = Sprite2D.new()
	_core_glow.texture = Art.halo()
	_core_glow.material = Art.additive()
	_core_glow.position = core_at
	_core_glow.modulate = Color(Palette.YOU, 0.45)
	add_child(_core_glow)
	_core = Sprite2D.new()
	_core.texture = Art.core()
	_core.position = core_at
	_core.scale = Vector2.ONE * Art.sprite_scale(tile_px) * 0.9
	add_child(_core)
	_towers_layer = Node2D.new()
	add_child(_towers_layer)
	_aliens_layer = Node2D.new()
	add_child(_aliens_layer)
	_fx = FxLayer.new()
	add_child(_fx)
	_origin = position


func size_px() -> Vector2:
	return _ground.size_px()


func core_position() -> Vector2:
	return _core.position


## Copies the sim's state after a tick and turns its events into effects.
## credits_before is the player's credits (x100) before the tick.
func on_tick(credits_before: int) -> void:
	var view: PackedInt64Array = _battle.alien_view()
	var present: Dictionary = {}
	for i in range(0, view.size(), STRIDE):
		var id: int = view[i]
		present[id] = true
		var at := Vector2(float(view[i + 4]), float(view[i + 5])) * k
		var alien: Variant = _aliens.get(id)
		if alien == null:
			alien = _take_view(id, view[i + 1], view[i + 2], view[i + 3] != 0)
			_prev[id] = at
		else:
			_prev[id] = _cur[id]
		_cur[id] = at
		var max_hp: float = maxf(1.0, float(view[i + 7]))
		var max_shield: int = view[i + 9]
		alien.set_health(float(view[i + 6]) / max_hp, float(view[i + 8]) / maxf(1.0, float(max_shield)), max_shield > 0)
	_sync_towers()
	_play_events(credits_before)
	for id: int in _aliens.keys():
		if not present.has(id):
			_release(id)


func _take_view(id: int, type_index: int, class_index: int, air: bool) -> AlienView:
	var alien: AlienView = _pool.pop_back() if not _pool.is_empty() else null
	if alien == null:
		alien = AlienView.new()
		_aliens_layer.add_child(alien)
	var type_id: String = _enemy_ids[type_index]
	alien.setup(id, type_id, SimConfig.CLASSES[class_index], air, tile_px, _config.enemy(type_id).speed_mtps)
	_aliens[id] = alien
	return alien


func _release(id: int) -> void:
	var alien: AlienView = _aliens[id]
	alien.visible = false
	_pool.append(alien)
	_aliens.erase(id)
	_prev.erase(id)
	_cur.erase(id)


func _sync_towers() -> void:
	var now: Dictionary = {}
	for t: Dictionary in _battle.towers:
		now[int(t.id)] = t
		var tower: TowerView = _towers.get(int(t.id))
		if tower == null:
			tower = TowerView.new()
			_towers_layer.add_child(tower)
			tower.setup(int(t.id), _tower_ids[int(t.type_index)], tile_px)
			tower.position = (Vector2(float(t.col), float(t.row)) + Vector2(0.5, 0.5)) * tile_px
			_towers[int(t.id)] = tower
			built[int(t.id)] = [_tower_ids[int(t.type_index)], Vector2i(int(t.col), int(t.row))]
		tower.set_level(int(t.level))
	for id: int in _towers.keys():
		if not now.has(id):
			_towers[id].queue_free()
			_towers.erase(id)
	_tower_state = now


func tower_at(tile: Vector2i) -> Dictionary:
	for t: Dictionary in _tower_state.values():
		if int(t.col) == tile.x and int(t.row) == tile.y:
			return t
	return {}


func is_build_tile(tile: Vector2i) -> bool:
	return _build_tiles.has(tile)


func _play_events(credits_before: int) -> void:
	var events: PackedInt64Array = _battle.events()
	var kills: Array = []
	var commands: bool = false
	for i in range(0, events.size(), 5):
		var kind: int = events[i]
		var at := Vector2(float(events[i + 3]), float(events[i + 4])) * k
		match kind:
			SHOT:
				_shot(int(events[i + 1]), int(events[i + 2]), at)
			KILL:
				var killer: int = int(events[i + 2])
				kills_by_tower[killer] = int(kills_by_tower.get(killer, 0)) + 1
				var alien: AlienView = _aliens.get(int(events[i + 1]))
				var color: Color = alien.color if alien != null else Palette.TEXT
				_fx.burst(at, color, 12, tile_px * 2.2, tile_px * 0.09, 0.45)
				_fx.ring(at, tile_px * 0.1, tile_px * 0.5, color, 3.0, 0.3)
				kills.append(at)
			LEAK:
				Input.vibrate_handheld(60)
				_core_hit = 1.0
				_fx.shake = 1.0
				_fx.ring(_core.position, tile_px * 0.4, tile_px * 1.6, Palette.DANGER, 5.0, 0.5)
			PLACED:
				commands = true
				_fx.ring(at, tile_px * 0.2, tile_px * 0.8, Palette.YOU, 4.0, 0.4)
				_fx.burst(at, Palette.YOU, 10, tile_px * 1.6, tile_px * 0.06, 0.35)
			UPGRADED:
				commands = true
				_fx.ring(at, tile_px * 0.3, tile_px * 0.9, Palette.YOU, 5.0, 0.45)
				_fx.burst(at, Palette.EYE, 14, tile_px * 1.8, tile_px * 0.06, 0.45)
			REFUSED:
				command_refused.emit()
			SOLD:
				commands = true
				_fx.burst(at, Palette.YOU, 18, tile_px * 2.4, tile_px * 0.07, 0.5)
				_sold[int(events[i + 1])] = true
	# Kill credits float up from the kills: what the credits gained this tick,
	# shared between them. In the rare tick that also ran a command, the gain
	# mixes in its cost, so the numbers are skipped rather than guessed.
	if not kills.is_empty() and not commands:
		var each: int = int(round(float(_battle.credits_x100 - credits_before) / kills.size() / 100.0))
		if each > 0:
			for at: Vector2 in kills:
				_fx.text(at, "+%d" % each, Palette.EYE)


func _shot(tower_id: int, target_id: int, impact: Vector2) -> void:
	var tower: TowerView = _towers.get(tower_id)
	if tower == null:
		return
	var angle: float = (impact - tower.position).angle()
	tower.fire(angle)
	var from: Vector2 = tower.muzzle()
	var target: AlienView = _aliens.get(target_id)
	if target != null:
		target.hit()
	match tower.tower_id:
		"railgun":
			_fx.tracer(from, impact, Palette.YOU, tile_px * 0.16, 0.22)
			_fx.ring(impact, tile_px * 0.05, tile_px * 0.35, Palette.YOU, 3.0, 0.25)
		"plasma_torch":
			var splash: float = float(_config.tower("plasma_torch").splash_mt) * k
			_fx.tracer(from, impact, Palette.HEAT, tile_px * 0.12, 0.12)
			_fx.ring(impact, tile_px * 0.1, splash, Palette.HEAT, 4.0, 0.3)
			_fx.burst(impact, Palette.HEAT, 6, tile_px * 1.2, tile_px * 0.07, 0.25)
			for other: AlienView in _aliens.values():
				if other.position.distance_to(impact) <= splash and not other.air:
					other.hit()
		_:
			_fx.tracer(from, impact, Palette.YOU, tile_px * 0.06, 0.09)
			_fx.burst(impact, Palette.YOU, 3, tile_px * 0.8, tile_px * 0.04, 0.15)


func _process(delta: float) -> void:
	_time += delta
	for id: int in _aliens:
		var alien: AlienView = _aliens[id]
		var from: Vector2 = _prev[id]
		var to: Vector2 = _cur[id]
		alien.position = from.lerp(to, alpha)
		var step: Vector2 = to - from
		if step.length_squared() > 0.01:
			alien.facing = lerp_angle(alien.facing, step.angle() - PI / 2.0, minf(1.0, delta * 12.0))
		alien.animate(_time, delta)
	for tower: TowerView in _towers.values():
		var state: Dictionary = _tower_state.get(tower.id, {})
		var target_id: int = int(state.get("target_id", 0))
		var target: AlienView = _aliens.get(target_id)
		tower.has_target = target != null
		if target != null:
			tower.aim = (target.position - tower.position).angle()
		tower.animate(delta)
	_core_hit = maxf(0.0, _core_hit - delta * 2.0)
	var pulse: float = 1.0 + 0.04 * sin(_time * 2.2)
	_core.scale = Vector2.ONE * Art.sprite_scale(tile_px) * 0.9 * pulse
	_core.modulate = Color.WHITE.lerp(Color(2.0, 0.5, 0.5), _core_hit)
	var glow_px: float = tile_px * (2.6 + 0.3 * sin(_time * 2.2) + 1.2 * _core_hit)
	_core_glow.scale = Vector2.ONE * glow_px / (100.0 * Art.PX_PER_UNIT)
	_core_glow.modulate = Color(Palette.YOU, 0.45).lerp(Color(Palette.DANGER, 0.7), _core_hit)
	position = _origin + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 6.0 * _fx.shake * _fx.shake
	_pads.queue_redraw()


func _draw_pads() -> void:
	var glow: float = 0.45 + 0.25 * sin(_time * 3.0)
	for tile: Vector2i in _build_tiles:
		var rect := Rect2(Vector2(tile) * tile_px, Vector2(tile_px, tile_px)).grow(-tile_px * 0.1)
		var taken: bool = not tower_at(tile).is_empty()
		_pads.draw_rect(rect, Color(Palette.PANEL, 0.85))
		var bracket: float = tile_px * 0.2
		var color: Color = Color(Palette.YOU, glow if not taken else 0.25)
		if tile == selected:
			color = Color(Palette.YOU, 1.0)
			_pads.draw_rect(rect, Color(Palette.YOU, 0.14))
		for corner in 4:
			var cx: float = rect.position.x if corner % 2 == 0 else rect.end.x
			var cy: float = rect.position.y if corner < 2 else rect.end.y
			var sx: float = 1.0 if corner % 2 == 0 else -1.0
			var sy: float = 1.0 if corner < 2 else -1.0
			_pads.draw_polyline(PackedVector2Array([Vector2(cx, cy + sy * bracket), Vector2(cx, cy), Vector2(cx + sx * bracket, cy)]), color, 2.5, true)
	if selected.x >= 0:
		var center: Vector2 = (Vector2(selected) + Vector2(0.5, 0.5)) * tile_px
		var radius: float = preview_range
		var tower: Dictionary = tower_at(selected)
		if not tower.is_empty():
			radius = float(tower.range_mt) * k
		if radius > 0.0:
			_pads.draw_circle(center, radius, Color(Palette.YOU, 0.06))
			var dashes: int = 48
			for i in dashes:
				if i % 2 == 0:
					_pads.draw_arc(center, radius, TAU * i / dashes, TAU * (i + 1) / dashes, 4, Color(Palette.YOU, 0.7), 2.0, true)


func _unhandled_input(event: InputEvent) -> void:
	var press := event as InputEventMouseButton
	if press == null or not press.pressed or press.button_index != MOUSE_BUTTON_LEFT:
		return
	var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * press.position
	var tile := Vector2i(floori(local.x / tile_px), floori(local.y / tile_px))
	if local.x < 0 or local.y < 0 or local.x >= size_px().x or local.y >= size_px().y:
		return
	get_viewport().set_input_as_handled()
	tile_tapped.emit(tile)
