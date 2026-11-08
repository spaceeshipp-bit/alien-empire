extends Control
## M0 test build home screen. Started with the user argument
## --run-tests-and-quit (desktop CI), it runs the sim tests, prints the report
## and exits with 0 only if everything passed.

const Ui := preload("res://ui/ui_kit.gd")
const SimReport := preload("res://ui/sim_report.gd")
const SimVersion := preload("res://sim/core/sim_version.gd")


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--run-tests-and-quit"):
		var report: Dictionary = SimReport.run()
		print(SimReport.as_text(report))
		get_tree().quit(0 if report["ok"] else 1)
		return
	var column: VBoxContainer = Ui.screen(self, "Alien Empire TD")
	column.add_child(Ui.label("M0 test build · sim v%d · Godot %s" % [
		SimVersion.SIM_VERSION, Engine.get_version_info()["string"],
	], 22, Ui.MUTED))
	column.add_child(Ui.button("Sim tests", func() -> void:
		get_tree().change_scene_to_file("res://scenes/sim_tests.tscn")
	))
	column.add_child(Ui.button("Plugin Lab", func() -> void:
		get_tree().change_scene_to_file("res://scenes/plugin_lab.tscn")
	))
	column.add_child(Ui.label(
		"Sim tests replay fixed battles and compare their hashes with the ones recorded on desktop. "
		+ "Plugin Lab tries billing, ads, push, sign-in and Play Integrity on this phone.",
		22, Ui.MUTED))
