extends "res://sim/tests/test_case.gd"

const LanePath := preload("res://sim/core/lane_path.gd")


func _path(points: Array) -> LanePath:
	var px := PackedInt64Array()
	var py := PackedInt64Array()
	for point in points:
		px.append(int(point[0]))
		py.append(int(point[1]))
	var lane := LanePath.new()
	expect_eq(lane.build(px, py), "", "build %s" % str(points))
	return lane


func test_lengths_and_positions() -> bool:
	var lane := _path([[0, 0], [3000, 4000], [3000, 10000]])
	expect_eq(lane.length, 11000, "length")
	expect_eq(lane.position_at(0), Vector2i(0, 0), "start")
	expect_eq(lane.position_at(2500), Vector2i(1500, 2000), "halfway along the first segment")
	expect_eq(lane.position_at(5000), Vector2i(3000, 4000), "the bend")
	expect_eq(lane.position_at(8000), Vector2i(3000, 7000), "second segment")
	expect_eq(lane.position_at(99999), Vector2i(3000, 10000), "clamped to the end")
	expect_eq(lane.position_at(-5), Vector2i(0, 0), "clamped to the start")
	return true


## Moving toward smaller coordinates must truncate toward zero, not floor.
func test_negative_direction_truncates() -> bool:
	var lane := _path([[5000, 5000], [2000, 1000]])
	expect_eq(lane.length, 5000, "length")
	expect_eq(lane.position_at(1), Vector2i(5000, 5000), "1 mt in")
	expect_eq(lane.position_at(4), Vector2i(4998, 4997), "4 mt in")
	return true


func test_repeated_points_are_skipped() -> bool:
	var lane := _path([[0, 0], [0, 0], [0, 1000], [0, 1000], [0, 3000]])
	expect_eq(lane.length, 3000, "length")
	expect_eq(lane.xs.size(), 3, "distinct waypoints")
	return true


func test_segment_lengths_are_floored() -> bool:
	var lane := _path([[0, 0], [1000, 1000]])
	expect_eq(lane.length, 1414, "floor of sqrt(2,000,000)")
	return true


func test_rejects_a_single_point() -> bool:
	var lane := LanePath.new()
	var problem: String = lane.build(PackedInt64Array([5, 5]), PackedInt64Array([7, 7]))
	expect_true(problem != "", "two copies of one point are refused")
	return true
