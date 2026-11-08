extends RefCounted
## Base class for sim unit tests, so no third-party test addon is needed.
## A test file extends this and defines methods named test_* that end with
## `return true`. sim/tests/test_runner.gd runs each one on a fresh instance.

const JsonFile := preload("res://sim/core/json_file.gd")

var failures: PackedStringArray = PackedStringArray()
var current_test: String = ""


func expect_eq(actual: Variant, expected: Variant, what: String) -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("%s: %s: expected %s (%s), got %s (%s)" % [
			current_test, what,
			str(expected), type_string(typeof(expected)),
			str(actual), type_string(typeof(actual)),
		])


func expect_true(condition: bool, what: String) -> void:
	if not condition:
		failures.append("%s: %s" % [current_test, what])


## Loads a JSON object from res://, failing the test if it can't.
func load_json(path: String) -> Dictionary:
	var result: Dictionary = JsonFile.read_dict(path)
	if not result["ok"]:
		failures.append("%s: %s" % [current_test, result["error"]])
		return {}
	return result["data"]
