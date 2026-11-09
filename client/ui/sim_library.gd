extends RefCounted
## The sim library (res://sim/aetd_sim.gdextension) and the scripts that need it.
##
## The sim scripts name the library's classes, so they only compile when it
## loaded. Screens ask loaded() first and load the report script at run time,
## so if the library failed to load on a phone, the home screen and the Plugin
## Lab still open and the Sim tests screen says what went wrong.

const NOT_LOADED := "The sim library (libaetd_sim) didn't load on this device, so the sim can't run. Godot's log says why."


static func loaded() -> bool:
	return ClassDB.class_exists(&"SimNative")


## "sim v1", or "sim library missing".
static func label() -> String:
	if not loaded():
		return "sim library missing"
	return "sim v%d" % ClassDB.class_get_integer_constant(&"SimNative", &"SIM_VERSION")


## The report script, res://ui/sim_report.gd. Call only when loaded() is true.
static func report_script() -> Variant:
	return load("res://ui/sim_report.gd")
