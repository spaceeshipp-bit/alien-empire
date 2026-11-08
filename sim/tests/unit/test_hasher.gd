extends "res://sim/tests/test_case.gd"

const StateHasher := preload("res://sim/core/state_hasher.gd")


## Checks the byte layout (little-endian ints, length-prefixed UTF-8) against
## hashes computed by tools/gen_vectors.py.
func test_matches_reference_vectors() -> bool:
	var doc: Dictionary = load_json("res://sim/tests/vectors/hash_vectors.json")
	var cases: Array = doc.get("cases", [])
	expect_true(cases.size() >= 5, "hash vectors loaded")
	for case_data in cases:
		var hasher := StateHasher.new()
		for op in case_data["ops"]:
			if String(op[0]) == "int":
				hasher.add_int(int(op[1]))
			else:
				hasher.add_string(String(op[1]))
		expect_eq(hasher.finish_hex(), String(case_data["sha256"]), "case %s" % str(case_data["name"]))
	return true


func test_order_matters() -> bool:
	var a := StateHasher.new()
	a.add_int(1)
	a.add_int(2)
	var b := StateHasher.new()
	b.add_int(2)
	b.add_int(1)
	expect_true(a.finish_hex() != b.finish_hex(), "swapped values hash differently")
	return true
