extends RefCounted
## Which build this is, so a screenshot from a phone names the commit it came
## from. CI writes res://build_info.json before it exports the APK
## (tools/ci/prepare_android_export.sh); a run from the editor has none.

const PATH := "res://build_info.json"


## "build 2401 · 6a0d65d", or "local build".
static func label() -> String:
	if not FileAccess.file_exists(PATH):
		return "local build"
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return "unknown build"
	return "build %d · %s" % [int(data.get("version_code", 0)), String(data.get("commit", "?"))]
