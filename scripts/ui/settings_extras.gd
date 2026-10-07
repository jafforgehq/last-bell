## The Accessibility rows of the Settings screen (scripts/ui/settings_menu.gd calls `add_rows(self)` at the end of its body): "Text size" (Normal, Large, Larger), "Colour-blind markers"
## and "Reduce flashes". What they do is in scripts/access.gd; each is saved at once in `Prefs` and the game reads it again (`apply_settings`), so a change shows on the screen behind.
extends RefCounted

const Access := preload("res://scripts/access.gd")
const Prefs := preload("res://scripts/prefs.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")

## The switches, in the screen's own form: [pref key, what the player reads, and what it does].
const SWITCHES := [
	["colour_blind", "Colour-blind markers", "Shapes and signs beside colours: chips, minimap, health, Build"],
	["reduce_flashes", "Reduce flashes", "A hit's red edge, the bell's vignette and gun light go gentle"],
]
## What each slider is, for its tooltip (the Sound rows).
const VOLUME_TIPS := {
	"master": "Everything at once. The other sliders are shares of it",
	"sfx": "Guns, doors, fists and the dead",
	"ambience": "Wind, crickets and the far-off sounds",
	"music": "The score. Zero is no music",
	"ui": "The clicks of the menus and the radio",
}
const SCALE_TIPS := {"minus": "A smaller interface, down to 80 percent", "plus": "A bigger interface, up to 150 percent (the window must have the room)"}
const TEXT_TIP :="How big the words are in the HUD and the menus, on top of the interface size"


## Puts the rows at the foot of `s.body` (the Settings screen): a heading, the text size and the two switches.
static func add_rows(s) -> void:
	s.body.add_child(s.section("Accessibility"))
	s.body.add_child(_text_row(s))
	var grid: GridContainer = s.new_switch_grid()
	for sw in SWITCHES:
		grid.add_child(s._switch_row(String(sw[0]), String(sw[1]), String(sw[2])))
	s.body.add_child(grid)
	refresh_text(s)


## "Text size": three buttons side by side (the one chosen is lit).
static func _text_row(s) -> Control:
	var row: HBoxContainer = s.hud._hbox(8)
	var l: Label = s.hud._label("Text size", Fonts.sans(500), 15, s.ink())
	l.custom_minimum_size.x = 112
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	row.tooltip_text = TEXT_TIP
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	for size_id in Access.TEXT_SIZES:
		var b: Button = s.button(String(Access.TEXT_LABELS[size_id]), false)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(96, 38)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.tooltip_text = "%s text: %s as big as the interface draws it" % [String(Access.TEXT_LABELS[size_id]), "about 1.15 times" if size_id == "large" else ("about 1.3 times" if size_id == "larger" else "the size")]
		b.pressed.connect(_on_text.bind(s, String(size_id)))
		row.add_child(b)
		s.text_buttons[String(size_id)] = b
	return row


static func _on_text(s, size_id: String) -> void:
	Prefs.set_value("ui", "text_size", size_id)
	refresh_text(s)
	s._changed()


## The buttons show the size now.
static func refresh_text(s) -> void:
	var now := Access.text_size()
	for size_id in s.text_buttons:
		var b: Button = s.text_buttons[size_id]
		b.set_pressed_no_signal(size_id == now)
		s.shell.restyle(b, size_id == now)
