extends Node2D
## One alien on screen, pooled. Motion comes from code (build prompt): a walk
## bob that squashes and stretches, turning to face the way it walks, a white
## flash when hit, and a glow in its class color under it. Health and shield
## bars show once it has taken damage.

const Art := preload("res://game/art.gd")
const Palette := preload("res://art/palette.gd")

var id: int = 0
var color: Color = Color.WHITE
var facing: float = 0.0
var hp_ratio: float = 1.0
var shield_ratio: float = 0.0
var has_shield: bool = false
var air: bool = false
var flash: float = 0.0
var _body: Sprite2D
var _halo: Sprite2D
var _base_scale: float = 1.0
var _phase: float = 0.0
var _radius: float = 20.0
var _bob_speed: float = 9.0


func _init() -> void:
	_halo = Sprite2D.new()
	_halo.texture = Art.halo()
	_halo.material = Art.additive()
	add_child(_halo)
	_body = Sprite2D.new()
	add_child(_body)


func setup(alien_id: int, type_id: String, klass: String, is_air: bool, tile_px: float, speed_mtps: int) -> void:
	id = alien_id
	air = is_air
	var scale_by: float = float(Palette.ALIEN_SCALE.get(type_id, 1.0))
	_body.texture = Art.alien(type_id)
	_base_scale = Art.sprite_scale(tile_px) * scale_by
	_body.scale = Vector2(_base_scale, _base_scale)
	_body.modulate = Color.WHITE
	color = Art.class_color(klass)
	_halo.modulate = Color(color, 0.5 if not air else 0.35)
	var halo_px: float = tile_px * 0.95 * scale_by * float(Palette.SPRITE_UNITS.get(type_id, 100)) / 100.0
	_halo.scale = Vector2.ONE * halo_px / (100.0 * Art.PX_PER_UNIT)
	_radius = tile_px * 0.36 * scale_by * float(Palette.SPRITE_UNITS.get(type_id, 100)) / 100.0
	_phase = float(alien_id % 17) * 0.7
	# Faster aliens scurry: a quicker bob.
	_bob_speed = clampf(4.0 + speed_mtps / 250.0, 4.0, 14.0)
	flash = 0.0
	hp_ratio = 1.0
	shield_ratio = 1.0
	has_shield = false
	z_index = 2 if air else 0
	visible = true
	queue_redraw()


func set_health(hp: float, shield: float, shielded: bool) -> void:
	if not is_equal_approx(hp, hp_ratio) or not is_equal_approx(shield, shield_ratio) or shielded != has_shield:
		hp_ratio = hp
		shield_ratio = shield
		has_shield = shielded
		queue_redraw()


func hit() -> void:
	flash = 0.09


func animate(t: float, delta: float) -> void:
	var bob: float = sin(t * _bob_speed + _phase)
	var squash: float = 0.06 if not air else 0.02
	_body.scale = Vector2(_base_scale * (1.0 + squash * bob), _base_scale * (1.0 - squash * bob))
	_body.rotation = facing
	if air:
		_body.position = Vector2(0, -_radius * 0.12 * (1.0 + sin(t * 2.4 + _phase)))
	_halo.scale = _halo.scale  # the glow stays put; only the body bobs
	if flash > 0.0:
		flash -= delta
		var f: float = clampf(flash / 0.09, 0.0, 1.0)
		_body.modulate = Color.WHITE.lerp(Color(3.0, 3.0, 3.0), f)
	elif _body.modulate != Color.WHITE:
		_body.modulate = Color.WHITE


func _draw() -> void:
	if hp_ratio >= 0.999 and (not has_shield or shield_ratio >= 0.999):
		return
	var width: float = _radius * 1.7
	var top: float = -_radius * 1.35
	var bar := Rect2(Vector2(-width / 2.0, top), Vector2(width, 4.0))
	draw_rect(bar.grow(1.0), Color(0, 0, 0, 0.6))
	var hp_color: Color = Color(0.55, 1.0, 0.55).lerp(Palette.DANGER, 1.0 - hp_ratio)
	draw_rect(Rect2(bar.position, Vector2(width * maxf(hp_ratio, 0.0), 4.0)), hp_color)
	if has_shield:
		var shield_bar := Rect2(bar.position - Vector2(0, 6), Vector2(width * maxf(shield_ratio, 0.0), 3.0))
		draw_rect(shield_bar, Palette.CLASS_COLORS["shielded"])
