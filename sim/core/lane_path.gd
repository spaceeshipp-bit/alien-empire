extends RefCounted
## A lane: waypoints in mt with precomputed integer segment lengths, computed by
## the sim core (sim/native/src/core/lane_path.cpp). Aliens store only how far
## along the path they are; positions are derived from that distance when needed
## (targeting, drawing, state hashes).

var _native := SimNativeLanePath.new()

var xs: PackedInt64Array:
	get:
		return _native.get_xs()
var ys: PackedInt64Array:
	get:
		return _native.get_ys()
## Distance from the start of the path to each waypoint, in mt.
var starts: PackedInt64Array:
	get:
		return _native.get_starts()
## Total length in mt. Segment lengths are floored square roots, so this can be
## a few mt shorter than the true length; it's the same on every device.
var length: int:
	get:
		return _native.get_length()


## Builds the path from waypoint coordinates. Repeated consecutive points are
## skipped. Returns "" on success, or what's wrong.
func build(px: PackedInt64Array, py: PackedInt64Array) -> String:
	return _native.build(px, py)


## Position after travelling distance mt from the start, clamped to the ends.
func position_at(distance: int) -> Vector2i:
	return _native.position_at(distance)
