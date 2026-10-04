## How the mouse aims (round 22, "Controls"): the setting `ui.aim_mode` and the rules that every view of the survivor's hands shares (the
## yard in scripts/main.gd, a place in scripts/raid/raid_scene.gd and the road in scripts/drive/drive_scene.gd). Pure: nothing here
## reads the engine's input state.
##
## "right" (the default, "Right button aims"): the pointer is a free arrow that clicks; the survivor faces the way they walk and keeps
##   their last facing when they stand still. While the RIGHT button is held (or SHIFT, for one hand on the keys) the survivor turns to the
##   pointer, the crosshair and the aim line show, and the LEFT button fires. A left click without it never fires and never turns the
##   survivor: it picks people and uses what the E prompt is on. The aim lets go the moment the pointer is over a HUD control, a menu or a
##   page, or leaves the window, and when the window loses the focus.
## "always" ("Always aim at the mouse", the way it was): the survivor aims at the pointer every frame and the left button fires anywhere in the
##   world; the pointer over the bare world is the crosshair.
extends RefCounted

const Prefs := preload("res://scripts/prefs.gd")

const RIGHT := "right"
const ALWAYS := "always"
const MODES := [RIGHT, ALWAYS]
## What the Settings screen calls them, and what each says in a line.
const LABELS := {RIGHT: "Right button aims", ALWAYS: "Always aim at the mouse"}
const NOTES := {
	RIGHT: "Right button or Shift aims, left click shoots; the pointer stays free to click.",
	ALWAYS: "The survivor aims at the mouse all the time; the left button fires.",
}


## The mode now: `ui.aim_mode`, "right" for anything the file holds that is not one of the two.
static func current() -> String:
	var v = Prefs.get_value("ui", "aim_mode")
	if typeof(v) == TYPE_STRING and MODES.has(String(v)):
		return String(v)
	return RIGHT


## Whether the mouse aims all the time (the old way).
static func always() -> bool:
	return current() == ALWAYS


static func set_mode(mode: String) -> void:
	Prefs.set_value("ui", "aim_mode", mode if MODES.has(mode) else RIGHT)


## Whether the survivor's hands are aiming: in "always" the pointer in the window (the caller says); in "right" the right button or Shift held
## while the pointer is on the bare world (not over a HUD control, a menu or a page, nor out of the window) and the hands are free.
static func aiming(mode: String, right_held: bool, shift_held: bool, pointer_ok: bool, hands_off: bool, over_hud: bool) -> bool:
	if mode == ALWAYS:
		return pointer_ok
	return (right_held or shift_held) and pointer_ok and not hands_off and not over_hud

