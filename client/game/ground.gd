extends Node2D
## The stage's ground, drawn once: dark tiles, the hive's breaches where the
## lanes begin, the lanes themselves with their magenta glow (magenta marks the
## hive), the air routes, and the colony around the Core. Positions are in
## pixels: k pixels per thousandth of a tile.

const Palette := preload("res://art/palette.gd")
const LANE_FILL := Color(0.075, 0.105, 0.165)
const ROCK := Color(0.09, 0.13, 0.2)

var stage: Dictionary = {}
var tile: float = 80.0
var k: float = 0.08


func setup(stage_data: Dictionary, tile_px: float) -> void:
	stage = stage_data
	tile = tile_px
	k = tile_px / 1000.0
	for child in get_children():
		child.queue_free()
	for lane: Dictionary in stage["lanes"]:
		var points := PackedVector2Array()
		for p: Array in lane["ground"]:
			points.append(_px(p))
		_line(points, tile * 1.02, Color(Palette.HIVE, 0.06))
		_line(points, tile * 0.86, Color(Palette.HIVE, 0.28))
		_line(points, tile * 0.78, LANE_FILL)
		_line(points, tile * 0.05, Color(Palette.HIVE, 0.12))
	var marks := Node2D.new()
	marks.draw.connect(_draw_marks.bind(marks))
	add_child(marks)
	queue_redraw()


func size_px() -> Vector2:
	return Vector2(float(stage["width"]), float(stage["height"])) * tile


func _px(p: Array) -> Vector2:
	return Vector2(float(p[0]), float(p[1])) * k


func _line(points: PackedVector2Array, width: float, color: Color) -> Line2D:
	var line := Line2D.new()
	line.points = points
	line.width = width
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	add_child(line)
	return line


func _draw() -> void:
	if stage.is_empty():
		return
	var w: int = int(stage["width"])
	var h: int = int(stage["height"])
	draw_rect(Rect2(Vector2.ZERO, size_px()), Palette.GROUND)
	for r in h:
		for c in w:
			if (r + c) % 2 == 0:
				draw_rect(Rect2(Vector2(c, r) * tile, Vector2(tile, tile)), Color(Palette.GROUND_2, 0.55))
	# Rocks and alien growth: the same for every play of a stage.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(stage["id"]))
	for i in 46:
		var center := Vector2(rng.randf() * w, rng.randf() * h) * tile
		var radius: float = tile * rng.randf_range(0.06, 0.16)
		var points := PackedVector2Array()
		for j in 6:
			var angle: float = TAU * j / 6.0 + rng.randf() * 0.5
			points.append(center + Vector2.from_angle(angle) * radius * rng.randf_range(0.7, 1.2))
		draw_colored_polygon(points, ROCK)
		draw_polyline(points + PackedVector2Array([points[0]]), Color(0.17, 0.24, 0.35, 0.6), 1.5, true)
	for i in 30:
		var spot := Vector2(rng.randf() * w, rng.randf() * h * 0.6) * tile
		draw_circle(spot, tile * 0.035, Color(Palette.SHELL, 0.35))
	# The hive's breach at the top of each lane.
	for lane: Dictionary in stage["lanes"]:
		var start: Vector2 = _px(lane["ground"][0])
		for ring in 5:
			draw_circle(start, tile * (1.4 - ring * 0.22), Color(Palette.HIVE, 0.05 + ring * 0.025))
	# The colony: a lit plaza around the Core and a few domes.
	var core: Vector2 = (Vector2(float(stage["core"][0]), float(stage["core"][1])) + Vector2(0.5, 0.5)) * tile
	draw_circle(core, tile * 1.7, Color(Palette.YOU_DEEP, 0.10))
	draw_circle(core, tile * 1.25, Color(Palette.PANEL, 0.9))
	draw_arc(core, tile * 1.25, 0.0, TAU, 64, Color(Palette.YOU, 0.35), 2.0, true)
	for dome: Vector2 in [Vector2(-2.6, 0.7), Vector2(2.6, 0.7), Vector2(-3.4, 1.0), Vector2(3.4, 1.0), Vector2(-1.8, 1.2), Vector2(1.8, 1.2)]:
		var at: Vector2 = core + dome * tile
		draw_circle(at, tile * 0.3, Palette.PANEL_2)
		draw_arc(at, tile * 0.3, PI, TAU, 16, Color(Palette.YOU, 0.6), 2.0, true)
		draw_circle(at + Vector2(0, -tile * 0.08), tile * 0.05, Color(Palette.YOU, 0.8))


## Chevrons along each lane, pointing the way the hive walks, and the dashed air routes.
func _draw_marks(marks: Node2D) -> void:
	for lane: Dictionary in stage["lanes"]:
		var points: Array = lane["ground"]
		for i in points.size() - 1:
			var a: Vector2 = _px(points[i])
			var b: Vector2 = _px(points[i + 1])
			var dir: Vector2 = (b - a).normalized()
			var side: Vector2 = dir.orthogonal()
			var length: float = a.distance_to(b)
			var step: float = tile * 1.0
			var d: float = step * 0.5
			while d < length:
				var at: Vector2 = a + dir * d
				var tip: Vector2 = at + dir * tile * 0.1
				marks.draw_polyline(PackedVector2Array([tip - dir * tile * 0.16 + side * tile * 0.14, tip, tip - dir * tile * 0.16 - side * tile * 0.14]),
						Color(Palette.HIVE, 0.32), 2.0, true)
				d += step
		if lane.has("air"):
			var air: Array = lane["air"]
			for i in air.size() - 1:
				marks.draw_dashed_line(_px(air[i]), _px(air[i + 1]), Color(Palette.CLASS_COLORS["air"], 0.22), 2.0, tile * 0.22, true, true)
