## The credits: the game, what it is built on, and the honest word about the pictures.
extends "res://scripts/ui/menu_screen.gd"

const OneHouse := preload("res://scripts/town/one_house.gd")

## The school's line (`--school`, the demo and a test's stand-in for the game); the real game says the town's (`OneHouse.text("words.tagline")`).
const TAGLINE := "Hold the schoolyard for thirty nights."
## [what, who]. The font's line is the one its licence file carries.
const ENTRIES := [
	["Engine", "Godot 4.7, under the MIT licence"],
	["Type", "Barlow, by The Barlow Project Authors, under the SIL Open Font Licence 1.1"],
	["Sound", "Recordings from Kenney's Impact Sounds, RPG Audio and Interface Sounds (CC0); the rest synthesised in-house"],
	["Pictures", "Drawn in-house, in code and in Blender"],
]
const THANKS := "Thank you for playing."

var back_button: Button


func _init() -> void:
	kind = "credits"
	max_w = 560.0


func _build_body() -> void:
	var name_label: Label = hud._label("LAST BELL", Fonts.cond(700, 3), 34, hud.ACCENT)
	body.add_child(name_label)
	body.add_child(note(OneHouse.text("words.tagline", TAGLINE) if OneHouse.town_start(shell.main) else TAGLINE, ink2(), 15))
	body.add_child(line())
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 10)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for entry in ENTRIES:
		var what: Label = hud._caps(String(entry[0]))
		what.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		what.custom_minimum_size.x = 76
		grid.add_child(what)
		grid.add_child(note(String(entry[1]), ink(), 14))
	body.add_child(grid)
	body.add_child(line())
	body.add_child(note(THANKS, ink2(), 15))


func _build_foot() -> void:
	back_button = button("Back", true)
	back_button.pressed.connect(close)
	foot.add_child(back_button)
