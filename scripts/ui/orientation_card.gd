## The little paper card of a first launch: "First time here? Orientation Day teaches the
## basics in about ten minutes." The shell shows it once (the flag `tutorial_offered`);
## the answer is Start Orientation Day or Not now (Esc is Not now).
extends "res://scripts/ui/menu_screen.gd"

const BODY := "Orientation Day teaches the basics in about ten minutes. You can play it again from the main menu."

var start_button: Button
var later_button: Button


func _init() -> void:
	kind = "orientation"
	max_w = 440.0
	paper = true
	hides_title = false
	dim_color = Color(0.03, 0.025, 0.02, 0.42)


func _build_body() -> void:
	body.add_child(note(BODY, ink(), 15))


func _build_foot() -> void:
	later_button = button("Not now", false)
	later_button.pressed.connect(close)
	foot.add_child(later_button)
	start_button = button("Start Orientation Day", true)
	start_button.pressed.connect(_start)
	foot.add_child(start_button)


func default_focus() -> Control:
	return start_button


func _start() -> void:
	close_sound = ""
	close()
	shell.start_orientation()
