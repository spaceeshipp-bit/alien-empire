extends Node2D
## Short-lived light: tracers, railgun beams, splash rings, sparks and floating
## credits. Everything here adds light (additive blending), drawn in one pass
## each frame, so hundreds of effects cost one node.

const Art := preload("res://game/art.gd")

var _tracers: Array = []  # [from, to, color, width, life, max_life]
var _rings: Array = []  # [center, r0, r1, color, width, life, max_life]
var _sparks: Array = []  # [pos, vel, color, size, life, max_life]
var _texts: Array = []  # [pos, text, color, life, max_life]
var _font: Font
var shake: float = 0.0


func _ready() -> void:
	material = Art.additive()
	_font = ThemeDB.fallback_font


func tracer(from: Vector2, to: Vector2, color: Color, width: float, life: float) -> void:
	_tracers.append([from, to, color, width, life, life])


func ring(center: Vector2, r0: float, r1: float, color: Color, width: float, life: float) -> void:
	_rings.append([center, r0, r1, color, width, life, life])


func burst(center: Vector2, color: Color, count: int, speed: float, size: float, life: float) -> void:
	for i in count:
		var angle: float = TAU * (i + randf() * 0.6) / count
		var velocity: Vector2 = Vector2.from_angle(angle) * speed * randf_range(0.5, 1.0)
		_sparks.append([center, velocity, color, size * randf_range(0.6, 1.0), life, life])


func text(at: Vector2, value: String, color: Color) -> void:
	_texts.append([at, value, color, 0.9, 0.9])


func _process(delta: float) -> void:
	for list: Array in [_tracers, _rings, _texts]:
		for item: Array in list:
			item[item.size() - 2] -= delta
	for spark: Array in _sparks:
		spark[4] -= delta
		spark[0] += spark[1] * delta
		spark[1] *= 0.9
	_tracers = _tracers.filter(func(t: Array) -> bool: return t[4] > 0.0)
	_rings = _rings.filter(func(r: Array) -> bool: return r[5] > 0.0)
	_sparks = _sparks.filter(func(s: Array) -> bool: return s[4] > 0.0)
	_texts = _texts.filter(func(t: Array) -> bool: return t[3] > 0.0)
	shake = maxf(0.0, shake - delta * 3.0)
	queue_redraw()


func _draw() -> void:
	for t: Array in _tracers:
		var f: float = t[4] / t[5]
		var color: Color = t[2]
		draw_line(t[0], t[1], Color(color, f), t[3] * (0.5 + 0.5 * f), true)
		draw_line(t[0], t[1], Color(1, 1, 1, f * 0.7), t[3] * 0.3, true)
	for r: Array in _rings:
		var f: float = 1.0 - r[5] / r[6]
		var radius: float = lerpf(r[1], r[2], 1.0 - pow(1.0 - f, 3.0))
		var color: Color = r[3]
		draw_arc(r[0], radius, 0.0, TAU, 40, Color(color, 1.0 - f), r[4] * (1.0 - f * 0.5), true)
	for s: Array in _sparks:
		var f: float = s[4] / s[5]
		var color: Color = s[2]
		draw_circle(s[0], s[3] * f, Color(color, f))
	for t: Array in _texts:
		var f: float = t[3] / t[4]
		var at: Vector2 = t[0] + Vector2(0, -28.0 * (1.0 - f))
		var color: Color = t[2]
		draw_string(_font, at + Vector2(-30, 0), t[1], HORIZONTAL_ALIGNMENT_CENTER, 60, 22, Color(color, f))
