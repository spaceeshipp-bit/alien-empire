extends Control
## Plugin Lab: tries each Android plugin the game depends on (billing, ads,
## push, Google sign-in, Play Integrity) so every one is proven on a real phone
## in M0, before any game system relies on it.

const Ui := preload("res://ui/ui_kit.gd")
const LabCheck := preload("res://plugin_lab/lab_check.gd")
const CHECKS := [
	preload("res://plugin_lab/billing_check.gd"),
	preload("res://plugin_lab/ads_check.gd"),
	preload("res://plugin_lab/push_check.gd"),
	preload("res://plugin_lab/signin_check.gd"),
	preload("res://plugin_lab/integrity_check.gd"),
]


func _ready() -> void:
	var column: VBoxContainer = Ui.screen(self, "Plugin Lab")
	column.add_child(Ui.button("Back", func() -> void:
		get_tree().change_scene_to_file("res://scenes/boot.tscn")
	))
	column.add_child(Ui.label("Run each check on your phone. A pass means the plugin works on this device.", 22, Ui.MUTED))
	for check_script in CHECKS:
		column.add_child(_check_card(check_script.new()))


func _check_card(check: LabCheck) -> Control:
	add_child(check)
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 8)
	card.add_child(Ui.label(check.title(), 30, Ui.CYAN))
	var status: Label = Ui.label(check.availability(), 22, Ui.MUTED)
	card.add_child(status)
	var output: Label = Ui.label("", 20, Ui.TEXT)
	var run_button: Button = Ui.button("Run check", func() -> void: pass)
	# One run at a time: a second tap would mix the plugin's answers to both
	# runs. Every run ends in finished, if only through its timeout.
	run_button.pressed.connect(func() -> void:
		run_button.disabled = true
		output.text = ""
		status.text = "Running…"
		status.add_theme_color_override("font_color", Ui.MUTED)
		check.start()
	)
	card.add_child(run_button)
	card.add_child(output)
	# Long values such as the FCM token can't be typed from the screen.
	card.add_child(Ui.button("Copy this check's output", func() -> void:
		DisplayServer.clipboard_set(output.text)
	))
	check.logged.connect(func(text: String) -> void:
		output.text += text + "\n"
	)
	check.finished.connect(func(ok: bool) -> void:
		run_button.disabled = false
		status.text = "PASS" if ok else "FAILED"
		status.add_theme_color_override("font_color", Ui.TEAL if ok else Ui.RED)
	)
	return card
