extends Control
## The battle's interface, over the map: the top bar (pause, the wave and its
## countdown, lives, credits), the bottom sheet (build, upgrade, sell), a toast
## for refusals, and the pause and end screens. It only shows what the
## controller (scenes/battle.gd) hands it and reports taps as signals.

signal build_pressed(tower_id: String)
signal upgrade_pressed
signal sell_pressed
signal sheet_closed
signal pause_pressed
signal start_pressed
signal call_pressed
signal speed_pressed
signal resume_pressed
signal restart_pressed
signal quit_pressed

const Palette := preload("res://art/palette.gd")
const Art := preload("res://game/art.gd")
const S := preload("res://game/strings.gd")

const TOP_HEIGHT := 92.0
const SHEET_HEIGHT := 178.0
## How long the call button stays off after the sheet changes or a wave is called.
const CALL_LOCK_MS := 600
const TOAST_SECONDS := 1.6

var _wave_label: Label
var _countdown_label: Label
var _lives_label: Label
var _credits_label: Label
var _sheet: PanelContainer
var _sheet_body: Control
var _toast: Label
var _toast_t: float = 0.0
var _overlay: Control
var _lives_flash: float = 0.0
var _speed_button: Button
var _next_row: HBoxContainer
var _next_key: String = ""
var _armed_card: String = ""
var _last_lives: int = -1
## The idle sheet's button that calls the next wave early, while that sheet shows.
var _call_button: Button
var _call_state: Array = [-1, 0, false]  # wave number, bonus, enabled
## Until this time (Time.get_ticks_msec()), the call button stays off: it shows
## where Start, Upgrade and Sell were a moment ago, so a double tap on one of
## those, or on Call itself, must not call a wave.
var _call_locked_until: int = 0
## Toasts wait their turn instead of replacing one another.
var _toast_queue: PackedStringArray = PackedStringArray()


func _ready() -> void:
	# Under a CanvasLayer the anchors alone leave this control 0 x 0 (seen on
	# Godot 4.7.2), so it takes the viewport's size itself and follows it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fit()
	get_viewport().size_changed.connect(_fit)
	_build_top_bar()
	_build_sheet()
	_toast = Label.new()
	_toast.add_theme_font_size_override("font_size", 26)
	_toast.add_theme_color_override("font_color", Palette.TEXT)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.position = Vector2(-300, -SHEET_HEIGHT - 70)
	_toast.size = Vector2(600, 40)
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)


func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size


func _panel_style(color: Color, radius: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


func _label(text: String, size: int, color: Color = Palette.TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, on_press: Callable, accent: Color = Palette.YOU) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 72)
	button.add_theme_font_size_override("font_size", 26)
	var normal := _panel_style(Color(accent, 0.18), 14)
	normal.border_color = Color(accent, 0.8)
	normal.border_width_left = 2
	normal.border_width_right = 2
	normal.border_width_top = 2
	normal.border_width_bottom = 2
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(accent, 0.4)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(Palette.PANEL, 0.6)
	disabled.border_color = Color(Palette.MUTED, 0.3)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", normal)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", Palette.TEXT)
	button.add_theme_color_override("font_disabled_color", Color(Palette.MUTED, 0.6))
	button.pressed.connect(on_press)
	return button


func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.custom_minimum_size = Vector2(0, TOP_HEIGHT)
	bar.add_theme_stylebox_override("panel", _panel_style(Color(Palette.GROUND, 0.92)))
	add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	bar.add_child(row)
	var pause := _button("II", func() -> void: pause_pressed.emit())
	pause.custom_minimum_size = Vector2(72, 64)
	row.add_child(pause)
	var wave_box := VBoxContainer.new()
	wave_box.add_theme_constant_override("separation", 0)
	wave_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wave_label = _label("", 30, Palette.YOU)
	_countdown_label = _label("", 20, Palette.MUTED)
	wave_box.add_child(_wave_label)
	_next_row = HBoxContainer.new()
	_next_row.add_theme_constant_override("separation", 4)
	_next_row.add_child(_countdown_label)
	wave_box.add_child(_next_row)
	row.add_child(wave_box)
	_speed_button = _button(S.t("hud.speed", [1]), func() -> void: speed_pressed.emit())
	_speed_button.custom_minimum_size = Vector2(72, 64)
	row.add_child(_speed_button)
	row.add_child(_stat_icon("lives"))
	_lives_label = _label("", 32)
	row.add_child(_lives_label)
	row.add_child(_stat_icon("credits"))
	_credits_label = _label("", 32, Palette.EYE)
	row.add_child(_credits_label)


