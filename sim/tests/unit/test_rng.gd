extends "res://sim/tests/test_case.gd"

const SimRng := preload("res://sim/core/sim_rng.gd")
const VECTORS := "res://sim/tests/vectors/rng_vectors.json"


## Replays the call scripts from tools/gen_vectors.py for every seed.
func test_matches_reference_vectors() -> bool:
	var doc: Dictionary = load_json(VECTORS)
	var cases: Array = doc.get("rng", [])
	expect_true(cases.size() >= 8, "rng vectors loaded")
	for case_data in cases:
		var seed_value: int = int(case_data["seed"])
		var rng := SimRng.new(seed_value)
		var calls: Array = case_data["calls"]
		for i in calls.size():
			var call_data: Array = calls[i]
			var what: String = "seed %d call %d" % [seed_value, i]
			match String(call_data[0]):
				"u32":
					expect_eq(rng.next_u32(), int(call_data[1]), what)
				"range":
					expect_eq(rng.range_int(int(call_data[1]), int(call_data[2])), int(call_data[3]), what)
				"chance":
					expect_eq(rng.chance_bp(int(call_data[1])), bool(call_data[2]), what)
				_:
					expect_true(false, "%s: unknown call %s" % [what, str(call_data[0])])
		var state: PackedInt64Array = rng.get_state()
		var expected_state: Array = case_data["state_after"]
		for w in 4:
			expect_eq(state[w], int(expected_state[w]), "seed %d state word %d" % [seed_value, w])
	return true


func test_mul32_vectors() -> bool:
	var doc: Dictionary = load_json(VECTORS)
	var rows: Array = doc.get("mul32", [])
	expect_true(rows.size() > 10, "mul32 vectors loaded")
	for row in rows:
		var a: int = int(row[0])
		var b: int = int(row[1])
		expect_eq(SimRng.mul32(a, b), int(row[2]), "mul32(%d, %d)" % [a, b])
	return true


func test_state_round_trip() -> bool:
	var original := SimRng.new(77)
	for i in 5:
		original.next_u32()
	var copy := SimRng.new(1)
	copy.set_state(original.get_state())
	for i in 10:
		expect_eq(copy.next_u32(), original.next_u32(), "draw %d after restoring the state" % i)
	return true


func test_range_int_bounds() -> bool:
	var rng := SimRng.new(123)
	var seen: Dictionary = {}
	for i in 2000:
		var value: int = rng.range_int(-3, 3)
		expect_true(value >= -3 and value <= 3, "range_int(-3, 3) gave %d" % value)
		seen[value] = true
	expect_eq(seen.size(), 7, "every value from -3 to 3 appears")
	return true
