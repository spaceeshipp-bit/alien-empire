extends RefCounted
## The sim library (res://sim/aetd_sim.gdextension) and the scripts that need it.
##
## The sim scripts name the library's classes, so they only compile when it
## loaded. Screens ask loaded() first and load the report script at run time,
## so if the library failed to load on a phone, the home screen and the Plugin
## Lab still open and the Sim tests screen says what went wrong.

const NOT_LOADED := "The sim library (libaetd_sim) didn't load on this device, so the sim can't run. Godot's log says why."
const NOT_COMPILED := "These sim scripts don't compile with this sim library (%s): %s. Usually the app and the library come from different builds: rebuild sim/bin and run tools/sync_sim.py."


static func loaded() -> bool:
	return ClassDB.class_exists(&"SimNative")


## "sim v1", or "sim library missing".
static func label() -> String:
	if not loaded():
		return "sim library missing"
	return "sim v%d" % ClassDB.class_get_integer_constant(&"SimNative", &"SIM_VERSION")


## The report script, res://ui/sim_report.gd, or null if any sim script doesn't
## compile (broken_scripts()). Call only when loaded() is true.
static func report_script() -> Variant:
	if not broken_scripts().is_empty():
		return null
	return load("res://ui/sim_report.gd")


## The sim scripts that don't compile, by path: a library from another build can
## lack what they call. In Godot 4.7.2 only the script with the error says so
## (can_instantiate() is false); scripts that depend on it still load and claim
## they can run, and then fail call by call. So every script under res://sim/ is
## asked, plus the report itself. ResourceLoader.list_directory() gives the
## original file names in an exported APK too.
static func broken_scripts() -> Array:
	var broken: Array = []
	_collect_broken("res://sim", broken)
	var report: Variant = load("res://ui/sim_report.gd")
	if report == null or not (report as GDScript).can_instantiate():
		broken.append("res://ui/sim_report.gd")
	return broken


## NOT_COMPILED filled in, for a screen or a log.
static func not_compiled_message() -> String:
	return NOT_COMPILED % [label(), ", ".join(PackedStringArray(broken_scripts()))]


static func _collect_broken(folder: String, broken: Array) -> void:
	for entry in ResourceLoader.list_directory(folder):
		if entry.ends_with("/"):
			_collect_broken(folder.path_join(entry.trim_suffix("/")), broken)
		elif entry.ends_with(".gd"):
			var path: String = folder.path_join(entry)
			var script: Variant = load(path)
			if script == null or not (script as GDScript).can_instantiate():
				broken.append(path)
