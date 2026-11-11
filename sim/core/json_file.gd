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
	var inexact: Dictionary = first_inexact_number(text)
	if not inexact.is_empty():
		return {"ok": false, "data": null, "error": "%s:%d: %s %s; every number must be a whole number, written plainly" % [
			path, inexact["line"], inexact["token"], inexact["problem"]]}
	return {"ok": true, "data": json.data, "error": ""}


## Like read(), but the top level must be an object.
static func read_dict(path: String) -> Dictionary:
	var result: Dictionary = read(path)
	if result["ok"] and typeof(result["data"]) != TYPE_DICTIONARY:
		return {"ok": false, "data": null, "error": "%s: top level must be an object" % path}
	return result



## The first number in JSON text that Godot's parser could read as a different
## number, as {"line", "token", "problem"}, or {} if there is none. Every number
## the sim reads is a whole number (D-004, D-029), and Godot turns each one into a
## float before anything can check it:
## - a fraction or an exponent arrives already rounded: 9007199254740991.0 comes
##   out one lower, and 4503599627370495.5 as a whole number;
## - leading zeros (which standard JSON forbids, but Godot accepts) count toward
##   the 18 digits it keeps, so 00000000000000000000123 comes out as 0.
## So the text itself is checked.
static func first_inexact_number(text: String) -> Dictionary:
	var in_string: bool = false
	var line: int = 1
	var i: int = 0
	var n: int = text.length()
	while i < n:
		var c: int = text.unicode_at(i)
		if c == 10:  # newline
			line += 1
		if in_string:
			if c == 92:  # backslash: the next character is escaped
				i += 1
			elif c == 34:  # closing quote
				in_string = false
			i += 1
			continue
		if c == 34:  # opening quote
			in_string = true
			i += 1
			continue
		if c == 45 or (c >= 48 and c <= 57):  # a number starts with - or a digit
			var start: int = i
			var decimal: bool = false
			while i < n:
				var d: int = text.unicode_at(i)
				if d == 46 or d == 101 or d == 69:  # . e E
					decimal = true
				elif not (d == 43 or d == 45 or (d >= 48 and d <= 57)):
					break
				i += 1
			var token: String = text.substr(start, i - start)
			if decimal:
				return {"line": line, "token": token, "problem": "is written as a decimal"}
			var digits: String = token.trim_prefix("-")
			if digits.length() > 1 and digits.begins_with("0"):
				return {"line": line, "token": token, "problem": "has leading zeros"}
			continue
		i += 1
	return {}
