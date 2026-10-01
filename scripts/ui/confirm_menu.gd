## "Are you sure?": a question, a line of what would be lost, and two buttons. The safe
## answer (Stay) is the gold one and has the keyboard, so a stray Enter changes nothing; Esc
## is Stay too.
extends "res://scripts/ui/menu_screen.gd"

var detail := ""
var ok_text := "OK"
var stay_text := "Stay"
## Runs if the answer is yes (after this screen is gone).
var on_ok: Callable
var ok_button: Button
var stay_button: Button


func _init() -> void:
	kind = "confirm"
	max_w = 420.0


func _build_body() -> void:
	if detail != "":
		body.add_child(note(detail, ink(), 15))


func _build_foot() -> void:
	ok_button = button(ok_text, false)
	ok_button.pressed.connect(_yes)
	foot.add_child(ok_button)
	stay_button = button(stay_text, true)
	stay_button.pressed.connect(close)
	foot.add_child(stay_button)


func default_focus() -> Control:
	return stay_button


func _yes() -> void:
	close_sound = ""
	var callback := on_ok
	close()
	if callback.is_valid():
		callback.call()
