extends Node2D
## One field tower on screen: a fixed base and a head that turns to aim, with
## recoil and a muzzle flash when it fires, a pop when built or upgraded, and
## pips for its level (docs/ART.md).

const Art := preload("res://game/art.gd")
const Palette := preload("res://art/palette.gd")

var id: int = 0
var tower_id: String = ""
var level: int = 1
var aim: float = -PI / 2.0
var has_target: bool = false
var _base: Sprite2D
var _head: Sprite2D
var _flash: Sprite2D
var _tile: float = 80.0
var _recoil: float = 0.0
var _flash_t: float = 0.0
var _pop: float = 0.0
var _scale: float = 1.0
var _idle: float = 0.0


func _init() -> void:
	_base = Sprite2D.new()
	_base.texture = Art.tower_base()
	add_child(_base)
	_head = Sprite2D.new()
	add_child(_head)
	_flash = Sprite2D.new()
	_flash.texture = Art.halo()
	_flash.material = Art.additive()
	_flash.visible = false
	add_child(_flash)


func setup(tower_index_id: int, type_id: String, tile_px: float) -> void:
	id = tower_index_id
	tower_id = type_id
	_tile = tile_px
	_scale = Art.sprite_scale(tile_px)
	_base.scale = Vector2(_scale, _scale)
	_head.texture = Art.tower_head(type_id)
	_head.scale = Vector2(_scale, _scale)
	_head.rotation = 0.0
	aim = -PI / 2.0
	_idle = randf() * TAU
	level = 1
	pop()
	queue_redraw()


func set_level(new_level: int) -> void:
	if new_level != level:
		level = new_level
		pop()
		queue_redraw()


func pop() -> void:
	_pop = 1.0


## Fires toward angle (radians, screen space).
func fire(angle: float) -> void:
	aim = angle
	_recoil = 1.0
	_flash_t = 0.09
	var color: Color = Palette.HEAT if tower_id == "plasma_torch" else Palette.YOU
	_flash.modulate = Color(color, 0.9)


## Where shots leave the barrel, in the parent's coordinates.
func muzzle() -> Vector2:
	return position + Vector2.from_angle(aim) * _tile * (0.55 if tower_id == "railgun" else 0.38)


func animate(delta: float) -> void:
	if not has_target:
		_idle += delta * 0.6
		aim = lerp_angle(aim, -PI / 2.0 + sin(_idle) * 0.5, delta * 1.5)
	_head.rotation = lerp_angle(_head.rotation, aim + PI / 2.0, minf(1.0, delta * 18.0))
	_recoil = maxf(0.0, _recoil - delta * 7.0)
	_head.position = -Vector2.from_angle(aim) * _tile * 0.07 * _recoil
	if _flash_t > 0.0:
		_flash_t -= delta
		_flash.visible = true
		_flash.position = Vector2.from_angle(aim) * _tile * (0.55 if tower_id == "railgun" else 0.38)
		var size: float = _tile * 0.5 * (0.6 + _flash_t / 0.09)
		_flash.scale = Vector2.ONE * size / (100.0 * Art.PX_PER_UNIT)
	else:
		_flash.visible = false
	if _pop > 0.0:
		_pop = maxf(0.0, _pop - delta * 4.0)
	var s: float = 1.0 + 0.28 * _pop * _pop
	scale = Vector2(s, s)


func _draw() -> void:
	var pips: int = level
	var gap: float = _tile * 0.12
	var y: float = _tile * 0.36
	for i in pips:
		var x: float = (i - (pips - 1) / 2.0) * gap
		draw_circle(Vector2(x, y), _tile * 0.035, Palette.YOU)
