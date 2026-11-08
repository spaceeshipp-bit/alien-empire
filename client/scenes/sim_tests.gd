extends Control
## Runs the sim unit tests and golden battles on this device and lists the
## results. On a phone this is the "identical hash on Android" check of M0.

const Ui := preload("res://ui/ui_kit.gd")
const SimReport := preload("res://ui/sim_report.gd")


func _ready() -> void:
	var column: VBoxContainer = Ui.screen(self, "Sim tests")
	column.add_child(Ui.button("Back", func() -> void:
		get_tree().change_scene_to_file("res://scenes/boot.tscn")
	))
	var status: Label = Ui.label("Running…", 30, Ui.MUTED)
	column.add_child(status)
	# Let the screen draw once before the tests take over the main thread.
	await get_tree().process_frame
	await get_tree().process_frame
	var report: Dictionary = SimReport.run()
	print(SimReport.as_text(report))
	status.text = "ALL CHECKS PASS" if report["ok"] else "SOME CHECKS FAILED"
	status.add_theme_color_override("font_color", Ui.TEAL if report["ok"] else Ui.RED)
	for line in report["lines"]:
		column.add_child(Ui.label(str(line[0]), 22, Ui.status_color(str(line[1]))))
