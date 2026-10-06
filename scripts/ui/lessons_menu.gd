## The Lessons page of the Esc menu (One House, TUTOR): the lessons of the first house on or off, and all of them again from the first. Opened by the pause menu's Lessons line
## (`shell.open_lessons`; only in a town run); Esc or Back closes it.
##
##   Lessons On / Off   the guide's card at the bottom left and the cues drawn in the world (scripts/ui/tutor_cues.gd): the same flag as the card's "No lessons" button
##                      (`oh_lessons_off` in the player's file), so the two always agree; turning them on brings back the ones skipped in this game
##   Replay all lessons every lesson again from the first, in order, each done when it is done again (`OneHouse.replay_lessons`); the lessons are put on if they were off, and the menu
##                      closes, so that the game goes on with the first lesson's cue
## It only drives the town HUD part (`town_hud.set_lessons`, `replay_lessons`); a game with no such part shows the page with its buttons disabled.
extends "res://scripts/ui/menu_screen.gd"

var back_button: Button
var switch: Button
var replay_button: Button
var state_note: Label


func _init() -> void:
	kind = "lessons"
	max_w = 520.0


func _town_hud():
	var game = shell.main if shell != null else null
	var town = game.get("town") if game != null else null
	return town.part("town_hud") if town != null and town.has_method("part") else null


func _build_body() -> void:
	var th = _town_hud()
	body.add_child(note("The lessons are the small card at the bottom left, and the rings, keys and marks drawn in the world beside what to do next.", ink2(), 14))
	var row: HBoxContainer = hud._hbox(12)
	var col: VBoxContainer = hud._vbox(1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_child(hud._label("Lessons", Fonts.sans(500), 15, ink()))
	state_note = note("", ink3(), 13)
	state_note.custom_minimum_size.x = 120
	col.add_child(state_note)
	row.add_child(col)
	switch = button("", false)
	switch.toggle_mode = true
	switch.custom_minimum_size = Vector2(84, 38)
	switch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	switch.tooltip_text = "Put the lessons away, or bring them back"
	switch.set_pressed_no_signal(th != null and bool(th.lessons_are_on()))
	switch.disabled = th == null
	switch.toggled.connect(_on_switch)
	row.add_child(switch)
	body.add_child(row)
	_paint()
	body.add_child(line())
	replay_button = shell.menu_item("Replay all lessons", "From the first: each is done when you do it again")
	replay_button.disabled = th == null
	replay_button.pressed.connect(_replay)
	body.add_child(replay_button)


func _build_foot() -> void:
	back_button = button("Back", true)
	back_button.pressed.connect(close)
	foot.add_child(back_button)


func default_focus() -> Control:
	return switch if switch != null else back_button


func _paint() -> void:
	switch.text = "On" if switch.button_pressed else "Off"
	shell.restyle(switch, switch.button_pressed)
	state_note.text = "The card and the cues are showing" if switch.button_pressed else "Nothing is taught: you know the way"


func _on_switch(on: bool) -> void:
	var th = _town_hud()
	if th != null:
		th.set_lessons(on)
	_paint()


func _replay() -> void:
	var th = _town_hud()
	shell.close_all()
	if th != null:
		th.replay_lessons()
