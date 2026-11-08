extends RefCounted
## Runs the sim unit tests and the golden battles and turns the results into
## report lines, for the on-device test screen and the desktop CI run.

const TestRunner := preload("res://sim/tests/test_runner.gd")
const GoldenRunner := preload("res://sim/tests/golden/golden_runner.gd")
const SimVersion := preload("res://sim/core/sim_version.gd")


## Returns {"ok": bool, "lines": Array of [text, status]}, status being
## "pass", "fail", "note" or "info".
static func run() -> Dictionary:
	var lines: Array = []
	lines.append(["%s on %s · Godot %s · sim v%d" % [
		OS.get_model_name(), OS.get_name(), Engine.get_version_info()["string"], SimVersion.SIM_VERSION,
	], "info"])

	var unit: Dictionary = TestRunner.run_all()
	var unit_ok: bool = unit["failed"] == 0
	lines.append(["Unit tests: %d passed, %d failed" % [unit["passed"], unit["failed"]], "pass" if unit_ok else "fail"])
	for line in unit["lines"]:
		lines.append([str(line), "fail"])

	var golden: Dictionary = GoldenRunner.run_all()
	for note in golden["errors"]:
		lines.append([str(note), "note"])
	for row in golden["rows"]:
		var status: String = row["status"]
		var usec: int = row["usec"]
		lines.append(["%s  %s  %s  %d ticks  %.1f ms" % [
			status, row["name"], String(row["hash"]).substr(0, 12), row["ticks"], usec / 1000.0,
		], "pass" if status == "PASS" else "fail"])
		if not String(row["detail"]).is_empty():
			lines.append(["    " + String(row["detail"]), "note"])
	return {"ok": unit_ok and golden["ok"], "lines": lines}


## The report as plain text, for logs.
static func as_text(report: Dictionary) -> String:
	var out := PackedStringArray()
	for line in report["lines"]:
		out.append(str(line[0]))
	out.append("RESULT: " + ("PASS" if report["ok"] else "FAIL"))
	return "\n".join(out)
