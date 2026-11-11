extends "res://sim/tests/test_case.gd"

const SimConfig := preload("res://sim/core/sim_config.gd")
const DataReader := preload("res://sim/core/data_reader.gd")
const BUNDLE := "res://sim/tests/golden/config_bundle.json"


func test_loads_the_frozen_bundle() -> bool:
	var bundle: Dictionary = load_json(BUNDLE)
	var config := SimConfig.new()
	expect_true(config.load_bundle(bundle), "bundle loads: %s" % str(config.errors))
	expect_eq(config.config_hash, String(bundle.get("config_hash", "")), "config hash")
	var ids: PackedStringArray = config.enemy_ids()
	expect_true(ids.size() > 0, "aliens loaded")
	var sorted_ids: Array = Array(ids)
	sorted_ids.sort()
	expect_eq(Array(ids), sorted_ids, "ids in sorted order")
	for i in ids.size():
		expect_eq(config.enemy(ids[i]).index, i, "index of %s" % ids[i])
	return true


func test_values_match_the_bundle() -> bool:
	var bundle: Dictionary = load_json(BUNDLE)
	var config := SimConfig.new()
	expect_true(config.load_bundle(bundle), "bundle loads")
	for entry in bundle["data"]["enemies"]["enemies"]:
		var id: String = String(entry["id"])
		var enemy_type: SimConfig.EnemyType = config.enemy(id)
		expect_eq(enemy_type.hp_x100, int(entry["hp_x100"]), "%s hp" % id)
		expect_eq(enemy_type.shield_x100, int(entry["shield_x100"]), "%s shield" % id)
		expect_eq(enemy_type.speed_mtps, int(entry["speed_mtps"]), "%s speed" % id)
		expect_eq(enemy_type.air, String(entry["movement"]) == "air", "%s movement" % id)
		expect_eq(enemy_type.leak_lives, int(entry["leak_lives"]), "%s leak lives" % id)
	return true


func test_refuses_decimal_values() -> bool:
	var bundle: Dictionary = load_json(BUNDLE)
	bundle["data"]["enemies"]["enemies"][0]["speed_mtps"] = 1.5
	var config := SimConfig.new()
	expect_true(not config.load_bundle(bundle), "a decimal speed is refused")
	expect_true(_mentions(config.errors, "whole number"), "error explains why: %s" % str(config.errors))
	return true


## Seeds go up to 2^53 - 1 (battle.schema.json), and Godot's JSON parser hands
## them over as floats.
func test_reads_the_largest_exact_json_int() -> bool:
	var values: Array = JSON.parse_string("[9007199254740991, 9007199254740992]")
	var reader := DataReader.new()
	expect_eq(reader.to_int(values[0], "largest"), 9007199254740991, "2^53 - 1 is read exactly")
	expect_eq(reader.errors.size(), 0, "no error for 2^53 - 1")
	reader.to_int(values[1], "too_big")
	expect_eq(reader.errors.size(), 1, "2^53 is refused: past it, a float can't hold every whole number")
	return true


## Godot's JSON parser rounds decimals before anything can check them, so the
## reader refuses decimal notation in the text itself.
func test_json_reader_refuses_decimal_notation() -> bool:
	var refused := {
		"{\"seed\": 9007199254740991.0}": "arrives one lower as a float",
		"{\"seed\": 4503599627370495.5}": "arrives as a whole number",
		"{\"n\": 12.0}": "a whole value, but written as a decimal",
		"{\"n\": 1e3}": "an exponent",
		"{\"list\": [1, 2, -0.5]}": "a negative fraction in a list",
	}
	for text in refused:
		var result: Dictionary = _read_text(text)
		expect_true(not result["ok"], "%s is refused: %s" % [text, refused[text]])
		expect_true(String(result["error"]).contains("whole number"), "the error says why: %s" % result["error"])
	var fine: Dictionary = _read_text("{\"seed\": 9007199254740991, \"note\": \"1.5e3 \\\" -2.5\", \"n\": -7}")
	expect_true(fine["ok"], "whole numbers, and decimals inside strings, are fine: %s" % fine["error"])
	return true


func _read_text(text: String) -> Dictionary:
	var path := "user://test_json_reader.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	var result: Dictionary = JsonFile.read_dict(path)
	DirAccess.remove_absolute(path)
	return result


func test_refuses_missing_field() -> bool:
	var bundle: Dictionary = load_json(BUNDLE)
	var first: Dictionary = bundle["data"]["enemies"]["enemies"][0]
	first.erase("hp_x100")
	var config := SimConfig.new()
	expect_true(not config.load_bundle(bundle), "a missing field is refused")
	expect_true(_mentions(config.errors, "missing field hp_x100"), "error names the field: %s" % str(config.errors))
	return true


func test_refuses_bad_hash() -> bool:
	var bundle: Dictionary = load_json(BUNDLE)
	bundle["config_hash"] = "not-a-hash"
	var config := SimConfig.new()
	expect_true(not config.load_bundle(bundle), "a malformed config hash is refused")
	return true


func _mentions(lines: PackedStringArray, text: String) -> bool:
	for line in lines:
		if line.contains(text):
			return true
	return false
