## The Controls page of the Esc menu: ONE page, no scrolling at 1280 by 800, with every key and mouse button of the town run in four groups (Move and fight, The crew, Panels and time,
## The game). It is made from the one table, scripts/ui/controls_table.gd, which the HUD's "?" panel and the legend of the first minute are made from too. It shows the way the mouse
## aims now (the right button, or always at the mouse) and says where that is changed. Opened by the pause menu's Controls line (`shell.open_controls`); Esc or Back closes it.
extends "res://scripts/ui/menu_screen.gd"

const ControlsTable := preload("res://scripts/ui/controls_table.gd")
const AimMode := preload("res://scripts/aim_mode.gd")

## How wide the column of keys is (a row of four chips, "W A S D", is the widest), so that the words of every row start on one line.
const KEYS_W := 104.0
const WORDS_MIN_W := 190.0

var back_button: Button
## The rows made, as [keys text, words text] (the tests and the screenshots read what the page says).
var rows: Array = []


func _init() -> void:
	kind = "controls"
	max_w = 960.0


func _build_body() -> void:
	var always := AimMode.always()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 12)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(grid)
	var groups := ControlsTable.groups(always)
	# two columns: the first two groups on the left, the other two on the right
	var left: VBoxContainer = hud._vbox(12)
	var right: VBoxContainer = hud._vbox(12)
	for col in [left, right]:
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		grid.add_child(col)
	for i in groups.size():
		(left if i < 2 else right).add_child(_group(groups[i]))
	var foot_note := note(ControlsTable.FOOTNOTE, ink3(), 13)
	body.add_child(foot_note)
	var aiming := note("Aiming: %s. Settings has the other way." % String(AimMode.LABELS[AimMode.current()]).to_lower(), ink3(), 13)
	body.add_child(aiming)


## A heading and its rows.
func _group(g: Dictionary) -> Control:
	var box: VBoxContainer = hud._vbox(5)
	box.add_child(section(String(g.title)))
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(1, 1, 1, 0.045) if not paper else Color(0, 0, 0, 0.04)
	st.set_corner_radius_all(5)
	st.content_margin_left = 10
	st.content_margin_right = 10
	st.content_margin_top = 6
	st.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", st)
	var col: VBoxContainer = hud._vbox(5)
	panel.add_child(col)
	for r in g.rows:
		col.add_child(_row(r))
	box.add_child(panel)
	return box


## One row: the keys as keycaps ("|" reads "or"), then what they do.
func _row(r: Dictionary) -> Control:
	var row: HBoxContainer = hud._hbox(10)
	var keys: HBoxContainer = hud._hbox(3)
	keys.custom_minimum_size.x = KEYS_W
	keys.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for word in String(r.keys).split(" "):
		if word == "|":
			keys.add_child(hud._label("or", Fonts.sans(400), 12, ink3()))
		else:
			keys.add_child(hud._kbd(word))
	row.add_child(keys)
	var words: Label = hud._label(String(r.what), Fonts.sans(400), 14, ink())
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.custom_minimum_size.x = WORDS_MIN_W
	row.add_child(words)
	rows.append([String(r.keys), String(r.what)])
	return row


func _build_foot() -> void:
	back_button = button("Back", true)
	back_button.pressed.connect(close)
	foot.add_child(back_button)


func default_focus() -> Control:
	return back_button
