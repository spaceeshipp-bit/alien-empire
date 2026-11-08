extends RefCounted
## Reads parsed JSON safely. Every number must be a whole number and every field
## must be present with the right type. GDScript has no exceptions, so problems
## are collected in errors instead of stopping the game.
##
## Godot's JSON parser may hand numbers over as floats. Floats appear only here,
## while converting parsed JSON to int before a battle starts; the sim itself
## never sees one.

## Largest integer a float holds exactly: 2^53 - 1.
const MAX_JSON_INT: float = 9007199254740991.0

var errors: PackedStringArray = PackedStringArray()


func fail(path: String, message: String) -> void:
	errors.append("%s: %s" % [path, message])


func to_int(value: Variant, path: String) -> int:
	match typeof(value):
		TYPE_INT:
			return value
		TYPE_FLOAT:
			var f: float = value
			if is_finite(f) and f == floorf(f) and absf(f) <= MAX_JSON_INT:
				return int(f)
	fail(path, "expected a whole number")
	return 0


func get_int(d: Dictionary, key: String, path: String, min_value: int, max_value: int) -> int:
	var where: String = "%s.%s" % [path, key]
	if not d.has(key):
		fail(path, "missing field %s" % key)
		return min_value
	var value: int = to_int(d[key], where)
	if value < min_value or value > max_value:
		fail(where, "%d is outside %d..%d" % [value, min_value, max_value])
	return value


## Milliseconds that must land on the 50 ms tick grid, returned as ticks.
func get_ticks(d: Dictionary, key: String, path: String, min_ms: int, max_ms: int) -> int:
	var ms: int = get_int(d, key, path, min_ms, max_ms)
	if ms % 50 != 0:
		fail("%s.%s" % [path, key], "%d ms is not a multiple of 50" % ms)
	return ms / 50


func get_string(d: Dictionary, key: String, path: String) -> String:
	if not d.has(key):
		fail(path, "missing field %s" % key)
		return ""
	if typeof(d[key]) != TYPE_STRING:
		fail("%s.%s" % [path, key], "expected text")
		return ""
	return d[key]


func get_bool(d: Dictionary, key: String, path: String) -> bool:
	if not d.has(key):
		fail(path, "missing field %s" % key)
		return false
	if typeof(d[key]) != TYPE_BOOL:
		fail("%s.%s" % [path, key], "expected true or false")
		return false
	return d[key]


func get_dict(d: Dictionary, key: String, path: String) -> Dictionary:
	if not d.has(key):
		fail(path, "missing field %s" % key)
		return {}
	if typeof(d[key]) != TYPE_DICTIONARY:
		fail("%s.%s" % [path, key], "expected an object")
		return {}
	return d[key]


func get_array(d: Dictionary, key: String, path: String) -> Array:
	if not d.has(key):
		fail(path, "missing field %s" % key)
		return []
	if typeof(d[key]) != TYPE_ARRAY:
		fail("%s.%s" % [path, key], "expected a list")
		return []
	return d[key]


## The value at index i of a list, which must be an object.
func item_dict(list: Array, i: int, path: String) -> Dictionary:
	if typeof(list[i]) != TYPE_DICTIONARY:
		fail("%s[%d]" % [path, i], "expected an object")
		return {}
	return list[i]
