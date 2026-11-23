extends "res://sim/tests/test_case.gd"
## sim/core/stage.gd: a stage and a seed make the same battle spec as
## tools/stages.py (sim/tests/generated/stage_specs.json), and that spec plays.

const Stage := preload("res://sim/core/stage.gd")
const SimConfig := preload("res://sim/core/sim_config.gd")
const BattleSpec := preload("res://sim/core/battle_spec.gd")
const Battle := preload("res://sim/core/battle.gd")
const SPECS := "res://sim/tests/generated/stage_specs.json"
const BUNDLE := "res://sim/tests/golden/config_bundle.json"


## JSON numbers arrive as floats; whole ones compare as ints.
static func _plain(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			return int(value) if value == floorf(value) else value
		TYPE_ARRAY:
			var out: Array = []
			for item in value:
				out.append(_plain(item))
			return out
		TYPE_DICTIONARY:
			var out: Dictionary = {}
			for key in value:
				out[key] = _plain(value[key])
			return out
	return value


func test_stage_specs_match_the_python_builder() -> bool:
	var doc: Dictionary = load_json(SPECS)
	var entries: Array = doc["stages"]
	expect_true(entries.size() > 0, "at least one stage")
	for entry: Dictionary in entries:
		var built: Dictionary = Stage.build_spec(entry["stage"], int(entry["seed"]))
		expect_eq(_plain(built), _plain(entry["spec"]), "stage %s" % entry["stage"]["id"])
	return true


func test_wave_scaling_truncates_each_step() -> bool:
	# x1.09 per wave: 10000, 10900, 11881, 12950 (12950.29), 14115 (14115.5)
	var got: Array = []
	for w in 5:
		got.append(Stage.wave_scale_bp(10900, w))
	expect_eq(got, [10000, 10900, 11881, 12950, 14115], "x1.09")
	return true


func test_a_stage_plays_without_towers() -> bool:
	var doc: Dictionary = load_json(SPECS)
	var config := SimConfig.new()
	expect_true(config.load_bundle(load_json(BUNDLE)), "config loads")
	for entry: Dictionary in doc["stages"]:
		var spec := BattleSpec.new()
		expect_true(spec.parse(Stage.build_spec(entry["stage"], 7)), "spec parses: %s" % str(spec.errors))
		var battle := Battle.new()
		expect_true(battle.setup(config, spec), "battle sets up: %s" % str(battle.errors))
		var result: Dictionary = battle.run()
		expect_eq(result["outcome"], "lost", "with no towers the colony falls")
	return true
