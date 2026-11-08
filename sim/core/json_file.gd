extends RefCounted
## Reads a JSON file. Used by the tests, the worker and the client to load
## config bundles and battle specs.


## Returns {"ok": bool, "data": Variant, "error": String}.
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "data": null, "error": "%s: file not found" % path}
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {"ok": false, "data": null, "error": "%s: can't read file (%s)" % [path, error_string(FileAccess.get_open_error())]}
	var json := JSON.new()
	var err: int = json.parse(text)
	if err != OK:
		return {"ok": false, "data": null, "error": "%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()]}
	return {"ok": true, "data": json.data, "error": ""}


## Like read(), but the top level must be an object.
static func read_dict(path: String) -> Dictionary:
	var result: Dictionary = read(path)
	if result["ok"] and typeof(result["data"]) != TYPE_DICTIONARY:
		return {"ok": false, "data": null, "error": "%s: top level must be an object" % path}
	return result
