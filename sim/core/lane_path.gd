extends RefCounted
## A lane: waypoints in mt with precomputed integer segment lengths. Aliens
## store only how far along the path they are; positions are derived from that
## distance when needed (targeting, drawing, state hashes).

const Fx := preload("res://sim/core/fx.gd")

var xs: PackedInt64Array = PackedInt64Array()
var ys: PackedInt64Array = PackedInt64Array()
## Distance from the start of the path to each waypoint, in mt.
var starts: PackedInt64Array = PackedInt64Array()
## Total length in mt. Segment lengths are floored square roots, so this can be
## a few mt shorter than the true length; it's the same on every device.
var length: int = 0


## Builds the path from waypoint coordinates. Repeated consecutive points are
## skipped. Returns "" on success, or what's wrong.
func build(px: PackedInt64Array, py: PackedInt64Array) -> String:
	xs = PackedInt64Array()
	ys = PackedInt64Array()
	starts = PackedInt64Array()
	length = 0
	if px.size() != py.size():
		return "x and y lists differ in length"
	for i in px.size():
		var last: int = xs.size() - 1
		if last >= 0:
			var dx: int = px[i] - xs[last]
			var dy: int = py[i] - ys[last]
			if dx == 0 and dy == 0:
				continue
			length += Fx.isqrt(dx * dx + dy * dy)
		xs.append(px[i])
		ys.append(py[i])
		starts.append(length)
	if xs.size() < 2:
		return "needs at least two different points"
	return ""


## Position after travelling distance mt from the start, clamped to the ends.
func position_at(distance: int) -> Vector2i:
	var last: int = xs.size() - 1
	if distance <= 0:
		return Vector2i(xs[0], ys[0])
	if distance >= length:
		return Vector2i(xs[last], ys[last])
	var i: int = 0
	while i < last - 1 and starts[i + 1] <= distance:
		i += 1
	var seg: int = starts[i + 1] - starts[i]
	var into: int = distance - starts[i]
	var x: int = xs[i] + (xs[i + 1] - xs[i]) * into / seg
	var y: int = ys[i] + (ys[i + 1] - ys[i]) * into / seg
	return Vector2i(x, y)