## A small drawn icon: the Core's hexagon for lives, a credit chip for credits.
func _stat_icon(kind: String) -> Control:
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(36, 64)
	icon.draw.connect(func() -> void:
		var c := Vector2(18, 32)
		var points := PackedVector2Array()
		for i in 7:
			points.append(c + Vector2.from_angle(TAU * i / 6.0 + PI / 6.0) * 14.0)
		if kind == "lives":
			icon.draw_colored_polygon(points, Color(Palette.YOU, 0.25))
			icon.draw_polyline(points, Palette.YOU, 2.5, true)
			icon.draw_circle(c, 5.0, Palette.YOU)
		else:
			icon.draw_circle(c, 13.0, Color(Palette.EYE, 0.25))
			icon.draw_arc(c, 13.0, 0.0, TAU, 24, Palette.EYE, 2.5, true)
			icon.draw_rect(Rect2(c - Vector2(5, 5), Vector2(10, 10)), Palette.EYE, false, 2.0)
	)
	return icon


func _build_sheet() -> void:
	_sheet = PanelContainer.new()
	_sheet.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_sheet.custom_minimum_size = Vector2(0, SHEET_HEIGHT)
	_sheet.offset_top = -SHEET_HEIGHT
	var style := _panel_style(Color(Palette.PANEL, 0.96), 0)
	style.border_color = Color(Palette.YOU, 0.35)
	style.border_width_top = 2
	_sheet.add_theme_stylebox_override("panel", style)
	add_child(_sheet)
	show_hint()


func _set_sheet(body: Control) -> void:
	if _sheet_body != null:
		_sheet_body.queue_free()
	_call_button = null
	_sheet_body = body
	_sheet.add_child(body)


