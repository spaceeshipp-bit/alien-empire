extends RefCounted
## Colors from the concept boards and small builders for the M0 test screens.
## Placeholder UI only; the real look arrives with the style test after M2.

const GROUND := Color(0.0431, 0.0863, 0.1490)  # #0b1626
const PANEL := Color(0.0745, 0.1294, 0.2275)  # #13213a
const TEXT := Color(0.9098, 0.9451, 1.0000)  # #e8f1ff
const MUTED := Color(0.6157, 0.6902, 0.7843)  # #9db0c8
const CYAN := Color(0.4863, 0.9529, 1.0000)  # #7cf3ff, "you" on the map
const TEAL := Color(0.1804, 0.7686, 0.7137)  # #2ec4b6, used here for passes
const AMBER := Color(0.9608, 0.6471, 0.1412)  # #f5a524, notes
const RED := Color(1.0000, 0.3529, 0.3725)  # #ff5a5f, failures


## Fills root with the dark ground and a scrolling column, adds the title and
## returns the column to put content in.
static func screen(root: Control, title: String) -> VBoxContainer:
	var background := ColorRect.new()
	background.color = GROUND
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 72)
	margin.add_theme_constant_override("margin_bottom", 32)
	root.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 16)
	scroll.add_child(column)
	column.add_child(label(title, 40, CYAN))
	return column


static func label(text: String, font_size: int = 26, color: Color = TEXT) -> Label:
	var result := Label.new()
	result.text = text
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	return result


## A full-width button at least 96 px tall, comfortably above the 44 px touch minimum.
static func button(text: String, on_press: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size = Vector2(0, 96)
	result.add_theme_font_size_override("font_size", 30)
	result.pressed.connect(on_press)
	return result


## Color for a report line status: pass, fail, note or info.
static func status_color(status: String) -> Color:
	match status:
		"pass":
			return TEAL
		"fail":
			return RED
		"note":
			return AMBER
	return MUTED
