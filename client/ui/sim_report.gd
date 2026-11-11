extends RefCounted
## Runs the sim unit tests and the golden battles and turns the results into
## report lines, for the on-device test screen and the desktop CI run.

const TestRunner := preload("res://sim/tests/test_runner.gd")
const GoldenRunner := preload("res://sim/tests/golden/golden_runner.gd")
const SimVersion := preload("res://sim/core/sim_version.gd")
const BuildInfo := preload("res://ui/build_info.gd")


## Returns {"ok": bool, "lines": Array of [text, status]}, status being
## "pass", "fail", "note" or "info". The golden battles get a line each; the
## generated battles get one line between them, plus one for each that fails.
static func run() -> Dictionary:
	var lines: Array = []
	lines.append(["%s on %s · Godot %s · sim v%d · %s" % [
		OS.get_model_name(), OS.get_name(), Engine.get_version_info()["string"], SimVersion.SIM_VERSION,
		BuildInfo.label(),
	], "info"])

	var unit: Dictionary = TestRunner.run_all()
	var unit_ok: bool = unit["failed"] == 0
	lines.append(["Unit tests: %d passed, %d failed" % [unit["passed"], unit["failed"]], "pass" if unit_ok else "fail"])
	for line in unit["lines"]:
		lines.append([str(line), "fail"])

	var golden: Dictionary = GoldenRunner.run_all()
	for note in golden["errors"]:
		lines.append([str(note), "note"])
	var generated: Array = []
	for row in golden["rows"]:
		if row["kind"] == "generated":
			generated.append(row)
		else:
			_add_row(lines, row)
	if not generated.is_empty():
		var passed: int = 0
		var usec: int = 0
		var updates: int = 0
		for row in generated:
			passed += 1 if row["status"] == "PASS" else 0
			usec += int(row["usec"])
			updates += int(row["entity_updates"])
		lines.append(["Generated battles: %d of %d match the reference model · %s" % [
			passed, generated.size(), speed(usec, updates),
		], "pass" if passed == generated.size() else "fail"])
		for row in generated:
			if row["status"] != "PASS":
				_add_row(lines, row)
	return {"ok": unit_ok and golden["ok"], "lines": lines}


## How fast the sim ran, as the worker reports it: ns per alien-tick, one
## alien's movement in one tick, timed from the first tick to the result.
static func speed(usec: int, updates: int) -> String:
	if updates <= 0:
		return "no aliens moved"
	return "%d ns per alien-tick" % roundi(1000.0 * usec / updates)


static func _add_row(lines: Array, row: Dictionary) -> void:
	var status: String = row["status"]
	lines.append(["%s  %s  %s  %d ticks  %.1f ms  %s" % [
		status, row["name"], String(row["hash"]).substr(0, 12), row["ticks"], int(row["usec"]) / 1000.0,
		speed(int(row["usec"]), int(row["entity_updates"])),
	], "pass" if status == "PASS" else "fail"])
	if not String(row["detail"]).is_empty():
		lines.append(["    " + String(row["detail"]), "note"])


## The report as plain text, for logs.
static func as_text(report: Dictionary) -> String:
	var out := PackedStringArray()
	for line in report["lines"]:
		out.append(str(line[0]))
	out.append("RESULT: " + ("PASS" if report["ok"] else "FAIL"))
	return "\n".join(out)