## Before the first wave: a button to start it, with time to build first.
func show_start() -> void:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	var hint := _label(S.t("build.start_hint"), 20, Palette.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	box.add_child(_button(S.t("build.start"), func() -> void: start_pressed.emit(), Palette.HIVE))
	_set_sheet(box)


func set_speed(speed: int) -> void:
	_speed_button.text = S.t("hud.speed", [speed])


## The next wave's classes as icons; a warning in red when nothing built can hit one.
func set_next_wave(classes: Array, uncovered: Array) -> void:
	var key: String = str(classes) + str(uncovered)
	if key == _next_key:
		return
	_next_key = key
	for child in _next_row.get_children():
		if child != _countdown_label:
			child.queue_free()
	for klass: String in classes:
		var icon := TextureRect.new()
		icon.texture = Art.icon(klass)
		icon.custom_minimum_size = Vector2(24, 24)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_next_row.add_child(icon)
	if not uncovered.is_empty():
		var names: PackedStringArray = PackedStringArray()
		for klass: String in uncovered:
			names.append(S.t("class." + klass))
		toast(S.t("hud.uncovered", [", ".join(names)]))


## The idle sheet: how to build, and the button that calls the next wave early.
func show_hint() -> void:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	var hint := _label(S.t("build.hint"), 22, Palette.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	var call_button := _button("", func() -> void: call_pressed.emit(), Palette.HIVE)
	box.add_child(call_button)
	_set_sheet(box)  # clears _call_button, which belonged to the old sheet
	_call_button = call_button
	lock_call(CALL_LOCK_MS)


## What calling the next wave would pay now. wave is its number (from 1), or -1
## when none is left; enabled is false while calling isn't possible.
func set_call(wave: int, bonus: int, enabled: bool) -> void:
	var state: Array = [wave, bonus, enabled]
	if state == _call_state:
		return
	_call_state = state
	_show_call()


## Keeps the call button off for ms milliseconds from now.
func lock_call(ms: int) -> void:
	_call_locked_until = maxi(_call_locked_until, Time.get_ticks_msec() + ms)
	_show_call()


func call_locked() -> bool:
	return Time.get_ticks_msec() < _call_locked_until


func _show_call() -> void:
	if _call_button == null or not is_instance_valid(_call_button):
		return
	var wave: int = _call_state[0]
	_call_button.visible = wave >= 0
	_call_button.text = S.t("hud.call", [wave, _call_state[1]])
	_call_button.disabled = not _call_state[2] or call_locked()


## The build menu: a card per tower, dimmed when the credits can't cover it.
## towers: [{id, cost, classes (strong against)}].
func show_build(towers: Array, credits: int, armed: String = "") -> void:
	_armed_card = armed
	var box := VBoxContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for t: Dictionary in towers:
		row.add_child(_tower_card(t, credits >= int(t.cost)))
	var close := _button("×", func() -> void: sheet_closed.emit(), Palette.MUTED)
	close.custom_minimum_size = Vector2(64, 0)
	row.add_child(close)
	box.add_child(row)
	_set_sheet(box)


func _tower_card(t: Dictionary, affordable: bool) -> Control:
	var card := Button.new()
	card.custom_minimum_size = Vector2(0, 150)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.disabled = not affordable
	var normal := _panel_style(Color(Palette.PANEL_2, 0.95), 16)
	normal.border_color = Color(Palette.YOU, 0.55)
	normal.border_width_left = 2
	normal.border_width_right = 2
	normal.border_width_top = 2
	normal.border_width_bottom = 2
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.border_color = Color(Palette.MUTED, 0.25)
	disabled.bg_color = Color(Palette.PANEL, 0.9)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(Palette.YOU, 0.25)
	card.add_theme_stylebox_override("normal", normal)
	card.add_theme_stylebox_override("hover", normal)
	card.add_theme_stylebox_override("pressed", pressed)
	card.add_theme_stylebox_override("disabled", disabled)
	card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	card.pressed.connect(func() -> void: build_pressed.emit(String(t.id)))
	if String(t.id) == _armed_card:
		normal.border_color = Palette.EYE
		normal.border_width_left = 4
		normal.border_width_right = 4
		normal.border_width_top = 4
		normal.border_width_bottom = 4
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 2)
	card.add_child(column)
	var picture := Control.new()
	picture.custom_minimum_size = Vector2(0, 64)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.draw.connect(func() -> void:
		var c := Vector2(picture.size.x / 2.0, 32)
		var base: Texture2D = Art.tower_base()
		var head: Texture2D = Art.tower_head(String(t.id))
		var s: float = 58.0 / 200.0
		picture.draw_texture_rect(base, Rect2(c - Vector2(100, 100) * s, Vector2(200, 200) * s), false,
				Color.WHITE if affordable else Color(1, 1, 1, 0.35))
		picture.draw_texture_rect(head, Rect2(c - Vector2(140, 140) * s, Vector2(280, 280) * s), false,
				Color.WHITE if affordable else Color(1, 1, 1, 0.35))
	)
	column.add_child(picture)
	var name_label := _label(S.t("tower." + String(t.id)), 19, Palette.TEXT if affordable else Palette.MUTED)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name_label)
	var cost_text: String = S.t("build.confirm") if String(t.id) == _armed_card else S.t("build.cost", [t.cost])
	var cost := _label(cost_text, 22 if String(t.id) != _armed_card else 16, Palette.EYE if affordable else Color(Palette.MUTED, 0.6))
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(cost)
	var icons := HBoxContainer.new()
	icons.alignment = BoxContainer.ALIGNMENT_CENTER
	icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for klass: String in t.classes:
		var icon := TextureRect.new()
		icon.texture = Art.icon(klass)
		icon.custom_minimum_size = Vector2(22, 22)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icons.add_child(icon)
	column.add_child(icons)
	return card


