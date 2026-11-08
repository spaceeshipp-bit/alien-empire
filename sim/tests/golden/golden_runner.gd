extends RefCounted
## Golden tests: fixed battles whose final state hash must match exactly on
## desktop, on Android and on the headless worker. The expected hashes are
## recorded once with the worker CLI (--record) and then verified everywhere.
##
## The scenarios run on a frozen config bundle (config_bundle.json), not the
## live balance files, so retuning balance never invalidates the goldens. Only
## a sim change (and a SIM_VERSION bump) means re-recording.

const JsonFile := preload("res://sim/core/json_file.gd")
const SimConfig := preload("res://sim/core/sim_config.gd")
const BattleSpec := preload("res://sim/core/battle_spec.gd")
const Battle := preload("res://sim/core/battle.gd")
const SimVersion := preload("res://sim/core/sim_version.gd")

const BUNDLE_PATH := "res://sim/tests/golden/config_bundle.json"
const EXPECTED_PATH := "res://sim/tests/golden/expected.json"
const SCENARIOS := [
	"res://sim/tests/golden/scenarios/g01_single_lane.json",
	"res://sim/tests/golden/scenarios/g02_bends_and_jitter.json",
	"res://sim/tests/golden/scenarios/g03_air_and_titans.json",
	"res://sim/tests/golden/scenarios/g04_dense_three_lanes.json",
]


## Runs every scenario and compares it with expected.json.
## Returns {"ok", "rows", "errors", "recorded", "config_hash"}. Each row is
## {"name", "status" (PASS, FAIL, NO GOLDEN or ERROR), "hash", "expected",
## "ticks", "entity_updates", "usec", "detail"}.
static func run_all() -> Dictionary:
	# Arrays and Dictionaries are shared by reference; packed arrays are not, so
	# errors are collected in a plain Array.
	var errors: Array = []
	var rows: Array = []
	var recorded: Dictionary = {}
	var config := SimConfig.new()
	var bundle_file: Dictionary = JsonFile.read_dict(BUNDLE_PATH)
	if not bundle_file["ok"]:
		errors.append(bundle_file["error"])
	elif not config.load_bundle(bundle_file["data"]):
		errors.append_array(Array(config.errors))
	if not errors.is_empty():
		return {"ok": false, "rows": rows, "errors": errors, "recorded": recorded, "config_hash": ""}
	var expected: Dictionary = _expected_scenarios(config, errors)
	var all_pass: bool = errors.is_empty()
	for path in SCENARIOS:
		var row: Dictionary = _run_one(path, config, expected, recorded)
		if row["status"] != "PASS":
			all_pass = false
		rows.append(row)
	return {"ok": all_pass, "rows": rows, "errors": errors, "recorded": recorded, "config_hash": config.config_hash}


## The expected.json document for a report, used when recording.
static func expected_document(report: Dictionary) -> Dictionary:
	return {
		"about": "Recorded by worker/cli/run_tests.gd --record. Every platform must reproduce these hashes.",
		"sim_version": SimVersion.SIM_VERSION,
		"config_hash": report["config_hash"],
		"recorded_with": "%s, Godot %s" % [OS.get_name(), Engine.get_version_info()["string"]],
		"scenarios": report["recorded"],
	}


static func _expected_scenarios(config: SimConfig, errors: Array) -> Dictionary:
	if not FileAccess.file_exists(EXPECTED_PATH):
		return {}
	var doc_file: Dictionary = JsonFile.read_dict(EXPECTED_PATH)
	if not doc_file["ok"]:
		errors.append(doc_file["error"])
		return {}
	var doc: Dictionary = doc_file["data"]
	var recorded_version: int = int(doc.get("sim_version", 0))
	if recorded_version != SimVersion.SIM_VERSION:
		errors.append("expected.json was recorded for sim version %d, this is %d: re-record it" % [recorded_version, SimVersion.SIM_VERSION])
	if String(doc.get("config_hash", "")) != config.config_hash:
		errors.append("expected.json was recorded with a different config bundle: re-record it")
	var scenarios: Variant = doc.get("scenarios", {})
	if typeof(scenarios) != TYPE_DICTIONARY:
		errors.append("expected.json: scenarios must be an object")
		return {}
	return scenarios


static func _run_one(path: String, config: SimConfig, expected: Dictionary, recorded: Dictionary) -> Dictionary:
	var scenario_name: String = path.get_file().get_basename()
	var row: Dictionary = {
		"name": scenario_name, "status": "ERROR", "hash": "", "expected": "",
		"ticks": 0, "entity_updates": 0, "usec": 0, "detail": "",
	}
	var spec_file: Dictionary = JsonFile.read_dict(path)
	if not spec_file["ok"]:
		row["detail"] = spec_file["error"]
		return row
	var spec := BattleSpec.new()
	if not spec.parse(spec_file["data"]):
		row["detail"] = "; ".join(spec.errors)
		return row
	var battle := Battle.new()
	if not battle.setup(config, spec):
		row["detail"] = "; ".join(battle.errors)
		return row
	var started: int = Time.get_ticks_usec()
	var result: Dictionary = battle.run()
	row["usec"] = Time.get_ticks_usec() - started
	row["hash"] = result["final_hash"]
	row["ticks"] = result["ticks"]
	row["entity_updates"] = result["entity_updates"]
	recorded[scenario_name] = {
		"final_hash": result["final_hash"],
		"ticks": result["ticks"],
		"outcome": result["outcome"],
		"checkpoints": result["checkpoints"],
	}
	if not expected.has(scenario_name):
		row["status"] = "NO GOLDEN"
		return row
	var want: Dictionary = expected[scenario_name]
	row["expected"] = String(want.get("final_hash", ""))
	if row["expected"] == row["hash"]:
		row["status"] = "PASS"
	else:
		row["status"] = "FAIL"
		row["detail"] = _first_divergence(want.get("checkpoints", []), result["checkpoints"])
	return row


static func _first_divergence(want: Array, got: Array) -> String:
	for i in mini(want.size(), got.size()):
		if String(want[i]) != String(got[i]):
			return "first differs at checkpoint %d (tick %d)" % [i, (i + 1) * Battle.CHECKPOINT_TICKS]
	if want.size() != got.size():
		return "checkpoint count differs: expected %d, got %d" % [want.size(), got.size()]
	return "every checkpoint matches; only the final state differs"
