extends RefCounted
## The string table: every player-facing text comes from res://strings/en.json,
## so the game can be translated without touching code (build prompt: string
## tables from day one). Missing keys show as the key itself, which a tool test
## catches before a build ships.

const PATH := "res://strings/en.json"

static var _table: Dictionary = {}


## The text for key, with {0}, {1}, ... filled from args.
static func t(key: String, args: Array = []) -> String:
	if _table.is_empty():
		_load()
	var text: String = _table.get(key, key)
	for i in args.size():
		text = text.replace("{%d}" % i, str(args[i]))
	return text


static func has(key: String) -> bool:
	if _table.is_empty():
		_load()
	return _table.has(key)


static func _load() -> void:
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_error("strings: can't open %s" % PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY and typeof(parsed.get("strings")) == TYPE_DICTIONARY:
		_table = parsed["strings"]
	else:
		push_error("strings: %s has no strings table" % PATH)