## The tower menu: its name and level, its stats and what it aims at, upgrade and sell.
func show_tower(tower_id: String, level: int, damage: float, range_tiles: float, upgrade_cost: int,
		refund: int, credits: int, targeting: String) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var title_row := HBoxContainer.new()
	var title := _label("%s · %s" % [S.t("tower." + tower_id), S.t("tower.level", [level])], 26, Palette.YOU)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var close := _button("×", func() -> void: sheet_closed.emit(), Palette.MUTED)
	close.custom_minimum_size = Vector2(56, 48)
	title_row.add_child(close)
	box.add_child(title_row)
	box.add_child(_label("%s · %s" % [S.t("tower.stats", ["%.1f" % damage, "%.2f" % range_tiles]),
			S.t("tower.targets", [S.t("targeting." + targeting)])], 20, Palette.MUTED))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	var upgrade: Button
	if upgrade_cost < 0:
		upgrade = _button(S.t("tower.max_level"), func() -> void: pass)
		upgrade.disabled = true
	else:
		upgrade = _button(S.t("tower.upgrade", [upgrade_cost]), func() -> void: upgrade_pressed.emit())
		upgrade.disabled = credits < upgrade_cost
	upgrade.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(upgrade)
	var sell := _button(S.t("tower.sell", [refund]), func() -> void: sell_pressed.emit(), Palette.RIVAL)
	sell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(sell)
	box.add_child(buttons)
	_set_sheet(box)


func set_status(wave: int, waves: int, next_wave_seconds: int, lives: int, credits: int) -> void:
	_wave_label.text = S.t("hud.wave", [maxi(wave, 1), waves])
	if wave >= waves:
		_countdown_label.text = S.t("hud.last_wave")
	elif next_wave_seconds >= 0:
		_countdown_label.text = S.t("hud.wave_soon", [wave + 1, next_wave_seconds])
	if _last_lives >= 0 and lives < _last_lives:
		_lives_flash = 1.0
	_last_lives = lives
	_lives_label.text = S.t("hud.lives", [lives])
	_credits_label.text = S.t("hud.credits", [credits])


## Shows a short message. One already showing finishes first; a repeat of a
## message that's showing or waiting is dropped, and at most three wait.
func toast(text: String) -> void:
	if _toast_t <= 0.0:
		_toast.text = text
		_toast_t = TOAST_SECONDS
	elif text != _toast.text and not _toast_queue.has(text) and _toast_queue.size() < 3:
		_toast_queue.append(text)


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t / 0.3, 0.0, 1.0)
	elif not _toast_queue.is_empty():
		_toast.text = _toast_queue[0]
		_toast_queue.remove_at(0)
		_toast_t = TOAST_SECONDS
	if _call_locked_until > 0 and not call_locked():
		_call_locked_until = 0
		_show_call()
	_lives_flash = maxf(0.0, _lives_flash - delta * 2.0)
	_lives_label.add_theme_color_override("font_color", Palette.TEXT.lerp(Palette.DANGER, _lives_flash))
	_lives_label.scale = Vector2.ONE * (1.0 + 0.25 * _lives_flash)


func show_pause() -> void:
	_show_overlay(S.t("hud.pause"), "", [
		[S.t("hud.resume"), func() -> void: resume_pressed.emit()],
		[S.t("hud.restart"), func() -> void: restart_pressed.emit()],
		[S.t("hud.quit"), func() -> void: quit_pressed.emit()],
	], Palette.YOU)


func show_end(won: bool, stats: String) -> void:
	_show_overlay(S.t("end.won") if won else S.t("end.lost"), stats, [
		[S.t("end.again"), func() -> void: restart_pressed.emit()],
		[S.t("end.menu"), func() -> void: quit_pressed.emit()],
	], Palette.YOU if won else Palette.DANGER)


func hide_overlay() -> void:
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null


func _show_overlay(title: String, detail: String, actions: Array, accent: Color) -> void:
	hide_overlay()
	_overlay = ColorRect.new()
	(_overlay as ColorRect).color = Color(0.02, 0.04, 0.08, 0.82)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.custom_minimum_size = Vector2(560, 0)
	column.position = Vector2(-280, -200)
	column.add_theme_constant_override("separation", 18)
	_overlay.add_child(column)
	var heading := _label(title, 40, accent)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(heading)
	if not detail.is_empty():
		var info := _label(detail, 22, Palette.MUTED)
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(info)
	for action: Array in actions:
		column.add_child(_button(action[0], action[1], accent))
