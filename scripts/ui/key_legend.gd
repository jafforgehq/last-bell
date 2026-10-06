## The legend of the keys of the One House (HUDA, the "clutter" pass): a small card in the bottom left corner, above the lesson card, for the first 45 seconds.
##
## It used to be a wide dark bar at the bottom centre over the game that, in a small window, covered the lesson card's Skip buttons. Now:
##   - two short lines of small chips in the lower left, above the lesson card (or the toolbar's height), never over the cards: `town_hud.gd` places it each frame
##     (`place`) and hides it for as long as it would touch another part of the HUD
##   - each hint goes for good once the player has done it: the key was pressed (move, reload, swing, use, weapon away, map, radio, menu), the right button went down
##     on the world (aim; or, with "Always aim at the mouse", the mouse was moved), the left button went down on the world (fire). It watches the input events
##     (`_input`, never consuming one); a press of a key counts, whether or not the game did anything with it
##   - the whole legend is gone when every hint is done, when 45 seconds of the run have passed (it fades over the last second), or for good when the HUD says the
##     first screen has done its job (`hint_spent`: somebody was asked for something, the setting for hints is off)
## A view only.
extends PanelContainer

const Fonts := preload("res://scripts/ui/fonts.gd")
const AimMode := preload("res://scripts/aim_mode.gd")

const ControlsTable := preload("res://scripts/ui/controls_table.gd")

## [id, key, words]: the first line is what the hands do, the second what the player reaches for. Both are read from the one table of the controls
## (scripts/ui/controls_table.gd, the rows that carry a "legend"), so the legend can never name a key the Controls page does not.
const FADE_S := 0.5
## With "Always aim at the mouse" there is no right button to press: the aim is done when the mouse has been moved this far (pixels).
const MOUSE_MOVED_PX := 300.0

var hud
## id -> {"node": the hint's box, "line": its row, "done": bool}
var entries := {}
var finished := false
var _rows: Array = []
var _mouse_px := 0.0
var _aim_chip: Label = null
var _aim_words: Label = null


func setup(hud_node) -> void:
	hud = hud_node
	name = "KeyLegend"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var st := StyleBoxFlat.new()
	st.bg_color = Color(hud.PANEL, 0.82)
	st.border_color = hud.LINE2
	st.set_border_width_all(1)
	st.set_corner_radius_all(5)
	st.content_margin_left = 8
	st.content_margin_right = 9
	st.content_margin_top = 4
	st.content_margin_bottom = 5
	add_theme_stylebox_override("panel", st)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	for line in [ControlsTable.legend_line("a"), ControlsTable.legend_line("b")]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for e in line:
			var box := HBoxContainer.new()
			box.add_theme_constant_override("separation", 4)
			box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var chip := _chip(String(e[1]))
			box.add_child(chip)
			var words: Label = hud._label(String(e[2]), Fonts.sans(400), 12, hud.INK2)
			box.add_child(words)
			if String(e[0]) == "aim":
				_aim_chip = chip.get_child(0)
				_aim_words = words
			row.add_child(box)
			entries[String(e[0])] = {"node": box, "line": row, "done": false}
		col.add_child(row)
		_rows.append(row)
	_words_for_aim()


## A small key chip (the HUD's own is taller).
func _chip(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	var f := StyleBoxFlat.new()
	f.bg_color = Color(0.93, 0.96, 0.89, 0.12)
	f.border_color = hud.LINE2
	f.set_border_width_all(1)
	f.set_corner_radius_all(3)
	f.content_margin_left = 4
	f.content_margin_right = 4
	f.content_margin_top = 0
	f.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", f)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l: Label = hud._label(text, Fonts.cond(600), 12, hud.INK)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


## "Right-click aim", or "Mouse aim" with the setting that the mouse aims by itself (the controls changed: the facade calls this).
func _words_for_aim() -> void:
	if _aim_chip != null:
		_aim_chip.text = "Mouse" if AimMode.always() else "Right-click"


func controls_changed() -> void:
	_words_for_aim()


## True once there is nothing left to teach.
func all_done() -> bool:
	for id in entries:
		if not entries[id].done:
			return false
	return true


## The player did `id` (move, aim, fire, reload, swing, use, away, map, radio, menu): its hint goes, for good.
func mark(id: String) -> void:
	var e: Dictionary = entries.get(id, {})
	if e.is_empty() or bool(e.done):
		return
	e.done = true
	var node: Control = e.node
	if hud != null and bool(hud.call("_calm")) or not is_inside_tree():
		_gone(id)
		return
	var t := create_tween()
	t.tween_property(node, "modulate:a", 0.0, FADE_S)
	t.tween_callback(_gone.bind(id))


func _gone(id: String) -> void:
	var e: Dictionary = entries[id]
	(e.node as Control).visible = false
	var row: Control = e.line
	var any := false
	for other in entries:
		if entries[other].line == row and not entries[other].done:
			any = true
	row.visible = any
	if all_done():
		finished = true
		visible = false


func _input(ev: InputEvent) -> void:
	if finished:
		return
	if ev is InputEventKey:
		var k := ev as InputEventKey
		if not k.pressed or k.echo:
			return
		match k.physical_keycode:
			KEY_W, KEY_A, KEY_S, KEY_D:
				mark("move")
		match k.keycode:
			KEY_R:
				mark("reload")
			KEY_F:
				mark("swing")
			KEY_E:
				mark("use")
			KEY_Q:
				mark("away")
			KEY_M:
				mark("map")
			KEY_T:
				mark("radio")
			KEY_ESCAPE:
				mark("menu")
			KEY_SHIFT:
				mark("aim")    # (Shift aims too)
	elif ev is InputEventMouseButton:
		var b := ev as InputEventMouseButton
		if not b.pressed or _over_ui():
			return
		if b.button_index == MOUSE_BUTTON_RIGHT:
			mark("aim")
		elif b.button_index == MOUSE_BUTTON_LEFT:
			mark("fire")
	elif ev is InputEventMouseMotion and AimMode.always():
		_mouse_px += (ev as InputEventMouseMotion).relative.length()
		if _mouse_px >= MOUSE_MOVED_PX:
			mark("aim")


## Whether the mouse is on a card or a button of the HUD (a click there is not a shot).
func _over_ui() -> bool:
	return get_viewport() != null and get_viewport().gui_get_hovered_control() != null


## Puts the legend with its lower left corner at `corner` (the HUD's points), unless it would touch one of `obstacles` (Control nodes, any that are visible),
## and sets how clear it is (`alpha`). Returns whether it shows.
func place(corner: Vector2, obstacles: Array, alpha: float) -> bool:
	size = get_combined_minimum_size()
	var rect := Rect2(corner - Vector2(0.0, size.y), size)
	var clear := true
	for o in obstacles:
		if o is Control and is_instance_valid(o) and (o as Control).is_visible_in_tree():
			var r := Rect2((o as Control).global_position - hud.global_position, (o as Control).size)
			if r.size.x > 1.0 and r.size.y > 1.0 and r.grow(4.0).intersects(rect):
				clear = false
	position = rect.position
	modulate.a = alpha
	visible = clear and not finished
	return visible
