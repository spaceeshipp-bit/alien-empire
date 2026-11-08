extends RefCounted
## Runs the sim unit tests. The headless worker CLI and the client's on-device
## test screen both call this, so the same checks run on every platform.

const TEST_SCRIPTS := [
	"res://sim/tests/unit/test_fx.gd",
	"res://sim/tests/unit/test_rng.gd",
	"res://sim/tests/unit/test_hasher.gd",
	"res://sim/tests/unit/test_lane_path.gd",
	"res://sim/tests/unit/test_config.gd",
	"res://sim/tests/unit/test_battle.gd",
]


## Returns {"passed": int, "failed": int, "lines": PackedStringArray}.
static func run_all() -> Dictionary:
	var passed: int = 0
	var failed: int = 0
	var lines := PackedStringArray()
	for script_path in TEST_SCRIPTS:
		var script: GDScript = load(script_path)
		if script == null:
			failed += 1
			lines.append("FAIL %s: can't load the test script" % script_path)
			continue
		var names: Array[String] = []
		for method in script.get_script_method_list():
			var method_name: String = method["name"]
			if method_name.begins_with("test_") and not names.has(method_name):
				names.append(method_name)
		names.sort()
		for method_name in names:
			var label: String = "%s.%s" % [script_path.get_file().get_basename(), method_name]
			var test_case: RefCounted = script.new()
			test_case.set("current_test", label)
			# A test that hits a script error stops without returning true.
			var finished: Variant = test_case.call(method_name)
			var failures: PackedStringArray = test_case.get("failures")
			if typeof(finished) != TYPE_BOOL or not finished:
				failures.append("%s: stopped before the end (script error?)" % label)
			if failures.is_empty():
				passed += 1
			else:
				failed += 1
				for line in failures:
					lines.append("FAIL " + line)
	return {"passed": passed, "failed": failed, "lines": lines}
