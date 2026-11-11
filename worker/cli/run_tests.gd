extends SceneTree
## Headless test entry point. The sim worker runs the same way on the server.
##
##   godot --headless --path worker --script res://cli/run_tests.gd
##   godot --headless --path worker --script res://cli/run_tests.gd -- --record /abs/path/sim/tests/golden/expected.json
##
## Runs the unit tests and the golden battles and prints a report. Exits 0 only
## if everything passes. With --record it writes the golden hashes instead of
## checking them; the unit tests must still pass.

const TestRunner := preload("res://sim/tests/test_runner.gd")
const GoldenRunner := preload("res://sim/tests/golden/golden_runner.gd")
const SimVersion := preload("res://sim/core/sim_version.gd")


func _initialize() -> void:
	quit(_run(OS.get_cmdline_user_args()))


func _run(args: PackedStringArray) -> int:
	var record_path: String = ""
	var flag: int = args.find("--record")
	if flag >= 0:
		if flag + 1 >= args.size():
			printerr("--record needs the path of sim/tests/golden/expected.json")
			return 2
		record_path = args[flag + 1]
	var headless: String = " (headless)" if DisplayServer.get_name() == "headless" else ""
	print("Sim version %d on %s%s, Godot %s" % [SimVersion.SIM_VERSION, OS.get_name(), headless, Engine.get_version_info()["string"]])

	var unit: Dictionary = TestRunner.run_all()
	for line in unit["lines"]:
		print(line)
	print("Unit tests: %d passed, %d failed" % [unit["passed"], unit["failed"]])

	var golden: Dictionary = GoldenRunner.run_all()
	for line in golden["errors"]:
		print("NOTE " + str(line))
	var generated: int = 0
	var generated_pass: int = 0
	for row in golden["rows"]:
		print(_row_text(row))
		if row["kind"] == "generated":
			generated += 1
			generated_pass += 1 if row["status"] == "PASS" else 0
	if generated > 0:
		print("Generated battles: %d of %d match the reference model" % [generated_pass, generated])

	var ok: bool = unit["failed"] == 0
	if record_path.is_empty():
		ok = ok and golden["ok"]
	else:
		ok = _record(golden, record_path) and ok
	print("RESULT: " + ("PASS" if ok else "FAIL"))
	return 0 if ok else 1


func _row_text(row: Dictionary) -> String:
	var usec: int = row["usec"]
	var updates: int = row["entity_updates"]
	var speed: String = "-"
	if updates > 0:
		speed = "%d ns per alien-tick" % roundi(1000.0 * usec / updates)
	return "%-24s %-9s ticks=%-5d %8.1f ms  %s  %s  %s" % [
		row["name"], row["status"], row["ticks"], usec / 1000.0, speed,
		String(row["hash"]).substr(0, 16), row["detail"],
	]


func _record(golden: Dictionary, path: String) -> bool:
	var rows: Array = golden["rows"]
	if rows.is_empty():
		printerr("not recording: no scenario ran")
		return false
	for row in rows:
		if row["status"] == "ERROR":
			printerr("not recording: %s didn't run (%s)" % [row["name"], row["detail"]])
			return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("can't write %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(GoldenRunner.expected_document(golden), "  ") + "\n")
	file.close()
	print("Recorded %d golden hashes to %s" % [rows.size(), path])
	return true
